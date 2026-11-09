extends "res://game/characters/motifect_visual.gd"

const WALK = preload("res://game/prologue/walk.tres")

func _ready() -> void:
	super._ready()
	# Astera's flared skirt needs more clearance than the source rig's idle.
	# Edit the private animation copy, preserving the breathing loop.
	var idle := library.get_animation("standing")
	for track in idle.get_track_count():
		if idle.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var name := str(idle.track_get_path(track).get_subname(0))
		if name not in ["J_Bip_L_UpperArm","J_Bip_R_UpperArm"]: continue
		var angle := deg_to_rad(18.0 if name == "J_Bip_L_UpperArm" else -18.0)
		var clearance := Quaternion(Vector3(0,0,1),angle)
		for key in idle.track_get_key_count(track):
			var rotation: Quaternion = idle.track_get_key_value(track,key)
			idle.track_set_key_value(track,key,(clearance*rotation).normalized())
	var walk := WALK.duplicate(true) as Animation
	for track in walk.get_track_count():
		var canonical := str(walk.track_get_path(track).get_subname(0))
		walk.track_set_path(track,NodePath(skeleton_path+":"+canonical))
	library.add_animation("walking",walk)

func bone(canonical: String) -> String:
	return canonical
