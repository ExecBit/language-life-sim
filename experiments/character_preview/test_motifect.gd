extends SceneTree
const Actor = preload("res://game/characters/lena_motifect.gd")
const Catalog = preload("res://game/characters/motifect_catalog.gd")

func _init() -> void: call_deferred("run")

func run() -> void:
	var actor = Actor.new()
	root.add_child(actor)
	assert(Catalog.SCENES.size() == 115)
	assert(Catalog.PACKS["Daily Life"].size() == 40)
	assert(Catalog.PACKS["Emotes & Social"].size() == 30)
	assert(Catalog.PACKS["Locomotion"].size() == 45)
	var identifiers := {}
	for pack in Catalog.PACKS.values():
		for identifier in pack:
			assert(Catalog.SCENES.has(identifier) and not identifiers.has(identifier))
			identifiers[identifier] = true
	var driver = actor.visual
	assert(actor.hand_attachment.bone_idx >= 0)
	var lengths := []
	for index in driver.target_skeleton.get_bone_count():
		lengths.append(driver.target_skeleton.get_bone_rest(index).origin.length())
	for name in Catalog.SCENES:
		actor.play_motion(name)
		var animation: Animation = driver.library.get_animation(name)
		assert(animation.length > 0 and animation.get_track_count() > 0)
		# Sample each imported clip without blending from the previous one.
		driver.animation_player.play("motifect/" + name, 0.0)
		driver.animation_player.seek(animation.length * 0.5, true)
		driver.animation_player.advance(0.0)
		await process_frame
		await process_frame
		for index in driver.target_skeleton.get_bone_count():
			var pose: Transform3D = driver.target_skeleton.get_bone_global_pose(index)
			assert(pose.is_finite())
			assert(is_equal_approx(driver.target_skeleton.get_bone_rest(index).origin.length(), lengths[index]))
		assert(driver.target_skeleton.position.is_finite())
		print("MOTIFECT_CLIP_OK ", name)
	actor.stop_motion()
	assert(driver.current == "standing")
	actor.play_motion("wave_hello")
	driver.animation_player.advance(30.0)
	await process_frame
	assert(driver.current == "standing")
	print("MOTIFECT_ALL_115_OK")
	quit()
