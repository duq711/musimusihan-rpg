extends "res://scripts/bandage_use_visuals.gd"
## KWOV8bPUCS8: forearm held across the body. Board rests on the dorsal sleeve.
## Three wraps and timed consumption remain in the existing left-arm treatment.
const SPLINT_DURATION := 7.2
const SPLINT_HANDS_END := 6.8
const SUPPORT_END := 2.0
const WIND_END := 5.3
const PRESS_END := 6.25
var splint: Node3D
var stage := ""
var support_seated := false
var pressed := false
var _support_frame := Transform3D.IDENTITY
var _support_contacts: Array[Dictionary] = []
var _tight_profile: Array[PackedFloat32Array] = []
const WRAP_SIDES := 64
const WRAP_ROWS := 41

func setup() -> void:
	super.setup()
	_cache_support_contacts()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("res://assets/3d/items/splint/wood_support.glb", state) == OK)
	splint = document.generate_scene(state)
	add_child(splint)
	left_arm.name = "SplintReceivingArm"
	right_arm.name = "SplintWindingArm"

func advance(delta: float) -> void:
	if not active or delta <= 0.0: return
	if elapsed + delta >= SPLINT_DURATION: clear()
	else: set_time(elapsed + delta)

func equipment_hidden() -> bool:
	return active and elapsed >= STOW_END and elapsed < SPLINT_HANDS_END

func _position_equipment() -> void:
	var tucked := smoothstep(0.0, STOW_END, elapsed)
	if elapsed >= SPLINT_HANDS_END: tucked = 1.0 - smoothstep(SPLINT_HANDS_END, SPLINT_DURATION, elapsed)
	var offset := Transform3D(Basis(Vector3.RIGHT, -0.55 * tucked), Vector3(0.02, -1.10, 0.12) * tucked)
	for entry: Dictionary in _carried:
		if is_instance_valid(entry.node): entry.node.global_transform = get_parent().global_transform * offset * (entry.camera as Transform3D)

