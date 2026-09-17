extends SceneTree

# Loads every generated GLB through Godot's normal importer and reports the
# resulting scene shape. This catches malformed files and failed `-colonly`
# post-processing without touching the game project.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var files := DirAccess.get_files_at("res://out")
	files.sort()
	var failed: Array[String] = []
	for file_name in files:
		if not file_name.ends_with(".glb"):
			continue
		var packed := load("res://out/%s" % file_name) as PackedScene
		if packed == null:
			failed.append("%s: not a PackedScene" % file_name)
			continue
		var root := packed.instantiate()
		var mesh_count := 0
		var body_count := 0
		var marker_count := 0
		for node in _all_descendants(root):
			if node is MeshInstance3D:
				mesh_count += 1
			elif node is StaticBody3D:
				body_count += 1
			elif node is Node3D and (node.name.ends_with("Anchor") or node.name in ["BladeTip", "DamageOrigin", "PortalTarget", "LidPivot", "StairBottom", "StairTop", "DoorwayCenter"]):
				marker_count += 1
		print("%-30s meshes=%3d static_bodies=%2d markers=%2d" % [file_name, mesh_count, body_count, marker_count])
		root.free()

	if failed.is_empty():
		print("Validation passed for all generated GLBs.")
		quit(0)
	else:
		push_error("Validation failed: %s" % "; ".join(failed))
		quit(1)


func _all_descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
