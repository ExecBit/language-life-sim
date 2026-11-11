extends SceneTree
const Parser = preload("res://implementations/communication_lab/game/communication/parser.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const LabScene = preload("res://implementations/communication_lab/communication_lab.tscn")
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
	var room := LabScene.instantiate()
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
	var idle_player: AnimationPlayer = astera.get("animation_player")
	check(idle_player.is_playing() and idle_player.current_animation == "lab/standing", "NPC plays the retargeted idle animation")
	room.queue_free()
	await process_frame
	print("COMMUNICATION_LAB_TESTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
