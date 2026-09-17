extends RefCounted
## Bake static world-projected stone into one surface per existing culling
## tile. Authored placement, topology and material stay unchanged. Timber
## is deliberately kept instanced because its grain uses local coordinates.


static func merge(meshes: Array[ArrayMesh], batches: Dictionary, keys: Array[String]) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	var vertex_count := 0
	var index_count := 0
	var has_uv := false
	var has_uv2 := false
	var has_tangents := false
	var sources: Dictionary = {}
	for key in keys:
		var batch: Dictionary = batches[key]
		var source: ArrayMesh = meshes[int(batch.variant)]
		assert(source.get_surface_count() == 1, "Mine stone merging requires one production surface per variant")
		var arrays := source.surface_get_arrays(0)
		sources[key] = arrays
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		vertex_count += points.size() * batch.transforms.size()
		index_count += (source_indices.size() if not source_indices.is_empty() else points.size()) * batch.transforms.size()
		has_uv = has_uv or arrays[Mesh.ARRAY_TEX_UV] != null
		has_uv2 = has_uv2 or arrays[Mesh.ARRAY_TEX_UV2] != null
		has_tangents = has_tangents or arrays[Mesh.ARRAY_TANGENT] != null
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	indices.resize(index_count)
	if has_uv:
		uv.resize(vertex_count)
	if has_uv2:
		uv2.resize(vertex_count)
	if has_tangents:
		tangents.resize(vertex_count * 4)
	var vertex_cursor := 0
	var index_cursor := 0
	var instances: Array[Dictionary] = []
	var bounds := AABB()
	var first := true
	for key in keys:
		var batch: Dictionary = batches[key]
		var source: ArrayMesh = meshes[int(batch.variant)]
		var arrays: Array = sources[key]
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var source_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var source_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var source_uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var source_tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for instance_index in range(batch.transforms.size()):
			var transform_value: Transform3D = batch.transforms[instance_index]
			var normal_basis := transform_value.basis.inverse().transposed()
			var tint: Color = batch.colors[instance_index]
			var current_bounds: AABB = transform_value * source.get_aabb()
			bounds = current_bounds if first else bounds.merge(current_bounds)
			first = false
			var added_indices := source_indices.size() if not source_indices.is_empty() else points.size()
			instances.append({"key": key, "instance": instance_index, "vertex_start": vertex_cursor,
				"vertex_count": points.size(), "index_start": index_cursor, "index_count": added_indices})
			for i in range(points.size()):
				var at := vertex_cursor + i
				vertices[at] = transform_value * points[i]
				normals[at] = (normal_basis * source_normals[i]).normalized()
				colors[at] = tint * (source_colors[i] if not source_colors.is_empty() else Color.WHITE)
				if not source_uv.is_empty():
					uv[at] = source_uv[i]
				if not source_uv2.is_empty():
					uv2[at] = source_uv2[i]
				if not source_tangents.is_empty():
					var tangent := (transform_value.basis * Vector3(source_tangents[i * 4], source_tangents[i * 4 + 1], source_tangents[i * 4 + 2])).normalized()
					tangents[at * 4] = tangent.x
					tangents[at * 4 + 1] = tangent.y
					tangents[at * 4 + 2] = tangent.z
					tangents[at * 4 + 3] = source_tangents[i * 4 + 3] * signf(transform_value.basis.determinant())
			for i in range(added_indices):
				indices[index_cursor + i] = vertex_cursor + (source_indices[i] if not source_indices.is_empty() else i)
			vertex_cursor += points.size()
			index_cursor += added_indices
	var output: Array = []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = vertices
	output[Mesh.ARRAY_NORMAL] = normals
	output[Mesh.ARRAY_COLOR] = colors
	output[Mesh.ARRAY_INDEX] = indices
	if has_uv:
		output[Mesh.ARRAY_TEX_UV] = uv
	if has_uv2:
		output[Mesh.ARRAY_TEX_UV2] = uv2
	if has_tangents:
		output[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
	return {"mesh": mesh, "instances": instances, "bounds": bounds,
		"vertices": vertex_count, "triangles": index_count / 3}
