class_name Lex01HUD
extends CanvasLayer

## The whole LEX-01 interface: one German sentence from the NPC, the answer buttons when
## the task is a spoken answer, and the day controls.
##
## The utterance label and the answer menu are Dialogue Manager's own maintained node types
## (`DialogueLabel` and `DialogueResponsesMenu`), used as widgets: the text comes from the
## scenario JSON instead of a .dialogue graph, so a new scenario needs no dialogue file.
## The plugin's example balloon is deliberately not used, because it marks every input as
## handled while it is open and would swallow the 3D clicks the find and bring tasks need.

## Language: the German this HUD shows is always the scenario record's own text. Every label it
## writes for itself comes from data/ui/lex01_ui_ru.json through `set_labels`, so the interface
## language is content and not a constant in this file.

signal continue_pressed()
signal skip_pressed()
signal end_day_pressed()
signal next_day_pressed()
signal reset_pressed()
signal help_pressed()
signal hint_pressed()
signal onboarding_close_pressed()
signal response_chosen(option_id: String)
signal resume_pressed()
signal pause_reset_pressed()
signal pause_quit_pressed()

# Crosshair states the game reports and the HUD only colours.
const CROSSHAIR_COLOR: Dictionary = {
	"off": Color(1, 1, 1, 0.15),
	"none": Color(1, 1, 1, 0.45),
	"targeted": Color(0.98, 0.85, 0.35, 0.95),
	"held": Color(1.0, 0.95, 0.6, 0.95),
	"far": Color(0.9, 0.42, 0.42, 0.95),
}

@onready var speaker_label: RichTextLabel = %SpeakerLabel
@onready var utterance_label: RichTextLabel = %UtteranceLabel
@onready var gloss_label: RichTextLabel = %GlossLabel
@onready var prompt_label: RichTextLabel = %PromptLabel
@onready var held_label: RichTextLabel = %HeldLabel
@onready var status_label: RichTextLabel = %StatusLabel
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu
@onready var continue_button: Button = %ContinueButton
@onready var skip_button: Button = %SkipButton
@onready var hint_button: Button = %HintButton
@onready var end_day_button: Button = %EndDayButton
@onready var next_day_button: Button = %NextDayButton
@onready var reset_button: Button = %ResetButton
@onready var help_button: Button = %HelpButton
@onready var summary_panel: PanelContainer = %SummaryPanel
@onready var summary_label: RichTextLabel = %SummaryLabel
@onready var onboarding_panel: PanelContainer = %OnboardingPanel
@onready var onboarding_label: RichTextLabel = %OnboardingLabel
@onready var onboarding_close_button: Button = %OnboardingCloseButton
@onready var crosshair_label: Label = %CrosshairLabel
@onready var target_label: RichTextLabel = %TargetLabel
@onready var controls_label: RichTextLabel = %ControlsLabel
@onready var pause_panel: PanelContainer = %PausePanel
@onready var pause_label: RichTextLabel = %PauseLabel
@onready var pause_resume_button: Button = %PauseResumeButton
@onready var pause_reset_button: Button = %PauseResetButton
@onready var pause_quit_button: Button = %PauseQuitButton

var _responses: Array[DialogueResponse] = []
var _last_feedback: String = ""
var _gloss: String = ""
var _target_text: String = ""
var _target_state: String = "none"


func _ready() -> void:
	# Everything is connected in code so the HUD stays a plain set of widgets.
	continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	end_day_button.pressed.connect(func() -> void: end_day_pressed.emit())
	next_day_button.pressed.connect(func() -> void: next_day_pressed.emit())
	reset_button.pressed.connect(func() -> void: reset_pressed.emit())
	help_button.pressed.connect(func() -> void: help_pressed.emit())
	hint_button.pressed.connect(func() -> void: hint_pressed.emit())
	onboarding_close_button.pressed.connect(func() -> void: onboarding_close_pressed.emit())
	pause_resume_button.pressed.connect(func() -> void: resume_pressed.emit())
	pause_reset_button.pressed.connect(func() -> void: pause_reset_pressed.emit())
	pause_quit_button.pressed.connect(func() -> void: pause_quit_pressed.emit())
	responses_menu.response_selected.connect(_on_response_selected)
	hide_summary()
	hide_onboarding()
	hide_pause()
	clear_gloss()
	set_target("", "off")
	set_buttons(false, false, false, false, false)


