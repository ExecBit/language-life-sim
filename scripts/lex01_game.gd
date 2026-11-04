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
## Point of view (TAV-02, Issue #9): the player is `scenes/fps_player.tscn`, a capsule with an eye
## camera, standing inside a room shell. An answer is given by putting the crosshair on something
## and pressing E or clicking - one interact path, one gate that decides whether the interface or
## the world owns the input, and one reach limit that comes from the room data. What a player does
## to answer (find_select / bring_deliver / respond) and what gets recorded are unchanged; only
## aiming replaced clicking a projected point on a fixed camera.
##
## Beginner flow: a run that has never been started opens in `briefing`, where 3D clicks do
## nothing until the onboarding overlay is closed, and the record its data marks `guided` is
## always presented first with its translation already open. Every later card hides its
## translation until the player asks for it.
##
## Retry policy: a wrong answer costs an attempt, never the run. After a wrong answer the
## objects and the answer order are rebuilt from the same record, so guessing by position
## cannot work, and the player can always continue with the skip button.

@onready var player: FpsPlayer = %Player
@onready var room_shell: StaticBody3D = %RoomShell
@onready var candidates: Node3D = %Candidates
@onready var npcs: Node3D = %NPCs
@onready var interior_root: Node3D = %Interior
@onready var hud: Lex01HUD = %HUD

var content: Lex01Content
var progress: Lex01Progress
var builder: Lex01RoomBuilder
# The tavern's fixed furniture, assembled from data once per run (TAV-03, Issue #10). It is a
# separate thing from the room builder on purpose: what stands in the room does not change from
# card to card, and only its `solid` entries stop the player.
var interior: Lex01Interior
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
# Pause is its own phase in the same pattern as the briefing: the phase that was running is kept
# and restored unchanged, so an overlay can never leave the learning loop in a state it never had.
var _pause_open: bool = false
var _phase_before_pause: String = ""
# Whether the answer menu of a respond task is on screen: while it is, the mouse and Enter belong
# to the menu and nothing in the room can be acted on.
var _answers_open: bool = false
# The cursor has exactly two modes, and aiming, looking and clicking all read this one state:
# captured means the mouse aims the crosshair, visible means the interface owns the mouse.
const CURSOR_CAPTURED: String = "captured"
const CURSOR_VISIBLE: String = "visible"
var _cursor_mode: String = CURSOR_VISIBLE
var _aim: Dictionary = {}
var _interact_range: float = 5.0
var _player_config: Dictionary = {}
var _probe_walk_frames: int = 300

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
	_player_config = content.player_config()
	_interact_range = float(_player_config.get("interact_range", 5.0))
	_probe_walk_frames = int(_player_config.get("probe_walk_frames", 300))
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
	# TAV-03 (Issue #10): the room is a tavern now, and it is built from data/room/lex01_room.json
	# rather than from nodes in the scene, so adding a table or a crate is a data change.
	interior = Lex01Interior.new()
	interior.setup(content, interior_root)
	var tavern: Dictionary = interior.build()
	for warning: String in interior.warnings:
		print("INTERIOR_WARNING %s" % warning)
	print("TAVERN built=%d solid=%d" % [int(tavern["built"]), int(tavern["solid"])])

	hud.continue_pressed.connect(_on_continue)
	hud.skip_pressed.connect(_on_skip)
	hud.end_day_pressed.connect(_on_end_day)
	hud.next_day_pressed.connect(_on_next_day)
	hud.reset_pressed.connect(_on_reset)
	hud.help_pressed.connect(_on_help)
	hud.hint_pressed.connect(_on_hint)
	hud.onboarding_close_pressed.connect(_on_close_onboarding)
	hud.response_chosen.connect(_on_response_chosen)
	hud.resume_pressed.connect(close_pause)
	hud.pause_reset_pressed.connect(_on_reset)
	hud.pause_quit_pressed.connect(_on_quit)
	hud.set_labels(content)
	player.set_tunables(_player_config)

	var day: int = int(content.days()[0])
	if progress.load_run() and content.days().has(progress.current_day):
		day = progress.current_day
		print("PROGRESS restored day=%d totals=%s" % [progress.current_day, progress.totals()])
	set_cursor(true)
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


