extends SceneTree
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
var failures := 0
var assertions := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func ask(name: String) -> Dictionary:
	var c := Session.initial_context()
	Session.opening_line(c)
	Session.submit("ich habe kein karte", c)
	Session.submit("ich bin neu", c)
	Session.submit("ich bin " + name, c)
	Session.submit("ich mochte vorläufige pass", c)
	Session.submit("ja", c)
	check(c.current_node == "G50_CONFIRM", "reproduced screenshot route " + name)
	return c
func run() -> void:
	for name in ["Alex", "Neral"]:
		for phrase in ["ja ich bin %s", "Ja, ich bin %s.", "Ja. Ich bin %s.", "ich bin %s", "ich heiße %s", "%s", "ja ich heiße %s", "ja %s"]:
			var c := ask(name)
			var r := Session.submit(phrase % name.to_lower(), c)
			check(c.current_node == "E_OFFICIAL" and c.has_pass and r.parse.frame.get("proposition_id", "") == "confirm_player_name", "full confirmation: " + phrase % name)
			check(Session.submit("Ja", c).effects.is_empty(), "no duplicate pass")
	for phrase in ["nein ich bin nicht Alex", "ich bin nicht Alex", "nein ich bin Neral", "ich bin Neral"]:
		var c := ask("Alex")
		var r := Session.submit(phrase, c)
		check(c.current_node == "G30_NAME" and not c.has_pass and r.parse.frame.get("confirmation", "") == "no", "identity disagreement: " + phrase)
	for phrase in ["ja ich bin Neral", "nein ich bin Alex", "ja ich bin nicht Alex", "ich bin nicht Neral", "ja du bist Alex", "ja ich bin Alex Karte", "ja ich bin Alex blorple", "ja ich möchte Alex sein"]:
		var c := ask("Alex")
		var r := Session.submit(phrase, c)
		check(c.current_node == "G50_CONFIRM" and not c.has_pass and r.effects.is_empty(), "no guessed confirmation: " + phrase)
		check(Session.submit("Ja", c).transition_id == "T_G50_CONFIRM", "retry answers the authored question after: " + phrase)
	var retry := ask("Alex")
	Session.submit("ich blorple helfen", retry)
	check(Session.submit("ja", retry).transition_id == "T_G50_CONFIRM", "failed wording preserves the authored question for retry")
	var unrelated := Session.initial_context()
	check(Session.submit("ja ich bin Alex", unrelated).transition_id.is_empty() and not unrelated.has_pass, "a name is not a confirmation outside a question")
	print("PROPOSITION_ANSWERS: %d failure(s), %d assertions" % [failures, assertions])
	quit(1 if failures else 0)
