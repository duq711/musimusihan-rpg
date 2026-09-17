extends SceneTree

const HIDEOUT := preload("res://scripts/hideout.gd")
const BATCHES := preload("res://scripts/static_stone_batches.gd")
const SHADOWS := preload("res://scripts/static_solid_shadows.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var helper := HIDEOUT.new()
	helper._build_materials()
	var region := Node3D.new()
	region.position = Vector3(3, 2, -5)
	region.rotation.y = 0.45
	root.add_child(region)
	for index in 3:
		helper._add_arch(region, Vector3(index * 4, 0, 0), index * 45, Vector3(1.08, 1.10, 1.08))
		helper._add_pillar(region, Vector3(index * 4, 0, 4), Vector3(1.26, 1.55, 1.26))
	var family_meshes := {}
	var originals := {}
	var expected_shadow_meshes := {}
	for shadow: MeshInstance3D in region.find_children("ExactArchitectureShadow", "MeshInstance3D", true, false):
		var art := shadow.get_parent() as Node3D
		var arch := str(art.name) == "PointedArchMasonry"
		var faces := PackedVector3Array()
		var normals := PackedVector3Array()
		var source_count := 0
		for source: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
			if source == shadow:
				continue
			source_count += 1
			_check(source.visible and source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the visible stone keeps its original render instance without duplicate shadows")
			var placement := BATCHES.relative_transform(source, art)
			for point: Vector3 in _expanded_positions(source.mesh):
				faces.append(placement * point)
			normals.append_array(_expanded_normals(source.mesh, placement.basis))
			originals[str(region.get_path_to(source))] = {"mesh": source.mesh, "material": source.get_active_material(0), "transform": region.global_transform.affine_inverse() * source.global_transform}
		_check(source_count == (130 if arch else 29), "all actual authored arch or clustered-column pieces must be included")
		_check(faces.size() / 3 == (32400 if arch else 8688), "shadow merging preserves the complete original triangle count")
		var merged := _expanded_positions(shadow.mesh)
		_check(faces.size() == merged.size(), "no original shadow triangle may be omitted or added")
		var maximum_error := 0.0
		for index in mini(faces.size(), merged.size()):
			maximum_error = maxf(maximum_error, faces[index].distance_to(merged[index]))
		print("EXACT SHADOW GEOMETRY: ", str(art.name), " triangles=", faces.size() / 3, " max_position_error=", maximum_error)
		_check(maximum_error < 0.000003, "merged triangles preserve original positions, order and winding within packing precision")
		var merged_normals := _expanded_normals(shadow.mesh, Basis.IDENTITY)
		_check(normals.size() == merged_normals.size(), "all original shadow-bias vertex normals must remain")
		var minimum_alignment := 1.0
		for index in mini(normals.size(), merged_normals.size()):
			minimum_alignment = minf(minimum_alignment, normals[index].normalized().dot(merged_normals[index].normalized()))
		_check(minimum_alignment > 0.99999, "merging cannot displace or reverse the original shadow-bias normals")
		_check(shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and shadow.mesh.get_surface_count() == 1, "each authored object submits one independent shadow surface")
		_check(shadow.visibility_range_end == 52.0 and shadow.visibility_range_end_margin == 4.0, "the shadow inherits the actual production visibility range")
		_check(shadow.transform == Transform3D.IDENTITY, "the shadow shares its original assembly transform")
		var family := "arch" if arch else "pillar"
		if family_meshes.has(family):
			_check(shadow.mesh == family_meshes[family], "identical assemblies reuse the cached exact shadow mesh despite independent placements")
		else:
			family_meshes[family] = shadow.mesh
		expected_shadow_meshes[shadow.get_instance_id()] = shadow.mesh
		_check(SHADOWS.add_exact(art) == shadow, "repeated setup cannot add another shadow")
		if arch:
			_check(not _intersects(merged, Vector3(0, 1.2, -1), Vector3(0, 1.2, 1)), "the original arch passage remains open to light")
			_check(_intersects(merged, Vector3(1.1, 1.2, -1), Vector3(1.1, 1.2, 1)), "the original arch jamb continues blocking light")
		else:
			_check(_intersects(merged, Vector3(0, 1.2, -1), Vector3(0, 1.2, 1)), "the original clustered column continues blocking light")
	_check(expected_shadow_meshes.size() == 6, "three real arches and three real pillars each have one shadow")
	_check(BATCHES.build(region) > 0, "the original visible stone batching remains active")
	for batch: MultiMeshInstance3D in region.find_children("*", "MultiMeshInstance3D", true, false):
		_check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "visible stone batches must not submit duplicate shadows")
		for path: String in batch.get_meta("source_paths"):
			_check(originals.has(path), "a visible batch must not absorb an exact shadow instance")
	for path in originals:
		var source := region.get_node(path) as MeshInstance3D
		var record: Dictionary = originals[path]
		_check(source.mesh == record.mesh and source.get_active_material(0) == record.material, "batching and shadow merging preserve every visible source mesh and material")
		_check((region.global_transform.affine_inverse() * source.global_transform).is_equal_approx(record.transform), "all source transforms remain unchanged")
	for shadow: MeshInstance3D in region.find_children("ExactArchitectureShadow", "MeshInstance3D", true, false):
		_check(shadow.visible and shadow.mesh == expected_shadow_meshes[shadow.get_instance_id()], "each exact shadow retains independent per-object culling after visible batching")
	region.free()
	helper.free()
	_check(snapshot == ExpeditionSession.capture_snapshot() and mouse == Input.mouse_mode, "exact shadow optimization preserves expedition and cursor")
	if failures.is_empty():
		print("PROP EXACT SHADOW PASS: 3 real arches and 3 pillars; all triangles/winding/normals/placements preserved; exact doorway and column light blocking; shared resources and original distance ranges; six independent shadow surfaces without duplicate MultiMesh shadows; unchanged session")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _expanded_positions(mesh: Mesh) -> PackedVector3Array:
	# Mesh.get_faces() goes through TriangleMesh's 0.1mm collision-grid
	# snapping. Compare the actual renderer arrays, with no such rounding.
	var result := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			result.append_array(vertices)
		else:
			for index in indices:
				result.append(vertices[index])
	return result


func _expanded_normals(mesh: Mesh, basis: Basis) -> PackedVector3Array:
	var result := PackedVector3Array()
	var normal_basis := basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for value in normals:
				result.append(normal_basis * value)
		else:
			for index in indices:
				result.append(normal_basis * normals[index])
	return result


func _intersects(faces: PackedVector3Array, start: Vector3, end: Vector3) -> bool:
	for index in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false


func _check(passed: bool, message: String) -> void:
	if not passed and message not in failures:
		failures.append(message)
