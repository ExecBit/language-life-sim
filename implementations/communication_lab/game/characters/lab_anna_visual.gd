extends Node3D
const SemanticResolver = preload("res://implementations/communication_lab/game/characters/semantic_bone_resolver.gd")
const MirrorRetarget = preload("res://implementations/communication_lab/game/characters/lab_mirror_retarget.gd")
const IDLE_CLIP: PackedScene = preload("res://assets/animations/motifect/Locomotion/idle_neutral.fbx")
const RIG_SCENE: PackedScene = preload("res://assets/animations/motifect/drink_from_cup.fbx")
const AVATAR: PackedScene = preload("res://assets/characters/anna.vrm")
const MAP := {"Hips":"J_Bip_C_Hips", "Spine1":"J_Bip_C_Spine", "Spine2":"J_Bip_C_Chest", "Chest":"J_Bip_C_UpperChest", "Neck2":"J_Bip_C_Neck", "Head":"J_Bip_C_Head", "LeftShoulder":"J_Bip_L_Shoulder", "LeftArm":"J_Bip_L_UpperArm", "LeftForeArm":"J_Bip_L_LowerArm", "LeftHand":"J_Bip_L_Hand", "RightShoulder":"J_Bip_R_Shoulder", "RightArm":"J_Bip_R_UpperArm", "RightForeArm":"J_Bip_R_LowerArm", "RightHand":"J_Bip_R_Hand", "LeftLeg":"J_Bip_L_UpperLeg", "LeftShin":"J_Bip_L_LowerLeg", "LeftFoot":"J_Bip_L_Foot", "LeftToeBase":"J_Bip_L_ToeBase", "RightLeg":"J_Bip_R_UpperLeg", "RightShin":"J_Bip_R_LowerLeg", "RightFoot":"J_Bip_R_Foot", "RightToeBase":"J_Bip_R_ToeBase"}
var target_skeleton: Skeleton3D
var animation_player: AnimationPlayer
var library := AnimationLibrary.new()
var skeleton_path := ""

func _ready() -> void:
	var driver := RIG_SCENE.instantiate()
	add_child(driver)
	var rig_skeleton := driver.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = driver.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	skeleton_path = str(animation_player.get_node(animation_player.root_node).get_path_to(rig_skeleton))
	for i in rig_skeleton.get_bone_count():
		var original := str(rig_skeleton.get_bone_name(i))
		if MAP.has(original): rig_skeleton.set_bone_name(i, MAP[original])
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("lab", library)
	var avatar := AVATAR.instantiate()
	target_skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var modifier := MirrorRetarget.new()
	modifier.name = "LabIdleRetarget"
	modifier.bone_pairs = SemanticResolver.build_retarget_pairs(target_skeleton, SemanticResolver.SEMANTIC_ORDER)
	rig_skeleton.add_child(modifier)
	target_skeleton.owner = null
	target_skeleton.get_parent().remove_child(target_skeleton)
	modifier.add_child(target_skeleton)
	avatar.free()
	var idle_source := IDLE_CLIP.instantiate()
	var source_player := (idle_source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer)
	var animation := source_player.get_animation(source_player.get_animation_list()[0]).duplicate(true) as Animation
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() > 0:
			var source_bone := str(path.get_subname(0))
			if MAP.has(source_bone): source_bone = MAP[source_bone]
			animation.track_set_path(track, NodePath(skeleton_path + ":" + source_bone))
	animation.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("standing", animation)
	idle_source.free()
	animation_player.play("lab/standing")
