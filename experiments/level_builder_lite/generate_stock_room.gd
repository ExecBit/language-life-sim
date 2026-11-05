extends SceneTree

const GENERATOR := preload("res://addons/level_builder/generator/generator.gd")
const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const BRIEF := preload("res://addons/level_builder/resources/generation_brief.gd")
const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const DEBUG := preload("res://addons/level_builder/generator/gen_debug.gd")
const WALKER := preload("res://addons/level_builder/runtime/test_player.gd")
const ASSET_PALETTE := preload("res://addons/level_builder/editor/asset_palette.gd")

const OUTPUT := "res://experiments/level_builder_lite/stock_bedroom.tscn"
const SEED := 4242


func _initialize() -> void:
	var brief: Resource = load("res://addons/level_builder/defaults/generation/brief_room_bedroom.tres").duplicate()
	brief.scope = BRIEF.Scope.ROOM
	brief.archetype_id = "bedroom"
	brief.kit_id = "greybox"
	brief.palette_id = "pristine"
	brief.size_class = 1
	brief.rng_seed = SEED

	var result: Dictionary = GENERATOR.generate(brief)
	if not result.get("ok", false):
		printerr("STOCK_GENERATION_FAIL: ", result.get("findings", []))
		quit(1)
		return
	var repeated: Dictionary = GENERATOR.generate(brief.duplicate())
	if _result_signature(result) != _result_signature(repeated):
		printerr("SEED_REPRODUCIBILITY_FAIL")
		quit(1)
		return

	var root: Node3D = BOOTSTRAP.build_skeleton("Indoor")
	root.name = "LBG01StockBedroom"
	get_root().add_child(root)
	await process_frame
	GENERATOR.apply(result, root)
	var player := CharacterBody3D.new()
	player.name = "TestPlayer"
	player.set_script(WALKER)
	player.transform.origin = Vector3(result["spawn"]) + Vector3(0, 0.5, 0)
	player.rotation.y = PI
	root.add_child(player)
	TYPES.own_deep(player, root)

	# Build the addon's temporary zone overlay to confirm it maps the generated room,
	# then remove it before saving because the dock describes this as preview only.
	var zone_count := DEBUG.build(root)
	var zone_names := PackedStringArray()
	var overlay: Node = root.get_node_or_null("LBZoneOverlay")
	if overlay and overlay.get_child_count() > 0:
		for zone in overlay.get_child(0).get_children():
			zone_names.append(zone.name.to_lower())
	DEBUG.clear(root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		printerr("PACK_FAIL: ", pack_error)
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, OUTPUT)
	if save_error != OK:
		printerr("SAVE_FAIL: ", save_error)
		quit(1)
		return

	var check := load(OUTPUT) as PackedScene
	var reopened := check.instantiate() if check else null
	if reopened == null:
		printerr("REOPEN_FAIL")
		quit(1)
		return
	root.queue_free()
	await process_frame
	get_root().add_child(reopened)
	await process_frame
	await physics_frame
	var walker := reopened.get_node("TestPlayer") as CharacterBody3D
	var walk_start := walker.global_position
	var forward := InputEventKey.new()
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	await create_timer(0.75).timeout
	forward.pressed = false
	Input.parse_input_event(forward)
	var walked := Vector2(walker.global_position.x - walk_start.x,
		walker.global_position.z - walk_start.z).length()
	if walked < 1.0:
		printerr("WALK_TEST_FAIL moved=%.2fm" % walked)
		reopened.queue_free()
		quit(1)
		return
	var prop_count := int(result["stats"]["props"])
	var node_count := reopened.find_children("*", "Node3D", true, false).size()
	var kaykit_entries := ASSET_PALETTE.scan(PackedStringArray([
		"res://assets/kaykit/furniture", "res://assets/kaykit/items"]))
	var loadable_kaykit := 0
	for entry in kaykit_entries:
		if ResourceLoader.load(String(entry["path"])) is PackedScene:
			loadable_kaykit += 1
	print("STOCK_GENERATION_PASS preset=Bedroom seed=%d props=%d units=%d zone_rooms=%d overlay_zones=%s scene_nodes3d=%d path=%s" % [
		SEED, prop_count, int(result["stats"]["units"]), zone_count, ",".join(zone_names), node_count, OUTPUT])
	print("SEED_REPRODUCIBILITY_PASS seed=%d" % SEED)
	print("WALK_TEST_PASS moved=%.2fm" % walked)
	print("KAYKIT_PALETTE_SCAN entries=%d loadable_packed_scenes=%d" % [kaykit_entries.size(), loadable_kaykit])
	print("FINDINGS: ", result["findings"])
	reopened.free()
	await process_frame
	quit(0)


func _result_signature(result: Dictionary) -> String:
	var signature := var_to_str(result["plan"])
	var unit_ids: Array = result["props"].keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		for placement in result["props"][unit_id]:
			var scene: PackedScene = placement["scene"]
			signature += "|%s:%s:%s:%s:%s" % [
				String(unit_id), String(placement["name"]), str(placement["cell"]),
				str(placement["yaw"]), scene.resource_path]
	return signature
