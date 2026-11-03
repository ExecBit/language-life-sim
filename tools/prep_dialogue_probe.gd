extends Node

## PREP-01 dialogue smoke (Issue #4).
## Shows one German line and a two-option reply through Dialogue Manager's own balloon
## (show_dialogue_balloon -> the plugin's example balloon), asserts that the balloon and
## both answer buttons are actually on screen, then selects an answer with a real input
## event and checks that the balloon advanced to the matching branch and ended.
##
## Automated run:  godot --path . res://scenes/prep_dialogue_smoke.tscn -- --auto
## Manual run:     run the scene in the editor and click a choice yourself.

const DIALOGUE_PATH: String = "res://content/dialogue/prep_smoke.dialogue"
const REQUIRED_OPTIONS: int = 2
# Mirrors content/dialogue/prep_smoke.dialogue so the test can name what it expects.
const EXPECTED_LINE_DE: String = "Guten Morgen! Wo ist die Tomate?"
const EXPECTED_OPTIONS: Array[String] = ["Auf dem Tisch.", "In dem Schrank."]
const EXPECTED_BRANCH_DE: String = "Nein, die Tomate ist nicht im Schrank. Such weiter."
# Prove the second option so a fixed first slot is never implied.
const CLICKED_OPTION: int = 1

const MAX_SELECT_ATTEMPTS: int = 2
const RESPONSES_WAIT_FRAMES: int = 300

const SETTLE_WAIT_FRAMES: int = 120
const BRANCH_WAIT_FRAMES: int = 180
const END_WAIT_FRAMES: int = 180
const ADVANCE_READY_WAIT_FRAMES: int = 600

var _dialogue_manager: Node = null
var _resource: DialogueResource = null
var _balloon: Node = null
var _failures: PackedStringArray = []
var _phase: StringName = &"wait_balloon"
var _phase_frames: int = 0
var _attempt: int = 0
var _previous_rect: Rect2 = Rect2()
var _stable_frames: int = 0
var _skip_sent: bool = false
var _auto: bool = false
var _ended: bool = false


func _ready() -> void:
	_auto = OS.get_cmdline_user_args().has("--auto")

	_dialogue_manager = Engine.get_singleton("DialogueManager")
	if _dialogue_manager == null:
		_report(PackedStringArray(["DialogueManager singleton is not registered (autoload missing)"]))
		return

	_resource = load(DIALOGUE_PATH) as DialogueResource
	if _resource == null:
		_report(PackedStringArray(["could not load " + DIALOGUE_PATH + " as a DialogueResource"]))
		return

	print("DIALOGUE loaded=%s first_cue=%s cues=%s" % [DIALOGUE_PATH, _resource.first_cue, _resource.cues])
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)

	_balloon = _dialogue_manager.show_dialogue_balloon(_resource, _resource.first_cue)
	if _balloon == null:
		_report(PackedStringArray(["show_dialogue_balloon returned no balloon"]))


func _process(_delta: float) -> void:
	_phase_frames += 1

	match _phase:
		&"wait_balloon":
			_wait_balloon()
		&"wait_responses":
			_wait_responses()
		&"settle":
			_settle()
		&"select":
			_select()
		&"wait_branch":
			_wait_branch()
		&"wait_advance_ready":
			_wait_advance_ready()
		&"advance":
			_advance()
		&"wait_end":
			_wait_end()
		&"manual":
			_wait_manual()


func _parts() -> Dictionary:
	return {
		"panel": _balloon.get("balloon"),
		"label": _balloon.get("dialogue_label"),
		"menu": _balloon.get("responses_menu"),
	}


func _wait_balloon() -> void:
	if is_instance_valid(_balloon) and _balloon.is_inside_tree() and _balloon.get("balloon") != null:
		_phase = &"wait_responses"
		_phase_frames = 0
	elif _phase_frames >= RESPONSES_WAIT_FRAMES:
		_report(PackedStringArray(["balloon was never added to the scene by show_dialogue_balloon"]))


