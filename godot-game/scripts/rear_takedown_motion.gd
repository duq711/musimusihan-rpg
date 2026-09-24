extends RefCounted
## One shared clock: reserve an unaware target, stab, briefly twist, then withdraw along the same axis.
## Contact coordinates are sampled from the actual posed target in world space.
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const ARM := preload("res://scripts/reference_sword_arm.gd")
const POSE := preload("res://scripts/sword_shield_choreography.gd")
const PREPARE_END := 0.55
const STAB_CONTACT := 0.61
const STAB_HIT := 0.90
const TWIST_START := 1.00
const TWIST_END := 1.22
const TWIST_RADIANS := deg_to_rad(20.0)
const HOLD_END := 1.30
const WITHDRAW_END := 1.90
const RECOVER_START := 1.96
const DURATION := 2.46
const WITHDRAW_CLEARANCE := .06
const PENETRATION_RATIO := 0.94
const STAMINA_COST := 24.0
const MIN_DISTANCE := 0.85
const MAX_DISTANCE := 1.50
const PREPARE_STANCE := Vector3(-.10, 0, 1.35)
const CLOSE_STANCE := Vector3(-.57, 0, .63)
const CONTACT_DISTANCE := .849588
const STAB_DISTANCE := 1.353699

static func grip_blend(elapsed: float) -> float:
	# Set the diagonal thrust grip before extending the arm; restore the
	# ordinary cutting grip only after the blade has left the body.
	return smoothstep(0.0, PREPARE_END, elapsed) * (1.0 - smoothstep(RECOVER_START, DURATION, elapsed))

static func wrist_local(elapsed: float) -> Vector3:
	# The ordinary adapter still uses the authored legacy landmark. Blend its
	# 2.5cm offset only during handoff, and solve the true wrist during thrust.
	return GRIP.REST_WRIST.lerp(GRIP.wrist_local(grip_blend(elapsed)), grip_blend(elapsed))

static func weapon_profile(definition: Dictionary) -> String:
	# Unsupported weapons must never silently reuse a sword execution.
	return str(definition.get("rear_takedown_profile", ""))

static func phase(elapsed: float) -> String:
	if elapsed < PREPARE_END: return "후방 제압 · 검 겨누기"
	if elapsed < STAB_HIT: return "후방 제압 · 깊게 찌르기"
	if elapsed < TWIST_START: return "후방 제압 · 찌른 검 유지"
	if elapsed < HOLD_END: return "후방 제압 · 짧게 비틀기"
	if elapsed < WITHDRAW_END: return "후방 제압 · 곧게 뽑기"
	return "후방 제압 · 자세 회복"

static func sword(elapsed: float, entry: Transform3D, back: Vector3, direction: Vector3, _neck: Vector3, blade_tip: Vector3, blade_length: float, stab_basis: Basis) -> Transform3D:
	# Keep the same wound channel. Only a brief axial roll follows the stab.
	var frame := Transform3D(stab_basis, Vector3.ZERO)
	frame.origin = back - frame.basis * blade_tip
	# Derive the preparation gap from the same continuous cubic stroke, so
	# the blade first crosses the skin at STAB_CONTACT for every blade length.
	# There is no extra key or artificial stop at the contact point.
	var contact_weight := smoothstep(PREPARE_END, STAB_HIT, STAB_CONTACT)
	var chamber_gap := blade_length * PENETRATION_RATIO * contact_weight / (1.0 - contact_weight)
	var chamber := frame.translated(direction * -chamber_gap)
	var deep := frame.translated(direction * (blade_length * PENETRATION_RATIO))
	if elapsed < PREPARE_END:
		var t := elapsed / PREPARE_END
		# Carry the hilt through a compact preparation arc. Anchoring a rotating
		# metre-long sword at its tip would pull the gripping arm out of reach.
		# Pass below the shoulder so the wrist does not cross the IK minimum
		# reach sphere and snap the elbow while the blade turns into line.
		return POSE.mix(entry, chamber, t).translated((Vector3(0, -.30, 0) - direction * .10) * pow(sin(PI * t), 2))
	if elapsed < STAB_HIT: return POSE.mix(chamber, deep, (elapsed - PREPARE_END) / (STAB_HIT - PREPARE_END))
	deep = _twist_about_blade(deep, blade_tip, smoothstep(TWIST_START, TWIST_END, elapsed))
	if elapsed < HOLD_END: return deep
	if elapsed < WITHDRAW_END:
		return axial_exit(deep, blade_length, (elapsed - HOLD_END) / (WITHDRAW_END - HOLD_END))
	var exited := axial_exit(deep, blade_length, 1.0)
	if elapsed < RECOVER_START: return exited
	return POSE.mix(exited, POSE.ready(), (elapsed - RECOVER_START) / (DURATION - RECOVER_START))

