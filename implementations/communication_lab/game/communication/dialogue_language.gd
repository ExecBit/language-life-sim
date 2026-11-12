extends RefCounted
## Deterministic, family-based analysis for the first Astera conversation.
## This class returns evidence only; LabSession owns all state changes.
const Catalog = preload("res://implementations/communication_lab/game/communication/word_catalog.gd")
const DATA_PATH := "res://implementations/communication_lab/data/communication/first_talk.json"
const SUBJECTS := ["ich", "du"]
const COPULAS := ["bin", "bist", "ist"]
const HELP_WORDS := ["helfen", "helfe", "hilfst", "hilft"]
const STATE_MODIFIERS := ["sehr", "auch", "heute", "jetzt", "ein", "bisschen"]
const HELP_ALLOWED := ["ich", "du", "mir", "dir", "kann", "kannst", "können", "kannst", "helfen", "helfe", "hilfst", "hilft", "nicht", "bitte", "heute", "hallo", "hi"]
static var _cached_data: Dictionary = {}

static func data() -> Dictionary:
	if _cached_data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_cached_data = parsed
		else:
			push_error("Could not read Communication Lab conversation data: %s" % DATA_PATH)
	return _cached_data

static func analyze(text: String, context: Dictionary) -> Dictionary:
	var rows := _token_rows(text)
	var tokens: Array[String] = []
	for row in rows:
		tokens.append(str(row.surface).to_lower())
	var result := _base_result(text, tokens, rows)
	if tokens.is_empty():
		return result
	if _multiple_intents(text, tokens):
		result.handled = true
		result.status = "UNSUPPORTED"
		result.reason = "MULTIPLE_INTENTS"
		result.unsupported_features.append("MULTIPLE_INTENTS")
		result.semantic_frames = _rough_component_frames(tokens)
		result.notification = "Попробуйте сказать по одной мысли."
		return result
	if tokens[0] in ["ja", "nein"]:
		var short_answer_shape := true
		for token in tokens.slice(1):
			if token not in ["bitte","danke"]:
				short_answer_shape = false
		if short_answer_shape:
			result.handled = true
			result.status = "RECOGNIZED"
			result.intent = "SHORT_YES" if tokens[0] == "ja" else "SHORT_NO"
			result.family = "short_answer"
			result.frame.speech_act = "answer"
			result.frame.polarity = "positive" if tokens[0] == "ja" else "negative"
			return result
	var help_result := _analyze_help(result, tokens, context)
	if not help_result.is_empty():
		return help_result
	var state_result := _analyze_state(result, tokens, context)
	if not state_result.is_empty():
		return state_result
	if bool(context.get("awaiting_name", false)):
		var name_result := _analyze_name(result, tokens, rows)
		if not name_result.is_empty():
			return name_result
		if _looks_like_name_input(tokens):
			result.handled = true
			result.status = "NEEDS_CLARIFICATION"
			result.family = "introduction"
			result.reason = "NAME_CONTINUATION"
			result.notification = "Астера не поняла продолжение имени. Назовите только имя."
			return result
	elif _looks_like_closed_name(tokens) and not (tokens.size() == 1 and text_ends_with_question(text)):
		result.handled = true
		result.status = "UNKNOWN"
		result.family = "introduction"
		result.reason = "NAME_SLOT_CLOSED"
		result.notification = "Имя принимается только в начале разговора. Выберите тему или задайте другой вопрос."
		return result
	if _contains_p67_signal(tokens):
		result.handled = true
		result.status = "UNKNOWN"
		result.reason = "UNSUPPORTED_CONSTRUCTION"
		result.notification = "Астера не поняла эту конструкцию. Попробуйте сказать иначе."
	return result

