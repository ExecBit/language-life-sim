@tool
extends RefCounted

# Place mode: ghost preview follows the mouse, click commits. The plugin
# forwards viewport input here; the dock arms/disarms and shows state.
#
# @tool safety: the ghost is OWNERLESS — it lives in the edited scene's tree
# for rendering but can never be saved with it. The committed instance is
# added through the undo manager, so every placement is one ctrl+Z.

const PLACEMENT_MATH := preload("res://addons/level_builder/editor/placement_math.gd")
const COLLIDER_TOOLS := preload("res://addons/level_builder/editor/collider_tools.gd")

const RAY_LENGTH := 2000.0
const PROFILE_DIR := "res://addons/level_builder/defaults"

var armed := false
var asset_path := ""
var profile: Resource  # PlacementProfile for the armed asset's category

var _ghost: Node3D
var _yaw := 0.0
var _scale := 1.0
var _rng := RandomNumberGenerator.new()
var _last_transform := Transform3D.IDENTITY
var _last_normal := Vector3.UP
var _has_surface := false


static func load_profiles() -> Array[Resource]:
	var profiles: Array[Resource] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		return profiles
	for file in dir.get_files():
		if file.begins_with("placement_") and file.ends_with(".tres"):
			var res: Resource = load(PROFILE_DIR + "/" + file)
			if res and "container_name" in res:
				profiles.append(res)
	return profiles


static func profile_for_category(category: String) -> Resource:
	var fallback: Resource = null
	for p in load_profiles():
		if p.category == category:
			return p
		if p.category == "":
			fallback = p
	return fallback


func arm(new_asset_path: String, category: String) -> void:
	disarm()
	asset_path = new_asset_path
	profile = profile_for_category(category)
	armed = true
	_roll_jitter()


func disarm() -> void:
	armed = false
	asset_path = ""
	_has_surface = false
	_last_normal = Vector3.UP
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


func _roll_jitter() -> void:
	_yaw = 0.0
	_scale = 1.0
	if profile:
		if profile.random_y_rotation:
			_yaw = PLACEMENT_MATH.random_yaw(_rng)
		_scale = PLACEMENT_MATH.random_scale(_rng, profile.scale_jitter_min, profile.scale_jitter_max)


func rotate_step(direction: int) -> void:
	# manual rotate takes over from random yaw for this placement
	_yaw = PLACEMENT_MATH.step_yaw(_yaw, 15.0, direction)
	if not _has_surface:
		return
	# The real transform, not just the ghost's: commit() reads _last_transform,
	# so R followed by a click with no mouse movement in between used to drop the
	# piece unrotated while the ghost sat there showing it turned. And it rebuilds
	# off the surface normal we actually hit — rebuilding off UP flattened an
	# aligned piece off its slope every time you pressed R.
	_last_transform = _placement_transform(_last_transform.origin, _last_normal)
	if is_instance_valid(_ghost):
		_ghost.transform = _last_transform


func _ensure_ghost(edited_root: Node) -> void:
	if is_instance_valid(_ghost) or asset_path == "":
		return
	var scene: PackedScene = load(asset_path)
	if scene == null:
		return
	_ghost = scene.instantiate() as Node3D
	if _ghost == null:
		return
	_ghost.name = "LBGhost"
	_make_ghostly(_ghost)
	# ownerless on purpose — renders, never saves
	edited_root.add_child(_ghost)


func _make_ghostly(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = 0.55
	if node is CollisionObject3D:
		# the ghost must be invisible to our own placement ray
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_make_ghostly(child)


func _placement_transform(hit_pos: Vector3, hit_normal: Vector3) -> Transform3D:
	var snap := 0.0
	var align := false
	if profile:
		snap = profile.snap_step
		align = profile.align_to_surface
	return PLACEMENT_MATH.placement_transform(hit_pos, hit_normal, _yaw, snap, align, _scale)


# Mouse moved: cast into the scene, park the ghost on whatever it hits.
# Fallback plane y=0 when the ray hits nothing (empty scene, sky shots).
func update_ghost(camera: Camera3D, mouse_pos: Vector2, edited_root: Node) -> void:
	if not armed or camera == null or edited_root == null:
		return
	_ensure_ghost(edited_root)
	if _ghost == null:
		return
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var hit_pos := Vector3.ZERO
	var hit_normal := Vector3.UP
	var got := false
	var world: World3D = camera.get_world_3d()
	if world and world.direct_space_state:
		var params := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH)
		var hit := world.direct_space_state.intersect_ray(params)
		if not hit.is_empty():
			hit_pos = hit["position"]
			hit_normal = hit["normal"]
			got = true
	if not got:
		# y=0 plane fallback
		if absf(dir.y) > 0.0001:
			var t := -from.y / dir.y
			if t > 0.0:
				hit_pos = from + dir * t
				got = true
	if not got:
		return
	_has_surface = true
	_last_normal = hit_normal
	_last_transform = _placement_transform(hit_pos, hit_normal)
	_ghost.transform = _last_transform


# Click: place the real thing. Fully configures the instance FIRST (colliders,
# layers), then adds the whole subtree as one undo step under the profile's
# container. Returns the placed node (null if not ready).
func commit(edited_root: Node, undo = null) -> Node3D:
	if not armed or not _has_surface or asset_path == "":
		return null
	var scene: PackedScene = load(asset_path)
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return null
	instance.transform = _last_transform

	if profile:
		if profile.collider_policy >= 0:
			COLLIDER_TOOLS.generate([instance], profile.collider_policy, instance, profile.layer_profile, null)
		if profile.layer_profile:
			# only touch bodies that are still on defaults — don't stomp authored bits
			for body in _default_layer_bodies(instance):
				body.collision_layer = profile.layer_profile.layers
				body.collision_mask = profile.layer_profile.mask

	var parent := _resolve_container(edited_root, undo)
	if undo:
		undo.add_do_method(parent, "add_child", instance)
		undo.add_do_method(COLLIDER_TOOLS, "set_owner_deep", instance, edited_root)
		undo.add_undo_method(parent, "remove_child", instance)
		undo.add_do_reference(instance)
	else:
		parent.add_child(instance)
		COLLIDER_TOOLS.set_owner_deep(instance, edited_root)

	_roll_jitter()  # next drop gets fresh jitter
	return instance


func _default_layer_bodies(node: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	for body in preload("res://addons/level_builder/editor/layer_tools.gd").collect_collision_objects([node]):
		if body.collision_layer == 1 and body.collision_mask == 1:
			out.append(body)
	return out


func _resolve_container(edited_root: Node, undo = null) -> Node:
	var container_name := "Props"
	if profile:
		container_name = profile.container_name
	if container_name == "":
		return edited_root
	var existing: Node = edited_root.get_node_or_null(NodePath(container_name))
	if existing:
		return existing
	var container := Node3D.new()
	container.name = container_name
	if undo:
		# container joins the same action as the instance — one ctrl+Z for both
		undo.add_do_method(edited_root, "add_child", container)
		undo.add_do_method(container, "set_owner", edited_root)
		undo.add_undo_method(edited_root, "remove_child", container)
		undo.add_do_reference(container)
	else:
		edited_root.add_child(container)
		container.owner = edited_root
	return container
