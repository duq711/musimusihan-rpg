extends RefCounted
## One shared clock: reserve an unaware target, stab, extract, then cut the neck.
## Contact coordinates are sampled from the actual posed target in world space.
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const ARM := preload("res://scripts/reference_sword_arm.gd")
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

static func sword(elapsed: float, entry: Transform3D, back: Vector3, direction: Vector3, neck: Vector3, blade_tip: Vector3, blade_length: float, stab_basis: Basis) -> Transform3D:
	# Keep the real blade orientation fixed in world space while it is embedded.
	var frame := Transform3D(stab_basis, Vector3.ZERO)
	frame.origin = back - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.20)
	var deep := frame.translated(direction * (blade_length * PENETRATION_RATIO))
	var withdrawn := frame.translated(direction * -.05)
	var windup := _natural_roll(POSE.held(Vector3(.43, -.10, -.16), Vector3(.30, .30, .90), 24.0), POSE.SWORD_GRIP)
	var cut := cut_pose(neck, blade_tip, blade_length)
	var follow := _natural_roll(POSE.held(Vector3(.04, -.24, -.32), Vector3(-.88, -.18, .32), 24.0), POSE.SWORD_GRIP)
	if elapsed < PREPARE_END:
		var t := elapsed / PREPARE_END
		return POSE.mix(entry, chamber, t).translated(Vector3(0, -.15, 0) * pow(sin(PI * t), 2))
	if elapsed < STAB_HIT: return POSE.mix(chamber, deep, (elapsed - PREPARE_END) / (STAB_HIT - PREPARE_END))
	if elapsed < HOLD_END: return deep
	if elapsed < WITHDRAW_END: return POSE.mix(deep, withdrawn, (elapsed - HOLD_END) / (WITHDRAW_END - HOLD_END))
	if elapsed < CUT_START:
		var t := (elapsed - WITHDRAW_END) / (CUT_START - WITHDRAW_END)
		var turning := POSE.mix(withdrawn, windup, t)
		# Turn below the shoulder with a shallow forward arc. Delay the forward
		# component until the extracted tip has turned clear of the entry surface.
		var arc := Vector3(0, -.10, -.20 * smoothstep(.10, .35, t))
		return turning.translated(arc * pow(sin(PI * t), 2))
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
	return _natural_roll(result, blade_tip - Vector3.UP * blade_length * CUT_EDGE_FROM_TIP)

static func shield(elapsed: float, entry: Transform3D) -> Transform3D:
	var lowered := entry.translated(Vector3(-.12, -.30, .08))
	if elapsed < PREPARE_END: return POSE.mix(entry, lowered, elapsed / PREPARE_END)
	if elapsed < CUT_END: return lowered
	return POSE.mix(lowered, entry, (elapsed - CUT_END) / (DURATION - CUT_END))

static func camera_offset(elapsed: float) -> Vector3:
	var lean := smoothstep(PREPARE_END, STAB_HIT, elapsed) * (1.0 - smoothstep(HOLD_END, WITHDRAW_END, elapsed))
	return Vector3(0, -.025, -.10) * lean


static func arm(pivot: Transform3D, elapsed: float, entry_arm: Dictionary, previous_bend := Vector3.ZERO) -> Dictionary:
	var shoulder: Vector3 = GRIP.SOURCE_READY * GRIP.REST_SHOULDER
	if not entry_arm.is_empty():
		if elapsed < PREPARE_END: shoulder = (entry_arm.shoulder as Vector3).lerp(shoulder, smoothstep(0, PREPARE_END, elapsed))
		elif elapsed > CUT_END: shoulder = shoulder.lerp(entry_arm.shoulder, smoothstep(CUT_END, DURATION, elapsed))
	var wrist := pivot * GRIP.REST_WRIST
	# The hand is rigidly holding the hilt. Its authored neutral forearm axis,
	# not a generic down/right pole, defines the closest reachable elbow circle.
	var neutral := (pivot.basis * (GRIP.REST_ELBOW - GRIP.REST_WRIST)).normalized()
	var hint := wrist + neutral * ARM.FOREARM_LENGTH

	if elapsed < PREPARE_END and not entry_arm.is_empty():
		hint = (entry_arm.elbow as Vector3).lerp(hint, smoothstep(0, PREPARE_END, elapsed))
	if elapsed > CUT_END:
		var ready := ARM.solve(shoulder, shoulder + Vector3(.75, -.72, .28), wrist, previous_bend)
		hint = hint.lerp(ready.elbow, smoothstep(CUT_END, DURATION, elapsed))
	var result := ARM.solve(shoulder, hint, wrist, previous_bend)
	result.merge({"raw_sword": pivot, "requested_shoulder": shoulder, "exact_sample": false, "fitted_pose": true})
	return result


static func _rolled(pose: Transform3D, anchor: Vector3, angle: float) -> Transform3D:
	var basis := Basis(pose.basis.y.normalized(), angle) * pose.basis
	return Transform3D(basis, pose * anchor - basis * anchor)


static func _roll_cost(pose: Transform3D) -> float:
	var shoulder: Vector3 = GRIP.SOURCE_READY * GRIP.REST_SHOULDER
	var wrist := pose * GRIP.REST_WRIST
	var neutral := (pose.basis * (GRIP.REST_ELBOW - GRIP.REST_WRIST)).normalized()
	var fitted := ARM.solve(shoulder, wrist + neutral * ARM.FOREARM_LENGTH, wrist)
	var discrepancy := neutral.angle_to((fitted.elbow - wrist).normalized())
	# Prefer a relaxed right elbow below the shoulder, without changing lengths
	# or moving the hand away from its measured weapon contact.
	return discrepancy * discrepancy + pow(float(fitted.shoulder_adjustment_m) * 60.0, 2) + pow(maxf(0, fitted.elbow.y - shoulder.y) * 3.0, 2) + pow(maxf(0, shoulder.x - fitted.elbow.x) * 2.0, 2)


static func _natural_roll(pose: Transform3D, anchor: Vector3) -> Transform3D:
	var best := 0.0
	var best_cost := INF
	for i in 72:
		var angle := TAU * float(i) / 72.0
		var cost := _roll_cost(_rolled(pose, anchor, angle))
		if cost < best_cost:
			best_cost = cost
			best = angle
	# Refine a continuous minimum; coarse angular steps must not show as snaps.
	var low := best - TAU / 72.0
	var high := best + TAU / 72.0
	for i in 12:
		var a := lerpf(low, high, 1.0 / 3.0)
		var b := lerpf(low, high, 2.0 / 3.0)
		if _roll_cost(_rolled(pose, anchor, a)) < _roll_cost(_rolled(pose, anchor, b)): high = b
		else: low = a
	return _rolled(pose, anchor, (low + high) * .5)


static func stab_basis(direction: Vector3) -> Basis:
	# Gravity provides a stable roll reference even when the initial camera is
	# looking directly along the blade. Initial view pitch must not twist a hand.
	var y := direction.normalized()
	var z := (Vector3.UP - y * y.dot(Vector3.UP)).normalized().rotated(y, deg_to_rad(84.0))
	return Basis(y.cross(z).normalized(), y, z)
