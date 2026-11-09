extends Node3D

const Visual = preload("res://game/characters/CharacterVisual.gd")
const HeadPose = preload("res://game/characters/lena_head_pose.gd")
const RelaxedIdle = preload("res://game/characters/relaxed_idle.gd")
const PRIVATE_MODEL := "res://assets/characters/private/astera.vrm"
const FALLBACK_MODEL := "res://assets/characters/fallback.vrm"

func model_resource() -> PackedScene:
	return load(PRIVATE_MODEL if ResourceLoader.exists(PRIVATE_MODEL) else FALLBACK_MODEL) as PackedScene
const RIG = preload("res://addons/cogito/Assets/UniversalAnimationLibrary/AnimationLibrary_Godot_Standard.glb")
var visual: CharacterVisual
var hand_attachment: BoneAttachment3D
var head_pose: SkeletonModifier3D
var holding := false
var talking := false
var clip := ""
var animation_ready := false

func _ready() -> void:
	visual = Visual.new()
	visual.rig_scene = RIG
	visual.model_scene = model_resource()
	add_child(visual)
	assert(visual.target_skeleton != null)
	head_pose = HeadPose.new()
	head_pose.head_index = SemanticBoneResolver.find(visual.target_skeleton, SemanticBoneResolver.HEAD)
	visual.target_skeleton.add_child(head_pose)
	hand_attachment = BoneAttachment3D.new()
	# Keep the cup attached to the left hand in the relaxed idle pose.
	hand_attachment.bone_idx = SemanticBoneResolver.find(visual.target_skeleton, SemanticBoneResolver.LEFT_HAND)
	visual.target_skeleton.add_child(hand_attachment)
	var light := OmniLight3D.new()
	light.position = Vector3(0,1.7,-1.0)
	light.light_color = Color("fff0dd")
	light.light_energy = 0.35
	light.omni_range = 3.0
	add_child(light)
	_start_idle()

func _start_idle() -> void:
	# Let CharacterVisual remove the hidden rig mesh before querying its poses.
	await get_tree().process_frame
	RelaxedIdle.install(visual)
	animation_ready = true
	_update_clip()

func _process(_delta: float) -> void:
	_update_clip()

func _update_clip() -> void:
	if not animation_ready: return
	# Dialogue and holding a cup should not switch Lena into the torch stance.
	var next := "lena/Relaxed"
	if clip == next: return
	clip = next
	var animation := visual.animation_player.get_animation(clip)
	assert(animation != null)
	animation.loop_mode = Animation.LOOP_LINEAR
	visual.play(clip, 0.25)

func animate_head(pitch: float, yaw: float) -> void:
	head_pose.pitch = pitch
	head_pose.yaw = yaw
