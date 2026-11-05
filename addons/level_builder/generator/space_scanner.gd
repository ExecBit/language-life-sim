@tool
extends Object

# Fill selection: read a space somebody else built.
#
# Instead of planning a shell, this asks the physics server what's already
# there — where the floor is, where you can stand, and where the walls have
# gaps. The answer feeds the same route and prop solvers a generated room uses,
# so your architecture gets the generator's dressing.
#
# Colliders register with the physics server in the editor even with simulation
# off, which is why this works on an open scene and why verify can drive it.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")

const HEAD_ROOM := 1.5        # you have to be able to stand in a cell for it to count
const FLOOR_NORMAL_MIN := 0.5 # steeper than this is a wall face, not a floor
const MAX_FLOOR_STEP := 0.4   # a bigger step than this is a different space
const CEILING_SKIPS := 4      # ceilings are hits too — punch through a few
const EDGE_DEPTH := 0.3       # thicker than any sane wall, thinner than a cell


# bounds is world space. Returns a grid the route and prop solvers understand,
# or {"ok": false} with a reason if there's nothing standable in there.
#
# Two different questions, deliberately: a CELL is standable if there's floor
# and headroom in the middle of it, and an EDGE is open if nothing blocks the
# gap between two cells. Asking only the first misses walls entirely — a 0.2 m
# wall on a 1 m grid sits exactly between two cell centres and shows up in
# neither probe, so the scan leaks straight out of the room.
#
# `ignore` are bodies to look straight through — a re-roll passes its own
# previous furniture, or the second pass reads the first pass's crates as walls
# and the room shrinks a little every time.
static func scan(root: Node3D, bounds: AABB, kit: Resource, ignore: Array = []) -> Dictionary:
	var world := root.get_world_3d()
	if world == null or world.direct_space_state == null:
		return {"ok": false, "message": "No physics world to scan — is the scene open?"}
	var space := world.direct_space_state
	var cell: float = kit.cell

	var probes := {
		"exclude": ignore,
		"space": space,
		"cell": cell,
		"top": bounds.end.y + 1.0,
		"bottom": bounds.position.y - 1.0,
		"cells": {},
		"cell_query": _query(Vector3(cell * 0.7, HEAD_ROOM, cell * 0.7), ignore),
		"edge_x": _query(Vector3(EDGE_DEPTH, HEAD_ROOM, cell * 0.6), ignore),
		"edge_z": _query(Vector3(cell * 0.6, HEAD_ROOM, EDGE_DEPTH), ignore),
	}

	# Half a cell in on each side. Selecting a room usually means selecting its
	# shell, and a shell's box reaches half a wall past the floor — leave that
	# sliver in and the flood walks out through the doorway and around the
	# outside of the room, which is nobody's idea of "fill this room".
	var inset: float = cell * 0.5
	var lo := Vector2i(floori((bounds.position.x + inset) / cell), floori((bounds.position.z + inset) / cell))
	var hi := Vector2i(ceili((bounds.end.x - inset) / cell), ceili((bounds.end.z - inset) / cell))
	if hi.x <= lo.x or hi.y <= lo.y:
		return {"ok": false, "message": "That selection is too small to furnish — it's under a metre across."}
	var any_standable := false
	for z in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			if bool(_cell(probes, Vector2i(x, z)).get("standable", false)):
				any_standable = true
	if not any_standable:
		return {"ok": false, "message": "Nothing standable inside the selection — try a bigger box, or one that contains a floor."}

	# One space, not two: flood out from the middle of the selection so a box
	# straddling a wall furnishes the room you pointed at, not both of them.
	var centre := Vector2i(
		floori((bounds.position.x + bounds.size.x * 0.5) / cell),
		floori((bounds.position.z + bounds.size.z * 0.5) / cell))
	if not bool(_cell(probes, centre).get("standable", false)):
		centre = _nearest_standable(probes, lo, hi, centre)
	# The flood stays inside the selection, full stop — that's the guarantee that
	# nothing gets furnished outside the box you drew. Doorways are found by
	# probing one cell past the edge, which doesn't need the flood to go there.
	var region := _flood(probes, centre, Rect2i(lo, hi - lo))

	# Gaps in the walls: a cell just outside the region you can walk to is where
	# the space carries on — a doorway. Everything else is wall.
	var doors: Array = []
	for at in region:
		for dir in TYPES.DIRS:
			var outside: Vector2i = at + dir
			if region.has(outside) or not _connected(probes, at, outside):
				continue
			doors.append(at)
			break

	var rect := _bounds_of(region)
	var grid := TYPES.make_grid(rect.size.x, rect.size.y, rect.position)
	for z in rect.size.y:
		for x in rect.size.x:
			if not region.has(rect.position + Vector2i(x, z)):
				TYPES.grid_set(grid, x, z, TYPES.OCCUPIED)

	var local_doors: Array = []
	for at in doors:
		local_doors.append(at - rect.position)

	var floor_y := -INF
	for at in region:
		floor_y = maxf(floor_y, float(_cell(probes, at)["y"]))
	return {
		"ok": true,
		"grid": grid,
		"doors": local_doors,
		"rect": rect,
		"floor_y": floor_y,
		"cells": region.size(),
	}


