extends RefCounted
class_name SwordClashGeometry

const SAT_EPSILON := 0.000001


static func blade_proxy(blade_mesh: MeshInstance3D) -> Dictionary:
	if blade_mesh == null or blade_mesh.mesh == null or not blade_mesh.is_inside_tree():
		return {}
	var bounds := blade_mesh.get_aabb()
	if bounds.size.length_squared() <= SAT_EPSILON:
		return {}

	var basis := blade_mesh.global_transform.basis
	var scale_x := basis.x.length()
	var scale_y := basis.y.length()
	var scale_z := basis.z.length()
	if minf(scale_x, minf(scale_y, scale_z)) <= SAT_EPSILON:
		return {}

	return {
		"center": blade_mesh.to_global(bounds.get_center()),
		"axes": PackedVector3Array([
			basis.x / scale_x,
			basis.y / scale_y,
			basis.z / scale_z,
		]),
		"half_extents": Vector3(
			bounds.size.x * scale_x * 0.5,
			bounds.size.y * scale_y * 0.5,
			bounds.size.z * scale_z * 0.5
		),
	}


static func proxies_overlap(first: Dictionary, second: Dictionary, margin := 0.02) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	var first_axes: PackedVector3Array = first.get("axes", PackedVector3Array())
	var second_axes: PackedVector3Array = second.get("axes", PackedVector3Array())
	if first_axes.size() != 3 or second_axes.size() != 3:
		return false
	var first_center: Vector3 = first.get("center", Vector3.ZERO)
	var second_center: Vector3 = second.get("center", Vector3.ZERO)
	var first_extents: Vector3 = first.get("half_extents", Vector3.ZERO)
	var second_extents: Vector3 = second.get("half_extents", Vector3.ZERO)
	if first_extents.x < 0.0 or first_extents.y < 0.0 or first_extents.z < 0.0:
		return false
	if second_extents.x < 0.0 or second_extents.y < 0.0 or second_extents.z < 0.0:
		return false
	var half_margin := maxf(0.0, margin) * 0.5
	first_extents += Vector3.ONE * half_margin
	second_extents += Vector3.ONE * half_margin

	var rotation := PackedFloat64Array()
	var absolute_rotation := PackedFloat64Array()
	rotation.resize(9)
	absolute_rotation.resize(9)
	for first_axis_index in range(3):
		for second_axis_index in range(3):
			var matrix_index := first_axis_index * 3 + second_axis_index
			rotation[matrix_index] = first_axes[first_axis_index].dot(second_axes[second_axis_index])
			absolute_rotation[matrix_index] = absf(rotation[matrix_index]) + SAT_EPSILON

	var world_translation := second_center - first_center
	var local_translation := Vector3(
		world_translation.dot(first_axes[0]),
		world_translation.dot(first_axes[1]),
		world_translation.dot(first_axes[2])
	)

	# The six face normals of both oriented blade boxes.
	for first_axis_index in range(3):
		var first_radius := _component(first_extents, first_axis_index)
		var second_radius := 0.0
		for second_axis_index in range(3):
			second_radius += _component(second_extents, second_axis_index) * absolute_rotation[first_axis_index * 3 + second_axis_index]
		if absf(_component(local_translation, first_axis_index)) > first_radius + second_radius:
			return false
	for second_axis_index in range(3):
		var first_radius := 0.0
		for first_axis_index in range(3):
			first_radius += _component(first_extents, first_axis_index) * absolute_rotation[first_axis_index * 3 + second_axis_index]
		var second_radius := _component(second_extents, second_axis_index)
		var projected_translation := 0.0
		for first_axis_index in range(3):
			projected_translation += _component(local_translation, first_axis_index) * rotation[first_axis_index * 3 + second_axis_index]
		if absf(projected_translation) > first_radius + second_radius:
			return false

	# The remaining nine axes are the pairwise cross products of box axes.
	for first_axis_index in range(3):
		var first_next := (first_axis_index + 1) % 3
		var first_last := (first_axis_index + 2) % 3
		for second_axis_index in range(3):
			var second_next := (second_axis_index + 1) % 3
			var second_last := (second_axis_index + 2) % 3
			var first_radius := (
				_component(first_extents, first_next) * absolute_rotation[first_last * 3 + second_axis_index]
				+ _component(first_extents, first_last) * absolute_rotation[first_next * 3 + second_axis_index]
			)
			var second_radius := (
				_component(second_extents, second_next) * absolute_rotation[first_axis_index * 3 + second_last]
				+ _component(second_extents, second_last) * absolute_rotation[first_axis_index * 3 + second_next]
			)
			var projected_translation := absf(
				_component(local_translation, first_last) * rotation[first_next * 3 + second_axis_index]
				- _component(local_translation, first_next) * rotation[first_last * 3 + second_axis_index]
			)
			if projected_translation > first_radius + second_radius:
				return false
	return true


static func _component(vector: Vector3, axis_index: int) -> float:
	match axis_index:
		0:
			return vector.x
		1:
			return vector.y
		_:
			return vector.z
