extends Node3D
const Composer = preload("res://implementations/communication_lab/game/communication/word_composer.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const AnnaVisual = preload("res://implementations/communication_lab/game/characters/lab_anna_visual.gd")
const PLAYER_SCENE = preload("res://addons/cogito/PackedScenes/cogito_player_simple.tscn")

var context := Session.initial_context()
var player: CogitoPlayerSimple
var composer: VBoxContainer
var dialog: PanelContainer
var diagnostic: RichTextLabel
var reply_label: Label
var effects_label: Label
var raw_label: Label
var dev_panel: VBoxContainer
var show_diagnostics := true
var last_record: Dictionary = {}
var key_visual: MeshInstance3D
var door_visual: MeshInstance3D
var pending_option: OptionButton
var owner_option: OptionButton
var busy_toggle: CheckBox
var knowledge_toggle: CheckBox

func _ready() -> void:
	_build_room()
	_build_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_room() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d6dfed")
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = Vector3(12, 0.2, 12)
	floor_mesh.mesh = box; floor_mesh.position.y = -0.12
	var floor_material := StandardMaterial3D.new(); floor_material.albedo_color = Color("a8b6bc"); floor_mesh.material_override = floor_material
	floor.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new(); var floor_box := BoxShape3D.new(); floor_box.size = box.size; floor_shape.shape = floor_box; floor_shape.position.y = -0.12; floor.add_child(floor_shape)
	add_child(floor)
	_add_wall(Vector3(0, 1.5, -6), Vector3(12, 3, .2))
	_add_wall(Vector3(-6, 1.5, 0), Vector3(.2, 3, 12))
	_add_wall(Vector3(6, 1.5, 0), Vector3(.2, 3, 12))
	_add_wall(Vector3(0, 3.1, 0), Vector3(12, .2, 12))
	var light := OmniLight3D.new(); light.position = Vector3(0, 2.7, -1); light.light_energy = 2.0; light.omni_range = 12; add_child(light)
	player = PLAYER_SCENE.instantiate() as CogitoPlayerSimple
	player.name = "CogitoPlayer"
	player.position = Vector3(0, 0, 2.5)
	add_child(player)
	var anna := AnnaVisual.new()
	anna.name = "Anna"
	anna.position = Vector3(0, 0, -2)
	anna.rotation.y = PI
	anna.scale = Vector3.ONE * 0.9
	add_child(anna)
	var table := MeshInstance3D.new(); table.name = "Table"
	var table_mesh := BoxMesh.new(); table_mesh.size = Vector3(1.5, .12, .8); table.mesh = table_mesh; table.position = Vector3(1, .75, -1.6)
	var table_mat := StandardMaterial3D.new(); table_mat.albedo_color = Color("795944"); table.material_override = table_mat; add_child(table)
	key_visual = MeshInstance3D.new(); key_visual.name = "Key"
	var key_mesh := SphereMesh.new(); key_mesh.radius = .12; key_mesh.height = .24; key_visual.mesh = key_mesh; key_visual.position = Vector3(1, .95, -1.6)
	var key_mat := StandardMaterial3D.new(); key_mat.albedo_color = Color("dfb967"); key_visual.material_override = key_mat; add_child(key_visual)
	door_visual = MeshInstance3D.new(); door_visual.name = "Door"
	var door_mesh := BoxMesh.new(); door_mesh.size = Vector3(1.2, 2.2, .12); door_visual.mesh = door_mesh; door_visual.position = Vector3(-2, 1.1, -5.85)
	var door_mat := StandardMaterial3D.new(); door_mat.albedo_color = Color("6b493b"); door_visual.material_override = door_mat; add_child(door_visual)
	_add_wall(Vector3(0, 1.5, 6), Vector3(12, 3, .2))
	_refresh_objects()

func _add_wall(at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	var mesh := MeshInstance3D.new(); var shape_mesh := BoxMesh.new(); shape_mesh.size = size; mesh.mesh = shape_mesh; mesh.position = at
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("d9d8cf"); mesh.material_override = mat; wall.add_child(mesh)
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = size; collider.shape = shape; collider.position = at; wall.add_child(collider); add_child(wall)

func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.name = "LabUI"; add_child(layer)
	var hint := Label.new(); hint.text = "WASD + мышь · E рядом с Анной — разговор · F2 — диагностика"; hint.position = Vector2(18, 12); layer.add_child(hint)
	dialog = PanelContainer.new(); dialog.position = Vector2(18, 50); dialog.size = Vector2(620, 480); dialog.hide(); layer.add_child(dialog)
	var column := VBoxContainer.new(); dialog.add_child(column)
	var title := Label.new(); title.text = "Language Communication Lab — Anna"; column.add_child(title)
	composer = Composer.new(); column.add_child(composer); composer.submitted.connect(_on_submitted); composer.cancelled.connect(_close_dialog)
	reply_label = Label.new(); reply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; reply_label.text = "Анна ждёт реплику."; column.add_child(reply_label)
	effects_label = Label.new(); effects_label.text = "Эффекты: —"; column.add_child(effects_label)
	var buttons := HFlowContainer.new(); column.add_child(buttons)
	var dev_toggle := CheckBox.new(); dev_toggle.text = "Показать диагностику (F2)"; dev_toggle.button_pressed = true; dev_toggle.toggled.connect(_toggle_dev); buttons.add_child(dev_toggle)
	var reset_button := Button.new(); reset_button.text = "Сбросить контекст"; reset_button.pressed.connect(_reset); buttons.add_child(reset_button)
	dev_panel = VBoxContainer.new(); column.add_child(dev_panel)
	var settings := HFlowContainer.new(); dev_panel.add_child(settings)
	busy_toggle = CheckBox.new(); busy_toggle.text = "Анна занята"; busy_toggle.toggled.connect(func(v): context.busy = v); settings.add_child(busy_toggle)
	knowledge_toggle = CheckBox.new(); knowledge_toggle.text = "Знает, где ключ"; knowledge_toggle.button_pressed = true; knowledge_toggle.toggled.connect(func(v): context.knows_key = v); settings.add_child(knowledge_toggle)
	owner_option = OptionButton.new(); owner_option.add_item("Ключ у Анны", 0); owner_option.add_item("Ключ в мире", 1); owner_option.add_item("Ключ у игрока", 2); owner_option.item_selected.connect(_set_owner); settings.add_child(owner_option)
	pending_option = OptionButton.new(); pending_option.add_item("Нет предложения", 0); pending_option.add_item("Ожидает Ja/Nein", 1); pending_option.add_item("Ожидает уточнение", 2); pending_option.item_selected.connect(_set_pending); settings.add_child(pending_option)
	raw_label = Label.new(); raw_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; dev_panel.add_child(raw_label)
	diagnostic = RichTextLabel.new(); diagnostic.fit_content = true; diagnostic.scroll_active = true; diagnostic.custom_minimum_size.y = 180; dev_panel.add_child(diagnostic)
	_update_diagnostics({})

func _input(event: InputEvent) -> void:
	if dialog.visible and composer.route_key(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			show_diagnostics = not show_diagnostics; dev_panel.visible = show_diagnostics
		elif event.keycode == KEY_E and not dialog.visible and player.global_position.distance_to(Vector3(0, 0, -2)) < 3.0:
			_open_dialog()
		elif event.keycode == KEY_ESCAPE and dialog.visible:
			_close_dialog()

func _open_dialog() -> void:
	dialog.show(); player.is_movement_paused = true; player.is_showing_ui = true; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	composer.phrase.grab_focus()

func _close_dialog() -> void:
	dialog.hide(); player.is_movement_paused = false; player.is_showing_ui = false; Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_submitted(text: String) -> void:
	last_record = Session.submit(text, context)
	reply_label.text = "Анна: %s" % last_record.answer
	effects_label.text = "Эффекты: %s" % (", ".join(last_record.effects) if not last_record.effects.is_empty() else "—")
	_update_diagnostics(last_record)
	_refresh_objects()

func _update_diagnostics(record: Dictionary) -> void:
	if not is_instance_valid(diagnostic): return
	if record.is_empty():
		raw_label.text = "Ввод: —"
		diagnostic.text = "Контекст: %s\nГоворите свободно; автоматические подсказки доступны в поле слов." % JSON.stringify(context)
		return
	var parsed: Dictionary = record.parse
	var frame: Dictionary = parsed.frame
	raw_label.text = "Ввод: %s" % record.input
	diagnostic.text = "Токены: %s\nСтатус: %s · намерение: %s\nFrame: subject=%s, addressee=%s, action=%s, object=%s, polarity=%s, speech_act=%s, target=%s\nНеоднозначность: %s\nНеподдерживаемое: %s\nДиагностика: %s\nОтвет: %s\nФактические эффекты: %s\nКонтекст после: %s" % [JSON.stringify(parsed.normalized_tokens), parsed.status, parsed.intent, frame.get("subject"), frame.get("addressee"), frame.get("action"), frame.get("object_id"), frame.get("polarity"), frame.get("speech_act"), frame.get("target_id"), JSON.stringify(parsed.ambiguity), JSON.stringify(parsed.unsupported_features), JSON.stringify(parsed.diagnostics), record.answer, JSON.stringify(record.effects), JSON.stringify(record.after)]

func _toggle_dev(value: bool) -> void:
	show_diagnostics = value; dev_panel.visible = value

func _set_owner(index: int) -> void:
	context.key_owner = ["anna", "world", "player"][index]; _refresh_objects()

func _set_pending(index: int) -> void:
	context.pending = ["", "offer", "help_target"][index]

func _refresh_objects() -> void:
	if not is_instance_valid(key_visual): return
	key_visual.visible = context.key_owner == "world" or context.key_owner == "anna"
	if is_instance_valid(door_visual): door_visual.rotation.y = PI / 2 if context.door_open else 0.0

func _reset() -> void:
	Session.reset(context); busy_toggle.button_pressed = false; knowledge_toggle.button_pressed = true
	owner_option.select(0); pending_option.select(0); reply_label.text = "Анна ждёт реплику."; effects_label.text = "Эффекты: —"; raw_label.text = "Ввод: —"
	_update_diagnostics({}); _refresh_objects()
