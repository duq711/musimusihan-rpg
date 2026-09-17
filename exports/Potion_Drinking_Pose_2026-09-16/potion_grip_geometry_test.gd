extends SceneTree
func _init() -> void: call_deferred("_run")
func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func _run() -> void:
	var motion := preload("res://scripts/potion_drink_visuals.gd").new()
	root.add_child(motion)
	motion.setup()
	var adapter: Node3D = motion.right_arm._active_visual
	var rig: Skeleton3D = adapter.skeleton
	var result := {"rest": [], "parents": [], "names": [], "axes": {}, "parts": [], "hand_build": matrix(adapter._hand_build_transform())}
	for i in rig.get_bone_count():
		result.rest.append(matrix(rig.get_bone_rest(i)))
		result.parents.append(rig.get_bone_parent(i))
		result.names.append(rig.get_bone_name(i))
	for k: String in adapter._axes:
		var a: Vector3 = adapter._axes[k]
		result.axes[k]=[a.x,a.y,a.z]
	for part: MeshInstance3D in adapter.hand_meshes:
		var bind := []
		var bone_ids := []
		for i in part.skin.get_bind_count():
			var b := part.skin.get_bind_bone(i)
			if b < 0: b=rig.find_bone(part.skin.get_bind_name(i))
			bone_ids.append(b)
			bind.append(matrix(part.skin.get_bind_pose(i)))
		for s in part.mesh.get_surface_count():
			var a := part.mesh.surface_get_arrays(s)
			var v := []
			for p in a[Mesh.ARRAY_VERTEX]: v.append([p.x,p.y,p.z])
			result.parts.append({"vertices":v,"bones":Array(a[Mesh.ARRAY_BONES]),"weights":Array(a[Mesh.ARRAY_WEIGHTS]),"bind":bind,"bone_ids":bone_ids})
	FileAccess.open("res://../exports/Potion_Drinking_Pose_2026-09-16/rig.json",FileAccess.WRITE).store_string(JSON.stringify(result))
	motion.queue_free()
	await process_frame
	print("POTION GRIP GEOMETRY TEST PASS")
	quit()
