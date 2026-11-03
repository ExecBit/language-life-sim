extends RefCounted

## LEX-01 verification probe (Issue #2). Not a test framework: it drives the real game object
## through the same entry points the mouse and the HUD buttons use, and asserts what the
## player would observe. Both modes run on scenes/main.tscn, so the room, the picking and the
## HUD are the shipped ones, not a copy.
##
##   --probe         headless: the whole learning loop over both days, progress, saves,
##                   retry re-shuffling, skip, end-of-day summary, day-2 revisits
##   --probe-input   windowed: a real mouse click on a prop, on a delivery target, and on a
##                   response button of the DialogueResponsesMenu

var _failures: PackedStringArray = []
var _checks: int = 0
var _completed: bool = false
# A probe that stopped early is a failure, never an empty pass.
const MIN_LOGIC_CHECKS: int = 60
const MIN_INPUT_CHECKS: int = 10


func run(game: Node, mode: String) -> int:
	_completed = false
	if mode == "input":
		await _run_input(game)
	else:
		_run_logic(game)
	if not _completed:
		_failures.append("the probe stopped before it finished, so its result is unknown")
	var minimum: int = MIN_INPUT_CHECKS if mode == "input" else MIN_LOGIC_CHECKS
	if _checks < minimum:
		_failures.append("only %d checks ran, at least %d were expected" % [_checks, minimum])
	if _failures.is_empty():
		print("%s OK checks=%d" % ["LEX01 INPUT PROBE" if mode == "input" else "LEX01 PROBE", _checks])
		return 0
	print("%s FAIL checks=%d" % ["LEX01 INPUT PROBE" if mode == "input" else "LEX01 PROBE", _checks])
	for failure: String in _failures:
		print("  - " + failure)
	return 1


# region headless logic probe

