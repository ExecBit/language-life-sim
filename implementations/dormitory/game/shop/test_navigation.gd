extends SceneTree
func _init() -> void:
	call_deferred("run")

func walk(player, waypoint: Vector3) -> void:
	for i in 250:
		var offset: Vector3 = waypoint-player.position
		offset.y = 0
		if offset.length() < 0.08: return
		player.move_and_collide(offset.limit_length(0.1))
	assert(false,"Blocked shop route at "+str(player.position)+" heading to "+str(waypoint))

func run() -> void:
	var scene = load("res://game/shop/shop.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	await physics_frame
	for waypoint in [Vector3(-1,0.9,2.5),Vector3(-1,0.9,-2.3),Vector3(3.6,0.9,-2.3),Vector3(-1,0.9,-2.3),Vector3(-1,0.9,2.0),Vector3(2.8,0.9,2.0)]:
		walk(scene.player,scene.shopping.world.global_position+waypoint)
	scene.player.position = Vector3(44.5,0.9,2.5)
	await physics_frame
	scene.player.move_and_collide(Vector3(3,0,0))
	assert(scene.player.position.x < 44.9,"Passed through shop wall")
	print("SHOP_WALKABLE_AISLES_COUNTER_AND_WALLS_OK")
	scene.queue_free()
	await process_frame
	quit()
