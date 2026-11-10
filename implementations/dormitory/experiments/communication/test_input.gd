extends SceneTree
## Route real InputEventKey objects through Godot's viewport and focused LineEdit.
## This checks GUI routing, not OS keyboard-layout translation.
func _init() -> void:
	call_deferred("run")

func key(code: int, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode_value
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var scene = load("res://implementations/dormitory/experiments/communication/COMMUNICATION_EXPERIMENT.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	scene.state.active = true
	scene.panel.show()
	scene.controls(true)
	scene.prefix.grab_focus()
	for prefix in ["ich","will","sch"]:
		for character in prefix:
			await key(character.to_upper().unicode_at(0),character.unicode_at(0))
		if scene.prefix.text != prefix:
			push_error("Expected prefix '%s', got '%s'; focus %s" % [prefix,scene.prefix.text,root.gui_get_focus_owner()])
			quit(1)
			return
		await key(KEY_TAB)
		assert(scene.prefix.text == "","Tab did not select the word")
	assert(scene.phrase.text == "ich will Schlüssel")
	# Editing the assembled phrase must work before submission, without losing it.
	scene.phrase.grab_focus()
	await key(KEY_END)
	await key(KEY_X,120)
	assert(scene.phrase.text == "ich will Schlüsselx")
	await key(KEY_BACKSPACE)
	assert(scene.phrase.text == "ich will Schlüssel")
	scene.prefix.grab_focus()
	await key(KEY_ENTER)
	assert(scene.state.key_location == "player" and scene.response.text == "Hier, bitte.")
	assert(scene.key.get_parent() == scene.hand and not scene.state.opened)
	scene.reset(0)
	scene.state.active = true
	scene.panel.show()
	scene.controls(true)
	scene.phrase.text = "Öffne die Tür nicht"
	scene.phrase.grab_focus()
	await key(KEY_ENTER)
	assert(not scene.state.opened and not scene.action_running and scene.state.key_location == "anna")
	assert(scene.state.attempts[-1].parse.intent == "PROHIBIT_ACTION")
	print("COMMUNICATION_VIEWPORT_KEYBOARD_WILL_REQUEST_NEGATION_PASS")
	scene.queue_free()
	await process_frame
	quit()
