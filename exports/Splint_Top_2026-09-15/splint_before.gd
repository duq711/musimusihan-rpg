extends "res://scripts/bandage_use_visuals.gd"
## sjPpfdlupx4, 31–37s: support below wrist, three wraps, press the end.
## Mirrored to the existing left-arm treatment. Timed consumption stays in player.
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
	winding = wrap_progress * TAU * 3.0
	var turn := (1.0 - cos(winding)) * 0.30
	var settle := smoothstep(WIND_END, WIND_END + 0.4, elapsed)
	# The receiving forearm rolls across the lower frame as the other hand
	# passes over it, then rolls back to expose its underside on each return.
	_wrist = Vector3(0.10, -0.13, -0.56).lerp(Vector3(0.23, -0.28, -0.44), maxf(turn, settle * 0.30)) + shift
	_elbow = Vector3(-0.25, -0.31, -0.30).lerp(Vector3(-0.18, -0.23, -0.38), turn) + shift
	_axis = (_elbow - _wrist).normalized()
	_normal = (Vector3(0, 0.65, 1) - _axis * _axis.dot(Vector3(0, 0.65, 1))).normalized()
	var left_basis := Basis(_normal.cross(_axis).normalized(), _normal, _axis).rotated(_axis, 1.10 + 0.32 * sin(winding))
	left_arm.transform = Transform3D(left_basis, _wrist)
	left_arm.set_grip(0.95, 0.42)
	left_arm.fit_arm(to_global(Vector3(-0.40, -0.39, -0.14)), to_global(_elbow))
	_cloth_frame = global_transform.affine_inverse() * left_arm._active_visual.get_forearm_frame()
	_axis = _cloth_frame.basis.z.normalized()
	_normal = _cloth_frame.basis.y.normalized()
	_binormal = _cloth_frame.basis.x.normalized()
	_fit_support()
	var place := smoothstep(1.0, SUPPORT_END, elapsed)
	support_seated = elapsed >= SUPPORT_END
	splint.transform = _support_frame
	splint.position += (_binormal * 0.13 - _normal * 0.05) * (1.0 - place)
	var radial := _radial(winding)
	var contact := _point(winding)
	var roll_position := contact + radial * 0.075
	var carry := splint.position + _binormal * 0.02 - _normal * 0.045
	roll_position = carry.lerp(roll_position, smoothstep(1.45, SUPPORT_END, elapsed))
	var arm_direction := Vector3(0.55, -0.60, 0.65).normalized()
	# Keep a stable elbow direction instead of projecting it onto a moving
	# radial plane, which crosses a wrist-orientation singularity each turn.
	var right_basis := _hand_basis(arm_direction, Vector3.UP).rotated(arm_direction, 0.22 * sin(winding))
	# Close the dressing by pressing its final edge against the stick, without
	# the old long belt-pull gesture or a detached floating tab.
	var press := smoothstep(WIND_END, WIND_END + 0.40, elapsed)
	var release := smoothstep(WIND_END + 0.70, PRESS_END, elapsed)
	var end_contact := _point(TAU * 3.0)
	roll_position = roll_position.lerp(end_contact + radial * 0.034, press)
	roll_position += Vector3(0.14, -0.12, 0.10) * release
	pressed = elapsed >= WIND_END + 0.40
	right_arm.transform = Transform3D(right_basis, roll_position - right_basis * GRIP)
	right_arm.set_grip(lerpf(0.94, 0.55, press * (1.0 - release)), 0.70)
	var wrist_world: Vector3 = right_arm._active_visual.global_position
	right_arm.fit_arm(to_global(Vector3(0.40, -0.40, -0.16)), wrist_world + global_basis * right_basis.z * 0.25)
	roll.transform = Transform3D(Basis(right_basis.y, -right_basis.x, right_basis.z), roll_position)
	var remaining := lerpf(1.0, 0.20, wrap_progress) * (1.0 - press)
	roll.scale = Vector3(maxf(remaining, 0.001), 1.0, maxf(remaining, 0.001))
	roll.visible = elapsed < WIND_END + 0.40
	cloth.visible = winding > 0.001
	strip.visible = elapsed >= 1.65 and elapsed < WIND_END + 0.40
	if cloth.visible: _build_wrap(winding)
	_build_strip(contact, roll_position - radial * 0.025 * remaining, -right_basis.x)
	stage = "나무 받치기" if elapsed < SUPPORT_END else ("붕대 감기" if elapsed < WIND_END else ("끝 눌러 고정" if elapsed < PRESS_END else "복귀"))

func _sleeve_radius(z: float) -> Vector2:
	var sample := clampf((z - 0.08) / 0.015, 0.0, _profile.size() - 1.001)
	return _profile[int(sample)].lerp(_profile[int(sample) + 1], fmod(sample, 1.0))

func _fit_support() -> void:
	# Follow actual skinned sleeve triangles, not the loose bandage envelope.
	var a := _support_contact(0)
	var b := _support_contact(1)
	var forward := (b - a).normalized()
	var side := (_binormal - forward * _binormal.dot(forward)).normalized()
	var up := forward.cross(side).normalized()
	_support_frame = Transform3D(Basis(side, up, forward * (a.distance_to(b) / 0.32)), (a + b) * 0.5 - up * 0.005)

func _cache_support_contacts() -> void:
	# Ray hits are cached once; only six weighted vertices are skinned per frame.
	for z: float in [0.065, 0.205]:
		var nearest := INF
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
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(0, -1, z), Vector3.UP, a, b, c)
				if hit == null or hit.y >= nearest: continue
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

func _point(angle: float, across: float = 0.0) -> Vector3:
	var z := 0.125 + (angle / TAU * 0.028 + across) / _cloth_frame.basis.z.length()
	var radius := _sleeve_radius(z) + Vector2.ONE * (0.003 + angle / TAU * 0.0007)
	var theta := angle + PI
	var y := cos(theta) * radius.y
	if y < 0:
		# Enclose the wooden underside as well as the cloth sleeve. The lower
		# half expands gradually, avoiding a hard kink at the stick edges.
		var local_support := _cloth_frame.affine_inverse() * _support_frame
		var start := local_support * Vector3(0, -0.007, -0.16)
		var finish := local_support * Vector3(0, -0.007, 0.16)
		var along := clampf((z - start.z) / (finish.z - start.z), 0, 1)
		var floor_y := lerpf(start.y, finish.y, along) - 0.003 - angle / TAU * 0.0007
		y = cos(theta) * maxf(radius.y, -floor_y)
	return _cloth_frame * Vector3(sin(theta) * radius.x, y, z)