static func _base_result(text: String, tokens: Array[String], rows: Array) -> Dictionary:
	var readings: Array = []
	var unknown_tokens: Array[String] = []
	for i in rows.size():
		var surface := str(rows[i].surface)
		var normalized := surface.to_lower()
		var catalog_readings: Array = Catalog.lookup(normalized)
		var state_reading := _state_reading(normalized)
		var custom_reading := _vocabulary_reading(normalized)
		var token_readings: Array = catalog_readings
		if token_readings.is_empty() and not state_reading.is_empty():
			token_readings = [state_reading]
		if token_readings.is_empty() and not custom_reading.is_empty():
			token_readings = [custom_reading]
		if token_readings.is_empty():
			token_readings = [{"surface":surface,"pos":"unknown","semantic_id":"unknown","availability":"unsupported"}]
			unknown_tokens.append(normalized)
		readings.append({"token":normalized,"surface":surface,"position":int(rows[i].position),"readings":token_readings})
	return {
		"handled":false,"status":"UNHANDLED","intent":"","semantic":"","family":"","reason":"",
		"raw_input":text,"normalized_tokens":tokens.duplicate(),"lexical_readings":readings,
		"ambiguity":[],"unsupported_features":[],"unknown_tokens":unknown_tokens,"diagnostics":[],
		"semantic_frames":[],"notification":"",
		"frame":{"speaker":"player","subject":"unresolved","actor":"unresolved","recipient":"unresolved",
			"helper":"unresolved","help_recipient":"unresolved","experiencer":"unresolved","predicate":"",
			"action":"","state_id":"","polarity":"unresolved","modality":"none","speech_act":"unresolved",
			"negation_scope":"","question_type":""}
	}