## The keys, in one place. Every check is an action check on the event itself, so a key reaches the
## game exactly the way the probe drives it and exactly the way a player presses it.
func _unhandled_input(event: InputEvent) -> void:
	# Esc is the pause key now. It never ends a run directly: quitting is a button on the pause
	# menu, and while the briefing is open Esc closes the briefing instead.
	if event.is_action_pressed("ui_cancel"):
		if _pause_open:
			close_pause()
		elif _onboarding_open:
			close_onboarding()
		else:
			open_pause()
		return
	if event.is_action_pressed("open_help"):
		_on_help()
		return
	if event.is_action_pressed("hint"):
		request_hint()
		return
	if event.is_action_pressed("skip_task"):
		skip_current()
		return
	if event.is_action_pressed("continue_task"):
		_on_continue()
		return
	# E and the left mouse button share the `interact` action. The click half only counts while the
	# mouse is captured, because captured is when the crosshair is what the player aims with; a click
	# made while the cursor is free belongs to the interface, even on HUD space with no button under
	# it, and must never answer through the room behind that space.
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		if _cursor_mode != CURSOR_CAPTURED:
			return
		interact_with_target()
		return
	if event.is_action_pressed("interact"):
		interact_with_target()


## The crosshair answer is recomputed every physics frame: aiming changes with mouse-look and with
## walking, and the target label, the crosshair colour, the object highlight and the interact key
## all read this one answer instead of each aiming on their own.
func _physics_process(_delta: float) -> void:
	player.set_active(not _interface_is_open())
	# Looking follows the cursor, not the phase: mouse motion turns the view only while the mouse is
	# captured. While `Tab` or an overlay has released the cursor, moving the mouse reaches the HUD
	# and has to leave the view exactly where it was.
	player.set_look_enabled(_cursor_mode == CURSOR_CAPTURED)
	_aim = builder.target_at_crosshair(player.camera, _interact_range) if phase == "asking" and not _interface_is_open() else {}
	_report_aim()
	# Tab is read from the input state rather than from an event, because a focused HUD button would
	# otherwise eat it as focus navigation - and freeing the cursor is the one key that has to work.
	if Input.is_action_just_pressed("toggle_cursor") and not _interface_is_open():
		toggle_cursor()


# region aiming, interacting and cursor mode

## The only place a pick becomes an answer. Whatever aimed at it - E or a left click - the same
## rules apply: the interface has to be closed, the task has to be open, and what is aimed at has
## to be within the reach the room data declares. An aim that is too far answers with the too-far
## cue and records nothing at all, so walking past the room cannot cost an attempt.
func interact_with_target() -> void:
	if phase != "asking" or _interface_is_open():
		return
	last_input_seen = true
	last_pick_result = _aim
	if _aim.is_empty():
		hud.show_feedback(content.ui_line("target_none"), false)
		return
	if not bool(_aim.get("in_range", false)):
		hud.show_feedback(content.ui_line("target_too_far"), false)
		return
	match String(_aim.get("kind", "")):
		"option":
			answer_with_option(String(_aim["option_id"]))
		"delivery":
			deliver_to("object", "", String(staging.get("delivery_path", "")))
		"npc":
			deliver_to("npc", String(_aim.get("npc", "")), "")
		_:
			hud.show_feedback(content.ui_line("target_none"), false)


## What the line under the crosshair says: what E would do to the thing the crosshair is on. The
## three forms are interface text from data; the name is the German the scenario recorded.
func _aim_label() -> String:
	if _aim.is_empty():
		return ""
	if not bool(_aim.get("in_range", false)):
		return content.ui_line("target_too_far")
	var carrying: bool = not builder.held_option_id().is_empty()
	match String(_aim.get("kind", "")):
		"option":
			if String(current_scenario.get("action_type", "")) != "bring_deliver":
				return content.ui_line("interact_hint") % option_label(String(_aim.get("option_id", "")))
			return content.ui_line("interact_take") % option_label(String(_aim.get("option_id", "")))
		"delivery":
			if carrying:
				return content.ui_line("interact_deliver") % delivery_label()
		"npc":
			if carrying and String(current_scenario.get("action_type", "")) == "bring_deliver":
				return content.ui_line("interact_deliver") % npc_label(String(_aim.get("npc", "")))
	return ""


