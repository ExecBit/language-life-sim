extends SceneTree
## Integration checks only, not language-quality evidence. No model inference here.
const Client = preload("res://implementations/communication_lab/game/communication/lfm_client.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
var failures := 0
class DelayedClient extends Node:
	var config := {"enabled":true}
	var calls := 0
	func interpret(text: String, context: Dictionary) -> Dictionary:
		calls += 1
		await get_tree().create_timer(0.1).timeout
		return Client.validate_meaning(text, {"intent":"REPORT_NO_CARD","name":"","needs_clarification":false,"clarification":""}, context)
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func run() -> void:
	var context := Session.initial_context()
	var invalid := Client.validate_meaning("anything", {"intent":"grant_admin","name":"","needs_clarification":false,"clarification":""}, context)
	check(Session.submit_interpreted("anything", context, invalid).transition_id.is_empty(), "unknown model label cannot execute an edge")
	var unbound := Client.validate_meaning("yes", {"intent":"SHORT_YES","name":"","needs_clarification":false,"clarification":""}, context)
	check(Session.submit_interpreted("yes", context, unbound).effects.is_empty(), "model yes needs a real pending proposition")
	var nameless := Client.validate_meaning("anything", {"intent":"PLAYER_NAME","name":"","needs_clarification":false,"clarification":""}, context)
	check(nameless.status == "UNKNOWN", "model label cannot claim a complete name meaning without its value")
	var departure := Session.initial_context()
	var farewell := Client.validate_meaning("Tschüss.", {"intent":"FAREWELL","name":"","needs_clarification":false,"clarification":""}, departure)
	var left := Session.submit_interpreted("Tschüss.", departure, farewell)
	check(departure.current_node == "E_LEAVE" and left.effects.is_empty(), "a valid farewell keeps its actual speaker and follows the authored edge")
	var client := Client.new()
	root.add_child(client)
	client.config.prompt_version = "context-v2"
	var history_context := Session.initial_context()
	Session.opening_line(history_context)
	Session.submit("Ich habe keine Karte.", history_context)
	check(history_context.dialogue_history.back().npc_reply == history_context.last_npc_line, "history stores the actual NPC reply for context")
	history_context.selected_action = "claim_technician"
	var body: Dictionary = client.build_request("Du hast keine Karte.", history_context)
	var user: Dictionary = JSON.parse_string(body.messages[1].content)
	check(user.player_utterance == "Du hast keine Karte." and user.reference_context.npc_last_reply == history_context.last_npc_line, "original utterance and current NPC wording remain distinct")
	check(user.reference_context.recent_dialogue.back().npc == history_context.last_npc_line, "prompt history uses actual replies")
	check(not user.reference_context.has("selected_action") and not body.messages[1].content.contains("semantic_evidence"), "menu goals and recursive old model requests are excluded")
	client.config.port = 38179
	client.config.auto_start = false
	var unavailable: Dictionary = await client.interpret("test", context)
	check(unavailable.reason == "SERVER_UNAVAILABLE" and not unavailable.notification.is_empty(), "unavailable server is explicit and not a grammar fallback")
	client.queue_free()
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	await process_frame
	room.language_client.queue_free()
	var delayed := DelayedClient.new()
	room.add_child(delayed)
	room.language_client = delayed
	room._open_dialog()
	room._select_dialogue_action("report_no_card")
	room.composer.phrase.text = "test"
	room.composer.send()
	room.composer.send()
	check(delayed.calls == 1 and room.language_busy, "duplicate Enter cannot dispatch twice")
	room._close_dialog()
	await create_timer(0.2).timeout
	check(room.context.current_node == "G00_GATE" and room.attempts.is_empty(), "late model answer after close cannot change plot or history")
	room._open_dialog()
	room._select_dialogue_action("report_no_card")
	room.composer.phrase.text = "test"
	room.composer.send()
	room._reset()
	await create_timer(0.2).timeout
	check(room.context.current_node == "G00_GATE" and room.attempts.is_empty() and not room.language_busy, "reset invalidates in-flight model answer")
	room.queue_free()
	await process_frame
	print("LFM_BOUNDARY: %d failure(s); transport/lifecycle only" % failures)
	quit(1 if failures else 0)
