extends RefCounted
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
const OBJECTIVE_TITLES := {"introduce":"Представиться", "ask_mood":"Узнать, как у неё дела", "ask_activity":"Спросить о её занятиях", "share_self":"Рассказать о себе", "offer_help":"Предложить помощь", "farewell":"Попрощаться"}

static func initial_context() -> Dictionary:
	return {"busy": false, "pending": "", "player_name":"", "topic":"introduction", "last_npc_line":"",
		"pending_question":"player_name", "offered_help":false, "player_mood":"", "astera_mood":"tired", "player_plan":"",
		"slow_speech":false, "activity":"working", "objective_progress":_initial_objectives(), "objective_evidence":{}}

static func _initial_objectives() -> Dictionary:
	var progress := {}
	for key in OBJECTIVE_TITLES: progress[key] = false
	return progress

static func opening_line(context: Dictionary) -> Dictionary:
	context.topic = "introduction"
	context.last_npc_line = "Oh! Hallo! Ich bin Astera. Und du?"
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
	_update_objectives(parsed, context, reaction, text)
	context.last_npc_line = answer
	var result := {"input": text, "before": before, "parse": parsed, "answer": answer, "effects": effects,
		"after": context.duplicate(true), "topic":str(context.get("topic", "")),
		"conversation_context":_conversation_snapshot(context), "reaction":reaction,
		"emotion_state":emotion,"animation_id":animation,
		"objective_progress":context.objective_progress.duplicate(true), "objective_evidence":context.objective_evidence.duplicate(true)}
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
				answer = "Hallo! Einen Moment, bitte."
				reaction = "greet_while_busy"; emotion = "concerned"; animation = "soft_concern"
			else:
				var opening := opening_line(context)
				answer = opening.answer; reaction = opening.reaction; emotion = opening.emotion_state; animation = opening.animation_id
		"PLAYER_NAME":
			context.player_name = parsed.name
			context.topic = "introduction"
			context.pending_question = "player_mood"
			answer = "Hallo, %s! Schön!" % context.player_name
			reaction = "welcome_player_by_name"; emotion = "happy"; animation = "small_happy_reaction"
		"ASK_MOOD":
			context.topic = "astera_mood"; context.pending_question = "player_mood"
			if context.astera_mood == "good":
				answer = "Mir geht's gut, danke! Und du? Was machst du heute?"
				reaction = "share_good_mood"; emotion = "happy"; animation = "small_happy_reaction"
			elif context.astera_mood == "neutral":
				answer = "Gut, danke!"
				reaction = "share_neutral_mood"; emotion = "friendly"; animation = "gentle_nod"
			else:
				answer = "Puh… Ich bin müde. Ich arbeite heute viel."
				reaction = "share_tired_mood"; emotion = "tired"; animation = "tired_sigh"
		"ASK_ASTERA_MOOD":
			if context.topic == "player_mood":
				context.topic = "astera_mood"; context.pending_question = "player_plan"
				answer = "Mir geht's gut, danke! Und du? Was machst du heute?"
				reaction = "answer_reciprocal_mood"; emotion = "friendly"; animation = "gentle_nod"
			elif context.topic == "astera_mood":
				context.pending_question = "player_mood"
				answer = "Danke! Ich bin müde."
				reaction = "answer_reciprocal_mood"; emotion = "tired"; animation = "tired_sigh"
			else:
				context.pending_question = "astera_mood"
				answer = "Wie geht's mir? Gute Frage!"
				reaction = "clarify_reciprocal_question"; emotion = "curious"; animation = "curious_head_tilt"
		"ASK_BACK":
			if context.topic == "player_mood":
				context.topic = "astera_mood"; context.pending_question = "player_plan"
				answer = "Mir geht's gut, danke! Was machst du heute?"
				reaction = "answer_reciprocal_mood"; emotion = "friendly"; animation = "point_at_object"
			else:
				context.pending_question = ""
				answer = "Was möchtest du wissen?"
				reaction = "clarify_reciprocal_question"; emotion = "curious"; animation = "curious_head_tilt"
		"PLAYER_MOOD_GOOD":
			context.player_mood = "good"; context.topic = "player_mood"
			context.pending_question = "player_plan"
			answer = "Oh, schön! Mir geht's auch gut. Was machst du heute?"
			reaction = "affirm_good_mood_and_invite_topic"; emotion = "happy"; animation = "gentle_nod"
		"PLAYER_MOOD_LOW":
			var is_tired: bool = parsed.normalized_tokens.has("müde") or parsed.normalized_tokens.has("mude")
			context.player_mood = "tired" if is_tired else "low"
			context.topic = "player_mood"; context.pending_question = "player_reason"
			answer = "Oh… warum?"
			reaction = "respond_with_concern"; emotion = "concerned"; animation = "soft_concern"
		"PLAYER_QUIET_ACK":
			context.topic = "player_mood"; context.pending_question = "player_plan"
			answer = "Oh! Okay!"
			reaction = "respond_to_quiet_player"; emotion = "playful"; animation = "playful_shrug"
		"WHY":
			if context.topic == "player_mood" and context.get("player_mood", "") in ["low", "tired"]:
				context.topic = "player_mood"; context.pending_question = "player_plan"
				answer = "Ich bin auch müde." if context.player_mood == "tired" else "Oh."
				reaction = "relate_to_player_reason"; emotion = "concerned"; animation = "soft_concern"
			elif context.topic in ["astera_mood", "activity"] or context.last_npc_line.to_lower().contains("müde"):
				context.topic = "work"; context.pending_question = ""
				answer = "Ich arbeite."
				reaction = "explain_tiredness"; emotion = "tired"; animation = "tired_sigh"
			else:
				answer = "Warum? Was meinst du?"
				reaction = "ask_why_clarification"; emotion = "curious"; animation = "curious_head_tilt"
		"ASK_ACTIVITY":
			context.topic = "activity"; context.activity = "working"; context.pending_question = "player_plan"
			answer = "Ich arbeite. Und du?"
			reaction = "explain_activity_and_invite_player"; emotion = "playful"; animation = "point_at_object"
		"OFFER_HELP":
			context.offered_help = true; context.pending_question = "help_offer"; context.topic = "help"
			answer = "Oh! Danke! Vielleicht später." if context.busy else "Oh! Danke! Das ist nett!"
			reaction = "accept_help_offer"; emotion = "grateful"; animation = "surprised_delighted"
		"ACCEPT_HELP":
			context.pending_question = ""; context.topic = "help"
			answer = "Danke!"
			reaction = "thank_player_for_help"; emotion = "grateful"; animation = "open_palm_offer"
		"DECLINE_HELP":
			context.pending_question = ""; context.topic = "help"
			answer = "Okay. Danke!"
			reaction = "accept_declined_help"; emotion = "friendly"; animation = "gentle_nod"
		"PLAYER_PLAN":
			if parsed.normalized_tokens.has("frei"):
				context.player_plan = "free"; context.topic = "player_plan"
				answer = "Oh, schön!"
				reaction = "respond_to_free_day"; emotion = "happy"; animation = "small_happy_reaction"
			elif parsed.normalized_tokens.has("lerne"):
				context.player_plan = "learning_german"; context.topic = "player_plan"
				context.pending_question = "slow_speech"
				answer = "Ah, Deutsch! Schön! Ich spreche langsam. Okay?"
				reaction = "offer_slow_speech"; emotion = "friendly"; animation = "gentle_nod"
			else:
				context.player_plan = "work"; context.topic = "player_plan"
				answer = "Oh! Viel Arbeit heute?"
				reaction = "respond_to_work_plan"; emotion = "friendly"; animation = "gentle_nod"
		"ACCEPT_SLOW":
			context.slow_speech = true; context.pending_question = ""; context.topic = "slow_speech"
			answer = "Gut! Ich spreche langsam."
			reaction = "enable_slow_speech"; emotion = "grateful"; animation = "gentle_nod"
		"DECLINE_SLOW":
			context.slow_speech = false; context.pending_question = ""; context.topic = "slow_speech"
			answer = "Okay!"
			reaction = "decline_slow_speech"; emotion = "friendly"; animation = "gentle_nod"
		"FAREWELL":
			context.topic = "farewell"; context.pending_question = ""
			answer = "Tschüss, %s!" % context.player_name if not str(context.player_name).is_empty() else "Tschüss! Bis später!"
			reaction = "say_goodbye"; emotion = "farewell"; animation = "farewell_wave"
	return {"answer":answer,"reaction":reaction,"emotion_state":emotion,"animation_id":animation}

