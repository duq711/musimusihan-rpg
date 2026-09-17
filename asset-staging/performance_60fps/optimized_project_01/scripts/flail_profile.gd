extends RefCounted
class_name FlailProfile

const MELEE_DAMAGE := 32.0
const MELEE_STAMINA := 18.0
const MELEE_HIT_TIME := 0.20
const MELEE_DURATION := 0.65
const SPIN_STAMINA := 24.0
const MIN_SPIN_DURATION := 0.35
const FULL_SPIN_DURATION := 1.2
const RECOVERY_DURATION := 0.25
const HEAD_RADIUS := 0.20
const RETURN_SPEED := 22.0


static func charge_for_time(seconds: float) -> float:
	return clampf(seconds / FULL_SPIN_DURATION, 0.0, 1.0)


static func throw_damage(charge: float) -> float:
	return lerpf(28.0, 60.0, clampf(charge, 0.0, 1.0))


static func throw_range(charge: float) -> float:
	return lerpf(6.0, 14.0, clampf(charge, 0.0, 1.0))


static func throw_speed(charge: float) -> float:
	return lerpf(14.0, 26.0, clampf(charge, 0.0, 1.0))


static func spin_rate(charge: float) -> float:
	return TAU * lerpf(3.0, 5.0, clampf(charge, 0.0, 1.0))