func _run_logic(game: Node) -> void:
	# Verification always starts from a clean run so the numbers below describe this run only.
	game.probe_reset()
	var reset_state: Dictionary = game.probe_state()
	print("RESET progress_cleared=%s day=%d queue=%d" % [
		int(reset_state["totals"]["encountered"]) == 0, int(reset_state["day"]), int(reset_state["queue_size"]),
	])
	var content: Variant = game.content
	var progress: Variant = game.progress

	print("CONTENT files=%d scenarios=%d lemmas=%d days=%s" % [
		content.scenario_files.size(), content.scenarios.size(), content.lemmas.size(), content.days(),
	])
	for problem: String in content.errors:
		_expect(false, "content error: " + problem)
	for warning: String in game.builder.warnings:
		_expect(false, "builder warning: " + warning)
	_expect(content.scenario_files.size() >= 2, "the loader reads more than one scenario file")
	_expect(content.scenarios.size() >= 16, "the loader also loads the extension scenarios")
	_expect(content.days().size() >= 2, "the data describes more than one day")

	var actions: Dictionary = {}
	for scenario: Dictionary in content.scenarios:
		actions[String(scenario["action_type"])] = int(actions.get(String(scenario["action_type"]), 0)) + 1
	print("ACTIONS %s" % [actions])
	for required: String in ["find_select", "bring_deliver", "respond"]:
		_expect(int(actions.get(required, 0)) > 0, "action type %s is playable" % required)

	_expect(String(game.probe_state()["phase"]) == "asking", "the day starts in a playable situation")
	_check_skip_does_not_lock(game, progress)

	var seen: PackedStringArray = PackedStringArray()
	var done: Dictionary = {}
	var presentations: int = 0
	var mismatches: int = 0
	var gloss_tokens: PackedStringArray = _forbidden_gloss_tokens(content)

	for day: int in content.days():
		if day != int(content.days()[0]):
			game.probe_next_day()
			print("NEXT_DAY day=%d queue=%d" % [int(game.probe_state()["day"]), int(game.probe_state()["queue_size"])])
		var revisited_before: Dictionary = _stat_snapshot(progress, "revisited")
		var day_total: int = int(game.probe_state()["queue_size"])
		var guard: int = 0
		while String(game.probe_state()["phase"]) == "asking" and guard < day_total + 4:
			guard += 1
			var scenario: Dictionary = game.current_scenario
			var id: String = String(scenario["id"])
			var action: String = String(scenario["action_type"])
			var authored: Array[String] = _option_ids(scenario)
			var state: Dictionary = game.probe_state()
			var visible: Array[String] = state["view_order"]
			presentations += 1
			if visible != authored:
				mismatches += 1
			print("SHUFFLE %s action=%s authored=%s visible=%s positions=%s staged=%d responses=%d" % [
				id, action, authored, visible, state["positions"], int(state["staged"]), int(state["responses"]),
			])
			_collect_text(seen, game.probe_hud_texts(), scenario)
			if action == "respond":
				_check_response_menu(game, scenario)
			if action == "find_select" and not done.has("find_wrong"):
				done["find_wrong"] = true
				_check_wrong_then_retry(game, scenario, progress)
			elif action == "bring_deliver" and not done.has("bring_wrong_target"):
				done["bring_wrong_target"] = true
				_check_wrong_target_then_fix(game, scenario, progress)
			elif action == "respond" and not done.has("respond_wrong"):
				done["respond_wrong"] = true
				_check_wrong_response(game, scenario, progress)
			if String(game.probe_state()["phase"]) == "asking":
				_collect_text(seen, game.probe_hud_texts(), scenario)
			_answer_by_correct_id(game, scenario)
			_expect(String(game.probe_state()["phase"]) == "solved",
				"%s solved by answering its recorded correct option id" % id)
			game.probe_continue()

		var totals: Dictionary = progress.totals()
		var scenarios: Dictionary = progress.scenario_totals()
		print("END_DAY day=%d presented=%d scenario_totals=%s lemma_totals=%s" % [day, day_total, scenarios, totals])
		_expect(String(game.probe_state()["phase"]) in ["day_finished", "run_finished"],
			"day %d ends with a summary instead of an unfinished scenario" % day)
		var lines: Array = progress.summary_lines(content)
		print("SUMMARY lines=%d first=%s" % [lines.size(), lines[0] if not lines.is_empty() else ""])
		_expect(not lines.is_empty(), "the end-of-day summary lists the lemmas the player met")
		_check_gloss_placement(lines, seen, gloss_tokens)
		for scenario: Dictionary in content.scenarios_for_day(day):
			var entry: Dictionary = progress.scenario_entry(String(scenario["id"]))
			_expect(bool(entry.get("presented", false)), "%s was presented on day %d" % [String(scenario["id"]), day])
			_expect(bool(entry.get("solved", false)) or bool(entry.get("skipped", false)),
				"%s left no scenario open" % String(scenario["id"]))
		if day != int(content.days()[0]):
			var revisited_now: Dictionary = _stat_snapshot(progress, "revisited")
			for scenario: Dictionary in content.scenarios_for_day(day):
				var source: String = String(scenario.get("revisit_of", ""))
				if source.is_empty():
					continue
				var gained: int = 0
				for lemma_id: String in scenario["target_lemma_ids"]:
					gained += int(revisited_now.get(lemma_id, 0)) - int(revisited_before.get(lemma_id, 0))
				print("REVISIT %s revisit_of=%s lemma_gain=%d stats=%s" % [String(scenario["id"]), source, gained, _stats_text(progress, scenario)])
				_expect(gained > 0, "%s counted as a delayed revisit of %s" % [String(scenario["id"]), source])

	_expect(presentations >= 16, "the probe played at least 16 presentations")
	print("SHUFFLE_COUNT presentations=%d different_from_authored_order=%d" % [presentations, mismatches])
	_expect(mismatches >= 6, "the visible answer order differs from the authored order often enough to rule out position guessing")

	var extension_ids: PackedStringArray = PackedStringArray()
	for scenario: Dictionary in content.scenarios:
		if String(scenario.get("_source_file", "")).ends_with("lex01_extension.json"):
			extension_ids.append(String(scenario["id"]))
	for id: String in extension_ids:
		var entry: Dictionary = progress.scenario_entry(id)
		print("EXTENSION %s played=%s solved=%s" % [id, bool(entry.get("presented", false)), bool(entry.get("solved", false))])
		_expect(bool(entry.get("solved", false)), "the data-only extension scenario %s played and was solvable" % id)

	var saved_totals: Dictionary = progress.totals()
	progress.save_run()
	var fresh: Lex01Progress = Lex01Progress.new()
	var reloaded: bool = fresh.load_run()
	var identical: bool = JSON.stringify(fresh.totals()) == JSON.stringify(saved_totals)
	print("SAVE path=%s reloaded=%s identical=%s totals=%s" % [Lex01Progress.SAVE_PATH, reloaded, identical, saved_totals])
	_expect(reloaded and identical, "progress saves and reloads identically")
	_expect(int(saved_totals["correct"]) >= 10 and int(saved_totals["incorrect"]) >= 3 and int(saved_totals["revisited"]) >= 1,
		"the probe recorded correct, incorrect and revisit counts separately")

	_check_scene_state_placement(game, content)


