extends RefCounted
## The one place where a validated authored edge changes RPG state.
const DialogueLanguage = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const DialogueGraph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")

static func initial_context() -> Dictionary:
	return {
		"roster_has_player":true, "is_technician":false, "has_pass":false,
		"access_status":"none", "player_name":"", "trust":"neutral", "message_promise":false,
		"technician_claimed":false, "current_node":"G00_GATE", "selected_action":"",
		"pending_proposition":{}, "pending_resolution":{}, "pending_clarification":{},
		"node_history":["G00_GATE"], "visited_nodes":["G00_GATE"], "dialogue_history":[],
		"dialog_opened_once":false, "last_npc_line":"", "last_event":{}
	}

static func opening_line(context: Dictionary) -> Dictionary:
	if bool(context.get("dialog_opened_once", false)) and _is_terminal(DialogueGraph.node_id(context)):
		var resolved := DialogueGraph.resolve_system(context, "reopen")
		var edge: Dictionary = resolved.get("edge", {})
		if not edge.is_empty():
			_apply_edge(edge, "REOPEN_DIALOG", {"system_event":"reopen"}, "", context, "")
	context.dialog_opened_once = true
	_ensure_open_proposition(context)
	var node_data := DialogueGraph.node(context)
	var line := DialogueGraph.display_line(context)
	context.last_npc_line = line
	return {"answer":line, "emotion_state":str(node_data.get("emotion_state", "neutral")),
		"animation_id":str(node_data.get("animation_id", "standing")), "node_id":DialogueGraph.node_id(context)}

static func available_actions(context: Dictionary) -> Array[Dictionary]:
	if not context.get("pending_resolution", {}).is_empty():
		var all_actions: Dictionary = DialogueGraph.data().get("actions", {})
		var choices: Array[Dictionary] = []
		for id in ["confirm_proposition", "reject_proposition"]:
			if all_actions.has(id):
				var item: Dictionary = all_actions[id].duplicate(true)
				item["id"] = id
				item["label"] = "Подтвердить понятный смысл" if id == "confirm_proposition" else "Отклонить и остаться здесь"
				choices.append(item)
		return choices
	return DialogueGraph.actions_for(context)

static func select_action(action_id: String, context: Dictionary) -> Dictionary:
	for action in available_actions(context):
		if str(action.get("id", "")) == action_id:
			context.selected_action = action_id
			return {"accepted":true, "action":action.duplicate(true)}
	return {"accepted":false}

static func select_topic(topic_id: String, context: Dictionary) -> Dictionary:
	# Kept for older UI callers; topic names are now stable action ids only.
	var result := select_action(topic_id, context)
	return {"selected_topic":str(context.get("selected_action", "")), "closed_clarification":false, "accepted":result.get("accepted", false)}

static func close_dialog(context: Dictionary) -> bool:
	# Closing the UI is not an in-world farewell and keeps every proposition/fact intact.
	context.selected_action = ""
	return false