func set_time(seconds: float) -> void:
	elapsed = clampf(seconds, 0.0, SPLINT_DURATION)
	_position_equipment()
	visible = elapsed >= STOW_END and elapsed < SPLINT_HANDS_END
	var lift := smoothstep(STOW_END, 1.0, elapsed)
	var leave := smoothstep(PRESS_END, SPLINT_HANDS_END, elapsed)
	var shift := Vector3(0, -0.55, 0.10) * (1.0 - lift + leave) + Vector3(0, 0.08, -0.08)
	var wrap_progress := clampf((elapsed - SUPPORT_END) / (WIND_END - SUPPORT_END), 0, 1)
	var cycle := wrap_progress * TAU * 3.0
	# Ease briefly on each regrip while preserving three complete turns.
	winding = cycle - 0.30 * sin(cycle)
	# Reference 8–12 s: show the open hand, draw it back into a braced fist,
	# then let the forearm give slightly with each pass of the working hand.
	var reach := smoothstep(0.55, 1.10, elapsed)
	var draw_back := smoothstep(1.35, 2.40, elapsed)
	var inspect := reach * (1.0 - draw_back)
	var brace := smoothstep(SUPPORT_END, SUPPORT_END + 0.5, elapsed)
	var gesture := Vector3(0.09, 0.07, -0.045) * inspect + Vector3(-0.025, 0.015, 0.015) * draw_back
	var sway := Vector3(0.008 * sin(winding), 0.012 * sin(winding - 0.3), 0) * brace
	_wrist = Vector3(-0.12, -0.18, -0.28) + shift + gesture + sway
	_elbow = Vector3(-0.50, -0.13, -0.04) + shift + gesture * 0.35 + sway
	_axis = (_elbow - _wrist).normalized()
	_normal = (Vector3(0, 0.65, 1) - _axis * _axis.dot(Vector3(0, 0.65, 1))).normalized()
	var left_basis := Basis(_normal.cross(_axis).normalized(), _normal, _axis).rotated(_axis, 0.22 * inspect - 0.08 * brace + 0.07 * sin(winding) * brace)
	left_arm.transform = Transform3D(left_basis, _wrist)
	# A relaxed open hand closes firmly as the first wrap takes tension.
	var finger_order := ["little", "ring", "middle", "index"]
	for index in finger_order.size():
		var delay := index * 0.045
		var fist := smoothstep(SUPPORT_END - 0.10 + delay, SUPPORT_END + 0.43 + delay, elapsed)
		var relaxed := Vector3(0.04, 0.10, 0.08)
		left_arm.set_digit_flexion(finger_order[index], relaxed.lerp(Vector3(1.0, 1.0, 0.96), fist))
	# The thumb folds over after the fingers start closing.
	var thumb_close := smoothstep(SUPPORT_END + 0.12, SUPPORT_END + 0.64, elapsed)
	left_arm.set_digit_flexion("thumb", Vector3(0.14, 0.16, 0.12).lerp(Vector3(0.84, 0.88, 0.82), thumb_close))
	left_arm.fit_arm(to_global(Vector3(-0.68, -0.32, -0.06)), to_global(_elbow))
	_cloth_frame = global_transform.affine_inverse() * left_arm._active_visual.get_forearm_frame()
	_axis = _cloth_frame.basis.z.normalized()
	_normal = _cloth_frame.basis.y.normalized()
	_binormal = _cloth_frame.basis.x.normalized()
	_fit_support()
	_update_tight_profile()
	var place := smoothstep(1.0, 1.75, elapsed)
	support_seated = elapsed >= SUPPORT_END
	splint.transform = _support_frame
	splint.position += (_binormal * 0.06 + _normal * 0.12) * (1.0 - place)
	var radial := _radial(winding)
	var contact := _point(winding)
	var roll_position := contact + radial * 0.18
	var carry := splint.position + _binormal * 0.02 - _normal * 0.045
	roll_position = carry.lerp(roll_position, smoothstep(1.45, SUPPORT_END, elapsed))
	var arm_direction := Vector3(0.75, -0.70, -0.40).normalized()
	# Keep a stable elbow direction instead of projecting it onto a moving
	# radial plane, which crosses a wrist-orientation singularity each turn.
	var right_basis := _hand_basis(arm_direction, Vector3.UP).rotated(arm_direction, 0.22 * sin(winding) + 0.07 * sin(winding * 2.0))
	# Close the dressing by pressing its final edge against the stick, without
	# the old long belt-pull gesture or a detached floating tab.
	var press := smoothstep(WIND_END, WIND_END + 0.70, elapsed)
	var release := smoothstep(WIND_END + 0.70, PRESS_END, elapsed)
	var end_contact := _point(TAU * 2.5)
	var press_normal := _radial(TAU * 2.5)
	roll_position = roll_position.lerp(end_contact + press_normal * 0.034, press)
	roll_position += Vector3(0.14, -0.12, 0.10) * release
	pressed = elapsed >= WIND_END + 0.40
	right_arm.transform = Transform3D(right_basis, roll_position - right_basis * GRIP)
	_animate_working_fingers(press, release)
	# Solve against the posed hand, including its enlarged geometry. The old
	# fixed GRIP offset left both props above the fingers after rig changes.
	right_arm.position += roll_position - _roll_grip_point()
	var carrying_board := 1.0 - smoothstep(1.75, SUPPORT_END, elapsed)
	var board_grip := splint.transform * Vector3(0, -0.006, -0.10)
	right_arm.position += (board_grip - _finger_point("index2")) * carrying_board
	# Place the pressing pads at the cloth edge, instead of pressing with the
	# old roll/palm anchor while the fingers remain curled around empty air.
	var rig: Skeleton3D = right_arm._active_visual.skeleton
	var pads := (rig.get_bone_global_pose(rig.find_bone("index2")).origin + rig.get_bone_global_pose(rig.find_bone("middle2")).origin) * 0.5
	var pad_position := to_local(rig.to_global(pads))
	right_arm.position += (end_contact + press_normal * 0.006 - pad_position) * press * (1.0 - release)
	# The shoulder stays at the body, and the elbow stays below/right of
	# the working area. Only the receiving arm is drawn left and forward.
	right_arm.fit_arm(to_global(Vector3(0.60, -0.60, -0.15)), to_global(Vector3(0.42, -0.42, clampf(_roll_grip_point().z, -0.65, 0.06))))

	# The roll stays in the palm/finger cradle during placement, winding and
	# the release into pressing; it is never animated independently of the hand.
	roll_position = _roll_grip_point()
	roll.transform = Transform3D(Basis(right_basis.y, -right_basis.x, right_basis.z), roll_position)
	var remaining := lerpf(1.0, 0.20, wrap_progress) * (1.0 - press)
	roll.scale = Vector3(maxf(remaining, 0.001), 1.0, maxf(remaining, 0.001))
	roll.visible = elapsed < WIND_END + 0.40
	cloth.visible = winding > 0.001
	strip.visible = elapsed >= 1.65 and elapsed < WIND_END + 0.40
	if cloth.visible: _build_wrap(winding)
	_build_strip(contact, roll_position - radial * 0.025 * remaining, -right_basis.x)
	stage = "팔 위에 판자 놓기" if elapsed < SUPPORT_END else ("붕대 감기" if elapsed < WIND_END else ("끝 눌러 고정" if elapsed < PRESS_END else "복귀"))

