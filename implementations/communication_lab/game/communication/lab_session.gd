extends RefCounted

const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
const DialogueLanguage = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const OBJECTIVE_TITLES := {"introduce":"Представиться", "ask_mood":"Узнать, как у неё дела", "ask_activity":"Спросить о её занятиях", "share_self":"Рассказать о себе", "offer_help":"Предложить помощь", "farewell":"Попрощаться"}

static func initial_context() -> Dictionary:
	return {"busy":false,"pending":"","player_name":"","topic":"introduction","selected_topic":"introduction","last_npc_line":"",
		"pending_question":"player_name","awaiting_name":true,"introduction_completed":false,"pending_clarification":{},
		"offered_help":false,"help_requested":false,"player_mood":"","astera_mood":"tired","last_player_state":{},"last_astera_state":{},
		"player_plan":"","slow_speech":false,"activity":"working","objective_progress":_initial_objectives(),"objective_evidence":{}}

static func _initial_objectives() -> Dictionary:
	var progress := {}
	for key in OBJECTIVE_TITLES: progress[key] = false
	return progress

static func opening_line(context: Dictionary) -> Dictionary:
	context.topic = "introduction"
	context.selected_topic = "introduction"
	context.awaiting_name = str(context.get("player_name","")).is_empty() and not bool(context.get("introduction_completed",false))
	context.pending_question = "player_name" if context.awaiting_name else ""
	context.last_npc_line = "Oh! Hallo! Ich bin Astera. Und du?" if context.awaiting_name else "Schön, dich wiederzusehen, %s! Was möchtest du besprechen?" % context.player_name
	return {"answer":context.last_npc_line,"topic":context.topic,"reaction":"player_arrived",
		"emotion_state":"surprised_soft","animation_id":"greeting_wave"}

static func select_topic(topic_id: String, context: Dictionary) -> Dictionary:
	var valid := false
	for topic in DialogueLanguage.data().get("topics", []):
		if str(topic.id) == topic_id:
			valid = true
			break
	if not valid:
		return {"selected_topic":str(context.get("selected_topic","introduction")),"closed_clarification":false}
	var changed := str(context.get("selected_topic","introduction")) != topic_id
	var pending: Dictionary = context.get("pending_clarification",{})
	var closed := changed and not pending.is_empty()
	if changed and str(context.get("pending_question","")) in ["help_offer","slow_speech"]:
		context.pending_question = ""
	if closed:
		context.pending_clarification = {}
	context.selected_topic = topic_id
	context.topic = topic_id
	return {"selected_topic":topic_id,"closed_clarification":closed}

static func close_dialog(context: Dictionary) -> bool:
	var pending: Dictionary = context.get("pending_clarification", {})
	var had_pending := not pending.is_empty()
	context.pending_clarification = {}
	if str(context.get("pending_question","")) in ["help_offer","slow_speech"]:
		context.pending_question = ""
	return had_pending

