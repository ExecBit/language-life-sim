@tool
extends Object

# Level brief → room graph. Rooms are rectangles (sometimes L-shaped) on the
# module grid, joined by one-module-wide corridors; the corridor IS the doorway,
# because the shell builder only walls edges that face nothing.
#
# The building grows as a tree off the entrance, which is what makes the rest
# possible: depth from the front door gives you wings without a wing solver
# (taproom at the front, cells at the back), the entry-to-goal walk gives you a
# critical path, and everything hanging off that path is a dead end worth
# putting something in.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")

const PLACE_ATTEMPTS := 32
const ADJACENCY_BONUS := 6.0   # "this room belongs next to that one"
const DEPTH_BONUS := 3.0       # "this room belongs at the front / at the back"


# `pinned` are units the caller wants left exactly where they are — locked rooms
# and the corridors hanging off them. They come in as already-placed, keep their
# ids, and the rest of the building grows around them.
static func plan(level_arch: Resource, size_class: int, seed_value: int,
		layer: String = "level", base_y: float = 0.0, id_prefix: String = "",
		pinned: Array = [], shape: Dictionary = {}) -> Dictionary:
	var openness := float(shape.get("openness", 0.5))
	var branching := float(shape.get("branching", 0.5))
	var rng := TYPES.rng_for(seed_value)
	# ±1 room, or every dungeon of a given size has exactly the same room count
	# and the place starts to feel prefabricated before you've walked it
	var want: int = maxi(1, level_arch.room_count(size_class) + rng.randi_range(-1, 1))

	var units: Array[Dictionary] = []
	var rooms: Array[Dictionary] = []       # every room, with its tree position
	var room_rects: Array[Rect2i] = []
	var corridor_rects: Array[Rect2i] = []
	var used_ids := {}
	var pinned_rooms := 0

	for entry in pinned:
		var kept: Dictionary = (entry as Dictionary).duplicate()
		kept["kept"] = true  # already built — don't emit nodes for it again
		units.append(kept)
		used_ids[String(kept["id"])] = true
		if String(kept["kind"]) == "room":
			room_rects.append(kept["rect"])
			rooms.append({"id": String(kept["id"]), "type": String(kept["type"]),
				"rect": kept["rect"], "depth": 0, "parent": "", "grown": false})
			pinned_rooms += 1
		else:
			corridor_rects.append(kept["rect"])

	var types := room_type_sequence(level_arch, maxi(want, pinned_rooms + 1), rng)
	# open places have longer runs between their rooms; tight ones are cellular
	var corridor_min: int = maxi(1, level_arch.corridor_modules.x)
	var corridor_max: int = maxi(corridor_min,
		level_arch.corridor_modules.y + int(round((openness - 0.5) * 2.0)))
	var wants: Dictionary = level_arch.adjacency()

	var placed := pinned_rooms
	var next_type := pinned_rooms

	if room_rects.is_empty():
		# The room you walk into carries a doorway the others don't — the front
		# door — and every doorway costs a lane. Build it a module bigger so it
		# can afford one and still be the room it's meant to be.
		var first_size := room_size(types[0], rng, openness) + Vector2i.ONE
		var first := _unit(next_id(id_prefix, "Room", used_ids), "room", types[0],
			Rect2i(Vector2i.ZERO, first_size), layer, base_y, _room_seed(seed_value, 0, types[0]))
		units.append(first)
		room_rects.append(first["rect"])
		rooms.append({"id": String(first["id"]), "type": types[0], "rect": first["rect"],
			"depth": 0, "parent": "", "grown": true})
		placed += 1
		next_type += 1

	# Dangling corridor ends come first: a pinned corridor whose far room was
	# regenerated away already has an opening there, so putting a room back is
	# the one placement that costs no geometry change at all.
	for entry in pinned:
		if placed >= want:
			break
		if String(entry["kind"]) != "corridor":
			continue
		for end_slot in _open_ends(entry, units):
			if placed >= want:
				break
			var type_id: String = types[mini(next_type, types.size() - 1)]
			var attached := _attach_at_end(end_slot, room_size(type_id, rng))
			if not _fits(attached, room_rects, corridor_rects, [entry["rect"] as Rect2i]):
				continue
			var room := _unit(next_id(id_prefix, "Room", used_ids), "room", type_id, attached,
				layer, base_y, _room_seed(seed_value, placed, type_id))
			units.append(room)
			room_rects.append(attached)
			# whatever the pinned corridor already leads to is this room's parent —
			# without that link the tree has two roots and the critical path
			# starts in the wrong place
			var host := _room_touching(rooms, entry["rect"])
			rooms.append({"id": String(room["id"]), "type": type_id, "rect": attached,
				"depth": (int(host["depth"]) + 1) if not host.is_empty() else 1,
				"parent": String(host["id"]) if not host.is_empty() else "", "grown": true})
			placed += 1
			next_type += 1

	# A room that won't fit anywhere gets the next one a turn rather than ending
	# the level — a different size roll often lands where the last one couldn't.
	var misses := 0
	while placed < want and misses < 3 and _has_growable(rooms):
		var landed := false
		var type_id: String = types[mini(next_type, types.size() - 1)]
		for attempt in PLACE_ATTEMPTS:
			var parent: Dictionary = _pick_parent(rooms, type_id, wants, level_arch, rng, branching)
			if parent.is_empty():
				break
			var parent_rect: Rect2i = parent["rect"]
			var dir: Vector2i = TYPES.DIRS[rng.randi_range(0, TYPES.DIRS.size() - 1)]
			var slot := _slot(parent_rect, room_size(type_id, rng, openness), dir,
				rng.randi_range(corridor_min, corridor_max), rng)
			var child_rect: Rect2i = slot["room"]
			var corridor_rect: Rect2i = slot["corridor"]
			if not _fits(child_rect, room_rects, corridor_rects, []):
				continue
			if not _fits(corridor_rect.grow(1), room_rects, corridor_rects, [parent_rect, child_rect], false):
				continue
			var corridor := _unit(next_id(id_prefix, "Corridor", used_ids), "corridor", "", corridor_rect,
				layer, base_y, TYPES.derive_seed(seed_value, "corridor:%d" % placed))
			corridor["axis"] = Vector2i(absi(dir.x), absi(dir.y))
			units.append(corridor)
			var room := _unit(next_id(id_prefix, "Room", used_ids), "room", type_id, child_rect,
				layer, base_y, _room_seed(seed_value, placed, type_id))
			units.append(room)
			room_rects.append(child_rect)
			corridor_rects.append(corridor_rect)
			rooms.append({"id": String(room["id"]), "type": type_id, "rect": child_rect,
				"depth": int(parent["depth"]) + 1, "parent": String(parent["id"]), "grown": true})
			placed += 1
			next_type += 1
			landed = true
			break
		if not landed:
			misses += 1
			next_type += 1

	# The yard goes on BEFORE any corner gets knocked off, so that the edge it
	# shares with the building counts as a doorway and the irregular pass knows
	# not to cut it away. Do it the other way round and the front door ends up
	# opening onto the piece of room that was just removed.
	var entry_unit := String(rooms[0]["id"]) if not rooms.is_empty() else ""
	var goal_unit := _deepest(rooms)
	var yard := _entry_yard(level_arch, rooms, units, room_rects, corridor_rects, layer, base_y,
		id_prefix, used_ids, seed_value, rng)
	if not yard.is_empty():
		units.append(yard)

	# Knock a corner off some of them. A building of nothing but rectangles is
	# the other half of why generated levels look generated.
	_make_irregular(units, rooms, level_arch, rng)

	var path := _critical_path(rooms, entry_unit, goal_unit)
	return {
		"layer": layer,
		"units": units,
		"occupancy": occupancy_of(units),
		"bounds": bounds_of(units),
		"entry_unit": entry_unit,
		"goal_unit": goal_unit,
		"yard_unit": String(yard["id"]) if not yard.is_empty() else "",
		"rooms": rooms,
		"critical_path": path,
		"dead_ends": _dead_ends(rooms, path),
		"seed": seed_value,
	}


