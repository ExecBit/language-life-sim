extends Node3D

const ROOM_WIDTH := 16.0
const ROOM_DEPTH := 12.0
const ROOM_HEIGHT := 3.0
const LAYOUT_PATH := "res://layout.json"

var _placements_by_id: Dictionary = {}
var _root_camera: Camera3D


func _ready() -> void:
	var stage1 := OS.get_cmdline_user_args().has("--stage1")
	var stage2 := OS.get_cmdline_user_args().has("--stage2")
	var default_layout := "res://stage1_layout.json" if stage1 else ("res://stage2-A-layout.json" if stage2 else LAYOUT_PATH)
	var layout_path := _argument("layout", default_layout)
	if not layout_path.begins_with("res://"):
		layout_path = "res://" + layout_path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
	if not parsed is Dictionary or not parsed.has("placements"):
		push_error("Missing or invalid FittingPlacer layout JSON: %s" % LAYOUT_PATH)
		get_tree().quit(1)
		return

	if stage1 or stage2:
		_build_stage1_rooms(parsed)
	else:
		_build_room()
	for placement: Dictionary in parsed["placements"]:
		var packed := load(placement["assetPath"]) as PackedScene
		if packed == null:
			push_error("KayKit scene failed to load: %s" % placement["assetPath"])
			get_tree().quit(1)
			return
		var instance := packed.instantiate() as Node3D
		instance.name = placement["id"]
		var t: Array = placement["translation"]
		var r: Array = placement["rotation"]
		instance.position = Vector3(float(t[0]), float(t[1]), float(t[2]))
		instance.rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
		add_child(instance)
		_placements_by_id[placement["id"]] = placement

	_add_lighting()
	_root_camera = Camera3D.new()
	_root_camera.name = "PreviewCamera"
	_root_camera.current = true
	_root_camera.fov = 72.0
	add_child(_root_camera)
	if stage2:
		_select_stage2_view(_argument("view", "top"), parsed)
	elif stage1:
		_select_stage1_view(_argument("view", "top"), parsed)
	else:
		_select_view(_argument("view", "top"))

	await get_tree().process_frame
	await get_tree().process_frame
	var capture_path := _argument("capture", "")
	if not capture_path.is_empty():
		var absolute_path := ProjectSettings.globalize_path(capture_path)
		DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
		var err := get_viewport().get_texture().get_image().save_png(absolute_path)
		if err != OK:
			push_error("Could not save preview screenshot: %s (error %s)" % [absolute_path, err])
		else:
			print("CAPTURED ", absolute_path)
	get_tree().quit()


func _build_stage1_rooms(layout: Dictionary) -> void:
	var floor_material := _material(Color(0.29, 0.25, 0.2))
	var wall_material := _material(Color(0.48, 0.42, 0.33))
	var trim_material := _material(Color(0.22, 0.17, 0.12))
	var zones: Array = layout["zones"]
	var hall: Dictionary = zones[0]
	var kitchen: Dictionary = zones[1]
	var wall := 0.2
	for zone: Dictionary in zones:
		var center := Vector3(float(zone["originX"]), 0, float(zone["originZ"]))
		var width := float(zone["width"])
		var depth := float(zone["depth"])
		_add_box(zone["id"] + "Floor", center + Vector3(0, -0.12, 0), Vector3(width, 0.24, depth), floor_material)
		_add_box(zone["id"] + "North", center + Vector3(0, 1.5, depth / 2), Vector3(width, 3, wall), wall_material)
		_add_box(zone["id"] + "South", center + Vector3(0, 1.5, -depth / 2), Vector3(width, 3, wall), wall_material)
		if zone["id"] == "hall":
			_add_box("HallWest", center + Vector3(-width / 2, 1.5, 0), Vector3(wall, 3, depth), wall_material)
		else:
			_add_box("KitchenEast", center + Vector3(width / 2, 1.5, 0), Vector3(wall, 3, depth), wall_material)
	# Shared partition has two solid jamb spans and a header; the center remains a real doorway.
	var partition_x := (float(hall["originX"]) + float(hall["width"]) / 2 + float(kitchen["originX"]) - float(kitchen["width"]) / 2) / 2
	var opening := float(layout["doorWidth"])
	var half_depth: float = max(float(hall["depth"]), float(kitchen["depth"])) / 2.0
	var jamb_depth: float = (half_depth * 2.0 - opening) / 2.0
	_add_box("PartitionNorth", Vector3(partition_x, 1.5, opening / 2 + jamb_depth / 2), Vector3(wall, 3, jamb_depth), wall_material)
	_add_box("PartitionSouth", Vector3(partition_x, 1.5, -opening / 2 - jamb_depth / 2), Vector3(wall, 3, jamb_depth), wall_material)
	_add_box("DoorHeader", Vector3(partition_x, 2.8, 0), Vector3(wall, 0.4, opening), trim_material)


