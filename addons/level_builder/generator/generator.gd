@tool
extends Object

# The pipeline, in one place: plan → shell → routes → props → gameplay →
# validate. One entry point per half — generate() is pure and builds a detached
# subtree, apply() is the only thing that touches the edited scene.
#
# Splitting it that way is what lets verify run 50 seeds a scope headless, and
# what makes the whole thing one undo step in the editor.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const LEVEL_PLANNER := preload("res://addons/level_builder/generator/level_planner.gd")
const WORLD_PLANNER := preload("res://addons/level_builder/generator/world_planner.gd")
const COURT_PLANNER := preload("res://addons/level_builder/generator/court_planner.gd")
const SHELL_BUILDER := preload("res://addons/level_builder/generator/shell_builder.gd")
const ROUTE_SOLVER := preload("res://addons/level_builder/generator/route_solver.gd")
const PROP_SOLVER := preload("res://addons/level_builder/generator/prop_solver.gd")
const GAMEPLAY_PASS := preload("res://addons/level_builder/generator/gameplay_pass.gd")
const GEN_VALIDATE := preload("res://addons/level_builder/generator/gen_validate.gd")
const GEN_SCENE := preload("res://addons/level_builder/generator/gen_scene.gd")
const SPACE_SCANNER := preload("res://addons/level_builder/generator/space_scanner.gd")
const STYLE_PASS := preload("res://addons/level_builder/generator/style_pass.gd")
const BOOTSTRAP := preload("res://addons/level_builder/editor/scene_bootstrap.gd")
const BRIEF := preload("res://addons/level_builder/resources/generation_brief.gd")

const SPAWN_LIFT := 1.0
const SELF := "res://addons/level_builder/generator/generator.gd"


# Plans and builds, detached from any scene. Free the returned nodes with
# discard() if you don't apply them.
#
# `pinned` are units already standing in the scene that must not move — locked
# rooms and the corridors hanging off them, from gen_scene.pinned_units(). They
# come back in the plan flagged "kept" so nothing rebuilds them, but they're
# still in the occupancy map, so new walls and validation see them.
static func generate(brief: Resource, pinned: Array = []) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {
		"ok": false,
		"scope": int(brief.scope),
		"seed": int(brief.rng_seed),
		"kit": null,
		"plan": {},
		"props": {},
		"repairs": {},
		"nodes": {},
		"spawn": Vector3.ZERO,
		"has_terrain": false,
		"findings": [],
		"stats": {},
	}

	var kit := LIBRARY.kit(String(brief.kit_id))
	if kit == null:
		result["findings"] = [_red("gen_kit_missing",
			"No kit profile found. Generation needs a kit_*.tres in addons/level_builder/defaults/generation/.")]
		return result
	# the library falls back to the first kit rather than crashing, and a typo'd
	# id shouldn't quietly build with the wrong one
	var wrong_kit := String(kit.kit_id) != String(brief.kit_id)
	result["kit"] = kit
	var missing: PackedStringArray = kit.missing_pieces()
	if missing.size() > 0:
		result["findings"] = [_red("gen_kit_missing",
			"Kit '%s' can't find its pieces: %s. Point the kit profile at scenes that exist."
			% [kit.display_name, ", ".join(missing)])]
		return result

	var plan := _plan(brief, kit, pinned)
	if plan.is_empty():
		result["findings"] = [_red("gen_no_archetype",
			"No %s archetype called '%s'. Add one in defaults/generation/."
			% [TYPES.SCOPE_NAMES[int(brief.scope)].to_lower(), brief.archetype_id])]
		return result
	plan["palette_id"] = String(brief.palette_id)
	result["plan"] = plan

	var palette := LIBRARY.palette(String(brief.palette_id))
	result["palette"] = palette
	var repairs := {}
	result["props"] = _furnish(plan, kit, repairs, palette, float(brief.density))
	result["repairs"] = repairs
	result["nodes"] = _build_nodes(plan, result["props"], kit)
	result["has_terrain"] = plan.has("terrain")
	result["spawn"] = _spawn_position(plan, kit)
	result["findings"] = GEN_VALIDATE.validate(result)
	if wrong_kit:
		result["findings"].append({"id": "gen_kit_fallback", "severity": "amber", "fixable": false,
			"message": "No kit called '%s' — built with '%s' instead." % [brief.kit_id, kit.kit_id]})
	if palette != null and String(palette.palette_id) != String(brief.palette_id):
		result["findings"].append({"id": "gen_palette_fallback", "severity": "amber", "fixable": false,
			"message": "No style palette called '%s' — used '%s' instead." % [brief.palette_id, palette.palette_id]})
	result["ok"] = _no_reds(result["findings"])
	result["stats"] = {
		"units": (plan["units"] as Array).size(),
		"props": _count_props(result["props"]),
		"rejected": _count_rejected(repairs),
		"repaired": _count_repaired(repairs),
		"msec": (Time.get_ticks_usec() - started) / 1000.0,
	}
	return result


