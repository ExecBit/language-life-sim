extends Node3D

const Communication = preload("res://game/communication/level_one_session.gd")
var communication: Node

const State = preload("res://game/prologue/prologue_state.gd")
const Story = preload("res://game/prologue/story.gd")
const House = preload("res://game/prologue/house.gd")
const Interface = preload("res://game/prologue/interface.gd")
const PLAYER = preload("res://addons/cogito/PackedScenes/cogito_player_simple.tscn")
const SAVE := "user://language_life_session_v5.json"
const PRIOR_PROLOGUE_SAVE := "user://language_life_prologue_v4.json"
const Shopping = preload("res://game/shop/shopping_session.gd")
const ShopState = preload("res://game/shop/shop_state.gd")
@export var start_in_shop := false
var shopping: Node
const PREVIOUS_SAVE := "user://language_life_prologue_v3.json"
const LEGACY_SAVE := "user://language_life_prologue_v2.json"
const SETTINGS := "user://language_life_prologue_settings.cfg"
const NAMES := {"lena":"Лена","anna":"Анна","player":"Вы","":""}
const GOALS := {"A":"Познакомьтесь с Леной и войдите в дом.","B":"Ответьте на предложение воды.","C":"Поставьте дорожную сумку у кровати и заберите ключ со стола.","D":"Осмотритесь, поговорите с Леной по желанию. Когда будете готовы — ложитесь спать.","E":"Наступает утро.","F":"Лена готовит завтрак. Можно помочь, отказаться или пройти мимо.","G":"Исследуйте дом, поздоровайтесь с Анной или попросите у неё воды. E у кровати завершает день.","END":"День 2 завершён. Это точка продолжения пролога."}

var state = State.new()
var steps: Array[Dictionary] = Story.build()
var step := {}
var house: Node3D
var player: CogitoPlayerSimple
var camera: Camera3D
var held: Marker3D
var ui: CanvasLayer
var checkpoint := {}
var menu_active := true
var paused := false
var pointer := false
var selecting := false
var choosing_subject := false
var pending_choice := ""
var elapsed := 0.0
var transition := 0.0
var gesture_time := 0.0
var gesture_kind := ""
var base_camera_rotation := Vector3.ZERO
var settings_parent := "menu"
var settings_values := {"volume":0.8,"sensitivity":0.22,"text_scale":1.0}
var exploration := false
var initialized := false
var automated := false
var optional_line := ""
var last_request := ""
var last_target := ""
var talking := false
var cooking_autosave := 0.0
var cooking_away := 0.0
var fixtures: Node
var life: Node

func _ready() -> void:
	preload("res://game/save_migration.gd").import_previous()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_size = Vector2i(1280,800)
	house = House.new()
	house.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(house)
	player = PLAYER.instantiate()
	player.position = Vector3(0,0.9,7.6)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	camera = player.camera
	player.player_hud.hide()
	player.player_interaction_component.set_process(false)
	held = Marker3D.new()
	held.position = Vector3(0.34,-0.29,-0.68)
	camera.add_child(held)
	ui = Interface.new()
	add_child(ui)
	ui.command.connect(_command)
	ui.setting_changed.connect(_setting)
	if start_in_shop:
		for label in ui.menu.find_children("*","Label",true,false):
			if label.text in ["ЗАСЕЛЕНИЕ","ОБЩЕЖИТИЕ"]: label.text = "ПЕРВЫЕ ПОКУПКИ"
			elif label.text in ["Language Life · Уровень 1","Пролог · Дни 1–2"]: label.text = "Language Life · Уровень 2"
	shopping = Shopping.new()
	shopping.controller = self
	add_child(shopping)
	communication = Communication.new()
	communication.controller = self
	add_child(communication)
	fixtures = preload("res://game/prologue/dormitory_fixtures.gd").new()
	fixtures.controller = self
	add_child(fixtures)
	life = preload("res://game/prologue/dormitory_life.gd").new()
	life.controller = self
	life.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(life)
	_register_inputs()
	_load_settings()
	_layout(true)
	house.sync_items(state,held)
	InputRouter.push(_input_event)
	_show_menu()
	if "--prologue-preview" in OS.get_cmdline_user_args(): _preview.call_deferred()

func _exit_tree() -> void:
	get_tree().paused = false
	if is_instance_valid(InputRouter): InputRouter.remove(_input_event)

func _register_inputs() -> void:
	var keys := {"prologue_interact":KEY_E,"prologue_pause":KEY_ESCAPE,"prologue_cursor":KEY_TAB,"prologue_goal":KEY_J,"prologue_cancel":KEY_BACKSPACE,"prologue_one":KEY_1,"prologue_two":KEY_2,"prologue_three":KEY_3,"prologue_four":KEY_4,"prologue_five":KEY_5,"prologue_six":KEY_6}
	for action in keys:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action,key)

