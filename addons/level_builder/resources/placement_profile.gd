@tool
extends Resource

# Per-category placement defaults: where placed things get parented and what
# gets auto-applied so drop #40 is as correct as drop #1. Ships as .tres in
# defaults/; category "" is the fallback profile.

@export var category := ""
@export var container_name := "Props"
# -1 = leave collision alone (asset already has it / doesn't want it).
# Otherwise a collider_tools.Policy value applied when the instance has none.
@export var collider_policy := -1
@export var layer_profile: Resource
@export var snap_step := 1.0
@export var align_to_surface := false
@export var random_y_rotation := false
@export var scale_jitter_min := 1.0
@export var scale_jitter_max := 1.0