## One aim, three consumers: the crosshair colour, the label under it and the object highlight.
func _report_aim() -> void:
	var label: String = _aim_label()
	if label.is_empty():
		hud.set_target("", "off" if _interface_is_open() else "none")
		builder.clear_hover()
		return
	var state: String = "targeted"
	if not bool(_aim.get("in_range", false)):
		state = "far"
	elif not builder.held_option_id().is_empty():
		state = "held"
	hud.set_target(label, state)
	if state != "far" and String(_aim.get("kind", "")) == "option":
		builder.set_hover(String(_aim["option_id"]))
	else:
		builder.clear_hover()


## While the briefing, the pause menu, the day summary or an answer menu is on screen, the interface
## owns the mouse and the keys: a click can only act on the interface, never on an object behind it.
func _interface_is_open() -> bool:
	return _onboarding_open or _pause_open or _answers_open or phase == "briefing" or phase == "paused" \
		or phase == "day_finished" or phase == "run_finished"


## Captured is the normal state of play: the mouse looks and the crosshair aims. Tab, or any
## interface that opens, releases the cursor so the HUD can be clicked; capture returns with play.
func set_cursor(captured: bool) -> void:
	var wanted: String = CURSOR_CAPTURED if captured else CURSOR_VISIBLE
	if _cursor_mode == wanted:
		return
	_cursor_mode = wanted
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	player.set_look_enabled(captured)
	if captured:
		# A click is hit-tested at the OS cursor position, and a captured cursor does not move on its
		# own, so the position is put under the crosshair: what a player clicks is what they look at.
		get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.5)
		# No Control keeps focus while aiming, so Tab and the other shortcuts reach the game instead
		# of moving focus between buttons.
		get_viewport().gui_release_focus()
	print("CURSOR mode=%s phase=%s scenario=%s" % [_cursor_mode, phase, String(current_scenario.get("id", ""))])


func toggle_cursor() -> void:
	set_cursor(_cursor_mode == CURSOR_VISIBLE)


func sync_cursor() -> void:
	set_cursor(not _interface_is_open())


func cursor_mode() -> String:
	return _cursor_mode


func open_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	_phase_before_pause = phase
	phase = "paused"
	builder.clear_hover()
	hud.show_pause(content.ui_line("paused_note"))
	_update_buttons()
	sync_cursor()
	print("PAUSE opened scenario=%s phase_before=%s" % [String(current_scenario.get("id", "")), _phase_before_pause])


func close_pause() -> void:
	if not _pause_open:
		return
	_pause_open = false
	hud.hide_pause()
	phase = _phase_before_pause if not _phase_before_pause.is_empty() else "asking"
	_phase_before_pause = ""
	_update_buttons()
	sync_cursor()
	print("PAUSE closed scenario=%s phase=%s" % [String(current_scenario.get("id", "")), phase])


func pause_open() -> bool:
	return _pause_open

# endregion


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
	place_player(String(current_scenario.get("context", "")))
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
	_answers_open = String(current_scenario.get("action_type", "")) == "respond"
	if _answers_open:
		hud.show_response_options(shuffled_options())
	phase = "asking"
	_update_buttons()
	sync_cursor()


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
	sync_cursor()


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
	sync_cursor()
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
	# A respond task keeps the keyboard focus in its answer menu, so arrow keys and Enter keep
	# answering; every other phase hands focus to the button the player would press next.
	if not _answers_open:
		hud.focus_primary_button()


## Rebuild the same scenario with a fresh shuffle, keeping the feedback the player just read.
func restage_same_scenario() -> void:
	var feedback: String = String(hud.prompt_text())
	staging = builder.stage_scenario(current_scenario)
	_build_view()
	_answers_open = String(current_scenario.get("action_type", "")) == "respond"
	if _answers_open:
		hud.show_response_options(shuffled_options())
	else:
		hud.clear_responses()
	hud.show_feedback(feedback, false)
	sync_cursor()


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
	sync_cursor()


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
	# The pause menu offers a new run too, so the pause has to be closed before the new run starts:
	# otherwise the new briefing sits behind the old pause panel, and `Esc` would later restore a
	# phase saved from a run that no longer exists.
	_close_pause_state()
	reset_run()


