extends RefCounted
## A small civilian idle authored on the animation DRIVER, before retargeting.
## Keeps the original VRM rest pose and the retarget algorithm unchanged.

static func install(visual: CharacterVisual) -> void:
	var skeleton := visual.rig_skeleton
	skeleton.reset_bone_poses()
	# Place the arms beside the torso with a small, natural elbow bend.
	for side in ["L", "R"]:
		var lateral := 0.10 if side == "L" else -0.10
		_align(skeleton, "J_Bip_%s_UpperArm" % side, "J_Bip_%s_LowerArm" % side, Vector3(lateral,-1,0.03))
		_align(skeleton, "J_Bip_%s_LowerArm" % side, "J_Bip_%s_Hand" % side, Vector3(lateral,-1,0.20))
	var animation := Animation.new()
	animation.length = 4.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var root := visual.animation_player.get_node(visual.animation_player.root_node)
	var skeleton_path := str(root.get_path_to(skeleton))
	for index in skeleton.get_bone_count():
		var bone := str(skeleton.get_bone_name(index))
		var rotation := skeleton.get_bone_pose_rotation(index)
		var position := skeleton.get_bone_rest(index).origin
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, NodePath(skeleton_path + ":" + bone))
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, NodePath(skeleton_path + ":" + bone))
		for time in [0.0, 1.0, 2.0, 3.0, 4.0]:
			var breath := sin(time * PI / 2.0)
			var pose := rotation
			var offset := Vector3.ZERO
			if bone == "J_Bip_C_Chest": pose = rotation * Quaternion(Vector3.RIGHT, breath * 0.006)
			if bone == "J_Bip_C_Hips": offset.y = breath * 0.002
			animation.rotation_track_insert_key(rotation_track, time, pose)
			animation.position_track_insert_key(position_track, time, position + offset)
	var library := AnimationLibrary.new()
	library.add_animation("Relaxed", animation)
	visual.animation_player.add_animation_library("lena", library)

static func _align(skeleton: Skeleton3D, name: String, child: String, desired: Vector3) -> void:
	var index := skeleton.find_bone(name)
	var child_index := skeleton.find_bone(child)
	assert(index >= 0 and child_index >= 0)
	var pose := skeleton.get_bone_global_pose(index)
	var direction := skeleton.get_bone_global_pose(child_index).origin - pose.origin
	var corrected := Basis(Quaternion(direction.normalized(), desired.normalized())) * pose.basis
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * corrected).get_rotation_quaternion())
