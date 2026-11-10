extends Node3D

const State = preload("res://implementations/dormitory/experiments/character_preview/prototype_state.gd")
const GeneratedCatalog = preload("res://implementations/dormitory/game/characters/generated_animation_catalog.gd")
const PLAYER_SCENE = preload("res://addons/cogito/PackedScenes/cogito_player_simple.tscn")
const LENA_VISUAL = preload("res://implementations/dormitory/game/characters/lena_motifect.gd")
const SAVE_PATH := "user://language_life_prototype.json"
var state = State.new()
var player: CogitoPlayerSimple
var camera: Camera3D
var lena: Node3D
var head: Node3D
var cup: StaticBody3D
var apple: StaticBody3D
var anchor: StaticBody3D
var hand: Marker3D
var lena_visual: Node3D
var motion_panel: PanelContainer
var motion_choice: OptionButton
var motion_pack: OptionButton
var motion_loop: CheckButton
var held: Marker3D
var panel: PanelContainer
var line: Label
var choices: VBoxContainer
var prompt: Label
var status: Label
var goals: Label
var pause_panel: PanelContainer
var notice: Label
var dialog_open := false
var selecting := false
var paused := false
var current_target := ""
var selected_flash := 0.0
var animation_time := 0.0
var gesture := ""
var notice_seconds := 0.0
var last_utterance := "Möchtest du die Tasse?"
var reset_confirmation := false

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1280, 800)
	_build_room()
	_build_player()
	_build_ui()
	_sync_cup()
	InputRouter.push(_on_input)
	if FileAccess.file_exists(SAVE_PATH):
		_notify("Есть сохранение: F9 — продолжить. Новая игра — в меню Esc.")
	else:
		_notify("Подойдите к Лене и нажмите E.")
	if "--prototype-smoke" in OS.get_cmdline_user_args():
		_smoke.call_deferred()
	if "--prototype-preview" in OS.get_cmdline_user_args():
		_preview.call_deferred()

func _build_room() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("81969e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e0e9ef")
	env.ambient_light_energy = 0.75
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 0.65
	light.shadow_enabled = true
	add_child(light)
	_box(Vector3(0,-0.15,0), Vector3(10,0.3,12), Color("c4b39c"))
	_box(Vector3(-5,1.7,0), Vector3(0.3,3.4,12), Color("d7dfd6"))
	_box(Vector3(5,1.7,0), Vector3(0.3,3.4,12), Color("d7dfd6"))
	_box(Vector3(0,1.7,-6), Vector3(10,3.4,0.3), Color("a9bdb4"))
	_box(Vector3(0,1.7,6), Vector3(10,3.4,0.3), Color("d7dfd6"))
	# A table behind Lena makes the target-selection detour observable.
	_box(Vector3(0,0.95,-3.6), Vector3(2.5,0.16,1.1), Color("856552"))
	for x in [-1.0,1.0]:
		for z in [-3.95,-3.25]: _box(Vector3(x,0.45,z), Vector3(0.12,0.9,0.12), Color("665041"))
	_box(Vector3(2.1,0.75,-1.4), Vector3(1.1,0.12,1.1), Color("856552"))
	_box(Vector3(2.1,0.35,-1.4), Vector3(0.2,0.7,0.2), Color("665041"))
	anchor = _body("table", Vector3(2.1,0.84,-1.4), Vector3(1.0,0.05,1.0))
	var mat := _material(Color("bcdac0"))
	var tray := MeshInstance3D.new()
	var tray_mesh := BoxMesh.new()
	tray_mesh.size = Vector3(0.85,0.025,0.8)
	tray.mesh = tray_mesh
	tray.material_override = mat
	anchor.add_child(tray)
	lena = _body("lena", Vector3(0,0,-2.0), Vector3(0.65,1.75,0.5), Vector3(0,0.9,0))
	lena.rotation.y = PI
	head = Node3D.new()
	lena.add_child(head)
	lena_visual = LENA_VISUAL.new()
	lena.add_child(lena_visual)
	hand = Marker3D.new()
	hand.position = Vector3(0,-0.01,-0.03)
	lena_visual.hand_attachment.add_child(hand)
	lena_visual.visual.target_skeleton.skeleton_updated.connect(func():
		if lena_visual.current_motion != "drink_from_cup": hand.global_basis = Basis.IDENTITY)
	_label3d(lena, "LENA", Vector3(0,2.0,0))
	apple = _body("apple", Vector3(0,1.18,-3.6), Vector3(0.32,0.32,0.32))
	_visual(apple, SphereMesh.new(), Vector3.ZERO, Vector3(0.3,0.28,0.3), Color("be4d43"))
	_visual(apple, CylinderMesh.new(), Vector3(0,0.16,0), Vector3(0.035,0.06,0.035), Color("69462e"))
	cup = _body("cup", Vector3.ZERO, Vector3(0.28,0.32,0.28))
	cup.scale = Vector3.ONE * 0.6
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.13
	cup_mesh.bottom_radius = 0.10
	cup_mesh.height = 0.26
	_visual(cup, cup_mesh, Vector3.ZERO, Vector3.ONE, Color("f2dfb2"))
	var rim := CylinderMesh.new()
	rim.top_radius = 0.105
	rim.bottom_radius = 0.105
	rim.height = 0.012
	_visual(cup, rim, Vector3(0,0.134,0), Vector3.ONE, Color("6b4a32"))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.05
	handle.outer_radius = 0.09
	var ring := _visual(cup, handle, Vector3(0.16,0,0), Vector3.ONE, Color("f2dfb2"))
	ring.rotation_degrees.x = 90
	_label3d(self, "LANGUAGE LIFE / 01", Vector3(0,2.6,-5.7))