# Shift a whole plan on the module grid — the world planner drops levels onto
# plots this way, so the level planner never needs to know where it landed.
static func translate(level_plan: Dictionary, offset: Vector2i) -> Dictionary:
	var moved: Array[Dictionary] = []
	for unit in level_plan["units"]:
		var copy: Dictionary = (unit as Dictionary).duplicate()
		copy["rect"] = Rect2i((unit["rect"] as Rect2i).position + offset, (unit["rect"] as Rect2i).size)
		var cells: Array = unit.get("cells", [])
		if not cells.is_empty():
			copy["cells"] = cells.map(func(c: Vector2i) -> Vector2i: return c + offset)
		moved.append(copy)
	var out := level_plan.duplicate()
	out["units"] = moved
	out["occupancy"] = occupancy_of(moved)
	out["bounds"] = bounds_of(moved)
	return out


static func occupancy_of(units: Array) -> Dictionary:
	var occupancy := {}
	for unit in units:
		for cell in TYPES.unit_cells(unit):
			occupancy[cell] = String(unit["id"])
	return occupancy


static func bounds_of(units: Array) -> Rect2i:
	if units.is_empty():
		return Rect2i()
	var bounds: Rect2i = units[0]["rect"]
	for unit in units:
		bounds = bounds.merge(unit["rect"])
	return bounds


