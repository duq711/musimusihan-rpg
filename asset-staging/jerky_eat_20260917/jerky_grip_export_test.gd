extends SceneTree

func vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
func trans(t: Transform3D) -> Array: return [vec(t.basis.x),vec(t.basis.y),vec(t.basis.z),vec(t.origin)]
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var arm = load("res://scripts/player_arm_visual.gd").new()
	root.add_child(arm)
	arm.setup(1)
	var visual = arm._active_visual
	var rig: Skeleton3D = visual.skeleton
	var data := {"bones":[],"parts":[],"axes":{},"rig_transform":trans(rig.global_transform)}
	for i in rig.get_bone_count():
		data.bones.append({"name":rig.get_bone_name(i),"parent":rig.get_bone_parent(i),"rest":trans(rig.get_bone_rest(i)),"pose":trans(rig.get_bone_pose(i))})
	for key in visual._axes: data.axes[key]=vec(visual._axes[key])
	for part in visual.hand_meshes:
		var a=part.mesh.surface_get_arrays(0)
		var p={"name":part.name,"vertices":[],"normals":[],"bones":Array(a[Mesh.ARRAY_BONES]),"weights":Array(a[Mesh.ARRAY_WEIGHTS]),"binds":[],"indices":Array(a[Mesh.ARRAY_INDEX])}
		for v in a[Mesh.ARRAY_VERTEX]:p.vertices.append(vec(v))
		for v in a[Mesh.ARRAY_NORMAL]:p.normals.append(vec(v))
		for i in part.skin.get_bind_count():
			var bone=part.skin.get_bind_bone(i)
			if bone < 0: bone=rig.find_bone(part.skin.get_bind_name(i))
			p.binds.append({"bone":bone,"transform":trans(part.skin.get_bind_pose(i))})
		data.parts.append(p)
	var model=load("res://assets/3d/items/beef_jerky/beef_jerky_variants.glb").instantiate()
	var food=model.find_child("Jerky_01_long_torn_strip",true,false)
	var fa=food.mesh.surface_get_arrays(0)
	data.food={"vertices":[],"indices":Array(fa[Mesh.ARRAY_INDEX])}
	for v in fa[Mesh.ARRAY_VERTEX]:data.food.vertices.append(vec(v))
	var f=FileAccess.open("res://../asset-staging/jerky_eat_20260917/hand_export.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(data));f.close()
	var fit=JSON.parse_string(FileAccess.get_file_as_string("res://../asset-staging/jerky_eat_20260917/grip_fit.json"))
	for d in fit.pose:
		var v=fit.pose[d]
		arm.set_digit_flexion(d,Vector3(v[0],v[1],v[2]))
	for vertex_index in [156,17]:
		var part: MeshInstance3D=visual.hand_meshes[0]
		var arrays=part.mesh.surface_get_arrays(0)
		var point=Vector3.ZERO
		for j in 4:
			var k=vertex_index*4+j
			var binding=arrays[Mesh.ARRAY_BONES][k]
			var bone=part.skin.get_bind_bone(binding)
			if bone < 0:bone=rig.find_bone(part.skin.get_bind_name(binding))
			point+=(rig.get_bone_global_pose(bone)*part.skin.get_bind_pose(binding)*arrays[Mesh.ARRAY_VERTEX][vertex_index])*arrays[Mesh.ARRAY_WEIGHTS][k]
		print("PAD ",vertex_index," ",rig.to_global(point))
	model.free();arm.free()
	print("JERKY GRIP EXPORT TEST PASS")
	quit()
