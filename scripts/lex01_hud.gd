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

signal continue_pressed()
signal skip_pressed()
signal end_day_pressed()
signal next_day_pressed()
signal reset_pressed()
signal response_chosen(option_id: String)

@onready var speaker_label: RichTextLabel = %SpeakerLabel
@onready var utterance_label: RichTextLabel = %UtteranceLabel
@onready var prompt_label: RichTextLabel = %PromptLabel
@onready var held_label: RichTextLabel = %HeldLabel
@onready var status_label: RichTextLabel = %StatusLabel
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu
@onready var continue_button: Button = %ContinueButton
@onready var skip_button: Button = %SkipButton
@onready var end_day_button: Button = %EndDayButton
@onready var next_day_button: Button = %NextDayButton
@onready var reset_button: Button = %ResetButton
@onready var summary_panel: PanelContainer = %SummaryPanel
@onready var summary_label: RichTextLabel = %SummaryLabel

var _responses: Array[DialogueResponse] = []
var _last_feedback: String = ""


func _ready() -> void:
	# Everything is connected in code so the HUD stays a plain set of widgets.
	continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	end_day_button.pressed.connect(func() -> void: end_day_pressed.emit())
	next_day_button.pressed.connect(func() -> void: next_day_pressed.emit())
	reset_button.pressed.connect(func() -> void: reset_pressed.emit())
	responses_menu.response_selected.connect(_on_response_selected)
	hide_summary()
	set_buttons(false, false, false, false, false)


func show_scenario(speaker: String, utterance: String, prompt: String, status: String) -> void:
	speaker_label.text = speaker
	utterance_label.text = utterance
	prompt_label.text = prompt
	status_label.text = status
	_last_feedback = ""
	set_held("")
	clear_responses()
	summary_label.text = ""


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
	held_label.text = text if text.is_empty() else "Du hältst: %s" % text


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
	responses_menu.focus_first_item()


func clear_responses() -> void:
	_responses.clear()
	responses_menu.responses = []
	responses_menu.hide()


func set_buttons(continue_visible: bool, skip_visible: bool, end_day_visible: bool, next_day_visible: bool, reset_visible: bool) -> void:
	continue_button.visible = continue_visible
	skip_button.visible = skip_visible
	end_day_button.visible = end_day_visible
	next_day_button.visible = next_day_visible
	reset_button.visible = reset_visible


func focus_primary_button() -> void:
	for button: Button in [continue_button, next_day_button, end_day_button, skip_button]:
		if button.visible:
			button.grab_focus()
			return


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