func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(0,0.08,2.4)
	add_child(player)
	camera = player.camera
	player.player_hud.hide()
	player.player_interaction_component.set_process(false)
	held = Marker3D.new()
	held.position = Vector3(0.36,-0.30,-0.72)
	camera.add_child(held)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func _visual(parent: Node3D, mesh: Mesh, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.scale = size
	node.material_override = _material(color)
	parent.add_child(node)
	return node

func _body(id: String, pos: Vector3, size: Vector3, offset := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.set_meta("target_id", id)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = offset
	body.add_child(collision)
	return body

func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := _body("", pos, size)
	var mesh := BoxMesh.new()
	mesh.size = size
	_visual(body, mesh, Vector3.ZERO, Vector3.ONE, color)

func _label3d(parent: Node3D, text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = 40
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("eaf3ef")
	parent.add_child(label)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := _label("LANGUAGE LIFE  /  ПРОТОТИП 01", 23)
	title.position = Vector2(28,20)
	var play_link := _label("F8 — играть в пролог общежития · дни 1–2",17)
	play_link.position = Vector2(700,20)
	root.add_child(play_link)
	root.add_child(title)
	goals = _label("", 17)
	goals.position = Vector2(28,58)
	root.add_child(goals)
	status = _label("", 16)
	status.position = Vector2(28,150)
	root.add_child(status)
	var cross := _label("·", 34)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(cross)
	prompt = _label("", 20)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-200,32)
	prompt.custom_minimum_size.x = 400
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)
	panel = _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -490
	panel.offset_right = -28
	panel.offset_top = -340
	panel.offset_bottom = -42
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label("LENA", 16))
	line = _label("", 25)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 400
	box.add_child(line)
	choices = VBoxContainer.new()
	box.add_child(choices)
	panel.hide()
	var help := _label("WASD — идти   •   мышь — взгляд   •   E — действие   •   F5 / F9 — сохранить / загрузить   •   Esc — пауза / отмена", 15)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(28,-28)
	root.add_child(help)
	notice = _label("", 17)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice.offset_top = 185
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice)
	pause_panel = _panel()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.position -= Vector2(200,180)
	pause_panel.custom_minimum_size = Vector2(400,320)
	root.add_child(pause_panel)
	var menu := VBoxContainer.new()
	pause_panel.add_child(menu)
	menu.add_child(_label("ПАУЗА", 27))
	_button(menu, "Продолжить", func(): _pause(false))
	_button(menu, "Сохранить", _save)
	_button(menu, "Загрузить", _load_save)
	_button(menu, "Новая игра (двойное подтверждение)", _reset)
	_button(menu, "Выход", func(): get_tree().quit())
	pause_panel.hide()
	motion_panel = _panel()
	motion_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	motion_panel.position += Vector2(-490,20)
	motion_panel.custom_minimum_size.x = 460
	root.add_child(motion_panel)
	var motion_box := VBoxContainer.new()
	motion_panel.add_child(motion_box)
	motion_box.add_child(_label("MOTIFECT + GENERATED / %d КЛИПОВ" % (lena_visual.visual.Catalog.SCENES.size() + GeneratedCatalog.SCENES.size()), 23))
	motion_pack = OptionButton.new()
	motion_pack.add_theme_font_override("font", ThemeDB.fallback_font)
	motion_pack.add_theme_font_size_override("font_size", 20)
	for pack_name in lena_visual.visual.Catalog.PACKS:
		motion_pack.add_item("%s — %d" % [pack_name, lena_visual.visual.Catalog.PACKS[pack_name].size()])
	for pack_name in GeneratedCatalog.PACKS:
		motion_pack.add_item("%s — %d" % [pack_name, GeneratedCatalog.PACKS[pack_name].size()])
	motion_pack.item_selected.connect(_select_motion_pack)
	motion_box.add_child(motion_pack)
	motion_choice = OptionButton.new()
	motion_choice.add_theme_font_override("font", ThemeDB.fallback_font)
	motion_choice.add_theme_font_size_override("font_size", 20)
	_select_motion_pack(0)
	motion_box.add_child(motion_choice)
	motion_loop = CheckButton.new()
	motion_loop.text = "Повторять клип"
	motion_box.add_child(motion_loop)
	_button(motion_box, "Проиграть", func(): lena_visual.play_motion(str(motion_choice.get_item_metadata(motion_choice.selected)), motion_loop.button_pressed))
	_button(motion_box, "Остановить / спокойный idle", func(): lena_visual.stop_motion())
	_button(motion_box, "Закрыть (F7)", func(): _motion_ui(false))
	motion_panel.hide()
	help.text += "   •   F7 — анимации"
	_update_status()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_color_override("font_color", Color("f0f5ef"))
	label.add_theme_color_override("font_shadow_color", Color("203333"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color("203333"))
	label.add_theme_constant_override("outline_size", 3)
	return label

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055,0.12,0.14,0.96)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	p.add_theme_stylebox_override("panel", style)
	return p