static func unit_by_id(units: Array, id: String) -> Dictionary:
	for unit in units:
		if String(unit["id"]) == id:
			return unit
	return {}


# ---- how the building takes shape ------------------------------------------

# Which room a new one should hang off. Adjacency is a strong pull ("cells go
# off the guardroom"), depth is a weaker one ("the taproom is near the door"),
# and there's enough randomness left that two seeds don't build the same house.
static func _pick_parent(rooms: Array, type_id: String, wants: Dictionary,
		level_arch: Resource, rng: RandomNumberGenerator, branching: float = 0.5) -> Dictionary:
	var candidates: Array = []
	var best := -INF
	for room in rooms:
		if not bool(room["grown"]):
			continue  # pinned rooms keep the geometry they have; don't cut new doors
		var score := rng.randf() * 2.0
		# Low branching keeps growing off whatever is furthest out, which walks
		# the plan onward in a line. High branching hangs the next room off
		# something near the front, which bushes out into a warren.
		var depth_now := int(room["depth"])
		score += lerpf(float(depth_now), -float(depth_now), branching) * 1.5
		var wanted: Array = wants.get(type_id, [])
		if String(room["type"]) in wanted:
			score += ADJACENCY_BONUS
		var depth := int(room["depth"])
		if type_id in level_arch.shallow_rooms:
			score += DEPTH_BONUS / float(1 + depth)
		elif type_id in level_arch.deep_rooms:
			score += DEPTH_BONUS * float(depth) / float(1 + depth)
		candidates.append([score, room])
		best = maxf(best, score)
	if candidates.is_empty():
		return {}
	var shortlist: Array = []
	for entry in candidates:
		if float(entry[0]) >= best - 1.0:
			shortlist.append(entry[1])
	return shortlist[rng.randi_range(0, shortlist.size() - 1)]


static func _room_touching(rooms: Array, rect: Rect2i) -> Dictionary:
	for room in rooms:
		if (room["rect"] as Rect2i).intersects(rect.grow(1)):
			return room
	return {}


static func _has_growable(rooms: Array) -> bool:
	for room in rooms:
		if bool(room["grown"]):
			return true
	return false