static func submit(text: String, context: Dictionary, selected_topic: String = "") -> Dictionary:
	var before := context.duplicate(true)
	if not selected_topic.is_empty():
		select_topic(selected_topic, context)
	var parsed: Dictionary = DialogueLanguage.analyze(text, context)
	var answer := ""
	var notification := ""
	var effects: Array[String] = []
	var reaction := "unrecognized"
	var emotion := "curious"
	var animation := "curious_head_tilt"
	var pending: Dictionary = context.get("pending_clarification", {}).duplicate(true)
	if not pending.is_empty() and str(parsed.get("intent","")) in ["SHORT_YES","SHORT_NO"]:
		var confirmed := str(parsed.intent) == "SHORT_YES"
		var outcome := _resolve_pending_clarification(parsed, pending, confirmed, context, effects)
		answer = str(outcome.answer)
		notification = str(outcome.get("notification",""))
		reaction = str(outcome.reaction)
		emotion = str(outcome.emotion_state)
		animation = str(outcome.animation_id)
	elif str(parsed.get("intent","")) in ["SHORT_YES","SHORT_NO"] and str(context.get("pending_question","")) in ["help_offer","slow_speech"]:
		parsed = DialogueGrammar.parse(text, context)
		var legacy_pending := _resolve_dialogue(parsed, context)
		answer = str(legacy_pending.answer)
		notification = _legacy_notification(parsed)
		reaction = str(legacy_pending.reaction)
		emotion = str(legacy_pending.emotion_state)
		animation = str(legacy_pending.animation_id)
	elif str(parsed.get("intent","")) in ["SHORT_YES","SHORT_NO"]:
		parsed.status = "NEEDS_CLARIFICATION"
		parsed.reason = "NO_OPEN_YES_NO_TARGET"
		parsed.notification = "Астера не поняла, к чему относится ответ «%s»." % ("Ja" if parsed.intent == "SHORT_YES" else "Nein")
		answer = "Was meinst du damit?"
		notification = str(parsed.notification)
		reaction = "clarify_no_open_question"
		emotion = "curious"
		animation = "curious_head_tilt"
	else:
		if not pending.is_empty():
			context.pending_clarification = {}
		if bool(parsed.get("handled",false)):
			if str(parsed.get("reason", "")) == "MULTIPLE_INTENTS":
				# Preserve richer component frames from the legacy grammar without applying its effects.
				var legacy_multi: Dictionary = DialogueGrammar.parse(text, context)
				var legacy_frames: Array = legacy_multi.get("semantic_frames", [])
				if legacy_frames.size() > parsed.get("semantic_frames", []).size():
					parsed.semantic_frames = legacy_frames.duplicate(true)
			var outcome := _resolve_p67(parsed, text, context, effects)
			answer = str(outcome.answer)
			notification = str(outcome.get("notification",parsed.get("notification","")))
			reaction = str(outcome.reaction)
			emotion = str(outcome.emotion_state)
			animation = str(outcome.animation_id)
		else:
			var extension_parse: Dictionary = DialogueGrammar.parse(text, context)
			if not extension_parse.is_empty():
				parsed = extension_parse
				var legacy := _resolve_dialogue(parsed, context)
				answer = str(legacy.answer)
				reaction = str(legacy.reaction)
				emotion = str(legacy.emotion_state)
				animation = str(legacy.animation_id)
			else:
				var parse_context := {"active":true,"pending":str(context.get("pending","")),"addressee":"anna","pointed_object_id":""}
				parsed = Parser.parse(text, "", parse_context)
				answer = _resolve_legacy(parsed, context, effects)
				reaction = "legacy_%s" % str(parsed.get("intent","unrecognized")).to_lower()
				var visual := _legacy_visuals(str(parsed.get("intent","")), str(parsed.get("status","")))
				emotion = str(visual.emotion_state)
				animation = str(visual.animation_id)
			notification = _legacy_notification(parsed)
	_update_objectives(parsed, context, reaction, text)
	context.last_npc_line = answer
	var result := {"input":text,"before":before,"parse":parsed,"answer":answer,"notification":notification,
		"effects":effects,"after":context.duplicate(true),"topic":str(context.get("topic","")),
		"selected_topic":str(context.get("selected_topic","introduction")),
		"conversation_context":_conversation_snapshot(context),"reaction":reaction,
		"emotion_state":emotion,"animation_id":animation,
		"objective_progress":context.objective_progress.duplicate(true),"objective_evidence":context.objective_evidence.duplicate(true)}
	_append_journal(result)
	return result

