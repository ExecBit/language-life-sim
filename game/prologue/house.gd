extends Node3D

const Layout = preload("res://game/prologue/dormitory_layout.gd")
var doors := {}
const Actor = preload("res://game/prologue/actor.gd")
var actors := {}
var items := {}
var anchors := {}
var furniture := {}
var zones := {"breakfast_work": Vector3(-4,1,-2.6), "entrance": Vector3(0,0,5.8), "kitchen": Vector3(-3,0,0), "common": Vector3(-3,0,3), "bedroom": Vector3(3,0,0), "corridor": Vector3(0,0,0), "bed": Vector3(4.7,0,-4.4), "exit": Vector3(0,0,7.5)}
var environment: Environment
var sun: DirectionalLight3D
var door: Node3D
var door_collision: CollisionShape3D
var pointer: MeshInstance3D
var pointer_target := ""
var pointer_actor := "lena"
var pulse_time := 0.0
var lights: Array[OmniLight3D] = []

func _ready() -> void:
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9bb8c4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e2ebf1")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-25,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	Layout.build(self)
	door = Node3D.new()
	door.position = Vector3(-0.475,0,5)
	add_child(door)
	var leaf := body("door",Vector3(0.475,1.05,0),Vector3(0.95,2.1,0.12),door)
	door_collision = leaf.get_child(0)
	visual(leaf,BoxMesh.new(),Vector3.ZERO,Vector3(0.95,2.1,0.12),Color("647c75"))
	visual(leaf,SphereMesh.new(),Vector3(0.33,0,0.1),Vector3.ONE*0.07,Color("e1bd6c"))

	table(Vector3(-4,0,-2.6),Vector3(3.6,0.12,1.3))
	table(Vector3(4.6,0,-2.6),Vector3(2.7,0.12,1.3))
	table(Vector3(-5.7,0,2.8),Vector3(1.4,0.12,1.1))
	box(Vector3(5.0,0.28,-4.7),Vector3(2.0,0.56,2.0),Color("775a48"))
	box(Vector3(5.0,0.62,-4.7),Vector3(1.9,0.2,1.95),Color("d7d1ba"))
	box(Vector3(5.0,0.76,-4.1),Vector3(1.85,0.1,0.9),Color("658c98"))
	box(Vector3(5.0,0.78,-5.25),Vector3(1.25,0.16,0.4),Color("efeadb"))
	for x in [-5.6,-2.5]:
		box(Vector3(x,0.45,-4.0),Vector3(0.6,0.12,0.6),Color("8e6e4e"))
		box(Vector3(x,0.8,-4.3),Vector3(0.6,0.7,0.1),Color("8e6e4e"))
		for dx in [-0.22,0.22]: box(Vector3(x+dx,0.22,-4.0),Vector3(0.08,0.44,0.5),Color("695346"))
	# Window panels, plants, shelves and warm practical lighting.
	for x in [-6.3,6.2]:
		visual(self,CylinderMesh.new(),Vector3(x,0.23,3.5),Vector3(0.55,0.3,0.55),Color("af775a"))
		visual(self,SphereMesh.new(),Vector3(x,0.8,3.5),Vector3(0.7,1.0,0.7),Color("567f59"))
	for y in [0.5,1.3,2.1]: box(Vector3(-6.5,y,-3.8),Vector3(0.65,0.1,2.0),Color("8f7358"))
	for position in [Vector3(-4.5,2.6,1.5),Vector3(4.5,2.6,1.5)]:
		var lamp := OmniLight3D.new()
		lamp.position = position
		lamp.light_color = Color("ffd6a2")
		lamp.light_energy = 0.45
		lamp.omni_range = 7
		add_child(lamp)
		lights.append(lamp)
		visual(self,SphereMesh.new(),position,Vector3.ONE*0.22,Color("f4dcaf"))
	# Safe overnight storage and a dedicated empty grocery compartment for the new resident.
	box(Vector3(3.05,0.35,-5.1),Vector3(1.2,0.7,0.55),Color("927960"))
	box(Vector3(-6.15,1.35,-3.6),Vector3(0.7,0.08,0.8),Color("b6a080"))
	var pantry := body("own_pantry",Vector3(-6.15,1.53,-3.6),Vector3(0.65,0.3,0.65))
	visual(pantry,BoxMesh.new(),Vector3(0,-0.1,0),Vector3(0.6,0.06,0.6),Color("d2c6ab"))
	for x in [-0.28,0.28]: visual(pantry,BoxMesh.new(),Vector3(x,0,0),Vector3(0.04,0.2,0.6),Color("b6a080"))
	visual(pantry,BoxMesh.new(),Vector3(0,0,-0.28),Vector3(0.6,0.2,0.04),Color("b6a080"))
	var nameplate := Label3D.new()
	nameplate.text = "Dein Fach"
	nameplate.font_size = 30
	nameplate.pixel_size = 0.002
	nameplate.position = Vector3(0,-0.07,0.31)
	pantry.add_child(nameplate)
	zones.own_pantry = pantry.position
	# Minimal cooking context: a board and a bowl at Lena's work surface.
	visual(self,BoxMesh.new(),Vector3(-4.35,0.965,-2.45),Vector3(0.55,0.035,0.35),Color("bd935e"))
	var bowl := TorusMesh.new()
	bowl.inner_radius = 0.09
	bowl.outer_radius = 0.13
	visual(self,bowl,Vector3(-4.9,1.0,-2.9),Vector3.ONE,Color("e7dbc3"))
	box(Vector3(-6.0,0.88,-0.9),Vector3(0.8,0.12,0.8),Color("97785c"))
	box(Vector3(-6.0,0.42,-0.9),Vector3(0.18,0.84,0.6),Color("6d5948"))
	var positions := {
		"tray":Vector3(-3.05,1,-2.6),"key_tray":Vector3(5.55,1,-2.6),
		"entrance_bag":Vector3(0.65,0.025,6.7),"bag_stand":Vector3(3.2,0.025,-3.6),
		"bell_stand":Vector3(-4.7,1,-2.6),
		"surface_common":Vector3(-4,1,-2.6),"surface_room":Vector3(4.4,1,-2.6),
		"surface_side":Vector3(-5.7,1,2.8),
		"nightstand":Vector3(3.35,0.76,-5.1),"bedside_spare":Vector3(2.75,0.76,-5.1),
		"kitchen_shelf":Vector3(-6.12,1,-0.9),"breakfast_table":Vector3(-3.65,1,-2.6),
	}
	for id in positions:
		var anchor := body(id,positions[id],Vector3(0.36,0.04,0.35))
		visual(anchor,BoxMesh.new(),Vector3(0,-0.015,0),Vector3(0.36,0.025,0.35),Color("b9c5b2"))
		anchors[id] = anchor
	for id in ["cup","bag","room_key","bell","bread"]:
		items[id] = make_item(id)
	# Water is scenery, not a second carrying exercise.
	var water := make_item("bottle")
	water.position = Vector3(-5.25,1,-2.6)
	for id in ["lena","anna"]:
		var actor := Actor.new()
		actor.actor_id = id
		add_child(actor)
		actors[id] = actor
		if id == "anna":
			actor.position = Vector3(-4.2,0,-8.4)
			actor.hide()
			actor.collision_layer = 0
		else: actor.position = Vector3.ZERO
		actor.arrived.connect(func():
			if pointer_actor == actor.actor_id and pointer_target != "": pulse_time = 4.0
		)
		var label := Label3D.new()
		label.text = "ANNA" if id == "anna" else "LENA"
		label.position.y = 1.85
		label.font_size = 28
		label.pixel_size = 0.0025
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		actor.add_child(label)
	pointer = MeshInstance3D.new()
	add_child(pointer)
	pointer.hide()