# Attaches a generated result to the edited scene as ONE undo step: containers,
# spawn move and (at world scope) the ground swap all ride in the same action.
static func apply(result: Dictionary, root: Node, undo = null, replace_ground: bool = true) -> bool:
	if not result.get("ok", false) or root == null:
		return false
	var nodes: Dictionary = result["nodes"]
	var kept_ids := {}
	for unit in result["plan"]["units"]:
		if bool(unit.get("kept", false)):
			kept_ids[String(unit["id"])] = true
	var standing := GEN_SCENE.unit_nodes(root)

	for container_name in TYPES.CONTAINERS:
		var generated: Node3D = nodes.get(container_name, null)
		if generated == null:
			continue
		var container := _ensure_container(root, container_name, undo)
		var existing: Node = container.get_node_or_null(NodePath(TYPES.GEN_ROOT_NAME))
		# Locked units move across before the old container goes: same nodes,
		# same names, same everything. That's what "byte-identical" means here —
		# nothing is rebuilt from a plan, the node itself is carried over.
		var carried := 0
		for unit_id in kept_ids:
			var kept: Node = (standing.get(unit_id, {}) as Dictionary).get(container_name, null)
			if kept == null:
				continue
			_reparent(kept, generated, undo)
			carried += 1
		if existing:
			_remove(container, existing, root, undo)
		# under undo nothing has actually moved yet, so count what will be there
		if generated.get_child_count() + carried == 0:
			generated.free()
			nodes[container_name] = null
			continue
		_add(container, generated, root, undo)

	if bool(result.get("has_terrain", false)) and replace_ground:
		var ground: Node = root.get_node_or_null(^"Geometry/Ground")
		if ground:
			_remove(ground.get_parent(), ground, root, undo)

	_move_spawn(root, Vector3(result["spawn"]) + Vector3.UP * SPAWN_LIFT, undo)
	return true


