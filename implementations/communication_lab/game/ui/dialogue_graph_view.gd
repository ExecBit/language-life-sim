extends VBoxContainer
## GraphEdit rendering of the exact graph data used by DialogueGraph and LabSession.
signal current_requested
const DialogueGraph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")

class FlowCanvas extends GraphEdit:
	func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
		var elbow := (from_position.x + to_position.x) * 0.5
		var points := PackedVector2Array([from_position])
		if to_position.x > from_position.x + 40:
			points.append(Vector2(elbow, from_position.y))
			points.append(Vector2(elbow, to_position.y))
		else:
			var lane := minf(from_position.y, to_position.y) - 48.0
			points.append(from_position + Vector2(28, 0))
			points.append(Vector2(from_position.x + 28, lane))
			points.append(Vector2(to_position.x - 28, lane))
			points.append(to_position - Vector2(28, 0))
		points.append(to_position)
		points.append(to_position + Vector2(-7, -4))
		points.append(to_position)
		points.append(to_position + Vector2(-7, 4))
		return points

var current_node_id := "G00_GATE"
var node_history: Array = ["G00_GATE"]
var dialogue_history: Array[Dictionary] = []
var selected_attempt := -1
var graph_edit: GraphEdit
var status_label: Label
var node_diagnostic: RichTextLabel
var error_label: Label
var current_button: Button
var center_button: Button
var zoom_label: Label
var _layout_ready := false
var _focused_node_id := ""
var _live_snapshot: Dictionary = {}
var _node_cards: Dictionary = {}
var _port_by_edge: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(560, 270)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var toolbar := HBoxContainer.new()
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("a9d5d0"))
	toolbar.add_child(status_label)
	var zoom_out_button := Button.new()
	zoom_out_button.text = "−"
	zoom_out_button.tooltip_text = "Уменьшить граф"
	zoom_out_button.custom_minimum_size.x = 34
	zoom_out_button.pressed.connect(func(): _change_zoom(-0.08))
	toolbar.add_child(zoom_out_button)
	zoom_label = Label.new()
	zoom_label.custom_minimum_size.x = 48
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zoom_label.add_theme_color_override("font_color", Color("c8d7dd"))
	toolbar.add_child(zoom_label)
	var zoom_in_button := Button.new()
	zoom_in_button.text = "+"
	zoom_in_button.tooltip_text = "Увеличить граф"
	zoom_in_button.custom_minimum_size.x = 34
	zoom_in_button.pressed.connect(func(): _change_zoom(0.08))
	toolbar.add_child(zoom_in_button)
	center_button = Button.new()
	center_button.text = "К текущему"
	center_button.tooltip_text = "Показать текущий узел"
	center_button.pressed.connect(center_on_current)
	toolbar.add_child(center_button)
	var overview_button := Button.new()
	overview_button.text = "Весь сюжет"
	overview_button.pressed.connect(_fit_graph)
	toolbar.add_child(overview_button)
	current_button = Button.new()
	current_button.text = "Текущее состояние"
	current_button.visible = false
	current_button.pressed.connect(_return_to_live)
	toolbar.add_child(current_button)
	add_child(toolbar)
	error_label = Label.new()
	error_label.add_theme_color_override("font_color", Color("ffb49d"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(error_label)
	graph_edit = FlowCanvas.new()
	graph_edit.name = "RuntimeDialogueGraph"
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_edit.show_zoom_buttons = false
	graph_edit.minimap_enabled = false
	graph_edit.show_minimap_button = false
	graph_edit.show_arrange_button = false
	graph_edit.show_grid_buttons = false
	graph_edit.show_menu = false
	graph_edit.show_zoom_label = false
	graph_edit.show_zoom_buttons = false
	graph_edit.show_grid = false
	graph_edit.grid_pattern = GraphEdit.GRID_PATTERN_DOTS
	graph_edit.add_theme_color_override("grid_minor", Color("263540", 0.62))
	graph_edit.add_theme_color_override("grid_major", Color("334653", 0.62))
	graph_edit.add_theme_color_override("connection_lines", Color("69818c", 0.34))
	graph_edit.add_theme_color_override("activity", Color("f0c982"))
	graph_edit.add_theme_color_override("connection_rim_color", Color(0, 0, 0, 0))
	graph_edit.zoom = 0.85
	graph_edit.zoom_min = 0.34
	graph_edit.zoom_max = 1.6
	graph_edit.connection_lines_curvature = 0.42
	graph_edit.connection_lines_thickness = 1.4
	graph_edit.connection_lines_antialiased = true
	graph_edit.node_selected.connect(_on_node_selected)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	body.add_child(graph_edit)
	node_diagnostic = RichTextLabel.new()
	node_diagnostic.custom_minimum_size.x = 320
	node_diagnostic.size_flags_horizontal = Control.SIZE_FILL
	node_diagnostic.add_theme_font_size_override("normal_font_size", 17)
	node_diagnostic.fit_content = false
	node_diagnostic.bbcode_enabled = false
	body.add_child(node_diagnostic)
	var legend := Label.new()
	legend.text = "Слева направо: развилки → решения → исходы. Яркие линии — сюжет; тонкие — повторы и возвраты. Выберите узел для подробностей."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 11)
	add_child(legend)
	_build_graph()
	set_snapshot({"current_node":"G00_GATE", "node_history":["G00_GATE"], "dialogue_history":[]}, -1)
	_update_zoom_label()
	call_deferred("_layout_cards")

func _build_graph() -> void:
	var errors := DialogueGraph.validate()
	if not errors.is_empty():
		error_label.text = "Ошибка графа диалога: " + "; ".join(errors)
		return
	error_label.text = ""
	var graph := DialogueGraph.data()
	var nodes: Dictionary = graph.get("nodes", {})
	var edges: Array = graph.get("transitions", [])
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for edge in edges:
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if not outgoing.has(from_id): outgoing[from_id] = []
		if not incoming.has(to_id): incoming[to_id] = []
		outgoing[from_id].append(edge)
		incoming[to_id].append(edge)
	_node_cards.clear()
	_port_by_edge.clear()
	for node_id_variant in nodes:
		var node_id := str(node_id_variant)
		var node_data: Dictionary = nodes[node_id]
		var card := GraphNode.new()
		card.name = node_id
		card.title = str(node_data.get("label", node_id))
		card.add_theme_font_size_override("title_font_size", 19)
		card.resizable = false
		card.draggable = false
		card.set("position_offset", _position_for(node_data, node_id))
		card.custom_minimum_size = Vector2(290, 0)
		var id_label := Label.new()
		id_label.text = _node_badge(node_id, node_data, false, 0)
		id_label.add_theme_font_size_override("font_size", 11)
		id_label.add_theme_color_override("font_color", Color("9fd0d1"))
		card.add_child(id_label)
		card.set_slot(0, false, 0, Color.WHITE, false, 0, Color.WHITE)
		var out_edges: Array = outgoing.get(node_id, [])
		var in_edges: Array = incoming.get(node_id, [])
		card.set_slot(0, false, 0, Color.WHITE, false, 0, Color.WHITE)
		card.tooltip_text = str(node_data.get("description", "")) + "\n" + str(node_data.get("npc_line", ""))
		var in_ports := {}
		var in_slots := {}
		for index in in_edges.size():
			var row := Control.new()
			row.custom_minimum_size.y = 2
			card.add_child(row)
			var slot := card.get_child_count() - 1
			card.set_slot(slot, true, 0, Color("7392a8", 0.01), false, 0, Color.WHITE)
			in_ports[str(in_edges[index].get("id", ""))] = index
			in_slots[str(in_edges[index].get("id", ""))] = slot
		var out_ports := {}
		var out_slots := {}
		for index in out_edges.size():
			var edge: Dictionary = out_edges[index]
			var action: Dictionary = graph.get("actions", {}).get(str(edge.get("action", "")), {})
			var row: Control
			if bool(edge.get("overview", false)):
				var label := Label.new()
				label.text = str(action.get("short_label", edge.get("action", ""))) + "  →"
				label.add_theme_font_size_override("font_size", 16)
				label.add_theme_color_override("font_color", Color("aecde2"))
				row = label
			else:
				row = Control.new()
				row.custom_minimum_size.y = 2
			row.tooltip_text = "%s · %s" % [str(action.get("label", "")), str(edge.get("guard_label", ""))]
			card.add_child(row)
			card.set_slot(card.get_child_count() - 1, false, 0, Color.WHITE, true, 0, Color("7392a8", 0.05))
			out_ports[str(edge.get("id", ""))] = index
			out_slots[str(edge.get("id", ""))] = card.get_child_count() - 1
		_apply_card_style(card, false, 0)
		graph_edit.add_child(card)
		_node_cards[node_id] = card
		_port_by_edge[node_id] = {"out":out_ports, "in":in_ports, "out_slots":out_slots, "in_slots":in_slots}
func _connect_graph() -> void:
	for edge in DialogueGraph.data().get("transitions", []):
		var edge_id := str(edge.get("id", ""))
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		var ports_from: Dictionary = _port_by_edge.get(from_id, {}).get("out", {})
		var ports_to: Dictionary = _port_by_edge.get(to_id, {}).get("in", {})
		var error := graph_edit.connect_node(from_id, int(ports_from.get(edge_id, 0)), to_id, int(ports_to.get(edge_id, 0)))
		if error != OK:
			error_label.text = "Не удалось показать переход %s (%s → %s)." % [edge_id, from_id, to_id]
			return

func set_snapshot(context: Dictionary, attempt_index := -1) -> void:
	if not is_instance_valid(graph_edit): return
	if attempt_index < 0:
		_live_snapshot = context.duplicate(true)
	current_node_id = str(context.get("current_node", DialogueGraph.data().get("initial_node", "G00_GATE")))
	node_history = context.get("node_history", ["G00_GATE"]).duplicate()
	if node_history.is_empty(): node_history = [current_node_id]
	dialogue_history.clear()
	for event in context.get("dialogue_history", []):
		if event is Dictionary: dialogue_history.append(event.duplicate(true))
	selected_attempt = attempt_index
	current_button.visible = selected_attempt >= 0
	var current_node: Dictionary = DialogueGraph.data().get("nodes", {}).get(current_node_id, {})
	status_label.text = ("ПОПЫТКА %02d" % (attempt_index + 1) if attempt_index >= 0 else "ТЕКУЩАЯ СЕССИЯ") + " · %s · %d событий" % [str(current_node.get("label", current_node_id)), dialogue_history.size()]
	_refresh_highlights()
	if _focused_node_id.is_empty() and _node_cards.has(current_node_id):
		_on_node_selected(_node_cards[current_node_id])

func _refresh_highlights() -> void:
	for node_id in _node_cards:
		var card: GraphNode = _node_cards[node_id]
		var current := str(node_id) == current_node_id
		var visits := node_history.count(node_id)
		var node_data: Dictionary = DialogueGraph.data().get("nodes", {}).get(node_id, {})
		var badge: Label = card.get_child(0) as Label
		badge.text = _node_badge(str(node_id), node_data, current, visits)
		_apply_card_style(card, current, visits)
	if not _layout_ready: return
	var visited_edges := {}
	var last_edge := ""
	for event in dialogue_history:
		var edge_id := str(event.get("transition_id", ""))
		if not edge_id.is_empty():
			visited_edges[edge_id] = true
			last_edge = edge_id
	var graph_edges: Array = DialogueGraph.data().get("transitions", [])
	for edge in graph_edges:
		var edge_id := str(edge.get("id", ""))
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		var from_ports: Dictionary = _port_by_edge.get(from_id, {}).get("out", {})
		var to_ports: Dictionary = _port_by_edge.get(to_id, {}).get("in", {})
		var output_port := int(from_ports.get(edge_id, 0))
		var input_port := int(to_ports.get(edge_id, 0))
		var focused := from_id == _focused_node_id
		var alpha := 0.7 if bool(edge.get("overview", false)) else 0.012
		if focused: alpha = 0.95
		var source_card: GraphNode = _node_cards[from_id]
		source_card.set_slot_color_right(int(_port_by_edge[from_id].out_slots[edge_id]), Color("88b6cf", alpha))
		var target_card: GraphNode = _node_cards[to_id]
		target_card.set_slot_color_left(int(_port_by_edge[to_id].in_slots[edge_id]), Color("88b6cf", alpha))
		var activity := 1.0 if edge_id == last_edge else (0.32 if visited_edges.has(edge_id) else 0.0)
		graph_edit.set_connection_activity(from_id, output_port, to_id, input_port, activity)

func _apply_card_style(card: GraphNode, current: bool, visits: int) -> void:
	var panel := StyleBoxFlat.new()
	var terminal := bool(DialogueGraph.data().get("nodes", {}).get(card.name, {}).get("terminal", false))
	panel.bg_color = Color("244548") if current else (Color("263c45") if visits > 0 else (Color("2d2a37") if terminal else Color("1a2832")))
	panel.border_color = Color("d4efc2") if current else (Color("78b9a2") if visits > 0 else (Color("756789") if terminal else Color("425965")))
	panel.set_border_width_all(3 if current else (2 if visits > 0 else 1))
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 11
	panel.content_margin_right = 11
	panel.content_margin_top = 8
	panel.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", panel)
	card.add_theme_stylebox_override("panel_focus", panel)
	for title_style in ["titlebar", "titlebar_selected"]:
		var title := StyleBoxFlat.new()
		title.bg_color = Color("356a68") if current else (Color("354d58") if visits > 0 else (Color("443c51") if terminal else Color("293b47")))
		title.set_corner_radius_all(7)
		title.content_margin_left = 10
		title.content_margin_top = 5
		title.content_margin_bottom = 5
		card.add_theme_stylebox_override(title_style, title)
	var selected: StyleBoxFlat = panel.duplicate()
	selected.border_color = Color("f0c982")
	card.add_theme_stylebox_override("panel_selected", selected)

func center_on_current() -> void:
	if not is_instance_valid(graph_edit) or not _node_cards.has(current_node_id): return
	var card: GraphNode = _node_cards[current_node_id]
	graph_edit.scroll_offset = (card.position_offset + card.size * 0.5) * graph_edit.zoom - graph_edit.size * Vector2(0.25, 0.5)
	_on_node_selected(card)

func _change_zoom(delta: float) -> void:
	if not is_instance_valid(graph_edit): return
	var logical_center := (graph_edit.scroll_offset + graph_edit.size * 0.5) / graph_edit.zoom
	graph_edit.zoom = clampf(graph_edit.zoom + delta, graph_edit.zoom_min, graph_edit.zoom_max)
	graph_edit.scroll_offset = logical_center * graph_edit.zoom - graph_edit.size * 0.5
	_update_zoom_label()

func _fit_graph() -> void:
	var bounds := Rect2()
	for card in _node_cards.values():
		var rect := Rect2(card.position_offset, card.size)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	graph_edit.zoom = clampf(minf((graph_edit.size.x - 60) / bounds.size.x, (graph_edit.size.y - 60) / bounds.size.y), graph_edit.zoom_min, 1.0)
	graph_edit.scroll_offset = bounds.get_center() * graph_edit.zoom - graph_edit.size * 0.5
	_update_zoom_label()

func _update_zoom_label() -> void:
	if is_instance_valid(zoom_label) and is_instance_valid(graph_edit):
		zoom_label.text = "%d%%" % roundi(graph_edit.zoom * 100.0)

func _node_badge(node_id: String, node_data: Dictionary, current: bool, visits: int) -> String:
	var badge := " · ИСХОД" if bool(node_data.get("terminal", false)) else ""
	if current:
		badge += " · СЕЙЧАС"
	elif visits > 0:
		badge += " · ×%d" % visits
	return badge.trim_prefix(" · ") if not badge.is_empty() else "РАЗВИЛКА"

func _incoming_tooltip(in_edges: Array, actions: Dictionary) -> String:
	var lines: PackedStringArray = ["Входящие переходы:"]
	for edge in in_edges:
		var action: Dictionary = actions.get(str(edge.get("action", "")), {})
		lines.append("%s · %s · %s" % [str(edge.get("from", "")), str(action.get("short_label", edge.get("action", ""))), str(edge.get("guard_label", "без условия"))])
	return "\n".join(lines)

func _return_to_live() -> void:
	set_snapshot(_live_snapshot, -1)
	center_on_current()
	current_requested.emit()

func _on_node_selected(node: Node) -> void:
	_focused_node_id = str(node.name)
	var node_data: Dictionary = DialogueGraph.data().get("nodes", {}).get(_focused_node_id, {})
	var lines: PackedStringArray = [str(node_data.get("label", "")), _focused_node_id, "", str(node_data.get("description", "")), "", "АСТЕРА", str(node_data.get("npc_line", "")), "", "ДЕЙСТВИЯ И УСЛОВИЯ"]
	for edge in DialogueGraph.data().get("transitions", []):
		if str(edge.get("from", "")) != _focused_node_id: continue
		var action: Dictionary = DialogueGraph.data().get("actions", {}).get(str(edge.get("action", "")), {})
		var target: Dictionary = DialogueGraph.data().get("nodes", {}).get(str(edge.get("to", "")), {})
		lines.append("\n" + str(action.get("label", edge.get("action", ""))) + "\n→ " + str(target.get("label", "")) + "\n" + str(edge.get("guard_label", "")))
		for effect in edge.get("effects", []):
			lines.append("Последствие: " + str(effect.get("reason", effect.get("id", ""))))
	node_diagnostic.text = "\n".join(lines)
	_refresh_highlights()

func _position_for(node_data: Dictionary, node_id: String) -> Vector2:
	var position: Array = node_data.get("debug_position", [0, 0])
	if position.size() < 2:
		return Vector2.ZERO
	return Vector2(72.0 + float(position[0]) * 335.0, 72.0 + float(position[1]) * 255.0)

func _layout_cards() -> void:
	# Container minimum sizes settle only after wrapped labels have a width.
	# Recompute row/column extents from real cards instead of a fixed pitch.
	for pass_index in 3:
		await get_tree().process_frame
		for card in _node_cards.values():
			card.reset_size()
	await get_tree().process_frame
	var widths := {}
	var heights := {}
	var nodes: Dictionary = DialogueGraph.data().get("nodes", {})
	for node_id in _node_cards:
		var cell: Array = nodes[node_id].get("debug_position", [0, 0])
		var card: GraphNode = _node_cards[node_id]
		widths[int(cell[0])] = maxf(float(widths.get(int(cell[0]), 0)), card.size.x)
		heights[int(cell[1])] = maxf(float(heights.get(int(cell[1]), 0)), card.size.y)
	for node_id in _node_cards:
		var cell: Array = nodes[node_id].get("debug_position", [0, 0])
		var position := Vector2(100, 100)
		for column in int(cell[0]): position.x += float(widths.get(column, 0)) + 170.0
		for row in int(cell[1]): position.y += float(heights.get(row, 0)) + 110.0
		_node_cards[node_id].position_offset = position
	_connect_graph()
	_layout_ready = true
	_refresh_highlights()
	center_on_current()

func _short(value: String, limit: int) -> String:
	var single := value.replace("\n", " ")
	return single if single.length() <= limit else single.substr(0, limit - 1) + "…"
