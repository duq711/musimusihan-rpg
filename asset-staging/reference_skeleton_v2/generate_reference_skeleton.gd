extends SceneTree

# Deterministic, dependency-free reference skeleton generator for Godot 4.7.
# The model is assembled from smooth custom tube surfaces and detailed primitive
# meshes, then exported as one GLB.  -Z is forward and the lowest toe is y=0.

const OUTPUT_DIR := "res://out"
const TEXTURE_DIR := "res://textures"
const OUTPUT_FILE := "res://out/reference_skeleton_3d.glb"
const TEXTURE_FILE := "res://textures/weathered_bone_albedo.png"

var materials: Dictionary = {}
var bone_texture: ImageTexture
var mesh_serial := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXTURE_DIR))
	_generate_bone_texture()
	_init_materials()
	var skeleton := _build_skeleton()
	var error := _export_glb(skeleton, OUTPUT_FILE)
	if error != OK:
		push_error("Could not export %s: %s" % [OUTPUT_FILE, error_string(error)])
		skeleton.free()
		quit(1)
		return
	print("Generated reference skeleton: %s" % ProjectSettings.globalize_path(OUTPUT_FILE))
	print("Procedural bone texture: %s" % ProjectSettings.globalize_path(TEXTURE_FILE))
	skeleton.free()
	quit(0)


func _generate_bone_texture() -> void:
	var size := 512
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var broad_noise := FastNoiseLite.new()
	broad_noise.seed = 0x51A7
	broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad_noise.frequency = 0.012
	broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	broad_noise.fractal_octaves = 5
	broad_noise.fractal_gain = 0.47
	broad_noise.fractal_lacunarity = 2.08
	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = 0xB04E
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.047
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_gain = 0.52
	for y in range(size):
		for x in range(size):
			var coarse := broad_noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var medium := detail_noise.get_noise_2d(float(x + 97), float(y + 31)) * 0.5 + 0.5
			var fine := _value_noise(float(x + 17) / 5.0, float(y + 211) / 5.0)
			var pores := _hash_noise(x / 2, y / 2)
			var stain := smoothstep(0.51, 0.79, coarse * 0.62 + medium * 0.38)
			var verdigris := smoothstep(0.64, 0.84, broad_noise.get_noise_2d(float(x + 283), float(y - 179)) * 0.5 + 0.5)
			var irregular_ridge := 1.0 - smoothstep(0.010, 0.038, absf((medium * 0.76 + coarse * 0.24) - 0.505))
			var crack_mask := irregular_ridge * smoothstep(0.63, 0.91, fine) * 0.72
			var base := Color("#82765d")
			base = base.lerp(Color("#4b4436"), stain * 0.38)
			base = base.lerp(Color("#647064"), verdigris * 0.24)
			base *= 0.91 + pores * 0.16
			base = base.lerp(Color("#3e3a2d"), crack_mask * 0.52)
			image.set_pixel(x, y, Color(base.r, base.g, base.b, 1.0))
	var save_error := image.save_png(ProjectSettings.globalize_path(TEXTURE_FILE))
	if save_error != OK:
		push_error("Bone texture save failed: %s" % error_string(save_error))
	bone_texture = ImageTexture.create_from_image(image)


