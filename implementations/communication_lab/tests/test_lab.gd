extends SceneTree

const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Graph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")
const GraphView = preload("res://implementations/communication_lab/game/ui/dialogue_graph_view.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	var context := Session.initial_context()
	check(context.current_node == "G00_GATE" and context.roster_has_player and not context.is_technician
		and not context.has_pass and context.access_status == "none" and context.player_name.is_empty()
		and context.trust == "neutral" and not context.message_promise and context.dialogue_history.is_empty(),
		"No Pass session starts with the authored neutral gate facts")
	check(Graph.validate().is_empty(), "the authored dialogue graph passes structural validation")

	var graph_view := GraphView.new()
	root.add_child(graph_view)
	await process_frame
	var rendered_nodes := 0
	for child in graph_view.graph_edit.get_children():
		if child is GraphNode: rendered_nodes += 1
	check(rendered_nodes == 18 and graph_view.graph_edit.get_connection_list().size() == 61,
		"live GraphEdit renders every authored RPG node and transition")
	check(graph_view.current_node_id == "G00_GATE" and graph_view.node_history == ["G00_GATE"],
		"live graph starts at the same runtime gate node")
	graph_view.queue_free()

	var room := (load("res://implementations/communication_lab/communication_lab.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	room.call("_toggle_dev", true)
	var graph_page: Control = room.dev_tabs.get_node("Граф диалога")
	check(room.dev_panel.visible and room.dev_tabs.current_tab == room.dev_tabs.get_tab_idx(graph_page),
		"F2 opens the No Pass graph inspector")
	check(room.topic_buttons.has("report_no_card") and room.topic_buttons.has("ask_rules")
		and not room.topic_buttons.has("ask_mood") and not room.topic_buttons.has("share_state"),
		"the player menu exposes the gate scenario instead of the previous social topics")
	room.queue_free()
	await process_frame
	print("COMMUNICATION_LAB_TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
