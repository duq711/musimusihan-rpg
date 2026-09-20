extends SceneTree
const FP = preload("res://scripts/supplied_fp_arm.gd")
func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func _init() -> void: call_deferred("run")
func run() -> void:
	var result := {}
	for side in [-1,1]:
		var arm = FP.new()
		root.add_child(arm)
		assert(arm.setup(side))
		var wrist = Vector3(side*.31,.94,-.075)
		var elbow = Vector3(side*.29,1.19,-.01)
		var shoulder = Vector3(side*.225,1.44,.015)
		var z = (elbow-wrist).normalized()
		var y = Vector3.FORWARD
		y = (y-z*y.dot(z)).normalized()
		var basis = Basis(y.cross(z).normalized(),y,z)
		arm.transform = Transform3D(basis,wrist-basis*arm._hand_build_transform().origin)
		arm.set_relaxed_pose(.25)
		arm.fit_arm(shoulder,elbow)
		var bones := {}
		var rest := {}
		for i in arm.skeleton.get_bone_count():
			bones[arm.skeleton.get_bone_name(i)] = matrix(arm.skeleton.get_bone_global_pose(i))
			rest[arm.skeleton.get_bone_name(i)] = matrix(arm.skeleton.get_bone_global_rest(i))
		var points := {}
		for part in arm.arm_meshes+arm.hand_meshes:
			var posed := []
			for surface in part.mesh.get_surface_count():
				var arrays = part.mesh.surface_get_arrays(surface)
				var verts = arrays[Mesh.ARRAY_VERTEX]
				var joints = arrays[Mesh.ARRAY_BONES]
				var weights = arrays[Mesh.ARRAY_WEIGHTS]
				var stride = weights.size()/verts.size()
				for vi in verts.size():
					var point = Vector3.ZERO
					for wi in stride:
						var slot = vi*stride+wi
						if weights[slot] <= 0: continue
						var bind = joints[slot]
						var name = part.skin.get_bind_name(bind)
						var bone = arm.skeleton.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind)
						point += (arm.skeleton.get_bone_global_pose(bone)*part.skin.get_bind_pose(bind)*verts[vi])*weights[slot]
					point = arm.skeleton.global_transform*point
					posed.append([point.x,point.y,point.z])
			points["Arm" if "_Arm" in str(part.name) else "Hand"] = posed
		result["L" if side<0 else "R"] = {"root":matrix(arm.global_transform),"bones":bones,"rest":rest,"surface_points":points}
		arm.free()
	var f = FileAccess.open("res://../asset-staging/player_fullbody_fp_arms_20260920/pose.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	f.close()
	print("FULLBODY FP POSE EXPORTED")
	quit()
