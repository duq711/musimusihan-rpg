extends RefCounted
## One shared clock: reserve an unaware target, stab through, twist once, then slice out to the right.
## Contact coordinates are sampled from the actual posed target in world space.
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const ARM := preload("res://scripts/reference_sword_arm.gd")
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const PREPARE_END := 0.28
const STAB_HIT := 0.68
const TWIST_START := 0.80
const TWIST_END := 1.12
const TWIST_DEGREES := -45.0
const HOLD_END := 1.22
const WITHDRAW_END := 1.98
const CUT_START := HOLD_END
const CUT_HIT := 1.48
const CUT_END := 2.10
const DURATION := 2.62
const PENETRATION_RATIO := 0.94
const STAMINA_COST := 24.0
const MIN_DISTANCE := 0.85
const MAX_DISTANCE := 1.50
const CUT_DISTANCE := .78
const STAB_DISTANCE := 1.15
const CUT_EDGE_FROM_TIP := .10

static func weapon_profile(definition: Dictionary) -> String:
	# Unsupported weapons must never silently reuse a sword execution.
	return str(definition.get("rear_takedown_profile", ""))

static func phase(elapsed: float) -> String:
	if elapsed < PREPARE_END: return "후방 제압 · 검 겨누기"
	if elapsed < STAB_HIT: return "후방 제압 · 깊게 찌르기"
	if elapsed < TWIST_START: return "후방 제압 · 깊게 관통"
	if elapsed < TWIST_END: return "후방 제압 · 검 비틀기"
	if elapsed < HOLD_END: return "후방 제압 · 비튼 검 유지"
	if elapsed < WITHDRAW_END: return "후방 제압 · 우측으로 베어 빼기"
	if elapsed < CUT_END: return "후방 제압 · 검 회수"
	return "후방 제압 · 자세 회복"

static func sword(elapsed: float, entry: Transform3D, back: Vector3, direction: Vector3, _neck: Vector3, blade_tip: Vector3, blade_length: float, stab_basis: Basis) -> Transform3D:
	# Keep the thrust axis fixed in world space, then intentionally roll once.
	var frame := Transform3D(stab_basis, Vector3.ZERO)
	frame.origin = back - frame.basis * blade_tip
	var chamber := frame.translated(direction * -.20)
	var deep := frame.translated(direction * (blade_length * PENETRATION_RATIO))
	if elapsed < PREPARE_END:
		var t := elapsed / PREPARE_END
		# Carry the hilt through a compact preparation arc. Anchoring a rotating
		# metre-long sword at its tip would pull the gripping arm out of reach.
		# Pass below the shoulder so the wrist does not cross the IK minimum
		# reach sphere and snap the elbow while the blade turns into line.
		return POSE.mix(entry, chamber, t).translated((Vector3(0, -.30, 0) - direction * .10) * pow(sin(PI * t), 2))
	if elapsed < STAB_HIT: return POSE.mix(chamber, deep, (elapsed - PREPARE_END) / (STAB_HIT - PREPARE_END))
	var twisted := _rolled(deep, blade_tip, deg_to_rad(TWIST_DEGREES))
	if elapsed < TWIST_START: return deep
	if elapsed < TWIST_END: return _rolled(deep, blade_tip, deg_to_rad(TWIST_DEGREES) * smoothstep(TWIST_START, TWIST_END, elapsed))
	if elapsed < HOLD_END: return twisted
	if elapsed < WITHDRAW_END:
		return lateral_exit(twisted, blade_tip, blade_length, (elapsed - HOLD_END) / (WITHDRAW_END - HOLD_END))
	var exited := lateral_exit(twisted, blade_tip, blade_length, 1.0)
	if elapsed < CUT_END: return exited
	return POSE.mix(exited, POSE.ready(), (elapsed - CUT_END) / (DURATION - CUT_END))

static func lateral_exit(deep: Transform3D, _blade_tip: Vector3, _blade_length: float, progress: float) -> Transform3D:
	# One continuous diagonal extraction. The grip travels right/back while the
	# blade opens right around the hand: no separate neck-height windup or strike.
	var t := smoothstep(0.0, 1.0, progress)
	var grip := deep * POSE.SWORD_GRIP
	var end_basis := Basis(Vector3.UP, deg_to_rad(-80.0)) * deep.basis
	var end_grip := grip + Vector3(.28, -.10, .26)
	var end_pose := _natural_roll(Transform3D(end_basis, end_grip - end_basis * POSE.SWORD_GRIP), POSE.SWORD_GRIP)
	var basis := Basis(deep.basis.get_rotation_quaternion().slerp(end_pose.basis.get_rotation_quaternion(), t))
	return Transform3D(basis, grip.lerp(end_grip, t) - basis * POSE.SWORD_GRIP)



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
		# Lead the preparation elbow out to the right instead of letting its
		# hint cross the shoulder–wrist axis and flip the bend direction.
		hint += Vector3.RIGHT * .30 * pow(sin(PI * elapsed / PREPARE_END), 2)

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
	var z := (Vector3.UP - y * y.dot(Vector3.UP)).normalized().rotated(y, deg_to_rad(130.0))
	return Basis(y.cross(z).normalized(), y, z)
