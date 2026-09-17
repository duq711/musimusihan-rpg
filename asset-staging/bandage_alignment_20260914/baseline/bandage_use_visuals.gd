extends Node3D
## Camera-space presentation only. Consumption/healing stay in use_consumable.
## The roll, free strip, and deposited cloth share one continuous winding path.
const ARM := preload("res://scripts/player_arm_visual.gd")
const DURATION := 4.0
const WRAP_START := 0.42
const WRAP_END := 2.85
const TURNS := 2.0
const WIDTH := 0.046
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
	var enter := smoothstep(0.0, 0.35, elapsed)
	var leave := smoothstep(3.45, DURATION, elapsed)
	var shift := Vector3(0.0, -0.58, 0.16) * (1.0 - enter + leave)
	# Reference: Polydin Studio, First Person Healing Animation Pack, 1–5s.
	# Two close passes with a clenched receiving hand and coordinated forearm
	# roll, followed by a short press. No distant roll orbit or rigid left arm.
	var wrap_time := clampf((elapsed - WRAP_START) / (WRAP_END - WRAP_START), 0.0, 1.0)
	var lap := minf(wrap_time * TURNS, TURNS - 0.000001)
	var lap_fraction := fmod(lap, 1.0)
	var eased_lap := lap_fraction - sin(lap_fraction * TAU) * 0.075
	winding = (floor(lap) + eased_lap) * TAU
	if wrap_time >= 1.0: winding = TURNS * TAU
	var working := smoothstep(0.22, WRAP_START, elapsed) * (1.0 - smoothstep(WRAP_END, 3.35, elapsed))
	var lift := sin(winding - 0.35) * working
	_wrist = Vector3(0.09, -0.13, -0.47) + Vector3(0.018 * lift, 0.040 * lift, 0.015 * lift) + shift
	_elbow = Vector3(-0.32, -0.23, -0.44) + shift
	_axis = (_elbow - _wrist).normalized()
	_normal = (Vector3.UP - _axis * _axis.dot(Vector3.UP)).normalized()
	var left_roll := deg_to_rad(-18.0 + 30.0 * sin(winding + 0.7)) * working
	var left_basis := Basis(_normal.cross(_axis).normalized(), _normal, _axis).rotated(_axis, left_roll)
	left_arm.transform = Transform3D(left_basis, _wrist)
	left_arm.set_grip(lerpf(0.15, 1.0, enter), lerpf(0.15, 0.40, enter))
	left_arm.fit_arm(to_global(Vector3(-0.37, -0.53, 0.14)), to_global(_elbow))
	_cloth_frame = global_transform.affine_inverse() * _forearm_mesh.global_transform
	_axis = _cloth_frame.basis.z.normalized()
	_normal = _cloth_frame.basis.y.normalized()
	_binormal = _cloth_frame.basis.x.normalized()
	var radial := _radial(winding)
	var contact := _point(winding)
	var roll_position := contact + radial * 0.070
	# The winding forearm follows the receiving forearm's axis. This lets
	# the hand pass closely in front/behind it without the elbow cutting
	# across the wound or the wrist making an independent full revolution.
	var palm_z := -_axis
	var palm_y := _normal
	var palm_x := palm_y.cross(palm_z).normalized()
	var right_basis := Basis(palm_x, palm_y, palm_z)
	var press := smoothstep(2.95, 3.22, elapsed)
	roll.visible = true
	strip.visible = elapsed >= 0.30 and elapsed < 3.15
	var grip_target := roll_position
	right_arm.transform = Transform3D(right_basis, grip_target - right_basis * GRIP)
	right_arm.set_grip(0.88, 0.72)
	right_arm.set_finger_curl(0, -0.72, -0.85)
	right_arm.set_finger_curl(1, -0.78, -0.95)
	right_arm.set_finger_curl(3, lerpf(-0.88, -0.55, press), lerpf(-1.0, -0.65, press))
	# Finish with the real index fingertip against the last turn, while the
	# thumb/middle finger continue holding the remaining roll.
	var skeleton: Skeleton3D = right_arm._active_visual.skeleton
	var tip_joint := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("index2")).origin
	var middle_joint := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("index1")).origin
	var fingertip := to_local(tip_joint + (tip_joint - middle_joint).normalized() * 0.018)
	var finish_shift := (contact + radial * 0.003 - fingertip) * press
	right_arm.position += finish_shift
	roll_position += finish_shift
	var right_elbow := right_arm.position + palm_z * 0.30
	right_arm.fit_arm(to_global(Vector3(0.38, -0.65, 0.06)), to_global(right_elbow))
	# The roll stays inside the same finger contact even while the free
	# ribbon twists slightly between the roll axle and the forearm.
	roll.transform = Transform3D(Basis(palm_y, -palm_x, palm_z), roll_position)
	var shrink := lerpf(1.0, 0.66, wrap_time)
	roll.scale = Vector3(shrink, 1.0, shrink)
	_build_wrap(maxf(0.06, winding))
	_build_strip(contact, roll_position - radial * 0.022, -palm_x)
	cloth.visible = elapsed >= 0.30

func _radial(angle: float) -> Vector3:
	return _normal * cos(angle) + _binormal * sin(angle)

func _point(angle: float, across: float = 0.0) -> Vector3:
	var z := 0.11 + (angle / TAU * 0.0405 + across) / _cloth_frame.basis.z.length()
	var sample := clampf((z - 0.08) / 0.015, 0.0, _profile.size() - 1.001)
	var radius := _profile[int(sample)].lerp(_profile[int(sample) + 1], fmod(sample, 1.0))
	# Cloth follows the measured elliptical sleeve, including its real pivot
	# and taper. Successive overlapping turns sit a fraction higher.
	radius += Vector2.ONE * (0.002 + angle / TAU * 0.0007)
	return _cloth_frame * Vector3(sin(angle) * radius.x, cos(angle) * radius.y, z)

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
