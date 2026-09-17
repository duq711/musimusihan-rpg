extends SceneTree
## Independent CPU skinning of the production GLB pads. This test does not
## instantiate a player, depend on current combat poses, or simulate contacts.
const ARM := preload("res://scripts/sword_shield_arm_visual.gd")
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const LENGTHS := [0.0176, 0.02104, 0.022, 0.02024, 0.025]
const CENTER := Vector3(0.0, -0.019, -0.0825)
var failures: Array[String] = []


func _init() -> void: call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var world := Node3D.new()
	root.add_child(world)
	var hands: Dictionary = {}
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
		hands[side] = {"arm": arm, "source": source}
		_check_anatomical_side(rig, source, side)
		_check_phalanx_proportions(rig, source, side)
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
			var neutral := rig.get_bone_rest(rig.find_bone(digit + "1")).basis.get_rotation_quaternion()
			_check(opened[rig.find_bone(digit + "1")].angle_to(neutral) < 0.0001, "Opening the hand must restore each imported anatomical joint rotation")
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
		var profile_pads: Dictionary = {}
		for digit: String in ["index", "middle", "ring"]: profile_pads[digit] = _pad_geometry(source, rig, digit).center
		arm.set_combat_grip("shield" if role == "sword" else "sword", 0.90)
		var squared_profile_difference := 0.0
		for digit: String in ["index", "middle", "ring"]:
			var other_pad: Vector3 = _pad_geometry(source, rig, digit).center
			squared_profile_difference += other_pad.distance_squared_to(profile_pads[digit])
		_check(sqrt(squared_profile_difference / 3.0) > 0.004, "Real skinned finger pads must occupy distinct shaft/ribbon contact surfaces, regardless of which joint supplies the bend")
		arm.set_grip(0.90)
		_check(arm.get_combat_grip_snapshot().role == role and _rotations(rig) == before_rotations, "Legacy set_grip callers must select the proper dedicated hand role")
		arm.set_combat_grip(role, NAN)
		arm.set_grip(INF)
		arm.set_combat_grip("unrecognized", 0.5)
		_check(_rotations(rig) == before_rotations, "Invalid presentation input must not corrupt the last valid hand pose")
		for bone in rig.get_bone_count():
			_check(rig.get_bone_rest(bone).is_equal_approx(rests[bone]), "Grip solving must never move the source bone rest positions or wrist attachment")
		_check(rig.get_bone_pose_rotation(rig.find_bone("wrist")).is_equal_approx(wrist_pose), "Finger contact solving must not change the imported wrist pose to hide an attachment error")
	if hands.size() == 2: _check_bilateral_response(hands)
	world.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "Independent grip geometry checks must preserve expedition and cursor state")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD GRIP ", "PASS" if failures.is_empty() else "FAIL", ": actual weighted skin pads, shaft/ribbon contact, joint limits, bilateral anatomy, role/cache/nonfinite isolation")
	quit(0 if failures.is_empty() else 1)


func _read_skin_source(part: MeshInstance3D, rig: Skeleton3D) -> Dictionary:
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
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
	_check(normals.size() == vertices.size(), "Mirrored visible hand surfaces must retain real vertex normals")
	var source := {"vertices": vertices, "normals": normals, "joints": joints, "weights": weights, "stride": stride, "bind_bones": bind_bones, "binds": binds, "pads": {}}
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
		if digit != "thumb":
			var middle := rig.find_bone(digit + "1")
			var middle_reference := rig.get_bone_global_rest(middle) * Vector3(0, rig.get_bone_rest(distal).origin.length() * 0.55, -0.007)
			source.pads[digit + "_middle"] = _select_skin_patch(source, middle, middle_reference)
			var proximal := rig.find_bone(digit + "0")
			var proximal_reference := rig.get_bone_global_rest(proximal) * Vector3(0, rig.get_bone_rest(middle).origin.length() * 0.85, -0.007)
			source.pads[digit + "_proximal"] = _select_skin_patch(source, proximal, proximal_reference)
			var root := rig.get_bone_global_rest(proximal).origin
			source.pads[digit + "_palm"] = _select_skin_patch(source, rig.find_bone("wrist"), Vector3(root.x, -0.016, root.z + 0.018), true)
	return source


