extends RefCounted
## Instance-local flexible cuff. Imported hand skin, source meshes and all
## contact transforms remain untouched. Only marked, unskinned cuffs opt in.

var enabled := false
var blend_start_z := 0.0
var blend_end_z := 0.0
var update_count := 0
var minimum_jacobian_determinant := 1.0
var invalid_vertex_count := 0
var minimum_inner_scale := 1.0
var _rest_wrist := Vector3.ZERO
var _surfaces: Array[Dictionary] = []
var _meshes: Array[Dictionary] = []
var _forearm_fit := Transform3D.IDENTITY
var _has_fit := false
var _headless := false


func setup(adapter: Node3D, cuff: Node3D, rest_wrist: Vector3) -> bool:
	# glTF imports custom node properties inside the "extras" dictionary.
	# Direct metadata remains supported for explicitly constructed scene nodes.
	var properties: Dictionary = {}
	var imported_extras: Variant = cuff.get_meta("extras", {})
	if imported_extras is Dictionary:
		properties = imported_extras
	if int(cuff.get_meta("wrist_flex_version", properties.get("wrist_flex_version", 0))) != 1:
		return false
	blend_start_z = float(cuff.get_meta("wrist_flex_start_z", properties.get("wrist_flex_start_z", NAN)))
	blend_end_z = float(cuff.get_meta("wrist_flex_end_z", properties.get("wrist_flex_end_z", NAN)))
	if not is_finite(blend_start_z) or not is_finite(blend_end_z) or blend_end_z - blend_start_z < 0.01:
		return false
	if not rest_wrist.is_finite() or rest_wrist.z <= blend_start_z or rest_wrist.z >= blend_end_z:
		return false
	_rest_wrist = rest_wrist
	var candidates: Array[MeshInstance3D] = []
	_collect(cuff, candidates)
	if candidates.is_empty():
		return false
	for part: MeshInstance3D in candidates:
		var source := part.mesh as ArrayMesh
		if source == null or part.skin != null or source.get_blend_shape_count() != 0:
			return false
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if vertices.is_empty() or normals.size() != vertices.size() or source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return false
	_headless = DisplayServer.get_name() == "headless"
	for part: MeshInstance3D in candidates:
		var source := part.mesh as ArrayMesh
		var runtime := ArrayMesh.new()
		runtime.resource_name = source.resource_name + "_Runtime"
		var from_mesh := _relative_transform(part, adapter)
		var indices: Array[int] = []
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents := PackedFloat32Array()
			if arrays[Mesh.ARRAY_TANGENT] != null:
				tangents = arrays[Mesh.ARRAY_TANGENT]
			if tangents.size() != vertices.size() * 4:
				tangents.resize(vertices.size() * 4)
				for index in vertices.size():
					var normal := normals[index].normalized()
					var tangent := (Vector3.FORWARD if absf(normal.z) < 0.9 else Vector3.UP).cross(normal).normalized()
					for axis in 3:
						tangents[index * 4 + axis] = tangent[axis]
					tangents[index * 4 + 3] = 1.0
			arrays[Mesh.ARRAY_TANGENT] = tangents
			var weights := PackedFloat32Array()
			weights.resize(vertices.size())
			for index in vertices.size():
				weights[index] = _rotation_progress(clampf(((from_mesh * vertices[index]).z - blend_start_z) / (blend_end_z - blend_start_z), 0.0, 1.0), blend_end_z - blend_start_z).x
			runtime.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
			runtime.surface_set_material(surface, source.surface_get_material(surface))
			runtime.surface_set_name(surface, source.surface_get_name(surface))
			var format := runtime.surface_get_format(surface)
			var record := {"mesh": part, "runtime": runtime, "surface": surface, "source": source, "arrays": arrays, "rest_vertices": vertices, "rest_normals": normals, "rest_tangents": tangents, "current_vertices": vertices, "current_normals": normals, "mesh_to_adapter": from_mesh, "weights": weights, "normal_offset": RenderingServer.mesh_surface_get_format_offset(format, vertices.size(), Mesh.ARRAY_NORMAL), "tangent_offset": RenderingServer.mesh_surface_get_format_offset(format, vertices.size(), Mesh.ARRAY_TANGENT), "normal_stride": RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertices.size())}
			indices.append(_surfaces.size())
			_surfaces.append(record)
		_meshes.append({"mesh": part, "source": source, "runtime": runtime, "surfaces": indices})
		part.mesh = runtime
	enabled = true
	apply_fit(Transform3D.IDENTITY)
	return true


