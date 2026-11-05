@tool
extends Object

# Shared vocabulary for the generator: seeds, the solver grid, node naming.
#
# Same rule as scene_bootstrap.gd — pure logic, no EditorInterface anywhere, so
# headless verify can drive the whole pipeline. Anything that touches the tree
# takes an optional EditorUndoRedoManager (null = mutate directly).

const BRIEF := preload("res://addons/level_builder/resources/generation_brief.gd")

const GEN_ROOT_NAME := "Generated"
# Generation writes into the same containers everything else in the dock uses.
const CONTAINERS := ["Geometry", "Props", "Gameplay"]

const SCOPE_NAMES := ["Room", "Level", "World"]
const SIZE_NAMES := ["Small", "Medium", "Large"]

# solver grid cell states
const FREE := 0
const ROUTE := 1    # reserved circulation — nothing may sit here
const OCCUPIED := 2 # a prop footprint
const DOOR := 3     # a route cell that is also a doorway

# Four ways out of a module cell, in a fixed order so plans stay deterministic.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


# Child seeds hang off the parent, so regenerating one room never reshuffles a
# neighbour and a bug report is just a seed.
static func derive_seed(parent_seed: int, salt: String) -> int:
	return int(("%d/%s" % [parent_seed, salt]).hash())


static func rng_for(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func pick(rng: RandomNumberGenerator, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[rng.randi_range(0, items.size() - 1)]


static func cells_per_module(kit: Resource) -> int:
	return maxi(1, int(round(kit.module / kit.cell)))


# Module coords go negative and GDScript's / truncates toward zero, so these two
# have to floor properly or everything west of the origin lands one cell out.
static func module_of(cell: Vector2i, cpm: int) -> Vector2i:
	return Vector2i(floori(float(cell.x) / cpm), floori(float(cell.y) / cpm))


static func module_centre_cell(module_cell: Vector2i, cpm: int) -> Vector2i:
	return module_cell * cpm + Vector2i(cpm / 2, cpm / 2)


# ---- solver grid -----------------------------------------------------------
# Flat byte grid in a Dictionary: house style is statics over Dictionaries, and
# it keeps grids trivially copyable for the debug overlays coming in M3.

static func make_grid(w: int, h: int, origin: Vector2i = Vector2i.ZERO) -> Dictionary:
	var cells := PackedByteArray()
	cells.resize(maxi(0, w * h))
	return {"w": w, "h": h, "origin": origin, "cells": cells}


static func in_grid(grid: Dictionary, x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < int(grid["w"]) and z < int(grid["h"])


static func grid_get(grid: Dictionary, x: int, z: int) -> int:
	if not in_grid(grid, x, z):
		return OCCUPIED  # outside is never placeable
	return int((grid["cells"] as PackedByteArray)[z * int(grid["w"]) + x])


static func grid_set(grid: Dictionary, x: int, z: int, value: int) -> void:
	if not in_grid(grid, x, z):
		return
	var cells: PackedByteArray = grid["cells"]
	cells[z * int(grid["w"]) + x] = value


# Can a footprint sit here without touching a route, a prop or the outside?
static func footprint_free(grid: Dictionary, x: int, z: int, size: Vector2i) -> bool:
	for dz in size.y:
		for dx in size.x:
			if grid_get(grid, x + dx, z + dz) != FREE:
				return false
	return true


static func fill_footprint(grid: Dictionary, x: int, z: int, size: Vector2i, value: int) -> void:
	for dz in size.y:
		for dx in size.x:
			grid_set(grid, x + dx, z + dz, value)


# ---- units -----------------------------------------------------------------
# A unit is a room, corridor, plot or road: the smallest thing that can be
# locked and regenerated on its own. Rectangular unless it carries explicit
# cells (roads get clipped around plots, so they can't be rectangles).

static func unit_cells(unit: Dictionary) -> Array:
	var explicit: Array = unit.get("cells", [])
	if not explicit.is_empty():
		return explicit
	var out: Array = []
	var rect: Rect2i = unit["rect"]
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, z))
	return out


static func surface_y(unit: Dictionary, kit: Resource) -> float:
	return float(unit["base_y"]) + float(kit.floor_thickness)


# Buildings are flat plates and sit at one height. A road climbing a hill can't
# be — it has to rise a little under every step — so a unit may carry a height
# per cell, and that wins where it exists.
static func base_y_at(unit: Dictionary, cell: Vector2i) -> float:
	var per_cell: Dictionary = unit.get("heights", {})
	if per_cell.has(cell):
		return float(per_cell[cell])
	return float(unit["base_y"])


static func surface_at(unit: Dictionary, cell: Vector2i, kit: Resource) -> float:
	return base_y_at(unit, cell) + float(kit.floor_thickness)


# ---- node naming -----------------------------------------------------------
# Stable names are the whole basis of "safe to re-apply": M2's per-unit locks
# key off them, so they must be a pure function of the plan, never of order.

static func sanitize(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		# letters (upper != lower), digits, and the two separators node names allow
		if c == "_" or c == "-" or c.is_valid_int() or c.to_upper() != c.to_lower():
			out += c
		else:
			out += "_"
	return out if out != "" else "Unit"


static func unit_node_name(unit_id: String) -> String:
	return sanitize(unit_id)


# ---- tree helpers ----------------------------------------------------------

# Instanced scenes own themselves; only the instance root needs an owner or the
# saved .tscn balloons with redundant node entries.
static func own_instance(node: Node, root: Node) -> void:
	node.owner = root


static func own_deep(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		if child.scene_file_path == "":
			own_deep(child, root)
		else:
			child.owner = root
