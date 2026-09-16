extends SceneTree
const ORC := preload("res://scripts/orc_enemy.gd")
func _init():call_deferred("run")
func run():
	if DisplayServer.get_name() != "embedded":quit(2);return
	var tag:=OS.get_environment("ORC_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):quit(2);return
	var path:=ProjectSettings.globalize_path("res://artifacts/visual_qa/orc/"+tag)
	if DirAccess.dir_exists_absolute(path):quit(2);return
	DirAccess.make_dir_recursive_absolute(path)
	root.gui_disable_input=true;root.physics_object_picking=false;AudioServer.set_bus_mute(0,true)
	var before:=ExpeditionSession.capture_snapshot();var cursor:=Input.mouse_mode
	var sandbox:=root.get_node("TestRoomSandbox");sandbox.begin()
	var view:=SubViewport.new();view.size=Vector2i(1000,1000);view.own_world_3d=true;view.gui_disable_input=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world:=Node3D.new();view.add_child(world)
	var env:=WorldEnvironment.new();var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.065,.078,.088);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.85,.9,1);e.ambient_light_energy=.65;e.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.environment=e;world.add_child(env)
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=2.0;light.shadow_enabled=true
	var fill:=OmniLight3D.new();world.add_child(fill);fill.position=Vector3(2,3,1);fill.omni_range=8;fill.light_energy=2
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor_mesh.mesh=plane;world.add_child(floor_mesh)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.15,.17,.18);mat.roughness=1;floor_mesh.material_override=mat
	var orc:=ORC.new();orc.position.y=.9;world.add_child(orc);orc.set_physics_process(false)
	var cam:=Camera3D.new();world.add_child(cam);cam.position=Vector3(3,2.3,-4.5);cam.look_at(Vector3(0,1.0,0));cam.fov=40;cam.current=true
	var captures=[]
	var poses: Array = ["front","side","back","run","attack1","attack2","attack3","hit","death"]
	if OS.get_environment("ORC_QA_SCOPE") == "timing":
		poses.clear()
		for clip in ["atack1","atack2","atack3","gethit"]:
			for frame in 10: poses.append(clip+"_"+str(frame))
	for pose: String in poses:
		cam.position=Vector3(0,1.8,-4.6)
		if pose=="side":cam.position=Vector3(4.6,1.8,0)
		if pose=="back":cam.position=Vector3(0,1.8,4.6)
		cam.look_at(Vector3(0,1.0,0))
		orc._set_state(DungeonEnemy.AIState.IDLE);orc.state_time=.5
		if pose=="run":orc._set_state(DungeonEnemy.AIState.CHASE);orc.state_time=.35
		if pose.begins_with("attack"):
			orc.attack_index=int(pose.right(1))-1;orc._set_state(DungeonEnemy.AIState.ACTIVE);orc.state_time=.09
		if pose=="hit":orc._set_state(DungeonEnemy.AIState.STAGGER);orc.state_time=.25
		if pose=="death":orc._set_state(DungeonEnemy.AIState.DEAD);orc.state_time=5
		orc._update_visual_pose(0)
		if "_" in pose:
			var parts:=pose.split("_");var clip:=parts[0]
			orc.animation_player.play(clip)
			orc.animation_player.seek(orc.animation_player.get_animation(clip).length*float(parts[1])/10.0,true)
		for i in 6:await process_frame
		RenderingServer.force_draw(false)
		assert(view.get_texture().get_image().save_png(path.path_join(pose+".png"))==OK)
		captures.append({"pose":pose,"state":orc.get_orc_snapshot()})
	view.queue_free();await process_frame
	if OS.get_environment("ORC_QA_SCOPE") != "timing": await capture_mine(path)
	sandbox.finish()
	assert(before==ExpeditionSession.capture_snapshot() and cursor==Input.mouse_mode)
	var file:=FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"captures":captures,"preserved_session_cursor":true,"source_sha256":FileAccess.get_sha256("res://assets/3d/enemies/orc/orc.scn")},"\t"))
	print("ORC ENEMY PREVIEW PASS: ",path)
	quit()

func capture_mine(path: String) -> void:
	var view:=SubViewport.new();view.size=Vector2i(1280,720);view.own_world_3d=true;view.gui_disable_input=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var mine: Node=load("res://tests/performance_scene_factory.gd").create("mine")
	view.add_child(mine)
	load("res://tests/item_detail_preview.gd").stop_external_execution(mine)
	var orc: Node3D
	for actor in mine.get_children():
		if actor.get_meta("enemy_archetype", "") == "orc":orc=actor;break
	assert(orc != null)
	# Keep the actual authored spawn and existing cave lights/materials.
	var eye:=orc.global_position+Vector3(0,.7,-3.4)
	load("res://tests/performance_preview.gd").position_player(mine,{"position":eye,"target":orc.global_position+Vector3(0,.65,0)},true)
	orc._face_direction((mine.player.global_position-orc.global_position).normalized(),1)
	orc._set_state(DungeonEnemy.AIState.IDLE);orc.state_time=.5;orc._update_visual_pose(0)
	for i in 30:
		mine.player._update_viewmodel(1.0/60.0)
		mine.player._update_torch(1.0/60.0)
		await process_frame
	mine.player.viewmodel_renderer.sync_view()
	for i in 8:await process_frame
	RenderingServer.force_draw(false)
	assert(view.get_texture().get_image().save_png(path.path_join("mine_encounter.png"))==OK)
	mine.suspend_stress_effects();view.queue_free();await process_frame
