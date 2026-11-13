extends SceneTree
## Real model/Composer/F2 transport smoke. Deliberately NOT an NLU accuracy test.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	root.content_scale_size = Vector2i(1920,1080)
	root.size = Vector2i(1920,1080)
	room.language_client.config.enabled = true
	for frame in 10: await process_frame
	room._open_dialog()
	await create_timer(0.7).timeout
	room._select_dialogue_action("report_no_card")
	room.composer.phrase.text = "Ich habe keine Karte."
	room.composer.send()
	while room.language_busy: await process_frame
	room._finish_reply_reveal()
	var parsed: Dictionary = room.last_record.parse
	var transport_ok := parsed.has("model_output") and str(parsed.get("backend", "")).begins_with("lfm3")
	print("SOURCE_MODEL_RESPONSE: ", JSON.stringify(parsed))
	room._toggle_dev(true)
	room._show_current_graph()
	for frame in 10: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.local/lfm3/source-model-graph.png"))
	print("LOCAL_LANGUAGE_SOURCE_TRANSPORT: %s (not a language quality PASS)" % ("PASS" if transport_ok else "FAIL"))
	room.queue_free()
	await process_frame
	quit(0 if transport_ok else 1)
