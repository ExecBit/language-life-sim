extends Node3D

## LEX-01 gameplay (Issue #2): the only script that drives a learning situation.
##
## It knows three things and no more: the three action types, how a day is assembled from
## the `day` field, and how an answer is recorded. Every German sentence, every prop,
## every position and every interface label comes from data/*.json, which is why adding a
## learning situation - or rewording an instruction - never touches this file. Correctness is
## always compared against `correct_option_id`, so the visible position of an answer can never
## matter.
##
## Language split: `utterance_de`, the option labels and `feedback_correct_de` are the German the
## player is learning and are shown exactly as written. The instruction, status, held, skip and
## retry lines are interface text and come from data/ui/lex01_ui_ru.json.
##
## Beginner flow: a run that has never been started opens in `briefing`, where 3D clicks do
## nothing until the onboarding overlay is closed, and the record its data marks `guided` is
## always presented first with its translation already open. Every later card hides its
## translation until the player asks for it.
##
## Retry policy: a wrong answer costs an attempt, never the run. After a wrong answer the
## objects and the answer order are rebuilt from the same record, so guessing by position
## cannot work, and the player can always continue with the skip button.

@onready var camera: Camera3D = %Camera3D
@onready var candidates: Node3D = %Candidates
@onready var npcs: Node3D = %NPCs
@onready var hud: Lex01HUD = %HUD

var content: Lex01Content
var progress: Lex01Progress
var builder: Lex01RoomBuilder
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var seed_value: int = 0
var current_day: int = 1
var queue: Array[Dictionary] = []
var queue_index: int = 0
var current_scenario: Dictionary = {}
var staging: Dictionary = {}
var phase: String = "boot"
var attempts: int = 0
var last_pick_result: Dictionary = {}
var last_input_seen: bool = false
# The answer order the player is actually looking at, cached so a check can read the real
# visible order instead of drawing yet another random one.
var current_view: Array[Dictionary] = []
# Onboarding and translation are player state, not difficulty settings: the first one gates the
# very first card, the second only decides whether a translation is on screen and whether the
# answer counts as unaided.
var _onboarding_open: bool = false
var _phase_before_onboarding: String = ""
var _hint_open: bool = false

var _probe_mode: String = ""


func _ready() -> void:
	var options: Dictionary = _command_line_options()
	_probe_mode = String(options.get("probe", ""))
	seed_value = int(options.get("seed", Time.get_unix_time_from_system()))
	rng.seed = seed_value

	content = Lex01Content.new()
	if not content.load_all():
		for problem: String in content.errors:
			print("CONTENT_ERROR %s" % problem)
		print("LEX01 CONTENT FAIL")
		get_tree().quit(1)
		return
	for problem: String in content.errors:
		print("CONTENT_ERROR %s" % problem)
	print("CONTENT lemmas=%d scenario_files=%d scenarios=%d days=%s" % [
		content.lemmas.size(), content.scenario_files.size(), content.scenarios.size(), content.days(),
	])

	progress = Lex01Progress.new()
	# An automated run drives the real scene and really saves, so it is pointed at the probe file
	# before anything is loaded, saved or deleted. A probe run can therefore never read, rewrite
	# or delete the progress a human built by pressing F5.
	if not _probe_mode.is_empty():
		progress.use_probe_save()
	builder = Lex01RoomBuilder.new()
	builder.setup(content, candidates, npcs, rng)
	builder.prepare_npcs()
	for warning: String in builder.warnings:
		print("BUILDER_WARNING %s" % warning)

	hud.continue_pressed.connect(_on_continue)
	hud.skip_pressed.connect(_on_skip)
	hud.end_day_pressed.connect(_on_end_day)
	hud.next_day_pressed.connect(_on_next_day)
	hud.reset_pressed.connect(_on_reset)
	hud.help_pressed.connect(_on_help)
	hud.hint_pressed.connect(_on_hint)
	hud.onboarding_close_pressed.connect(_on_close_onboarding)
	hud.response_chosen.connect(_on_response_chosen)
	hud.set_labels(content)

	var day: int = int(content.days()[0])
	if progress.load_run() and content.days().has(progress.current_day):
		day = progress.current_day
		print("PROGRESS restored day=%d totals=%s" % [progress.current_day, progress.totals()])
	start_day(day)
	print("RUN seed=%d mode=%s" % [seed_value, _probe_mode if not _probe_mode.is_empty() else "play"])

	if not _probe_mode.is_empty():
		await get_tree().process_frame
		var probe_script: Variant = load("res://tools/lex01_probe.gd")
		if not (probe_script is GDScript):
			print("LEX01 PROBE FAIL missing or broken tools/lex01_probe.gd")
			get_tree().quit(1)
			return
		var probe: Variant = (probe_script as GDScript).new()
		if probe == null:
			print("LEX01 PROBE FAIL could not create the probe")
			get_tree().quit(1)
			return
		var verdict: Variant = await probe.run(self, _probe_mode)
		get_tree().quit(int(verdict))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit(0)
		return
	if event is InputEventMouseMotion and phase == "asking" and not _onboarding_open:
		var hover: Dictionary = builder.pick_at_screen(camera, event.position)
		if String(hover.get("kind", "")) == "option":
			builder.set_hover(String(hover["option_id"]))
		else:
			builder.clear_hover()
		return
	if phase != "asking" or _onboarding_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		last_input_seen = true
		var hit: Dictionary = builder.pick_at_screen(camera, event.position)
		last_pick_result = hit
		match String(hit.get("kind", "")):
			"option":
				answer_with_option(String(hit["option_id"]))
			"delivery":
				deliver_to("object", "", String(staging.get("delivery_path", "")))
			"npc":
				deliver_to("npc", String(hit.get("npc", "")), "")


