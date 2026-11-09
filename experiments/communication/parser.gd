extends "res://game/communication/parser.gd"
## Compatibility adapter: only this scene defaults to Anna; rules remain shared.
static func parse(text: String, pointed_target := "", conversation: Dictionary = {}) -> Dictionary:
	var context := conversation.duplicate()
	if not context.has("addressee"): context.addressee = "anna"
	return preload("res://game/communication/parser.gd").parse(text,pointed_target,context)
