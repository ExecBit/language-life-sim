extends SceneTree

const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	var initial := Session.initial_context()
	var no_card_forms := ["Ich habe keine Karte.", "Ich hab keine Karte.", "Ich habe keinen Pass."]
	for phrase in no_card_forms:
		var parsed := Language.analyze_rpg(phrase, initial)
		check(parsed.status == "RECOGNIZED" and parsed.intent == "REPORT_NO_CARD" and parsed.frame.polarity == "negative",
			"productive first-person negation reports a missing pass: " + phrase)
	var positive := Language.analyze_rpg("Ich habe einen Pass.", initial)
	check(positive.intent == "REPORT_HAS_CARD" and positive.frame.polarity == "positive",
		"positive possession remains distinct from negation")
	var other_subject := Language.analyze_rpg("Du hast keine Karte.", initial)
	check(other_subject.intent != "REPORT_NO_CARD", "second-person possession cannot be read as the player's loss")

	var claim := Language.analyze_rpg("Ich bin ein Techniker.", initial)
	var denial := Language.analyze_rpg("Ich bin kein Techniker.", initial)
	check(claim.intent == "CLAIM_TECHNICIAN" and claim.frame.polarity == "positive"
		and denial.intent == "DENY_TECHNICIAN" and denial.frame.polarity == "negative",
		"role and negation keep their semantic contrast")
	var other_role := Language.analyze_rpg("Du bist Techniker.", initial)
	check(other_role.intent != "CLAIM_TECHNICIAN", "another participant's role is not attributed to the player")

	var offer := Language.analyze_rpg("Kann ich dir helfen?", initial)
	var request := Language.analyze_rpg("Kannst du mir helfen?", initial)
	check(offer.intent == "OFFER_HELP" and offer.frame.actor == "player" and offer.frame.recipient == "astera"
		and request.intent == "REQUEST_HELP" and request.frame.actor == "astera" and request.frame.recipient == "player",
		"help wording preserves the helper and recipient when roles reverse")

	var alternative := Language.analyze_rpg("Gibt es eine andere Möglichkeit?", initial)
	var rules := Language.analyze_rpg("Wie komme ich rein?", initial)
	check(alternative.intent == "ASK_ALTERNATIVE" and rules.intent == "ASK_RULES",
		"open alternatives and rules requests map to separate semantic families")
	var open_question := initial.duplicate(true)
	open_question.pending_proposition = {"id":"confirm_player_name", "value":"Neral"}
	var yes := Language.analyze_rpg("Ja, danke.", open_question)
	var no := Language.analyze_rpg("Nein, danke.", open_question)
	check(yes.intent == "SHORT_YES" and no.intent == "SHORT_NO"
		and yes.frame.proposition_id == "confirm_player_name" and no.frame.confirmation == "no",
		"short answers preserve polarity and bind to the current concrete proposition")
	var unbound_yes := Language.analyze_rpg("Ja", initial)
	check(unbound_yes.status == "NEEDS_CLARIFICATION" and unbound_yes.reason == "NO_OPEN_YES_NO_TARGET",
		"a bare yes without an open proposition cannot select an outcome")

	var compound := Language.analyze_rpg("Ich habe keine Karte. Ich bin neu.", initial)
	var unknown := Language.analyze_rpg("Ich habe keine Karte, blorple", initial)
	check(compound.status == "UNSUPPORTED" and compound.reason == "MULTIPLE_INTENTS",
		"compound utterances are rejected as a whole")
	check(unknown.status == "UNKNOWN" and unknown.reason == "UNKNOWN_TOKEN",
		"an unknown continuation cannot partially consume a known prefix")
	print("PRODUCTIVE_RPG_INTENTS: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
