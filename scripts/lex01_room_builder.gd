class_name Lex01RoomBuilder
extends RefCounted

## Puts exactly one scenario's objects into the room and takes them out again.
##
## Which objects appear and which role they have comes from the scenario record; where a
## role is placed comes from data/room/lex01_room.json. Because the room is rebuilt per
## scenario, only the objects the current situation names are present, so "Such den Tisch!"
## never has two candidate tables standing around.
##
## There is no physics simulation here: props get a runtime StaticBody3D box built from their
## imported bounding box so they can be clicked, and carrying is a position change onto the hold
## tray. StaticBody3D rather than Area3D because Godot's ray queries report bodies. Collision
## boxes approximate irregular props, which is acceptable - pixel-precise collision is an
## explicit non-goal of this slice.

const PICK_LAYER: int = 2  # collision layer used by everything clickable
const GROUND_Y: float = 0.0
const SPREAD_GAP: float = 0.24
const FRONT_GAP: float = 0.18

var warnings: PackedStringArray = []

var _content: Lex01Content
var _candidates: Node3D
var _npcs: Node3D
var _rng: RandomNumberGenerator

var _staged: Array[Node3D] = []
var _colliders: Array[StaticBody3D] = []
var _highlights: Array[MeshInstance3D] = []
var _by_path: Dictionary = {}       # scene_object path -> Node3D
var _by_option: Dictionary = {}     # option id -> Node3D
var _option_slot: Dictionary = {}   # option id -> candidate slot index used
var _option_origin: Dictionary = {} # option id -> Vector3 where the object was placed
var _interactive: Dictionary = {}   # pick body -> { "kind": ..., "option_id": ... }
var _npc_bodies: Dictionary = {}    # npc name -> StaticBody3D
var _tray: Node3D = null
var _held_option_id: String = ""
var _hover_option_id: String = ""
var _slot_pool: Array = []
var _used_slot_count: int = 0


func setup(content: Lex01Content, candidates: Node3D, npcs: Node3D, rng: RandomNumberGenerator) -> void:
	_content = content
	_candidates = candidates
	_npcs = npcs
	_rng = rng


func prepare_npcs() -> void:
	_ensure_tray()
	for npc_name: String in _npc_names():
		var node: Node3D = npc_node(npc_name)
		if node == null:
			warnings.append("npc '%s' is not instanced under %s (name it after the npc key in %s)" % [npc_name, _npcs.get_path(), Lex01Content.ROOM_PATH])
			continue
		var config: Dictionary = _content.npc_config(npc_name)
		node.position = _vector3(config.get("position", [0, 0, 0]))
		node.rotation_degrees = _vector3(config.get("rotation_deg", [0, 0, 0]))
		var body: StaticBody3D = _add_collider(node, "%sPickBody" % npc_name, true)
		if body != null:
			_interactive[body] = {"kind": "npc", "npc": npc_name}
			_npc_bodies[npc_name] = body
	idle_all()


