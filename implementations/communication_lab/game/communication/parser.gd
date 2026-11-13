extends RefCounted
## Pure shallow grammar; world preconditions are resolved separately.
const Catalog = preload("res://implementations/communication_lab/game/communication/word_catalog.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")

static func suggestions(prefix: String) -> Array[String]:
	var result := Catalog.suggestions(prefix)
	for surface in DialogueGrammar.suggestions(prefix):
		if surface not in result: result.append(surface)
	result.sort()
	return result

static func parse(text: String, pointed_target := "", conversation: Dictionary = {}) -> Dictionary:
	var r := {"status":"UNKNOWN", "intent":"", "ambiguity":[], "unsupported_features":[],
		"diagnostics":[], "normalized_tokens":[], "lexical_readings":[],
		"frame": {"speaker":"player", "subject":"unresolved",
			"addressee":conversation.get("addressee","addressee"), "predicate":"",
			"action":"", "object_id":"", "polarity":"unresolved", "modality":"none",
			"speech_act":"unresolved", "target_id":"", "negation_scope":"", "question_type":""}}
	var regex := RegEx.new()
	regex.compile("[\\p{L}\\p{N}_]+|[^\\s]")
	var tokens: Array[String] = []
	var unknown := false
	var vocative := false
	var boundary := false
	var multiple_clauses := false
	for match_result in regex.search_all(text):
		var token: String = match_result.get_string().to_lower()
		if token in ["?","!",".",",",";",":"]:
			if token == "," and tokens.size() == 1 and _actor(tokens[0],r.frame.addressee) == r.frame.addressee: vocative = true
			if token in ["?","!",".",";",":"] and not tokens.is_empty(): boundary = true
			continue
		if boundary: multiple_clauses = true
		var readings: Array = Catalog.lookup(token)
		r.lexical_readings.append({"token":token,"position":match_result.get_start(),"readings":readings})
		if readings.is_empty():
			unknown = true
			r.diagnostics.append({"code":"UNKNOWN_TOKEN","token":token,"position":match_result.get_start()})
		tokens.append(token)
	r.normalized_tokens = tokens.duplicate()
	if not tokens.is_empty():
		r.frame.subject = _actor(tokens[0],r.frame.addressee)
	if unknown: return _done(r)
	if tokens.is_empty(): return _clarify(r,"EMPTY_INPUT")
	var clause_index := tokens.size()
	for marker in ["dass","weil"]:
		var index := tokens.find(marker)
		if index >= 0: clause_index = mini(index,clause_index)
	var main: Array[String] = []
	main.assign(tokens.slice(0,clause_index))
	_structure(r,main,str(conversation.get("pointed_object_id",pointed_target)),conversation,text.contains("?"),vocative)
	if "das" in tokens and pointed_target != "" and r.frame.object_id == conversation.get("pointed_object_id",pointed_target):
		r.frame.target_id = pointed_target
	if clause_index < tokens.size() or multiple_clauses:
		r.status = "UNSUPPORTED"
		r.intent = ""
		r.unsupported_features.append("SUBORDINATE_CLAUSE" if clause_index < tokens.size() else "MULTIPLE_CLAUSES")
	return _done(r)

static func _done(r: Dictionary) -> Dictionary:
	# Compatibility view for the existing scene. Status gates every world effect.
	r.target = "door" if r.frame.object_id == "room" else r.frame.object_id
	r.subject = r.frame.subject
	r.negative = r.frame.polarity == "negative"
	r.modal = r.frame.modality != "none"
	r.question = r.frame.speech_act == "question"
	r.tokens = r.normalized_tokens
	return r

static func _clarify(r: Dictionary, reason: String) -> Dictionary:
	r.status = "NEEDS_CLARIFICATION"
	r.intent = ""
	r.ambiguity.append(reason)
	return _done(r)

static func _unsupported(r: Dictionary, feature: String) -> void:
	r.status = "UNSUPPORTED"
	r.intent = ""
	r.unsupported_features.append(feature)

static func _recognized(r: Dictionary, intent: String, act: String) -> void:
	r.status = "RECOGNIZED"
	r.intent = intent
	r.frame.speech_act = act

