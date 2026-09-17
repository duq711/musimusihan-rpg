extends Node3D
## Camera-space presentation only. Consumption/healing stay in use_consumable.
## The roll, free strip, and deposited cloth share one continuous winding path.
const ARM := preload("res://scripts/player_arm_visual.gd")
const DURATION := 6.2
const WRAP_START := 2.05
const WRAP_END := 5.05
const TURNS := 3.0
const WIDTH := 0.080
const GRIP := Vector3(-0.018, 0.014, -0.106)
var active := false
var elapsed := 0.0
var left_arm: Node3D
var right_arm: Node3D
var roll: MeshInstance3D
var cloth: MeshInstance3D
var strip: MeshInstance3D
var _material: StandardMaterial3D
var _wrist := Vector3.ZERO
var _elbow := Vector3.ZERO
var _axis := Vector3.ZERO
var _normal := Vector3.ZERO
var _binormal := Vector3.ZERO
var winding := 0.0
var _cloth_frame := Transform3D.IDENTITY
var _forearm_mesh: MeshInstance3D
var _profile: Array[Vector2] = []

func setup() -> void:
	left_arm = ARM.new()
	left_arm.name = "BandageLeftArm"
	add_child(left_arm)
	left_arm.setup(-1)
	_forearm_mesh = left_arm.arm_meshes.filter(func(part: MeshInstance3D) -> bool: return part.name.begins_with("Forearm_Surface"))[0]
	_measure_sleeve()
	right_arm = ARM.new()
	right_arm.name = "BandageRightArm"
	add_child(right_arm)
	right_arm.setup(1)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.76, 0.71, 0.58)
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var noise := FastNoiseLite.new()
	noise.frequency = 0.38
	var texture := NoiseTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.noise = noise
	texture.as_normal_map = true
	texture.bump_strength = 0.18
	_material.normal_enabled = true
	_material.normal_texture = texture
	_material.uv1_scale = Vector3(24.0, 5.0, 1.0)
	roll = MeshInstance3D.new()
	roll.name = "LinenBandageRoll"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.028
	cylinder.bottom_radius = 0.028
	cylinder.height = WIDTH
	cylinder.radial_segments = 40
	roll.mesh = cylinder
	roll.material_override = _material
	add_child(roll)
	# A dark paper core and concentric cloth rings make the roll legible.
	for end in [-1.0, 1.0]:
		var core := MeshInstance3D.new()
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 0.007
		core_mesh.bottom_radius = 0.007
		core_mesh.height = 0.001
		core.mesh = core_mesh
		var core_material := StandardMaterial3D.new()
		core_material.albedo_color = Color(0.18, 0.13, 0.08)
		core.material_override = core_material
		roll.add_child(core)
		core.position.y = end * (WIDTH * 0.5 + 0.0005)
	cloth = MeshInstance3D.new()
	cloth.name = "DepositedBandage"
	cloth.material_override = _material
	add_child(cloth)
	strip = MeshInstance3D.new()
	strip.name = "TensionedBandageStrip"
	strip.material_override = _material
	add_child(strip)
	clear()

func begin() -> void:
	# Load the supplied rigs only on the first eligible use.
	if not is_instance_valid(left_arm): setup()
	active = true
	elapsed = 0.0
	visible = true
	set_time(0.0)

func clear() -> void:
	active = false
	elapsed = 0.0
	winding = 0.0
	visible = false

func advance(delta: float) -> void:
	if not active or delta <= 0.0: return
	if elapsed + delta >= DURATION:
		clear()
	else:
		set_time(elapsed + delta)

