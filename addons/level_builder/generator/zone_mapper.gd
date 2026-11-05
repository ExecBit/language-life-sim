@tool
extends Object

# What each cell of a space is FOR. This is the layer that stops generated
# rooms looking like scattered props: a bed belongs against a wall, a workbench
# belongs where the work happens, and neither belongs in the doorway.
#
# Two passes, and the split matters.
#
# The STRUCTURAL pass is the engine's: wall, corner, centre, entrance, travel.
# Those fall out of the shape of the space and the lanes already reserved
# through it, and they're facts rather than opinions — a cell touching two
# boundaries is a corner whether the place is a bedroom or a hatchery.
#
# The FUNCTIONAL pass belongs to whoever is building the place. It used to be
# the engine's too, and it encoded a farmhouse: storage on the wall furthest
# from the door, presentation between the door and the altar. Sound reasoning
# about a farmhouse, pure assumption about anything else. Now an archetype
# declares its own recipe and this just runs it, so the zones a space has — and
# what "storage" even means in it — are the creator's to name.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")

# Structural zones, fixed because they're geometry. Functional ones are
# allocated per space from the archetype's recipe, starting after these.
const NONE := 0
const TRAVEL := 1
const ENTRANCE := 2
const WALL := 3
const CORNER := 4
const CENTER := 5
const STRUCTURAL := ["none", "travel", "entrance", "wall", "corner", "center"]

const ENTRANCE_REACH := 1  # cells of apron in front of a doorway


# Pass one: the shape of the space, given the lanes route_solver already took.
static func map_geometry(grid: Dictionary) -> Dictionary:
	var w := int(grid["w"])
	var h := int(grid["h"])
	var zones := TYPES.make_grid(w, h, grid["origin"])
	zones["names"] = PackedStringArray(STRUCTURAL)
	for z in h:
		for x in w:
			var state := TYPES.grid_get(grid, x, z)
			if state == TYPES.DOOR:
				TYPES.grid_set(zones, x, z, ENTRANCE)
			elif state == TYPES.ROUTE:
				TYPES.grid_set(zones, x, z, TRAVEL)
			elif state == TYPES.OCCUPIED:
				TYPES.grid_set(zones, x, z, NONE)
			else:
				TYPES.grid_set(zones, x, z, _edge_zone(grid, x, z, w, h))

	# a doorway needs room to walk out into, not just the threshold cell
	for z in h:
		for x in w:
			if TYPES.grid_get(zones, x, z) != ENTRANCE:
				continue
			for dz in range(-ENTRANCE_REACH, ENTRANCE_REACH + 1):
				for dx in range(-ENTRANCE_REACH, ENTRANCE_REACH + 1):
					if absi(dx) + absi(dz) > ENTRANCE_REACH:
						continue
					var near := TYPES.grid_get(zones, x + dx, z + dz)
					if near == WALL or near == CORNER or near == CENTER:
						TYPES.grid_set(zones, x + dx, z + dz, ENTRANCE)
	return zones


# Pass two: run the archetype's recipe, now that we know where the anchor is.
# Rules apply in order, so a later one can refine what an earlier one claimed.
static func map_function(zones: Dictionary, _grid: Dictionary, anchor_cell: Vector2i,
		anchor_size: Vector2i, arch: Resource) -> void:
	var rules: Array = arch.zone_rules if arch != null else []
	if rules.is_empty():
		return
	var w := int(zones["w"])
	var h := int(zones["h"])
	var anchor_centre := Vector2(anchor_cell) + Vector2(anchor_size) * 0.5
	var entrances := _cells_with(zones, ENTRANCE)
	var span: float = maxf(1.0, Vector2(w, h).length())

	for rule in rules:
		if rule == null:
			continue
		var claim := _register(zones, String(rule.zone))
		var over := _ids_of(zones, rule.over)
		if over.is_empty():
			continue
		for z in h:
			for x in w:
				if not TYPES.grid_get(zones, x, z) in over:
					continue
				if _matches(rule, Vector2(x + 0.5, z + 0.5), anchor_centre, entrances, span):
					TYPES.grid_set(zones, x, z, claim)


