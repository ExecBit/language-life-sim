extends Node3D
const Composer = preload("res://implementations/communication_lab/game/communication/word_composer.gd")
const Session = preload("res://implementations/communication_lab/game/communication/lab_session.gd")
const WordCatalog = preload("res://implementations/communication_lab/game/communication/word_catalog.gd")
const DialogueGrammar = preload("res://implementations/communication_lab/game/communication/dialogue_resolver.gd")
const DialogueLanguage = preload("res://implementations/communication_lab/game/communication/dialogue_language.gd")
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
var parse_view: RichTextLabel
var context_view: RichTextLabel
var inspection_label: Label
var vocabulary_card: PanelContainer
var vocabulary_search: LineEdit
var vocabulary_rows: Array[Dictionary] = []
var pending_option: OptionButton
var busy_toggle: CheckBox
var mood_option: OptionButton
var astera_mood_option: OptionButton
var offered_help_toggle: CheckBox
var name_toggle: CheckBox
var topic_option: OptionButton
var objective_panel: PanelContainer
var objective_labels: Dictionary = {}
var topic_menu: HBoxContainer
var topic_buttons: Dictionary = {}
var notice_label: Label
var greeted := false
var motion_paths: Dictionary = {}
var conversation_camera: Camera3D
var exploration_camera: Camera3D
var camera_tween: Tween
var heading_card: PanelContainer
var history_expand_button: Button
var history_expanded := false
var dialogue_silence_seconds := 0.0
var silence_tease_shown := false
const SILENCE_TEASE_DELAY := 24.0

func _process(delta: float) -> void:
	if not dialog.visible or silence_tease_shown or vocabulary_card.visible: return
	if not composer.phrase.text.strip_edges().is_empty():
		dialogue_silence_seconds = 0.0
		return
	dialogue_silence_seconds += delta
	if dialogue_silence_seconds >= SILENCE_TEASE_DELAY:
		silence_tease_shown = true
		_append_conversation_line("Астера", "Du bist sehr still!", true)
		astera_visual.set_emotion("playful")
		_play_reaction_motion("playful_shrug")

