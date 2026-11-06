extends SceneTree
var game: Node3D
var rooms: Array
var failures := 0
const STEP := 0.2
var free: Dictionary = {}
var parents: Dictionary = {}
func _initialize() -> void:
	call_deferred("check")
func check() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local"))
	game = load("res://scenes/main.tscn").instantiate()
	game.set_meta("integration_probe", true)
	root.add_child(game)
	await process_frame
	await physics_frame
	game.set_physics_process(false)
	game.player.set_active(true)
	rooms = JSON.parse_string(FileAccess.get_file_as_string("res://data/room/tavern_generated.json"))["rooms"]
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [game.player.get_rid()]
	for x: int in range(-85, 86):
		for z: int in range(-51, 52):
			var point := Vector3(x * STEP, 0.9, z * STEP)
			var inside := false
			for room: Dictionary in rooms:
				if absf(point.x - room["originX"]) <= room["width"] / 2 and absf(point.z - room["originZ"]) <= room["depth"] / 2: inside = true
			if not inside: continue
			query.transform = Transform3D(Basis.IDENTITY, point)
			if game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): free[Vector2i(x,z)] = true
	var start := Vector2i(-35,-44)
	flood(start)
	var destinations := {"hall": Vector2i(-15,-25), "kitchen": Vector2i(47,-10), "storeroom": Vector2i(65,0)}
	for label: String in destinations:
		var target: Vector2i = destinations[label]
		var reachable := parents.has(target)
		print("ROUTE %s reachable=%s" % [label, reachable])
		if not reachable: failures += 1
		if reachable:
			var path: Array[Vector2i] = [target]
			while path.back() != start: path.append(parents[path.back()])
			path.reverse()
			game.player.global_position = Vector3(start.x * STEP,0,start.y * STEP)
			# Walk only the corners of the validated route, through the actual player controller.
			for i: int in range(1, path.size()):
				if i < path.size()-1 and path[i]-path[i-1] == path[i+1]-path[i]: continue
				var point := Vector3(path[i].x * STEP, 0, path[i].y * STEP)
				var result: Dictionary = await game.player.walk_to(point, 0.08, 700)
				if not result.get("arrived",false):
					print("WALK FAIL ",label," ",point," ",result)
					failures += 1
					break
			print("WALK ", label, " final=",game.player.global_position)
	# A closed service doorway must disconnect the kitchen and storeroom.
	for cell: Vector2i in free.keys():
		if absf(cell.x * STEP - 3.07095) < 0.6 and absf(cell.y * STEP + 2.9) < 1.1: free.erase(cell)
	flood(start)
	var negative := not parents.has(destinations["kitchen"]) and not parents.has(destinations["storeroom"])
	print("BLOCKED_DOOR_NEGATIVE ",negative)
	if not negative: failures += 1
	# Exercise the real E pickup/delivery path at the generated stations.
	game.current_scenario = game.content.scenarios.filter(func(s): return s["id"] == "t02")[0]
	game.restage_same_scenario()
	game.close_onboarding()
	game.player.global_position = Vector3(8, 0, 0.4)
	await physics_frame
	game.probe_face(String(game.current_scenario["correct_option_id"]))
	var pickup: Dictionary = game.probe_press_interact()
	print("GENERATED_PICKUP held=", pickup["held"])
	if game.builder.held_option_id() != String(game.current_scenario["correct_option_id"]): failures += 1
	game.player.global_position = Vector3(-8, 0, -6.4)
	await physics_frame
	game.probe_face_point(game._delivery_target_point())
	game.probe_press_interact()
	print("GENERATED_DELIVERY phase=",game.phase)
	if game.phase != "solved": failures += 1
	game.hud.visible = false
	for view: Dictionary in [{"name":"entrance","at":Vector3(-7,1.6,-8.7),"target":Vector3(-7,1.2,0)}, {"name":"bar","at":Vector3(-3,1.6,7),"target":Vector3(1,1,2)}, {"name":"kitchen","at":Vector3(8,1.6,-3),"target":Vector3(5,1,0)}, {"name":"storeroom","at":Vector3(12,1.6,0),"target":Vector3(15,1,1)}]:
		game.player.camera.global_position = view["at"]
		game.player.camera.look_at(view["target"])
		await process_frame
		await process_frame
		if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("res://.local/"+view["name"]+".png")
	print("GENERATED_INTEGRATION failures=",failures)
	quit(0 if failures == 0 else 1)
func flood(start: Vector2i) -> void:
	parents = {start:start}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next := cell+direction
			if free.has(next) and not parents.has(next):
				parents[next] = cell
				queue.append(next)


