@tool
extends Object

# Layer role application + the layer audit. Pure logic — the dock owns
# selection, dialogs and undo actions. All fixes take an optional
# EditorUndoRedoManager (null = mutate directly, the headless-test path).

const PROFILE_DIR := "res://addons/level_builder/defaults"

# Layer number → default name, written to ProjectSettings on explicit Apply.
const DEFAULT_LAYER_NAMES := {
	1: "World",
	2: "Player",
	3: "Enemy",
	4: "Projectile",
	5: "Pickup",
	6: "Trigger",
}


static func load_profiles() -> Array[Resource]:
	var profiles: Array[Resource] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		return profiles
	for file in dir.get_files():
		if not (file.begins_with("layer_") and file.ends_with(".tres")):
			continue
		var res: Resource = load(PROFILE_DIR + "/" + file)
		if res and "profile_name" in res:
			profiles.append(res)
	# stable, intentional order: by layer bit, not filename
	profiles.sort_custom(func(a: Resource, b: Resource) -> bool: return a.layers < b.layers)
	return profiles


static func collect_collision_objects(nodes: Array) -> Array[CollisionObject3D]:
	var found: Array[CollisionObject3D] = []
	for node in nodes:
		if node is CollisionObject3D:
			found.append(node)
		if node is Node:
			for child in (node as Node).get_children():
				found.append_array(collect_collision_objects([child]))
	return found


# Returns how many bodies changed.
static func apply_profile(nodes: Array, profile: Resource, undo = null) -> int:
	var bodies := collect_collision_objects(nodes)
	var changed := 0
	for body in bodies:
		if body.collision_layer == profile.layers and body.collision_mask == profile.mask:
			continue
		if undo:
			undo.add_do_property(body, "collision_layer", profile.layers)
			undo.add_do_property(body, "collision_mask", profile.mask)
			undo.add_undo_property(body, "collision_layer", body.collision_layer)
			undo.add_undo_property(body, "collision_mask", body.collision_mask)
		else:
			body.collision_layer = profile.layers
			body.collision_mask = profile.mask
		changed += 1
	return changed


# Findings: {id, severity, message, fixable} — same row shape as scene_bootstrap.audit.
static func audit(root: Node) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	var bodies := collect_collision_objects([root])
	var dead := 0
	var deaf_movers := 0
	var untouched := 0
	for body in bodies:
		if body.collision_layer == 0 and body.collision_mask == 0:
			dead += 1
		elif body.collision_mask == 0 and (body is CharacterBody3D or body is RigidBody3D):
			deaf_movers += 1
		elif body.collision_layer == 1 and body.collision_mask == 1:
			untouched += 1
	if dead > 0:
		findings.append({"id": "dead_layers", "severity": "red",
			"message": "%d body(ies) with layer 0 AND mask 0 — they can never collide with anything." % dead,
			"fixable": false})
	if deaf_movers > 0:
		findings.append({"id": "deaf_movers", "severity": "red",
			"message": "%d moving body(ies) with mask 0 — they'll fall through the world." % deaf_movers,
			"fixable": false})
	if untouched > 0 and untouched == bodies.size():
		findings.append({"id": "all_default", "severity": "amber",
			"message": "Every body is on default layer 1 / mask 1 — fine until you need pickups or projectiles. Apply roles from the Layers tab.",
			"fixable": false})
	return findings


# ---- project layer names ---------------------------------------------------
# ProjectSettings writes are global and NOT undoable. The dock gates this
# behind an explicit Apply + confirm. save_settings=false is the test path —
# headless verify must never persist to the project file.

static func apply_layer_names(names: Dictionary = DEFAULT_LAYER_NAMES, save_settings: bool = false) -> void:
	for layer_num in names:
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % layer_num, names[layer_num])
	if save_settings:
		ProjectSettings.save()


static func current_layer_name(layer_num: int) -> String:
	return str(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % layer_num, ""))