# Knocks a corner block out of a room, leaving an L. Entry rooms are left alone
# — the spawn and the front door both key off their shape.
static func _make_irregular(units: Array, rooms: Array, level_arch: Resource,
		rng: RandomNumberGenerator) -> void:
	var chance: float = level_arch.irregular_rooms
	if chance <= 0.0:
		return
	# Cells with a neighbour belonging to something else are doorways. Cut one of
	# those away and the corridor now opens onto a hole, with everything past it
	# stranded — which is exactly what happened the first time this ran.
	var occupancy := occupancy_of(units)
	var doorways := {}
	for cell in occupancy:
		for dir in TYPES.DIRS:
			var neighbour: Vector2i = cell + dir
			if occupancy.has(neighbour) and String(occupancy[neighbour]) != String(occupancy[cell]):
				doorways[cell] = true
				break

	for index in range(1, rooms.size()):
		var room: Dictionary = rooms[index]
		var rect: Rect2i = room["rect"]
		if not bool(room.get("grown", true)):
			continue  # pinned: its walls are already standing and we promised not to move them
		if bool(room.get("hosts_yard", false)):
			continue
		if rect.size.x < 2 or rect.size.y < 2 or rng.randf() > chance:
			continue
		# min_modules is a hard floor everywhere else, and it has to be one here
		# too: cut a smithy below the size a forge needs and no amount of
		# repairing will make it a smithy again.
		var arch := LIBRARY.room_archetype(String(room["type"]))
		var must_fit := Vector2i.ONE
		if arch != null:
			must_fit = (arch.min_modules as Vector2i).max(Vector2i.ONE)
		var unit := room_unit_of(units, String(room["id"]))
		if unit.is_empty():
			continue
		# a few goes at it: one corner may hold a doorway while another is free
		for attempt in 4:
			var bite := Vector2i(rng.randi_range(1, rect.size.x - 1), rng.randi_range(1, rect.size.y - 1))
			var corner := rng.randi_range(0, 3)  # which corner loses the block
			var cut := Rect2i(rect.position + Vector2i(
				0 if corner % 2 == 0 else rect.size.x - bite.x,
				0 if corner < 2 else rect.size.y - bite.y), bite)
			var kept: Array = []
			var takes_a_doorway := false
			for cell in TYPES.unit_cells(unit):
				if not cut.has_point(cell):
					kept.append(cell)
				elif doorways.has(cell):
					takes_a_doorway = true
			# Area isn't the test — shape is. An L with the right number of
			# modules can still be a one-module strip, and a forge doesn't fit
			# down a corridor.
			if takes_a_doorway or not _block_fits(kept, must_fit):
				continue
			unit["cells"] = kept
			break


# Is there still an unbroken block this big somewhere in what's left?
static func _block_fits(cells: Array, size: Vector2i) -> bool:
	var present := {}
	for cell in cells:
		present[cell] = true
	for origin in cells:
		var whole := true
		for z in size.y:
			for x in size.x:
				if not present.has((origin as Vector2i) + Vector2i(x, z)):
					whole = false
					break
			if not whole:
				break
		if whole:
			return true
	return false


static func room_unit_of(units: Array, id: String) -> Dictionary:
	for unit in units:
		if String(unit["id"]) == id:
			return unit
	return {}


