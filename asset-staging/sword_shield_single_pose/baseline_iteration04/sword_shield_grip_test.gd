extends SceneTree
## Independent CPU skinning of the production GLB pads. This test does not
## instantiate a player, depend on current combat poses, or simulate contacts.
const ARM := preload("res://scripts/sword_shield_arm_visual.gd")
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const LENGTHS := [0.022, 0.0263, 0.0275, 0.0253, 0.03125]
const CENTER := Vector3(0.0, -0.0275, -0.0925)
var failures: Array[String] = []


func _init() -> void: call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var world := Node3D.new()
	root.add_child(world)
	for side in [-1, 1]:
		var arm := ARM.new()
		world.add_child(arm)
		arm.position.x = float(side)
		arm.setup(side)
		var rig := arm.skeleton as Skeleton3D
		_check(rig != null and rig.get_bone_count() == 16, "Both independent hands must retain the original 16-joint skin rig")
		var part: MeshInstance3D
		for candidate: MeshInstance3D in arm.hand_meshes:
			if str(candidate.name).begins_with("ContinuousAnatomicalHand"): part = candidate
		_check(part != null and part.skin != null and part.skin.get_bind_count() == 16, "Contact checks require the actual continuously weighted skin, not the glove or detached markers")
		if rig == null or part == null: continue
		var wrist_pose := rig.get_bone_pose_rotation(rig.find_bone("wrist"))
		var source := _read_skin_source(part, rig)
		var rests: Array[Transform3D] = []
		for bone in rig.get_bone_count(): rests.append(rig.get_bone_rest(bone))
		var role := "shield" if side < 0 else "sword"
		for tension in [0.0, 0.30, 0.75, 0.90, 1.0]:
			arm.set_combat_grip(role, tension)
			_check_joint_limits(arm, tension)
			if tension >= 0.75: _check_skin_contact(arm, source, role, side)
		var closed := _rotations(rig)
		arm.set_combat_grip(role, 0.0)
		var opened := _rotations(rig)
		for digit: String in DIGITS:
			_check(opened[rig.find_bone(digit + "1")].is_equal_approx(Quaternion.IDENTITY), "Opening the hand must release each anatomical joint")
			_check(not closed[rig.find_bone(digit + "1")].is_equal_approx(opened[rig.find_bone(digit + "1")]), "Each real finger, including thumb, must participate in the grip")
		arm.set_combat_grip(role, 0.90)
		var before := arm.get_combat_grip_snapshot()
		var before_rotations := _rotations(rig)
		arm.set_combat_grip(role, 0.90)
		_check(arm.get_combat_grip_snapshot().solve_count == before.solve_count and _rotations(rig) == before_rotations, "An unchanged grip must reuse the real joint pose without another solve")
		arm.set_combat_grip(role, 0.75)
		var cached_count := int(arm.get_combat_grip_snapshot().solve_count)
		arm.set_combat_grip(role, 0.90)
		_check(arm.get_combat_grip_snapshot().solve_count == cached_count and _rotations(rig) == before_rotations, "Returning to a cached tension must restore the same exact skinning transforms")
		arm.set_combat_grip("shield" if role == "sword" else "sword", 0.90)
		var other_profile := _rotations(rig)
		_check(other_profile[rig.find_bone("index2")].angle_to(before_rotations[rig.find_bone("index2")]) > 0.10, "Flat shield ribbon and oval sword shaft need distinct distal finger articulation")
		arm.set_grip(0.90)
		_check(arm.get_combat_grip_snapshot().role == role and _rotations(rig) == before_rotations, "Legacy set_grip callers must select the proper dedicated hand role")
		arm.set_combat_grip(role, NAN)
		arm.set_grip(INF)
		arm.set_combat_grip("unrecognized", 0.5)
		_check(_rotations(rig) == before_rotations, "Invalid presentation input must not corrupt the last valid hand pose")
		for bone in rig.get_bone_count():
			_check(rig.get_bone_rest(bone).is_equal_approx(rests[bone]), "Grip solving must never move the source bone rest positions or wrist attachment")
		_check(rig.get_bone_pose_rotation(rig.find_bone("wrist")).is_equal_approx(wrist_pose), "Finger contact solving must not change the imported wrist pose to hide an attachment error")
	world.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "Independent grip geometry checks must preserve expedition and cursor state")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD GRIP ", "PASS" if failures.is_empty() else "FAIL", ": actual weighted skin pads, shaft/ribbon contact, joint limits, bilateral anatomy, role/cache/nonfinite isolation")
	quit(0 if failures.is_empty() else 1)


func _read_skin_source(part: MeshInstance3D, rig: Skeleton3D) -> Dictionary:
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := joints.size() / vertices.size()
	var bind_bones: Array[int] = []
	var binds: Array[Transform3D] = []
	for bind in part.skin.get_bind_count():
		var bone := part.skin.get_bind_bone(bind)
		if bone < 0: bone = rig.find_bone(str(part.skin.get_bind_name(bind)))
		bind_bones.append(bone)
		binds.append(part.skin.get_bind_pose(bind))
	var source := {"vertices": vertices, "joints": joints, "weights": weights, "stride": stride, "bind_bones": bind_bones, "binds": binds, "pads": {}}
	for digit_index in DIGITS.size():
		var digit: String = DIGITS[digit_index]
		var distal := rig.find_bone(digit + "2")
		var reference := rig.get_bone_global_rest(distal) * Vector3(0, LENGTHS[digit_index] * 0.82, -0.006)
		var nearest: Array[Dictionary] = []
		for vertex in vertices.size():
			var distal_weight := 0.0
			var total := 0.0
			for slot in stride:
				var weight := weights[vertex * stride + slot]
				total += weight
				if bind_bones[joints[vertex * stride + slot]] == distal: distal_weight += weight
			if distal_weight > 0.55:
				_check(absf(total - 1.0) < 0.002, "Visible finger-pad vertices must have normalized real skin weights")
				nearest.append({"index": vertex, "distance": vertices[vertex].distance_squared_to(reference)})
		nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
		var indices: Array[int] = []
		for sample in mini(20, nearest.size()): indices.append(int(nearest[sample].index))
		_check(indices.size() == 20, "Each digit requires a real distal skin patch with at least twenty measurable vertices")
		source.pads[digit] = indices
	return source


