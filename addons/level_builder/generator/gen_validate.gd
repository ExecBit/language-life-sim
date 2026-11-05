@tool
extends Object

# The generator's own acceptance test, in the same finding shape Check Level
# uses so the dock renders both lists with one renderer.
#
# These run on the plan, not the scene, so verify can hammer 50 seeds a scope
# without ever building a node. scene_findings() adds the physics-backed
# playability pass once the result is actually in a tree.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const LEVEL_CHECK := preload("res://addons/level_builder/editor/level_check.gd")
const ROUTE_SOLVER := preload("res://addons/level_builder/generator/route_solver.gd")
const ZONES := preload("res://addons/level_builder/generator/zone_mapper.gd")
const PROP_SOLVER := preload("res://addons/level_builder/generator/prop_solver.gd")

# How big a step up you can take without a ramp. Anything more needs one built.
const STEP_HEIGHT := 0.25


static func validate(result: Dictionary) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	var plan: Dictionary = result.get("plan", {})
	var units: Array = plan.get("units", [])
	if units.is_empty():
		findings.append(_red("gen_no_units", "The planner produced nothing to build. Try another seed."))
		return findings

	var kit: Resource = result["kit"]
	var props: Dictionary = result.get("props", {})
	var layers: Dictionary = plan.get("layers", {String(plan.get("layer", "level")): plan.get("occupancy", {})})

	_check_overlaps(units, layers, findings)
	_check_room_types(units, findings)
	_check_anchors(units, props, findings)
	_check_props(units, props, kit, findings)
	_check_zones(props, findings)
	_check_groups(props, findings)
	_check_repairs(result.get("repairs", {}), findings)
	_check_routes(units, layers, props, kit, findings)
	_check_reachability(plan, units, layers, props, kit, findings)
	_check_route_through(plan, findings)
	return findings


# The physics half — needs the generated scene in a tree with a spawn.
static func scene_findings(root: Node) -> Array[Dictionary]:
	return LEVEL_CHECK.check(root)


# ---- checks ----------------------------------------------------------------

static func _check_overlaps(units: Array, layers: Dictionary, findings: Array[Dictionary]) -> void:
	for layer in layers:
		var seen := {}
		for unit in units:
			if String(unit["layer"]) != String(layer):
				continue
			for cell in TYPES.unit_cells(unit):
				if seen.has(cell):
					findings.append(_red("gen_unit_overlap",
						"'%s' overlaps '%s' at module %s — the planner placed two units on one cell."
						% [unit["id"], seen[cell], cell]))
					return
				seen[cell] = String(unit["id"])


# Archetype lookups fall back to the first entry rather than crashing, which
# would quietly turn a typo in a room_mix into "every room is a bedroom".
static func _check_room_types(units: Array, findings: Array[Dictionary]) -> void:
	var unknown := {}
	for unit in units:
		if String(unit["kind"]) != "room" or String(unit["type"]) == "" or bool(unit.get("kept", false)):
			continue
		var arch := LIBRARY.room_archetype(String(unit["type"]))
		if arch == null or String(arch.archetype_id) != String(unit["type"]):
			unknown[String(unit["type"])] = true
	if not unknown.is_empty():
		findings.append(_red("gen_unknown_room_type",
			"No room archetype called %s — check the room_mix on the level archetype."
			% ", ".join(PackedStringArray(unknown.keys()))))


static func _check_anchors(units: Array, props: Dictionary, findings: Array[Dictionary]) -> void:
	var missing := PackedStringArray()
	for unit in units:
		if String(unit["kind"]) != "room" or bool(unit.get("kept", false)):
			continue  # a kept room's props are already in the scene, not in this plan
		var arch := LIBRARY.room_archetype(String(unit["type"]))
		if arch == null or String(arch.anchor_tag) == "":
			continue
		var placed: Array = props.get(String(unit["id"]), [])
		var has_anchor := false
		for placement in placed:
			if String(placement["tag"]) == String(arch.anchor_tag):
				has_anchor = true
		if not has_anchor:
			missing.append("%s (%s)" % [unit["id"], arch.anchor_tag])
	if missing.size() > 0:
		findings.append(_red("gen_missing_anchor",
			"%d room(s) got no anchor prop, so they aren't for anything yet: %s."
			% [missing.size(), ", ".join(missing)]))


