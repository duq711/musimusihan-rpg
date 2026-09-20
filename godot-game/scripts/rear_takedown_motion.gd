extends RefCounted
## One shared clock: reserve an unaware target, stab, extract, then cut the neck.
## Contact coordinates are sampled from the actual posed target in world space.
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const PREPARE_END := 0.28
const STAB_HIT := 0.62
const HOLD_END := 1.03
const WITHDRAW_END := 1.42
const CUT_START := 1.72
const CUT_HIT := 1.98
const CUT_END := 2.23
const DURATION := 2.70
const PENETRATION_RATIO := 0.55
const STAMINA_COST := 24.0
const MIN_DISTANCE := 0.85
const MAX_DISTANCE := 1.50
const CUT_DISTANCE := .82
const STAB_DISTANCE := 1.15
const CUT_EDGE_FROM_TIP := .10

static func weapon_profile(definition: Dictionary) -> String:
	# Unsupported weapons must never silently reuse a sword execution.
	return str(definition.get("rear_takedown_profile", ""))

static func phase(elapsed: float) -> String:
	if elapsed < PREPARE_END: return "후방 제압 · 검 겨누기"
	if elapsed < STAB_HIT: return "후방 제압 · 깊게 찌르기"
	if elapsed < HOLD_END: return "후방 제압 · 제압 유지"
	if elapsed < WITHDRAW_END: return "후방 제압 · 검 뽑기"
	if elapsed < CUT_START: return "후방 제압 · 크게 휘두를 준비"
	if elapsed < CUT_END: return "후방 제압 · 목 베기"
	return "후방 제압 · 자세 회복"

static func sword(elapsed: float, entry: Transform3D, back: Vector3, direction: Vector3, neck: Vector3, blade_tip: Vector3, blade_length: float) -> Transform3D:
	var frame := POSE.held(Vector3.ZERO, direction, -12.0)
	frame.origin = back - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.20)
	var deep := frame.translated(direction * (blade_length * PENETRATION_RATIO))
	var withdrawn := frame.translated(direction * -.25)
	var windup := POSE.held(Vector3(.48, .02, -.18), Vector3(.30, .30, .90), 24.0)
	var cut := cut_pose(neck, blade_tip, blade_length)
	var follow := POSE.held(Vector3(-.10, -.14, -.32), Vector3(-.88, -.18, .32), 24.0)
	if elapsed < PREPARE_END: return POSE.mix(entry, chamber, elapsed / PREPARE_END)
	if elapsed < STAB_HIT: return POSE.mix(chamber, deep, (elapsed - PREPARE_END) / (STAB_HIT - PREPARE_END))
	if elapsed < HOLD_END: return deep
	if elapsed < WITHDRAW_END: return POSE.mix(deep, withdrawn, (elapsed - HOLD_END) / (WITHDRAW_END - HOLD_END))
	if elapsed < CUT_START: return POSE.mix(withdrawn, windup, (elapsed - WITHDRAW_END) / (CUT_START - WITHDRAW_END))
	if elapsed < CUT_HIT: return windup.interpolate_with(cut, (elapsed - CUT_START) / (CUT_HIT - CUT_START))
	if elapsed < CUT_END: return cut.interpolate_with(follow, (elapsed - CUT_HIT) / (CUT_END - CUT_HIT))
	return POSE.mix(follow, POSE.ready(), (elapsed - CUT_END) / (DURATION - CUT_END))

static func cut_pose(neck: Vector3, blade_tip: Vector3, blade_length: float) -> Transform3D:
	# Aim the forward cutting edge from a reachable right-hand position. The
	# coordinator takes a collision-tested step during extraction, so the hand
	# and its fixed-length arm do not have to teleport out to the victim's neck.
	var direction := (neck - Vector3(.44, -.02, -.35)).normalized()
	var result := POSE.held(Vector3.ZERO, direction, 24.0)
	result.origin = neck - result.basis * (blade_tip - Vector3.UP * blade_length * CUT_EDGE_FROM_TIP)
	return result

static func shield(elapsed: float, entry: Transform3D) -> Transform3D:
	var lowered := entry.translated(Vector3(-.12, -.30, .08))
	if elapsed < PREPARE_END: return POSE.mix(entry, lowered, elapsed / PREPARE_END)
	if elapsed < CUT_END: return lowered
	return POSE.mix(lowered, entry, (elapsed - CUT_END) / (DURATION - CUT_END))

static func camera_offset(elapsed: float) -> Vector3:
	var lean := smoothstep(PREPARE_END, STAB_HIT, elapsed) * (1.0 - smoothstep(HOLD_END, WITHDRAW_END, elapsed))
	return Vector3(0, -.025, -.10) * lean
