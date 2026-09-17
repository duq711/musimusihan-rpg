extends SceneTree

const STONE := preload("res://scripts/dungeon_concept_visual.gd")
const BATCHES := preload("res://scripts/static_stone_batches.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var region := Node3D.new()
	region.position = Vector3(3, 2, -4)
	root.add_child(region)
	for index in 3:
		var arch := Node3D.new()
		arch.name = "ActualArch%d" % index
		arch.position = Vector3(index * 3, 0, index * 2)
		arch.rotation.y = index * 0.45
		arch.scale = Vector3(1.08, 1.1, 1.08)
		region.add_child(arch)
		STONE.apply_archway(arch)
	var original := {}
	for mesh: MeshInstance3D in region.find_children("*", "MeshInstance3D", true, false):
		original[str(region.get_path_to(mesh))] = {"mesh": mesh.mesh, "material": mesh.get_active_material(0), "transform": region.global_transform.affine_inverse() * mesh.global_transform, "cast_shadow": mesh.cast_shadow, "layers": mesh.layers}
	var untouched := MeshInstance3D.new()
	untouched.name = "OrdinaryNonArchitectureProp"
	untouched.mesh = original.values()[0].mesh
	untouched.material_override = original.values()[0].material
	region.add_child(untouched)
	var total_batches := BATCHES.build(region)
	_check(total_batches > 0, "actual repeated production arch geometry must use static instance batches")
	var covered := {}
	for batch: MultiMeshInstance3D in region.find_children("*", "MultiMeshInstance3D", true, false):
		var paths: Array = batch.get_meta("source_paths")
		var submitted: Array = batch.get_meta("submitted_transforms")
		_check(paths.size() >= 3 and paths.size() == submitted.size() and paths.size() == batch.multimesh.instance_count, "batch must submit each recorded source exactly once")
		for index in paths.size():
			var path := str(paths[index])
			_check(original.has(path) and not covered.has(path), "batch must refer to an original source once")
			if not original.has(path):
				continue
			covered[path] = true
			var prior: Dictionary = original[path]
			var source := region.get_node(path) as MeshInstance3D
			_check(not source.visible and source.mesh == prior.mesh, "source node and mesh must remain inspectable without duplicate rendering")
			_check(batch.multimesh.mesh == prior.mesh and batch.material_override == prior.material, "batch must reuse exact source geometry and local triplanar material")
			_check((submitted[index] as Transform3D).is_equal_approx(prior.transform), "submitted transform must match the independent live scene transform")
			_check(batch.cast_shadow == prior.cast_shadow and batch.layers == prior.layers, "shadow and camera layers must be preserved")
			var placed: AABB = submitted[index] * prior.mesh.get_aabb()
			_check(batch.multimesh.custom_aabb.grow(0.0001).encloses(placed), "combined culling bounds must include every original source extent")
	_check(covered.size() > original.size() * 0.70, "repeated actual arches must meaningfully reduce render instances")
	_check(untouched.visible, "non-architecture props must retain their independent rendering")
	_check(BATCHES.build(region) == 0, "repeated setup must not duplicate or hide existing batches")
	region.free()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "batching must preserve expedition and cursor")
	if failures.is_empty():
		print("PROP STATIC BATCH PASS: actual repeated arches, exact mesh/material/transforms/shadow/layers, complete culling bounds, unique source coverage and preserved expedition/cursor")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
