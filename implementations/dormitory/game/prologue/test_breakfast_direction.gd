extends SceneTree
## Focused regression: a stale conversation/shelf heading must not orient cooking.
var game: Node3D
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> bool:
	if not value:
		push_error("BREAKFAST_DIRECTION_FAIL: "+label)
		quit(1)
	return value
func settle() -> void:
	for frame in 100:
		game.life._tick_breakfast_motion()
		await physics_frame
func run() -> void:
	var stage := Node.new()
	root.add_child(stage)
	current_scene = stage
	game = load("res://implementations/dormitory/game/prologue/prologue.tscn").instantiate()
	stage.add_child(game)
	game._start_new()
	game.automated = true
	game.state.day = 2
	game.state.items.room_key = "nightstand"
	game.state.ensure_cooking()
	game.state.index = game._step_index("f_arrival")
	game._enter_step(true)
	var lena = game.house.actors.lena
	for stale_heading in [PI,PI/2,-PI/2]:
		lena.heading = stale_heading
		lena.rotation.y = stale_heading
		lena.visual.stop()
		await settle()
		var to_counter: Vector3 = game.house.zones.breakfast_work-lena.position
		to_counter.y = 0
		if not check((-lena.global_basis.z).dot(to_counter.normalized()) > 0.99,"Working body faces counter"): return
		if not check(lena.visual.current == "a02_breakfast_routine","Routine resumes after turning"): return
	game.communication.reopen()
	game.life._tick_breakfast_motion()
	game.house.point("lena","bread")
	game.communication.close()
	game.life._tick_breakfast_motion()
	if not check(lena.visual.current == "emote_point_at_opponent","Do not interrupt explicit pointing"): return
	game.house.pulse_time = 0
	lena.visual.stop()
	await settle()
	if not check(absf(angle_difference(lena.rotation.y,0)) < 0.12,"Return from shelf to counter"): return
	# Verify the retargeted clip itself reaches toward the counter, not behind the actor.
	lena.visual.play("a02_breakfast_routine",true)
	lena.visual.animation_player.play("motifect/a02_breakfast_routine",0.0)
	lena.visual.animation_player.seek(1.0,true)
	await process_frame
	var sk = lena.visual.target_skeleton
	var hands: Vector3 = (sk.get_bone_global_pose(sk.find_bone("J_Bip_L_Hand")).origin+sk.get_bone_global_pose(sk.find_bone("J_Bip_R_Hand")).origin)*0.5
	var hips: Vector3 = sk.get_bone_global_pose(sk.find_bone("J_Bip_C_Hips")).origin
	if not check((hands-hips).z < -0.1,"Retargeted working hands extend forward"): return
	print("BREAKFAST_DIRECTION_OK: stale headings, dialogue return, pointing priority, retargeted hand direction")
	game.queue_free()
	await process_frame
	quit(0)
