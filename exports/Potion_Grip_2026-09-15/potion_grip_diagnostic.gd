extends SceneTree
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var motion := preload("res://scripts/potion_drink_visuals.gd").new()
	root.add_child(motion)
	motion.setup()
	motion.set_time(1.5)
	var adapter: Node3D = motion.right_arm._active_visual
	var rig: Skeleton3D = adapter.skeleton
	var to_bottle: Transform3D = motion.bottle.global_transform.affine_inverse() * rig.global_transform
	var result := {"vertices": [], "bones": [], "glass": []}
	for part: MeshInstance3D in adapter.hand_meshes:
		var matrices: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = rig.find_bone(part.skin.get_bind_name(bind))
			matrices.append(to_bottle * rig.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
		for surf in part.mesh.get_surface_count():
			var a := part.mesh.surface_get_arrays(surf)
			var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / vertices.size()
			for i in vertices.size():
				var point := Vector3.ZERO
				for j in influences:
					var k := i * influences + j
					point += (matrices[bones[k]] * vertices[i]) * weights[k]
				result.vertices.append([point.x, point.y, point.z])
	for i in rig.get_bone_count():
		var point: Vector3 = to_bottle * rig.get_bone_global_pose(i).origin
		result.bones.append([rig.get_bone_name(i), point.x, point.y, point.z])
	var glass: MeshInstance3D = motion.bottle.find_child("Glass", true, false)
	for point in glass.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: result.glass.append([point.x, point.y, point.z])
	FileAccess.open("res://../exports/Potion_Grip_2026-09-15/fit.json", FileAccess.WRITE).store_string(JSON.stringify(result))
	motion.queue_free()
	await process_frame
	print("POTION GRIP FIT TEST PASS")
	quit()
