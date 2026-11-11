extends RefCounted
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")

static func initial_context() -> Dictionary:
	return {"busy": false, "knows_key": true, "key_owner": "anna", "door_open": false,
		"pending": "", "player_name":"", "topic":"introduction", "last_npc_line":"",
		"pending_question":"player_name", "offered_help":false, "player_mood":"", "player_plan":"",
		"slow_speech":false, "activity":"tidying"}

static func opening_line(context: Dictionary) -> Dictionary:
	context.topic = "introduction"
	context.last_npc_line = "Oh! Hallo! Du bist ja schon da!"
	context.pending_question = "player_name"
	return {"answer":context.last_npc_line,"topic":context.topic,"reaction":"player_arrived",
		"emotion_state":"surprised_soft","animation_id":"greeting_wave"}

static func submit(text: String, context: Dictionary) -> Dictionary:
	var before := context.duplicate(true)
	var extension_parse: Dictionary = DialogueGrammar.parse(text, context)
	var parsed: Dictionary
	var answer := ""
	var effects: Array[String] = []
	var reaction := "unrecognized"
	var emotion := "curious"
	var animation := "curious_head_tilt"
	if not extension_parse.is_empty():
		parsed = extension_parse
		var outcome := _resolve_dialogue(parsed, context)
		answer = outcome.answer
		reaction = outcome.reaction
		emotion = outcome.emotion_state
		animation = outcome.animation_id
	else:
		var parse_context := {"active": true, "pending": str(context.get("pending", "")), "addressee": "anna", "pointed_object_id": ""}
		parsed = Parser.parse(text, "", parse_context)
		answer = _resolve_legacy(parsed, context, effects)
		reaction = "legacy_%s" % str(parsed.get("intent", "unrecognized")).to_lower()
		var visual := _legacy_visuals(str(parsed.get("intent", "")), str(parsed.status))
		emotion = visual.emotion_state
		animation = visual.animation_id
	context.last_npc_line = answer
	var result := {"input": text, "before": before, "parse": parsed, "answer": answer, "effects": effects,
		"after": context.duplicate(true), "topic":str(context.get("topic", "")),
		"conversation_context":_conversation_snapshot(context), "reaction":reaction,
		"emotion_state":emotion,"animation_id":animation}
	_append_journal(result)
	return result

