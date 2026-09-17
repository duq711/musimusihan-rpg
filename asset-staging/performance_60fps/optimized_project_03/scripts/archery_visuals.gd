extends RefCounted
class_name ArcheryVisuals

const OAK_TEXTURE: Texture2D = preload("res://assets/ai/materials/ancient_oak.png")
const IRON_TEXTURE: Texture2D = preload("res://assets/ai/materials/pitted_black_iron.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const LIMB_POINTS := [
	Vector3(0, 0.065, 0.015),
	Vector3(0, 0.20, -0.075),
	Vector3(0, 0.36, -0.14),
	Vector3(0, 0.49, -0.115),
	Vector3(0, 0.585, -0.005),
	Vector3(0, 0.62, 0.12),
]


static func create_bow() -> Node3D:
	var bow := Node3D.new()
	bow.name = "HuntingBow"
	var wood := AGED_SURFACES.old_oak(Color(0.50, 0.43, 0.32), 2.8)
	var leather := AGED_SURFACES.leather(Color(0.105, 0.103, 0.089))
	var string_material := AGED_SURFACES.linen(Color(0.46, 0.41, 0.31))
	var iron := AGED_SURFACES.bone(Color(0.49, 0.45, 0.33))
	for side in [-1, 1]:
		for index in range(LIMB_POINTS.size() - 1):
			var radius := lerpf(0.027, 0.011, float(index) / (LIMB_POINTS.size() - 2))
			var limb := _cylinder(radius * 0.84, radius, 1.0, wood)
			limb.name = "Limb_%d_%d" % [side, index]
			limb.visible = false
			bow.add_child(limb)
		var smooth_limb := MeshInstance3D.new()
		smooth_limb.name = "SmoothBentOakLimb_%d" % side
		smooth_limb.material_override = wood
		bow.add_child(smooth_limb)
		var string_segment := _cylinder(0.0028, 0.0028, 1.0, string_material)
		string_segment.name = "String_%d" % side
		bow.add_child(string_segment)
		var tip := _cylinder(0.013, 0.013, 0.044, iron)
		tip.name = "Tip_%d" % side
		bow.add_child(tip)
		for wrap_index in 3:
			var tip_binding := _cylinder(0.015, 0.015, 0.004, string_material)
			tip_binding.name = "HornNockBinding%d" % wrap_index
			tip_binding.position.y = -0.014 + float(wrap_index) * 0.012
			tip.add_child(tip_binding)
	var grip := _cylinder(0.033, 0.033, 0.17, leather)
	grip.name = "LeatherGrip"
	grip.scale.z = 0.83
	bow.add_child(grip)
	for index in range(7):
		var binding := _cylinder(0.0345, 0.0345, 0.008, leather)
		binding.name = "GripBinding%d" % index
		binding.position.y = -0.068 + index * 0.022
		binding.scale.z = 0.83
		bow.add_child(binding)
	var nocked_arrow := create_arrow()
	nocked_arrow.name = "NockedArrow"
	bow.add_child(nocked_arrow)
	set_bow_draw(bow, 0.0)
	return bow


static func set_bow_draw(bow: Node3D, ratio: float) -> void:
	if not is_instance_valid(bow):
		return
	var draw := clampf(ratio, 0.0, 1.0)
	# Pose coordinates are local to the bow. Moving/rotating the complete
	# weapon does not require resubmitting an identical draw pose.
	if bow.has_meta("last_bow_art_draw") and float(bow.get_meta("last_bow_art_draw")) == draw:
		return
	var changed_shape := not bow.has_meta("last_bow_art_draw") or not is_equal_approx(float(bow.get_meta("last_bow_art_draw", -1.0)), draw)
	bow.set_meta("last_bow_art_draw", draw)
	var string_center := Vector3(0, 0.05, lerpf(0.12, 0.40, draw))
	for side in [-1, 1]:
		if changed_shape:
			var smooth_limb := bow.get_node_or_null("SmoothBentOakLimb_%d" % side) as MeshInstance3D
			if smooth_limb != null:
				smooth_limb.mesh = _smooth_limb_mesh(side, draw)
		for index in range(LIMB_POINTS.size() - 1):
			var limb := bow.get_node_or_null("Limb_%d_%d" % [side, index]) as MeshInstance3D
			if limb != null:
				_set_segment(limb, _limb_point(index, side, draw), _limb_point(index + 1, side, draw))
		var tip_position := _limb_point(LIMB_POINTS.size() - 1, side, draw)
		var string_segment := bow.get_node_or_null("String_%d" % side) as MeshInstance3D
		if string_segment != null:
			_set_segment(string_segment, string_center, tip_position)
		var tip := bow.get_node_or_null("Tip_%d" % side) as Node3D
		if tip != null:
			tip.position = tip_position
	var arrow := bow.get_node_or_null("NockedArrow") as Node3D
	if arrow != null:
		# The rear nock stays on the pulled string; the iron point faces local -Z.
		arrow.position = string_center + Vector3(0, 0, -0.80)


