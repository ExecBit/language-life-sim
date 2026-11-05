extends SceneTree

const GENERATOR := preload("res://addons/level_builder/generator/generator.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const WALKER := preload("res://addons/level_builder/runtime/test_player.gd")
const PROP_FILES := [
	"prop_kaykit_table_round.tres",
	"prop_kaykit_table_round_small.tres",
	"prop_kaykit_chair.tres",
	"prop_kaykit_stool.tres",
	"prop_kaykit_cabinet.tres",
	"prop_kaykit_bar_counter.tres",
	"prop_kaykit_kitchen_counter.tres",
	"prop_kaykit_stove.tres",
	"prop_kaykit_crate.tres",
	"prop_kaykit_crate_potatoes.tres",
	"prop_kaykit_couch.tres",
	"prop_kaykit_fridge.tres",
]
const GROUP_FILES := [
	"group_tavern_bar.tres",
	"group_tavern_tables.tres",
	"group_tavern_kitchen.tres",
	"group_tavern_lounge.tres",
	"group_tavern_storage.tres",
]
const OUTPUT := "res://experiments/level_builder_lite/kaykit_tavern.tscn"
const GENERATION_DIR := "res://addons/level_builder/defaults/generation"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 7001
	var output_path := OUTPUT
	if args.size() > 0:
		seed_value = int(args[0])
	if args.size() > 1:
		output_path = String(args[1])

	var props: Array[Resource] = []
	for filename in PROP_FILES:
		props.append(load("res://experiments/level_builder_lite/generation/" + filename))
	LIBRARY._cache["props"] = props

	var groups: Array[Resource] = []
	for filename in GROUP_FILES:
		groups.append(load("res://experiments/level_builder_lite/generation/" + filename))
	LIBRARY._cache["activity_groups"] = groups
	LIBRARY._cache["room_archetypes"] = [load("res://experiments/level_builder_lite/generation/tavern_archetype.tres")]
	var temp_files: Array[String] = []
	for filename in PROP_FILES + GROUP_FILES:
		var source_path := "res://experiments/level_builder_lite/generation/" + String(filename)
		var destination_path := GENERATION_DIR + "/" + String(filename)
		if not _copy_text_resource(source_path, destination_path):
			printerr("CONFIG_COPY_FAIL ", destination_path)
			quit(1)
			return
		temp_files.append(destination_path)
	var archetype_path := GENERATION_DIR + "/room_00_lbg02_tavern.tres"
	if not _copy_text_resource("res://experiments/level_builder_lite/generation/tavern_archetype.tres", archetype_path):
		printerr("CONFIG_COPY_FAIL ", archetype_path)
		quit(1)
		return
	temp_files.append(archetype_path)
	LIBRARY.refresh()

	var brief: Resource = load("res://experiments/level_builder_lite/generation/tavern_brief.tres").duplicate()
	brief.rng_seed = seed_value
	var result: Dictionary = GENERATOR.generate(brief)
	if not result.get("ok", false):
		printerr("TAVERN_GENERATION_FAIL seed=%d findings=%s" % [seed_value, result.get("findings", [])])
		quit(1)
		return

	var root := BOOTSTRAP.build_skeleton("Indoor", false)
	root.name = "KayKitTavernSeed%d" % seed_value
	get_root().add_child(root)
	await process_frame
	if not GENERATOR.apply(result, root):
		printerr("TAVERN_APPLY_FAIL seed=%d" % seed_value)
		quit(1)
		return
	# The stock Room generator puts its single stoop on the north side. Reflect
	# the generated root across Z to move that entry south while retaining the
	# generator's west/east side assignment for the bar and kitchen zones.
	root.scale.z = -1.0
	root.position.z = 12.0
	_add_npc_markers(root)
	var player := CharacterBody3D.new()
	player.name = "TestWalkPlayer"
	player.set_script(WALKER)
	player.set_meta("placement_source", "manual player spawn for first-person review")
	# Place the preview walker just inside the reflected south opening; all
	# furniture stays generator-owned.
	player.position = Vector3(14.5, 0.0, 0.5)
	player.rotation.y = PI
	root.add_child(player)
	_own_recursive(root, root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		printerr("TAVERN_PACK_FAIL seed=%d error=%d" % [seed_value, pack_error])
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, output_path)
	if save_error != OK:
		printerr("TAVERN_SAVE_FAIL path=%s error=%d" % [output_path, save_error])
		quit(1)
		return
	for path in temp_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	LIBRARY.refresh()

	var placements: Array = result["props"].get("Room_0", [])
	print("TAVERN_GENERATION_PASS seed=%d room_modules=4x3 room_metres=16x12 props=%d path=%s findings=%s" % [
		seed_value, placements.size(), output_path, result["findings"]])
	for placement in placements:
		print("PLACEMENT %s tag=%s group=%s cell=%s yaw=%s zones=%s" % [
			placement["name"], placement["tag"], placement.get("group", ""),
			placement["cell"], placement["yaw"], placement.get("zones", [])])
	quit(0)


func _add_npc_markers(root: Node3D) -> void:
	var markers := Node3D.new()
	markers.name = "ManualNPCMarkers"
	markers.set_meta("placement_source", "manual location markers; no NPC implementation")
	root.get_node("Gameplay").add_child(markers)
	for i in 3:
		var marker := Marker3D.new()
		marker.name = "NPCPosition%d" % (i + 1)
		marker.position = [Vector3(5, 0.2, 3), Vector3(9, 0.2, 4), Vector3(7, 0.2, 8)][i]
		markers.add_child(marker)


func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		# Descendants inside PackedScene instances must retain their source-scene
		# owners; overriding them duplicates those nested nodes when packing.
		if child.scene_file_path.is_empty():
			_own_recursive(child, owner)


func _copy_text_resource(source: String, destination: String) -> bool:
	var source_file := FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		return false
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return false
	output.store_string(source_file.get_as_text())
	return output.get_error() == OK