static func _resolve_dialogue(parsed: Dictionary, context: Dictionary) -> Dictionary:
	var intent := str(parsed.semantic)
	var answer := "Ich verstehe nicht."
	var reaction := "clarify"
	var emotion := "curious"
	var animation := "curious_head_tilt"
	match intent:
		"GREETING":
			if context.busy:
				context.topic = "introduction"; context.pending_question = "player_name"
				answer = "Oh! Hallo! Einen Moment, ich bin gerade beschäftigt."
				reaction = "greet_while_busy"; emotion = "concerned"; animation = "soft_concern"
			else:
				var opening := opening_line(context)
				answer = opening.answer; reaction = opening.reaction; emotion = opening.emotion_state; animation = opening.animation_id
		"PLAYER_NAME":
			context.player_name = parsed.name
			context.topic = "introduction"
			context.pending_question = "player_mood"
			answer = "Freut mich, %s! Wie geht's dir?" % context.player_name
			reaction = "welcome_player_by_name"; emotion = "happy"; animation = "small_happy_reaction"
		"ASK_MOOD":
			context.topic = "astera_mood"; context.pending_question = "player_mood"
			answer = "Puh… Ich bin ein bisschen müde. Viel Arbeit heute!"
			reaction = "share_tired_mood"; emotion = "tired"; animation = "tired_sigh"
		"ASK_ASTERA_MOOD":
			if context.topic == "player_mood":
				context.topic = "astera_mood"; context.pending_question = "player_plan"
				answer = "Mir geht's gut, danke! Was machst du heute?"
				reaction = "answer_reciprocal_mood"; emotion = "friendly"; animation = "gentle_nod"
			elif context.topic == "astera_mood":
				context.pending_question = "player_mood"
				answer = "Danke! Ein bisschen müde, aber es geht."
				reaction = "answer_reciprocal_mood"; emotion = "tired"; animation = "tired_sigh"
			else:
				context.pending_question = "astera_mood"
				answer = "Fragst du, wie es mir geht?"
				reaction = "clarify_reciprocal_question"; emotion = "curious"; animation = "curious_head_tilt"
		"ASK_BACK":
			if context.topic == "player_mood":
				context.topic = "astera_mood"; context.pending_question = "player_plan"
				answer = "Mir geht's gut, danke! Was machst du heute?"
				reaction = "answer_reciprocal_mood"; emotion = "friendly"; animation = "gentle_nod"
			else:
				context.pending_question = ""
				answer = "Und ich? Was möchtest du wissen?"
				reaction = "clarify_reciprocal_question"; emotion = "curious"; animation = "curious_head_tilt"
		"PLAYER_MOOD_GOOD":
			context.player_mood = "good"; context.topic = "player_mood"
			context.pending_question = "player_plan"
			answer = "Das freut mich! Mir geht's auch gut. Was machst du heute?"
			reaction = "affirm_good_mood_and_invite_topic"; emotion = "happy"; animation = "gentle_nod"
		"PLAYER_MOOD_LOW":
			var is_tired: bool = parsed.normalized_tokens.has("müde") or parsed.normalized_tokens.has("mude")
			context.player_mood = "tired" if is_tired else "low"
			context.topic = "player_mood"; context.pending_question = "player_reason"
			answer = "Oh, das tut mir leid. Möchtest du erzählen?"
			reaction = "respond_with_concern"; emotion = "concerned"; animation = "soft_concern"
		"WHY":
			if context.topic in ["astera_mood", "activity"] or context.last_npc_line.to_lower().contains("müde"):
				context.topic = "work"; context.pending_question = ""
				answer = "Viel Arbeit heute. Ich räume gerade auf."
				reaction = "explain_tiredness"; emotion = "tired"; animation = "tired_sigh"
			else:
				answer = "Warum genau? Meinst du meine Arbeit oder etwas anderes?"
				reaction = "ask_why_clarification"; emotion = "curious"; animation = "curious_head_tilt"
		"ASK_ACTIVITY":
			context.topic = "activity"; context.activity = "tidying"; context.pending_question = "cup_owner"
			answer = "Ich räume auf. Aber diese Tasse ist nicht meine!"
			reaction = "explain_activity_and_point_out_cup"; emotion = "playful"; animation = "point_at_object"
		"ASK_CUP_OWNER", "CUP_REACTION":
			context.topic = "cup"; context.pending_question = ""
			answer = "Nein, die Tasse ist nicht meine. Ich weiß nicht, wem sie gehört!"
			reaction = "clarify_unknown_cup_owner"; emotion = "playful"; animation = "playful_shrug"
		"OFFER_HELP":
			context.offered_help = true; context.pending_question = "help_offer"; context.topic = "help"
			answer = "Oh, wirklich? Das ist lieb! Ja, bitte — kannst du die Tasse hierher stellen?"
			reaction = "accept_help_offer"; emotion = "grateful"; animation = "surprised_delighted"
		"ACCEPT_HELP":
			context.pending_question = ""; context.topic = "help"
			answer = "Danke! Das hilft mir sehr."
			reaction = "thank_player_for_help"; emotion = "grateful"; animation = "open_palm_offer"
		"DECLINE_HELP":
			context.pending_question = ""; context.topic = "help"
			answer = "Alles gut. Danke, dass du gefragt hast."
			reaction = "accept_declined_help"; emotion = "friendly"; animation = "gentle_nod"
		"PLAYER_PLAN":
			if parsed.normalized_tokens.has("frei"):
				context.player_plan = "free"; context.topic = "player_plan"
				answer = "Das klingt schön! Ein freier Tag tut gut."
				reaction = "respond_to_free_day"; emotion = "happy"; animation = "small_happy_reaction"
			elif parsed.normalized_tokens.has("lerne"):
				context.player_plan = "learning_german"; context.topic = "player_plan"
				context.pending_question = "slow_speech"
				answer = "Ach so, du lernst Deutsch! Dann spreche ich langsam, okay?"
				reaction = "offer_slow_speech"; emotion = "friendly"; animation = "gentle_nod"
			else:
				context.player_plan = "work"; context.topic = "player_plan"
				answer = "Oh, du arbeitest heute. Ich wünsche dir einen guten Tag!"
				reaction = "respond_to_work_plan"; emotion = "friendly"; animation = "gentle_nod"
		"ACCEPT_SLOW":
			context.slow_speech = true; context.pending_question = ""; context.topic = "slow_speech"
			answer = "Gern. Ich spreche langsam. Danke!"
			reaction = "enable_slow_speech"; emotion = "grateful"; animation = "gentle_nod"
		"DECLINE_SLOW":
			context.slow_speech = false; context.pending_question = ""; context.topic = "slow_speech"
			answer = "In Ordnung. Sag einfach Bescheid."
			reaction = "decline_slow_speech"; emotion = "friendly"; animation = "gentle_nod"
		"FAREWELL":
			context.topic = "farewell"; context.pending_question = ""
			answer = "Bis dann! Wir sehen uns später."
			reaction = "say_goodbye"; emotion = "farewell"; animation = "farewell_wave"
	return {"answer":answer,"reaction":reaction,"emotion_state":emotion,"animation_id":animation}

