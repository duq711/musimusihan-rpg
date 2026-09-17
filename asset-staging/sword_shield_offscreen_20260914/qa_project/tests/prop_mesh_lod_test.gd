extends SceneTree

const SKULL := preload("res://scripts/dark_fantasy_skull.gd")
const SOURCE_PATH := "res://assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb"
const OUTPUT_PATH := "res://assets/3d/dark_fantasy/generated_lods/anatomical_skull_lod.res"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var source := SKULL.source_mesh_data()
	var skull := SKULL.create()
	var original := source.mesh as ArrayMesh
	if OS.get_environment("BAKE_PROP_LODS") == "1":
		_bake(original, source)
	_check(ResourceLoader.exists(OUTPUT_PATH), "the offline skull LOD resource must be packaged")
	if ResourceLoader.exists(OUTPUT_PATH):
		var baked := load(OUTPUT_PATH) as ArrayMesh
		_check(baked != null, "the baked resource must be a runtime ArrayMesh")
		if baked != null:
			_verify(original, baked)
			_check(_array_hash(skull.mesh) == _array_hash(original), "production skull must retain the independently reconstructed original geometry")
			_check(ImporterMesh.from_mesh(skull.mesh).get_surface_lod_count(0) >= 4, "production skull must actually use the packaged engine LOD indices")
	skull.free()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "LOD generation and inspection must preserve expedition and cursor")
	if failures.is_empty():
		print("PROP MESH LOD PASS: exact source vertex/index/normal/UV arrays, bounded decreasing LOD index buffers, rigid anatomy provenance and unchanged expedition/cursor")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _bake(original: ArrayMesh, source: Dictionary) -> void:
	var importer := ImporterMesh.new()
	for surface in original.get_surface_count():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, original.surface_get_arrays(surface))
	var started := Time.get_ticks_usec()
	importer.generate_lods(60.0, 25.0, [])
	var baked := ArrayMesh.new()
	var report: Array = []
	for surface in original.get_surface_count():
		var lods := {}
		for level in importer.get_surface_lod_count(surface):
			var indices := importer.get_surface_lod_indices(surface, level)
			# Keep the cavity/jaw silhouette even at the lowest retained level.
			if indices.size() < 1500 * 3:
				continue
			var error := importer.get_surface_lod_size(surface, level)
			lods[error] = indices
			report.append({"surface": surface, "screen_error": error, "triangles": indices.size() / 3})
		# Preserve the base arrays verbatim; the optimizer only contributes
		# alternate indices into the same vertex/normal/UV buffers.
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, original.surface_get_arrays(surface), [], lods)
		baked.surface_set_material(surface, original.surface_get_material(surface))
	# Re-encoding decoded normals introduces another tiny quantization step.
	# Copy Godot's serialized packed base buffers verbatim, then attach only
	# its generated LOD data. This offline operation uses the same _surfaces
	# storage property read by ResourceLoader, and is checked after reloading.
	var original_packed: Array = original.get("_surfaces")
	var generated_packed: Array = baked.get("_surfaces")
	var preserved_surfaces: Array = original_packed.duplicate(true)
	for surface in preserved_surfaces.size():
		preserved_surfaces[surface]["lods"] = generated_packed[surface]["lods"]
	var preserved := ArrayMesh.new()
	preserved.set("_surfaces", preserved_surfaces)
	baked = preserved
	baked.set_meta("source_path", SOURCE_PATH)
	baked.set_meta("source_sha256", FileAccess.get_sha256(SOURCE_PATH))
	baked.set_meta("license", "BodyParts3D / CC BY 4.0; original attribution retained in asset provenance")
	baked.set_meta("source_bounds", source.source_bounds)
	baked.set_meta("source_piece_count", source.source_piece_count)
	baked.set_meta("source_base_arrays_sha256", _array_hash(original))
	baked.set_meta("lod_levels", report)
	baked.set_meta("generation_ms", float(Time.get_ticks_usec() - started) / 1000.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	_check(ResourceSaver.save(baked, OUTPUT_PATH, ResourceSaver.FLAG_COMPRESS) == OK, "offline LOD resource must save")
	print("SKULL OFFLINE LOD: ", report, " generation_ms=", baked.get_meta("generation_ms"), " bytes=", FileAccess.get_file_as_bytes(OUTPUT_PATH).size())


func _verify(original: ArrayMesh, baked: ArrayMesh) -> void:
	_check(baked.get_surface_count() == original.get_surface_count(), "surface count must remain exact")
	_check(_array_hash(original) == _array_hash(baked), "all base arrays must remain byte-identical after saved resource loading")
	_check(baked.get_aabb() == original.get_aabb(), "the original anatomy bounds must remain exact")
	_check(baked.get_meta("source_sha256", "") == FileAccess.get_sha256(SOURCE_PATH), "baked resource must identify the current immutable anatomical source")
	_check(baked.get_meta("source_base_arrays_sha256", "") == _array_hash(original), "baked evidence must identify the actual base arrays")
	var importer := ImporterMesh.from_mesh(baked)
	for surface in original.get_surface_count():
		var source_indices: PackedInt32Array = original.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		var source_vertices: PackedVector3Array = original.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var previous := source_indices.size()
		var previous_error := 0.0
		_check(importer.get_surface_lod_count(surface) >= 4, "dense skull must retain at least four useful engine LOD levels")
		for level in importer.get_surface_lod_count(surface):
			var indices := importer.get_surface_lod_indices(surface, level)
			var error := importer.get_surface_lod_size(surface, level)
			_check(indices.size() < previous and indices.size() >= 4500 and indices.size() % 3 == 0, "each retained LOD must reduce complete triangles while preserving a 1500 triangle floor")
			_check(error > previous_error, "LOD transitions must use increasing screen error thresholds")
			for index in indices:
				if index < 0 or index >= source_vertices.size():
					_check(false, "LOD indices may only reference original vertices")
					break
			previous = indices.size()
			previous_error = error
		_check(previous < source_indices.size() / 16, "the far skull index count must be at least 16 times smaller")


func _array_hash(mesh: ArrayMesh) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for surface in mesh.get_surface_count():
		hashing.update(var_to_bytes(mesh.surface_get_arrays(surface)))
	return hashing.finish().hex_encode()


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
