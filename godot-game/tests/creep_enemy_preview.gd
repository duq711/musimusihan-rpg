extends SceneTree
const CREEP := preload("res://scripts/creep_enemy.gd")
func _init():call_deferred("run")
func run():
	if DisplayServer.get_name() != "embedded":quit(2);return
	var tag:=OS.get_environment("CREEP_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):quit(2);return
	var path:=ProjectSettings.globalize_path("res://artifacts/visual_qa/creep/"+tag)
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
	var creep:=CREEP.new();creep.position.y=.9;world.add_child(creep);creep.set_physics_process(false)
	var cam:=Camera3D.new();world.add_child(cam);cam.position=Vector3(3,2.3,-4.5);cam.look_at(Vector3(0,1.0,0));cam.fov=40;cam.current=true
	var captures=[]
	var sequence := OS.get_environment("CREEP_QA_SEQUENCE") == "1"
	if sequence:
		captures = await capture_sequence(view, creep, cam, path)

	var poses: Array = [] if sequence else ["front","side","back","walk","bite","punch_right","punch_left","hit","death"]
	for pose: String in poses:
		cam.position=Vector3(0,1.5,-4.6)
		if pose=="side":cam.position=Vector3(4.6,1.8,0)
		if pose=="back":cam.position=Vector3(0,1.8,4.6)
		cam.look_at(Vector3(0,1.0,0))
		creep._set_state(DungeonEnemy.AIState.IDLE);creep.state_time=.5
		if pose=="walk":creep._set_state(DungeonEnemy.AIState.CHASE);creep.state_time=.35
		if pose in ["bite", "punch_right", "punch_left"]:
			creep.attack_index = 0 if pose == "bite" else 1
			creep._set_state(DungeonEnemy.AIState.ACTIVE)
			creep.state_time = .18 if pose == "bite" else (.06 if pose == "punch_right" else .34)
		if pose=="hit":creep._set_state(DungeonEnemy.AIState.STAGGER);creep.state_time=.25
		if pose=="death":creep._set_state(DungeonEnemy.AIState.DEAD);creep.state_time=5
		creep._update_visual_pose(0)
		for i in 6:await process_frame
		RenderingServer.force_draw(false)
		assert(view.get_texture().get_image().save_png(path.path_join(pose+".png"))==OK)
		captures.append({"pose":pose,"state":creep.get_creep_snapshot()})
	view.queue_free();await process_frame
	if not sequence: await capture_mine(path)
	sandbox.finish()
	assert(before==ExpeditionSession.capture_snapshot() and cursor==Input.mouse_mode)
	var file:=FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"captures":captures,"sequence":sequence,"fps":30 if sequence else 0,"preserved_session_cursor":true,"source_sha256":FileAccess.get_sha256(CREEP.MODEL_PATH)},"\t"))
	print("CREEP ENEMY PREVIEW PASS: ",path)
	quit()

func capture_mine(path: String) -> void:
	var view:=SubViewport.new();view.size=Vector2i(1280,720);view.own_world_3d=true;view.gui_disable_input=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var mine: Node=load("res://tests/performance_scene_factory.gd").create("mine")
	view.add_child(mine)
	load("res://tests/item_detail_preview.gd").stop_external_execution(mine)
	var creep: Node3D
	for actor in mine.get_children():
		if actor.get_meta("enemy_archetype", "") == "creep":creep=actor;break
	assert(creep != null and mine.enemies_alive == 6)
	# Keep the actual authored spawn and existing cave lights/materials.
	var eye:=creep.global_position+Vector3(0,.7,-3.4)
	load("res://tests/performance_preview.gd").position_player(mine,{"position":eye,"target":creep.global_position+Vector3(0,.65,0)},true)
	creep._face_direction((mine.player.global_position-creep.global_position).normalized(),1)
	creep._set_state(DungeonEnemy.AIState.IDLE);creep.state_time=.5;creep._update_visual_pose(0)
	for i in 30:
		mine.player._update_viewmodel(1.0/60.0)
		mine.player._update_torch(1.0/60.0)
		await process_frame
	mine.player.viewmodel_renderer.sync_view()
	for i in 8:await process_frame
	RenderingServer.force_draw(false)
	assert(view.get_texture().get_image().save_png(path.path_join("mine_encounter.png"))==OK)
	mine.suspend_stress_effects();view.queue_free();await process_frame


func capture_sequence(view: SubViewport, actor: Node3D, camera: Camera3D, path: String) -> Array:
	var reel := preload("res://tests/creep_motion_reel.gd")
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var code_hash := FileAccess.get_sha256("res://scripts/creep_enemy.gd")
	view.size = Vector2i(1280, 720)
	camera.position = Vector3(2.25, 1.65, -4.60)
	camera.look_at(Vector3(0, 1.12, 0))
	camera.fov = 37
	actor.move_speed = 2.2 # Same authored movement setting as the live mine encounter.
	var canvas := CanvasLayer.new()
	view.add_child(canvas)
	var heading := Label.new()
	heading.position = Vector2(38, 24)
	heading.add_theme_font_override("font", preload("res://assets/fonts/NotoSansKR-Variable.ttf"))
	heading.add_theme_font_size_override("font_size", 25)
	heading.text = "CREEP  |  게임에 적용된 모션"
	canvas.add_child(heading)
	var title := Label.new()
	title.position = Vector2(38, 590)
	title.add_theme_font_override("font", heading.get_theme_font("font"))
	title.add_theme_font_size_override("font_size", 30)
	canvas.add_child(title)
	var note := Label.new()
	note.position = Vector2(40, 638)
	note.add_theme_font_override("font", heading.get_theme_font("font"))
	note.add_theme_font_size_override("font_size", 19)
	note.modulate = Color(.78, .84, .88)
	canvas.add_child(note)
	var directory := path.path_join("frames")
	DirAccess.make_dir_recursive_absolute(directory)
	var samples: Array = []
	var frame_index := 0
	for segment: Dictionary in reel.SEGMENTS:
		title.text = segment.title
		note.text = segment.note
		for frame in ceili(float(segment.duration) * reel.FPS):
			var pose := reel.sample(actor, segment.id, float(frame) / reel.FPS)
			for settle in 2: await process_frame
			RenderingServer.force_draw(false)
			var filename := "%05d.png" % frame_index
			assert(view.get_texture().get_image().save_png(directory.path_join(filename)) == OK)
			samples.append({"frame": frame_index, "segment": segment.id, "pose": pose})
			frame_index += 1
		print("CREEP REEL SEGMENT: ", segment.id, " / frames: ", frame_index)
	assert(source_hash == FileAccess.get_sha256(CREEP.MODEL_PATH))
	assert(code_hash == FileAccess.get_sha256("res://scripts/creep_enemy.gd"))
	return samples
