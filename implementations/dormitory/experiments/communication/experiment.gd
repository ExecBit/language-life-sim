extends Node3D
const Composer = preload("res://game/communication/word_composer.gd")
var composer: VBoxContainer
const Parser = preload("res://experiments/communication/parser.gd")
const Context = preload("res://experiments/communication/context.gd")
const House = preload("res://game/prologue/house.gd")
const Actor = preload("res://game/prologue/actor.gd")
const PLAYER = preload("res://addons/cogito/PackedScenes/cogito_player_simple.tscn")
var state = Context.new()
var room: Node3D
var anna: Node3D
var player: CogitoPlayerSimple
var key: Node3D
var key_table: Node3D
var hand: Marker3D
var door: Node3D
var collision: CollisionShape3D
var panel: PanelContainer
var phrase: LineEdit
var prefix: LineEdit
var matches: ItemList
var response: Label
var status: Label
var pointing := false
var action_running := false
var logs: Array = []
var paused := false
var pause_panel: PanelContainer
var reset_button: Button
var editor_was_visible := false
var saved_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().content_scale_size = Vector2i(1280,800)
	room = Node3D.new()
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(room)
	build_room()
	player = PLAYER.instantiate()
	player.position = Vector3(0,0.9,3.2)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.player_hud.hide()
	player.player_interaction_component.set_process(false)
	hand = Marker3D.new()
	hand.position = Vector3(0.3,-0.3,-0.7)
	player.camera.add_child(hand)
	build_ui()
	InputRouter.push(input_event)
	reset(0)

