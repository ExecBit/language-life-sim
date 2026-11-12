extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1280, 720)
	room.player.position = Vector3(0, 0, 0.5)
	await process_frame
	room._open_dialog()
	await create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/p67-opening.png")
	assert(room.topic_buttons.size() == 3)
	assert(not room.objective_panel.visible)
	assert(room.transcript.get_parsed_text().contains("Und du?"))

	room._select_dialogue_topic("player_mood")
	room.composer.phrase.text = "Ich bin glücklich"
	room.composer.send()
	for i in 30: await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(room.last_record.parse.intent == "REPORT_STATE")
	assert(room.context.player_mood == "happy")
	root.get_texture().get_image().save_png("res://.local/p67-state.png")

	room._select_dialogue_topic("help")
	room.composer.phrase.text = "ich helfen"
	room.composer.send()
	for i in 30: await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(room.context.pending_clarification.size() > 0)
	assert(room.notice_label.visible and room.notice_label.text.contains("кому"))
	root.get_texture().get_image().save_png("res://.local/p67-notice.png")

	room.composer.phrase.text = "Ja"
	room.composer.send()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	assert(room.context.offered_help)
	assert(room.last_record.parse.intent == "CONFIRM_CLARIFICATION")
	root.get_texture().get_image().save_png("res://.local/p67-help.png")

	room._toggle_vocabulary()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var has_help_construction := false
	for row in room.vocabulary_rows:
		if not row.header and row.search.contains("kann ich dir helfen"): has_help_construction = true
	assert(has_help_construction)
	root.get_texture().get_image().save_png("res://.local/p67-memo.png")

	room._reset()
	assert(room.context.awaiting_name and room.context.player_name.is_empty())
	assert(room.conversation_lines.is_empty())
	room._close_dialog()
	assert(not room.player.is_movement_paused)
	print("P67_UI_WORKFLOW: PASS menu, state response, help notice, confirmation, F1 memo, reset")
	quit()