# Furnish a space the user built themselves.
#
# No shell is planned or emitted — the scanner reads their walls, the same route
# and prop solvers do the rest, and the only geometry we add is an empty marker
# node carrying the unit's metadata so locks and re-roll work on it like anything
# else. Props never land outside the scanned region, by construction: the solver
# grid IS the region.
static func fill_selection(root: Node, bounds: AABB, archetype_id: String, seed_value: int,
		undo = null) -> Dictionary:
	var kit := _scene_kit(root)
	if kit == null or kit.missing_pieces().size() > 0:
		return {"ok": false, "message": "The greybox kit isn't available to measure the grid with."}
	var arch := LIBRARY.room_archetype(archetype_id)
	if arch == null or String(arch.archetype_id) != archetype_id:
		return {"ok": false, "message": "No room archetype called '%s'." % archetype_id}
	if not (root is Node3D) or not root.is_inside_tree():
		return {"ok": false, "message": "Fill selection needs the scene open — it reads your walls with physics."}

	# look through whatever a previous fill left here, if anything
	var scan := SPACE_SCANNER.scan(root, bounds, kit, _fill_ignore(root, bounds, kit))
	if not bool(scan["ok"]):
		return {"ok": false, "message": String(scan["message"])}

	var rect: Rect2i = scan["rect"]
	var cpm := TYPES.cells_per_module(kit)
	var module_lo := TYPES.module_of(rect.position, cpm)
	var module_hi := TYPES.module_of(rect.end - Vector2i.ONE, cpm)
	# base_y is set so the solver's surface height lands on the floor we measured
	var unit := _unit(_fill_id(root, rect), "scan", archetype_id,
		Rect2i(module_lo, module_hi - module_lo + Vector2i.ONE),
		"fill", float(scan["floor_y"]) - float(kit.floor_thickness), seed_value, false)

	var grid: Dictionary = ROUTE_SOLVER.reserve(scan["grid"], scan["doors"])
	var palette := _scene_palette(root)
	var placements := PROP_SOLVER.furnish(unit, grid, arch, kit, TYPES.rng_for(seed_value), {}, palette)
	placements.append_array(STYLE_PASS.decorate(unit, grid, palette, kit,
		TYPES.rng_for(TYPES.derive_seed(seed_value, "style")), placements))
	if placements.is_empty():
		return {"ok": false,
			"message": "Nothing fits in there — the space is smaller than a %s needs, or the doorways use all of it." % arch.display_name}

	var unit_id := String(unit["id"])
	var marker := Node3D.new()
	marker.name = TYPES.unit_node_name(unit_id)
	marker.set_meta("lb_unit_id", unit_id)
	marker.set_meta("lb_unit_kind", "scan")
	marker.set_meta("lb_unit_layer", "fill")
	marker.set_meta("lb_unit_type", archetype_id)
	marker.set_meta("lb_rect", unit["rect"])
	marker.set_meta("lb_base_y", float(unit["base_y"]))
	marker.set_meta("lb_walls", false)
	marker.set_meta("lb_seed", seed_value)
	marker.set_meta("lb_fill_bounds", bounds)

	var group := Node3D.new()
	group.name = marker.name
	group.set_meta("lb_unit_id", unit_id)
	for placement in placements:
		var instance := _instance_prop(placement)
		if instance:
			group.add_child(instance)

	# Replace by overlap, not by name. A name derived from where the scan started
	# collides when two different spaces happen to start at the same cell, and
	# orphans the old fill when a wall moves and the scan comes out a cell
	# different. Overlapping the space you just filled is the actual question.
	_clear_overlapping_fills(root, unit["rect"], undo)
	_replace_in_generated(root, "Geometry", marker, undo)
	_replace_in_generated(root, "Props", group, undo)
	return {"ok": true, "unit": unit_id, "props": placements.size(), "cells": int(scan["cells"]),
		"doors": (scan["doors"] as Array).size(),
		"message": "%s: %d props in %d m² of your space, %d doorway(s) kept clear." % [
			unit_id, placements.size(), int(scan["cells"]), (scan["doors"] as Array).size()]}


# A re-fill has to look through its own previous furniture. The unit id is
# derived from where the space is, so we can find last time's props before we
# know this time's answer.
static func _fill_ignore(root: Node, bounds: AABB, kit: Resource) -> Array:
	var ignore: Array = []
	var props_root := GEN_SCENE.generated_root(root, "Props")
	if props_root == null:
		return ignore
	for child in props_root.get_children():
		if not child.has_meta("lb_unit_id"):
			continue
		if not String(child.get_meta("lb_unit_id")).begins_with("Fill_"):
			continue
		if not bounds.intersects(SPACE_SCANNER.node_bounds(child)):
			continue
		ignore.append_array(SPACE_SCANNER.body_rids(child))
	return ignore


# Whatever kit this scene was generated with, falling back to greybox for a
# scene the generator has never touched (which is the fill-selection case).
# Whatever palette this scene was dressed with, so a re-roll or a fill doesn't
# quietly hand a ruined room clean furniture.
static func _scene_palette(root: Node) -> Resource:
	var generated := GEN_SCENE.generated_root(root, "Geometry")
	if generated and generated.has_meta("lb_palette"):
		var found := LIBRARY.palette(String(generated.get_meta("lb_palette")))
		if found:
			return found
	return LIBRARY.palette("")


static func _scene_kit(root: Node) -> Resource:
	var generated := GEN_SCENE.generated_root(root, "Geometry")
	if generated and generated.has_meta("lb_kit"):
		var kit := LIBRARY.kit(String(generated.get_meta("lb_kit")))
		if kit:
			return kit
	return LIBRARY.kit("greybox")


# Anything previously filled that shares ground with what we're about to fill.
static func _clear_overlapping_fills(root: Node, rect: Rect2i, undo) -> void:
	var doomed := PackedStringArray()
	for unit in GEN_SCENE.read_units(root):
		if not String(unit["id"]).begins_with("Fill_"):
			continue
		if (unit["rect"] as Rect2i).intersects(rect):
			doomed.append(String(unit["id"]))
	if doomed.is_empty():
		return
	var standing := GEN_SCENE.unit_nodes(root)
	for unit_id in doomed:
		for container_name in (standing.get(unit_id, {}) as Dictionary):
			var node: Node = (standing[unit_id] as Dictionary)[container_name]
			_remove(node.get_parent(), node, root, undo)