func safe_player_position(value: Vector3, player_rid: RID) -> Vector3:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = value
	query.exclude = [player_rid]
	for npc in actors.values(): query.exclude.append(npc.get_rid())
	if get_world_3d().direct_space_state.intersect_shape(query).is_empty(): return value
	return Vector3(0,0.9,clampf(value.z,-11.4,4.2))

func route_points(source: Vector3, destination: Vector3) -> Array[Vector3]:
	var from_room := Layout.room_at(source)
	var to_room := Layout.room_at(destination)
	var points: Array[Vector3] = []
	if from_room == to_room:
		if from_room != "" and not Layout.ROOMS[from_room].get("end_door",false) and absf(source.x-destination.x) > 0.8:
			var z: float = Layout.ROOMS[from_room].door_z
			points.append(Vector3(source.x,0,z))
			points.append(Vector3(destination.x,0,z))
	else:
		if from_room != "":
			var room: Dictionary = Layout.ROOMS[from_room]
			if doors.has(from_room): doors[from_room].open_door(null)
			if room.get("end_door",false): points.append(Vector3(0,0,-13))
			else: points.append(Vector3(room.side*2.0,0,room.door_z))
			points.append(Vector3(0,0,room.door_z))
		if to_room != "":
			var room: Dictionary = Layout.ROOMS[to_room]
			if doors.has(to_room): doors[to_room].open_door(null)
			points.append(Vector3(0,0,room.door_z))
			if room.get("end_door",false): points.append(Vector3(0,0,-13))
			else:
				points.append(Vector3(room.side*2.0,0,room.door_z))
				points.append(Vector3(destination.x,0,room.door_z))
	points.append(destination)
	return points