static func _resolve_p67(parsed: Dictionary, text: String, context: Dictionary, effects: Array[String]) -> Dictionary:
	var reaction := "clarify"
	var emotion := "curious"
	var animation := "curious_head_tilt"
	if str(parsed.get("status","")) != "RECOGNIZED":
		var candidate: Dictionary = parsed.get("clarification_candidate",{})
		if not candidate.is_empty() and str(candidate.get("question_kind","yes_no")) == "yes_no":
			var question := _question_for_candidate(candidate)
			context.pending_clarification = {
				"expected_response":"yes_no","question":question,"proposition":candidate.duplicate(true),
				"original_input":text,"source_frame":parsed.get("frame",{}).duplicate(true),
				"topic":str(context.get("selected_topic","introduction"))
			}
			return {"answer":question,"notification":str(parsed.get("notification","")),
				"reaction":"ask_one_clarification","emotion_state":"curious","animation_id":"curious_head_tilt"}
		var response := "Was meinst du?"
		if parsed.get("reason","") == "MULTIPLE_INTENTS":
			response = "Bitte eins nach dem anderen."
		elif parsed.get("status","") == "UNKNOWN":
			response = "Ich habe das Wort nicht verstanden. Kannst du es anders sagen?"
		elif parsed.get("reason","") == "NAME_CONTINUATION":
			response = "Wie heißt du?"
		elif parsed.get("reason","") == "NEGATED_NAME":
			response = "Wie heißt du?"
		elif parsed.get("reason","") == "NO_BRANCH":
			response = str(DialogueLanguage.data().help_replies.no_branch)
		return {"answer":response,"notification":str(parsed.get("notification","")),
			"reaction":"clarify_%s" % str(parsed.get("reason","unknown")).to_lower(),
			"emotion_state":"curious","animation_id":"curious_head_tilt"}
	match str(parsed.get("intent","")):
		"PLAYER_NAME":
			var name := str(parsed.get("name","")).strip_edges()
			if name.is_empty() or not bool(context.get("awaiting_name",false)):
				return {"answer":"Ich kenne deinen Namen schon. Was möchtest du besprechen?",
					"notification":"Астера не открыла состояние знакомства для нового имени.",
					"reaction":"name_slot_closed","emotion_state":"friendly","animation_id":"gentle_nod"}
			if str(context.get("player_name","")) != name:
				context.player_name = name
				effects.append("player_name_set")
			context.awaiting_name = false
			context.introduction_completed = true
			context.pending_question = ""
			context.topic = "introduction"
			return {"answer":"Hallo, %s! Schön!" % name,"notification":"",
				"reaction":"welcome_player_by_name","emotion_state":"happy","animation_id":"small_happy_reaction"}
		"REPORT_STATE":
			return _apply_state_report(parsed, context, effects, true)
		"REPORT_ASTERA_STATE":
			return _apply_state_report(parsed, context, effects, false)
		"OFFER_HELP":
			return _apply_help_offer(context, effects)
		"REQUEST_HELP":
			context.topic = "help"
			if not bool(context.get("help_requested",false)):
				context.help_requested = true
				effects.append("request_help_from_astera")
			return {"answer":str(DialogueLanguage.data().help_replies.request),"notification":"",
				"reaction":"respond_to_help_request","emotion_state":"friendly","animation_id":"open_palm_offer"}
		"PLAYER_CANNOT_HELP":
			context.topic = "help"
			return {"answer":str(DialogueLanguage.data().help_replies.refusal),"notification":"",
				"reaction":"acknowledge_cannot_help","emotion_state":"concerned","animation_id":"soft_concern"}
	return {"answer":"Was meinst du?","notification":"","reaction":reaction,"emotion_state":emotion,"animation_id":animation}

static func _resolve_pending_clarification(parsed: Dictionary, pending: Dictionary, confirmed: bool, context: Dictionary, effects: Array[String]) -> Dictionary:
	context.pending_clarification = {}
	var proposition: Dictionary = pending.get("proposition",{}).duplicate(true)
	parsed.confirmed_proposition = proposition.duplicate(true)
	parsed.intent = "CONFIRM_CLARIFICATION" if confirmed else "REJECT_CLARIFICATION"
	parsed.semantic = parsed.intent
	parsed.frame = proposition.duplicate(true)
	parsed.frame.speaker = "player"
	parsed.frame.confirmation = "yes" if confirmed else "no"
	parsed.status = "RECOGNIZED"
	if not confirmed:
		return {"answer":"Alles klar. Was möchtest du besprechen?","notification":"",
			"reaction":"reject_clarification","emotion_state":"friendly","animation_id":"gentle_nod"}
	match str(proposition.get("intent","")):
		"OFFER_HELP":
			return _apply_help_offer(context, effects)
		"REQUEST_HELP":
			context.topic = "help"
			if not bool(context.get("help_requested",false)):
				context.help_requested = true
				effects.append("request_help_from_astera")
			return {"answer":str(DialogueLanguage.data().help_replies.request),"notification":"",
				"reaction":"respond_to_help_request","emotion_state":"friendly","animation_id":"open_palm_offer"}
		"REPORT_STATE":
			var synthetic := {"intent":"REPORT_STATE","state_id":proposition.get("state_id",""),
				"polarity":proposition.get("polarity","positive"),"frame":{"experiencer":proposition.get("experiencer","player")}}
			return _apply_state_report(synthetic, context, effects, true)
	parsed.status = "NEEDS_CLARIFICATION"
	parsed.reason = "UNSUPPORTED_CONFIRMATION_TARGET"
	return {"answer":"Was meinst du?","notification":"","reaction":"clarify_confirmation_target",
		"emotion_state":"curious","animation_id":"curious_head_tilt"}

