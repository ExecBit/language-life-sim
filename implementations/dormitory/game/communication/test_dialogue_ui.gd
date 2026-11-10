extends SceneTree
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for index in count: await physics_frame

func interact() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.unicode = 101
	event.pressed = true
	# Headless has no OS-focused window when no text field owns focus.
	root.push_input(event)
	await process_frame
	event.pressed = false
	root.push_input(event)
	await process_frame

func run() -> void:
	var scene = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	scene._advance()
	var session = scene.communication
	var actor = scene.house.actors.lena
	check(not session.conversation_open and not scene.ui.dialog.visible and not session.composer.visible,"NPC greeting cannot open full dialogue")
	check(session.subtitle_panel.visible and session.subtitle.text == "Лена: Hallo!","NPC greeting appears as subtitle")
	check(not scene.player.is_movement_paused and scene.player.is_physics_processing(),"Subtitles cannot block movement")
	await create_timer(3.3).timeout
	check(not session.subtitle_panel.visible and not scene.ui.dialog.visible,"Subtitle expires without opening dialogue")
	await scene._aim_at("lena")
	actor.go(actor.position+Vector3(1,0,0))
	await frames(2)
	scene.player.velocity = Vector3(2,0,0)
	scene.player.main_velocity = Vector3(2,0,0)
	check(scene._target() == "lena","Test camera targets visible NPC before E")
	await interact()
	check(session.conversation_open and scene.ui.dialog.visible and session.composer.visible,"E on visible NPC opens dialogue")
	check(scene.player.is_movement_paused and not scene.player.is_physics_processing(),"Open dialogue locks physics")
	check(scene.player.velocity == Vector3.ZERO and scene.player.main_velocity == Vector3.ZERO,"Old movement momentum is cleared")
	check(not session.subtitle_panel.visible,"Dialogue and subtitle do not overlap")
	var player_position: Vector3 = scene.player.position
	var actor_position: Vector3 = actor.position
	Input.action_press("forward")
	Input.action_press("jump")
	await frames(12)
	Input.action_release("forward")
	Input.action_release("jump")
	check(scene.player.position == player_position,"Typing WASD/jump cannot move the player")
	check(actor.position == actor_position and not actor.walking,"NPC route pauses during dialogue")
	session.composer.phrase.text = "Was ist das?"
	session.composer.release()
	session.composer.help_button.grab_focus()
	scene._controls()
	Input.action_press("right")
	await frames(6)
	Input.action_release("right")
	check(scene.player.position == player_position and scene.player.is_movement_paused,"Button focus cannot unlock movement")
	session.composer.matches.grab_focus()
	scene._controls()
	await frames(3)
	check(scene.player.position == player_position,"Suggestion-list focus cannot unlock movement")
	session.begin_point()
	check(session.selecting and not scene.player.is_movement_paused and scene.player.is_physics_processing(),"Pointing temporarily restores FPS")
	Input.action_press("back")
	await frames(12)
	Input.action_release("back")
	check(scene.player.position.distance_to(player_position) > 0.01,"FPS movement actually works during target selection")
	check(actor.position == actor_position,"NPC stays available while player selects target")
	session.cancel_point()
	check(session.conversation_open and scene.ui.dialog.visible and not scene.player.is_physics_processing(),"Cancel selection restores locked dialogue")
	check(session.composer.phrase.text == "Was ist das?","Target cancellation preserves draft")
	session.close()
	check(not session.conversation_open and not scene.ui.dialog.visible and scene.player.is_physics_processing(),"Close restores ordinary FPS")
	await frames(12)
	check(actor.position.distance_to(actor_position) > 0.05 and actor.walking,"NPC continues the same paused route")
	session.toggle_helper()
	session.toggle_helper()
	check(not scene.ui.dialog.visible and not session.conversation_open,"Closing H outside dialogue cannot open it")
	scene.optional_line = "Komm!"
	scene._show_dialog()
	check(session.subtitle.text == "Лена: Komm!" and not scene.ui.dialog.visible,"Later NPC line stays a subtitle")
	scene.player.camera.look_at(scene.player.camera.global_position+Vector3(0,1,5))
	await interact()
	check(not session.conversation_open,"E away from NPC cannot open dialogue")
	await scene._aim_at("lena")
	scene.transition = 0.5
	await interact()
	check(not session.conversation_open,"E during a transition cannot freeze the transition")
	scene.transition = 0
	print("MVP_DIALOGUE_UI: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("MVP_SUBTITLES_E_DIALOGUE_PLAYER_NPC_LOCK_PASS")
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
