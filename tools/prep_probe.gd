extends Node3D

## PREP-01 compatibility smoke (Issue #4).
## Checks that the two KayKit characters imported with the required clips on their
## own rig, that the selected furniture and item props import as meshes, and that
## idle / walk / interact actually move a bone. No rig tuning, no IK, no navigation.

const REQUIRED_CLIPS: Array[String] = ["Idle", "Walking_A", "Interact"]
const CHARACTER_NAMES: Array[String] = ["Knight", "Mage"]
const PROP_NAMES: Array[String] = [
	"TableMedium",
	"CabinetMedium",
	"Couch",
	"BedSingleA",
	"PictureframeMedium",
	"FridgeA",
	"Bun",
	"Potato",
	"Tomato",
	"Steak",
]

var _targets: Array[Dictionary] = []
var _samples: Dictionary = {}
var _playing: Dictionary = {}
var _failures: PackedStringArray = []
var _frames: int = 0
var _finished: bool = false


func _ready() -> void:
	for character_name: String in CHARACTER_NAMES:
		var character: Node = get_node_or_null(NodePath(character_name))
		if character == null:
			_failures.append("missing character node " + character_name)
			continue
		var player: AnimationPlayer = _find_animation_player(character)
		if player == null:
			_failures.append("no AnimationPlayer under " + character_name)
			continue
		var skeleton: Skeleton3D = _find_skeleton(character)
		if skeleton == null or skeleton.get_bone_count() == 0:
			_failures.append("no Skeleton3D with bones under " + character_name)
			continue
		var clip_names: PackedStringArray = player.get_animation_list()
		print("CHARACTER %s animations=%d" % [character_name, clip_names.size()])
		for clip: String in REQUIRED_CLIPS:
			if not clip_names.has(clip):
				_failures.append("%s is missing clip %s" % [character_name, clip])
				continue
			_targets.append({ "name": character_name, "clip": clip, "player": player, "skeleton": skeleton })

	var prop_meshes: int = 0
	for prop_name: String in PROP_NAMES:
		var prop: Node = get_node_or_null(NodePath(prop_name))
		if prop == null:
			_failures.append("missing prop node " + prop_name)
			continue
		if _has_mesh(prop):
			prop_meshes += 1
		else:
			_failures.append("prop has no mesh: " + prop_name)
	print("PROPS with mesh=%d/%d" % [prop_meshes, PROP_NAMES.size()])

	if _targets.is_empty():
		_report()


func _process(_delta: float) -> void:
	if _finished:
		return
	_frames += 1
	var slot: int = int(float(_frames) / 10.0)
	if slot >= REQUIRED_CLIPS.size():
		_report()
		return
	if _frames % 10 == 1:
		for target: Dictionary in _targets:
			var player: AnimationPlayer = target["player"]
			player.play(target["clip"])
	if _frames % 10 == 3:
		_take_sample("early")
	elif _frames % 10 == 8:
		_take_sample("late")


func _take_sample(stage: String) -> void:
	for target: Dictionary in _targets:
		var key: String = "%s/%s" % [target["name"], target["clip"]]
		var player: AnimationPlayer = target["player"]
		_playing[key] = player.is_playing()
		# Sample the bound skeleton instead of resolving animation track paths by hand:
		# a pose that changes while the clip plays proves the imported rig works as is.
		var skeleton: Skeleton3D = target["skeleton"]
		var pose_sum: Vector3 = Vector3.ZERO
		for i: int in mini(skeleton.get_bone_count(), 8):
			pose_sum += skeleton.get_bone_global_pose(i).origin
		_samples[key + "_" + stage] = pose_sum


func _report() -> void:
	if _finished:
		return
	_finished = true
	for target: Dictionary in _targets:
		var key: String = "%s/%s" % [target["name"], target["clip"]]
		var early: Variant = _samples.get(key + "_early")
		var late: Variant = _samples.get(key + "_late")
		var moved: bool = early is Vector3 and late is Vector3 and early.distance_to(late) > 0.001
		var played: bool = bool(_playing.get(key, false))
		print("CLIP %s -> playing=%s bone_moved=%s" % [key, played, moved])
		if not played or not moved:
			_failures.append("clip did not play or did not move a bone: " + key)
	if _failures.is_empty():
		print("PREP PROBE OK")
		get_tree().quit(0)
	else:
		print("PREP PROBE FAIL")
		for failure: String in _failures:
			print("  - " + failure)
		get_tree().quit(1)


func _find_skeleton(node: Node) -> Skeleton3D:
	for child: Node in node.get_children():
		if child is Skeleton3D:
			return child as Skeleton3D
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child: Node in node.get_children():
		if _has_mesh(child):
			return true
	return false