## Build the room for one scenario and report what the player can act on.
func stage_scenario(scenario: Dictionary) -> Dictionary:
	clear()
	var context: String = String(scenario.get("context", ""))
	var action: String = String(scenario.get("action_type", ""))
	_slot_pool = _shuffled(_content.candidate_slots(context))

	var state: Dictionary = (scenario.get("scene_state", {}) as Dictionary) if scenario.get("scene_state", null) is Dictionary else {}
	var target: Dictionary = (scenario.get("delivery_target", {}) as Dictionary) if scenario.get("delivery_target", null) is Dictionary else {}
	var target_path: String = String(target.get("scene_object", ""))

	# 1. Anchors the scenario depends on: a placement slot's surface (the table a bun sits
	#    on, the fridge something is put at) and the delivery target. These exist even when
	#    they are not one of the answers.
	var anchor_paths: Array[String] = []
	for key: String in _placement_keys(state):
		var anchor: String = String(_content.placement_slot(String(state[key])).get("anchor", ""))
		if not anchor.is_empty() and not anchor_paths.has(anchor):
			anchor_paths.append(anchor)
	if not target_path.is_empty() and not anchor_paths.has(target_path):
		anchor_paths.append(target_path)
	for anchor_path: String in anchor_paths:
		_spawn_prop(anchor_path, _content.anchor_position(anchor_path, context))

	# 2. The clickable answers of a find or bring task, each on a random candidate position.
	var plan: Array[Dictionary] = []
	if action != "respond":
		for option: Variant in scenario.get("options", []):
			var option_id: String = String((option as Dictionary).get("id", ""))
			var scene_object: String = String((option as Dictionary).get("scene_object", ""))
			var reused: bool = _by_path.has(scene_object)
			var node: Node3D = _by_path[scene_object] as Node3D if reused else _spawn_prop(scene_object, _next_candidate_position())
			if node == null:
				warnings.append("%s: could not stage option model %s" % [String(scenario.get("id", "?")), scene_object])
				continue
			_by_option[option_id] = node
			_option_slot[option_id] = -1 if reused else _used_slot_count - 1
			_enable_picking(node, option_id)
			plan.append({"id": option_id, "slot": int(_option_slot[option_id]), "path": scene_object, "reused_anchor": reused})

	# 3. What the situation states: which object is in focus, which two are compared, and
	#    where the named lemmas are.
	var focus: String = String(state.get("focus_object", ""))
	var compared: String = String(state.get("compared_object", ""))
	for path: String in [focus, compared]:
		if not path.is_empty() and not _by_path.has(path):
			_spawn_prop(path, _next_candidate_position())
	var groups: Dictionary = {}
	for key: String in _placement_keys(state):
		var object_path: String = _content.object_path(key)
		var slot: Dictionary = _content.placement_slot(String(state[key]))
		if object_path.is_empty() or slot.is_empty():
			continue
		var group_key: String = "%s|%s" % [String(slot.get("anchor", "")), String(slot.get("mode", "on_top"))]
		if not groups.has(group_key):
			groups[group_key] = {"anchor": String(slot.get("anchor", "")), "mode": String(slot.get("mode", "on_top")), "items": []}
		(groups[group_key] as Dictionary)["items"].append(object_path)
	for group_key: String in groups:
		var group: Dictionary = groups[group_key] as Dictionary
		var anchor_node: Node3D = _by_path.get(String(group["anchor"]), null) as Node3D
		if anchor_node == null:
			continue
		var items: Array[Node3D] = []
		for object_path: String in (group["items"] as Array):
			var node: Node3D = _by_path.get(object_path, null) as Node3D
			if node == null:
				node = _spawn_prop(object_path, anchor_node.position)
			if node != null and not items.has(node):
				items.append(node)
		_spread_on(items, anchor_node, String(group["mode"]))
	if not focus.is_empty() and _by_path.has(focus):
		_highlight(_by_path[focus] as Node3D, "focus")
	if not compared.is_empty() and _by_path.has(compared):
		_highlight(_by_path[compared] as Node3D, "compared")

	# 4. For a respond task the sentences name objects, so those objects have to be visible:
	#    the player answers from what they see, not from a word game.
	if action == "respond":
		for option: Variant in scenario.get("options", []):
			for lemma_id: String in _string_array((option as Dictionary).get("lemma_ids", [])):
				var object_path: String = _content.object_path(lemma_id)
				if object_path.is_empty() or _by_path.has(object_path):
					continue
				_spawn_prop(object_path, _next_candidate_position())

	# 5. A bring task names where the object goes: that target becomes clickable and marked.
	var delivery_kind: String = String(target.get("kind", ""))
	if action == "bring_deliver":
		if delivery_kind == "object" and _by_path.has(target_path):
			var delivery_node: Node3D = _by_path[target_path] as Node3D
			_enable_picking(delivery_node, "", "delivery")
			_highlight(delivery_node, "delivery")
		elif delivery_kind == "npc":
			var npc_name: String = String(target.get("npc", ""))
			var npc_node: Node3D = npc_node(npc_name)
			if npc_node != null:
				_highlight(npc_node, "delivery")

	# Origins are recorded last, after every placement has moved the objects.
	for option_id: String in _by_option:
		var node: Node3D = _by_option[option_id] as Node3D
		_option_origin[option_id] = node.position
	for entry: Dictionary in plan:
		entry["position"] = (_by_option[String(entry["id"])] as Node3D).position

	return {
		"options": plan,
		"delivery_kind": delivery_kind,
		"delivery_npc": String(target.get("npc", "")),
		"delivery_path": target_path,
		"slots_available": _slot_pool.size(),
		"staged": _staged.size(),
	}


