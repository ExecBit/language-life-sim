extends SceneTree
## Real source scene, Composer signal, NPC clarification, confirmation, F2 history.
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func send(room: Node, action: String, text: String) -> void:
	room._finish_reply_reveal()
	room._select_dialogue_action(action)
	room.composer.phrase.text = text
	room.composer.send()
func run() -> void:
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	for frame in 10: await process_frame
	room._open_dialog()
	send(room, "report_no_card", "ich keine Karte")
	send(room, "report_newcomer", "Ich bin neu")
	send(room, "introduce", "Ich bin Alex")
	send(room, "request_pass", "Ich möchte vorläufigen")
	room._finish_reply_reveal()
	check(room.context.current_node == "G40_REGISTERED" and room.last_record.answer == "Einen vorläufigen Pass?" and not room.context.has_pass, "actual scene displays a specific object clarification without access")
	check(room.topic_buttons.has("confirm_proposition") and room.topic_buttons.has("reject_proposition"), "Composer can answer the generated question")
	if DisplayServer.get_name() != "headless":
		for frame in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.local/semantic-clarification.png"))
	send(room, "confirm_proposition", "Ja")
	check(room.context.current_node == "G50_CONFIRM" and room.context.player_name == "Alex", "scene confirms exactly the inferred request")
	send(room, "confirm_proposition", "ja ich bin alex")
	check(room.context.current_node == "E_OFFICIAL" and room.context.has_pass, "official path completes through real Composer input")
	room._finish_reply_reveal()
	room._toggle_dev(true)
	room._show_current_graph()
	for frame in 10: await process_frame
	check(room.graph_view.current_node_id == "E_OFFICIAL" and room.graph_view.graph_edit.get_connection_list().size() == 61 and room.attempts.size() == 6, "F2 shows actual semantic recovery route and all events")
	var card: GraphNode = room.graph_view._node_cards["E_OFFICIAL"]
	check(card.get_global_rect().intersects(room.graph_view.graph_edit.get_global_rect()), "opening F2 brings the actual current card into the visible canvas")
	check(room.context.dialogue_history[4].resolved_frame.referent_id == "pass", "history keeps the confirmed contextual referent")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.local/semantic-scene-f2.png"))
	room.queue_free()
	await process_frame
	print("SEMANTIC_SCENE: %d failure(s)" % failures)
	quit(1 if failures else 0)