# region day and scenario flow

func start_day(day: int) -> void:
	current_day = day
	progress.set_current_day(day)
	queue = []
	for scenario: Variant in _day_queue(day, rng):
		queue.append(scenario as Dictionary)
	queue_index = 0
	hud.hide_summary()
	present_current()
	# Teach before test: nobody should click a German sentence they were never told how to answer.
	if not progress.has_seen_onboarding():
		open_onboarding()


## The order one day is presented in. The record its data marks `guided` is always first and
## every other record keeps the existing shuffle, so the guarantee is a property of the data and
## not of one seed.
func _day_queue(day: int, shuffle_rng: RandomNumberGenerator) -> Array[Dictionary]:
	var guided: Dictionary = content.guided_scenario_for_day(day)
	var guided_id: String = String(guided.get("id", ""))
	var rest: Array[Dictionary] = []
	for scenario: Dictionary in content.scenarios_for_day(day):
		if String(scenario.get("id", "")) == guided_id:
			continue
		rest.append(scenario)
	var result: Array[Dictionary] = []
	if not guided.is_empty():
		result.append(guided)
	for scenario: Variant in _shuffled(rest, shuffle_rng):
		result.append(scenario as Dictionary)
	return result


func present_current() -> void:
	if queue_index >= queue.size():
		finish_day()
		return
	current_scenario = queue[queue_index]
	attempts = 0
	var guided: bool = bool(current_scenario.get("guided", false))
	# The guided example keeps the object positions its record authored, so the first task is one
	# calm example; a retry of it restages shuffled like every other retry.
	staging = builder.stage_scenario(current_scenario, guided)
	_apply_camera(String(current_scenario.get("context", "")))
	progress.present(current_scenario)
	_build_view()
	builder.speak(String(current_scenario.get("npc", "")))
	var prompt: String = content.action_prompt(String(current_scenario.get("action_type", "")))
	if guided:
		prompt = "%s\n%s" % [prompt, content.ui_line("guided")]
	hud.show_scenario(npc_label(String(current_scenario.get("npc", ""))), String(current_scenario.get("utterance_de", "")), prompt, status_text())
	_hint_open = guided
	if guided:
		progress.mark_hint_used(current_scenario)
		hud.set_gloss(_gloss_text())
	if String(current_scenario.get("action_type", "")) == "respond":
		hud.show_response_options(shuffled_options())
	phase = "asking"
	_update_buttons()


## The ? button: the onboarding overlay is available at any time, not only on a first run.
## Reopening while it is already open must not be a no-op that leaves `phase` behind the overlay,
## because presenting a card sets phase to "asking" before the briefing is opened again.
func open_onboarding() -> void:
	if not _onboarding_open:
		_phase_before_onboarding = phase
	_onboarding_open = true
	phase = "briefing"
	hud.show_onboarding("%s\n\n%s" % [content.onboarding_text(), content.ui_line("briefing_hint")])
	_update_buttons()