func _check_skip_does_not_lock(game: Node, progress: Variant) -> void:
	var before: Dictionary = game.probe_state()
	var id: String = String(before["scenario_id"])
	game.probe_skip()
	var after: Dictionary = game.probe_state()
	var entry: Dictionary = progress.scenario_entry(id)
	print("SKIP %s queue_advanced=%s phase=%s skipped=%d" % [
		id, int(after["queue_index"]) > int(before["queue_index"]), String(after["phase"]),
		int(progress.scenario_totals()["skipped"]),
	])
	_expect(int(after["queue_index"]) > int(before["queue_index"]), "Weiter ohne Antwort advances to the next scenario")
	_expect(bool(entry.get("skipped", false)), "a skipped scenario is recorded as skipped")
	_expect(not bool(entry.get("solved", false)), "a skipped scenario is never recorded as correct")
	_expect(String(after["phase"]) == "asking", "the room keeps playing after a skip instead of locking")


func _check_wrong_then_retry(game: Node, scenario: Dictionary, progress: Variant) -> void:
	var id: String = String(scenario["id"])
	var wrong: String = _wrong_option_id(scenario)
	game.probe_select_option(wrong)
	var entry: Dictionary = progress.scenario_entry(id)
	var layouts: Array[String] = [JSON.stringify(game.probe_state()["positions"])]
	for extra: int in 2:
		game.restage_same_scenario()
		layouts.append(JSON.stringify(game.probe_state()["positions"]))
	print("RETRYRESHUFFLE %s wrong=%s attempts=%d solved=%s phase=%s layouts=%d distinct_layouts=%d" % [
		id, wrong, int(entry["attempts"]), bool(entry["solved"]), String(game.probe_state()["phase"]),
		layouts.size(), _distinct_count(layouts),
	])
	_expect(int(entry["attempts"]) == 1, "%s records a wrong answer as exactly one attempt" % id)
	_expect(not bool(entry["solved"]), "%s is not solved by a wrong answer" % id)
	_expect(String(game.probe_state()["phase"]) == "asking", "%s stays playable after a wrong answer" % id)
	_expect(_distinct_count(layouts) >= 2, "%s lays the room out differently after a wrong answer, so guessing by position cannot work" % id)