## Drop pause state without handing back a phase. `close_pause()` is the resume path and restores
## what was running; this is the path that replaces the run instead.
func _close_pause_state() -> void:
	_pause_open = false
	_phase_before_pause = ""
	hud.hide_pause()


func _on_quit() -> void:
	get_tree().quit(0)


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
		"player_position": _position_text(player.global_position),
		"player_eye": _position_text(player.eye_position()),
		"cursor_mode": _cursor_mode,
		"pause_open": _pause_open,
		"answers_open": _answers_open,
		"target_label": hud.target_text(),
		"target_state": hud.target_state(),
		"interact_range": _interact_range,
		"aim": _aim_summary(),
	}


## What the crosshair is on right now, in a form a check can assert against.
func _aim_summary() -> Dictionary:
	if _aim.is_empty():
		return {"kind": "", "option_id": "", "npc": "", "distance": -1.0, "in_range": false, "label": ""}
	return {
		"kind": String(_aim.get("kind", "")),
		"option_id": String(_aim.get("option_id", "")),
		"npc": String(_aim.get("npc", "")),
		"distance": float(_aim.get("distance", -1.0)),
		"in_range": bool(_aim.get("in_range", false)),
		"label": _aim_label(),
	}


func _position_text(value: Vector3) -> String:
	return "%.2f|%.2f|%.2f" % [value.x, value.y, value.z]


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


# region first-person probe affordances (TAV-02)

## Walk to an answer the way a player walks to it - through the player's own movement code - and
## report what happened. This is what replaces clicking a projected screen point.
func probe_walk_to_option(option_id: String) -> Dictionary:
	var center: Vector3 = builder.option_center(option_id)
	if center == Vector3.ZERO:
		return {"error": "no staged object for %s" % option_id}
	var stop: float = _interact_range * 0.7
	var walk: Dictionary = await player.walk_to(center, stop, _probe_walk_frames)
	walk["option_id"] = option_id
	walk["stop_distance"] = stop
	# Aim at a visible part of the object rather than only at its middle, which is what a player does
	# when the middle is hidden behind something bigger.
	walk["aim"] = probe_face(option_id)
	return walk


## Walk forward blindly for a fixed number of physics frames, which is how a check shows that a
## wall stops the player instead of letting them leave the room or drop through the floor.
func probe_walk_forward(frames: int) -> Dictionary:
	var before: Dictionary = probe_state()
	var walk: Dictionary = await player.walk_forward_for(frames)
	walk["before_position"] = before["player_position"]
	walk["after"] = probe_state()
	return walk


## Recompute the crosshair answer and report it, without waiting for a physics frame.
func probe_aim() -> Dictionary:
	_aim = builder.target_at_crosshair(player.camera, _interact_range)
	_report_aim()
	return _aim_summary()


## Turn the eye toward an answer, which is exactly what aiming at it by hand means. If the first
## point lands the crosshair on something in front of it, the next points try the top of its box,
## because that is what a player does: they aim at the part of the object they can actually see.
func probe_face(option_id: String) -> Dictionary:
	var box: AABB = builder.option_aabb(option_id)
	if box.size.length() <= 0.0:
		return {"error": "no staged object for %s" % option_id}
	var top: float = box.position.y + box.size.y
	var points: Array[Vector3] = [
		box.get_center(),
		Vector3(box.get_center().x, top, box.get_center().z),
		Vector3(box.position.x + box.size.x * 0.25, top, box.get_center().z),
		Vector3(box.position.x + box.size.x * 0.75, top, box.get_center().z),
		Vector3(box.get_center().x, top, box.position.z + box.size.z * 0.75),
	]
	for point: Vector3 in points:
		player.face_point(point)
		var aim: Dictionary = probe_aim()
		if String(aim.get("option_id", "")) == option_id:
			return aim
	return probe_aim()


