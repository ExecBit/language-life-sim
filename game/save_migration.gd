extends RefCounted

const FILES := ["language_life_session_v5.json", "language_life_prologue_v4.json", "language_life_prologue_v3.json", "language_life_prologue_v2.json", "language_life_prologue_settings.cfg"]

static func import_previous(previous_directory: String = "") -> void:
    # Standard Godot per-user location used by the original Cogito project.
    var previous := previous_directory if not previous_directory.is_empty() else OS.get_data_dir().path_join("Godot/app_userdata/Cogito")
    for filename in FILES:
        var source := previous.path_join(filename)
        var target := "user://".path_join(filename)
        if not FileAccess.file_exists(target) and FileAccess.file_exists(source):
            var result := DirAccess.copy_absolute(source, ProjectSettings.globalize_path(target))
            if result != OK:
                push_warning("Could not import previous save: " + filename)
