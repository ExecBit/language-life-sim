@tool
extends Object

# Anchors first, then the things that anchor needs within reach. A room is FOR
# something; the anchor is that something, and everything else is placed
# relative to it.
#
# Three kinds of rule, in the order they're cheapest to apply:
#
#   must   — a hard filter. The footprint fits on free cells, or it doesn't.
#   never  — a veto. On a vetoed zone, or too close to a tag it avoids, the cell
#            is out no matter how good the rest of the score is.
#   prefer — a weighted score. Zones it likes, tags it wants nearby, and how
#            close it is to the thing it belongs to.
#
# The veto being separate from the score is the whole point: preferences trade
# off against each other, vetoes don't. A crate that would score brilliantly in
# the middle of a doorway still doesn't go in the doorway.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const ZONES := preload("res://addons/level_builder/generator/zone_mapper.gd")

const NEAR_WEIGHT := 4.0    # pull toward whatever this belongs to
const NEEDS_WEIGHT := 2.5   # pull toward a tag it wants in reach
# How far below the best a spot can score and still be considered. Taking the
# single highest-scoring cell every time is what makes a generator look like
# one: every bed ends up in a corner, because a corner is a wall twice over.
# Anything this close to the best is good enough, so pick among them.
const GOOD_ENOUGH := 1.0


# The repair ladder.
#
# The doc's version is "drop clutter, then optional props, then retry, then
# reject the shell". Clutter and optional props are placed last here, so
# dropping them can never make room for something placed earlier — they're
# already best-effort. What actually helps is putting the group somewhere else,
# so the ladder is: try again in a different spot, then let the members break
# their own zone rules, then swap the lead for another prop that fits the same
# role, then give up on the group and keep the lead alone.
#
# The last rung matters most and took measuring to find: the first few change
# HOW we ask, and when a room is simply too small that changes nothing. So the
# bottom of the ladder changes WHAT we ask for and lets a group stand on its
# lead alone. A four-metre shrine with an altar and no candlesticks is still a
# shrine; rejecting it outright is the worse answer.
const REPAIR_RUNGS := [
	{"relax_members": false, "lead_choice": 0, "lead_only": false},
	{"relax_members": false, "lead_choice": 0, "lead_only": false},
	{"relax_members": true, "lead_choice": 0, "lead_only": false},
	{"relax_members": true, "lead_choice": 1, "lead_only": false},
	{"relax_members": true, "lead_choice": 0, "lead_only": true},
]
const REPAIR_REJECTED := 99


# Returns placements in GLOBAL solver-cell coordinates; mutates the grid so the
# caller can keep validating against it.
#
# `report` comes back with which rung of the repair ladder was needed and how
# many groups landed — the numbers M4 is judged on.
static func furnish(unit: Dictionary, grid: Dictionary, arch: Resource, kit: Resource,
		rng: RandomNumberGenerator, report: Dictionary = {}, palette: Resource = null,
		density: float = 0.5) -> Array[Dictionary]:
	report["repair"] = REPAIR_REJECTED
	report["groups"] = 0
	report["dropped"] = 0
	var empty: Array[Dictionary] = []
	if arch == null:
		return empty
	# typed local, not `as`: `as` is for Object types, and on a PackedStringArray
	# it quietly hands back an empty one instead of failing
	var wanted_groups: PackedStringArray = arch.groups
	if wanted_groups.is_empty():
		return empty  # nothing to place — no point climbing the ladder over it

	var pristine: PackedByteArray = (grid["cells"] as PackedByteArray).duplicate()
	for rung in REPAIR_RUNGS.size():
		var options: Dictionary = REPAIR_RUNGS[rung]
		# a fresh rng per rung, derived from the room's own seed, so retrying is
		# deterministic but genuinely tries somewhere else
		var attempt_rng := TYPES.rng_for(TYPES.derive_seed(int(unit["seed"]), "repair:%d" % rung))
		var attempt_report := {}
		var placements := _attempt(unit, grid, arch, kit, attempt_rng, options, attempt_report,
			palette, density)
		if not placements.is_empty():
			report["repair"] = rung
			report["groups"] = int(attempt_report.get("groups", 0))
			report["dropped"] = int(attempt_report.get("dropped", 0))
			var real: Array[Dictionary] = []
			for placement in placements:
				if not bool(placement.get("placeholder", false)):
					real.append(placement)
			return real
		grid["cells"] = pristine.duplicate()  # nothing landed — put the room back
	return empty


