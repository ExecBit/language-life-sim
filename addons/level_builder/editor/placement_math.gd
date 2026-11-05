@tool
extends Object

# The math half of place mode, kept pure so verify can hammer it headless.
# The controller feeds it raycast hits; it answers where and how the piece sits.


# Grid snap on the ground plane. Y stays put — height comes from the surface hit.
static func snap_position(pos: Vector3, step: float) -> Vector3:
	if step <= 0.0:
		return pos
	return Vector3(snappedf(pos.x, step), pos.y, snappedf(pos.z, step))


# Basis with local up = surface normal, yawed around it. Degenerate normals
# (straight down, zero) fall back to plain yaw so nothing flips inside walls.
static func align_to_normal(normal: Vector3, yaw: float) -> Basis:
	var up := normal.normalized()
	if not up.is_finite() or up.length_squared() < 0.5 or up.dot(Vector3.UP) < -0.99:
		up = Vector3.UP
	var basis := Basis.IDENTITY
	if up.dot(Vector3.UP) < 0.9999:
		var axis := Vector3.UP.cross(up).normalized()
		basis = Basis(axis, Vector3.UP.angle_to(up))
	return basis.rotated(up, yaw)


static func step_yaw(current: float, step_deg: float, direction: int) -> float:
	if step_deg <= 0.0:
		return current
	return wrapf(current + deg_to_rad(step_deg) * float(direction), 0.0, TAU)


static func random_yaw(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(0.0, TAU)


static func random_scale(rng: RandomNumberGenerator, s_min: float, s_max: float) -> float:
	if s_max <= s_min:
		return maxf(s_min, 0.01)
	return rng.randf_range(s_min, s_max)


# Full transform for a placement: hit point + normal + the profile knobs.
static func placement_transform(hit_pos: Vector3, hit_normal: Vector3, yaw: float,
		snap_step: float, align: bool, scale: float) -> Transform3D:
	var basis := align_to_normal(hit_normal if align else Vector3.UP, yaw)
	basis = basis.scaled(Vector3.ONE * scale)
	return Transform3D(basis, snap_position(hit_pos, snap_step))
