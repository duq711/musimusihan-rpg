extends RefCounted
class_name ReferenceSwordArm
## Fixed-length camera-space IK for interpolation, transitions and overlays.
## Authored keys bypass this helper. A usable elbow hint owns the bend direction.

const UPPER_LENGTH := 0.34000002959
const FOREARM_LENGTH := 0.26000002263
const MIN_REACH := UPPER_LENGTH - FOREARM_LENGTH
const MAX_REACH := UPPER_LENGTH + FOREARM_LENGTH
const DIRECTION_EPS := 0.000001
const HINT_EPS := 0.00001
const LIMIT_EPS := 0.000001


static func solve(shoulder: Vector3, elbow_hint: Vector3, wrist: Vector3, previous_bend: Vector3 = Vector3.ZERO) -> Dictionary:
	# Source validation normally excludes nonfinite positions. Keep this utility's
	# degenerate-input fallback finite without letting a bad hint poison a pose.
	if not wrist.is_finite():
		wrist = Vector3.ZERO
	if not shoulder.is_finite():
		shoulder = wrist
	if not elbow_hint.is_finite():
		elbow_hint = wrist
	if not previous_bend.is_finite():
		previous_bend = Vector3.ZERO
	var original_shoulder := shoulder
	var offset := wrist - shoulder
	var distance := offset.length()
	var axis: Vector3
	if distance > 0.0:
		axis = offset / distance
	else:
		axis = _coincident_axis(elbow_hint - wrist, previous_bend)
	var reach := clampf(distance, MIN_REACH, MAX_REACH)
	var reach_adjusted := distance < MIN_REACH or distance > MAX_REACH
	if reach_adjusted:
		# Closest point to the original shoulder on the wrist-centred reachable
		# shell. The hand stays exact; moving either end tangentially costs more.
		shoulder = wrist - axis * reach
	var at_limit := reach - MIN_REACH <= LIMIT_EPS or MAX_REACH - reach <= LIMIT_EPS
	var bend := _choose_bend(axis, elbow_hint - shoulder, previous_bend, at_limit)
	var along := (UPPER_LENGTH * UPPER_LENGTH - FOREARM_LENGTH * FOREARM_LENGTH + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0, UPPER_LENGTH * UPPER_LENGTH - along * along))
	var elbow := shoulder + axis * along + bend * height
	return {
		"shoulder": shoulder,
		"elbow": elbow,
		"wrist": wrist,
		"bend": bend,
		"shoulder_adjustment_m": shoulder.distance_to(original_shoulder),
		"reach_adjusted": reach_adjusted,
	}


static func _choose_bend(axis: Vector3, hint: Vector3, previous: Vector3, at_limit: bool) -> Vector3:
	var hinted := hint - axis * hint.dot(axis)
	var retained := previous - axis * previous.dot(axis)
	# Real hints can intentionally cross from below to above the sword. Do not
	# force their hemisphere to the old pose when the elbow circle is defined.
	if not at_limit and hinted.length() > HINT_EPS:
		return hinted.normalized()
	# At a collapsed circle or parallel hint the old bend is the only useful
	# directional history; project it onto the new axis instead of keeping skew.
	if retained.length() > DIRECTION_EPS:
		return retained.normalized()
	if hinted.length() > HINT_EPS:
		return hinted.normalized()
	return _perpendicular(axis)


static func _coincident_axis(hint: Vector3, previous: Vector3) -> Vector3:
	# With coincident endpoints every direction gives the same minimal shoulder
	# shift. Prefer the hint's axis while retaining a useful previous bend plane.
	if hint.length() > DIRECTION_EPS:
		return hint.normalized()
	if previous.length() > DIRECTION_EPS:
		var retained := previous.normalized()
		var forward := Vector3.FORWARD - retained * Vector3.FORWARD.dot(retained)
		return forward.normalized() if forward.length() > DIRECTION_EPS else _perpendicular(retained)
	return Vector3.FORWARD


static func _perpendicular(axis: Vector3) -> Vector3:
	# Choose the least parallel coordinate axis; never normalize a zero cross.
	var guide := Vector3.RIGHT
	if absf(axis.y) < absf(axis.x):
		guide = Vector3.UP
	if absf(axis.z) < absf(axis.dot(guide)):
		guide = Vector3.BACK
	return (guide - axis * guide.dot(axis)).normalized()
