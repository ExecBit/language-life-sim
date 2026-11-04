class_name FpsPlayer
extends CharacterBody3D

## First-person controller (TAV-02, Issue #9).
##
## A `CharacterBody3D` with a capsule, an eye camera, WASD movement, gravity and mouse-look.
## There is deliberately no body mesh, no animation, no IK and no carried-object physics: the
## player *is* the camera, and the only thing this node decides is where the eye is and which
## way it looks.
##
## Collision is one rule: this node is on layer 1 and masks layer 1, which is the room shell
## only. Scenario props and NPC pick bodies stay on layer 2, so they can be aimed at and clicked
## but can never block, push or trap the player. That is why a first-person room cannot soft-lock.
##
## Every tunable (eye height, speed, sensitivity, pitch limit) arrives through `set_tunables`
## from `data/room/lex01_room.json`. Nothing here hard-codes a coordinate or a text string.

const PROBE_STEP_DISTANCE: float = 0.01

@export var gravity: float = 22.0

var camera: Camera3D
var walk_speed: float = 4.0
var eye_height: float = 1.6
var look_sensitivity: float = 0.0022
var pitch_limit_deg: float = 70.0

# `active` gates movement and look together: while an overlay, a pause or an answer menu is open
# the player stands still and the mouse belongs to the interface.
var _active: bool = true
var _look_enabled: bool = true
# Probe-only forward push, so a check drives the same movement code a keyboard drives.
var _walk_override: Vector2 = Vector2.ZERO


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("EyeCamera") as Camera3D
	_apply_eye_height()


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if _active:
		direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if direction.length_squared() <= 0.0:
			direction = _walk_override

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	var wanted: Vector3 = (global_transform.basis * Vector3(direction.x, 0.0, direction.y))
	if direction.length_squared() > 0.0 and wanted.length_squared() > 0.0:
		wanted = wanted.normalized()
	velocity.x = wanted.x * walk_speed
	velocity.z = wanted.z * walk_speed
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	# Looking and walking are gated apart: while an answer menu is up the player stands still but can
	# still turn the head, because a respond task asks them to look at the room.
	if not _look_enabled:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * look_sensitivity)
		if camera != null:
			camera.rotate_x(-event.relative.y * look_sensitivity)
			camera.rotation_degrees.x = clampf(camera.rotation_degrees.x, -pitch_limit_deg, pitch_limit_deg)


# region setup and state

func set_tunables(config: Dictionary) -> void:
	eye_height = float(config.get("eye_height", eye_height))
	walk_speed = float(config.get("walk_speed", walk_speed))
	look_sensitivity = float(config.get("look_sensitivity", look_sensitivity))
	pitch_limit_deg = float(config.get("pitch_limit_deg", pitch_limit_deg))
	if camera != null:
		camera.fov = float(config.get("fov", camera.fov))
		var capsule: CapsuleShape3D = _capsule_shape()
		if capsule != null:
			capsule.radius = float(config.get("capsule_radius", capsule.radius))
			capsule.height = float(config.get("capsule_height", capsule.height))
	_apply_eye_height()


## Put the player at a feet position and give it the facing a context declares.
func spawn_at(position: Vector3, rotation_deg: Vector3) -> void:
	global_position = position
	rotation_degrees = Vector3(0.0, rotation_deg.y, 0.0)
	velocity = Vector3.ZERO
	if camera != null:
		camera.rotation_degrees = Vector3(clampf(rotation_deg.x, -pitch_limit_deg, pitch_limit_deg), 0.0, 0.0)
	_apply_eye_height()


func set_active(enabled: bool) -> void:
	_active = enabled
	if not enabled:
		_walk_override = Vector2.ZERO
		velocity = Vector3.ZERO


func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled


func is_active() -> bool:
	return _active


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, eye_height, 0.0)


## Turn the eye toward a world point - yaw on the body, pitch on the camera.
func face_point(point: Vector3) -> void:
	var to: Vector3 = point - eye_position()
	var horizontal: float = Vector2(to.x, to.z).length()
	if horizontal <= 0.05:
		return
	rotation_degrees.y = rad_to_deg(atan2(-to.x, -to.z))
	if camera != null:
		camera.rotation_degrees.x = clampf(rad_to_deg(atan2(to.y, horizontal)), -pitch_limit_deg, pitch_limit_deg)

# endregion

# region probe-only movement helpers

## Walk straight ahead with the same movement code a keyboard drives, until the horizontal
## distance to `point` is within `stop_distance` or the frame guard runs out.
func walk_to(point: Vector3, stop_distance: float, max_frames: int) -> Dictionary:
	var start: Vector3 = global_position
	var frames: int = 0
	var blocked_frames: int = 0
	_walk_override = Vector2(0.0, -1.0)
	# Face the destination first: an object already within reach has to be looked at too, otherwise a
	# walk that needs no steps would leave the crosshair pointing wherever the spawn put it.
	face_point(point)
	while frames < max_frames:
		var to: Vector3 = point - global_position
		if Vector2(to.x, to.z).length() <= stop_distance:
			break
		face_point(point)
		var before: Vector3 = global_position
		frames += 1
		await get_tree().physics_frame
		if before.distance_to(global_position) < PROBE_STEP_DISTANCE:
			blocked_frames += 1
		else:
			blocked_frames = 0
	_walk_override = Vector2.ZERO
	# Face it once more from where the walk ended, because the last step changed the angle to it.
	face_point(point)
	var remaining: float = Vector2(point.x - global_position.x, point.z - global_position.z).length()
	return {
		"arrived": remaining <= stop_distance,
		"distance": remaining,
		"frames": frames,
		"blocked_frames": blocked_frames,
		"start": _text(start),
		"position": _text(global_position),
	}


## Walk forward blindly for a fixed number of physics frames, which is how a check proves a wall
## stops the player instead of letting them leave the room or fall through the floor.
func walk_forward_for(frames: int) -> Dictionary:
	var lowest_y: float = global_position.y
	var start: Vector3 = global_position
	_walk_override = Vector2(0.0, -1.0)
	for _frame: int in frames:
		await get_tree().physics_frame
		lowest_y = minf(lowest_y, global_position.y)
	_walk_override = Vector2.ZERO
	return {
		"start": _text(start),
		"position": _text(global_position),
		"lowest_y": lowest_y,
		"traveled": start.distance_to(global_position),
		"frames": frames,
	}

# endregion

func _apply_eye_height() -> void:
	if camera != null:
		camera.position = Vector3(0.0, eye_height, 0.0)


func _capsule_shape() -> CapsuleShape3D:
	for child: Node in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			return (child as CollisionShape3D).shape as CapsuleShape3D
	return null


func _text(position: Vector3) -> String:
	return "%.2f|%.2f|%.2f" % [position.x, position.y, position.z]