static func _question_for_candidate(candidate: Dictionary) -> String:
	match str(candidate.get("intent","")):
		"OFFER_HELP":
			return str(DialogueLanguage.data().help_replies.clarify_offer)
		"REQUEST_HELP":
			return str(DialogueLanguage.data().help_replies.clarify_request)
		"REPORT_STATE":
			var state_id := str(candidate.get("state_id",""))
			var forms: Array = DialogueLanguage.data().get("states",{}).get(state_id,{}).get("forms",[])
			var state_word := str(forms[0]) if not forms.is_empty() else state_id
			var negative := "nicht " if str(candidate.get("polarity","positive")) == "negative" else ""
			return "Du bist %s%s?" % [negative,state_word]
	return "Meinst du das?"

static func _apply_help_offer(context: Dictionary, effects: Array[String]) -> Dictionary:
	context.topic = "help"
	if not bool(context.get("offered_help",false)):
		context.offered_help = true
		effects.append("offer_help_to_astera")
	return {"answer":str(DialogueLanguage.data().help_replies.offer),"notification":"",
		"reaction":"accept_help_offer","emotion_state":"grateful","animation_id":"surprised_delighted"}

static func _apply_state_report(parsed: Dictionary, context: Dictionary, effects: Array[String], player_state: bool) -> Dictionary:
	var state_id := str(parsed.get("state_id",""))
	var polarity := str(parsed.get("polarity",parsed.get("frame",{}).get("polarity","positive")))
	var state: Dictionary = DialogueLanguage.data().get("states",{}).get(state_id,{})
	context.topic = "player_mood" if player_state else "astera_mood"
	if player_state:
		var previous: Dictionary = context.get("last_player_state",{})
		var current := {"state_id":state_id,"polarity":polarity}
		if previous != current:
			effects.append("player_state:%s:%s" % [state_id,polarity])
		context.last_player_state = current
		if polarity == "positive":
			context.player_mood = state_id
			return {"answer":str(state.get("reply","Danke, dass du es sagst.")),"notification":"",
				"reaction":"respond_to_player_state_%s" % state_id,
				"emotion_state":str(state.get("emotion","friendly")),"animation_id":str(state.get("animation","gentle_nod"))}
		context.player_mood = ""
		return {"answer":str(state.get("negative_reply","Verstehe. Danke, dass du es sagst.")),"notification":"",
			"reaction":"acknowledge_negated_player_state","emotion_state":"friendly","animation_id":"gentle_nod"}
	var previous_astera: Dictionary = context.get("last_astera_state",{})
	var current_astera := {"state_id":state_id,"polarity":polarity}
	if previous_astera != current_astera:
		effects.append("astera_state:%s:%s" % [state_id,polarity])
	context.last_astera_state = current_astera
	if polarity == "positive":
		context.astera_mood = state_id
		return {"answer":str(state.get("npc_ack","Ja, das stimmt.")),"notification":"",
			"reaction":"acknowledge_astera_state_%s" % state_id,
			"emotion_state":str(state.get("emotion","friendly")),"animation_id":str(state.get("animation","gentle_nod"))}
	context.astera_mood = ""
	return {"answer":str(state.get("negative_reply","Verstehe. Danke, dass du es sagst.")),"notification":"",
		"reaction":"acknowledge_negated_astera_state","emotion_state":"friendly","animation_id":"gentle_nod"}