## Every control label the HUD owns, taken from the loaded interface content once.
func set_labels(content: Lex01Content) -> void:
	continue_button.text = content.button_label("continue")
	skip_button.text = content.button_label("skip")
	hint_button.text = content.button_label("hint")
	end_day_button.text = content.button_label("end_day")
	next_day_button.text = content.button_label("next_day")
	reset_button.text = content.button_label("reset")
	help_button.text = content.button_label("help")
	onboarding_close_button.text = content.button_label("close_onboarding")
	pause_resume_button.text = content.button_label("pause_resume")
	pause_reset_button.text = content.button_label("pause_new_run")
	pause_quit_button.text = content.button_label("pause_quit")
	# The control line is interface text too, so it comes from data like every other label.
	controls_label.text = content.ui_line("controls_hint")


func show_scenario(speaker: String, utterance: String, prompt: String, status: String) -> void:
	speaker_label.text = speaker
	utterance_label.text = utterance
	prompt_label.text = prompt
	status_label.text = status
	_last_feedback = ""
	set_held("")
	clear_gloss()
	clear_responses()
	summary_label.text = ""


## The Russian meaning of the German sentence and its answers. Empty means hidden, which is the
## default: only the guided example shows it unasked, and any other reveal is the player's choice.
func set_gloss(text: String) -> void:
	_gloss = text
	gloss_label.visible = not text.is_empty()
	gloss_label.text = "" if text.is_empty() else "[color=#9fc6e8]%s[/color]" % text


func clear_gloss() -> void:
	set_gloss("")


func gloss_text() -> String:
	return _gloss


func show_onboarding(text: String) -> void:
	onboarding_label.text = text
	onboarding_panel.visible = true
	onboarding_close_button.grab_focus()


func hide_onboarding() -> void:
	onboarding_panel.visible = false


func onboarding_open() -> bool:
	return onboarding_panel.visible


func onboarding_text() -> String:
	return onboarding_label.text


func hint_button_center() -> Vector2:
	return hint_button.get_global_rect().get_center()


func onboarding_close_button_center() -> Vector2:
	return onboarding_close_button.get_global_rect().get_center()


func set_hint_visible(visible: bool) -> void:
	hint_button.visible = visible


func help_button_center() -> Vector2:
	return help_button.get_global_rect().get_center()


## The crosshair cue line in the top-left corner, so a check can read the control reminder the player
## is meant to see instead of a copy of it.
func controls_text() -> String:
	return controls_label.text


## The labels of the controls themselves, so a check reads the buttons the player clicks instead
## of a copy of them.
func chrome_labels() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for button: Button in [continue_button, skip_button, hint_button, end_day_button, next_day_button, reset_button, help_button, onboarding_close_button, pause_resume_button, pause_reset_button, pause_quit_button]:
		result.append(button.text)
	return result


func show_feedback(text: String, was_correct: bool) -> void:
	var mark: String = "[color=#8fd08a]" if was_correct else "[color=#e08a8a]"
	prompt_label.text = "%s%s[/color]" % [mark, text]
	_last_feedback = text


## The feedback exactly as the scenario data recorded it, without the display markup.
func feedback_text() -> String:
	return _last_feedback


func set_status(text: String) -> void:
	status_label.text = text


func utterance_text() -> String:
	return utterance_label.text


func speaker_text() -> String:
	return speaker_label.text


func held_text() -> String:
	return held_label.text


func status_text() -> String:
	return status_label.text


func prompt_text() -> String:
	return prompt_label.text


