extends SceneTree
## Static geometric fixtures only; no authored motion, scene or hardware input.

const ARM := preload("res://scripts/reference_sword_arm.gd")
const TOLERANCE := 0.00001
var failures: Array[String] = []
var checked_poses := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reachable_hint_and_rigid_frame()
	_test_new_hint_can_change_bend_side()
	_test_reach_boundaries_and_minimal_shoulder_shift()
	_test_coincident_and_nearly_coincident_endpoints()
	_test_parallel_hint_and_previous_bend()
	_test_limit_keeps_directional_history()
	_test_finite_degenerate_fallbacks()
	_test_static_geometry_domain()
	for failure in failures:
		push_error(failure)
	print("REFERENCE SWORD ARM %s: %d fixed-length poses, wrist preservation, reachable shoulders, minimal reach correction, independent hint ownership and singular bend continuity" % ["PASS" if failures.is_empty() else "FAIL", checked_poses])
	quit(0 if failures.is_empty() else 1)


func _test_reachable_hint_and_rigid_frame() -> void:
	# Construct a known physical elbow from two independent fixed-length bones.
	# The solver must recover this pose instead of merely satisfying its own data.
	var shoulder := Vector3(0.2482, -0.1699, 0.0788)
	var expected_elbow := shoulder + Vector3(0.20, -0.12, -0.25).normalized() * ARM.UPPER_LENGTH
	var wrist := expected_elbow + Vector3(0.10, 0.04, -0.23).normalized() * ARM.FOREARM_LENGTH
	var result := ARM.solve(shoulder, expected_elbow, wrist)
	_assert_pose(result, wrist, "known reachable joint")
	_check((result.shoulder as Vector3) == shoulder and not result.reach_adjusted, "Reachable IK must leave the supplied shoulder exact")
	_check((result.elbow as Vector3).distance_to(expected_elbow) < TOLERANCE, "A physically valid elbow hint must recover its actual joint")
	_check(float(result.shoulder_adjustment_m) == 0.0, "Reachable pose must report zero shoulder movement")
	# A solver defined in camera space must respect a common rigid frame change.
	var frame := Transform3D(Basis(Vector3(0.2, 0.7, -0.3).normalized(), 1.13), Vector3(-0.31, 0.14, -0.28))
	var moved := ARM.solve(frame * shoulder, frame * expected_elbow, frame * wrist)
	_assert_pose(moved, frame * wrist, "same joint in a changed rigid frame")
	_check((moved.elbow as Vector3).distance_to(frame * expected_elbow) < TOLERANCE, "Regular IK must be equivariant under camera-space rotation and translation")
	_check((moved.bend as Vector3).dot(frame.basis * (result.bend as Vector3)) > 0.99999, "A regular elbow bend must rotate with the physical pose")


func _test_new_hint_can_change_bend_side() -> void:
	var shoulder := Vector3.ZERO
	var wrist := Vector3(0, 0, -0.4)
	for side: float in [-1.0, 1.0]:
		var wanted := Vector3.UP * side
		var result := ARM.solve(shoulder, Vector3(0, side * 0.2, -0.17), wrist, -wanted)
		_assert_pose(result, wrist, "new valid hint overrides old side %.0f" % side)
		_check((result.bend as Vector3).dot(wanted) > 0.99999, "History must not prevent a new authored elbow hint crossing from below to above")
		_check(signf((result.elbow as Vector3).y) == side, "The actual elbow must follow the new side, not just report a changed bend")


