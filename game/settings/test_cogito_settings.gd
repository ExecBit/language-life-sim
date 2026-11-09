extends SceneTree

var game_config
var scene
var checks := 0
var failures := 0

func _init() -> void:
    call_deferred("run")

func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error(message)

func key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = true
    return event

func run() -> void:
    game_config = root.get_node("CogitoGameConfig")
    scene = load("res://game/prologue/prologue.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    await process_frame
    await process_frame
    var panel = scene.ui.settings
    var options = panel.options
    check(scene.menu_active and not panel.visible, "Settings start closed")
    scene._command("settings")
    check(panel.visible and not scene.ui.menu.visible and paused, "Open from main menu without unpausing")
    check(options.tab_container.get_tab_count() == 4, "Reuse all four Cogito tabs")
    check(options.windowed_resolution_option_button.item_count == game_config.RESOLUTION_DICTIONARY.size(), "Expose Cogito resolutions")
    check(options.bindings_container.get_child_count() == options.ACTIONS.size(), "Bindings use current game actions")
    options.invert_y_check_button.button_pressed = false
    options.toggle_crouching_check_button.button_pressed = true
    options.mouse_sens_slider.value = 0.4
    options.gp_look_sens_slider.value = 3.0
    options.headbob_option_button.select(2)
    options.headbob_option_button.item_selected.emit(2)
    options.vsync_check_button.button_pressed = false
    options.anti_aliasing_3d_option_button.select(1)
    options.anti_aliasing_3d_option_button.item_selected.emit(1)
    options.sfx_volume_slider.hslider.value = 0.3
    options.music_volume_slider.hslider.value = 0.5
    var resolution: int = game_config.RESOLUTION_DICTIONARY.keys().find("1280x720 (16:9)")
    options.windowed_resolution_option_button.select(resolution)
    options.windowed_resolution_option_button.item_selected.emit(resolution)
    await create_timer(0.3).timeout
    options.get_node("%ApplyChanges").pressed.emit()
    check(panel.visible, "Apply keeps settings open")
    check(not scene.player.INVERT_Y_AXIS and scene.player.TOGGLE_CROUCH, "Saved invert and crouch flags apply independently to player")
    check(is_equal_approx(scene.player.MOUSE_SENS, 0.4), "Sensitivity reaches active player")
    check(scene.player.HEADBOBBLE == 7 and scene.player.JOY_H_SENS == 3, "Headbob and gamepad sensitivity reach player")
    var config := ConfigFile.new()
    check(config.load(OptionsConstants.config_file_name) == OK, "Cogito options saved")
    check(not config.get_value("Options", "invert_vertical_axis"), "Inversion persisted")
    check(config.get_value("Options", "toggle_crouching"), "Crouch persisted separately")
    check(config.get_value("Options", "resolution_index") == resolution, "Resolution persisted")
    check(not config.get_value("Options", "vsync") and config.get_value("Options", "msaa_3d") == 1, "Graphics persisted")
    check(is_equal_approx(config.get_value("Options", "sfx_volume"), 0.3), "Sound volume persisted")
    check(is_equal_approx(config.get_value("Options", "music_volume"), 0.5), "Music volume persisted")
    if DisplayServer.get_name() != "headless":
        check(root.size == Vector2i(1280,720), "Actual game window uses selected resolution")
        options.tab_container.current_tab = 1
        await create_timer(0.3).timeout
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("user://cogito_settings_graphics.png")
        options.tab_container.current_tab = 0
        await create_timer(0.3).timeout
        await RenderingServer.frame_post_draw
        root.get_texture().get_image().save_png("user://cogito_settings_gameplay.png")
    var bind = options.bindings_container.get_child(0).kbm_bind_button
    bind.button_pressed = true
    scene._input_event(key(KEY_ESCAPE))
    check(panel.visible and not bind.is_remapping, "Escape cancels a binding capture before closing")
    scene._input_event(key(KEY_ESCAPE))
    check(not panel.visible and scene.ui.menu.visible and paused, "Escape returns to main menu")
    scene._start_new()
    scene._set_pause(true)
    scene._command("settings")
    var position_before: Vector3 = scene.player.global_position
    Input.action_press("forward")
    for i in 4: await physics_frame
    Input.action_release("forward")
    check(scene.player.global_position.is_equal_approx(position_before), "World remains paused while editing settings")
    scene._command("settings_back")
    check(scene.paused and scene.ui.pause_panel.visible and paused, "Back returns to pause, not gameplay")
    scene._set_pause(false)
    scene.player.head.rotation.x = 0
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(0, 20)
    scene._input_event(motion)
    var normal_pitch: float = scene.player.head.rotation.x
    scene._set_pause(true)
    scene._command("settings")
    options.invert_y_check_button.button_pressed = true
    scene._command("settings_back")
    scene._set_pause(false)
    scene.player.head.rotation.x = 0
    scene._input_event(motion)
    check(normal_pitch * scene.player.head.rotation.x < 0, "Inversion reverses actual camera motion")
    options.toggle_crouching_check_button.button_pressed = false
    options._on_apply_changes_pressed()
    game_config.load_options()
    check(game_config.invert_y and not game_config.toggle_crouching, "Reload preserves independent inverse/crouch values")
    var rebound := key(KEY_UP)
    root.get_node("InputHelper").set_keyboard_input_for_action("forward", rebound, false)
    options._on_apply_changes_pressed()
    root.remove_child(scene)
    scene.free()
    await process_frame
    scene = load("res://game/prologue/prologue.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    await process_frame
    check(scene.player.INVERT_Y_AXIS and not scene.player.TOGGLE_CROUCH, "New scene restores saved player settings")
    check(InputMap.event_is_action(rebound, "forward"), "Rebound movement restores in new scene")
    check(is_equal_approx(scene.player.MOUSE_SENS, 0.4), "New scene does not overwrite Cogito sensitivity with legacy settings")
    print("COGITO_SETTINGS: ", checks, " checks, ", failures, " failures")
    if failures == 0: print("COGITO_GAME_SETTINGS_PASS")
    scene.queue_free()
    paused = false
    await process_frame
    quit(1 if failures else 0)
