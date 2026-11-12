extends SceneTree
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
var failures := 0
var assertions := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func send(c: Dictionary, action: String, phrase: String) -> Dictionary:
	Session.select_action(action, c)
	return Session.submit(phrase, c)
func registered() -> Dictionary:
	var c := Session.initial_context()
	Session.opening_line(c)
	send(c, "report_no_card", "Ich habe keine Karte.")
	send(c, "report_newcomer", "Ich bin neu.")
	send(c, "introduce", "Ich heiße Neral.")
	return c
func exposed() -> Dictionary:
	var c := Session.initial_context()
	Session.opening_line(c)
	send(c, "claim_technician", "Ich bin Techniker.")
	send(c, "introduce", "Ich heiße Neral.")
	return c
func run() -> void:
	var c := registered()
	check(c.current_node == "G40_REGISTERED", "test context reached through actual runtime")
	for phrase in ["Ich möchte einen Pass.", "Kann ich einen Pass bekommen?", "Darf ich einen Pass haben?", "Ich brauche einen Pass.", "Ich möchte einen vorläufigen Pass."]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.status == "RECOGNIZED" and p.intent == "REQUEST_PASS" and p.frame.polarity == "positive", "request versus possession: " + phrase)
	for phrase in ["Ich habe keinen Pass.", "Ich hab keine Karte.", "ich keine Karte"]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.status == "RECOGNIZED" and p.intent == "REPORT_NO_CARD", "recoverable possession: " + phrase)
	for phrase in ["Ich möchte keinen Pass.", "Ich will keinen Pass."]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.intent not in ["REQUEST_PASS", "REPORT_NO_CARD", "REPORT_HAS_CARD"] and str(p.frame.get("polarity", "")) == "negative", "negative desire is not missing possession: " + phrase)
	for phrase in ["Ich möchte vorläufigen", "Ich möchte einen vorläufigen.", "Einen vorläufigen, bitte."]:
		var attempt := registered()
		var r := send(attempt, "request_pass", phrase)
		check(r.parse.status == "NEEDS_CLARIFICATION" and attempt.current_node == "G40_REGISTERED" and not attempt.has_pass, "ellipsis waits: " + phrase)
		check(r.answer.to_lower().contains("pass") and not attempt.pending_resolution.is_empty(), "ellipsis asks about the missing object: " + phrase)
		var yes := send(attempt, "confirm_proposition", "Ja")
		check(attempt.current_node == "G50_CONFIRM" and not yes.transition_id.is_empty(), "yes resolves the preserved meaning once")
	var rejected := registered()
	send(rejected, "request_pass", "Ich möchte einen vorläufigen.")
	send(rejected, "reject_proposition", "Nein")
	check(rejected.current_node == "G40_REGISTERED" and rejected.pending_resolution.is_empty(), "no cancels semantic clarification")
	var expired := registered()
	send(expired, "request_pass", "Ich möchte vorläufigen")
	Session.submit("Ich bin kein Techniker.", expired)
	var stale := Session.submit("Ja", expired)
	check(stale.transition_id.is_empty() and expired.current_node == "G40_REGISTERED", "new content expires old inferred request")
	var closed := registered()
	send(closed, "request_pass", "Ich möchte vorläufigen")
	Session.close_dialog(closed)
	check(Session.submit("Ja", closed).transition_id.is_empty(), "closing cancels transient semantic confirmation")
	for phrase in ["Ich bin Techniker nein", "Ich bin nein Techniker", "Ich bin Techniker, nein."]:
		var attempt := exposed()
		var r := send(attempt, "claim_technician", phrase)
		check(r.parse.status == "NEEDS_CLARIFICATION" and attempt.trust == "neutral" and r.effects.is_empty(), "self repair cannot penalize player: " + phrase)
		check(r.answer.to_lower().contains("kein"), "self repair proposes denial, not a positive role")
	var denial := exposed()
	send(denial, "deny_technician", "Nein")
	check(denial.current_node == "G20_RULES" and denial.trust == "neutral", "short no binds to the challenged role")
	for actor in ["Ich", "Du"]:
		for negative in [false, true]:
			var recipient := "dir" if actor == "Ich" else "mir"
			var modal := "kann" if actor == "Ich" else "kannst"
			for ending in [".", "?"]:
				var phrase := "%s %s %s %shelfen%s" % [actor, modal, recipient, "nicht " if negative else "", ending]
				var p := Language.analyze_rpg(phrase, Session.initial_context())
				check(str(p.frame.get("actor", "")) == ("player" if actor == "Ich" else "astera"), "help subject role: " + phrase)
				check(str(p.frame.get("polarity", "")) == ("negative" if negative else "positive"), "help polarity: " + phrase)
				if negative: check(p.intent not in ["OFFER_HELP", "REQUEST_HELP"], "negative help cannot become positive")
	for phrase in ["Ich bin Techniker, aber ich bin kein Techniker.", "Ich habe keine Karte und bin neu.", "Ich habe keine Karte. Ich bin neu."]:
		var attempt := exposed()
		var r := send(attempt, "claim_technician", phrase)
		check(r.transition_id.is_empty() and r.effects.is_empty() and r.parse.status in ["UNSUPPORTED", "NEEDS_CLARIFICATION"], "compound/contradiction is not partially executed: " + phrase)
	for phrase in ["Ich habe keine Karte blorple", "Ich bin Techniker wenn blorple"]:
		var attempt := exposed()
		var r := send(attempt, "claim_technician", phrase)
		check(r.parse.status == "UNKNOWN" and r.transition_id.is_empty() and attempt.trust == "neutral", "unknown content is not dropped: " + phrase)
	var other := Language.analyze_rpg("Du bist Techniker.", exposed())
	check(other.intent != "CLAIM_TECHNICIAN", "other participant is not the player")
	var wish := Language.analyze_rpg("Ich möchte Techniker sein.", exposed())
	check(wish.intent != "CLAIM_TECHNICIAN", "wanting a role is not asserting it")
	var message := Language.analyze_rpg("Kannst du Tom eine Nachricht geben?", c)
	check(message.intent != "ACCEPT_MESSAGE" and message.frame.get("actor", "") == "astera", "NPC-directed delivery is not player's promise")
	for phrase in ["Ich bin Techniker Karte", "Ich bin neu registriert", "Ich bin Techniker morgen", "Ich bin Techniker vielleicht", "Ich bin Techniker wo", "Ich habe keine Karte Tom", "Ich kann dir helfen Pass"]:
		var r := Session.submit(phrase, exposed())
		check(r.transition_id.is_empty() and r.effects.is_empty(), "known extra meaning cannot be swallowed: " + phrase)
	for phrase in ["Ich wiederhole.", "Ich spreche langsamer.", "Kannst du nicht wiederholen?", "Kann ich dir nicht helfen?"]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.intent not in ["ASK_REPEAT", "REQUEST_SLOWER", "OFFER_HELP"], "statement/negative question is not an affirmative request: " + phrase)
	for phrase in ["Ich möchte keinen vorläufigen", "Ich habe keine vorläufige", "Ich kann dir nicht helfen"]:
		var p := Language.analyze_rpg(phrase, c)
		check(not str(p.clarification).to_lower().begins_with("einen vorläufigen pass") and not str(p.clarification).contains("möchtest mir helfen"), "clarification preserves negative polarity: " + phrase)
	var once := registered()
	for phrase in ["Bin ich Techniker?", "Ich möchte neu sein", "Habe ich keine Karte?"]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.intent not in ["CLAIM_TECHNICIAN", "REPORT_NEWCOMER", "REPORT_NO_CARD"], "questions and wishes do not assert facts: " + phrase)
	Session.submit("Ich möchte vorläufigen", once)
	Session.submit("Ja", once)
	Session.submit("Ja", once)
	var duplicate := Session.submit("Ja", once)
	check(once.current_node == "E_OFFICIAL" and duplicate.effects.is_empty(), "confirmation and terminal replies cannot duplicate effects")
	for phrase in ["Ich muss Tom eine Nachricht geben.", "Ich habe nicht keine Karte."]:
		var p := Language.analyze_rpg(phrase, c)
		check(p.intent not in ["ACCEPT_MESSAGE", "REPORT_NO_CARD", "REQUEST_PASS"], "obligation/double negation cannot become a positive commitment: " + phrase)
	var unclear := registered()
	Session.submit("Ich möchte vorläufigen", unclear)
	Session.submit("Wer?", unclear)
	check(Session.submit("Ja", unclear).effects.is_empty() and unclear.current_node == "G40_REGISTERED", "unresolved new question cannot confirm the old object")
	var name_context := Session.initial_context()
	send(name_context, "ask_rules", "Wie komme ich rein?")
	for phrase in ["Heiße ich Alex?", "Ich heiße Alex morgen", "Ich möchte Alex sein", "Ich heiße Alex Tom"]:
		check(Language.analyze_rpg(phrase, name_context).intent != "PLAYER_NAME", "name slot cannot consume questions, modality or extra content: " + phrase)
	for pair in [["Es tut mir leid.","APOLOGIZE"],["Entschuldigung.","APOLOGIZE"],["Was soll ich machen?","ASK_DETAILS"],["Ich gebe Tom eine Nachricht.","ACCEPT_MESSAGE"],["Ich gebe Tom keine Nachricht.","REFUSE_DEAL"],["Ich verstehe nicht.","ASK_REPEAT"],["Sprich bitte langsamer.","REQUEST_SLOWER"],["Bis später.","FAREWELL"]]:
		var local := registered()
		local.current_node = "G90_DEAL"
		check(Language.analyze_rpg(pair[0], local).intent == pair[1], "action family stays productive: " + pair[0])
	for phrase in ["Ich bin mit Techniker", "Ich möchte mit Pass"]:
		check(Language.analyze_rpg(phrase, c).intent not in ["CLAIM_TECHNICIAN","REQUEST_PASS"], "preposition cannot silently change the argument relation: " + phrase)
	var asked := registered()
	send(asked, "request_pass", "Ich möchte einen Pass")
	check(Language.analyze_rpg("Doch", asked).intent != "SHORT_NO", "contradictory affirmative is never converted into rejection")
	print("SEMANTIC_LANGUAGE: %d failure(s), %d assertions" % [failures, assertions])
	quit(1 if failures else 0)
