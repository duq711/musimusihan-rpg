extends RefCounted
## A single grounded thrust. The exact source blade tip follows the reserved
## creature's skin contact; damage is owned by the shared gameplay clock.
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const HIT_SECONDS := 0.82
const DURATION := 1.55
const PENETRATION := 0.10
const MIN_DISTANCE := 1.10
const MAX_DISTANCE := 1.65
const CONTACT_DISTANCE := 1.15

static func phase(elapsed: float) -> String:
	if elapsed < .55: return "포복 처형 · 칼끝 겨누기"
	if elapsed < HIT_SECONDS: return "포복 처형 · 내려찌르기"
	if elapsed < .94: return "포복 처형 · 결정타"
	return "포복 처형 · 검 뽑기"

static func sword(elapsed: float, entry: Transform3D, contact: Vector3, direction: Vector3, blade_tip: Vector3) -> Transform3D:
	var frame := POSE.held(Vector3.ZERO, direction, -12.0)
	frame.origin = contact - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.25)
	var buried := frame.translated(direction * PENETRATION)
	var withdrawn := frame.translated(direction * -.34)
	if elapsed < .36: return POSE.mix(entry, chamber, elapsed / .36)
	if elapsed < .55: return chamber
	# Keep the full blade on one axis through thrust and withdrawal.
	if elapsed < HIT_SECONDS: return chamber.interpolate_with(buried, (elapsed - .55) / (HIT_SECONDS - .55))
	if elapsed < .94: return buried
	if elapsed < 1.20: return POSE.mix(buried, withdrawn, (elapsed - .94) / .26)
	return POSE.mix(withdrawn, POSE.ready(), (elapsed - 1.20) / (DURATION - 1.20))

static func shield(elapsed: float, entry: Transform3D) -> Transform3D:
	var lowered := entry.translated(Vector3(-.10, -.18, .04))
	if elapsed < .36: return POSE.mix(entry, lowered, elapsed / .36)
	if elapsed < 1.20: return lowered
	return POSE.mix(lowered, entry, (elapsed - 1.20) / (DURATION - 1.20))

static func camera_offset(elapsed: float) -> Vector3:
	var weight := smoothstep(0, .36, elapsed) * (1.0 - smoothstep(1.10, DURATION, elapsed))
	return Vector3(0, -.045, -.035) * weight

static func camera_rotation(elapsed: float) -> Vector3:
	var weight := smoothstep(0, .36, elapsed) * (1.0 - smoothstep(1.10, DURATION, elapsed))
	return Vector3(-.025, 0, 0) * weight
