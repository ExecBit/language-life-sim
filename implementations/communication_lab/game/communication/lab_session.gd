extends RefCounted
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")

static func initial_context() -> Dictionary:
	return {"busy": false, "knows_key": true, "key_owner": "anna", "door_open": false, "pending": ""}

static func submit(text: String, context: Dictionary) -> Dictionary:
	var before := context.duplicate(true)
	var parse_context := {"active": true, "pending": str(context.get("pending", "")), "addressee": "anna", "pointed_object_id": ""}
	var parsed: Dictionary = Parser.parse(text, "", parse_context)
	var answer := ""
	var effects: Array[String] = []
	if parsed.status == "RECOGNIZED":
		var frame: Dictionary = parsed.frame
		var target := str(frame.get("object_id", ""))
		match parsed.intent:
			"GREETING": answer = "Ich bin gerade beschäftigt." if context.busy else "Hallo!"
			"THANKS": answer = "Gern!"
			"FAREWELL": answer = "Auf Wiedersehen!"
			"POLITENESS": answer = "Bitte schön."
			"APOLOGY": answer = "Schon gut."
			"REQUEST_REPEAT": answer = "Bitte frag noch einmal."
			"ACCEPT":
				answer = "Ja, gern."; context.pending = ""
			"REFUSE":
				answer = "In Ordnung."; context.pending = ""
			"ASK_LOCATION":
				if target == "key" and context.knows_key: answer = "Der Schlüssel liegt auf dem Tisch."
				else: answer = "Das weiß ich nicht."
			"IDENTIFY": answer = "Das ist der Schlüssel." if target == "key" and context.knows_key else "Das weiß ich nicht."
			"REQUEST_ITEM":
				if context.busy: answer = "Einen Moment bitte."
				elif target == "key" and context.key_owner == "anna":
					context.key_owner = "player"; answer = "Hier, bitte."; effects.append("key_owner: anna → player")
				elif target == "key" and context.key_owner == "player": answer = "Du hast den Schlüssel schon."
				else: answer = "Das kann ich gerade nicht geben."
			"REQUEST_ACTION":
				if context.busy: answer = "Einen Moment bitte."
				elif target == "door" and not context.door_open:
					context.door_open = true; answer = "Die Tür ist offen."; effects.append("door_open: false → true")
				else: answer = "Das kann ich gerade nicht tun."
			"REQUEST_HELP": answer = "Wobei soll ich helfen?"; context.pending = "help_target"
			"PROHIBIT_ACTION": answer = "Okay, das mache ich nicht."
			"REPORT_NONUNDERSTANDING": answer = "Was möchtest du wissen?"
			"REPORT_PROBLEM": answer = "Das tut mir leid."
			"ASK_PERMISSION": answer = "Ja, du kannst die Tür öffnen."
			"REPORT_STATE", "EXPRESS_DESIRE": answer = "Verstanden."
			_: answer = "Was meinst du genau?"
	else:
		answer = "Was meinst du genau?" if parsed.status == "NEEDS_CLARIFICATION" else "Ich verstehe nicht."
	var result := {"input": text, "before": before, "parse": parsed, "answer": answer, "effects": effects, "after": context.duplicate(true)}
	_append_journal(result)
	return result

static func reset(context: Dictionary) -> Dictionary:
	context.clear()
	context.merge(initial_context())
	return context

static func _append_journal(record: Dictionary) -> void:
	var file := FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.WRITE)
	if file == null:
		push_warning("Could not open communication lab attempt journal: %s" % FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()