func _input_event(event: InputEvent) -> void:
	if fixtures != null and initialized and not menu_active and not paused:
		if event is InputEventKey and event.pressed and not event.echo:
			if fixtures.mode != "":
				if event.keycode in [KEY_I,KEY_ESCAPE]: fixtures.close()
				elif event.keycode == KEY_H:
					fixtures.close()
					communication.toggle_helper()
				return
			if event.keycode == KEY_I and not communication.conversation_open:
				fixtures.open("player_pocket")
				return
	if communication != null and communication.input(event): return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("prologue_pause"):
		if ui.settings.visible: _command("settings_back")
		elif not menu_active: _set_pause(not paused)
		return
	if menu_active or paused: return
	if shopping != null and shopping.active():
		shopping.input(event)
		return
	if state.finished and not exploration: return
	if event.is_action_pressed("prologue_cancel") and step.get("id","") in ["a_greeting","b_water"] and not communication.conversation_open:
		_skip_intro()
		return
	if event.is_action_pressed("prologue_cancel") and not selecting and not choosing_subject and state.day == 2 and state.cooking.get("status","") in ["offered","accepted"]:
		_cancel_cooking("cancelled")
		return
	if event.is_action_pressed("prologue_goal"):
		ui.notify(GOALS.get(str(step.get("phase","A")),"Осмотритесь."))
		return
	if event.is_action_pressed("prologue_cancel") and (selecting or choosing_subject):
		_cancel_target()
		return
	if event.is_action_pressed("prologue_cursor"):
		pointer = not pointer
		_controls()
		return
	for i in 6:
		if event.is_action_pressed(["prologue_one","prologue_two","prologue_three","prologue_four","prologue_five","prologue_six"][i]):
			if communication == null and i < ui.answer_ids.size() and not selecting and not choosing_subject: _answer(ui.answer_ids[i])
			return
	if event.is_action_pressed("prologue_interact"):
		# Do not deliver the opening E to the newly focused LineEdit.
		get_viewport().set_input_as_handled()
		_interact()
		if communication != null and communication.enabled() and communication.conversation_open:
			communication.composer.suppress_opener(event)
		return
	if event is InputEventMouseMotion and not pointer and not choosing_subject:
		player.on_input(event)

func _controls() -> void:
	if communication != null: communication.sync_mode()
	player.is_movement_paused = (communication != null and communication.blocks_movement()) or pointer or choosing_subject or menu_active or paused or (state.finished and not exploration and (shopping == null or not shopping.active()))
	# A dialogue is a gameplay mode, independent of which widget owns text focus.
	var dialogue_lock: bool = communication != null and communication.blocks_movement()
	player.set_physics_process(not dialogue_lock)
	if dialogue_lock:
		player.velocity = Vector3.ZERO
		player.main_velocity = Vector3.ZERO
		player.last_velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if player.is_movement_paused else Input.MOUSE_MODE_CAPTURED

func _start_new() -> void:
	if communication != null: communication.reset()
	if fixtures != null: fixtures.close()
	life.reset()
	state = State.new()
	if shopping != null: shopping.reset()
	talking = false
	cooking_autosave = 0.0
	cooking_away = 0.0
	optional_line = ""
	last_request = ""
	last_target = ""
	initialized = true
	menu_active = false
	paused = false
	pointer = false
	selecting = false
	choosing_subject = false
	exploration = false
	transition = 0
	gesture_time = 0
	house.pointer_target = ""
	house.pulse_time = 0
	for actor in house.actors.values(): actor.idle()
	player.position = Vector3(0,0.9,7.6)
	player.body.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	ui.menu.hide()
	ui.pause_panel.hide()
	ui.complete_panel.hide()
	ui.subject.hide()
	get_tree().paused = false
	_take_checkpoint()
	_save()
	_enter_step(true)
	if start_in_shop:
		_prepare_shop_entry()
		shopping.travel_shop()
		return
	ui.notify("Осмотритесь. WASD — движение, E — взаимодействие. J — текущая цель.")

func _command(id: String) -> void:
	if id == "fixture_close": fixtures.close(); return
	if id == "fixture_deposit": fixtures.put_held(); return
	if shopping != null and shopping.handle_command(id): return
	if id.begins_with("answer:"):
		_answer(id.trim_prefix("answer:"))
		return
	if id.begins_with("subject:"):
		var target := id.trim_prefix("subject:")
		choosing_subject = false
		ui.subject.hide()
		if state.items.get(target) == "player": return
		house.point("lena",target)
		optional_line = "Hier."
		_show_dialog()
		pointer = false
		_controls()
		return
	match id:
		"new":
			if FileAccess.file_exists(SAVE):
				var confirmation := ConfirmationDialog.new()
				confirmation.title = "Новая игра"
				confirmation.dialog_text = "Заменить сохранение игры и начать заново?"
				confirmation.ok_button_text = "Начать заново"
				confirmation.cancel_button_text = "Отмена"
				ui.root.add_child(confirmation)
				confirmation.confirmed.connect(func(): _start_new(); confirmation.queue_free())
				confirmation.canceled.connect(confirmation.queue_free)
				confirmation.popup_centered()
			else: _start_new()
		"continue": _load_save()
		"resume": _set_pause(false)
		"menu":
			if initialized: _save()
			_show_menu()
		"quit":
			if initialized: _save()
			get_tree().quit()
		"settings":
			settings_parent = "menu" if menu_active else "pause"
			ui.menu.hide()
			ui.pause_panel.hide()
			ui.settings.show()
		"settings_back":
			ui.settings.hide()
			if settings_parent == "menu": ui.menu.show()
			else: ui.pause_panel.show()
		"fullscreen":
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		"cancel_target": _cancel_target()
		"explore":
			ui.complete_panel.hide()
			exploration = true
			pointer = false
			_controls()

