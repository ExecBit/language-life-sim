extends SceneTree
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _busy_context() -> Dictionary:
	var context := Session.initial_context()
	context.busy = true
	return context

func _why_context_answer() -> String:
	var context := Session.initial_context()
	context.topic = "astera_mood"
	context.last_npc_line = "Ich bin müde."
	return Session.submit("Warum?", context).answer

func _goodbye_line() -> String:
	return Session.submit("Bis später!", Session.initial_context()).answer

func run() -> void:
	var c := Session.initial_context()
	var parser_context := {"active":true,"addressee":"anna","pending":""}
	var r_matrix := [
		{"text":"Ich will Schlüssel", "intent":"REQUEST_ITEM"},
		{"text":"Ich brauche den Schlüssel", "intent":"REQUEST_ITEM"},
		{"text":"Schlüssel bitte", "intent":"REQUEST_ITEM"},
		{"text":"Wo ist der Schlüssel?", "intent":"ASK_LOCATION"},
		{"text":"Ich habe keinen Schlüssel", "intent":"REPORT_PROBLEM"},
		{"text":"Kannst du mir helfen?", "intent":"REQUEST_HELP"},
		{"text":"Kannst du die Tür öffnen?", "intent":"REQUEST_ACTION"},
		{"text":"Warum ist die Tür zu?", "intent":"ASK_REASON"},
		{"text":"Kann ich die Tür öffnen?", "intent":"ASK_PERMISSION"},
		{"text":"Ich brauchen Schlüssel", "intent":"REQUEST_ITEM"},
		{"text":"Ich will nicht öffnen", "intent":"EXPRESS_DESIRE"},
		{"text":"Anna hat keinen Schlüssel", "intent":"REPORT_STATE"}
	]
	for row in r_matrix:
		var row_result: Dictionary = Parser.parse(row.text, "", parser_context)
		check(row_result.status == "RECOGNIZED" and row_result.intent == row.intent, "parser matrix: %s → %s" % [row.text, row.intent])
	var item_frame: Dictionary = Parser.parse("Ich will Schlüssel", "", parser_context).frame
	check(item_frame.subject == "player" and item_frame.object_id == "key" and item_frame.polarity == "positive" and item_frame.speech_act == "request", "item frame fields preserve speaker, object, polarity and speech act")
	var action_frame: Dictionary = Parser.parse("Kannst du die Tür öffnen?", "", parser_context).frame
	check(action_frame.subject == "anna" and action_frame.action == "open" and action_frame.object_id == "door" and action_frame.speech_act == "request", "action frame distinguishes NPC action request from permission question")
	var subordinate := Parser.parse("Ich will nicht, dass Anna die Tür öffnet", "", parser_context)
	check(subordinate.status == "UNSUPPORTED" and subordinate.unsupported_features.has("SUBORDINATE_CLAUSE"), "subordinate clause remains unsupported")
	var prohibition: Dictionary = Parser.parse("Öffne die Tür nicht", "", parser_context)
	check(prohibition.frame.polarity == "negative" and prohibition.frame.speech_act == "prohibition" and prohibition.frame.object_id == "door", "negative command frame keeps polarity and target")
	var free_greeting := Session.submit("Hallo", c)
	c.busy = true
	var busy_greeting := Session.submit("Hallo", c)
	check(free_greeting.parse.intent == "GREETING" and busy_greeting.answer != free_greeting.answer, "same utterance gets context-dependent reply")
	var conversation := Session.initial_context()
	Session.opening_line(conversation)
	var named := Session.submit("Ich heiße Alex", conversation)
	check(named.parse.intent == "PLAYER_NAME" and conversation.player_name == "Alex" and named.answer.contains("Alex"), "player name is remembered and used in a response")
	for greeting_name in ["Hallo ich bin alex", "Hallo! Ich heiße Alex.", "Hi, ich bin Alex"]:
		var greeting_context := Session.initial_context()
		var greeting_result := Session.submit(greeting_name, greeting_context)
		check(greeting_context.player_name == "Alex" and greeting_result.parse.intent == "PLAYER_NAME" and greeting_result.objective_progress.introduce and greeting_result.answer == "Hallo, Alex! Schön!", "greeting plus introduction resolves once: " + greeting_name)
		check(greeting_result.parse.normalized_tokens[0] in ["hallo", "hi"] and greeting_result.parse.lexical_readings.back().readings[0].semantic_id == "player_name", "combined introduction keeps full tokens and name reading")
	for invalid_intro in ["Hallo ich bin Alex und ich fliege zum Mond", "Hallo ich bin nicht Alex", "Hallo ich bin müde und ich arbeite"]:
		var invalid_context := Session.initial_context()
		var invalid_result := Session.submit(invalid_intro, invalid_context)
		check(invalid_result.parse.status == "UNSUPPORTED" and invalid_context.player_name.is_empty() and not invalid_result.objective_progress.introduce and invalid_result.effects.is_empty(), "unsupported combined input cannot partially apply: " + invalid_intro)
	var greeted_tired := Session.submit("Hallo, ich bin müde", Session.initial_context())
	check(greeted_tired.parse.intent == "PLAYER_MOOD_LOW" and not greeted_tired.objective_progress.introduce, "greeting plus tiredness remains a mood statement")
	var activity_first := Session.submit("Was machst du?", Session.initial_context())
	check(activity_first.answer.contains("Ich arbeite.") and activity_first.animation_id == "point_at_object", "activity question works before the mood topic and reuses the player-directed gesture")
	var why_context := Session.initial_context(); why_context.topic = "astera_mood"; why_context.last_npc_line = "Ich bin müde."
	var why_answer := Session.submit("Warum?", why_context)
	check(why_answer.answer.contains("arbeite") and why_answer.reaction == "explain_tiredness", "why uses the tiredness context")
	var why_without_context := Session.submit("Warum?", Session.initial_context())
	check(why_without_context.answer.contains("Was meinst du") and why_without_context.effects.is_empty(), "why without context asks for clarification")
	var good_mood := Session.submit("Sehr gut!", Session.initial_context())
	var low_mood := Session.submit("Nicht gut.", Session.initial_context())
	check(good_mood.answer != low_mood.answer and good_mood.emotion_state == "happy" and low_mood.emotion_state == "concerned", "good and low moods produce distinct responses and emotions")
	var tired_input := Session.submit("Ich bin müde.", Session.initial_context())
	check(tired_input.parse.intent == "PLAYER_MOOD_LOW" and tired_input.parse.name.is_empty(), "I am tired is not mistaken for a player name")
	var quiet_response := Session.submit("Ja, ein bisschen.", Session.initial_context())
	check(quiet_response.parse.intent == "PLAYER_QUIET_ACK" and quiet_response.answer == "Oh! Okay!", "A0 quiet acknowledgment receives a playful contextual reply")
	check(Session.submit("Hilfe?", Session.initial_context()).parse.intent == "OFFER_HELP", "single-word A0 help offer is recognized")
	var neutral_npc_context := Session.initial_context(); neutral_npc_context.astera_mood = "neutral"
	check(Session.submit("Wie geht's dir?", neutral_npc_context).answer == "Gut, danke!", "F2 neutral NPC mood produces a distinct social reply")
	var reciprocal_context := Session.initial_context(); reciprocal_context.topic = "player_mood"
	var reciprocal := Session.submit("Und du?", reciprocal_context)
	var reciprocal_without_context := Session.submit("Und du?", Session.initial_context())
	check(reciprocal.answer.contains("Mir geht's gut") and reciprocal_without_context.answer.contains("Was möchtest du wissen"), "reciprocal question uses mood context or requests clarification")
	var free_plan := Session.submit("Ich habe frei.", Session.initial_context())
	var work_plan := Session.submit("Ich arbeite.", Session.initial_context())
	var learning_plan := Session.submit("Ich lerne Deutsch.", Session.initial_context())
	check(free_plan.answer != work_plan.answer and work_plan.answer != learning_plan.answer, "free day, work and learning plans produce distinct responses")
	var help_context := Session.initial_context()
	var help_offer := Session.submit("Kann ich helfen?", help_context)
	var help_accept := Session.submit("Ja, bitte!", help_context)
	check(help_offer.parse.intent == "OFFER_HELP" and help_accept.parse.intent == "ACCEPT_HELP" and help_context.offered_help and help_context.pending_question == "", "help offer and acceptance are remembered without pretending an object moved")
	var help_decline_context := Session.initial_context(); help_decline_context.pending_question = "help_offer"
	var help_decline := Session.submit("Nein, danke.", help_decline_context)
	check(help_decline.parse.intent == "DECLINE_HELP" and help_decline.effects.is_empty(), "declining help is distinct from accepting it")
	var learn_context := Session.initial_context()
	Session.submit("Ich lerne Deutsch", learn_context)
	var slow_accept := Session.submit("Ja, danke", learn_context)
	check(slow_accept.parse.intent == "ACCEPT_SLOW" and learn_context.slow_speech, "accepting slow German affects presentation context")
	var confused := Session.submit("Ich fliege zum Mond", Session.initial_context())
	check(confused.parse.status in ["UNKNOWN", "UNSUPPORTED"] and confused.effects.is_empty(), "unsupported free text remains explicitly unrecognized and has no effect")
	var goodbye := Session.submit("Bis später!", Session.initial_context())
	check(goodbye.animation_id == "farewell_wave" and goodbye.answer.contains("Bis später"), "farewell keeps the beginner line and original gesture")
	var cup_input := Session.submit("Was ist das?", Session.initial_context())
	check(cup_input.parse.status in ["UNKNOWN", "UNSUPPORTED", "NEEDS_CLARIFICATION"] and cup_input.effects.is_empty(), "removed prop topics do not resolve as scene interactions")
	var activity_objective := Session.submit("Was machst du?", Session.initial_context())
	check(activity_objective.objective_progress.ask_activity and activity_objective.objective_evidence.ask_activity.intent == "ASK_ACTIVITY", "objective progress records a processed activity question and its evidence")
	var unknown_objective := Session.submit("Ich fliege zum Mond", Session.initial_context())
	check(not unknown_objective.objective_progress.share_self, "unsupported text cannot advance a conversation objective")
	var out_of_order_context := Session.initial_context()
	Session.submit("Was machst du?", out_of_order_context)
	var out_of_order_name := Session.submit("Ich heiße Alex", out_of_order_context)
	check(out_of_order_name.objective_progress.introduce and out_of_order_name.objective_progress.ask_activity, "independent conversation goals retain progress in any order")
	var a0_lines: Array[String] = [
		Session.opening_line(Session.initial_context()).answer,
		Session.submit("Hallo", _busy_context()).answer,
		Session.submit("Alex", Session.initial_context()).answer,
		Session.submit("Wie geht's dir?", Session.initial_context()).answer,
		Session.submit("Gut, danke.", Session.initial_context()).answer,
		Session.submit("Wie geht's dir?", Session.initial_context()).answer,
		Session.submit("Sehr gut!", Session.initial_context()).answer,
		Session.submit("Nicht gut.", Session.initial_context()).answer,
		Session.submit("Ich bin müde.", Session.initial_context()).answer,
		Session.submit("Was machst du?", Session.initial_context()).answer,
		_why_context_answer(),
		Session.submit("Warum?", Session.initial_context()).answer,
		Session.submit("Ja, ein bisschen.", Session.initial_context()).answer,
		Session.submit("Und du?", Session.initial_context()).answer,
		Session.submit("Kann ich helfen?", Session.initial_context()).answer,
		Session.submit("Ich habe frei.", Session.initial_context()).answer,
		Session.submit("Ich arbeite.", Session.initial_context()).answer,
		Session.submit("Ich lerne Deutsch.", Session.initial_context()).answer,
		_goodbye_line()
	]
	var good_astera_context := Session.initial_context(); good_astera_context.astera_mood = "good"
	a0_lines.append(Session.submit("Wie geht's dir?", good_astera_context).answer)
	var neutral_astera_context := Session.initial_context(); neutral_astera_context.astera_mood = "neutral"
	a0_lines.append(Session.submit("Wie geht's dir?", neutral_astera_context).answer)
	var tired_player_context := Session.initial_context()
	Session.submit("Ich bin müde.", tired_player_context)
	a0_lines.append(Session.submit("Warum?", tired_player_context).answer)
	var reciprocal_context_for_line := Session.initial_context(); reciprocal_context_for_line.topic = "player_mood"
	a0_lines.append(Session.submit("Und du?", reciprocal_context_for_line).answer)
	var reciprocal_mood_context := Session.initial_context(); reciprocal_mood_context.topic = "astera_mood"
	a0_lines.append(Session.submit("Und du?", reciprocal_mood_context).answer)
	var ask_back_context := Session.initial_context(); ask_back_context.topic = "player_mood"
	var ask_back_line := Session.submit("Und du?", ask_back_context)
	a0_lines.append(ask_back_line.answer)
	check(ask_back_line.animation_id == "point_at_object", "compatible pointing gesture is used toward the player for a reciprocal question")
	var help_offer_context := Session.initial_context()
	Session.submit("Kann ich helfen?", help_offer_context)
	a0_lines.append(Session.submit("Ja, bitte!", help_offer_context).answer)
	var help_idle_context := Session.initial_context()
	a0_lines.append(Session.submit("Kann ich helfen?", help_idle_context).answer)
	var help_decline_context_for_line := Session.initial_context(); help_decline_context_for_line.pending_question = "help_offer"
	a0_lines.append(Session.submit("Nein, danke.", help_decline_context_for_line).answer)
	var slow_offer_context := Session.initial_context()
	a0_lines.append(Session.submit("Ich lerne Deutsch.", slow_offer_context).answer)
	a0_lines.append(Session.submit("Ja, bitte.", slow_offer_context).answer)
	var slow_decline_context := Session.initial_context(); slow_decline_context.pending_question = "slow_speech"
	a0_lines.append(Session.submit("Nein, danke.", slow_decline_context).answer)
	var named_goodbye_context := Session.initial_context(); named_goodbye_context.player_name = "Alex"
	a0_lines.append(Session.submit("Tschüss!", named_goodbye_context).answer)
	a0_lines.append_array([
		"Gern!", "Bitte!", "Okay!", "Bitte noch einmal.", "Ja!", "Ich weiß es nicht.", "Das geht nicht.", "Du bist sehr still!",
		"Was brauchst du?", "Okay. Ich mache das nicht.", "Was möchtest du wissen?", "Das tut mir leid."
	])
	var uncovered_forms: Array[String] = []
	for npc_line in a0_lines:
		for token in DialogueGrammar.words(npc_line):
			if (not DialogueGrammar.LEXICON.has(token) or DialogueGrammar.translation_for(token).is_empty()) and token not in ["alex", "astera"] and not uncovered_forms.has(token):
				uncovered_forms.append(token)
	check(uncovered_forms.is_empty(), "A0 NPC utterance forms all have F1 entries: %s" % ", ".join(uncovered_forms))
	var player_variants := ["Ich bin Alex.", "Alex.", "Gut, danke.", "Sehr gut!", "Nicht gut.", "Ich bin müde.",
		"Warum?", "Was machst du?", "Was machst du heute?", "Ich lerne Deutsch.", "Ich arbeite.",
		"Ich habe frei.", "Kann ich helfen?", "Hilfe?", "Ja, bitte!", "Nein, danke.", "Bis später!", "Tschüss!"]
	var uncovered_player_forms: Array[String] = []
	for player_line in player_variants:
		for token in DialogueGrammar.words(player_line):
			if (not DialogueGrammar.LEXICON.has(token) or DialogueGrammar.translation_for(token).is_empty()) and token != "alex" and not uncovered_player_forms.has(token):
				uncovered_player_forms.append(token)
	check(uncovered_player_forms.is_empty(), "A0 player-response forms also appear in F1: %s" % ", ".join(uncovered_player_forms))
	var phrase_entries: Array[Dictionary] = DialogueGrammar.vocabulary_entries().filter(func(entry): return entry.pos == "phrase")
	var phrases_translated := not phrase_entries.is_empty()
	for entry in phrase_entries:
		if DialogueGrammar.translation_for(entry.surface).is_empty(): phrases_translated = false
	check(phrases_translated, "F1 provides Russian translations for whole phrase entries")
	check(DialogueGrammar.translation_for("Wie geht's dir?") == "Как дела?" and DialogueGrammar.translation_for("Bis später!") == "До встречи!" and DialogueGrammar.translation_for("Ich arbeite heute viel.") == "Я сегодня много работаю." and DialogueGrammar.translation_for("vielleicht später.") == "Может быть, позже." and DialogueGrammar.translation_for("Das ist nett!") == "Это мило!", "idiomatic dialogue and activity lines use contextual phrase translations")
	c.busy = false
	var world_key_context := Session.initial_context(); world_key_context.key_owner = "world"
	var unavailable_key := Session.submit("Ich brauche den Schlüssel", world_key_context)
	check(unavailable_key.effects.is_empty() and world_key_context.key_owner == "world", "legacy key request remains inert in the social-only lab")
	var busy_key_context := Session.initial_context(); busy_key_context.busy = true; busy_key_context.key_owner = "anna"
	var busy_key := Session.submit("Ich brauche den Schlüssel", busy_key_context)
	check(busy_key.effects.is_empty() and busy_key_context.key_owner == "anna", "busy state does not create a hidden item interaction")
	var unknown_location_context := Session.initial_context(); unknown_location_context.knows_key = false
	var unknown_location := Session.submit("Wo ist der Schlüssel?", unknown_location_context)
	check(unknown_location.answer == "Ich weiß es nicht." and unknown_location.effects.is_empty(), "unsupported location request does not invent a world fact")
	var door_context := Session.initial_context(); door_context.door_open = false
	var door_request := Session.submit("Kannst du die Tür öffnen?", door_context)
	check(door_request.parse.intent == "REQUEST_ACTION" and not door_context.door_open and door_request.effects.is_empty(), "legacy door request stays a parser-only regression without a world effect")
	var blocked_door_context := Session.initial_context(); blocked_door_context.busy = true; blocked_door_context.door_open = false
	var blocked_door := Session.submit("Kannst du die Tür öffnen?", blocked_door_context)
	check(not blocked_door_context.door_open and blocked_door.effects.is_empty(), "busy Anna leaves the door closed")
	c.pending = "offer"
	check(Parser.parse("Ja", "", {"active":true,"pending":"offer"}).intent == "ACCEPT", "Ja inside pending offer")
	check(Parser.parse("Ja", "", {"active":true,"pending":""}).status == "NEEDS_CLARIFICATION", "Ja outside pending offer")
	check(Parser.parse("Nein", "", {"active":true,"pending":"offer"}).intent == "REFUSE", "Nein inside pending offer")
	check(Parser.parse("Nein", "", {"active":true,"pending":""}).status == "NEEDS_CLARIFICATION", "Nein outside pending offer")
	var fragment := Parser.parse("Schlüssel?", "", {"active":true,"pending":""})
	var location := Session.submit("Wo ist der Schlüssel?", c)
	check(fragment.status == "NEEDS_CLARIFICATION" and location.answer == "Ich weiß es nicht.", "key fragment asks clarification; unsupported scene topic remains inert")
	c.door_open = false
	var before_door: bool = c.door_open
	var negative := Session.submit("Öffne die Tür nicht.", c)
	check(negative.parse.status == "RECOGNIZED" and negative.parse.intent == "PROHIBIT_ACTION" and c.door_open == before_door and negative.effects.is_empty(), "negative command does not change world")
	var unsupported := Session.submit("Ich gehe zum Markt.", c)
	check(unsupported.parse.status in ["UNKNOWN", "UNSUPPORTED"] and unsupported.effects.is_empty(), "unsupported or unknown phrase has no effect")
	var missing := Session.submit("Ich will Flöte.", c)
	check(missing.parse.status == "UNKNOWN" and missing.effects.is_empty(), "word absent from catalog remains typeable and reports unknown")
	c.key_owner = "anna"
	var first := Session.submit("Ich brauche den Schlüssel", c)
	var second := Session.submit("Ich brauche den Schlüssel", c)
	check(first.effects.is_empty() and second.effects.is_empty() and c.key_owner == "anna", "repeated legacy item requests cannot produce scene effects")
	c.pending = "offer"; c.door_open = true
	Session.reset(c)
	check(c.pending == "" and not c.has("door_open") and not c.has("key_owner"), "reset clears legacy object state from the conversation context")
	var room := (load("res://implementations/communication_lab/communication_lab.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	var player: Node = room.get("player")
	var hud: Control = player.get("player_hud")
	var communication_panel: Control = room.get("dialog")
	check(not hud.visible, "standard Cogito HUD is hidden in the lab")
	check(communication_panel.anchor_left == 0.0 and communication_panel.anchor_right == 1.0 and communication_panel.anchor_bottom == 1.0 and communication_panel.offset_left == 0.0 and communication_panel.offset_right == 0.0, "conversation panel spans the bottom screen width")
	check(room.get_node_or_null("Table") == null, "obstructing table is removed")
	check(room.get_node_or_null("Cup") == null and room.get_node_or_null("Key") == null and room.get_node_or_null("Door") == null, "social-only scene contains no object props or interactions")
	check(room.get("objective_labels").size() == 6 and room.get("objective_panel").visible, "six unobtrusive social objectives are visible from the start")
	check(not Session.initial_context().has("key_owner") and not Session.initial_context().has("door_open"), "object state is absent from the live communication context")
	var preserved_motions := ["greeting_wave", "self_introduction", "curious_head_tilt", "small_happy_reaction", "tired_sigh", "playful_shrug", "gentle_nod", "farewell_wave", "open_palm_offer", "surprised_delighted", "point_at_object", "soft_concern"]
	var missing_motions: Array[String] = []
	for motion_id in preserved_motions:
		if not room.get("motion_paths").has(motion_id): missing_motions.append(motion_id)
	check(missing_motions.is_empty(), "all twelve existing generated motion IDs remain available: %s" % ", ".join(missing_motions))
	var astera: Node = room.get_node("Astera")
	var expected_avatar := "res://implementations/communication_lab/assets/characters/avatar_sample_b.vrm"
	check(astera.get("avatar_path_in_use") == expected_avatar, "AvatarSample_B is the selected conversation avatar")
	check(room.call("_can_interact"), "spawn position is inside Astera conversation range")
	var idle_player: AnimationPlayer = astera.get("animation_player")
	check(idle_player.is_playing() and idle_player.current_animation == "lab/standing", "NPC plays the retargeted idle animation")
	var face_channels: Dictionary = astera.get("expression_channels")
	check(not face_channels.is_empty(), "selected avatar has discovered VRM expression channels")
	print("VRM_EXPRESSION_CHANNELS: ", JSON.stringify(face_channels.keys()))
	astera.call("set_emotion", "happy")
	for i in 30: await process_frame
	var face_mesh: MeshInstance3D = astera.get("face_mesh")
	var joyful_channel_used := false
	for channel in face_channels:
		if str(channel) == "morph_3" and face_mesh.get_blend_shape_value(face_channels[channel]) > 0.1: joyful_channel_used = true
	check(joyful_channel_used, "happy emotion smoothly drives the selected VRM joy blendshape")
	var suggestions: Array = Parser.suggestions("mü")
	check(suggestions.has("müde"), "new dialogue vocabulary is included in composer suggestions")
	var open_event := InputEventKey.new(); open_event.keycode = KEY_E; open_event.pressed = true
	room.call("_input", open_event)
	check(astera.get("active_animation_id") == "greeting_wave" and room.get("transcript").get_parsed_text().contains("Hallo"), "opening encounter plays a greeting motion and line")
	check(room.get("dialog").visible and player.get("is_movement_paused"), "E interaction opens the conversation and pauses player movement")
	var h_event := InputEventKey.new(); h_event.keycode = KEY_H; h_event.pressed = true
	check(not room.get("composer").route_key(h_event), "H is not consumed as a word-memo shortcut while typing")
	var memo_event := InputEventKey.new(); memo_event.keycode = KEY_F1; memo_event.pressed = true
	room.call("_input", memo_event)
	check(room.get("vocabulary_card").visible, "F1 opens the word memo while the phrase field is active")
	var phrase_helper_found := false
	for row in room.get("vocabulary_rows"):
		if row.get("search", "").contains("wie geht's dir"): phrase_helper_found = true
	room.get("vocabulary_search").text = "Wie geht's dir"
	room.call("_filter_vocabulary", "Wie geht's dir")
	var visible_helper_matches := 0
	for row in room.get("vocabulary_rows"):
		if not row.header and row.label.visible: visible_helper_matches += 1
	check(phrase_helper_found and visible_helper_matches == 1, "F1 search narrows to a single contextual phrase translation")
	room.get("vocabulary_search").clear()
	room.call("_filter_vocabulary", "")
	room.call("_input", memo_event)
	check(not room.get("vocabulary_card").visible, "F1 closes the word memo without closing the conversation")
	var editor = room.get("composer")
	editor.phrase.clear(); editor.prefix.text = "wi"; editor.update_matches("wi"); editor.prefix.grab_focus()
	var tab_event := InputEventKey.new(); tab_event.keycode = KEY_TAB; tab_event.pressed = true
	editor.route_key(tab_event)
	check(editor.matches.get_selected_items()[0] == 1 and editor.phrase.text == "", "Tab cycles suggestions without inserting a word")
	var chosen_word: String = editor.matches.get_item_text(1)
	var space_event := InputEventKey.new(); space_event.keycode = KEY_SPACE; space_event.pressed = true
	editor.route_key(space_event)
	check(editor.phrase.text == chosen_word and editor.prefix.text == "", "Space inserts the selected suggestion into the main phrase")
	editor.phrase.grab_focus()
	check(not editor.route_key(space_event), "Space remains normal text input in the main phrase")
	await create_timer(0.7).timeout
	check(root.get_camera_3d() == room.get("conversation_camera") and is_equal_approx(room.get("conversation_camera").fov, 40.0), "dialogue camera completes its smooth close-up")
	room.call("_on_submitted", "Was machst du?")
	check(astera.get("active_animation_id") == "point_at_object" and room.get("last_record").get("reaction") == "explain_activity_and_invite_player", "conversation response triggers the compatible gesture toward the player")
	check(room.get("context").objective_progress.ask_activity and room.get("context").objective_evidence.ask_activity.input == "Was machst du?", "handled dialogue action updates the visible objective and records its basis")
	check(room.get("objective_labels").ask_activity.text.begins_with("✓") and room.get("context_view").text.contains("objective_evidence"), "F2 shows objective status and its diagnostic evidence")
	check(room.get("conversation_lines").size() == 3 and room.get("transcript").get_parsed_text().contains("Вы  Was machst du?"), "player-visible transcript retains greeting, player message and NPC response")
	check(room.get("transcript").visible_characters < room.get("transcript").get_total_character_count(), "new NPC response starts a text reveal animation")
	room.call("_finish_reply_reveal")
	check(room.get("transcript").visible_characters == -1, "reply reveal can be completed immediately")
	editor.phrase.text = "Ich brauche den Schlüssel"; editor.send()
	check(astera.get("active_animation_id") == "open_palm_offer" and editor.phrase.text.is_empty(), "actual composer submission triggers a legacy reply gesture and clears the sent draft")
	await create_timer(0.4).timeout
	idle_player.seek(1.5, true)
	await process_frame
	var rig: Skeleton3D = astera.get("rig_skeleton")
	var before_pose: Array[Quaternion] = []
	for bone in rig.get_bone_count(): before_pose.append(rig.get_bone_pose_rotation(bone))
	editor.phrase.text = "Ich brauche den Schlüssel"; editor.send()
	check(idle_player.current_animation_position < 0.1 and astera.get("active_animation_id") == "open_palm_offer", "repeated submission restarts the same gesture at its beginning")
	await create_timer(0.4).timeout
	var changed_bone := false
	for bone in rig.get_bone_count():
		if before_pose[bone].angle_to(rig.get_bone_pose_rotation(bone)) > 0.03: changed_bone = true
	check(changed_bone, "restarted gesture actually changes skeletal pose")
	await create_timer(4.25).timeout
	check(astera.get("active_animation_id") == "standing", "conversation gesture returns to idle")
	var original_camera: Camera3D = room.get("exploration_camera")
	room.call("_close_dialog")
	check(root.get_camera_3d() == original_camera and not player.get("is_movement_paused"), "closing dialogue restores exploration camera and movement")
	var retained_lines: int = room.get("conversation_lines").size()
	room.call("_open_dialog")
	check(room.get("conversation_lines").size() == retained_lines, "reopening conversation preserves its transcript without duplicating the greeting")
	check(room.get("context").objective_progress.ask_activity, "objective progress survives closing and returning to the conversation")
	room.call("_reset")
	check(room.get("conversation_lines").is_empty() and room.get("transcript").get_parsed_text().is_empty(), "reset clears player-visible conversation while diagnostic attempt history remains")
	room.call("_open_dialog")
	room.call("_process", room.get("SILENCE_TEASE_DELAY"))
	check(room.get("conversation_lines").back().text == "Du bist sehr still!" and room.get("astera_visual").get("active_animation_id") == "playful_shrug", "long conversational silence triggers the playful A0 nudge and motion")
	check(not room.get("context").objective_progress.ask_activity and room.get("objective_labels").ask_activity.text.begins_with("○"), "reset clears and visually refreshes objective progress")
	room.call("_reset")
	room.get("composer").phrase.text = "Hallo ich bin alex"
	room.get("composer").send()
	check(room.get("context").player_name == "Alex" and room.get("conversation_lines").size() == 2 and room.get("conversation_lines").back().text == "Hallo, Alex! Schön!", "actual composer accepts greeting plus name with one NPC reply")
	room.queue_free()
	await process_frame
	print("COMMUNICATION_LAB_TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