func _check_wrong_target_then_fix(game: Node, scenario: Dictionary, progress: Variant) -> void:
	var id: String = String(scenario["id"])
	var correct: String = String(scenario["correct_option_id"])
	game.probe_select_option(correct)
	var held: Dictionary = game.probe_state()
	print("BRING_PICK %s held=%s attempts=%d" % [id, String(held["held"]), int(held["attempts"])])
	_expect(String(held["held"]) == correct, "%s picks the chosen object up" % id)
	_expect(int(held["attempts"]) == 0, "%s does not score an attempt for picking something up" % id)

	# Put the right object in the wrong place: still a wrong answer.
	var kind: String = String(game.staging.get("delivery_kind", ""))
	var wrong_target: Dictionary = {}
	if kind == "object":
		wrong_target = game.probe_deliver_at("npc", String(scenario.get("npc", "")), "")
	else:
		wrong_target = game.probe_deliver_at("object", "", String((scenario["options"] as Array)[0]["scene_object"]))
	var entry: Dictionary = progress.scenario_entry(id)
	print("BRING_WRONG_TARGET %s declared_target=%s attempts=%d solved=%s phase=%s held_after=%s" % [
		id, kind, int(entry["attempts"]), bool(entry["solved"]), String(wrong_target["phase"]), String(wrong_target["held"]),
	])
	_expect(int(entry["attempts"]) == 1, "%s counts a delivery to the wrong place as a wrong answer" % id)
	_expect(String(wrong_target["phase"]) == "asking" and String(wrong_target["held"]).is_empty(),
		"%s puts the object back and keeps the scenario open" % id)

	game.probe_select_option(correct)
	var solved: Dictionary = game.probe_deliver()
	var solved_entry: Dictionary = progress.scenario_entry(id)
	print("BRING_DELIVER %s attempts=%d solved=%s phase=%s" % [id, int(solved_entry["attempts"]), bool(solved_entry["solved"]), String(solved["phase"])])
	_expect(String(solved["phase"]) == "solved", "%s is solved by delivering the right object to the declared target" % id)


func _check_wrong_response(game: Node, scenario: Dictionary, progress: Variant) -> void:
	var id: String = String(scenario["id"])
	game.probe_respond(_wrong_option_id(scenario))
	var entry: Dictionary = progress.scenario_entry(id)
	var orders: Array[String] = [JSON.stringify(game.hud.response_texts())]
	for extra: int in 3:
		game.restage_same_scenario()
		orders.append(JSON.stringify(game.hud.response_texts()))
	print("RESPOND_RETRY %s attempts=%d solved=%s phase=%s answers=%d distinct_orders=%d first=%s" % [
		id, int(entry["attempts"]), bool(entry["solved"]), String(game.probe_state()["phase"]),
		orders.size(), _distinct_count(orders), orders[0],
	])
	_expect(int(entry["attempts"]) == 1, "%s records a wrong answer as exactly one attempt" % id)
	_expect(String(game.probe_state()["phase"]) == "asking", "%s stays playable after a wrong answer" % id)
	_expect(_distinct_count(orders) >= 2, "%s re-orders the answer sentences after a wrong answer" % id)


func _check_response_menu(game: Node, scenario: Dictionary) -> void:
	var id: String = String(scenario["id"])
	var expected: PackedStringArray = PackedStringArray()
	for option: Dictionary in scenario["options"]:
		expected.append(String(option["label_de"]))
	var shown: PackedStringArray = game.hud.response_texts()
	var same_set: bool = shown.size() == expected.size()
	for text: String in shown:
		if not expected.has(text):
			same_set = false
	_expect(same_set, "%s builds its answer buttons from the scenario data" % id)


