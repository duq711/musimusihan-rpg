extends SceneTree

const MASONRY := preload("res://scripts/hideout_ruin_masonry.gd")
const CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const BATCHES := preload("res://scripts/static_stone_batches.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for case in [
		{"kind": "wall", "architecture": "ossuary_wall", "size": Vector3(3.0, 2.5, 0.5), "axis": 2},
		{"kind": "floor", "architecture": "wet_flagstone_floor", "size": Vector3(3.0, 0.84, 3.0), "axis": 1},
		{"kind": "ceiling", "architecture": "crypt_ceiling", "size": Vector3(3.0, 0.5, 3.0), "axis": 1},
	]:
		_test_mesh(case)
	_test_production_hierarchy()
	_test_batch_eligibility()
	_check(MASONRY.erode_mesh(null, "wall") == null, "missing geometry fails closed")
	var unrelated := ArrayMesh.new()
	_check(MASONRY.erode_mesh(unrelated, "unknown") == null, "unrelated or unsupported geometry fails closed")
	if failures.is_empty():
		print("HIDEOUT RUIN MASONRY PASS: deterministic cached physical erosion, immutable source geometry/materials, bounded displacement and sealed perimeters, UV/normal preservation, original physics/shadows and static-batch eligibility")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_mesh(case: Dictionary) -> void:
	var architecture := CONCEPT.create_architecture(case.size, case.architecture)
	var node := architecture.get_node("BondedMasonryBlocks" if case.kind == "wall" else "FlagstoneSlabs") as MeshInstance3D
	var source := node.mesh as ArrayMesh
	var before := source.surface_get_arrays(0).duplicate(true)
	var source_material := node.get_active_material(0) as StandardMaterial3D
	var material_before := _material_snapshot(source_material)
	var mesh := MASONRY.erode_mesh(source, case.kind, 2)
	_check(mesh != null and mesh != source, "erosion produces a local mesh: " + str(case.kind))
	if mesh == null:
		architecture.free()
		return
	_check(MASONRY.erode_mesh(source, case.kind, 2) == mesh and MASONRY.erode_mesh(source, case.kind, 7) == mesh, "same source/kind/normalized variant shares the immutable cached erosion: " + str(case.kind))
	var other := MASONRY.erode_mesh(source, case.kind, 3)
	_check(other != mesh and var_to_bytes(other.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]) != var_to_bytes(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]), "placement variants produce distinct deterministic surface damage: " + str(case.kind))
	_check(source.surface_get_arrays(0) == before and node.mesh == source, "creating local erosion does not mutate the global catalog geometry: " + str(case.kind))
	_check(_material_snapshot(source_material) == material_before, "creating physical damage does not mutate original maps, color or material settings: " + str(case.kind))
	var after := mesh.surface_get_arrays(0)
	var vertices_before: PackedVector3Array = before[Mesh.ARRAY_VERTEX]
	var vertices_after: PackedVector3Array = after[Mesh.ARRAY_VERTEX]
	var uv_before: PackedVector2Array = before[Mesh.ARRAY_TEX_UV]
	var uv_after: PackedVector2Array = after[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = after[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = after[Mesh.ARRAY_TANGENT]
	var colors: PackedColorArray = after[Mesh.ARRAY_COLOR]
	var corners_before := _corner_indices(before)
	var corners_after := _corner_indices(after)
	_check(corners_after.size() == corners_before.size(), "erosion retains every authored triangle: " + str(case.kind))
	_check(normals.size() == vertices_after.size() and uv_after.size() == vertices_after.size() and tangents.size() == vertices_after.size() * 4 and colors.size() == vertices_after.size(), "rebuilt geometry retains complete normals, UVs, tangents and mineral colors: " + str(case.kind))
	var limit := 0.027 if case.kind == "floor" else 0.067
	var moved := 0
	var anchored := 0
	var maximum := 0.0
	var bounds := source.get_aabb()
	var normal_axis := int(case.axis)
	var first_axis := 1 if normal_axis == 0 else 0
	var second_axis := 1 if normal_axis == 2 else 2
	var uv_preserved := true
	var rim_preserved := true
	var displacement_bounded := true
	# SurfaceTool may reindex vertices while regenerating normals. Compare
	# corresponding triangle corners, which preserves actual rendered UVs.
	for corner in mini(corners_before.size(), corners_after.size()):
		var original := vertices_before[corners_before[corner]]
		var current := vertices_after[corners_after[corner]]
		var movement := original.distance_to(current)
		maximum = maxf(maximum, movement)
		if movement > 0.001:
			moved += 1
		displacement_bounded = displacement_bounded and current.is_finite() and movement <= limit + 0.00001
		uv_preserved = uv_preserved and uv_before[corners_before[corner]].distance_to(uv_after[corners_after[corner]]) < 0.000001
		var rim := minf(minf(original[first_axis] - bounds.position[first_axis], bounds.end[first_axis] - original[first_axis]), minf(original[second_axis] - bounds.position[second_axis], bounds.end[second_axis] - original[second_axis]))
		if rim < 0.000001:
			anchored += 1
			rim_preserved = rim_preserved and movement < 0.000001
	_check(moved > 50 and maximum > 0.005, "damage changes real vertices and silhouettes, rather than only material normals: " + str(case.kind))
	_check(displacement_bounded, "actual mesh displacement obeys the safe wall/floor cap: " + str(case.kind))
	_check(anchored > 0 and rim_preserved, "outer panel rim stays fixed against unchanged mortar seals: " + str(case.kind))
	_check(uv_preserved, "each rendered triangle corner preserves its source texture coordinates: " + str(case.kind))
	var valid_normals := true
	for normal in normals:
		valid_normals = valid_normals and normal.is_finite() and absf(normal.length() - 1.0) < 0.002
	_check(valid_normals, "erosion rebuilds valid unit surface normals: " + str(case.kind))
	_check(absf(float(mesh.get_meta("hideout_erosion_max_displacement")) - maximum) < 0.00001, "inspection metadata reports the actual maximum deformation: " + str(case.kind))
	architecture.free()


func _test_production_hierarchy() -> void:
	var region := Node3D.new()
	var preserved: Array[Dictionary] = []
	for kind in ["ossuary_wall", "wet_flagstone_floor", "crypt_ceiling"]:
		var size := Vector3(2.0, 1.5, 0.5) if kind == "ossuary_wall" else Vector3(2.0, 0.5, 2.0)
		var body := StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 2
		region.add_child(body)
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		var architecture := CONCEPT.create_architecture(size, kind)
		body.add_child(architecture)
		var mesh := architecture.get_node("BondedMasonryBlocks" if kind == "ossuary_wall" else "FlagstoneSlabs") as MeshInstance3D
		var backing := architecture.get_node("RecessedMortarCore") as MeshInstance3D
		var shadow := architecture.get_node("SolidArchitectureShadow") as MeshInstance3D
		var material := mesh.get_active_material(0) as StandardMaterial3D
		preserved.append({"body": body, "collision": collision, "shape": shape, "size": size, "architecture": architecture, "kind": kind, "visible": mesh, "source": mesh.mesh, "arrays": mesh.mesh.surface_get_arrays(0).duplicate(true), "material": material, "material_state": _material_snapshot(material), "backing": backing, "backing_mesh": backing.mesh, "shadow": shadow, "shadow_mesh": shadow.mesh})
	_check(MASONRY.weather_geometry(region) == 3, "production architecture traversal physically erodes each wall, floor and ceiling surface")
	_check(MASONRY.weather_geometry(region) == 0, "repeated construction is idempotent and never compounds erosion")
	for entry in preserved:
		_check(entry.collision.get_parent() == entry.body and entry.collision.shape == entry.shape and entry.shape.size == entry.size and entry.body.collision_layer == 4 and entry.body.collision_mask == 2, "actual static-body and collision shape identity/dimensions remain unchanged: " + str(entry.kind))
		_check(entry.architecture.get_meta("architecture_kind") == entry.kind and entry.backing.mesh == entry.backing_mesh and entry.shadow.mesh == entry.shadow_mesh and entry.shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "architecture identity, mortar and closed-panel shadow remain the existing production objects: " + str(entry.kind))
		_check(entry.source.surface_get_arrays(0) == entry.arrays and _material_snapshot(entry.material) == entry.material_state, "local installation leaves the reusable global source arrays and material untouched: " + str(entry.kind))
		var current_material := entry.visible.get_active_material(0) as StandardMaterial3D
		_check(current_material != entry.material and current_material.vertex_color_use_as_albedo and current_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "per-instance mineral variance uses a cached opaque material copy: " + str(entry.kind))
	region.free()


func _test_batch_eligibility() -> void:
	var region := Node3D.new()
	for index in 3:
		region.add_child(CONCEPT.create_architecture(Vector3(1.5, 1.2, 0.5), "ossuary_wall"))
	_check(MASONRY.weather_geometry(region) == 3, "repeated panels all receive the same eligible local mesh transformation")
	_check(BATCHES.build(region) > 0 and int(region.get_meta("static_stone_batched_instances", 0)) >= 3, "opaque eroded geometry retains the production static-batching path")
	region.free()


func _corner_indices(arrays: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		result = arrays[Mesh.ARRAY_INDEX]
	if result.is_empty():
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			result.append(index)
	return result


func _material_snapshot(material: StandardMaterial3D) -> Dictionary:
	return {"color": material.albedo_color, "albedo": material.albedo_texture, "normal": material.normal_texture, "normal_scale": material.normal_scale, "next_pass": material.next_pass, "vertex_color": material.vertex_color_use_as_albedo, "transparency": material.transparency, "surface_family": material.get_meta("dark_fantasy_surface", "")}


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
