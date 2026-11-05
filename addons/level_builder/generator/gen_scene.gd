@tool
extends Object

# Reading generation back out of the scene.
#
# Every unit node carries its own plan entry as metadata, so "what's already
# here" is a question the scene answers by itself. No sidecar file to get out
# of sync, and deleting a room by hand is a supported edit rather than a
# corruption — it just isn't there next time we look.
#
# This is the half of the editing contract that makes locks possible.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")

const LOCK_META := "lb_locked"


static func generated_root(root: Node, container_name: String) -> Node:
	var container: Node = root.get_node_or_null(NodePath(container_name))
	if container == null:
		return null
	return container.get_node_or_null(NodePath(TYPES.GEN_ROOT_NAME))


# unit_id -> {container_name: Node}. A unit spans up to three containers and
# locks move all of it or none of it.
static func unit_nodes(root: Node) -> Dictionary:
	var found := {}
	for container_name in TYPES.CONTAINERS:
		var generated := generated_root(root, container_name)
		if generated == null:
			continue
		for child in generated.get_children():
			if not child.has_meta("lb_unit_id"):
				continue
			var unit_id := String(child.get_meta("lb_unit_id"))
			if not found.has(unit_id):
				found[unit_id] = {}
			(found[unit_id] as Dictionary)[container_name] = child
	return found


# The plan entries for everything currently in the scene, rebuilt from metadata.
static func read_units(root: Node) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	var generated := generated_root(root, "Geometry")
	if generated == null:
		return units
	for child in generated.get_children():
		if not (child.has_meta("lb_unit_id") and child.has_meta("lb_rect")):
			continue
		var unit := {
			"id": String(child.get_meta("lb_unit_id")),
			"kind": String(child.get_meta("lb_unit_kind", "room")),
			"type": String(child.get_meta("lb_unit_type", "")),
			"layer": String(child.get_meta("lb_unit_layer", "level")),
			"rect": child.get_meta("lb_rect") as Rect2i,
			"base_y": float(child.get_meta("lb_base_y", 0.0)),
			"walls": bool(child.get_meta("lb_walls", true)),
			"seed": int(child.get_meta("lb_seed", 0)),
			"locked": bool(child.get_meta(LOCK_META, false)),
		}
		if child.has_meta("lb_poi_layer"):
			unit["poi_layer"] = String(child.get_meta("lb_poi_layer"))
		if child.has_meta("lb_axis"):
			unit["axis"] = child.get_meta("lb_axis") as Vector2i
		var per_cell: Dictionary = child.get_meta("lb_heights", {})
		if not per_cell.is_empty():
			unit["heights"] = per_cell
		var cells: Array = child.get_meta("lb_cells", [])
		if not cells.is_empty():
			unit["cells"] = cells
		units.append(unit)
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return units


static func scope_of(root: Node) -> int:
	var generated := generated_root(root, "Geometry")
	if generated == null or not generated.has_meta("lb_gen_scope"):
		return -1
	return int(generated.get_meta("lb_gen_scope"))


static func seed_of(root: Node) -> int:
	var generated := generated_root(root, "Geometry")
	if generated == null:
		return 0
	return int(generated.get_meta("lb_gen_seed", 0))


static func set_locked(root: Node, unit_id: String, locked: bool, undo = null) -> void:
	var nodes: Dictionary = unit_nodes(root).get(unit_id, {})
	for container_name in nodes:
		var node: Node = nodes[container_name]
		if undo:
			undo.add_do_method(node, "set_meta", LOCK_META, locked)
			undo.add_undo_method(node, "set_meta", LOCK_META, node.get_meta(LOCK_META, false))
		else:
			node.set_meta(LOCK_META, locked)


# What regeneration must not move.
#
# A lock spreads exactly one hop, and only along the connections that would
# otherwise break: locking a room pins the corridors touching it, because those
# corridors have no wall on the shared edge and rebuilding one side without the
# other leaves a doorway opening onto a wall. Locking anything inside a POI pins
# that whole building and its plot — a half-regenerated building is nobody's
# idea of a feature.
static func pinned_units(root: Node) -> Array[Dictionary]:
	var units := read_units(root)
	# Which layers are POI buildings, learned from the plots that own them. Only
	# these propagate by layer — a level's rooms all share one layer, and pinning
	# that would mean locking any room locked the whole building.
	var poi_layers := {}
	for unit in units:
		if unit.has("poi_layer"):
			poi_layers[String(unit["poi_layer"])] = true

	var pinned := {}
	var pinned_pois := {}
	for unit in units:
		if not bool(unit["locked"]):
			continue
		if String(unit["kind"]) == "road":
			continue  # roads have no walls and cost nothing to redraw — never pinned
		pinned[String(unit["id"])] = true
		if unit.has("poi_layer"):
			pinned_pois[String(unit["poi_layer"])] = true
		if poi_layers.has(String(unit["layer"])):
			pinned_pois[String(unit["layer"])] = true

	# a locked POI plot pins its building, and anything inside pins the plot
	for unit in units:
		if pinned_pois.has(String(unit["layer"])):
			pinned[String(unit["id"])] = true
		if unit.has("poi_layer") and pinned_pois.has(String(unit["poi_layer"])):
			pinned[String(unit["id"])] = true

	# one hop: corridors touching a pinned room
	for unit in units:
		if String(unit["kind"]) != "corridor" or pinned.has(String(unit["id"])):
			continue
		for other in units:
			if not pinned.has(String(other["id"])) or String(other["kind"]) != "room":
				continue
			if String(other["layer"]) != String(unit["layer"]):
				continue
			if (unit["rect"] as Rect2i).intersects((other["rect"] as Rect2i).grow(1)):
				pinned[String(unit["id"])] = true
				break

	var out: Array[Dictionary] = []
	for unit in units:
		if pinned.has(String(unit["id"])):
			out.append(unit)
	return out


static func locked_ids(root: Node) -> PackedStringArray:
	var ids := PackedStringArray()
	for unit in read_units(root):
		if bool(unit["locked"]):
			ids.append(String(unit["id"]))
	return ids