# ---- reading zones back -----------------------------------------------------

static func name_of(zones: Dictionary, id: int) -> String:
	var names: PackedStringArray = zones.get("names", PackedStringArray(STRUCTURAL))
	return String(names[id]) if id >= 0 and id < names.size() else "none"


static func count_of(zones: Dictionary, zone: int) -> int:
	var count := 0
	for z in int(zones["h"]):
		for x in int(zones["w"]):
			if TYPES.grid_get(zones, x, z) == zone:
				count += 1
	return count


# The zones a footprint sits across, by NAME — a 2x2 bed can straddle wall and
# corner. Names rather than ids because ids are allocated per space now, and a
# prop's rules travel with it between spaces.
static func zones_under(zones: Dictionary, x: int, z: int, size: Vector2i) -> PackedStringArray:
	var found := PackedStringArray()
	for dz in size.y:
		for dx in size.x:
			var zone_name := name_of(zones, TYPES.grid_get(zones, x + dx, z + dz))
			if not zone_name in found:
				found.append(zone_name)
	return found


# ---- internals -------------------------------------------------------------

# A zone name gets an id the first time a recipe asks for it.
static func _register(zones: Dictionary, zone_name: String) -> int:
	var names: PackedStringArray = zones["names"]
	var existing := names.find(zone_name)
	if existing >= 0:
		return existing
	names.append(zone_name)
	zones["names"] = names
	return names.size() - 1


static func _ids_of(zones: Dictionary, wanted: PackedStringArray) -> Array:
	var names: PackedStringArray = zones["names"]
	var ids: Array = []
	for zone_name in wanted:
		var id := names.find(String(zone_name))
		if id >= 0:
			ids.append(id)
	return ids


static func _matches(rule: Resource, here: Vector2, anchor: Vector2,
		entrances: Array, span: float) -> bool:
	match String(rule.rule):
		"near_anchor":
			return here.distance_to(anchor) <= float(rule.radius)
		"far_from_entrances":
			if entrances.is_empty():
				return true
			return _nearest_of(entrances, here).distance_to(here) > float(rule.reach) * span
		"near_entrances":
			if entrances.is_empty():
				return false
			return _nearest_of(entrances, here).distance_to(here) <= float(rule.reach) * span
		"between_entrance_and_anchor":
			if entrances.is_empty():
				return false
			return _between(here, _nearest_of(entrances, anchor), anchor)
		"remaining":
			return true
	return false


static func _edge_zone(grid: Dictionary, x: int, z: int, w: int, h: int) -> int:
	# against the outside of the grid, or against something solid — both read as
	# "there's a wall here" to anything being placed
	var touches := 0
	for dir in TYPES.DIRS:
		var nx: int = x + dir.x
		var nz: int = z + dir.y
		if nx < 0 or nz < 0 or nx >= w or nz >= h or TYPES.grid_get(grid, nx, nz) == TYPES.OCCUPIED:
			touches += 1
	if touches >= 2:
		return CORNER
	return WALL if touches == 1 else CENTER


static func _cells_with(zones: Dictionary, zone: int) -> Array:
	var found: Array = []
	for z in int(zones["h"]):
		for x in int(zones["w"]):
			if TYPES.grid_get(zones, x, z) == zone:
				found.append(Vector2(x + 0.5, z + 0.5))
	return found


static func _nearest_of(points: Array, to: Vector2) -> Vector2:
	var best := to
	var best_distance := INF
	for point in points:
		var distance: float = (point as Vector2).distance_to(to)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


# Roughly on the line from a to b, within a cell and a half of it.
static func _between(here: Vector2, a: Vector2, b: Vector2) -> bool:
	var span := b - a
	if span.length_squared() < 0.01:
		return false
	var t := clampf((here - a).dot(span) / span.length_squared(), 0.0, 1.0)
	return here.distance_to(a + span * t) <= 1.5