static func _smooth_limb_mesh(side: int, draw: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 30:
		var t0 := float(step) / 30.0
		var t1 := float(step + 1) / 30.0
		for radial in 10:
			var angle0 := float(radial) / 10.0 * TAU
			var angle1 := float(radial + 1) / 10.0 * TAU
			var a := _smooth_limb_vertex(t0, angle0, side, draw)
			var b := _smooth_limb_vertex(t0, angle1, side, draw)
			var c := _smooth_limb_vertex(t1, angle1, side, draw)
			var d := _smooth_limb_vertex(t1, angle0, side, draw)
			for vertex in [a, c, b, a, d, c]:
				surface.set_uv(Vector2(vertex.x, vertex.y))
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()


static func _smooth_limb_vertex(t: float, angle: float, side: int, draw: float) -> Vector3:
	var center := _smooth_limb_center(t, side, draw)
	var tangent := (_smooth_limb_center(minf(1.0, t + 0.005), side, draw) - _smooth_limb_center(maxf(0.0, t - 0.005), side, draw)).normalized()
	var orientation := Basis(Quaternion(Vector3.UP, tangent))
	var radius := lerpf(0.033, 0.013, t)
	return center + orientation * Vector3(cos(angle) * radius * 0.68, 0.0, sin(angle) * radius * 0.44)


static func _smooth_limb_center(t: float, side: int, draw: float) -> Vector3:
	var at := clampf(t, 0.0, 1.0) * float(LIMB_POINTS.size() - 1)
	var index := mini(int(at), LIMB_POINTS.size() - 2)
	var local := at - float(index)
	var p1 := _limb_point(index, side, draw)
	var p2 := _limb_point(index + 1, side, draw)
	var p0 := _limb_point(index - 1, side, draw) if index > 0 else p1 * 2.0 - p2
	var p3 := _limb_point(index + 2, side, draw) if index + 2 < LIMB_POINTS.size() else p2 * 2.0 - p1
	return p1.cubic_interpolate(p2, p0, p3, local)


static func create_arrow() -> Node3D:
	var arrow := Node3D.new()
	arrow.name = "ArrowVisual"
	var wood := AGED_SURFACES.old_oak(Color(0.56, 0.52, 0.42), 3.0)
	var iron := AGED_SURFACES.pitted_iron(Color(0.52, 0.54, 0.52), 4.0)
	var feather := AGED_SURFACES.linen(Color(0.48, 0.46, 0.40), 8.0)
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shaft := _cylinder(0.007, 0.007, 0.69, wood)
	shaft.name = "WoodenShaft"
	shaft.rotation.x = PI / 2.0
	shaft.position.z = 0.445
	arrow.add_child(shaft)
	var point := _cylinder(0.0, 0.026, 0.12, iron)
	point.name = "IronArrowhead"
	var point_surface := SurfaceTool.new()
	point_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip_vertex := Vector3.ZERO
	var left_vertex := Vector3(-0.026, 0.0, 0.115)
	var right_vertex := Vector3(0.026, 0.0, 0.115)
	var rear_vertex := Vector3(0.0, 0.0, 0.096)
	for side in [-1.0, 1.0]:
		var ridge := Vector3(0.0, side * 0.004, 0.072)
		for vertex in [tip_vertex, left_vertex, ridge, left_vertex, rear_vertex, ridge, rear_vertex, right_vertex, ridge, right_vertex, tip_vertex, ridge] if side < 0.0 else [tip_vertex, ridge, left_vertex, left_vertex, ridge, rear_vertex, rear_vertex, ridge, right_vertex, right_vertex, ridge, tip_vertex]:
			point_surface.add_vertex(vertex)
	point_surface.generate_normals()
	point.mesh = point_surface.commit()
	arrow.add_child(point)
	var collar := _cylinder(0.012, 0.012, 0.042, iron)
	collar.name = "ArrowheadSocket"
	collar.rotation.x = PI / 2.0
	collar.position.z = 0.125
	arrow.add_child(collar)
	for index in range(3):
		var vane := MeshInstance3D.new()
		vane.name = "Fletching%d" % index
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for barb in 20:
			var t := float(barb) / 20.0
			var width := pow(sin((0.08 + t * 0.84) * PI), 0.7) * 0.037
			var z := 0.60 + t * 0.18
			for vertex in [Vector3(0.005, 0.0, z), Vector3(width, 0.002 * sin(float(barb)), z + 0.017), Vector3(0.005, 0.0, z + 0.008)]:
				surface.set_uv(Vector2(vertex.x * 12.0, vertex.z * 8.0))
				surface.add_vertex(vertex)
		surface.generate_normals()
		vane.mesh = surface.commit()
		vane.material_override = feather
		vane.rotation.z = index * TAU / 3.0
		arrow.add_child(vane)
	var nock := _cylinder(0.009, 0.009, 0.022, feather)
	nock.name = "StringNock"
	nock.rotation.x = PI / 2.0
	nock.position.z = 0.789
	arrow.add_child(nock)
	for z in [0.132, 0.602, 0.776]:
		var binding := _cylinder(0.011, 0.011, 0.009, AGED_SURFACES.linen(Color(0.35, 0.30, 0.20)))
		binding.name = "SinewBinding"
		binding.position.z = z
		binding.rotation.x = PI * 0.5
		arrow.add_child(binding)
	return arrow


static func _limb_point(index: int, side: int, draw: float) -> Vector3:
	var point: Vector3 = LIMB_POINTS[index]
	var leverage := float(index) / (LIMB_POINTS.size() - 1)
	point.y = (point.y - 0.045 * draw * leverage * leverage) * side
	point.z += 0.075 * draw * leverage * leverage
	return point


static func _set_segment(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	mesh.position = (from + to) * 0.5
	mesh.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	mesh.scale = Vector3(1, direction.length(), 1)


static func _cylinder(top_radius: float, bottom_radius: float, height_value: float, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height_value
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _material(color: Color, roughness: float, metallic := 0.0, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if texture != null:
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * 3.0
	return material