static func _fill_id(root: Node, rect: Rect2i) -> String:
	# position-derived so re-filling the same space replaces rather than stacks
	return "Fill_%d_%d" % [rect.position.x, rect.position.y]


static func _replace_in_generated(root: Node, container_name: String, node: Node, undo) -> void:
	var container := _ensure_container(root, container_name, undo)
	var generated: Node = container.get_node_or_null(NodePath(TYPES.GEN_ROOT_NAME))
	if generated == null:
		generated = Node3D.new()
		generated.name = TYPES.GEN_ROOT_NAME
		_add(container, generated, root, undo)
	var existing: Node = generated.get_node_or_null(NodePath(node.name))
	if existing:
		_remove(generated, existing, root, undo)
	_add(generated, node, root, undo)


# Re-roll one room's furniture and nothing else.
#
# Reads the shell straight back out of the scene, so every rect stays put and
# only this room's Props and Gameplay subtrees are replaced. Neighbours can't
# change because nothing outside this unit is even looked at, let alone touched.
static func regenerate_unit(root: Node, unit_id: String, new_seed: int, undo = null) -> Dictionary:
	var kit := _scene_kit(root)
	if kit == null:
		return {"ok": false, "message": "No kit profile to build with."}

	var units := GEN_SCENE.read_units(root)
	var unit := LEVEL_PLANNER.unit_by_id(units, unit_id)
	if unit.is_empty():
		return {"ok": false, "message": "No generated unit called '%s' in this scene." % unit_id}
	if String(unit["kind"]) == "scan":
		# a filled selection re-scans: the walls are the user's and may have moved
		var shell_node: Node = (GEN_SCENE.unit_nodes(root).get(unit_id, {}) as Dictionary).get("Geometry", null)
		if shell_node == null or not shell_node.has_meta("lb_fill_bounds"):
			return {"ok": false, "message": "Lost track of what '%s' was filling — re-run Fill selection." % unit_id}
		return fill_selection(root, shell_node.get_meta("lb_fill_bounds") as AABB,
			String(unit["type"]), new_seed, undo)
	if String(unit["kind"]) != "room" or String(unit["type"]) == "":
		return {"ok": false, "message": "Only rooms carry furniture — '%s' is a %s." % [unit_id, unit["kind"]]}
	var arch := LIBRARY.room_archetype(String(unit["type"]))
	if arch == null:
		return {"ok": false, "message": "No room archetype called '%s'." % unit["type"]}

	var same_layer := units.filter(func(u: Dictionary) -> bool: return String(u["layer"]) == String(unit["layer"]))
	var occupancy := LEVEL_PLANNER.occupancy_of(same_layer)
	var grid := ROUTE_SOLVER.solve(unit, occupancy, kit)
	var palette := _scene_palette(root)
	var placements := PROP_SOLVER.furnish(unit, grid, arch, kit, TYPES.rng_for(new_seed), {}, palette)
	placements.append_array(STYLE_PASS.decorate(unit, grid, palette, kit,
		TYPES.rng_for(TYPES.derive_seed(new_seed, "style")), placements))

	var group := Node3D.new()
	group.name = TYPES.unit_node_name(unit_id)
	group.set_meta("lb_unit_id", unit_id)
	for placement in placements:
		var instance := _instance_prop(placement)
		if instance:
			group.add_child(instance)

	var props_root := GEN_SCENE.generated_root(root, "Props")
	if props_root == null:
		group.free()
		return {"ok": false, "message": "This scene has no generated props to replace."}
	var existing: Node = props_root.get_node_or_null(NodePath(group.name))
	if existing:
		_remove(props_root, existing, root, undo)
	_add(props_root, group, root, undo)
	if undo:
		var shell: Node = (GEN_SCENE.unit_nodes(root).get(unit_id, {}) as Dictionary).get("Geometry", null)
		if shell:
			undo.add_do_method(shell, "set_meta", "lb_seed", new_seed)
			undo.add_undo_method(shell, "set_meta", "lb_seed", int(unit["seed"]))
	else:
		var shell_node: Node = (GEN_SCENE.unit_nodes(root).get(unit_id, {}) as Dictionary).get("Geometry", null)
		if shell_node:
			shell_node.set_meta("lb_seed", new_seed)
	return {"ok": true, "props": placements.size(),
		"message": "%s re-rolled: %d props, seed %d." % [unit_id, placements.size(), new_seed]}


