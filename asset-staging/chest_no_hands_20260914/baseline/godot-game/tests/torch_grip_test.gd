extends SceneTree
const BASE = preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures.append(message)
func key(p: Vector3) -> String:
	return str(roundi(p.x*100000))+","+str(roundi(p.y*100000))+","+str(roundi(p.z*100000))
func run():
	var saved=ExpeditionSession.capture_snapshot(); var mouse=Input.mouse_mode
	var sandbox=root.get_node("TestRoomSandbox"); sandbox.begin()
	var viewport=BASE.create_viewport();root.add_child(viewport)
	var f=BASE.populate_viewport(viewport);var p=f.player
	await physics_frame;await physics_frame
	check(BASE.configure_pose(f,"torch_safe_zone"),"real torch fixture")
	check(p.torch_arm.visible and not p.left_support_arm.visible and not p.shield_arm.visible,"one visible left hand owns torch")
	check(p.torch_arm.detailed_visual.get_meta("source_model","")=="res://assets/3d/player/hands_detailed/left_hand_torch.glb","torch owns separate corrected left skin")
	check(p.right_relaxed_arm.detailed_visual.get_meta("source_model","")=="res://assets/3d/player/hands_detailed/right_hand_detailed.glb","right hand keeps original source")
	var torch_transform: Transform3D=p.torch_pivot.transform
	var expected: Transform3D=p.torch_arm.transform
	for profile in ["greybox","detailed","original"]:
		check(p.set_hands_visual_profile(profile),"profile available")
		p._update_character_arms()
		check(p.torch_pivot.transform==torch_transform,"hand profile cannot move shaft")
		if profile!="greybox":check(p.torch_arm.transform.is_equal_approx(expected),"authored torch frame restored")
	p.torch_arm.reset_pose();p._update_character_arms()
	check(is_equal_approx(p.torch_arm.get_joint_snapshot().angles_radians.thumb.x, p.TORCH_GRIP.JOINT_ANGLES.thumb.x),"torch restores authored thumb root after reset")
	for speed in [0.,p.WALK_SPEED,p.SPRINT_SPEED]:
		p.velocity=Vector3(0,0,-speed)
		for i in 18:p._update_viewmodel(1./60.)
		check(p.torch_arm.transform.is_equal_approx(expected),"shaft-relative grip locked during locomotion")
		check(p.get_first_person_motion_snapshot().hand_contacts.torch.error<0.00001,"torch contact frame preserved")
		var angle: float=p.get_first_person_motion_snapshot().joint_landmarks.torch.wrist_angle_degrees
		print("TORCH WRIST angle_degrees=",angle)
		check(angle<25.0,"forearm and hand longitudinal axes stay within 25 degrees during locomotion")
	p.set_torch_enabled(false);p._update_character_arms()
	check(not p.torch_arm.visible and p.left_support_arm.visible,"extinguish restores free left hand")
	p.set_torch_enabled(true);p._update_character_arms()
	check(p.torch_arm.visible and not p.left_support_arm.visible,"relight restores one torch hand")
	var utility=p.inventory_model.equipment.get("utility", "")
	p.inventory_model.equipment["utility"]="";p._refresh_hand_visibility();p._update_viewmodel(.2)
	check(not p.torch_arm.visible,"unequipping utility releases torch hand")
	p.inventory_model.equipment["utility"]=utility;p._refresh_hand_visibility()
	for i in 30:p._update_viewmodel(1./60.)
	check(p.torch_arm.visible and p.torch_arm.transform.is_equal_approx(expected),"equipping utility restores authored grip through transition")
	audit_surface(p)
	viewport.queue_free();await process_frame;sandbox.finish()
	check(saved==ExpeditionSession.capture_snapshot() and mouse==Input.mouse_mode,"fixture restores actual expedition and cursor")
	await audit_testroom()
	if failures.is_empty():print("TORCH GRIP PASS: actual skin/shaft clearance and six pad contacts, unique left hand, motion lock, profile/reset/relight restoration and playable testroom lifecycle")
	else:
		for e in failures:push_error(e)
	quit(0 if failures.is_empty() else 1)
