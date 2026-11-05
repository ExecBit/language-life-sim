@tool
extends Object

# Palette scan: configured folders → placeable asset entries. Pure logic; the
# dock owns thumbnails (EditorResourcePreview is editor-only) and drag-drop.

const PLACEABLE_EXTENSIONS := ["tscn", "scn", "glb", "gltf", "fbx", "obj"]


# Entries: {path, name, category}. Category = first folder under the scan root
# (or the root's own basename for files sitting at its top level).
static func scan(dirs: PackedStringArray) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for dir in dirs:
		_scan_dir(dir.trim_suffix("/"), dir.trim_suffix("/"), entries)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["path"]) < String(b["path"]))
	return entries


static func _scan_dir(path: String, scan_root: String, entries: Array[Dictionary]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension().to_lower() in PLACEABLE_EXTENSIONS and not file.begins_with("."):
			entries.append({
				"path": path + "/" + file,
				"name": file.get_basename(),
				"category": _category_for(path, scan_root),
			})
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_scan_dir(path + "/" + sub, scan_root, entries)


static func _category_for(path: String, scan_root: String) -> String:
	if path == scan_root:
		return scan_root.get_file()  # files at the root: category = folder name
	var rel := path.substr(scan_root.length() + 1)
	return rel.split("/")[0]


static func categories(entries: Array[Dictionary]) -> PackedStringArray:
	var seen := {}
	var names := PackedStringArray()
	for entry in entries:
		var cat := String(entry["category"])
		if not seen.has(cat):
			seen[cat] = true
			names.append(cat)
	return names


static func filter(entries: Array[Dictionary], search: String, category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var needle := search.to_lower()
	for entry in entries:
		if category != "" and String(entry["category"]) != category:
			continue
		if needle != "" and not String(entry["name"]).to_lower().contains(needle):
			continue
		out.append(entry)
	return out
