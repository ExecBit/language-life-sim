@tool
extends Object

# World brief → terrain, plots and a road network, with each POI carrying a
# derived seed and (optionally) the level that stands on it.
#
# The same pipeline one scale up: POIs are the "props", roads are the "routes",
# the first POI is where you start.
#
# Plots live on the "ground" layer with the roads. Each POI's building lives on
# its own layer so a road can never knock a hole in a wall, but at the same
# height, with its footprint cut out of the plot beneath it — that's what makes
# a point of interest something you can walk into rather than just up to.
#
# The ground is still flat. Rolling terrain needs roads that terminate at the
# plots they join; they're currently routed centre-to-centre and clipped, which
# leaves them touching whatever they happen to pass. On flat ground that works
# by accident. Heights turn it into a road you can't get onto, so the road model
# comes first.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const LEVEL_PLANNER := preload("res://addons/level_builder/generator/level_planner.gd")
# for the planner choice only — world_planner never plans a building itself
const GENERATOR := preload("res://addons/level_builder/generator/generator.gd")

const GROUND_LAYER := "ground"
const PLOT_GAP := 4      # modules of wilds between neighbouring plots
const TERRAIN_MARGIN := 6



static func plan(world_arch: Resource, size_class: int, seed_value: int,
		generate_interiors: bool, kit: Resource, pinned: Array = [],
		shape: Dictionary = {}) -> Dictionary:
	var rng := TYPES.rng_for(seed_value)
	# ±1, same reason as room counts: a region where every map has the same
	# number of places on it reads as a template
	var count: int = maxi(1, world_arch.poi_count(size_class) + rng.randi_range(-1, 1))
	var mix: PackedStringArray = world_arch.poi_mix
	if mix.is_empty():
		mix = PackedStringArray(["outpost"])

	# Pinned POIs keep their plot and their building exactly where they are.
	# Nothing on the ground layer has walls, so unlike a level there's no shell
	# to get out of sync — new plots and roads just route around them.
	var kept_units: Array[Dictionary] = []
	var kept_rects: Array[Rect2i] = []
	var kept_pois: Array[Dictionary] = []
	var kept_layers := {}
	for unit in pinned:
		var kept: Dictionary = (unit as Dictionary).duplicate()
		kept["kept"] = true
		kept_units.append(kept)
		if String(kept["kind"]) == "pad":
			kept_rects.append(kept["rect"])
			kept_pois.append({
				"id": String(kept["id"]).trim_suffix("_Plot"),
				"archetype_id": String(kept["type"]),
				"display_name": String(kept["type"]),
				"layer": String(kept.get("poi_layer", "")),
				"seed": int(kept["seed"]),
				"plot_size": (kept["rect"] as Rect2i).size,
				"level_plan": {},
				"pad_unit": String(kept["id"]),
				"rect": kept["rect"],
				"center": (kept["rect"] as Rect2i).get_center(),
				"kept": true,
			})
		if kept.has("poi_layer"):
			kept_layers[String(kept["poi_layer"])] = true

	# Plan the interiors first: a plot is sized to fit its building, not the
	# other way round, so nothing ever pokes out of its plot.
	var fresh: Array[Dictionary] = []
	var plot_size_max := Vector2i(4, 4)
	for rect in kept_rects:
		plot_size_max = plot_size_max.max(rect.size)
	var index := 0
	while fresh.size() + kept_pois.size() < count:
		var layer := "poi_%d" % index
		index += 1
		if kept_layers.has(layer):
			continue  # that slot belongs to a POI somebody locked
		var poi_seed := TYPES.derive_seed(seed_value, "poi:%d" % (index - 1))
		var arch := LIBRARY.poi_archetype(_pick_poi_id(mix, rng))
		var level_plan := {}
		var plot_size: Vector2i = arch.plot_modules if arch else Vector2i(6, 6)
		if generate_interiors:
			var level_arch := LIBRARY.level_archetype(arch.level_archetype_id if arch else "")
			if level_arch:
				# The building sits at plot height, not stacked on top of it. Its
				# footprint is cut out of the plot below (see the clip further
				# down), so there's no doubled floor to z-fight and — the point —
				# no step to climb: road, plot, yard and entrance hall are all
				# one surface, and you can walk in.
				#
				# Through the generator's planner choice rather than straight to
				# the tree planner: a POI pointing at a court archetype should get
				# a court, and the creator's three knobs have to mean the same
				# thing down here as they do at level scope.
				level_plan = GENERATOR.plan_level_with(level_arch, maxi(0, size_class - 1),
					poi_seed, layer, 0.0, "P%d_" % (index - 1), [], shape)
				plot_size = (level_plan["bounds"] as Rect2i).size + Vector2i(2, 2)
		plot_size_max = plot_size_max.max(plot_size)
		fresh.append({
			"id": "POI_%d" % (index - 1),
			"archetype_id": String(arch.archetype_id) if arch else "outpost",
			"display_name": String(arch.display_name) if arch else "Outpost",
			"layer": layer,
			"seed": poi_seed,
			"plot_size": plot_size,
			"level_plan": level_plan,
		})

	# Lay the plots out one per sub-cell of a coarse grid. Disjoint sub-cells
	# mean plots can jitter without overlapping each other; pinned plots sit
	# wherever they already are, so a slot that clashes with one is skipped.
	var cols: int = maxi(1, int(ceil(sqrt(float(count)))))
	var sub := plot_size_max + Vector2i(PLOT_GAP, PLOT_GAP)
	var max_slots: int = cols * (int(ceil(float(count) / float(cols))) + 4)
	var taken: Array[Rect2i] = kept_rects.duplicate()
	var units: Array[Dictionary] = kept_units.duplicate()
	var pois: Array[Dictionary] = kept_pois.duplicate()
	var slot := 0

	for poi in fresh:
		var plot: Vector2i = poi["plot_size"]
		var origin := Vector2i.ZERO
		var landed := false
		while slot < max_slots and not landed:
			var base := Vector2i((slot % cols) * sub.x, (slot / cols) * sub.y)
			var slack := Vector2i(maxi(0, sub.x - plot.x - 2), maxi(0, sub.y - plot.y - 2))
			origin = base + Vector2i(1 + rng.randi_range(0, slack.x), 1 + rng.randi_range(0, slack.y))
			slot += 1
			landed = true
			for other in taken:
				if Rect2i(origin, plot).grow(1).intersects(other):
					landed = false
					break
		if not landed:
			continue  # no room left on the map for this one
		taken.append(Rect2i(origin, plot))
		var pad := _unit("%s_Plot" % poi["id"], "pad", String(poi["archetype_id"]),
			Rect2i(origin, plot), GROUND_LAYER, 0.0, int(poi["seed"]))
		pad["poi_layer"] = String(poi["layer"])  # locking a plot locks its building
		units.append(pad)
		poi["pad_unit"] = String(pad["id"])
		poi["rect"] = pad["rect"]
		poi["center"] = origin + plot / 2
		if not (poi["level_plan"] as Dictionary).is_empty():
			# centre the building on its plot, leaving the apron walkable
			var level_bounds: Rect2i = poi["level_plan"]["bounds"]
			var offset := origin + (plot - level_bounds.size) / 2 - level_bounds.position
			poi["level_plan"] = LEVEL_PLANNER.translate(poi["level_plan"], offset)
			units.append_array(_typed(poi["level_plan"]["units"]))
			# and cut the building's footprint out of the plot, so the plot is an
			# apron around it rather than a floor underneath it
			pad["cells"] = _apron(pad["rect"], poi["level_plan"]["units"])
		pois.append(poi)

	# Everything already standing, on any layer. Roads were once clipped against
	# the ground layer alone, which let one run straight through a building —
	# two floors in the same cell and a road on the wrong side of a wall.
	var ground_occupancy := LEVEL_PLANNER.occupancy_of(units)

	# Roads: chain the POIs in placement order with L-paths, clipped so they
	# never double up on a plot's floor tiles.
	for i in range(1, pois.size()):
		var cells := _clipped_road(pois[i - 1]["center"], pois[i]["center"], ground_occupancy)
		if cells.is_empty():
			continue
		# named after what it joins, not its index — the name survives a POI
		# being locked and the rest of the map being re-rolled around it
		var road_id := "Road_%s_%s" % [pois[i - 1]["id"], pois[i]["id"]]
		var road := _unit(road_id, "road", "", _bounds_of_cells(cells), GROUND_LAYER, 0.0,
			TYPES.derive_seed(seed_value, "road:%d" % i))
		road["cells"] = cells
		road["walls"] = false
		units.append(road)
		for cell in cells:
			ground_occupancy[cell] = String(road["id"])

	var layers := {}
	for unit in units:
		var layer := String(unit["layer"])
		if not layers.has(layer):
			layers[layer] = {}
		for cell in TYPES.unit_cells(unit):
			(layers[layer] as Dictionary)[cell] = String(unit["id"])

	var bounds := LEVEL_PLANNER.bounds_of(units)
	# the plot's corner is apron — the building is centred, so nothing is built here
	var spawn_cell := TYPES.module_centre_cell(
		(pois[0]["rect"] as Rect2i).position if not pois.is_empty() else Vector2i.ZERO,
		TYPES.cells_per_module(kit))
	return {
		"layer": GROUND_LAYER,
		"units": units,
		"layers": layers,
		"bounds": bounds,
		"terrain": bounds.grow(TERRAIN_MARGIN),
		"pois": pois,
		"spawn_layer": GROUND_LAYER,
		"spawn_cell": spawn_cell,
		"seed": seed_value,
	}