func _check_scene_state_placement(game: Node, content: Variant) -> void:
	var table: String = "res://assets/kaykit/furniture/table_medium.gltf"
	var fridge: String = "res://assets/kaykit/items/fridge_A.gltf"
	var bun: String = "res://assets/kaykit/items/food_ingredient_bun.gltf"
	for scenario: Dictionary in [content.scenario("s10"), content.scenario("x02")]:
		if scenario.is_empty():
			_expect(false, "scenario missing from the loaded data")
			continue
		game.staging = game.builder.stage_scenario(scenario)
		var table_box: AABB = game.builder.prop_aabb(table)
		_expect(table_box.size.length() > 0.0, "%s has the table it places things on" % String(scenario["id"]))
		var bun_box: AABB = game.builder.prop_aabb(bun)
		var on_table: bool = bun_box.size.length() > 0.0 \
			and absf(bun_box.position.y - (table_box.position.y + table_box.size.y)) < 0.12 \
			and absf(bun_box.get_center().z - table_box.get_center().z) < 0.6
		print("PLACE %s bun_on_table=%s bun=%s table_top=%.3f" % [String(scenario["id"]), on_table, bun_box, table_box.position.y + table_box.size.y])
		_expect(on_table, "%s really places the bun on the table surface" % String(scenario["id"]))
		game.builder.clear()
	var s13: Dictionary = content.scenario("s13")
	if not s13.is_empty():
		game.staging = game.builder.stage_scenario(s13)
		var fridge_box: AABB = game.builder.prop_aabb(fridge)
		var potato_box: AABB = game.builder.prop_aabb("res://assets/kaykit/items/food_ingredient_potato.gltf")
		var at_front: bool = potato_box.size.length() > 0.0 and potato_box.get_center().z > fridge_box.position.z + fridge_box.size.z \
			and absf(potato_box.position.y) < 0.25
		print("PLACE s13 potato_at_fridge=%s potato=%s fridge=%s" % [at_front, potato_box, fridge_box])
		_expect(at_front, "s13 places the potato at the fridge, the way the scenario states it")
		game.builder.clear()
	# Leave the game on the scenario it was actually presenting.
	game.builder.stage_scenario(game.current_scenario)
	_completed = true


func _answer_by_correct_id(game: Node, scenario: Dictionary) -> void:
	var action: String = String(scenario["action_type"])
	var correct: String = String(scenario["correct_option_id"])
	match action:
		"find_select":
			game.probe_select_option(correct)
		"respond":
			game.probe_respond(correct)
		"bring_deliver":
			if String(game.probe_state()["held"]).is_empty():
				game.probe_select_option(correct)
			game.probe_deliver()

# endregion

# region windowed input probe

