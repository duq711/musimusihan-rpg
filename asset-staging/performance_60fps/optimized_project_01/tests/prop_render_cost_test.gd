extends SceneTree

# Measures actual authored geometry without entering gameplay or starting a
# renderer. Surface counts are submission candidates, never measured draw calls.
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("PROP AUDIT: starting isolated geometry census")
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var report := {"measurement": "headless production construction and CPU geometry census; not GPU frame timing", "locations": {}}
	for location in ["hideout", "dungeon"]:
		var rounds: Array = []
		for repetition in 2:
			print("PROP AUDIT: constructing ", location, " round ", repetition)
			var started := Time.get_ticks_usec()
			var source_path := "res://scripts/hideout.gd" if location == "hideout" else "res://scripts/game.gd"
			var helper: Node = load(source_path).new()
			helper.call("_build_materials")
			if location == "hideout":
				helper.call("_build_world")
			else:
				helper.call("_build_environment")
				helper.call("_build_dungeon")
				helper.call("_build_extraction_gate")
			var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
			print("PROP AUDIT: construction complete in ", build_ms, " ms; counting submitted mesh arrays")
			var data := _census(helper)
			data["construction_ms"] = build_ms
			rounds.append(data)
			helper.free()
			await process_frame
			report.locations[location] = rounds
		_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse, "construction must preserve all expedition state and cursor")
	var label := OS.get_environment("PROP_RENDER_COST_LABEL")
	if label.is_empty():
		label = "latest"
	_check(label.is_valid_filename(), "report label must be a filename")
	var folder := "res://artifacts/performance"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder + "/prop_geometry_" + label + ".json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	_check(output != null, "geometry audit must write its evidence")
	if output != null:
		output.store_string(JSON.stringify(report, "\t") + "\n")
	if failures.is_empty():
		print("PROP RENDER COST PASS: two actual hideout/dungeon constructions, CPU geometry census, unchanged expedition and cursor; " + ProjectSettings.globalize_path(path))
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _census(root_node: Node) -> Dictionary:
	var data := {"node_count": 0, "mesh_instances": 0, "visible_mesh_instances": 0, "multimesh_batches": 0, "multimesh_instances": 0, "visible_surfaces": 0, "visible_triangles": 0, "visible_vertices": 0, "shadow_casting_meshes": 0, "unique_visible_meshes": 0, "unique_visible_materials": 0, "triplanar_surfaces": 0, "transparent_surfaces": 0, "lights": [], "particle_systems": [], "largest_meshes": [], "mesh_name_families": {}, "regions": {}}
	var meshes := {}
	var materials := {}
	_visit(root_node, true, data, meshes, materials, "world")
	data.unique_visible_meshes = meshes.size()
	data.unique_visible_materials = materials.size()
	data.largest_meshes.sort_custom(func(a, b): return a.triangles > b.triangles)
	data.largest_meshes = data.largest_meshes.slice(0, 18)
	return data


func _visit(node: Node, parent_visible: bool, data: Dictionary, meshes: Dictionary, materials: Dictionary, region: String) -> void:
	data.node_count += 1
	var visible := parent_visible and (not node is Node3D or (node as Node3D).visible)
	if node.has_meta("region_id"):
		region = str(node.get_meta("region_id"))
	if node is MeshInstance3D:
		data.mesh_instances += 1
		var instance := node as MeshInstance3D
		if visible and instance.mesh != null:
			data.visible_mesh_instances += 1
			meshes[instance.mesh.get_instance_id()] = true
			var triangles := 0
			var vertex_count := 0
			for surface in instance.mesh.get_surface_count():
				var arrays := instance.mesh.surface_get_arrays(surface)
				if arrays.is_empty():
					continue
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				vertex_count += vertices.size()
				triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
				data.visible_surfaces += 1
				var material := instance.get_active_material(surface)
				if material != null:
					materials[material.get_instance_id()] = true
					if material is StandardMaterial3D:
						data.triplanar_surfaces += int(material.uv1_triplanar)
						data.transparent_surfaces += int(material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			data.visible_triangles += triangles
			data.visible_vertices += vertex_count
			data.shadow_casting_meshes += int(instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var family := str(node.name).trim_prefix("@").get_slice("@", 0)
			var family_data: Dictionary = data.mesh_name_families.get(family, {"instances": 0, "triangles": 0})
			family_data.instances += 1
			family_data.triangles += triangles
			data.mesh_name_families[family] = family_data
			var region_data: Dictionary = data.regions.get(region, {"instances": 0, "triangles": 0})
			region_data.instances += 1
			region_data.triangles += triangles
			data.regions[region] = region_data
			data.largest_meshes.append({"name": str(node.name), "triangles": triangles, "vertices": vertex_count, "region": region})
	elif node is MultiMeshInstance3D and visible:
		var batch := node as MultiMeshInstance3D
		if batch.multimesh != null and batch.multimesh.mesh != null:
			var source := batch.multimesh.mesh
			var count := batch.multimesh.instance_count if batch.multimesh.visible_instance_count < 0 else batch.multimesh.visible_instance_count
			data.multimesh_batches += 1
			data.multimesh_instances += count
			meshes[source.get_instance_id()] = true
			var triangles := 0
			var vertices := 0
			for surface in source.get_surface_count():
				var arrays := source.surface_get_arrays(surface)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				vertices += points.size() * count
				triangles += (indices.size() if not indices.is_empty() else points.size()) / 3 * count
				data.visible_surfaces += 1
			var material := batch.material_override
			if material != null:
				materials[material.get_instance_id()] = true
				if material is StandardMaterial3D:
					data.triplanar_surfaces += int(material.uv1_triplanar)
			data.visible_triangles += triangles
			data.visible_vertices += vertices
			data.shadow_casting_meshes += int(batch.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var region_data: Dictionary = data.regions.get(region, {"instances": 0, "triangles": 0})
			region_data.instances += 1
			region_data.triangles += triangles
			data.regions[region] = region_data
	elif node is Light3D:
		data.lights.append({"name": str(node.name), "visible": visible, "shadow": node.shadow_enabled, "region": region})
	elif node is CPUParticles3D:
		data.particle_systems.append({"name": str(node.name), "amount": node.amount, "visible": visible, "region": region})
	for child in node.get_children():
		_visit(child, visible, data, meshes, materials, region)


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
