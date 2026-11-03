extends Node3D

## LEX-01 gameplay (Issue #2): the only script that drives a learning situation.
##
## It knows three things and no more: the three action types, how a day is assembled from
## the `day` field, and how an answer is recorded. Every German sentence, every prop and
## every position comes from data/*.json, which is why adding a scenario never touches this
## file. Correctness is always compared against `correct_option_id`, so the visible position
## of an answer can never matter.
##
## Retry policy: a wrong answer costs an attempt, never the run. After a wrong answer the
## objects and the answer order are rebuilt from the same record, so guessing by position
## cannot work, and the player can always continue with "Weiter ohne Antwort".

const ACTION_PROMPTS: Dictionary = {
	"find_select": "Klicke das gesuchte Objekt im Raum an.",
	"bring_deliver": "Klicke zuerst ein Objekt an, dann das Ziel. Du kannst das Objekt wechseln.",
	"respond": "Klicke den Satz, der zu dem passt, was du siehst.",
}
const SKIP_FEEDBACK_DE: String = "Übersprungen. Weiter geht es."

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
	hud.response_chosen.connect(_on_response_chosen)

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
	if event is InputEventMouseMotion and phase == "asking":
		var hover: Dictionary = builder.pick_at_screen(camera, event.position)
		if String(hover.get("kind", "")) == "option":
			builder.set_hover(String(hover["option_id"]))
		else:
			builder.clear_hover()
		return
	if phase != "asking":
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
	for scenario: Dictionary in _shuffled(content.scenarios_for_day(day)):
		queue.append(scenario)
	queue_index = 0
	hud.hide_summary()
	present_current()


func present_current() -> void:
	if queue_index >= queue.size():
		finish_day()
		return
	current_scenario = queue[queue_index]
	attempts = 0
	staging = builder.stage_scenario(current_scenario)
	_apply_camera(String(current_scenario.get("context", "")))
	progress.present(current_scenario)
	_build_view()
	builder.speak(String(current_scenario.get("npc", "")))
	var prompt: String = String(ACTION_PROMPTS.get(String(current_scenario.get("action_type", "")), ""))
	hud.show_scenario(npc_label(String(current_scenario.get("npc", ""))), String(current_scenario.get("utterance_de", "")), prompt, status_text())
	if String(current_scenario.get("action_type", "")) == "respond":
		hud.show_response_options(shuffled_options())
	phase = "asking"
	_update_buttons()


func npc_label(npc_name: String) -> String:
	var label: Variant = content.npc_config(npc_name).get("label_de", null)
	return String(label) if label != null else npc_name


## The visible order of the answers, freshly shuffled for every presentation and every retry.
func shuffled_options() -> Array[Dictionary]:
	return current_view


func _build_view() -> void:
	current_view = []
	var pool: Array = _shuffled(scenario_options())
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
	return "Tag %d · Aufgabe %d/%d · gelöst %d · falsche Antworten %d · übersprungen %d" % [
		current_day, mini(queue_index + 1, queue.size()), queue.size(),
		int(totals["solved"]), int(totals["wrong_attempts"]), int(totals["skipped"]),
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
		hud.set_held(option_label(option_id))
		hud.set_status(status_text() + " · Ziel: %s" % delivery_label())
		return
	if action == "bring_deliver":
		# Clicking another object while carrying one swaps what is carried, without penalty.
		builder.set_held(option_id)
		hud.set_held(option_label(option_id))
		return
	record_attempt(option_id)


## Deliver what is carried to the place the player clicked. A bring task is only correct when
## both halves of the sentence are right: the carried object and the target.
func deliver_to(clicked_kind: String, clicked_npc: String = "", clicked_path: String = "") -> void:
	if phase != "asking":
		return
	var held: String = builder.held_option_id()
	if held.is_empty():
		hud.show_feedback("Du hältst noch nichts. Klicke zuerst ein Objekt an.", false)
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
	hud.show_feedback(SKIP_FEEDBACK_DE, false)
	advance()


func finish_day() -> void:
	phase = "day_finished"
	builder.clear()
	builder.clear_hover()
	progress.mark_day_finished(current_day)
	progress.save_run()
	var days: Array[int] = content.days()
	var has_next: bool = current_day < days[days.size() - 1]
	var title: String = "Tag %d · dein Stand" % current_day
	if not has_next:
		title += " · kein weiterer Tag in den Szenarien"
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
		return String(current_scenario.get("feedback_correct_de", ""))
	return String(current_scenario.get("feedback_wrong_de", ""))


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
	hud.set_buttons(solved, asking, asking or solved, false, true)


func _shuffled(values: Array) -> Array:
	var result: Array = values.duplicate()
	for i: int in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = result[i]
		result[i] = result[j]
		result[j] = swap
	return result

# endregion
