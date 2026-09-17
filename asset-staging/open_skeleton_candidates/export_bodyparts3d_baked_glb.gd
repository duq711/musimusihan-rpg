extends SceneTree

## Builds the runtime-friendly BodyParts3D GLB with metre/Y-up conversion baked
## into every vertex. All FJ mesh nodes then live directly in identity root space,
## so pivots from bodyparts3d_runtime_mapping.json can be used without reparenting
## across a scale/axis-conversion parent.

const SOURCE_DIRECTORY := "res://bodyparts3d_cc_by_sa/complete_skeleton_obj_99"
const OUTPUT_PATH := "res://bodyparts3d_cc_by_sa/bodyparts3d_skeleton_cc_by_4_baked.glb"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	scene_root.name = "BodyParts3D_Skeleton_CC_BY_4_Baked"

	var files := DirAccess.get_files_at(SOURCE_DIRECTORY)
	files.sort()
	var loaded := 0
	for file_name in files:
		if not file_name.ends_with(".obj"):
			continue
		var source_path := "%s/%s" % [SOURCE_DIRECTORY, file_name]
		var source_mesh := load(source_path) as Mesh
		if source_mesh == null:
			push_error("Could not load %s" % source_path)
			quit(1)
			return
		var instance := MeshInstance3D.new()
		instance.name = file_name.get_basename()
		instance.mesh = _bake_mm_z_up_to_m_y_up(source_mesh)
		scene_root.add_child(instance)
		loaded += 1

	if loaded != 202:
		push_error("Expected 202 source OBJ meshes, got %d" % loaded)
		quit(1)
		return

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(scene_root, state)
	if append_error != OK:
		push_error("GLTF append failed: %s" % error_string(append_error))
		quit(1)
		return

	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	var write_error := document.write_to_filesystem(state, absolute_output)
	if write_error != OK:
		push_error("GLTF write failed: %s" % error_string(write_error))
		quit(1)
		return

	print("Exported %d baked meshes to %s" % [loaded, absolute_output])
	scene_root.free()
	quit(0)


func _bake_mm_z_up_to_m_y_up(source: Mesh) -> ArrayMesh:
	var converted := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface_index)

		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for index in range(vertices.size()):
			var vertex := vertices[index]
			vertices[index] = Vector3(vertex.x, vertex.z, -vertex.y) * 0.001
		arrays[Mesh.ARRAY_VERTEX] = vertices

		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			for index in range(normals.size()):
				var normal := normals[index]
				normals[index] = Vector3(normal.x, normal.z, -normal.y).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals

		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
			for index in range(0, tangents.size(), 4):
				var x := tangents[index]
				var y := tangents[index + 1]
				var z := tangents[index + 2]
				tangents[index] = x
				tangents[index + 1] = z
				tangents[index + 2] = -y
			arrays[Mesh.ARRAY_TANGENT] = tangents

		converted.add_surface_from_arrays(
			source.surface_get_primitive_type(surface_index), arrays
		)
		converted.surface_set_name(
			converted.get_surface_count() - 1, source.surface_get_name(surface_index)
		)
		converted.surface_set_material(
			converted.get_surface_count() - 1, source.surface_get_material(surface_index)
		)
	return converted