func material(color: Color) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = 0.85
	return value

func visual(parent: Node3D, mesh: Mesh, position_: Vector3, scale_: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if mesh is BoxMesh: mesh.size = Vector3.ONE
	node.mesh = mesh
	node.position = position_
	node.scale = scale_
	node.material_override = material(color)
	parent.add_child(node)
	return node

func body(id: String, position_: Vector3, size: Vector3, parent: Node3D = null) -> StaticBody3D:
	if parent == null: parent = self
	var node := StaticBody3D.new()
	node.position = position_
	node.set_meta("target_id",id)
	parent.add_child(node)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	return node

func box(position_: Vector3, size: Vector3, color: Color, solid := true) -> void:
	var parent: Node3D = body("",position_,size) if solid else Node3D.new()
	if not solid:
		parent.position = position_
		add_child(parent)
	visual(parent,BoxMesh.new(),Vector3.ZERO,size,color)

func table(position_: Vector3, size: Vector3) -> void:
	var id := "table_room" if position_.x > 0 else ("table_side" if position_.z > 0 else "table_common")
	var top := body(id,position_+Vector3(0,0.88,0),size)
	visual(top,BoxMesh.new(),Vector3.ZERO,size,Color("97785c"))
	for x in [-size.x*0.42,size.x*0.42]:
		for z in [-size.z*0.35,size.z*0.35]: box(position_+Vector3(x,0.42,z),Vector3(0.12,0.84,0.12),Color("6d5948"))

func make_item(id: String) -> StaticBody3D:
	var node := body(id,Vector3.ZERO,Vector3(0.26,0.28,0.26))
	if id.begins_with("cup"):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.085
		mesh.bottom_radius = 0.065
		mesh.height = 0.17
		visual(node,mesh,Vector3(0,0.09,0),Vector3.ONE,Color("eee0bb"))
		var ring := TorusMesh.new()
		ring.inner_radius = 0.035
		ring.outer_radius = 0.055
		visual(node,ring,Vector3(0.105,0.09,0),Vector3.ONE,Color("eee0bb")).rotation_degrees.x = 90
	elif id.ends_with("key"):
		var ring := TorusMesh.new()
		ring.inner_radius = 0.035
		ring.outer_radius = 0.055
		visual(node,ring,Vector3(0,0.025,0),Vector3.ONE,Color("d6b56b"))
		visual(node,BoxMesh.new(),Vector3(0.09,0.025,0),Vector3(0.12,0.025,0.025),Color("d6b56b"))
		visual(node,BoxMesh.new(),Vector3(0.13,0.025,0.025),Vector3(0.025,0.025,0.06),Color("d6b56b"))
	elif id in ["apple","snack"]:
		visual(node,SphereMesh.new(),Vector3(0,0.13,0),Vector3(0.22,0.23,0.22),Color("c8644c") if id == "apple" else Color("acbf68"))
	elif id == "bread":
		# A single recognizable loaf with crust and scoring, not an extra exercise prop.
		visual(node,SphereMesh.new(),Vector3(0,0.1,0),Vector3(0.45,0.2,0.24),Color("b87938"))
		for x in [-0.12,0.0,0.12]:
			var cut := visual(node,BoxMesh.new(),Vector3(x,0.195,0),Vector3(0.025,0.009,0.12),Color("ecd3a0"))
			cut.rotation.y = 0.35
	elif id == "bottle":
		visual(node,CylinderMesh.new(),Vector3(0,0.2,0),Vector3(0.16,0.2,0.16),Color("83b8b5"))
		visual(node,CylinderMesh.new(),Vector3(0,0.43,0),Vector3(0.075,0.04,0.075),Color("426674"))
	elif id == "bell":
		var bell := CylinderMesh.new()
		bell.top_radius = 0.025
		bell.bottom_radius = 0.12
		bell.height = 0.16
		visual(node,bell,Vector3(0,0.1,0),Vector3.ONE,Color("d8b963"))
		visual(node,CylinderMesh.new(),Vector3(0,0.23,0),Vector3(0.04,0.07,0.04),Color("795d48"))
	elif id == "flashlight":
		visual(node,CylinderMesh.new(),Vector3(0,0.1,0),Vector3(0.11,0.15,0.11),Color("4f6971")).rotation_degrees.x = 90
		var light := OmniLight3D.new()
		light.name = "Beam"
		light.position = Vector3(0,0.1,0.15)
		light.omni_range = 4
		light.light_energy = 2
		light.visible = false
		node.add_child(light)
	elif id == "bag":
		visual(node,BoxMesh.new(),Vector3(0,0.15,0),Vector3(0.38,0.3,0.22),Color("7b656c"))
		visual(node,TorusMesh.new(),Vector3(0,0.34,0),Vector3(0.18,0.18,0.18),Color("51444d")).rotation_degrees.x = 90
	elif id == "cloth":
		visual(node,BoxMesh.new(),Vector3(0,0.03,0),Vector3(0.26,0.06,0.2),Color("8caaa2"))
	else:
		visual(node,SphereMesh.new(),Vector3(0,0.08,0),Vector3(0.2,0.14,0.15),Color("98968f"))
	return node

func position_of(id: String) -> Vector3:
	if furniture.has(id): return furniture[id].global_position
	if items.has(id): return items[id].global_position + Vector3(0,0.12,0)
	if id in ["bottle","water"]: return Vector3(-5.25,1,-2.6) + Vector3(0,0.12,0)
	if anchors.has(id): return anchors[id].global_position + Vector3(0,0.15,0)
	if actors.has(id): return actors[id].global_position + Vector3(0,1.2,0)
	return zones.get(id,Vector3.ZERO) + Vector3(0,0.15,0)

func sync_items(state, player_hand: Node3D) -> void:
	for id in state.items:
		var location: String = state.items[id]
		var parent: Node3D = player_hand if location in ["player","player_pocket"] else (actors[location].hand if actors.has(location) else anchors[location])
		if items[id].get_parent() != parent: items[id].reparent(parent,false)
		items[id].position = Vector3.ZERO
		items[id].rotation = Vector3.ZERO
		items[id].visible = location != "player_pocket" and (id != "bread" or state.day == 2)
		items[id].collision_layer = 0 if location in ["lena","anna","player","player_pocket"] or not items[id].visible else 1

func point(actor: String, target: String) -> void:
	pointer_actor = actor
	pointer_target = target
	if actors.has(actor):
		actors[actor].face(position_of(target))
		actors[actor].gesture("emote_point_at_opponent")
	pulse_time = 4.0

func set_period(period: String) -> void:
	sun.light_energy = 0.15 if period == "evening" else 0.9
	environment.ambient_light_energy = 0.18 if period == "evening" else 0.45
	environment.background_color = Color("344959") if period == "evening" else Color("a9c8d5")
	for light in lights: light.light_energy = 1.3 if period == "evening" else 0.45


func _process(delta: float) -> void:
	pulse_time -= delta
	pointer.visible = pulse_time > 0 and pointer_target != "" and actors.has(pointer_actor)
	if not pointer.visible: return
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("e2b765")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,mat)
	mesh.surface_add_vertex(actors[pointer_actor].hand.global_position)
	mesh.surface_add_vertex(position_of(pointer_target))
	mesh.surface_end()
	pointer.mesh = mesh