static func _collect(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, output)


static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var current := node.get_parent()
	while current != ancestor and current != null:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func apply_fit(fitted: Transform3D) -> void:
	if not enabled or not fitted.is_finite() or (_has_fit and fitted.is_equal_approx(_forearm_fit)):
		return
	_forearm_fit = fitted
	_has_fit = true
	update_count += 1
	minimum_jacobian_determinant = INF
	invalid_vertex_count = 0
	minimum_inner_scale = 1.0
	var rotation := fitted.basis.orthonormalized().get_rotation_quaternion().normalized()
	if rotation.w < 0.0:
		rotation = -rotation
	var angle := rotation.get_angle()
	var axis := rotation.get_axis() if absf(angle) > 0.000001 else Vector3.RIGHT
	var bend_direction := Vector3(-axis.y, axis.x, 0.0).normalized()
	var section_cache := {}
	for record: Dictionary in _surfaces:
		var rest: PackedVector3Array = record.rest_vertices
		var rest_normals: PackedVector3Array = record.rest_normals
		var rest_tangents: PackedFloat32Array = record.rest_tangents
		var from_mesh: Transform3D = record.mesh_to_adapter
		var to_mesh := from_mesh.affine_inverse()
		var current := PackedVector3Array()
		var normals := PackedVector3Array()
		var tangents := PackedFloat32Array()
		current.resize(rest.size())
		normals.resize(rest.size())
		tangents.resize(rest.size() * 4)
		for index in rest.size():
			var point := from_mesh * rest[index]
			if not section_cache.has(point.z):
				section_cache[point.z] = _evaluate_section(point.z, fitted, rotation, axis, angle)
			var section: Dictionary = section_cache[point.z]
			var basis: Basis = section.basis
			var rest_radial := Vector3(point.x - _rest_wrist.x, point.y - _rest_wrist.y, 0.0)
			var inner := rest_radial.dot(bend_direction)
			var radial_slope := 1.0
			var radial_z_slope := 0.0
			if inner < 0.0:
				# An elastic bend shortens only the inside of the cuff. The outer
				# half and the width across the bend remain unchanged. This smooth
				# map has a positive spatial derivative even at steep wrist bends;
				# it is not a correction applied to an already inverted surface.
				var curvature := float(section.curvature)
				var denominator := sqrt(1.0 + curvature * curvature * inner * inner)
				var shortened := inner / denominator
				radial_slope = 1.0 / (denominator * denominator * denominator)
				radial_z_slope = -inner * inner * inner * curvature * float(section.curvature_derivative) * radial_slope
				rest_radial += bend_direction * (shortened - inner)
				minimum_inner_scale = minf(minimum_inner_scale, 1.0 / denominator)
			var radial := basis * rest_radial
			current[index] = to_mesh * ((section.center as Vector3) + radial)
			# Exact Jacobian includes axial stretch, rotating sections and the
			# changing elastic compression. Inverse-transpose normals therefore
			# stay attached to the evaluated surface, including at both seams.
			var jacobian := Basis(basis * (Vector3.RIGHT + bend_direction * bend_direction.x * (radial_slope - 1.0)), basis * (Vector3.UP + bend_direction * bend_direction.y * (radial_slope - 1.0)), (section.center_derivative as Vector3) + axis.cross(radial) * angle * float(section.derivative) + basis * bend_direction * radial_z_slope)
			var local_jacobian := to_mesh.basis * jacobian * from_mesh.basis
			var determinant := local_jacobian.determinant()
			minimum_jacobian_determinant = minf(minimum_jacobian_determinant, determinant)
			if not is_finite(determinant) or determinant <= 0.000001:
				invalid_vertex_count += 1
			# Keep invalid geometry observable to QA; never clamp the fit or flip
			# its determinant to make a folded cuff look numerically valid.
			if absf(determinant) > 0.000001:
				normals[index] = (local_jacobian.inverse().transposed() * rest_normals[index]).normalized()
			else:
				normals[index] = Vector3.ZERO
			var tangent := local_jacobian * Vector3(rest_tangents[index * 4], rest_tangents[index * 4 + 1], rest_tangents[index * 4 + 2])
			tangent = (tangent - normals[index] * normals[index].dot(tangent)).normalized()
			for component in 3:
				tangents[index * 4 + component] = tangent[component]
			tangents[index * 4 + 3] = rest_tangents[index * 4 + 3]
		record.current_vertices = current
		record.current_normals = normals
		var arrays: Array = record.arrays
		arrays[Mesh.ARRAY_VERTEX] = current
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		if not _headless:
			_update_vertex_buffer(record, current, normals, tangents)
	for item: Dictionary in _meshes:
		var runtime: ArrayMesh = item.runtime
		if _headless:
			# Godot's dummy mesh storage intentionally ignores region updates.
			# Preserve the exact same evaluated CPU geometry in headless tests.
			runtime.clear_surfaces()
			for index: int in item.surfaces:
				var record: Dictionary = _surfaces[index]
				runtime.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, record.arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
				runtime.surface_set_material(int(record.surface), (item.source as ArrayMesh).surface_get_material(int(record.surface)))
				runtime.surface_set_name(int(record.surface), (item.source as ArrayMesh).surface_get_name(int(record.surface)))
		var bounds := AABB()
		var first := true
		for index: int in item.surfaces:
			for point: Vector3 in _surfaces[index].current_vertices:
				if first:
					bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					bounds = bounds.expand(point)
		runtime.custom_aabb = bounds.grow(0.001)