func set_held(text: String) -> void:
	held_label.text = text


## Build the answer buttons in the order the game shuffled them. `order` entries are the
## scenario's option records; the option id is carried on DialogueResponse.id so the answer
## is resolved by id and never by button position.
func show_response_options(order: Array[Dictionary]) -> void:
	_responses.clear()
	for option: Dictionary in order:
		var response: DialogueResponse = DialogueResponse.new()
		response.id = String(option.get("id", ""))
		response.text = String(option.get("label_de", ""))
		response.is_allowed = true
		_responses.append(response)
	responses_menu.responses = _responses
	responses_menu.show()
	# The menu configures its own focus chain (arrow keys between the answer sentences) and focuses
	# its first item, so the keyboard can answer from the moment the task appears.


func clear_responses() -> void:
	_responses.clear()
	responses_menu.responses = []
	responses_menu.hide()


## Hand keyboard focus to one answer button, which is what the arrow keys do for a player.
func focus_response(index: int) -> bool:
	var items: Array = responses_menu.get_menu_items()
	if index < 0 or index >= items.size() or not (items[index] is Control):
		return false
	(items[index] as Control).grab_focus()
	return true


func set_buttons(continue_visible: bool, skip_visible: bool, end_day_visible: bool, next_day_visible: bool, reset_visible: bool) -> void:
	continue_button.visible = continue_visible
	skip_button.visible = skip_visible
	end_day_button.visible = end_day_visible
	next_day_button.visible = next_day_visible
	reset_button.visible = reset_visible
	# The hint belongs to a task, so it appears and disappears with the task controls.
	hint_button.visible = skip_visible


func focus_primary_button() -> void:
	for button: Button in [continue_button, next_day_button, end_day_button, skip_button]:
		if button.visible:
			button.grab_focus()
			return


## The crosshair and the line under it are the only place first-person targeting is reported, so
## the game pushes one state per frame and the HUD decides what it looks like. `text` empty means
## no aim: during a briefing, a pause, a summary or an answer menu nothing in the room is aimable.
func set_target(text: String, state: String) -> void:
	_target_text = text
	_target_state = state if CROSSHAIR_COLOR.has(state) else "none"
	var aiming: bool = _target_state != "off"
	crosshair_label.visible = aiming
	crosshair_label.modulate = CROSSHAIR_COLOR[_target_state]
	target_label.visible = not text.is_empty()
	if text.is_empty():
		target_label.text = ""
	elif _target_state == "far":
		target_label.text = "[color=#e08a8a]%s[/color]" % text
	else:
		var color: String = "#f0d76a" if _target_state != "held" else "#fff0b0"
		target_label.text = "[color=%s]%s[/color]" % [color, text]


func target_text() -> String:
	return _target_text


func target_state() -> String:
	return _target_state


func show_pause(text: String) -> void:
	pause_label.text = text
	pause_panel.visible = true
	pause_resume_button.grab_focus()


func hide_pause() -> void:
	pause_panel.visible = false


func pause_open() -> bool:
	return pause_panel.visible


func pause_text() -> String:
	return pause_label.text


func show_summary(title: String, lines: Array[String]) -> void:
	var text: String = "[b]%s[/b]\n" % title
	for line: String in lines:
		text += line + "\n"
	summary_label.text = text
	summary_panel.show()


func hide_summary() -> void:
	summary_panel.hide()
	summary_label.text = ""


func response_count() -> int:
	return responses_menu.get_menu_items().size()


func response_texts() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for item: Variant in responses_menu.get_menu_items():
		if item is Button:
			result.append(String((item as Button).text))
	return result


func response_button_center(index: int) -> Vector2:
	var items: Array = responses_menu.get_menu_items()
	if index < 0 or index >= items.size():
		return Vector2.ZERO
	return (items[index] as Control).get_global_rect().get_center()


func _on_response_selected(response: Variant) -> void:
	response_chosen.emit(String(response.id))
