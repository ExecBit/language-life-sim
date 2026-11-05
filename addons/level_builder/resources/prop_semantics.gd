@tool
extends Resource

# What a prop MEANS, so the solver can place it on purpose instead of at random.
# One resource per asset, living beside the asset or in defaults/generation/.
# Untagged assets never generate — the solver would only be guessing.

@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
# bed, forge, altar, storage, pillar… — archetypes ask for props by tag.
@export var tags: PackedStringArray = PackedStringArray()
@export var footprint := Vector2i(1, 1)  # solver cells
# Kit pieces (floors, walls) carry semantics too but are never furniture.
@export var is_prop := true

# The must / prefer / never rules, as data.
#
# prefer_zones is a weighted nudge: wall, corner, center, work, storage,
# presentation, clutter, entrance. avoid_zones is a veto — nothing is ever
# placed on one, however good the rest of the score looks. Leave prefer_zones
# empty and the thing is happy anywhere that isn't vetoed.
@export var prefer_zones: PackedStringArray = PackedStringArray()
@export var avoid_zones: PackedStringArray = PackedStringArray(["travel", "entrance"])
@export var prefer_weight := 3.0
# Tags this wants within reach (a nightstand wants a bed) and tags it won't sit
# next to (a bed doesn't want the forge). Both measured in solver cells.
@export var needs_nearby: PackedStringArray = PackedStringArray()
@export var needs_range := 4
@export var avoids: PackedStringArray = PackedStringArray()
@export var avoids_range := 3
@export var style_tags: PackedStringArray = PackedStringArray()


func scene() -> PackedScene:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return null
	return load(scene_path) as PackedScene


func has_tag(tag: String) -> bool:
	return tag in tags