static func _resolve_legacy(parsed: Dictionary, context: Dictionary, effects: Array[String]) -> String:
	if parsed.status != "RECOGNIZED": return "Was meinst du?" if parsed.status == "NEEDS_CLARIFICATION" else "Ich verstehe nicht."
	match parsed.intent:
		"GREETING": return "Hallo!"
		"THANKS": return "Gern!"
		"FAREWELL": return "Tschüss!"
		"POLITENESS": return "Bitte!"
		"APOLOGY": return "Okay!"
		"REQUEST_REPEAT": return "Bitte noch einmal."
		"ACCEPT": context.pending = ""; return "Ja!"
		"REFUSE": context.pending = ""; return "Okay."
		"ASK_LOCATION", "IDENTIFY": return "Ich weiß es nicht."
		"REQUEST_ITEM":
			return "Das geht nicht."
		"REQUEST_ACTION":
			return "Das geht nicht."
		"REQUEST_HELP": context.pending = "help_target"; return "Was brauchst du?"
		"PROHIBIT_ACTION": return "Okay. Ich mache das nicht."
		"REPORT_NONUNDERSTANDING": return "Was möchtest du wissen?"
		"REPORT_PROBLEM": return "Das tut mir leid."
		"ASK_PERMISSION": return "Das geht nicht."
		"REPORT_STATE", "EXPRESS_DESIRE": return "Okay!"
	return "Was meinst du?"

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
	var keys := ["busy","player_name","topic","last_npc_line","pending_question","offered_help","player_mood","astera_mood","player_plan","slow_speech","objective_progress","objective_evidence"]
	var snapshot := {}
	for key in keys: snapshot[key] = context.get(key, null)
	return snapshot

static func _update_objectives(parsed: Dictionary, context: Dictionary, reaction: String, input_text: String) -> void:
	if parsed.get("status", "") != "RECOGNIZED": return
	if reaction.begins_with("clarify") or reaction in ["ask_why_clarification", "unrecognized"]: return
	var intent := str(parsed.get("intent", ""))
	var completed: Array[String] = []
	match intent:
		"PLAYER_NAME":
			if not str(parsed.get("name", "")).is_empty(): completed.append("introduce")
		"ASK_MOOD", "ASK_ASTERA_MOOD", "ASK_BACK": completed.append("ask_mood")
		"ASK_ACTIVITY": completed.append("ask_activity")
		"PLAYER_MOOD_GOOD", "PLAYER_MOOD_LOW", "PLAYER_PLAN": completed.append("share_self")
		"OFFER_HELP": completed.append("offer_help")
		"FAREWELL": completed.append("farewell")
	var progress: Dictionary = context.get("objective_progress", {})
	var evidence: Dictionary = context.get("objective_evidence", {})
	for key in completed:
		if not progress.get(key, false):
			progress[key] = true
			evidence[key] = {"intent":intent, "input":input_text}
	context.objective_progress = progress
	context.objective_evidence = evidence

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
