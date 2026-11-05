@tool
extends Object

# Tiny per-project prefs (palette folders, custom test player, snap settings).
# user:// is per-project, so buyers' projects each keep their own — and we
# never write into res:// or ProjectSettings for mere preferences.

const PREFS_PATH := "user://level_builder_prefs.json"


static func load_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var f := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func save_prefs(prefs: Dictionary) -> void:
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Level Builder: couldn't open %s to save dock preferences (%s)." % [PREFS_PATH, error_string(FileAccess.get_open_error())])
		return
	var text := JSON.stringify(prefs, "\t")
	f.store_string(text)
	f.close()
	# Opening for write truncates first, so a failed write leaves an empty file
	# and the dock silently forgets its settings next time.
	var check := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if check == null or check.get_length() != text.to_utf8_buffer().size():
		push_warning("Level Builder: dock preferences at %s did not write fully; they may not persist." % PREFS_PATH)
	if check != null:
		check.close()


static func get_pref(key: String, fallback: Variant = null) -> Variant:
	return load_prefs().get(key, fallback)


static func set_pref(key: String, value: Variant) -> void:
	var prefs := load_prefs()
	prefs[key] = value
	save_prefs(prefs)