static func discard(result: Dictionary) -> void:
	for key in result.get("nodes", {}):
		var node: Node = result["nodes"][key]
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	result["nodes"] = {}


# ---- planning --------------------------------------------------------------

# What the creator asked for, as the planners see it.
static func _shape_of(brief: Resource) -> Dictionary:
	return {"density": float(brief.density), "openness": float(brief.openness),
		"branching": float(brief.branching)}


static func _plan(brief: Resource, kit: Resource, pinned: Array) -> Dictionary:
	match int(brief.scope):
		BRIEF.Scope.ROOM:
			return _plan_room(brief, kit, pinned)
		BRIEF.Scope.LEVEL:
			return _plan_level(brief, kit, pinned)
		BRIEF.Scope.WORLD:
			return _plan_world(brief, kit, pinned)
	return {}


# A standalone room gets a one-module stoop outside its door: it gives the
# shell somewhere to leave an opening, and you somewhere to spawn and walk in
# from. Fill-selection mode (M2) replaces this with your own walls.
static func _plan_room(brief: Resource, kit: Resource, pinned: Array) -> Dictionary:
	var arch := LIBRARY.room_archetype(String(brief.archetype_id))
	if arch == null or String(arch.archetype_id) != String(brief.archetype_id):
		return {}
	# A room scope is one room and its stoop, and the stoop's doorway only lines
	# up with the walls either side of it. Lock either and you've locked both —
	# to re-roll just the furniture, use regenerate_unit().
	if not pinned.is_empty():
		return _plan_from_pinned(pinned, "room", kit)
	var seed_value := int(brief.rng_seed)
	var rng := TYPES.rng_for(seed_value)
	var size := _room_size(arch, int(brief.size_class), rng, float(brief.openness))
	var room := _unit("Room_0", "room", String(arch.archetype_id), Rect2i(Vector2i.ZERO, size),
		"room", 0.0, TYPES.derive_seed(seed_value, "room:0:" + String(arch.archetype_id)), true)
	var stoop_x := rng.randi_range(0, size.x - 1)
	var stoop := _unit("Entry", "corridor", "", Rect2i(Vector2i(stoop_x, -1), Vector2i.ONE),
		"room", 0.0, TYPES.derive_seed(seed_value, "entry"), false)
	var units: Array[Dictionary] = [room, stoop]
	return {
		"scope": BRIEF.Scope.ROOM,
		"seed": seed_value,
		"units": units,
		"layers": {"room": LEVEL_PLANNER.occupancy_of(units)},
		"bounds": LEVEL_PLANNER.bounds_of(units),
		"entry_unit": "Entry",
		"goal_unit": "Room_0",
		"spawn_layer": "room",
		# the stoop never gets furniture, so its middle is always standable
		"spawn_cell": TYPES.module_centre_cell(Vector2i(stoop_x, -1), TYPES.cells_per_module(kit)),
	}


static func _plan_level(brief: Resource, kit: Resource, pinned: Array) -> Dictionary:
	var arch := LIBRARY.level_archetype(String(brief.archetype_id))
	if arch == null or String(arch.archetype_id) != String(brief.archetype_id):
		return {}
	var plan := plan_level_with(arch, int(brief.size_class), int(brief.rng_seed),
		"level", 0.0, "", _pinned_on_layer(pinned, "level"), _shape_of(brief))
	plan["scope"] = BRIEF.Scope.LEVEL
	plan["layers"] = {String(plan["layer"]): plan["occupancy"]}
	plan["spawn_layer"] = String(plan["layer"])
	# You arrive outside the front door if there is one, and in the entrance hall
	# if there isn't. The yard never gets furniture, so its middle is always free.
	var arrival := LEVEL_PLANNER.unit_by_id(plan["units"], String(plan.get("yard_unit", "")))
	if arrival.is_empty():
		arrival = LEVEL_PLANNER.unit_by_id(plan["units"], String(plan["entry_unit"]))
	plan["spawn_cell"] = ROUTE_SOLVER.centre_cell(arrival, kit) if not arrival.is_empty() else Vector2i.ZERO
	return plan