func _show_menu() -> void:
	if fixtures != null and fixtures.mode != "": fixtures.close()
	if communication != null: communication.suspend()
	menu_active = true
	paused = false
	ui.menu.show()
	ui.chapter.text = "Пролог · Общежитие · Дни 1–2" if not start_in_shop else "Первые покупки"
	ui.pause_panel.hide()
	ui.settings.hide()
	ui.complete_panel.hide()
	ui.subject.hide()
	ui.dialog.hide()
	ui.prompt.text = ""
	ui.hide_shop_panel()
	ui.shop_status.hide()
	ui.shop_hud.hide()
	ui.continue_button.disabled = not _save_valid()
	if ui.continue_button.disabled and FileAccess.file_exists(SAVE): ui.notify("Сохранение повреждено или несовместимо. Файл не изменён.")
	get_tree().paused = true
	_controls()

func _set_pause(value: bool) -> void:
	if communication != null: communication.pause(value)
	paused = value
	ui.pause_panel.visible = value
	ui.complete_panel.visible = not value and state.finished and not exploration and not shopping.active()
	if shopping.active():
		ui.shop_panel.visible = not value and shopping.modal != ""
		ui.dialog.visible = not value and not shopping.selecting and shopping.dialogue != ""
		get_tree().paused = value
		_controls()
		return
	ui.subject.visible = choosing_subject and not value
	ui.dialog.visible = not value and not selecting and not choosing_subject and not step.get("text","").is_empty()
	if not value and not selecting and not choosing_subject: _show_dialog()
	get_tree().paused = value
	_controls()

func _enter_step(instant := false) -> void:
	if state.finished and state.index == _step_index("g_ready"): state.index = _step_index("complete")
	step = steps[state.index]
	optional_line = ""
	state.enter(step)
	if step.get("help",false):
		last_request = str(step.text)
		last_target = str(step.get("point",step.get("target","")))
	elapsed = 0
	transition = 0
	_layout(instant)
	house.sync_items(state,held)
	house.set_period(state.period)
	fixtures.sync()
	house.door.rotation.y = -PI/2 if state.flags.get("door_open",false) else 0.0
	house.door_collision.disabled = state.flags.get("door_open",false)
	if shopping != null and shopping.active():
		for actor in house.actors.values(): actor.attention.hide()
		return
	ui.chapter.text = "Общежитие · День %d · %s" % [state.day,{"day":"день","evening":"вечер","morning":"утро"}[state.period]]
	for actor in house.actors.values(): actor.attention.hide()
	var speaker := str(step.get("speaker",""))
	if house.actors.has("anna"):
		house.actors.anna.visible = state.day >= 2
		house.actors.anna.collision_layer = 1 if state.day >= 2 else 0
	if house.actors.has(speaker):
		house.actors[speaker].attention.show()
		var recipient := str(step.get("to","player"))
		var look: Vector3 = player.global_position if recipient == "player" else house.position_of(recipient)
		if state.day == 2 and not talking: look = Vector3(-4,1,-2.6)
		# LEVEL_01 attention is tied to an actual utterance, visibility and a short lease.
		if communication == null or not communication.enabled(): house.actors[speaker].face(look)
	if step.has("point"): _point(str(step.point))
	if step.has("gesture") and house.actors.has(speaker): house.actors[speaker].gesture(str(step.gesture))
	life.enter_step()
	_show_dialog()
	pointer = false
	_controls()
	if step.get("wait","") == "done" or state.finished:
		_take_checkpoint()
		_save()
		ui.dialog.hide()
		ui.complete_panel.show()
		pointer = true
		_controls()

func _layout(instant := false) -> void:
	var phase := str(steps[state.index].phase)
	var id := str(steps[state.index].id)
	var destination := Vector3(-3.8,0,-1)
	if phase == "A" and id != "a_enter": destination = Vector3(-0.55,0,4)
	elif phase in ["C","D"]: destination = Vector3(5.6,0,-1.65)
	if phase == "D" and state.flags.get("said_bye",false): destination = Vector3(-3.8,0,-1)
	if state.day == 2 and state.cooking.get("activity","") != "finished": destination = Vector3(-4,0,-1.5)
	if id == "f_self_walk": destination = Vector3(-5.1,0,-0.9)
	# Keep an existing route running across consecutive lines in the same room.
	var actor = house.actors.lena
	if instant or not actor.has_meta("destination") or actor.get_meta("destination") != destination:
		actor.go(destination,instant)
		actor.set_meta("destination",destination)

func _resolve(value: String) -> String:
	return state.chosen_target if value == "@target" else value