static func _resolve_legacy(parsed: Dictionary, context: Dictionary, effects: Array[String]) -> String:
	if parsed.status != "RECOGNIZED": return "Was meinst du genau?" if parsed.status == "NEEDS_CLARIFICATION" else "Ich verstehe nicht."
	var frame: Dictionary = parsed.frame
	var target := str(frame.get("object_id", ""))
	match parsed.intent:
		"GREETING": return "Hallo! Schön, dich zu sehen."
		"THANKS": return "Gern!"
		"FAREWELL": return "Auf Wiedersehen!"
		"POLITENESS": return "Bitte schön."
		"APOLOGY": return "Schon gut."
		"REQUEST_REPEAT": return "Bitte frag noch einmal."
		"ACCEPT": context.pending = ""; return "Ja, gern."
		"REFUSE": context.pending = ""; return "In Ordnung."
		"ASK_LOCATION": return "Der Schlüssel liegt dort auf dem Boden." if target == "key" and context.knows_key else "Das weiß ich nicht."
		"IDENTIFY": return "Das ist der Schlüssel." if target == "key" and context.knows_key else "Das weiß ich nicht."
		"REQUEST_ITEM":
			if context.busy: return "Einen Moment bitte."
			if target == "key" and context.key_owner == "anna":
				context.key_owner = "player"; effects.append("key_owner: anna → player"); return "Hier, bitte."
			if target == "key" and context.key_owner == "player": return "Du hast den Schlüssel schon."
			return "Das kann ich gerade nicht geben."
		"REQUEST_ACTION":
			if context.busy: return "Einen Moment bitte."
			if target == "door" and not context.door_open:
				context.door_open = true; effects.append("door_open: false → true"); return "Die Tür ist offen."
			return "Das kann ich gerade nicht tun."
		"REQUEST_HELP": context.pending = "help_target"; return "Wobei soll ich helfen?"
		"PROHIBIT_ACTION": return "Okay, das mache ich nicht."
		"REPORT_NONUNDERSTANDING": return "Was möchtest du wissen?"
		"REPORT_PROBLEM": return "Das tut mir leid."
		"ASK_PERMISSION": return "Ja, du kannst die Tür öffnen."
		"REPORT_STATE", "EXPRESS_DESIRE": return "Verstanden."
	return "Was meinst du genau?"

static func _legacy_visuals(intent: String, status: String) -> Dictionary:
	var visuals := {
		"GREETING":["surprised_soft","greeting_wave"], "THANKS":["grateful","gentle_nod"],
		"FAREWELL":["farewell","farewell_wave"], "REQUEST_HELP":["friendly","open_palm_offer"],
		"REQUEST_ITEM":["friendly","open_palm_offer"], "REQUEST_ACTION":["friendly","gentle_nod"],
		"ASK_LOCATION":["friendly","point_at_object"], "IDENTIFY":["curious","curious_head_tilt"],
		"ACCEPT":["happy","gentle_nod"], "REFUSE":["friendly","gentle_nod"],
		"REQUEST_REPEAT":["curious","curious_head_tilt"], "REPORT_PROBLEM":["concerned","soft_concern"]}
	var chosen: Array = visuals.get(intent, ["curious","curious_head_tilt"] if status != "RECOGNIZED" else ["friendly","gentle_nod"])
	return {"emotion_state":chosen[0],"animation_id":chosen[1]}

static func _conversation_snapshot(context: Dictionary) -> Dictionary:
	var keys := ["player_name","topic","last_npc_line","pending_question","offered_help","player_mood","player_plan","slow_speech"]
	var snapshot := {}
	for key in keys: snapshot[key] = context.get(key, null)
	return snapshot

static func reset(context: Dictionary) -> Dictionary:
	context.clear()
	context.merge(initial_context())
	return context

static func _append_journal(record: Dictionary) -> void:
	var file := FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.READ_WRITE)
	if file == null: file = FileAccess.open("user://communication_lab_attempts.jsonl", FileAccess.WRITE)
	if file == null:
		push_warning("Could not open communication lab attempt journal: %s" % FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()
