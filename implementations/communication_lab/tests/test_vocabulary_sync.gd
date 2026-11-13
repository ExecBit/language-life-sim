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

func search_memo(room: Node, query: String) -> void:
	room.vocabulary_search.text = query
	# Programmatic LineEdit assignment does not emit the user's edit signal.
	room.vocabulary_search.text_changed.emit(query)

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
	var complete_actions := true
	var action_count := 0
	for action in Language.data().dialogue.actions.values():
		if action.get("system", false): continue
		action_count += 1
		if action.get("vocabulary", []).is_empty() or action.get("search_words", []).is_empty(): complete_actions = false
		for word in action.get("vocabulary", []) + action.get("search_words", []):
			if not words.has(str(word).to_lower()): complete_actions = false
		lines.append(" ".join(action.get("vocabulary", [])))
	check(complete_actions, "all %d player actions have complete memo/completion word coverage" % action_count)
	for entry in Language.data().constructions: lines.append(str(entry.surface))
	for reason in ["MULTIPLE_INTENTS", "NO_OPEN_YES_NO_TARGET", "UNKNOWN_TOKEN"]:
		lines.append(Session._failure_reply({"reason":reason}))
	for intent in ["REQUEST_HELP", "REPORT_HAS_CARD", "CLAIM_TECHNICIAN", "SHORT_NO", "OTHER"]:
		var context := Session.initial_context()
		context.current_node = "G40_REGISTERED"
		lines.append(Session._no_branch_reply(intent, {}, context))
	lines.append("Alles klar. Wir bleiben beim selben Thema.")
	lines.append("Was meinst du genau?")
	# Production-generated clarification templates are also learning material.
	for line in ["Ja oder nein?", "Wer soll das machen? Ich oder du?", "Welche Rolle meinst du?", "Wem? Mir oder dir?", "Was meinst du genau?", "Du bist also kein Techniker?", "Du möchtest mir helfen?", "Soll ich dir helfen?", "Du kannst mir nicht helfen?", "Ich kann dir nicht helfen?", "Soll ich das wiederholen?", "Meinst du das?", "Ja oder nein? Sag es bitte anders."]:
		lines.append(line)
	for phrase in ["Ich möchte vorläufigen", "Ich möchte keinen vorläufigen", "Ich bin Techniker nein"]:
		lines.append(Language.analyze_rpg(phrase, Session.initial_context()).clarification)
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
	var saw_phrase := false
	var ordered := true
	var previous_frequency := 2147483647
	for row in room.vocabulary_rows:
		if row.header: continue
		if row.group == "phrase":
			saw_phrase = true
		else:
			if saw_phrase or int(row.frequency) > previous_frequency: ordered = false
			previous_frequency = int(row.frequency)
	check(ordered and saw_phrase, "actual F1 globally orders words by decreasing scenario frequency and puts all sentences last")
	check(room.composer.matches.get_item_text(0).to_lower() in ["ich", "du"], "frequent pronouns lead the unfiltered word picker")
	for prefix in ["tec", "TEC", "nach", "möch"]:
		room.composer.update_matches(prefix)
		check(room.composer.matches.item_count > 0, "actual Composer prefix lookup: " + prefix)
	room.composer.update_matches("tec")
	check(room.composer.matches.get_item_text(0).to_lower() == "techniker", "Techniker appears as the first tec completion")
	search_memo(room, "техник")
	var techniker_visible := false
	for row in room.vocabulary_rows:
		if not row.header and str(row.label.text).to_lower().begins_with("techniker  "):
			techniker_visible = row.label.visible
	check(techniker_visible, "F1 Russian translation search finds Techniker")
	search_memo(room, "времен")
	var temporary_matches := {}
	for row in room.vocabulary_rows:
		if not row.header and row.label.visible: temporary_matches[str(row.surface).to_lower()] = true
	check(temporary_matches.has("pass") and temporary_matches.has("vorläufigen") and not temporary_matches.has("ich") and not temporary_matches.has("du"), "Russian temporary-pass search finds Pass and its adjective as individual words")
	var action_searches := true
	for action in Language.data().dialogue.actions.values():
		if action.get("system", false): continue
		search_memo(room, str(action.label))
		var found := false
		for row in room.vocabulary_rows:
			if not row.header and row.group == "words" and row.label.visible and str(row.surface).to_lower() in action.search_words:
				found = true
		if not found: action_searches = false
	check(action_searches, "every Russian action label finds relevant individual words in actual F1")
	if DisplayServer.get_name() != "headless":
		root.content_scale_size = Vector2i(1920, 1080)
		root.size = Vector2i(1920, 1080)
		room.vocabulary_card.show()
		search_memo(room, "")
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var directory := ProjectSettings.globalize_path("res://.local")
		DirAccess.make_dir_recursive_absolute(directory)
		check(root.get_texture().get_image().save_png(directory.path_join("memo-frequency.png")) == OK, "rendered frequency list saved")
		search_memo(room, "времен")
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("memo-temporary.png")) == OK, "rendered temporary-pass search saved")
		search_memo(room, "")
		for frame in 3: await process_frame
		for child in room.vocabulary_card.find_children("*", "ScrollContainer", true, false): child.scroll_vertical = 100000
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("memo-phrases-bottom.png")) == OK, "rendered final phrase block saved")
	print("VOCABULARY_SYNC: %d failure(s), %d words, %d memo entries" % [failures, words.size(), entries.size()])
	quit(1 if failures else 0)