static func _twist_about_blade(deep: Transform3D, blade_tip: Vector3, weight: float) -> Transform3D:
	# Rotate around the actual blade line, not the hilt node origin. The tip
	# and wound stay fixed while the forearm rolls by a restrained 20 degrees.
	var tip := deep * blade_tip
	var rotated_basis := Basis(deep.basis.y.normalized(), TWIST_RADIANS * weight) * deep.basis
	return Transform3D(rotated_basis, tip - rotated_basis * blade_tip)

static func axial_exit(deep: Transform3D, blade_length: float, progress: float) -> Transform3D:
	# Retrace the wound channel with the completed twist held fixed.
	var distance := blade_length * PENETRATION_RATIO + WITHDRAW_CLEARANCE
	return deep.translated(-deep.basis.y.normalized() * distance * smoothstep(0.0, 1.0, progress))


static func shield(elapsed: float, entry: Transform3D) -> Transform3D:
	var lowered := entry.translated(Vector3(-.12, -.30, .08))
	if elapsed < PREPARE_END: return POSE.mix(entry, lowered, elapsed / PREPARE_END)
	if elapsed < RECOVER_START: return lowered
	return POSE.mix(lowered, entry, (elapsed - RECOVER_START) / (DURATION - RECOVER_START))

static func stance_offset(elapsed: float, initial: Vector3) -> Vector3:
	# Sweep around the rear shoulder rather than backing down the centreline.
	# Retraction returns along the same tested route while the blade comes out.
	var prepared := _arc_stance(initial, PREPARE_STANCE, smoothstep(0, PREPARE_END, elapsed))
	var close_weight := smoothstep(PREPARE_END, STAB_HIT, elapsed) * (1.0 - smoothstep(HOLD_END, WITHDRAW_END, elapsed))
	return _arc_stance(prepared, CLOSE_STANCE, close_weight)