func _argument(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _select_view(view_name: String) -> void:
	if view_name == "top":
		_root_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_root_camera.size = 14.0
		_root_camera.position = Vector3(0.0, 18.0, 0.0)
		_root_camera.look_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
		return

	_root_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_root_camera.fov = 72.0
	var target := Vector3(0.0, 1.0, 0.0)
	var eye := Vector3(0.0, 1.65, -5.3)
	if view_name == "bar":
		var bar: Dictionary = _placements_by_id.get("bar_section_a_01", {})
		var p: Array = bar.get("translation", [0.0, 0.0, 0.0])
		var yaw := float(bar.get("rotation", [0.0, 0.0, 0.0])[1])
		var front := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
		target = Vector3(float(p[0]), 0.9, float(p[2]))
		eye = target + front * 4.2 + Vector3.UP * 0.75
	elif view_name == "kitchen":
		var counter: Dictionary = _placements_by_id.get("kitchen_counter_01", {})
		var p: Array = counter.get("translation", [0.0, 0.0, 0.0])
		var yaw := float(counter.get("rotation", [0.0, 0.0, 0.0])[1])
		var work_front := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
		target = Vector3(float(p[0]), 1.0, float(p[2]))
		eye = target + work_front * 7.0 + Vector3.UP * 0.65
	elif view_name == "dining":
		var table: Dictionary = _placements_by_id.get("dining_table_01", {})
		var p: Array = table.get("translation", [0.0, 0.0, 0.0])
		var yaw := float(table.get("rotation", [0.0, 0.0, 0.0])[1])
		var front := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
		target = Vector3(float(p[0]), 0.9, float(p[2]))
		eye = target + front * 4.6 + Vector3.UP * 0.75
	_root_camera.position = eye
	_root_camera.look_at(target, Vector3.UP)


func _select_stage1_view(view_name: String, layout: Dictionary) -> void:
	var zones: Array = layout["zones"]
	var hall: Dictionary = zones[0]
	var kitchen: Dictionary = zones[1]
	var center_x := (float(hall["originX"]) - float(hall["width"]) / 2 + float(kitchen["originX"]) + float(kitchen["width"]) / 2) / 2
	if view_name == "top":
		_root_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_root_camera.size = float(layout["totalWidth"]) + 2.0
		_root_camera.position = Vector3(center_x, 22.0, 0.0)
		_root_camera.look_at(Vector3(center_x, 0, 0), Vector3(0, 0, -1))
		return
	if view_name == "doorway":
		_root_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_root_camera.fov = 84.0
		var doorway_placements: Array = layout["placements"]
		var kitchen_target := Vector3.ZERO
		var kitchen_count := 0
		for placement: Dictionary in doorway_placements:
			if placement["zoneId"] == "kitchen":
				var p: Array = placement["translation"]
				kitchen_target += Vector3(float(p[0]), 1.0, float(p[2]))
				kitchen_count += 1
		kitchen_target /= max(1, kitchen_count)
		kitchen_target.x += 1.1
		# Hall side of the partition, aligned so the sightline passes through its clear opening.
		_root_camera.position = Vector3(float(hall["originX"]) + float(hall["width"]) / 2 - 3.0, 1.65, 1.5)
		_root_camera.look_at(kitchen_target, Vector3.UP)
		return
	else:
		_root_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_root_camera.fov = 72.0
		var placements: Array = layout["placements"]
		var kitchen_points: Array[Vector3] = []
		for placement: Dictionary in placements:
			if placement["zoneId"] == "kitchen":
				var p: Array = placement["translation"]
				kitchen_points.append(Vector3(float(p[0]), 1.0, float(p[2])))
		var target := Vector3.ZERO
		for point: Vector3 in kitchen_points: target += point
		target /= max(1, kitchen_points.size())
		# Favor the work line over the fridge so the eye-level view shows the separate room's function.
		target.x += 1.1
		# Eye-level inside the kitchen, in front of the solver-generated work line.
		_root_camera.position = Vector3(float(kitchen["originX"]) - 0.5, 1.65, 0.5)
		_root_camera.look_at(target, Vector3.UP)


func _select_stage2_view(view_name: String, layout: Dictionary) -> void:
	var hall: Dictionary = layout["zones"][0]
	var dining: Dictionary = layout["logicalZones"][0]
	var bar: Dictionary = layout["logicalZones"][1]
	if view_name == "top":
		var kitchen: Dictionary = layout["zones"][1]
		var left_edge := float(hall["originX"]) - float(hall["width"]) / 2.0
		var right_edge := float(kitchen["originX"]) + float(kitchen["width"]) / 2.0
		var center_x := (left_edge + right_edge) / 2.0
		_root_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_root_camera.size = max(float(layout["totalDepth"]), float(layout["totalWidth"]) / 1.72) + 2.0
		_root_camera.position = Vector3(center_x, 28.0, 0.0)
		_root_camera.look_at(Vector3(center_x, 0, 0), Vector3(0, 0, -1))
		return
	_root_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_root_camera.fov = 82.0
	var targets := _zone_asset_centers(layout["placements"])
	var target: Vector3
	var eye: Vector3
	if view_name == "hall_bar":
		target = targets.get("bar", Vector3(float(bar["originX"]), 1.0, float(bar["originZ"])))
		var bar_rotated := false
		for placement: Dictionary in layout["placements"]:
			if placement["zoneId"] == "bar" and String(placement["assetId"]).begins_with("bar_section_"):
				bar_rotated = absf(float(placement["rotation"][1])) > 3.0
				break
		if bar_rotated:
			eye = Vector3(float(bar["originX"]) - float(bar["width"]) / 2.0 - 2.5, 1.65, float(bar["originZ"]))
		else:
			eye = Vector3(float(bar["originX"]), 1.65, float(bar["originZ"]) - float(bar["depth"]) / 2.0 + 0.35)
	else:
		target = targets.get("dining", Vector3(float(dining["originX"]), 1.0, float(dining["originZ"])))
		var dining_east := float(dining["originX"]) + float(dining["width"]) / 2.0
		var dining_north := float(dining["originZ"]) + float(dining["depth"]) / 2.0
		var bar_south := float(bar["originZ"]) - float(bar["depth"]) / 2.0
		var open_strip_south: float = maxf(dining_north, bar_south)
		eye = Vector3(dining_east + 1.0, 1.65, open_strip_south - 0.8)
	_root_camera.position = eye
	_root_camera.look_at(target, Vector3.UP)


func _zone_asset_centers(placements: Array) -> Dictionary:
	var sums := {"dining": Vector3.ZERO, "bar": Vector3.ZERO}
	var counts := {"dining": 0, "bar": 0}
	for placement: Dictionary in placements:
		var zone_id: String = placement["zoneId"]
		var asset_id: String = placement["assetId"]
		if zone_id == "dining" and asset_id != "dining_chair":
			var dining_position: Array = placement["translation"]
			sums["dining"] += Vector3(float(dining_position[0]), 1.0, float(dining_position[2]))
			counts["dining"] += 1
		elif zone_id == "bar" and asset_id.begins_with("bar_section_"):
			var bar_position: Array = placement["translation"]
			sums["bar"] += Vector3(float(bar_position[0]), 1.0, float(bar_position[2]))
			counts["bar"] += 1
	for zone_id: String in ["dining", "bar"]:
		if counts[zone_id] > 0:
			sums[zone_id] /= counts[zone_id]
	return sums


func _build_room() -> void:
	var floor_material := _material(Color(0.29, 0.25, 0.2))
	var wall_material := _material(Color(0.48, 0.42, 0.33))
	var trim_material := _material(Color(0.22, 0.17, 0.12))
	_add_box("Floor", Vector3(0.0, -0.12, 0.0), Vector3(ROOM_WIDTH, 0.24, ROOM_DEPTH), floor_material)
	_add_box("NorthWall", Vector3(0.0, ROOM_HEIGHT / 2.0, ROOM_DEPTH / 2.0), Vector3(ROOM_WIDTH, ROOM_HEIGHT, 0.2), wall_material)
	_add_box("WestWall", Vector3(-ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0, 0.0), Vector3(0.2, ROOM_HEIGHT, ROOM_DEPTH), wall_material)
	_add_box("EastWall", Vector3(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0, 0.0), Vector3(0.2, ROOM_HEIGHT, ROOM_DEPTH), wall_material)
	var jamb := 0.6
	var side_width := ROOM_WIDTH / 2.0 - jamb
	_add_box("SouthWallLeft", Vector3(-jamb - side_width / 2.0, ROOM_HEIGHT / 2.0, -ROOM_DEPTH / 2.0), Vector3(side_width, ROOM_HEIGHT, 0.2), wall_material)
	_add_box("SouthWallRight", Vector3(jamb + side_width / 2.0, ROOM_HEIGHT / 2.0, -ROOM_DEPTH / 2.0), Vector3(side_width, ROOM_HEIGHT, 0.2), wall_material)
	_add_box("DoorHeader", Vector3(0.0, ROOM_HEIGHT - 0.3, -ROOM_DEPTH / 2.0), Vector3(jamb * 2.0, 0.6, 0.2), trim_material)
	_add_box("DoorLeftTrim", Vector3(-jamb, 1.35, -ROOM_DEPTH / 2.0), Vector3(0.08, 2.7, 0.16), trim_material)
	_add_box("DoorRightTrim", Vector3(jamb, 1.35, -ROOM_DEPTH / 2.0), Vector3(0.08, 2.7, 0.16), trim_material)


func _add_box(node_name: String, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	add_child(mesh_instance)


func _add_lighting() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.08, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.54, 0.48)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 1.6
	add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.7, 0.0)
	fill.omni_range = 13.0
	fill.light_energy = 1.0
	add_child(fill)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material
