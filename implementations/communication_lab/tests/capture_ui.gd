extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1280, 720)
	room.player.position = Vector3(0, 0, 0.5)
	room._open_dialog()
	room.composer.phrase.text = "Hallo"
	room.composer.send()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/commlab-normal.png")
	room._toggle_dev(true)
	room.composer.phrase.text = "Ich brauche den"
	room.composer.prefix.text = "Schlüssel"
	room.composer.send()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/commlab-debug.png")
	var tabs: TabContainer = room.parse_view.get_parent()
	for index in [1, 2, 3]:
		tabs.current_tab = index
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/commlab-tab-%d.png" % index)
	assert(room.dialog.get_global_rect().end.y <= root.get_visible_rect().size.y)
	assert(room.player.is_movement_paused)
	assert(room.attempts.size() == 2)
	room.history_list.select(0)
	room._recall_attempt()
	assert(room.composer.phrase.text == "Hallo")
	assert(room.context.key_owner == "player")
	room._reset()
	assert(room.context.key_owner == "anna")
	assert(room.attempts.size() == 2)
	room._close_dialog()
	assert(not room.player.is_movement_paused)
	assert(not room.dev_panel.visible)
	print("UI_WORKFLOW: PASS conversation, debug, recall, reset, movement")
	quit()
