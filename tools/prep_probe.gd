extends Node3D

## PREP-01 compatibility smoke (Issue #4).
## Checks that the two KayKit characters imported with the required clips on their
## own rig, that the selected furniture and item props import as meshes, and that
## every required clip actually plays and moves a bone. No rig tuning, no IK, no navigation.
##
## Each (character, clip) pair gets its own exclusive time slot: both characters share a
## single AnimationPlayer, so playing three clips in one slot would leave only the last
## one active and make the earlier results meaningless. Inside its slot the probe also
## asserts that the player is really playing the clip it is measuring.
##
## Headless run  -> automated probe: report and quit.
## Windowed run  -> manual preview: loop the clips for human inspection until Esc or close.

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
# The two committed props whose measured sizes back scenario s14 in
# data/scenarios/lex01_starter.json ("Ist das Sofa größer als das Bild?").
const SIZE_COMPARISON: Array[String] = ["Couch", "PictureframeMedium"]

const SLOT_FRAMES: int = 18
const SAMPLE_FRAMES: Array[int] = [2, 8, 14]

var _slots: Array[Dictionary] = []
var _poses: Dictionary = {}
var _playing: Dictionary = {}
var _current_animation: Dictionary = {}
var _failures: PackedStringArray = []
var _frames: int = 0
var _finished: bool = false
var _manual: bool = false


func _ready() -> void:
	_manual = DisplayServer.get_name() != "headless"

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
			# One slot per character and clip - never two clips on one player at a time.
			_slots.append({ "name": character_name, "clip": clip, "player": player, "skeleton": skeleton })

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

	_measure_size_comparison()

	if _slots.is_empty():
		_report()
	elif _manual:
		print("PREVIEW MANUAL - clips loop on both characters, press Esc or close the window to finish")


func _process(_delta: float) -> void:
	if _finished:
		return
	_frames += 1
	var slot_index: int = int((_frames - 1) / SLOT_FRAMES)
	if slot_index >= _slots.size():
		if _manual:
			# Manual preview keeps cycling so a person can watch each clip.
			_frames = 0
			return
		_report()
		return
	var frame_in_slot: int = (_frames - 1) % SLOT_FRAMES
	var target: Dictionary = _slots[slot_index]
	var player: AnimationPlayer = target["player"]
	if frame_in_slot == 0:
		player.play(target["clip"])
		if _manual:
			print("PREVIEW %s -> %s" % [target["name"], target["clip"]])
	elif SAMPLE_FRAMES.has(frame_in_slot):
		_take_sample(target)


func _unhandled_input(event: InputEvent) -> void:
	if _manual and event.is_action_pressed("ui_cancel"):
		get_tree().quit(0)


# Sample every bone of the bound skeleton three times inside the slot of the clip that
# owns it, so a pose delta always belongs to the animation that was actually assigned to
# the player, and no clip can hide behind a bone that never moves.
func _take_sample(target: Dictionary) -> void:
	var key: String = "%s/%s" % [target["name"], target["clip"]]
	var player: AnimationPlayer = target["player"]
	_playing[key] = player.is_playing()
	_current_animation[key] = player.current_animation
	var skeleton: Skeleton3D = target["skeleton"]
	var pose: PackedVector3Array = PackedVector3Array()
	for i: int in skeleton.get_bone_count():
		pose.append(skeleton.get_bone_global_pose(i).origin)
	var poses: Array = _poses.get(key, [])
	poses.append(pose)
	_poses[key] = poses


# Largest distance any single bone travelled between two consecutive samples.
func _max_bone_delta(key: String) -> float:
	var poses: Array = _poses.get(key, [])
	var largest: float = 0.0
	for s: int in range(1, poses.size()):
		var previous: PackedVector3Array = poses[s - 1]
		var current: PackedVector3Array = poses[s]
		if previous.size() != current.size():
			continue
		for i: int in previous.size():
			largest = maxf(largest, previous[i].distance_to(current[i]))
	return largest


func _report() -> void:
	if _finished:
		return
	_finished = true
	for target: Dictionary in _slots:
		var key: String = "%s/%s" % [target["name"], target["clip"]]
		var moved: bool = _max_bone_delta(key) > 0.001
		var played: bool = bool(_playing.get(key, false))
		var current: String = String(_current_animation.get(key, ""))
		var correct_clip: bool = current == String(target["clip"])
		print("CLIP %s -> current=%s playing=%s max_bone_delta=%.4f bone_moved=%s" % [key, current, played, _max_bone_delta(key), moved])
		if not correct_clip:
			_failures.append("player was not playing the clip under test: %s (current=%s)" % [key, current])
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


# Measure the two props s14 compares, once, from the meshes Godot already imported.
func _measure_size_comparison() -> void:
	var sizes: Array[Vector3] = []
	for prop_name: String in SIZE_COMPARISON:
		var size: Vector3 = _prop_world_size(prop_name)
		if size == Vector3.ZERO:
			_failures.append("cannot measure prop size: " + prop_name)
		print("PROP_SIZE %s size=(%.3f, %.3f, %.3f)" % [prop_name, size.x, size.y, size.z])
		sizes.append(size)
	if sizes.size() != SIZE_COMPARISON.size():
		return
	var larger: float = sizes[0].x * sizes[0].y * sizes[0].z
	var smaller: float = sizes[1].x * sizes[1].y * sizes[1].z
	var is_larger: bool = larger > smaller
	print("SIZE_CHECK %s > %s = %s" % [SIZE_COMPARISON[0], SIZE_COMPARISON[1], is_larger])
	if not is_larger:
		_failures.append("scenario s14 expects %s to be larger than %s" % [SIZE_COMPARISON[0], SIZE_COMPARISON[1]])


func _prop_world_size(prop_name: String) -> Vector3:
	var prop: Node = get_node_or_null(NodePath(prop_name))
	if prop == null:
		return Vector3.ZERO
	var meshes: Array[Node] = []
	_collect_meshes(prop, meshes)
	# Bounding box by hand from the eight world-space corners of each mesh: exact for the
	# unrotated props in the preview scene and free of any geometry helper.
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var found: bool = false
	for mesh: Node in meshes:
		var instance: MeshInstance3D = mesh as MeshInstance3D
		for corner: Vector3 in _corners(instance.get_aabb()):
			var point: Vector3 = instance.global_transform * corner
			low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
			high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))
			found = true
	return high - low if found else Vector3.ZERO


func _corners(box: AABB) -> Array[Vector3]:
	var lo: Vector3 = box.position
	var hi: Vector3 = box.position + box.size
	return [
		lo,
		Vector3(hi.x, lo.y, lo.z),
		Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z),
		Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, hi.z),
		hi,
	]


func _collect_meshes(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


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
