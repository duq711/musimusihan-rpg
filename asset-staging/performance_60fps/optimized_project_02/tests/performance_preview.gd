extends SceneTree
## Actual gameplay in an unhosted viewport; no native window/input operation.

const FACTORY := preload("res://tests/performance_scene_factory.gd")
const SAMPLER := preload("res://scripts/performance_sampler.gd")
const GEOMETRY_READY := preload("res://tests/art_direction_preview.gd")
const EVIDENCE := preload("res://tests/dark_fantasy_capture_evidence.gd")
const CASES := [
	{"id": "hideout_hearth", "scene": "hideout", "position": Vector3(3.5, 1.65, 5.5), "target": Vector3(0, 0.65, 2.2)},
	{"id": "dungeon_entry", "scene": "dungeon", "position": Vector3(0, 1.72, 13), "target": Vector3(0, 1.4, 3)},
	{"id": "mine_entrance", "scene": "mine", "position": Vector3(0.6, 1.75, 60.1), "target": Vector3(3.356, 0.65, 57.54)},
	{"id": "mine_water_shore", "scene": "mine", "position": Vector3(-57, 1.5, -18), "target": Vector3(-53.9, 0.035, -15.8)},
]
var _diagnostic_draw_count := 0


func _init() -> void:
	print("PERFORMANCE BOOT: script initialized")
	call_deferred("_run")


static func create_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "GameplayPerformanceViewport"
	viewport.size = size
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.audio_listener_enable_2d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Read the playable project's defaults, not the art gallery's MSAA4.
	viewport.msaa_3d = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	viewport.screen_space_aa = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0))
	viewport.use_taa = bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false))
	viewport.use_occlusion_culling = bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false))
	return viewport


static func position_player(game: Node, scenario: Dictionary, target_view: bool = false) -> void:
	var player: DungeonPlayer = game.get("player")
	player.global_position = scenario.position - Vector3(0, 0.67, 0)
	player.velocity = Vector3.ZERO
	player.camera.look_at(scenario.target)
	if target_view:
		var direction := (Vector3(scenario.target) - player.camera.global_position).normalized()
		player.rotation.y = atan2(-direction.x, -direction.z)
		var pitch := clampf(asin(direction.y), deg_to_rad(-82), deg_to_rad(78))
		player.set("_pitch", pitch)
		player.head.rotation.x = pitch
		player.camera.rotation = Vector3.ZERO
	player.viewmodel_renderer.sync_view()


