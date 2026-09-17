extends SceneTree

const STONE := preload("res://scripts/dungeon_concept_visual.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	for kind in ["ossuary_wall", "wet_flagstone_floor", "crypt_ceiling"]:
		var size := Vector3(4, 3, 0.5) if kind == "ossuary_wall" else Vector3(4, 0.5, 5)
		var first := STONE.create_architecture(size, kind)
		var second := STONE.create_architecture(size, kind)
		var different := STONE.create_architecture(size + Vector3(1, 0, 0), kind)
		var name_value := "BondedMasonryBlocks" if kind == "ossuary_wall" else "FlagstoneSlabs"
		var first_mesh := first.get_node(name_value) as MeshInstance3D
		var second_mesh := second.get_node(name_value) as MeshInstance3D
		var different_mesh := different.get_node(name_value) as MeshInstance3D
		_check(first_mesh.mesh == second_mesh.mesh, "repeated whole stone assemblies must reuse the actual mesh: " + kind)
		_check(first_mesh.mesh != different_mesh.mesh, "different dimensions must retain independent exact geometry: " + kind)
		_check(first_mesh.material_override == second_mesh.material_override, "identical static surfaces must share their material")
		var original_transform := second.transform
		var original_mesh_bounds := second_mesh.mesh.get_aabb()
		first.position = Vector3(11, 4, -9)
		first.scale = Vector3(1.2, 0.8, 1.4)
		first.rotation.y = 0.7
		_check(second.transform == original_transform and second_mesh.mesh.get_aabb() == original_mesh_bounds, "shared resources must not share placement or change their geometry")
		var first_core := first.get_node("RecessedMortarCore") as MeshInstance3D
		var second_core := second.get_node("RecessedMortarCore") as MeshInstance3D
		var seal := first.get_node("MortarBoundarySeal") as MeshInstance3D
		_check(first_core.material_override == second_core.material_override and first_core.material_override == seal.material_override, "opaque seams must share the exact existing mortar response")
		_check(first_core.mesh.get_aabb().size == size * (Vector3(1, 1, 0.75) if kind == "ossuary_wall" else Vector3(1, 0.75, 1)), "caching must preserve recessed core dimensions")
		first.free()
		second.free()
		different.free()
		await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse, "cache reuse must preserve expedition and cursor")
	if failures.is_empty():
		print("PROP MESH CACHE PASS: actual wall/floor/ceiling resources reused, dimensions separated, transforms independent, opaque cores/seals preserved and expedition/cursor unchanged")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
