extends StaticBody3D

const Visual = preload("res://implementations/dormitory/game/prologue/prologue_visual.gd")
signal arrived
const WALK_SPEED := 1.15 # metres per second; a calm indoor pace
var walking := false
var heading := 0.0
var pending_face := Vector3.INF
var pending_gesture := ""
var actor_id := "lena"
var visual: Node3D
var hand: Marker3D
var moving: Tween
var attention: MeshInstance3D

func _ready() -> void:
	set_meta("target_id", actor_id)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.65
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)
	visual = Visual.new()
	if actor_id == "anna": visual.avatar_path = "res://assets/characters/anna.vrm"
	add_child(visual)
	var attachment := BoneAttachment3D.new()
	visual.target_skeleton.add_child(attachment)
	attachment.bone_name = visual.bone("J_Bip_L_Hand")
	hand = Marker3D.new()
	hand.position = Vector3(0,-0.01,-0.03)
	attachment.add_child(hand)
	visual.target_skeleton.skeleton_updated.connect(func(): hand.global_basis = Basis.IDENTITY)
	attention = MeshInstance3D.new()
	var indicator := SphereMesh.new()
	indicator.radius = 0.065
	indicator.height = 0.13
	attention.mesh = indicator
	attention.position.y = 1.95
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("dfb967")
	attention.material_override = material
	add_child(attention)
	attention.hide()

func face(point: Vector3) -> void:
	if walking:
		pending_face = point
		return
	var direction := point-global_position
	if Vector2(direction.x,direction.z).length() > 0.01:
		heading = atan2(-direction.x,-direction.z)

func go(destination: Vector3, instant := false) -> void:
	if is_instance_valid(moving): moving.kill()
	pending_face = Vector3.INF
	pending_gesture = ""
	if instant or position.distance_to(destination) < 0.05:
		position = destination
		walking = false
		visual.stop()
		return
	var points: Array[Vector3] = get_parent().route_points(position,destination)
	walking = true
	visual.animation_player.speed_scale = 1.0
	visual.play("walking",true)
	moving = create_tween()
	moving.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var previous := position
	for point in points:
		var distance := previous.distance_to(point)
		if distance < 0.01: continue
		var direction := point-previous
		var angle := atan2(-direction.x,-direction.z)
		moving.tween_callback(func(): heading = angle)
		moving.tween_property(self,"position",point,distance/WALK_SPEED).set_trans(Tween.TRANS_LINEAR)
		previous = point
	moving.tween_callback(_arrive)

func _arrive() -> void:
	walking = false
	visual.stop()
	if pending_face != Vector3.INF: face(pending_face)
	if pending_gesture != "": gesture(pending_gesture)
	pending_face = Vector3.INF
	pending_gesture = ""
	arrived.emit()

func gesture(name: String) -> void:
	if walking:
		pending_gesture = name
		return
	if name in visual.Catalog.SCENES or name in visual.GeneratedCatalog.SCENES: visual.play(name)

func idle() -> void:
	if is_instance_valid(moving): moving.kill()
	walking = false
	pending_face = Vector3.INF
	pending_gesture = ""
	visual.stop()

func _process(delta: float) -> void:
	rotation.y = rotate_toward(rotation.y,heading,delta*3.5)
