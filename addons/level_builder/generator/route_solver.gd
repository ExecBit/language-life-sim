@tool
extends Object

# Circulation before furniture. Every doorway gets a lane to the middle of the
# room, those cells are reserved, and nothing the prop solver does afterwards
# can touch them. This one rule is most of the difference between a generated
# room and a designed one.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")

const LANE_RADIUS := 1  # cells either side of the lane centre → a 3-cell lane


# Builds the unit's solver grid with doors and lanes already reserved.
static func solve(unit: Dictionary, occupancy: Dictionary, kit: Resource) -> Dictionary:
	var cpm := TYPES.cells_per_module(kit)
	var rect: Rect2i = unit["rect"]
	var grid := TYPES.make_grid(rect.size.x * cpm, rect.size.y * cpm, rect.position * cpm)

	# An L-shaped room has a corner missing. Those cells have no floor under
	# them, so mark them solid before anything reserves a lane through thin air.
	var members := {}
	for cell in TYPES.unit_cells(unit):
		members[cell] = true
	if members.size() < rect.size.x * rect.size.y:
		for z in rect.size.y:
			for x in rect.size.x:
				if members.has(rect.position + Vector2i(x, z)):
					continue
				TYPES.fill_footprint(grid, x * cpm, z * cpm, Vector2i(cpm, cpm), TYPES.OCCUPIED)

	return reserve(grid, door_anchors(unit, occupancy, cpm))


# The lane-reserving half on its own, for grids that didn't come from a plan —
# a space the scanner read out of the scene arrives already shaped, with its
# doorways found by probing rather than by looking at neighbouring units.
static func reserve(grid: Dictionary, doors: Array) -> Dictionary:
	for anchor in doors:
		if TYPES.grid_get(grid, anchor.x, anchor.y) != TYPES.OCCUPIED:
			TYPES.grid_set(grid, anchor.x, anchor.y, TYPES.DOOR)

	# Converge on the middle, unless the middle is a pillar — then the nearest
	# cell you could actually stand in.
	var centre := _standable_near(grid, _local_centre(grid))
	for anchor in doors:
		_paint_lane(grid, anchor, centre)
	if doors.is_empty():
		# sealed space — keep the middle clear anyway so there's somewhere to stand
		TYPES.grid_set(grid, centre.x, centre.y, TYPES.ROUTE)
	return grid


# Where every lane converges, in GLOBAL solver cells. Always reserved, so it's
# the one cell in a room guaranteed to be standable — which is what makes it
# the right place to put a spawn or start a reachability flood fill.
#
# Derived from the same helper solve() uses on purpose: computing it from module
# centres instead drifts by half a module on even-sized rooms, and then a prop
# can land on the spawn.
static func centre_cell(unit: Dictionary, kit: Resource) -> Vector2i:
	var cpm := TYPES.cells_per_module(kit)
	var rect: Rect2i = unit["rect"]
	return rect.position * cpm + _local_centre(TYPES.make_grid(rect.size.x * cpm, rect.size.y * cpm))


# One anchor cell per doorway: the inside cell at the middle of a shared edge,
# in grid-local coordinates.
static func door_anchors(unit: Dictionary, occupancy: Dictionary, cpm: int) -> Array:
	var unit_id := String(unit["id"])
	var rect: Rect2i = unit["rect"]
	var anchors: Array = []
	for cell in TYPES.unit_cells(unit):
		for dir in TYPES.DIRS:
			var neighbour_id: String = occupancy.get(cell + dir, "")
			if neighbour_id == "" or neighbour_id == unit_id:
				continue
			var local: Vector2i = (cell - rect.position) * cpm
			var mid := cpm / 2
			if dir.x > 0:
				anchors.append(Vector2i(local.x + cpm - 1, local.y + mid))
			elif dir.x < 0:
				anchors.append(Vector2i(local.x, local.y + mid))
			elif dir.y > 0:
				anchors.append(Vector2i(local.x + mid, local.y + cpm - 1))
			else:
				anchors.append(Vector2i(local.x + mid, local.y))
	return anchors


# ---- internals -------------------------------------------------------------

static func _local_centre(grid: Dictionary) -> Vector2i:
	return Vector2i(int(grid["w"]) / 2, int(grid["h"]) / 2)


# Planned rooms are empty rectangles, so this always answers `from` for them and
# nothing about M1's output moves. Scanned spaces have obstacles in them.
static func _standable_near(grid: Dictionary, from: Vector2i) -> Vector2i:
	if TYPES.grid_get(grid, from.x, from.y) != TYPES.OCCUPIED:
		return from
	var best := from
	var best_distance := INF
	for z in int(grid["h"]):
		for x in int(grid["w"]):
			if TYPES.grid_get(grid, x, z) == TYPES.OCCUPIED:
				continue
			var distance := Vector2(x - from.x, z - from.y).length()
			if distance < best_distance:
				best_distance = distance
				best = Vector2i(x, z)
	return best

# The shortest walk from a doorway to the middle, around anything solid.
#
# This used to be a plain L — along X, then along Z — which is fine while every
# room is a rectangle and stops being fine the moment one isn't: the L happily
# runs through the missing corner, the lanes don't actually join up, and
# furniture is then free to wall off half the room. A breadth-first walk costs
# almost nothing on a grid this size and can't produce a lane you can't use.
static func _paint_lane(grid: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var came_from := {}
	var queue: Array[Vector2i] = [from]
	came_from[from] = from
	var reached := false
	while not queue.is_empty() and not reached:
		var at: Vector2i = queue.pop_front()
		for dir in TYPES.DIRS:
			var next: Vector2i = at + dir
			if came_from.has(next) or not TYPES.in_grid(grid, next.x, next.y):
				continue
			if TYPES.grid_get(grid, next.x, next.y) == TYPES.OCCUPIED:
				continue  # no floor there
			came_from[next] = at
			if next == to:
				reached = true
				break
			queue.append(next)
	if not reached and from != to:
		return  # nothing to reserve; validation will notice if it matters

	var cursor := to
	var guard := 0
	while guard < 4096:
		_paint_cell(grid, cursor.x, cursor.y)
		if cursor == from:
			break
		cursor = came_from[cursor]
		guard += 1


static func _paint_cell(grid: Dictionary, x: int, z: int) -> void:
	for dz in range(-LANE_RADIUS, LANE_RADIUS + 1):
		for dx in range(-LANE_RADIUS, LANE_RADIUS + 1):
			if TYPES.grid_get(grid, x + dx, z + dz) == TYPES.FREE:
				TYPES.grid_set(grid, x + dx, z + dz, TYPES.ROUTE)