func _line() -> String:
	if not optional_line.is_empty(): return optional_line
	var text := str(step.get("text",""))
	if text == "@target": return {"bell":"Eine Glocke.","flashlight":"Eine Taschenlampe.","apple":"Ein Apfel."}.get(state.chosen_target,"Hier.")
	if text == "@where": return "Dein Schlüssel ist dort." if state.chosen_target == "room_key" else "Deine Tasche ist dort."
	return text

func _free_conversation() -> bool:
	return step.get("wait","") == "optional" or step.get("id","") == "g_ready"

func _responses() -> Array:
	var result: Array = step.get("answers",[]).duplicate()
	if step.id == "f_place" and not state.flags.get("morning_welcome",false): result.append({"id":"morning_welcome","text":"Bitte."})
	if _free_conversation():
		if state.day == 1 and not state.flags.get("thanked",false): result.append({"id":"thanks","text":"Danke!"})
		result.append({"id":"what","text":"Was ist das?"})
		if state.items.room_key != "player" or state.items.bag != "player": result.append({"id":"where","text":"Wo ist …?"})
		result.append({"id":"bye","text":"Tschüss!"})
		if state.day == 1: result.append_array([{"id":"repeat","text":"Noch einmal, bitte."},{"id":"show","text":"Ich verstehe nicht."}])
	if step.get("help",false):
		var repeat := {"id":"repeat","text":"Noch einmal, bitte."}
		var show := {"id":"show","text":"Ich verstehe nicht."}
		result.append_array([show,repeat] if step.phase == "H" else [repeat,show])
	if state.day == 2 and state.cooking.get("status","") in ["offered","accepted"]:
		result.append({"id":"cancel_cooking","text":"Отменить просьбу"})
	return result

func _show_dialog() -> void:
	if shopping != null and shopping.active(): return
	ui.display(NAMES[str(step.get("speaker",""))],NAMES[str(step.get("to",""))],_line(),[])
	if communication != null: communication.display()
	ui.text_scale(float(settings_values.text_scale))
	ui.dialog.visible = ui.dialog.visible and not selecting and not choosing_subject and not paused and not menu_active
	if state.day == 2 and (not talking or state.finished): ui.dialog.hide()

func _answer(id: String) -> void:
	if shopping != null and shopping.active():
		shopping.answer(id)
		return
	if menu_active or paused or transition > 0: return
	if id == "cancel_cooking":
		_cancel_cooking("cancelled")
		return
	if state.day == 2 and not talking: return
	if id in ["repeat","show"] and (step.get("help",false) or step.get("wait","") == "optional"):
		state.ask_help(str(step.id),id)
		if id == "repeat":
			optional_line = last_request
		else:
			_point(last_target)
			optional_line = "Hier."
		_show_dialog()
		_take_checkpoint()
		_save()
		return
	if id in ["morning_hello","morning_welcome"]:
		if (id == "morning_hello" and step.id != "f_arrival") or (id == "morning_welcome" and step.id != "f_place"): return
		if player.position.distance_to(house.actors.lena.position) > 4.5: return
		state.flags[id] = true
		ui.display("Вы","Лена","Hallo!" if id == "morning_hello" else "Bitte.",[])
		_take_checkpoint()
		_save()
		return
	if _free_conversation():
		if player.position.distance_to(house.actors.lena.position) > 4.5:
			ui.notify("Подойдите к Лене, чтобы обратиться к ней.")
			return
		match id:
			"thanks":
				state.flags.thanked = true
				if "danke" not in state.units: state.units.append("danke")
				optional_line = "Gern."
			"bye":
				state.flags.said_bye = true
				if "tschuss" not in state.units: state.units.append("tschuss")
				optional_line = "Tschüss!"
				if state.day == 1:
					state.period = "evening"
					house.set_period(state.period)
					_layout()
			"what":
				selecting = true
				pointer = false
				ui.dialog.hide()
				_controls()
				return
			"where":
				choosing_subject = true
				ui.subject.show()
				for button in ui.subject.find_children("*","Button",true,false):
					if button.text.contains("Schlüssel"): button.visible = state.items.room_key != "player"
					if button.text.contains("Tasche"): button.visible = state.items.bag != "player"
				_controls()
				return
			_: return
		_show_dialog()
		_take_checkpoint()
		_save()
		return
	var chosen := {}
	for answer in step.get("answers",[]):
		if str(answer.id) == id: chosen = answer
	if chosen.is_empty(): return
	if step.id == "b_water" and id == "yes" and not state.held("player").is_empty():
		ui.notify("Рука занята. Сначала поставьте предмет на свободную поверхность: E.")
		return
	var speaker: String = step.get("speaker","")
	var allowed_distance := 4.5
	for operation in chosen.get("ops",[]):
		if operation[0] == "move" and operation[3] == "player": allowed_distance = 3.2
	if house.actors.has(speaker) and player.position.distance_to(house.actors[speaker].position) > allowed_distance:
		pointer = false
		_controls()
		ui.notify("Подойдите к собеседнику.")
		return
	if chosen.get("intent","") == "target":
		selecting = true
		pending_choice = id
		pointer = false
		ui.dialog.hide()
		_controls()
		return
	if chosen.get("intent","") == "subject":
		choosing_subject = true
		pending_choice = id
		ui.subject.show()
		ui.dialog.hide()
		_controls()
		return
	_advance(id)

