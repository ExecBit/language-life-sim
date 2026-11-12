extends SceneTree
## Authoring gate: vocabulary, semantics, memo and scenario must remain connected.
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Graph = preload("res://implementations/communication_lab/game/communication/dialogue_graph.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
func _initialize() -> void:
	var data := Language.data()
	var words := {}
	var entities := {}
	var kinds := ["pronoun","entity","predicate","operator","attribute","property","topic","act","response","negation","interrogative","polite","reference","name_marker","repeat_marker","until","time","article","possessive","greeting","expletive","conjunction","preposition","degree","discourse"]
	for row in data.vocabulary:
		var word := str(row.surface).to_lower()
		check(not words.has(word), "duplicate lexeme " + word)
		check(not str(row.get("translation", "")).is_empty() and row.translation != "служебная форма", "real translation " + word)
		words[word] = row
		if not row.has("syntax"): continue # NPC comprehension-only vocabulary is allowed.
		var s: Dictionary = row.syntax
		check(str(s.get("kind", "")) in kinds, "known syntax kind " + word)
		for pair in [["predicate","predicate"],["operator","operator"],["property","property"],["topic","topic"],["attribute","attribute"],["response","answer"],["act","family"]]:
			if s.get("kind") == pair[0]: check(not str(s.get(pair[1], "")).is_empty(), "typed meaning " + word)
		if s.get("kind") == "entity":
			check(s.has("entity_id") and s.has("entity_type") and s.get("gender", "") in ["m","f","n"] and s.has("label"), "entity declaration " + word)
			entities[str(s.get("entity_id", ""))] = s
	var bound := {"SHORT_YES":true,"SHORT_NO":true,"REOPEN_DIALOG":true}
	for binding in data.language.bindings:
		check(binding.has("family") and binding.has("intent") and binding.has("requires") and binding.has("frame"), "complete domain binding")
		bound[str(binding.intent)] = true
	for node in Graph.data().nodes.values():
		for id in node.get("language_context", {}).get("referents", []): check(entities.has(str(id)), "context referent exists: " + str(id))
		var proposition: Dictionary = node.get("open_proposition", {})
		var schema: Dictionary = proposition.get("answer_schema", {})
		if not schema.is_empty():
			check(schema.has("family") and schema.has("requires") and not str(schema.get("value_slot", "")).is_empty() and proposition.has("value_field"), "value proposition declares its answer contract")
	for id in Graph.data().actions:
		var action: Dictionary = Graph.data().actions[id]
		check(bound.has(str(action.semantic_action)), "action has semantic binding: " + str(id))
		for word in action.get("vocabulary", []):
			check(words.has(str(word).to_lower()) and words.get(str(word).to_lower(), {}).has("syntax"), "player action word has parser metadata: " + str(word))
	print("LANGUAGE_CONTRACT: %d failure(s)" % failures)
	quit(1 if failures else 0)
