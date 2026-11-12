extends SceneTree
const Language = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + label)
	else:
		print("PASS ", label)

func run() -> void:
	var words := {}
	var entries := {}
	for entry in Language.vocabulary_entries():
		if entry.availability != "available": continue
		entries[str(entry.surface).to_lower()] = true
		if entry.pos != "phrase": words[str(entry.surface).to_lower()] = true
		check(not Language.translation_for(str(entry.surface)).is_empty(), "translation: " + str(entry.surface))
	var suggested := {}
	for word in Language.suggestions(""): suggested[str(word).to_lower()] = true
	check(suggested == words, "suggestions exactly cover every memo word without legacy catalog extras")
	var lines: Array[String] = []
	for node in Language.data().dialogue.nodes.values():
		lines.append(str(node.get("npc_line", "")))
		for line in node.get("npc_line_by_access", {}).values(): lines.append(str(line))
	for action in Language.data().dialogue.actions.values(): lines.append(str(action.get("confirm_question", "")))
	for entry in Language.data().constructions: lines.append(str(entry.surface))
	for reason in ["MULTIPLE_INTENTS", "NO_OPEN_YES_NO_TARGET", "UNKNOWN_TOKEN"]:
		lines.append(Session._failure_reply({"reason":reason}))
	for intent in ["REQUEST_HELP", "REPORT_HAS_CARD", "CLAIM_TECHNICIAN", "SHORT_NO", "OTHER"]:
		var context := Session.initial_context()
		context.current_node = "G40_REGISTERED"
		lines.append(Session._no_branch_reply(intent, {}, context))
	lines.append("Alles klar. Wir bleiben beim selben Thema.")
	lines.append("Was meinst du genau?")
	var placeholders := RegEx.new()
	placeholders.compile("\\{[^}]+\\}")
	var tokens := RegEx.new()
	tokens.compile("[\\p{L}]+")
	var missing := {}
	for line in lines:
		for token in tokens.search_all(placeholders.sub(line, "", true).to_lower()):
			if not words.has(token.get_string()): missing[token.get_string()] = true
	check(missing.is_empty(), "all authored NPC, clarification, fallback and construction words covered: " + str(missing.keys()))
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	await process_frame
	room.composer.update_matches("")
	var actual := {}
	for index in room.composer.matches.item_count:
		actual[room.composer.matches.get_item_text(index).to_lower()] = true
	check(actual == words, "actual Composer ItemList uses the same word set as F1")
	var memo := {}
	var translations_match := true
	for row in room.vocabulary_rows:
		if row.header: continue
		var surface := str(row.label.text).split("  —  ")[0]
		memo[surface.to_lower()] = true
		if not str(row.label.text).ends_with(Language.translation_for(surface)): translations_match = false
	check(memo == entries and translations_match, "actual F1 rows and translations match the scenario catalog")
	for prefix in ["tec", "TEC", "nach", "möch"]:
		room.composer.update_matches(prefix)
		check(room.composer.matches.item_count > 0, "actual Composer prefix lookup: " + prefix)
	room.composer.update_matches("tec")
	check(room.composer.matches.get_item_text(0).to_lower() == "techniker", "Techniker appears as the first tec completion")
	room.call("_filter_vocabulary", "техник")
	var techniker_visible := false
	for row in room.vocabulary_rows:
		if not row.header and str(row.label.text).to_lower().begins_with("techniker  "):
			techniker_visible = row.label.visible
	check(techniker_visible, "F1 Russian translation search finds Techniker")
	print("VOCABULARY_SYNC: %d failure(s), %d words, %d memo entries" % [failures, words.size(), entries.size()])
	quit(1 if failures else 0)