# ---- internals -------------------------------------------------------------

static func _query(size: Vector3, ignore: Array = []) -> PhysicsShapeQueryParameters3D:
	var box := BoxShape3D.new()
	box.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.exclude = ignore
	return query


# Every body under a node, as RIDs — what the scanner needs to ignore it.
static func body_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject3D:
		rids.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		rids.append_array(body_rids(child))
	return rids


# Memoised, because doorway hunting asks about the same cells repeatedly and
# every miss is a ray plus a shape query.
static func _cell(probes: Dictionary, at: Vector2i) -> Dictionary:
	var cache: Dictionary = probes["cells"]
	if cache.has(at):
		return cache[at]
	var space: PhysicsDirectSpaceState3D = probes["space"]
	var cell: float = probes["cell"]
	var x := (at.x + 0.5) * cell
	var z := (at.y + 0.5) * cell
	var from := Vector3(x, probes["top"], z)
	var result := {"standable": false, "y": 0.0}
	for skip in CEILING_SKIPS:
		var ray := PhysicsRayQueryParameters3D.create(from, Vector3(x, probes["bottom"], z))
		ray.exclude = probes["exclude"]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			break
		if (hit["normal"] as Vector3).dot(Vector3.UP) >= FLOOR_NORMAL_MIN:
			var floor_y := (hit["position"] as Vector3).y
			var query: PhysicsShapeQueryParameters3D = probes["cell_query"]
			query.transform = Transform3D(Basis.IDENTITY, Vector3(x, floor_y + HEAD_ROOM * 0.5 + 0.1, z))
			result = {"standable": space.intersect_shape(query, 1).is_empty(), "y": floor_y}
			break
		from = Vector3(x, (hit["position"] as Vector3).y - 0.02, z)  # that was a ceiling
	cache[at] = result
	return result


# Can you walk from a to b? Both ends standable, the step between them small,
# and nothing filling the gap they share.
static func _connected(probes: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var here := _cell(probes, a)
	var there := _cell(probes, b)
	if not (bool(here["standable"]) and bool(there["standable"])):
		return false
	if absf(float(here["y"]) - float(there["y"])) > MAX_FLOOR_STEP:
		return false
	var cell: float = probes["cell"]
	var dir: Vector2i = b - a
	var query: PhysicsShapeQueryParameters3D = probes["edge_x" if dir.x != 0 else "edge_z"]
	var edge := Vector3(
		(a.x + 0.5 + dir.x * 0.5) * cell,
		maxf(float(here["y"]), float(there["y"])) + HEAD_ROOM * 0.5 + 0.1,
		(a.y + 0.5 + dir.y * 0.5) * cell)
	query.transform = Transform3D(Basis.IDENTITY, edge)
	return (probes["space"] as PhysicsDirectSpaceState3D).intersect_shape(query, 1).is_empty()


static func _flood(probes: Dictionary, start: Vector2i, limit: Rect2i) -> Dictionary:
	var region := {}
	if not bool(_cell(probes, start).get("standable", false)):
		return region
	var queue: Array[Vector2i] = [start]
	region[start] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for dir in TYPES.DIRS:
			var next: Vector2i = at + dir
			if region.has(next) or not limit.has_point(next):
				continue
			if _connected(probes, at, next):
				region[next] = true
				queue.append(next)
	return region


static func _nearest_standable(probes: Dictionary, lo: Vector2i, hi: Vector2i, to: Vector2i) -> Vector2i:
	var best := to
	var best_distance := INF
	for z in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var at := Vector2i(x, z)
			if not bool(_cell(probes, at).get("standable", false)):
				continue
			var distance := Vector2(at - to).length()
			if distance < best_distance:
				best_distance = distance
				best = at
	return best


static func _bounds_of(cells: Dictionary) -> Rect2i:
	var rect := Rect2i()
	var first := true
	for at in cells:
		if first:
			rect = Rect2i(at, Vector2i.ONE)
			first = false
		else:
			rect = rect.merge(Rect2i(at, Vector2i.ONE))
	return rect


# The world-space box a node occupies, meshes and colliders alike. What the dock
# hands the scanner when you select the room you want furnished.
static func node_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var started := false
	for mesh in _meshes(node):
		if not mesh.is_inside_tree():
			continue  # no global transform to speak of yet
		var world_box := mesh.global_transform * mesh.get_aabb()
		box = world_box if not started else box.merge(world_box)
		started = true
	return box


static func _meshes(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
