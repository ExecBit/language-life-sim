class_name CharacterVisual
extends Node3D
## Reusable character visual: plays Quaternius Universal animations on a hidden
## driver rig and retargets the pose onto the astera VRM model via
## MirrorRetargetModifier3D (model-space, proportion-preserving).
##
## Structure:
##   CharacterVisual
##   └── Rig (Quaternius .glb, mesh hidden)      <- source skeleton, plays anims
##       └── Skeleton3D (bones renamed to J_Bip)
##           └── MirrorRetargetModifier3D (J_Bip names)
##               └── Skeleton3D (astera.vrm)     <- target, visible model

const BONE_MAP := {
	"root": "Root",
	"DEF-hips": "J_Bip_C_Hips",
	"DEF-spine.001": "J_Bip_C_Spine",
	"DEF-spine.002": "J_Bip_C_Chest",
	"DEF-spine.003": "J_Bip_C_UpperChest",
	"DEF-neck": "J_Bip_C_Neck",
	"DEF-head": "J_Bip_C_Head",
	# Left arm / hand
	"DEF-shoulder.L": "J_Bip_L_Shoulder",
	"DEF-upper_arm.L": "J_Bip_L_UpperArm",
	"DEF-forearm.L": "J_Bip_L_LowerArm",
	"DEF-hand.L": "J_Bip_L_Hand",
	"DEF-f_index.01.L": "J_Bip_L_Index1",
	"DEF-f_index.02.L": "J_Bip_L_Index2",
	"DEF-f_index.03.L": "J_Bip_L_Index3",
	"DEF-f_middle.01.L": "J_Bip_L_Middle1",
	"DEF-f_middle.02.L": "J_Bip_L_Middle2",
	"DEF-f_middle.03.L": "J_Bip_L_Middle3",
	"DEF-f_pinky.01.L": "J_Bip_L_Little1",
	"DEF-f_pinky.02.L": "J_Bip_L_Little2",
	"DEF-f_pinky.03.L": "J_Bip_L_Little3",
	"DEF-f_ring.01.L": "J_Bip_L_Ring1",
	"DEF-f_ring.02.L": "J_Bip_L_Ring2",
	"DEF-f_ring.03.L": "J_Bip_L_Ring3",
	"DEF-thumb.01.L": "J_Bip_L_Thumb1",
	"DEF-thumb.02.L": "J_Bip_L_Thumb2",
	"DEF-thumb.03.L": "J_Bip_L_Thumb3",
	# Right arm / hand
	"DEF-shoulder.R": "J_Bip_R_Shoulder",
	"DEF-upper_arm.R": "J_Bip_R_UpperArm",
	"DEF-forearm.R": "J_Bip_R_LowerArm",
	"DEF-hand.R": "J_Bip_R_Hand",
	"DEF-f_index.01.R": "J_Bip_R_Index1",
	"DEF-f_index.02.R": "J_Bip_R_Index2",
	"DEF-f_index.03.R": "J_Bip_R_Index3",
	"DEF-f_middle.01.R": "J_Bip_R_Middle1",
	"DEF-f_middle.02.R": "J_Bip_R_Middle2",
	"DEF-f_middle.03.R": "J_Bip_R_Middle3",
	"DEF-f_pinky.01.R": "J_Bip_R_Little1",
	"DEF-f_pinky.02.R": "J_Bip_R_Little2",
	"DEF-f_pinky.03.R": "J_Bip_R_Little3",
	"DEF-f_ring.01.R": "J_Bip_R_Ring1",
	"DEF-f_ring.02.R": "J_Bip_R_Ring2",
	"DEF-f_ring.03.R": "J_Bip_R_Ring3",
	"DEF-thumb.01.R": "J_Bip_R_Thumb1",
	"DEF-thumb.02.R": "J_Bip_R_Thumb2",
	"DEF-thumb.03.R": "J_Bip_R_Thumb3",
	# Legs / feet
	"DEF-thigh.L": "J_Bip_L_UpperLeg",
	"DEF-shin.L": "J_Bip_L_LowerLeg",
	"DEF-foot.L": "J_Bip_L_Foot",
	"DEF-toe.L": "J_Bip_L_ToeBase",
	"DEF-thigh.R": "J_Bip_R_UpperLeg",
	"DEF-shin.R": "J_Bip_R_LowerLeg",
	"DEF-foot.R": "J_Bip_R_Foot",
	"DEF-toe.R": "J_Bip_R_ToeBase",
}

## Profile bone names shared by the rig (after rename) and the VRM skeleton.
## Head/neck are deliberately EXCLUDED: they are a facial layer driven directly by
## GazeController (set_bone_pose_rotation) on the target skeleton. If they were in
## the profile, MirrorRetargetModifier3D would overwrite their pose every frame
## (copying the neutral Idle head from the rig), erasing gaze/gestures.
## Eyes (J_Adj_*) are likewise excluded so look-direction survives.
const PROFILE_BONES := [
	"Root", "J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest",
	"J_Bip_L_Shoulder", "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
	"J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot", "J_Bip_L_ToeBase",
	"J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
	"J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot", "J_Bip_R_ToeBase",
]

