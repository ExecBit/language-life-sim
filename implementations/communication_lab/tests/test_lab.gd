extends SceneTree
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

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
	var activity_first := Session.submit("Was machst du?", Session.initial_context())
	check(activity_first.answer.contains("räume auf") and activity_first.animation_id == "point_at_object", "activity question works before the mood topic and points at the cup")
	var why_context := Session.initial_context(); why_context.topic = "astera_mood"; why_context.last_npc_line = "Ich bin müde."
	var why_answer := Session.submit("Warum?", why_context)
	check(why_answer.answer.contains("Arbeit") and why_answer.reaction == "explain_tiredness", "why uses the tiredness context")
	var why_without_context := Session.submit("Warum?", Session.initial_context())
	check(why_without_context.answer.contains("Warum genau") and why_without_context.effects.is_empty(), "why without context asks for clarification")
	var good_mood := Session.submit("Sehr gut!", Session.initial_context())
	var low_mood := Session.submit("Nicht so gut.", Session.initial_context())
	check(good_mood.answer != low_mood.answer and good_mood.emotion_state == "happy" and low_mood.emotion_state == "concerned", "good and low moods produce distinct responses and emotions")
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
	check(goodbye.animation_id == "farewell_wave" and goodbye.answer.contains("Bis dann"), "farewell selects its authored line and gesture")
	c.busy = false
	var world_key_context := Session.initial_context(); world_key_context.key_owner = "world"
	var unavailable_key := Session.submit("Ich brauche den Schlüssel", world_key_context)
	check(unavailable_key.effects.is_empty() and world_key_context.key_owner == "world", "request does not transfer a key held elsewhere")
	var busy_key_context := Session.initial_context(); busy_key_context.busy = true
	var busy_key := Session.submit("Ich brauche den Schlüssel", busy_key_context)
	check(busy_key.effects.is_empty() and busy_key_context.key_owner == "anna", "busy Anna does not transfer her key")
	var unknown_location_context := Session.initial_context(); unknown_location_context.knows_key = false
	var unknown_location := Session.submit("Wo ist der Schlüssel?", unknown_location_context)
	check(unknown_location.answer == "Das weiß ich nicht." and unknown_location.effects.is_empty(), "unknown location is not invented")
	var door_context := Session.initial_context()
	var door_request := Session.submit("Kannst du die Tür öffnen?", door_context)
	check(door_request.parse.intent == "REQUEST_ACTION" and door_context.door_open and door_request.effects.size() == 1, "free Anna opens the door only after a request")
	var blocked_door_context := Session.initial_context(); blocked_door_context.busy = true
	var blocked_door := Session.submit("Kannst du die Tür öffnen?", blocked_door_context)
	check(not blocked_door_context.door_open and blocked_door.effects.is_empty(), "busy Anna leaves the door closed")
	c.pending = "offer"
	check(Parser.parse("Ja", "", {"active":true,"pending":"offer"}).intent == "ACCEPT", "Ja inside pending offer")
	check(Parser.parse("Ja", "", {"active":true,"pending":""}).status == "NEEDS_CLARIFICATION", "Ja outside pending offer")
	check(Parser.parse("Nein", "", {"active":true,"pending":"offer"}).intent == "REFUSE", "Nein inside pending offer")
	check(Parser.parse("Nein", "", {"active":true,"pending":""}).status == "NEEDS_CLARIFICATION", "Nein outside pending offer")
	var fragment := Parser.parse("Schlüssel?", "", {"active":true,"pending":""})
	var location := Session.submit("Wo ist der Schlüssel?", c)
	check(fragment.status == "NEEDS_CLARIFICATION" and location.answer.contains("Tisch"), "key fragment asks clarification; full location question resolves")
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
	check(first.effects.size() == 1 and second.effects.is_empty() and c.key_owner == "player", "repeat does not duplicate item transfer")
	c.pending = "offer"; c.door_open = true
	Session.reset(c)
	check(c.pending == "" and c.door_open == false and c.key_owner == "anna", "reset restores initial context and clears pending")
	var room := (load("res://implementations/communication_lab/communication_lab.tscn") as PackedScene).instantiate()
	root.add_child(room)
	await process_frame
	var player: Node = room.get("player")
	var hud: Control = player.get("player_hud")
	var communication_panel: Control = room.get("dialog")
	check(not hud.visible, "standard Cogito HUD is hidden in the lab")
	check(communication_panel.name == "CommunicationPanel" and communication_panel.anchor_left == 0.0 and communication_panel.anchor_bottom == 1.0 and communication_panel.offset_left == 18.0, "communication panel occupies the bottom-left HUD position")
	var astera: Node = room.get_node("Astera")
	var expected_avatar := "res://assets/characters/private/astera.vrm" if ResourceLoader.exists("res://assets/characters/private/astera.vrm") else "res://assets/characters/anna.vrm"
	check(astera.get("avatar_path_in_use") == expected_avatar, "Astera is selected when available with redistributable fallback")
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
	check(joyful_channel_used, "happy emotion smoothly drives the Astera VRM joy blendshape")
	var suggestions: Array = Parser.suggestions("mü")
	check(suggestions.has("müde"), "new dialogue vocabulary is included in composer suggestions")
	var open_event := InputEventKey.new(); open_event.keycode = KEY_E; open_event.pressed = true
	room.call("_input", open_event)
	check(astera.get("active_animation_id") == "greeting_wave" and room.get("reply_label").text.contains("Hallo"), "opening encounter plays a greeting motion and line")
	check(room.get("dialog").visible and player.get("is_movement_paused"), "E interaction opens the conversation and pauses player movement")
	var h_event := InputEventKey.new(); h_event.keycode = KEY_H; h_event.pressed = true
	check(not room.get("composer").route_key(h_event), "H is not consumed as a word-memo shortcut while typing")
	var memo_event := InputEventKey.new(); memo_event.keycode = KEY_F1; memo_event.pressed = true
	room.call("_input", memo_event)
	check(room.get("vocabulary_card").visible, "F1 opens the word memo while the phrase field is active")
	room.call("_input", memo_event)
	check(not room.get("vocabulary_card").visible, "F1 closes the word memo without closing the conversation")
	room.call("_on_submitted", "Was machst du?")
	check(astera.get("active_animation_id") == "point_at_object" and room.get("last_record").get("reaction") == "explain_activity_and_point_out_cup", "conversation response triggers selected generated motion")
	await create_timer(4.25).timeout
	check(astera.get("active_animation_id") == "standing", "conversation gesture returns to idle")
	room.queue_free()
	await process_frame
	print("COMMUNICATION_LAB_TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