func _test_reach_boundaries_and_minimal_shoulder_shift() -> void:
	for reach: float in [ARM.MIN_REACH, ARM.MIN_REACH + 0.0001, ARM.MAX_REACH - 0.0001, ARM.MAX_REACH]:
		var wrist := Vector3(0, 0, -reach)
		var result := ARM.solve(Vector3.ZERO, Vector3(0.1, -0.2, -0.2), wrist, Vector3.DOWN)
		_assert_pose(result, wrist, "reach boundary %.9f" % reach)
		_check((result.shoulder as Vector3).length() < 0.000001, "Boundary and interior reaches must not introduce visible shoulder movement")
	for reach: float in [0.025, ARM.MIN_REACH - 0.0001, ARM.MAX_REACH + 0.0001, 0.9, 1.4]:
		var shoulder := Vector3(0.21, -0.19, 0.08)
		var direction := Vector3(0.2, -0.15, -0.8).normalized()
		var wrist := shoulder + direction * reach
		var result := ARM.solve(shoulder, shoulder + Vector3(0.2, -0.3, -0.2), wrist, Vector3.DOWN)
		_assert_pose(result, wrist, "unreachable distance %.9f" % reach)
		var expected_shift := ARM.MIN_REACH - reach if reach < ARM.MIN_REACH else reach - ARM.MAX_REACH
		_check(result.reach_adjusted, "An unreachable wrist must report a reach correction")
		_check(absf(float(result.shoulder_adjustment_m) - expected_shift) < TOLERANCE, "Shoulder correction must attain the distance lower bound, not take an arbitrary detour")
		var adjustment: Vector3 = result.shoulder - shoulder
		_check(adjustment.cross(direction).length() < TOLERANCE, "Minimal shoulder correction must lie on the original shoulder–wrist axis")
		_check(absf(adjustment.length() - float(result.shoulder_adjustment_m)) < TOLERANCE, "Reported shoulder movement must equal actual displacement")


func _test_coincident_and_nearly_coincident_endpoints() -> void:
	var wrist := Vector3(0.19, -0.11, -0.42)
	for hint_offset: Vector3 in [Vector3.ZERO, Vector3(0.2, 0.1, 0.0)]:
		for previous: Vector3 in [Vector3.ZERO, Vector3.DOWN]:
			var result := ARM.solve(wrist, wrist + hint_offset, wrist, previous)
			_assert_pose(result, wrist, "coincident endpoints")
			_check(result.reach_adjusted and absf(float(result.shoulder_adjustment_m) - ARM.MIN_REACH) < TOLERANCE, "Coincident endpoints need exactly the minimum reach in shoulder movement")
	# A nonzero tiny offset still defines the uniquely minimal movement axis.
	# Treating every near-zero offset as coincident would choose the wrong axis.
	var tiny_wrist := Vector3(0.00000001, 0, 0)
	var tiny := ARM.solve(Vector3.ZERO, Vector3(0, 0.3, 0), tiny_wrist)
	_assert_pose(tiny, tiny_wrist, "nonzero 10nm endpoint offset")
	_check((tiny.shoulder as Vector3).x < -0.079 and absf((tiny.shoulder as Vector3).y) < TOLERANCE and absf((tiny.shoulder as Vector3).z) < TOLERANCE, "A small nonzero endpoint direction must retain the minimal correction axis")


func _test_parallel_hint_and_previous_bend() -> void:
	var shoulder := Vector3(0.24, -0.17, 0.08)
	var axis := Vector3(0.15, 0.05, -0.6).normalized()
	var wrist := shoulder + axis * 0.42
	var previous := Vector3(0.2, -1.0, 0.7).normalized()
	var expected := (previous - axis * previous.dot(axis)).normalized()
	for offset: Vector3 in [Vector3.ZERO, axis * 0.2, axis * 0.2 + expected * 0.000001]:
		var result := ARM.solve(shoulder, shoulder + offset, wrist, previous)
		_assert_pose(result, wrist, "parallel or nearly parallel hint")
		_check((result.bend as Vector3).dot(expected) > 0.99999, "Degenerate hint must retain previous bend projected onto the new axis")
	var no_plane := ARM.solve(shoulder, shoulder + axis * 0.2, wrist, axis)
	_assert_pose(no_plane, wrist, "both hint and previous bend parallel to reach")
	# Successive changed axes must transport history without an arbitrary flip
	# when all elbow hints remain parallel. These are geometric stability samples.
	var retained := Vector3.DOWN
	for index in 61:
		var moving_axis := Vector3(sin(float(index) * 0.003), 0.03, -1.0).normalized()
		var result := ARM.solve(shoulder, shoulder + moving_axis * 0.2, shoulder + moving_axis * 0.43, retained)
		_assert_pose(result, shoulder + moving_axis * 0.43, "parallel-hint plane transport %d" % index)
		_check((result.bend as Vector3).dot(retained) > 0.999, "Parallel-hint fallback must not flip as the wrist axis changes")
		retained = result.bend


