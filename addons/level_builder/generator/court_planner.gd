@tool
extends Object

# A second way to arrange a place, and the reason the planner is a choice at all.
#
# The tree planner grows rooms outward off an entrance, joined by corridors.
# That's a building, and it was the only shape this thing could make — which
# meant "level" quietly meant "terrestrial building" no matter what vocabulary
# you pointed it at.
#
# This one has no corridors. Rooms ring a single open space and open directly
# onto it, so the middle is the circulation and the route through is a hub
# rather than a walk. A cloister, a caravanserai, a hive around its chamber, a
# reactor ring, a village green.
#
# It returns exactly what the tree planner returns, because everything
# downstream — shells, zones, furniture, style, validation — never knew or
# cared how the units were arrived at.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LEVEL_PLANNER := preload("res://addons/level_builder/generator/level_planner.gd")


static func plan(level_arch: Resource, size_class: int, seed_value: int,
		layer: String = "level", base_y: float = 0.0, id_prefix: String = "",
		pinned: Array = [], shape: Dictionary = {}) -> Dictionary:
	var rng := TYPES.rng_for(seed_value)
	var openness := float(shape.get("openness", 0.5))
	var want: int = maxi(2, level_arch.room_count(size_class) + rng.randi_range(-1, 1))
	var types := LEVEL_PLANNER.room_type_sequence(level_arch, want, rng)

	# The court first: everything else is placed against it, so its size is the
	# one decision the rest follows from.
	var declared: Vector2i = level_arch.court_modules
	var court_size := (declared + Vector2i.ONE * int(round((openness - 0.5) * 4.0))).max(Vector2i(2, 2))
	var court := _unit("%sCourt" % id_prefix, "pad", "", Rect2i(Vector2i.ZERO, court_size),
		layer, base_y, TYPES.derive_seed(seed_value, "court"))
	court["walls"] = false

	var units: Array[Dictionary] = [court]
	var rooms: Array[Dictionary] = []
	var taken: Array[Rect2i] = [Rect2i(Vector2i.ZERO, court_size)]
	var used_ids := {}
	used_ids[String(court["id"])] = true

	# Walk the court's perimeter placing rooms outward. Each shares an edge with
	# the court, and a shared edge is a doorway, so every room opens onto the
	# middle without a corridor existing anywhere.
	var placed := 0
	for slot in _perimeter_slots(court_size, rng):
		if placed >= want:
			break
		var type_id: String = types[mini(placed, types.size() - 1)]
		var size := LEVEL_PLANNER.room_size(type_id, rng, openness)
		# The first room off the court is the way in, and it carries a second
		# doorway the others don't — the front door. Every doorway costs a lane,
		# so it's built a module bigger, exactly as the tree planner does.
		if placed == 0:
			size += Vector2i.ONE
		var rect := _outward(court_size, slot, size)
		if not _fits(rect, taken):
			continue
		var room := _unit(LEVEL_PLANNER.next_id(id_prefix, "Room", used_ids), "room", type_id, rect,
			layer, base_y, TYPES.derive_seed(seed_value, "room:%d:%s" % [placed, type_id]))
		units.append(room)
		taken.append(rect)
		rooms.append({"id": String(room["id"]), "type": type_id, "rect": rect,
			"depth": 1, "parent": "", "grown": true})
		placed += 1

	if rooms.is_empty():
		return LEVEL_PLANNER.plan(level_arch, size_class, seed_value, layer, base_y, id_prefix,
			pinned, shape)  # nothing would fit around it — fall back to a building

	# The first room is the way in and the last is what you came for. Everything
	# hangs off the entrance because everything is one step from the court:
	# a hub has a short route through by definition, and that's the point of it.
	var entry := String(rooms[0]["id"])
	rooms[0]["depth"] = 0
	for index in range(1, rooms.size()):
		rooms[index]["parent"] = entry
	var goal := String(rooms[rooms.size() - 1]["id"])

	var yard := _entry_yard(court_size, rooms[0]["rect"], taken, layer, base_y, id_prefix,
		used_ids, seed_value)
	if not yard.is_empty():
		units.append(yard)

	var path := PackedStringArray([entry])
	if goal != entry:
		path.append(goal)
	return {
		"layer": layer,
		"units": units,
		"occupancy": LEVEL_PLANNER.occupancy_of(units),
		"bounds": LEVEL_PLANNER.bounds_of(units),
		"entry_unit": entry,
		"goal_unit": goal,
		"yard_unit": String(yard["id"]) if not yard.is_empty() else "",
		"rooms": rooms,
		"critical_path": path,
		"dead_ends": _dead_ends(rooms, path),
		"seed": seed_value,
	}


