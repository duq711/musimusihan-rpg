extends "res://scripts/bandage_use_visuals.gd"
## Shares the supplied hands and equipment transition; medical effects stay in player.
const SPLINT_DURATION := 8.6
const SPLINT_HANDS_END := 8.2
var splint: Node3D
var straps: Array[Node3D] = []
var stage := ""
var tightened := 0

func setup() -> void:
	super.setup()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var loaded := document.append_from_file("res://assets/3d/items/splint/wood_linen_splint.glb", state)
	assert(loaded == OK, "Splint GLB must be available")
	splint = document.generate_scene(state)
	add_child(splint)
	for i in 3:
		straps.append(splint.find_child("Strap_%d" % i, true, false))
	for node in splint.find_children("*", "AnimationPlayer", true, false):
		node.stop()

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
	roll.visible = false
	cloth.visible = false
	strip.visible = false
	var lift := smoothstep(0.4, 1.0, elapsed)
	var leave := smoothstep(7.5, SPLINT_HANDS_END, elapsed)
	var shift := Vector3(0, -0.65, 0.10) * (1.0 - lift + leave)
	_wrist = Vector3(-0.055, -0.07, -0.57) + shift
	_elbow = Vector3(-0.25, -0.35, -0.30) + shift
	_axis = (_elbow - _wrist).normalized()
	_normal = (Vector3(0, 0.7, 1) - _axis * _axis.dot(Vector3(0, 0.7, 1))).normalized()
	left_arm.transform = Transform3D(Basis(_normal.cross(_axis).normalized(), _normal, _axis), _wrist)
	left_arm.set_grip(0.86, 0.45)
	left_arm.fit_arm(to_global(Vector3(-0.40, -0.42, -0.12)), to_global(_elbow))
	_cloth_frame = global_transform.affine_inverse() * _forearm_mesh.global_transform
	# Rigid orthonormal frame keeps wooden rails straight when the sleeve stretches.
	var frame := Transform3D(_cloth_frame.basis.orthonormalized(), _cloth_frame.origin)
	var place := smoothstep(1.8, 2.8, elapsed)
	splint.transform = frame
	splint.position += frame.basis.x * (0.18 * (1.0 - place)) + frame.basis.y * (0.10 * (1.0 - place))
	stage = "꺼내기" if elapsed < 1.4 else ("팔 준비" if elapsed < 1.8 else "패드 배치")
	tightened = 0
	var target := splint.transform * Vector3(0.055, 0.10, 0.18)
	if elapsed >= 2.8:
		var index := mini(2, int((elapsed - 2.8) / 1.1))
		var local_time := elapsed - (2.8 + index * 1.1)
		var pull := smoothstep(0.2, 0.75, local_time)
		var release := smoothstep(0.8, 1.1, local_time)
		target = frame * Vector3(0.022 + 0.09 * pull, 0.10 + 0.025 * release, 0.085 + index * 0.095)
		# Smooth transfer between the three fastening sites, with no wrist jump.
		if index > 0:
			var prior := frame * Vector3(0.112, 0.125, 0.085 + (index - 1) * 0.095)
			target = prior.lerp(target, smoothstep(0.0, 0.20, local_time))
		else:
			target = (frame * Vector3(0.055, 0.10, 0.18)).lerp(target, smoothstep(0.0, 0.20, local_time))
		stage = ["하단 스트랩", "중앙 스트랩", "상단 스트랩"][index]
	for i in 3:
		var close := smoothstep(3.0 + i * 1.1, 3.55 + i * 1.1, elapsed)
		straps[i].scale = Vector3(lerpf(1.45, 1.0, close), lerpf(1.45, 1.0, close), 1.0)
		if close >= 0.999: tightened += 1
	if elapsed >= 6.1:
		stage = "최종 확인" if elapsed < 7.1 else "사용 완료"
		target += Vector3(0.12, -0.18, 0.06) * smoothstep(6.1, 7.1, elapsed)
	var right_basis := _hand_basis(Vector3(0.55, -0.55, 0.70), Vector3(0, 0.8, 1))
	right_arm.transform = Transform3D(right_basis, target - right_basis * GRIP)
	right_arm.set_grip(0.86, 0.70)
	var wrist_world: Vector3 = right_arm._active_visual.to_global(right_arm._active_visual._wrist_fit_anchor)
	right_arm.fit_arm(to_global(Vector3(0.40, -0.40, -0.12)), wrist_world + global_basis * right_basis.z * 0.25)
