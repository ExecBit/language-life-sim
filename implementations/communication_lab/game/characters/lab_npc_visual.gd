extends Node3D
const SemanticResolver = preload("res://implementations/communication_lab/game/characters/semantic_bone_resolver.gd")
const MirrorRetarget = preload("res://implementations/communication_lab/game/characters/lab_mirror_retarget.gd")
const IDLE_CLIP: PackedScene = preload("res://assets/animations/motifect/Locomotion/idle_neutral.fbx")
const RIG_SCENE: PackedScene = preload("res://assets/animations/motifect/drink_from_cup.fbx")
const ASTERA_AVATAR_PATH := "res://assets/characters/private/astera.vrm"
const FALLBACK_AVATAR_PATH := "res://assets/characters/anna.vrm"
const MAP := {"Hips":"J_Bip_C_Hips", "Spine1":"J_Bip_C_Spine", "Spine2":"J_Bip_C_Chest", "Chest":"J_Bip_C_UpperChest", "Neck2":"J_Bip_C_Neck", "Head":"J_Bip_C_Head", "LeftShoulder":"J_Bip_L_Shoulder", "LeftArm":"J_Bip_L_UpperArm", "LeftForeArm":"J_Bip_L_LowerArm", "LeftHand":"J_Bip_L_Hand", "RightShoulder":"J_Bip_R_Shoulder", "RightArm":"J_Bip_R_UpperArm", "RightForeArm":"J_Bip_R_LowerArm", "RightHand":"J_Bip_R_Hand", "LeftLeg":"J_Bip_L_UpperLeg", "LeftShin":"J_Bip_L_LowerLeg", "LeftFoot":"J_Bip_L_Foot", "LeftToeBase":"J_Bip_L_ToeBase", "RightLeg":"J_Bip_R_UpperLeg", "RightShin":"J_Bip_R_LowerLeg", "RightFoot":"J_Bip_R_Foot", "RightToeBase":"J_Bip_R_ToeBase"}
var rig_skeleton: Skeleton3D
var target_skeleton: Skeleton3D
var animation_player: AnimationPlayer
var library := AnimationLibrary.new()
var skeleton_path := ""
var avatar_path_in_use := ""
var face_mesh: MeshInstance3D
var emotion_state := "neutral"
var active_animation_id := "standing"
var expression_channels: Dictionary = {}
## VRM 0 expression preset bindings verified in both the private Astera VRM
## and redistributable Anna fallback. Godot imports the morphs as morph_N.
var expression_presets := {"angry":"morph_1", "fun":"morph_2", "joy":"morph_3", "sorrow":"morph_4", "surprised":"morph_5"}
var expression_from: Dictionary = {}
var expression_target: Dictionary = {}
var expression_tween := 1.0

func _ready() -> void:
	var driver := RIG_SCENE.instantiate()
	add_child(driver)
	rig_skeleton = driver.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	animation_player = driver.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	skeleton_path = str(animation_player.get_node(animation_player.root_node).get_path_to(rig_skeleton))
	for i in rig_skeleton.get_bone_count():
		var original := str(rig_skeleton.get_bone_name(i))
		if MAP.has(original): rig_skeleton.set_bone_name(i, MAP[original])
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("lab", library)
	avatar_path_in_use = ASTERA_AVATAR_PATH if ResourceLoader.exists(ASTERA_AVATAR_PATH) else FALLBACK_AVATAR_PATH
	if avatar_path_in_use == FALLBACK_AVATAR_PATH:
		push_warning("Local Astera asset is unavailable; Communication Lab is showing the redistributable Anna fallback.")
	var avatar := (load(avatar_path_in_use) as PackedScene).instantiate()
	target_skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var face_meshes := avatar.find_children("*", "MeshInstance3D", true, false)
	for candidate in face_meshes:
		var mesh_node := candidate as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_blend_shape_count() > 0:
			face_mesh = mesh_node
			for shape_index in mesh_node.mesh.get_blend_shape_count():
				expression_channels["morph_%d" % shape_index] = shape_index
			break
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
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D: continue
		var target_bone := str(animation.track_get_path(track).get_subname(0))
		if target_bone not in ["J_Bip_L_UpperArm", "J_Bip_R_UpperArm"]: continue
		var angle := deg_to_rad(18.0 if target_bone == "J_Bip_L_UpperArm" else -18.0)
		var clearance := Quaternion(Vector3(0, 0, 1), angle)
		for key in animation.track_get_key_count(track):
			var rotation: Quaternion = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, (clearance * rotation).normalized())
	animation.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("standing", animation)
	idle_source.free()
	animation_player.animation_finished.connect(func(_name):
		active_animation_id = "standing"
		animation_player.play("lab/standing", 0.3))
	animation_player.play("lab/standing")
	active_animation_id = "standing"
	set_emotion("neutral")

func set_emotion(state: String) -> void:
	var preset: Dictionary = {
		"neutral": {}, "surprised_soft": {"surprised": 0.45},
		"friendly": {"fun": 0.35}, "curious": {"surprised": 0.25, "fun": 0.15},
		"happy": {"joy": 0.7}, "tired": {"sorrow": 0.45},
		"concerned": {"sorrow": 0.35}, "playful": {"fun": 0.55},
		"grateful": {"joy": 0.5}, "farewell": {"joy": 0.4}
	}.get(state, {})
	emotion_state = state if state in ["neutral", "surprised_soft", "friendly", "curious", "happy", "tired", "concerned", "playful", "grateful", "farewell"] else "neutral"
	expression_from.clear()
	expression_target.clear()
	for channel in expression_channels:
		var current := face_mesh.get_blend_shape_value(expression_channels[channel]) if is_instance_valid(face_mesh) else 0.0
		expression_from[channel] = current
		expression_target[channel] = 0.0
	for emotion in preset:
		var channel: String = expression_presets.get(str(emotion), "")
		if expression_channels.has(channel): expression_target[channel] = float(preset[emotion])
	expression_tween = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(face_mesh) or expression_tween >= 1.0: return
	expression_tween = minf(1.0, expression_tween + delta * 3.0)
	var blend := smoothstep(0.0, 1.0, expression_tween)
	for channel in expression_target:
		var value := lerpf(float(expression_from[channel]), float(expression_target[channel]), blend)
		face_mesh.set_blend_shape_value(expression_channels[channel], value)

func play_generated(id: String, path: String) -> void:
	if not library.has_animation(id):
		var scene := (load(path) as PackedScene).instantiate()
		var source: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var animation := source.get_animation(source.get_animation_list()[0]).duplicate(true) as Animation
		var mapped := 0
		for track in animation.get_track_count():
			var source_path := animation.track_get_path(track)
			if source_path.get_name_count() == 0:
				animation.track_set_enabled(track, false)
				continue
			var bone := str(source_path.get_name(source_path.get_name_count() - 1))
			bone = str(MAP.get(bone, bone))
			if rig_skeleton.find_bone(bone) < 0:
				animation.track_set_enabled(track, false)
				continue
			animation.track_set_path(track, NodePath(skeleton_path + ":" + bone))
			mapped += 1
		assert(mapped > 0, "Generated clip has no mapped tracks: " + id)
		animation.loop_mode = Animation.LOOP_NONE
		library.add_animation(id, animation)
		scene.free()
	active_animation_id = id
	animation_player.play("lab/" + id, 0.3)

func return_to_idle() -> void:
	if not is_instance_valid(animation_player) or not library.has_animation("standing"): return
	active_animation_id = "standing"
	animation_player.play("lab/standing", 0.3)
