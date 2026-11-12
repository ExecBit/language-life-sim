extends RefCounted
## Authored social topics, available actions and transitions. Recognition stays in the language layer.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")

static func data() -> Dictionary:
	return Language.data().get("dialogue", {})

static func current_node(context: Dictionary) -> String:
	if not context.get("pending_clarification", {}).is_empty() and data().get("nodes", {}).has("clarification"):
		return "clarification"
	return str(context.get("dialogue_node", "opening"))

static func initial_history() -> Dictionary:
	return {"dialogue_history":[], "dialogue_node_history":["opening"]}

static func available_actions(context: Dictionary) -> Array[Dictionary]:
	var graph := data()
	var node_id := current_node(context)
	var node: Dictionary = graph.get("nodes", {}).get(node_id, {})
	var result: Array[Dictionary] = []
	for action_id in node.get("actions", []):
		var action: Dictionary = graph.get("actions", {}).get(action_id, {})
		var allowed := true
		for field in action.get("requires", {}):
			if context.get(field) != action.requires[field]:
				allowed = false
		if allowed and not action.is_empty():
			var item := action.duplicate(true)
			item["id"] = action_id
			var proposition: Dictionary = context.get("pending_clarification", {}).get("proposition", {})
			var meaning := str(graph.get("clarification_meanings", {}).get(str(proposition.get("intent", "")), ""))
			if not meaning.is_empty() and action.has("label_template"):
				var state_id := str(proposition.get("state_id", ""))
				var state := str(Language.data().get("states", {}).get(state_id, {}).get("translation", state_id))
				if str(proposition.get("polarity", "positive")) == "negative":
					state = "не " + state
				item.label = str(action.label_template).format({"meaning":meaning.format({"state":state})})
			result.append(item)
	return result

static func sync_selection(context: Dictionary) -> void:
	var actions := available_actions(context)
	for action in actions:
		if str(action.id) == str(context.get("selected_action", "")):
			context.selected_topic = str(action.get("topic", ""))
			return
	context.selected_action = "" if actions.is_empty() else str(actions[0].id)
	context.selected_topic = "" if actions.is_empty() else str(actions[0].get("topic", ""))

static func advance(context: Dictionary, reaction: String, parsed: Dictionary, input_text: String, before: Dictionary) -> Dictionary:
	var graph := data()
	var from_node := current_node(before)
	var to_node := current_node(context)
	var transition: Dictionary = {}
	if str(parsed.get("status", "")) == "RECOGNIZED":
		for candidate in graph.get("transitions", []):
			if not _source_matches(candidate.get("from", "*"), from_node):
				continue
			if reaction.match(str(candidate.get("reaction", ""))):
				transition = candidate
				break
	if not transition.is_empty():
		to_node = str(transition.get("to", to_node))
		context.dialogue_node = to_node
	elif not context.get("pending_clarification", {}).is_empty():
		to_node = "clarification"
	else:
		to_node = current_node(context)
	var event := {
		"from":from_node,
		"to":to_node,
		"reaction":reaction,
		"intent":str(parsed.get("intent", "")),
		"status":str(parsed.get("status", "")),
		"input":input_text,
		"changed":from_node != to_node,
		"authored_transition":not transition.is_empty()
	}
	_append_event(context, event)
	sync_selection(context)
	return event

static func record_navigation(context: Dictionary, reason: String) -> Dictionary:
	var from_node := current_node(context)
	context.pending_clarification = {}
	var to_node := current_node(context)
	var event := {"from":from_node,"to":to_node,"reaction":reason,"intent":"TOPIC_CHANGE",
		"status":"NAVIGATION","input":"","changed":from_node != to_node,"authored_transition":false}
	_append_event(context, event)
	sync_selection(context)
	return event

static func _append_event(context: Dictionary, event: Dictionary) -> void:
	var events: Array = context.get("dialogue_history", []).duplicate(true)
	events.append(event.duplicate(true))
	context.dialogue_history = events
	var visits: Array = context.get("dialogue_node_history", ["opening"]).duplicate()
	if visits.is_empty():
		visits.append(str(event.get("from", "opening")))
	if str(visits.back()) != str(event.get("to", "")):
		visits.append(str(event.get("to", "")))
	context.dialogue_node_history = visits

static func _source_matches(source: Variant, node_id: String) -> bool:
	if source is Array:
		return source.has(node_id)
	return str(source) == "*" or str(source) == node_id