func _test_limit_keeps_directional_history() -> void:
	for reach: float in [ARM.MIN_REACH, ARM.MAX_REACH, ARM.MAX_REACH + 0.04]:
		var wrist := Vector3(0, 0, -reach)
		var result := ARM.solve(Vector3.ZERO, Vector3(0, 0.2, -0.2), wrist, Vector3.DOWN)
		_assert_pose(result, wrist, "collapsed circle at %.9f" % reach)
		_check((result.bend as Vector3).dot(Vector3.DOWN) > 0.99999, "At a collapsed elbow circle, keep history for the next bent frame")
	var bent := ARM.solve(Vector3.ZERO, Vector3(0, 0.2, -0.2), Vector3(0, 0, -0.55), Vector3.DOWN)
	_assert_pose(bent, Vector3(0, 0, -0.55), "valid bend after full extension")
	_check((bent.bend as Vector3).dot(Vector3.UP) > 0.99999, "Leaving a singular reach must let a valid new hint take ownership again")


func _test_finite_degenerate_fallbacks() -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var wrist := axis * 0.4
		var result := ARM.solve(Vector3.ZERO, axis * 0.2, wrist)
		_assert_pose(result, wrist, "no-history principal-axis fallback")
	var wrist := Vector3(0.1, -0.1, -0.4)
	var bad_hint := ARM.solve(Vector3.ZERO, Vector3(NAN, 0, 0), wrist, Vector3(INF, 0, 0))
	_assert_pose(bad_hint, wrist, "invalid directional hints")
	var invalid_positions := ARM.solve(Vector3(NAN, 0, 0), Vector3(NAN, 0, 0), Vector3(INF, 0, 0))
	_assert_pose(invalid_positions, Vector3.ZERO, "finite fallback for invalid endpoint input")


func _test_static_geometry_domain() -> void:
	var shoulder := Vector3(0.2482, -0.1699, 0.0788)
	for axis: Vector3 in [Vector3(0.1, 0.2, -1).normalized(), Vector3(-0.6, -0.8, 0.1).normalized(), Vector3(0.9, -0.2, 0.3).normalized()]:
		for radius: float in [0.081, 0.12, 0.3, 0.5, 0.599]:
			for hint: Vector3 in [Vector3(0.2, 0.15, -0.3), Vector3(-0.3, -0.2, 0.1), Vector3(0.04, -0.3, -0.2)]:
				var wrist := shoulder + axis * radius
				var result := ARM.solve(shoulder, shoulder + hint, wrist)
				_assert_pose(result, wrist, "reachable static domain")
				_check((result.shoulder as Vector3) == shoulder and not result.reach_adjusted, "Reachable static-domain cases must not move the shoulder")


func _assert_pose(result: Dictionary, expected_wrist: Vector3, context: String) -> void:
	checked_poses += 1
	for key: String in ["shoulder", "elbow", "wrist", "bend"]:
		_check(result.has(key) and result[key] is Vector3 and (result[key] as Vector3).is_finite(), "Finite vector result required for %s: %s" % [key, context])
	var shoulder: Vector3 = result.shoulder
	var elbow: Vector3 = result.elbow
	var wrist: Vector3 = result.wrist
	var bend: Vector3 = result.bend
	_check(wrist == expected_wrist, "Wrist must remain bit-for-bit unchanged: " + context)
	_check(absf(shoulder.distance_to(elbow) - ARM.UPPER_LENGTH) < TOLERANCE, "Upper arm must keep its original length: " + context)
	_check(absf(elbow.distance_to(wrist) - ARM.FOREARM_LENGTH) < TOLERANCE, "Forearm must keep its original length: " + context)
	_check(absf(bend.length() - 1.0) < TOLERANCE and absf(bend.dot((wrist - shoulder).normalized())) < TOLERANCE, "Returned bend must be a unit direction perpendicular to reach: " + context)
	_check(is_finite(float(result.shoulder_adjustment_m)) and float(result.shoulder_adjustment_m) >= 0.0, "Shoulder movement must be finite and nonnegative: " + context)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
