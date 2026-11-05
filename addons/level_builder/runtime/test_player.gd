extends CharacterBody3D

# The bundled Test Walk player. Zero dependencies on purpose: builds its own
# capsule, camera and HUD in _ready, reads physical keys directly so it works
# in projects with no input map. This is a QA tool, not a shipping controller —
# the Controller pack is the real one.
#
# WASD move · mouse look · Space jump · Shift run · F fly · Esc release mouse

const WALK_SPEED := 5.0
const RUN_SPEED := 9.0
const FLY_SPEED := 12.0
const JUMP_VELOCITY := 4.8
const MOUSE_SENS := 0.0025

var _cam: Camera3D
var _flying := false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	collision_layer = 2   # Player role
	collision_mask = 5    # World + Enemy

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.35
	cap_mesh.height = 1.7
	mesh.mesh = cap_mesh
	mesh.position = Vector3(0, 0.85, 0)
	add_child(mesh)

	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.55, 0)
	_cam.current = true
	add_child(_cam)

	var hud := CanvasLayer.new()
	var hint := Label.new()
	hint.text = "TEST WALK   WASD move · Space jump · Shift run · F fly · Esc mouse"
	hint.position = Vector2(12, 8)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 4)
	hud.add_child(hint)
	add_child(hud)

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENS)
		_cam.rotate_x(-motion.relative.y * MOUSE_SENS)
		_cam.rotation.x = clampf(_cam.rotation.x, -1.4, 1.4)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				else Input.MOUSE_MODE_CAPTURED
		elif key.physical_keycode == KEY_F:
			_flying = not _flying
			velocity = Vector3.ZERO
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()
	var forward := -global_basis.z
	var right := global_basis.x

	if _flying:
		var fly := (forward * -input_dir.y + right * input_dir.x) * FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SPACE):
			fly.y += FLY_SPEED
		if Input.is_physical_key_pressed(KEY_SHIFT):
			fly.y -= FLY_SPEED
		velocity = fly
	else:
		var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
		var horizontal := (forward * -input_dir.y + right * input_dir.x) * speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		if not is_on_floor():
			velocity.y -= _gravity * delta
		elif Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_VELOCITY
	move_and_slide()
