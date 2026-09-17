extends SceneTree

## Repackages the official BodyParts3D 99%-polygon OBJ skeleton subset as a
## Godot-ready, metre-scale, Y-up GLB. Geometry is not edited; only the media
## format and root coordinate transform change. BodyParts3D's current official
## license is CC BY 4.0: https://dbarchive.biosciencedbc.jp/en/bodyparts3d/lic.html

const SOURCE_DIRECTORY := "res://bodyparts3d_cc_by_sa/complete_skeleton_obj_99"
const OUTPUT_PATH := "res://bodyparts3d_cc_by_sa/bodyparts3d_skeleton_cc_by_4.glb"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	scene_root.name = "BodyParts3D_Skeleton_CC_BY_4"

	# BodyParts3D OBJ coordinates are millimetres and Z-up. This child transform
	# presents the asset to Godot as metres and Y-up while preserving source data.
	var coordinate_conversion := Node3D.new()
	coordinate_conversion.name = "BodyParts3D_mm_Zup_to_m_Yup"
	coordinate_conversion.rotation_degrees.x = -90.0
	coordinate_conversion.scale = Vector3.ONE * 0.001
	scene_root.add_child(coordinate_conversion)

	var files := DirAccess.get_files_at(SOURCE_DIRECTORY)
	files.sort()
	var loaded := 0
	for file_name in files:
		if not file_name.ends_with(".obj"):
			continue
		var source_path := "%s/%s" % [SOURCE_DIRECTORY, file_name]
		var mesh := load(source_path) as Mesh
		if mesh == null:
			push_error("Could not load %s" % source_path)
			quit(1)
			return
		var instance := MeshInstance3D.new()
		instance.name = file_name.get_basename()
		instance.mesh = mesh
		coordinate_conversion.add_child(instance)
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

	print("Exported %d meshes to %s" % [loaded, absolute_output])
	quit(0)
