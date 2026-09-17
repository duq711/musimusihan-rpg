extends "res://tests/torch_grip_preview.gd"
const CONTACT = preload("res://tests/contact_visual_preview.gd")
func run():
	if DisplayServer.get_name() != "embedded":quit(2);return
	output=ProjectSettings.globalize_path("res://artifacts/visual_qa/wooden_torch_unity_flipbook")
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input=true; AudioServer.set_bus_mute(0,true)
	var saved=ExpeditionSession.capture_snapshot();var mouse=Input.mouse_mode
	var sandbox=root.get_node("TestRoomSandbox");sandbox.begin()
	var vp=CONTACT.create_viewport();root.add_child(vp)
	var p=CONTACT.populate_viewport(vp);active_player=p
	var inv=ExpeditionInventory.new();inv.seed_default_loadout();p.bind_inventory(inv)
	await physics_frame;await physics_frame
	CONTACT.configure_shot(p,{"name":"wooden","position":Vector3(.6,1.75,60.1),"target":Vector3(3.356,.65,57.54),"equipment":true})
	p.configure_safe_zone(true);p._update_viewmodel(1.0);p._torch_time=0;p._update_torch(0);p.viewmodel_renderer.sync_view()
	await create_timer(1.0).timeout
	await capture(vp,"game_full")
	await create_timer(.5).timeout
	await capture(vp,"game_fire_later")
	p.set_torch_enabled(false);p._update_character_arms();await capture(vp,"extinguished")
	p.set_torch_enabled(true);p._update_character_arms();await capture(vp,"relit")
	# Fixed torch; move only a separate inspection camera around the oil-soaked cloth.
	var camera := Camera3D.new();p.get_parent().add_child(camera)
	camera.cull_mask=1<<19;camera.fov=48;camera.near=.01
	var center:Vector3=p.torch_pivot.to_global(Vector3(0,.73,0))
	var key:=DirectionalLight3D.new();key.layers=1<<19;key.light_cull_mask=1<<19;key.light_energy=.7;p.get_parent().add_child(key)
	for side in [1.0,-1.0]:
		camera.global_position=center+p.camera.global_basis.z*.78*side
		camera.look_at(center,Vector3.UP);camera.make_current();key.global_rotation=camera.global_rotation
		p.viewmodel_renderer.sync_view()
		await capture(vp,"cloth_front" if side>0 else "cloth_back")
	vp.queue_free();await process_frame;sandbox.finish()
	if saved!=ExpeditionSession.capture_snapshot() or mouse!=Input.mouse_mode:failures.append("State not preserved")
	var file=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":records,"failures":failures},"\t"));file.close()
	print("WOODEN TORCH PREVIEW "+("PASS" if failures.is_empty() else "FAIL"));quit(0 if failures.is_empty() else 1)
