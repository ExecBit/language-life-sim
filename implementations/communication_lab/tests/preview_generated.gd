extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var room = load("res://implementations/communication_lab/communication_lab.tscn").instantiate()
	root.add_child(room)
	room.player.is_movement_paused = true
	var camera := Camera3D.new()
	room.add_child(camera)
	camera.position = Vector3(0, 1.0, 1.0)
	camera.look_at(Vector3(0, 0.85, -2))
	camera.current = true
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://implementations/communication_lab/animations/generated/manifest.json"))
	for job in jobs:
		var path := "res://implementations/communication_lab/animations/generated/%s_%s.glb" % [job.key, job.job_id]
		if not ResourceLoader.exists(path): continue
		room.astera_visual.play_generated(job.key, path)
		for moment in [0.3, 1.5, 3.0]:
			room.astera_visual.animation_player.seek(moment, true)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/motion_%s_%s.png" % [job.key, moment])
		var length: float = room.astera_visual.library.get_animation(job.key).length
		room.astera_visual.animation_player.seek(length - 0.01, true)
		room.astera_visual.animation_player.advance(0.1)
		await process_frame
		assert(room.astera_visual.active_animation_id == "standing")
		print("MOTION_PREVIEW ", job.key, " length=", length, " RETURN_TO_IDLE PASS")
	quit()