func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_font_override("font", ThemeDB.fallback_font)
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	parent.add_child(button)

func _process(delta: float) -> void:
	if paused: return
	lena_visual.talking = dialog_open
	current_target = _target()
	prompt.text = ""
	if selecting:
		prompt.text = "Выберите яблоко: обойдите Лену. E — подтвердить; Esc — отменить"
		if current_target == "apple": prompt.text = "E — указать на этот предмет"
	elif not dialog_open:
		match current_target:
			"lena": prompt.text = "E — поговорить с Леной"
			"cup":
				if state.cup_location == "table": prompt.text = "E — взять чашку"
			"table":
				if state.cup_location == "player": prompt.text = "E — поставить чашку"
	if notice_seconds > 0:
		notice_seconds -= delta
		if notice_seconds <= 0: notice.text = ""
	if selected_flash > 0:
		selected_flash -= delta
		apple.scale = Vector3.ONE * (1.0 + 0.12 * sin(selected_flash * 15))
	else: apple.scale = Vector3.ONE
	if animation_time > 0:
		animation_time = maxf(0, animation_time - delta)
		var angle := sin(animation_time * 18.0) * 0.12 * sin(animation_time * PI / 0.7)
		if gesture == "nod":
			head.rotation.x = angle
			camera.rotation.x = angle * 0.28
		else:
			head.rotation.y = angle
			camera.rotation.y = angle * 0.28
		if animation_time == 0:
			head.rotation = Vector3.ZERO
			camera.rotation = Vector3.ZERO

func _target() -> String:
	var start := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(start, start - camera.global_basis.z * 3.2)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return ""
	return str(hit.collider.get_meta("target_id", ""))

