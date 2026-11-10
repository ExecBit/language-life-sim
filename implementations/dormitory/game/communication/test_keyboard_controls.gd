extends SceneTree
var checks := 0
var failures := 0
var sent: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func dispatch(code: int, unicode_value := 0, pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)
	await process_frame
	await process_frame

func key(code: int, unicode_value := 0) -> void:
	await dispatch(code,unicode_value)
	await dispatch(code,unicode_value,false)

func run() -> void:
	var scene = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	scene._advance()
	await scene._aim_at("lena")
	var session = scene.communication
	var composer = session.composer
	composer.submitted.connect(func(text): sent.append(text))
	# Test opening key, repeat while held, release, and then deliberate normal typing.
	await dispatch(KEY_E,101)
	check(session.conversation_open and composer.prefix.has_focus(),"E opens dialogue and focuses input")
	check(composer.prefix.text == "" and composer.phrase.text == "","Opening E must not leak into either field")
	await dispatch(KEY_E,101,true,true)
	check(composer.prefix.text == "","Holding opening E cannot insert repeat characters")
	await dispatch(KEY_E,101,false)
	check(composer.opener_key == 0,"Release ends opening-key suppression")
	await key(KEY_E,101)
	check(composer.prefix.text == "e","A later intentional e is typed normally")
	composer.clear()
	await key(KEY_H,104)
	await key(KEY_A,97)
	check(composer.prefix.text == "ha" and not session.helper.visible,"Letters still work in active input")
	await key(KEY_TAB)
	check(composer.phrase.text == "Hallo" and composer.prefix.text == "","Tab selects the highlighted word")
	check(sent.is_empty() and scene.step.id == "a_greeting","Tab cannot send or advance the scene")
	await dispatch(KEY_TAB,0,true,true)
	await dispatch(KEY_TAB,0,false)
	check(composer.phrase.text == "Hallo","Holding Tab does not append the default empty-prefix suggestion")
	composer.clear()
	composer.prefix.text = "ha"
	composer.update_matches("ha")
	await key(KEY_DOWN)
	var selected_word: String = composer.matches.get_item_text(composer.matches.get_selected_items()[0])
	check(selected_word != "Hallo","Arrows select another suggestion")
	await key(KEY_TAB)
	check(composer.phrase.text == selected_word and composer.prefix.has_focus(),"Tab accepts selected alternative and keeps text focus")
	await key(KEY_ENTER)
	check(sent.size() == 1 and sent[-1] == selected_word,"Enter sends once, without choosing another word")
	check(scene.player.is_movement_paused,"Sending keeps the active conversation movement lock")
	composer.clear()
	composer.phrase.text = "Öffne die Tür"
	composer.prefix.text = "nicht"
	composer.update_matches("nicht")
	composer.prefix.grab_focus()
	var before: Dictionary = scene.state.items.duplicate()
	await key(KEY_ENTER)
	check(sent[-1] == "Öffne die Tür nicht","Unconfirmed negation is sent literally instead of silently discarded")
	check(session.last_parse.intent == "PROHIBIT_ACTION" and scene.state.items == before,"Pending negation cannot become a positive world action")
	composer.clear()
	composer.phrase.text = "ich will"
	composer.prefix.text = "sch"
	composer.update_matches("sch")
	composer.matches.grab_focus()
	await key(KEY_ENTER)
	check(sent[-1] == "ich will sch" and session.last_parse.status == "UNKNOWN","Enter in suggestion list sends literal draft, not first completion")
	composer.phrase.text = "ich will"
	composer.prefix.text = "sch"
	composer.update_matches("sch")
	composer.matches.grab_focus()
	await key(KEY_TAB)
	check(composer.phrase.text == "ich will Schlüssel" and composer.prefix.text == "","Tab also selects from a focused suggestion list")
	await key(KEY_KP_ENTER)
	check(sent[-1] == "ich will Schlüssel" and session.last_parse.intent == "REQUEST_ITEM","Numpad Enter sends the composed sentence")
	composer.clear()
	composer.prefix.grab_focus()
	var count := sent.size()
	await key(KEY_TAB)
	await key(KEY_ENTER)
	check(composer.phrase.text == "" and sent.size() == count,"Empty Tab/Enter does not insert Anna or send an empty line")
	composer.prefix.text = "Hallo"
	composer.update_matches("Hallo")
	await key(KEY_ENTER)
	check(sent[-1] == "Hallo" and scene.state.completed.has("a_greeting"),"Enter can send a fully typed word without autocomplete acceptance")
	print("COMPOSER_KEYBOARD: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("MVP_TAB_SELECT_ENTER_SEND_E_OPENER_PASS")
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