static func _plan_world(brief: Resource, kit: Resource, pinned: Array) -> Dictionary:
	var arch := LIBRARY.world_archetype(String(brief.archetype_id))
	if arch == null or String(arch.archetype_id) != String(brief.archetype_id):
		return {}
	var plan := WORLD_PLANNER.plan(arch, int(brief.size_class), int(brief.rng_seed),
		bool(brief.generate_interiors), kit, pinned, _shape_of(brief))
	plan["scope"] = BRIEF.Scope.WORLD
	plan["entry_unit"] = String(plan["pois"][0]["pad_unit"]) if not (plan["pois"] as Array).is_empty() else ""
	plan["goal_unit"] = ""
	return plan


# Size class picks which end of the archetype's own range to roll in — it never
# goes outside it. min_modules means minimum: shrink a smithy past the point
# where a forge fits and it stops being a smithy. Widen the archetype if you
# want bigger rooms.
static func _room_size(arch: Resource, size_class: int, rng: RandomNumberGenerator,
		openness: float = 0.5) -> Vector2i:
	var lo: Vector2i = arch.min_modules.max(Vector2i.ONE)
	var hi: Vector2i = (arch.max_modules as Vector2i).max(lo)
	match size_class:
		0:
			hi = lo + (hi - lo) / 2
		2:
			lo = hi - (hi - lo) / 2
	var bias := Vector2i(
		int(round(float(hi.x - lo.x) * (openness - 0.5))),
		int(round(float(hi.y - lo.y) * (openness - 0.5))))
	var low := (lo + bias.max(Vector2i.ZERO)).min(hi)
	var high := (hi + bias.min(Vector2i.ZERO)).max(low)
	return Vector2i(rng.randi_range(low.x, high.x), rng.randi_range(low.y, high.y))


static func _unit(id: String, kind: String, type_id: String, rect: Rect2i,
		layer: String, base_y: float, seed_value: int, walls: bool) -> Dictionary:
	return {"id": id, "kind": kind, "type": type_id, "rect": rect, "layer": layer,
		"base_y": base_y, "seed": seed_value, "walls": walls}


static func _pinned_on_layer(pinned: Array, layer: String) -> Array:
	var out: Array = []
	for unit in pinned:
		if String(unit["layer"]) == layer:
			out.append(unit)
	return out


# Everything already standing, nothing new: what a fully locked scope looks like.
static func _plan_from_pinned(pinned: Array, layer: String, kit: Resource) -> Dictionary:
	var units: Array[Dictionary] = []
	var entry := ""
	var goal := ""
	for entry_unit in pinned:
		var kept: Dictionary = (entry_unit as Dictionary).duplicate()
		kept["kept"] = true
		units.append(kept)
		if String(kept["kind"]) == "room" and goal == "":
			goal = String(kept["id"])
		if String(kept["kind"]) == "corridor" and entry == "":
			entry = String(kept["id"])
	if entry == "":
		entry = goal
	var spawn_unit := LEVEL_PLANNER.unit_by_id(units, entry)
	return {
		"scope": BRIEF.Scope.ROOM,
		"seed": 0,
		"units": units,
		"layers": {layer: LEVEL_PLANNER.occupancy_of(units)},
		"bounds": LEVEL_PLANNER.bounds_of(units),
		"entry_unit": entry,
		"goal_unit": goal,
		"spawn_layer": layer,
		"spawn_cell": TYPES.module_centre_cell((spawn_unit["rect"] as Rect2i).position,
			TYPES.cells_per_module(kit)) if not spawn_unit.is_empty() else Vector2i.ZERO,
	}


# The archetype says which planner arranges it. Everything downstream — shells,
# zones, furniture, style, validation — takes the same units either way and
# never asks how they were arrived at, which is the only reason a second
# topology costs one file instead of a rewrite.
static func plan_level_with(arch: Resource, size_class: int, seed_value: int, layer: String,
		base_y: float, id_prefix: String, pinned: Array, shape: Dictionary) -> Dictionary:
	if String(arch.planner) == "court" and pinned.is_empty():
		return COURT_PLANNER.plan(arch, size_class, seed_value, layer, base_y, id_prefix, pinned, shape)
	# Locks are the tree planner's: it knows how to grow around what's already
	# standing, and a court can't be rearranged around a pinned room without
	# moving the middle. Regenerating a locked court falls back to a building.
	return LEVEL_PLANNER.plan(arch, size_class, seed_value, layer, base_y, id_prefix, pinned, shape)


