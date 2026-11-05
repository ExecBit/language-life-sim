@tool
extends Object

# Plan → geometry. One Node3D per unit, floors on every cell, and a wall on
# every edge that faces nothing on the same layer.
#
# That last rule is the whole trick: an edge between two units is a doorway
# because neither side asked for a wall there, so rooms, corridors and roads
# join up without anybody having to place a door.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")

# Greybox ground colour, borrowed so generated terrain matches a bootstrap scene.
const TERRAIN_COLOR := Color(0.42, 0.44, 0.42)


# Returns unit_id -> Node3D, ready to be parented under Geometry/Generated.
static func build(units: Array, layers: Dictionary, kit: Resource) -> Dictionary:
	var nodes := {}
	var floor_scene: PackedScene = kit.floor_scene()
	var wall_scene: PackedScene = kit.wall_scene()
	var path_scene: PackedScene = kit.path_scene()
	if floor_scene == null:
		return nodes
	for unit in units:
		var occupancy: Dictionary = layers.get(String(unit["layer"]), {})
		var piece: PackedScene = path_scene if String(unit["kind"]) in ["pad", "road"] else floor_scene
		nodes[String(unit["id"])] = _build_unit(unit, occupancy, kit, piece, wall_scene)
	return nodes


# Flat ground under the whole region.
#
# The heightfield that belongs here is written up in the plan: it needs roads
# that actually terminate at the plots they join, which they don't yet, so it
# waits for that rather than sitting half-built. build_terrain still takes the
# ground map so the seam is where it will be needed.
static func build_terrain(rect: Rect2i, kit: Resource, _ground: Dictionary = {}) -> StaticBody3D:
	var size := Vector2(float(rect.size.x) * kit.module, float(rect.size.y) * kit.module)
	var centre := Vector3((float(rect.position.x) + rect.size.x * 0.5) * kit.module, 0.0,
		(float(rect.position.y) + rect.size.y * 0.5) * kit.module)

	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = BOOTSTRAP.WORLD_LAYER
	body.collision_mask = BOOTSTRAP.WORLD_MASK
	body.position = centre

	var mesh := MeshInstance3D.new()
	mesh.name = "TerrainMesh"
	var plane := PlaneMesh.new()
	plane.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TERRAIN_COLOR
	mat.roughness = 0.95
	plane.material = mat
	mesh.mesh = plane
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "TerrainShape"
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 1.0, size.y)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	return body


# ---- internals -------------------------------------------------------------

static func _build_unit(unit: Dictionary, occupancy: Dictionary, kit: Resource,
		floor_scene: PackedScene, wall_scene: PackedScene) -> Node3D:
	var node := Node3D.new()
	node.name = TYPES.unit_node_name(String(unit["id"]))
	# Enough metadata to rebuild this unit's plan entry from the scene alone —
	# that's what lets regeneration honour locks without a sidecar file, and
	# survive the user deleting a room by hand.
	node.set_meta("lb_unit_id", String(unit["id"]))
	node.set_meta("lb_unit_kind", String(unit["kind"]))
	node.set_meta("lb_unit_layer", String(unit["layer"]))
	node.set_meta("lb_unit_type", String(unit["type"]))
	node.set_meta("lb_rect", unit["rect"])
	node.set_meta("lb_base_y", float(unit["base_y"]))
	node.set_meta("lb_walls", bool(unit.get("walls", true)))
	node.set_meta("lb_seed", int(unit["seed"]))
	if unit.has("poi_layer"):
		node.set_meta("lb_poi_layer", String(unit["poi_layer"]))
	if unit.has("axis"):
		# a one-module corridor is square — which way it runs can't be recovered
		# from the rect, and re-planning around a pinned one needs to know
		node.set_meta("lb_axis", unit["axis"])
	var cells: Array = unit.get("cells", [])
	if not cells.is_empty():
		node.set_meta("lb_cells", cells)

	var module: float = kit.module
	var walls: bool = bool(unit.get("walls", true)) and wall_scene != null
	var per_cell: Dictionary = unit.get("heights", {})
	if not per_cell.is_empty():
		node.set_meta("lb_heights", per_cell)

	for cell in TYPES.unit_cells(unit):
		var base_y := TYPES.base_y_at(unit, cell)
		var wall_y := base_y + float(kit.floor_thickness)
		var tile := floor_scene.instantiate() as Node3D
		if tile:
			tile.name = "Floor_%d_%d" % [cell.x, cell.y]
			tile.position = Vector3((cell.x + 0.5) * module, base_y, (cell.y + 0.5) * module)
			node.add_child(tile)
		if not walls:
			continue
		for dir in TYPES.DIRS:
			var neighbour: Vector2i = cell + dir
			if occupancy.has(neighbour):
				continue  # something walkable next door — that's a doorway, not a wall
			var wall := wall_scene.instantiate() as Node3D
			if wall == null:
				continue
			wall.name = "Wall_%d_%d_%s" % [cell.x, cell.y, _dir_suffix(dir)]
			wall.position = _wall_position(cell, dir, module, wall_y)
			if dir.x != 0:
				wall.rotation.y = PI * 0.5
			node.add_child(wall)
	return node


static func _wall_position(cell: Vector2i, dir: Vector2i, module: float, y: float) -> Vector3:
	if dir.x > 0:
		return Vector3((cell.x + 1) * module, y, (cell.y + 0.5) * module)
	if dir.x < 0:
		return Vector3(cell.x * module, y, (cell.y + 0.5) * module)
	if dir.y > 0:
		return Vector3((cell.x + 0.5) * module, y, (cell.y + 1) * module)
	return Vector3((cell.x + 0.5) * module, y, cell.y * module)


static func _dir_suffix(dir: Vector2i) -> String:
	if dir.x > 0:
		return "E"
	if dir.x < 0:
		return "W"
	return "S" if dir.y > 0 else "N"
