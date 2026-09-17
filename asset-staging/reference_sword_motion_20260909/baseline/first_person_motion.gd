extends RefCounted
class_name FirstPersonMotion
## Presentation curves sample the real combat clock. They do not advance an
## attack, move a projectile, spend resources, or change the camera's aim.

const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")

const SWORD_HIT_TIME := 0.055
const SWORD_ACTIVE_END := 0.16
const EQUIP_DURATION := 0.32
const BOW_RENOCK_DURATION := 0.55


static func smooth_phase(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func damping(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(0.0, rate) * maxf(0.0, delta))


static func pose(position: Vector3, degrees: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(degrees * PI / 180.0), position)


static func blend(a: Transform3D, b: Transform3D, amount: float) -> Transform3D:
	return a.interpolate_with(b, smooth_phase(amount))


static func sword(phase: String, elapsed: float, charge: float = 0.0, guard := false, shield := true, variant := "right_diagonal") -> Transform3D:
	if shield:
		return CHOREOGRAPHY.guard_sword(1.0) if guard else CHOREOGRAPHY.sword(phase, elapsed, charge, variant)
	return _legacy_sword(phase, elapsed, charge, guard, shield)


static func _legacy_sword(phase: String, elapsed: float, charge: float, guard: bool, shield: bool) -> Transform3D:
	var ready := CHOREOGRAPHY.ready()
	var windup := pose(Vector3(0.53, 0.06, -0.60), Vector3(-34, 15, -46))
	windup.origin += Vector3(0.015, 0.04, 0.035) * clampf(charge, 0.0, 1.0)
	# The edge travels across the left melee space just before contact, then
	# follows forward through it. The actual modeled blade owns this sweep.
	var crossing := pose(Vector3(0.30, -0.30, -1.115), Vector3(20, -15, 95))
	var impact := pose(Vector3(0.30, -0.255, -1.160), Vector3(20, -15, 95))
	var follow := pose(Vector3(0.30, -0.10, -1.15), Vector3(20, -15, 95))
	var extension := pose(Vector3(0.474, 0.0065, -0.845), Vector3(53.51, -27.59, 62.36))
	var recover := pose(Vector3(0.43, -0.20, -0.74), Vector3(-15, -24, 48))
	if guard:
		return pose(Vector3(0.704, -0.352, -0.867), Vector3(-16.73, -28.92, 11.72)) if shield else pose(Vector3(0.34, -0.09, -0.65), Vector3(-13, -25, 58))
	match phase:
		"windup":
			return blend(ready, windup, elapsed / 0.22)
		"active":
			if elapsed <= 0.05:
				return blend(windup, crossing, elapsed / 0.05)
			if elapsed <= SWORD_HIT_TIME:
				return blend(crossing, impact, (elapsed - 0.05) / (SWORD_HIT_TIME - 0.05))
			if elapsed <= 0.07:
				return blend(impact, follow, (elapsed - SWORD_HIT_TIME) / (0.07 - SWORD_HIT_TIME))
			if elapsed <= 0.12:
				return blend(follow, extension, (elapsed - 0.07) / 0.05)
			return blend(extension, recover, (elapsed - 0.12) / (SWORD_ACTIVE_END - 0.12))
		"recovery":
			return blend(recover, ready, elapsed / lerpf(0.47, 0.68, clampf(charge, 0.0, 1.0)))
		"guard_break":
			var lowered := pose(Vector3(0.42, -0.42, -0.48), Vector3(-3, 10, -61))
			return blend(lowered, ready, elapsed / 1.05)
	return ready


static func bow(draw: float, release_progress: float = 1.0, release_draw_ratio: float = 1.0) -> Transform3D:
	# Carry the undrawn bow closer and more side-on so the two real contact
	# points have enough projected separation for each anatomical wrist.
	var ready := pose(Vector3(-0.22, -0.16, -0.50), Vector3(12, 75, -20))
	var drawn := pose(Vector3(-0.27, -0.10, -0.70), Vector3(10, 60, -5))
	return blend(ready, drawn, draw) if release_progress >= 1.0 else blend(blend(ready, drawn, release_draw_ratio), ready, release_progress)


static func flail(state: String, elapsed: float, phase: float, charge: float) -> Transform3D:
	var ready := pose(Vector3(0.42, -0.16, -0.67), Vector3(-20, -12, 16))
	var raised := pose(Vector3(0.48, 0.09, -0.62), Vector3(-26, 18, -65))
	var extended := pose(Vector3(0.38, -0.17, -0.91), Vector3(-35, -32, 60))
	match state:
		"melee":
			if elapsed < 0.12:
				return blend(ready, raised, elapsed / 0.12)
			if elapsed < 0.20:
				return blend(raised, extended, (elapsed - 0.12) / 0.08)
			return blend(extended, ready, (elapsed - 0.20) / 0.45)
		"spinning":
			var result := blend(ready, raised, elapsed / 0.24)
			result.origin += Vector3(cos(phase) * 0.018, sin(phase) * 0.015, 0) * clampf(charge + 0.25, 0.0, 1.0)
			return result
		"outbound":
			return blend(raised, extended, elapsed / 0.16)
		"returning":
			var catching := pose(Vector3(0.44, -0.08, -0.70), Vector3(-16, -15, 25))
			return blend(extended, catching, elapsed / 0.22)
		"recovery":
			return blend(pose(Vector3(0.44, -0.08, -0.70), Vector3(-16, -15, 25)), ready, elapsed / 0.25)
	return ready


static func staff(cast_remaining: float) -> Transform3D:
	var ready := pose(Vector3(0.33, 0.30, -1.10), Vector3(-45, -5, -9))
	if cast_remaining <= 0.0:
		return ready
	var elapsed := 0.22 - clampf(cast_remaining, 0.0, 0.22)
	var casting := pose(Vector3(0.22, 0.13, -1.22), Vector3(-65, -22, 32))
	return blend(ready, casting, elapsed / 0.055) if elapsed <= 0.055 else blend(casting, ready, (elapsed - 0.055) / 0.165)


static func shield(blocking: bool, impact_remaining: float, phase: String) -> Transform3D:
	var result := pose(Vector3(-0.3985, -0.5272, -0.6575), Vector3(-19.28, 83.44, -41.75))
	if blocking:
		result = pose(Vector3(-0.231, -0.109, -0.696), Vector3(24.62, 66.04, -10))
	elif phase in ["windup", "active"]:
		result = pose(Vector3(-0.8807, -0.0812, -0.7519), Vector3(11.36, -16.61, 77))
	# A compact damped recoil travels backward once; no high frequency rattling.
	if impact_remaining > 0.0:
		var pulse := sin(clampf(impact_remaining / 0.22, 0.0, 1.0) * PI)
		var braced := pose(Vector3(-0.4759, 0.0273, -0.7502), Vector3(39.45, 95.56, -16.5))
		result = result.interpolate_with(braced, pulse)
	return result


static func locomotion(clock: float, speed: float, side_speed: float, aiming: bool) -> Dictionary:
	var amount := clampf(speed / 4.2, 0.0, 1.5)
	var sprint := clampf((speed - 4.2) / 2.0, 0.0, 1.0)
	var aim_scale := 0.18 if aiming else 1.0
	var stride := clock * lerpf(7.3, 10.5, sprint)
	var position := Vector3(sin(stride) * 0.015, -absf(sin(stride)) * 0.016, cos(stride * 2.0) * 0.008) * amount * aim_scale
	position += Vector3(0.0, sin(clock * 1.65) * 0.004, sin(clock * 1.1) * 0.002) * (1.0 - minf(amount, 1.0))
	position += Vector3(0.03, -0.12, 0.055) * sprint * aim_scale
	var rotation := Vector3(cos(stride * 2.0) * 0.013, sin(stride) * 0.016, -side_speed * 0.012) * amount * aim_scale
	rotation += Vector3(0.10, 0.0, -0.04) * sprint * aim_scale
	return {"position": position, "rotation": rotation, "sprint": sprint}


static func elbow(shoulder: Vector3, wrist: Vector3, pole: Vector3) -> Vector3:
	var axis := wrist - shoulder
	var direction := axis.normalized() if axis.length_squared() > 0.000001 else Vector3.FORWARD
	var perpendicular := pole - direction * pole.dot(direction)
	if perpendicular.length_squared() < 0.000001:
		perpendicular = Vector3.DOWN
	var reach := axis.length()
	var bend := clampf(0.23 - (reach - 0.40) * 0.34, 0.045, 0.23)
	return shoulder.lerp(wrist, 0.52) + perpendicular.normalized() * bend
