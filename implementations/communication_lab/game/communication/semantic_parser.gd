extends RefCounted
## Typed, bounded semantic grammar. No NPC names, node IDs or whole utterances.
## Lexical meanings, domain bindings and discourse referents come from scenario data.

static func analyze(text: String, context: Dictionary, scenario: Dictionary, depth := 0) -> Dictionary:
	var result := {"handled":true,"raw_input":text,"status":"UNKNOWN","reason":"NO_SUPPORTED_CONSTRUCTION",
		"intent":"","semantic":"","family":"","frame":{},"semantic_frames":[],"candidates":[],
		"normalized_tokens":[],"lexical_readings":[],"unknown_tokens":[],"unused_tokens":[],
		"diagnostics":[],"explicit_evidence":[],"inferred_fields":[],"repairs":[],
		"grammatical_error_detected":false,"semantic_recovery_status":"NONE","recovery_used":false,
		"notification":"","clarification":""}
	var model: Dictionary = scenario.get("language", {})
	var participants: Dictionary = model.get("participants", {"speaker":"player","addressee":"npc"})
	var speaker := str(participants.get("speaker", "player"))
	var addressee := str(participants.get("addressee", "npc"))
	var graph: Dictionary = scenario.get("dialogue", {})
	var node: Dictionary = graph.get("nodes", {}).get(str(context.get("current_node", "")), {})
	var discourse: Dictionary = node.get("language_context", {})
	var lexicon := {}
	for row in scenario.get("vocabulary", []): lexicon[str(row.surface).to_lower()] = row
	var regex := RegEx.new()
	regex.compile("[\\p{L}]+")
	var tokens: Array[Dictionary] = []
	for match in regex.search_all(text):
		var surface: String = match.get_string()
		var word := surface.to_lower()
		var entry: Dictionary = lexicon.get(word, {})
		var syntax: Dictionary = entry.get("syntax", {"kind":"content"}).duplicate(true)
		var token := {"surface":surface,"word":word,"position":match.get_start(),"syntax":syntax,"known":not entry.is_empty()}
		tokens.append(token)
		result.normalized_tokens.append(word)
		result.lexical_readings.append({"token":word,"surface":surface,"position":match.get_start(),"readings":[syntax]})
		if entry.is_empty(): result.unknown_tokens.append(word)
	if tokens.is_empty(): return _failure(result, "UNKNOWN", "EMPTY_INPUT")
	# Clause structure is checked before constructing any executable interpretation.
	var stripped := text.strip_edges()
	var greeting := RegEx.new()
	greeting.compile("(?i)^\\s*(hallo|hi)[!?.]*\\s+")
	stripped = greeting.sub(stripped, "", false)
	var clause_boundary := RegEx.new()
	clause_boundary.compile("[.!?;:]+\\s*(?=[\\p{L}])|\\b(?:und|aber|weil|wenn)\\b")
	var boundaries := clause_boundary.search_all(stripped)
	if not boundaries.is_empty() and depth == 0:
		var start := 0
		for boundary in boundaries:
			var part := stripped.substr(start, boundary.get_start() - start).strip_edges()
			if not part.is_empty():
				var sub := analyze(part, context, scenario, 1)
				result.semantic_frames.append({"intent":sub.intent,"frame":sub.frame,"status":sub.status})
			start = boundary.get_end()
		var tail := stripped.substr(start).strip_edges()
		if not tail.is_empty():
			var sub := analyze(tail, context, scenario, 1)
			result.semantic_frames.append({"intent":sub.intent,"frame":sub.frame,"status":sub.status})
		result["unsupported_features"] = ["MULTIPLE_INTENTS"]
		return _failure(result, "UNKNOWN" if not result.unknown_tokens.is_empty() else "UNSUPPORTED", "MULTIPLE_INTENTS")
	var subjects: Array[String] = []
	var recipients: Array[String] = []
	var entities: Array[Dictionary] = []
	var predicates: Array[String] = []
	var operators: Array[String] = []
	var attributes: Array[Dictionary] = []
	var properties: Array[String] = []
	var topics: Array[String] = []
	var acts: Array[String] = []
	var responses: Array[String] = []
	var negative := false
	var negation_count := 0
	var question := text.strip_edges().ends_with("?")
	var has_interrogative := false
	var has_polite := false
	var reference := false
	var name_marker := false
	var repeated := false
	var until := false
	var time := false
	for token in tokens:
		var s: Dictionary = token.syntax
		var kind := str(s.get("kind", "content"))
		match kind:
			"pronoun":
				var participant := speaker if str(s.get("participant", "")) == "speaker" else addressee
				var target := subjects if str(s.get("case", "")) == "nom" else recipients
				if not target.has(participant): target.append(participant)
			"entity": entities.append(s)
			"predicate":
				var predicate := str(s.get("predicate", ""))
				if not predicates.has(predicate): predicates.append(predicate)
			"operator":
				var operator := str(s.get("operator", ""))
				if not operators.has(operator): operators.append(operator)
				if s.has("normalizes_to"):
					result.repairs.append({"token":token.word,"normalization":s.normalizes_to,"ambiguous":s.get("ambiguous_normalization", false)})
			"attribute": attributes.append(s)
			"property": properties.append(str(s.get("property", "")))
			"topic": topics.append(str(s.get("topic", "")))
			"act": acts.append(str(s.get("family", "")))
			"response": responses.append(str(s.get("answer", "")))
			"negation": negative = true; negation_count += 1
			"interrogative": has_interrogative = true; question = true
			"polite": has_polite = true
			"reference": reference = true
			"name_marker": name_marker = true
			"repeat_marker": repeated = true
			"until": until = true
			"time": time = true
	if str(tokens[0].syntax.get("kind", "")) == "operator": question = true
	var open_question: Dictionary = context.get("pending_proposition", {})
	var only_answer := not responses.is_empty()
	for token in tokens:
		if str(token.syntax.get("kind", "")) not in ["response", "polite"]: only_answer = false
	if only_answer:
		if responses.has("contradict"): return _clarify(result, "CONTRADICTORY_ANSWER_TARGET", [], "Sag es bitte anders.")
		if responses.has("yes") and responses.has("no"): return _clarify(result, "CONFLICTING_ANSWERS", [], "Ja oder nein?")
		if not open_question.is_empty():
			var yes := responses[0] == "yes"
			return _complete(result, {"family":"response","intent":"SHORT_YES" if yes else "SHORT_NO", "frame":{"speaker":speaker,"actor":speaker,"confirmation":"yes" if yes else "no","speech_act":"answer","proposition_id":str(open_question.get("id", "")),"polarity":"positive" if yes else "negative"}}, [])
		if not context.get("pending_clarification", {}).is_empty():
			return _clarify(result, "NO_OPEN_YES_NO_TARGET", [], "Sag es bitte anders.")
		var challenge: Dictionary = discourse.get("challenge", {})
		if not challenge.is_empty() and responses[0] in ["yes", "no"]:
			var f := challenge.duplicate(true)
			f.polarity = "negative" if responses[0] == "no" else "positive"
			f["speaker"] = speaker
			f["speech_act"] = "answer"
			result.inferred_fields = ["challenge_from_current_node"]
			return _finish(result, [f], context, scenario, false, ["challenge_from_current_node"])
		return _clarify(result, "NO_OPEN_YES_NO_TARGET", [], "Worauf bezieht sich dein Ja oder Nein?")
	# Unknown names are allowed only in a declared name slot and name construction.
	var name_slot := bool(discourse.get("name_slot", false))
	var selected: Dictionary = graph.get("actions", {}).get(str(context.get("selected_action", "")), {})
	var name_shape := predicates.has("name") or (predicates == ["be"] and entities.is_empty() and properties.is_empty()) or (tokens.size() == 1 and str(selected.get("semantic_action", "")) == "PLAYER_NAME")
	var pure_name := not question and operators.is_empty() and entities.is_empty() and properties.is_empty()
	for token in tokens:
		if token.known and str(token.syntax.get("kind", "")) not in ["pronoun", "predicate", "name_marker", "article", "possessive", "polite", "greeting"]: pure_name = false
	if name_slot and name_shape and pure_name and not negative:
		var names: Array[String] = []
		for token in tokens:
			if not token.known: names.append(str(token.surface))
		if names.size() == 1 and result.unknown_tokens.size() == 1 and (subjects.is_empty() or subjects == [speaker]):
			var name := names[0].substr(0, 1).to_upper() + names[0].substr(1).to_lower()
			result.unknown_tokens.clear()
			return _finish(result, [{"family":"name","actor":speaker,"name":name,"polarity":"positive","speech_act":"statement"}], context, scenario, false, ["name_slot"])
	if not result.unknown_tokens.is_empty(): return _failure(result, "UNKNOWN", "UNKNOWN_TOKEN")
	if negation_count > 1: return _clarify(result, "NEGATION_SCOPE", [], "Sag es bitte anders.")
	if subjects.size() > 1: return _clarify(result, "AMBIGUOUS_ROLES", [], "Wer soll das machen? Ich oder du?")
	if predicates.size() > 1:
		# Modal operators are separate; two independent lexical heads are not silently collapsed.
		return _failure(result, "UNSUPPORTED", "MULTIPLE_PREDICATES")
	var actor := subjects[0] if subjects.size() == 1 else "unresolved"
	var head := predicates[0] if predicates.size() == 1 else ""
	var frame := {"speaker":speaker,"actor":actor,"subject":actor,"polarity":"negative" if negative else "positive", "speech_act":"question" if question else "statement","mode":"assert","family":"","object_id":"","object_type":"","recipient":"unresolved","recipient_id":""}
	if recipients.size() == 1: frame.recipient = recipients[0]
	if recipients.size() > 1: return _clarify(result, "AMBIGUOUS_RECIPIENT", [], "Wem? Mir oder dir?")
	var objects: Array[Dictionary] = []
	var people: Array[Dictionary] = []
	var roles: Array[Dictionary] = []
	for entity in entities:
		match str(entity.get("entity_type", "")):
			"person": people.append(entity)
			"role": roles.append(entity)
			_: objects.append(entity)
	var wish := operators.has("desire") or operators.has("need")
	var request_mode := wish or (question and (operators.has("ability") or operators.has("permission")))
	var inferred: Array[String] = []
	var confirmation_needed := false
	var allowed_heads: Array[String] = []
	if wish: frame.mode = "desire"
	elif not operators.is_empty(): frame.mode = "ability"
	if acts.has("farewell") or (until and time and head.is_empty()):
		frame.family = "farewell"; allowed_heads = [""]
	elif acts.has("apology") or head == "apologize":
		frame.family = "apology"; allowed_heads = ["", "apologize"]
	elif not roles.is_empty() and head in ["", "be"]:
		if roles.size() != 1: return _clarify(result, "AMBIGUOUS_ROLE", [], "Welche Rolle meinst du?")
		frame.family = "role"; frame["role_id"] = str(roles[0].entity_id)
		frame["role_label"] = str(roles[0].label); frame["gender"] = str(roles[0].get("gender", "m"))
		if wish: frame.mode = "desire"
		elif not operators.is_empty(): frame.mode = "ability"
		allowed_heads = ["", "be"]
	elif not properties.is_empty() and head in ["", "be"]:
		frame["property"] = properties[0]
		frame.family = "registration" if properties[0] == "registered" else "property"
		allowed_heads = ["", "be"]
	elif head == "repeat" or (head == "understand" and negative) or (repeated and head.is_empty() and objects.is_empty()):
		if head == "repeat" and actor == speaker and not question:
			return _failure(result, "UNSUPPORTED", "NOT_AN_NPC_SPEECH_REQUEST")
		if head == "repeat" and negative:
			return _finish(result, [{"family":"repeat","actor":speaker,"agent":addressee,"polarity":"positive","speech_act":"request_repeat"}], context, scenario, true, ["negative_question_pragmatics"])
		frame.family = "repeat"; frame["agent"] = actor if actor != "unresolved" else addressee
		frame.actor = speaker; allowed_heads = ["", "repeat", "understand"]
	elif _has_attribute(attributes, "slow") and head in ["", "speak"]:
		if actor == speaker or negative: return _failure(result, "UNSUPPORTED", "NOT_AN_NPC_SPEECH_REQUEST")
		frame.family = "slower"; frame["agent"] = actor if actor != "unresolved" else addressee
		frame.actor = speaker; allowed_heads = ["", "speak"]
	elif topics.has("registration") and question:
		frame.family = "registration"; allowed_heads = ["", "be", "know"]
	elif topics.has("alternative") or _has_attribute(attributes, "alternative"):
		frame.family = "alternative"; allowed_heads = ["", "exist", "know"]
	elif topics.has("access") and head in ["", "move", "leave", "know", "confirm"]:
		frame.family = str(discourse.get("entry_family", "rules"))
		allowed_heads = ["", "move", "leave", "know", "confirm"]
		if frame.family == "access":
			objects = _referents(discourse, lexicon, [])
	elif head == "help":
		frame.family = "help"; allowed_heads = ["help"]
		frame.mode = "offer" if actor == speaker else ("request" if question or not operators.is_empty() else "assert")
		if not negative and not question and operators.has("ability"): confirmation_needed = true; inferred.append("speech_act")
	elif question and head in ["do", "know"] and (str(discourse.get("topic", "")) == "message" or not objects.is_empty()):
		frame.family = "details"; allowed_heads = ["do", "know"]
	elif head == "deliver" or (head == "do" and reference and str(discourse.get("topic", "")) == "message"):
		frame.family = "delivery"; allowed_heads = ["deliver", "do"]
		frame.mode = "commit" if not question and not operators.has("ability") else "ability"
		if operators.has("obligation"): frame.mode = "obligation"
		if reference and objects.is_empty(): objects = _referents(discourse, lexicon, [{"entity_types":["message"]}]); inferred.append("object_id")
		if people.size() == 1: frame.recipient_id = str(people[0].entity_id)
		elif str(discourse.get("recipient_id", "")) != "": frame.recipient_id = str(discourse.recipient_id); inferred.append("recipient_id")
	elif head == "acquire" or wish or (head == "possess" and request_mode):
		frame.family = "acquisition"; allowed_heads = ["", "acquire", "possess"]
		if head == "acquire" and not request_mode:
			if question: frame.mode = "request"
			else: frame.family = "receipt"
		else: frame.speech_act = "question" if question else "request"
	elif head == "possess" or (head.is_empty() and not objects.is_empty() and negative):
		frame.family = "possession"; allowed_heads = ["", "possess"]
	elif head == "leave":
		frame.family = "farewell"; allowed_heads = ["leave"]
	elif not objects.is_empty() or not attributes.is_empty() or reference:
		# A noun phrase can complete a stored choice or propose a request; never a fact.
		var pending: Dictionary = context.get("pending_clarification", {})
		var pure_choice := not negative and not question and people.is_empty() and roles.is_empty()
		for token in tokens:
			if str(token.syntax.get("kind", "")) not in ["entity", "article", "attribute", "polite"]: pure_choice = false
		if pure_choice and str(pending.get("kind", "")) == "choice" and str(pending.get("node_id", "")) == str(context.get("current_node", "")) and int(pending.get("source_turn", -2)) == context.get("dialogue_history", []).size() - 1 and objects.size() == 1:
			for candidate in pending.get("candidates", []):
				if str(candidate.frame.get("referent_id", "")) == str(objects[0].entity_id):
					result.inferred_fields = ["intent_from_clarification"]
					return _complete(result, candidate, ["intent_from_clarification"])
		frame.family = "acquisition"; allowed_heads = [""]; confirmation_needed = true; inferred.append("predicate")
	if str(frame.family).is_empty(): return _failure(result, "UNSUPPORTED", "UNSUPPORTED_CONSTRUCTION")
	# Never use familiarity of a word as permission to drop its meaning.
	for token in tokens:
		var s: Dictionary = token.syntax
		var kind := str(s.get("kind", "content"))
		if kind == "content": result.unused_tokens.append(token.word)
		if kind == "predicate" and str(s.get("predicate", "")) not in allowed_heads: result.unused_tokens.append(token.word)
		if kind == "time" and str(s.get("reference", "present")) != "present" and frame.family != "farewell": result.unused_tokens.append(token.word)
		if kind == "interrogative" and frame.family in ["role", "property", "name", "possession", "delivery"]: result.unused_tokens.append(token.word)
		if kind == "conjunction": result.unused_tokens.append(token.word)
		if kind == "act" and str(s.get("family", "")) != frame.family: result.unused_tokens.append(token.word)
		if kind == "preposition" and frame.family in ["role", "property", "possession", "acquisition"]: result.unused_tokens.append(token.word)
	if properties.size() > 1: return _failure(result, "UNSUPPORTED", "MULTIPLE_PROPERTIES")
	if not topics.is_empty() and frame.family in ["role", "property", "possession", "name", "apology", "farewell"]: return _failure(result, "UNSUPPORTED", "UNACCOUNTED_TOPIC")
	if not people.is_empty() and frame.family != "delivery": return _failure(result, "UNSUPPORTED", "UNACCOUNTED_RECIPIENT")
	if not recipients.is_empty() and frame.family not in ["help", "delivery", "repeat", "slower", "apology"]: return _failure(result, "UNSUPPORTED", "UNACCOUNTED_RECIPIENT")
	if not attributes.is_empty() and frame.family in ["role", "property", "name", "apology", "farewell"]: return _failure(result, "UNSUPPORTED", "UNACCOUNTED_ATTRIBUTE")
	if not result.unused_tokens.is_empty(): return _failure(result, "UNSUPPORTED", "UNACCOUNTED_CONTENT")
	if not roles.is_empty() and frame.family != "role": return _failure(result, "UNSUPPORTED", "UNACCOUNTED_ROLE")
	if frame.family == "role" and (not objects.is_empty() or not people.is_empty()): return _failure(result, "UNSUPPORTED", "UNACCOUNTED_ENTITY")
	if frame.family in ["rules", "alternative", "registration", "details", "apology", "farewell", "repeat", "slower"] and not objects.is_empty() and frame.family != "details": return _failure(result, "UNSUPPORTED", "UNACCOUNTED_ENTITY")
	if frame.actor == "unresolved":
		frame.actor = speaker; inferred.append("actor")
		if frame.family in ["role", "possession", "help", "delivery"]: confirmation_needed = true
	if frame.family == "help" and frame.recipient == "unresolved":
		frame.recipient = addressee if frame.actor == speaker else speaker
		inferred.append("recipient"); confirmation_needed = true
	if frame.family == "help" and frame.actor == addressee and frame.mode == "assert":
		return _finish(result, [frame], context, scenario, true, ["speech_act"])
	if head.is_empty() and frame.family in ["role", "property", "possession", "registration"]:
		result.diagnostics.append({"code":"MISSING_FINITE_VERB"})
	for token in tokens:
		var person := int(token.syntax.get("person", 0))
		if person > 0 and subjects.size() == 1:
			var expected := 1 if subjects[0] == speaker else 2
			if person != expected: result.diagnostics.append({"code":"AGREEMENT_MISMATCH","token":token.word})
	if responses.has("no") and not negative:
		frame.polarity = "negative"
		confirmation_needed = true; inferred.append("self_repair_polarity")
	elif responses.has("yes") and negative:
		return _clarify(result, "AMBIGUOUS_NEGATION", [], "Ja oder nein? Sag es bitte anders.")
	for repair in result.repairs:
		if repair.get("ambiguous", false): confirmation_needed = true; inferred.append("normalization")
	var frames: Array = []
	if frame.family in ["acquisition", "receipt", "possession", "delivery", "access"]:
		if objects.is_empty():
			objects = _referents(discourse, lexicon, attributes)
			inferred.append("object_id"); confirmation_needed = true
		if objects.is_empty(): return _clarify(result, "MISSING_OBJECT", [], "Was meinst du genau?")
		for object in objects:
			if not _fits(object, attributes): continue
			var f := frame.duplicate(true)
			f.object_id = str(object.entity_id); f.object_type = str(object.entity_type)
			f["referent_id"] = str(object.entity_id); f["object_label"] = str(object.get("accusative", object.get("label", object.entity_id)))
			f["gender"] = str(object.get("gender", "m")); f["attributes"] = attributes.duplicate(true)
			frames.append(f)
	else: frames.append(frame)
	return _finish(result, frames, context, scenario, confirmation_needed, inferred)