# Two props can't share a cell, and a prop can't wander outside the unit that
# placed it. Checked from the placements alone, so it catches a solver that
# forgot to mark its own footprints as well as one that ran off the grid.
static func _check_props(units: Array, props: Dictionary, kit: Resource,
		findings: Array[Dictionary]) -> void:
	var cpm := TYPES.cells_per_module(kit)
	var seen := {}
	var overlaps := 0
	var escapees := PackedStringArray()
	for unit in units:
		var rect: Rect2i = unit["rect"]
		var layer := String(unit["layer"])
		for placement in props.get(String(unit["id"]), []):
			var cell: Vector2i = placement["cell"]
			var footprint: Vector2i = placement["footprint"]
			for dz in footprint.y:
				for dx in footprint.x:
					var at: Vector2i = cell + Vector2i(dx, dz)
					var key := "%s:%d,%d" % [layer, at.x, at.y]
					if seen.has(key):
						overlaps += 1
					seen[key] = true
					var module := TYPES.module_of(at, cpm)
					if not rect.has_point(module):
						escapees.append("%s/%s" % [unit["id"], placement["name"]])
	if overlaps > 0:
		findings.append(_red("gen_prop_overlap", "%d prop cell(s) sit on top of another prop." % overlaps))
	if escapees.size() > 0:
		findings.append(_red("gen_prop_escaped",
			"%d prop(s) landed outside the unit that placed them: %s."
			% [escapees.size(), ", ".join(escapees)]))


# Nothing sits on a zone it declared it would never sit on. The prop records
# which zones it ended up across, so this reads back what the solver decided
# rather than asking the solver to grade its own homework.
static func _check_zones(props: Dictionary, findings: Array[Dictionary]) -> void:
	var offenders := PackedStringArray()
	var compromised := PackedStringArray()
	for unit_id in props:
		for placement in props[unit_id]:
			var avoid: PackedStringArray = placement.get("avoid_zones", PackedStringArray())
			var sat_in: PackedStringArray = placement.get("zones", PackedStringArray())
			for zone_name in avoid:
				if not String(zone_name) in sat_in:
					continue
				var where := "%s/%s in %s" % [unit_id, placement["name"], zone_name]
				# an anchor that relaxed its preferences did so on purpose — it's
				# worth knowing about, it isn't a defect
				if bool(placement.get("relaxed", false)):
					compromised.append(where)
				else:
					offenders.append(where)
	if offenders.size() > 0:
		findings.append(_red("gen_zone_violation",
			"%d prop(s) landed somewhere they're meant to keep out of: %s."
			% [offenders.size(), ", ".join(offenders)]))
	if compromised.size() > 0:
		findings.append({"id": "gen_anchor_compromised", "severity": "amber", "fixable": false,
			"message": "%d room(s) were too tight to place the anchor properly, so it took the best spot left: %s. A bigger room or a smaller anchor would sit better."
				% [compromised.size(), ", ".join(compromised)]})


# An activity group is only a group if its parts are within reach of each other.
# A nightstand across the room from its bed is two props, not a bedside.
static func _check_groups(props: Dictionary, findings: Array[Dictionary]) -> void:
	var strays := PackedStringArray()
	for unit_id in props:
		for placement in props[unit_id]:
			var group_id := String(placement.get("group", ""))
			if group_id == "":
				continue
			var group := LIBRARY.activity_group(group_id)
			if group == null:
				continue
			var lead: Vector2i = placement.get("lead_cell", placement["local_cell"])
			var here: Vector2i = placement["local_cell"]
			if Vector2(here - lead).length() > float(group.radius) + 0.001:
				strays.append("%s/%s" % [unit_id, placement["name"]])
	if strays.size() > 0:
		findings.append(_red("gen_group_scattered",
			"%d prop(s) drifted out of the group they belong to: %s."
			% [strays.size(), ", ".join(strays)]))


