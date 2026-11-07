class_name Lex01Interior
extends RefCounted

## Read-only bindings to the editor-authored tavern scene.
var warnings: PackedStringArray = []
var _root: Node3D
var _nodes: Array[Node3D] = []
var _solid_boxes: Array[AABB] = []


func setup(_content: Lex01Content, root: Node3D) -> void:
	_root = root


func build() -> Dictionary:
	_nodes.clear()
	_solid_boxes.clear()
	warnings.clear()
	_collect(_root)
	_collect_solids(_root)
	return {"built": _nodes.size(), "solid": _solid_boxes.size(), "solid_boxes": _solid_boxes.duplicate()}


func summary() -> Dictionary:
	return {"built": _nodes.size(), "solid": _solid_boxes.size(), "solid_boxes": _solid_boxes.duplicate()}


func node_for_id(id: String) -> Node3D:
	for node in _nodes:
		if String(node.get_meta("station_id", "")) == id:
			return node
	return null


func node_for_model(scene_object: String) -> Node3D:
	for node in _nodes:
		if node.scene_file_path == scene_object:
			return node
	return null


func position_for_id(id: String) -> Vector3:
	var node := node_for_id(id)
	return node.position if node != null else Vector3.ZERO


func node_count() -> int:
	return _nodes.size()


func solid_boxes() -> Array[AABB]:
	return _solid_boxes.duplicate()


func _collect(node: Node) -> void:
	if node is Node3D and node != _root:
		_nodes.append(node as Node3D)
	for child in node.get_children():
		_collect(child)


func _collect_solids(node: Node) -> void:
	if node is StaticBody3D and String(node.name).ends_with("Collision"):
		for child in node.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
				var shape := child as CollisionShape3D
				var extents := (shape.shape as BoxShape3D).size * shape.global_transform.basis.get_scale() * 0.5
				_solid_boxes.append(AABB(shape.global_position - extents, extents * 2.0))
	for child in node.get_children():
		_collect_solids(child)