static func _analyze_state(result: Dictionary, tokens: Array[String], context: Dictionary) -> Dictionary:
	var found: Array[Dictionary] = []
	for i in tokens.size():
		var state := _state_for(tokens[i])
		if not state.is_empty():
			found.append({"index":i,"id":str(state.id),"token":tokens[i],"data":state})
	if found.is_empty():
		return {}
	result.handled = true
	result.family = "state_report"
	result.frame.action = "report_state"
	result.frame.predicate = "state"
	if found.size() > 1:
		result.status = "UNSUPPORTED"
		result.reason = "MULTIPLE_STATE_VALUES"
		result.unsupported_features.append("MULTIPLE_INTENTS")
		result.semantic_frames = found
		result.notification = "Попробуйте сказать по одной мысли."
		return result
	var state_item: Dictionary = found[0]
	var state_id := str(state_item.id)
	var allowed := ["ich","du","bin","bist","ist","nicht",state_item.token,"hallo","hi"] + STATE_MODIFIERS
	var unsupported := _unsupported_tokens(tokens, allowed)
	if not unsupported.is_empty():
		return _mark_unsupported_tokens(result, unsupported)
	var actor_tokens: Array[String] = []
	for token in tokens:
		if token in SUBJECTS:
			actor_tokens.append(token)
	if actor_tokens.size() > 1:
		result.status = "UNSUPPORTED"
		result.reason = "MULTIPLE_PARTICIPANTS"
		result.unsupported_features.append("MULTIPLE_INTENTS")
		result.notification = "Попробуйте сказать по одной мысли."
		return result
	var body: Array[String] = tokens.duplicate()
	while not body.is_empty() and body[0] in ["hallo", "hi"]:
		body.pop_front()
	var leading_time := ""
	if not body.is_empty() and body[0] in ["heute", "jetzt"]:
		leading_time = body.pop_front()
	var state_tail: Dictionary = {}
	result.frame.state_id = state_id
	result.frame.speech_act = "statement"
	if actor_tokens.is_empty():
		var subjectless_tail := body
		if not subjectless_tail.is_empty() and subjectless_tail[0] in COPULAS:
			subjectless_tail = subjectless_tail.slice(1)
		state_tail = _state_tail(subjectless_tail, str(state_item.token), leading_time)
		if not bool(state_tail.get("valid", false)):
			var subjectless_unknown: Array[String] = []
			for token in state_tail.get("unknown", []): subjectless_unknown.append(str(token))
			return _mark_unsupported_tokens(result, subjectless_unknown)
		var subjectless_polarity := "negative" if bool(state_tail.get("negative", false)) else "positive"
		result.status = "NEEDS_CLARIFICATION"
		result.reason = "MISSING_EXPERIENCER"
		result.ambiguity.append("MISSING_EXPERIENCER")
		result.frame.experiencer = "unresolved"
		result.frame.polarity = subjectless_polarity
		result.clarification_candidate = {"intent":"REPORT_STATE","experiencer":"player","state_id":state_id,"polarity":subjectless_polarity,"source":"topic_guided_question"}
		result.notification = "Астера не поняла, о ком вы говорите."
		return result
	var actor := actor_tokens[0]
	var subject_index := body.find(actor)
	var copula := ""
	var inverted := not leading_time.is_empty()
	if inverted:
		if body.size() < 3 or body[0] not in COPULAS or body[1] != actor:
			return _mark_unsupported_tokens(result, [])
		copula = body[0]
		subject_index = 1
	else:
		if subject_index != 0:
			return _mark_unsupported_tokens(result, [])
		if body.size() > 1 and body[1] in COPULAS:
			copula = body[1]
	var expected_copula := "bin" if actor == "ich" else "bist"
	if not copula.is_empty():
		var actual_copula_index := 0 if inverted else 1
		if not inverted and (body.size() <= 1 or body[1] not in COPULAS):
			actual_copula_index = -1
		if actual_copula_index < 0:
			copula = ""
	elif inverted:
		return _mark_unsupported_tokens(result, [])
	var tail_start := subject_index + 1
	if not copula.is_empty() and not inverted:
		tail_start += 1
	state_tail = _state_tail(body.slice(tail_start), str(state_item.token), leading_time)
	if not bool(state_tail.get("valid", false)):
		var state_unknown: Array[String] = []
		for token in state_tail.get("unknown", []): state_unknown.append(str(token))
		return _mark_unsupported_tokens(result, state_unknown)
	var negative := bool(state_tail.get("negative", false))
	var experiencer := "player" if actor == "ich" else "astera"
	result.frame.subject = experiencer
	result.frame.actor = experiencer
	result.frame.experiencer = experiencer
	result.intent = "REPORT_STATE" if experiencer == "player" else "REPORT_ASTERA_STATE"
	result.semantic = result.intent
	if not copula.is_empty():
		if copula != expected_copula:
			result.diagnostics.append({"code":"AGREEMENT_MISMATCH","token":copula,"expected":expected_copula,"field":"finite_verb"})
	elif not negative:
		result.diagnostics.append({"code":"OMITTED_COPULA","field":"finite_verb"})
	result.frame.polarity = "negative" if negative else "positive"
	result.frame.negation_scope = "state" if negative else ""
	result.status = "RECOGNIZED"
	result.recovery_used = not result.diagnostics.is_empty()
	result.grammatical_error_detected = not result.diagnostics.is_empty()
	result.semantic_recovery_status = "COMPLETE"
	result.state_id = state_id
	result.polarity = result.frame.polarity
	return result

static func _state_tail(tokens: Array[String], state_form: String, leading_time: String = "") -> Dictionary:
	var state_index := tokens.find(state_form)
	if state_index < 0 or tokens.find(state_form, state_index + 1) >= 0:
		return {"valid":false,"unknown":[]}
	var negative := false
	var seen_modifiers := {}
	var modifier_phase := 1 if not leading_time.is_empty() else 0
	var time_seen := not leading_time.is_empty()
	if time_seen: seen_modifiers[leading_time] = true
	var index := 0
	while index < state_index:
		var token := tokens[index]
		if token == "nicht":
			if negative or modifier_phase > 1: return {"valid":false,"unknown":[]}
			negative = true
			modifier_phase = 2
		elif token in ["sehr", "auch", "heute", "jetzt"]:
			if seen_modifiers.has(token): return {"valid":false,"unknown":[]}
			if token in ["heute", "jetzt"]:
				if time_seen or modifier_phase > 1: return {"valid":false,"unknown":[]}
				modifier_phase = 1
				time_seen = true
			else:
				if modifier_phase >= 3: return {"valid":false,"unknown":[]}
				modifier_phase = 3
			seen_modifiers[token] = true
		elif token == "ein":
			if modifier_phase >= 3 or index + 1 >= state_index or tokens[index + 1] != "bisschen" or seen_modifiers.has("ein_bisschen"):
				return {"valid":false,"unknown":[]}
			seen_modifiers["ein_bisschen"] = true
			modifier_phase = 3
			index += 1
		elif token in ["bisschen", "ich", "du", "bin", "bist", "ist"]:
			return {"valid":false,"unknown":[]}
		else:
			return {"valid":false,"unknown":[token]}
		index += 1
	var trailing_time := ""
	for token in tokens.slice(state_index + 1):
		if token not in ["heute", "jetzt"] or time_seen or not trailing_time.is_empty():
			return {"valid":false,"unknown":[]}
		trailing_time = token
	return {"valid":true,"negative":negative}

