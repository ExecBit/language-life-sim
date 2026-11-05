@tool
extends Object

# The zone and lane overlay: a flat coloured tile over every solver cell, so you
# can see what the generator thought it was doing.
#
# The whole thing is ONE ownerless node. Ownerless means it renders in the
# viewport and can never be saved into the scene — the same trick place mode
# uses for its ghost. Rebuild it or drop it any time; nothing else depends on it.

const TYPES := preload("res://addons/level_builder/generator/gen_types.gd")
const ZONES := preload("res://addons/level_builder/generator/zone_mapper.gd")
const GEN_SCENE := preload("res://addons/level_builder/generator/gen_scene.gd")
const LIBRARY := preload("res://addons/level_builder/generator/gen_library.gd")
const ROUTE_SOLVER := preload("res://addons/level_builder/generator/route_solver.gd")
const LEVEL_PLANNER := preload("res://addons/level_builder/generator/level_planner.gd")

const OVERLAY_NAME := "LBZoneOverlay"
const LIFT := 0.06  # above the floor, under the furniture

# Keyed by zone NAME, because zones are the creator's to name now. The four
# shipped functional zones get the colours they always had; anything invented
# gets one picked from its name, so a new zone shows up without touching code.
const COLORS := {
	"travel": Color(0.20, 0.55, 0.95, 0.55),
	"entrance": Color(0.30, 0.85, 0.95, 0.55),
	"wall": Color(0.60, 0.60, 0.62, 0.40),
	"corner": Color(0.45, 0.45, 0.50, 0.45),
	"center": Color(0.75, 0.75, 0.72, 0.28),
	"work": Color(0.95, 0.62, 0.20, 0.55),
	"storage": Color(0.55, 0.35, 0.75, 0.55),
	"presentation": Color(0.95, 0.85, 0.25, 0.55),
	"clutter": Color(0.40, 0.70, 0.35, 0.45),
}


static func colour_for(zone_name: String) -> Color:
	if COLORS.has(zone_name):
		return COLORS[zone_name]
	var hue := float(abs(zone_name.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85, 0.5)


static func clear(root: Node) -> void:
	var existing: Node = root.get_node_or_null(NodePath(OVERLAY_NAME))
	if existing:
		root.remove_child(existing)
		existing.queue_free()


# Rebuilds the overlay from what's in the scene. Returns how many rooms it
# could describe — zero means nothing generated here yet.
static func build(root: Node) -> int:
	clear(root)
	var kit := LIBRARY.kit(_kit_id(root))
	if kit == null:
		return 0
	var units := GEN_SCENE.read_units(root)
	if units.is_empty():
		return 0

	var overlay := Node3D.new()
	overlay.name = OVERLAY_NAME
	var mapped := 0
	for unit in units:
		if String(unit["kind"]) != "room" or String(unit["type"]) == "":
			continue
		var arch := LIBRARY.room_archetype(String(unit["type"]))
		if arch == null:
			continue
		var same_layer := units.filter(
			func(u: Dictionary) -> bool: return String(u["layer"]) == String(unit["layer"]))
		var grid := ROUTE_SOLVER.solve(unit, LEVEL_PLANNER.occupancy_of(same_layer), kit)
		var zones := ZONES.map_geometry(grid)
		# the functional half needs an anchor; use the one that's actually there
		var anchor := _anchor_of(root, String(unit["id"]), kit)
		if anchor.x >= 0:
			ZONES.map_function(zones, grid, anchor - (grid["origin"] as Vector2i),
				Vector2i.ONE, arch)
		overlay.add_child(_tiles(zones, unit, kit))
		mapped += 1

	if mapped == 0:
		overlay.free()
		return 0
	# ownerless on purpose — renders, never saves
	root.add_child(overlay)
	return mapped


# ---- internals -------------------------------------------------------------

static func _kit_id(root: Node) -> String:
	var generated := GEN_SCENE.generated_root(root, "Geometry")
	if generated and generated.has_meta("lb_kit"):
		return String(generated.get_meta("lb_kit"))
	return "greybox"


static func _anchor_of(root: Node, unit_id: String, kit: Resource) -> Vector2i:
	var props: Node = GEN_SCENE.generated_root(root, "Props")
	if props == null:
		return Vector2i(-1, -1)
	var group: Node = props.get_node_or_null(NodePath(TYPES.unit_node_name(unit_id)))
	if group == null:
		return Vector2i(-1, -1)
	for child in group.get_children():
		if not String(child.name).begins_with("Anchor"):
			continue
		return Vector2i(
			floori((child as Node3D).position.x / kit.cell),
			floori((child as Node3D).position.z / kit.cell))
	return Vector2i(-1, -1)


static func _tiles(zones: Dictionary, unit: Dictionary, kit: Resource) -> Node3D:
	var group := Node3D.new()
	group.name = TYPES.unit_node_name(String(unit["id"]))
	var origin: Vector2i = zones["origin"]
	var cell: float = kit.cell
	var y := TYPES.surface_y(unit, kit) + LIFT

	# one mesh per zone colour, not one per cell — a big level is thousands of
	# cells and that many MeshInstance3Ds makes the editor crawl
	var by_zone := {}
	for z in int(zones["h"]):
		for x in int(zones["w"]):
			var zone := ZONES.name_of(zones, TYPES.grid_get(zones, x, z))
			if zone == "none":
				continue
			if not by_zone.has(zone):
				by_zone[zone] = PackedVector3Array()
			_quad(by_zone[zone], (origin.x + x) * cell, (origin.y + z) * cell, cell, y)

	for zone in by_zone:
		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = by_zone[zone]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = colour_for(String(zone))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.name = String(zone).capitalize()
		instance.mesh = mesh
		group.add_child(instance)
	return group


static func _quad(into: PackedVector3Array, x: float, z: float, size: float, y: float) -> void:
	var inset := size * 0.05  # hairline gap so the grid reads as cells
	var x0 := x + inset
	var z0 := z + inset
	var x1 := x + size - inset
	var z1 := z + size - inset
	into.append(Vector3(x0, y, z0))
	into.append(Vector3(x0, y, z1))
	into.append(Vector3(x1, y, z1))
	into.append(Vector3(x0, y, z0))
	into.append(Vector3(x1, y, z1))
	into.append(Vector3(x1, y, z0))
