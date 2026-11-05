@tool
extends Resource

# A region's purpose: which POIs live in it and how much ground there is
# between them. Sibling of LevelArchetype, one scale up.

@export var archetype_id := "frontier_valley"
@export var display_name := "Frontier Valley"
@export var poi_mix: PackedStringArray = PackedStringArray()
# POI count per size class: small, medium, large.
@export var poi_counts: PackedInt32Array = PackedInt32Array([3, 4, 6])
# No map-edge knob here yet on purpose: the region's extent falls out of how big
# the plots turn out to be, so a declared size would be a number nothing reads.
# It comes back with the terrain work, which needs a real boundary to carve to.


func poi_count(size_class: int) -> int:
	if poi_counts.is_empty():
		return 3
	return poi_counts[clampi(size_class, 0, poi_counts.size() - 1)]
