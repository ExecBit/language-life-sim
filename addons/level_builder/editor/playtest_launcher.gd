@tool
extends Object

# Test Walk plumbing. Builds a wrapper scene (level instance + a player at
# PlayerSpawn) and saves it for EditorInterface.play_custom_scene.
#
# The wrapper runs the level as SAVED ON DISK — the dock prompts save-first,
# otherwise the user walks a stale level and thinks the tool is broken.
#
# Wrapper lives at res:// project root: play_custom_scene needs a res:// path,
# and .gdignore'd folders can't be loaded from. Overwritten every walk, safe
# to delete, says so in its root node name.

const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const TEST_PLAYER := preload("res://addons/level_builder/runtime/test_player.gd")

const WRAPPER_PATH := "res://lb_test_run.tscn"
const SPAWN_LIFT := 0.5  # start the capsule a hair above the marker


static func controller_pack_present() -> bool:
	return DirAccess.dir_exists_absolute("res://addons/controller")


# Spawn transform in level-root space, without needing the scene in a tree.
static func find_spawn_transform(level_root: Node) -> Transform3D:
	var spawn := BOOTSTRAP.find_spawn(level_root) as Marker3D
	if spawn == null:
		return Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
	var t := Transform3D.IDENTITY
	var cursor: Node = spawn
	while cursor != null and cursor != level_root:
		if cursor is Node3D:
			t = (cursor as Node3D).transform * t
		cursor = cursor.get_parent()
	return t


# level_scene must be saved (have a resource_path) so the wrapper references it
# instead of inlining a stale copy. custom_player: optional scene to use
# instead of the bundled walker (must handle its own camera).
static func build_wrapper(level_scene: PackedScene, custom_player: PackedScene = null) -> PackedScene:
	var root := Node3D.new()
	root.name = "LBTestRun_SafeToDelete"

	var level := level_scene.instantiate()
	root.add_child(level)
	level.owner = root

	var spawn_t := find_spawn_transform(level)
	var player: Node3D
	if custom_player:
		player = custom_player.instantiate()
	else:
		player = CharacterBody3D.new()
		player.set_script(TEST_PLAYER)
	player.name = "TestPlayer"
	player.transform = spawn_t
	player.position += Vector3.UP * SPAWN_LIFT
	root.add_child(player)
	player.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return null
	root.free()
	return packed


# Editor-side: save wrapper + launch. Kept tiny so everything above stays
# headless-testable.
static func save_and_play(level_scene: PackedScene, custom_player: PackedScene = null) -> bool:
	var wrapper := build_wrapper(level_scene, custom_player)
	if wrapper == null:
		return false
	if ResourceSaver.save(wrapper, WRAPPER_PATH) != OK:
		return false
	EditorInterface.play_custom_scene(WRAPPER_PATH)
	return true