static func _rotation_progress(t: float, span: float) -> Vector3:
	# A mostly uniform rotation spreads curvature across the authored sleeve.
	# Short quadratic ends make the section rotation stationary at each seam.
	var ease := minf(0.008 / span, 0.4)
	if t <= 0.0:
		return Vector3.ZERO
	if t >= 1.0:
		return Vector3(1.0, 0.0, 0.0)
	if t < ease:
		return Vector3(t * t / (2.0 * ease * (1.0 - ease)), t / (ease * (1.0 - ease)), 1.0 / (ease * (1.0 - ease)))
	if t > 1.0 - ease:
		var remaining := 1.0 - t
		return Vector3(1.0 - remaining * remaining / (2.0 * ease * (1.0 - ease)), remaining / (ease * (1.0 - ease)), -1.0 / (ease * (1.0 - ease)))
	return Vector3((t - ease * 0.5) / (1.0 - ease), 1.0 / (1.0 - ease), 0.0)


func _evaluate_section(z: float, fitted: Transform3D, rotation: Quaternion, axis: Vector3, angle: float) -> Dictionary:
	var native_center := Vector3(_rest_wrist.x, _rest_wrist.y, z)
	if z <= blend_start_z:
		return {"basis": Basis.IDENTITY, "center": native_center, "center_derivative": Vector3.BACK, "derivative": 0.0, "curvature": 0.0, "curvature_derivative": 0.0}
	if z >= blend_end_z:
		return {"basis": Basis(rotation), "center": fitted * native_center, "center_derivative": fitted.basis.z, "derivative": 0.0, "curvature": 0.0, "curvature_derivative": 0.0}
	var span := blend_end_z - blend_start_z
	var t := (z - blend_start_z) / span
	var progress := _rotation_progress(t, span)
	var derivative := progress.y / span
	var second_derivative := progress.z / (span * span)
	var basis := Basis(Quaternion.IDENTITY.slerp(rotation, progress.x))
	var scale_difference := fitted.basis.z.length() - 1.0
	var following_length := blend_end_z - _rest_wrist.z
	var power := span / following_length
	# Distribute arm length fitting across the transition without pulling its
	# center backward. Both position and axial derivative match the rigid ends.
	var axial := z - _rest_wrist.z + scale_difference * following_length * pow(t, power)
	var axial_derivative := 1.0 + scale_difference * pow(t, power - 1.0)
	var axial_second_derivative := scale_difference * (power - 1.0) * pow(t, power - 2.0) / span
	var center_offset := basis.z * axial
	var bend_rate := angle * Vector2(axis.x, axis.y).length()
	var curvature := bend_rate * derivative / axial_derivative
	var curvature_derivative := bend_rate * (second_derivative / axial_derivative - derivative * axial_second_derivative / (axial_derivative * axial_derivative))
	return {"basis": basis, "center": _rest_wrist + center_offset, "center_derivative": basis.z * axial_derivative + axis.cross(center_offset) * angle * derivative, "derivative": derivative, "curvature": curvature, "curvature_derivative": curvature_derivative}


