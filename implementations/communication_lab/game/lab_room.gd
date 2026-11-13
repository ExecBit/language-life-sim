extends Node3D
const Composer = preload("res://implementations/communication_lab/game/communication/word_composer.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const LfmClient = preload("res://implementations/communication_lab/game/communication/lfm_client.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
const DialogueLanguage = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
const DialogueGraphView = preload("res://implementations/communication_lab/game/ui/dialogue_graph_view.gd")
const AsteraVisual = preload("res://implementations/communication_lab/game/characters/lab_npc_visual.gd")
const PLAYER_SCENE = preload("res://addons/cogito/PackedScenes/cogito_player_simple.tscn")
const CONVERSATION_FOCUS_HEIGHT := 1.02
const CONVERSATION_CAMERA_HEIGHT := 1.38
const CONVERSATION_DISTANCE := 1.35
const CONVERSATION_FOV := 36.0
@export_file("*.vrm") var npc_avatar_path := AsteraVisual.SAMPLE_B_AVATAR_PATH

var context := Session.initial_context()
var player: CogitoPlayerSimple
var astera_visual
var composer: VBoxContainer
var dialog: PanelContainer
var diagnostic: RichTextLabel
var transcript: RichTextLabel
var conversation_lines: Array[Dictionary] = []
var reveal_tween: Tween
var dev_panel: PanelContainer
var show_diagnostics := false
var last_record: Dictionary = {}
var attempts: Array[Dictionary] = []
var history_list: ItemList
var graph_view: Control
var graph_history_view: RichTextLabel
var dev_tabs: TabContainer
var dev_section_label: Label
var selected_attempt_index := -1
var parse_view: RichTextLabel
var context_view: RichTextLabel
var inspection_label: Label
var vocabulary_card: PanelContainer
var vocabulary_search: LineEdit
var vocabulary_rows: Array[Dictionary] = []
var topic_menu: VBoxContainer
var topic_buttons: Dictionary = {}
var notice_label: Label
var notice_card: PanelContainer
var notice_timer: Timer
var reply_editor: VBoxContainer
var selected_reply_label: Label
var editing_action := ""
var greeted := false
var motion_paths: Dictionary = {}
var conversation_camera: Camera3D
var exploration_camera: Camera3D
var camera_tween: Tween
var heading_card: PanelContainer
var history_expand_button: Button
var history_expanded := false
var language_client: Node
var language_busy := false
var language_epoch := 0
func _process(delta: float) -> void:
	# Silence and failed attempts do not alter the authored RPG conversation.
	pass

func _ready() -> void:
	language_client = LfmClient.new()
	add_child(language_client)
	_load_motion_manifest()
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
	player.player_hud.hide()
	astera_visual = AsteraVisual.new()
	astera_visual.avatar_path = npc_avatar_path
	astera_visual.name = "Astera"
	astera_visual.position = Vector3(0, 0, -2)
	astera_visual.rotation.y = PI
	astera_visual.scale = Vector3.ONE * 0.9
	add_child(astera_visual)
	conversation_camera = Camera3D.new(); conversation_camera.name = "ConversationCamera"; add_child(conversation_camera)
	_add_wall(Vector3(0, 1.5, 6), Vector3(12, 3, .2))

func _add_wall(at: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	var mesh := MeshInstance3D.new(); var shape_mesh := BoxMesh.new(); shape_mesh.size = size; mesh.mesh = shape_mesh; mesh.position = at
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("d9d8cf"); mesh.material_override = mat; wall.add_child(mesh)
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = size; collider.shape = shape; collider.position = at; wall.add_child(collider); add_child(wall)

func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18; style.content_margin_right = 18
	style.content_margin_top = 14; style.content_margin_bottom = 14
	return style

func _label(parent: Node, text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _inspector(tabs: TabContainer, title: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = title
	text.selection_enabled = true
	text.add_theme_constant_override("line_separation", 3)
	text.add_theme_font_size_override("normal_font_size", 16)
	var mono := SystemFont.new(); mono.font_names = PackedStringArray(["Consolas", "monospace"])
	text.add_theme_font_override("normal_font", mono)
	tabs.add_child(text)
	return text

func _build_ui() -> void:
	var layer := CanvasLayer.new(); layer.name = "LabUI"; add_child(layer)
	var canvas := Control.new(); layer.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new(); theme.default_font_size = 18
	for kind in ["PanelContainer", "TabContainer"]:
		theme.set_stylebox("panel", kind, _style(Color("111b26"), Color("344553")))
	for kind in ["Button", "OptionButton", "LineEdit", "ItemList"]:
		theme.set_stylebox("normal", kind, _style(Color("1d2c3a"), Color("3b5060")))
		theme.set_stylebox("focus", kind, _style(Color(0,0,0,0), Color("68d7c5")))
		theme.set_stylebox("hover", kind, _style(Color("2b4354"), Color("68d7c5")))
	canvas.theme = theme
	heading_card = PanelContainer.new(); canvas.add_child(heading_card)
	heading_card.position = Vector2(18, 18); heading_card.size.x = 640
	var heading := VBoxContainer.new(); heading_card.add_child(heading)
	_label(heading, "COMMUNICATION / LAB", 16).modulate = Color("85c9c4")
	_label(heading, "WASD · движение   /   E · проход   /   F2 · лаборатория", 16)
	dialog = PanelContainer.new(); dialog.name = "CommunicationPanel"; canvas.add_child(dialog)
	dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialog.anchor_top = 1.0; dialog.anchor_bottom = 1.0
	dialog.anchor_right = 1.0
	dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dialog.offset_left = 0; dialog.offset_top = -460; dialog.offset_right = 0; dialog.offset_bottom = 0
	dialog.hide()
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10); dialog.add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	var title := _label(header, "Астера", 24); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_expand_button = _button(header, "История на весь экран", _toggle_history_expanded)
	_button(header, "Памятка · F1", _toggle_vocabulary)
	_button(header, "Лаборатория · F2", func(): _toggle_dev(not show_diagnostics))
	_button(header, "Закрыть · Esc", _close_dialog)
	transcript = RichTextLabel.new(); transcript.name = "ConversationTranscript"
	transcript.custom_minimum_size.y = 110
	transcript.selection_enabled = true; transcript.scroll_following = true
	transcript.add_theme_font_size_override("normal_font_size", 20)
	transcript.add_theme_constant_override("line_separation", 5)
	transcript.tooltip_text = "Нажмите на разговор, чтобы показать ответ целиком. Колесо мыши — предыдущие реплики."
	transcript.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _finish_reply_reveal())
	column.add_child(transcript)
	_build_topic_menu(column)
	reply_editor = VBoxContainer.new()
	reply_editor.name = "ReplyEditor"
	reply_editor.add_theme_constant_override("separation", 12)
	column.add_child(reply_editor)
	var reply_header := HBoxContainer.new()
	reply_editor.add_child(reply_header)
	selected_reply_label = _label(reply_header, "", 20)
	selected_reply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(reply_header, "К выбору реплики", _back_to_choices)
	composer = Composer.new(); reply_editor.add_child(composer)
	composer.submitted.connect(_on_submitted); composer.cancelled.connect(_back_to_choices)
	composer.help_requested.connect(_toggle_vocabulary)
	vocabulary_card = PanelContainer.new(); canvas.add_child(vocabulary_card)
	vocabulary_card.anchor_left = 0.5; vocabulary_card.anchor_top = 0.5
	vocabulary_card.anchor_right = 0.5; vocabulary_card.anchor_bottom = 0.5
	vocabulary_card.offset_left = -340; vocabulary_card.offset_top = -260
	vocabulary_card.offset_right = 340; vocabulary_card.offset_bottom = 260
	vocabulary_card.hide()
	var vocab_content := VBoxContainer.new(); vocabulary_card.add_child(vocab_content)
	var vocab_header := HBoxContainer.new(); vocab_content.add_child(vocab_header)
	var vocab_title := _label(vocab_header, "Памятка по словам", 22); vocab_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(vocab_header, "Закрыть · F1", _toggle_vocabulary)
	_label(vocab_content, "Ищите немецкое слово, перевод или цель реплики. Полные фразы находятся внизу.", 15)
	vocabulary_search = LineEdit.new(); vocabulary_search.placeholder_text = "Найти слово, перевод или цель реплики…"; vocabulary_search.clear_button_enabled = true
	vocabulary_search.text_changed.connect(_filter_vocabulary); vocab_content.add_child(vocabulary_search)
	var vocab_scroll := ScrollContainer.new(); vocab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; vocab_content.add_child(vocab_scroll)
	var vocab_list := VBoxContainer.new(); vocab_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vocab_scroll.add_child(vocab_list)
	var memo_entries: Array = DialogueLanguage.memo_entries()
	var previous_group := ""
	for entry in memo_entries:
		var group := "phrase" if entry.pos == "phrase" else "words"
		if group != previous_group:
			var group_title := "Фразы целиком" if group == "phrase" else "Слова · частые в этом разговоре — выше"
			var group_label := _label(vocab_list, group_title, 16)
			group_label.modulate = Color("85c9c4")
			vocabulary_rows.append({"label":group_label,"group":group,"header":true,"search":""})
			previous_group = group
		var translation := DialogueLanguage.translation_for(str(entry.surface))
		var entry_label := _label(vocab_list, "%s  —  %s" % [entry.surface, translation], 16)
		vocabulary_rows.append({"label":entry_label,"surface":str(entry.surface),"frequency":int(entry.frequency),
			"group":group,"header":false,
			"search":("%s %s %s" % [entry.surface, translation, str(entry.get("search_terms", ""))]).to_lower()})
	_filter_vocabulary("")
	dev_panel = PanelContainer.new(); canvas.add_child(dev_panel)
	dev_panel.anchor_left = 0.035; dev_panel.anchor_top = 0.035; dev_panel.anchor_right = 0.965; dev_panel.anchor_bottom = 0.965
	dev_panel.offset_left = 0; dev_panel.offset_top = 0; dev_panel.offset_right = 0; dev_panel.offset_bottom = 0
	dev_panel.hide()
	var tools := VBoxContainer.new(); tools.add_theme_constant_override("separation", 12); dev_panel.add_child(tools)
	var bar := HBoxContainer.new(); tools.add_child(bar)
	var tool_title := _label(bar, "Лаборатория общения", 24); tool_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(bar, "Скрыть · F2", func(): _toggle_dev(false))
	dev_section_label = _label(tools, "СЮЖЕТНЫЕ ФАКТЫ И ПОСЛЕДСТВИЯ", 14)
	dev_section_label.modulate = Color("85c9c4")
	inspection_label = _label(tools, "Отправьте реплику, чтобы увидеть результат.", 16)
	dev_tabs = TabContainer.new(); dev_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; tools.add_child(dev_tabs)
	var tabs := dev_tabs
	parse_view = _inspector(tabs, "Разбор")
	diagnostic = _inspector(tabs, "Ответ и эффекты")
	context_view = _inspector(tabs, "Состояние")
	var history := VBoxContainer.new(); history.name = "История"; tabs.add_child(history)
	_label(history, "Выберите попытку для инспекции. Контекст мира не изменится.", 16)
	history_list = ItemList.new(); history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; history.add_child(history_list)
	history_list.item_selected.connect(_on_attempt_selected)
	_button(history, "Вернуть выбранный текст в редактор", _recall_attempt)
	var graph_page := VBoxContainer.new(); graph_page.name = "Граф диалога"
	graph_view = DialogueGraphView.new()
	graph_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_view.current_requested.connect(_show_current_graph)
	graph_page.add_child(graph_view)
	var graph_history_title := _label(graph_page, "ИСТОРИЯ ДИАЛОГА · выбранная попытка", 13)
	graph_history_title.modulate = Color("85c9c4")
	graph_history_view = RichTextLabel.new()
	graph_history_view.name = "DialogueGraphHistory"
	graph_history_view.custom_minimum_size.y = 78
	graph_history_view.size_flags_vertical = Control.SIZE_FILL
	graph_history_view.fit_content = false
	graph_history_view.scroll_following = true
	graph_page.add_child(graph_history_view)
	tabs.add_child(graph_page)
	dev_tabs.tab_changed.connect(_on_dev_tab_changed)
	_on_dev_tab_changed(dev_tabs.current_tab)
	_label(tools, "История — текущая сессия. Полный журнал сохраняется в JSONL.", 14).modulate = Color("9aafbd")
	_build_notice(canvas)
	_update_reply_view()
	_update_diagnostics({})
	_show_live_context()

func _build_topic_menu(parent: VBoxContainer) -> void:
	topic_menu = VBoxContainer.new()
	topic_menu.name = "DialogueActions"
	topic_menu.add_theme_constant_override("separation", 4)
	parent.add_child(topic_menu)
	_update_topic_menu()

func _build_notice(canvas: Control) -> void:
	notice_card = PanelContainer.new()
	notice_card.name = "ConversationToast"
	notice_card.position = Vector2(18, 18)
	notice_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_card.add_theme_stylebox_override("panel", _style(Color("29251f"), Color("c29c56")))
	canvas.add_child(notice_card)
	notice_label = _label(notice_card, "", 18)
	notice_label.name = "ConversationNotice"
	notice_label.modulate = Color("f0d6a7")
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var resize_notice := func():
		notice_card.size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 36.0)
	get_viewport().size_changed.connect(resize_notice)
	resize_notice.call()
	notice_timer = Timer.new()
	notice_timer.one_shot = true
	notice_timer.wait_time = 10.0
	notice_timer.timeout.connect(func(): _set_notice(""))
	add_child(notice_timer)
	_set_notice("")

func _update_reply_view() -> void:
	if not is_instance_valid(reply_editor):
		return
	var writing := not editing_action.is_empty() and not history_expanded
	reply_editor.visible = writing
	composer.visible = writing
	topic_menu.visible = not writing and not history_expanded

func _back_to_choices() -> void:
	editing_action = ""
	composer.release()
	_update_reply_view()
	if not topic_buttons.is_empty():
		topic_buttons.values()[0].grab_focus()

func _update_topic_menu() -> void:
	for child in topic_menu.get_children():
		topic_menu.remove_child(child)
		child.queue_free()
	topic_buttons.clear()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for action in Session.available_actions(context):
		var action_id := str(action.id)
		var button := Button.new()
		button.name = "Action_%s" % action_id
		button.text = str(action.label)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		if button.toggle_mode:
			button.button_group = group
			button.button_pressed = action_id == str(context.get("selected_action", ""))
		button.custom_minimum_size.y = 32
		button.pressed.connect(_select_dialogue_action.bind(action_id))
		topic_menu.add_child(button)
		topic_buttons[action_id] = button
	_update_reply_view()

func _select_dialogue_action(action_id: String) -> void:
	if language_busy: return
	var label := ""
	for action in Session.available_actions(context):
		if str(action.id) == action_id:
			label = str(action.label)
	var result: Dictionary = Session.select_action(action_id, context)
	if not result.get("accepted", false):
		return
	editing_action = action_id
	selected_reply_label.text = label
	_update_topic_menu()
	_show_live_context()
	composer.phrase.grab_focus()

func _set_notice(text: String) -> void:
	if not is_instance_valid(notice_label): return
	notice_label.text = text
	notice_label.visible = not text.is_empty()
	notice_card.visible = not text.is_empty()
	notice_timer.stop()
	if not text.is_empty():
		notice_timer.start()

func _select_dialogue_topic(topic_id: String) -> void:
	var result: Dictionary = Session.select_topic(topic_id, context)
	if result.get("closed_clarification", false):
		_set_notice("Уточнение закрыто при смене темы. Задайте новый вопрос.")
	else:
		_set_notice("")
	_update_topic_menu()

func _filter_vocabulary(query: String) -> void:
	var normalized := query.strip_edges().to_lower()
	var matching_groups := {}
	for row in vocabulary_rows:
		if not row.header and (normalized.is_empty() or str(row.search).contains(normalized)):
			matching_groups[row.group] = true
	for row in vocabulary_rows:
		var visible := matching_groups.has(row.group) if row.header else (normalized.is_empty() or str(row.search).contains(normalized))
		row.label.visible = visible

func _load_motion_manifest() -> void:
	var file := FileAccess.open("res://implementations/communication_lab/animations/generated/manifest.json", FileAccess.READ)
	if file == null: return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array: return
	for motion in parsed:
		if motion is Dictionary and motion.has("key") and motion.has("file"):
			motion_paths[str(motion.key)] = "res://implementations/communication_lab/animations/generated/" + str(motion.file)

func _recall_attempt() -> void:
	var selected := history_list.get_selected_items()
	if selected.is_empty(): return
	selected_attempt_index = selected[0]
	var action_id := str(context.get("selected_action", ""))
	_select_dialogue_action(action_id)
	composer.phrase.text = attempts[selected[0]].input
	composer.prefix.clear()
	composer.phrase.grab_focus()

func _toggle_vocabulary() -> void:
	vocabulary_card.visible = not vocabulary_card.visible
	if vocabulary_card.visible: composer.release()
	elif composer.visible: composer.phrase.grab_focus()

func _toggle_history_expanded() -> void:
	history_expanded = not history_expanded
	if history_expanded:
		dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dialog.offset_left = 0; dialog.offset_top = 0; dialog.offset_right = 0; dialog.offset_bottom = 0
		transcript.custom_minimum_size.y = 0
		transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_update_reply_view()
		heading_card.hide(); dev_panel.hide(); vocabulary_card.hide()
		history_expand_button.text = "Вернуться к разговору"
	else:
		dialog.anchor_left = 0.0; dialog.anchor_top = 1.0; dialog.anchor_right = 1.0; dialog.anchor_bottom = 1.0
		dialog.offset_left = 0; dialog.offset_top = -460; dialog.offset_right = 0; dialog.offset_bottom = 0
		transcript.custom_minimum_size.y = 110
		transcript.size_flags_vertical = Control.SIZE_FILL
		_update_reply_view()
		heading_card.show()
		history_expand_button.text = "История на весь экран"
		if composer.visible: composer.phrase.grab_focus()

func _show_live_context() -> void:
	if is_instance_valid(context_view):
		context_view.text = "СОСТОЯНИЕ РАЗГОВОРА / следующая попытка\n" + JSON.stringify(Session._conversation_snapshot(context), "  ")
	if is_instance_valid(graph_view) and selected_attempt_index < 0:
		_update_graph_view(context, -1)

func _input(event: InputEvent) -> void:
	if dialog.visible and composer.visible and composer.route_key(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 and dialog.visible:
			_toggle_vocabulary()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			if not dialog.visible: _open_dialog()
			_toggle_dev(not show_diagnostics)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and not dialog.visible and _can_interact():
			composer.suppress_opener(event)
			_open_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and dialog.visible:
			if not editing_action.is_empty():
				_back_to_choices()
			else:
				_close_dialog()
			get_viewport().set_input_as_handled()

func _open_dialog() -> void:
	if not dialog.visible: _start_conversation_camera()
	dialog.show(); player.is_movement_paused = true; player.is_showing_ui = true; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	heading_card.hide()
	_update_topic_menu()
	var opening: Dictionary = Session.opening_line(context)
	_append_conversation_line("Астера", opening.answer, true)
	astera_visual.set_emotion(opening.emotion_state)
	_play_reaction_motion(opening.animation_id)
	greeted = true
	_back_to_choices()

func _can_interact() -> bool:
	return is_instance_valid(player) and is_instance_valid(astera_visual) and player.global_position.distance_to(astera_visual.global_position) <= 5.0

func _close_dialog() -> void:
	language_epoch += 1
	language_busy = false
	composer.set_busy(false)
	if history_expanded: _toggle_history_expanded()
	Session.close_dialog(context)
	_set_notice("")
	_finish_reply_reveal()
	astera_visual.fade_expression_to_rest()
	dialog.hide(); _toggle_dev(false); composer.release(); player.is_movement_paused = false; player.is_showing_ui = false; Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	vocabulary_card.hide()
	heading_card.show()
	if is_instance_valid(camera_tween): camera_tween.kill()
	if is_instance_valid(exploration_camera): exploration_camera.make_current()

func _start_conversation_camera() -> void:
	exploration_camera = get_viewport().get_camera_3d()
	if is_instance_valid(camera_tween): camera_tween.kill()
	if is_instance_valid(exploration_camera):
		conversation_camera.global_transform = exploration_camera.global_transform
		conversation_camera.fov = exploration_camera.fov
	conversation_camera.make_current()
	var focus: Vector3 = astera_visual.global_position + Vector3(0, CONVERSATION_FOCUS_HEIGHT, 0)
	var shot := Transform3D(Basis.IDENTITY, focus + Vector3(0, CONVERSATION_CAMERA_HEIGHT - CONVERSATION_FOCUS_HEIGHT, CONVERSATION_DISTANCE)).looking_at(focus, Vector3.UP)
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(conversation_camera, "global_transform", shot, 0.6)
	camera_tween.tween_property(conversation_camera, "fov", CONVERSATION_FOV, 0.6)

func _on_submitted(text: String) -> void:
	if editing_action.is_empty() or language_busy:
		return
	language_epoch += 1
	var epoch := language_epoch
	language_busy = true
	composer.set_busy(true)
	var snapshot := context.duplicate(true)
	_append_conversation_line("Вы", text)
	_set_notice("Астера обдумывает ответ…")
	var parsed: Dictionary
	if bool(language_client.config.get("enabled", true)):
		parsed = await language_client.interpret(text, snapshot)
	else:
		parsed = DialogueLanguage.analyze_rpg(text, snapshot)
		parsed["backend"] = "offline-grammar"
	if epoch != language_epoch: return
	language_busy = false
	composer.set_busy(false)
	last_record = Session.submit_interpreted(text, context, parsed)
	_set_notice(str(last_record.get("notification", "")))
	var completed: bool = not str(last_record.get("transition_id", "")).is_empty()
	var awaiting_action_confirmation: bool = not context.get("pending_resolution", {}).is_empty()
	if completed or awaiting_action_confirmation or str(last_record.parse.get("status", "")) == "RECOGNIZED":
		editing_action = ""
		composer.clear()
	_update_topic_menu()
	astera_visual.set_emotion(last_record.emotion_state)
	_play_reaction_motion(last_record.animation_id)
	attempts.append(last_record.duplicate(true))
	selected_attempt_index = -1
	history_list.add_item("%02d  %s  ·  %s" % [attempts.size(), text, last_record.parse.status])
	history_list.deselect_all()
	_append_conversation_line("Астера", last_record.answer, true)

	_update_diagnostics(last_record)
	if editing_action.is_empty():
		_back_to_choices()

func _finish_reply_reveal() -> void:
	if is_instance_valid(reveal_tween): reveal_tween.kill()
	if is_instance_valid(transcript): transcript.visible_characters = -1

func _append_conversation_line(speaker: String, text: String, animate := false) -> void:
	_finish_reply_reveal()
	conversation_lines.append({"speaker":speaker, "text":text})
	transcript.push_color(Color("85d9ba") if speaker == "Астера" else Color("9ac9ff"))
	transcript.add_text(speaker + "  ")
	transcript.pop()
	var start := transcript.get_total_character_count()
	transcript.add_text(text + "\n")
	if animate:
		var total := transcript.get_total_character_count()
		transcript.visible_characters = start
		var rate := 28.0 if context.get("slow_speech", false) else 50.0
		reveal_tween = create_tween()
		reveal_tween.tween_property(transcript, "visible_characters", total, clampf(float(total - start) / rate, 0.25, 3.0))
		reveal_tween.tween_callback(func():
			transcript.visible_characters = -1
			if speaker == "Астера" and is_instance_valid(astera_visual):
				astera_visual.fade_expression_to_rest()
		)

func _play_reaction_motion(animation_id: String) -> void:
	if animation_id == "standing":
		astera_visual.return_to_idle()
	elif motion_paths.has(animation_id):
		astera_visual.play_generated(animation_id, motion_paths[animation_id])

func _update_diagnostics(record: Dictionary) -> void:
	_show_live_context()
	if record.is_empty():
		inspection_label.text = "Нет выбранной попытки · контекст готов"
		parse_view.text = "Разбор появится после отправки реплики.\n\nМожно вводить любые слова; распознаются только поддерживаемые конструкции."
		diagnostic.text = "Здесь будут ответ NPC и фактически применённые эффекты."
		selected_attempt_index = -1
		_update_graph_view(context, -1)
		return
	var parsed: Dictionary = record.parse
	inspection_label.text = "Попытка %02d  ·  %s / %s" % [attempts.find(record) + 1, parsed.status, parsed.intent]
	inspection_label.modulate = Color("85d9ba") if parsed.status == "RECOGNIZED" else Color("edc488")
	var recovery: Dictionary = parsed.get("recovery", {})
	var semantic_frames: Array = parsed.get("semantic_frames", [])
	parse_view.text = "ВВОД\n%s\n\nТОКЕНЫ\n%s\n\nСЕМАНТИЧЕСКИЙ FRAME\n%s\n\nСОСТАВНЫЕ FRAME\n%s\n\nВОССТАНОВЛЕНИЕ СМЫСЛА\nПолнота: %s  ·  грамматическая ошибка: %s  ·  восстановление использовано: %s\nДоказательства: %s\nВыведено из грамматики/контекста: %s\n\nAMBIGUITY\n%s\n\nUNSUPPORTED FEATURES\n%s\n\nDIAGNOSTICS\n%s" % [record.input, JSON.stringify(parsed.normalized_tokens), JSON.stringify(parsed.frame, "  "), JSON.stringify(semantic_frames, "  "), str(parsed.get("semantic_recovery_status", "NONE")), "да" if parsed.get("grammatical_error_detected", false) else "нет", "да" if parsed.get("recovery_used", false) else "нет", JSON.stringify(parsed.get("explicit_evidence", recovery.get("explicit_evidence", []))), JSON.stringify(parsed.get("inferred_fields", recovery.get("inferred_fields", []))), JSON.stringify(parsed.get("candidates", parsed.get("ambiguity", [])), "  "), JSON.stringify(parsed.get("unsupported_features", []), "  "), JSON.stringify(parsed.get("diagnostics", []), "  ")]
	parse_view.text += "\n\nЯЗЫКОВОЙ ДВИЖОК\n%s · %s мс\n%s" % [str(parsed.get("backend", "offline-grammar")), str(parsed.get("latency_ms", "—")), JSON.stringify(parsed.get("model_output", {}), "  ")]
	if parsed.has("model_request"):
		parse_view.text += "\n\nФАКТИЧЕСКИЙ ЗАПРОС МОДЕЛИ · %s\n%s" % [str(parsed.get("prompt_version", "")), JSON.stringify(parsed.model_request, "  ")]
	diagnostic.text = "ОТВЕТ NPC\n%s\n\nВЫБРАННАЯ РЕАКЦИЯ\n%s\n\nТЕМА\n%s\n\nФАКТИЧЕСКИЕ ЭФФЕКТЫ\n%s\n\nЭМОЦИЯ\n%s\n\nANIMATION ID\n%s" % [record.answer, record.get("reaction", ""), record.get("topic", ""), JSON.stringify(record.effects, "  "), record.get("emotion_state", "neutral"), record.get("animation_id", "standing")]
	context_view.text += "\n\nКОНТЕКСТ РАЗГОВОРА\n%s" % JSON.stringify(record.get("conversation_context", {}), "  ")
	context_view.text += "\n\nВЫБРАННАЯ ПОПЫТКА / до\n%s\n\nпосле\n%s" % [JSON.stringify(record.before, "  "), JSON.stringify(record.after, "  ")]
	_update_graph_view(record.get("conversation_context", record.get("after", {})), selected_attempt_index)

func _on_attempt_selected(index: int) -> void:
	if index < 0 or index >= attempts.size(): return
	selected_attempt_index = index
	_update_diagnostics(attempts[index])

func _show_current_graph() -> void:
	selected_attempt_index = -1
	if is_instance_valid(history_list): history_list.deselect_all()
	_show_live_context()
	_update_graph_view(context, -1)

func _update_graph_view(graph_context: Dictionary, attempt_index: int) -> void:
	if not is_instance_valid(graph_view): return
	graph_view.call("set_snapshot", graph_context, attempt_index)
	var route: Array = graph_context.get("dialogue_history", [])
	graph_history_view.text = _format_graph_history(route)

func _format_graph_history(events: Array) -> String:
	if events.is_empty():
		return "Пока нет отправленных реплик. Неподдерживаемый текст остаётся на текущем узле."
	var nodes: Dictionary = DialogueLanguage.data().get("dialogue", {}).get("nodes", {})
	var start := maxi(0, events.size() - 8)
	var lines: Array[String] = []
	for index in range(start, events.size()):
		var event: Dictionary = events[index]
		var from_id := str(event.get("node_before", "G00_GATE"))
		var to_id := str(event.get("node_after", from_id))
		var from_label := str(nodes.get(from_id, {}).get("label", from_id))
		var to_label := str(nodes.get(to_id, {}).get("label", to_id))
		var input_text := str(event.get("input", ""))
		var edge_id := str(event.get("transition_id", ""))
		var movement := "%s → %s · %s" % [from_label, to_label, edge_id] if not edge_id.is_empty() else "%s · без перехода" % from_label
		lines.append("%02d  %s  ·  %s / %s%s" % [index + 1, movement, str(event.get("actual_intent", "")),
			str(event.get("status", "")), "  ·  «%s»" % input_text if not input_text.is_empty() else ""])
	return "\n".join(lines)

func _toggle_dev(value: bool) -> void:
	show_diagnostics = value; dev_panel.visible = value
	if value and is_instance_valid(dev_tabs):
		var graph_page: Control = dev_tabs.get_node("Граф диалога")
		var graph_tab: int = dev_tabs.get_tab_idx_from_control(graph_page)
		dev_tabs.current_tab = graph_tab

func _on_dev_tab_changed(tab_index: int) -> void:
	if not is_instance_valid(dev_tabs): return
	var graph_page: Control = dev_tabs.get_node("Граф диалога")
	var graph_tab: int = dev_tabs.get_tab_idx_from_control(graph_page)
	var show_inspector_heading: bool = tab_index != graph_tab
	if is_instance_valid(dev_section_label): dev_section_label.visible = show_inspector_heading
	if is_instance_valid(inspection_label): inspection_label.visible = show_inspector_heading

func _reset() -> void:
	language_epoch += 1
	language_busy = false
	composer.set_busy(false)
	editing_action = ""
	selected_attempt_index = -1
	if is_instance_valid(history_list): history_list.deselect_all()
	composer.clear()
	Session.reset(context); last_record = {}
	_finish_reply_reveal(); transcript.clear(); conversation_lines.clear()
	_update_diagnostics({})
	_update_topic_menu(); _set_notice("")
	greeted = false
	astera_visual.set_emotion("neutral")
	astera_visual.return_to_idle()
