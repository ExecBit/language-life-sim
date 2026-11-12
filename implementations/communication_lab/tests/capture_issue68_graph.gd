extends SceneTree

const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Graph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("capture")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func send(context: Dictionary, action_id: String, sentence: String) -> void:
	var selected := Session.select_action(action_id, context)
	check(bool(selected.get("accepted", false)), "route action available: " + action_id)
	var record := Session.submit(sentence, context)
	check(not str(record.get("transition_id", "")).is_empty(), "route transition applied: " + action_id)

func capture() -> void:
	var room := (load("res://implementations/communication_lab/communication_lab.tscn") as PackedScene).instantiate()
	root.add_child(room)
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1280, 720)
	var context := Session.initial_context()
	Session.opening_line(context)
	send(context, "report_no_card", "Ich habe keine Karte.")
	send(context, "report_newcomer", "Ich bin neu.")
	send(context, "introduce", "Ich heiße Neral.")
	send(context, "request_pass", "Ich möchte einen Pass.")
	send(context, "confirm_proposition", "Ja")
	room.context = context
	room.call("_toggle_dev", true)
	room.call("_show_current_graph")
	await process_frame
	await process_frame
	for frame in 10: await process_frame
	room.graph_view.center_on_current()
	await RenderingServer.frame_post_draw
	var edit: GraphEdit = room.graph_view.graph_edit
	var node_count := 0
	for child in edit.get_children():
		if child is GraphNode: node_count += 1
	var graph_page: Control = room.dev_tabs.get_node("Граф диалога")
	check(room.dev_panel.visible and room.dev_tabs.current_tab == room.dev_tabs.get_tab_idx_from_control(graph_page), "F2 opens the live dialogue graph tab")
	check(node_count == 18 and edit.get_connection_list().size() == 61, "viewport contains the 18 authored nodes and all 61 runtime edges")
	var cards: Array[GraphNode] = []
	for child in edit.get_children():
		if child is GraphNode: cards.append(child)
	var overlaps := 0
	for left in cards.size():
		for right in range(left + 1, cards.size()):
			if Rect2(cards[left].position_offset, cards[left].size).intersects(Rect2(cards[right].position_offset, cards[right].size)):
				overlaps += 1
	check(overlaps == 0, "all 18 actual GraphNode rectangles are separated after layout")
	check(room.graph_view.current_node_id == "E_OFFICIAL" and room.graph_history_view.text.contains("Официальный доступ"), "viewport shows the actual official route and event history")
	check(edit.size.x >= 700 and edit.size.y >= 300, "expanded graph viewport has room for inspection")
	var output_dir := ProjectSettings.globalize_path("res://.local")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("issue68-f2-graph.png")
	var image := root.get_texture().get_image()
	var save_error := image.save_png(output_path)
	check(save_error == OK, "viewport screenshot saved to " + output_path)
	print("ISSUE68_GRAPH_CAPTURE: %d failure(s) · %s" % [failures, output_path])
	quit(1 if failures > 0 else 0)
