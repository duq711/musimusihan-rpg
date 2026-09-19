extends RefCounted
## Brace, shallow stab, resisted deeper push, then axial withdrawal.
## The shared gameplay clock commits death only at the end of the deeper push.
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const PREPARE_END := 0.48
const THRUST_START := 0.75
const INITIAL_CONTACT := 1.03
const DEEP_THRUST_START := 1.18
const HIT_SECONDS := 1.52
const WITHDRAW_START := 1.72
const WITHDRAW_END := 2.12
const DURATION := 2.50
const SHALLOW_PENETRATION := 0.045
const PENETRATION := 0.22
const MIN_DISTANCE := 1.10
const MAX_DISTANCE := 1.65
const CONTACT_DISTANCE := 1.05

static func phase(elapsed: float) -> String:
	if elapsed < THRUST_START: return "포복 처형 · 찌를 자세 잡기"
	if elapsed < INITIAL_CONTACT: return "포복 처형 · 첫 찌르기"
	if elapsed < DEEP_THRUST_START: return "포복 처형 · 힘 싣기"
	if elapsed < HIT_SECONDS: return "포복 처형 · 깊게 밀어 넣기"
	if elapsed < WITHDRAW_START: return "포복 처형 · 결정타"
	return "포복 처형 · 검 뽑기"

static func sword(elapsed: float, entry: Transform3D, contact: Vector3, direction: Vector3, blade_tip: Vector3) -> Transform3D:
	var frame := POSE.held(Vector3.ZERO, direction, -12.0)
	frame.origin = contact - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.28)
	var shallow := frame.translated(direction * SHALLOW_PENETRATION)
	var buried := frame.translated(direction * PENETRATION)
	var withdrawn := frame.translated(direction * -.34)
	if elapsed < PREPARE_END: return POSE.mix(entry, chamber, elapsed / PREPARE_END)
	if elapsed < THRUST_START: return chamber
	# Each stroke and the extraction share one axis, with no re-aim inside skin.
	if elapsed < INITIAL_CONTACT: return chamber.interpolate_with(shallow, (elapsed - THRUST_START) / (INITIAL_CONTACT - THRUST_START))
	if elapsed < DEEP_THRUST_START: return shallow
	if elapsed < HIT_SECONDS: return POSE.mix(shallow, buried, (elapsed - DEEP_THRUST_START) / (HIT_SECONDS - DEEP_THRUST_START))
	if elapsed < WITHDRAW_START: return buried
	if elapsed < WITHDRAW_END: return POSE.mix(buried, withdrawn, (elapsed - WITHDRAW_START) / (WITHDRAW_END - WITHDRAW_START))
	return POSE.mix(withdrawn, POSE.ready(), (elapsed - WITHDRAW_END) / (DURATION - WITHDRAW_END))

static func shield(elapsed: float, entry: Transform3D) -> Transform3D:
	var lowered := entry.translated(Vector3(-.10, -.18, .04))
	if elapsed < PREPARE_END: return POSE.mix(entry, lowered, elapsed / PREPARE_END)
	if elapsed < WITHDRAW_END: return lowered
	return POSE.mix(lowered, entry, (elapsed - WITHDRAW_END) / (DURATION - WITHDRAW_END))

static func camera_offset(elapsed: float) -> Vector3:
	var weight := smoothstep(0, PREPARE_END, elapsed) * (1.0 - smoothstep(WITHDRAW_END, DURATION, elapsed))
	var push := smoothstep(DEEP_THRUST_START, HIT_SECONDS, elapsed) * (1.0 - smoothstep(WITHDRAW_START, WITHDRAW_END, elapsed))
	return Vector3(0, -.045, -.035) * weight + Vector3(0, -.025, -.020) * push

static func camera_rotation(elapsed: float) -> Vector3:
	var weight := smoothstep(0, PREPARE_END, elapsed) * (1.0 - smoothstep(WITHDRAW_END, DURATION, elapsed))
	return Vector3(-.025, 0, 0) * weight