func _cancel_target() -> void:
	if communication != null and communication.selecting:
		communication.cancel_point()
		return
	selecting = false
	choosing_subject = false
	ui.subject.hide()
	_show_dialog()
	pointer = false
	_controls()

func _target() -> String:
	var start := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(start,start-camera.global_basis.z*3.2)
	query.exclude = [player.get_rid()]
	var hit := house.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return ""
	return str(hit.collider.get_meta("target_id",""))

func _interact() -> void:
	if transition > 0 or choosing_subject or exploration: return
	if communication != null:
		if communication.selecting:
			communication.confirm_point(_target())
			return
		if _target() == "lena": communication.reopen()
	var target := _target()
	if fixtures.interact(target): return
	if (step.id == "a_greeting" and player.position.z < 2.8) or (step.id == "b_water" and player.position.x > 1.5):
		_skip_intro()
	if target == "anna" and state.day == 2 and not state.finished:
		if player.position.distance_to(house.actors.anna.position) > 4.5:
			ui.notify("Подойдите к Анне, чтобы обратиться к ней.")
			return
		state.flags.anna_met = true
		var greeting: String = life.anna_greeting()
		communication.open_for("anna",greeting)
		_save()
		return
	if target == "bottle":
		if state.items.get("cup") != "player": ui.notify("Возьмите чашку, чтобы попить.")
		else: life.drink()
		return
	if selecting:
		if house.items.has(target) and state.items.get(target) not in ["player","lena"]:
			selecting = false
			house.point("lena",target)
			optional_line = {"bell":"Eine Glocke.","cup":"Eine Tasse.","bag":"Eine Tasche.","room_key":"Ein Schlüssel.","bread":"Ein Brot."}[target]
			if "was_ist_das" not in state.units: state.units.append("was_ist_das")
			if target == "bread" and "brot" not in state.units: state.units.append("brot")
			_show_dialog()
		else: ui.notify("Наведитесь на видимый доступный предмет. Backspace — отмена.")
		return
	if state.day == 2 and Vector2(player.position.x-3.3,player.position.z+4.6).length() < 1.2 and not state.finished:
		if state.cooking.get("activity","") != "finished":
			if state.cooking.get("status","") in ["available","offered","accepted"]: _cancel_cooking("sleep")
			if state.items.bread == "lena": state.transfer("bread","lena","breakfast_table")
			state.finish_without_loaf()
		state.index = _step_index("g_ready")
		_enter_step()
	if step.get("wait","") in ["optional","sleep_end"] and (target == "bed" or Vector2(player.position.x-3.3,player.position.z+4.6).length() < 1.2):
		# Farewell is offered, never required to unlock sleep.
		_advance()
		return
	if target == "lena":
		if state.day == 2:
			talking = true
			if step.id == "f_arrival":
				if not house.actors.lena.walking and state.offer_cooking():
					_advance()
				else:
					ui.display("Лена","Вы","Hallo!",[])
					if communication != null and communication.enabled(): communication.reply("Hallo!")
					pointer = false
					_controls()
				return
		if step.get("wait","") == "give":
			_advance()
			return
		_show_dialog()
		pointer = false
		_controls()
		return
	if _object_action(target):
		_check_object_progress()

func _object_action(target: String) -> bool:
	var item: String = state.held("player")
	var changed := false
	if target.begins_with("table_") and not item.is_empty():
		var surfaces: Array = {"table_common":["surface_common","tray"],"table_room":["surface_room","key_tray"],"table_side":["surface_side"]}.get(target,[])
		for surface in surfaces:
			if surface not in state.items.values():
				target = surface
				break
	if house.items.has(target) and state.items.get(target) not in ["lena","anna","player","player_pocket"]:
		if not item.is_empty():
			ui.notify("Рука занята. Поставьте предмет на свободную поверхность: E.")
			return false
		if target == "bell": return false
		if target == "bread" and state.day != 2: return false
		changed = state.transfer(target,str(state.items[target]),"player")
	elif house.anchors.has(target) and not item.is_empty():
		if target == "bag_stand" and item != "bag": return false
		if target == "entrance_bag" and item != "bag": return false
		if target in ["bell_stand","kitchen_shelf","breakfast_table"]: return false
		if target == "nightstand" and item != "room_key": return false
		changed = state.transfer(item,"player",target)
	if changed:
		house.sync_items(state,held)
		_take_checkpoint()
		_save()
	return changed

func _check_object_progress() -> void:
	var wait := str(step.get("wait",""))
	if wait == "stored" and state.items.get(str(step.item)) == step.anchor: _advance()
	elif wait == "owned" and state.items.get(str(step.item)) == "player": _advance()