func _ready() -> void:
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
	_label(heading, "WASD · движение   /   E · разговор   /   F2 · лаборатория", 16)
	_build_objective_tracker(canvas)
	dialog = PanelContainer.new(); dialog.name = "CommunicationPanel"; canvas.add_child(dialog)
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
	composer = Composer.new(); column.add_child(composer)
	composer.submitted.connect(_on_submitted); composer.cancelled.connect(_close_dialog)
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
	_label(vocab_content, "Tab переключает варианты; пробел добавляет выбранное слово. Свободный ввод тоже доступен.", 15)
	vocabulary_search = LineEdit.new(); vocabulary_search.placeholder_text = "Найти немецкое слово или перевод…"; vocabulary_search.clear_button_enabled = true
	vocabulary_search.text_changed.connect(_filter_vocabulary); vocab_content.add_child(vocabulary_search)
	var vocab_scroll := ScrollContainer.new(); vocab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; vocab_content.add_child(vocab_scroll)
	var vocab_list := VBoxContainer.new(); vocab_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vocab_scroll.add_child(vocab_list)
	var memo_entries: Array = WordCatalog.ENTRIES.duplicate(true)
	memo_entries.append_array(DialogueGrammar.vocabulary_entries())
	memo_entries.append_array(DialogueLanguage.vocabulary_entries())
	var unique_entries: Array = []
	var seen_surfaces := {}
	for entry in memo_entries:
		var normalized_surface: String = str(entry.surface).to_lower()
		if seen_surfaces.has(normalized_surface): continue
		seen_surfaces[normalized_surface] = true
		unique_entries.append(entry)
	memo_entries = unique_entries
	var groups := {"phrase": [], "pronoun": [], "verb": [], "noun": [], "adjective": [], "other": []}
	for entry in memo_entries:
		if entry.availability != "available": continue
		var group: String = entry.pos if groups.has(entry.pos) else "other"
		if not groups[group].has(entry.surface): groups[group].append(entry.surface)
	var group_titles := {"phrase":"Фразы целиком", "pronoun":"Местоимения", "verb":"Глаголы и формы", "noun":"Существительные и имена", "adjective":"Признаки", "other":"Другие слова"}
	var translations := {"lamp":"лампа", "player":"я / мне", "addressee":"ты / тебе", "anna":"Анна (в каталоге)", "want":"хотеть", "need":"нуждаться", "can":"мочь", "have":"иметь", "be":"быть", "open":"открывать", "give":"давать", "help":"помогать", "know":"знать", "key":"ключ", "door":"дверь", "room":"комната", "article":"артикль", "no":"никакой / не", "reference":"это", "not":"не", "where":"где", "why":"почему", "what":"что", "please":"пожалуйста", "closed":"закрыт", "accept":"да", "refuse":"нет", "thanks":"спасибо", "greeting":"приветствие", "subordinate":"что / потому что", "here":"здесь", "later":"позже", "lena":"Лена", "farewell":"пока", "apology":"извинение", "understand":"понимать", "again":"ещё раз", "once":"один раз", "approach":"подойти", "take":"взять", "water":"вода", "cup":"чашка", "bag":"сумка", "bread":"хлеб", "bell":"колокольчик", "market":"супермаркет", "possessive":"мой / моя"}
	for group in ["phrase", "pronoun", "verb", "noun", "adjective", "other"]:
		if groups[group].is_empty(): continue
		var group_label := _label(vocab_list, group_titles[group], 16)
		group_label.modulate = Color("85c9c4")
		vocabulary_rows.append({"label":group_label,"group":group,"header":true,"search":""})
		for entry in memo_entries:
			if entry.availability != "available" or (entry.pos if groups.has(entry.pos) else "other") != group: continue
			var translation: String = DialogueGrammar.translation_for(entry.surface)
			if translation == "": translation = DialogueLanguage.translation_for(entry.surface)
			if translation == "": translation = translations.get(entry.semantic_id, "перевод не указан")
			var entry_label := _label(vocab_list, "%s  —  %s" % [entry.surface, translation], 16)
			vocabulary_rows.append({"label":entry_label,"group":group,"header":false,"search":("%s %s" % [entry.surface, translation]).to_lower()})
	_filter_vocabulary("")
	dev_panel = PanelContainer.new(); canvas.add_child(dev_panel)
	dev_panel.anchor_left = 0.56; dev_panel.anchor_right = 1.0; dev_panel.anchor_bottom = 1.0
	dev_panel.offset_left = 0; dev_panel.offset_top = 18; dev_panel.offset_right = -18; dev_panel.offset_bottom = -440
	dev_panel.hide()
	var tools := VBoxContainer.new(); tools.add_theme_constant_override("separation", 12); dev_panel.add_child(tools)
	var bar := HBoxContainer.new(); tools.add_child(bar)
	var tool_title := _label(bar, "Лаборатория общения", 24); tool_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(bar, "Скрыть · F2", func(): _toggle_dev(false))
	_label(tools, "КОНТЕКСТ СЛЕДУЮЩЕЙ ПОПЫТКИ", 14).modulate = Color("85c9c4")
	var settings := HFlowContainer.new(); tools.add_child(settings)
	busy_toggle = CheckBox.new(); busy_toggle.text = "Астера занята"; busy_toggle.toggled.connect(func(v): context.busy = v; _show_live_context()); settings.add_child(busy_toggle)
	name_toggle = CheckBox.new(); name_toggle.text = "Знает имя"; name_toggle.toggled.connect(func(v): context.player_name = "Alex" if v else ""; _show_live_context()); settings.add_child(name_toggle)
	mood_option = OptionButton.new()
	for title_text in ["Настроение: нет", "Хорошее", "Плохое", "Усталость"]: mood_option.add_item(title_text)
	mood_option.item_selected.connect(_set_player_mood); settings.add_child(mood_option)
	astera_mood_option = OptionButton.new()
	for title_text in ["Астера: устала", "Астера: обычно", "Астера: хорошо"]: astera_mood_option.add_item(title_text)
	astera_mood_option.item_selected.connect(func(index): context.astera_mood = ["tired", "neutral", "good"][index]; _show_live_context()); settings.add_child(astera_mood_option)
	offered_help_toggle = CheckBox.new(); offered_help_toggle.text = "Помощь предложена"; offered_help_toggle.toggled.connect(func(value): context.offered_help = value; _show_live_context()); settings.add_child(offered_help_toggle)
	topic_option = OptionButton.new()
	for title_text in ["Тема: знакомство", "Самочувствие игрока", "Самочувствие Астеры", "Занятия", "Помощь", "Медленная речь", "Прощание"]: topic_option.add_item(title_text)
	topic_option.item_selected.connect(_set_topic); settings.add_child(topic_option)
	pending_option = OptionButton.new()
	for title_text in ["Ожидание: имя", "Ожидание: самочувствие", "Ожидание: занятие", "Ожидание: помощь", "Ожидание: медленная речь", "Ожидание: нет"]: pending_option.add_item(title_text)
	pending_option.item_selected.connect(_set_pending); settings.add_child(pending_option)
	_button(settings, "Сбросить контекст", _reset)
	inspection_label = _label(tools, "Отправьте реплику, чтобы увидеть результат.", 16)
	var tabs := TabContainer.new(); tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; tools.add_child(tabs)
	parse_view = _inspector(tabs, "Разбор")
	diagnostic = _inspector(tabs, "Ответ и эффекты")
	context_view = _inspector(tabs, "Состояние")
	var history := VBoxContainer.new(); history.name = "История"; tabs.add_child(history)
	_label(history, "Выберите попытку для инспекции. Контекст мира не изменится.", 16)
	history_list = ItemList.new(); history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; history.add_child(history_list)
	history_list.item_selected.connect(func(index): _update_diagnostics(attempts[index]))
	_button(history, "Вернуть выбранный текст в редактор", _recall_attempt)
	_label(tools, "История — текущая сессия. Полный журнал сохраняется в JSONL.", 14).modulate = Color("9aafbd")
	_update_diagnostics({})
	_update_objective_tracker()