# How hard the room was to furnish. Climbing the ladder is normal; running out
# of rungs means the shell was rejected, and that's worth saying out loud.
static func _check_repairs(repairs: Dictionary, findings: Array[Dictionary]) -> void:
	var rejected := PackedStringArray()
	var repaired := 0
	for unit_id in repairs:
		var rung := int(repairs[unit_id].get("repair", 0))
		if rung >= PROP_SOLVER.REPAIR_REJECTED:
			rejected.append(String(unit_id))
		elif rung > 0:
			repaired += 1
	if rejected.size() > 0:
		findings.append(_red("gen_room_unfurnishable",
			"%d room(s) couldn't be furnished at all, even after retrying: %s. Try another seed or a bigger room."
			% [rejected.size(), ", ".join(rejected)]))
	if repaired > 0:
		findings.append({"id": "gen_room_repaired", "severity": "amber", "fixable": false,
			"message": "%d room(s) needed a second go before everything fitted. Nothing's wrong with them — they're just tight." % repaired})


# Re-derives the reserved lanes from scratch and checks nothing landed on them.
# Deliberately independent of the grid the prop solver mutated — otherwise this
# would just be asking the solver whether it agrees with itself.
static func _check_routes(units: Array, layers: Dictionary, props: Dictionary,
		kit: Resource, findings: Array[Dictionary]) -> void:
	var blocked := 0
	for unit in units:
		var placed: Array = props.get(String(unit["id"]), [])
		if placed.is_empty():
			continue
		var occupancy: Dictionary = layers.get(String(unit["layer"]), {})
		var grid := ROUTE_SOLVER.solve(unit, occupancy, kit)
		var origin: Vector2i = grid["origin"]
		for placement in placed:
			var cell: Vector2i = (placement["cell"] as Vector2i) - origin
			var footprint: Vector2i = placement["footprint"]
			for dz in footprint.y:
				for dx in footprint.x:
					var state := TYPES.grid_get(grid, cell.x + dx, cell.y + dz)
					if state == TYPES.ROUTE or state == TYPES.DOOR:
						blocked += 1
	if blocked > 0:
		findings.append(_red("gen_prop_blocks_route",
			"%d prop cell(s) sit in a reserved doorway or walking lane." % blocked))


# Can you walk to all of it, from where you start?
#
# One flood fill over everything, not one per layer. A point of interest's plot
# is on the ground layer and the building standing on it is on its own, and the
# whole question M7 asks is whether you can get from one to the other — so the
# fill has to cross between them.
#
# Two cells connect when they're next to each other, at much the same height,
# and there's no wall in between. Within a layer, being next to each other IS
# the absence of a wall — that's how doorways work here. Across layers, a wall
# stands unless both sides are open ground: a plot next to an outside wall is
# still outside it.
static func _check_reachability(plan: Dictionary, units: Array, layers: Dictionary,
		props: Dictionary, kit: Resource, findings: Array[Dictionary]) -> void:
	var cpm := TYPES.cells_per_module(kit)
	var by_id := {}
	for unit in units:
		by_id[String(unit["id"])] = unit

	# every walkable solver cell, and which unit owns it
	var owner := {}
	var doubled := 0
	for unit in units:
		for module_cell in TYPES.unit_cells(unit):
			for dz in cpm:
				for dx in cpm:
					var cell: Vector2i = module_cell * cpm + Vector2i(dx, dz)
					if owner.has(cell) and String(owner[cell]) != String(unit["id"]):
						doubled += 1
					owner[cell] = String(unit["id"])
	if doubled > 0:
		findings.append(_red("gen_stacked_floors",
			"%d cell(s) have two floors on them — one would be buried inside the other." % doubled))
	for unit in units:
		for placement in props.get(String(unit["id"]), []):
			var cell: Vector2i = placement["cell"]
			var footprint: Vector2i = placement["footprint"]
			for dz in footprint.y:
				for dx in footprint.x:
					owner.erase(cell + Vector2i(dx, dz))

	var start: Vector2i = plan.get("spawn_cell", Vector2i.ZERO)
	if not owner.has(start):
		findings.append(_red("gen_start_blocked",
			"Where you start isn't standable — something was built on it."))
		start = _first_cell(owner)
	var reached := _flood_across(owner, by_id, start, cpm)

	var stranded := PackedStringArray()
	for unit in units:
		if not _unit_reached(unit, reached, cpm):
			stranded.append(String(unit["id"]))
	if stranded.size() > 0:
		findings.append(_red("gen_unreachable",
			"%d unit(s) can't be walked to from where you start: %s."
			% [stranded.size(), ", ".join(stranded)]))