# ---- furnishing ------------------------------------------------------------

static func _furnish(plan: Dictionary, kit: Resource, repairs: Dictionary,
		palette: Resource = null, density: float = 0.5) -> Dictionary:
	var props := {}
	var layers: Dictionary = plan["layers"]
	for unit in plan["units"]:
		if String(unit["kind"]) != "room" or String(unit["type"]) == "":
			continue
		if bool(unit.get("kept", false)):
			continue  # already furnished and locked — its props stay as they are
		var arch := LIBRARY.room_archetype(String(unit["type"]))
		if arch == null:
			continue
		var occupancy: Dictionary = layers.get(String(unit["layer"]), {})
		var grid := ROUTE_SOLVER.solve(unit, occupancy, kit)
		var report := {}
		var placements := PROP_SOLVER.furnish(unit, grid, arch, kit,
			TYPES.rng_for(int(unit["seed"])), report, palette, density)
		repairs[String(unit["id"])] = report
		if placements.is_empty():
			continue
		# style goes on last, over a room that already works
		placements.append_array(STYLE_PASS.decorate(unit, grid, palette, kit,
			TYPES.rng_for(TYPES.derive_seed(int(unit["seed"]), "style")), placements))
		props[String(unit["id"])] = placements
	return props


# ---- building --------------------------------------------------------------

static func _build_nodes(plan: Dictionary, props: Dictionary, kit: Resource) -> Dictionary:
	var geometry := _gen_root()
	geometry.set_meta("lb_gen_seed", int(plan["seed"]))
	geometry.set_meta("lb_gen_scope", int(plan["scope"]))
	geometry.set_meta("lb_kit", String(kit.kit_id))
	geometry.set_meta("lb_palette", String(plan.get("palette_id", "")))
	if plan.has("terrain"):
		geometry.add_child(SHELL_BUILDER.build_terrain(plan["terrain"], kit, plan.get("ground", {})))
	# kept units are already in the scene; apply() moves them across untouched
	var fresh: Array = plan["units"].filter(func(u: Dictionary) -> bool: return not bool(u.get("kept", false)))
	var shells := SHELL_BUILDER.build(fresh, plan["layers"], kit)
	for unit in fresh:
		var shell: Node3D = shells.get(String(unit["id"]), null)
		if shell:
			geometry.add_child(shell)

	var prop_root := _gen_root()
	for unit in fresh:
		var placements: Array = props.get(String(unit["id"]), [])
		if placements.is_empty():
			continue
		var group := Node3D.new()
		group.name = TYPES.unit_node_name(String(unit["id"]))
		group.set_meta("lb_unit_id", String(unit["id"]))
		for placement in placements:
			var instance := _instance_prop(placement)
			if instance:
				group.add_child(instance)
		prop_root.add_child(group)

	var gameplay := _gen_root()
	var markers := GAMEPLAY_PASS.build(plan, kit)
	for unit in fresh:
		var group: Node3D = markers.get(String(unit["id"]), null)
		if group:
			gameplay.add_child(group)
	for key in markers:
		var orphan: Node3D = markers[key]
		if orphan.get_parent() == null:
			orphan.free()  # built for a kept unit that already has its own

	return {"Geometry": geometry, "Props": prop_root, "Gameplay": gameplay}


static func _gen_root() -> Node3D:
	var node := Node3D.new()
	node.name = TYPES.GEN_ROOT_NAME
	return node


static func _instance_prop(placement: Dictionary) -> Node3D:
	var scene: PackedScene = placement["scene"]
	if scene == null:
		return null
	var instance := scene.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = String(placement["name"])
	var cell: Vector2i = placement["cell"]
	var footprint: Vector2i = placement["footprint"]
	var size: float = placement["cell_size"]
	instance.position = Vector3(
		(cell.x + footprint.x * 0.5) * size,
		float(placement["y"]),
		(cell.y + footprint.y * 0.5) * size)
	instance.rotation.y = float(placement["yaw"])
	instance.set_meta("lb_prop_tag", String(placement["tag"]))
	return instance