static func _lemma(token: String, pos := "") -> String:
	for entry in Catalog.lookup(token):
		if pos == "" or entry.pos == pos: return entry.semantic_id
	return ""

static func _nominal(words: Array, pointed: String) -> Dictionary:
	var n := {"valid":true,"object_id":"","negative":false,"reference":false,"diagnostics":[]}
	var body := words.duplicate()
	var determiner := false
	if not body.is_empty() and _lemma(body[0],"determiner") != "":
		determiner = true
		n.negative = _lemma(body[0],"determiner") == "no"
		body.pop_front()
	# 'das' has both article and demonstrative readings in the catalog.
	if words == ["das"]:
		n.reference = true
		n.object_id = pointed
		return n
	if body.size() != 1 or _lemma(body[0],"noun") == "":
		n.valid = body.is_empty() and not determiner
		return n
	n.object_id = _lemma(body[0],"noun")
	if not determiner: n.diagnostics.append("OMITTED_ARTICLE")
	elif words[0] in ["der","die","den","das","ein","eine"]:
		var expected: Array = {"key":["der","den","ein"],"door":["die","eine"],"room":["das","ein"]}.get(n.object_id,[])
		if words[0] not in expected: n.diagnostics.append("ARTICLE_MISMATCH")
	return n

static func _description(words: Array, pointed: String) -> Dictionary:
	var d := {"valid":true,"action":"","object_id":"","negative":false,
		"negation_scope":"","recipient":"","reference":false,"diagnostics":[]}
	var body := words.duplicate()
	# Negation belongs to this predicate or its noun phrase, never to the whole input.
	if not body.is_empty() and body[0] == "nicht":
		d.negative = true
		body.pop_front()
	if not body.is_empty() and body[-1] == "nicht":
		if d.negative: d.valid = false
		d.negative = true
		body.pop_back()
	if not body.is_empty() and _lemma(body[-1],"verb") in ["open","give","help"]:
		d.action = _lemma(body.pop_back(),"verb")
	if not body.is_empty() and body[-1] == "nicht":
		if d.negative: d.valid = false
		d.negative = true
		body.pop_back()
	if "nicht" in body:
		d.valid = false
		return d
	if "mir" in body or "dir" in body:
		var dative := "mir" if "mir" in body else "dir"
		d.recipient = "player" if dative == "mir" else "addressee"
		body.erase(dative)
	var n := _nominal(body,pointed)
	d.valid = d.valid and n.valid
	d.object_id = n.object_id
	d.reference = n.reference
	d.diagnostics = n.diagnostics
	if d.negative and n.negative: d.valid = false
	d.negative = d.negative or n.negative
	if d.negative: d.negation_scope = "object" if n.negative else "predicate"
	return d

static func _apply_description(r: Dictionary, d: Dictionary) -> void:
	r.frame.action = d.action
	r.frame.object_id = d.object_id
	r.frame.target_id = "door" if d.object_id == "room" else d.object_id
	r.frame.polarity = "negative" if d.negative else "positive"
	r.frame.negation_scope = d.negation_scope
	r.diagnostics.append_array(d.diagnostics)

static func _actor(token: String, addressee: String) -> String:
	if token == "ich": return "player"
	if token == "du": return addressee
	for entry in Catalog.lookup(token):
		if entry.pos == "proper_noun": return entry.semantic_id
	return "unresolved"