func _build_objective_tracker(parent: Control) -> void:
	objective_panel = PanelContainer.new()
	objective_panel.name = "ConversationObjectives"
	parent.add_child(objective_panel)
	objective_panel.position = Vector2(18, 112)
	objective_panel.custom_minimum_size = Vector2(280, 0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	objective_panel.add_child(content)
	_label(content, "ЗНАКОМСТВО С АСТЕРОЙ", 14).modulate = Color("85c9c4")
	var objectives := {
		"introduce":"Представиться", "ask_mood":"Узнать, как у неё дела", "ask_activity":"Спросить о её занятиях",
		"share_self":"Рассказать о себе", "offer_help":"Предложить помощь", "farewell":"Попрощаться"}
	for key in objectives:
		var item := _label(content, "○  " + str(objectives[key]), 16)
		item.name = "Objective_%s" % key
		item.custom_minimum_size.x = 250
		objective_labels[key] = item
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.hide()

func _build_topic_menu(parent: VBoxContainer) -> void:
	topic_menu = HBoxContainer.new()
	topic_menu.name = "DialogueTopics"
	topic_menu.add_theme_constant_override("separation", 8)
	parent.add_child(topic_menu)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for topic in DialogueLanguage.data().get("topics", []):
		var topic_id := str(topic.get("id", ""))
		var button := Button.new()
		button.name = "Topic_%s" % topic_id
		button.text = str(topic.get("label", topic_id))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.pressed.connect(_select_dialogue_topic.bind(topic_id))
		topic_menu.add_child(button)
		topic_buttons[topic_id] = button
	notice_label = Label.new()
	notice_label.name = "ConversationNotice"
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size.y = 22
	notice_label.add_theme_font_size_override("font_size", 15)
	notice_label.modulate = Color("edc488")
	parent.add_child(notice_label)
	notice_label.hide()
	_update_topic_menu()

func _update_topic_menu() -> void:
	var selected := str(context.get("selected_topic", "introduction"))
	for topic_id in topic_buttons:
		var button: Button = topic_buttons[topic_id]
		button.button_pressed = str(topic_id) == selected

func _set_notice(text: String) -> void:
	if not is_instance_valid(notice_label): return
	notice_label.text = text
	notice_label.visible = not text.is_empty()

func _select_dialogue_topic(topic_id: String) -> void:
	var result: Dictionary = Session.select_topic(topic_id, context)
	if result.get("closed_clarification", false):
		_set_notice("Уточнение закрыто при смене темы. Задайте новый вопрос.")
	else:
		_set_notice("")
	_update_topic_menu()

func _update_objective_tracker() -> void:
	if not is_instance_valid(objective_panel): return
	var progress: Dictionary = context.get("objective_progress", {})
	for key in objective_labels:
		var label: Label = objective_labels[key]
		var done: bool = progress.get(key, false)
		var title: String = Session.OBJECTIVE_TITLES.get(key, key)
		label.text = ("✓  " if done else "○  ") + title
		label.modulate = Color("85d9ba") if done else Color("e0e8ef")

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
	composer.phrase.text = attempts[selected[0]].input
	composer.prefix.clear()
	composer.phrase.grab_focus()

func _toggle_vocabulary() -> void:
	vocabulary_card.visible = not vocabulary_card.visible
	if vocabulary_card.visible: composer.release()
	else: composer.phrase.grab_focus()

func _toggle_history_expanded() -> void:
	history_expanded = not history_expanded
	if history_expanded:
		dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dialog.offset_left = 0; dialog.offset_top = 0; dialog.offset_right = 0; dialog.offset_bottom = 0
		transcript.custom_minimum_size.y = 0
		transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
		composer.hide()
		heading_card.hide(); objective_panel.hide(); dev_panel.hide(); vocabulary_card.hide()
		history_expand_button.text = "Вернуться к разговору"
	else:
		dialog.anchor_left = 0.0; dialog.anchor_top = 1.0; dialog.anchor_right = 1.0; dialog.anchor_bottom = 1.0
		dialog.offset_left = 0; dialog.offset_top = -460; dialog.offset_right = 0; dialog.offset_bottom = 0
		transcript.custom_minimum_size.y = 110
		transcript.size_flags_vertical = Control.SIZE_FILL
		composer.show()
		heading_card.show(); objective_panel.hide()
		history_expand_button.text = "История на весь экран"
		composer.phrase.grab_focus()

func _show_live_context() -> void:
	if is_instance_valid(context_view):
		context_view.text = "СОСТОЯНИЕ РАЗГОВОРА / следующая попытка\n" + JSON.stringify(Session._conversation_snapshot(context), "  ")

func _input(event: InputEvent) -> void:
	if dialog.visible and composer.route_key(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 and vocabulary_card.visible:
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
			_close_dialog()
			get_viewport().set_input_as_handled()

func _open_dialog() -> void:
	if not dialog.visible: _start_conversation_camera()
	dialog.show(); player.is_movement_paused = true; player.is_showing_ui = true; Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dialogue_silence_seconds = 0.0
	heading_card.hide()
	_update_topic_menu()
	if not greeted:
		var opening: Dictionary = Session.opening_line(context)
		_append_conversation_line("Астера", opening.answer, true)
		astera_visual.set_emotion(opening.emotion_state)
		_play_reaction_motion(opening.animation_id)
		greeted = true
	composer.phrase.grab_focus()

func _can_interact() -> bool:
	return is_instance_valid(player) and is_instance_valid(astera_visual) and player.global_position.distance_to(astera_visual.global_position) <= 5.0

func _close_dialog() -> void:
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
	dialogue_silence_seconds = 0.0
	_append_conversation_line("Вы", text)
	last_record = Session.submit(text, context, str(context.get("selected_topic", "")))
	_set_notice(str(last_record.get("notification", "")))
	_update_topic_menu()
	astera_visual.set_emotion(last_record.emotion_state)
	_play_reaction_motion(last_record.animation_id)
	_update_objective_tracker()
	name_toggle.button_pressed = not context.player_name.is_empty()
	mood_option.select(["", "good", "low", "tired"].find(context.player_mood))
	astera_mood_option.select(["tired", "neutral", "good"].find(context.astera_mood))
	offered_help_toggle.button_pressed = context.offered_help
	topic_option.select(["introduction", "player_mood", "astera_mood", "activity", "help", "slow_speech", "farewell"].find(context.topic))
	pending_option.select(["player_name", "player_mood", "player_plan", "help_offer", "slow_speech", ""].find(context.pending_question))
	attempts.append(last_record.duplicate(true))
	history_list.add_item("%02d  %s  ·  %s" % [attempts.size(), text, last_record.parse.status])
	history_list.select(attempts.size() - 1)
	_append_conversation_line("Астера", last_record.answer, true)
	composer.clear()

	_update_diagnostics(last_record)

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
		return
	var parsed: Dictionary = record.parse
	inspection_label.text = "Попытка %02d  ·  %s / %s" % [attempts.find(record) + 1, parsed.status, parsed.intent]
	inspection_label.modulate = Color("85d9ba") if parsed.status == "RECOGNIZED" else Color("edc488")
	var recovery: Dictionary = parsed.get("recovery", {})
	var semantic_frames: Array = parsed.get("semantic_frames", [])
	parse_view.text = "ВВОД\n%s\n\nТОКЕНЫ\n%s\n\nСЕМАНТИЧЕСКИЙ FRAME\n%s\n\nСОСТАВНЫЕ FRAME\n%s\n\nВОССТАНОВЛЕНИЕ СМЫСЛА\nПолнота: %s  ·  грамматическая ошибка: %s  ·  восстановление использовано: %s\nДоказательства: %s\nВыведено из грамматики/контекста: %s\n\nAMBIGUITY\n%s\n\nUNSUPPORTED FEATURES\n%s\n\nDIAGNOSTICS\n%s" % [record.input, JSON.stringify(parsed.normalized_tokens), JSON.stringify(parsed.frame, "  "), JSON.stringify(semantic_frames, "  "), str(parsed.get("semantic_recovery_status", "NONE")), "да" if parsed.get("grammatical_error_detected", false) else "нет", "да" if parsed.get("recovery_used", false) else "нет", JSON.stringify(recovery.get("explicit_evidence", [])), JSON.stringify(recovery.get("inferred_fields", [])), JSON.stringify(parsed.get("ambiguity", []), "  "), JSON.stringify(parsed.get("unsupported_features", []), "  "), JSON.stringify(parsed.get("diagnostics", []), "  ")]
	diagnostic.text = "ОТВЕТ NPC\n%s\n\nВЫБРАННАЯ РЕАКЦИЯ\n%s\n\nТЕМА\n%s\n\nФАКТИЧЕСКИЕ ЭФФЕКТЫ\n%s\n\nЭМОЦИЯ\n%s\n\nANIMATION ID\n%s" % [record.answer, record.get("reaction", ""), record.get("topic", ""), JSON.stringify(record.effects, "  "), record.get("emotion_state", "neutral"), record.get("animation_id", "standing")]
	context_view.text += "\n\nКОНТЕКСТ РАЗГОВОРА\n%s" % JSON.stringify(record.get("conversation_context", {}), "  ")
	context_view.text += "\n\nВЫБРАННАЯ ПОПЫТКА / до\n%s\n\nпосле\n%s" % [JSON.stringify(record.before, "  "), JSON.stringify(record.after, "  ")]

func _toggle_dev(value: bool) -> void:
	show_diagnostics = value; dev_panel.visible = value

func _set_pending(index: int) -> void:
	context.pending_question = ["player_name", "player_mood", "player_plan", "help_offer", "slow_speech", ""][index]; _show_live_context()

func _set_player_mood(index: int) -> void:
	context.player_mood = ["", "good", "low", "tired"][index]; _show_live_context()

func _set_topic(index: int) -> void:
	context.topic = ["introduction", "player_mood", "astera_mood", "activity", "help", "slow_speech", "farewell"][index]; _show_live_context()

func _reset() -> void:
	Session.reset(context); busy_toggle.button_pressed = false; name_toggle.button_pressed = false; offered_help_toggle.button_pressed = false
	mood_option.select(0); astera_mood_option.select(0); topic_option.select(0); pending_option.select(0); last_record = {}
	_finish_reply_reveal(); transcript.clear(); conversation_lines.clear()
	_update_diagnostics({}); _update_objective_tracker()
	_update_topic_menu(); _set_notice("")
	greeted = false
	dialogue_silence_seconds = 0.0; silence_tease_shown = false
	astera_visual.set_emotion("neutral")
	astera_visual.return_to_idle()