func _finger_point(bone_name: String) -> Vector3:
	var rig: Skeleton3D = right_arm._active_visual.skeleton
	return to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone_name)).origin))

func _roll_grip_point() -> Vector3:
	return (_finger_point("middle1") + _finger_point("ring1") + _finger_point("thumb2")) / 3.0

func _hand_clearance_samples(arm: Node3D) -> Array[Vector4]:
	var rig: Skeleton3D = arm._active_visual.skeleton
	var samples: Array[Vector4] = []
	for name: String in ["wrist", "palm", "index0", "middle0", "ring0", "little0", "thumb0", "index1", "middle1", "ring1", "little1", "thumb1", "index2", "middle2", "ring2", "little2", "thumb2"]:
		var point := to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(name)).origin))
		var radius := 0.038 if name in ["wrist", "palm"] else (0.025 if name.ends_with("0") else 0.018)
		samples.append(Vector4(point.x, point.y, point.z, radius))
	return samples

func _mesh_projection(arm: Node3D, direction: Vector3) -> Vector2:
	var adapter: Node3D = arm._active_visual
	var skeleton: Skeleton3D = adapter.skeleton
	var local_from_rig := global_transform.affine_inverse() * skeleton.global_transform
	var result := Vector2(INF, -INF)
	for part: MeshInstance3D in adapter.hand_meshes + adapter.arm_meshes:
		var matrices: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(part.skin.get_bind_name(bind))
			matrices.append(local_from_rig * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := int(bones.size() / vertices.size())
			for vertex in vertices.size():
				var point := Vector3.ZERO
				for influence in influences:
					var index := vertex * influences + influence
					if weights[index] > 0: point += (matrices[bones[index]] * vertices[vertex]) * weights[index]
				var projected := point.dot(direction)
				result.x = minf(result.x, projected)
				result.y = maxf(result.y, projected)
	return result

func _animate_working_fingers(press: float, release: float) -> void:
	# Thumb/middle finger retain the roll while index leads each small regrip.
	var working := smoothstep(1.45, SUPPORT_END, elapsed)
	var reset := pow(0.5 + 0.5 * cos(winding), 3.0) * working
	var trailing := pow(0.5 + 0.5 * cos(winding - 0.55), 3.0) * working
	var poses := {
		"index": Vector3(0.82, 0.85, 0.65).lerp(Vector3(0.22, 0.32, 0.30), reset),
		"middle": Vector3(0.83, 0.88, 0.70).lerp(Vector3(0.65, 0.66, 0.48), trailing),
		"ring": Vector3(0.82, 0.86, 0.72).lerp(Vector3(0.40, 0.45, 0.38), trailing),
		"little": Vector3(0.72, 0.82, 0.65).lerp(Vector3(0.26, 0.34, 0.28), trailing),
		"thumb": Vector3(0.76, 0.68, 0.60).lerp(Vector3(0.48, 0.42, 0.36), reset * 0.65)
	}
	for digit: String in poses:
		var pose: Vector3 = poses[digit]
		var pressing := Vector3(0.18, 0.20, 0.22) if digit in ["index", "middle"] else Vector3(0.44, 0.50, 0.40)
		pose = pose.lerp(pressing, press)
		pose = pose.lerp(Vector3(0.22, 0.28, 0.22), release)
		right_arm.set_digit_flexion(digit, pose)

func _sleeve_radius(z: float) -> Vector2:
	var sample := clampf((z - 0.08) / 0.015, 0.0, _profile.size() - 1.001)
	return _profile[int(sample)].lerp(_profile[int(sample) + 1], fmod(sample, 1.0))

func _fit_support() -> void:
	# Follow actual skinned sleeve triangles, not the loose bandage envelope.
	var a := _support_contact(0)
	var b := _support_contact(_support_contacts.size() - 1)
	var forward := (b - a).normalized()
	var side := (_binormal - forward * _binormal.dot(forward)).normalized()
	var up := forward.cross(side).normalized()
	# A rigid board rests on the sleeve's convex folds rather than cutting
	# through the middle when the two end samples are lower than the bulge.
	var rise := 0.0
	for index in _support_contacts.size():
		rise = maxf(rise, (_support_contact(index) - a).dot(up))
	_support_frame = Transform3D(Basis(side, up, forward * (a.distance_to(b) / 0.32)), (a + b) * 0.5 + up * (rise + 0.005))

func _cache_support_contacts() -> void:
	# Cache nine surface rays along the board centerline once.
	for station in 9:
		var z := lerpf(0.065, 0.205, station / 8.0)
		var nearest := -INF
		var contact: Dictionary = {}
		for surface in _forearm_mesh.mesh.get_surface_count():
			var arrays := _forearm_mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for offset in range(0, indices.size(), 3):
				var ids := [indices[offset], indices[offset + 1], indices[offset + 2]]
				var a := vertices[ids[0]]
				var b := vertices[ids[1]]
				var c := vertices[ids[2]]
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(0, 1, z), Vector3.DOWN, a, b, c)
				if hit == null or hit.y <= nearest: continue
				nearest = hit.y
				var u := b - a
				var v := c - a
				var w: Vector3 = hit - a
				var denominator := u.dot(u) * v.dot(v) - u.dot(v) * u.dot(v)
				var beta := (v.dot(v) * w.dot(u) - u.dot(v) * w.dot(v)) / denominator
				var gamma := (u.dot(u) * w.dot(v) - u.dot(v) * w.dot(u)) / denominator
				contact = {"arrays": arrays, "ids": ids, "bary": [1.0 - beta - gamma, beta, gamma]}
		assert(not contact.is_empty(), "Wood support requires actual sleeve surface contacts")
		_support_contacts.append(contact)

