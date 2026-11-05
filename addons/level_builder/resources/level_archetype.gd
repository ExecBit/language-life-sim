@tool
extends Resource

# A building's purpose: which rooms it's made of, how many, which one you walk
# in through, and — the part that makes it read as a building rather than a
# heap of rooms — which rooms belong next to which.
#
# The same scale-free pipeline as a room. Rooms are the "props", corridors are
# the "routes", the goal room is the "anchor".

@export var archetype_id := "dungeon"
@export var display_name := "Dungeon"
@export var room_mix: PackedStringArray = PackedStringArray()
# Room count per size class: small, medium, large. Varies by ±1 per seed.
@export var room_counts: PackedInt32Array = PackedInt32Array([3, 5, 8])
@export var entry_room := ""
@export var goal_room := ""
# Corridor length in modules, min/max.
@export var corridor_modules := Vector2i(1, 2)

@export_group("How it's laid out")
# Which planner arranges the place. "tree" grows rooms outward off the entrance
# down corridors — a building. "court" rings them around one open space — a
# cloister, a caravanserai, a hive around its chamber, a reactor ring. The
# planner decides the topology; everything downstream is the same.
@export_enum("tree", "court") var planner := "tree"
# court only: how big the open middle is, in modules.
@export var court_modules := Vector2i(3, 3)
# "a>b" — a room of type a wants to be next door to a room of type b. A strong
# preference, not a rule: a kitchen off the hall, cells off the guardroom.
@export var adjacency_pairs: PackedStringArray = PackedStringArray()
# Rooms that belong near the way in (the taproom, the guardroom) and rooms that
# belong at the back (the vault, the cells). Wings, without a wing solver.
@export var shallow_rooms: PackedStringArray = PackedStringArray()
@export var deep_rooms: PackedStringArray = PackedStringArray()
# An open approach outside the front door, so the building has an outside and
# somewhere to arrive. Also what gives the entry room a door to the world.
@export var entry_yard := true
@export var entry_yard_modules := Vector2i(2, 2)
# How often a room comes out L-shaped instead of a plain rectangle, 0..1.
@export_range(0.0, 1.0) var irregular_rooms := 0.25


func room_count(size_class: int) -> int:
	if room_counts.is_empty():
		return 3
	return room_counts[clampi(size_class, 0, room_counts.size() - 1)]


# type -> the types it would rather be next to.
func adjacency() -> Dictionary:
	var wants := {}
	for pair in adjacency_pairs:
		var halves := String(pair).split(">")
		if halves.size() != 2:
			continue
		var from := halves[0].strip_edges()
		var to := halves[1].strip_edges()
		if not wants.has(from):
			wants[from] = []
		(wants[from] as Array).append(to)
	return wants
