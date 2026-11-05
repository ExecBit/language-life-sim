@tool
extends Object

# What the level is FOR, in nodes. M1 emits the marker fallback only: clean
# Marker3Ds under Gameplay/, named and tagged so wiring them by hand is
# obvious. M8 swaps these for real nodes from the other packs when they're
# installed — loot chests, enemy spawns, vendors — with these markers staying
# as the always-tested baseline.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")


# Returns unit_id -> Node3D of markers, ready to go under Gameplay/Generated.
static func build(plan: Dictionary, kit: Resource) -> Dictionary:
	var nodes := {}
	# At world scope the plan-level entry/goal are the region's, not a building's —
	# each POI's own level knows where its way in and its objective are.
	var roles := {}
	_collect_roles(plan, roles)
	for poi in plan.get("pois", []):
		_collect_roles(poi.get("level_plan", {}), roles)
	# Rooms off the critical path are the ones you only reach by choosing to look
	# around, so that's where the reward for looking around goes.
	var caches := {}
	_collect_dead_ends(plan, caches)
	for poi in plan.get("pois", []):
		_collect_dead_ends(poi.get("level_plan", {}), caches)

	for unit in plan["units"]:
		if String(unit["kind"]) != "room":
			continue
		var unit_id := String(unit["id"])
		var markers: Array[Marker3D] = []
		match String(roles.get(unit_id, "")):
			"goal":
				markers.append(_marker("Objective", {"lb_role": "objective"}))
			"entry":
				pass  # where you come in — no encounter waiting on the doormat
			_:
				if caches.has(unit_id):
					markers.append(_marker("Cache",
						{"lb_role": "cache", "lb_room_type": String(unit["type"])}))
				else:
					markers.append(_marker("Encounter",
						{"lb_role": "encounter", "lb_room_type": String(unit["type"])}))
		if markers.is_empty():
			continue
		nodes[unit_id] = _group(unit, markers, kit)

	for poi in plan.get("pois", []):
		var marker := _marker("Waypoint", {
			"lb_role": "poi",
			"lb_poi_archetype": String(poi["archetype_id"]),
			"lb_seed": int(poi["seed"]),
		})
		var pad_id := String(poi["pad_unit"])
		var pad := _unit_by_id(plan["units"], pad_id)
		if pad.is_empty():
			continue
		nodes[pad_id] = _group(pad, [marker], kit)
	return nodes


# ---- internals -------------------------------------------------------------

# Goal wins over entry: a one-room level is both, and the objective is the
# more useful marker of the two.
static func _collect_roles(source: Dictionary, roles: Dictionary) -> void:
	var entry := String(source.get("entry_unit", ""))
	var goal := String(source.get("goal_unit", ""))
	if entry != "":
		roles[entry] = "entry"
	if goal != "":
		roles[goal] = "goal"


static func _collect_dead_ends(source: Dictionary, into: Dictionary) -> void:
	for unit_id in source.get("dead_ends", PackedStringArray()):
		into[String(unit_id)] = true


static func _marker(marker_name: String, metas: Dictionary) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	for key in metas:
		marker.set_meta(String(key), metas[key])
	return marker


static func _group(unit: Dictionary, markers: Array, kit: Resource) -> Node3D:
	var group := Node3D.new()
	group.name = TYPES.unit_node_name(String(unit["id"]))
	group.set_meta("lb_unit_id", String(unit["id"]))
	# The cell nearest the rect centre that actually EXISTS. In an L-shaped room
	# the rect centre can be the cut-away corner, and a cache marker floating in
	# the void outside the wall helps nobody.
	var rect: Rect2i = unit["rect"]
	var want := Vector2(rect.position) + Vector2(rect.size) * 0.5
	var best: Vector2i = rect.position
	var best_distance := INF
	for cell in TYPES.unit_cells(unit):
		var distance := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(want)
		if distance < best_distance:
			best_distance = distance
			best = cell
	var centre := Vector3(
		(best.x + 0.5) * kit.module,
		TYPES.surface_y(unit, kit),
		(best.y + 0.5) * kit.module)
	for marker in markers:
		(marker as Marker3D).position = centre
		group.add_child(marker)
	return group


static func _unit_by_id(units: Array, id: String) -> Dictionary:
	for unit in units:
		if String(unit["id"]) == id:
			return unit
	return {}
