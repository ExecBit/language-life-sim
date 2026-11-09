extends SceneTree
func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://game/prologue/prologue.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.automated = true
	scene._start_new()
	await create_timer(0.3).timeout
	var actor = scene.house.actors.lena
	var origin: Vector3 = actor.position
	actor.go(Vector3(-3.8,0,-1))
	actor.face(Vector3(0,0,0))
	actor.gesture("emote_point_at_opponent")
	assert(actor.walking and actor.visual.current == "walking")
	var first := Quaternion.IDENTITY
	var leg: int = actor.visual.target_skeleton.find_bone("J_Bip_L_UpperLeg")
	var previous: Vector3 = actor.position
	var elapsed := 0.0
	var changed := false
	while actor.walking:
		await process_frame
		var delta := float(root.get_process_delta_time())
		elapsed += delta
		assert(actor.position.distance_to(previous) <= maxf(0.06,delta*1.15+0.04),"Movement jumped")
		previous = actor.position
		if elapsed < 0.1: first = actor.visual.target_skeleton.get_bone_pose_rotation(leg)
		if elapsed > 0.4 and elapsed < 0.8:
			changed = changed or first.angle_to(actor.visual.target_skeleton.get_bone_pose_rotation(leg)) > 0.08
		if elapsed > 20: assert(false,"Route did not finish")
	assert(elapsed > 6.9 and elapsed < 7.8,"Incorrect walking duration "+str(elapsed))
	assert(changed,"Leg did not animate")
	assert(actor.position.distance_to(Vector3(-3.8,0,-1)) < 0.01)
	assert(actor.visual.current == "emote_point_at_opponent","Queued gesture missing")
	actor.go(Vector3(3.2,0,-1))
	await create_timer(0.4).timeout
	await get_tree_pause_test(actor)
	await create_timer(0.3).timeout
	assert(actor.walking and actor.visual.current == "walking")
	actor.idle()
	assert(not actor.walking and actor.visual.current == "standing")
	print("PROLOGUE_WALK_OK duration=",elapsed," leg_motion=",changed)
	scene.queue_free()
	await process_frame
	quit()

func get_tree_pause_test(actor) -> void:
	# The scene's existing pause stops both path tween and animation processing.
	paused = true
	var frozen: Vector3 = actor.position
	await create_timer(0.2,true).timeout
	assert(actor.position == frozen)
	paused = false
