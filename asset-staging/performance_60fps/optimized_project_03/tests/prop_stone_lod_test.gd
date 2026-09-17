extends SceneTree

const STONE := preload("res://scripts/dungeon_concept_visual.gd")
const BAKER := preload("res://tests/prop_lod_bake_helpers.gd")
const FOLDER := "res://assets/3d/dark_fantasy/generated_lods/stone_samples"
const SAMPLES := [
	{"id": "dungeon_west_wall", "method": "_masonry_mesh", "size": Vector3(0.8, 5.2, 34)},
	{"id": "dungeon_floor", "method": "_paving_mesh", "size": Vector3(21, 1, 34)}
]
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var records: Array = []
	for sample in SAMPLES:
		var source: ArrayMesh = STONE.source_assembly_mesh("masonry" if sample.method == "_masonry_mesh" else "paving", sample.size)
		var path := FOLDER.path_join(str(sample.id) + ".res")
		if OS.get_environment("BAKE_PROP_STONE_LODS") == "1":
			var result := BAKER.add_index_lods(source)
			var mesh: ArrayMesh = result.mesh
			mesh.set_meta("source_factory", "DungeonConceptVisual." + str(sample.method))
			mesh.set_meta("source_size", sample.size)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
			_check(ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) == OK, "representative stone LOD must save")
			records.append({"id": sample.id, "size": var_to_str(sample.size), "source_triangles": source.surface_get_array_index_len(0) / 3, "base_arrays_sha256": BAKER.array_hash(source), "lods": result.levels, "generation_ms": result.generation_ms, "resource_bytes": FileAccess.get_file_as_bytes(path).size(), "resource_sha256": FileAccess.get_sha256(path)})
		_check(ResourceLoader.exists(path), "the prepared stone sample must exist: " + str(sample.id))
		if ResourceLoader.exists(path):
			var baked := load(path) as ArrayMesh
			_check(baked != null, "the sample must be a runtime ArrayMesh")
			if baked != null:
				for message in BAKER.verify_index_lods(source, baked):
					_check(false, str(sample.id) + ": " + message)
		await process_frame
	if not records.is_empty():
		var output := FileAccess.open(FOLDER.path_join("generation.json"), FileAccess.WRITE)
		output.store_string(JSON.stringify({"samples": records, "runtime_connected": false, "method": "Original packed base buffers plus offline engine LOD indices. Original production instance transforms and triplanar material remain external and unchanged."}, "\t") + "\n")
	_check(snapshot == ExpeditionSession.capture_snapshot() and mouse == Input.mouse_mode, "stone preparation must preserve expedition and cursor")
	if failures.is_empty():
		print("PROP STONE LOD PASS: representative real 34m wall and 21x34m floor; exact packed base buffers/material/bounds and useful valid engine LOD indices")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
