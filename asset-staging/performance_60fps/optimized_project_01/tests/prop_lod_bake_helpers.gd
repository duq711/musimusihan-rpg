extends RefCounted

# Offline only. Runtime consumes saved ArrayMesh resources and never executes
# simplification. Godot's storage buffers preserve their original quantization.
static func add_index_lods(source: ArrayMesh, minimum_triangles := 1500) -> Dictionary:
	var importer := ImporterMesh.new()
	for surface in source.get_surface_count():
		importer.add_surface(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface))
	var started := Time.get_ticks_usec()
	importer.generate_lods(60.0, 25.0, [])
	var generated := ArrayMesh.new()
	var levels: Array = []
	for surface in source.get_surface_count():
		var lods := {}
		for level in importer.get_surface_lod_count(surface):
			var indices := importer.get_surface_lod_indices(surface, level)
			if indices.size() < minimum_triangles * 3:
				continue
			var error := importer.get_surface_lod_size(surface, level)
			lods[error] = indices
			levels.append({"surface": surface, "screen_error": error, "triangles": indices.size() / 3})
		generated.add_surface_from_arrays(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface), [], lods)
	var source_packed: Array = source.get("_surfaces")
	var generated_packed: Array = generated.get("_surfaces")
	var preserved: Array = source_packed.duplicate(true)
	for surface in preserved.size():
		if generated_packed[surface].has("lods"):
			preserved[surface]["lods"] = generated_packed[surface]["lods"]
	var mesh := ArrayMesh.new()
	mesh.set("_surfaces", preserved)
	mesh.set_meta("source_base_arrays_sha256", array_hash(source))
	mesh.set_meta("lod_levels", levels)
	return {"mesh": mesh, "levels": levels, "generation_ms": float(Time.get_ticks_usec() - started) / 1000.0}


static func array_hash(mesh: ArrayMesh) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for surface in mesh.get_surface_count():
		hashing.update(var_to_bytes(mesh.surface_get_arrays(surface)))
	return hashing.finish().hex_encode()


static func verify_index_lods(source: ArrayMesh, baked: ArrayMesh, minimum_triangles := 1500) -> Array[String]:
	var failures: Array[String] = []
	if source.get_surface_count() != baked.get_surface_count():
		failures.append("surface count changed")
		return failures
	if array_hash(source) != array_hash(baked):
		failures.append("base vertex, normal, UV or index buffers changed")
	if source.get_aabb() != baked.get_aabb():
		failures.append("source bounds changed")
	var importer := ImporterMesh.from_mesh(baked)
	for surface in source.get_surface_count():
		if source.surface_get_material(surface) != baked.surface_get_material(surface):
			failures.append("surface material changed")
		var original: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
		var previous_count: int = original[Mesh.ARRAY_INDEX].size()
		var previous_error := 0.0
		if importer.get_surface_lod_count(surface) == 0:
			failures.append("no engine LOD indices were generated")
		for level in importer.get_surface_lod_count(surface):
			var indices := importer.get_surface_lod_indices(surface, level)
			var error := importer.get_surface_lod_size(surface, level)
			if indices.size() >= previous_count or indices.size() < minimum_triangles * 3 or indices.size() % 3 != 0:
				failures.append("LOD indices do not form decreasing complete triangles")
			if error <= previous_error:
				failures.append("LOD screen errors are not increasing")
			for index in indices:
				if index < 0 or index >= vertices.size():
					failures.append("LOD references a vertex outside the original buffers")
					break
			previous_count = indices.size()
			previous_error = error
		if previous_count >= int(original[Mesh.ARRAY_INDEX].size()) / 2:
			failures.append("LOD does not offer at least a twofold triangle reduction")
	return failures