func close_onboarding() -> void:
	if not _onboarding_open:
		return
	_onboarding_open = false
	hud.hide_onboarding()
	progress.set_onboarding_seen(true)
	progress.save_run()
	phase = _phase_before_onboarding if not _phase_before_onboarding.is_empty() else "asking"
	_phase_before_onboarding = ""
	_update_buttons()
	print("ONBOARDING closed scenario=%s phase=%s" % [String(current_scenario.get("id", "")), phase])


## The learner asked for the translation of this task, so anything answered from now on is
## answered with a translation open and is recorded that way.
func request_hint() -> void:
	if _hint_open:
		return
	_hint_open = true
	progress.mark_hint_used(current_scenario)
	progress.save_run()
	hud.set_gloss(_gloss_text())
	print("HINT scenario=%s gloss_lines=%d assisted=true" % [String(current_scenario.get("id", "")), _gloss_lines().size()])


## What the translation reveals: the German sentence in Russian, then every German answer or
## object with its Russian meaning. The German stays on screen; the translation is added next to
## it, not instead of it.
func _gloss_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var utterance_gloss: String = String(current_scenario.get("utterance_gloss_ru", ""))
	if not utterance_gloss.is_empty():
		lines.append(utterance_gloss)
	for option: Variant in current_scenario.get("options", []):
		var record: Dictionary = option as Dictionary
		var gloss: String = String(record.get("gloss_ru", ""))
		if gloss.is_empty():
			for lemma_id: String in _option_lemma_ids(record):
				gloss = content.lemma_gloss_ru(lemma_id)
				if not gloss.is_empty():
					break
		if gloss.is_empty():
			continue
		lines.append("%s = %s" % [String(record.get("label_de", "")), gloss])
	return lines


func _gloss_text() -> String:
	var lines: PackedStringArray = _gloss_lines()
	if lines.is_empty():
		return ""
	if lines.size() == 1:
		return "%s %s" % [content.ui_line("gloss_prefix"), lines[0]]
	var rest: PackedStringArray = PackedStringArray()
	for index: int in range(1, lines.size()):
		rest.append(lines[index])
	return "%s %s\n%s" % [content.ui_line("gloss_prefix"), lines[0], "\n".join(rest)]


