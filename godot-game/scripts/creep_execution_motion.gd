extends RefCounted
## Move through preparation directly into the stab; no held pre-thrust delay.
## The shared gameplay clock commits death only at the end of the deeper push.
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const PREPARE_END := 0.30
const THRUST_START := PREPARE_END
const INITIAL_CONTACT := 0.58
const DEEP_THRUST_START := 0.68
const HIT_SECONDS := 1.02
const WITHDRAW_START := 1.46
const WITHDRAW_END := 1.86
const DURATION := 2.24
const SHALLOW_PENETRATION := 0.045
const PENETRATION_RATIO := 0.55
const FIRST_IMPACT_SECONDS := THRUST_START + (INITIAL_CONTACT - THRUST_START) * .28 / (.28 + SHALLOW_PENETRATION)
const MIN_DISTANCE := 1.10
const MAX_DISTANCE := 1.65
const CONTACT_DISTANCE := 0.84

static func phase(elapsed: float) -> String:
	if elapsed < THRUST_START: return "포복 처형 · 찌를 자세 잡기"
	if elapsed < INITIAL_CONTACT: return "포복 처형 · 첫 찌르기"
	if elapsed < DEEP_THRUST_START: return "포복 처형 · 힘 싣기"
	if elapsed < HIT_SECONDS: return "포복 처형 · 깊게 밀어 넣기"
	if elapsed < WITHDRAW_START: return "포복 처형 · 깊게 찌른 채 유지"
	return "포복 처형 · 검 뽑기"

static func sword(elapsed: float, entry: Transform3D, contact: Vector3, direction: Vector3, blade_tip: Vector3, penetration: float) -> Transform3D:
	var frame := POSE.held(Vector3.ZERO, direction, -12.0)
	frame.origin = contact - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.28)
	var shallow := frame.translated(direction * SHALLOW_PENETRATION)
	# The player measures the equipped blade mesh, so half-burial does not
	# depend on an assumed sword length or on the decorative tip marker.
	var buried := frame.translated(direction * penetration)
	var withdrawn := frame.translated(direction * -.34)
	if elapsed < PREPARE_END: return POSE.mix(entry, chamber, elapsed / PREPARE_END)
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
	# Follow the hands with a forward body lean instead of stretching the arm.
	return Vector3(0, -.045, -.035) * weight + Vector3(0, -.105, -.235) * push

static func camera_rotation(elapsed: float) -> Vector3:
	var weight := smoothstep(0, PREPARE_END, elapsed) * (1.0 - smoothstep(WITHDRAW_END, DURATION, elapsed))
	return Vector3(-.025, 0, 0) * weight