func _skin_vertex(source: Dictionary, matrices: Array[Transform3D], vertex: int) -> Vector3:
	var point := Vector3.ZERO
	for slot in int(source.stride):
		var entry := vertex * int(source.stride) + slot
		var weight := float(source.weights[entry])
		if weight <= 0.0: continue
		var bind := int(source.joints[entry])
		point += (matrices[bind] * (source.vertices[vertex] as Vector3)) * weight
	return point


func _check_skin_contact(arm, source: Dictionary, role: String, side: int) -> void:
	var rig: Skeleton3D = arm.skeleton
	var matrices: Array[Transform3D] = []
	for bind in source.binds.size(): matrices.append(rig.get_bone_global_pose(source.bind_bones[bind]) * (source.binds[bind] as Transform3D))
	var snapshot: Dictionary = arm.get_combat_grip_snapshot()
	var centers: Dictionary = {}
	for digit: String in DIGITS:
		var mean := Vector3.ZERO
		var points: Array[Vector3] = []
		for vertex: int in source.pads[digit]:
			var point := _skin_vertex(source, matrices, vertex)
			_check(point.is_finite(), "Actual skinning must remain finite for both anatomical sides")
			mean += point
			points.append(point)
		mean /= points.size()
		centers[digit] = mean
		_check(mean.distance_to(snapshot.contacts[digit].actual) < 0.00002, "Reported contact must equal independent full vertex-weight skinning, not a detached bone marker")
		_check(float(snapshot.contacts[digit].error) < 0.010, "Solved visible pad must reach its role contact within ten millimetres: " + role + "/" + digit)
		if digit == "thumb":
			_check(mean.x * side > 0.025 and mean.x * side < 0.068, "The opposed thumb must stay on the anatomical index side instead of crossing through the palm")
			continue
		if role == "sword":
			var radial := Vector2(mean.y - CENTER.y, mean.z - CENTER.z).length()
			_check(radial >= 0.015 and radial <= 0.027, "Actual finger pads must close around the small shaft, without passing through it or remaining extended")
			for point in points:
				_check(Vector2(point.y - CENTER.y, point.z - CENTER.z).length() >= 0.010, "Distal skin must not cross deeply through the sword shaft")
		else:
			_check(absf(mean.y - CENTER.y) < 0.0145 and mean.z - CENTER.z > -0.0015 and mean.z - CENTER.z < 0.010, "Actual shield pads must meet the thin ribbon face within its modeled width")
			for point in points: _check(point.z - CENTER.z > -0.004, "Visible shield-pad skin must not pass fully through the leather ribbon")
		_check(mean.y < -0.020 and mean.z > -0.125, "Closed finger pads must curve back into the grip instead of pointing ahead as straight bars")
	for index in 3:
		_check((centers[DIGITS[index]] as Vector3).distance_to(centers[DIGITS[index + 1]]) > 0.018, "Adjacent anatomical fingertips must remain separate rather than intersecting one another")
	_check((centers.thumb as Vector3).distance_to(centers.index) > 0.014, "Thumb opposition must close beside the index finger without overlapping its distal pad: " + role + "/" + str(side))


func _check_joint_limits(arm, tension: float) -> void:
	var snapshot: Dictionary = arm.get_combat_grip_snapshot()
	var rig: Skeleton3D = arm.skeleton
	for digit: String in DIGITS:
		var contact: Dictionary = snapshot.contacts[digit]
		var lower := Vector3(-0.85, -1.45, -1.45) if digit == "thumb" else Vector3(-1.65, -1.95, -1.35)
		var upper := Vector3(0.65, 0.35, 0.10) if digit == "thumb" else Vector3.ZERO
		_check(absf(float(contact.lateral)) <= (1.0501 if digit == "thumb" else 0.2201), "MCP lateral motion must remain limited rather than introducing arbitrary finger spread")
		for joint in 3:
			_check(contact.angles[joint] >= lower[joint] - 0.0001 and contact.angles[joint] <= upper[joint] + 0.0001, "Each anatomical hinge must remain within its flexion/extension range")
			var rotation := rig.get_bone_pose_rotation(rig.find_bone(digit + str(joint)))
			_check(rotation.is_finite() and rotation.is_normalized(), "Actual joint rotations must stay finite and normalized")
	if tension >= 0.75:
		_check((snapshot.contacts.little.angles as Vector3).distance_to(snapshot.contacts.middle.angles) > 0.08, "Different finger lengths must receive individual articulation rather than identical curls")


func _rotations(rig: Skeleton3D) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for bone in rig.get_bone_count(): result.append(rig.get_bone_pose_rotation(bone))
	return result


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