func set_time(seconds: float) -> void:
	elapsed = clampf(seconds, 0.0, DURATION)
	var enter := smoothstep(0.0, 0.30, elapsed)
	var settle := smoothstep(1.30, WRAP_START, elapsed)
	var leave := smoothstep(5.55, DURATION, elapsed)
	var shift := Vector3(0.0, -0.55, 0.12) * (1.0 - enter + leave)
	# Escape from Tarkov reference Q9hG7zeQ3xM, 50–56.5s:
	# draw out the dressing, bring the receiving arm across the lower frame,
	# three one-second passes, then pull down and return.
	var wrap_time := clampf((elapsed - WRAP_START) / (WRAP_END - WRAP_START), 0.0, 1.0)
	winding = wrap_time * TURNS * TAU
	var beat := sin(winding * 0.5) * sin(winding * 0.5)
	var working := settle * (1.0 - smoothstep(WRAP_END, 5.5, elapsed))
	_wrist = Vector3(0.22, -0.365, -0.43) + Vector3(0.005, 0.030, 0.0) * beat * working + shift
	_elbow = Vector3(-0.18, -0.23, -0.40) + Vector3(0.0, 0.020, 0.0) * beat * working + shift
	_axis = (_elbow - _wrist).normalized()
	_normal = (Vector3.UP - _axis * _axis.dot(Vector3.UP)).normalized()
	var left_roll := deg_to_rad(-25.0 + 8.0 * sin(winding))
	var winding_left_basis := Basis(_normal.cross(_axis).normalized(), _normal, _axis).rotated(_axis, left_roll)
	var prep_left_basis := _hand_basis(Vector3(-0.65, -0.5, 0.55), Vector3(0, 0.5, 1))
	var pull := smoothstep(0.45, 1.15, elapsed)
	var free_end := Vector3(-0.035 - 0.095 * pull, -0.15, -0.46) + shift
	var prep_left_position := free_end - prep_left_basis * GRIP
	var left_basis := Basis(prep_left_basis.get_rotation_quaternion().slerp(winding_left_basis.get_rotation_quaternion(), settle))
	left_arm.transform = Transform3D(left_basis, prep_left_position.lerp(_wrist, settle))
	left_arm.set_grip(lerpf(0.84, 1.0, settle), lerpf(0.70, 0.40, settle))
	var prep_elbow := prep_left_position + prep_left_basis.z * 0.25
	left_arm.fit_arm(to_global(Vector3(-0.37, -0.34, -0.16)), to_global(prep_elbow.lerp(_elbow, settle)))
	_cloth_frame = global_transform.affine_inverse() * _forearm_mesh.global_transform
	_axis = _cloth_frame.basis.z.normalized()
	_normal = _cloth_frame.basis.y.normalized()
	_binormal = _cloth_frame.basis.x.normalized()
	var radial := _radial(winding)
	var contact := _point(winding)
	var prep_roll := Vector3(0.045 + 0.045 * pull, -0.15, -0.46) + shift
	var roll_position := prep_roll.lerp(contact + radial * 0.085, settle)
	# Limit the inward forearm angle while allowing the hand to tip down
	# between passes. Keep clearance from the receiving sleeve.
	var arm_direction := Vector3(0.55, -0.65, 0.65).normalized()
	arm_direction -= radial * minf(0.0, arm_direction.dot(radial) + 0.23)
	arm_direction = (arm_direction + radial * 0.10).normalized()
	var winding_right_basis := _hand_basis(arm_direction, Vector3(0.0, 0.45, 1.0))
	var prep_right_basis := _hand_basis(Vector3(0.75, -0.4, 0.5), Vector3(0.0, 0.5, 1.0))
	var right_basis := Basis(prep_right_basis.get_rotation_quaternion().slerp(winding_right_basis.get_rotation_quaternion(), settle))
	var press := smoothstep(5.10, 5.35, elapsed)
	var finish_pull := smoothstep(5.35, 5.55, elapsed)
	roll_position += Vector3(0.035, -0.055, 0.015) * finish_pull
	right_arm.transform = Transform3D(right_basis, roll_position - right_basis * GRIP)
	right_arm.set_grip(0.96, 0.70)
	right_arm.set_finger_curl(3, lerpf(-1.0, -0.65, press), lerpf(-1.35, -0.80, press))
	var wrist_pivot: Vector3 = right_arm._active_visual._wrist_fit_anchor
	var wrist_world: Vector3 = right_arm._active_visual.to_global(wrist_pivot)
	var right_elbow := to_local(wrist_world) + right_basis.z * 0.25
	right_arm.fit_arm(to_global(Vector3(0.38, -0.42, -0.24)), to_global(right_elbow))
	roll.transform = Transform3D(Basis(right_basis.y, -right_basis.x, right_basis.z), roll_position)
	var shrink := lerpf(1.0, 0.66, wrap_time)
	roll.scale = Vector3(shrink, 1.0, shrink)
	roll.visible = true
	cloth.visible = elapsed >= WRAP_START
	strip.visible = elapsed >= 0.30 and elapsed < 5.45
	_build_wrap(maxf(0.06, winding))
	var ribbon_start := free_end.lerp(contact, settle)
	_build_strip(ribbon_start, roll_position - radial * 0.022 * settle, -right_basis.x)