## Semantic-кости, которые ретаргетит визуальный слой (голова/шея — НЕ здесь:
## их ведёт GazeController напрямую, см. PROFILE_BONES).
const RETARGET_SEMANTIC: Array[StringName] = [
	SemanticBoneResolver.ROOT, SemanticBoneResolver.HIPS, SemanticBoneResolver.SPINE,
	SemanticBoneResolver.CHEST, SemanticBoneResolver.UPPER_CHEST,
	SemanticBoneResolver.LEFT_SHOULDER, SemanticBoneResolver.LEFT_UPPER_ARM,
	SemanticBoneResolver.LEFT_LOWER_ARM, SemanticBoneResolver.LEFT_HAND,
	SemanticBoneResolver.RIGHT_SHOULDER, SemanticBoneResolver.RIGHT_UPPER_ARM,
	SemanticBoneResolver.RIGHT_LOWER_ARM, SemanticBoneResolver.RIGHT_HAND,
	SemanticBoneResolver.LEFT_UPPER_LEG, SemanticBoneResolver.LEFT_LOWER_LEG,
	SemanticBoneResolver.LEFT_FOOT, SemanticBoneResolver.LEFT_TOES,
	SemanticBoneResolver.RIGHT_UPPER_LEG, SemanticBoneResolver.RIGHT_LOWER_LEG,
	SemanticBoneResolver.RIGHT_FOOT, SemanticBoneResolver.RIGHT_TOES,
]

@export var rig_scene: PackedScene
## 0 = auto (normalize только при non-identity парах), 1 = принудительно ON,
## 2 = принудительно OFF (для диагностики режимов ретаргета).
@export var rest_normalize_mode := 0
@export var model_scene: PackedScene
## When set, reuse an existing Skeleton3D (e.g. an NPC's astera model) as the
## retarget target instead of instantiating a fresh copy of `model_scene`.
@export var target_skeleton_path: NodePath

## The rig's AnimationPlayer (drives the hidden source skeleton). Use this as the
## `anim_player` for an AnimationTree, or call play()/blend directly.
var animation_player: AnimationPlayer
var rig_skeleton: Skeleton3D
var target_skeleton: Skeleton3D


func _ready() -> void:
	var rig := rig_scene.instantiate()
	add_child(rig)
	# The rig is only an animation driver: drop its mesh so its DEF-named skin
	# binds no longer error after the bones are renamed, and it never renders.
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		mesh.queue_free()

	for node in rig.find_children("*", "AnimationPlayer", true, false):
		animation_player = node
		break
	for node in rig.find_children("*", "Skeleton3D", true, false):
		rig_skeleton = node
		break

	_rename_rig(rig_skeleton)
	_remap_animations()

	var model: Node = null
	if target_skeleton_path != NodePath():
		target_skeleton = get_node_or_null(target_skeleton_path) as Skeleton3D
	else:
		model = model_scene.instantiate()
		for node in model.find_children("*", "Skeleton3D", true, false):
			target_skeleton = node
			break

	var modifier := MirrorRetargetModifier3D.new()
	modifier.name = "MirrorRetargetModifier3D"
	modifier.profile_bones = PackedStringArray(PROFILE_BONES)
	# Semantic compatibility layer: пары «J_Bip-имя на риге -> реальная кость
	# target». Для VRM 0.0 (J_Bip в target) пары identity — поведение то же,
	# что раньше. Для VRM 1.0 (Hips/Left_arm/...) пары резолвятся скелету.
	var pairs := SemanticBoneResolver.build_retarget_pairs(target_skeleton, RETARGET_SEMANTIC)
	modifier.bone_pairs = pairs
	# Rest-pose normalization: default OFF (безопасно — при ON у VRM 1.0
	# ломаются ноги, стопы уходят вверх). rest_normalize_mode форсирует режим
	# (1 = ON для экспериментов, 2 = OFF для диагностики).
	match rest_normalize_mode:
		1: modifier.normalize_rest = true
		2: modifier.normalize_rest = false
		_: modifier.normalize_rest = false
	rig_skeleton.add_child(modifier)
	if target_skeleton:
		target_skeleton.set_owner(null)
		target_skeleton.get_parent().remove_child(target_skeleton)
		modifier.add_child(target_skeleton)
	if model:
		model.queue_free()

	if animation_player == null:
		push_warning("CharacterVisual: no AnimationPlayer in rig")
	if rig_skeleton == null or target_skeleton == null:
		push_warning("CharacterVisual: missing skeleton (%s / %s)" % [rig_skeleton, target_skeleton])


func play(animation: String, blend: float = 0.2) -> void:
	if animation_player == null:
		return
	animation_player.play(animation, blend)


func _rename_rig(skel: Skeleton3D) -> void:
	if skel == null:
		return
	for i in skel.get_bone_count():
		var old := skel.get_bone_name(i)
		if BONE_MAP.has(old):
			skel.set_bone_name(i, BONE_MAP[old])


func _remap_animations() -> void:
	if animation_player == null:
		return
	for anim_name in animation_player.get_animation_list():
		var anim: Animation = animation_player.get_animation(anim_name)
		for track in anim.get_track_count():
			var path := anim.track_get_path(track)
			if path.get_subname_count() == 0:
				continue
			var bone_old := String(path.get_subname(0))
			if BONE_MAP.has(bone_old):
				var new_path := NodePath(
					path.get_concatenated_names() + ":" + BONE_MAP[bone_old])
				anim.track_set_path(track, new_path)