func clear() -> void:
	for node: Node3D in _staged:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_staged.clear()
	for body: StaticBody3D in _colliders:
		if is_instance_valid(body):
			body.queue_free()
	_colliders.clear()
	for mesh: MeshInstance3D in _highlights:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_highlights.clear()
	_by_path.clear()
	_by_option.clear()
	_option_slot.clear()
	_option_origin.clear()
	_interactive.clear()
	# NPC pick bodies belong to the scene rather than to one scenario.
	for npc_name: String in _npc_bodies:
		_interactive[_npc_bodies[npc_name]] = {"kind": "npc", "npc": npc_name}
	_held_option_id = ""
	_hover_option_id = ""
	_slot_pool = []
	_used_slot_count = 0


func option_node(option_id: String) -> Node3D:
	return _by_option.get(option_id, null) as Node3D


func option_slot(option_id: String) -> int:
	return int(_option_slot.get(option_id, -1))


func option_position(option_id: String) -> Vector3:
	var node: Node3D = option_node(option_id)
	return node.position if node != null else Vector3.ZERO


## Centre of the clickable box around an option - the point a click has to land on.
func option_center(option_id: String) -> Vector3:
	var box: AABB = option_aabb(option_id)
	return box.get_center()


func option_aabb(option_id: String) -> AABB:
	var node: Node3D = option_node(option_id)
	return _world_aabb(node) if node != null else AABB()


## Where a staged prop ended up, so a check can confirm what the scenario stated about it.
func prop_aabb(scene_object: String) -> AABB:
	var node: Node3D = _by_path.get(scene_object, null) as Node3D
	return _world_aabb(node) if node != null else AABB()


func prop_center(scene_object: String) -> Vector3:
	var node: Node3D = _by_path.get(scene_object, null) as Node3D
	return _world_aabb(node).get_center() if node != null else Vector3.ZERO


func option_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _by_option:
		result.append(String(key))
	result.sort()
	return result


func staged_count() -> int:
	return _staged.size()


func set_held(option_id: String) -> void:
	if _held_option_id == option_id or not _by_option.has(option_id):
		return
	var node: Node3D = _by_option[option_id] as Node3D
	clear_held()
	if _tray == null:
		return
	var single: Array[Node3D] = [node]
	_spread_on(single, _tray, "on_top")
	_held_option_id = option_id
	_highlight(node, "held")


func held_option_id() -> String:
	return _held_option_id


func clear_held() -> void:
	if _held_option_id.is_empty():
		return
	var node: Node3D = _by_option.get(_held_option_id, null) as Node3D
	if node != null:
		node.position = _option_origin.get(_held_option_id, node.position) as Vector3
		_drop_highlight(node, "held")
	_held_option_id = ""


func place_delivered(option_id: String, delivery_kind: String, delivery_npc: String, delivery_path: String) -> void:
	var node: Node3D = _by_option.get(option_id, null) as Node3D
	if node == null:
		return
	if delivery_kind == "npc":
		var npc_node: Node3D = npc_node(delivery_npc)
		if npc_node != null:
			var offset: Vector3 = _vector3(_content.delivery_config().get("npc_offset", [0, 0.9, 0.8]))
			node.position = npc_node.position + offset
			_highlight(node, "held")
	elif delivery_kind == "object":
			var delivery_node: Node3D = _by_path.get(delivery_path, null) as Node3D
			if delivery_node != null:
				var single: Array[Node3D] = [node]
				_spread_on(single, delivery_node, "on_top")
			_highlight(node, "held")
	_held_option_id = option_id