func _hand_basis(direction: Vector3, dorsal: Vector3) -> Basis:
	var forward := direction.normalized()
	var up := (dorsal - forward * dorsal.dot(forward)).normalized()
	return Basis(up.cross(forward).normalized(), up, forward)

func _radial(angle: float) -> Vector3:
	return _normal * cos(angle + PI) + _binormal * sin(angle + PI)

func _point(angle: float, across: float = 0.0) -> Vector3:
	var z := 0.145 + (angle / TAU * 0.027 + across) / _cloth_frame.basis.z.length()
	var sample := clampf((z - 0.08) / 0.015, 0.0, _profile.size() - 1.001)
	var radius := _profile[int(sample)].lerp(_profile[int(sample) + 1], fmod(sample, 1.0))
	# Cloth follows the measured elliptical sleeve, including its real pivot
	# and taper. Successive overlapping turns sit a fraction higher.
	radius += Vector2.ONE * (0.002 + angle / TAU * 0.0007)
	return _cloth_frame * Vector3(sin(angle + PI) * radius.x, cos(angle + PI) * radius.y, z)

func _measure_sleeve() -> void:
	var vertices := PackedVector3Array()
	for surface in _forearm_mesh.mesh.get_surface_count():
		vertices.append_array(_forearm_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	for index in 10:
		var z := 0.08 + index * 0.015
		var radius := Vector2(0.045, 0.04)
		for vertex in vertices:
			if absf(vertex.z - z) < 0.018:
				radius.x = maxf(radius.x, absf(vertex.x))
				radius.y = maxf(radius.y, absf(vertex.y))
		_profile.append(radius)

func _build_wrap(angle: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(2, ceili(angle / TAU * 80.0))
	for i in steps:
		var a := angle * float(i) / steps
		var b := angle * float(i + 1) / steps
		_quad(surface, _point(a, -WIDTH * 0.5), _point(a, WIDTH * 0.5), _point(b, -WIDTH * 0.5), _point(b, WIDTH * 0.5), a / TAU, b / TAU)
	surface.generate_normals()
	cloth.mesh = surface.commit()

func _build_strip(start: Vector3, finish: Vector3, axle: Vector3) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, start - _axis * WIDTH * 0.5, start + _axis * WIDTH * 0.5, finish - axle * WIDTH * 0.5, finish + axle * WIDTH * 0.5, 0.0, 0.4)
	surface.generate_normals()
	strip.mesh = surface.commit()

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, v: float) -> void:
	for corner in [[a, Vector2(u, 0)], [c, Vector2(v, 0)], [b, Vector2(u, 1)], [b, Vector2(u, 1)], [c, Vector2(v, 0)], [d, Vector2(v, 1)]]:
		surface.set_uv(corner[1])
		surface.add_vertex(corner[0])
