extends SceneTree

func _init() -> void:
    var migration = preload("res://implementations/dormitory/game/save_migration.gd")
    var source_dir := "user://migration_fixture"
    DirAccess.make_dir_recursive_absolute(source_dir)
    var snapshots := {}
    for filename in migration.FILES:
        var destination := "user://".path_join(filename)
        snapshots[filename] = FileAccess.get_file_as_bytes(destination) if FileAccess.file_exists(destination) else null
        if FileAccess.file_exists(destination): DirAccess.remove_absolute(destination)
        var source := FileAccess.open(source_dir.path_join(filename), FileAccess.WRITE)
        source.store_string("old:" + filename)
        source.close()
    migration.import_previous(ProjectSettings.globalize_path(source_dir))
    for filename in migration.FILES:
        assert(FileAccess.get_file_as_string("user://".path_join(filename)) == "old:" + filename)
        var newer := FileAccess.open("user://".path_join(filename), FileAccess.WRITE)
        newer.store_string("newer")
        newer.close()
    migration.import_previous(ProjectSettings.globalize_path(source_dir))
    for filename in migration.FILES:
        var destination := "user://".path_join(filename)
        assert(FileAccess.get_file_as_string(destination) == "newer")
        assert(FileAccess.get_file_as_string(source_dir.path_join(filename)) == "old:" + filename)
        DirAccess.remove_absolute(source_dir.path_join(filename))
        if snapshots[filename] == null:
            DirAccess.remove_absolute(destination)
        else:
            var original := FileAccess.open(destination, FileAccess.WRITE)
            original.store_buffer(snapshots[filename])
            original.close()
    DirAccess.remove_absolute(source_dir)
    print("SAVE_MIGRATION_NONDESTRUCTIVE_PASS")
    quit()