func speak(npc_name: String) -> void:
	var node: Node3D = npc_node(npc_name)
	if node != null:
		_play_clip(node, String(_content.npc_config(npc_name).get("clips", {}).get("speak", "Interact")))


func idle_all() -> void:
	for npc_name: String in _npc_names():
		var node: Node3D = npc_node(npc_name)
		if node != null:
			_play_clip(node, String(_content.npc_config(npc_name).get("clips", {}).get("idle", "Idle")))


func set_hover(option_id: String) -> void:
	if _hover_option_id == option_id:
		return
	clear_hover()
	var node: Node3D = option_node(option_id)
	if node == null:
		return
	_hover_option_id = option_id
	_highlight(node, "hover")


func clear_hover() -> void:
	if _hover_option_id.is_empty():
		return
	_drop_highlight(option_node(_hover_option_id), "hover")
	_hover_option_id = ""


## Resolve a screen point to the clickable thing under it. The real mouse handler and the
## windowed probe both go through this one picking path.
func pick_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if camera == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera.project_position(screen_position, 0.0),
		camera.project_position(screen_position, 60.0),
		PICK_LAYER,
	)
	var space: PhysicsDirectSpaceState3D = _candidates.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Variant = hit.get("collider", null)
	if collider == null or not _interactive.has(collider):
		return {}
	return _interactive[collider] as Dictionary


# region staging internals

func _spawn_prop(scene_object: String, world_position: Vector3) -> Node3D:
	if scene_object.is_empty():
		return null
	var packed: Variant = load(scene_object)
	if not (packed is PackedScene):
		warnings.append("cannot load model %s" % scene_object)
		return null
	var node: Node3D = (packed as PackedScene).instantiate() as Node3D
	if node == null:
		warnings.append("model %s does not instantiate as Node3D" % scene_object)
		return null
	node.name = _scene_name(scene_object)
	_candidates.add_child(node)
	node.position = world_position
	_ground(node)
	_staged.append(node)
	_by_path[scene_object] = node
	return node


func _ground(node: Node3D) -> void:
	var box: AABB = _world_aabb(node)
	if box.size.y <= 0.0:
		return
	var local_low: float = box.position.y - node.position.y
	node.position = Vector3(node.position.x, GROUND_Y - local_low, node.position.z)


## Stand the given objects side by side on (on_top) or in front of (at_front) an anchor.
func _spread_on(items: Array[Node3D], anchor: Node3D, mode: String) -> void:
	if items.is_empty():
		return
	var anchor_box: AABB = _world_aabb(anchor)
	var boxes: Array[AABB] = []
	var total_width: float = 0.0
	for node: Node3D in items:
		var box: AABB = _world_aabb(node)
		boxes.append(box)
		total_width += box.size.x
	total_width += SPREAD_GAP * float(maxi(items.size() - 1, 0))
	var cursor: float = anchor_box.get_center().x - total_width * 0.5
	var front_z: float = anchor_box.position.z + anchor_box.size.z + FRONT_GAP
	for index: int in items.size():
		var node: Node3D = items[index]
		var box: AABB = boxes[index]
		var local_low: float = box.position.y - node.position.y
		var local_center: Vector3 = box.get_center() - node.position
		var center_x: float = cursor + box.size.x * 0.5
		cursor += box.size.x + SPREAD_GAP
		var position: Vector3 = node.position
		if mode == "on_top":
			position = Vector3(
				center_x - local_center.x,
				anchor_box.position.y + anchor_box.size.y - local_low,
				anchor_box.get_center().z - local_center.z,
			)
		else:
			position = Vector3(
				anchor_box.get_center().x - local_center.x,
				GROUND_Y - local_low,
				front_z + box.size.z * 0.5 - local_center.z,
			)
		node.position = position


func _next_candidate_position() -> Vector3:
	if _slot_pool.is_empty():
		return Vector3(0.0, GROUND_Y, 0.0)
	var index: int = mini(_used_slot_count, _slot_pool.size() - 1)
	_used_slot_count += 1
	return _vector3(_slot_pool[index])


