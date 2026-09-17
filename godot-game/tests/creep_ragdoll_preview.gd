extends SceneTree
## Actual gameplay death under continuous 60 Hz physics, recorded at 30 fps.
## Run only through the reviewed embedded runner after the headless tests pass.
const CREEP := preload("res://scripts/creep_enemy.gd")
const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const FPS := 30
const PHYSICS_HZ := 60
const FRAME_COUNT := 210
const HIT_FRAME := 15
const SOURCES := [
	"res://scripts/creep_enemy.gd",
	"res://scripts/creep_ragdoll.gd",
	"res://scripts/creep_ragdoll_pose.gd",
	"res://scripts/enemy.gd",
	"res://tests/creep_ragdoll_preview.gd",
	"res://project.godot",
	CREEP.MODEL_PATH,
]
const CASES := [
	{"id": "side_impact", "title": "01  측면 충격 · 벽  /  SIDE IMPACT · WALL", "from": Vector3(-3, 0.9, 0), "wall_position": Vector3(1.35, 1.25, 0.20), "wall_size": Vector3(0.16, 2.5, 4.5)},
	{"id": "front_impact", "title": "02  정면 충격 · 바닥  /  FRONT IMPACT · FLOOR", "from": Vector3(0, 0.9, -3), "wall_position": Vector3(0.20, 1.25, 4.0), "wall_size": Vector3(4.5, 2.5, 0.16)},
]

