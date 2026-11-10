extends SceneTree
const Parser = preload("res://implementations/dormitory/game/communication/parser.gd")
const Helper = preload("res://implementations/dormitory/game/communication/helper_catalog.gd")
var scene
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(code: int, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func say(text: String) -> void:
	scene.communication.composer.phrase.text = text
	scene.communication.submit(text)

func run() -> void:
	scene = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	await physics_frame
	for route in ["helped","declined","skipped"]:
		var water: bool = route == "helped"
		scene._start_new()
		check(Helper.rows(scene.state.flags).size() == 15,"I02 baseline helper only")
		check(scene._advance(),"A door")
		check(not scene.ui.dialog.visible and scene.communication.subtitle_time > 0,"UI automatic greeting is a subtitle")
		await scene._aim_at("lena")
		scene._interact()
		var session = scene.communication
		check(scene.ui.answer_ids.is_empty() and scene.ui.answers.get_child_count() == 0,"I01 no German response buttons")
		check(session.composer.visible,"I01 composer starts with greeting")
		# H is an ordinary character in a focused field, including habe.
		session.composer.prefix.grab_focus()
		await key(KEY_H,104)
		check(session.composer.prefix.text == "h" and not session.helper.visible,"I03 h is typed, not a helper hotkey")
		for character in "abe": await key(character.to_upper().unicode_at(0),character.unicode_at(0))
		check(session.composer.prefix.text == "habe","I03 habe can be typed")
		session.composer.clear()
		for character in "hallo": await key(character.to_upper().unicode_at(0),character.unicode_at(0))
		await key(KEY_TAB)
		check(session.composer.phrase.text == "Hallo","I01 Hallo is composed")
		scene._set_pause(true)
		check(scene.paused and not session.composer.visible,"I04 ordinary pause suspends composer")
		scene._set_pause(false)
		await process_frame
		await process_frame
		check(session.composer.phrase.text == "Hallo" and session.composer.prefix.has_focus(),"I04 ordinary pause restores draft and text focus")
		if water:
			session.composer.phrase.grab_focus()
			session.composer.phrase.caret_column = 3
			session.composer.help_button.pressed.emit()
			check(session.helper.visible and paused,"I02 clickable helper available while editing")
			check(session.helper_grid.get_child_count() == 30,"I02 fifteen baseline units, no future words")
			await key(KEY_ESCAPE)
			check(not session.helper.visible and not scene.paused and not paused,"I04 Escape closes note before pausing")
			check(session.composer.phrase.text == "Hallo" and session.composer.phrase.caret_column == 3,"I04 helper preserves draft/caret")
			session.composer.prefix.grab_focus()
		await key(KEY_ENTER)
		check(scene.state.completed.has("a_greeting") and session.last_parse.intent == "GREETING","I01 parsed greeting advances existing event")
		scene._enter_step(true)
		check(scene._advance(),"A entry to B")
		await scene._aim_at("lena")
		scene._interact()
		check(scene.step.id == "b_water" and session.context.pending == "offer","I05 actual water offer context")
		var offered_items: Dictionary = scene.state.items.duplicate()
		say("Ich will nicht, dass Anna die Tür öffnet")
		check(scene.state.items == offered_items and scene.step.id == "b_water","I05 unsupported phrase cannot consume the offer")
		say("Helfen bitte")
		check(session.context.pending == "help_target" and scene.state.items == offered_items,"I04 clarification does not consume the water offer")
		var cup_id: int = scene.house.items.cup.get_instance_id()
		if water:
			session.composer.release()
			await key(KEY_H,104)
			check(session.helper.visible,"I03 H outside text opens helper")
			await key(KEY_ESCAPE)
			check(session.context.pending == "help_target","I04 H preserves pending clarification")
		say("Ja" if water else "Nein")
		check(scene.state.items.cup == ("player" if water else "tray"),"I05 distinct physical cup outcome")
		check(scene.gesture_kind == ("yes" if water else "no") and scene.gesture_time > 0,"I05 expected FPS gesture")
		check(scene.house.actors.lena.visual.current == ("nod_yes" if water else "shake_head_no"),"I05 expected NPC gesture")
		check(scene.house.items.cup.get_instance_id() == cup_id,"I05 single cup")
		say("Ja") # duplicate callback during the transition
		scene._enter_step(true)
		await scene._aim_at("lena")
		scene._interact()
		var before: Dictionary = scene.state.items.duplicate()
		say("Ja")
		check(scene.state.items == before and session.last_parse.status == "NEEDS_CLARIFICATION","I05 no offer means no transfer")
		check(Helper.rows(scene.state.flags).any(func(row): return row[0] == "water"),"I09 first NPC exposure opens water entry")
		check(not Helper.rows(scene.state.flags).any(func(row): return row[0] == "bread"),"I09 bread not revealed before encounter")
		say("Noch einmal, bitte")
		var repeated: String = scene.ui.line.text
		say("Noch einmal bitte")
		check(scene.ui.line.text == repeated and scene.state.items == before,"I07 repeat same utterance without side effects")
		say("Ich verstehe nicht")
		check(scene.house.pointer_target == "bedroom" and scene.state.items == before,"I07 misunderstanding shows target, not item transfer")
		check(scene._advance(),"C follow")
		if water:
			await scene._aim_at("surface_room")
			scene._interact()
		await scene._aim_at("bag")
		scene._interact()
		await scene._aim_at("bag_stand")
		scene._interact()
		check(scene.step.id == "c_key" and scene.state.items.room_key == "key_tray","C existing physical actions")
		await scene._aim_at("lena")
		scene._interact()
		before = scene.state.items.duplicate()
		say("ich will Schlüssel")
		check(session.last_parse.intent == "REQUEST_ITEM" and scene.state.items == before,"I10 request resolves actual key location; no text pickup")
		await scene._aim_at("room_key")
		scene._interact()
		check(scene.step.id == "c_welcome" and scene.state.items.room_key == "player","C physical key pickup preserved")
		await scene._aim_at("lena")
		scene._interact()
		before = scene.state.items.duplicate()
		say("Was ist das?")
		check(session.selecting and scene.selecting and not scene.player.is_movement_paused,"I06 target choice restores FPS")
		session.toggle_helper()
		session.toggle_helper()
		check(session.selecting and session.pending_text == "Was ist das?" and not scene.player.is_movement_paused,"I04 note preserves pending selection")
		scene._cancel_target()
		check(not session.selecting and session.composer.phrase.text == "Was ist das?" and scene.state.items == before,"I04/I06 cancel preserves text, no effects")
		say("Was ist das?")
		# The bag stand is behind the desk from the default test camera; use its open side.
		scene.player.position = Vector3(2.0,0.9,-3.1)
		await physics_frame
		await physics_frame
		scene.camera.look_at(scene.house.position_of("bag"))
		check(scene._target() == "bag","I06 bag visible from the open side")
		scene._interact()
		check(not session.selecting and scene.ui.line.text == "Eine Tasche." and scene.house.pointer_target == "bag","I06 actual ray-selected target")
		check(scene.state.items == before,"I06 identify does not move items")
		session.close()
		check(not scene.player.is_movement_paused,"I04 close returns movement")
		scene.player.position = Vector3(3.3,0.9,-4.6)
		scene._interact()
		check(scene.state.day == 2 and scene.step.id == "f_arrival","E existing sleep progression")
		check(not scene.ui.dialog.visible,"F no forced morning dialogue")
		scene._layout(true)
		if route == "skipped":
			scene._finish_level()
			check(scene.state.finished and scene.state.cooking.status == "skipped","I08 skip does not block exit")
		else:
			await scene._aim_at("lena")
			scene._interact()
			check(scene.step.id == "f_offer","F optional contact starts existing offer")
			say("Ja" if route == "helped" else "Nein")
			scene._enter_step(true)
			var bread_id: int = scene.house.items.bread.get_instance_id()
			if route == "helped":
				session.toggle_helper()
				session.toggle_helper()
				check(Helper.rows(scene.state.flags).any(func(row): return row[0] == "bread"),"I09 bread opens on first script encounter")
				await scene._aim_at("bread")
				scene._interact()
				check(scene.step.id == "f_give" and scene.state.items.bread == "player","F physical take")
				await scene._aim_at("lena")
				scene._interact()
				check(scene.step.id == "f_place" and scene.state.items.bread == "lena","F physical give")
				scene._tick_breakfast(3.3)
				check(scene.state.flags.get("nimm_usage","") == "assisted","I09 H counted as help, not independent knowledge")
			else:
				scene._tick_breakfast(1.3)
				scene._enter_step(true)
				scene._tick_breakfast(1.3)
			check(scene.step.id == "g_ready" and scene.state.flags.breakfast_result == route,"I08 morning outcome")
			check(scene.house.items.bread.get_instance_id() == bread_id and scene.state.items.bread == "breakfast_table","I08 single loaf")
			scene._finish_level()
		var flags: Dictionary = scene.state.flags.duplicate()
		var items: Dictionary = scene.state.items.duplicate()
		check(scene._save(),"I08 safe save")
		scene._load_save()
		check(scene.state.flags == flags and scene.state.items == items and scene.state.finished,"I08/I09 save preserves helper exposure and world outcomes")
		check(Helper.rows(scene.state.flags).any(func(row): return row[0] == "key"),"I09 encountered words survive sleep and load")
		var history: Array = JSON.parse_string(scene.state.flags.comm_history)
		check(history.any(func(entry): return entry.assisted == water),"I09 assistance tracked separately")
		print("MVP_COMMUNICATION_ROUTE_PASS water=%s morning=%s" % [water,route])
	# Same parser, speaker-neutral grammar, contextual roles only.
	for text in ["ich will Schlüssel","Kannst du die Tür öffnen?","Öffne die Tür nicht","Wo Schlüssel?"]:
		var anna := Parser.parse(text,"",{"addressee":"anna"})
		var lena := Parser.parse(text,"",{"addressee":"lena"})
		check(anna.status == lena.status and anna.intent == lena.intent and anna.frame.object_id == lena.frame.object_id and anna.frame.polarity == lena.frame.polarity,"I10 shared semantics for both NPCs")
	check(Parser.parse("Lena, will Schlüssel","",{"addressee":"lena"}).intent == "REQUEST_ITEM","I10 vocative is independent of NPC name")
	check(Parser.parse("Hallo Lena","",{"addressee":"lena"}).intent == "GREETING","I10 greeting uses current addressee")
	# LEVEL_02 still enters through the existing route, with its unchanged legacy UI.
	scene._command("travel_shop")
	await process_frame
	scene.shopping.say("Hallo!",true)
	check(scene.shopping.active() and not scene.communication.enabled() and not scene.communication.composer.visible,"I12 shop stays legacy")
	check(scene.ui.answer_ids.size() == 4 and scene.ui.answers.visible,"I12 shop legacy conversation unchanged")
	print("MVP_COMMUNICATION_INTEGRATION: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("MVP_COMMUNICATION_I01_I11_AUTOMATED_PASS")
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