static func _structure(r: Dictionary, input: Array[String], pointed: String, conversation: Dictionary, question: bool, vocative: bool) -> void:
	var t := input.duplicate()
	var npc: String = r.frame.addressee
	r.frame.polarity = "positive"
	if t.is_empty():
		_clarify(r,"INCOMPLETE_CLAUSE")
		return
	if _actor(t[0],npc) == npc and t[0] != "du" and (vocative or (t.size() > 1 and t[1] in ["ich","du","öffne","gib","hilf","kannst"])):
		r.frame.addressee = npc
		t.pop_front()
	var polite := "bitte" in t
	while "bitte" in t: t.erase("bitte")
	if not t.is_empty() and _lemma(t[0],"social") in ["greeting","thanks"]:
		if t.size() == 1 or (t.size() == 2 and _actor(t[1],npc) == npc):
			r.frame.subject = "player"
			_recognized(r,"GREETING" if _lemma(t[0],"social") == "greeting" else "THANKS","statement")
		else: _clarify(r,"ADDRESSEE_OR_SOCIAL_STRUCTURE")
		return
	if t in [["ja"],["nein"]]:
		r.frame.subject = "player"
		if conversation.get("active",false) and (conversation.get("pending","") in ["help_offer","offer"] or conversation.get("offer_pending",false)):
			_recognized(r,"ACCEPT" if t[0] == "ja" else "REFUSE","statement")
		else: _clarify(r,"NO_ACTIVE_OFFER")
		return
	if t.size() == 1 and _lemma(t[0],"social") in ["farewell","apology","politeness"]:
		r.frame.subject = "player"
		_recognized(r,{"farewell":"FAREWELL","apology":"APOLOGY","politeness":"POLITENESS"}[_lemma(t[0],"social")],"statement")
		return
	if t == ["noch","einmal"]:
		r.frame.subject = "player"
		r.frame.predicate = "repeat"
		_recognized(r,"REQUEST_REPEAT","request")
		return
	if t.is_empty() and polite:
		r.frame.subject = "player"
		_recognized(r,"POLITENESS","statement")
		return
	if t.is_empty():
		_clarify(r,"MISSING_PREDICATE")
		return
	# Information questions consume the complete noun phrase, not just a keyword.
	if t[0] in ["wo","warum","was"]:
		var wh: String = t.pop_front()
		r.frame.question_type = _lemma(wh,"interrogative")
		r.frame.subject = "unresolved"
		r.frame.predicate = "be"
		r.frame.speech_act = "question"
		if not t.is_empty() and t[0] == "ist": t.pop_front()
		else: r.diagnostics.append("OMITTED_COPULA")
		if wh == "warum" and not t.is_empty() and t[-1] == "zu": t.pop_back()
		var n := _description(t,pointed)
		_apply_description(r,n)
		if not n.valid or n.negative or n.action != "": _unsupported(r,"QUESTION_STRUCTURE")
		elif n.object_id == "": _clarify(r,"MISSING_REFERENCE")
		else: _recognized(r,{"wo":"ASK_LOCATION","warum":"ASK_REASON","was":"IDENTIFY"}[wh],"question")
		return
	var subject := "unresolved"
	var inverted := false
	if _actor(t[0],npc) != "unresolved":
		subject = _actor(t.pop_front(),npc)
	elif t.size() > 1 and _lemma(t[0],"verb") in ["can","want","need","have","be"] and _actor(t[1],npc) != "unresolved":
		subject = _actor(t[1],npc)
		t.remove_at(1)
		inverted = true
	r.frame.subject = subject
	r.frame.speech_act = "question" if question or inverted else "statement"
	if t.is_empty():
		_clarify(r,"MISSING_PREDICATE")
		return
	var head: String = t[0]
	var predicate := _lemma(head,"verb")
	var imperative := subject == "unresolved" and head in ["öffne","gib","hilf"]
	if predicate != "": t.pop_front()
	r.frame.predicate = predicate
	if predicate in ["want","need","can"]:
		r.frame.modality = predicate
		if subject == "unresolved" and predicate in ["want","need"]:
			subject = "player"
			r.frame.subject = subject
			r.diagnostics.append("OMITTED_SUBJECT")
	var d := _description(t,pointed)
	if predicate in ["open","give","help"]:
		if d.action != "": d.valid = false
		d.action = predicate
	_apply_description(r,d)
	if not d.valid:
		_clarify(r,"CONFLICTING_STRUCTURE_OR_SCOPE")
		return
	if predicate != "" and subject != "unresolved" and not imperative:
		var expected_person := 1 if subject == "player" else (2 if input.has("du") else 3)
		var agrees := false
		for entry in Catalog.lookup(head):
			if entry.pos == "verb" and expected_person in entry.features.get("persons",[]): agrees = true
		if not agrees: r.diagnostics.append("AGREEMENT_MISMATCH")
	if imperative:
		r.frame.subject = npc
		if d.negative: _recognized(r,"PROHIBIT_ACTION","prohibition")
		elif predicate == "help" and d.object_id == "" and d.recipient in ["","player"]: _recognized(r,"REQUEST_HELP","request")
		elif d.object_id == "": _clarify(r,"MISSING_OBJECT")
		elif d.recipient == "addressee": _clarify(r,"RECIPIENT_CONFLICT")
		else: _recognized(r,"REQUEST_ITEM" if predicate == "give" else "REQUEST_ACTION","request")
		return
	if predicate in ["want","need"]:
		if d.negative or d.action != "": _recognized(r,"EXPRESS_DESIRE" if subject == "player" else "REPORT_STATE","question" if question or inverted else "statement")
		elif d.object_id == "": _clarify(r,"MISSING_OBJECT")
		elif question or inverted: _clarify(r,"DESIRE_QUESTION")
		elif subject == "player" and r.frame.addressee != "unresolved": _recognized(r,"REQUEST_ITEM","request")
		else: _recognized(r,"REPORT_STATE","statement")
		return
	if predicate == "understand":
		if subject == "player" and d.negative and not question and not inverted and d.object_id == "" and d.action == "": _recognized(r,"REPORT_NONUNDERSTANDING","statement")
		else: _unsupported(r,"UNDERSTANDING_STRUCTURE")
		return
	if predicate == "have":
		if d.action != "" or d.object_id == "": _clarify(r,"STATE_STRUCTURE")
		elif question or inverted: _unsupported(r,"POSSESSION_QUESTION")
		elif subject == "player" and d.negative: _recognized(r,"REPORT_PROBLEM","statement")
		elif subject != "unresolved": _recognized(r,"REPORT_STATE","statement")
		else: _clarify(r,"MISSING_SUBJECT")
		return
	if predicate == "can":
		if d.action not in ["open","help","give"] or subject == "unresolved": _clarify(r,"MISSING_ACTION_OR_SUBJECT")
		elif d.negative:
			if question or inverted: _unsupported(r,"NEGATIVE_MODAL_QUESTION")
			elif subject == "player" and d.action == "open" and d.object_id != "": _recognized(r,"REPORT_PROBLEM","statement")
			else: _recognized(r,"REPORT_STATE","statement")
		elif subject == "player" and (question or inverted) and d.action == "open" and d.object_id != "": _recognized(r,"ASK_PERMISSION","question")
		elif subject == npc and (question or inverted) and ("du" in input) and d.recipient in ["","player"]:
			if d.action == "help": _recognized(r,"REQUEST_HELP","request")
			elif d.object_id == "": _clarify(r,"MISSING_OBJECT")
			else: _recognized(r,"REQUEST_ITEM" if d.action == "give" else "REQUEST_ACTION","request")
		else: _recognized(r,"REPORT_STATE","question" if question or inverted else "statement")
		return
	if predicate == "help" and subject == "unresolved" and head == "helfen" and polite and not d.negative and d.recipient in ["","player"]:
		r.frame.subject = npc
		_recognized(r,"REQUEST_HELP","request")
		return
	if predicate == "":
		if d.object_id != "" and d.action == "" and not d.negative and not question and subject == "unresolved" and conversation.get("active",false) and conversation.get("pending","") == "help_target":
			r.frame.subject = npc
			r.frame.action = "help"
			r.diagnostics.append("CONTEXTUAL_TARGET")
			_recognized(r,"REQUEST_HELP","request")
		elif d.object_id != "" and d.action == "" and polite and not d.negative and not question and subject == "unresolved":
			r.frame.subject = "player"
			r.frame.predicate = "need"
			_recognized(r,"REQUEST_ITEM","request")
		else: _clarify(r,"AMBIGUOUS_FRAGMENT")
		return
	if predicate in ["open","give","help"] and subject != "unresolved":
		_recognized(r,"REPORT_STATE","question" if question or inverted else "statement")
		return
	_unsupported(r,"UNSUPPORTED_CONSTRUCTION")
