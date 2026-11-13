extends SceneTree
## A new domain is declared entirely in fixture data, using the same production engine.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const Graph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")
var failures := 0
var assertions := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func run() -> void:
	var original := Language.data().duplicate(true)
	var extended := original.duplicate(true)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://implementations/communication_lab/tests/fixtures/language_extension.json"))
	extended.vocabulary.append_array(fixture.vocabulary)
	extended.language.bindings.append_array(fixture.bindings)
	Language._cached_data = extended
	check(Language.suggestions("aus").has("Ausweis") and Language.translation_for("Ausweis") != "", "data word reaches completion and memo")
	check(Language.analyze_rpg("Ich möchte einen Ausweis.", Session.initial_context()).intent == "REQUEST_PASS", "new word of an existing type needs no grammar change")
	check(Language.analyze_rpg("Ich bin Pfleger.", Session.initial_context()).intent != "CLAIM_TECHNICIAN", "new role cannot impersonate the technician")
	Language._cached_data.dialogue = fixture.dialogue
	check(Graph.validate().is_empty(), "new two-node domain validates without the original node count")
	for phrase in ["Ich möchte einen sterilen Verband.", "Kann ich einen Verband bekommen?", "Ich brauche einen Verband."]:
		var c := Session.initial_context()
		Session.opening_line(c)
		var r := Session.submit(phrase, c)
		check(c.current_node == "E_SUPPLY" and c.has_bandage and r.parse.frame.object_id == "bandage", "new domain binding and effect: " + phrase)
	for phrase in ["Ich möchte keinen Verband.", "Du möchtest einen Verband.", "Ich habe einen Verband.", "Ich möchte einen Verband blorple"]:
		var c := Session.initial_context()
		var r := Session.submit(phrase, c)
		check(c.current_node == "G_MEDIC" and not c.has_bandage and r.effects.is_empty(), "semantic contrast in new domain: " + phrase)
	var c := Session.initial_context()
	var r := Session.submit("Einen sterilen, bitte.", c)
	check(r.parse.status == "NEEDS_CLARIFICATION" and r.answer.contains("Verband") and r.answer.contains("Tupfer") and c.pending_resolution.is_empty(), "ambiguous omission asks for the object rather than choosing one")
	check(Session.submit("Ja", c).effects.is_empty() and not c.has_bandage, "yes cannot choose between different objects")
	# Start a fresh question: unsupported replies expire transient choices.
	Session.submit("Einen sterilen, bitte.", c)
	var chosen := Session.submit("Verband", c)
	check(c.has_bandage and chosen.transition_id == "T_SUPPLY", "a noun completes the stored semantic choice")
	for phrase in ["Verband Tom", "keinen Verband", "Verband morgen"]:
		var ambiguous := Session.initial_context()
		Session.submit("Einen sterilen, bitte.", ambiguous)
		check(Session.submit(phrase, ambiguous).effects.is_empty() and not ambiguous.has_bandage, "choice cannot discard extra meaning: " + phrase)
	var single: Dictionary = fixture.dialogue.duplicate(true)
	single.nodes.G_MEDIC.language_context.referents = ["bandage"]
	Language._cached_data.dialogue = single
	c = Session.initial_context()
	r = Session.submit("Ich möchte sterilen", c)
	check(not c.has_bandage and not c.pending_resolution.is_empty() and r.answer.contains("Verband"), "unique omitted object is proposed without effects")
	r = Session.submit("Ja", c)
	check(c.has_bandage and r.graph_event.get("resolved_frame", {}).get("referent_id", "") == "bandage", "confirmation keeps the new typed referent")
	Language._cached_data = original
	print("LANGUAGE_EXTENSION: %d failure(s), %d assertions" % [failures, assertions])
	quit(1 if failures else 0)