static func _legacy_notification(parsed: Dictionary) -> String:
	var unknown: Array = parsed.get("unknown_tokens",[])
	if unknown.is_empty():
		for diagnostic in parsed.get("diagnostics",[]):
			if diagnostic is Dictionary and diagnostic.get("code","") in ["UNKNOWN_TOKEN","UNSUPPORTED_TOKEN"]:
				unknown.append(str(diagnostic.get("token","")))
	if not unknown.is_empty():
		return "Астера не поняла слово „%s“. Попробуйте выразиться иначе." % str(unknown[0])
	if parsed.get("status","") in ["UNKNOWN","UNSUPPORTED","NEEDS_CLARIFICATION"]:
		return "Астера не поняла, что вы хотите сказать. Выберите тему в меню или попробуйте другую формулировку."
	return ""
static func _resolve_dialogue(parsed: Dictionary, context: Dictionary) -> Dictionary:
	if parsed.get("status", "") != "RECOGNIZED":
		var reason := str(parsed.get("reason", ""))
		var response := "Was meinst du?"
		if parsed.get("status", "") == "UNSUPPORTED" and "MULTIPLE_INTENTS" in parsed.get("unsupported_features", []):
			response = "Bitte eins nach dem anderen."
		elif parsed.get("status", "") == "UNKNOWN":
			response = "Ich verstehe das Wort nicht."
		elif reason == "AMBIGUOUS_ROLES":
			response = "Möchtest du mir helfen oder brauchst du Hilfe?"
		elif reason == "QUESTION_OR_STATEMENT":
			response = "Möchtest du, dass ich dir helfe?"
		elif reason in ["ELLIPTIC_YES_NO", "MISSING_CONTEXT", "UND_DU_CONTEXT"]:
			response = "Was möchtest du wissen?"
		return {"answer":response,"reaction":"clarify_%s" % reason.to_lower() if not reason.is_empty() else "clarify",
			"emotion_state":"curious","animation_id":"curious_head_tilt"}
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
		"PLAYER_CANNOT_HELP":
			context.topic = "help"; context.pending_question = ""
			answer = "Oh, okay. Danke, dass du es sagst."
			reaction = "acknowledge_cannot_help"; emotion = "concerned"; animation = "soft_concern"
		"REQUEST_HELP":
			context.topic = "help"; context.pending_question = "help_target"
			answer = "Ja, gern. Was brauchst du?"
			reaction = "respond_to_help_request"; emotion = "friendly"; animation = "open_palm_offer"
		"REQUEST_SLOW_SPEECH":
			context.slow_speech = true; context.topic = "slow_speech"; context.pending_question = ""
			answer = "Ja. Ich spreche langsam."
			reaction = "speak_slowly"; emotion = "friendly"; animation = "gentle_nod"
		"REQUEST_REPEAT":
			context.topic = "repeat"; context.pending_question = ""
			if context.last_npc_line.is_empty():
				answer = "Was soll ich wiederholen?"
				reaction = "ask_what_to_repeat"; emotion = "curious"; animation = "curious_head_tilt"
			else:
				answer = "Ja, gern. Ich wiederhole es."
				reaction = "repeat_line"; emotion = "friendly"; animation = "gentle_nod"
		"REPORT_NONUNDERSTANDING":
			context.topic = "understanding"; context.pending_question = ""
			answer = "Oh! Was verstehst du nicht?"
			reaction = "ask_what_is_unclear"; emotion = "curious"; animation = "curious_head_tilt"
		"PLAYER_SPEECH_RATE":
			context.topic = "slow_speech"; context.pending_question = ""
			answer = "Oh, okay!"
			reaction = "acknowledge_speech_preference"; emotion = "friendly"; animation = "gentle_nod"
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
	var keys := ["busy","player_name","topic","selected_topic","awaiting_name","introduction_completed",
		"pending_question","pending_clarification","offered_help","help_requested","player_mood","astera_mood",
		"last_player_state","last_astera_state","player_plan","slow_speech","objective_progress","objective_evidence"]
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

