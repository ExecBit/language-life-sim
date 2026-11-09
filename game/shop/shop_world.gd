extends "res://game/prologue/house.gd"
const Vendor = preload("res://game/shop/vendor.gd")
var register_label: Label3D

func _ready() -> void:
	zones = {"spawn":Vector3(0,0.9,4.15),"exit":Vector3(0,0,4.5)}
	box(Vector3(0,-0.15,0),Vector3(10,0.3,11),Color("d6ccad"))
	box(Vector3(0,3.15,0),Vector3(10,0.15,11),Color("ebe5d3"),false)
	for x in [-5.0,5.0]: box(Vector3(x,1.6,0),Vector3(0.2,3.2,11),Color("d1dbcb"))
	box(Vector3(0,1.6,-5.5),Vector3(10,3.2,0.2),Color("d1dbcb"))
	for x in [-3.1,3.1]: box(Vector3(x,1.6,5.5),Vector3(3.8,3.2,0.2),Color("71877e"))
	var exit := body("shop_exit",Vector3(0,1.2,5.4),Vector3(2.1,2.4,0.15))
	visual(exit,BoxMesh.new(),Vector3.ZERO,Vector3(2.1,2.4,0.1),Color("91b3b2"))
	make_sign(exit,"←",Vector3(0,0.3,-0.1),60).rotation.y = PI
	# Windows and a quiet, distinct shop palette.
	for x in [-3.2,3.2]:
		box(Vector3(x,1.7,5.35),Vector3(2.5,1.45,0.05),Color("a9d0d0"),false)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	for x in [-2.8,2.8]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,2.65,0)
		lamp.light_energy = 0.9
		lamp.omni_range = 8
		lamp.light_color = Color("ffe6be")
		add_child(lamp)
		visual(self,BoxMesh.new(),lamp.position,Vector3(1.6,0.05,0.28),Color("f3e8c8"))
	shelf(Vector3(-3.6,0,-1.6),Vector3(2.2,0.1,1.0))
	shelf(Vector3(3.6,0,-3.9),Vector3(1.8,0.1,0.9))
	shelf(Vector3(-3.5,0,-4.4),Vector3(2.4,0.1,0.6))
	# Non-interactive produce supplies visual context without a third shopping requirement.
	for x in [-4.2,-3.8,-3.4,-3.0]:
		visual(self,SphereMesh.new(),Vector3(x,1.05,-4.4),Vector3.ONE*0.19,Color("b85f46"))
	box(Vector3(2.25,0.46,0.55),Vector3(4.3,0.92,1.15),Color("668579"))
	box(Vector3(2.25,0.95,0.55),Vector3(4.45,0.08,1.25),Color("e0cfae"))
	var positions := {"shelf_bread":Vector3(-3.6,1.05,-1.6),"shelf_milk":Vector3(3.6,1.05,-3.9),
		"counter_left":Vector3(1.0,1.02,0.7),"counter_right":Vector3(1.8,1.02,0.7),"packing_stand":Vector3(3.8,1.02,0.7)}
	for id in positions:
		var anchor := body(id,positions[id],Vector3(0.55,0.025,0.5))
		visual(anchor,BoxMesh.new(),Vector3.ZERO,Vector3(0.55,0.02,0.5),Color("c5cdb8"))
		anchors[id] = anchor
	# Full tabletop is also a valid placement target, using the first free checkout slot.
	var counter := body("shop_counter",Vector3(2.25,0.99,0.55),Vector3(4.4,0.025,1.2))
	var register := body("checkout",Vector3(2.8,1.24,0.35),Vector3(0.6,0.5,0.3))
	visual(register,BoxMesh.new(),Vector3.ZERO,Vector3(0.6,0.5,0.3),Color("334b48"))
	register_label = make_sign(register,"0,00 €",Vector3(0,0,0.16),32)
	items.grocery_bread = make_item("bread")
	items.grocery_bread.set_meta("target_id","grocery_bread")
	items.grocery_milk = milk()
	items.shopping_bag = bag()
	var vendor := Vendor.new()
	vendor.position = Vector3(1.8,0,-0.7)
	add_child(vendor)
	actors.vendor = vendor
	pointer_actor = "vendor"
	pointer = MeshInstance3D.new()
	add_child(pointer)
	pointer.hide()
	make_sign(self,"SUPERMARKT",Vector3(0,2.65,-5.33),65)
	make_sign(self,"1,80 €",Vector3(-3.6,0.9,-1.02),34)
	make_sign(self,"1,20 €",Vector3(3.6,0.9,-3.37),34)

func shelf(position_: Vector3, size: Vector3) -> void:
	for y in [0.2,0.95]: box(position_+Vector3(0,y,0),size,Color("aa8a61"))
	for x in [-size.x*0.45,size.x*0.45]: box(position_+Vector3(x,0.55,0),Vector3(0.1,1.1,size.z),Color("7a7156"))

func make_sign(parent: Node3D, text: String, position_: Vector3, size := 30) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.003
	label.position = position_
	label.outline_size = 5
	parent.add_child(label)
	return label

func milk() -> StaticBody3D:
	var node := body("grocery_milk",Vector3.ZERO,Vector3(0.25,0.46,0.25))
	visual(node,BoxMesh.new(),Vector3(0,0.2,0),Vector3(0.22,0.4,0.22),Color("f2eee0"))
	visual(node,BoxMesh.new(),Vector3(0,0.16,0.112),Vector3(0.2,0.18,0.01),Color("75a7ba"))
	var roof := PrismMesh.new()
	visual(node,roof,Vector3(0,0.43,0),Vector3(0.22,0.13,0.22),Color("75a7ba"))
	make_sign(node,"1 L",Vector3(0,0.17,0.122),26)
	return node

func bag() -> StaticBody3D:
	var node := body("shopping_bag",Vector3.ZERO,Vector3(0.42,0.5,0.28))
	visual(node,BoxMesh.new(),Vector3(0,0.2,0),Vector3(0.4,0.4,0.25),Color("bc9a63"))
	for z in [-0.09,0.09]:
		var ring := visual(node,TorusMesh.new(),Vector3(0,0.46,z),Vector3(0.18,0.18,0.18),Color("80653f"))
		ring.rotation.x = PI/2
	make_sign(node,"▱",Vector3(0,0.2,0.13),30)
	return node

func sync_shopping(state, player_hand: Node3D, home_anchors: Dictionary) -> void:
	for id in state.items:
		var location: String = state.items[id]
		var parent: Node3D = self
		if location == "player": parent = player_hand
		elif location == "in:shopping_bag": parent = items.shopping_bag
		elif home_anchors.has(location): parent = home_anchors[location]
		elif anchors.has(location): parent = anchors[location]
		if items[id].get_parent() != parent: items[id].reparent(parent,false)
		items[id].position = Vector3.ZERO
		items[id].rotation = Vector3.ZERO
		items[id].visible = location not in ["hidden","in:shopping_bag"]
		items[id].collision_layer = 0 if location in ["hidden","in:shopping_bag","player"] else 1
	register_label.text = "3,00 €\n✓" if state.paid else "%d/2\n%s" % [state.on_counter().size(),state.price(state.total())]