## How far an answer is from the eye, and whether that is inside the reach the room declares:
## the reachability question a player answers by walking. `surface_distance` is the distance to the
## nearest point of the object's box, because that is what the crosshair measures, not the middle
## of a large object.
func probe_reach(option_id: String) -> Dictionary:
	var center: Vector3 = builder.option_center(option_id)
	var box: AABB = builder.option_aabb(option_id)
	var eye: Vector3 = player.eye_position()
	var nearest: Vector3 = Vector3(
		clampf(eye.x, box.position.x, box.position.x + box.size.x),
		clampf(eye.y, box.position.y, box.position.y + box.size.y),
		clampf(eye.z, box.position.z, box.position.z + box.size.z),
	)
	return {
		"option_id": option_id,
		"distance": eye.distance_to(center),
		"surface_distance": eye.distance_to(nearest),
		"interact_range": _interact_range,
		"in_range": eye.distance_to(nearest) <= _interact_range,
		"center": _position_text(center),
	}


## Press E the way a player does, through the viewport, so the ordinary interact path runs.
func probe_press_interact() -> Dictionary:
	var pressed: InputEventKey = InputEventKey.new()
	pressed.physical_keycode = KEY_E
	pressed.pressed = true
	var released: InputEventKey = InputEventKey.new()
	released.physical_keycode = KEY_E
	released.pressed = false
	get_viewport().push_input(pressed)
	get_viewport().push_input(released)
	return probe_state()


## Press a named action key the way a player does: H for the translation, X to skip, F1 for the
## briefing, Tab to free the cursor. In first person these are the controls, not the HUD buttons.
func probe_press_key(action: String) -> Dictionary:
	var pressed: InputEventAction = InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	var released: InputEventAction = InputEventAction.new()
	released.action = action
	released.pressed = false
	get_viewport().push_input(pressed)
	get_viewport().push_input(released)
	return probe_state()


## Free or capture the cursor the way Tab does.
func probe_toggle_cursor() -> Dictionary:
	toggle_cursor()
	return probe_state()


## Move the mouse the way a player does, through the viewport, so the ordinary look path runs and a
## check can see whether the view turned or stayed where it was.
func probe_push_mouse_motion(relative: Vector2) -> Dictionary:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = relative
	motion.position = get_viewport().get_visible_rect().size * 0.5
	get_viewport().push_input(motion)
	return {
		"cursor_mode": _cursor_mode,
		"look_enabled": player.is_look_enabled(),
		"player_yaw": player.rotation_degrees.y,
		"camera_pitch": player.camera.rotation_degrees.x if player.camera != null else 0.0,
	}


## Click at the centre of the screen without aiming at anything first, which is what a player does
## when they click HUD space that has no button under it. With the cursor free this must stay a click
## on the interface, and with the mouse captured it is the ordinary crosshair action.
func probe_click_without_aim() -> Dictionary:
	var before: Dictionary = probe_state()
	_push_mouse_click(_crosshair_point())
	return {
		"cursor_mode": _cursor_mode,
		"pick": last_pick_result,
		"click_reached_world": last_input_seen,
		"before": before,
		"after": probe_state(),
	}


## Press the new-run button of the pause menu, which has to close the pause before the new run and
## its briefing appear.
func probe_pause_new_run() -> Dictionary:
	_on_reset()
	return probe_state()


func probe_open_pause() -> Dictionary:
	open_pause()
	return probe_state()


func probe_close_pause() -> Dictionary:
	close_pause()
	return probe_state()


## Where every staged answer stands in the room, so a check can confirm a spawn really looks at the
## situation instead of trusting one hand-placed coordinate.
func probe_spawn_clearance() -> Dictionary:
	var result: Dictionary = {"player": _position_text(player.global_position)}
	var blocked: PackedStringArray = PackedStringArray()
	var radius: float = float(_player_config.get("capsule_radius", 0.35))
	for option_id: String in builder.option_ids():
		var box: AABB = builder.option_aabb(option_id)
		if box.size.length() <= 0.0:
			continue
		var grown: AABB = box.grow(radius + 0.05)
		if grown.has_point(player.global_position) or grown.has_point(player.eye_position()):
			blocked.append(option_id)
	var npcs: Variant = content.room.get("npcs", null)
	if npcs is Dictionary:
		for npc_name: String in (npcs as Dictionary):
			var node: Node3D = builder.npc_node(npc_name)
			if node != null and node.global_position.distance_to(player.global_position) < radius + 0.6:
				blocked.append(String(node.name))
	result["blocked_by"] = blocked
	return result

