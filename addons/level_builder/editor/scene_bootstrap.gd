@tool
extends Object

# Scene bootstrap: presets → a lit, organized 3D scene skeleton, plus the
# audit that tells you what an existing scene is missing and the fixes that
# repair it.
#
# Pure logic on purpose — no EditorInterface anywhere, so headless verify can
# drive all of it. The dock owns dialogs and undo actions; every fix here
# takes an optional EditorUndoRedoManager (null = mutate directly, which is
# what the tests do).

const CONTAINERS := ["Geometry", "Props", "Gameplay", "Lighting", "FX"]
const SPAWN_NAME := "PlayerSpawn"
const GROUND_SIZE := 60.0

# World role bits, duplicated from the World layer profile so bootstrap has no
# load-order dependency on defaults/. Keep in sync with layer_world.tres.
const WORLD_LAYER := 1
const WORLD_MASK := 0

const SELF := "res://addons/level_builder/editor/scene_bootstrap.gd"

const PRESETS := {
	"Outdoor Day": {
		"sky": true,
		"sky_top": Color(0.30, 0.51, 0.79),
		"sky_horizon": Color(0.65, 0.78, 0.90),
		"ground_horizon": Color(0.65, 0.72, 0.70),
		"ground_bottom": Color(0.22, 0.20, 0.17),
		"ambient_energy": 1.0,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"glow": false,
		"fog": false,
		"sun_rot": Vector3(-50.0, -35.0, 0.0),
		"sun_energy": 1.3,
		"sun_color": Color(1.0, 0.98, 0.92),
	},
	"Outdoor Night": {
		"sky": true,
		"sky_top": Color(0.02, 0.03, 0.08),
		"sky_horizon": Color(0.08, 0.10, 0.18),
		"ground_horizon": Color(0.07, 0.08, 0.12),
		"ground_bottom": Color(0.01, 0.01, 0.02),
		"ambient_energy": 0.35,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"glow": true,
		"fog": true,
		"fog_color": Color(0.04, 0.05, 0.10),
		"fog_density": 0.008,
		"sun_rot": Vector3(-40.0, 20.0, 0.0),
		"sun_energy": 0.25,
		"sun_color": Color(0.65, 0.72, 0.95),
	},
	"Indoor": {
		"sky": false,
		"bg_color": Color(0.05, 0.05, 0.06),
		"ambient_color": Color(0.55, 0.53, 0.50),
		"ambient_energy": 0.6,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"glow": true,
		"fog": false,
		"sun_rot": Vector3(-60.0, -20.0, 0.0),
		"sun_energy": 0.4,
		"sun_color": Color(1.0, 0.95, 0.85),
	},
	"Stylized": {
		"sky": true,
		"sky_top": Color(0.45, 0.65, 0.95),
		"sky_horizon": Color(0.95, 0.80, 0.75),
		"ground_horizon": Color(0.80, 0.75, 0.65),
		"ground_bottom": Color(0.35, 0.30, 0.28),
		"ambient_energy": 1.2,
		"tonemap": Environment.TONE_MAPPER_LINEAR,
		"glow": false,
		"fog": false,
		"sun_rot": Vector3(-45.0, -30.0, 0.0),
		"sun_energy": 1.0,
		"sun_color": Color(1.0, 0.93, 0.80),
	},
}


static func preset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for key in PRESETS:
		names.append(key)
	return names


static func build_environment(preset_name: String) -> Environment:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS["Outdoor Day"])
	var env := Environment.new()
	if bool(p.get("sky", false)):
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = p["sky_top"]
		mat.sky_horizon_color = p["sky_horizon"]
		mat.ground_horizon_color = p["ground_horizon"]
		mat.ground_bottom_color = p["ground_bottom"]
		var sky := Sky.new()
		sky.sky_material = mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = p["bg_color"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = p["ambient_color"]
	env.ambient_light_energy = float(p.get("ambient_energy", 1.0))
	env.tonemap_mode = int(p.get("tonemap", Environment.TONE_MAPPER_FILMIC))
	env.glow_enabled = bool(p.get("glow", false))
	if bool(p.get("fog", false)):
		env.fog_enabled = true
		env.fog_light_color = p.get("fog_color", Color(0.5, 0.6, 0.7))
		env.fog_density = float(p.get("fog_density", 0.01))
	return env


static func build_sun(preset_name: String) -> DirectionalLight3D:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS["Outdoor Day"])
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = p.get("sun_rot", Vector3(-50, -35, 0))
	sun.light_energy = float(p.get("sun_energy", 1.0))
	sun.light_color = p.get("sun_color", Color.WHITE)
	sun.shadow_enabled = true
	return sun


static func build_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = WORLD_MASK

	var mesh := MeshInstance3D.new()
	mesh.name = "GroundMesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.42)
	plane.material = mat
	mesh.mesh = plane
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "GroundShape"
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	return body


static func build_spawn() -> Marker3D:
	var spawn := Marker3D.new()
	spawn.name = SPAWN_NAME
	spawn.position = Vector3(0, 1.0, 0)
	return spawn


