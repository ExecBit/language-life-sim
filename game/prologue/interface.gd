extends CanvasLayer
const BREAD_ICON = preload("res://game/shop/bread.svg")
const MILK_ICON = preload("res://game/shop/milk.svg")
const KEY_ICON = preload("res://game/prologue/key.svg")
const BAG_ICON = preload("res://game/prologue/bag.svg")
signal command(id: String)
signal setting_changed(id: String, value: float)

var root: Control
var dialog: PanelContainer
var speaker: Label
var line: Label
var answers: HFlowContainer
var prompt: Label
var notice: Label
var chapter: Label
var menu: PanelContainer
var pause_panel: PanelContainer
var settings: PanelContainer
var subject: PanelContainer
var complete_panel: PanelContainer
var continue_button: Button
var shop_panel: PanelContainer
var shop_content: VBoxContainer
var shop_status: Label
var shop_hud: HBoxContainer
var shop_modal_ids: Array[String] = []
var fonts := []
var answer_ids: Array[String] = []
var notice_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 20
	root.theme = theme
	add_child(root)
	chapter = label("Первый день",19)
	chapter.position = Vector2(24,20)
	root.add_child(chapter)
	var dot := label("·",32)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(dot)
	prompt = label("",20)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-260,36)
	prompt.custom_minimum_size.x = 520
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)
	notice = label("",18)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice.offset_top = 62
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice)
	var controls := label("WASD — идти    Мышь — взгляд    E — действие    Tab — курсор    J — цель    Esc — пауза",16)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position += Vector2(24,-28)
	root.add_child(controls)
	dialog = panel()
	dialog.anchor_left = 0.12
	dialog.anchor_right = 0.88
	dialog.anchor_top = 1.0
	dialog.anchor_bottom = 1.0
	dialog.offset_top = -195
	dialog.offset_bottom = -48
	root.add_child(dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",9)
	dialog.add_child(content)
	speaker = label("",16)
	speaker.add_theme_color_override("font_color",Color("e3c087"))
	content.add_child(speaker)
	line = label("",27)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(line)
	answers = HFlowContainer.new()
	answers.add_theme_constant_override("h_separation",10)
	answers.add_theme_constant_override("v_separation",6)
	content.add_child(answers)
	dialog.hide()
	menu = centered(Vector2(470,440))
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation",12)
	menu.add_child(main)
	main.add_child(label("ЗАСЕЛЕНИЕ",34))
	main.add_child(label("Language Life · Уровень 1",19))
	main.add_child(label("Освойтесь в новом доме.\nНаблюдайте, общайтесь, действуйте.",18))
	continue_button = button(main,"Продолжить","continue")
	button(main,"Новая игра","new")
	button(main,"Настройки","settings")
	button(main,"Выход","quit")
	pause_panel = centered(Vector2(420,310))
	var pause_box := VBoxContainer.new()
	pause_box.add_theme_constant_override("separation",12)
	pause_panel.add_child(pause_box)
	pause_box.add_child(label("ПАУЗА",29))
	button(pause_box,"Продолжить","resume")
	button(pause_box,"Настройки","settings")
	button(pause_box,"Главное меню","menu")
	pause_panel.hide()
	subject = centered(Vector2(580,230))
	var subject_box := VBoxContainer.new()
	subject.add_child(subject_box)
	subject_box.add_child(label("Wo ist …?",28))
	var key_button := button(subject_box,"Wo ist mein Schlüssel?","subject:room_key")
	key_button.icon = KEY_ICON
	key_button.add_theme_constant_override("icon_max_width",48)
	var bag_button := button(subject_box,"Wo ist meine Tasche?","subject:bag")
	bag_button.icon = BAG_ICON
	bag_button.add_theme_constant_override("icon_max_width",48)
	button(subject_box,"Отмена","cancel_target")
	subject.hide()
	settings = centered(Vector2(530,400))
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation",10)
	settings.add_child(options)
	options.add_child(label("НАСТРОЙКИ",28))
	slider(options,"Громкость","volume",0.0,1.0,0.8)
	slider(options,"Чувствительность мыши","sensitivity",0.05,0.7,0.22)
	slider(options,"Размер текста","text_scale",0.85,1.3,1.0)
	button(options,"Окно / полный экран","fullscreen")
	button(options,"Назад","settings_back")
	settings.hide()
	complete_panel = centered(Vector2(540,300))
	var end := VBoxContainer.new()
	end.add_theme_constant_override("separation",14)
	complete_panel.add_child(end)
	end.add_child(label("ДЕНЬ 2 ЗАВЕРШЁН",27))
	end.add_child(label("Первые два дня в доме завершены.\nДальнейшее продолжение пролога появится позже.",21))
	button(end,"Продолжить прогулку","explore")
	button(end,"Главное меню","menu")
	complete_panel.hide()
	shop_panel = centered(Vector2(540,360))
	shop_content = VBoxContainer.new()
	shop_content.add_theme_constant_override("separation",12)
	shop_panel.add_child(shop_content)
	shop_panel.hide()
	shop_hud = product_icons()
	shop_hud.anchor_left = 1.0
	shop_hud.anchor_right = 1.0
	shop_hud.offset_left = -610
	shop_hud.offset_top = 18
	shop_hud.offset_right = -24
	root.add_child(shop_hud)
	shop_status = label("",23)
	shop_hud.add_child(shop_status)
	shop_hud.hide()

func product_icons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	for i in 2:
		var icon := TextureRect.new()
		icon.texture = BREAD_ICON if i == 0 else MILK_ICON
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(54,44)
		row.add_child(icon)
		row.add_child(label("1,80 €" if i == 0 else "1,20 €",23))
	return row

func add_receipt_icons() -> void:
	var row := product_icons()
	shop_content.add_child(row)
	shop_content.move_child(row,1)

func show_shop_panel(title: String, text: String, choices: Array) -> void:
	for child in shop_content.get_children():
		shop_content.remove_child(child)
		child.queue_free()
	shop_modal_ids.clear()
	shop_content.add_child(label(title,28))
	var body := label(text,23)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 470
	shop_content.add_child(body)
	for choice in choices:
		shop_modal_ids.append(str(choice.id))
		var choice_button := button(shop_content,"%d  %s" % [shop_modal_ids.size(),choice.text],str(choice.id))
		if str(choice.id).begins_with("shop_unpack:"):
			choice_button.icon = BREAD_ICON if str(choice.id).ends_with("grocery_bread") else MILK_ICON
			choice_button.add_theme_constant_override("icon_max_width",40)
	shop_panel.show()

func hide_shop_panel() -> void:
	shop_panel.hide()
	shop_modal_ids.clear()

func label(text: String, size: int) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size",size)
	value.add_theme_color_override("font_color",Color("f2eee4"))
	value.add_theme_color_override("font_outline_color",Color("22343c"))
	value.add_theme_constant_override("outline_size",3)
	fonts.append([value,size])
	return value

func panel() -> PanelContainer:
	var value := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055,0.12,0.14,0.96)
	style.set_corner_radius_all(12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	value.add_theme_stylebox_override("panel",style)
	return value

func centered(size: Vector2) -> PanelContainer:
	var value := panel()
	value.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	value.position -= size/2
	value.custom_minimum_size = size
	root.add_child(value)
	return value

func button(parent: Control, text: String, id: String) -> Button:
	var value := Button.new()
	value.text = text
	value.custom_minimum_size.y = 36
	value.add_theme_font_size_override("font_size",21)
	value.pressed.connect(func(): command.emit(id))
	parent.add_child(value)
	fonts.append([value,21])
	return value

func slider(parent: Control, text: String, id: String, low: float, high: float, initial: float) -> void:
	parent.add_child(label(text,18))
	var value := HSlider.new()
	value.min_value = low
	value.max_value = high
	value.step = 0.01
	value.value = initial
	value.name = id
	value.value_changed.connect(func(number): setting_changed.emit(id,number))
	parent.add_child(value)

func display(from: String, to: String, text: String, responses: Array) -> void:
	speaker.text = (from + ("  →  " + to if to != "" else ""))
	line.text = text
	for child in answers.get_children():
		answers.remove_child(child)
		child.queue_free()
	answer_ids.clear()
	for response in responses:
		var id := str(response.id)
		answer_ids.append(id)
		button(answers,"%d  %s" % [answer_ids.size(),response.text],"answer:"+id)
	dialog.visible = not text.is_empty() or not responses.is_empty()

func notify(text: String) -> void:
	notice.text = text
	notice_time = 5.0

func text_scale(value: float) -> void:
	for entry in fonts:
		if is_instance_valid(entry[0]): entry[0].add_theme_font_size_override("font_size",int(entry[1]*value))
	root.theme.default_font_size = int(20*value)

func _process(delta: float) -> void:
	if notice_time > 0:
		notice_time -= delta
		if notice_time <= 0: notice.text = ""