func _on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F8:
				InputRouter.remove(_on_input)
				get_tree().paused = false
				get_tree().change_scene_to_file("res://implementations/dormitory/game/prologue/prologue.tscn")
				return
			KEY_F7:
				if not paused: _motion_ui(not motion_panel.visible)
				return
			KEY_ESCAPE:
				if motion_panel.visible: _motion_ui(false)
				elif selecting:
					selecting = false
					_talk()
				else: _pause(not paused)
				return
			KEY_F5: _save(); return
			KEY_F9: _load_save(); return
			KEY_E:
				if paused or dialog_open or motion_panel.visible: return
				if selecting:
					if _target() == "apple":
						selecting = false
						_commit("identify")
						selected_flash = 0.8
						_talk("Das ist ein Apfel.")
					else: _notify("Наведитесь на видимое яблоко с расстояния не более 3,2 м.")
					return
				match _target():
					"lena": _talk()
					"cup":
						if _commit("take"): _notify("Чашка у вас. Подойдите к Лене или поставьте её на поднос.")
					"table": _commit("place")
				return
	if not paused and not dialog_open and not motion_panel.visible and (event is InputEventMouseMotion or event is InputEventJoypadMotion):
		player.on_input(event)

func _talk(utterance := "") -> void:
	if player.global_position.distance_to(lena.global_position) > 3.5:
		_notify("Подойдите ближе к Лене.")
		return
	dialog_open = true
	selecting = false
	player.is_movement_paused = true
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	if not utterance.is_empty(): last_utterance = utterance
	elif state.phase == "offer": last_utterance = "Möchtest du die Tasse?"
	elif state.cup_location == "player": last_utterance = "Gib mir bitte die Tasse."
	else: last_utterance = "Was möchtest du wissen?"
	line.text = last_utterance
	if state.phase == "offer":
		_button(choices, "Ja.", func(): _answer("accept"))
		_button(choices, "Nein.", func(): _answer("decline"))
	else:
		_button(choices, "Was ist das?  →  выбрать предмет", _select_target)
		if state.cup_location == "player":
			_button(choices, "Hier, bitte.  →  передать чашку", func(): _answer("give"))
		if state.cup_location == "lena":
			_button(choices, "Trink, bitte.  →  выпить из чашки", func(): lena_visual.play_motion("drink_from_cup"))
		_button(choices, "Noch einmal, bitte.", func(): _talk(last_utterance))
		_button(choices, "Bis gleich.  →  закончить разговор", _close_dialog)

func _answer(action: String) -> void:
	if player.global_position.distance_to(lena.global_position) > 3.5:
		_close_dialog()
		return
	if not _commit(action): return
	gesture = "shake" if action == "decline" else "nod"
	animation_time = 0.7
	lena_visual.play_motion("shake_head_no" if action == "decline" else "nod_yes")
	_talk({"accept": "Hier, bitte. Gib mir bitte die Tasse.", "decline": "Gut. Ich stelle die Tasse auf den Tisch.", "give": "Danke!"}[action])

func _select_target() -> void:
	_close_dialog()
	selecting = true
	_notify("Вопрос сохранён. Найдите яблоко за Леной; Esc возвращает к разговору.")

func _close_dialog() -> void:
	dialog_open = false
	panel.hide()
	player.is_movement_paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _commit(action: String) -> bool:
	# No animation callback applies gameplay effects. The logical transaction happens once.
	var id := action
	if action in ["take", "place"]: id += ":" + str(state.completed.size())
	if not state.commit(id, action): return false
	_sync_cup()
	_update_status()
	_save()
	return true

func _sync_cup() -> void:
	var destination: Node3D = self
	match state.cup_location:
		"player": destination = held
		"lena": destination = hand
	cup.reparent(destination, false)
	cup.position = Vector3(2.1,1.0,-1.4) if state.cup_location == "table" else Vector3.ZERO
	cup.collision_layer = 1 if state.cup_location == "table" else 0
	lena_visual.holding = state.cup_location == "lena"

