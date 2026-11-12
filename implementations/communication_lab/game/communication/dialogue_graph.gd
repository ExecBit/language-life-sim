extends RefCounted
## Authored menu availability and transitions, independent of German recognition.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")

static func available_actions(context: Dictionary) -> Array[Dictionary]:
	var graph: Dictionary = Language.data().get("dialogue", {})
	var node_id := str(context.get("dialogue_node", "opening"))
	if not context.get("pending_clarification", {}).is_empty():
		node_id = "clarification"
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

static func advance(context: Dictionary, reaction: String) -> void:
	var graph: Dictionary = Language.data().get("dialogue", {})
	for transition in graph.get("transitions", []):
		if reaction.match(str(transition.get("reaction", ""))):
			context.dialogue_node = str(transition.to)
			break
	sync_selection(context)
