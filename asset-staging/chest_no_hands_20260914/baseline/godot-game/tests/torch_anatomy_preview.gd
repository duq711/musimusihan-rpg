extends "res://tests/torch_grip_preview.gd"
const CONTACT = preload("res://tests/contact_visual_preview.gd")
func pose_signature(arm):
	var skel=arm.detailed_visual.skeleton
	var a=[]
	for i in skel.get_bone_count():a.append(skel.get_bone_pose(i))
	return str(arm.global_transform)+str(a)
func run():
	if DisplayServer.get_name()!="embedded":quit(2);return
	var iteration=OS.get_environment("TORCH_ANATOMY_ITERATION")
	if not iteration.is_valid_filename():quit(2);return
	output=ProjectSettings.globalize_path("res://artifacts/visual_qa/torch_anatomy/"+iteration)
	if DirAccess.dir_exists_absolute(output):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input=true;root.physics_object_picking=false;AudioServer.set_bus_mute(0,true)
	var saved=ExpeditionSession.capture_snapshot();var mouse=Input.mouse_mode;var initial_hashes=hashes()
	var sandbox=root.get_node("TestRoomSandbox");sandbox.begin()
	var vp=BASE.create_viewport();root.add_child(vp);var f=BASE.populate_viewport(vp);var p=f.player;active_player=p
	await physics_frame;await physics_frame
	BASE.configure_pose(f,"torch_safe_zone")
	p._torch_time=0;p._update_torch(0)
	await capture(vp,"studio_game")
	p.torch.visible=false;p.torch_fill.visible=false;p.torch_flame.visible=false
	var arm=p.torch_arm;var adapter=arm.detailed_visual
	for other in [p.weapon_pivot,p.shield_pivot,p.support_arm_root]:other.visible=false
	for mesh in p.torch_pivot.find_children("*","MeshInstance3D",true,false):
		if not arm.is_ancestor_of(mesh) and not (str(mesh.name).begins_with("WoodenTorch") or str(mesh.name).begins_with("CharredHandle") or str(mesh.name).begins_with("LeatherWrap")):mesh.visible=false
	var center:Vector3=arm.to_global(Vector3(0,.015,-.06))
	var camera=Camera3D.new();f.stage.add_child(camera);camera.cull_mask=1<<19;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.31;camera.near=.01
	var key=DirectionalLight3D.new();key.layers=1<<19;key.light_cull_mask=1<<19;key.light_energy=1.0;f.stage.add_child(key)
	var fill=OmniLight3D.new();fill.layers=1<<19;fill.light_cull_mask=1<<19;fill.light_energy=.6;fill.omni_range=2;f.stage.add_child(fill);fill.global_position=center+arm.global_basis.y*.45
	var dirs={"top":arm.global_basis.y,"bottom":-arm.global_basis.y,"left":arm.global_basis.x,"right":-arm.global_basis.x}
	var signature=pose_signature(arm)
	for name in dirs:
		camera.global_position=center+dirs[name]*.65;camera.look_at(center,-arm.global_basis.z);camera.make_current();key.global_rotation=camera.global_rotation
		await capture(vp,"fixed_"+name)
		if pose_signature(arm)!=signature:failures.append("Pose moved between angles")
	var torch_meshes=[]
	for m in p.torch_pivot.find_children("*","MeshInstance3D",true,false):
		if not arm.is_ancestor_of(m):torch_meshes.append(m);m.visible=false
	camera.global_position=center+(arm.global_basis.y+arm.global_basis.x*.65).normalized()*.65;camera.look_at(center,-arm.global_basis.z);key.global_rotation=camera.global_rotation
	await capture(vp,"grip_no_torch_skin")
	var skin_materials={}
	for m in adapter.hand_meshes:
		if str(m.name).begins_with("Supplied_"):
			skin_materials[m]=m.material_override
			var soft=m.get_active_material(0).duplicate() as StandardMaterial3D
			if soft!=null:soft.normal_scale*=.65;m.material_override=soft
	await capture(vp,"grip_no_torch_soft_normal")
	for m in skin_materials:m.material_override=skin_materials[m]
	var mats={}
	for m in adapter.hand_meshes:
		mats[m]=m.material_override
		var material=StandardMaterial3D.new();material.albedo_color=Color(.42,.42,.42);material.roughness=.88;m.material_override=material
	for mode in ["grip","rest"]:
		if mode=="rest":adapter.reset_pose()
		for name in dirs:
			camera.global_position=center+dirs[name]*.65;camera.look_at(center,-arm.global_basis.z);key.global_rotation=camera.global_rotation
			await capture(vp,mode+"_gray_no_torch_"+name)
	adapter.set_torch_grip()
	for m in mats:m.material_override=mats[m]
	var measures={"pose_fixed_between_angles":pose_signature(arm)==signature,"arm_transform":mat(arm.transform),"wrist":p.get_first_person_motion_snapshot().joint_landmarks.get("torch",{})}
	vp.queue_free();await process_frame
	# Same production cave, camera, light clock and motion sample in both runs.
	vp=CONTACT.create_viewport();root.add_child(vp);p=CONTACT.populate_viewport(vp);active_player=p
	var inv=ExpeditionInventory.new();inv.seed_default_loadout();p.bind_inventory(inv)
	await physics_frame;await physics_frame
	CONTACT.configure_shot(p,{"name":"torch_anatomy","position":Vector3(.6,1.75,60.1),"target":Vector3(3.356,.65,57.54),"equipment":true})
	p.configure_safe_zone(true);p._update_viewmodel(1.0);p._torch_time=0;p._update_torch(0);p.viewmodel_renderer.sync_view()
	await capture(vp,"game_full")
	var im=vp.get_texture().get_image();var crop=im.get_region(Rect2i(160,480,300,240));crop.save_png(output.path_join("game_hand_crop.png"))
	measures["game_camera"]=mat(p.camera.global_transform);measures["camera_fov"]=p.camera.fov
	measures["torch_light_energy"]=p.torch.light_energy;measures["torch_fill_energy"]=p.torch_fill.light_energy
	vp.queue_free();await process_frame;sandbox.finish()
	var preserved=saved==ExpeditionSession.capture_snapshot() and mouse==Input.mouse_mode and initial_hashes==hashes()
	if not preserved:failures.append("State or sources changed")
	var file=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"captures":records,"failures":failures,"source_hashes":initial_hashes,"measures":measures,"preserved":preserved,"renderer":RenderingServer.get_current_rendering_driver_name()},"\t"));file.close()
	print("TORCH ANATOMY PREVIEW "+("PASS" if failures.is_empty() else "FAIL")+": "+output);quit(0 if failures.is_empty() else 1)
