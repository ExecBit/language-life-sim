extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	scene.state.index = 7
	scene.state.flags.door_open = true
	scene.state.items.bag = "bag_stand"
	scene.state.items.room_key = "player"
	scene._enter_step(true)
	assert(scene._advance())
	scene._finish_level()
	scene._take_checkpoint()
	# An old v4 prologue has no shopping section at all.
	var legacy: Dictionary = scene.checkpoint.duplicate(true)
	legacy.erase("shop")
	var save := FileAccess.open(scene.SAVE,FileAccess.WRITE)
	save.store_string(JSON.stringify(legacy))
	save.close()
	assert(scene._save_valid())
	scene._load_save()
	assert(not scene.shopping.active() and scene.state.day == 2)
	scene._command("travel_shop")
	assert(scene.shopping.active() and scene.shopping.state.location == "shop")
	assert(not scene.player.is_movement_paused and not scene.house.visible)
	assert(scene.state.cooking.status == "skipped")
	scene._layout(true)
	scene._tick_breakfast(1.3)
	scene._layout(true)
	scene._tick_breakfast(1.3)
	assert(scene.state.cooking.activity == "finished")
	assert(scene.ui.chapter.text.contains("магазин") and scene.shopping.world.visible)
	assert(scene._save())
	scene._load_save()
	assert(scene.shopping.state.location == "shop" and scene.state.cooking.activity == "finished")
	print("SHOP_V4_PROLOGUE_BRIDGE_AND_BACKGROUND_COOKING_OK")
	scene.queue_free()
	await process_frame
	quit()
