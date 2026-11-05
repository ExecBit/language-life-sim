@tool
extends Object

# The condition layer: what's happened to this room since it was built.
#
# Runs last, over a room that already works. Everything here is additive and
# optional — rubble, debris, scorch marks — and it goes through the same
# placement rules as the furniture, so a collapsed ceiling still can't block
# the door. Mess that blocks the way out isn't atmosphere, it's a bug.
#
# It clusters rather than sprinkles. Real neglect pools: it gathers in a corner,
# banks against a wall, spreads from one spot. Evenly-scattered debris reads as
# confetti and is the fastest way to make a room look generated.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const ZONES := preload("res://addons/level_builder/generator/zone_mapper.gd")
const PROP_SOLVER := preload("res://addons/level_builder/generator/prop_solver.gd")

const CELLS_PER_HELPING := 100.0  # condition_density is "per 100 cells of floor"
const MAX_CONDITION := 40         # nobody needs more debris than this in one room


# Adds condition props to a room that's already furnished. Returns just the new
# placements; the grid is updated so nothing lands on anything.
static func decorate(unit: Dictionary, grid: Dictionary, palette: Resource, kit: Resource,
		rng: RandomNumberGenerator, placed: Array) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if palette == null or palette.condition_tags.is_empty() or palette.condition_density <= 0.0:
		return added

	var cells := float(int(grid["w"]) * int(grid["h"]))
	var wanted := mini(MAX_CONDITION,
		int(round(cells / CELLS_PER_HELPING * float(palette.condition_density))))
	if wanted <= 0:
		return added

	var zones := ZONES.map_geometry(grid)
	var seeds_wanted := maxi(1, int(ceil(float(wanted) / 3.0)))  # a few pools, not one carpet
	var pools: Array[Vector2i] = []
	var everything: Array = []
	everything.append_array(placed)

	for index in wanted:
		var tag := String(palette.condition_tags[index % palette.condition_tags.size()])
		# the first few pick their own spot; the rest bank against one already chosen
		var near := Vector2i(-1, -1)
		var radius := 0
		if pools.size() >= seeds_wanted:
			near = pools[rng.randi_range(0, pools.size() - 1)]
			radius = maxi(1, int(palette.cluster_radius))
		var placement := PROP_SOLVER.place_one(unit, grid, zones, tag, kit, rng, everything,
			near, radius, "Condition_%d" % index, palette)
		if placement.is_empty():
			continue
		placement["condition"] = true
		added.append(placement)
		everything.append(placement)
		if pools.size() < seeds_wanted:
			pools.append(placement["local_cell"])
	return added
