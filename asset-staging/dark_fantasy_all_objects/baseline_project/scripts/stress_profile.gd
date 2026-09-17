extends RefCounted
class_name StressProfile

const MAX_STRESS := 100.0
const UNEASE_THRESHOLD := 40.0
const AUDIO_THRESHOLD := 60.0
const VISION_THRESHOLD := 80.0
const NEED_THRESHOLD := 25.0
const LOW_HEALTH_RATIO := 0.30
const DARKNESS_RATE := 0.09
const LOW_HEALTH_RATE := 0.07
const LOW_NEED_RATE := 0.04
const CONDITION_RATE := 0.035
const THREAT_RATE := 0.06
const MAX_GAIN_RATE := 0.4
const DAMAGE_FACTOR := 0.35
const MAX_DAMAGE_GAIN := 12.0
const SAFE_RECOVERY_RATE := 0.35
const CAMP_RELIEF := {"rest": 18.0, "meal": 30.0, "treat": 6.0}


static func stage_index(value: float) -> int:
	if value >= VISION_THRESHOLD:
		return 3
	if value >= AUDIO_THRESHOLD:
		return 2
	if value >= UNEASE_THRESHOLD:
		return 1
	return 0


static func stage_name(value: float) -> String:
	return ["안정", "불안", "동요", "극심"][stage_index(value)]


static func gain_per_second(context: Dictionary, hunger: float, thirst: float, condition_count: int) -> float:
	# Empty context means ordinary survival-only simulation (including camp).
	# Only active dungeon exploration supplies the live environmental context.
	if context.is_empty() or bool(context.get("safe_zone", false)):
		return 0.0
	var rate := 0.0
	if not bool(context.get("torch_lit", true)):
		rate += DARKNESS_RATE
	if float(context.get("health_ratio", 1.0)) <= LOW_HEALTH_RATIO:
		rate += LOW_HEALTH_RATE
	if hunger <= NEED_THRESHOLD:
		rate += LOW_NEED_RATE
	if thirst <= NEED_THRESHOLD:
		rate += LOW_NEED_RATE
	rate += maxf(0.0, float(condition_count)) * CONDITION_RATE
	if bool(context.get("threatened", false)):
		rate += THREAT_RATE
	return minf(rate, MAX_GAIN_RATE)


static func damage_gain(actual_damage: float) -> float:
	return clampf(actual_damage * DAMAGE_FACTOR, 0.0, MAX_DAMAGE_GAIN)


static func audio_interval(value: float) -> float:
	return lerpf(14.0, 5.0, clampf((value - AUDIO_THRESHOLD) / (MAX_STRESS - AUDIO_THRESHOLD), 0.0, 1.0))


static func vision_interval(value: float) -> float:
	return lerpf(18.0, 7.0, clampf((value - VISION_THRESHOLD) / (MAX_STRESS - VISION_THRESHOLD), 0.0, 1.0))
