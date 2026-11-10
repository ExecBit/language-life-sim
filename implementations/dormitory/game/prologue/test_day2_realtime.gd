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
	assert(not scene.house.items.bread.visible)
	assert(scene._advance())
	assert(scene.state.day == 2 and scene.state.held("player") == "")
	assert(scene.house.items.bread.visible)
	scene.player.position = Vector3(-3,0.9,0.6)
	await physics_frame
	await physics_frame
	scene.camera.look_at(scene.house.position_of("lena"))
	scene.automated = false
	await create_timer(3.4).timeout
	assert(scene.step.id == "f_arrival","Walking past started a forced conversation")
	assert(scene.state.cooking.status == "available" and not scene.ui.dialog.visible)
	assert(not scene.player.is_movement_paused)
	await scene._aim_at("lena")
	scene._interact()
	assert(scene.step.id == "f_offer" and scene.state.cooking.status == "offered")
	scene._answer("no")
	var owners: Array[String] = ["kitchen_shelf"]
	var time := 0.0
	while scene.step.id != "g_ready":
		await physics_frame
		time += 1.0/Engine.physics_ticks_per_second
		var owner: String = scene.state.items.bread
		if owner != owners[-1]:
			owners.append(owner)
			if owner == "lena": assert(scene.house.actors.lena.position.distance_to(scene.house.anchors.kitchen_shelf.position) < 2.0)
			if owner == "breakfast_table": assert(scene.house.actors.lena.position.distance_to(scene.house.anchors.breakfast_table.position) < 2.2)
		assert(time < 18,"Refusal branch did not finish")
	assert(owners == ["kitchen_shelf","lena","breakfast_table"])
	assert(scene.state.flags.breakfast_result == "declined")
	assert(time > 9.0,"Lena skipped walking")
	assert(not scene.state.finished,"Level completed before the player chose to exit")
	assert(scene.state.items.room_key == "nightstand")
	scene.automated = true
	scene.player.is_movement_paused = true
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(-2.2,1.4,0.8)
	camera.look_at(Vector3(-4.5,1.0,-1.5))
	camera.current = true
	if not DisplayServer.get_name() == "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://day2_breakfast_preview.png")
	print("REV04_REALTIME_NO_AUTODIALOGUE_AND_REFUSAL_OK seconds=",time," owners=",owners)
	scene.queue_free()
	await process_frame
	quit()
