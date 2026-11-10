extends StaticBody3D
const MODEL_PATH := "res://implementations/dormitory/game/shop/Assets/vendor.vrm"
const FALLBACK_PATH := "res://implementations/dormitory/game/shop/Assets/fallback_vendor.vrm"
var visual: Node3D
var hand: Node3D
var moving: Tween
var actor_id := "vendor"

func _ready() -> void:
	set_meta("target_id","vendor")
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.65
	capsule.radius = 0.3
	collider.shape = capsule
	collider.position.y = 0.85
	add_child(collider)
	hand = Marker3D.new()
	hand.position = Vector3(-0.35,1.0,0)
	add_child(hand)
	if ResourceLoader.exists(MODEL_PATH) or ResourceLoader.exists(FALLBACK_PATH):
		visual = load("res://implementations/dormitory/game/shop/seller_visual.gd").new()
		add_child(visual)
	else:
		# Explicit development fallback while the BOOTH file is being downloaded.
		var body := MeshInstance3D.new()
		body.mesh = CapsuleMesh.new()
		body.position.y = 0.9
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("4c7872")
		body.material_override = material
		add_child(body)
		var label := Label3D.new()
		label.text = "Продавец · VRM не установлен"
		label.position.y = 1.9
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 24
		add_child(label)
	face(global_position+Vector3(0,0,2))

func face(point: Vector3) -> void:
	var direction := point-global_position
	if Vector2(direction.x,direction.z).length() > 0.01: rotation.y = atan2(-direction.x,-direction.z)

func gesture(name: String) -> void:
	if visual != null and name in visual.Catalog.SCENES: visual.play(name)
