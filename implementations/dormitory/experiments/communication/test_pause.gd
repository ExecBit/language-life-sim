extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://implementations/dormitory/experiments/communication/COMMUNICATION_EXPERIMENT.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.state.active = true
	scene.state.pending = "help_offer"
	scene.panel.show()
	scene.phrase.text = "Ich brauche"
	scene.prefix.text = "sch"
	scene.prefix.grab_focus()
	scene.anna.go(Vector3(1.5,0,0))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	scene._input(esc)
	assert(paused and scene.paused and scene.pause_panel.visible and not scene.panel.visible)
	assert(scene.player.is_movement_paused)
	var position: Vector3 = scene.anna.position
	await create_timer(0.25,true).timeout
	assert(scene.anna.position == position,"NPC moved while paused")
	scene._input(esc)
	assert(not paused and not scene.pause_panel.visible and scene.panel.visible)
	assert(scene.phrase.text == "Ich brauche" and scene.prefix.text == "sch")
	assert(scene.state.pending == "help_offer" and scene.state.active)
	scene.close()
	scene._input(esc)
	assert(scene.pause_panel.visible)
	scene.reset_button.pressed.emit()
	assert(not paused and not scene.panel.visible and not scene.player.is_movement_paused)
	assert(scene.state.key_location == "anna" and not scene.state.opened)
	print("COMMUNICATION_ESCAPE_MENU_DRAFT_NPC_PAUSE_RESET_PASS")
	scene.queue_free()
	await process_frame
	quit()