func _select_skin_patch(source: Dictionary, bone: int, reference: Vector3, palmar: bool = false) -> Array[int]:
	var candidates: Array[Dictionary] = []
	for vertex in source.vertices.size():
		if palmar and (source.normals[vertex] as Vector3).y > -0.3: continue
		var influence := 0.0
		for slot in int(source.stride):
			var entry: int = vertex * int(source.stride) + slot
			if int(source.bind_bones[source.joints[entry]]) == bone: influence += float(source.weights[entry])
		if influence > 0.55: candidates.append({"index": vertex, "distance": (source.vertices[vertex] as Vector3).distance_squared_to(reference)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var indices: Array[int] = []
	for sample in mini(20, candidates.size()): indices.append(int(candidates[sample].index))
	_check(indices.size() == 20, "Each independently selected middle/palm patch must contain twenty actual skin vertices")
	return indices


func _skin_vertex(source: Dictionary, matrices: Array[Transform3D], vertex: int) -> Vector3:
	var point := Vector3.ZERO
	for slot in int(source.stride):
		var entry := vertex * int(source.stride) + slot
		var weight := float(source.weights[entry])
		if weight <= 0.0: continue
		var bind := int(source.joints[entry])
		point += (matrices[bind] * (source.vertices[vertex] as Vector3)) * weight
	return point


func _skin_normal(source: Dictionary, matrices: Array[Transform3D], vertex: int) -> Vector3:
	if source.normals.size() != source.vertices.size(): return Vector3.ZERO
	var normal := Vector3.ZERO
	for slot in int(source.stride):
		var entry := vertex * int(source.stride) + slot
		var weight := float(source.weights[entry])
		if weight <= 0.0: continue
		var bind := int(source.joints[entry])
		normal += matrices[bind].basis.inverse().transposed() * (source.normals[vertex] as Vector3) * weight
	return normal.normalized()


func _pad_geometry(source: Dictionary, rig: Skeleton3D, digit: String, rest: bool = false) -> Dictionary:
	var matrices: Array[Transform3D] = []
	for bind in source.binds.size():
		var bone := int(source.bind_bones[bind])
		var frame := rig.get_bone_global_rest(bone) if rest else rig.get_bone_global_pose(bone)
		matrices.append(frame * (source.binds[bind] as Transform3D))
	var center := Vector3.ZERO
	var normal := Vector3.ZERO
	for vertex: int in source.pads[digit]:
		center += _skin_vertex(source, matrices, vertex)
		normal += _skin_normal(source, matrices, vertex)
	return {"center": center / float(maxi(1, source.pads[digit].size())), "normal": normal.normalized()}


func _check_anatomical_side(rig: Skeleton3D, source: Dictionary, side: int) -> void:
	# This is a physical coordinate convention, not a source-name assertion:
	# fingers point -Z, hand back is +Y, so a right thumb occupies -X.
	var thumb := rig.get_bone_global_rest(rig.find_bone("thumb0")).origin
	var index := rig.get_bone_global_rest(rig.find_bone("index0")).origin
	var little := rig.get_bone_global_rest(rig.find_bone("little0")).origin
	_check(thumb.x * side < -0.01, "Actual rest skeleton must put the right thumb on -X and the left thumb on +X")
	_check((index.x - little.x) * side < -0.04, "The physical knuckle order must agree with the thumb side")
	var thumb_skin := _pad_geometry(source, rig, "thumb", true)
	var index_skin := _pad_geometry(source, rig, "index", true)
	_check(float(thumb_skin.center.x) * side < -0.025, "The real weighted thumb surface must have the correct chirality, not only its bone label")
	_check(float((thumb_skin.center - index_skin.center).x) * side < 0.0, "The visible thumb must occupy the outside of its anatomical index finger")


func _check_phalanx_proportions(rig: Skeleton3D, source: Dictionary, side: int) -> void:
	# Values come from the corrected pre-extension GLB, not the grip profile.
	# Only phalanx lengths changed: wrist/palm/MCP width and thumb CMC remain.
	var source_lengths := [[0.04601000249, 0.02746061794], [0.05701999366, 0.03645888716], [0.05904659629, 0.03704928979], [0.05400536954, 0.03667701781], [0.05395619571, 0.03909112141]]
	for digit_index in DIGITS.size():
		var digit: String = DIGITS[digit_index]
		for child in [1, 2]:
			var bone := rig.find_bone(digit + str(child))
			var factor := 1.0 if digit == "thumb" and child == 1 else 0.8
			_check(bone >= 0 and absf(rig.get_bone_rest(bone).origin.length() - float(source_lengths[digit_index][child - 1]) * factor) < 0.000002, "Actual phalanx length must be 0.8 of its source while the thumb MCP anchor remains unchanged: " + digit + str(child))
	var wrist := rig.get_bone_global_rest(rig.find_bone("wrist")).origin
	var index := rig.get_bone_global_rest(rig.find_bone("index0")).origin
	var little := rig.get_bone_global_rest(rig.find_bone("little0")).origin
	var middle := rig.get_bone_global_rest(rig.find_bone("middle0")).origin
	var thumb_cmc := rig.get_bone_global_rest(rig.find_bone("thumb0")).origin
	var thumb_mcp := rig.get_bone_global_rest(rig.find_bone("thumb1")).origin
	_check(wrist.distance_to(Vector3(0, 0, 0.05625)) < 0.000002, "Shortening fingers must preserve the actual wrist anchor")
	_check(absf((little.x - index.x) * side - 0.09125) < 0.000002 and absf(middle.z + 0.10125) < 0.000002, "Palm width and length must remain unchanged instead of shrinking the whole hand")
	_check(absf(thumb_cmc.x * side + 0.0375) < 0.000002 and absf(thumb_cmc.z + 0.00625) < 0.000002 and absf(thumb_mcp.x * side + 0.075) < 0.000002 and absf(thumb_mcp.z + 0.04375) < 0.000002, "Thumb metacarpal and its MCP placement must remain at their original palm anchors")
	for bind in source.binds.size():
		var rest_bind: Transform3D = rig.get_bone_global_rest(int(source.bind_bones[bind])) * (source.binds[bind] as Transform3D)
		_check(rest_bind.origin.length() < 0.000002 and (rest_bind.basis.x - Vector3.RIGHT).length() < 0.000002 and (rest_bind.basis.y - Vector3.UP).length() < 0.000002 and (rest_bind.basis.z - Vector3.BACK).length() < 0.000002, "Each actual inverse bind must match the shortened rest skeleton without hidden hand scale")


func _reflect_hand(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, point.z)


func _check_bilateral_response(hands: Dictionary) -> void:
	var left = hands[-1].arm
	var right = hands[1].arm
	var left_rig := left.skeleton as Skeleton3D
	var right_rig := right.skeleton as Skeleton3D
	for role in ["sword", "shield"]:
		# Compare equal tasks on both actual skins. Comparing each default role
		# would confuse the intended shaft/ribbon difference with handedness.
		for tension in [0.0, 0.75, 0.90, 1.0]:
			left.set_combat_grip(role, tension)
			right.set_combat_grip(role, tension)
			for digit: String in DIGITS:
				var left_pad := _pad_geometry(hands[-1].source, left_rig, digit)
				var right_pad := _pad_geometry(hands[1].source, right_rig, digit)
				var context := "%s/%s tension %.2f" % [role, digit, tension]
				_check((left_pad.center as Vector3).distance_to(_reflect_hand(right_pad.center)) < 0.002, "Equal grips must produce reflected real skin-pad positions within 2mm: " + context)
				_check((left_pad.normal as Vector3).dot(_reflect_hand(right_pad.normal)) > 0.94, "Mirroring the anatomical skin must also reflect its posed surface normal, without inside-out shading: " + context)


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
		# This test owns the physical patch definition; it does not accept a
		# solver-selected point from metadata as evidence of correct contact.
		var contact_geometry := _pad_geometry(source, rig, digit)
		if role == "shield": _check(str(snapshot.contacts[digit].patch) == digit, "All shield fingers must bear on the independently selected shortened distal skin patch")
		_check((contact_geometry.center as Vector3).distance_to(snapshot.contacts[digit].actual) < 0.00002, "Reported contact must equal the independently selected real distal skin")
		_check(mean.distance_to(snapshot.contacts[digit].distal_actual) < 0.00002, "Reported distal skin must equal the actual independent fingertip samples")
		_check(float(snapshot.contacts[digit].error) < 0.010, "Solved visible pad must reach its role contact within ten millimetres: " + role + "/" + digit)
		if digit == "thumb":
			_check(-mean.x * side > 0.025 and -mean.x * side < 0.068, "The opposed thumb must stay on the anatomical index side instead of crossing through the palm")
			var thumb_geometry := _pad_geometry(source, rig, digit)
			if role == "sword":
				# This is the independent hand solver's nominal contact shaft.
				# Actual imported leather is oval: its posed surface clearance is
				# a separate model-level check, not a claim about this radius.
				var nominal_radius := 0.0172
				var radial := Vector2(mean.y - CENTER.y, mean.z - CENTER.z)
				var clearance := radial.length() - nominal_radius
				_check(clearance >= 0.0002 and clearance <= 0.0033, "The opposed thumb skin must settle within 0.5–3mm of its nominal sword contact shaft, allowing 0.3mm sampling tolerance")
				for point in points:
					_check(Vector2(point.y - CENTER.y, point.z - CENTER.z).length() >= nominal_radius - 0.0005, "Real thumb-pad samples must not penetrate deeply into the nominal sword contact shaft")
				var inward := Vector3(0, -radial.x, -radial.y).normalized()
				_check((thumb_geometry.normal as Vector3).dot(inward) > 0.5, "The visible thumb pad must face into the sword grip instead of offering its nail or side")
			else:
				_check((thumb_geometry.normal as Vector3).dot(snapshot.contacts[digit].inward) > 0.4, "The opposed shield thumb pad must face its actual curved strap surface")
			continue
		if role == "sword":
			var radial := Vector2(mean.y - CENTER.y, mean.z - CENTER.z).length()
			_check(radial >= 0.015 and radial <= 0.027, "Actual finger pads must close around the small shaft, without passing through it or remaining extended")
			for point in points:
				_check(Vector2(point.y - CENTER.y, point.z - CENTER.z).length() >= 0.010, "Distal skin must not cross deeply through the sword shaft")
		else:
			var palm := _pad_geometry(source, rig, digit + "_palm")
			_check((palm.center as Vector3).distance_to(snapshot.contacts[digit].palm_actual) < 0.00002, "Reported palm must equal actual wrist-weighted palmar skin")
			var open_distal := _pad_geometry(source, rig, digit, true)
			var open_palm := _pad_geometry(source, rig, digit + "_palm", true)
			var open_gap := (open_distal.center as Vector3).distance_to(open_palm.center)
			_check(mean.distance_to(palm.center) < open_gap * 0.65, "Closed shield distal phalanges must fold toward their real palm instead of staying in an open C shape")
			_check((mean - (palm.center as Vector3)).dot(palm.normal) >= -0.001, "Closed distal skin must not penetrate through the actual palmar surface")
			_check(str(snapshot.contacts[digit].contact_kind) == "strap", "All four shortened fingers must bear on the real padded loop, including the little finger")
			_check((contact_geometry.normal as Vector3).dot(snapshot.contacts[digit].inward) > 0.4, "Load-bearing palmar pads must face into their real strap contact")
		if role == "sword": _check(mean.y < -0.020 and mean.z > -0.125, "Closed sword finger pads must curve back into the grip instead of pointing ahead as straight bars")
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
		if digit == "thumb":
			var opposition := float(contact.get("opposition", 0.0))
			_check(is_finite(opposition) and absf(opposition) <= 0.7501, "The actual thumb CMC opposition must remain finite and within its anatomical 0.75-radian range")
			if tension >= 0.75:
				_check(absf(opposition) > 0.5, "A closed thumb must use its actual CMC opposition joint to turn the pad toward the grip")
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
