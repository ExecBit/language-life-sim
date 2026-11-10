extends Node3D

const Driver = preload("res://implementations/dormitory/game/characters/motifect_visual.gd")
var visual: Node3D
var hand_attachment: BoneAttachment3D
var holding := false
var talking := false
var current_motion: String:
	get: return visual.current

func _ready() -> void:
	visual = Driver.new()
	add_child(visual)
	hand_attachment = BoneAttachment3D.new()
	visual.target_skeleton.add_child(hand_attachment)
	# This pack's drink_from_cup raises the LEFT hand to the mouth.
	var index := SemanticBoneResolver.find(visual.target_skeleton, SemanticBoneResolver.LEFT_HAND)
	hand_attachment.bone_name = visual.target_skeleton.get_bone_name(index)
	assert(hand_attachment.bone_idx == index)

func animate_head(_pitch: float, _yaw: float) -> void:
	pass # Motifect owns the head pose; keep the authored nod/shake motion.

func play_motion(name: String, loop := false) -> void:
	visual.play(name, loop)

func stop_motion() -> void:
	visual.stop()
