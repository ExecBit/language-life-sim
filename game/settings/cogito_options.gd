extends "res://addons/cogito/EasyMenus/Scripts/OptionsTabMenu.gd"
## Project adapter for the unmodified Cogito settings scene.

const ACTIONS := {
    "forward":"Вперёд", "back":"Назад", "left":"Влево", "right":"Вправо",
    "jump":"Прыжок", "sprint":"Бег", "crouch":"Присесть",
}

func _ready() -> void:
    super._ready()
    # The upstream scene also connects Apply to a scriptless bindings tab.
    # save_options already persists bindings; retain the valid root connection only.
    var apply_button := get_node("%ApplyChanges") as Button
    for connection in apply_button.pressed.get_connections():
        if connection.callable.get_object() != self:
            apply_button.pressed.disconnect(connection.callable)
    tab_container.custom_minimum_size = Vector2(500, 0)
    tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    get_node("VBoxContainer/TabContainer/TAB_GAMEPLAY/ScrollContainer/VBoxContainer/HBoxContainer_Language").hide()
    var titles := ["Игра", "Графика", "Звук", "Клавиши"]
    for index in titles.size(): tab_container.set_tab_title(index, titles[index])
    tab_container.current_tab = 0
    # Font fallback includes Cyrillic, unlike the stock tab font override.
    tab_container.add_theme_font_override("font", ThemeDB.fallback_font)
    var translations := {
        "InvertYModeLabel":"Инверсия мыши по Y", "ToggleCrouchModeLabel":"Приседание переключателем",
        "HeadbobLabel":"Покачивание камеры", "MouseSensLabel":"Чувствительность мыши",
        "GPLookSensLabel":"Чувствительность геймпада", "FullscreenModeLabel":"Полный экран",
        "ResolutionLabel":"Разрешение окна", "FullscreenResolutionLabel":"Масштаб рендера",
        "GUIScaleLabel":"Масштаб интерфейса", "VSyncModeLabel":"Вертикальная синхронизация",
        "AntiAliasing2DLabel":"Сглаживание 2D", "AntiAliasing3DLabel":"Сглаживание 3D",
    }
    for node_name in translations:
        var label := find_child(node_name, true, false) as Label
        if label: label.text = translations[node_name]
    get_node("VBoxContainer/TabContainer/TAB_GAMEPLAY/ScrollContainer/VBoxContainer/HBoxContainer_Group/Label").text = "Геймпад"
    sfx_volume_slider.title = "Звуки"
    music_volume_slider.title = "Музыка"
    apply_button.text = "Применить"

func _on_options_loaded(skip_applying: bool) -> void:
    # Preserve the independently saved crouch toggle: the upstream loader emits invert_y here.
    var crouch: bool = CogitoGameConfig.toggle_crouching
    super._on_options_loaded(skip_applying)
    toggle_crouching_check_button.set_pressed_no_signal(crouch)
    CogitoGameConfig.toggle_crouching = crouch

func create_action_remap_items() -> void:
    for action in ACTIONS:
        var entry = remap_entry.instantiate()
        entry.action = action
        bindings_container.add_child(entry)
        entry.label.text = ACTIONS[action]

func remapping() -> bool:
    for entry in bindings_container.get_children():
        if entry.kbm_bind_button.is_remapping or entry.gamepad_bind_button.is_remapping: return true
    return false

func cancel_remapping() -> bool:
    var active := remapping()
    for entry in bindings_container.get_children():
        if entry.kbm_bind_button.is_remapping: entry.kbm_bind_button.end_remapping()
        if entry.gamepad_bind_button.is_remapping: entry.gamepad_bind_button.end_remapping()
    return active
