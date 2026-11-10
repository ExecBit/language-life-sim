extends SceneTree
## Check room separation, ordinary door dimensions and NPC capsule clearance along authored routes.
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> bool:
	if not ok:
		push_error("DORMITORY_LAYOUT_FAIL: "+label)
		quit(1)
	return ok
func run() -> void:
	var stage := Node.new()
	root.add_child(stage)
	current_scene = stage
	var game = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	stage.add_child(game)
	game._start_new()
	game.automated = true
	var h = game.house
	var routes: Array = []
	for id in h.Layout.ROOMS:
		var data: Dictionary = h.Layout.ROOMS[id]
		var target: String = "room_door" if id == "bedroom" else "door_"+id
		var leaf = h.furniture[target]
		if not check(leaf.get_child(0).shape.size.z <= 1.0 and leaf.get_child(0).shape.size.y <= 2.15,"Door dimensions: "+id): return
		var source := Vector3(0,0,-13.2) if data.get("end_door",false) else Vector3(data.side*2.7,0,data.door_z)
		var points: Array[Vector3] = [source]
		points.append_array(h.route_points(source,Vector3(0,0,4)))
		routes.append(points)
	await create_timer(1.5).timeout
	var excluded: Array[RID] = [game.player.get_rid()]
	for npc in h.actors.values(): excluded.append(npc.get_rid())
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = excluded
	for points in routes:
		for i in range(1,points.size()):
			var count := ceili(points[i-1].distance_to(points[i])/0.15)
			for sample in range(count+1):
				var point: Vector3 = points[i-1].lerp(points[i],float(sample)/maxi(1,count))
				query.transform.origin = point+Vector3(0,0.85,0)
				var hits: Array = h.get_world_3d().direct_space_state.intersect_shape(query)
				if not check(hits.is_empty(),"NPC route obstructed at "+str(point)+": "+str(hits)): return
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-4,1,0),Vector3(-4,1,3))
	ray.exclude = excluded
	var wall: Dictionary = h.get_world_3d().direct_space_state.intersect_ray(ray)
	if not check(not wall.is_empty() and absf(wall.position.z-1.5) < 0.15,"Kitchen and shared room have a separating wall"): return
	var recovered: Vector3 = h.safe_player_position(Vector3(-4,0.9,1.5),game.player.get_rid())
	if not check(recovered.x == 0,"Old save inside new partition recovers to corridor"): return
	print("DORMITORY_LAYOUT_OK: four bedrooms, kitchen, shared room, bathroom, 90cm doors, NPC capsule routes")
	game.queue_free()
	await process_frame
	quit(0)