# spawn_cell is a SOLVER cell, not a module — it has to line up with the lane
# the route solver reserved, and those are half-module accurate.
static func _spawn_position(plan: Dictionary, kit: Resource) -> Vector3:
	var cell: Vector2i = plan.get("spawn_cell", Vector2i.ZERO)
	var layer := String(plan.get("spawn_layer", ""))
	var module := TYPES.module_of(cell, TYPES.cells_per_module(kit))
	var base_y := 0.0
	for unit in plan["units"]:
		if String(unit["layer"]) == layer and TYPES.unit_cells(unit).has(module):
			base_y = TYPES.surface_y(unit, kit)
			break
	return Vector3((cell.x + 0.5) * kit.cell, base_y, (cell.y + 0.5) * kit.cell)


# ---- tree plumbing ---------------------------------------------------------

static func _ensure_container(root: Node, container_name: String, undo) -> Node:
	var existing: Node = root.get_node_or_null(NodePath(container_name))
	if existing:
		return existing
	var container := Node3D.new()
	container.name = container_name
	_add(root, container, root, undo)
	return container


static func _add(parent: Node, child: Node, root: Node, undo) -> void:
	if undo:
		undo.add_do_method(parent, "add_child", child)
		undo.add_do_method(load(SELF), "own_deep", child, root)
		undo.add_do_reference(child)
		undo.add_undo_method(parent, "remove_child", child)
	else:
		parent.add_child(child)
		own_deep(child, root)


# Moves a node between two parents without touching it. The new parent isn't in
# the tree yet, which add_child handles fine and which is why this has to happen
# before the old container is removed.
static func _reparent(node: Node, new_parent: Node, undo) -> void:
	var old_parent := node.get_parent()
	if old_parent == null or old_parent == new_parent:
		return
	if undo:
		undo.add_do_method(old_parent, "remove_child", node)
		undo.add_do_method(new_parent, "add_child", node)
		undo.add_undo_method(new_parent, "remove_child", node)
		undo.add_undo_method(old_parent, "add_child", node)
		undo.add_do_reference(node)
	else:
		old_parent.remove_child(node)
		new_parent.add_child(node)


static func _remove(parent: Node, child: Node, root: Node, undo) -> void:
	if undo:
		undo.add_do_method(parent, "remove_child", child)
		undo.add_undo_method(parent, "add_child", child)
		undo.add_undo_method(load(SELF), "own_deep", child, root)
		undo.add_undo_reference(child)
	else:
		# immediate, not queue_free — the replacement wants this name back now
		parent.remove_child(child)
		child.queue_free()


# Reachable through the undo manager, so it has to be a plain static here.
static func own_deep(node: Node, root: Node) -> void:
	TYPES.own_deep(node, root)


static func _move_spawn(root: Node, position: Vector3, undo) -> void:
	var spawn := BOOTSTRAP.find_spawn(root) as Marker3D
	if spawn == null:
		var marker := BOOTSTRAP.build_spawn()
		marker.position = position
		var parent: Node = root.get_node_or_null(^"Gameplay")
		_add(parent if parent else root, marker, root, undo)
		return
	if undo:
		undo.add_do_property(spawn, "position", position)
		undo.add_undo_property(spawn, "position", spawn.position)
	else:
		spawn.position = position


# ---- odds and ends ---------------------------------------------------------

# Rooms the repair ladder ran out of rungs on, and rooms it had to climb at all.
static func _count_rejected(repairs: Dictionary) -> int:
	var count := 0
	for unit_id in repairs:
		if int(repairs[unit_id].get("repair", 0)) >= PROP_SOLVER.REPAIR_REJECTED:
			count += 1
	return count


static func _count_repaired(repairs: Dictionary) -> int:
	var count := 0
	for unit_id in repairs:
		var rung := int(repairs[unit_id].get("repair", 0))
		if rung > 0 and rung < PROP_SOLVER.REPAIR_REJECTED:
			count += 1
	return count


static func _count_props(props: Dictionary) -> int:
	var count := 0
	for key in props:
		count += (props[key] as Array).size()
	return count


static func _no_reds(findings: Array) -> bool:
	for finding in findings:
		if String(finding["severity"]) == "red":
			return false
	return true


static func _red(id: String, message: String) -> Dictionary:
	return {"id": id, "severity": "red", "message": message, "fixable": false}