func _advance(choice := "",payload := "") -> bool:
	var old := step.duplicate(true)
	if not state.complete(old,choice,payload): return false
	if old.get("wait","") in ["optional","sleep_end"]:
		life.stop_drink()
		life.settle_handoff()
	if communication != null: communication.before_transition(old.id == "f_arrival")
	if old.id == "f_offer" and choice == "no": talking = false
	if old.get("wait","") == "optional":
		player.position = Vector3(3.3,0.9,-4.2)
		player.body.rotation.y = PI
		player.head.rotation = Vector3.ZERO
		camera.rotation = Vector3.ZERO
		player.velocity = Vector3.ZERO
	house.sync_items(state,held)
	_take_checkpoint()
	_save()
	pointer = false
	_controls()
	var reply := ""
	for answer in old.get("answers",[]):
		if str(answer.id) == choice: reply = str(answer.text)
	if payload in ["room_key","bag"] and choice == "where": reply = "Wo ist mein Schlüssel?" if payload == "room_key" else "Wo ist meine Tasche?"
	if reply in ["Ja.","Nein."]:
		gesture_kind = "yes" if reply == "Ja." else "no"
		gesture_time = 0.7
		base_camera_rotation = camera.rotation
	if not reply.is_empty():
		ui.display("Вы",NAMES[str(old.get("speaker",""))],reply,[])
		if communication != null and communication.enabled(): communication.show_subtitle(reply,"Вы")
		transition = 1.0
	else: _enter_step(old.get("wait","") == "optional")
	return true

func _point(target: String) -> void:
	var id := _resolve(target)
	var actor := str(step.get("speaker","lena"))
	if house.actors.has(actor): house.point(actor,id)

func _process(delta: float) -> void:
	if menu_active or paused or automated or (communication != null and communication.helper.visible): return
	if fixtures.mode != "": return
	life.tick(delta)
	if communication != null and communication.enabled() and communication.conversation_open: return
	if shopping != null and shopping.active():
		_tick_cooking(delta)
		shopping.tick(delta)
		return
	if gesture_time > 0:
		gesture_time = maxf(0,gesture_time-delta)
		var angle := sin(gesture_time*18)*0.055*sin(gesture_time*PI/0.7)
		camera.rotation = base_camera_rotation + (Vector3(angle,0,0) if gesture_kind == "yes" else Vector3(0,angle,0))
	if transition > 0:
		transition -= delta
		if transition <= 0: _enter_step()
		return
	if state.day == 2:
		_tick_cooking(delta)
		if not state.finished and step.get("wait","") == "exit":
			var exit: Vector3 = house.zones.exit
			if Vector2(player.position.x-exit.x,player.position.z-exit.z).length() < 1.05:
				_finish_level()
				return
	if exploration or state.finished: return
	if (step.id == "a_greeting" and player.position.z < 2.8) or (step.id == "b_water" and player.position.x > 1.5): _skip_intro()
	var target := _target()
	ui.prompt.text = ""
	if selecting:
		ui.prompt.text = "E — выбрать видимый предмет · Backspace — отмена"
		return
	if state.held("player") != "" and (house.anchors.has(target) or target.begins_with("table_")): ui.prompt.text = "E — поставить предмет"
	elif target in ["bag","cup","room_key"] or (target == "bread" and state.day == 2): ui.prompt.text = "E — взять предмет"
	elif target == "lena": ui.prompt.text = "E — передать хлеб" if step.get("wait","") == "give" and state.held("player") == "bread" else "E — обратиться · H — слова · Tab — курсор"
	elif target.begins_with("door_"): ui.prompt.text = "E — открыть / закрыть дверь"
	elif target in ["room_door","drawer","room_lamp"]: ui.prompt.text = {"room_door":"E — открыть / закрыть дверь","drawer":"E — тумба · I — карман","room_lamp":"E — включить / выключить свет"}[target]
	elif target == "anna" and state.day == 2: ui.prompt.text = "E — поздороваться / обратиться"
	elif target == "bottle" and state.day == 2: ui.prompt.text = "E — выпить воды" if state.items.get("cup") == "player" else "Сначала нужна чашка"
	if step.id in ["a_greeting","b_water"]: ui.prompt.text += " · Backspace — продолжить заселение"
	var wait := str(step.get("wait",""))
	if state.day == 2 and Vector2(player.position.x-3.3,player.position.z+4.6).length() < 1.2: ui.prompt.text = "E — лечь спать"
	if wait in ["near","exit"]:
		var zone: Vector3 = house.zones[str(step.target)]
		if Vector2(player.position.x-zone.x,player.position.z-zone.z).length() < 1.05 or (str(step.target) == "bedroom" and player.position.x > 1.4):
			if wait == "exit" or (str(step.target) == "bedroom" and not house.actors.lena.walking) or _visible_actor("lena"): _advance()
	elif wait == "cooking": pass
	elif wait in ["npc_take","npc_place"]: pass
	elif wait in ["stored","owned"]: _check_object_progress()
	elif wait == "sleep_end":
		if Vector2(player.position.x-3.3,player.position.z+4.6).length() < 1.2: ui.prompt.text = "E — завершить день"
	elif wait == "optional":
		if Vector2(player.position.x-3.3,player.position.z+4.6).length() < 1.2:
			ui.prompt.text = "E — лечь спать"
		if not state.flags.get("said_bye",false) and player.position.distance_to(house.actors.lena.position) > 3.5:
			state.flags.said_bye = true
			optional_line = "Tschüss!"
			if "tschuss" not in state.units: state.units.append("tschuss")
			state.period = "evening"
			house.set_period(state.period)
			_layout()
			_show_dialog()
			_take_checkpoint()
			_save()
	elif wait == "" and step.get("answers",[]).is_empty() and _visible_actor("lena"):
		elapsed += delta
		if elapsed > 2.8: _advance()