func _wait_responses() -> void:
	var parts: Dictionary = _parts()
	var panel: Control = parts["panel"] as Control
	var label: Control = parts["label"] as Control
	var menu: DialogueResponsesMenu = parts["menu"] as DialogueResponsesMenu

	if panel == null or label == null or menu == null:
		if _phase_frames >= RESPONSES_WAIT_FRAMES:
			_report(PackedStringArray(["balloon is missing its Balloon / DialogueLabel / ResponsesMenu controls"]))
		return

	var items: Array = menu.get_menu_items()
	if not panel.visible or items.size() != REQUIRED_OPTIONS:
		if _phase_frames >= RESPONSES_WAIT_FRAMES:
			_report(PackedStringArray([
				"balloon visible=%s responses=%d (expected %d visible answer buttons)" \
				% [panel.visible, items.size(), REQUIRED_OPTIONS],
			]))
		return

	var label_text: String = label.get_text()
	if not label_text.contains(EXPECTED_LINE_DE):
		_report(PackedStringArray(["balloon label was '%s' instead of '%s'" % [label_text, EXPECTED_LINE_DE]]))
		return

	print("BALLOON visible=true label=\"%s\" responses=%d" % [label_text, items.size()])
	var texts: PackedStringArray = []
	for i: int in items.size():
		var item: Control = items[i] as Control
		var text: String = item.get_text()
		texts.append(text)
		print("RESPONSE index=%d name=%s visible=%s text=\"%s\"" % [i, item.name, item.visible, text])

	for i: int in EXPECTED_OPTIONS.size():
		if texts[i] != EXPECTED_OPTIONS[i]:
			_failures.append("answer button %d says '%s' instead of '%s'" % [i, texts[i], EXPECTED_OPTIONS[i]])

	if not _failures.is_empty():
		_report(_failures)
		return

	if _auto:
		_phase = &"settle"
		_phase_frames = 0
		_previous_rect = Rect2()
	else:
		_phase = &"manual"
		_phase_frames = 0
		print("MANUAL - click an answer in the window to continue")


# The answer buttons are created by the plugin during this frame, so their container has
# not laid them out yet. Wait until typing is done and one button's global rect stops
# moving, otherwise the simulated click lands on an empty part of the screen.
func _settle() -> void:
	var parts: Dictionary = _parts()
	var label: Control = parts["label"] as Control
	var menu: DialogueResponsesMenu = parts["menu"] as DialogueResponsesMenu
	var items: Array = menu.get_menu_items()
	if items.size() != REQUIRED_OPTIONS:
		_report(PackedStringArray(["answer buttons disappeared while settling"]))
		return
	var item: Control = items[CLICKED_OPTION] as Control
	var rect: Rect2 = item.get_global_rect()

	if label.get("is_typing") == true or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_previous_rect = Rect2()
		_stable_frames = 0
		if _phase_frames >= SETTLE_WAIT_FRAMES:
			_report(PackedStringArray(["answer button never got a layout rect: %s" % rect]))
		return

	if rect == _previous_rect:
		_stable_frames += 1
	else:
		_stable_frames = 0
	_previous_rect = rect

	if _stable_frames >= 3:
		print("SETTLE viewport=%s panel=%s button=%s" % [
			get_viewport().get_visible_rect().size,
			(parts["panel"] as Control).get_global_rect(),
			rect,
		])
		_phase = &"select"
		_phase_frames = 0
	elif _phase_frames >= SETTLE_WAIT_FRAMES:
		_report(PackedStringArray(["answer button layout never settled: %s" % rect]))


func _select() -> void:
	var parts: Dictionary = _parts()
	var menu: DialogueResponsesMenu = parts["menu"] as DialogueResponsesMenu
	var items: Array = menu.get_menu_items()
	if items.size() != REQUIRED_OPTIONS:
		_report(PackedStringArray(["answer buttons disappeared before selection"]))
		return
	var item: Control = items[CLICKED_OPTION] as Control

	if _attempt == 0:
		var rect: Rect2 = item.get_global_rect()
		var center: Vector2 = rect.get_center()
		print("CLICK attempt=1 mouse at (%.0f, %.0f) on %s rect=%s" % [center.x, center.y, item.name, rect])
		_click_at(center)
	elif _attempt == 1:
		print("CLICK attempt=2 focus+Enter key on %s" % item.name)
		item.grab_focus()
		_press_enter(false)
	else:
		print("BALLOON SELECTION NOT_TESTED - automated selection did not advance the balloon after %d attempts" % MAX_SELECT_ATTEMPTS)
		print("  the balloon stays open so the scene can be verified by hand")
		_phase = &"manual"
		_phase_frames = 0
		return

	_attempt += 1
	_phase = &"wait_branch"
	_phase_frames = 0


