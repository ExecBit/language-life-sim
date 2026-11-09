extends Node3D
signal motion_finished(name: String)

const Catalog = preload("res://game/characters/motifect_catalog.gd")
const Mirror = preload("res://game/characters/MirrorRetargetModifier3D.gd")
const PRIVATE_MODEL := "res://assets/characters/private/astera.vrm"
const FALLBACK_MODEL := "res://assets/characters/fallback.vrm"

func model_resource() -> PackedScene:
	return load(PRIVATE_MODEL if ResourceLoader.exists(PRIVATE_MODEL) else FALLBACK_MODEL) as PackedScene
const CALM_IDLE = preload("res://game/characters/calm_idle.tres")
const MAP := {
	"Hips": "J_Bip_C_Hips", "Spine1": "J_Bip_C_Spine", "Spine2": "J_Bip_C_Chest",
	"Chest": "J_Bip_C_UpperChest", "Neck2": "J_Bip_C_Neck", "Head": "J_Bip_C_Head",
	"LeftShoulder": "J_Bip_L_Shoulder", "LeftArm": "J_Bip_L_UpperArm", "LeftForeArm": "J_Bip_L_LowerArm", "LeftHand": "J_Bip_L_Hand",
	"RightShoulder": "J_Bip_R_Shoulder", "RightArm": "J_Bip_R_UpperArm", "RightForeArm": "J_Bip_R_LowerArm", "RightHand": "J_Bip_R_Hand",
	"LeftLeg": "J_Bip_L_UpperLeg", "LeftShin": "J_Bip_L_LowerLeg", "LeftFoot": "J_Bip_L_Foot", "LeftToeBase": "J_Bip_L_ToeBase",
	"RightLeg": "J_Bip_R_UpperLeg", "RightShin": "J_Bip_R_LowerLeg", "RightFoot": "J_Bip_R_Foot", "RightToeBase": "J_Bip_R_ToeBase",
}
var rig_skeleton: Skeleton3D
var target_skeleton: Skeleton3D
var animation_player: AnimationPlayer
var library := AnimationLibrary.new()
var current := "standing"
var source_hip_height := 1.0
var target_hip_height := 1.0
var skeleton_path := ""

func _ready() -> void:
	var driver: Node3D = Catalog.SCENES.drink_from_cup.instantiate()
	add_child(driver)
	rig_skeleton = driver.find_children("*", "Skeleton3D", true, false)[0]
	animation_player = driver.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton_path = str(animation_player.get_node(animation_player.root_node).get_path_to(rig_skeleton))
	for i in rig_skeleton.get_bone_count():
		var old := str(rig_skeleton.get_bone_name(i))
		rig_skeleton.set_bone_name(i, _canonical(old))
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("motifect", library)
	var model: Node3D = model_resource().instantiate()
	target_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var modifier := Mirror.new()
	modifier.name = "MotifectRetarget"
	modifier.bone_pairs = SemanticBoneResolver.build_retarget_pairs(target_skeleton, SemanticBoneResolver.SEMANTIC_ORDER)
	# Finger chains have the canonical VRoid names after import.
	for i in rig_skeleton.get_bone_count():
		var bone := str(rig_skeleton.get_bone_name(i))
		if target_skeleton.find_bone(bone) >= 0: modifier.bone_pairs[bone] = bone
	rig_skeleton.add_child(modifier)
	target_skeleton.owner = null
	target_skeleton.get_parent().remove_child(target_skeleton)
	modifier.add_child(target_skeleton)
	model.free()
	var target_hips := SemanticBoneResolver.find(target_skeleton, SemanticBoneResolver.HIPS)
	target_hip_height = target_skeleton.get_bone_global_rest(target_hips).origin.y
	_load_clip("wave_hello")
	var reference := library.get_animation("wave_hello")
	# Use the reference only to calibrate root height, never as the idle pose.
	for track in reference.get_track_count():
		var first: Variant = reference.track_get_key_value(track, 0)
		if reference.track_get_path(track).get_subname(0) == "J_Bip_C_Hips" and reference.track_get_type(track) == Animation.TYPE_POSITION_3D:
			source_hip_height = maxf(0.01, first.y)
	var standing := CALM_IDLE.duplicate(true) as Animation
	for track in standing.get_track_count():
		var bone := str(standing.track_get_path(track).get_subname(0))
		standing.track_set_path(track, NodePath(skeleton_path + ":" + bone))
	library.add_animation("standing", standing)
	animation_player.animation_finished.connect(_finished)
	play("standing")
	print("MOTIFECT_READY: ", Catalog.SCENES.size(), " clips; ", modifier.bone_pairs.size(), " bone pairs")

func _canonical(bone: String) -> String:
	if MAP.has(bone): return MAP[bone]
	for side in ["Left", "Right"]:
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for joint in [1,2,3]:
				if bone == "%sHand%s%d" % [side,finger,joint]:
					return "J_Bip_%s_%s%d" % ["L" if side == "Left" else "R", "Little" if finger == "Pinky" else finger, joint]
	return bone

func _load_clip(name: String) -> void:
	if library.has_animation(name): return
	assert(Catalog.SCENES.has(name))
	var scene: Node = Catalog.SCENES[name].instantiate()
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var animation := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() > 0:
			animation.track_set_path(track, NodePath(skeleton_path + ":" + _canonical(str(path.get_subname(0)))))
	animation.loop_mode = Animation.LOOP_NONE
	library.add_animation(name, animation)
	scene.free()

func play(name: String, loop := false) -> void:
	if name != "standing": _load_clip(name)
	current = name
	library.get_animation(name).loop_mode = Animation.LOOP_LINEAR if loop or name == "standing" else Animation.LOOP_NONE
	animation_player.play("motifect/" + name, 0.25)

func stop() -> void:
	play("standing")

func _finished(qualified: StringName) -> void:
	var name := str(qualified).trim_prefix("motifect/")
	stop()
	motion_finished.emit(name)

func _process(_delta: float) -> void:
	if target_skeleton == null: return
	# Root stays anchored in X/Z. Preserve the clip's vertical displacement for sitting/bending.
	var source_hips := rig_skeleton.find_bone("J_Bip_C_Hips")
	var height := rig_skeleton.get_bone_pose_position(source_hips).y
	target_skeleton.position.y = (height - source_hip_height) * target_hip_height / source_hip_height