func _run() -> void:
	print("PERFORMANCE BOOT: deferred runner entered")
	if DisplayServer.get_name() != "embedded":
		push_error("Performance preview requires the audited unhosted embedded renderer.")
		quit(2)
		return
	if OS.get_environment("PERFORMANCE_QA_DIAGNOSTIC") == "bootstrap":
		await _bootstrap_probe()
		return
	var iteration := OS.get_environment("PERFORMANCE_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Use a new PERFORMANCE_QA_ITERATION filename.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path("res://artifacts/performance".path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Performance evidence folders are immutable; use a new iteration.")
		quit(2)
		return
	var frames := maxi(30, int(OS.get_environment("PERFORMANCE_QA_FRAMES")))
	if OS.get_environment("PERFORMANCE_QA_FRAMES").is_empty():
		frames = 180
	var warmup := 90
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2560, 1664)]
	if OS.get_environment("PERFORMANCE_QA_RESOLUTION") == "720p":
		sizes = [Vector2i(1280, 720)]
	elif OS.get_environment("PERFORMANCE_QA_RESOLUTION") == "native":
		sizes = [Vector2i(2560, 1664)]
	var selection := OS.get_environment("PERFORMANCE_QA_CASES").split(",", false)
	var motion_enabled := OS.get_environment("PERFORMANCE_QA_MOTION") == "1"
	var target_view := OS.get_environment("PERFORMANCE_QA_CAMERA_POLICY") == "target"
	var effects_diagnostic := OS.get_environment("PERFORMANCE_QA_DIAGNOSTIC") == "effects"
	var original_inventory := ExpeditionSession.get_inventory()
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var original_mouse := Input.mouse_mode
	var original_fps := Engine.max_fps
	var original_low_usage := OS.low_processor_usage_mode
	var original_mute := AudioServer.is_bus_mute(0)
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Benchmark process must own a fresh independent sandbox.")
		quit(2)
		return
	sandbox.begin()
	FACTORY.disable_event_delivery(root)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.frame_post_draw.connect(_diagnostic_drawn)
	var source_hashes := sources()
	print("PERFORMANCE BOOT: sandbox and source snapshot ready")
	var reports: Array[Dictionary] = []
	var failed := false
	for size in sizes:
		for scene_id in ["hideout", "mine", "dungeon"]:
			var relevant: Array[Dictionary] = []
			for scenario in CASES:
				if scenario.scene == scene_id and (selection.is_empty() or scenario.id in selection):
					if effects_diagnostic:
						for variant in ["normal", "ssil_off", "world_shadows_off", "ssao_off"]:
							var diagnostic_case: Dictionary = scenario.duplicate()
							diagnostic_case["diagnostic_variant"] = variant
							relevant.append(diagnostic_case)
					else:
						relevant.append(scenario)
			if relevant.is_empty():
				continue
			sandbox.reset_loadout()
			seed(412560)
			var viewport := create_viewport(size)
			root.add_child(viewport)
			var game := FACTORY.create(scene_id)
			print("PERFORMANCE BUILD: " + scene_id)
			viewport.add_child(game)
			print("PERFORMANCE BUILD COMPLETE: " + scene_id)
			FACTORY.disable_event_delivery(game)
			await physics_frame
			await physics_frame
			if scene_id == "mine" and not await GEOMETRY_READY.await_geometry_ready(game.get("cave_geometry")):
				failed = true
				viewport.free()
				break
			# GPU instance readback is only allowed before warmup, never in the
			# measurement window. Verify actual batch submissions, not a mock.
			var batch_validation := validate_submitted_batches(game)
			failed = failed or not batch_validation.passed
			var dressing_validation: Dictionary = {"passed": true, "not_applicable": true}
			if scene_id == "mine":
				RenderingServer.force_draw(false)
				dressing_validation = GEOMETRY_READY.inspect_detail_rendering(game.get("cave_geometry"))
				failed = failed or not dressing_validation.passed
			var renderer_state := capture_renderer_state(game, viewport)
			for scenario in relevant:
				var variant: String = scenario.get("diagnostic_variant", "normal")
				apply_diagnostic_variant(renderer_state, variant)
				position_player(game, scenario, target_view)
				var host_load_before := host_load_snapshot()
				var motion: Node
				if motion_enabled:
					motion = FACTORY.Motion.new()
					motion.player = game.get("player")
					game.add_child(motion)
				var sampler := SAMPLER.new()
				sampler.begin(SAMPLER.collect_viewports(root))
				var case_warmup := 30 if effects_diagnostic and variant != "normal" else warmup
				for frame in case_warmup:
					await process_frame
					if frame % 30 == 29:
						print("PERFORMANCE WARMUP: %s %s %d/%d" % [scenario.id, variant, frame + 1, case_warmup])
				var before_physics := Engine.get_physics_frames()
				var before_draws := _diagnostic_draw_count
				var before_elapsed := float(game.get("elapsed"))
				var last_tick := Time.get_ticks_usec()
				for frame in frames:
					await process_frame
					var tick := Time.get_ticks_usec()
					sampler.record(float(tick - last_tick) / 1000.0)
					last_tick = tick
				# Everything below is outside the measured frame window.
				sampler.end()
				var camera: Camera3D = game.get("player").camera
				var record := {"id": str(scenario.id), "resolution": [size.x, size.y], "warmup_frames": warmup, "measured_frames": frames, "summary": sampler.summary(), "samples": sampler.samples, "physics_ticks_during_window": Engine.get_physics_frames() - before_physics, "actual_game_elapsed_seconds": float(game.get("elapsed")) - before_elapsed, "player_health": game.get("player").health, "enemy_count": game.find_children("*", "CharacterBody3D", true, false).size() - 1, "camera_transform": var_to_str(camera.global_transform), "camera_fov": camera.fov, "taa": viewport.use_taa, "msaa": viewport.msaa_3d, "occlusion_enabled": viewport.use_occlusion_culling, "player_physics_enabled": game.get("player").is_physics_processing(), "game_process_enabled": game.is_processing(), "game_physics_enabled": game.is_physics_processing()}
				record["scripted_motion"] = motion_enabled
				record["warmup_frames"] = case_warmup
				record["diagnostic_variant"] = variant if effects_diagnostic else "none"
				record["renderer_options"] = renderer_options(renderer_state)
				record["scaling_3d_scale"] = viewport.scaling_3d_scale
				record["scaling_3d_mode"] = viewport.scaling_3d_mode
				record["host_load_before_warmup"] = host_load_before
				record["host_load_after_measurement"] = host_load_snapshot()
				record["gpu_batch_submission_validation"] = batch_validation
				record["gpu_cave_dressing_validation"] = dressing_validation
				record["completed_render_frames_during_window"] = _diagnostic_draw_count - before_draws
				record["gpu_timestamps_available"] = record.summary.render_gpu_ms.p50 > 0.0
				record["camera_policy"] = "Actual production forward (-Z) view at each listed position; local look_at is reset by the production recoil update. Retained for identical baseline framing."
				if target_view:
					record["camera_policy"] = "Target-facing view through actual player body yaw/head pitch; requires a matching target-policy baseline."
				if motion_enabled:
					record["movement_distance_m"] = motion.distance_travelled
					record["actual_attack_requests"] = motion.attack_requests
					record["maximum_yaw_change_radians"] = motion.maximum_yaw_change
					motion.free()
				if record.completed_render_frames_during_window < frames - 2 or record.summary.draw_calls.p50 <= 0.0 or record.actual_game_elapsed_seconds <= 0.0 or Input.mouse_mode != original_mouse or game.has_meta("benchmark_player_died"):
					failed = true
				if RenderingServer.get_current_rendering_driver_name() == "vulkan" and not record.gpu_timestamps_available:
					failed = true
				RenderingServer.force_draw(false)
				var file_name := "%s_%dx%d" % [scenario.id, size.x, size.y]
				if effects_diagnostic:
					file_name = "%s__%s_%dx%d" % [scenario.id, variant, size.x, size.y]
				var screenshot := viewport.get_texture().get_image()
				record["screenshot_file"] = file_name + ".png"
				if screenshot == null or screenshot.save_png(output.path_join(record.screenshot_file)) != OK:
					failed = true
				else:
					record["screenshot_sha256"] = FileAccess.get_sha256(output.path_join(record.screenshot_file))
				if OS.get_environment("PERFORMANCE_QA_CAPTURE_MONITOR") == "1":
					record["performance_monitor_ui"] = await _capture_monitor(sandbox, viewport, output, file_name)
					failed = failed or not record.performance_monitor_ui.passed
				write_json(output.path_join(file_name + ".json"), record)
				record["sample_json_file"] = file_name + ".json"
				record["sample_json_sha256"] = FileAccess.get_sha256(output.path_join(record.sample_json_file))
				record.erase("samples")
				reports.append(record)
				print("PERFORMANCE CASE: %s wall p50 %.2f / p95 %.2f ms; GPU p50 %.2f ms; render CPU p50 %.2f ms" % [file_name, record.summary.wall_ms.p50, record.summary.wall_ms.p95, record.summary.render_gpu_ms.p50, record.summary.render_cpu_ms.p50])
			apply_diagnostic_variant(renderer_state, "normal")
			viewport.free()
			await process_frame
	sandbox.finish()
	Engine.max_fps = original_fps
	OS.low_processor_usage_mode = original_low_usage
	AudioServer.set_bus_mute(0, original_mute)
	var preserved: bool = original_snapshot == ExpeditionSession.capture_snapshot() and original_inventory == ExpeditionSession.get_inventory() and Input.mouse_mode == original_mouse and not sandbox.active
	var unchanged := source_hashes == sources()
	failed = failed or not preserved or not unchanged or reports.is_empty()
	var manifest := {"renderer": RenderingServer.get_current_rendering_driver_name(), "device": RenderingServer.get_video_adapter_name(), "display_driver": DisplayServer.get_name(), "engine_version": Engine.get_version_info(), "processor": OS.get_processor_name(), "processor_count": OS.get_processor_count(), "memory": OS.get_memory_info(), "source_sha256": source_hashes, "source_files_unchanged": unchanged, "expedition_inventory_cursor_preserved": preserved, "frame_budget_ms": SAMPLER.FRAME_BUDGET_MS, "engine_max_fps_during_measurement": 0, "low_processor_usage_during_measurement": false, "vsync": "disabled; unhosted viewport has no screen presentation wait", "scheduling": "low CPU/I/O priority (taskpolicy -b, nice10)", "limitations": ["Unhosted render throughput excludes native window composition, display presentation and input latency.", "Other running desktop apps are preserved and may contend for this shared CPU/GPU; compare repeated paired runs. At baseline another game/editor and busy browser were reported active.", "Native mouse capture is never enabled: production interaction raycasts and capture-gated stress presentation are skipped. Allow headroom for those costs in interactive gameplay.", "Actual inherited gameplay/player/AI/physics/HUD/equipment continue; only native-input scene entry and OS window notifications are bypassed.", "No image readback, force_draw, file writes or sorting occur inside the sample window. Cached renderer counter queries have separately recorded overhead.", "GPU timestamps may lag the sampled engine frame; percentiles represent sustained workload, not matching per-frame CPU/GPU pairs."], "cases": reports, "passed": not failed}
	if OS.get_environment("PERFORMANCE_QA_SCHEDULING") == "normal":
		manifest["scheduling"] = "normal process priority; no native window or input activation"
	manifest["pipeline_disk_cache_enabled"] = ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable", true)
	manifest["diagnostic_only"] = effects_diagnostic
	manifest["diagnostic_policy"] = "One scene instance, normal baseline then one feature disabled at a time; original options restored before cleanup. These diagnostic choices do not change production defaults." if effects_diagnostic else "Production rendering defaults"
	manifest["user_data_directory"] = OS.get_user_data_dir()
	write_json(output.path_join("performance_manifest.json"), manifest)
	print("PERFORMANCE PREVIEW %s: %d real gameplay cases; %s" % ["FAIL" if failed else "PASS", reports.size(), output])
	quit(1 if failed else 0)


