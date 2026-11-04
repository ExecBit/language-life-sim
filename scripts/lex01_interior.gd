class_name Lex01Interior
extends RefCounted

## Stands the tavern's fixed furniture up from data, once per run.
##
## The room builder (`Lex01RoomBuilder`) stages one scenario's answer objects, which change from
## card to card. The tavern itself does not change, so it is not staged anywhere: it is assembled
## from the `interior` array of data/room/lex01_room.json, which names a model, where it stands,
## which way it faces and whether the player can walk into it. Adding a table, a crate or a lamp to
## the room is therefore one JSON entry, not a code change, exactly like a new scenario.
##
## Two rules keep the first-person room trustworthy:
##
## 1. Grounding. KayKit pieces are modelled around their own origin, so `wall` sits with its feet
##    at y = 0 while `kitchencabinet` is modelled as a wall unit whose mesh starts at y = 2 and
##    `shelf` starts below zero. Each entry is placed so the bottom of its imported bounding box
##    sits on the floor (y = 0) unless it declares `"ground": false`, which is how a wall unit or a
##    picture keeps the height it was modelled at.
## 2. Collision. Only entries marked `"solid"` get a collider, all of them in ONE StaticBody3D on
##    the room layer, so the walls, the bar counter and the storage crates stop the player while
##    guest tables, chairs, lamps, NPCs and every staged answer object stay walk-through. The player
##    masks only that layer, which is the same rule TAV-02 shipped for props: nothing a task can ask
##    about can ever block or trap the player. Colliders are measured BoxShape3D boxes rather than
##    imported meshes - a bar counter and a crate are boxes, and precise collision is an explicit
##    non-goal of this slice.

const GROUND_Y: float = 0.0
const SOLID_LAYER: int = 1
const SOLID_BODY_NAME: String = "TavernFurniture"

var warnings: PackedStringArray = []

var _content: Lex01Content
var _root: Node3D
var _solid_body: StaticBody3D = null
var _nodes: Array[Node3D] = []
var _solid_boxes: Array[AABB] = []


func setup(content: Lex01Content, root: Node3D) -> void:
	_content = content
	_root = root


## Build every entry the room data declares and report what stands in the tavern.
func build() -> Dictionary:
	clear()
	for entry: Variant in _content.interior_entries():
		if not (entry is Dictionary):
			warnings.append("interior entry is not an object: %s" % [entry])
			continue
		_place(entry as Dictionary)
	return summary()


func summary() -> Dictionary:
	return {
		"built": _nodes.size(),
		"solid": _solid_boxes.size(),
		"solid_boxes": _solid_boxes.duplicate(),
	}


## The solid footprints, so a check can confirm that nothing solid stands outside the room shell.
func solid_boxes() -> Array[AABB]:
	return _solid_boxes.duplicate()


func node_count() -> int:
	return _nodes.size()


func clear() -> void:
	for node: Node3D in _nodes:
		if node != null and node.is_inside_tree():
			node.get_parent().remove_child(node)
			node.queue_free()
	_nodes.clear()
	_solid_boxes.clear()
	if _solid_body != null and _solid_body.is_inside_tree():
		_solid_body.get_parent().remove_child(_solid_body)
		_solid_body.queue_free()
	_solid_body = null


func _place(entry: Dictionary) -> void:
	var scene_object: String = String(entry.get("model", ""))
	if scene_object.is_empty():
		warnings.append("interior entry without a model: %s" % [entry])
		return
	var packed: Variant = load(scene_object)
	if not (packed is PackedScene):
		warnings.append("interior model cannot be loaded: %s" % scene_object)
		return
	var node: Node3D = (packed as PackedScene).instantiate() as Node3D
	if node == null:
		warnings.append("interior model does not instantiate as Node3D: %s" % scene_object)
		return
	node.name = _scene_name(scene_object)
	_root.add_child(node)
	node.position = _vector3(entry.get("position", [0.0, 0.0, 0.0]))
	node.rotation_degrees = _vector3(entry.get("rotation_deg", [0.0, 0.0, 0.0]))
	if entry.get("ground", true) == true:
		_ground(node)
	_nodes.append(node)
	if entry.get("solid", false) == true:
		_make_solid(node, scene_object)


## One shared static body holds every solid piece, so the room's walk-blocking furniture is a single
## thing a check can count and the player's collision mask stays exactly what TAV-02 declared.
func _make_solid(node: Node3D, scene_object: String) -> void:
	var box: AABB = _world_aabb(node)
	if box.size.length() <= 0.0:
		warnings.append("interior solid entry has no measurable mesh: %s" % scene_object)
		return
	if _solid_body == null:
		_solid_body = StaticBody3D.new()
		_solid_body.name = SOLID_BODY_NAME
		_solid_body.collision_layer = SOLID_LAYER
		_solid_body.collision_mask = 0
		_root.add_child(_solid_body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	_solid_body.add_child(shape)
	# The shape sits where the model stands, expressed in the static body's own frame so the
	# placement does not depend on where the interior root happens to be.
	shape.position = _solid_body.to_local(box.get_center())
	_solid_boxes.append(box)


func _ground(node: Node3D) -> void:
	var box: AABB = _world_aabb(node)
	if box.size.y <= 0.0:
		return
	var local_low: float = box.position.y - node.position.y
	node.position = Vector3(node.position.x, GROUND_Y - local_low, node.position.z)


func _world_aabb(node: Node3D) -> AABB:
	# The eight world-space corners of every mesh under the node - the same measurement
	# Lex01RoomBuilder and tools/prep_probe.gd use on these models.
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	var found: bool = false
	for instance: MeshInstance3D in meshes:
		for corner: Vector3 in _corners(instance.get_aabb()):
			var point: Vector3 = instance.global_transform * corner
			low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
			high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))
		found = true
	return AABB(low, high - low) if found else AABB()


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


func _corners(box: AABB) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x: float in [box.position.x, box.position.x + box.size.x]:
		for y: float in [box.position.y, box.position.y + box.size.y]:
			for z: float in [box.position.z, box.position.z + box.size.z]:
				result.append(Vector3(x, y, z))
	return result


func _scene_name(scene_object: String) -> String:
	var result: String = ""
	var capitalize_next: bool = true
	for character: String in scene_object.get_file().get_basename():
		if character == "_" or character == "-":
			capitalize_next = true
			continue
		result += character.to_upper() if capitalize_next else character
		capitalize_next = false
	return result


func _vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
