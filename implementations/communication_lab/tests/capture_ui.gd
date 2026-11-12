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

	assert(room.topic_menu.visible and not room.composer.visible)
	var attempt_count: int = room.attempts.size()
	room.composer.phrase.text = "unselected draft"
	room.composer.send()
	assert(room.attempts.size() == attempt_count)
	room.composer.clear()
	room.topic_buttons["introduce"].emit_signal("pressed")
	assert(room.reply_editor.visible and room.composer.visible and not room.topic_menu.visible)
	assert(room.selected_reply_label.text == "Представиться")
	room.composer.phrase.text = "Ich bin Neral"
	room._back_to_choices()
	assert(room.topic_menu.visible and not room.composer.visible and room.composer.phrase.text == "Ich bin Neral")
	room.topic_buttons["introduce"].emit_signal("pressed")
	await process_frame
	await RenderingServer.frame_post_draw
	assert(room.composer.get_global_rect().end.y <= root.get_visible_rect().end.y)
	root.get_texture().get_image().save_png("res://.local/p67-writing.png")
	room._toggle_history_expanded()
	assert(not room.composer.visible and not room.topic_menu.visible)
	room._toggle_history_expanded()
	assert(room.composer.visible and room.selected_reply_label.text == "Представиться" and room.composer.phrase.text == "Ich bin Neral")
	room.composer.send()
	await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(not room.topic_buttons.has("introduce"))
	assert(room.composer.get_global_rect().end.y <= root.get_visible_rect().end.y)
	root.get_texture().get_image().save_png("res://.local/p67-after-name.png")
	room._select_dialogue_action("share_state")
	room.composer.phrase.text = "Ich bin glücklich"
	room.composer.send()
	for i in 30: await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(room.last_record.parse.intent == "REPORT_STATE")
	assert(room.context.player_mood == "happy")
	root.get_texture().get_image().save_png("res://.local/p67-state.png")

	room._select_dialogue_action("request_help")
	room.composer.phrase.text = "ich helfe dir"
	room.composer.send()
	await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(not room.context.offered_help and not room.context.help_requested)
	assert(room.last_record.parse.reason == "SELECTED_ACTION_MISMATCH")
	assert(room.notice_label.text.contains("выбрали") and room.topic_buttons.has("confirm"))
	assert(room.notice_card.visible and room.notice_card.position == Vector2(18, 18))
	assert(room.notice_card.get_parent() != room.dialog and not room.dialog.is_ancestor_of(room.notice_card))
	assert(room.topic_menu.visible and not room.composer.visible)
	assert(room.topic_buttons["confirm"].text == "Подтвердить, что хотите помочь Астере")
	assert(room.topic_buttons["reject"].text == "Отрицать, что хотите помочь Астере")
	root.get_texture().get_image().save_png("res://.local/p67-choice-conflict.png")
	room.topic_buttons["reject"].emit_signal("pressed")
	room.composer.phrase.text = "Nein"
	room.composer.send()
	assert(not room.context.offered_help and not room.context.help_requested)
	room._select_dialogue_action("offer_help")
	room.composer.phrase.text = "ich helfen"
	room.composer.send()
	for i in 30: await process_frame
	room._finish_reply_reveal()
	await RenderingServer.frame_post_draw
	assert(room.context.pending_clarification.size() > 0)
	assert(room.topic_buttons.keys() == ["confirm", "reject", "back"])
	assert(room.notice_label.visible and room.notice_label.text.contains("кому"))
	assert(room.composer.get_global_rect().end.y <= root.get_visible_rect().end.y)
	root.get_texture().get_image().save_png("res://.local/p67-notice.png")

	room._select_dialogue_action("confirm")
	room.composer.phrase.text = "Ja"
	room.composer.send()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	assert(room.context.offered_help)
	assert(not room.topic_buttons.has("confirm") and not room.topic_buttons.has("offer_help"))
	assert(room.last_record.parse.intent == "CONFIRM_CLARIFICATION")
	root.get_texture().get_image().save_png("res://.local/p67-help.png")

	room.notice_timer.timeout.emit()
	assert(not room.notice_card.visible)
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
	assert(room.conversation_lines.is_empty() and room.topic_menu.visible and not room.composer.visible)
	room._close_dialog()
	assert(not room.player.is_movement_paused)
	print("P67_UI_WORKFLOW: PASS menu, state response, help notice, confirmation, F1 memo, reset")
	quit()