func _run_input(game: Node) -> void:
	game.probe_reset()
	_expect(String(game.probe_state()["phase"]) == "asking", "the room opens in a playable situation")

	if not _goto_action(game, "find_select"):
		_completed = true
		return
	var scenario: Dictionary = game.current_scenario
	var correct: String = String(scenario["correct_option_id"])
	var wrong: String = _wrong_option_id(scenario)
	await _settle(game)
	var wrong_click: Dictionary = game.probe_click_option_on_screen(wrong)
	print("INPUT_CLICK scenario=%s action=find_select wrong_object=%s screen=%s pick=%s phase_after=%s" % [
		String(scenario["id"]), wrong, wrong_click.get("screen", Vector2.ZERO), wrong_click.get("pick", {}),
		String(wrong_click.get("after", {}).get("phase", "")),
	])
	_expect(not wrong_click.has("error"), "the wrong object of %s could be clicked at a visible point" % String(scenario["id"]))
	_expect(String(wrong_click.get("pick", {}).get("option_id", "")) == wrong,
		"a real mouse click on a prop resolves exactly that prop by option id")
	_expect(String(wrong_click.get("after", {}).get("phase", "")) == "asking",
		"a wrong click leaves the scenario playable instead of ending it")
	await _settle(game)
	var click: Dictionary = game.probe_click_option_on_screen(correct)
	print("INPUT_CLICK scenario=%s action=find_select object=%s screen=%s pick=%s phase_after=%s" % [
		String(scenario["id"]), correct, click.get("screen", Vector2.ZERO), click.get("pick", {}),
		String(click.get("after", {}).get("phase", "")),
	])
	_expect(String(click.get("pick", {}).get("option_id", "")) == correct,
		"clicking the prop the German sentence asked for resolves that prop")
	_expect(String(click.get("after", {}).get("phase", "")) == "solved",
		"clicking the object the utterance asked for solves the scenario")
	game.probe_continue()

	if not _goto_action(game, "bring_deliver"):
		_completed = true
		return
	scenario = game.current_scenario
	correct = String(scenario["correct_option_id"])
	await _settle(game)
	var picked: Dictionary = game.probe_click_option_on_screen(correct)
	print("INPUT_CLICK scenario=%s action=bring_deliver object=%s pick=%s held_after=%s attempts=%d" % [
		String(scenario["id"]), correct, picked.get("pick", {}), String(picked.get("after", {}).get("held", "")), int(picked.get("after", {}).get("attempts", 0)),
	])
	_expect(String(picked.get("after", {}).get("held", "")) == correct, "a real click picks the clicked object up")
	_expect(int(picked.get("after", {}).get("attempts", 0)) == 0, "picking something up is not yet an answer")
	await _settle(game)
	var delivered: Dictionary = game.probe_click_delivery_on_screen()
	print("INPUT_CLICK scenario=%s action=bring_deliver target_click=%s error=%s input_reached_game=%s phase_after=%s totals=%s" % [
		String(scenario["id"]), delivered.get("pick", {}), delivered.get("error", ""), bool(delivered.get("input_reached_game", false)), String(delivered.get("after", {}).get("phase", "")), delivered.get("after", {}).get("totals", {}),
	])
	_expect(String(delivered.get("after", {}).get("phase", "")) == "solved",
		"clicking the declared delivery target with the right object solves the scenario")
	game.probe_continue()

	if not _goto_action(game, "respond"):
		_completed = true
		return
	scenario = game.current_scenario
	correct = String(scenario["correct_option_id"])
	var view: Array = game.probe_state()["view_order"]
	var index: int = view.find(correct)
	var shown: PackedStringArray = game.hud.response_texts()
	var expected_labels: PackedStringArray = PackedStringArray()
	for option: Dictionary in game.current_view:
		expected_labels.append(String(option["label_de"]))
	var menu_matches_view: bool = shown.size() == expected_labels.size()
	for menu_index: int in shown.size():
		if shown[menu_index] != expected_labels[menu_index]:
			menu_matches_view = false
	_expect(menu_matches_view, "the answer buttons on screen are the shuffled options in the order the game reports")
	await _settle(game)
	var response_click: Dictionary = game.probe_click_response_on_screen(index)
	print("INPUT_CLICK scenario=%s action=respond button=%d text=\"%s\" attempts=%d phase_after=%s" % [
		String(scenario["id"]), index, String(response_click.get("clicked_text", "")),
		int(response_click.get("after", {}).get("attempts", 0)), String(response_click.get("after", {}).get("phase", "")),
	])
	_expect(index >= 0, "the correct answer is one of the visible buttons")
	_expect(int(response_click.get("after", {}).get("attempts", 0)) == 1, "a real click on an answer button counts as exactly one attempt")
	_expect(String(response_click.get("after", {}).get("phase", "")) == "solved",
		"clicking the answer sentence that matches the scene solves the scenario")

	var texts: Dictionary = game.probe_hud_texts()
	print("INPUT HUD speaker=\"%s\" utterance=\"%s\" prompt=\"%s\" status=\"%s\"" % [
		String(texts.get("speaker", "")), String(texts.get("utterance", "")), String(texts.get("prompt", "")), String(texts.get("status", "")),
	])
	var feedback: String = game.hud.feedback_text()
	print("INPUT FEEDBACK scenario=%s shown=\"%s\" recorded=\"%s\"" % [String(scenario["id"]), feedback, String(scenario.get("feedback_correct_de", ""))])
	_expect(String(texts.get("utterance", "")) == String(scenario.get("utterance_de", "")),
		"the HUD shows the German sentence from the scenario data")
	_expect(feedback == String(scenario.get("feedback_correct_de", "")),
		"the HUD shows the recorded correct feedback after the answer")

	var responses: PackedStringArray = game.hud.response_texts()
	print("INPUT MENU responses=%d order=%s" % [responses.size(), game.probe_state()["view_order"]])
	_expect(responses.size() == (scenario["options"] as Array).size(), "the answer menu shows every option of the scenario")
	_completed = true

# endregion

# region helpers