static func _update_vertex_buffer(record: Dictionary, vertices: PackedVector3Array, normals: PackedVector3Array, tangents: PackedFloat32Array) -> void:
	var stride := int(record.normal_stride)
	var bytes := vertices.to_byte_array()
	bytes.resize(vertices.size() * (12 + stride))
	for index in vertices.size():
		var oct := normals[index].octahedron_encode() if normals[index].length_squared() > 0.0 else Vector2.ZERO
		_encode_oct(bytes, int(record.normal_offset) + index * stride, oct)
		var tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
		var tangent_oct := tangent.octahedron_encode() if tangent.length_squared() > 0.0 else Vector2.ZERO
		# Godot's uncompressed vertex format stores normal/tangent as oct16.
		tangent_oct.y = maxf(tangent_oct.y, 1.0 / 32767.0) * 0.5 + 0.5
		if tangents[index * 4 + 3] < 0.0:
			tangent_oct.y = 1.0 - tangent_oct.y
		var tx := clampi(int(tangent_oct.x * 65535.0), 0, 65535)
		var ty := clampi(int(tangent_oct.y * 65535.0), 0, 65535)
		if tx == 0 and ty == 65535:
			tx = 65535
		var offset := int(record.tangent_offset) + index * stride
		bytes.encode_u16(offset, tx)
		bytes.encode_u16(offset + 2, ty)
	(record.runtime as ArrayMesh).surface_update_vertex_region(int(record.surface), 0, bytes)


static func _encode_oct(bytes: PackedByteArray, offset: int, oct: Vector2) -> void:
	bytes.encode_u16(offset, clampi(int(oct.x * 65535.0), 0, 65535))
	bytes.encode_u16(offset + 2, clampi(int(oct.y * 65535.0), 0, 65535))


func source_mesh_for(part: MeshInstance3D) -> Mesh:
	for item: Dictionary in _meshes:
		if item.mesh == part:
			return item.source as Mesh
	return part.mesh


func get_snapshot() -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for record: Dictionary in _surfaces:
		surfaces.append({"mesh": record.mesh, "surface": record.surface, "mesh_to_adapter": record.mesh_to_adapter, "rest_vertices": record.rest_vertices, "current_vertices": record.current_vertices, "rest_normals": record.rest_normals, "current_normals": record.current_normals, "weights": record.weights})
	return {"enabled": enabled, "blend_start_z": blend_start_z, "blend_end_z": blend_end_z, "update_count": update_count, "minimum_jacobian_determinant": minimum_jacobian_determinant, "invalid_vertex_count": invalid_vertex_count, "minimum_inner_scale": minimum_inner_scale, "deformation": "elastic_inner_bend", "forearm_fit": _forearm_fit, "surfaces": surfaces}
