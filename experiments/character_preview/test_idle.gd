extends SceneTree
const Driver = preload("res://game/characters/motifect_visual.gd")

func _init() -> void: call_deferred("run")

func run() -> void:
	var driver = Driver.new()
	root.add_child(driver)
	var animation: Animation = driver.library.get_animation("standing")
	assert(animation.loop_mode == Animation.LOOP_LINEAR and animation.length >= 4.0)
	var breath_track := -1
	for track in animation.get_track_count():
		var first: Variant = animation.track_get_key_value(track, 0)
		var last: Variant = animation.track_get_key_value(track, animation.track_get_key_count(track)-1)
		if first is Quaternion: assert(first.is_equal_approx(last))
		elif first is Vector3: assert(first.is_equal_approx(last))
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D and str(animation.track_get_path(track)).ends_with(":J_Bip_C_Chest"):
			breath_track = track
	assert(breath_track >= 0)
	assert(animation.rotation_track_interpolate(breath_track,1.25).angle_to(animation.rotation_track_interpolate(breath_track,3.75)) > 0.02)
	for time in [0.0,1.25,2.5,3.75,5.0]:
		driver.animation_player.play("motifect/standing",0.0)
		driver.animation_player.seek(time, true)
		driver.animation_player.advance(0.0)
		await process_frame
		await process_frame
		var skeleton: Skeleton3D = driver.target_skeleton
		for side in ["LEFT", "RIGHT"]:
			var shoulder := SemanticBoneResolver.find(skeleton, StringName(side + "_UPPER_ARM"))
			var elbow := SemanticBoneResolver.find(skeleton, StringName(side + "_LOWER_ARM"))
			var wrist := SemanticBoneResolver.find(skeleton, StringName(side + "_HAND"))
			var a := skeleton.get_bone_global_pose(shoulder).origin
			var b := skeleton.get_bone_global_pose(elbow).origin
			var c := skeleton.get_bone_global_pose(wrist).origin
			assert(c.y < a.y - 0.35 and b.y < a.y - 0.15)
			assert(c.is_finite())
		assert(absf(skeleton.position.y) < 0.005)
	driver.play("emote_thumbs_up")
	driver.animation_player.advance(30.0)
	await process_frame
	assert(driver.current == "standing")
	print("CALM_IDLE_TESTS_OK")
	quit()
