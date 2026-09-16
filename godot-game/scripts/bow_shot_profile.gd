extends RefCounted
class_name BowShotProfile

# A cone half-angle, not a fixed yaw/pitch offset: every point within the
# indicated aim cone is possible and no world direction is favored.
const MAX_SPREAD_DEGREES := 12.0
const DRAW_DURATION := 1.0
const MIN_DAMAGE := 18.0
const MAX_DAMAGE := 46.0
const STAMINA_DRAIN_PER_SECOND := 22.0
const SLACK_DRAW_RATIO := 0.1
const MAX_SPEED := 42.0
const SLACK_DROP_SPEED := 1.0
const SLACK_GRAVITY := 9.8
const FULL_DRAW_GRAVITY := 5.0


static func damage_for_draw(draw_ratio: float) -> float:
	return lerpf(MIN_DAMAGE, MAX_DAMAGE, clampf(draw_ratio, 0.0, 1.0))


static func is_slack_draw(draw_ratio: float) -> bool:
	return clampf(draw_ratio, 0.0, 1.0) <= SLACK_DRAW_RATIO


static func speed_for_draw(draw_ratio: float) -> float:
	# A quick tap has not tensioned the string. Above that short slack window,
	# forward launch speed grows from zero to the existing full-draw speed.
	return MAX_SPEED * _launch_tension(draw_ratio)


static func gravity_for_draw(draw_ratio: float) -> float:
	return lerpf(SLACK_GRAVITY, FULL_DRAW_GRAVITY, _launch_tension(draw_ratio))


static func _launch_tension(draw_ratio: float) -> float:
	return clampf((draw_ratio - SLACK_DRAW_RATIO) / (1.0 - SLACK_DRAW_RATIO), 0.0, 1.0)


static func spread_degrees(draw_ratio: float) -> float:
	var instability := 1.0 - clampf(draw_ratio, 0.0, 1.0)
	return MAX_SPREAD_DEGREES * instability * instability


static func recoil_strength(draw_ratio: float) -> float:
	if is_slack_draw(draw_ratio):
		return 0.0
	return lerpf(1.0, 0.25, clampf(draw_ratio, 0.0, 1.0))


static func sample_direction(aim: Vector3, draw_ratio: float, rng: RandomNumberGenerator) -> Vector3:
	var forward := aim.normalized() if aim.length_squared() > 0.000001 else Vector3.FORWARD
	var cone_angle := deg_to_rad(spread_degrees(draw_ratio))
	# Full draw is exact, with no hidden minimum spread and no random draw.
	if cone_angle <= 0.0:
		return forward
	var reference_up := Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var right := forward.cross(reference_up).normalized()
	var up := right.cross(forward).normalized()
	# Uniform solid-angle sampling avoids square corners and directional bias.
	var cos_angle := lerpf(1.0, cos(cone_angle), rng.randf())
	var sin_angle := sqrt(maxf(0.0, 1.0 - cos_angle * cos_angle))
	var azimuth := rng.randf() * TAU
	return (forward * cos_angle + (right * cos(azimuth) + up * sin(azimuth)) * sin_angle).normalized()