static func sources() -> Dictionary:
	var result := EVIDENCE.collect()
	for path in ["res://project.godot", "res://tests/performance_preview.gd", "res://tests/performance_scene_factory.gd", "res://tests/performance_mine_scene.gd", "res://tests/run_embedded_preview.sh", "res://tests/art_direction_preview.gd", "res://tests/cave_detail_submission_checks.gd"]:
		if FileAccess.file_exists(path):
			result[path] = FileAccess.get_sha256(path)
	if FileAccess.file_exists("res://override.cfg"):
		result["res://override.cfg"] = FileAccess.get_sha256("res://override.cfg")
	_hash_lod_sources(result, "res://assets/3d/dark_fantasy/generated_lods")
	return result


func _capture_monitor(sandbox: Node, viewport: SubViewport, output: String, file_name: String) -> Dictionary:
	# This optional UI proof runs only after the benchmark window has ended.
	# The real test-room toggle owns the sampler and its cleanup; the canvas is
	# attached to our unhosted viewport instead of any desktop window.
	if not sandbox.has_method("toggle_performance_monitor"):
		return {"passed": false, "reason": "Production source does not contain the test-room performance monitor"}
	var previous_scene := current_scene
	current_scene = viewport
	sandbox.call("toggle_performance_monitor")
	var overlay: CanvasLayer = sandbox.get("performance_overlay")
	overlay.custom_viewport = viewport
	FACTORY.disable_event_delivery(overlay)
	for frame in 240:
		await process_frame
		if overlay.get("sampler").samples.size() >= 20 and "GPU" in overlay.get("label").text:
			break
	RenderingServer.force_draw(false)
	var path := output.path_join(file_name + "__monitor.png")
	var capture := viewport.get_texture().get_image()
	var result := {"passed": false, "sample_count": overlay.get("sampler").samples.size(), "display_text": overlay.get("label").text, "screenshot_file": path.get_file(), "measured_after_benchmark_window": true}
	var saved := capture != null and capture.save_png(path) == OK
	if saved:
		result["screenshot_sha256"] = FileAccess.get_sha256(path)
	overlay.call("set_enabled", false)
	overlay.custom_viewport = null
	current_scene = previous_scene
	result["cleanup_preserved"] = not overlay.get("enabled") and overlay.get("sampler").viewports.is_empty()
	result.passed = saved and result.sample_count >= 20 and "GPU" in result.display_text and result.cleanup_preserved
	return result


