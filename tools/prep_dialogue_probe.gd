extends Node

## PREP-01 dialogue smoke (Issue #4).
## Resolves one German line and a two-option reply through Dialogue Manager without
## showing any balloon UI, so the plugin itself is what is being tested.

const DIALOGUE_PATH: String = "res://content/dialogue/prep_smoke.dialogue"
const REQUIRED_OPTIONS: int = 2


func _ready() -> void:
	var failures: PackedStringArray = []
	var dialogue_manager: Node = Engine.get_singleton("DialogueManager")
	if dialogue_manager == null:
		_report(PackedStringArray(["DialogueManager singleton is not registered (autoload missing)"]))
		return

	var resource: DialogueResource = load(DIALOGUE_PATH) as DialogueResource
	if resource == null:
		_report(PackedStringArray(["could not load " + DIALOGUE_PATH + " as a DialogueResource"]))
		return

	print("DIALOGUE loaded=%s first_cue=%s" % [DIALOGUE_PATH, resource.first_cue])

	var line: DialogueLine = await dialogue_manager.get_next_dialogue_line(resource, resource.first_cue)
	if line == null:
		_report(PackedStringArray(["first dialogue line was null"]))
		return

	print("LINE character=%s text=%s" % [line.character, line.text])
	print("OPTIONS count=%d" % line.responses.size())
	for response: DialogueResponse in line.responses:
		print("  OPTION text=%s next_id=%s allowed=%s" % [response.text, response.next_id, response.is_allowed])

	if line.responses.size() != REQUIRED_OPTIONS:
		failures.append("expected %d options, got %d" % [REQUIRED_OPTIONS, line.responses.size()])

	if not failures.is_empty():
		_report(failures)
		return

	var chosen: DialogueResponse = line.responses[0]
	var branch: DialogueLine = await dialogue_manager.get_next_dialogue_line(resource, chosen.next_id)
	if branch == null:
		_report(PackedStringArray(["choosing the first option produced no line"]))
		return

	print("BRANCH chosen=\"%s\" -> character=%s text=%s" % [chosen.text, branch.character, branch.text])

	var other: DialogueResponse = line.responses[1]
	var other_branch: DialogueLine = await dialogue_manager.get_next_dialogue_line(resource, other.next_id)
	if other_branch == null:
		_report(PackedStringArray(["choosing the second option produced no line"]))
		return

	print("BRANCH chosen=\"%s\" -> character=%s text=%s" % [other.text, other_branch.character, other_branch.text])
	print("PREP DIALOGUE PROBE OK")
	get_tree().quit(0)


func _report(failures: PackedStringArray) -> void:
	print("PREP DIALOGUE PROBE FAIL")
	for failure: String in failures:
		print("  - " + failure)
	get_tree().quit(1)