# ---- internals -------------------------------------------------------------

# One slot per module of the court's edge, in a shuffled order so two seeds
# don't fill the ring the same way round.
static func _perimeter_slots(court: Vector2i, rng: RandomNumberGenerator) -> Array:
	var slots: Array = []
	for x in court.x:
		slots.append({"dir": Vector2i(0, -1), "at": x})
		slots.append({"dir": Vector2i(0, 1), "at": x})
	for z in court.y:
		slots.append({"dir": Vector2i(-1, 0), "at": z})
		slots.append({"dir": Vector2i(1, 0), "at": z})
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = slots[i]
		slots[i] = slots[j]
		slots[j] = swap
	return slots


# A room sitting against the court on the given side, centred on the slot.
static func _outward(court: Vector2i, slot: Dictionary, size: Vector2i) -> Rect2i:
	var dir: Vector2i = slot["dir"]
	var at: int = slot["at"]
	if dir.y < 0:
		return Rect2i(Vector2i(at - size.x / 2, -size.y), size)
	if dir.y > 0:
		return Rect2i(Vector2i(at - size.x / 2, court.y), size)
	if dir.x < 0:
		return Rect2i(Vector2i(-size.x, at - size.y / 2), size)
	return Rect2i(Vector2i(court.x, at - size.y / 2), size)


# Rooms may touch the court — that edge is their door — but never each other,
# or two rooms become one.
static func _fits(rect: Rect2i, taken: Array[Rect2i], touching: Rect2i = Rect2i()) -> bool:
	for index in taken.size():
		var other: Rect2i = taken[index]
		# The court, and whatever this is meant to share an edge with: touching
		# is the point, overlapping isn't.
		if index == 0 or other == touching:
			if rect.intersects(other):
				return false
			continue
		if rect.grow(1).intersects(other):
			return false
	return true


# The way in, hung off the entrance room and pointing away from the court.
static func _entry_yard(court: Vector2i, entry: Rect2i, taken: Array[Rect2i], layer: String,
		base_y: float, id_prefix: String, used_ids: Dictionary, seed_value: int) -> Dictionary:
	var court_rect := Rect2i(Vector2i.ZERO, court)
	for dir in TYPES.DIRS:
		var rect := _outward_from(entry, dir, Vector2i(2, 2))
		if court_rect.grow(1).intersects(rect) or not _fits(rect, taken, entry):
			continue
		var yard := _unit(LEVEL_PLANNER.next_id(id_prefix, "Yard", used_ids), "pad", "", rect,
			layer, base_y, TYPES.derive_seed(seed_value, "yard"))
		yard["walls"] = false
		return yard
	return {}


static func _outward_from(host: Rect2i, dir: Vector2i, size: Vector2i) -> Rect2i:
	if dir.x > 0:
		return Rect2i(Vector2i(host.end.x, host.position.y), size)
	if dir.x < 0:
		return Rect2i(Vector2i(host.position.x - size.x, host.position.y), size)
	if dir.y > 0:
		return Rect2i(Vector2i(host.position.x, host.end.y), size)
	return Rect2i(Vector2i(host.position.x, host.position.y - size.y), size)


static func _dead_ends(rooms: Array, path: PackedStringArray) -> PackedStringArray:
	var found := PackedStringArray()
	for room in rooms:
		if not String(room["id"]) in path:
			found.append(String(room["id"]))
	return found


# Room types, room sizes and unit ids are the same questions whichever way the
# rooms are arranged, so they're the tree planner's and this borrows them —
# three copies of the openness bias was three places for it to drift.


static func _unit(id: String, kind: String, type_id: String, rect: Rect2i,
		layer: String, base_y: float, seed_value: int) -> Dictionary:
	return {"id": id, "kind": kind, "type": type_id, "rect": rect, "layer": layer,
		"base_y": base_y, "seed": seed_value, "walls": true}
