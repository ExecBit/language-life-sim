extends PanelContainer
signal command(id: String)
signal setting_changed(id: String, value: float)

var options: Control
var back: Button

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    z_index = 20
    var background := StyleBoxFlat.new()
    background.bg_color = Color("18252d")
    add_theme_stylebox_override("panel", background)
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    offset_left = 16
    offset_top = 16
    offset_right = -16
    offset_bottom = -16
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)
    var heading := Label.new()
    heading.text = "Настройки"
    heading.add_theme_font_size_override("font_size", 26)
    column.add_child(heading)
    options = preload("res://game/settings/cogito_options.tscn").instantiate()
    column.add_child(options)
    var extra := HBoxContainer.new()
    extra.add_theme_constant_override("separation", 12)
    column.add_child(extra)
    add_slider(extra, "Общая громкость", "volume", 0.0, 1.0, 0.8)
    add_slider(extra, "Размер текста", "text_scale", 0.85, 1.3, 1.0)
    back = Button.new()
    back.text = "Сохранить и назад"
    back.custom_minimum_size.y = 42
    column.add_child(back)
    back.pressed.connect(func(): command.emit("settings_back"))
    hide()

func add_slider(parent: Node, title: String, id: String, low: float, high: float, initial: float) -> void:
    var label := Label.new()
    label.text = title
    parent.add_child(label)
    var slider := HSlider.new()
    slider.name = id
    slider.min_value = low
    slider.max_value = high
    slider.step = 0.01
    slider.value = initial
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size.x = 80
    parent.add_child(slider)
    slider.value_changed.connect(func(value): setting_changed.emit(id, value))

func open() -> void:
    show()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    options.tab_container.get_tab_bar().grab_focus()

func apply_and_close() -> void:
    options.cancel_remapping()
    options._on_apply_changes_pressed()
    hide()

func input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if options.cancel_remapping():
            get_viewport().set_input_as_handled()
            return
        command.emit("settings_back")
        get_viewport().set_input_as_handled()
