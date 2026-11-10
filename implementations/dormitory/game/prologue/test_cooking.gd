extends SceneTree

func _init() -> void:
	call_deferred("run")

func setup(scene) -> void:
	scene.automated = true
	scene._start_new()
	scene.state.index = 7
	scene.state.flags.door_open = true
	scene.state.items.bag = "bag_stand"
	scene.state.items.room_key = "player"
	scene._enter_step(true)
	assert(scene._advance())
	assert(scene.step.id == "f_arrival")
	assert(scene.state.cooking.status == "available")
	assert(scene.state.cooking.event_id == "2:breakfast:bread")
	assert(not scene.ui.dialog.visible)

func offer(scene) -> void:
	await scene._aim_at("lena")
	assert(scene._target() == "lena")
	scene._interact()
	assert(scene.step.id == "f_offer" and scene.state.cooking.status == "offered")
	var id: String = scene.state.cooking.event_id
	scene._interact()
	assert(scene.state.cooking.event_id == id and scene.state.cooking.history.count("offered") == 1)

func self_finish(scene) -> void:
	scene._layout(true)
	scene._tick_breakfast(1.3)
	assert(scene.state.items.bread == "lena")
	scene._layout(true)
	scene._tick_breakfast(1.3)
	assert(scene.state.items.bread == "breakfast_table")
	assert(scene.state.cooking.activity == "finished")

func run() -> void:
	var scene = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	setup(scene)
	# Cooking progresses without seeing Lena or entering a conversation.
	scene.player.position = Vector3(3.3,0.9,-4.2)
	scene._tick_cooking(20.0)
	assert(scene.state.cooking.elapsed == 20.0 and scene.state.cooking.status == "available")
	scene._set_pause(true)
	scene.automated = false
	scene._process(30.0)
	scene.automated = true
	assert(scene.state.cooking.elapsed == 20.0)
	scene._set_pause(false)
	assert(scene._save())
	scene._load_save()
	assert(scene.state.cooking.elapsed == 20.0 and scene.state.cooking.status == "available")
	scene._tick_cooking(100.0)
	assert(scene.state.cooking.status == "skipped")
	self_finish(scene)
	assert(scene.state.flags.breakfast_result == "skipped")
	assert(not scene.state.flags.has("nimm_usage") and not scene.state.flags.has("gib_usage"))
	print("REV04_UNATTENDED_PERIOD_AND_SAVE_PAUSE_OK")
	# Leaving is allowed immediately; autonomous completion continues in the same scene.
	setup(scene)
	scene.player.position = scene.house.zones.exit+Vector3(0,0.9,0)
	scene.automated = false
	scene._process(0.02)
	scene.automated = true
	assert(scene.state.finished and scene.state.cooking.status == "skipped")
	assert(scene.ui.complete_panel.visible)
	assert(scene._save())
	scene._load_save()
	assert(scene.state.finished and scene.ui.complete_panel.visible)
	self_finish(scene)
	assert(scene.step.id == "complete" and scene.state.finished)
	print("REV04_EXIT_WITHOUT_HELP_OK")
	# An unanswered offer expires safely; it cannot be offered again after loading.
	setup(scene)
	await offer(scene)
	scene._tick_cooking(12.0)
	assert(scene._save())
	scene._load_save()
	assert(scene.state.cooking.status == "offered" and scene.state.cooking.elapsed == 12.0)
	scene._tick_cooking(120.0)
	assert(scene.state.cooking.status == "skipped")
	self_finish(scene)
	assert(scene._save())
	scene._load_save()
	assert(not scene.state.offer_cooking())
	print("REV04_UNANSWERED_OFFER_AND_NO_REOFFER_OK")
	# Cancel after accepting but before taking: Lena performs the task herself.
	setup(scene)
	await offer(scene)
	scene._answer("yes")
	scene._enter_step(true)
	scene._answer("cancel_cooking")
	assert(scene.state.cooking.status == "skipped")
	self_finish(scene)
	assert(not scene.state.flags.has("nimm_usage"))
	print("REV04_CANCEL_BEFORE_TAKE_OK")
	# Cancel with the loaf held: no remote retrieval, no copy, and exit stays available.
	setup(scene)
	await offer(scene)
	scene._answer("yes")
	scene._enter_step(true)
	await scene._aim_at("bread")
	scene._interact()
	assert(scene.state.items.bread == "player" and scene.step.id == "f_give")
	var instance: int = scene.house.items.bread.get_instance_id()
	scene._answer("cancel_cooking")
	assert(scene.state.items.bread == "player" and scene.state.cooking.status == "skipped")
	assert(scene.state.cooking.activity == "finished")
	assert(scene.house.items.bread.get_instance_id() == instance and scene.house.items.bread.get_parent() == scene.held)
	scene._finish_level()
	assert(scene.state.finished and scene.state.items.bread == "player")
	print("REV04_CANCEL_WITH_HELD_LOAF_OK")
	# Moving away cancels an active offer without freezing the player.
	setup(scene)
	await offer(scene)
	scene.player.position = Vector3(3.3,0.9,-4.2)
	scene._tick_cooking(8.1)
	assert(scene.state.cooking.status == "skipped" and not scene.player.is_movement_paused)
	assert(not scene.ui.dialog.visible)
	print("REV04_WALK_AWAY_OK")
	# The request cannot name an unavailable loaf.
	setup(scene)
	assert(scene.state.transfer("bread","kitchen_shelf","player"))
	scene.house.sync_items(scene.state,scene.held)
	await scene._aim_at("lena")
	scene._interact()
	assert(scene.step.id == "f_arrival" and scene.state.cooking.status == "available")
	assert(not scene.state.offer_cooking())
	scene._tick_cooking(120.0)
	assert(scene.state.items.bread == "player" and scene.state.cooking.activity == "finished")
	print("REV04_UNAVAILABLE_ITEM_OK")
	print("REV04_COOKING_ALL_OK")
	scene.queue_free()
	await process_frame
	quit()
