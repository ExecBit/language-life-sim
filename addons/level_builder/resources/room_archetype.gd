@tool
extends Resource

# A room's purpose, as data. The anchor is the thing the room is FOR; supports
# are what that activity needs within reach. Everything else is dressing, and
# dressing comes later in the pipeline.

@export var archetype_id := "bedroom"
@export var display_name := "Bedroom"
@export var min_modules := Vector2i(2, 2)
@export var max_modules := Vector2i(3, 3)
# The one prop that must land or the room is a failure. It's also the lead of
# the room's first activity group — the thing the room is FOR.
@export var anchor_tag := "bed"
# ActivityGroup ids. The first is the room's reason for being and has to land;
# the rest are placed if there's room and dropped if there isn't.
@export var groups: PackedStringArray = PackedStringArray()
# How many of each group to try for — a tavern wants one bar and three tables.
# Counts above one vary by ±1 per seed, so taverns don't all seat the same
# number. The first group is the room's anchor and is always placed exactly
# once, whatever this says.
@export var group_counts: PackedInt32Array = PackedInt32Array()
# What the parts of this room are for, in order. Empty means the room has only
# the structural zones — wall, corner, centre — which is a perfectly good answer
# for a space that's just a space.
@export var zone_rules: Array[Resource] = []
# Placed last, wherever they're welcome. Clutter fills a room; it never leads it.
@export var clutter_tags: PackedStringArray = PackedStringArray()


func count_for(index: int) -> int:
	if index < 0 or index >= group_counts.size():
		return 1
	return maxi(1, group_counts[index])
