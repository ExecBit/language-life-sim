extends SceneTree

const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")

var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	var data := Language.data()
	var graph: Dictionary = data.get("dialogue", {})
	check(graph.get("assessment", "") == "none" and graph.get("progression", "") == "open_conversation_no_pass_fail", "authored dialogue is open-ended and has no pass/fail assessment")
	for node_id in graph.get("nodes", {}):
		for action_id in graph.nodes[node_id].get("actions", []):
			check(graph.get("actions", {}).has(action_id), "%s references authored action %s" % [node_id, action_id])
	for transition in graph.get("transitions", []):
		var source: Variant = transition.get("from", "")
		var sources: Array = source if source is Array else [source]
		check(graph.get("nodes", {}).has(transition.get("to", "")), "transition target %s is authored" % transition.get("to", ""))
		check(sources.has("*") or sources.all(func(id): return graph.nodes.has(id)), "transition source is authored")

	var subjects := [
		{"prefix":"Ich bin", "inverted":"Heute bin ich", "actor":"player", "intent":"REPORT_STATE"},
		{"prefix":"Du bist", "inverted":"Heute bist du", "actor":"astera", "intent":"REPORT_ASTERA_STATE"}
	]
	for state_id in data.get("states", {}):
		var forms: Array = data.states[state_id].get("forms", [])
		if forms.is_empty():
			check(false, "state %s has at least one surface form" % state_id)
			continue
		var state_form := str(forms[0])
		for subject in subjects:
			var actor := str(subject.actor)
			var expected_intent := str(subject.intent)
			var phrases := [
				"%s %s" % [subject.prefix, state_form],
				"%s sehr %s" % [subject.prefix, state_form],
				"%s ein bisschen %s" % [subject.prefix, state_form],
				"%s nicht %s" % [subject.prefix, state_form],
				"%s %s" % [subject.inverted, state_form]
			]
			for phrase in phrases:
				var parsed: Dictionary = Language.analyze(phrase, Session.initial_context())
				check(parsed.get("status", "") == "RECOGNIZED" and parsed.get("intent", "") == expected_intent,
					"productive state template preserves %s subject for %s" % [actor, state_id])
				check(parsed.get("frame", {}).get("state_id", "") == state_id and parsed.get("frame", {}).get("experiencer", "") == actor,
					"productive state template preserves lexical state and experiencer")
			var negative_phrase := "%s nicht %s" % [subject.prefix, state_form]
			var negative: Dictionary = Language.analyze(negative_phrase, Session.initial_context())
			check(negative.get("status", "") == "RECOGNIZED" and negative.get("frame", {}).get("polarity", "") == "negative",
				"negation remains explicit for %s" % state_id)
	for modifier in ["sehr", "auch", "heute", "jetzt", "ein", "bisschen"]:
		check(not Language.translation_for(modifier).is_empty(), "new productive modifier %s has an F1 translation" % modifier)
	check(not Language.translation_for("ein bisschen …").is_empty(), "the productive degree phrase has a whole-unit F1 translation")

	for sample in [
		{"text":"Kann ich dir helfen?", "intent":"OFFER_HELP", "actor":"player", "recipient":"astera"},
		{"text":"Ich helfe dir", "intent":"OFFER_HELP", "actor":"player", "recipient":"astera"},
		{"text":"Kannst du mir helfen?", "intent":"REQUEST_HELP", "actor":"astera", "recipient":"player"},
		{"text":"Du hilfst mir", "intent":"REQUEST_HELP", "actor":"astera", "recipient":"player"}
	]:
		var parsed: Dictionary = Language.analyze(str(sample.text), Session.initial_context())
		check(parsed.get("status", "") == "RECOGNIZED" and parsed.get("intent", "") == sample.intent
			and parsed.get("frame", {}).get("actor", "") == sample.actor and parsed.get("frame", {}).get("recipient", "") == sample.recipient,
			"productive help wording preserves helper and recipient roles: %s" % sample.text)

	for sample in [{"text":"Hallo, ich bin Alex", "name":"Alex"}, {"text":"Hi! Ich heiße Mira", "name":"Mira"}, {"text":"Ich heiße Neral", "name":"Neral"}]:
		var context := Session.initial_context()
		var named: Dictionary = Session.submit(str(sample.text), context)
		check(named.parse.get("intent", "") == "PLAYER_NAME" and context.get("player_name", "") == sample.name,
			"open name slot accepts productive introduction form: %s" % sample.text)
		check(named.effects.has("player_name_set") and context.dialogue_node == "conversation", "accepted name is recorded once and reaches conversation")

	var free_order := Session.initial_context()
	var activity: Dictionary = Session.submit("Was machst du?", free_order)
	check(activity.parse.get("status", "") == "RECOGNIZED" and activity.parse.get("intent", "") == "ASK_ACTIVITY" and free_order.dialogue_node == "after_activity",
		"player can ask about Astera's activity before giving a name or mood report")
	var no_pass_actions: Array = Session.available_actions(free_order).map(func(action): return action.id)
	check(no_pass_actions.has("introduce") and no_pass_actions.has("ask_mood") and no_pass_actions.has("farewell"), "nonlinear topics remain available after an initiative question")

	var no_pass := Session.initial_context()
	var unsupported: Dictionary = Session.submit("Ich bin blorple müde", no_pass)
	check(unsupported.parse.get("status", "") == "UNKNOWN" and unsupported.effects.is_empty() and no_pass.player_mood.is_empty(),
		"unknown vocabulary is honestly rejected without a state effect")
	check(no_pass.dialogue_node == "opening" and no_pass.dialogue_history.back().get("changed", true) == false,
		"unknown phrase leaves the RPG graph at its current node")
	var word_order: Dictionary = Session.submit("Heute ich bin müde", no_pass)
	check(word_order.parse.get("status", "") == "UNKNOWN" and no_pass.player_mood.is_empty(),
		"unsupported word order does not become a positive state report")
	var negation_order: Dictionary = Session.submit("Ich bin sehr nicht müde", no_pass)
	check(negation_order.parse.get("status", "") == "UNKNOWN" and no_pass.player_mood.is_empty(),
		"invalid negation order does not become a positive or negative state report")
	var mixed: Dictionary = Session.submit("Ich bin müde und glücklich", no_pass)
	check(mixed.parse.get("status", "") == "UNSUPPORTED" and mixed.effects.is_empty() and no_pass.dialogue_node == "opening",
		"two state meanings do not partially apply or advance the dialogue")

	var tired_context := Session.initial_context()
	var tired: Dictionary = Session.submit("Ich bin sehr müde", tired_context)
	var happy_context := Session.initial_context()
	var happy: Dictionary = Session.submit("Ich bin sehr glücklich", happy_context)
	check(tired.answer != happy.answer and tired.emotion_state != happy.emotion_state,
		"the same productive grammar template selects distinct authored reactions by meaning")

	print("PRODUCTIVE_INTENT_TESTS: %d assertions, %d failure(s)" % [assertions, failures])
	quit(1 if failures > 0 else 0)