static func _hash_lod_sources(result: Dictionary, folder: String) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".res") or file.ends_with(".json"):
			var path := folder.path_join(file)
			result[path] = FileAccess.get_sha256(path)
	for directory in DirAccess.get_directories_at(folder):
		_hash_lod_sources(result, folder.path_join(directory))


static func validate_submitted_batches(game: Node) -> Dictionary:
	var result := {"passed": true, "batches": 0, "instances": 0, "mismatches": []}
	for node in game.find_children("*", "MultiMeshInstance3D", true, false):
		if not node.has_meta("submitted_transforms"):
			continue
		var batch := node as MultiMeshInstance3D
		var expected: Array = batch.get_meta("submitted_transforms")
		result.batches += 1
		if batch.multimesh.instance_count != expected.size():
			result.mismatches.append(str(batch.get_path()) + ": count")
			continue
		for index in expected.size():
			result.instances += 1
			if not batch.multimesh.get_instance_transform(index).is_equal_approx(expected[index]):
				result.mismatches.append(str(batch.get_path()) + ": transform " + str(index))
	result.passed = result.mismatches.is_empty()
	return result


static func capture_renderer_state(game: Node, viewport: SubViewport) -> Dictionary:
	# own_world_3d creates an inherited world without assigning world_3d's
	# optional override property. Read the actual authored environment node.
	var environments := game.find_children("*", "WorldEnvironment", true, false)
	var environment := (environments[0] as WorldEnvironment).environment
	var result := {"environment": environment, "ssao_enabled": environment.ssao_enabled, "ssil_enabled": environment.ssil_enabled, "lights": []}
	for light in game.find_children("*", "Light3D", true, false):
		if light.layers & (1 << 19) == 0:
			result.lights.append({"node": light, "shadow_enabled": light.shadow_enabled})
	return result