# An open approach outside the front door. It's a pad, so it has no walls, and
# the edge it shares with the entry room is therefore a doorway — which is how a
# generated building stops being a sealed box.
#
# It has to stick out past the rest of the building. A yard that fits neatly
# inside the footprint is a courtyard: lovely, reachable from inside, and no use
# whatsoever as a way in — which is exactly how one point of interest in twelve
# ended up sealed with a front door it couldn't be reached through.
static func _entry_yard(level_arch: Resource, rooms: Array, units: Array,
		room_rects: Array[Rect2i], corridor_rects: Array[Rect2i], layer: String, base_y: float,
		id_prefix: String, used_ids: Dictionary, seed_value: int, rng: RandomNumberGenerator) -> Dictionary:
	if not level_arch.entry_yard or rooms.is_empty():
		return {}
	var footprint := bounds_of(rooms)
	var declared: Vector2i = level_arch.entry_yard_modules
	var wanted := declared.max(Vector2i.ONE)

	var sides: Array = TYPES.DIRS.duplicate()
	for i in range(sides.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Vector2i = sides[i]
		sides[i] = sides[j]
		sides[j] = swap

	# The entrance the archetype asked for gets first refusal; if it's walled in
	# on every side, the front door goes on the next room out rather than nowhere.
	var hosts: Array = _hosts_by_depth(rooms)
	# A corridor is the last resort and a perfectly good one: an entrance
	# passage. Corridors hold no furniture, so a door onto one costs nothing,
	# where a second door in a small room can cost it the thing it's for.
	for unit in units:
		if String(unit["kind"]) == "corridor":
			hosts.append({"id": String(unit["id"]), "rect": unit["rect"], "type": "", "depth": 99})
	for host in hosts:
		if not _can_spare_a_door(host):
			continue
		var host_rect: Rect2i = host["rect"]
		var size := wanted
		while size.x >= 1 and size.y >= 1:
			for dir in sides:
				for offset in _yard_offsets(host_rect, dir):
					var rect := _yard_rect_at(host_rect, size, dir, offset)
					if footprint.encloses(rect):
						continue  # a courtyard, not a way in
					# Overlapping anything is out. Touching the host room is the
					# whole point — that edge is the front door — and touching a
					# corridor just gives it a side door, which costs nothing
					# since corridors hold no furniture. Touching any OTHER room
					# does cost something: a second doorway in a small room can
					# leave no wall long enough to put its anchor against.
					if not _fits(rect, room_rects, corridor_rects, [], false):
						continue
					if not _rooms_can_afford(rect, rooms, host):
						continue
					var yard := _unit(next_id(id_prefix, "Yard", used_ids), "pad", "", rect,
						layer, base_y, TYPES.derive_seed(seed_value, "yard"))
					yard["walls"] = false
					# the room with the front door is already carrying an extra
					# doorway; it doesn't also get a corner knocked off it
					host["hosts_yard"] = true
					return yard
			size -= Vector2i.ONE
	return {}


# Every room the yard would open onto has to be able to take the extra door,
# not just the one it's attached to. An entrance passage beside two cramped
# rooms puts a door in both of them.
static func _rooms_can_afford(rect: Rect2i, rooms: Array, host: Dictionary) -> bool:
	var zone := rect.grow(1)
	for room in rooms:
		if String(room["id"]) == String(host["id"]):
			continue
		if not zone.intersects(room["rect"]):
			continue
		if not _can_spare_a_door(room):
			return false
	return true


# Can this room afford another doorway? Every door reserves a lane to the middle
# of the room, and in a room that's only just big enough for its anchor, two
# lanes leave nowhere to put it. Rooms with a module to spare can take a second
# door; rooms at their archetype minimum can't.
static func _can_spare_a_door(host: Dictionary) -> bool:
	if String(host["type"]) == "":
		return true  # a corridor is nothing but circulation already
	var arch := LIBRARY.room_archetype(String(host["type"]))
	if arch == null:
		return true
	var lo: Vector2i = arch.min_modules
	return (host["rect"] as Rect2i).get_area() > lo.x * lo.y


# The declared entrance first, then outward — a front door on the second room is
# still a front door.
static func _hosts_by_depth(rooms: Array) -> Array:
	var ordered: Array = rooms.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["depth"]) < int(b["depth"]))
	return ordered


static func _yard_offsets(entry: Rect2i, dir: Vector2i) -> Array:
	var span: int = entry.size.y if dir.x != 0 else entry.size.x
	var offsets: Array = []
	for i in maxi(1, span):
		offsets.append(i)
	return offsets


static func _yard_rect_at(entry: Rect2i, size: Vector2i, dir: Vector2i, offset: int) -> Rect2i:
	if dir.x > 0:
		return Rect2i(Vector2i(entry.end.x, entry.position.y + offset), size)
	if dir.x < 0:
		return Rect2i(Vector2i(entry.position.x - size.x, entry.position.y + offset), size)
	if dir.y > 0:
		return Rect2i(Vector2i(entry.position.x + offset, entry.end.y), size)
	return Rect2i(Vector2i(entry.position.x + offset, entry.position.y - size.y), size)


