extends RefCounted

## Imports the existing FittingPlacer output into the playable room. No solver runs in-game.
static func install(game: Node3D, content: Lex01Content) -> bool:
	var path := String(content.room.get("generated_layout", "res://data/room/tavern_generated.json"))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.has_all(["rooms", "placements", "doors", "publicEntrance"]):
		push_error("Invalid generated tavern: " + path)
		return false
	var layout: Dictionary = parsed
	var entries: Array = []
	var aliases := {"dining_dining_table_01": "guest_table_1", "kitchen_kitchen_counter_01": "service_counter", "kitchen_kitchen_fridge_01": "kitchen_fridge"}
	var by_id: Dictionary = {}
	for placement: Dictionary in layout["placements"]:
		var filename: String = String(placement["assetPath"]).get_file()
		var model := "res://assets/kaykit/items/" + filename
		if not ResourceLoader.exists(model):
			model = "res://assets/kaykit/furniture/" + filename
		if not ResourceLoader.exists(model):
			push_error("Generated tavern asset missing: " + model)
			return false
		var rotation: Array = placement["rotation"]
		var entry := {"model": model, "id": aliases.get(placement["id"], placement["id"]), "position": placement["translation"], "rotation_deg": [rad_to_deg(rotation[0]), rad_to_deg(rotation[1]), rad_to_deg(rotation[2])], "ground": false, "solid": String(placement["assetId"]).contains("counter") or String(placement["assetId"]).begins_with("bar_section")}
		entries.append(entry)
		by_id[entry["id"]] = entry
	content.room["interior"] = entries
	# Preserve stable station ids while binding them to the generated meshes.
	var old_table := "res://assets/kaykit/items/table_round_A_small.gltf"
	var new_table := "res://assets/kaykit/items/table_round_A.gltf"
	for scenario: Dictionary in content.scenarios:
		_replace_path(scenario, old_table, new_table)
	for lemma: Dictionary in content.lemmas.values():
		_replace_path(lemma, old_table, new_table)
	content.room["placement_slots"]["on_table"]["anchor"] = new_table
	for slot: Dictionary in content.room["placement_slots"].values():
		if not slot.has("anchor_id"): continue
		var entry: Dictionary = by_id[slot["anchor_id"]]
		content.room["anchors"][slot["anchor"]] = {"default": entry["position"], "room": entry["position"], "kitchen": entry["position"]}
	var rooms: Array = layout["rooms"]
	var hall: Dictionary = rooms[0]
	var entrance_x := float(layout["publicEntrance"]["centerX"])
	var entrance_z := float(hall["originZ"]) - float(hall["depth"]) / 2
	for context: String in ["default", "room", "kitchen"]:
		content.room["cameras"][context] = {"position": [entrance_x, 0, entrance_z + 1.5], "rotation_deg": [-6, 180, 0]}
	content.room["hold"]["tray_position"] = [entrance_x + 1, 0.85, entrance_z + 2]
	var kitchen: Dictionary = rooms[1]
	content.room["npcs"]["mage"]["position"] = [float(kitchen["originX"]) + float(kitchen["width"]) / 2 - 1.5, 0, -1.7]
	var bar: Dictionary = by_id["bar_bar_section_a_01"]
	content.room["npcs"]["knight"]["position"] = [float(bar["position"][0]) - 2.75, 0, float(bar["position"][2])]
	var table: Dictionary = by_id["guest_table_1"]
	content.room["npcs"]["gast"]["position"] = [float(table["position"][0]) - 3.0, 0, float(table["position"][2])]
	# Remove the old compact shell; retain its body so existing player/probe references work.
	for name: String in ["Floor", "Ceiling"]:
		var old := game.get_node(name)
		game.remove_child(old)
		old.queue_free()
	var shell: StaticBody3D = game.get_node("RoomShell")
	for old: Node in shell.get_children():
		shell.remove_child(old)
		old.queue_free()
	for room: Dictionary in rooms:
		var x := float(room["originX"])
		var z := float(room["originZ"])
		var w := float(room["width"])
		var d := float(room["depth"])
		_box(game, shell, Vector3(x, -0.12, z), Vector3(w, 0.24, d), true)
		_box(game, shell, Vector3(x, 1.5, z + d / 2 + 0.1), Vector3(w, 3, 0.2))
		if room["id"] != "hall":
			_box(game, shell, Vector3(x, 1.5, z - d / 2 - 0.1), Vector3(w, 3, 0.2))
	var left := float(hall["originX"]) - float(hall["width"]) / 2
	var right := float(hall["originX"]) + float(hall["width"]) / 2
	var half_open := float(layout["publicEntrance"]["width"]) / 2
	_box(game, shell, Vector3((left + entrance_x - half_open) / 2, 1.5, entrance_z - 0.1), Vector3(entrance_x - half_open - left, 3, 0.2))
	_box(game, shell, Vector3((right + entrance_x + half_open) / 2, 1.5, entrance_z - 0.1), Vector3(right - entrance_x - half_open, 3, 0.2))
	_box(game, shell, Vector3(entrance_x, 2.8, entrance_z - 0.1), Vector3(half_open * 2, 0.4, 0.2))
	# Bound the entrance outside, since this slice has no exterior.
	_box(game, shell, Vector3(entrance_x, -0.12, entrance_z - 0.6), Vector3(half_open * 2, 0.24, 1.2), true)
	_box(game, shell, Vector3(entrance_x, 1.5, entrance_z - 1.2), Vector3(half_open * 2, 3, 0.2))
	_box(game, shell, Vector3(entrance_x - half_open - 0.1, 1.5, entrance_z - 0.6), Vector3(0.2, 3, 1.2))
	_box(game, shell, Vector3(entrance_x + half_open + 0.1, 1.5, entrance_z - 0.6), Vector3(0.2, 3, 1.2))
	_box(game, shell, Vector3(left - 0.1, 1.5, 0), Vector3(0.2, 3, hall["depth"]))
	var store: Dictionary = rooms[2]
	_box(game, shell, Vector3(float(store["originX"]) + float(store["width"]) / 2 + 0.1, 1.5, 0), Vector3(0.2, 3, store["depth"]))
	for i: int in range(2):
		var room: Dictionary = rooms[i]
		var x := float(room["originX"]) + float(room["width"]) / 2
		var half := maxf(room["depth"], rooms[i + 1]["depth"]) / 2
		var dz := float(layout["doors"][i]["centerZ"])
		var opening := float(layout["doors"][i]["width"])
		var low := dz - opening / 2
		var high := dz + opening / 2
		_box(game, shell, Vector3(x, 1.5, (-half + low) / 2), Vector3(0.2, 3, low + half))
		_box(game, shell, Vector3(x, 1.5, (half + high) / 2), Vector3(0.2, 3, half - high))
		_box(game, shell, Vector3(x, 2.8, dz), Vector3(0.2, 0.4, opening))
	print("GENERATED_TAVERN layout=%s rooms=%d furniture=%d" % [path, rooms.size(), entries.size()])
	return true


static func _replace_path(value: Variant, old: String, replacement: String) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if value[key] is String and value[key] == old: value[key] = replacement
			else: _replace_path(value[key], old, replacement)
	elif value is Array:
		for item: Variant in value: _replace_path(item, old, replacement)


static func _box(game: Node3D, shell: StaticBody3D, at: Vector3, size: Vector3, floor: bool = false) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.29, 0.25, 0.2) if floor else Color(0.48, 0.42, 0.33)
	visual.material_override = material
	game.add_child(visual)
	visual.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	shell.add_child(collider)
	collider.position = at