func _skip_intro() -> void:
	if step.id not in ["a_greeting","b_water"]: return
	if communication.conversation_open: communication.close()
	state.flags[str(step.id)+":choice"] = "skipped"
	if str(step.id) not in state.completed: state.completed.append(str(step.id))
	state.index = _step_index("b_water" if step.id == "a_greeting" else "c_follow")
	_enter_step()
	_save()

func _step_index(id: String) -> int:
	for i in steps.size():
		if str(steps[i].id) == id: return i
	return -1

func _cancel_cooking(reason: String) -> void:
	if not state.skip_cooking(reason): return
	if communication != null: communication.before_transition()
	talking = false
	selecting = false
	choosing_subject = false
	pointer = false
	transition = 0.0
	cooking_away = 0.0
	ui.subject.hide()
	if state.items.bread == "kitchen_shelf" and state.held("lena") == "":
		state.index = _step_index("f_self_walk")
	elif state.items.bread == "lena":
		state.index = _step_index("f_self_return")
	else:
		state.finish_without_loaf()
		state.index = _step_index("g_ready")
	_enter_step()
	_save()

func _finish_level() -> void:
	if state.finished: return
	_cancel_cooking("left_house")
	state.finished = true
	state.flags.level_exit = true
	if state.cooking.get("activity","") == "finished": state.index = _step_index("complete")
	talking = false
	_enter_step()
	_save()

func _tick_cooking(delta: float) -> void:
	if state.day != 2 or state.cooking.is_empty(): return
	var event: Dictionary = state.cooking
	if event.activity != "finished": event.elapsed = minf(state.Cooking.DURATION,float(event.elapsed)+delta)
	if event.status in ["available","offered","accepted"]:
		if float(event.elapsed) >= state.Cooking.DURATION:
			_cancel_cooking("period_ended")
		elif event.status in ["offered","accepted"]:
			cooking_away = cooking_away+delta if player.position.distance_to(house.actors.lena.position) > 6.0 else 0.0
			if cooking_away >= 8.0: _cancel_cooking("walked_away")
	if step.get("wait","") in ["npc_take","npc_place"]: _tick_breakfast(delta)
	cooking_autosave += delta
	if cooking_autosave >= 5.0 and event.activity != "finished":
		cooking_autosave = 0.0
		_save()

func _tick_breakfast(delta: float) -> void:
	if step.get("wait","") == "npc_take" and state.items.bread != "kitchen_shelf":
		state.finish_without_loaf()
		state.index = _step_index("g_ready")
		_enter_step()
		_save()
		return
	if house.actors.lena.walking: return
	# The refusal branch takes the real loaf only after reaching its surface.
	if step.get("wait","") == "npc_take" and house.actors.lena.position.distance_to(house.position_of("bread")) > 2.0: return
	if step.get("wait","") == "npc_place" and house.actors.lena.position.distance_to(house.position_of("breakfast_table")) > 2.2: return
	elapsed += delta
	if elapsed >= (3.2 if step.id == "f_place" else 1.2): _advance()

func _visible_actor(id: String) -> bool:
	var actor = house.actors[id]
	if actor.moving != null and actor.moving.is_running(): return false
	var position_: Vector3 = actor.global_position+Vector3(0,1.4,0)
	if camera.global_position.distance_to(position_) > 8 or not camera.is_position_in_frustum(position_): return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,position_)
	query.exclude = [player.get_rid()]
	var hit := house.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == actor

func _take_checkpoint() -> void:
	checkpoint = state.snapshot()
	if shopping != null: checkpoint.shop = shopping.state.snapshot()
	checkpoint.last_request = last_request
	checkpoint.last_target = last_target
	checkpoint.player = [player.position.x,player.position.y,player.position.z]
	checkpoint.yaw = player.body.rotation.y
	checkpoint.pitch = player.head.rotation.x

func _save() -> bool:
	if initialized: _take_checkpoint()
	if checkpoint.is_empty(): return false
	var file := FileAccess.open(SAVE+".tmp",FileAccess.WRITE)
	if file == null:
		ui.notify("Не удалось сохранить прогресс.")
		return false
	file.store_string(JSON.stringify(checkpoint))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(SAVE+".tmp",SAVE) != OK:
		ui.notify("Ошибка записи. Предыдущее сохранение не заменено.")
		return false
	return true

func _read_save() -> Variant:
	var path := SAVE
	for candidate in [SAVE,PRIOR_PROLOGUE_SAVE,PREVIOUS_SAVE,LEGACY_SAVE]:
		if FileAccess.file_exists(candidate):
			path = candidate
			break
	var file := FileAccess.open(path,FileAccess.READ)
	return null if file == null else JSON.parse_string(file.get_as_text())

