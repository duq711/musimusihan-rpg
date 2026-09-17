extends SceneTree
## Private production fixture, no window, hardware input, focus, or desktop capture.
const BASE = preload("res://tests/player_arm_preview.gd")
var output: String
var records: Array = []
var active_player: DungeonPlayer
var failures: Array[String] = []
const SOURCES = ["res://assets/3d/player/hands_detailed/left_hand_torch.glb","res://tests/torch_grip_preview.gd","res://scripts/player.gd","res://scripts/player_arm_visual.gd","res://scripts/greybox_arm_visual.gd","res://scripts/torch_grip_pose.gd","res://assets/3d/player/hands_detailed/left_hand_detailed.glb","res://assets/3d/dark_fantasy/iron_cage_torch.glb"]
func hashes() -> Dictionary:
	var result = {}
	for path in SOURCES: result[path]=FileAccess.get_sha256(path)
	return result
func _init():
	call_deferred("run")
func vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]
func mat(t: Transform3D) -> Array:
	return [vec(t.basis.x),vec(t.basis.y),vec(t.basis.z),vec(t.origin)]
func run():
	if DisplayServer.get_name() != "embedded":
		quit(2); return
	var iteration = OS.get_environment("TORCH_GRIP_QA_ITERATION")
	if iteration.is_empty() or not iteration.is_valid_filename():
		quit(2); return
	output = ProjectSettings.globalize_path("res://artifacts/visual_qa/torch_grip/"+iteration)
	if DirAccess.dir_exists_absolute(output):
		push_error("Preserving existing captures"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input = true; root.physics_object_picking = false
	AudioServer.set_bus_mute(0,true)
	var saved = ExpeditionSession.capture_snapshot(); var mouse = Input.mouse_mode; var initial_hashes=hashes()
	var sandbox = root.get_node("TestRoomSandbox"); sandbox.begin()
	var viewport = BASE.create_viewport(); root.add_child(viewport)
	var fixture = BASE.populate_viewport(viewport); var player = fixture.player; active_player=player
	await physics_frame; await physics_frame
	BASE.configure_pose(fixture,"torch_safe_zone")
	var arm = player.torch_arm
	var adapter = arm.detailed_visual
	var skel: Skeleton3D = adapter.skeleton
	var report = {"arm_in_torch":mat(arm.transform),"adapter_in_arm":mat(adapter.transform),"skeleton_in_adapter":mat(adapter.global_transform.affine_inverse()*skel.global_transform),"bones":{},"torch_meshes":[],"wrist_chain":player.get_first_person_motion_snapshot().joint_landmarks.get("torch",{})}
	for b in skel.get_bone_count():
		report.bones[skel.get_bone_name(b)]={"rest":mat(skel.get_bone_global_rest(b)),"pose":mat(skel.get_bone_global_pose(b)),"rotation":[skel.get_bone_pose_rotation(b).x,skel.get_bone_pose_rotation(b).y,skel.get_bone_pose_rotation(b).z,skel.get_bone_pose_rotation(b).w]}
	for mesh in player.torch_pivot.find_children("*","MeshInstance3D",true,false):
		if arm.is_ancestor_of(mesh): continue
		report.torch_meshes.append({"name":str(mesh.name),"transform":mat(player.torch_pivot.global_transform.affine_inverse()*mesh.global_transform),"aabb_position":vec(mesh.get_aabb().position),"aabb_size":vec(mesh.get_aabb().size)})
	var file = FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	if OS.get_environment("TORCH_GRIP_QA_SWEEP")=="1":
		var rest: Transform3D=arm.transform
		for angle in [90,135,180]:
			arm.transform=Transform3D(Basis(Vector3.UP,deg_to_rad(float(angle))),Vector3.ZERO)*rest
			var shoulder: Vector3=player.camera.to_global(Vector3(-.29,-.34,.10))
			var pole: Vector3=player.camera.global_basis*Vector3(-.65,-.85,.14)
			arm.fit_arm(shoulder,player.MOTION.elbow(shoulder,arm.global_position,pole))
			player.viewmodel_renderer.sync_view()
			await capture(viewport,"rotation_"+str(angle))
		arm.transform=rest; player._update_character_arms()
	await capture(viewport,"game_torch")
	if OS.get_environment("TORCH_GRIP_QA_FINAL")=="1":
		for mode in ["walk","sprint"]:
			player.velocity=Vector3(0,0,-player.WALK_SPEED if mode=="walk" else -player.SPRINT_SPEED)
			for i in 21: player._update_viewmodel(1./60.)
			player.viewmodel_renderer.sync_view()
			await capture(viewport,mode)
		player.set_torch_enabled(false); player._update_character_arms()
		player.set_torch_enabled(true); player.velocity=Vector3.ZERO
		for i in 45: player._update_viewmodel(1./60.)
		player.viewmodel_renderer.sync_view()
		await capture(viewport,"relight")
		player.torch_fill.visible=false; player.torch.visible=false
		player.torch_flame.visible=false
	var target: Vector3 = player.torch_pivot.to_global(Vector3(0,.12,0))
	var direction: Vector3 = (player.camera.global_position-target).normalized()
	var camera = Camera3D.new(); fixture.stage.add_child(camera)
	camera.cull_mask = 1<<19; camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = .36; camera.near = .01
	camera.global_position = target+direction*.7; camera.look_at(target,Vector3.UP); camera.make_current()
	var light = DirectionalLight3D.new(); light.layers=1<<19; light.light_cull_mask=1<<19; light.light_energy=1.2; fixture.stage.add_child(light); light.global_rotation=camera.global_rotation
	await capture(viewport,"closeup")
	var materials = {}
	for mesh in arm.find_children("*","MeshInstance3D",true,false):
		materials[mesh]=mesh.material_override
		var m = StandardMaterial3D.new(); m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color=Color(.18,.62,.92) if str(mesh.name).begins_with("Supplied_") else Color(.1,.9,.4) if str(mesh.name).begins_with("Nail_") else Color(.9,.15,.22) if str(mesh.name).begins_with("WristCuff") else Color(.25,.25,.25)
		mesh.material_override=m
	await capture(viewport,"part_ids")
	for mesh in materials: mesh.material_override=materials[mesh]
	camera.global_position=target+direction.rotated(Vector3.UP,PI*.5)*.7; camera.look_at(target,Vector3.UP); light.global_rotation=camera.global_rotation
	await capture(viewport,"side")
	camera.global_position=target-direction*.7; camera.look_at(target,Vector3.UP); light.global_rotation=camera.global_rotation
	await capture(viewport,"opposite")
	viewport.queue_free(); await process_frame; sandbox.finish()
	var preserved = saved==ExpeditionSession.capture_snapshot() and mouse==Input.mouse_mode and initial_hashes==hashes() and failures.is_empty()
	file=FileAccess.open(output.path_join("capture_manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":records,"failures":failures,"source_sha256":initial_hashes,"sources_unchanged":initial_hashes==hashes(),"actual_renderer":RenderingServer.get_current_rendering_driver_name(),"display_driver":DisplayServer.get_name(),"desktop_capture":false,"state_preserved":preserved,"hand_sha256":FileAccess.get_sha256("res://assets/3d/player/hands_detailed/left_hand_detailed.glb")},"\t")); file.close()
	print("TORCH GRIP PREVIEW "+("PASS" if preserved else "FAIL")+": "+output)
	quit(0 if preserved else 1)
func capture(viewport: SubViewport,label: String):
	for i in 16: await process_frame
	RenderingServer.force_draw(false)
	var im = viewport.get_texture().get_image(); var path=output.path_join(label+".png")
	assert(im!=null and not im.is_empty()); assert(im.save_png(path)==OK)
	var cuff: Dictionary=active_player.torch_arm.get_wrist_snapshot()
	var cuff_ok: bool=bool(cuff.get("enabled",false)) and float(cuff.get("minimum_jacobian_determinant",-1))>0 and int(cuff.get("invalid_vertex_count",1))==0
	if not cuff_ok: failures.append("Invalid torch cuff deformation: "+label)
	records.append({"image":label+".png","sha256":FileAccess.get_sha256(path),"cuff_valid":cuff_ok,"cuff_minimum_jacobian":cuff.get("minimum_jacobian_determinant"),"cuff_invalid_vertices":cuff.get("invalid_vertex_count")})
	print("TORCH CAPTURE "+label)
