extends SceneTree
## Geometry and motion checks supplement the real rendered preview.
const MOTION := preload("res://scripts/jerky_eat_visuals.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)

func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var motion := MOTION.new()
	parent.add_child(motion)
	var equipment := Node3D.new()
	parent.add_child(equipment)
	equipment.transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.3, -0.3, -0.5))
	var equipment_before := equipment.transform
	motion.begin([equipment])
	_check(motion.active and motion.food_meshes.size() == 3, "original strip and two bitten states load")
	var bounds: AABB = motion.food_meshes[0].get_aabb()
	_check(bounds.size.x > 0.17 and bounds.size.x < 0.21, "uses the original full-size irregular long strip")
	for i in [1, 2]:
		var bitten: AABB = motion.food_meshes[i].get_aabb()
		_check(absf(bitten.position.x - bounds.position.x) < 0.00001, "biting preserves the gripped end")
		_check(bitten.size.x < motion.food_meshes[i - 1].get_aabb().size.x - 0.04, "each bite removes a visible section")
		_check(bitten.size.z > bounds.size.z * 0.90, "bites do not scale down the whole food")
		_check(motion.food_meshes[i].surface_get_material(0) == motion.food_meshes[0].surface_get_material(0), "bitten food keeps the supplied Substance material")
	var last_hand := Vector3.ZERO
	var last_food := Vector3.ZERO
	var last_basis := Quaternion.IDENTITY
	var ring_before := Quaternion.IDENTITY
	var ring_moves := false
	var distances := []
	for i in range(1, 480):
		motion.set_time(float(i) / 60.0)
		var hand: Node3D = motion.right_arm
		var relative: Transform3D = hand.transform.affine_inverse() * motion.food.transform
		_check(relative.is_equal_approx(motion.food_in_hand), "jerky stays attached to the hand throughout drawing and both bites")
		_check(not motion.left_arm.visible, "unused hand stays out of the eating path")
		if i > 1:
			_check(hand.position.distance_to(last_hand) < 0.050, "wrist travels continuously with no teleport")
			_check(motion.food.position.distance_to(last_food) < 0.050, "food never jumps when a bitten state changes")
			_check(hand.quaternion.angle_to(last_basis) < 0.16, "wrist turns continuously")
		last_hand = hand.position
		last_food = motion.food.position
		last_basis = hand.quaternion
		var rig: Skeleton3D = hand._active_visual.skeleton
		var ring := rig.get_bone_pose_rotation(rig.find_bone("ring1"))
		if i > 1 and ring.angle_to(ring_before) > 0.0001: ring_moves = true
		ring_before = ring
		if i == 150: _check(motion.bite_count == 0, "food remains whole before first contact")
		if i == 210: _check(motion.bite_count == 1, "first bite is visible while lowering")
		if i == 400: _check(motion.bite_count == 2, "second bite is visible after second contact")
	_check(ring_moves, "free fingers settle instead of a frozen fist")
	motion.advance(0.1)
	_check(not motion.active and not motion.visible and equipment.transform.is_equal_approx(equipment_before), "finish restores the original equipment transform")
	var contact_flow := []
	for bite_time: float in [MOTION.BITE_TIMES.x, MOTION.BITE_TIMES.y]:
		motion.begin([equipment])
		# Inspect the edible tip just before it is removed by the bite, rather
		# than requiring a held pose early in the approach.
		motion.set_time(bite_time - 0.001)
		var end: float = motion.food.mesh.get_aabb().end.x
		var endpoint: Vector3 = motion.food.transform * Vector3(end, 0.004, 0.0)
		distances.append(endpoint.distance_to(MOTION.EAT_MOUTH))
		_check(endpoint.distance_to(MOTION.EAT_MOUTH) < 0.008, "the actual edible tip reaches the lips for both bites")
		_check(endpoint.y < -0.11 and endpoint.z > -0.09, "bite stays below the nose and eye camera")
		contact_flow.append(_check_contact_flow(motion, bite_time))
		motion.clear()
	motion.begin([equipment])
	motion.set_time(5.6)
	motion.clear()
	_check(not motion.active and equipment.transform.is_equal_approx(equipment_before), "mid-bite cancellation restores equipment")
	motion.begin([equipment])
	_check(motion.bite_count == 0 and motion.food.mesh == motion.food_meshes[0], "repeating starts with a fresh whole strip")
	motion.clear()
	parent.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("JERKY MOTION TEST %s: bite-tip distances %s; contact flow %s" % ["PASS" if failures.is_empty() else "FAIL", distances, contact_flow])
	quit(0 if failures.is_empty() else 1)

func _check_contact_flow(motion: Node3D, bite_time: float) -> Dictionary:
	# A brief turnaround is natural, but a several-frame frozen wrist reads
	# as a pause. Track actual rendered transforms over both sides of contact.
	# The held end survives both bites, so mesh removal cannot fake movement.
	var held_end: Vector3 = motion.source_bounds.position
	var previous_wrist := Vector3.ZERO
	var previous_food := Vector3.ZERO
	var previous_rotation := Quaternion.IDENTITY
	var still_frames := 0
	var longest_still := 0
	var minimum_step := INF
	var maximum_step := 0.0
	var maximum_rotation := 0.0
	for sample in range(31):
		motion.set_time(bite_time - 0.25 + float(sample) / 60.0)
		var wrist: Vector3 = motion.right_arm.position
		var food_point: Vector3 = motion.food.transform * held_end
		var rotation: Quaternion = motion.right_arm.quaternion
		if sample > 0:
			var wrist_step := wrist.distance_to(previous_wrist)
			var food_step := food_point.distance_to(previous_food)
			var turn := rotation.angle_to(previous_rotation)
			var movement := maxf(wrist_step, food_step)
			minimum_step = minf(minimum_step, movement)
			maximum_step = maxf(maximum_step, movement)
			maximum_rotation = maxf(maximum_rotation, turn)
			still_frames = still_frames + 1 if movement < 0.000015 and turn < 0.0001 else 0
			longest_still = maxi(longest_still, still_frames)
		previous_wrist = wrist
		previous_food = food_point
		previous_rotation = rotation
	_check(longest_still <= 2, "each bite flows through lip contact without a frozen wrist or food plateau")
	_check(maximum_step < 0.015 and maximum_rotation < 0.075, "continuous mouth contact does not introduce a position or rotation jump")
	return {"bite": bite_time, "longest_still_frames": longest_still, "min_step_m": minimum_step, "max_step_m": maximum_step, "max_rotation_rad": maximum_rotation}