func _valid_pose(data: Dictionary) -> bool:
	if not data.get("player") is Array or data.player.size() != 3: return false
	for value in data.player:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	for key in ["yaw","pitch"]:
		if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])): return false
	if data.get("shop") is Dictionary and data.shop.get("location") == "shop":
		return absf(data.player[0]-40.0) < 4.8 and data.player[2] > -5.3 and data.player[2] < 5.3 and data.player[1] >= 0 and data.player[1] < 3
	return absf(data.player[0]) < 6.8 and data.player[2] > -11.8 and data.player[2] < 8.8 and data.player[1] >= -0.1 and data.player[1] < 3.0

func _save_valid() -> bool:
	var data: Variant = _read_save()
	var candidate = State.new()
	return data is Dictionary and candidate.restore(data,steps.size()) and _valid_shopping(data,candidate) and _valid_pose(data)

func _load_save() -> void:
	if communication != null: communication.reset()
	var data: Variant = _read_save()
	var candidate = State.new()
	if not data is Dictionary or not candidate.restore(data,steps.size()) or not _valid_shopping(data,candidate) or not _valid_pose(data):
		ui.notify("Сохранение отсутствует, повреждено или несовместимо. Оно не изменено.")
		return
	fixtures.close()
	life.reset()
	state = candidate
	talking = state.day == 2 and state.cooking.get("status","") in ["offered","accepted"]
	cooking_autosave = 0.0
	cooking_away = 0.0
	last_request = str(data.get("last_request",""))
	last_target = str(data.get("last_target",""))
	checkpoint = data.duplicate(true)
	player.position = Vector3(data.player[0],data.player[1],data.player[2])
	if not (data.get("shop") is Dictionary and data.shop.get("location") == "shop"):
		player.position = house.safe_player_position(player.position,player.get_rid())
	player.body.rotation.y = data.yaw
	player.head.rotation.x = data.pitch
	player.velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	gesture_time = 0
	initialized = true
	menu_active = false
	paused = false
	selecting = false
	choosing_subject = false
	exploration = false
	ui.menu.hide()
	ui.pause_panel.hide()
	ui.subject.hide()
	get_tree().paused = false
	ui.complete_panel.hide()
	shopping.restore(data.get("shop"))
	_enter_step(true)
	_take_checkpoint()
	_save()

func _valid_shopping(data: Dictionary, home_state) -> bool:
	if not data.has("shop"): return true
	var candidate = ShopState.new()
	if not candidate.restore(data.shop): return false
	if candidate.started and home_state.day != 2: return false
	return candidate.held() == "" or home_state.held("player") == ""

func _prepare_shop_entry() -> void:
	# Standalone LEVEL_02 preview starts at the day-two boundary without awarding vocabulary.
	state.day = 2
	state.period = "morning"
	state.finished = true
	state.index = _step_index("complete")
	state.items.bag = "bag_stand"
	state.items.room_key = "nightstand"
	state.items.bread = "breakfast_table"
	state.flags = {"door_open":true,"slept":true,"breakfast_done":true,"breakfast_result":"skipped"}
	state.ensure_cooking()
	state.Cooking.mark(state.cooking,"skipped")
	state.cooking.activity = "finished"
	_enter_step(true)

func _setting(id: String,value: float) -> void:
	settings_values[id] = value
	if id == "volume": AudioServer.set_bus_volume_db(0,linear_to_db(value) if value > 0 else -80)
	if id == "sensitivity": player.MOUSE_SENS = value
	if id == "text_scale": ui.text_scale(value)
	var config := ConfigFile.new()
	for key in settings_values: config.set_value("settings",key,settings_values[key])
	config.save(SETTINGS)

func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	for key in settings_values:
		var value: float = config.get_value("settings",key,settings_values[key])
		_setting(key,value)
		var slider := ui.settings.find_child(key,true,false) as Range
		if slider: slider.set_value_no_signal(value)

func _aim_at(target: String) -> void:
	var point: Vector3 = house.position_of(target)
	if house.anchors.has(target): point = house.anchors[target].global_position
	if house.actors.has(target):
		player.position = Vector3(0 if step.phase == "A" and step.id != "a_enter" else point.x,0.9,point.z+2.0)
	else: player.position = Vector3(point.x+0.8,0.9,point.z+1.5)
	if target == "bag_stand": player.position = Vector3(2.0,0.9,-3.1)
	player.velocity = Vector3.ZERO
	player.body.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.head.position.y = 0.0
	player.eyes.position = Vector3.ZERO
	player.try_crouch = false
	player.is_crouching = false
	player.standing_collision_shape.disabled = false
	player.crouching_collision_shape.disabled = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	camera.look_at(point)
	if _target() != target:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.2)
		query.exclude = [player.get_rid()]
		print("AIM_DIAGNOSTIC ",target," camera=",camera.global_position," point=",point," hit=",house.get_world_3d().direct_space_state.intersect_ray(query))

func _preview() -> void:
	_start_new()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://prologue_preview.png")
	get_tree().quit()
