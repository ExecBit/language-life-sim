extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://implementations/dormitory/experiments/communication/COMMUNICATION_EXPERIMENT.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	await physics_frame
	scene.state.active = true
	scene.panel.show()
	scene.prefix.text = "hal"
	scene.update_matches("hal")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	scene.composer.route_key(tab)
	assert(scene.phrase.text == "Hallo" and scene.prefix.text == "")
	scene.prefix.text_submitted.emit("")
	assert(scene.response.text == "Hallo!" and scene.phrase.text == "")
	assert(scene.state.attempts.size() == 1)
	scene.phrase.text = "Hallo Anna"
	scene.phrase.text_submitted.emit(scene.phrase.text)
	assert(scene.state.attempts.size() == 2 and scene.response.text == "Hallo!")
	var key_id: int = scene.key.get_instance_id()
	scene.player.position = Vector3(0,0.9,0)
	scene.player.move_and_collide(Vector3(0,0,-2))
	assert(scene.player.position.z > -1,"Locked door did not block the player")
	# Assemble words through the same prefix/selection path used by Enter.
	scene.state.active = true
	scene.panel.show()
	for word in ["Ich","will","Schlüssel"]:
		scene.prefix.text = word
		scene.update_matches(word)
		scene.choose_word()
	assert(scene.phrase.text.to_lower() == "ich will schlüssel")
	scene.submit()
	assert(scene.state.key_location == "player" and not scene.state.opened)
	assert(scene.key.get_parent() == scene.hand)
	scene.phrase.text = "Ich will Schlüssel"
	scene.submit()
	assert(scene.key.get_instance_id() == key_id and scene.state.successes == 0)
	assert(scene.state.open_door("player"))
	scene.sync_world()
	await physics_frame
	await physics_frame
	scene.player.position = Vector3(0,0.9,0)
	scene.player.move_and_collide(Vector3(0,0,-2))
	assert(scene.player.position.z < -1)
	scene.reset(0)
	scene.player.position = Vector3(1,0.9,1.8)
	scene.state.active = true
	scene.phrase.text = "Helfen bitte"
	scene.submit()
	assert(scene.state.pending == "help_target" and not scene.state.opened)
	scene.phrase.text = "Tür"
	scene.submit()
	await create_timer(3.5).timeout
	assert(scene.state.opened and scene.state.key_location == "anna")
	assert(scene.state.successes == 1 and not scene.action_running)
	assert(scene.key.get_instance_id() == key_id)
	scene.reset(3)
	assert(scene.state.key_location == "world" and not scene.state.knows)
	assert(scene.key.get_parent() == scene.key_table)
	for text in ["Ich will Schlüssel", "Öffne die Tür nicht", "Ich will die Tür öffnen", "Ich will nicht öffnen", "Ich will nicht, dass Anna die Tür öffnet", "Ich will Banane", "Anna hat keinen Schlüssel", "Das öffnen"]:
		scene.state.active = true
		scene.phrase.text = text
		scene.submit()
		assert(not scene.state.opened and not scene.action_running)
		assert(scene.state.key_location == "world" and scene.key.get_parent() == scene.key_table)
	scene.phrase.text = "Wo ist der Schlüssel?"
	scene.submit()
	assert(scene.response.text == "Das weiß ich nicht.")
	# New syntax for an explicit action must also drive the real NPC route.
	scene.reset(0)
	scene.state.active = true
	scene.phrase.text = "Kannst du die Tür öffnen?"
	scene.submit()
	assert(scene.action_running and not scene.state.opened)
	await create_timer(3.5).timeout
	assert(scene.state.opened and scene.state.successes == 1)
	assert(scene.key.get_instance_id() == key_id and scene.key.get_parent() == scene.anna.hand)
	print("COMMUNICATION_WORLD_TWO_PATHS_COLLISION_COMPOSER_RESET_PASS")
	scene.queue_free()
	await process_frame
	quit()