# ---- one go at furnishing the room -----------------------------------------

static func _attempt(unit: Dictionary, grid: Dictionary, arch: Resource, kit: Resource,
		rng: RandomNumberGenerator, options: Dictionary, report: Dictionary,
		palette: Resource = null, density: float = 0.5) -> Array[Dictionary]:
	var zones := ZONES.map_geometry(grid)
	var placements: Array[Dictionary] = []
	var group_ids: PackedStringArray = arch.groups
	if group_ids.is_empty():
		return placements  # nothing asked for — furnish() gives up without climbing

	# The room's reason for being goes down first, and it is not optional.
	var lead_group := LIBRARY.activity_group(group_ids[0])
	if lead_group == null:
		return placements
	var anchor := _place_tag(unit, grid, zones, String(arch.anchor_tag), kit, rng,
		placements, Vector2i(-1, -1), 0, "Anchor", true, int(options["lead_choice"]), false, palette)
	if anchor.is_empty():
		return placements
	anchor["group"] = String(lead_group.group_id)
	anchor["lead_cell"] = anchor["local_cell"]
	placements.append(anchor)

	# now the room knows what it's for, so the rest of it can mean something
	ZONES.map_function(zones, grid, anchor["local_cell"], anchor["footprint"], arch)

	# the anchor's own group has to hold together, or this whole attempt is off
	var members := _place_members(unit, grid, zones, lead_group, kit, rng, placements,
		anchor, "Anchor", bool(options["relax_members"]), bool(options["lead_only"]), palette)
	if members.is_empty():
		return [] as Array[Dictionary]
	placements.append_array(members)
	report["groups"] = 1

	# everything else is welcome but not required
	var dropped := 0
	for index in range(1, group_ids.size()):
		var group := LIBRARY.activity_group(group_ids[index])
		if group == null:
			continue
		# a tavern that always has exactly three tables is a tavern you've seen
		# before; one that asks for one of something still gets one
		var wanted: int = arch.count_for(index)
		if wanted > 1:
			wanted = maxi(1, wanted + rng.randi_range(-1, 1))
		for repeat in wanted:
			var label := "%s_%d" % [TYPES.sanitize(String(group.group_id)), repeat]
			var whole := _place_group(unit, grid, zones, group, kit, rng, placements, label,
				bool(options["relax_members"]), bool(options["lead_only"]), palette)
			if whole.is_empty():
				dropped += 1
				continue
			placements.append_array(whole)
			report["groups"] = int(report["groups"]) + 1
	report["dropped"] = dropped

	# Clutter is placed last and anywhere it's welcome — it fills, it doesn't
	# lead. How much of it there is is the palette's call: a swept room and a
	# hoarder's room can share a floor plan.
	var clutter_rate := (1.0 if palette == null else float(palette.clutter_density)) * _fullness(density)
	var clutter_index := 0
	for tag in arch.clutter_tags:
		for helping in _helpings(clutter_rate, rng):
			var clutter := _place_tag(unit, grid, zones, String(tag), kit, rng, placements,
				Vector2i(-1, -1), 0, "Clutter_%d" % clutter_index, false, 0, false, palette)
			clutter_index += 1
			if not clutter.is_empty():
				placements.append(clutter)
	return placements


# 0.5 is "as much as the archetype asked for"; 0 is a bare shell and 1 is
# roughly double. Kept multiplicative so it stacks with the palette's own
# clutter rate rather than fighting it.
static func _fullness(density: float) -> float:
	return clampf(density, 0.0, 1.0) * 2.0


# A density of 1.6 means "one for certain, and a second 60% of the time" — so a
# palette can ask for less than one of something without rounding it away.
static func _helpings(density: float, rng: RandomNumberGenerator) -> int:
	var whole := int(floor(density))
	if rng.randf() < density - float(whole):
		whole += 1
	return whole


