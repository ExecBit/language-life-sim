@tool
extends Object

# The Check Level button: composes the bootstrap audit, the layer audit and
# the playability checks into one list. Pure logic; the dock renders rows and
# wires Fix buttons.
#
# The ground check is a real physics ray, so it needs the scene in a tree with
# physics up (true in-editor and in the verify scene). Colliders register with
# the physics server in the editor even though simulation is off, so space
# queries work there.

const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const LAYER_TOOLS := preload("res://addons/level_builder/editor/layer_tools.gd")
const COLLIDER_TOOLS := preload("res://addons/level_builder/editor/collider_tools.gd")

const GROUND_RAY_LENGTH := 50.0


static func ground_under_spawn(root: Node) -> bool:
	var spawn := BOOTSTRAP.find_spawn(root) as Marker3D
	if spawn == null or not spawn.is_inside_tree():
		return false
	var world: World3D = spawn.get_world_3d()
	if world == null or world.direct_space_state == null:
		return false
	var from: Vector3 = spawn.global_position + Vector3.UP * 0.5
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * GROUND_RAY_LENGTH)
	return not world.direct_space_state.intersect_ray(params).is_empty()


static func meshes_without_collision(root: Node) -> int:
	# only look under Geometry/Props — decorative FX meshes are allowed to be hollow
	var count := 0
	for container_name in ["Geometry", "Props"]:
		var container: Node = root.get_node_or_null(NodePath(container_name))
		if container == null:
			continue
		for mi in COLLIDER_TOOLS.collect_meshes([container]):
			if not COLLIDER_TOOLS.has_collision(mi):
				count += 1
	return count


static func check(root: Node) -> Array[Dictionary]:
	var findings: Array[Dictionary] = BOOTSTRAP.audit(root)
	findings.append_array(LAYER_TOOLS.audit(root))

	# ground: only meaningful once a spawn exists — no spawn already reds out above
	if BOOTSTRAP.find_spawn(root) != null and not ground_under_spawn(root):
		findings.append({"id": "no_ground_under_spawn", "severity": "red",
			"message": "Nothing to stand on under PlayerSpawn — you'd fall forever. Add ground or move the spawn.",
			"fixable": root.get_node_or_null(^"Geometry/Ground") == null})

	var hollow := meshes_without_collision(root)
	if hollow > 0:
		findings.append({"id": "hollow_meshes", "severity": "amber",
			"message": "%d mesh(es) under Geometry/Props with no collider — the Colliders tab can batch-fix the selection." % hollow,
			"fixable": false})

	var nav := BOOTSTRAP.find_first(root, "NavigationRegion3D") as NavigationRegion3D
	if nav != null and nav.navigation_mesh == null:
		findings.append({"id": "nav_not_baked", "severity": "amber",
			"message": "NavigationRegion3D has no navigation mesh — enemies can't path until you bake one.",
			"fixable": false})
	return findings


# Fix dispatch for check-specific rows; bootstrap rows go through
# scene_bootstrap.apply_fix. Returns true if the id was ours.
static func apply_fix(id: String, root: Node, undo = null) -> bool:
	match id:
		"no_ground_under_spawn":
			BOOTSTRAP.fix_ground(root, undo)
		_:
			return false
	return true