func _enable_picking(node: Node3D, option_id: String, role: String = "option") -> void:
	var body: StaticBody3D = _add_collider(node, "%sPickBody" % node.name, false)
	if body == null:
		return
	if option_id.is_empty():
		_interactive[body] = {"kind": role, "option_id": option_id}
	else:
		_interactive[body] = {"kind": "option", "option_id": option_id}


func _add_collider(node: Node3D, body_name: String, persistent: bool) -> StaticBody3D:
	var box: AABB = _world_aabb(node)
	if box.size.length() <= 0.0:
		return null
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size * 1.06
	shape.shape = box_shape
	body.add_child(shape)
	_candidates.add_child(body)
	body.global_position = box.get_center()
	if not persistent:
		_colliders.append(body)
	return body


func _highlight(node: Node3D, kind: String) -> void:
	if node == null:
		return
	var box: AABB = _world_aabb(node)
	if box.size.length() <= 0.0:
		return
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "%sHighlight_%s" % [kind, node.name]
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = box.size * 1.12
	mesh.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _content.highlight_color(kind, Color(1, 1, 1, 0.4))
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_candidates.add_child(mesh)
	mesh.global_position = box.get_center()
	_highlights.append(mesh)


func _drop_highlight(node: Node3D, kind: String) -> void:
	if node == null:
		return
	var marker: String = "%sHighlight_%s" % [kind, node.name]
	for index: int in range(_highlights.size() - 1, -1, -1):
		var mesh: MeshInstance3D = _highlights[index]
		if is_instance_valid(mesh) and String(mesh.name) == marker:
			mesh.queue_free()
			_highlights.remove_at(index)


func _ensure_tray() -> void:
	if _tray != null:
		return
	var config: Dictionary = _content.hold_config()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "HoldTray"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = _vector3(config.get("tray_size", [1.0, 0.1, 0.8]))
	mesh.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.22, 0.26, 1.0)
	mesh.material_override = material
	_candidates.add_child(mesh)
	mesh.position = _vector3(config.get("tray_position", [0, 0.9, 4.5]))
	_tray = mesh


func _npc_names() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in (_content.room.get("npcs", {}) as Dictionary):
		result.append(String(key))
	result.sort()
	return result


## The scene node of an npc. Scene node names may differ in case from the npc keys in the
## room data (Knight in the scene, "knight" in the data), so the match ignores case.
func npc_node(npc_name: String) -> Node3D:
	var wanted: String = npc_name.to_lower()
	for child: Node in _npcs.get_children():
		var name_lower: String = String(child.name).to_lower()
		if name_lower == wanted or name_lower == wanted + "npc" or name_lower == wanted + "_npc":
			return child as Node3D if child is Node3D else null
	return null


func _play_clip(node: Node3D, clip: String) -> void:
	if clip.is_empty():
		return
	var player: AnimationPlayer = _find_animation_player(node)
	if player == null:
		warnings.append("%s has no AnimationPlayer" % node.name)
		return
	if not player.get_animation_list().has(clip):
		warnings.append("%s is missing clip %s" % [node.name, clip])
		return
	player.play(clip)


func _placement_keys(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in state:
		if Lex01Content.SCENE_STATE_SPECIAL_KEYS.has(key):
			continue
		result.append(key)
	result.sort()
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


func _shuffled(values: Array) -> Array:
	var result: Array = values.duplicate()
	for i: int in range(result.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: Variant = result[i]
		result[i] = result[j]
		result[j] = swap
	return result


func _world_aabb(node: Node3D) -> AABB:
	# The eight world-space corners of every mesh under the node - the same measurement
	# tools/prep_probe.gd already uses on these props.
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
	var low: Vector3 = box.position
	var high: Vector3 = box.position + box.size
	return [
		low,
		Vector3(high.x, low.y, low.z),
		Vector3(low.x, high.y, low.z),
		Vector3(low.x, low.y, high.z),
		Vector3(high.x, high.y, low.z),
		Vector3(high.x, low.y, high.z),
		Vector3(low.x, high.y, high.z),
		high,
	]


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(String(entry))
	return result


func _vector3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

# endregion
