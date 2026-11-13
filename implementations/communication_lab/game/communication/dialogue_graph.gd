extends RefCounted
## Pure access and validation for the authored RPG graph. LabSession applies effects.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")

static func data() -> Dictionary:
	return Language.data().get("dialogue", {})

static func node_id(context: Dictionary) -> String:
	return str(context.get("current_node", data().get("initial_node", "G00_GATE")))

static func node(context: Dictionary) -> Dictionary:
	return data().get("nodes", {}).get(node_id(context), {})

static func actions_for(context: Dictionary) -> Array[Dictionary]:
	var graph := data()
	var source: Dictionary = graph.get("nodes", {}).get(node_id(context), {})
	var result: Array[Dictionary] = []
	for action_id in source.get("actions", []):
		var action: Dictionary = graph.get("actions", {}).get(str(action_id), {})
		if action.is_empty() or not guard_matches(action.get("visible_when", {}), context):
			continue
		var view := action.duplicate(true)
		view["id"] = str(action_id)
		result.append(view)
	return result

static func outgoing(context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in data().get("transitions", []):
		if str(candidate.get("from", "")) == node_id(context):
			result.append(candidate)
	return result

static func resolve(context: Dictionary, actual_intent: String, frame: Dictionary) -> Dictionary:
	var matches: Array[Dictionary] = []
	for candidate in outgoing(context):
		if str(candidate.get("semantic_action", "")) != actual_intent:
			continue
		if not frame_matches(candidate.get("required_frame", {}), frame):
			continue
		if not guard_matches(candidate.get("guard", {}), context):
			continue
		matches.append(candidate)
	if matches.size() == 1:
		return {"edge":matches[0], "error":""}
	if matches.size() > 1:
		return {"edge":{}, "error":"AMBIGUOUS_AUTHORED_EDGE", "candidates":matches}
	return {"edge":{}, "error":"NO_AUTHORED_EDGE"}

static func resolve_system(context: Dictionary, system_event: String) -> Dictionary:
	for action in data().get("actions", {}).values():
		if action.get("system_event", "") == system_event:
			return resolve(context, str(action.get("semantic_action", "")), {"system_event":system_event})
	return {"edge":{}, "error":"UNKNOWN_SYSTEM_EVENT"}

static func frame_matches(required: Dictionary, frame: Dictionary) -> bool:
	for key in required:
		if not frame.has(key):
			return false
		var expected: Variant = required[key]
		var actual: Variant = frame[key]
		if expected is Dictionary:
			match str(expected.get("op", "eq")):
				"not_empty":
					if str(actual).strip_edges().is_empty(): return false
				"empty":
					if not str(actual).strip_edges().is_empty(): return false
				"in":
					if actual not in expected.get("value", []): return false
				_:
					if actual != expected.get("value"): return false
		elif expected is Array:
			if actual not in expected: return false
		elif actual != expected:
			return false
	return true

static func guard_matches(guard: Variant, context: Dictionary) -> bool:
	if guard is Array:
		for condition in guard:
			if condition is Dictionary and not _condition_matches(condition, context):
				return false
		return true
	if not guard is Dictionary:
		return false
	for condition in guard.get("all", []):
		if not _condition_matches(condition, context): return false
	if not guard.get("any", []).is_empty():
		var any_passed := false
		for condition in guard.get("any", []):
			if _condition_matches(condition, context): any_passed = true
		if not any_passed: return false
	for condition in guard.get("not", []):
		if _condition_matches(condition, context): return false
	return true

static func _condition_matches(condition: Dictionary, context: Dictionary) -> bool:
	var actual: Variant = _read_path(context, str(condition.get("field", "")))
	var expected: Variant = condition.get("value")
	match str(condition.get("op", "eq")):
		"eq": return actual == expected
		"ne": return actual != expected
		"in": return actual in (expected if expected is Array else [])
		"not_in": return actual not in (expected if expected is Array else [])
		"not_empty": return not str(actual).strip_edges().is_empty()
		"empty": return str(actual).strip_edges().is_empty()
		"truthy": return bool(actual)
		"falsy": return not bool(actual)
	return false

static func _read_path(source: Dictionary, path: String) -> Variant:
	var value: Variant = source
	for part in path.split("."):
		if not value is Dictionary or not value.has(part):
			return null
		value = value[part]
	return value

static func active_conditions(edge: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var conditions: Array[Dictionary] = []
	var guard: Variant = edge.get("guard", {})
	if guard is Array:
		for raw in guard:
			if raw is Dictionary: conditions.append(_condition_snapshot(raw, context))
	else:
		for group in ["all", "any", "not"]:
			for raw in guard.get(group, []):
				if raw is Dictionary:
					var row := _condition_snapshot(raw, context)
					row["group"] = group
					conditions.append(row)
	return conditions

static func _condition_snapshot(condition: Dictionary, context: Dictionary) -> Dictionary:
	var field := str(condition.get("field", ""))
	return {"field":field, "op":str(condition.get("op", "eq")), "expected":condition.get("value"),
		"actual":_read_path(context, field), "active":_condition_matches(condition, context)}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var graph := data()
	var nodes: Dictionary = graph.get("nodes", {})
	var actions: Dictionary = graph.get("actions", {})
	var transitions: Array = graph.get("transitions", [])
	if nodes.size() != int(graph.get("expected_node_count", nodes.size())): errors.append("Authored node count mismatch")
	var edge_ids := {}
	var reachable := {str(graph.get("initial_node", "")):true}
	var changed := true
	while changed:
		changed = false
		for candidate in transitions:
			if reachable.has(str(candidate.get("from", ""))) and not reachable.has(str(candidate.get("to", ""))):
				reachable[str(candidate.to)] = true
				changed = true
	for node_key in nodes:
		if not reachable.has(str(node_key)): errors.append("Unreachable node: %s" % node_key)
		var node_data: Dictionary = nodes[node_key]
		if str(node_data.get("label", "")).is_empty(): errors.append("Node has no label: %s" % node_key)
		for action_id in node_data.get("actions", []):
			if not actions.has(str(action_id)): errors.append("Unknown action %s on %s" % [action_id, node_key])
	for candidate in transitions:
		var edge_id := str(candidate.get("id", ""))
		if edge_id.is_empty(): errors.append("Edge has no stable id")
		elif edge_ids.has(edge_id): errors.append("Duplicate edge id: %s" % edge_id)
		edge_ids[edge_id] = true
		if not nodes.has(str(candidate.get("from", ""))): errors.append("Unknown edge source: %s" % candidate.get("from", ""))
		if not nodes.has(str(candidate.get("to", ""))): errors.append("Unknown edge destination: %s" % candidate.get("to", ""))
		if not actions.has(str(candidate.get("action", ""))): errors.append("Unknown edge action: %s" % candidate.get("action", ""))
		if not candidate.get("guard", {}) is Dictionary: errors.append("Malformed guard on %s" % edge_id)
		if not candidate.get("required_frame", {}) is Dictionary: errors.append("Malformed frame on %s" % edge_id)
		for effect in candidate.get("effects", []):
			if not effect.has("id") or not effect.has("reason") or not effect.has("fields"):
				errors.append("Malformed effect on %s" % edge_id)
		for other in transitions:
			if other == candidate: continue
			if str(other.get("from", "")) == str(candidate.get("from", "")) and str(other.get("semantic_action", "")) == str(candidate.get("semantic_action", "")) and other.get("required_frame", {}) == candidate.get("required_frame", {}) and other.get("guard", {}) == candidate.get("guard", {}):
				errors.append("Competing identical edges: %s and %s" % [edge_id, str(other.get("id", ""))])
				break
	for terminal in graph.get("terminal_nodes", []):
		if not nodes.has(str(terminal)) or not bool(nodes.get(str(terminal), {}).get("terminal", false)):
			errors.append("Invalid terminal node: %s" % terminal)
	for node_key in nodes:
		if bool(nodes[node_key].get("terminal", false)) and not str(node_key).begins_with("E_"):
			errors.append("Terminal node must use E_ prefix: %s" % node_key)
	return errors

static func display_line(context: Dictionary) -> String:
	var data_node := node(context)
	var line := str(data_node.get("npc_line", ""))
	if data_node.has("npc_line_by_access"):
		line = str(data_node.npc_line_by_access.get(str(context.get("access_status", "none")), data_node.npc_line_by_access.get("none", "")))
	return line.format({"player_name":str(context.get("player_name", "")) if not str(context.get("player_name", "")).is_empty() else "Fremder"})