# endregion


## Choose an answer sentence, as the response menu would.
func probe_respond(option_id: String) -> Dictionary:
	_on_response_chosen(option_id)
	return probe_state()


## Where the delivery target of the staged scenario is in the room, whether it is a prop or a
## person: the point the crosshair has to land on to answer a bring task.
func _delivery_target_point() -> Vector3:
	var kind: String = String(staging.get("delivery_kind", ""))
	if kind == "object":
		return builder.prop_center(String(staging.get("delivery_path", "")))
	if kind == "npc":
		var npc_node: Node3D = builder.npc_node(String(staging.get("delivery_npc", "")))
		if npc_node != null:
			return npc_node.global_position + Vector3(0, 0.9, 0)
	return Vector3.ZERO


## Click the delivery target the scenario declares, through the ordinary interact path, from where
## the player is standing. The first-person probe uses this to confirm the aim really lands on the
## target; the answer itself is given by walking to it and pressing E.
func probe_click_delivery_on_screen() -> Dictionary:
	var target: Vector3 = _delivery_target_point()
	if target == Vector3.ZERO:
		return {"error": "no delivery target to click", "staging": staging}
	player.face_point(target)
	var before: Dictionary = probe_state()
	_push_mouse_click(_crosshair_point())
	return {
		"screen": _crosshair_point(),
		"pick": last_pick_result,
		"aim": probe_aim(),
		"input_reached_game": last_input_seen,
		"before": before,
		"after": probe_state(),
	}


## Walk to a world point with the player's own movement, used by the containment and out-of-range
## checks so a walk can start and end at a known place in the room.
func probe_walk_to_point(point: Vector3) -> Dictionary:
	var walk: Dictionary = await player.walk_to(point, 0.8, _probe_walk_frames)
	walk["point"] = _position_text(point)
	return walk


## Walk to the delivery target the way a player walks to a person or a place they were told to bring
## something to.
func probe_walk_to_delivery_target() -> Dictionary:
	var target: Vector3 = _delivery_target_point()
	if target == Vector3.ZERO:
		return {"error": "no delivery target in the staged scenario", "staging": staging}
	var walk: Dictionary = await player.walk_to(target, _interact_range * 0.6, _probe_walk_frames)
	walk["aim"] = probe_face_point(target)
	return walk


## Turn the eye toward an exact world point and report what the crosshair landed on.
func probe_face_point(point: Vector3) -> Dictionary:
	player.face_point(point)
	return probe_aim()


## Put the player back at the spawn of the current context and walk straight ahead until a wall
## stops them: the containment check has to start from a known place and a known facing.
func probe_walk_into_wall(frames: int) -> Dictionary:
	place_player(String(current_scenario.get("context", "")))
	await get_tree().physics_frame
	return await probe_walk_forward(frames)


