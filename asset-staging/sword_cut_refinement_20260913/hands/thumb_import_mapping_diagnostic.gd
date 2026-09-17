extends SceneTree
func _init() -> void:
	var source: Node3D = load("res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb").instantiate()
	var glove := source.find_child("RightHand_Glove", true, false) as MeshInstance3D
	var arrays := glove.mesh.surface_get_arrays(0)
	var vertices: Array = []
	var normals: Array = []
	for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: vertices.append([point.x, point.y, point.z])
	for point: Vector3 in arrays[Mesh.ARRAY_NORMAL]: normals.append([point.x, point.y, point.z])
	var file := FileAccess.open("res://../asset-staging/sword_cut_refinement_20260913/hands/godot_imported_glove.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"vertices": vertices, "normals": normals, "indices": Array(arrays[Mesh.ARRAY_INDEX]), "transform": str(glove.transform)}, "\t"))
	file.close()
	print("THUMB IMPORT MAPPING PASS")
	source.free()
	quit()