# A group lands whole or not at all: place the lead, place what it can't do
# without, and if any of that fails put every cell back the way it was.
static func _place_group(unit: Dictionary, grid: Dictionary, zones: Dictionary, group: Resource,
		kit: Resource, rng: RandomNumberGenerator, placed: Array, label: String,
		relax_members: bool, lead_only: bool = false, palette: Resource = null) -> Array[Dictionary]:
	var lead := _place_tag(unit, grid, zones, String(group.lead_tag), kit, rng, placed,
		Vector2i(-1, -1), 0, "%s_Lead" % label, false, 0, false, palette)
	if lead.is_empty():
		return [] as Array[Dictionary]
	lead["group"] = String(group.group_id)
	lead["lead_cell"] = lead["local_cell"]

	var with_lead: Array = []
	with_lead.append_array(placed)
	with_lead.append(lead)
	var members := _place_members(unit, grid, zones, group, kit, rng, with_lead, lead,
		label, relax_members, lead_only, palette)
	if members.is_empty():
		_release(grid, [lead])  # the lead is no use on its own — give the cells back
		return [] as Array[Dictionary]
	var whole: Array[Dictionary] = [lead]
	whole.append_array(members)
	return whole


# Returns the members, or an empty array if a required one wouldn't fit — in
# which case anything already placed for this group is released.
static func _place_members(unit: Dictionary, grid: Dictionary, zones: Dictionary, group: Resource,
		kit: Resource, rng: RandomNumberGenerator, placed: Array, lead: Dictionary,
		label: String, relax_members: bool, lead_only: bool = false,
		palette: Resource = null) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var lead_cell: Vector2i = lead["local_cell"]
	var radius: int = group.radius
	var index := 0
	# the bottom rung: the lead is the whole group, and that's allowed
	if lead_only:
		members.append(_marker_member(group, lead_cell))
		return members
	for tag in group.required_tags:
		var member := _place_tag(unit, grid, zones, String(tag), kit, rng, _joined(placed, members),
			lead_cell, radius, "%s_%d" % [label, index], false, 0, relax_members, palette)
		index += 1
		if member.is_empty():
			_release(grid, members)
			return [] as Array[Dictionary]
		member["group"] = String(group.group_id)
		member["lead_cell"] = lead_cell
		members.append(member)
	for tag in group.optional_tags:
		var extra := _place_tag(unit, grid, zones, String(tag), kit, rng, _joined(placed, members),
			lead_cell, radius, "%s_%d" % [label, index], false, 0, relax_members, palette)
		index += 1
		if extra.is_empty():
			continue
		extra["group"] = String(group.group_id)
		extra["lead_cell"] = lead_cell
		members.append(extra)
	# a group with no required members still counts as placed — the lead is the group
	if members.is_empty() and group.required_tags.is_empty():
		members.append(_marker_member(group, lead_cell))
	return members


# A group whose members are all optional and none fitted still succeeded. This
# stands in for "yes, that worked" without emitting a prop nobody asked for.
static func _marker_member(group: Resource, lead_cell: Vector2i) -> Dictionary:
	return {"name": "", "tag": "", "tags": PackedStringArray(), "scene": null,
		"cell": lead_cell, "local_cell": lead_cell, "footprint": Vector2i.ONE,
		"yaw": 0.0, "y": 0.0, "cell_size": 1.0, "zones": [], "avoid_zones": PackedStringArray(),
		"relaxed": false, "group": String(group.group_id), "lead_cell": lead_cell,
		"placeholder": true}


static func _joined(a: Array, b: Array) -> Array:
	var out: Array = []
	out.append_array(a)
	out.append_array(b)
	return out


static func _release(grid: Dictionary, placements: Array) -> void:
	for placement in placements:
		if bool(placement.get("placeholder", false)):
			continue
		var cell: Vector2i = placement["local_cell"]
		TYPES.fill_footprint(grid, cell.x, cell.y, placement["footprint"], TYPES.FREE)


# One prop, by tag, wherever it fits best — what the style pass uses to scatter
# rubble through the same rules the furniture went through.
static func place_one(unit: Dictionary, grid: Dictionary, zones: Dictionary, tag: String,
		kit: Resource, rng: RandomNumberGenerator, placed: Array, near: Vector2i,
		radius: int, name_prefix: String, palette: Resource = null) -> Dictionary:
	return _place_tag(unit, grid, zones, tag, kit, rng, placed, near, radius,
		name_prefix, false, 0, false, palette)


# ---- internals -------------------------------------------------------------