func audit_surface(p):
	var adapter=p.torch_arm.detailed_visual
	var skel: Skeleton3D=adapter.skeleton
	var source=JSON.parse_string(FileAccess.get_file_as_string("res://tests/torch_grip_contact_samples.json"))
	var wanted={};var found={}
	for label in source:
		found[label]=[]
		for a in source[label].bind_points_godot:
			wanted[key(Vector3(a[0],a[1],a[2]))]=label
	var handle: MeshInstance3D=p.torch_pivot.find_child("WoodenTorch",true,false)
	var hv: PackedVector3Array=handle.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rings={}
	for v in hv:
		var a: Vector3=p.torch_pivot.to_local(handle.to_global(v));var y=snappedf(a.y,.005)
		rings[y]=maxf(rings.get(y,0.),Vector2(a.x,a.z).length())
	var levels=rings.keys();levels.sort()
	var minimum=INF;var count=0;var bodies=0;var nails=0
	for mesh in adapter.hand_meshes:
		if str(mesh.name).begins_with("Nail_"):nails+=1;continue
		if not str(mesh.name).begins_with("Supplied_"):continue
		bodies+=1
		var matrices=[]
		for b in mesh.skin.get_bind_count():
			var bone=mesh.skin.get_bind_bone(b)
			if bone<0:bone=skel.find_bone(str(mesh.skin.get_bind_name(b)))
			matrices.append(skel.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(b))
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var stride=int(bones.size()/vertices.size());var shapes=[]
			for j in mesh.get_blend_shape_count():
				var amount=mesh.get_blend_shape_value(j)
				if absf(amount)>.000001:shapes.append([amount,mesh.mesh.surface_get_blend_shape_arrays(surface)[j][Mesh.ARRAY_VERTEX]])
			for i in vertices.size():
				var v=vertices[i]
				for shape in shapes:v+=(shape[1][i]-vertices[i] if mesh.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[1][i])*shape[0]
				var point=Vector3.ZERO
				for slot in stride:
					var e=i*stride+slot
					if weights[e]>0:point+=(matrices[bones[e]]*v)*weights[e]
				var a: Vector3=p.torch_pivot.to_local(mesh.to_global(point))
				var radius: float=rings[levels[0]]
				for j in range(1,levels.size()):
					if a.y<=levels[j]:
						radius=lerpf(rings[levels[j-1]],rings[levels[j]],inverse_lerp(levels[j-1],levels[j],a.y));break
				var clearance=Vector2(a.x,a.z).length()-radius
				minimum=minf(minimum,clearance);count+=1
				var k=key(vertices[i])
				if wanted.has(k):found[wanted[k]].append(clearance)
	check(bodies==1 and nails==5,"actual torch model is one skin and five nails")
	check(count>22000 and minimum>=-.0002,"actual skin must stay outside shaft: "+str(minimum))
	for label in found:
		var values: Array=found[label]
		check(values.size()>=12,"actual imported pad samples found: "+label)
		if not values.is_empty():
			check(values.min()>=-.0002 and values.max()<.003,"pad contact within3mm: "+label+" "+str(values.min())+".."+str(values.max()))
			print("TORCH PAD ",label," samples=",values.size()," min/max_m=",values.min(),"/",values.max())
	print("TORCH SKIN vertices=",count," minimum_clearance_m=",minimum)
func audit_testroom():
	var snapshot=ExpeditionSession.capture_snapshot();var mouse=Input.mouse_mode
	var room=(load("res://test_room.tscn") as PackedScene).instantiate();root.add_child(room);current_scene=room
	await process_frame
	for i in 2:
		room.run_feature("motion_torch");room.player.set_physics_process(false)
		await physics_frame;await physics_frame
		room.player._update_character_arms()
		check(room.player.torch_arm.visible and room.player.get_first_person_motion_snapshot().left_hand_role=="torch","testroom entry runs actual torch grip")
		check(room.inventory!=snapshot.get("inventory"),"testroom inventory isolated")
		room._show_test_panel()
	room.queue_free();await process_frame
	root.get_node("TestRoomSandbox").finish();paused=false
	check(ExpeditionSession.capture_snapshot()==snapshot and Input.mouse_mode==mouse,"testroom restores original state")