func _option_lemma_ids(option: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var value: Variant = option.get("lemma_ids", [])
	if value is Array:
		for entry: Variant in value:
			result.append(String(entry))
	return result


func npc_label(npc_name: String) -> String:
	var label: Variant = content.npc_config(npc_name).get("label_de", null)
	return String(label) if label != null else npc_name


## The visible order of the answers, freshly shuffled for every presentation and every retry.
func shuffled_options() -> Array[Dictionary]:
	return current_view


func _build_view() -> void:
	current_view = []
	# The answer order is shuffled for every presentation and every retry, including the guided
	# example: only its object positions are the authored ones, so position guessing never works.
	var pool: Array = _shuffled(scenario_options(), rng)
	for entry: Variant in pool:
		current_view.append(entry as Dictionary)


func scenario_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option: Variant in current_scenario.get("options", []):
		options.append(option as Dictionary)
	return options


func option_ids_in_view() -> Array[String]:
	var result: Array[String] = []
	for option: Dictionary in shuffled_options():
		result.append(String(option.get("id", "")))
	return result


func slot_map() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in staging.get("options", []):
		result[String(entry["id"])] = int(entry["slot"])
	return result


## Where each clickable answer actually stands, as a compact string, so a check can see that
## a retry really moved the objects instead of only re-deciding the order.
func option_positions() -> Dictionary:
	var result: Dictionary = {}
	for option_id: String in builder.option_ids():
		var center: Vector3 = builder.option_center(option_id)
		result[option_id] = "%.2f|%.2f|%.2f" % [center.x, center.y, center.z]
	return result


func status_text() -> String:
	var totals: Dictionary = progress.scenario_totals()
	return "%s %d · %d/%d · %s %d (%s %d, %s %d) · %s %d · %s %d" % [
		content.stat_label("day"), current_day, mini(queue_index + 1, queue.size()), queue.size(),
		content.stat_label("correct"), int(totals["solved"]),
		content.stat_label("unaided"), int(totals["solved_unaided"]),
		content.stat_label("assisted"), int(totals["solved_assisted"]),
		content.stat_label("incorrect"), int(totals["wrong_attempts"]),
		content.stat_label("skip"), int(totals["skipped"]),
	]


## A click on a candidate object. For bring_deliver the first click only picks the object up.
func answer_with_option(option_id: String) -> void:
	if phase != "asking":
		return
	var action: String = String(current_scenario.get("action_type", ""))
	if action == "respond":
		return
	if action == "bring_deliver" and builder.held_option_id().is_empty():
		builder.set_held(option_id)
		hud.set_held(_held_text(option_id))
		hud.set_status("%s · %s" % [status_text(), content.ui_line("delivery_hint") % delivery_label()])
		return
	if action == "bring_deliver":
		# Clicking another object while carrying one swaps what is carried, without penalty.
		builder.set_held(option_id)
		hud.set_held(_held_text(option_id))
		return
	record_attempt(option_id)


## Deliver what is carried to the place the player clicked. A bring task is only correct when
## both halves of the sentence are right: the carried object and the target.
func deliver_to(clicked_kind: String, clicked_npc: String = "", clicked_path: String = "") -> void:
	if phase != "asking":
		return
	var held: String = builder.held_option_id()
	if held.is_empty():
		hud.show_feedback(content.ui_line("nothing_held"), false)
		return
	var want_kind: String = String(staging.get("delivery_kind", ""))
	var want_npc: String = String(staging.get("delivery_npc", ""))
	var want_path: String = String(staging.get("delivery_path", ""))
	var target_ok: bool = clicked_kind == want_kind \
		and (want_kind != "npc" or clicked_npc == want_npc) \
		and (want_kind != "object" or clicked_path == want_path)
	if target_ok:
		builder.place_delivered(held, want_kind, want_npc, want_path)
	else:
		# The object was put somewhere else, so it goes back and the attempt is wrong.
		builder.clear_held()
	record_attempt(held, target_ok)


func record_attempt(option_id: String, target_ok: bool = true) -> void:
	var correct: bool = option_id == String(current_scenario.get("correct_option_id", "")) and target_ok
	attempts += 1
	progress.attempt(current_scenario, correct)
	progress.save_run()
	builder.clear_hover()
	hud.show_feedback(_feedback_text(correct), correct)
	hud.set_status(status_text())
	if correct:
		phase = "solved"
		builder.clear_held()
		hud.set_held("")
	else:
		# The retry gets a different room: objects move and the answer order changes.
		builder.clear_held()
		hud.set_held("")
		restage_same_scenario()
	_update_buttons()
	hud.focus_primary_button()


## Rebuild the same scenario with a fresh shuffle, keeping the feedback the player just read.
func restage_same_scenario() -> void:
	var feedback: String = String(hud.prompt_text())
	staging = builder.stage_scenario(current_scenario)
	_build_view()
	if String(current_scenario.get("action_type", "")) == "respond":
		hud.show_response_options(shuffled_options())
	else:
		hud.clear_responses()
	hud.show_feedback(feedback, false)


func advance() -> void:
	if queue_index >= queue.size():
		finish_day()
		return
	queue_index += 1
	progress.save_run()
	present_current()


func skip_current() -> void:
	if phase != "asking":
		return
	progress.skip(current_scenario)
	progress.save_run()
	hud.show_feedback(content.ui_line("skipped"), false)
	advance()


func finish_day() -> void:
	phase = "day_finished"
	builder.clear()
	builder.clear_hover()
	progress.mark_day_finished(current_day)
	progress.save_run()
	var days: Array[int] = content.days()
	var has_next: bool = current_day < days[days.size() - 1]
	var title: String = "%s %d · %s" % [content.stat_label("day"), current_day, content.stat_label("summary_title")]
	if not has_next:
		title += " · %s" % content.ui_line("no_next_day")
	hud.show_summary(title, progress.summary_lines(content))
	hud.set_buttons(false, false, false, has_next, true)
	if not has_next:
		phase = "run_finished"


func end_day() -> void:
	if phase == "asking":
		progress.skip(current_scenario)
		progress.save_run()
	finish_day()


func reset_run() -> void:
	progress.delete_run()
	start_day(int(content.days()[0]))


func _feedback_text(was_correct: bool) -> String:
	if was_correct:
		# The praise for a right answer stays exactly the German the scenario recorded.
		return String(current_scenario.get("feedback_correct_de", ""))
	# A wrong answer is explained in the interface language first. The recorded German feedback
	# stays under that line, because it is still comprehensible input.
	return "%s\n%s" % [content.ui_line("retry"), String(current_scenario.get("feedback_wrong_de", ""))]


func _held_text(option_id: String) -> String:
	var label: String = option_label(option_id)
	if _hint_open:
		for lemma_id: String in _option_lemma_ids(_option_record(option_id)):
			var gloss: String = content.lemma_gloss_ru(lemma_id)
			if not gloss.is_empty():
				label = "%s (%s)" % [label, gloss]
				break
	return content.ui_line("held") % label


func _option_record(option_id: String) -> Dictionary:
	for option: Variant in current_scenario.get("options", []):
		if String((option as Dictionary).get("id", "")) == option_id:
			return option as Dictionary
	return {}


func option_label(option_id: String) -> String:
	for option: Variant in current_scenario.get("options", []):
		if String((option as Dictionary).get("id", "")) == option_id:
			return String((option as Dictionary).get("label_de", ""))
	return option_id


func delivery_label() -> String:
	var target: Variant = current_scenario.get("delivery_target", null)
	if target is Dictionary:
		var label: Variant = (target as Dictionary).get("label_de", null)
		if label != null:
			return String(label)
		return npc_label(String((target as Dictionary).get("npc", "")))
	return ""


func is_solved() -> bool:
	return phase == "solved"


func is_asking() -> bool:
	return phase == "asking"


func onboarding_open() -> bool:
	return _onboarding_open


func hint_open() -> bool:
	return _hint_open

# endregion

# region hud callbacks

func _on_continue() -> void:
	if phase == "solved":
		advance()


func _on_skip() -> void:
	skip_current()


func _on_end_day() -> void:
	if phase == "asking" or phase == "solved":
		end_day()


func _on_next_day() -> void:
	var days: Array[int] = content.days()
	var next_day: int = current_day
	for day: int in days:
		if day > current_day:
			next_day = day
			break
	start_day(next_day)


func _on_reset() -> void:
	reset_run()


func _on_help() -> void:
	if _onboarding_open:
		close_onboarding()
	else:
		open_onboarding()


func _on_close_onboarding() -> void:
	close_onboarding()


func _on_hint() -> void:
	request_hint()


func _on_response_chosen(option_id: String) -> void:
	if phase != "asking" or String(current_scenario.get("action_type", "")) != "respond":
		return
	record_attempt(option_id)

# endregion

# region probes and setup helpers

## Snapshot the probe can assert against without driving the game.
func probe_state() -> Dictionary:
	return {
		"day": current_day,
		"scenario_id": String(current_scenario.get("id", "")),
		"action_type": String(current_scenario.get("action_type", "")),
		"phase": phase,
		"queue_index": queue_index,
		"queue_size": queue.size(),
		"attempts": attempts,
		"held": builder.held_option_id(),
		"view_order": option_ids_in_view(),
		"slots": slot_map(),
		"positions": option_positions(),
		"staged": builder.staged_count(),
		"responses": hud.response_count(),
		"totals": progress.totals(),
		"onboarding_open": _onboarding_open,
		"hint_open": _hint_open,
		"guided": bool(current_scenario.get("guided", false)),
		"gloss": hud.gloss_text(),
		"utterance_visible": hud.utterance_text(),
		"prompt": hud.prompt_text(),
		"status_visible": hud.status_text(),
		"onboarding_text": hud.onboarding_text(),
		"chrome": hud.chrome_labels(),
	}


func probe_select_option(option_id: String) -> Dictionary:
	answer_with_option(option_id)
	return probe_state()


func probe_deliver() -> Dictionary:
	return probe_deliver_at(String(staging.get("delivery_kind", "")), String(staging.get("delivery_npc", "")), String(staging.get("delivery_path", "")))


## Deliver to an explicit target so the probe can also check a delivery that went somewhere
## else: that has to count as a wrong attempt even when the carried object was the right one.
func probe_deliver_at(clicked_kind: String, clicked_npc: String, clicked_path: String) -> Dictionary:
	deliver_to(clicked_kind, clicked_npc, clicked_path)
	return probe_state()


## Choose an answer sentence, as the response menu would.
func probe_respond(option_id: String) -> Dictionary:
	_on_response_chosen(option_id)
	return probe_state()


## Click the delivery target the scenario declares, through the ordinary picking path.
func probe_click_delivery_on_screen() -> Dictionary:
	var kind: String = String(staging.get("delivery_kind", ""))
	var target: Vector3 = Vector3.ZERO
	if kind == "object":
		target = builder.prop_center(String(staging.get("delivery_path", "")))
	elif kind == "npc":
		var npc_node: Node3D = builder.npc_node(String(staging.get("delivery_npc", "")))
		if npc_node != null:
			target = npc_node.global_position + Vector3(0, 0.9, 0)
	if target == Vector3.ZERO:
		return {"error": "no delivery target to click", "staging": staging}
	var screen: Vector2 = camera.unproject_position(target)
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {
		"screen": screen,
		"pick": last_pick_result,
		"input_reached_game": last_input_seen,
		"before": before,
		"after": probe_state(),
	}


func probe_hud_texts() -> Dictionary:
	return {
		"speaker": hud.speaker_text(),
		"utterance": hud.utterance_text(),
		"prompt": hud.prompt_text(),
		"held": hud.held_text(),
		"status": hud.status_text(),
		"gloss": hud.gloss_text(),
		"onboarding": hud.onboarding_text(),
	}


func probe_skip() -> Dictionary:
	skip_current()
	return probe_state()


func probe_continue() -> Dictionary:
	if phase == "solved":
		advance()
	return probe_state()


func probe_end_day() -> Dictionary:
	finish_day()
	return probe_state()


func probe_next_day() -> Dictionary:
	_on_next_day()
	return probe_state()


func probe_reset() -> Dictionary:
	reset_run()
	return probe_state()


func probe_open_onboarding() -> Dictionary:
	open_onboarding()
	return probe_state()


func probe_close_onboarding() -> Dictionary:
	close_onboarding()
	return probe_state()


func probe_request_hint() -> Dictionary:
	request_hint()
	return probe_state()


## The order a day would be presented in for one seed, without presenting or recording anything,
## so a check can compare seeds instead of trusting a single run.
func probe_day_order(day: int, seed: int) -> PackedStringArray:
	var probe_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	probe_rng.seed = seed
	var ids: PackedStringArray = PackedStringArray()
	for scenario: Dictionary in _day_queue(day, probe_rng):
		ids.append(String(scenario.get("id", "")))
	return ids


## Press the ? button the way the HUD does.
func probe_click_help_on_screen() -> Dictionary:
	var screen: Vector2 = hud.help_button_center()
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {"screen": screen, "before": before, "after": probe_state()}


## Press the translation button the way the HUD does.
func probe_click_hint_on_screen() -> Dictionary:
	var screen: Vector2 = hud.hint_button_center()
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {"screen": screen, "before": before, "after": probe_state()}


## Press the button on the briefing overlay itself, which is the one a beginner is meant to press.
func probe_click_onboarding_close_on_screen() -> Dictionary:
	var screen: Vector2 = hud.onboarding_close_button_center()
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {"screen": screen, "before": before, "after": probe_state()}


## Find a screen point where this object really is the thing under the cursor, so the probe
## clicks where a player would click it instead of clicking through another object.
func probe_option_screen_point(option_id: String) -> Dictionary:
	var box: AABB = builder.option_aabb(option_id)
	if box.size.length() <= 0.0:
		return {"error": "no staged object for %s" % option_id}
	var top: float = box.position.y + box.size.y
	var candidates: Array[Vector3] = [
		box.get_center(),
		Vector3(box.get_center().x, top, box.get_center().z),
		Vector3(box.position.x + box.size.x * 0.25, top, box.get_center().z),
		Vector3(box.position.x + box.size.x * 0.75, top, box.get_center().z),
		Vector3(box.get_center().x, top, box.position.z + box.size.z * 0.25),
		Vector3(box.get_center().x, top, box.position.z + box.size.z * 0.75),
	]
	var tried: PackedStringArray = PackedStringArray()
	for point: Vector3 in candidates:
		var screen: Vector2 = camera.unproject_position(point)
		var hit: Dictionary = builder.pick_at_screen(camera, screen)
		tried.append("%s->%s" % [screen, hit.get("option_id", hit.get("kind", "none"))])
		if String(hit.get("option_id", "")) == option_id:
			return {"screen": screen, "hit": hit, "tried": tried}
	return {"error": "no screen point where %s is the object under the cursor" % option_id, "tried": tried}


## Push a real left click at the screen position of a staged object, so what gets tested is
## the ordinary mouse picking path. Returns what the picking resolved plus the state change.
func probe_click_option_on_screen(option_id: String) -> Dictionary:
	var point: Dictionary = probe_option_screen_point(option_id)
	if point.has("error"):
		return point
	var screen: Vector2 = point["screen"]
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {
		"screen": screen,
		"pick": last_pick_result,
		"direct_pick": builder.pick_at_screen(camera, screen),
		"tried": point.get("tried", []),
		"input_reached_game": last_input_seen,
		"before": before,
		"after": probe_state(),
	}


## Push a real left click onto a response button of the DialogueResponsesMenu.
func probe_click_response_on_screen(index: int) -> Dictionary:
	var texts: PackedStringArray = hud.response_texts()
	if index < 0 or index >= texts.size():
		return {"error": "no response button at index %d" % index}
	var center: Vector2 = hud.response_button_center(index)
	var before: Dictionary = probe_state()
	_push_mouse_click(center)
	return {
		"clicked_text": texts[index],
		"screen": center,
		"before": before,
		"after": probe_state(),
	}


func hud_utterance_text() -> String:
	return hud.utterance_text()


func hud_prompt_text() -> String:
	return hud.prompt_text()


func _push_mouse_click(screen: Vector2) -> void:
	last_pick_result = {}
	last_input_seen = false
	var pressed: InputEventMouseButton = InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = screen
	pressed.global_position = screen
	pressed.pressed = true
	var released: InputEventMouseButton = InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = screen
	released.global_position = screen
	released.pressed = false
	get_viewport().push_input(pressed)
	get_viewport().push_input(released)


func _command_line_options() -> Dictionary:
	var result: Dictionary = {}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in args.size():
		if args[index] == "--probe" or args[index] == "--probe-input":
			result["probe"] = "input" if args[index] == "--probe-input" else "logic"
		elif args[index] == "--seed" and index + 1 < args.size():
			result["seed"] = int(args[index + 1])
	return result


func _apply_camera(context: String) -> void:
	var config: Dictionary = content.camera_for(context)
	if config.is_empty():
		return
	camera.position = Vector3(
		float((config.get("position", [0, 4, 8.6]) as Array)[0]),
		float((config.get("position", [0, 4, 8.6]) as Array)[1]),
		float((config.get("position", [0, 4, 8.6]) as Array)[2]),
	)
	var rotation_deg: Variant = config.get("rotation_deg", [-22, 0, 0])
	if rotation_deg is Array:
		camera.rotation_degrees = Vector3(float(rotation_deg[0]), float(rotation_deg[1]), float(rotation_deg[2]))
	camera.current = true


func _update_buttons() -> void:
	var asking: bool = phase == "asking"
	var solved: bool = phase == "solved"
	# While the onboarding overlay is open the only control that makes sense is closing it, and
	# that button lives on the overlay itself.
	var briefing: bool = phase == "briefing"
	hud.set_buttons(solved, asking, asking or solved, false, not briefing)
	hud.set_hint_visible(asking)


func _shuffled(values: Array, shuffle_rng: RandomNumberGenerator) -> Array:
	var result: Array = values.duplicate()
	for i: int in range(result.size() - 1, 0, -1):
		var j: int = shuffle_rng.randi_range(0, i)
		var swap: Variant = result[i]
		result[i] = result[j]
		result[j] = swap
	return result

# endregion