## Answer an answer-menu button with the keyboard instead of the mouse: the button is given focus
## (arrow keys do that for a player) and a real Enter key is pushed through the viewport, so the
## ordinary button activation and its `response_selected` signal run.
func probe_answer_response_with_keys(index: int) -> Dictionary:
	var texts: PackedStringArray = hud.response_texts()
	if index < 0 or index >= texts.size():
		return {"error": "no response button at index %d" % index}
	if not hud.focus_response(index):
		return {"error": "response button %d could not take keyboard focus" % index}
	var before: Dictionary = probe_state()
	var pressed: InputEventKey = InputEventKey.new()
	pressed.keycode = KEY_ENTER
	pressed.physical_keycode = KEY_ENTER
	pressed.pressed = true
	var released: InputEventKey = InputEventKey.new()
	released.keycode = KEY_ENTER
	released.physical_keycode = KEY_ENTER
	released.pressed = false
	get_viewport().push_input(pressed)
	get_viewport().push_input(released)
	return {
		"clicked_text": texts[index],
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


## Press the button on the briefing overlay itself, which is the one a beginner is meant to press -
## and the cursor is free while that overlay is open, so this click is what a player really does.
func probe_click_onboarding_close_on_screen() -> Dictionary:
	var screen: Vector2 = hud.onboarding_close_button_center()
	var before: Dictionary = probe_state()
	_push_mouse_click(screen)
	return {"screen": screen, "before": before, "after": probe_state()}


## Push a real left click while the eye is aimed at a staged object, through the ordinary interact
## path. This is the click half of the shared path: a click acts on the crosshair target, exactly
## like E, and never on wherever the OS cursor happens to be.
func probe_click_option_on_screen(option_id: String) -> Dictionary:
	var aim: Dictionary = probe_face(option_id)
	if String(aim.get("option_id", "")) != option_id:
		return {
			"error": "aiming at %s resolves %s instead" % [option_id, aim.get("option_id", aim.get("kind", "nothing"))],
			"aim": aim,
		}
	var before: Dictionary = probe_state()
	_push_mouse_click(_crosshair_point())
	return {
		"screen": _crosshair_point(),
		"pick": last_pick_result,
		"aim": aim,
		"input_reached_game": last_input_seen,
		"before": before,
		"after": probe_state(),
	}


## The point the crosshair is at, which is the point a click is aimed at while the mouse is captured.
func _crosshair_point() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


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


## The room shell's own bounds, merged from its collision shapes: a StaticBody3D has no bounding box
## of its own, and "is the player still inside the room" is a question about those shapes.
func room_shell_bounds() -> AABB:
	if room_shell == null:
		return AABB()
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var found: bool = false
	for child: Node in room_shell.get_children():
		if not (child is CollisionShape3D):
			continue
		var shape_node: CollisionShape3D = child as CollisionShape3D
		if shape_node.shape == null:
			continue
		for corner: Vector3 in _corners(_shape_rect(shape_node.shape)):
			var point: Vector3 = shape_node.global_transform * corner
			low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
			high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))
			found = true
	return AABB(low, high - low) if found else AABB()


## The box a collision shape occupies around its own origin. Godot's Shape3D has no bounding box of
## its own, and the room shell is built from boxes, so their declared size is the measurement.
func _shape_rect(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		var diameter: float = capsule.radius * 2.0
		return AABB(
			Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius),
			Vector3(diameter, capsule.height, diameter),
		)
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		return AABB(Vector3(-radius, -radius, -radius), Vector3(radius * 2.0, radius * 2.0, radius * 2.0))
	return AABB()


func _corners(box: AABB) -> Array[Vector3]:
	var low: Vector3 = box.position
	var high: Vector3 = box.position + box.size
	return [
		low,
		Vector3(high.x, low.y, low.z),
		Vector3(low.x, high.y, low.z),
		Vector3(low.x, low.y, high.z),
		Vector3(high.x, high.y, low.z),
		Vector3(high.x, low.y, high.z),
		Vector3(low.x, high.y, high.z),
		high,
	]


## Where the player stands for one context. TAV-02 (Issue #9) put the player where the fixed camera
## used to be, read from the same `cameras` section of the room layout: a day-2 revisit is still a
## different situation because the player is put down somewhere else and looks at a different layout.
func place_player(context: String) -> void:
	var config: Dictionary = content.camera_for(context)
	if config.is_empty():
		return
	var position_value: Variant = config.get("position", [0, 0, 0])
	if not (position_value is Array):
		return
	var rotation_value: Variant = config.get("rotation_deg", [0, 0, 0])
	player.spawn_at(
		Vector3(float((position_value as Array)[0]), float((position_value as Array)[1]), float((position_value as Array)[2])),
		Vector3(0.0, 0.0, 0.0) if not (rotation_value is Array) else Vector3(float(rotation_value[0]), float(rotation_value[1]), float(rotation_value[2])),
	)
	print("SPAWN context=%s scenario=%s position=%.2f|%.2f|%.2f" % [context, String(current_scenario.get("id", "")), player.global_position.x, player.global_position.y, player.global_position.z])


func _update_buttons() -> void:
	var asking: bool = phase == "asking"
	var solved: bool = phase == "solved"
	# While the onboarding overlay or the pause menu is open the only controls that make sense are
	# the ones on the overlay itself, and the panels behind them would only overlap them.
	var overlay: bool = phase == "briefing" or phase == "paused"
	hud.set_buttons(solved, asking, asking or solved, false, not overlay)
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