static func _analyze_help(result: Dictionary, tokens: Array[String], context: Dictionary) -> Dictionary:
	var has_help := false
	for token in tokens:
		if token in HELP_WORDS:
			has_help = true
			break
	if not has_help:
		return {}
	result.handled = true
	result.family = "help"
	result.frame.action = "help"
	result.frame.predicate = "help"
	var actor_tokens: Array[String] = []
	var recipient_tokens: Array[String] = []
	for token in tokens:
		if token in SUBJECTS:
			actor_tokens.append(token)
		elif token == "dir":
			recipient_tokens.append("astera")
		elif token == "mir":
			recipient_tokens.append("player")
	var unsupported := _unsupported_tokens(tokens, HELP_ALLOWED)
	var actor := "player" if actor_tokens.size() == 1 and actor_tokens[0] == "ich" else ("astera" if actor_tokens.size() == 1 else "unresolved")
	var recipient := recipient_tokens[0] if recipient_tokens.size() == 1 else "unresolved"
	if not unsupported.is_empty():
		result.frame.actor = actor
		result.frame.helper = actor
		result.frame.recipient = recipient
		result.frame.help_recipient = recipient
		result.frame.polarity = "negative" if tokens.has("nicht") else "unresolved"
		return _mark_unsupported_tokens(result, unsupported)
	if actor_tokens.size() > 1 or recipient_tokens.size() > 1:
		result.status = "NEEDS_CLARIFICATION"
		result.reason = "AMBIGUOUS_ROLES"
		result.ambiguity.append("AMBIGUOUS_ROLES")
		result.notification = "Астера не поняла участников помощи."
		return result
	result.frame.actor = actor
	result.frame.helper = actor
	result.frame.recipient = recipient
	result.frame.help_recipient = recipient
	result.frame.subject = actor
	result.frame.modality = "ability" if tokens.has("kann") or tokens.has("kannst") or tokens.has("können") else "none"
	result.frame.speech_act = "question" if text_ends_with_question(result.raw_input) or tokens[0] in ["kann","kannst"] else "statement"
	var negative := tokens.has("nicht")
	result.frame.polarity = "negative" if negative else "positive"
	result.frame.negation_scope = "help" if negative else ""
	if actor == "player" and recipient == "astera":
		result.intent = "PLAYER_CANNOT_HELP" if negative else "OFFER_HELP"
	elif actor == "astera" and recipient == "player":
		result.intent = "REQUEST_HELP" if not negative else "REQUEST_HELP_NEGATED"
	else:
		result.intent = ""
	result.semantic = result.intent
	if actor == "player" and recipient == "player" or actor == "astera" and recipient == "astera":
		result.status = "NEEDS_CLARIFICATION"
		result.reason = "CONTRADICTORY_HELP_ROLES"
		result.ambiguity.append("CONTRADICTORY_HELP_ROLES")
		result.notification = "Астера не поняла участников помощи."
		return result
	if actor != "unresolved" and recipient != "unresolved":
		result.status = "RECOGNIZED"
		if not tokens.has("kann") and not tokens.has("kannst") and not tokens.has("können"):
			result.diagnostics.append({"code":"OMITTED_MODAL","field":"modality"})
			result.recovery_used = true
			result.grammatical_error_detected = true
			result.semantic_recovery_status = "COMPLETE"
		return result
	result.status = "NEEDS_CLARIFICATION"
	if actor == "unresolved":
		result.reason = "MISSING_HELPER"
		result.ambiguity.append("MISSING_HELPER")
		result.notification = str(data().help_replies.get("clarify_helper_notice","Астера не поняла, кто должен помочь."))
	elif recipient == "unresolved":
		result.reason = "MISSING_RECIPIENT"
		result.ambiguity.append("MISSING_RECIPIENT")
		result.notification = str(data().help_replies.get("clarify_recipient_notice","Астера не поняла, кому вы хотите помочь."))
	var proposal_actor := actor
	var proposal_recipient := recipient
	if proposal_actor == "unresolved" and str(context.get("selected_topic","")) == "help":
		proposal_actor = "player"
		proposal_recipient = "astera"
	elif proposal_actor == "player" and proposal_recipient == "unresolved":
		proposal_recipient = "astera"
	elif proposal_actor == "astera" and proposal_recipient == "unresolved":
		proposal_recipient = "player"
	if not negative and proposal_actor != "unresolved" and proposal_recipient != "unresolved" and proposal_actor != proposal_recipient:
		var proposal_intent := "OFFER_HELP" if proposal_actor == "player" else "REQUEST_HELP"
		result.clarification_candidate = {"intent":proposal_intent,"actor":proposal_actor,"recipient":proposal_recipient,
			"polarity":"positive","question_kind":"yes_no","source":"possible_addressee"}
	return result

