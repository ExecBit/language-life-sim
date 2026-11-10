extends SceneTree
const Driver = preload("res://implementations/dormitory/game/characters/motifect_visual.gd")

func _init() -> void: call_deferred("run")

func run() -> void:
	var driver = Driver.new()
	root.add_child(driver)
	var animation: Animation = driver.library.get_animation("standing")
	assert(animation.loop_mode == Animation.LOOP_LINEAR and animation.length > 0.0)
	assert(driver.library.has_animation("idle_neutral"))
	assert(animation.get_track_count() > 0)
	for time in [0.0, animation.length * 0.25, animation.length * 0.5, animation.length * 0.75, animation.length]:
		driver.animation_player.play("motifect/standing", 0.0)
		driver.animation_player.seek(time, true)
		driver.animation_player.advance(0.0)
		await process_frame
		await process_frame
		assert(driver.target_skeleton.position.is_finite())
		assert(absf(driver.target_skeleton.position.y) < 0.005)
	driver.play("emote_thumbs_up")
	driver.animation_player.advance(30.0)
	await process_frame
	assert(driver.current == "standing")
	print("MOTIFECT_IDLE_TESTS_OK")
	quit()
