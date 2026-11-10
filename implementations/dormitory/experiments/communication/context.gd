extends RefCounted
var locked := true
var opened := false
var key_location := "anna"
var available := true
var knows := true
var permission := false
var may_grant := true
var anna_access := true
var reason := "Das Zimmer ist privat."
var active := false
var pending := ""
var target_id := ""
var attempts: Array = []
var hints := 0
var successes := 0

func parser_context() -> Dictionary:
	return {"active":active,"pending":pending,"addressee":"anna"}

func open_door(actor: String) -> bool:
	if opened or actor not in ["player","anna"]: return false
	if actor == "player" and (key_location != "player" or not permission): return false
	if actor == "anna" and (key_location != "anna" or not available or not anna_access or not permission): return false
	locked = false
	opened = true
	successes += 1
	return true

func respond(r: Dictionary) -> Dictionary:
	var before := {"opened":opened,"key_location":key_location,"permission":permission}
	var out := {"text":"Ich verstehe nicht.","action":"","point":""}
	active = true
	# Partial frames are useful for clarification, but never authorize a world action.
	if r.get("status","") == "NEEDS_CLARIFICATION":
		if "NO_ACTIVE_OFFER" in r.ambiguity:
			out.text = "Was meinst du?"
		elif r.frame.object_id == "key":
			pending = "key_intent"
			out.text = "Meinst du den Ort, oder möchtest du den Schlüssel?"
		else: out.text = "Was möchtest du genau?"
	elif r.get("status","") == "RECOGNIZED":
		out = _react(r)
	attempts.append({"parse":r.duplicate(true),"response":out.duplicate(),"hint_count":hints,
		"world_before":before,"world_after":{"opened":opened,"key_location":key_location,"permission":permission}})
	return out

func _help(target: String) -> Dictionary:
	var out := {"text":"Ich kann dir dabei nicht helfen.","action":"","point":""}
	if not available:
		out.text = "Später, bitte."
		pending = ""
	elif target == "":
		pending = "help_target"
		out.text = "Wobei?"
	elif target == "door":
		pending = ""
		if opened: out.text = "Die Tür ist schon offen."
		elif key_location == "anna" and anna_access and (permission or may_grant):
			permission = true
			out.text = "Ja. Ich helfe dir."
			out.action = "open"
		else: out.text = "Ich kann die Tür nicht öffnen."
	else: pending = ""
	return out

func _react(r: Dictionary) -> Dictionary:
	var out := {"text":"Ich verstehe nicht.","action":"","point":""}
	var f: Dictionary = r.frame
	var target: String = f.target_id
	var intent: String = r.intent
	if intent == "GREETING": out.text = "Hallo!"
	elif intent == "THANKS": out.text = "Bitte!"
	elif intent in ["ACCEPT","REFUSE"]:
		# Validate again: a delayed UI callback must not accept an expired offer.
		if pending != "help_offer": out.text = "Was meinst du?"
		elif intent == "REFUSE":
			pending = ""
			out.text = "Okay."
		else:
			pending = ""
			return _help("door")
	elif intent == "PROHIBIT_ACTION":
		pending = ""
		out.text = "Okay. Ich mache das nicht."
	elif intent == "EXPRESS_DESIRE":
		pending = ""
		out.text = "Okay. Du möchtest das nicht." if f.polarity == "negative" else "Du möchtest das selbst machen."
	elif intent == "REPORT_STATE":
		pending = ""
		out.text = "Verstanden."
	elif intent == "IDENTIFY":
		out.text = {"key":"Ein Schlüssel.","door":"Eine Tür.","cup":"Eine Tasse."}.get(target,"Was meinst du?")
		out.point = target
	elif intent == "ASK_REASON": out.text = reason if target == "door" and reason != "" else "Das weiß ich nicht."
	elif intent == "ASK_LOCATION":
		out.text = "Das weiß ich nicht."
		if target == "key" and knows:
			out.text = {"anna":"Ich habe den Schlüssel.","world":"Der Schlüssel ist dort.","player":"Du hast den Schlüssel."}[key_location]
			out.point = "key"
	elif intent == "REPORT_PROBLEM":
		if f.subject != "player": return out
		pending = "help_offer" if available else ""
		out.text = "Soll ich dir helfen?" if available else "Später, bitte."
	elif intent == "ASK_PERMISSION":
		if f.subject == "player" and target == "door" and may_grant:
			permission = true
			out.text = "Ja. Du kannst das Zimmer öffnen."
		else: out.text = "Nein. Das Zimmer ist privat."
	elif intent == "REQUEST_HELP":
		if f.subject != "anna" or f.polarity != "positive": return out
		return _help(target)
	elif intent == "REQUEST_ACTION":
		if f.subject != "anna" or f.polarity != "positive": return out
		if f.action == "open" and target == "door": return _help(target)
		out.text = "Das kann ich nicht machen."
	elif intent == "REQUEST_ITEM":
		if f.polarity != "positive" or f.speech_act != "request": return out
		pending = ""
		if not available: out.text = "Später, bitte."
		elif target != "key": out.text = "Das kann ich nicht geben."
		elif key_location == "player": out.text = "Du hast den Schlüssel."
		elif key_location == "anna" and may_grant:
			key_location = "player"
			permission = true
			out.text = "Hier, bitte."
			out.action = "give"
		else: out.text = "Ich kann dir den Schlüssel nicht geben."
	return out
