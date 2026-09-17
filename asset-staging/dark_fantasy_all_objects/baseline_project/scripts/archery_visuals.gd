extends RefCounted
class_name ArcheryVisuals

const OAK_TEXTURE: Texture2D = preload("res://assets/ai/materials/ancient_oak.png")
const IRON_TEXTURE: Texture2D = preload("res://assets/ai/materials/pitted_black_iron.png")
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
	var wood := _material(Color(0.62, 0.38, 0.16), 0.79, 0.0, OAK_TEXTURE)
	var leather := _material(Color(0.14, 0.075, 0.045), 0.96)
	var string_material := _material(Color(0.87, 0.76, 0.52), 0.92)
	var iron := _material(Color(0.30, 0.30, 0.29), 0.57, 0.8, IRON_TEXTURE)
	for side in [-1, 1]:
		for index in range(LIMB_POINTS.size() - 1):
			var radius := lerpf(0.027, 0.011, float(index) / (LIMB_POINTS.size() - 2))
			var limb := _cylinder(radius * 0.84, radius, 1.0, wood)
			limb.name = "Limb_%d_%d" % [side, index]
			bow.add_child(limb)
		var string_segment := _cylinder(0.0028, 0.0028, 1.0, string_material)
		string_segment.name = "String_%d" % side
		bow.add_child(string_segment)
		var tip := _cylinder(0.013, 0.013, 0.044, iron)
		tip.name = "Tip_%d" % side
		bow.add_child(tip)
	var grip := _cylinder(0.033, 0.033, 0.17, leather)
	grip.name = "LeatherGrip"
	grip.scale.z = 0.83
	bow.add_child(grip)
	for index in range(7):
		var binding := _cylinder(0.0345, 0.0345, 0.005, string_material)
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
	var string_center := Vector3(0, 0.05, lerpf(0.12, 0.40, draw))
	for side in [-1, 1]:
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


static func create_arrow() -> Node3D:
	var arrow := Node3D.new()
	arrow.name = "ArrowVisual"
	var wood := _material(Color(0.69, 0.46, 0.22), 0.85, 0.0, OAK_TEXTURE)
	var iron := _material(Color(0.42, 0.44, 0.47), 0.4, 0.87, IRON_TEXTURE)
	var feather := _material(Color(0.79, 0.72, 0.53), 0.96)
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shaft := _cylinder(0.007, 0.007, 0.69, wood)
	shaft.name = "WoodenShaft"
	shaft.rotation.x = PI / 2.0
	shaft.position.z = 0.445
	arrow.add_child(shaft)
	var point := _cylinder(0.0, 0.026, 0.12, iron)
	point.name = "IronArrowhead"
	point.rotation.x = -PI / 2.0
	point.position.z = 0.06
	point.scale.x = 0.65
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
		for vertex in [Vector3(0.004, 0, 0.60), Vector3(0.058, 0, 0.745), Vector3(0.004, 0, 0.78)]:
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
	mesh.radial_segments = 8
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