var failures: Array[String] = []
var samples: Array[Dictionary] = []
var scenarios: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Creep ragdoll preview requires the audited embedded runner with --fixed-fps 30.")
		quit(2)
		return
	var tag := OS.get_environment("CREEP_RAGDOLL_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):
		push_error("Set CREEP_RAGDOLL_QA_ITERATION to a new output directory name.")
		quit(2)
		return
	if not CREEP.is_available():
		push_error("Install the licensed Creep model before running its ragdoll preview.")
		quit(2)
		return
	var directory := ProjectSettings.globalize_path("res://artifacts/visual_qa/creep_ragdoll/" + tag)
	if DirAccess.dir_exists_absolute(directory):
		push_error("The ragdoll preview does not overwrite an existing capture.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) != OK:
		push_error("Could not create the ragdoll capture directory.")
		quit(2)
		return

	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_was_active: bool = sandbox.active
	if sandbox_was_active:
		push_error("Ragdoll preview requires its own isolated test-room session.")
		quit(2)
		return
	var hashes_before := _source_hashes()
	var original_physics_hz := Engine.physics_ticks_per_second
	var original_max_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.max_physics_steps_per_frame = maxi(8, original_max_steps)
	sandbox.begin()

	for scenario: Dictionary in CASES:
		var viewport := _create_viewport()
		root.add_child(viewport)
		var fixture := _create_fixture(viewport, scenario)
		# Compile shaders and settle the standing capsule before recording.
		# The actor's actual _physics_process stays enabled throughout.
		for warmup in 12:
			await process_frame
			await RenderingServer.frame_post_draw
		await _record_scenario(viewport, fixture, scenario, directory)
		viewport.queue_free()
		await process_frame
		print("CREEP RAGDOLL SCENARIO: ", scenario.id, " / ", FRAME_COUNT, " frames")

	sandbox.finish()
	Engine.physics_ticks_per_second = original_physics_hz
	Engine.max_physics_steps_per_frame = original_max_steps
	var hashes_after := _source_hashes()
	var session_preserved := session_before == ExpeditionSession.capture_snapshot()
	var cursor_preserved := cursor_before == Input.mouse_mode
	var sandbox_preserved: bool = sandbox.active == sandbox_was_active
	_check(session_preserved, "Original expedition changed during ragdoll capture.")
	_check(cursor_preserved, "Cursor mode changed during ragdoll capture.")
	_check(sandbox_preserved, "Test-room sandbox was not restored.")
	_check(hashes_before == hashes_after, "Model or production code changed during capture.")
	_check(samples.size() == FRAME_COUNT * CASES.size(), "The capture sequence is incomplete.")
	var manifest := {
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"resolution": [1280, 720], "fps": FPS, "physics_hz": PHYSICS_HZ,
		"fixed_fps_argument": 30, "frame_count": samples.size(),
		"duration_seconds": float(samples.size()) / FPS,
		"simulation": "Continuous production _physics_process, 2 real physics ticks per saved frame; no pose seeking or manual physics calls.",
		"capture_scope": "Isolated GPU-rendered studio fixture; no desktop capture, hardware input, OS focus or audio.",
		"floor_grid_spacing_m": 0.5, "fatal_hit": {"damage": 1000, "charge": 1.0, "headshot": false, "frame": HIT_FRAME},
		"source_hashes_before": hashes_before, "source_hashes_after": hashes_after,
		"source_files_unchanged": hashes_before == hashes_after,
		"session_preserved": session_preserved, "cursor_preserved": cursor_preserved,
		"sandbox_preserved": sandbox_preserved,
		"scenarios": scenarios, "frames": samples, "failures": failures,
	}
	var output := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if output == null:
		_check(false, "Could not save the capture manifest.")
	else:
		output.store_string(JSON.stringify(_json_safe(manifest), "\t"))
		output.close()
	print("CREEP RAGDOLL PREVIEW %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)

func _record_scenario(viewport: SubViewport, fixture: Dictionary, scenario: Dictionary, directory: String) -> void:
	var actor: Node3D = fixture.actor
	var label: Label = fixture.status
	var prior_physics_frame := -1
	var first_physics_frame := -1
	var case_samples: Array[Dictionary] = []
	var phase_frames := {"living": [], "reaction": [], "simulating": [], "settled": []}
	var tick_errors := 0
	var fatal_hits := 0
	for frame in FRAME_COUNT:
		# SceneTree.process_frame follows the ordinary physics callbacks. With
		# --fixed-fps 30, PNG/GPU wall-clock cost cannot skip simulation ticks.
		await process_frame
		if frame == HIT_FRAME:
			actor.receive_hit(1000.0, scenario["from"], 1.0, false)
			fatal_hits += 1
		var physics_tick := int(Engine.get_physics_frames())
		if first_physics_frame < 0:
			first_physics_frame = physics_tick
		var physics_delta := 0 if prior_physics_frame < 0 else physics_tick - prior_physics_frame
		if prior_physics_frame >= 0 and physics_delta != PHYSICS_HZ / FPS:
			tick_errors += 1
		prior_physics_frame = physics_tick
		var snapshot: Dictionary = actor.get_creep_snapshot()
		var ragdoll: Dictionary = snapshot.get("ragdoll", {})
		var phase: String = ragdoll.get("phase", "missing")
		var time_seconds := float(frame) / FPS
		var death_seconds := maxf(0.0, float(frame - HIT_FRAME) / FPS)
		label.text = "%s  |  %.2f s  |  60 Hz physics · 30 fps" % [_phase_label(phase), time_seconds]
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var filename := "frames/%05d.png" % samples.size()
		_check(image != null and not image.is_empty(), "Empty GPU image in " + scenario.id)
		if image != null and not image.is_empty():
			_check(image.save_png(directory.path_join(filename)) == OK, "Could not save " + filename)
		var sample := {
			"frame": samples.size(), "scenario": scenario.id, "scenario_frame": frame,
			"file": filename, "scenario_seconds": time_seconds, "death_seconds": death_seconds,
			"physics_frame": physics_tick, "physics_ticks_since_previous": physics_delta,
			"scenario_physics_seconds": float(physics_tick - first_physics_frame) / PHYSICS_HZ,
			"phase": phase, "snapshot": snapshot,
		}
		samples.append(sample)
		case_samples.append(sample)
		if phase_frames.has(phase):
			phase_frames[phase].append(frame)

	_check(tick_errors == 0, "%s: %d frames did not advance exactly two physics ticks." % [scenario.id, tick_errors])
	_check(fatal_hits == 1, scenario.id + ": expected exactly one actual fatal hit.")
	for phase: String in phase_frames:
		_check(not phase_frames[phase].is_empty(), scenario.id + ": missing real phase " + phase)
	_check(case_samples.back().phase == "settled", scenario.id + ": body did not settle within the recorded duration.")
	var stills := {}
	var choices := {
		"pre": HIT_FRAME - 1,
		"react": _nearest_phase_frame(phase_frames.reaction, HIT_FRAME + 2),
		"collapse": _nearest_phase_frame(phase_frames.simulating, HIT_FRAME + 21),
		"settled": _nearest_phase_frame(phase_frames.settled, FRAME_COUNT - 1),
	}
	for name: String in choices:
		var selected: int = choices[name]
		if selected < 0:
			continue
		var filename: String = scenario.id + "_" + name + ".png"
		var sample: Dictionary = case_samples[selected]
		_check(DirAccess.copy_absolute(directory.path_join(sample.file), directory.path_join(filename)) == OK, "Could not save still " + filename)
		stills[name] = {"file": filename, "scenario_frame": selected, "phase": sample.phase, "death_seconds": sample.death_seconds}
	scenarios.append({
		"id": scenario.id, "title": scenario.title, "impact_from": scenario["from"],
		"wall_center": scenario.wall_position, "wall_size": scenario.wall_size,
		"camera_position": fixture.camera.position, "camera_target": Vector3(0.1, 0.8, 0.2),
		"camera_fov": fixture.camera.fov, "phase_frames": phase_frames,
		"physics_tick_errors": tick_errors, "fatal_hit_count": fatal_hits,
		"stills": stills, "final_snapshot": case_samples.back().snapshot,
	})

func _create_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	return viewport

func _create_fixture(viewport: SubViewport, scenario: Dictionary) -> Dictionary:
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.085, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.84, 0.90, 1.0)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -34, 0)
	key.light_color = Color(1.0, 0.96, 0.90)
	key.light_energy = 1.6
	key.light_angular_distance = 8.0
	key.shadow_enabled = true
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 2.8, -2.2)
	fill.light_color = Color(0.78, 0.87, 1.0)
	fill.light_energy = 2.0
	fill.omni_range = 10.0
	fill.light_size = 1.0
	world.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.5, 3.2, 1.8)
	rim.light_color = Color(1.0, 0.89, 0.76)
	rim.light_energy = 2.0
	rim.omni_range = 7.0
	rim.light_size = 0.8
	world.add_child(rim)
	_add_solid(world, "Floor", Vector3(8, 0.2, 8), Vector3(0, -0.1, 0), Color(0.19, 0.21, 0.23))
	_add_solid(world, "ContactWall", scenario.wall_size, scenario.wall_position, Color(0.24, 0.27, 0.30))
	var grid_material := _material(Color(0.31, 0.34, 0.36))
	for index in range(-7, 8):
		var offset := float(index) * 0.5
		_add_grid_line(world, Vector3(0, 0.003, offset), Vector3(7, 0.002, 0.008), grid_material)
		_add_grid_line(world, Vector3(offset, 0.003, 0), Vector3(0.008, 0.002, 7), grid_material)
	var actor := CREEP.new()
	actor.position = Vector3(0, 0.90, 0)
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	world.add_child(actor)
	var camera := Camera3D.new()
	camera.position = Vector3(-3.8, 2.6, -5.3)
	camera.fov = 43.0
	world.add_child(camera)
	camera.look_at(Vector3(0.1, 0.8, 0.2))
	camera.current = true
	var canvas := CanvasLayer.new()
	viewport.add_child(canvas)
	_add_label(canvas, "CREEP  |  실제 물리 사망  /  PHYSICS DEATH", Vector2(34, 20), 24)
	_add_label(canvas, scenario.title, Vector2(34, 595), 27)
	var status := _add_label(canvas, "", Vector2(36, 638), 18)
	status.modulate = Color(0.79, 0.85, 0.91)
	_add_label(canvas, "0.5 m grid", Vector2(1118, 28), 17)
	return {"world": world, "actor": actor, "camera": camera, "status": status}