static func submit(text: String, context: Dictionary, selected_action: String = "") -> Dictionary:
	if not selected_action.is_empty(): context.selected_action = selected_action
	var before: Dictionary = context.duplicate(true)
	var action_before := str(context.get("selected_action", ""))
	var parsed: Dictionary = DialogueLanguage.analyze_rpg(text, context)
	var effects: Array[Dictionary] = []
	var answer := ""
	var notification := str(parsed.get("notification", ""))
	var transition: Dictionary = {}
	var transition_error := ""
	var applied_event: Dictionary = {}
	var intent := str(parsed.get("intent", ""))
	var frame: Dictionary = parsed.get("frame", {}).duplicate(true)
	var edge_intent := intent
	var edge_frame: Dictionary = frame.duplicate(true)
	var pending_resolution: Dictionary = context.get("pending_resolution", {}).duplicate(true)

	if not pending_resolution.is_empty() and intent in ["SHORT_YES", "SHORT_NO"]:
		var confirmed := intent == "SHORT_YES"
		if confirmed:
			var delayed := _edge_by_id(str(pending_resolution.get("edge_id", "")))
			if str(delayed.get("from", "")) == DialogueGraph.node_id(context) and DialogueGraph.guard_matches(delayed.get("guard", {}), context):
				transition = delayed
				edge_frame = pending_resolution.get("frame", frame).duplicate(true)
				edge_intent = str(pending_resolution.get("actual_intent", intent))
				context.pending_resolution = {}
				context.pending_proposition = pending_resolution.get("previous_proposition", {}).duplicate(true)
			else:
				transition_error = "PENDING_EDGE_NO_LONGER_VALID"
		else:
			context.pending_resolution = {}
			context.pending_proposition = pending_resolution.get("previous_proposition", {}).duplicate(true)
			answer = "Alles klar. Wir bleiben beim selben Thema."
			context.selected_action = ""
	elif str(parsed.get("status", "")) == "RECOGNIZED":
		var resolved := DialogueGraph.resolve(context, intent, frame)
		transition = resolved.get("edge", {})
		transition_error = str(resolved.get("error", ""))
		if not transition.is_empty() and action_before != str(transition.get("action", "")):
			var previous_proposition: Dictionary = context.get("pending_proposition", {}).duplicate(true)
			var target_action: Dictionary = DialogueGraph.data().get("actions", {}).get(str(transition.action), {})
			context.pending_resolution = {"edge_id":str(transition.id), "frame":frame.duplicate(true),
				"actual_intent":intent, "selected_action":action_before, "previous_proposition":previous_proposition}
			context.pending_proposition = {"id":"confirm_intended_action", "kind":"intent_mismatch",
				"edge_id":str(transition.id), "value":str(transition.get("semantic_action", ""))}
			answer = str(target_action.get("confirm_question", "Meinst du das?"))
			context.selected_action = ""
			transition = {}
			transition_error = "SELECTED_ACTION_MISMATCH"
		elif transition.is_empty():
			answer = _no_branch_reply(intent, frame, context)
			context.selected_action = ""
	else:
		answer = _failure_reply(parsed)
		if str(parsed.get("status", "")) == "RECOGNIZED": context.selected_action = ""

	if not transition.is_empty():
		var applied := _apply_edge(transition, edge_intent, edge_frame, text, context, action_before)
		effects = applied.effects
		answer = str(applied.answer)
		applied_event = applied.event
		if edge_intent != intent:
			applied_event["actual_intent"] = intent
			applied_event["frame"] = frame.duplicate(true)
			applied_event["resolved_intent"] = edge_intent
			applied_event["resolved_frame"] = edge_frame.duplicate(true)
			var stored: Array = context.dialogue_history.duplicate(true)
			stored[stored.size() - 1] = applied_event.duplicate(true)
			context.dialogue_history = stored
			context.last_event = applied_event.duplicate(true)
	elif answer.is_empty():
		if transition_error == "SELECTED_ACTION_MISMATCH":
			notification = "Выбранная цель и смысл фразы различаются. Подтверди вопрос NPC, чтобы выполнить понятное действие."
		elif transition_error == "AMBIGUOUS_AUTHORED_EDGE":
			notification = "Для этой фразы доступно несколько веток; состояние не изменено."
			answer = "Was meinst du genau?"
		else:
			answer = _no_branch_reply(intent, frame, context)

	var event: Dictionary = applied_event if not applied_event.is_empty() else {
		"transition_id":str(transition.get("id", "")),
		"node_before":str(before.get("current_node", "G00_GATE")),
		"node_after":str(context.get("current_node", "G00_GATE")),
		"selected_action":action_before,
		"actual_intent":intent,
		"input":text,
		"frame":frame.duplicate(true),
		"effects":effects.duplicate(true),
		"active_conditions":_condition_history(transition, before) if not transition.is_empty() else _outgoing_conditions(before),
		"status":str(parsed.get("status", "")),
		"changed":str(before.get("current_node", "")) != str(context.get("current_node", "")),
		"reason":transition_error
	}
	if applied_event.is_empty(): _append_event(context, event)
	var node_data := DialogueGraph.node(context)
	var result := {
		"input":text, "before":before, "parse":parsed, "answer":answer, "notification":notification,
		"effects":effects, "after":context.duplicate(true), "current_node":DialogueGraph.node_id(context),
		"dialogue_node":DialogueGraph.node_id(context), "transition_id":str(event.transition_id),
		"graph_event":event.duplicate(true), "dialogue_history":context.dialogue_history.duplicate(true),
		"node_history":context.node_history.duplicate(true), "selected_action":action_before,
		"conversation_context":_conversation_snapshot(context),
		"emotion_state":str(node_data.get("emotion_state", "neutral")),
		"animation_id":str(node_data.get("animation_id", "standing")),
		"reaction":str(intent).to_lower(), "topic":str(intent), "objective_progress":{}, "objective_evidence":{}
	}
	_append_journal(result)
	return result

static func _apply_edge(edge: Dictionary, intent: String, frame: Dictionary, input_text: String, context: Dictionary, selected_action: String) -> Dictionary:
	var from_node := DialogueGraph.node_id(context)
	var guard_snapshot := DialogueGraph.active_conditions(edge, context)
	var effects_applied: Array[Dictionary] = []
	for effect_data in edge.get("effects", []):
		var changes: Dictionary = {}
		for key in effect_data.get("fields", {}):
			var raw: Variant = effect_data.fields[key]
			var value: Variant = raw
			if raw is String and str(raw).begins_with("$frame."):
				value = frame.get(str(raw).trim_prefix("$frame."), "")
			if context.get(str(key)) != value:
				changes[str(key)] = value
		for key in changes: context[str(key)] = changes[key]
		if not changes.is_empty():
			effects_applied.append({"id":str(effect_data.get("id", "")), "changes":changes,
				"reason":str(effect_data.get("reason", ""))})
	context.current_node = str(edge.get("to", from_node))
	context.pending_resolution = {}
	context.pending_clarification = {}
	context.selected_action = ""
	if not edge.get("to", "").is_empty() and DialogueGraph.data().get("nodes", {}).has(str(edge.to)):
		context.pending_proposition = _proposition_for(str(edge.to), context)
	var history: Array = context.get("node_history", [from_node]).duplicate()
	history.append(str(context.current_node))
	context.node_history = history
	var visited: Array = context.get("visited_nodes", []).duplicate()
	if not visited.has(str(context.current_node)): visited.append(str(context.current_node))
	context.visited_nodes = visited
	var event := {"transition_id":str(edge.get("id", "")), "node_before":from_node,
		"node_after":str(context.current_node), "selected_action":selected_action, "actual_intent":intent,
		"input":input_text, "frame":frame.duplicate(true), "effects":effects_applied.duplicate(true),
		"active_conditions":guard_snapshot, "status":"RECOGNIZED", "changed":from_node != str(context.current_node),
		"reason":str(edge.get("reason", ""))}
	_append_event(context, event)
	var answer := DialogueGraph.display_line(context)
	context.last_npc_line = answer
	return {"answer":answer, "effects":effects_applied, "event":event}

