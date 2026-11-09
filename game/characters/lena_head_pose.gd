extends SkeletonModifier3D

var pitch := 0.0
var yaw := 0.0
var head_index := -1

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if head_index < 0: return
	var rest := skeleton.get_bone_rest(head_index).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(head_index, rest * Quaternion.from_euler(Vector3(pitch, yaw, 0)))