# The furthest room from the front door, which is where the thing you came for
# belongs. "Last one placed" is nearly this and occasionally embarrassing.
static func _deepest(rooms: Array) -> String:
	var best := ""
	var deepest := -1
	for room in rooms:
		if int(room["depth"]) > deepest:
			deepest = int(room["depth"])
			best = String(room["id"])
	return best


static func _critical_path(rooms: Array, entry_id: String, goal_id: String) -> PackedStringArray:
	var by_id := {}
	for room in rooms:
		by_id[String(room["id"])] = room
	var path := PackedStringArray()
	var cursor := goal_id
	var guard := 0
	while cursor != "" and by_id.has(cursor) and guard < 64:
		path.append(cursor)
		if cursor == entry_id:
			break
		cursor = String(by_id[cursor]["parent"])
		guard += 1
	path.reverse()
	return path


# Every room that isn't on the way to the goal, and has nothing hanging off it.
# These are the rooms a player only visits on purpose, so they're where the
# reward for looking around belongs.
static func _dead_ends(rooms: Array, path: PackedStringArray) -> PackedStringArray:
	var has_child := {}
	for room in rooms:
		var parent := String(room["parent"])
		if parent != "":
			has_child[parent] = true
	var found := PackedStringArray()
	for room in rooms:
		var id := String(room["id"])
		if id in path or has_child.has(id):
			continue
		found.append(id)
	return found


# ---- internals -------------------------------------------------------------

static func _unit(id: String, kind: String, type_id: String, rect: Rect2i,
		layer: String, base_y: float, seed_value: int) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"type": type_id,
		"rect": rect,
		"layer": layer,
		"base_y": base_y,
		"seed": seed_value,
		"walls": true,
	}


static func room_type_sequence(level_arch: Resource, want: int, rng: RandomNumberGenerator) -> PackedStringArray:
	var mix: PackedStringArray = level_arch.room_mix
	if mix.is_empty():
		mix = PackedStringArray(["bedroom"])
	var types := PackedStringArray()
	types.append(level_arch.entry_room if level_arch.entry_room != "" else mix[0])
	for i in range(1, want):
		types.append(mix[rng.randi_range(0, mix.size() - 1)])
	if want > 1 and level_arch.goal_room != "":
		types[want - 1] = level_arch.goal_room
	return types


# The room type is part of the salt, so a smithy and a bedroom in the same slot
# of the same seed don't come out furnished identically.
static func _room_seed(parent_seed: int, index: int, type_id: String) -> int:
	return TYPES.derive_seed(parent_seed, "room:%d:%s" % [index, type_id])


# Openness slides which end of the archetype's own range gets rolled in. It
# never leaves that range: min_modules is still the size below which the room
# stops being what it's named after.
static func room_size(type_id: String, rng: RandomNumberGenerator, openness: float = 0.5) -> Vector2i:
	var arch := LIBRARY.room_archetype(type_id)
	if arch == null:
		return Vector2i(2, 2)
	var lo: Vector2i = arch.min_modules
	var hi: Vector2i = (arch.max_modules as Vector2i).max(lo)
	var bias := Vector2i(
		int(round(float(hi.x - lo.x) * (openness - 0.5))),
		int(round(float(hi.y - lo.y) * (openness - 0.5))))
	var low := (lo + bias.max(Vector2i.ZERO)).min(hi)
	var high := (hi + bias.min(Vector2i.ZERO)).max(low)
	return Vector2i(rng.randi_range(low.x, high.x), rng.randi_range(low.y, high.y))