# When several props fit a role, the palette gets first refusal — a ruined room
# reaches for the broken crate. Still a coin toss among whatever it prefers, so
# style doesn't cost variety.
static func _pick_styled(rng: RandomNumberGenerator, candidates: Array, palette: Resource) -> Resource:
	if palette == null:
		return TYPES.pick(rng, candidates)
	var favoured: Array = []
	for prop in candidates:
		if palette.prefers(prop):
			favoured.append(prop)
	return TYPES.pick(rng, favoured if not favoured.is_empty() else candidates)


# `insist` is for the anchor. A room without its anchor isn't the room it's
# meant to be, and that must-rule outranks the anchor's own preferences — so if
# nothing survives the vetoes, it takes the best vetoed spot rather than
# leaving the room meaningless. Supports and clutter get dropped instead, which
# is the right trade the other way: better a bedroom with no chest than a chest
# in the doorway. (The full repair ladder — drop clutter, retry, then reject the
# shell — is M4; this is the one rung of it the anchor can't do without.)
static func _place_tag(unit: Dictionary, grid: Dictionary, zones: Dictionary, tag: String,
		kit: Resource, rng: RandomNumberGenerator, placed: Array, near: Vector2i,
		radius: int, name_prefix: String, insist: bool = false,
		choice: int = 0, relax: bool = false, palette: Resource = null) -> Dictionary:
	if tag == "":
		return {}
	var candidates := LIBRARY.props_with_tag(tag, palette)
	if candidates.is_empty():
		return {}
	# choice > 0 is the ladder asking for a different prop in the same role — a
	# narrower forge, a smaller altar. With a one-piece kit there's nothing else
	# to offer and it falls back to the same prop, which is fine.
	var prop: Resource = _pick_styled(rng, candidates, palette)
	if choice > 0 and candidates.size() > 1:
		prop = candidates[choice % candidates.size()]
	var footprint: Vector2i = prop.footprint
	var cell := _best_cell(grid, zones, prop, placed, near, radius, rng, relax)
	if cell.x < 0 and insist and radius > 0:
		cell = _best_cell(grid, zones, prop, placed, near, 0, rng, relax)  # anywhere in the room
	var relaxed := relax
	if cell.x < 0 and insist:
		cell = _best_cell(grid, zones, prop, placed, near, 0, rng, true)  # vetoes relaxed
		relaxed = cell.x >= 0
	if cell.x < 0:
		return {}
	TYPES.fill_footprint(grid, cell.x, cell.y, footprint, TYPES.OCCUPIED)

	var origin: Vector2i = grid["origin"]
	var centre := Vector2i(int(grid["w"]) / 2, int(grid["h"]) / 2)
	return {
		"name": "%s_%s" % [name_prefix, TYPES.sanitize(tag)],
		"tag": tag,
		"tags": prop.tags,
		"scene": prop.scene(),
		"cell": origin + cell,
		"local_cell": cell,
		"footprint": footprint,
		"yaw": _face(cell + footprint / 2, centre),
		"y": TYPES.surface_y(unit, kit),
		"cell_size": float(kit.cell),
		"zones": ZONES.zones_under(zones, cell.x, cell.y, footprint),
		# carried on the placement, not looked up again by tag — several props
		# can share a tag and validation must grade the one actually placed
		"avoid_zones": prop.avoid_zones,
		"relaxed": relaxed,  # took a compromised spot rather than leave the room meaningless
	}