func _update_status() -> void:
	goals.text = "%s Ответить Ja / Nein\n%s Выбрать яблоко в разговоре\n%s Передать чашку Лене" % ["●" if state.phase != "offer" else "○", "●" if state.identified else "○", "●" if state.phase == "returned" else "○"]
	status.text = "Чашка: %s  ·  знакомства с выражениями: %d" % [{"lena": "у Лены", "player": "у вас", "table": "на подносе"}[state.cup_location], state.units.size()]

func _pause(value: bool) -> void:
	paused = value
	reset_confirmation = false
	pause_panel.visible = value
	player.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	lena_visual.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value or dialog_open or motion_panel.visible else Input.MOUSE_MODE_CAPTURED

func _motion_ui(value: bool) -> void:
	motion_panel.visible = value
	panel.visible = dialog_open and not value
	player.is_movement_paused = value or dialog_open
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value or dialog_open else Input.MOUSE_MODE_CAPTURED

func _select_motion_pack(index: int) -> void:
	var catalog = lena_visual.visual.Catalog
	var pack_names: Array = catalog.PACKS.keys()
	var names: Array
	var is_generated := index >= pack_names.size()
	if is_generated:
		var generated_pack_names: Array = GeneratedCatalog.PACKS.keys()
		names = GeneratedCatalog.PACKS[generated_pack_names[index - pack_names.size()]]
	else:
		names = catalog.PACKS[pack_names[index]]
	motion_choice.clear()
	for name in names:
		var label: String = str(GeneratedCatalog.LABELS.get(name, name)).trim_prefix("emote_") if is_generated else str(name).trim_prefix("emote_")
		motion_choice.add_item(label)
		motion_choice.set_item_metadata(motion_choice.item_count - 1, name)
	motion_choice.select(0)

func _save() -> void:
	var data: Dictionary = state.snapshot()
	data["player"] = [player.position.x, player.position.y, player.position.z]
	data["yaw"] = player.body.rotation.y
	# Retain the previous valid save if writing fails.
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		_notify("Не удалось записать сохранение.")
		return
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH) != OK:
		_notify("Ошибка сохранения; предыдущий файл сохранён.")
		return
	_notify("Сохранено на завершённом шаге.")

func _load_save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_notify("Сохранение пока отсутствует.")
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	var candidate = State.new()
	if not candidate.restore(data) or not _valid_pose(data):
		_notify("Сохранение повреждено или несовместимо. Текущая игра сохранена в памяти.")
		return
	_pause(false)
	_motion_ui(false)
	lena_visual.stop_motion()
	_close_dialog()
	selecting = false
	state = candidate
	player.position = Vector3(data.player[0],data.player[1],data.player[2])
	player.body.rotation.y = data.yaw
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	animation_time = 0
	head.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	_sync_cup()
	_update_status()
	_notify("Загружено. E рядом с Леной — продолжить разговор.")

func _valid_pose(data: Dictionary) -> bool:
	if not data.get("player") is Array or data.player.size() != 3: return false
	for value in data.player:
		if not (value is float or value is int) or not is_finite(float(value)): return false
	if not (data.get("yaw") is float or data.get("yaw") is int): return false
	return is_finite(float(data.yaw)) and absf(data.player[0]) < 4.7 and absf(data.player[2]) < 5.7 and data.player[1] >= -0.1 and data.player[1] < 3.0

func _reset() -> void:
	if not reset_confirmation:
		reset_confirmation = true
		_notify("Нажмите «Новая игра» ещё раз: текущий прогресс будет заменён.")
		return
	_pause(false)
	_motion_ui(false)
	lena_visual.stop_motion()
	_close_dialog()
	selecting = false
	state = State.new()
	player.position = Vector3(0,0.08,2.4)
	player.rotation = Vector3.ZERO
	player.body.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	animation_time = 0
	_sync_cup()
	_update_status()
	_save()

func _notify(message: String) -> void:
	notice.text = message
	notice_seconds = 6.0