# ---- internals -------------------------------------------------------------

# Which kind of place goes on the next plot, weighted by the archetype's own
# `weight`. A mix where every weight is the same falls through to a plain
# uniform draw — same rng calls, same regions — so turning the knob on costs
# nothing to anyone who never touches it.
static func _pick_poi_id(mix: PackedStringArray, rng: RandomNumberGenerator) -> String:
	var weights := PackedFloat64Array()
	var total := 0.0
	var varied := false
	for id in mix:
		var arch := LIBRARY.poi_archetype(String(id))
		var w := maxf(0.0, float(arch.weight)) if arch != null else 1.0
		if not weights.is_empty() and not is_equal_approx(w, weights[0]):
			varied = true
		weights.append(w)
		total += w
	if not varied or total <= 0.0:
		return String(mix[rng.randi_range(0, mix.size() - 1)])
	var roll := rng.randf() * total
	for i in mix.size():
		roll -= weights[i]
		if roll <= 0.0:
			return String(mix[i])
	return String(mix[mix.size() - 1])


static func _typed(units: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for unit in units:
		out.append(unit)
	return out


static func _unit(id: String, kind: String, type_id: String, rect: Rect2i,
		layer: String, base_y: float, seed_value: int) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"type": type_id,
		"rect": rect,
		"layer": layer,
		"base_y": base_y,
		"seed": seed_value,
		"walls": false,  # nothing on the ground layer gets walls
	}


# The plot minus whatever stands on it.
static func _apron(plot: Rect2i, level_units: Array) -> Array:
	var taken := {}
	for unit in level_units:
		for cell in TYPES.unit_cells(unit):
			taken[cell] = true
	var apron: Array = []
	for z in range(plot.position.y, plot.end.y):
		for x in range(plot.position.x, plot.end.x):
			var cell := Vector2i(x, z)
			if not taken.has(cell):
				apron.append(cell)
	return apron


static func _clipped_road(from: Vector2i, to: Vector2i, occupied: Dictionary) -> Array:
	var cells: Array = []
	var step_x := signi(to.x - from.x)
	var x := from.x
	while x != to.x:
		cells.append(Vector2i(x, from.y))
		x += step_x
	var step_z := signi(to.y - from.y)
	var z := from.y
	while z != to.y:
		cells.append(Vector2i(to.x, z))
		z += step_z
	cells.append(to)
	var kept: Array = []
	var seen := {}  # the L-path doubles back on its own corner; dict, not `in`
	for cell in cells:
		if occupied.has(cell) or seen.has(cell):
			continue
		seen[cell] = true
		kept.append(cell)
	return kept


static func _bounds_of_cells(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var bounds := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	return bounds