static func _flood_across(owner: Dictionary, by_id: Dictionary, start: Vector2i, cpm: int) -> Dictionary:
	var reached := {}
	if not owner.has(start):
		return reached
	var queue: Array[Vector2i] = [start]
	reached[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		var here: Dictionary = by_id[owner[cell]]
		for dir in TYPES.DIRS:
			var next: Vector2i = cell + dir
			if reached.has(next) or not owner.has(next):
				continue
			var there: Dictionary = by_id[owner[next]]
			if not can_step(here, there, TYPES.module_of(cell, cpm), TYPES.module_of(next, cpm)):
				continue
			reached[next] = true
			queue.append(next)
	return reached


# The one rule that decides whether a building can be entered. Public so verify
# can test it directly rather than inferring it from a whole region.
static func can_step(here: Dictionary, there: Dictionary,
		from_cell: Vector2i = Vector2i.ZERO, to_cell: Vector2i = Vector2i.ZERO) -> bool:
	if absf(TYPES.base_y_at(here, from_cell) - TYPES.base_y_at(there, to_cell)) > STEP_HEIGHT:
		return false
	if String(here["layer"]) == String(there["layer"]):
		return true  # neighbours on a layer means a doorway, by construction
	# different layers: whatever has walls, has one here
	return not bool(here.get("walls", true)) and not bool(there.get("walls", true))


static func _first_cell(owner: Dictionary) -> Vector2i:
	for cell in owner:
		return cell
	return Vector2i(-99999, -99999)


# A building needs a way in and a way through: somewhere to arrive, and a walk
# from there to whatever you came for. A level where those are the same room
# isn't a level, it's a room.
static func _check_route_through(plan: Dictionary, findings: Array[Dictionary]) -> void:
	var plans: Array = [plan]
	for poi in plan.get("pois", []):
		var level_plan: Dictionary = poi.get("level_plan", {})
		if not level_plan.is_empty():
			plans.append(level_plan)
	var broken := PackedStringArray()
	for entry in plans:
		var rooms: Array = entry.get("rooms", [])
		if rooms.size() < 2:
			continue  # a one-room building has nothing to check
		# Nothing has a parent, so the planner didn't build a tree this time —
		# which is what a fully locked level looks like. It was a coherent
		# building when it was generated and locking it can't have changed that.
		var grew := false
		for room in rooms:
			if String(room["parent"]) != "":
				grew = true
				break
		if not grew:
			continue
		var path: PackedStringArray = entry.get("critical_path", PackedStringArray())
		if path.size() < 2:
			broken.append("no walk from the way in to the objective")
			continue
		# It has to start at a root, not necessarily at rooms[0]: lock a room in
		# the middle of a level and the tree legitimately has more than one.
		var roots := {}
		for room in rooms:
			if String(room["parent"]) == "":
				roots[String(room["id"])] = true
		if not roots.has(String(path[0])):
			broken.append("the critical path starts nowhere")
		if String(path[path.size() - 1]) != String(entry.get("goal_unit", "")):
			broken.append("the critical path doesn't end at the objective")
	if broken.size() > 0:
		findings.append(_red("gen_no_critical_path",
			"%d building(s) don't hold together: %s." % [broken.size(), ", ".join(broken)]))


# ---- grid helpers ----------------------------------------------------------

static func _unit_reached(unit: Dictionary, reached: Dictionary, cpm: int) -> bool:
	for module_cell in TYPES.unit_cells(unit):
		for dz in cpm:
			for dx in cpm:
				if reached.has(module_cell * cpm + Vector2i(dx, dz)):
					return true
	return false


static func _unit_by_id(units: Array, id: String) -> Dictionary:
	for unit in units:
		if String(unit["id"]) == id:
			return unit
	return {}


static func _red(id: String, message: String) -> Dictionary:
	return {"id": id, "severity": "red", "message": message, "fixable": false}