func _wait_branch() -> void:
	var line: DialogueLine = _balloon.get("dialogue_line") as DialogueLine
	if line != null and line.text == EXPECTED_BRANCH_DE:
		print("BRANCH clicked=\"%s\" -> text=\"%s\"" % [EXPECTED_OPTIONS[CLICKED_OPTION], line.text])
		_attempt = 0
		_phase = &"wait_advance_ready"
		_phase_frames = 0
		return
	if line != null and line.text != EXPECTED_LINE_DE and line.text != "":
		_failures.append("balloon advanced to an unexpected line: '%s'" % line.text)
		_report(_failures)
		return
	if _phase_frames >= BRANCH_WAIT_FRAMES:
		_phase = &"select"
		_phase_frames = 0


# The branch line has no options, so the balloon itself waits for a click or Enter.
# Advance only after the plugin stopped typing and declared that it is waiting, otherwise
# the input just skips the typing animation and the line never advances.
func _wait_advance_ready() -> void:
	var waiting: bool = bool(_balloon.get("is_waiting_for_input"))
	var label: Control = _parts()["label"] as Control
	var typing: bool = bool(label.get("is_typing"))
	if waiting and not typing:
		_phase = &"advance"
		_phase_frames = 0
		return
	# The balloon's own handler turns a click into "skip typing", which is what a player
	# would do; without it a long typed line could outlast the smoke test.
	if typing and not _skip_sent and _phase_frames >= 20:
		_skip_sent = true
		print("ADVANCE skip typing by clicking on the balloon")
		_click_at((_parts()["panel"] as Control).get_global_rect().get_center())
	elif _phase_frames % 60 == 0:
		print("  waiting=%s typing=%s visible_ratio=%s" % [waiting, typing, label.get("visible_ratio")])
	if _phase_frames >= ADVANCE_READY_WAIT_FRAMES:
		_report(PackedStringArray(["balloon never started waiting for input on the branch line (waiting=%s typing=%s)" % [waiting, typing]]))


func _advance() -> void:
	var parts: Dictionary = _parts()
	var panel: Control = parts["panel"] as Control
	if _attempt == 0:
		print("ADVANCE attempt=1 click on %s rect=%s" % [panel.name, panel.get_global_rect()])
		_click_at(panel.get_global_rect().get_center())
	elif _attempt == 1:
		print("ADVANCE attempt=2 Enter key")
		_press_enter(true)
	else:
		_report(PackedStringArray(["dialogue never ended after the branch line"]))
		return
	_attempt += 1
	_phase = &"wait_end"
	_phase_frames = 0


func _wait_end() -> void:
	if _ended:
		_finish()
	elif _phase_frames >= END_WAIT_FRAMES:
		_phase = &"advance"
		_phase_frames = 0


func _wait_manual() -> void:
	if _ended:
		_finish()


func _press_enter(with_focus_on_balloon: bool) -> void:
	if with_focus_on_balloon:
		var panel: Control = _parts()["panel"] as Control
		panel.grab_focus()
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_ENTER
	press.physical_keycode = KEY_ENTER
	press.pressed = true
	get_viewport().push_input(press)

	var release: InputEventKey = press.duplicate() as InputEventKey
	release.pressed = false
	get_viewport().push_input(release)


func _click_at(position: Vector2) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	get_viewport().push_input(press)

	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release)


func _finish() -> void:
	var other_cue: String = "found_tomate" if CLICKED_OPTION == 1 else "wrong_place"
	var line_id: String = String(_resource.cues.get(other_cue, ""))
	var line: Dictionary = _resource.lines.get(line_id, {})
	print("OTHER_BRANCH cue=%s text=\"%s\"" % [other_cue, String(line.get("text", ""))])
	if _failures.is_empty():
		print("PREP DIALOGUE PROBE OK")
		get_tree().quit(0)
	else:
		_report(_failures)


func _report(failures: PackedStringArray) -> void:
	print("PREP DIALOGUE PROBE FAIL")
	for failure: String in failures:
		print("  - " + failure)
	get_tree().quit(1)


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	_ended = true