# The whole skeleton, owners set, ready to pack into a new .tscn.
static func build_skeleton(preset_name: String, with_ground: bool = true, with_nav: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Level"

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"  # or Godot names it @WorldEnvironment@2
	world_env.environment = build_environment(preset_name)
	root.add_child(world_env)

	for container_name in CONTAINERS:
		var c := Node3D.new()
		c.name = container_name
		root.add_child(c)

	root.get_node("Lighting").add_child(build_sun(preset_name))
	root.get_node("Gameplay").add_child(build_spawn())
	if with_ground:
		root.get_node("Geometry").add_child(build_ground())
	if with_nav:
		var nav := NavigationRegion3D.new()
		nav.name = "NavRegion"
		root.add_child(nav)

	_own_recursive(root, root)
	return root


static func _own_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_recursive(child, root)


# ---- audit ----------------------------------------------------------------

static func find_first(root: Node, klass: String) -> Node:
	if root.is_class(klass):
		return root
	for child in root.get_children():
		var found := find_first(child, klass)
		if found:
			return found
	return null


static func find_spawn(root: Node) -> Node:
	var found: Node = root.find_child(SPAWN_NAME, true, false)
	return found if found is Marker3D else null


# Findings: {id, severity ("red"/"amber"), message, fixable}
static func audit(root: Node) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	var env := find_first(root, "WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null:
		findings.append({"id": "missing_environment", "severity": "red",
			"message": "No WorldEnvironment — the scene renders with engine defaults.", "fixable": true})
	if find_first(root, "Light3D") == null:
		findings.append({"id": "missing_light", "severity": "red",
			"message": "No light — a 3D scene with no light is a black screen.", "fixable": true})
	if find_spawn(root) == null:
		findings.append({"id": "missing_spawn", "severity": "red",
			"message": "No PlayerSpawn marker — Test Walk has nowhere to start.", "fixable": true})
	var missing := PackedStringArray()
	for container_name in CONTAINERS:
		if not (root.get_node_or_null(NodePath(container_name)) is Node3D):
			missing.append(container_name)
	if missing.size() > 0:
		findings.append({"id": "missing_containers", "severity": "amber",
			"message": "Missing containers: %s — placement targets these." % ", ".join(missing), "fixable": true})
	var loose := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			loose += 1
	if loose > 0:
		findings.append({"id": "loose_meshes", "severity": "amber",
			"message": "%d mesh(es) parented straight to the scene root — consider moving them under Geometry or Props." % loose,
			"fixable": false})
	return findings


# ---- fixes ----------------------------------------------------------------
# undo is an EditorUndoRedoManager or null. The dock wraps calls in one
# create_action/commit_action pair; headless tests pass null.

static func _add_owned(parent: Node, child: Node, root: Node, undo) -> void:
	if undo:
		undo.add_do_method(parent, "add_child", child)
		# owners after add_child, and DEEP: the ground is a body with a mesh and
		# a shape under it, and a child without an owner is dropped on save
		undo.add_do_method(load(SELF), "set_owner_deep", child, root)
		undo.add_do_reference(child)
		undo.add_undo_method(parent, "remove_child", child)
	else:
		parent.add_child(child)
		set_owner_deep(child, root)


# Reachable through the undo manager, so it has to be a plain static here.
static func set_owner_deep(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		set_owner_deep(child, root)


static func fix_environment(root: Node, preset_name: String, undo = null) -> void:
	var env := find_first(root, "WorldEnvironment") as WorldEnvironment
	if env:
		# node exists but has no resource — just fill it in
		if undo:
			undo.add_do_property(env, "environment", build_environment(preset_name))
			undo.add_undo_property(env, "environment", env.environment)
		else:
			env.environment = build_environment(preset_name)
		return
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = build_environment(preset_name)
	_add_owned(root, node, root, undo)


static func fix_sun(root: Node, preset_name: String, undo = null) -> void:
	var parent: Node = root.get_node_or_null(^"Lighting")
	if parent == null:
		parent = root
	_add_owned(parent, build_sun(preset_name), root, undo)


static func fix_spawn(root: Node, undo = null) -> void:
	var parent: Node = root.get_node_or_null(^"Gameplay")
	if parent == null:
		parent = root
	_add_owned(parent, build_spawn(), root, undo)


static func fix_containers(root: Node, undo = null) -> void:
	for container_name in CONTAINERS:
		if root.get_node_or_null(NodePath(container_name)) is Node3D:
			continue
		var c := Node3D.new()
		c.name = container_name
		_add_owned(root, c, root, undo)


static func fix_ground(root: Node, undo = null) -> void:
	var parent: Node = root.get_node_or_null(^"Geometry")
	if parent == null:
		parent = root
	_add_owned(parent, build_ground(), root, undo)


# Fix dispatcher so the dock can wire audit rows to fixes without a switch per row.
static func apply_fix(id: String, root: Node, preset_name: String, undo = null) -> bool:
	match id:
		"missing_environment":
			fix_environment(root, preset_name, undo)
		"missing_light":
			fix_sun(root, preset_name, undo)
		"missing_spawn":
			fix_spawn(root, undo)
		"missing_containers":
			fix_containers(root, undo)
		_:
			return false
	return true