func _exit_tree() -> void:
	get_tree().paused = false
	InputRouter.remove(input_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func box(pos: Vector3, size: Vector3, color: Color, id := "") -> StaticBody3D:
	var helper = House.new()
	var body: StaticBody3D = helper.body(id,pos,size,room)
	helper.visual(body,BoxMesh.new(),Vector3.ZERO,size,color)
	helper.free()
	return body

func build_room() -> void:
	box(Vector3(0,-0.15,-1),Vector3(10,0.3,13),Color("a99072"))
	for x in [-5.0,5.0]: box(Vector3(x,1.5,-1),Vector3(0.15,3,13),Color("c6d1c7"))
	for z in [-7.5,5.5]: box(Vector3(0,1.5,z),Vector3(10,3,0.15),Color("c6d1c7"))
	for x in [-3.05,3.05]: box(Vector3(x,1.5,-1),Vector3(3.9,3,0.15),Color("c6d1c7"))
	box(Vector3(0,2.75,-1),Vector3(2.2,0.5,0.15),Color("c6d1c7"))
	door = box(Vector3(0,1.2,-1),Vector3(2.15,2.4,0.15),Color("6b8078"),"door")
	collision = door.get_child(0)
	box(Vector3(-3,0.4,1),Vector3(1.4,0.8,0.8),Color("927654"))
	key_table = Marker3D.new()
	key_table.position = Vector3(-3,0.85,1)
	add_child(key_table)
	var helper = House.new()
	key = helper.make_item("room_key")
	key.reparent(self,false)
	key.set_meta("target_id","key")
	helper.free()
	anna = Actor.new()
	anna.actor_id = "anna"
	anna.position = Vector3(2.5,0,0.4)
	anna.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(anna)
	var label := Label3D.new()
	label.text = "ANNA"
	label.position.y = 1.85
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anna.add_child(label)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	add_child(light)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("aabfc6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	env.environment = settings
	add_child(env)

func button(parent: Node, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 34
	b.pressed.connect(callback)
	parent.add_child(b)

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 18
	root.theme = theme
	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(crosshair)
	status = Label.new()
	status.position = Vector2(18,18)
	root.add_child(status)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -410
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05,0.1,0.12,0.96)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",style)
	root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	response = Label.new()
	response.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	response.add_theme_font_size_override("font_size",24)
	column.add_child(response)
	composer = Composer.new()
	column.add_child(composer)
	phrase = composer.phrase
	prefix = composer.prefix
	matches = composer.matches
	composer.submitted.connect(func(_text): submit())
	composer.point_requested.connect(begin_point)
	composer.help_requested.connect(hint)
	composer.cancelled.connect(close)
	var debug := HBoxContainer.new()
	column.add_child(debug)
	for i in 4:
		button(debug,["Сброс: ключ у Анны","Ключ на столе","Анна занята","Анна не знает"][i],reset.bind(i))
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.position -= Vector2(180,120)
	pause_panel.custom_minimum_size = Vector2(360,240)
	pause_panel.add_theme_stylebox_override("panel",style.duplicate())
	root.add_child(pause_panel)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation",12)
	pause_panel.add_child(menu)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	button(menu,"Продолжить",set_pause.bind(false))
	button(menu,"Начать заново",func(): set_pause(false); reset(0))
	reset_button = menu.get_child(menu.get_child_count()-1)
	button(menu,"Закончить разговор",func(): set_pause(false); close())
	button(menu,"Выход",func(): write_log(); get_tree().quit())
	pause_panel.hide()
	update_matches("")

func set_pause(value: bool) -> void:
	if value == paused: return
	paused = value
	if value:
		editor_was_visible = panel.visible
		saved_focus = get_viewport().gui_get_focus_owner()
		panel.hide()
		reset_button.disabled = action_running
		write_log()
	else:
		panel.visible = editor_was_visible
	pause_panel.visible = value
	get_tree().paused = value
	controls(value or panel.visible)
	if not value and panel.visible:
		if is_instance_valid(saved_focus): saved_focus.grab_focus()
		else: prefix.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_pause(not paused)
		get_viewport().set_input_as_handled()

func update_matches(value: String) -> void:
	composer.update_matches(value)

func prefix_enter() -> void:
	composer.prefix_enter()

func choose_word() -> void:
	composer.choose_word()

func controls(editing: bool) -> void:
	player.is_movement_paused = editing
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if editing else Input.MOUSE_MODE_CAPTURED

func close() -> void:
	panel.hide()
	pointing = false
	state.active = false
	state.pending = ""
	controls(false)

func begin_point() -> void:
	pointing = true
	panel.hide()
	controls(false)

func hint() -> void:
	state.hints += 1
	response.text = "Schlüssel · Tür"
	anna.face(key.global_position)
	anna.gesture("emote_point_at_opponent")
	logs.append({"event":"hint","attempt":state.attempts.size()})
	write_log()

func ray_target() -> String:
	var start := player.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(start,start-player.camera.global_basis.z*3.2)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return "" if hit.is_empty() else str(hit.collider.get_meta("target_id",""))

func interact() -> void:
	var target := ray_target()
	if pointing:
		if target not in ["key","door"]: return
		state.target_id = target
		pointing = false
		panel.show()
		controls(true)
		prefix.grab_focus()
	elif target == "anna":
		state.active = true
		panel.show()
		controls(true)
		prefix.grab_focus()
	elif target == "key" and state.key_location == "world":
		state.key_location = "player"
		sync_world()
	elif target == "door":
		if state.open_door("player"): sync_world()
		else: status.text = "Tür zu. E — Анна · T — ввод · F5 — сброс"

func submit() -> void:
	if action_running or not state.active: return
	if player.position.distance_to(anna.position) > 4.5:
		response.text = "Anna ist zu weit weg."
		return
	var parsed := Parser.parse(phrase.text,state.target_id,state.parser_context())
	var result := state.respond(parsed)
	response.text = result.text
	phrase.clear()
	if result.action == "open":
		action_running = true
		close()
		anna.go(Vector3(1.5,0,0.0))
		await anna.arrived
		state.open_door("anna")
		action_running = false
	if result.point == "key": anna.face(key.global_position); anna.gesture("emote_point_at_opponent")
	sync_world()
	write_log()

func write_log() -> void:
	var file := FileAccess.open("user://communication_experiment.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"attempts":logs+state.attempts,"hints":state.hints,"successes":state.successes}))

func sync_world() -> void:
	var parent: Node3D = anna.hand if state.key_location == "anna" else (hand if state.key_location == "player" else key_table)
	if key.get_parent() != parent: key.reparent(parent,false)
	key.position = Vector3.ZERO
	key.collision_layer = 1 if state.key_location == "world" else 0
	collision.set_deferred("disabled",state.opened)
	door.visible = not state.opened
	status.text = "WASD / мышь · E — действие · T — разговор · F5 — сброс · Esc — меню"+("   ✓ Zimmer offen" if state.opened else "")

func reset(preset: int) -> void:
	if action_running: return
	if state != null: logs.append({"event":"reset","attempts":state.attempts.duplicate(true),"successes":state.successes,"hints":state.hints})
	state = Context.new()
	state.key_location = "world" if preset in [1,3] else "anna"
	state.available = preset != 2
	state.knows = preset != 3
	anna.go(Vector3(2.5,0,0.4),true)
	player.position = Vector3(0,0.9,3.2)
	anna.face(player.position)
	phrase.clear()
	response.text = "Hallo!"
	close()
	sync_world()
	write_log()

func input_event(event: InputEvent) -> void:
	if composer.consume_opener(event): return
	if paused: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5: reset(0); return
		if panel.visible:
			composer.route_key(event)
			return
		if event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			interact()
			if panel.visible: composer.suppress_opener(event)
		if event.keycode == KEY_T:
			if player.position.distance_to(anna.position) <= 4.5:
				get_viewport().set_input_as_handled()
				state.active = true
				panel.show()
				controls(true)
				prefix.grab_focus()
				composer.suppress_opener(event)
	if event is InputEventMouseMotion and not panel.visible: player.on_input(event)