static func _fits(entity: Dictionary, attributes: Array) -> bool:
	for attribute in attributes:
		var types: Array = attribute.get("entity_types", [])
		if not types.is_empty() and str(entity.get("entity_type", "")) not in types: return false
	return true

static func _has_attribute(attributes: Array, id: String) -> bool:
	for attribute in attributes:
		if str(attribute.get("attribute", "")) == id: return true
	return false

static func _referents(discourse: Dictionary, lexicon: Dictionary, attributes: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	for id in discourse.get("referents", []):
		for row in lexicon.values():
			var syntax: Dictionary = row.get("syntax", {})
			if str(syntax.get("kind", "")) != "entity" or str(syntax.get("entity_id", "")) != str(id) or seen.has(str(id)): continue
			if not _fits(syntax, attributes): continue
			found.append(syntax.duplicate(true)); seen[str(id)] = true
	return found

static func _finish(result: Dictionary, frames: Array, context: Dictionary, scenario: Dictionary, needs_confirmation: bool, inferred: Array) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var seen := {}
	for f in frames:
		var best := -1
		var matching: Array = []
		for binding in scenario.get("language", {}).get("bindings", []):
			if str(binding.get("family", "")) != str(f.get("family", "")): continue
			var ok := true
			for field in binding.get("requires", {}):
				var expected: Variant = binding.requires[field]
				if expected is Array:
					if f.get(field) not in expected: ok = false
				elif f.get(field) != expected: ok = false
			if not ok: continue
			var specificity: int = binding.get("requires", {}).size()
			if specificity > best: matching.clear(); best = specificity
			if specificity == best: matching.append(binding)
		if matching.is_empty(): matching.append({"intent":str(f.family).to_upper(),"frame":{}})
		for binding in matching:
			var frame: Dictionary = f.duplicate(true)
			for field in binding.get("frame", {}): frame[field] = binding.frame[field]
			for field in frame.keys():
				if frame[field] is String and str(frame[field]) in ["", "unresolved"]: frame.erase(field)
			var candidate := {"intent":str(binding.intent),"family":str(f.family),"frame":frame}
			var key := JSON.stringify(candidate)
			if not seen.has(key): candidates.append(candidate); seen[key] = true
	if candidates.is_empty(): return _failure(result, "UNSUPPORTED", "INCOMPATIBLE_ARGUMENTS")
	result.candidates = candidates.duplicate(true)
	result.inferred_fields = inferred.duplicate()
	if candidates.size() > 1:
		var names: Array[String] = []
		for candidate in candidates: names.append(_noun_phrase(candidate.frame, scenario))
		return _clarify(result, "AMBIGUOUS_OBJECT", candidates, "Meinst du " + " oder ".join(names) + "?")
	if needs_confirmation:
		return _clarify(result, "VERIFY_RECOVERED_MEANING", candidates, confirmation(candidates[0].frame, scenario))
	return _complete(result, candidates[0], inferred)

static func _complete(result: Dictionary, candidate: Dictionary, inferred: Array) -> Dictionary:
	result.status = "RECOGNIZED"; result.reason = "COMPOSITIONAL_MEANING"
	result.intent = candidate.intent; result.semantic = candidate.intent
	result.family = candidate.family; result.frame = candidate.frame.duplicate(true)
	result.semantic_frames = [candidate.duplicate(true)]
	result.inferred_fields = inferred.duplicate()
	result.explicit_evidence = result.normalized_tokens.duplicate()
	result.semantic_recovery_status = "COMPLETE"
	result.grammatical_error_detected = not result.diagnostics.is_empty()
	result.recovery_used = result.grammatical_error_detected or not result.repairs.is_empty()
	return result

static func _failure(result: Dictionary, status: String, reason: String) -> Dictionary:
	result.status = status; result.reason = reason
	result.semantic_recovery_status = "PARTIAL" if not result.semantic_frames.is_empty() else "NONE"
	result.notification = "Не удалось надёжно разобрать всю реплику. Попробуй одну короткую мысль."
	if not result.unknown_tokens.is_empty(): result.notification = "Неизвестные слова: " + ", ".join(result.unknown_tokens)
	return result

static func _clarify(result: Dictionary, reason: String, candidates: Array, question: String) -> Dictionary:
	result.status = "NEEDS_CLARIFICATION"; result.reason = reason
	result.candidates = candidates.duplicate(true); result.clarification = question
	result.semantic_recovery_status = "PARTIAL"
	result.notification = "Собеседник уточняет смысл реплики."
	if candidates.size() == 1: result.frame = candidates[0].frame.duplicate(true); result.family = str(candidates[0].family)
	return result

static func _noun_phrase(frame: Dictionary, scenario: Dictionary) -> String:
	var gender := str(frame.get("gender", "m"))
	var article := str(scenario.get("language", {}).get("articles_acc", {}).get(gender, "ein"))
	if str(frame.get("polarity", "")) == "negative":
		article = {"m":"keinen","f":"keine","n":"kein"}.get(gender, "kein")
	var parts: Array[String] = [article]
	for attribute in frame.get("attributes", []):
		var form := str(attribute.get("acc_forms", {}).get(gender, ""))
		if not form.is_empty(): parts.append(form)
	parts.append(str(frame.get("object_label", frame.get("object_id", "das"))))
	return " ".join(parts)

static func confirmation(frame: Dictionary, scenario: Dictionary) -> String:
	match str(frame.get("family", "")):
		"acquisition", "access", "receipt":
			var phrase := _noun_phrase(frame, scenario)
			return phrase.substr(0, 1).to_upper() + phrase.substr(1) + "?"
		"role":
			var no := str(scenario.get("language", {}).get("negative_articles", {}).get(str(frame.get("gender", "m")), "kein")) + " " if str(frame.get("polarity", "")) == "negative" else ""
			return "Du bist also " + no + str(frame.get("role_label", "")) + "?"
		"help":
			var player_actor := str(frame.get("actor", "")) == str(scenario.get("language", {}).get("participants", {}).get("speaker", "player"))
			if str(frame.get("polarity", "")) == "negative": return "Du kannst mir nicht helfen?" if player_actor else "Ich kann dir nicht helfen?"
			return "Du möchtest mir helfen?" if player_actor else "Soll ich dir helfen?"
		"repeat": return "Soll ich das wiederholen?"
		"possession": return "Du hast " + _noun_phrase(frame, scenario) + "?"
	return "Meinst du das?"