func _goto_action(game: Node, action_type: String) -> bool:
	for guard: int in 24:
		var state: Dictionary = game.probe_state()
		if String(state["phase"]) == "asking" and String(state["action_type"]) == action_type:
			return true
		if String(state["phase"]) == "asking":
			game.probe_skip()
		else:
			var days: Array = game.content.days()
			var current: int = int(state["day"])
			var next_day: int = current
			for day: int in days:
				if day > current:
					next_day = day
					break
			if next_day == current:
				break
			game.probe_next_day()
	_expect(String(game.probe_state()["action_type"]) == action_type, "found a %s scenario to test" % action_type)
	return String(game.probe_state()["action_type"]) == action_type


## Staging creates collision shapes at runtime, and a ray query only sees them after the physics
## server has processed them - which is also true before a human could click.
func _settle(game: Node) -> void:
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	await game.get_tree().process_frame


func _distinct_count(values: Array) -> int:
	var seen: Dictionary = {}
	for value: Variant in values:
		seen[String(value)] = true
	return seen.size()


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _option_ids(scenario: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for option: Variant in scenario.get("options", []):
		result.append(String((option as Dictionary)["id"]))
	return result


func _wrong_option_id(scenario: Dictionary) -> String:
	for option_id: String in _option_ids(scenario):
		if option_id != String(scenario["correct_option_id"]):
			return option_id
	return ""


func _collect_text(seen: PackedStringArray, hud_texts: Dictionary, scenario: Dictionary) -> void:
	for key: String in ["speaker", "utterance", "prompt", "held", "status"]:
		var text: String = String(hud_texts.get(key, ""))
		if not text.is_empty() and not seen.has(text):
			seen.append(text)
	for option: Variant in scenario.get("options", []):
		var label: String = String((option as Dictionary)["label_de"])
		if not seen.has(label):
			seen.append(label)


## English helper glosses that must never appear while playing. Glosses that are the German
## word itself (das Sofa / sofa) are excluded, otherwise the check would flag correct German.
func _forbidden_gloss_tokens(content: Variant) -> PackedStringArray:
	var german: Dictionary = {}
	for key: Variant in content.lemmas:
		german[String((content.lemmas[key] as Dictionary)["lemma"]).to_lower()] = true
	var result: PackedStringArray = PackedStringArray()
	for key: Variant in content.lemmas:
		var record: Dictionary = content.lemmas[key] as Dictionary
		for token: String in String(record["en"]).split(","):
			token = token.strip_edges()
			if token.length() < 5 or german.has(token.to_lower()):
				continue
			if not result.has(token):
				result.append(token)
	return result


func _check_gloss_placement(lines: Array, seen: PackedStringArray, gloss_tokens: PackedStringArray) -> void:
	var in_summary: int = 0
	for line: String in lines:
		for token: String in gloss_tokens:
			if line.to_lower().contains(token.to_lower()):
				in_summary += 1
				break
	_expect(in_summary >= 3, "the end-of-day summary shows the English gloss of the lemmas met")
	var leaked: PackedStringArray = PackedStringArray()
	for text: String in seen:
		for token: String in gloss_tokens:
			if text.to_lower().contains(token.to_lower()):
				leaked.append("'%s' contains '%s'" % [text, token])
	if not leaked.is_empty():
		for problem: String in leaked:
			_expect(false, "English gloss appeared during play: " + problem)
	print("LANGUAGE in_game_texts=%d english_gloss_leaks=%d summary_lines_with_gloss=%d" % [seen.size(), leaked.size(), in_summary])


func _stat_snapshot(progress: Variant, stat_key: String) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in progress.lemma_stats:
		result[String(key)] = int((progress.lemma_stats[key] as Dictionary)[stat_key])
	return result


func _stats_text(progress: Variant, scenario: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for lemma_id: String in scenario["target_lemma_ids"]:
		var values: Dictionary = progress.stats(lemma_id)
		parts.append("%s:%s" % [lemma_id, values])
	return ", ".join(parts)

# endregion
