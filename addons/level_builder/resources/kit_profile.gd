@tool
extends Resource

# The modular-kit contract: everything the shell builder needs to lay pieces on
# a grid without knowing which kit it's holding. Paths not PackedScenes on
# purpose — the addon folder must not hard-depend on demo/, and a missing piece
# should be a readable finding, not a broken ext_resource.

@export var kit_id := "greybox"
@export var display_name := "Greybox"
@export var module := 4.0          # shell grid pitch in metres — one floor piece
@export var cell := 1.0            # solver grid pitch in metres
@export var floor_thickness := 0.2 # walkable surface height above a piece origin

@export_file("*.tscn") var floor_scene_path := ""
@export_file("*.tscn") var wall_scene_path := ""
# Roads and POI plots. Empty falls back to the floor piece.
@export_file("*.tscn") var path_scene_path := ""


func resolve(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func floor_scene() -> PackedScene:
	return resolve(floor_scene_path)


func wall_scene() -> PackedScene:
	return resolve(wall_scene_path)


func path_scene() -> PackedScene:
	var scene := resolve(path_scene_path)
	return scene if scene else floor_scene()


# Which declared pieces are actually on disk. Empty = kit is usable.
func missing_pieces() -> PackedStringArray:
	var missing := PackedStringArray()
	if floor_scene() == null:
		missing.append(floor_scene_path if floor_scene_path != "" else "floor")
	if wall_scene() == null:
		missing.append(wall_scene_path if wall_scene_path != "" else "wall")
	return missing