static func _analyze_name(result: Dictionary, tokens: Array[String], rows: Array) -> Dictionary:
	var offset := 0
	while offset < tokens.size() and tokens[offset] in ["hallo", "hi"]:
		offset += 1
	var body: Array[String] = tokens.slice(offset)
	if body.size() == 4 and body[0] == "ich" and body[1] in ["bin","heiße","heisse"] and body[2] == "nicht":
		var rejected := str(body[3])
		if _state_for(rejected).is_empty():
			result.handled = true
			result.status = "NEEDS_CLARIFICATION"
			result.family = "introduction"
			result.intent = "NEGATED_NAME"
			result.reason = "NEGATED_NAME"
			result.frame.subject = "player"
			result.frame.actor = "player"
			result.frame.polarity = "negative"
			result.frame.speech_act = "statement"
			result.frame.name_candidate = rejected
			result.notification = "Астера не записала имя по отрицательной фразе. Назовите имя без nicht."
			return result
	var name_index := -1
	if body.size() == 1:
		name_index = offset
	elif body.size() == 3 and body[0] == "ich" and body[1] in ["bin","heiße","heisse"]:
		name_index = offset + 2
	if body.size() == 1 and text_ends_with_question(result.raw_input):
		return {}
	if name_index < 0:
		return {}
	var candidate := tokens[name_index]
	if not _state_for(candidate).is_empty() or candidate in CONTROL_WORDS:
		return {}
	var readings: Array = Catalog.lookup(candidate)
	if not readings.is_empty():
		var proper := false
		for reading in readings:
			if str(reading.get("pos","")) == "proper_noun":
				proper = true
		if not proper:
			return {}
	var raw_name := str(rows[name_index].surface) if tokens.size() == 1 else str(rows[name_index].surface)
	var display_name := raw_name.substr(0,1).to_upper() + raw_name.substr(1).to_lower()
	result.handled = true
	result.status = "RECOGNIZED"
	result.family = "introduction"
	result.intent = "PLAYER_NAME"
	result.semantic = "PLAYER_NAME"
	result.name = display_name
	result.name_source = "open_name_slot"
	var lexical_readings: Array = result.get("lexical_readings", [])
	if name_index < lexical_readings.size():
		var name_evidence: Dictionary = lexical_readings[name_index].duplicate(true)
		name_evidence.readings = [{"lemma_id":"player_name","surface":str(rows[name_index].surface),
			"pos":"proper_noun","features":{"slot":"open_player_name"},"semantic_id":"player_name","availability":"available"}]
		lexical_readings[name_index] = name_evidence
		result.lexical_readings = lexical_readings
	result.frame.subject = "player"
	result.frame.actor = "player"
	result.frame.predicate = "name"
	result.frame.action = "introduce"
	result.frame.name = display_name
	result.frame.polarity = "positive"
	result.frame.speech_act = "statement"
	return result