func _smoke() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_motion_ui(true)
	_select_motion_pack(1)
	assert(motion_choice.item_count == 30)
	assert(str(motion_choice.get_item_metadata(0)).begins_with("emote_"))
	lena_visual.play_motion(str(motion_choice.get_item_metadata(0)))
	assert(lena_visual.current_motion.begins_with("emote_"))
	lena_visual.stop_motion()
	_select_motion_pack(0)
	assert(motion_choice.item_count == 40)
	_motion_ui(false)
	assert(is_instance_valid(player.camera))
	assert(cup.get_parent() == hand)
	assert(state.commit("test-accept", "accept"))
	_sync_cup()
	assert(cup.get_parent() == held)
	assert(state.commit("test-give", "give"))
	_sync_cup()
	assert(cup.get_parent() == hand)
	# Aim at the apple through Lena: the solid NPC must occlude the target.
	player.position = Vector3(0,0.05,0)
	await get_tree().physics_frame
	camera.look_at(apple.global_position)
	await get_tree().physics_frame
	assert(_target() != "apple")
	# Move to the side and approach the table: the same target becomes visible.
	player.position = Vector3(2,0.05,-2.7)
	await get_tree().physics_frame
	camera.look_at(apple.global_position)
	await get_tree().physics_frame
	assert(_target() == "apple")
	# Cancellation leaves the question uncommitted and returns to the same conversation.
	_talk()
	_select_target()
	assert(selecting and not state.identified)
	selecting = false
	_talk()
	assert(dialog_open and not state.identified)
	_pause(true)
	assert(paused and player.process_mode == Node.PROCESS_MODE_DISABLED)
	_pause(false)
	assert(dialog_open)
	_close_dialog()
	assert(_commit("identify"))
	# Exercise real file replacement, deserialization and one-owner restoration.
	_save()
	assert(FileAccess.file_exists(SAVE_PATH))
	state = State.new()
	_load_save()
	assert(state.identified and state.cup_location == "lena")
	assert(cup.get_parent() == hand)
	var generated_pack_index: int = lena_visual.visual.Catalog.PACKS.size()
	for pack_offset in GeneratedCatalog.PACKS.size():
		var pack_name: String = GeneratedCatalog.PACKS.keys()[pack_offset]
		_select_motion_pack(generated_pack_index + pack_offset)
		assert(motion_choice.item_count == GeneratedCatalog.PACKS[pack_name].size())
		for identifier: String in GeneratedCatalog.PACKS[pack_name]:
			lena_visual.play_motion(identifier)
			var animation: Animation = lena_visual.visual.library.get_animation(identifier)
			assert(animation.length > 0 and animation.get_track_count() > 0)
			lena_visual.visual.animation_player.seek(animation.length * 0.5, true)
			lena_visual.visual.animation_player.advance(0.0)
			await get_tree().process_frame
			await get_tree().process_frame
			for bone_index in lena_visual.visual.target_skeleton.get_bone_count():
				assert(lena_visual.visual.target_skeleton.get_bone_global_pose(bone_index).is_finite())
			print("GENERATED_CLIP_OK ", identifier)
		lena_visual.stop_motion()
	print("LANGUAGE_LIFE_SMOKE_OK")
	get_tree().quit()

func _preview() -> void:
	await get_tree().create_timer(2.0).timeout
	player.position = Vector3(1.4,0.05,0.0)
	await get_tree().physics_frame
	camera.look_at(lena.global_position + Vector3(0,1.3,0))
	_talk()
	if "--emotes-preview" in OS.get_cmdline_user_args():
		_motion_ui(true)
		motion_pack.select(1)
		_select_motion_pack(1)
		lena_visual.play_motion("emote_thumbs_up")
		await get_tree().create_timer(2.0).timeout
	if "--motifect-preview" in OS.get_cmdline_user_args():
		lena_visual.play_motion("drink_from_cup")
		await get_tree().create_timer(2.5).timeout
		var skeleton: Skeleton3D = lena_visual.visual.target_skeleton
		for semantic in [SemanticBoneResolver.LEFT_HAND, SemanticBoneResolver.RIGHT_HAND, SemanticBoneResolver.HEAD]:
			print("MOTION_POSE ", semantic, " ", (skeleton.global_transform * skeleton.get_bone_global_pose(SemanticBoneResolver.find(skeleton, semantic))).origin)
		print("CUP_POSE ", cup.global_position, " BONE ", lena_visual.hand_attachment.bone_name)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://prototype_preview.png")
	get_tree().quit()
