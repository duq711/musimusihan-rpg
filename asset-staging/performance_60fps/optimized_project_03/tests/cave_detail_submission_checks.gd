extends RefCounted
## Inspect the real submitted ArrayMesh ranges, including every source index.
## Cached arrays avoid repeatedly reading the same large tile for each variant.


static func inspect(submission: Dictionary, visual: Node3D, cache: Dictionary, read_multimesh: bool) -> Dictionary:
	var count: int = submission.transforms.size()
	if not submission.get("merged", false):
		if not visual is MultiMeshInstance3D or visual.multimesh == null or visual.multimesh.instance_count != count:
			return {"instances": 0, "mismatches": 1}
		var wrong := 0
		if read_multimesh:
			for i in range(count):
				var expected: Transform3D = submission.transforms[i]
				var actual: Transform3D = visual.multimesh.get_instance_transform(i)
				if actual.origin.distance_to(expected.origin) > 0.0001 or actual.basis.x.distance_to(expected.basis.x) > 0.0001 or actual.basis.y.distance_to(expected.basis.y) > 0.0001 or actual.basis.z.distance_to(expected.basis.z) > 0.0001:
					wrong += 1
		return {"instances": count, "mismatches": wrong}
	if not visual is MeshInstance3D or visual.mesh == null or submission.ranges.size() != count:
		return {"instances": 0, "mismatches": 1}
	var id: int = visual.mesh.get_instance_id()
	if not cache.has(id):
		cache[id] = visual.mesh.surface_get_arrays(0)
	var actual: Array = cache[id]
	var source: Array = submission.source_mesh.surface_get_arrays(0)
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var source_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var source_colors: PackedColorArray = source[Mesh.ARRAY_COLOR] if source[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var mismatches := 0
	for i in range(count):
		var placement: Dictionary = submission.ranges[i]
		var transform_value: Transform3D = submission.transforms[i]
		var normal_basis := transform_value.basis.inverse().transposed()
		var tint: Color = submission.colors[i]
		var offset := int(placement.vertex_start)
		var index_offset := int(placement.index_start)
		var index_count := source_indices.size() if not source_indices.is_empty() else points.size()
		var valid := int(placement.vertex_count) == points.size() and int(placement.index_count) == index_count
		for j in range(points.size()):
			var expected := transform_value * points[j]
			var expected_normal := (normal_basis * normals[j]).normalized()
			var expected_color := tint * (source_colors[j] if not source_colors.is_empty() else Color.WHITE)
			var actual_color: Color = actual[Mesh.ARRAY_COLOR][offset + j]
			valid = valid and actual[Mesh.ARRAY_VERTEX][offset + j].distance_to(expected) < 0.00003
			# ArrayMesh encodes normals and colors; compare within their native
			# quantization. The production stone shader does not consume COLOR.
			valid = valid and actual[Mesh.ARRAY_NORMAL][offset + j].distance_to(expected_normal) < 0.001
			valid = valid and absf(actual_color.r - expected_color.r) <= 1.01 / 255.0 and absf(actual_color.g - expected_color.g) <= 1.01 / 255.0 and absf(actual_color.b - expected_color.b) <= 1.01 / 255.0 and absf(actual_color.a - expected_color.a) <= 1.01 / 255.0
		for j in range(index_count):
			valid = valid and int(actual[Mesh.ARRAY_INDEX][index_offset + j]) == offset + (int(source_indices[j]) if not source_indices.is_empty() else j)
		if not valid:
			mismatches += 1
	return {"instances": count, "mismatches": mismatches}