static func apply_diagnostic_variant(state: Dictionary, variant: String) -> void:
	state.environment.ssao_enabled = state.ssao_enabled and variant != "ssao_off"
	state.environment.ssil_enabled = state.ssil_enabled and variant != "ssil_off"
	for item in state.lights:
		item.node.shadow_enabled = item.shadow_enabled and variant != "world_shadows_off"


static func renderer_options(state: Dictionary) -> Dictionary:
	var shadow_lights := 0
	for item in state.lights:
		if item.node.shadow_enabled:
			shadow_lights += 1
	return {"ssao_enabled": state.environment.ssao_enabled, "ssil_enabled": state.environment.ssil_enabled, "world_shadow_lights": shadow_lights}


static func host_load_snapshot() -> Dictionary:
	# Read-only process census outside measured frames. No command lines,
	# document titles or user data are collected, and no app is controlled.
	var output: Array = []
	var result := {"timestamp_utc": Time.get_datetime_string_from_system(true), "benchmark_pid": OS.get_process_id(), "benchmark_cpu_percent": 0.0, "other_process_cpu_percent_sum": 0.0, "other_godot_processes": []}
	if OS.execute("/bin/ps", PackedStringArray(["-axo", "pid=,%cpu=,comm="]), output) != 0:
		result["available"] = false
		return result
	result["available"] = true
	for row in str(output[0]).split("\n", false):
		var columns := row.strip_edges().split(" ", false)
		if columns.size() < 3:
			continue
		var pid := int(columns[0])
		var cpu := float(columns[1])
		if pid == OS.get_process_id():
			result.benchmark_cpu_percent = cpu
		else:
			result.other_process_cpu_percent_sum += cpu
			if row.ends_with("/Godot"):
				result.other_godot_processes.append({"pid": pid, "cpu_percent": cpu})
	return result


func _bootstrap_probe() -> void:
	var viewport := create_viewport(Vector2i(256, 256))
	root.add_child(viewport)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	viewport.add_child(mesh)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position.z = 3.0
	camera.current = true
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	RenderingServer.frame_post_draw.connect(_diagnostic_drawn)
	print("PERFORMANCE DIAGNOSTIC: primitive ready; no force_draw")
	var started := Time.get_ticks_msec()
	for frame in 30:
		await process_frame
		if frame % 5 == 4:
			print("PERFORMANCE DIAGNOSTIC: frame %d physics %d gpu %.6f cpu %.3f drawcalls %d completed_draws %d elapsed %d" % [frame + 1, Engine.get_physics_frames(), RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()), RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), _diagnostic_draw_count, Time.get_ticks_msec() - started])
	print("PERFORMANCE PREVIEW PASS: bootstrap diagnostic only, no production FPS claim")
	quit(0)


func _diagnostic_drawn() -> void:
	_diagnostic_draw_count += 1


static func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t") + "\n")
