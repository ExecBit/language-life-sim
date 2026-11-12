extends Control
## Live view of authored conversation nodes and the route taken by recorded attempts.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const DialogueGraph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")

var current_node_id := "opening"
var node_history: Array = ["opening"]
var dialogue_history: Array[Dictionary] = []
var selected_attempt := -1

const NODE_POSITIONS := {
	"opening": Vector2i(0, 0),
	"conversation": Vector2i(1, 0),
	"after_tired": Vector2i(2, 0),
	"after_request": Vector2i(0, 1),
	"after_offer": Vector2i(1, 1),
	"after_state": Vector2i(2, 1),
	"farewell": Vector2i(0, 2),
	"after_activity": Vector2i(1, 2),
	"clarification": Vector2i(2, 2)
}

func _ready() -> void:
	custom_minimum_size = Vector2(450, 300)
	queue_redraw()

func set_snapshot(context: Dictionary, attempt_index := -1) -> void:
	current_node_id = DialogueGraph.current_node(context)
	node_history = context.get("dialogue_node_history", ["opening"]).duplicate()
	dialogue_history.clear()
	for event in context.get("dialogue_history", []):
		if event is Dictionary:
			dialogue_history.append(event.duplicate(true))
	selected_attempt = attempt_index
	queue_redraw()

func _draw() -> void:
	var graph: Dictionary = Language.data().get("dialogue", {})
	var nodes: Dictionary = graph.get("nodes", {})
	var cards := _card_rects(nodes)
	_draw_history_edges(cards)
	_draw_live_edges(cards, graph.get("transitions", []))
	for node_id in NODE_POSITIONS:
		if not nodes.has(node_id) or not cards.has(node_id):
			continue
		_draw_node(str(node_id), nodes[node_id], cards[node_id], graph.get("actions", {}))

func _card_rects(nodes: Dictionary) -> Dictionary:
	var result := {}
	var column_width := size.x / 3.0
	var card_width := maxf(132.0, minf(220.0, column_width - 12.0))
	var card_height := 76.0
	var row_gap := 18.0
	var top := 8.0
	for node_id in NODE_POSITIONS:
		if not nodes.has(node_id):
			continue
		var grid: Vector2i = NODE_POSITIONS[node_id]
		var left := column_width * float(grid.x) + (column_width - card_width) * 0.5
		var y := top + float(grid.y) * (card_height + row_gap)
		result[node_id] = Rect2(Vector2(left, y), Vector2(card_width, card_height))
	return result

func _draw_node(node_id: String, node: Dictionary, rect: Rect2, actions: Dictionary) -> void:
	var visited := node_history.has(node_id)
	var current := node_id == current_node_id
	var fill := Color("24505a") if current else (Color("293b4a") if visited else Color("182633"))
	var outline := Color("a8e3c3") if current else (Color("649d91") if visited else Color("435568"))
	draw_rect(rect, fill, true)
	draw_rect(rect, outline, false, 2.0 if current else 1.0)
	var font: Font = ThemeDB.fallback_font
	var title := str(node.get("label", node_id))
	draw_string(font, rect.position + Vector2(8, 19), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 13, Color("f0f4f7"))
	var action_labels: Array[String] = []
	for action_id in node.get("actions", []):
		var action: Dictionary = actions.get(action_id, {})
		if not action.is_empty():
			action_labels.append(str(action.get("short_label", action.get("label", action_id))))
	var action_line := ", ".join(action_labels)
	if action_line.length() > 38:
		action_line = action_line.substr(0, 35) + "…"
	draw_string(font, rect.position + Vector2(8, 39), action_line, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 10, Color("bad0d9"))
	var visits := _visit_count(node_id)
	var suffix := "СЕЙЧАС" if current else ("×%d" % visits if visits > 0 else "")
	if not suffix.is_empty():
		draw_string(font, rect.position + Vector2(8, rect.size.y - 8), suffix, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, 10, Color("a8e3c3") if current else Color("82b7ac"))

func _draw_live_edges(cards: Dictionary, transitions: Array) -> void:
	if not cards.has(current_node_id):
		return
	var source_rect: Rect2 = cards[current_node_id]
	for transition in transitions:
		var from_value: Variant = transition.get("from", "*")
		var applies: bool = from_value == "*" or (from_value is Array and from_value.has(current_node_id)) or str(from_value) == current_node_id
		if not applies:
			continue
		var destination := str(transition.get("to", ""))
		if destination == current_node_id or not cards.has(destination):
			continue
		_draw_arrow(source_rect, cards[destination], Color("82b8b4", 0.82), 1.5)

func _draw_history_edges(cards: Dictionary) -> void:
	for event in dialogue_history:
		var source := str(event.get("from", ""))
		var destination := str(event.get("to", ""))
		if source == destination or not cards.has(source) or not cards.has(destination):
			continue
		_draw_arrow(cards[source], cards[destination], Color("e8c783", 0.86), 2.5)

func _draw_arrow(source: Rect2, destination: Rect2, color: Color, width: float) -> void:
	var start_point := source.get_center()
	var end_point := destination.get_center()
	var direction := (end_point - start_point).normalized()
	if direction == Vector2.ZERO:
		return
	var start := _rect_edge(source, direction) + direction * 2.0
	var end := _rect_edge(destination, -direction) - direction * 4.0
	draw_line(start, end, color, width, true)
	var perpendicular := Vector2(-direction.y, direction.x)
	var arrow_size := 6.0
	draw_colored_polygon(PackedVector2Array([end, end - direction * arrow_size + perpendicular * arrow_size * 0.55,
		end - direction * arrow_size - perpendicular * arrow_size * 0.55]), color)

func _rect_edge(rect: Rect2, direction: Vector2) -> Vector2:
	var x_distance := (rect.size.x * 0.5) / maxf(absf(direction.x), 0.001)
	var y_distance := (rect.size.y * 0.5) / maxf(absf(direction.y), 0.001)
	return rect.get_center() + direction * minf(x_distance, y_distance)

func _visit_count(node_id: String) -> int:
	var count := 0
	for visit in node_history:
		if str(visit) == node_id:
			count += 1
	return count