func _hash_noise(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263 + 0x4A31B24D
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


func _value_noise(x: float, y: float) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var tx := x - float(x0)
	var ty := y - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(_hash_noise(x0, y0), _hash_noise(x0 + 1, y0), tx)
	var b := lerpf(_hash_noise(x0, y0 + 1), _hash_noise(x0 + 1, y0 + 1), tx)
	return lerpf(a, b, ty)


func _init_materials() -> void:
	materials.bone = _bone_material(Color("#eee6d1"), 0.92)
	materials.bone_light = _bone_material(Color("#fff4d7"), 0.88)
	materials.bone_dark = _bone_material(Color("#b7aa8b"), 0.94)
	materials.bone_grey = _bone_material(Color("#c5c6ba"), 0.93)
	materials.bone_green = _bone_material(Color("#a4b1a5"), 0.94)
	materials.bone_solid = _plain_material(Color("#968568"), 0.92)
	materials.bone_solid_light = _plain_material(Color("#aa9b7b"), 0.88)
	materials.cavity = _plain_material(Color("#090806"), 1.0)
	materials.cavity_soft = _plain_material(Color("#19140d"), 1.0)
	materials.cartilage = _plain_material(Color("#493a28"), 0.97)


func _bone_material(tint: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = bone_texture
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _plain_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _new_pivot(parent: Node3D, scene_root: Node3D, pivot_name: String, position := Vector3.ZERO, rotation_degrees := Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = position
	pivot.rotation_degrees = rotation_degrees
	parent.add_child(pivot)
	pivot.owner = scene_root
	return pivot


func _add_mesh(parent: Node3D, scene_root: Node3D, node_name: String, mesh: Mesh, material: Material, position := Vector3.ZERO, rotation_degrees := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.scale = scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	instance.owner = scene_root
	mesh_serial += 1
	return instance


func _sphere(segments := 24, rings := 12) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _tube_mesh(points: Array[Vector3], radii: Array[float], radial_segments := 10, cap_ends := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_count := points.size()
	for ring in range(ring_count - 1):
		var tangent_a := _curve_tangent(points, ring)
		var tangent_b := _curve_tangent(points, ring + 1)
		var frame_a := _tube_frame(tangent_a)
		var frame_b := _tube_frame(tangent_b)
		for segment in range(radial_segments):
			var next_segment := (segment + 1) % radial_segments
			var angle_a := TAU * float(segment) / float(radial_segments)
			var angle_b := TAU * float(next_segment) / float(radial_segments)
			var normal_a0: Vector3 = frame_a[0] * cos(angle_a) + frame_a[1] * sin(angle_a)
			var normal_a1: Vector3 = frame_a[0] * cos(angle_b) + frame_a[1] * sin(angle_b)
			var normal_b0: Vector3 = frame_b[0] * cos(angle_a) + frame_b[1] * sin(angle_a)
			var normal_b1: Vector3 = frame_b[0] * cos(angle_b) + frame_b[1] * sin(angle_b)
			var a0 := points[ring] + normal_a0 * radii[ring]
			var a1 := points[ring] + normal_a1 * radii[ring]
			var b0 := points[ring + 1] + normal_b0 * radii[ring + 1]
			var b1 := points[ring + 1] + normal_b1 * radii[ring + 1]
			var u0 := float(segment) / float(radial_segments)
			var u1 := float(segment + 1) / float(radial_segments)
			var v0 := float(ring) / float(ring_count - 1)
			var v1 := float(ring + 1) / float(ring_count - 1)
			_add_vertex(st, a0, normal_a0, Vector2(u0, v0))
			_add_vertex(st, b0, normal_b0, Vector2(u0, v1))
			_add_vertex(st, b1, normal_b1, Vector2(u1, v1))
			_add_vertex(st, a0, normal_a0, Vector2(u0, v0))
			_add_vertex(st, b1, normal_b1, Vector2(u1, v1))
			_add_vertex(st, a1, normal_a1, Vector2(u1, v0))
	if cap_ends:
		_add_tube_cap(st, points[0], -_curve_tangent(points, 0), radii[0], radial_segments)
		_add_tube_cap(st, points[-1], _curve_tangent(points, ring_count - 1), radii[-1], radial_segments)
	st.generate_tangents()
	return st.commit()


func _curve_tangent(points: Array[Vector3], index: int) -> Vector3:
	if index <= 0:
		return (points[1] - points[0]).normalized()
	if index >= points.size() - 1:
		return (points[-1] - points[-2]).normalized()
	return (points[index + 1] - points[index - 1]).normalized()


func _tube_frame(tangent: Vector3) -> Array[Vector3]:
	var reference := Vector3.UP
	if absf(tangent.dot(reference)) > 0.88:
		reference = Vector3.FORWARD
	var axis_a := tangent.cross(reference).normalized()
	var axis_b := axis_a.cross(tangent).normalized()
	return [axis_a, axis_b]


func _add_tube_cap(st: SurfaceTool, center: Vector3, normal: Vector3, radius: float, radial_segments: int) -> void:
	var frame := _tube_frame(normal)
	for segment in range(radial_segments):
		var a0 := TAU * float(segment) / float(radial_segments)
		var a1 := TAU * float(segment + 1) / float(radial_segments)
		var p0 := center + (frame[0] * cos(a0) + frame[1] * sin(a0)) * radius
		var p1 := center + (frame[0] * cos(a1) + frame[1] * sin(a1)) * radius
		_add_vertex(st, center, normal, Vector2(0.5, 0.5))
		_add_vertex(st, p0, normal, Vector2(cos(a0) * 0.5 + 0.5, sin(a0) * 0.5 + 0.5))
		_add_vertex(st, p1, normal, Vector2(cos(a1) * 0.5 + 0.5, sin(a1) * 0.5 + 0.5))


func _add_vertex(st: SurfaceTool, vertex: Vector3, normal: Vector3, uv: Vector2) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.add_vertex(vertex)


func _bone_mesh(start: Vector3, finish: Vector3, shaft_radius: float, joint_radius: float, bow := Vector3.ZERO, radial_segments := 12) -> ArrayMesh:
	var delta := finish - start
	var points: Array[Vector3] = [
		start,
		start + delta * 0.08 + bow * 0.20,
		start + delta * 0.22 + bow * 0.55,
		start + delta * 0.50 + bow,
		start + delta * 0.78 + bow * 0.55,
		start + delta * 0.92 + bow * 0.20,
		finish,
	]
	var radii: Array[float] = [joint_radius * 0.78, joint_radius, shaft_radius * 1.10, shaft_radius, shaft_radius * 1.05, joint_radius * 0.92, joint_radius * 0.78]
	return _tube_mesh(points, radii, radial_segments, true)


func _closed_tube_mesh(points: Array[Vector3], radius: float, radial_segments := 10) -> ArrayMesh:
	var closed := points.duplicate()
	closed.append(points[0])
	var radii: Array[float] = []
	for _point in closed:
		radii.append(radius)
	return _tube_mesh(closed, radii, radial_segments, false)


func _extruded_polygon(points: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_depth := depth * 0.5
	for index in range(1, points.size() - 1):
		_add_triangle(st, Vector3(points[0].x, points[0].y, -half_depth), Vector3(points[index + 1].x, points[index + 1].y, -half_depth), Vector3(points[index].x, points[index].y, -half_depth), Vector3(0, 0, -1))
		_add_triangle(st, Vector3(points[0].x, points[0].y, half_depth), Vector3(points[index].x, points[index].y, half_depth), Vector3(points[index + 1].x, points[index + 1].y, half_depth), Vector3(0, 0, 1))
	for index in range(points.size()):
		var next := (index + 1) % points.size()
		var a := Vector3(points[index].x, points[index].y, -half_depth)
		var b := Vector3(points[next].x, points[next].y, -half_depth)
		var c := Vector3(points[next].x, points[next].y, half_depth)
		var d := Vector3(points[index].x, points[index].y, half_depth)
		var normal := (b - a).cross(c - a).normalized()
		_add_triangle(st, a, b, c, normal)
		_add_triangle(st, a, c, d, normal)
	st.generate_tangents()
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	_add_vertex(st, a, normal, Vector2(0, 0))
	_add_vertex(st, b, normal, Vector2(1, 0))
	_add_vertex(st, c, normal, Vector2(0.5, 1))


func _export_glb(root: Node3D, resource_path: String) -> Error:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(root, state)
	if append_error != OK:
		return append_error
	return document.write_to_filesystem(state, ProjectSettings.globalize_path(resource_path))


func _build_skeleton() -> Node3D:
	var root := Node3D.new()
	root.name = "ReferenceSkeleton3D"
	var visual := _new_pivot(root, root, "VisualRoot")
	var torso := _new_pivot(visual, root, "TorsoPivot", Vector3(0, 1.24, 0), Vector3(-2, 0, 0))
	var head := _new_pivot(torso, root, "HeadPivot", Vector3(0, 0.475, -0.012), Vector3(-3, 0, 0))
	var arm_l := _new_pivot(torso, root, "ArmLPivot", Vector3(-0.315, 0.245, 0), Vector3(-2, -3, -22))
	var arm_r := _new_pivot(torso, root, "ArmRPivot", Vector3(0.315, 0.245, 0), Vector3(-2, 3, 22))
	var leg_l := _new_pivot(visual, root, "LegLPivot", Vector3(-0.135, 0.965, 0.018), Vector3(0, -2, -4))
	var leg_r := _new_pivot(visual, root, "LegRPivot", Vector3(0.135, 0.965, 0.018), Vector3(0, 2, 4))

	_build_torso(torso, root)
	_build_head(head, root)
	_build_arm(arm_l, root, -1)
	_build_arm(arm_r, root, 1)
	_build_leg(leg_l, root, -1)
	_build_leg(leg_r, root, 1)
	return root


func _build_torso(torso: Node3D, root: Node3D) -> void:
	# Twenty-four visible vertebral bodies create a readable neck-to-sacrum line.
	for index in range(20):
		var progress := float(index) / 19.0
		var y := 0.335 - progress * 0.675
		var z := 0.092 + sin(progress * PI) * 0.025
		var width := 0.050 + sin(progress * PI) * 0.018
		_add_mesh(torso, root, "BoneSpineVertebra%02d" % index, _sphere(14, 7), materials.bone_dark, Vector3(0, y, z), Vector3(0, index * 13, 0), Vector3(width * 2.0, 0.038, 0.072))
		if index > 1 and index < 18:
			_add_mesh(torso, root, "BoneSpineProcessL%02d" % index, _bone_mesh(Vector3.ZERO, Vector3(-0.075, 0.006, 0.015), 0.007, 0.012, Vector3(0, 0.006, 0), 7), materials.bone_dark, Vector3(0, y, z))
			_add_mesh(torso, root, "BoneSpineProcessR%02d" % index, _bone_mesh(Vector3.ZERO, Vector3(0.075, 0.006, 0.015), 0.007, 0.012, Vector3(0, 0.006, 0), 7), materials.bone_dark, Vector3(0, y, z))

	# Sternum has a broad manubrium and a tapered xiphoid process.
	_add_mesh(torso, root, "BoneSternum", _tube_mesh([
		Vector3(0, 0.255, -0.182), Vector3(0, 0.20, -0.198),
		Vector3(0, 0.04, -0.216), Vector3(0, -0.16, -0.187), Vector3(0, -0.245, -0.145)
	], [0.036, 0.031, 0.024, 0.018, 0.008], 12, true), materials.bone_dark)

	# Twelve independent rib pairs; their curved tubes leave real intercostal gaps.
	for rib in range(12):
		var p := float(rib) / 11.0
		var y := 0.285 - p * 0.505
		var bell := sin((p * 0.86 + 0.08) * PI)
		var width := 0.225 + bell * 0.105 - maxf(0.0, p - 0.72) * 0.15
		var front_z := -0.165 - bell * 0.055
		var rib_radius := lerpf(0.0125, 0.0085, p)
		for side in [-1, 1]:
			var sf := float(side)
			var finish_x := sf * (0.042 if rib < 8 else lerpf(0.095, 0.18, (p - 0.72) / 0.28))
			var points: Array[Vector3] = [
				Vector3(sf * 0.022, y + 0.012, 0.086),
				Vector3(sf * width * 0.42, y + 0.012, 0.104),
				Vector3(sf * width * 0.84, y - 0.002, 0.038),
				Vector3(sf * width, y - 0.027 - p * 0.012, -0.058),
				Vector3(sf * width * 0.82, y - 0.055 - p * 0.022, front_z),
				Vector3(finish_x, y - 0.070 - p * 0.030, front_z - 0.010),
			]
			_add_mesh(torso, root, "BoneRib%s%02d" % [("L" if side < 0 else "R"), rib + 1], _tube_mesh(points, [rib_radius * 0.88, rib_radius, rib_radius, rib_radius * 0.94, rib_radius * 0.82, rib_radius * 0.62], 10, true), materials.bone)

	# Clavicles and thin rear scapulae preserve a recognisable shoulder girdle.
	for side in [-1, 1]:
		var sf := float(side)
		_add_mesh(torso, root, "BoneClavicle%s" % ("L" if side < 0 else "R"), _tube_mesh([
			Vector3(sf * 0.02, 0.266, -0.175), Vector3(sf * 0.13, 0.295, -0.16),
			Vector3(sf * 0.235, 0.275, -0.105), Vector3(sf * 0.325, 0.245, -0.025)
		], [0.018, 0.020, 0.017, 0.024], 11, true), materials.bone_light)
		var scapula_points := PackedVector2Array([
			Vector2(sf * 0.315, 0.235), Vector2(sf * 0.155, 0.20),
			Vector2(sf * 0.19, -0.035), Vector2(sf * 0.28, 0.035),
		])
		if side < 0:
			scapula_points.reverse()
		_add_mesh(torso, root, "BoneScapula%s" % ("L" if side < 0 else "R"), _extruded_polygon(scapula_points, 0.018), materials.bone_solid, Vector3(0, 0, 0.115), Vector3(0, 0, 0))
		_add_mesh(torso, root, "BoneScapulaSpine%s" % ("L" if side < 0 else "R"), _bone_mesh(Vector3(sf * 0.16, 0.17, 0.132), Vector3(sf * 0.31, 0.16, 0.11), 0.007, 0.012, Vector3(0, 0.015, 0), 8), materials.bone_grey)

	_build_pelvis(torso, root)


func _build_pelvis(torso: Node3D, root: Node3D) -> void:
	# Sacrum is a tapered wedge at the rear of the pelvic ring.
	var sacrum_points := PackedVector2Array([
		Vector2(-0.075, -0.255), Vector2(0.075, -0.255),
		Vector2(0.055, -0.445), Vector2(0, -0.505), Vector2(-0.055, -0.445),
	])
	_add_mesh(torso, root, "BonePelvisSacrum", _extruded_polygon(sacrum_points, 0.075), materials.bone_dark, Vector3(0, 0, 0.075))

	for side in [-1, 1]:
		var sf := float(side)
		# The iliac wing is broad like the reference, while the obturator foramen is
		# genuinely empty because its boundary is made from a closed tube.
		var wing_points := PackedVector2Array([
			Vector2(sf * 0.035, -0.275), Vector2(sf * 0.155, -0.235),
			Vector2(sf * 0.275, -0.285), Vector2(sf * 0.255, -0.405),
			Vector2(sf * 0.155, -0.455), Vector2(sf * 0.085, -0.385),
		])
		if side < 0:
			wing_points.reverse()
		_add_mesh(torso, root, "BonePelvisIlium%s" % ("L" if side < 0 else "R"), _extruded_polygon(wing_points, 0.052), materials.bone_solid_light, Vector3(0, 0, 0.015), Vector3(0, 0, 0))
		var foramen: Array[Vector3] = []
		for point_index in range(18):
			var angle := TAU * float(point_index) / 18.0
			foramen.append(Vector3(sf * (0.13 + cos(angle) * 0.070), -0.445 + sin(angle) * 0.078, -0.055 - cos(angle) * 0.018))
		_add_mesh(torso, root, "BonePelvisObturatorForamen%s" % ("L" if side < 0 else "R"), _closed_tube_mesh(foramen, 0.016, 9), materials.bone_dark)
		_add_mesh(torso, root, "BonePelvisPubicRamus%s" % ("L" if side < 0 else "R"), _bone_mesh(Vector3(sf * 0.19, -0.42, -0.04), Vector3(sf * 0.025, -0.475, -0.12), 0.013, 0.021, Vector3(0, 0.025, -0.012), 10), materials.bone)
		_add_mesh(torso, root, "BonePelvisIschium%s" % ("L" if side < 0 else "R"), _bone_mesh(Vector3(sf * 0.20, -0.385, 0.0), Vector3(sf * 0.13, -0.515, 0.015), 0.016, 0.025, Vector3(sf * 0.015, 0, 0), 10), materials.bone_dark)
		_add_mesh(torso, root, "BonePelvisAcetabulum%s" % ("L" if side < 0 else "R"), _sphere(18, 9), materials.cavity_soft, Vector3(sf * 0.205, -0.39, -0.015), Vector3.ZERO, Vector3(0.082, 0.085, 0.035))
	_add_mesh(torso, root, "BonePelvisPubicSymphysis", _bone_mesh(Vector3(0, -0.42, -0.125), Vector3(0, -0.49, -0.125), 0.014, 0.020, Vector3.ZERO, 9), materials.bone_light)


func _build_head(head: Node3D, root: Node3D) -> void:
	# A proportionally large weathered cranium follows the supplied reference.
	_add_mesh(head, root, "BoneSkullCranium", _sphere(40, 24), materials.bone, Vector3(0, 0.035, -0.010), Vector3(0, 0, 0), Vector3(0.240, 0.320, 0.220))

	# Eye and nose shapes are unlit matte recesses, not luminous eyeballs.
	for side in [-1, 1]:
		var sf := float(side)
		var side_name := "L" if side < 0 else "R"
		var socket_center_x := sf * 0.064
		var socket_points := PackedVector2Array([
			Vector2(socket_center_x - sf * 0.026, 0.061),
			Vector2(socket_center_x + sf * 0.035, 0.058),
			Vector2(socket_center_x + sf * 0.041, 0.025),
			Vector2(socket_center_x + sf * 0.027, -0.016),
			Vector2(socket_center_x - sf * 0.019, -0.024),
			Vector2(socket_center_x - sf * 0.033, 0.007),
		])
		if side < 0:
			socket_points.reverse()
		_add_mesh(head, root, "BoneSkullEyeSocket%s" % side_name, _extruded_polygon(socket_points, 0.010), materials.cavity, Vector3(0, 0, -0.154), Vector3(sf * -3, sf * 2, sf * 2))
		_add_mesh(head, root, "BoneSkullEyeDepth%s" % side_name, _sphere(20, 11), materials.cavity, Vector3(sf * 0.064, 0.021, -0.128), Vector3(-5, sf * 4, sf * 5), Vector3(0.064, 0.052, 0.034))
		_add_mesh(head, root, "BoneSkullCheek%s" % side_name, _bone_mesh(Vector3(sf * 0.135, 0.014, -0.105), Vector3(sf * 0.112, -0.075, -0.125), 0.011, 0.017, Vector3(sf * 0.010, 0, -0.008), 9), materials.bone)
		_add_mesh(head, root, "BoneSkullZygomaticArch%s" % side_name, _tube_mesh([
			Vector3(sf * 0.080, -0.018, -0.118), Vector3(sf * 0.145, -0.015, -0.082),
			Vector3(sf * 0.155, 0.010, 0.005), Vector3(sf * 0.115, 0.020, 0.055)
		], [0.010, 0.013, 0.011, 0.008], 9, true), materials.bone_dark)
		_add_mesh(head, root, "BoneSkullBrow%s" % side_name, _bone_mesh(Vector3(sf * 0.005, 0.098, -0.132), Vector3(sf * 0.135, 0.083, -0.115), 0.011, 0.016, Vector3(0, 0.012, -0.004), 10), materials.bone_dark)

	var nose_points := PackedVector2Array([
		Vector2(0, 0.044), Vector2(-0.030, -0.025), Vector2(-0.024, -0.083),
		Vector2(0, -0.105), Vector2(0.024, -0.083), Vector2(0.030, -0.025),
	])
	_add_mesh(head, root, "BoneSkullNasalCavity", _extruded_polygon(nose_points, 0.008), materials.cavity, Vector3(0, 0, -0.205))
	_add_mesh(head, root, "BoneSkullNasalVoid", _sphere(22, 12), materials.cavity, Vector3(0, -0.026, -0.196), Vector3(0, 0, 0), Vector3(0.043, 0.096, 0.026))

	# Maxilla and a true U-shaped mandible frame the individually modelled teeth.
	_add_mesh(head, root, "BoneSkullMaxilla", _tube_mesh([
		Vector3(-0.105, -0.065, -0.114), Vector3(-0.075, -0.094, -0.145),
		Vector3(0, -0.105, -0.160), Vector3(0.075, -0.094, -0.145),
		Vector3(0.105, -0.065, -0.114)
	], [0.020, 0.022, 0.023, 0.022, 0.020], 11, true), materials.bone)
	var jaw_points: Array[Vector3] = [
		Vector3(-0.115, -0.055, -0.076), Vector3(-0.120, -0.145, -0.096),
		Vector3(-0.085, -0.205, -0.118), Vector3(0, -0.225, -0.130),
		Vector3(0.085, -0.205, -0.118), Vector3(0.120, -0.145, -0.096),
		Vector3(0.115, -0.055, -0.076)
	]
	_add_mesh(head, root, "BoneJaw", _tube_mesh(jaw_points, [0.019, 0.022, 0.022, 0.024, 0.022, 0.022, 0.019], 12, true), materials.bone_dark)
	_add_mesh(head, root, "BoneJawChin", _bone_mesh(Vector3(-0.065, -0.204, -0.130), Vector3(0.065, -0.204, -0.130), 0.012, 0.018, Vector3(0, -0.015, -0.006), 10), materials.bone)

	for tooth in range(14):
		var x := lerpf(-0.088, 0.088, float(tooth) / 13.0)
		var arch := pow(absf(x) / 0.088, 1.65)
		var z := -0.166 + arch * 0.025
		var width := 0.0085 if tooth in [0, 1, 12, 13] else 0.0105
		var upper_length := 0.031 + (0.005 if tooth in [2, 11] else 0.0)
		_add_mesh(head, root, "BoneToothUpper%02d" % (tooth + 1), _bone_mesh(Vector3(x, -0.098, z), Vector3(x, -0.098 - upper_length, z - 0.002), width * 0.58, width, Vector3.ZERO, 7), materials.bone_light)
		var lower_length := 0.027 + (0.004 if tooth in [2, 11] else 0.0)
		_add_mesh(head, root, "BoneToothLower%02d" % (tooth + 1), _bone_mesh(Vector3(x, -0.184, z - 0.002), Vector3(x, -0.184 + lower_length, z - 0.004), width * 0.55, width * 0.92, Vector3.ZERO, 7), materials.bone_light)

	# Subtle embedded fissures and mineral marks break the perfect procedural dome.
	_add_mesh(head, root, "BoneSkullSutureSagittal", _tube_mesh([
		Vector3(0, 0.232, -0.028), Vector3(-0.006, 0.210, 0.015),
		Vector3(0.005, 0.170, 0.075), Vector3(-0.004, 0.115, 0.108)
	], [0.0035, 0.003, 0.003, 0.0025], 6, true), materials.cavity_soft)


func _build_arm(arm: Node3D, root: Node3D, side: int) -> void:
	var sf := float(side)
	var side_name := "L" if side < 0 else "R"
	_add_mesh(arm, root, "BoneShoulder%s" % side_name, _sphere(22, 12), materials.bone, Vector3.ZERO, Vector3.ZERO, Vector3(0.090, 0.085, 0.085))
	_add_mesh(arm, root, "BoneHumerus%s" % side_name, _bone_mesh(Vector3(0, -0.015, 0), Vector3(sf * 0.012, -0.315, 0.010), 0.025, 0.052, Vector3(sf * 0.012, 0, -0.012), 14), materials.bone)
	_add_mesh(arm, root, "BoneHumerusDeltoidTuberosity%s" % side_name, _sphere(14, 7), materials.bone_dark, Vector3(sf * 0.018, -0.13, -0.012), Vector3.ZERO, Vector3(0.045, 0.060, 0.038))

	var elbow := _new_pivot(arm, root, "Elbow%sPivot" % side_name, Vector3(sf * 0.012, -0.315, 0.010), Vector3(-8, 0, sf * 8))
	_add_mesh(elbow, root, "BoneElbow%s" % side_name, _sphere(18, 9), materials.bone_light, Vector3.ZERO, Vector3.ZERO, Vector3(0.074, 0.066, 0.065))
	_add_mesh(elbow, root, "BoneUlna%s" % side_name, _bone_mesh(Vector3(sf * 0.018, -0.010, 0.010), Vector3(sf * 0.030, -0.305, 0.003), 0.014, 0.031, Vector3(sf * 0.010, 0, 0.013), 11), materials.bone_dark)
	_add_mesh(elbow, root, "BoneRadius%s" % side_name, _bone_mesh(Vector3(sf * -0.025, -0.012, -0.012), Vector3(sf * -0.024, -0.305, -0.010), 0.015, 0.032, Vector3(sf * -0.010, 0, -0.010), 11), materials.bone)
	_add_mesh(elbow, root, "BoneOlecranon%s" % side_name, _sphere(14, 7), materials.bone_dark, Vector3(0, 0.015, 0.040), Vector3.ZERO, Vector3(0.043, 0.070, 0.048))

	var wrist_name := "Wrist%sPivot" % side_name
	var wrist := _new_pivot(elbow, root, wrist_name, Vector3(sf * 0.003, -0.310, -0.006), Vector3(4, sf * -3, sf * -4))
	_add_mesh(wrist, root, "BoneWrist%sRadiusHead" % side_name, _sphere(14, 7), materials.bone, Vector3(sf * -0.024, 0, -0.008), Vector3.ZERO, Vector3(0.047, 0.052, 0.044))
	_add_mesh(wrist, root, "BoneWrist%sUlnaHead" % side_name, _sphere(14, 7), materials.bone_dark, Vector3(sf * 0.026, 0.002, 0.008), Vector3.ZERO, Vector3(0.040, 0.047, 0.040))
	var hand_parent := wrist
	if side > 0:
		# Compatibility pivot remains geometry-free: it is a wrist/attack anchor only.
		hand_parent = _new_pivot(wrist, root, "WeaponPivot")
	var hand := _new_pivot(hand_parent, root, "Hand%sPivot" % side_name, Vector3(0, -0.015, 0), Vector3.ZERO)
	_build_hand(hand, root, side)


func _build_hand(hand: Node3D, root: Node3D, side: int) -> void:
	var sf := float(side)
	var side_name := "L" if side < 0 else "R"
	# Eight small carpal bones instead of a single mitten block.
	for row in range(2):
		for column in range(4):
			var x := -0.043 + float(column) * 0.029
			var y := -0.020 - float(row) * 0.028
			var z := -0.004 + (0.007 if (row + column) % 2 == 0 else -0.004)
			_add_mesh(hand, root, "BoneHand%sCarpal%02d" % [side_name, row * 4 + column + 1], _sphere(12, 6), materials.bone_dark if (row + column) % 3 == 0 else materials.bone, Vector3(x, y, z), Vector3(column * 11, row * 7, 0), Vector3(0.028, 0.032, 0.025))

	var finger_x := [-0.048, -0.024, 0.002, 0.028, 0.051]
	var finger_lengths := [0.070, 0.090, 0.100, 0.094, 0.075]
	var phalanx_counts := [2, 3, 3, 3, 3]
	for digit in range(5):
		var is_thumb := digit == 0
		var base_x: float = finger_x[digit]
		if side > 0:
			base_x = -base_x
		var metacarpal_start := Vector3(base_x * 0.65, -0.045, 0.0)
		var metacarpal_end := Vector3(base_x, -0.118 + absf(base_x) * 0.12, -0.012)
		if is_thumb:
			metacarpal_end = Vector3(sf * 0.087, -0.086, -0.004)
		_add_mesh(hand, root, "BoneHand%sMetacarpal%02d" % [side_name, digit + 1], _bone_mesh(metacarpal_start, metacarpal_end, 0.0075, 0.013, Vector3(0, 0, -0.004), 8), materials.bone)
		var segment_start := metacarpal_end
		for phalanx in range(phalanx_counts[digit]):
			var length: float = finger_lengths[digit] * (0.43 if phalanx == 0 else (0.33 if phalanx == 1 else 0.24))
			var segment_end: Vector3
			if is_thumb:
				segment_end = segment_start + Vector3(sf * length * 0.70, -length * 0.70, -0.004 - phalanx * 0.003)
			else:
				var curl := 0.008 * float(phalanx)
				segment_end = segment_start + Vector3(sf * base_x * 0.05, -length, -curl)
			_add_mesh(hand, root, "BoneFinger%s_%02d_%02d" % [side_name, digit + 1, phalanx + 1], _bone_mesh(segment_start, segment_end, 0.0058 - phalanx * 0.0007, 0.0095 - phalanx * 0.0008, Vector3(0, 0, -0.003), 7), materials.bone_light if phalanx == 2 else materials.bone)
			segment_start = segment_end


func _build_leg(leg: Node3D, root: Node3D, side: int) -> void:
	var sf := float(side)
	var side_name := "L" if side < 0 else "R"
	_add_mesh(leg, root, "BoneHipHead%s" % side_name, _sphere(22, 12), materials.bone_light, Vector3.ZERO, Vector3.ZERO, Vector3(0.092, 0.088, 0.088))
	_add_mesh(leg, root, "BoneFemurNeck%s" % side_name, _bone_mesh(Vector3.ZERO, Vector3(sf * 0.035, -0.055, 0.006), 0.022, 0.041, Vector3(sf * 0.008, 0, 0), 11), materials.bone)
	_add_mesh(leg, root, "BoneFemur%s" % side_name, _bone_mesh(Vector3(sf * 0.035, -0.045, 0.006), Vector3(sf * 0.012, -0.390, 0.012), 0.031, 0.064, Vector3(sf * 0.020, 0, -0.008), 15), materials.bone)
	_add_mesh(leg, root, "BoneFemurLineaAspera%s" % side_name, _bone_mesh(Vector3(sf * 0.020, -0.10, 0.030), Vector3(sf * 0.016, -0.325, 0.038), 0.006, 0.009, Vector3(sf * 0.004, 0, 0), 7), materials.bone_dark)

	var knee := _new_pivot(leg, root, "Knee%sPivot" % side_name, Vector3(sf * 0.012, -0.390, 0.012), Vector3(3, 0, sf * -2))
	_add_mesh(knee, root, "BoneKneeCondyle%s" % side_name, _sphere(20, 10), materials.bone, Vector3.ZERO, Vector3.ZERO, Vector3(0.104, 0.078, 0.080))
	_add_mesh(knee, root, "BonePatella%s" % side_name, _sphere(18, 9), materials.bone_light, Vector3(0, -0.002, -0.052), Vector3(-12, 0, 0), Vector3(0.060, 0.070, 0.032))
	_add_mesh(knee, root, "BoneTibia%s" % side_name, _bone_mesh(Vector3(sf * -0.014, -0.018, -0.008), Vector3(sf * -0.012, -0.408, -0.004), 0.025, 0.051, Vector3(sf * -0.010, 0, -0.012), 14), materials.bone)
	_add_mesh(knee, root, "BoneTibialCrest%s" % side_name, _bone_mesh(Vector3(sf * -0.006, -0.065, -0.040), Vector3(sf * -0.010, -0.325, -0.025), 0.0055, 0.009, Vector3(0, 0, -0.005), 7), materials.bone_light)
	_add_mesh(knee, root, "BoneFibula%s" % side_name, _bone_mesh(Vector3(sf * 0.052, -0.035, 0.006), Vector3(sf * 0.045, -0.410, 0.012), 0.013, 0.029, Vector3(sf * 0.012, 0, 0.010), 10), materials.bone_dark)

	var ankle := _new_pivot(knee, root, "Ankle%sPivot" % side_name, Vector3(0, -0.410, -0.004), Vector3(-3, sf * 2, 0))
	_add_mesh(ankle, root, "BoneAnkle%sTalus" % side_name, _sphere(18, 9), materials.bone, Vector3(0, -0.030, -0.018), Vector3.ZERO, Vector3(0.100, 0.075, 0.090))
	_build_foot(ankle, root, side)


func _build_foot(foot: Node3D, root: Node3D, side: int) -> void:
	var side_name := "L" if side < 0 else "R"
	_add_mesh(foot, root, "BoneFoot%sCalcaneus" % side_name, _sphere(18, 9), materials.bone_dark, Vector3(0, -0.070, 0.050), Vector3(-10, 0, 0), Vector3(0.105, 0.090, 0.135))
	_add_mesh(foot, root, "BoneFoot%sNavicular" % side_name, _sphere(14, 7), materials.bone, Vector3(0, -0.077, -0.045), Vector3.ZERO, Vector3(0.093, 0.055, 0.070))
	for tarsal in range(3):
		_add_mesh(foot, root, "BoneFoot%sCuneiform%02d" % [side_name, tarsal + 1], _sphere(12, 6), materials.bone if tarsal != 1 else materials.bone_dark, Vector3(-0.034 + tarsal * 0.034, -0.087, -0.082), Vector3(0, tarsal * 14, 0), Vector3(0.038, 0.043, 0.052))

	var toe_x := [-0.052, -0.027, 0.0, 0.028, 0.053]
	var toe_lengths := [0.105, 0.092, 0.084, 0.075, 0.064]
	var phalanx_counts := [2, 3, 3, 3, 3]
	for digit in range(5):
		var x: float = toe_x[digit]
		var met_start := Vector3(x * 0.70, -0.088, -0.080)
		var met_end := Vector3(x, -0.118 - absf(x) * 0.10, -0.195 + absf(x) * 0.10)
		_add_mesh(foot, root, "BoneFoot%sMetatarsal%02d" % [side_name, digit + 1], _bone_mesh(met_start, met_end, 0.0085, 0.015, Vector3(0, 0.006, -0.005), 8), materials.bone)
		var segment_start := met_end
		for phalanx in range(phalanx_counts[digit]):
			var fraction := 0.48 if phalanx == 0 else (0.31 if phalanx == 1 else 0.21)
			var segment_end := segment_start + Vector3(x * 0.025, -0.006 - phalanx * 0.002, -toe_lengths[digit] * fraction)
			_add_mesh(foot, root, "BoneToe%s_%02d_%02d" % [side_name, digit + 1, phalanx + 1], _bone_mesh(segment_start, segment_end, 0.0054 - phalanx * 0.0007, 0.0090 - phalanx * 0.0007, Vector3(0, 0.002, -0.002), 7), materials.bone_light if digit == 0 else materials.bone)
			segment_start = segment_end
