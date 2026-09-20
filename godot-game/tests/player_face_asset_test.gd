extends SceneTree
## Regression: visible natural eyes and facial skin must survive GLB import.
const MODEL := "res://assets/3d/player/gravebound_player.glb"
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var body := (load(MODEL) as PackedScene).instantiate()
	root.add_child(body)
	var eyes := body.find_child("Gravebound_Eyes", true, false) as MeshInstance3D
	var head := body.find_child("Gravebound_AnatomicalHead", true, false) as MeshInstance3D
	if eyes == null or head == null:
		failures.append("actual head and eyes must be present")
	else:
		var found: Array[String] = []
		for surface in eyes.mesh.get_surface_count():
			var material := eyes.get_active_material(surface) as BaseMaterial3D
			if material == null: failures.append("eyes require lit PBR materials"); continue
			found.append(material.resource_name)
			if material.resource_name.contains("Garment"): failures.append("clothing texture must not cover the eyes")
			if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: failures.append("eyes must respond to real lighting")
		for expected: String in ["Gravebound_Eye_Warm_Sclera", "Gravebound_Eye_Brown_Iris", "Gravebound_Eye_Pupil"]:
			if expected not in found: failures.append("missing visible eye surface: " + expected)
		# Inspect triangles on the upper nose in the head's authored local frame.
		# Those used scalp material before the repair, making a black patch.
		var nose_triangles := 0
		for surface in head.mesh.get_surface_count():
			var arrays := head.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := head.get_active_material(surface) as BaseMaterial3D
			for offset in range(0, indices.size(), 3):
				var center := (vertices[indices[offset]] + vertices[indices[offset + 1]] + vertices[indices[offset + 2]]) / 3.0
				# Blender local (x,y,z) becomes glTF local (x,z,-y).
				if absf(center.x) < .015 and center.z > .10 and center.y > 1.595 and center.y < 1.63:
					nose_triangles += 1
					if material != null and (material.resource_name.contains("Hair") or material.resource_name.contains("Scalp")):
						failures.append("nose triangles must use facial skin, not scalp hair")
		if nose_triangles == 0: failures.append("nose regression must inspect actual imported triangles")
	body.free()
	for failure in failures: push_error(failure)
	print("PLAYER FACE ASSET " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