static func _arc_stance(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var angle := lerp_angle(atan2(from.x, from.z), atan2(to.x, to.z), weight)
	var radius := lerpf(Vector2(from.x, from.z).length(), Vector2(to.x, to.z).length(), weight)
	return Vector3(sin(angle), 0, cos(angle)) * radius


static func camera_offset(elapsed: float) -> Vector3:
	var lean := smoothstep(PREPARE_END, STAB_HIT, elapsed) * (1.0 - smoothstep(HOLD_END, WITHDRAW_END, elapsed))
	return Vector3(0, -.015, -.025) * lean


static func arm(pivot: Transform3D, elapsed: float, entry_arm: Dictionary, previous_bend := Vector3.ZERO) -> Dictionary:
	var shoulder: Vector3 = GRIP.SOURCE_READY * GRIP.REST_SHOULDER
	if not entry_arm.is_empty():
		if elapsed < PREPARE_END: shoulder = (entry_arm.shoulder as Vector3).lerp(shoulder, smoothstep(0, PREPARE_END, elapsed))
		elif elapsed > RECOVER_START: shoulder = shoulder.lerp(entry_arm.shoulder, smoothstep(RECOVER_START, DURATION, elapsed))
	var amount := grip_blend(elapsed)
	var wrist := pivot * wrist_local(elapsed)
	# The hand is rigidly holding the hilt. Its authored neutral forearm axis,
	# not a generic down/right pole, defines the closest reachable elbow circle.
	var neutral := (pivot.basis * GRIP.neutral_axis_local(amount)).normalized()
	var hint := wrist + neutral * ARM.FOREARM_LENGTH
	# The blade and grip keep their thrust orientation during withdrawal.
	# Follow the same elbow circle back without a lateral-extraction pole.
	var reach_axis := (wrist - shoulder).normalized()
	var clearance := .25 * smoothstep(PREPARE_END, STAB_HIT, elapsed)
	hint = shoulder + _clearance_bend(shoulder, wrist, neutral, clearance)

	if elapsed < PREPARE_END and not entry_arm.is_empty():
		# Transport the initial elbow around the moving shoulder–wrist axis.
		# Interpolating two elbow *positions* can cross that axis and reverse
		# the IK pole, even though both endpoint poses are valid.
		var axis := (wrist - shoulder).normalized()
		var entry_axis := ((entry_arm.wrist as Vector3) - (entry_arm.shoulder as Vector3)).normalized()
		var entry_bend := (entry_arm.elbow as Vector3) - (entry_arm.shoulder as Vector3)
		entry_bend = (entry_bend - entry_axis * entry_bend.dot(entry_axis)).normalized()
		var transported := (Basis(Quaternion(entry_axis, axis)) * entry_bend).normalized()
		var desired := hint - shoulder
		desired = (desired - axis * desired.dot(axis)).normalized()
		if desired.length_squared() < .000001: desired = transported
		var angle := atan2(axis.dot(transported.cross(desired)), transported.dot(desired))
		var bend := transported.rotated(axis, angle * smoothstep(PREPARE_END * .5, PREPARE_END, elapsed))
		hint = shoulder + bend

	if elapsed > RECOVER_START:
		var ready := ARM.solve(shoulder, shoulder + Vector3(.75, -.72, .28), wrist, previous_bend)
		var current := hint - shoulder
		current = (current - reach_axis * current.dot(reach_axis)).normalized()
		var desired := (ready.elbow as Vector3) - shoulder
		desired = (desired - reach_axis * desired.dot(reach_axis)).normalized()
		var turn := atan2(reach_axis.dot(current.cross(desired)), current.dot(desired))
		hint = shoulder + current.rotated(reach_axis, turn * smoothstep(RECOVER_START, DURATION, elapsed))
	var result := ARM.solve(shoulder, hint, wrist, previous_bend)
	result.merge({"raw_sword": pivot, "requested_shoulder": shoulder, "exact_sample": false, "fitted_pose": true})
	return result


static func _clearance_bend(shoulder: Vector3, wrist: Vector3, neutral: Vector3, weight: float) -> Vector3:
	var axis := (wrist - shoulder).normalized()
	var bend := wrist + neutral * ARM.FOREARM_LENGTH - shoulder
	bend = (bend - axis * bend.dot(axis)).normalized()
	var outside := Vector3(.55, -.60, 0)
	outside = (outside - axis * outside.dot(axis)).normalized()
	var turn := atan2(axis.dot(bend.cross(outside)), bend.dot(outside))
	return bend.rotated(axis, turn * weight)


static func stab_basis(direction: Vector3) -> Basis:
	# Gravity provides a stable roll reference even when the initial camera is
	# looking directly along the blade. Initial view pitch must not twist a hand.
	var y := direction.normalized()
	var z := (Vector3.UP - y * y.dot(Vector3.UP)).normalized().rotated(y, deg_to_rad(330.0))
	return Basis(y.cross(z).normalized(), y, z)