static func _looks_like_name_input(tokens: Array[String]) -> bool:
	var offset := 0
	while offset < tokens.size() and tokens[offset] in ["hallo", "hi"]:
		offset += 1
	var body: Array[String] = tokens.slice(offset)
	return body.size() >= 3 and body[0] == "ich" and body[1] in ["bin","heiße","heisse"]

static func _looks_like_closed_name(tokens: Array[String]) -> bool:
	var offset := 0
	while offset < tokens.size() and tokens[offset] in ["hallo", "hi"]:
		offset += 1
	var body: Array[String] = tokens.slice(offset)
	var candidate := ""
	if body.size() == 1:
		candidate = body[0]
	elif body.size() == 3 and body[0] == "ich" and body[1] in ["bin","heiße","heisse"]:
		candidate = body[2]
	elif body.size() == 4 and body[0] == "ich" and body[1] in ["bin","heiße","heisse"] and body[2] == "nicht":
		candidate = body[3]
	else:
		return false
	if not _state_for(candidate).is_empty() or candidate in CONTROL_WORDS:
		return false
	var readings: Array = Catalog.lookup(candidate)
	if readings.is_empty():
		return true
	for reading in readings:
		if str(reading.get("pos","")) == "proper_noun":
			return true
	return false

static func _contains_p67_signal(tokens: Array[String]) -> bool:
	for token in tokens:
		if token in HELP_WORDS or not _state_for(token).is_empty():
			return true
	return false

static func _multiple_intents(text: String, tokens: Array[String]) -> bool:
	if tokens == ["und","du"]:
		return false
	var intent_text := text.strip_edges()
	if not tokens.is_empty() and tokens[0] in ["hallo","hi"]:
		var greeting_prefix := RegEx.new()
		greeting_prefix.compile("(?i)^\\s*(hallo|hi)[!?.]*\\s*")
		var greeting_match := greeting_prefix.search(intent_text)
		if greeting_match != null:
			intent_text = intent_text.substr(greeting_match.get_end()).strip_edges()
	var punctuation := RegEx.new()
	punctuation.compile("[.!?;:]+")
	for found in punctuation.search_all(intent_text):
		var after := intent_text.substr(found.get_end()).strip_edges()
		if not after.is_empty() and not _token_rows(after).is_empty():
			return true
	for i in tokens.size() - 1:
		if tokens[i] == "und" and tokens[i + 1] in SUBJECTS:
			return true
	return false

static func _rough_component_frames(tokens: Array[String]) -> Array:
	var frames: Array = []
	var state_ids: Array[String] = []
	for token in tokens:
		var state := _state_for(token)
		if not state.is_empty() and state.id not in state_ids:
			state_ids.append(str(state.id))
			frames.append({"family":"state_report","state_id":str(state.id)})
	var has_help := false
	for token in tokens:
		if token in HELP_WORDS:
			has_help = true
			break
	if has_help:
		frames.append({"family":"help","action":"help"})
	return frames

static func _mark_unsupported_tokens(result: Dictionary, unsupported: Array[String]) -> Dictionary:
	result.status = "UNKNOWN"
	result.reason = "UNSUPPORTED_CONTINUATION" if not unsupported.is_empty() else "UNSUPPORTED_WORD_ORDER"
	result.unknown_tokens = unsupported.duplicate()
	for token in unsupported:
		result.diagnostics.append({"code":"UNSUPPORTED_TOKEN","token":token})
	if unsupported.is_empty():
		result.diagnostics.append({"code":"UNSUPPORTED_WORD_ORDER"})
		result.notification = "Астера не поняла порядок слов. Попробуйте сказать иначе."
	else:
		result.notification = "Астера не поняла продолжение „%s“. Попробуйте выразиться иначе." % unsupported[0]
	return result

static func _unsupported_tokens(tokens: Array[String], allowed: Array) -> Array[String]:
	var result: Array[String] = []
	for token in tokens:
		if token not in allowed and token not in result:
			result.append(token)
	return result