static func _proposition_for(node_id: String, context: Dictionary) -> Dictionary:
	var node_data: Dictionary = DialogueGraph.data().get("nodes", {}).get(node_id, {})
	var authored: Dictionary = node_data.get("open_proposition", {}).duplicate(true)
	if authored.is_empty(): return {}
	if authored.has("value_field"):
		authored.value = context.get(str(authored.value_field), "")
	authored.node_id = node_id
	return authored

static func _ensure_open_proposition(context: Dictionary) -> void:
	if context.get("pending_resolution", {}).is_empty() and context.get("pending_proposition", {}).is_empty():
		context.pending_proposition = _proposition_for(DialogueGraph.node_id(context), context)

static func _is_terminal(node_id: String) -> bool:
	return str(node_id) in DialogueGraph.data().get("terminal_nodes", [])

static func _edge_by_id(edge_id: String) -> Dictionary:
	for edge in DialogueGraph.data().get("transitions", []):
		if str(edge.get("id", "")) == edge_id: return edge
	return {}

static func _failure_reply(parsed: Dictionary) -> String:
	if str(parsed.get("reason", "")) == "MULTIPLE_INTENTS": return "Bitte eins nach dem anderen."
	if str(parsed.get("reason", "")) == "NO_OPEN_YES_NO_TARGET": return "Worauf bezieht sich dein Ja oder Nein?"
	return "Wie bitte? Sag es bitte anders oder bitte mich um Wiederholung."

static func _no_branch_reply(intent: String, frame: Dictionary, context: Dictionary) -> String:
	if intent in ["REQUEST_HELP", "OFFER_HELP"]:
		return "Ich brauche eine klare Antwort zur Karte oder zur Nachricht für Tom."
	if intent == "REPORT_HAS_CARD": return "Du hast eine Karte? Ich sehe dich nicht im Register."
	if intent == "CLAIM_TECHNICIAN" and str(context.get("current_node", "")) not in ["G00_GATE", "G70_EXPOSED", "G80_WARNING"]:
		return "Du bist gerade nicht am richtigen Ort für diese Aussage."
	if intent == "SHORT_YES" or intent == "SHORT_NO": return "Was meinst du damit?"
	return "Das passt gerade nicht. Was möchtest du tun?"

static func _condition_history(edge: Dictionary, context: Dictionary) -> Array[Dictionary]:
	return [{"edge_id":str(edge.get("id", "")), "label":str(edge.get("guard_label", "")),
		"conditions":DialogueGraph.active_conditions(edge, context), "reason":str(edge.get("reason", ""))}]

static func _outgoing_conditions(context: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for edge in DialogueGraph.outgoing(context):
		rows.append({"edge_id":str(edge.get("id", "")), "label":str(edge.get("guard_label", "")),
			"active":DialogueGraph.guard_matches(edge.get("guard", {}), context),
			"conditions":DialogueGraph.active_conditions(edge, context)})
	return rows

static func _append_event(context: Dictionary, event: Dictionary) -> void:
	var history: Array = context.get("dialogue_history", []).duplicate(true)
	history.append(event.duplicate(true))
	context.dialogue_history = history
	context.last_event = event.duplicate(true)

static func _conversation_snapshot(context: Dictionary) -> Dictionary:
	return {"roster_has_player":context.get("roster_has_player"), "is_technician":context.get("is_technician"),
		"has_pass":context.get("has_pass"), "access_status":context.get("access_status"),
		"player_name":context.get("player_name"), "trust":context.get("trust"),
		"message_promise":context.get("message_promise"), "current_node":context.get("current_node"),
		"selected_action":context.get("selected_action"), "pending_proposition":context.get("pending_proposition"),
		"pending_resolution":context.get("pending_resolution"), "node_history":context.get("node_history"),
		"visited_nodes":context.get("visited_nodes"), "dialogue_history":context.get("dialogue_history")}

static func reset(context: Dictionary) -> Dictionary:
	context.clear()
	context.merge(initial_context())
	return context

static func _append_journal(record: Dictionary) -> void:
	var file := FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.WRITE)
	if file == null:
		push_warning("Could not open Communication Lab attempt journal: %s" % FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()