func _add_solid(parent: Node3D, object_name: String, size: Vector3, center: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = center
	body.collision_layer = DungeonEnemy.WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	body.add_child(mesh)
	parent.add_child(body)

func _add_grid_line(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = center
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _add_label(parent: CanvasLayer, text: String, position: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _phase_label(phase: String) -> String:
	match phase:
		"living": return "대기 / IDLE"
		"reaction": return "충격 반응 / HIT REACTION"
		"simulating": return "물리 낙하 / RAGDOLL FALL"
		"settled": return "정착 / SETTLED"
	return "확인 필요 / UNKNOWN"

func _nearest_phase_frame(frames: Array, target: int) -> int:
	var nearest := -1
	for value: int in frames:
		if nearest < 0 or absi(value - target) < absi(nearest - target):
			nearest = value
	return nearest

func _source_hashes() -> Dictionary:
	var hashes := {}
	for source: String in SOURCES:
		var value := FileAccess.get_sha256(source)
		_check(not value.is_empty(), "Could not hash source " + source)
		hashes[source] = value
	return hashes

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _json_safe(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	if value is Transform3D:
		return {"origin": _json_safe(value.origin), "basis": [_json_safe(value.basis.x), _json_safe(value.basis.y), _json_safe(value.basis.z)]}
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _json_safe(value[key])
		return result
	if value is Array:
		var result := []
		for entry: Variant in value:
			result.append(_json_safe(entry))
		return result
	return value