func _support_contact(index: int) -> Vector3:
	var sample := _support_contacts[index]
	var arrays: Array = sample.arrays
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := bones.size() / vertices.size()
	var skeleton: Skeleton3D = left_arm._active_visual.skeleton
	var skin := _forearm_mesh.skin
	var point := Vector3.ZERO
	for corner in 3:
		var vertex: int = sample.ids[corner]
		for influence in int(influences):
			var offset := vertex * int(influences) + influence
			if weights[offset] <= 0: continue
			var bind := bones[offset]
			var bone := skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
			point += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset] * float(sample.bary[corner])
	return to_local(skeleton.to_global(point))

func _update_tight_profile() -> void:
	# Use the current weighted sleeve, including elbow/wrist blending.
	var skeleton: Skeleton3D = left_arm._active_visual.skeleton
	var skin := _forearm_mesh.skin
	var matrices: Array[Transform3D] = []
	var cloth_from_skeleton := _cloth_frame.affine_inverse() * global_transform.affine_inverse() * skeleton.global_transform
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
		matrices.append(cloth_from_skeleton * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var sections: Array[PackedVector2Array] = []
	for row in WRAP_ROWS: sections.append(PackedVector2Array())
	for surface in _forearm_mesh.mesh.get_surface_count():
		var arrays := _forearm_mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var influences := int(bones.size() / vertices.size())
		var posed := PackedVector3Array()
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for influence in influences:
				var offset := vertex * influences + influence
				if weights[offset] > 0: point += (matrices[bones[offset]] * vertices[vertex]) * weights[offset]
			posed.append(point)
		for offset in range(0, indices.size(), 3):
			for edge in 3:
				var a := posed[indices[offset + edge]]
				var b := posed[indices[offset + (edge + 1) % 3]]
				if absf(a.z - b.z) < 0.000001: continue
				var first := maxi(0, ceili((minf(a.z, b.z) - 0.065) / 0.004))
				var last := mini(WRAP_ROWS - 1, floori((maxf(a.z, b.z) - 0.065) / 0.004))
				for row in range(first, last + 1):
					var point := a.lerp(b, (0.065 + row * 0.004 - a.z) / (b.z - a.z))
					sections[row].append(Vector2(point.x, point.y))
	_tight_profile.clear()
	for row in WRAP_ROWS:
		var hull := Geometry2D.convex_hull(sections[row])
		var radii := PackedFloat32Array()
		for side in WRAP_SIDES:
			var theta := TAU * side / WRAP_SIDES
			var direction := Vector2(sin(theta), cos(theta))
			var radius := 0.0
			for edge in maxi(0, hull.size() - 1):
				var a := hull[edge]
				var segment := hull[edge + 1] - a
				var denominator := direction.cross(segment)
				if absf(denominator) < 0.000001: continue
				var distance := a.cross(segment) / denominator
				var along := a.cross(direction) / denominator
				if along >= 0 and along <= 1: radius = maxf(radius, distance)
			assert(radius > 0, "Tight wrap needs a closed posed sleeve section")
			radii.append(radius)
		_tight_profile.append(radii)

func _build_wrap(angle: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(2, ceili(angle / TAU * 96.0))
	for i in steps:
		var a := angle * float(i) / steps
		var b := angle * float(i + 1) / steps
		for across in 16:
			var lo := WIDTH * (across / 16.0 - 0.5)
			var hi := WIDTH * ((across + 1) / 16.0 - 0.5)
			_quad(surface, _point(a, lo), _point(a, hi), _point(b, lo), _point(b, hi), a / TAU, b / TAU)
	surface.generate_normals()
	cloth.mesh = surface.commit()

func _tight_radius(theta: float, z: float) -> float:
	var row := clampf((z - 0.065) / 0.004, 0, WRAP_ROWS - 1.001)
	var sector := fposmod(theta, TAU) / TAU * WRAP_SIDES
	var a := int(sector) % WRAP_SIDES
	var b := (a + 1) % WRAP_SIDES
	var lower := lerpf(_tight_profile[int(row)][a], _tight_profile[int(row)][b], fmod(sector, 1.0))
	var upper := lerpf(_tight_profile[int(row) + 1][a], _tight_profile[int(row) + 1][b], fmod(sector, 1.0))
	return lerpf(lower, upper, fmod(row, 1.0))

func _board_radius(origin: Vector3, direction: Vector3) -> float:
	# Exit distance through the actual narrow board, rather than inflating
	# the entire upper half of the bandage to the height of the board.
	var board_from_cloth := _support_frame.affine_inverse() * _cloth_frame
	var p := board_from_cloth * origin
	var d := board_from_cloth.basis * direction
	var bounds := Vector3(0.022, 0.006, 0.16)
	var near := 0.0
	var far := INF
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if absf(p[axis]) > bounds[axis]: return 0.0
			continue
		var a := (-bounds[axis] - p[axis]) / d[axis]
		var b := (bounds[axis] - p[axis]) / d[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
		if far < near: return 0.0
	return maxf(0.0, far)

func _point(angle: float, across: float = 0.0) -> Vector3:
	var z := 0.095 + (angle / TAU * 0.028 + across) / _cloth_frame.basis.z.length()
	var theta := angle + PI
	var direction := Vector3(sin(theta), cos(theta), 0)
	var origin := Vector3(0, 0, z)
	var radius := maxf(_tight_radius(theta, z), _board_radius(origin, direction))
	# Physical 3 mm clearance, with thin overlapping layers, after arm scaling.
	var clearance := (0.003 + angle / TAU * 0.0004) / (_cloth_frame.basis * direction).length()
	return _cloth_frame * (origin + direction * (radius + clearance))
