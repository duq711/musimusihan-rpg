extends RefCounted
## A geometry transfer for background Blender inspection. It is not a Godot
## render: custom shaders and light exposure require approximate conversion.

const OUTPUT := "res://artifacts/visual_qa/cave_offline"


static func export_geometry(viewport: SubViewport, shots: Array) -> Dictionary:
	var stage := viewport.get_node("CavePreviewStage") as Node3D
	var geometry := stage.get_node("CaveGeometry") as Node3D
	var rock := StandardMaterial3D.new()
	rock.resource_name = "CaveRockOfflineApproximation"
	rock.albedo_color = Color(0.24, 0.19, 0.13)
	rock.roughness = 0.91
	rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wet_rock := rock.duplicate() as StandardMaterial3D
	wet_rock.resource_name = "WetCaveRockOfflineApproximation"
	wet_rock.albedo_color = Color(0.18, 0.19, 0.13)
	wet_rock.roughness = 0.45
	var water := StandardMaterial3D.new()
	water.resource_name = "CaveWaterOfflineApproximation"
	water.albedo_color = Color(0.025, 0.063, 0.061)
	water.metallic = 0.32
	water.roughness = 0.18
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node in geometry.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.material_override is ShaderMaterial:
			var shader_material := mesh_node.material_override as ShaderMaterial
			if shader_material.shader.resource_path.ends_with("cave_water.gdshader"):
				mesh_node.material_override = water
			elif shader_material.get_shader_parameter("wetness") != null and float(shader_material.get_shader_parameter("wetness")) > 0.0:
				mesh_node.material_override = wet_rock
			else:
				mesh_node.material_override = rock
		elif mesh_node.material_override is StandardMaterial3D:
			var standard := mesh_node.material_override as StandardMaterial3D
			if standard.albedo_texture != null and standard.uv1_triplanar:
				standard.resource_name = "CaveTriplanar_" + standard.albedo_texture.resource_path.get_file().get_basename()
	_set_owner_recursive(geometry, geometry)
	var absolute_output := ProjectSettings.globalize_path(OUTPUT)
	var error := DirAccess.make_dir_recursive_absolute(absolute_output)
	if error != OK:
		return {"success": false, "error": error_string(error)}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	error = document.append_from_scene(geometry, state)
	if error != OK:
		return {"success": false, "error": error_string(error)}
	error = document.write_to_filesystem(state, absolute_output + "/cave_geometry.glb")
	if error != OK:
		return {"success": false, "error": error_string(error)}
	var serial_shots: Array[Dictionary] = []
	for shot in shots:
		serial_shots.append({"name": shot.name, "position": _vector(shot.position), "target": _vector(shot.target), "fov": shot.fov})
	var metadata := {
		"source": "Actual Godot cave_geometry.build() output",
		"notice": "Blender reference render; custom rock/water shaders and light response are approximate. Not a Godot screenshot.",
		"footprint_metres": [131.0, 139.0],
		"shots": serial_shots,
	}
	var file := FileAccess.open(absolute_output + "/metadata.json", FileAccess.WRITE)
	if file == null:
		return {"success": false, "error": error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(metadata, "\t"))
	file.close()
	print("CAVE OFFLINE GEOMETRY EXPORT: " + absolute_output)
	return {"success": true, "directory": absolute_output}


static func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner_recursive(child, owner_node)


static func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
