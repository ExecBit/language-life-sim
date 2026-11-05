@tool
extends Object

# Collider assistant: batch collision generation for selected meshes.
# Pure logic — dock owns selection, progress UI and undo actions.
#
# Wrapping rule: if the mesh already lives under a physics body, add the shape
# to that body (positioned to match). Otherwise give the MeshInstance3D a
# StaticBody3D child — non-destructive, one subtree per mesh, trivially
# undoable, and the collider follows the mesh when it moves.

enum Policy { TRIMESH, CONVEX, SIMPLIFIED_CONVEX, FIT_BOX, FIT_SPHERE, FIT_CAPSULE }

const POLICY_NAMES := ["Trimesh (static world)", "Convex", "Simplified convex", "Fitted box", "Fitted sphere", "Fitted capsule"]


static func collect_meshes(nodes: Array) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in nodes:
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			found.append(node)
		if node is Node:
			for child in (node as Node).get_children():
				found.append_array(collect_meshes([child]))
	return found


static func make_shape(mesh: Mesh, policy: int) -> Shape3D:
	match policy:
		Policy.TRIMESH:
			return mesh.create_trimesh_shape()
		Policy.CONVEX:
			return mesh.create_convex_shape(true, false)
		Policy.SIMPLIFIED_CONVEX:
			return mesh.create_convex_shape(true, true)
		Policy.FIT_BOX:
			var box := BoxShape3D.new()
			box.size = mesh.get_aabb().size
			return box
		Policy.FIT_SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = mesh.get_aabb().get_longest_axis_size() * 0.5
			return sphere
		Policy.FIT_CAPSULE:
			var aabb := mesh.get_aabb()
			var capsule := CapsuleShape3D.new()
			capsule.radius = maxf(aabb.size.x, aabb.size.z) * 0.5
			capsule.height = maxf(aabb.size.y, capsule.radius * 2.0)
			return capsule
	return null


# Fitted primitives are AABB-centered; mesh geometry usually isn't at origin.
static func _shape_offset(mesh: Mesh, policy: int) -> Vector3:
	match policy:
		Policy.FIT_BOX, Policy.FIT_SPHERE, Policy.FIT_CAPSULE:
			return mesh.get_aabb().get_center()
	return Vector3.ZERO


static func _find_ancestor_body(node: Node) -> CollisionObject3D:
	var cursor := node.get_parent()
	while cursor:
		if cursor is CollisionObject3D:
			return cursor
		cursor = cursor.get_parent()
	return null


# Generates one collider for one mesh. Returns the created CollisionShape3D
# (its body too, if one was created — caller doesn't need it, undo holds refs).
static func add_collider(mi: MeshInstance3D, policy: int, root: Node, profile: Resource = null, undo = null) -> CollisionShape3D:
	var shape_res := make_shape(mi.mesh, policy)
	if shape_res == null:
		return null
	var shape := CollisionShape3D.new()
	shape.name = "%sShape" % mi.name
	shape.shape = shape_res

	var body := _find_ancestor_body(mi)
	if body:
		# put the shape where the mesh is, in the body's space
		shape.transform = body.global_transform.affine_inverse() * mi.global_transform
		shape.position += shape.basis * _shape_offset(mi.mesh, policy)
		_add_owned(body, shape, root, undo)
	else:
		var new_body := StaticBody3D.new()
		new_body.name = "%sBody" % mi.name
		if profile:
			new_body.collision_layer = profile.layers
			new_body.collision_mask = profile.mask
		shape.position = _shape_offset(mi.mesh, policy)
		new_body.add_child(shape)
		_add_owned(mi, new_body, root, undo)
	return shape


# Two different questions, two functions:
# has_collision = "will this mesh block anything?" — the level-check semantic.
# Any shape on the ancestor body counts, whoever made it.
static func has_collision(mi: MeshInstance3D) -> bool:
	var body := _find_ancestor_body(mi)
	if body:
		for child in body.get_children():
			if child is CollisionShape3D:
				return true
		return false
	for child in mi.get_children():
		if child is CollisionObject3D:
			return true
	return false


# already_generated = "did WE make one for this mesh?" — the batch-skip
# semantic. Name-based under a shared body so multi-mesh bodies get a shape
# per mesh and re-runs stay no-ops.
static func already_generated(mi: MeshInstance3D) -> bool:
	var body := _find_ancestor_body(mi)
	if body:
		return body.get_node_or_null(NodePath(mi.name + "Shape")) != null
	for child in mi.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			return true
	return false


# Batch over a selection. skip_existing keeps re-runs idempotent.
# Returns how many colliders were created.
static func generate(nodes: Array, policy: int, root: Node, profile: Resource = null, undo = null, skip_existing: bool = true) -> int:
	var count := 0
	for mi in collect_meshes(nodes):
		if skip_existing and already_generated(mi):
			continue
		if add_collider(mi, policy, root, profile, undo) != null:
			count += 1
	return count


static func _add_owned(parent: Node, child: Node, root: Node, undo) -> void:
	if undo:
		undo.add_do_method(parent, "add_child", child)
		# owners after add_child, deep — packed scenes need every node owned
		undo.add_do_method(load("res://addons/level_builder/editor/collider_tools.gd"), "set_owner_deep", child, root)
		undo.add_undo_method(parent, "remove_child", child)
		undo.add_do_reference(child)
	else:
		parent.add_child(child)
		set_owner_deep(child, root)


static func set_owner_deep(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		set_owner_deep(child, root)
