extends "res://game/characters/motifect_visual.gd"

func _ready() -> void:
	super._ready()
	_load_clip("walk_forward")
	var walking := library.get_animation("walk_forward").duplicate(true) as Animation
	walking.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("walking", walking)
	# Astera's flared skirt needs extra clearance at the upper arms in idle.
	var idle := library.get_animation("standing")
	for track in idle.get_track_count():
		if idle.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var name := str(idle.track_get_path(track).get_subname(0))
		if name not in ["J_Bip_L_UpperArm", "J_Bip_R_UpperArm"]: continue
		var angle := deg_to_rad(18.0 if name == "J_Bip_L_UpperArm" else -18.0)
		var clearance := Quaternion(Vector3(0, 0, 1), angle)
		for key in idle.track_get_key_count(track):
			var rotation: Quaternion = idle.track_get_key_value(track, key)
			idle.track_set_key_value(track, key, (clearance * rotation).normalized())

func bone(canonical: String) -> String:
	return canonical