# Where a child room and its corridor would land if we grew off parent in dir.
static func _slot(parent: Rect2i, size: Vector2i, dir: Vector2i, corridor_len: int,
		rng: RandomNumberGenerator) -> Dictionary:
	if dir.x != 0:
		# corridor runs along X out of one of the parent's rows
		var row := rng.randi_range(parent.position.y, parent.end.y - 1)
		var child_z := row - rng.randi_range(0, size.y - 1)
		if dir.x > 0:
			return {
				"corridor": Rect2i(parent.end.x, row, corridor_len, 1),
				"room": Rect2i(Vector2i(parent.end.x + corridor_len, child_z), size),
			}
		return {
			"corridor": Rect2i(parent.position.x - corridor_len, row, corridor_len, 1),
			"room": Rect2i(Vector2i(parent.position.x - corridor_len - size.x, child_z), size),
		}
	var col := rng.randi_range(parent.position.x, parent.end.x - 1)
	var child_x := col - rng.randi_range(0, size.x - 1)
	if dir.y > 0:
		return {
			"corridor": Rect2i(col, parent.end.y, 1, corridor_len),
			"room": Rect2i(Vector2i(child_x, parent.end.y + corridor_len), size),
		}
	return {
		"corridor": Rect2i(col, parent.position.y - corridor_len, 1, corridor_len),
		"room": Rect2i(Vector2i(child_x, parent.position.y - corridor_len - size.y), size),
	}


# Sequential ids that skip whatever is already taken, so a pinned Room_2 keeps
# its name and nothing else can claim it.
static func next_id(prefix: String, kind: String, used_ids: Dictionary) -> String:
	var index := 0
	while true:
		var candidate := "%s%s_%d" % [prefix, kind, index]
		if not used_ids.has(candidate):
			used_ids[candidate] = true
			return candidate
		index += 1
	return ""


# The cells just past a corridor's two ends, and the direction out. An end is
# open when nothing occupies it — which is exactly what a pinned corridor looks
# like once the room it used to lead to has been regenerated away.
#
# Ends only, never the long sides: a corridor's sides are walled, so hanging a
# room off one would need a doorway cut into geometry we promised not to touch.
# A one-module corridor is square, so the axis can't be recovered from the rect
# — it's recorded on the unit when the corridor is planned.
static func _open_ends(corridor_unit: Dictionary, units: Array) -> Array:
	var corridor: Rect2i = corridor_unit["rect"]
	var along: Vector2i = corridor_unit.get("axis",
		Vector2i(1, 0) if corridor.size.x >= corridor.size.y else Vector2i(0, 1))
	var occupied := occupancy_of(units)
	var ends: Array = []
	for dir in [along, -along]:
		var cell: Vector2i = corridor.position - along if dir == -along else corridor.end - Vector2i.ONE + along
		if not occupied.has(cell):
			ends.append({"cell": cell, "dir": dir})
	return ends


# Put a room's edge flush against an open corridor end.
static func _attach_at_end(end_slot: Dictionary, size: Vector2i) -> Rect2i:
	var cell: Vector2i = end_slot["cell"]
	var dir: Vector2i = end_slot["dir"]
	if dir.x > 0:
		return Rect2i(Vector2i(cell.x, cell.y - size.y / 2), size)
	if dir.x < 0:
		return Rect2i(Vector2i(cell.x - size.x + 1, cell.y - size.y / 2), size)
	if dir.y > 0:
		return Rect2i(Vector2i(cell.x - size.x / 2, cell.y), size)
	return Rect2i(Vector2i(cell.x - size.x / 2, cell.y - size.y + 1), size)


# Rooms keep a one-module gap from everything. That gap is what makes a shared
# edge mean "doorway" instead of "two rooms fused into one" — corridors are the
# only things allowed to touch, and only the two they connect.
static func _fits(rect: Rect2i, room_rects: Array[Rect2i], corridor_rects: Array[Rect2i],
		allow: Array, grow_first: bool = true) -> bool:
	var zone := rect.grow(1) if grow_first else rect
	for other in room_rects:
		if other in allow:
			continue
		if zone.intersects(other):
			return false
	for other in corridor_rects:
		if other in allow:
			continue
		if zone.intersects(other):
			return false
	return true