static func _best_cell(grid: Dictionary, zones: Dictionary, prop: Resource, placed: Array,
		near: Vector2i, radius: int, rng: RandomNumberGenerator, relax: bool = false) -> Vector2i:
	var w := int(grid["w"])
	var h := int(grid["h"])
	var footprint: Vector2i = prop.footprint
	var max_dist := maxf(1.0, Vector2(w, h).length() * 0.5)
	var prefer: PackedStringArray = prop.prefer_zones
	# Reserved lanes are already excluded by the must-filter — they're not FREE
	# in the grid — so relaxing vetoes can never put anything in a walking lane.
	var veto := PackedStringArray() if relax else (prop.avoid_zones as PackedStringArray)
	var scored: Array = []
	var best_score := -INF

	for z in range(0, h - footprint.y + 1):
		for x in range(0, w - footprint.x + 1):
			# must: does it physically fit on free cells?
			if not TYPES.footprint_free(grid, x, z, footprint):
				continue
			if near.x >= 0 and radius > 0 and Vector2(x - near.x, z - near.y).length() > float(radius):
				continue
			# never: vetoed zone, or too close to something it won't sit beside
			var under := ZONES.zones_under(zones, x, z, footprint)
			if _any_in(under, veto):
				continue
			if _too_close_to_avoided(prop, placed, x, z, footprint):
				continue
			# prefer: everything else is a weighted nudge.
			#
			# Scored once for sitting somewhere it likes, NOT once per zone it
			# touches — otherwise a corner (which is wall twice over) always beats
			# the middle of a wall, and every bed in the game ends up in a corner.
			var score := 0.0
			if _any_in(under, prefer):
				score += float(prop.prefer_weight)
			if near.x >= 0:
				score += NEAR_WEIGHT * (1.0 - clampf(Vector2(x - near.x, z - near.y).length() / max_dist, 0.0, 1.0))
			score += _needs_score(prop, placed, x, z, footprint)
			scored.append([score, Vector2i(x, z)])
			best_score = maxf(best_score, score)

	if scored.is_empty():
		return Vector2i(-1, -1)
	return _weighted_pick(scored, best_score, rng)


# Pick among the spots that are good enough, weighted by how good. Uniform
# picking gives lovely variety and noticeably worse rooms — chests drift away
# from the beds they belong to. Squaring the margin keeps the best spots the
# likely ones while leaving the rest genuinely reachable.
static func _weighted_pick(scored: Array, best_score: float, rng: RandomNumberGenerator) -> Vector2i:
	var floor_score := best_score - GOOD_ENOUGH
	var shortlist: Array = []
	var total := 0.0
	for entry in scored:
		var margin := float(entry[0]) - floor_score
		if margin <= 0.0:
			continue
		var weight := margin * margin
		shortlist.append([weight, entry[1]])
		total += weight
	if shortlist.is_empty():
		return scored[0][1]
	var roll := rng.randf() * total
	for entry in shortlist:
		roll -= float(entry[0])
		if roll <= 0.0:
			return entry[1]
	return shortlist[shortlist.size() - 1][1]


static func _any_in(values: PackedStringArray, wanted: PackedStringArray) -> bool:
	for value in values:
		if value in wanted:
			return true
	return false


static func _centre_of(x: int, z: int, footprint: Vector2i) -> Vector2:
	return Vector2(x + footprint.x * 0.5, z + footprint.y * 0.5)


static func _too_close_to_avoided(prop: Resource, placed: Array, x: int, z: int,
		footprint: Vector2i) -> bool:
	if prop.avoids.is_empty():
		return false
	var here := _centre_of(x, z, footprint)
	for other in placed:
		if not _shares_tag(other, prop.avoids):
			continue
		var there := _centre_of((other["local_cell"] as Vector2i).x,
			(other["local_cell"] as Vector2i).y, other["footprint"])
		if here.distance_to(there) < float(prop.avoids_range):
			return true
	return false


static func _needs_score(prop: Resource, placed: Array, x: int, z: int, footprint: Vector2i) -> float:
	if prop.needs_nearby.is_empty():
		return 0.0
	var here := _centre_of(x, z, footprint)
	var score := 0.0
	for other in placed:
		if not _shares_tag(other, prop.needs_nearby):
			continue
		var there := _centre_of((other["local_cell"] as Vector2i).x,
			(other["local_cell"] as Vector2i).y, other["footprint"])
		var distance := here.distance_to(there)
		if distance <= float(prop.needs_range):
			score += NEEDS_WEIGHT * (1.0 - distance / float(prop.needs_range))
	return score


static func _shares_tag(placement: Dictionary, wanted: PackedStringArray) -> bool:
	var tags: PackedStringArray = placement.get("tags", PackedStringArray())
	for tag in wanted:
		if tag in tags:
			return true
	return false


# Face the middle of the room, snapped to quarter turns — a bed against the
# north wall should look south, not at 37 degrees.
static func _face(from: Vector2i, to: Vector2i) -> float:
	var delta := to - from
	if delta == Vector2i.ZERO:
		return 0.0
	if absi(delta.x) >= absi(delta.y):
		return PI * 0.5 if delta.x > 0 else -PI * 0.5
	return 0.0 if delta.y > 0 else PI
