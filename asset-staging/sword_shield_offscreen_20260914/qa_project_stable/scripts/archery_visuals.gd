extends RefCounted
class_name ArcheryVisuals

const OAK_TEXTURE: Texture2D = preload("res://assets/ai/materials/ancient_oak.png")
const IRON_TEXTURE: Texture2D = preload("res://assets/ai/materials/pitted_black_iron.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const BOW_GRIP := Vector3.ZERO
const ARROW_REST := Vector3(0.0, 0.105, 0.018)
const ARROW_NOCK_LOCAL := Vector3(0.0, 0.0, 0.80)
const STRING_REST_Z := 0.12
const STRING_DRAW_Z := 0.64
const STRING_DRAW_TRAVEL := STRING_DRAW_Z - STRING_REST_Z
const STRING_LENGTH := 1.24
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
		var string_segment := _cylinder(0.0016, 0.0016, 1.0, string_material)
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
	# Real contact frames are shared with the articulated player hands. They
	# remain bow-local through world/viewmodel transforms and draw cancellation.
	_contact(bow, "BowGrip", BOW_GRIP)
	_contact(bow, "StringGrip", Vector3(0.0, ARROW_REST.y, STRING_REST_Z))
	_contact(bow, "ArrowRest", ARROW_REST)
	var rest := MeshInstance3D.new()
	rest.name = "CarvedArrowRest"
	var rest_mesh := BoxMesh.new()
	rest_mesh.size = Vector3(0.047, 0.011, 0.026)
	rest.mesh = rest_mesh
	rest.material_override = iron
	rest.position = Vector3(0.020, 0.095, ARROW_REST.z)
	bow.add_child(rest)
	var nocked_arrow := create_arrow()
	nocked_arrow.name = "NockedArrow"
	bow.add_child(nocked_arrow)
	set_bow_draw(bow, 0.0)
	return bow


static func set_bow_draw(bow: Node3D, ratio: float) -> void:
	if not is_instance_valid(bow) or not is_finite(ratio):
		return
	var draw := clampf(ratio, 0.0, 1.0)
	# Pose coordinates are local to the bow. Moving/rotating the complete
	# weapon does not require resubmitting an identical draw pose.
	if bow.has_meta("last_bow_art_draw") and float(bow.get_meta("last_bow_art_draw")) == draw:
		return
	var changed_shape := not bow.has_meta("last_bow_art_draw") or not is_equal_approx(float(bow.get_meta("last_bow_art_draw", -1.0)), draw)
	bow.set_meta("last_bow_art_draw", draw)
	var string_center := Vector3(0, ARROW_REST.y, lerpf(STRING_REST_Z, STRING_DRAW_Z, draw))
	var string_grip := bow.get_node_or_null("StringGrip") as Marker3D
	if string_grip != null:
		string_grip.position = string_center
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
			tip.quaternion = Quaternion(Vector3.UP, (tip_position - _limb_point(LIMB_POINTS.size() - 2, side, draw)).normalized())
	var arrow := bow.get_node_or_null("NockedArrow") as Node3D
	if arrow != null:
		# The rear nock stays on the pulled string; the iron point faces local -Z.
		arrow.position = string_center - ARROW_NOCK_LOCAL


static func bow_hand_anchors(bow: Node3D) -> Dictionary:
	if not is_instance_valid(bow):
		return {}
	var grip := bow.get_node_or_null("BowGrip") as Marker3D
	var string := bow.get_node_or_null("StringGrip") as Marker3D
	var rest := bow.get_node_or_null("ArrowRest") as Marker3D
	if grip == null or string == null or rest == null:
		return {}
	return {"grip": grip.position, "string": string.position, "arrow_rest": rest.position, "arrow_forward": Vector3.FORWARD}


static func _contact(parent: Node3D, marker_name: String, at: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	parent.add_child(marker)


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
	var feather := AGED_SURFACES.linen(Color(0.29, 0.27, 0.23), 8.0)
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shaft := _cylinder(0.0042, 0.0042, 0.71, wood)
	shaft.name = "WoodenShaft"
	shaft.rotation.x = PI / 2.0
	shaft.position.z = 0.435
	arrow.add_child(shaft)
	var point := _cylinder(0.0, 0.026, 0.12, iron)
	point.name = "IronArrowhead"
	var point_surface := SurfaceTool.new()
	point_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip_vertex := Vector3.ZERO
	var left_vertex := Vector3(-0.016, 0.0, 0.082)
	var right_vertex := Vector3(0.016, 0.0, 0.082)
	var rear_vertex := Vector3(0.0, 0.0, 0.074)
	for side in [-1.0, 1.0]:
		var ridge := Vector3(0.0, side * 0.003, 0.052)
		for vertex in [tip_vertex, left_vertex, ridge, left_vertex, rear_vertex, ridge, rear_vertex, right_vertex, ridge, right_vertex, tip_vertex, ridge] if side < 0.0 else [tip_vertex, ridge, left_vertex, left_vertex, ridge, rear_vertex, rear_vertex, ridge, right_vertex, right_vertex, ridge, tip_vertex]:
			point_surface.add_vertex(vertex)
	point_surface.generate_normals()
	point.mesh = point_surface.commit()
	arrow.add_child(point)
	var collar := _cylinder(0.0065, 0.0065, 0.025, iron)
	collar.name = "ArrowheadSocket"
	collar.rotation.x = PI / 2.0
	collar.position.z = 0.086
	arrow.add_child(collar)
	for index in range(3):
		var vane := MeshInstance3D.new()
		vane.name = "Fletching%d" % index
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for barb in 26:
			var t := float(barb) / 26.0
			var width := pow(sin((0.08 + t * 0.84) * PI), 0.7) * 0.016
			var z := 0.627 + t * 0.14
			for vertex in [Vector3(0.0038, 0.0, z), Vector3(width, 0.0007 * sin(float(barb)), z + 0.012), Vector3(0.0038, 0.0, z + 0.005)]:
				surface.set_uv(Vector2(vertex.x * 12.0, vertex.z * 8.0))
				surface.add_vertex(vertex)
		surface.generate_normals()
		vane.mesh = surface.commit()
		vane.material_override = feather
		vane.rotation.z = index * TAU / 3.0
		arrow.add_child(vane)
	var nock := Node3D.new()
	nock.name = "StringNock"
	arrow.add_child(nock)
	var nock_base := _cylinder(0.0056, 0.0056, 0.010, feather)
	nock_base.name = "HornNockBase"
	nock_base.rotation.x = PI / 2.0
	nock_base.position.z = 0.784
	nock.add_child(nock_base)
	# The string sits between two short horn cheeks instead of penetrating a
	# solid cylinder. Its exact rear contact remains 0.8m from the arrow tip.
	for side in [-1, 1]:
		var cheek := _cylinder(0.0024, 0.0024, 0.012, feather)
		cheek.name = "NockCheek_%d" % side
		cheek.rotation.x = PI / 2.0
		cheek.position = Vector3(side * 0.0042, 0.0, 0.794)
		nock.add_child(cheek)
	_contact(arrow, "ArrowNock", ARROW_NOCK_LOCAL)
	for z in [0.094, 0.628, 0.775]:
		var binding := _cylinder(0.0057, 0.0057, 0.006, AGED_SURFACES.linen(Color(0.35, 0.30, 0.20)))
		binding.name = "SinewBinding"
		binding.position.z = z
		binding.rotation.x = PI * 0.5
		arrow.add_child(binding)
	return arrow


static func _limb_point(index: int, side: int, draw: float) -> Vector3:
	var point: Vector3 = LIMB_POINTS[index]
	var leverage := float(index) / (LIMB_POINTS.size() - 1)
	# For a 1.24m cord, the two limb tips are the foci of an ellipse. This
	# solves their backward flex from the real nock travel without stretching
	# the string as the right hand pulls to the wider full-draw target pose.
	var half_cord := STRING_LENGTH * 0.5
	var tip_height := half_cord - 0.095 * draw * draw
	var depth_gap := sqrt(maxf(0.0, half_cord * half_cord - tip_height * tip_height)) * sqrt(1.0 - ARROW_REST.y * ARROW_REST.y / (half_cord * half_cord))
	var tip_depth := lerpf(STRING_REST_Z, STRING_DRAW_Z, draw) - depth_gap
	point.y = (point.y - 0.095 * draw * draw * leverage * leverage) * side
	point.z += (tip_depth - STRING_REST_Z) * leverage * leverage
	if side > 0:
		# A small carved riser offset gives the centred arrow actual clearance
		# above the wrapped grip; the string and aiming axis stay on local -Z.
		point.x += 0.045 * pow(1.0 - leverage, 3.0)
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