static func _tokens_outside(tokens: Array[String], allowed: Array) -> Array[String]:
	return _unsupported_tokens(tokens, allowed)

static func _state_for(token: String) -> Dictionary:
	var normalized := token.to_lower()
	for state_id in data().get("states",{}):
		var state: Dictionary = data().states[state_id]
		for form in state.get("forms",[]):
			if str(form).to_lower() == normalized:
				return {"id":str(state_id),"forms":state.get("forms",[]),"translation":state.get("translation","")}
	return {}

static func _state_reading(token: String) -> Dictionary:
	var state := _state_for(token)
	if state.is_empty():
		return {}
	return {"lemma_id":str(state.id),"surface":token,"pos":"adjective","features":{},
		"semantic_id":str(state.id),"availability":"available","translation":str(state.translation)}

static func _vocabulary_reading(token: String) -> Dictionary:
	for entry in data().get("vocabulary",[]):
		if str(entry.surface).to_lower() == token.to_lower():
			return {"lemma_id":str(entry.get("semantic_id",token)),"surface":str(entry.surface),"pos":str(entry.pos),
				"features":{},"semantic_id":str(entry.get("semantic_id",token)),"availability":"available",
				"translation":str(entry.translation)}
	return {}

static func _known(token: String) -> bool:
	if token in CONTROL_WORDS:
		return true
	if not _state_for(token).is_empty() or not _vocabulary_reading(token).is_empty():
		return true
	return Catalog.available_for_input(token)

static func _token_rows(text: String) -> Array:
	var rows: Array = []
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}]+")
	for found in regex.search_all(text):
		rows.append({"surface":found.get_string(),"position":found.get_start()})
	return rows

static func text_ends_with_question(text: String) -> bool:
	return text.strip_edges().ends_with("?")

static func suggestions(prefix: String) -> Array[String]:
	var result: Array[String] = []
	var normalized := prefix.to_lower()
	for entry in vocabulary_entries():
		if entry.pos == "phrase":
			continue
		var surface := str(entry.surface)
		if surface.to_lower().begins_with(normalized) and surface not in result:
			result.append(surface)
	result.sort()
	return result

static func vocabulary_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in data().get("vocabulary",[]):
		result.append({"lemma_id":str(entry.get("semantic_id",entry.surface)),"surface":str(entry.surface),
			"pos":str(entry.pos),"features":{},"semantic_id":str(entry.get("semantic_id",entry.surface)),
			"availability":"available"})
	for state_id in data().get("states",{}):
		var state: Dictionary = data().states[state_id]
		for form in state.get("forms",[]):
			result.append({"lemma_id":str(state_id),"surface":str(form),"pos":"adjective","features":{},
				"semantic_id":str(state_id),"availability":"available"})
	for construction in data().get("constructions",[]):
		result.append({"lemma_id":"construction","surface":str(construction.surface),"pos":"phrase","features":{},
			"semantic_id":"construction","availability":"available"})
	return result

static func translation_for(surface: String) -> String:
	var normalized := surface.strip_edges().to_lower()
	for entry in data().get("vocabulary",[]):
		if str(entry.surface).to_lower() == normalized:
			return str(entry.translation)
	for state_id in data().get("states",{}):
		var state: Dictionary = data().states[state_id]
		for form in state.get("forms",[]):
			if str(form).to_lower() == normalized:
				return str(state.translation)
	for construction in data().get("constructions",[]):
		if str(construction.surface).to_lower() == normalized:
			return str(construction.translation)
	return ""

const CONTROL_WORDS := {
	"ich":true,"du":true,"mir":true,"dir":true,"bin":true,"bist":true,"ist":true,
	"heisse":true,"heiße":true,"kann":true,"kannst":true,"können":true,"helfen":true,
	"helfe":true,"hilfst":true,"hilft":true,"nicht":true,"ja":true,"nein":true,
	"und":true,"bitte":true,"heute":true,"jetzt":true,"sehr":true,"auch":true,"ein":true,"bisschen":true
}
