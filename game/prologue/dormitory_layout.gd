extends RefCounted
## Authored rooms and their corridor doors, in metres. Shared by geometry and NPC routes.
const DOOR_WIDTH := 0.9
const DOOR_HEIGHT := 2.1
const ROOMS := {
	"kitchen":{"bounds":Rect2(-7,-6,5.9,7.5),"side":-1,"door_z":0.0,"label":"Küche"},
	"bedroom":{"bounds":Rect2(1.1,-6,5.9,7.5),"side":1,"door_z":0.0,"label":"01"},
	"common":{"bounds":Rect2(-7,1.5,5.9,3.5),"side":-1,"door_z":3.0,"label":"Gemeinschaftsraum"},
	"spare":{"bounds":Rect2(1.1,1.5,5.9,3.5),"side":1,"door_z":3.0,"label":"02"},
	"anna":{"bounds":Rect2(-7,-12,5.9,6),"side":-1,"door_z":-8.4,"label":"Anna · 03"},
	"lena":{"bounds":Rect2(1.1,-12,5.9,6),"side":1,"door_z":-8.4,"label":"Lena · 04"},
}

static func room_at(point: Vector3) -> String:
	for id in ROOMS:
		if ROOMS[id].bounds.has_point(Vector2(point.x,point.z)): return id
	return ""

static func build(h: Node3D) -> void:
	h.box(Vector3(0,-0.15,-1.5),Vector3(14,0.3,21),Color("aa9275"))
	h.box(Vector3(0,2.9,-3.5),Vector3(14,0.2,17),Color("e7e5dc"))
	for x in [-7.0,7.0]: h.box(Vector3(x,1.4,-3.5),Vector3(0.2,2.8,17),Color("d7d8c9"))
	h.box(Vector3(0,1.4,-12),Vector3(14,2.8,0.2),Color("c3cbbb"))
	for side in [-1.0,1.0]:
		h.box(Vector3(side*3.76,1.4,5),Vector3(6.48,2.8,0.2),Color("d4c6b1"))
	h.box(Vector3(0,2.5,5),Vector3(1.04,0.6,0.2),Color("d4c6b1"))
	# Corridor walls have actual narrow openings; all other segments are solid.
	for x in [-1.1,1.1]:
		var previous := -12.0
		for centre in [-8.4,0.0,3.0]:
			var edge: float = centre-0.49
			h.box(Vector3(x,1.4,(previous+edge)*0.5),Vector3(0.18,2.8,edge-previous),Color("dfddd2"))
			h.box(Vector3(x,2.5,centre),Vector3(0.18,0.6,0.98),Color("dfddd2"))
			previous = centre+0.49
		h.box(Vector3(x,1.4,(previous+5)*0.5),Vector3(0.18,2.8,5-previous),Color("dfddd2"))
	for z in [-6.0,1.5]:
		for side in [-1.0,1.0]: h.box(Vector3(side*4.05,1.4,z),Vector3(5.9,2.8,0.18),Color("d8d4c5"))
	for id in ROOMS:
		var data: Dictionary = ROOMS[id]
		var rect: Rect2 = data.bounds
		var centre := rect.get_center()
		h.box(Vector3(centre.x,0.012,centre.y),Vector3(rect.size.x-0.2,0.025,rect.size.y-0.2),Color("b8a27c") if data.side == 1 else (Color("82968d") if id == "kitchen" else Color("a5b1a5")),false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(centre.x,2.45,centre.y)
		lamp.omni_range = 6.0
		lamp.light_energy = 0.5
		lamp.light_color = Color("ffe5c4")
		h.add_child(lamp)
		h.lights.append(lamp)
	# Real furnished neighboring bedrooms, reached through the corridor.
	for side in [-1.0,1.0]:
		h.box(Vector3(side*5.6,0.3,-10.3),Vector3(1.5,0.6,2.2),Color("8d735c"))
		h.box(Vector3(side*5.6,0.65,-10.3),Vector3(1.45,0.15,2.15),Color("8fa4b5") if side < 0 else Color("a9ad7d"))
		h.box(Vector3(side*3.1,0.72,-11.3),Vector3(1.8,0.12,0.65),Color("9c805d"))
		h.box(Vector3(side*2.5,1.0,-6.5),Vector3(0.8,2,0.6),Color("9a8266"))
	# Shared room is separate from the kitchen, with seats and a low table.
	h.box(Vector3(-4.0,0.3,4.1),Vector3(2.8,0.6,0.85),Color("5c7e87"))
	h.box(Vector3(-4.0,0.8,4.5),Vector3(2.8,0.7,0.15),Color("5c7e87"))
	h.box(Vector3(-4.0,0.4,2.8),Vector3(1.6,0.12,0.7),Color("9c805d"))
	h.box(Vector3(-5.8,0.3,1.95),Vector3(0.8,0.6,0.8),Color("7c9186"))
	# A fourth, accessible bedroom by the entrance.
	h.box(Vector3(5.6,0.3,3.6),Vector3(1.5,0.6,2.1),Color("8d735c"))
	h.box(Vector3(5.6,0.65,3.6),Vector3(1.45,0.15,2.05),Color("b2a17f"))
	h.box(Vector3(3.1,0.72,4.4),Vector3(1.7,0.12,0.65),Color("9c805d"))
	for side in [-1.0,1.0]:
		for z in [-9.2,-3.7,3.0]: h.box(Vector3(side*6.88,1.8,z),Vector3(0.04,1.1,1.6),Color("a4cbd5"),false)
