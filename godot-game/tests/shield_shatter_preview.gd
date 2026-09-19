extends "res://tests/shield_damage_preview.gd"
## The last successful production block breaks the carried shield into actual
## world-space rigid bodies. Only the player's viewing pitch is choreographed.
const SHATTER_OUTPUT := "res://artifacts/visual_qa/shield_shatter"
const SHATTER_FRAMES := 240
const SHATTER_TICKS := 480
const HIT_TICK := 48
const LOOK_START := .9
const LOOK_END := 1.7
const LOOK_PITCH := -1.20
const SHATTER_SOURCES := [
	"res://tests/shield_shatter_preview.gd", "res://tests/shield_shatter_preview.gd.uid",
	"res://scripts/shield_shatter.gd", "res://scripts/player.gd",
	"res://assets/3d/player/shield_damage/round_shield_fragments.glb",
	"res://assets/3d/player/shield_damage/round_shield_fragments.glb.import",
	"res://shaders/shield_fracture_wood.gdshader", "res://project.godot",
]
const SHATTER_STAGES := {"ready": 2, "last_intact": 46, "break": 50, "burst": 64, "floor": 180, "settled": 480}

class ShatterDriver extends Node:
	var player: DungeonPlayer
	var tick := 0
	var original_pitch := 0.0
	var hit_result: Dictionary = {}
	var before_hit: Dictionary = {}
	var after_hit: Dictionary = {}
	var actual_hit_count := 0

	func _physics_process(delta: float) -> void:
		tick += 1
		player.advance_action_timers(delta)
		player.advance_combat_state(delta, tick <= HIT_TICK)
		if tick == HIT_TICK:
			before_hit = {"durability": player.get_shield_damage_snapshot(),
				"shatter": player.get_shield_shatter_snapshot(), "health": player.health,
				"model_transform": player.shield_model.global_transform, "camera": player.camera.global_transform}
			hit_result = player.receive_attack(40.0, player.global_position - player.global_basis.z * 2.0)
			actual_hit_count += 1
			after_hit = {"shatter": player.get_shield_shatter_snapshot(), "health": player.health,
				"offhand": player.inventory_model.equipment.get("offhand", "")}
		# A recorded camera inspection, not movement applied to the fragments.
		var time := float(tick) / 60.0
		var blend := clampf((time - LOOK_START) / (LOOK_END - LOOK_START), 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		player._pitch = lerpf(original_pitch, LOOK_PITCH, blend)
		player.head.rotation.x = player._pitch
		player._update_viewmodel(delta)
		player._update_torch(delta)
		player.viewmodel_renderer.sync_view()
		if tick >= SHATTER_TICKS: set_physics_process(false)


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Shield shatter preview requires the reviewed embedded runner with --fixed-fps 30.")
		quit(2)
		return
	var iteration := OS.get_environment("SHIELD_SHATTER_QA_ITERATION").strip_edges()
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Set SHIELD_SHATTER_QA_ITERATION to a new plain folder name.")
		quit(2)
		return
	var directory := ProjectSettings.globalize_path(SHATTER_OUTPUT.path_join(iteration))
	if DirAccess.dir_exists_absolute(directory):
		push_error("Previous shatter captures will not be overwritten.")
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Shatter preview requires its own isolated test-room session.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create shatter capture directory.")
		quit(2)
		return
	var stills_only := OS.get_environment("SHIELD_SHATTER_QA_STILLS") == "1"
	if not stills_only: _check(DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) == OK, "video frame directory created")
	root.gui_disable_input = true
	root.physics_object_picking = false
	var audio_before := AudioServer.is_bus_mute(0)
	var cursor_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var fingerprint_before := STUDIO.PREVIEW.inventory_fingerprint(session_before.inventory)
	AudioServer.set_bus_mute(0, true)
	var source_paths: Array = STUDIO.PREVIEW.SOURCE_FILES.duplicate()
	source_paths.append_array(STUDIO.SOURCES)
	source_paths.append_array(SOURCES)
	source_paths.append_array(SHATTER_SOURCES)
	var hashes := {}
	for path: String in source_paths:
		hashes[path] = FileAccess.get_sha256(path)
		_check(str(hashes[path]).length() == 64, "capture dependency exists: " + path)
	var previous_hz := Engine.physics_ticks_per_second
	var previous_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(previous_steps, 8)
	sandbox.begin()
	var viewport := STUDIO.create_studio_viewport()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var fixture := STUDIO.PREVIEW.populate_viewport(viewport)
	var world: Node3D = fixture.stage
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_add_physical_floor(world)
	await physics_frame
	await physics_frame
	_check(STUDIO.configure_pose(fixture, "guard"), "actual first-person guard pose is available")
	STUDIO.configure_studio(fixture)
	inventory.set_equipment_durability("offhand", 5.0)
	player.block_time = .6
	var initial_health := player.health
	var player_position := player.global_position
	var initial_damage := player.get_shield_damage_snapshot()
	_check(initial_damage.get("visual_stage", "") == "low" and is_equal_approx(float(initial_damage.get("current", -1)), 5.0), "actual damaged shield starts with five durability")
	_check(int(player.get_shield_shatter_snapshot().get("fragment_count", -1)) == 0, "no fragments before the last block")
	var starting_materials := _materials(player.shield_model)
	_check(bool(starting_materials.valid) and int(starting_materials.fracture_shader_surfaces) > 0, "initial shield uses the actual fracture grain shader")
	var driver := ShatterDriver.new()
	driver.player = player
	driver.original_pitch = player._pitch
	driver.set_physics_process(false)
	world.add_child(driver)
	driver.set_physics_process(false)
	var label := _label(viewport, "내구도 5 · 마지막 방어 → 방패 파손")
	for warm in 8:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
	driver.set_physics_process(true)
	var records: Array[Dictionary] = []
	var stills := {}
	var stages := {}
	var previous_tick := -1
	var all_ground_contacts := {}
	var peak_fragment_count := 0
	for frame in SHATTER_FRAMES:
		await process_frame
		if previous_tick >= 0: _check(driver.tick - previous_tick == 2, "two actual gameplay physics ticks per 30 fps frame")
		previous_tick = driver.tick
		var shatter := player.get_shield_shatter_snapshot()
		var count := int(shatter.get("fragment_count", 0))
		peak_fragment_count = maxi(peak_fragment_count, count)
		for body: Dictionary in shatter.get("bodies", []):
			if bool(body.get("ground_contact", false)): all_ground_contacts[body.id] = true
		var state_caption := "마지막 방어 · 내구도 5" if driver.tick < HIT_TICK else ("실제 물리 파편 · 낙하" if driver.tick < 180 else "바닥 충돌 · 흩어진 파편")
		label.text = "%s\n%.2f초 · 파편 %d개" % [state_caption, float(driver.tick) / 60.0, count]
		var record := {"frame": frame, "physics_tick": driver.tick, "shatter": shatter,
			"health": player.health, "stamina": player.stamina, "offhand": inventory.equipment.get("offhand", ""),
			"production": player.get_first_person_motion_snapshot(), "camera": player.camera.global_transform,
			"camera_pitch": player._pitch, "player_position": player.global_position}
		var pending: Array[String] = []
		for stage_name: String in SHATTER_STAGES:
			if not stages.has(stage_name) and driver.tick >= int(SHATTER_STAGES[stage_name]):
				stages[stage_name] = record
				pending.append(stage_name)
		if not stills_only or not pending.is_empty():
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			_check(pixels != null and not pixels.is_empty() and pixels.get_size() == IMAGE_SIZE, "actual shatter GPU pixels exist")
			if pixels != null and not pixels.is_empty():
				if not stills_only: _check(pixels.save_jpg(directory.path_join("frames/%05d.jpg" % frame), .94) == OK, "actual GPU video frame saved")
				for stage_name: String in pending:
					var filename := stage_name + ".png"
					_check(pixels.save_png(directory.path_join(filename)) == OK, "actual GPU phase saved: " + stage_name)
					stills[stage_name] = {"file": filename, "frame": frame, "physics_tick": driver.tick}
		_check(player.global_position.is_equal_approx(player_position), "player position stays fixed while camera pitch inspects the floor")
		if driver.tick < HIT_TICK:
			_check(count == 0 and str(inventory.equipment.get("offhand", "")) == "round_shield", "shield is intact before the actual final hit")
		else:
			_check(int(shatter.get("spawn_count", -1)) == 1, "final block spawns exactly one shatter event")
			_check(str(inventory.equipment.get("offhand", "")).is_empty(), "broken offhand item is removed")
			_check(not bool(record.production.get("shield_visible", true)), "original carried shield no longer renders after breaking")
		records.append(record)
	var final_shatter := player.get_shield_shatter_snapshot()
	_check(driver.tick == SHATTER_TICKS and records.size() == SHATTER_FRAMES, "eight seconds of continuous actual physics captured")
	_check(stills.size() == SHATTER_STAGES.size(), "six requested GPU stills captured")
	_check(driver.actual_hit_count == 1, "exactly one actual receive_attack call triggered wear")
	_check(bool(driver.hit_result.get("blocked", false)) and bool(driver.hit_result.get("shield_guard", false)) and is_zero_approx(float(driver.hit_result.get("damage", -1))), "the breaking hit is still fully blocked by the shield")
	_check(is_equal_approx(player.health, initial_health), "last shield block preserves player health")
	_check(peak_fragment_count >= 20 and peak_fragment_count <= 32, "twenty to thirty-two actual rigid fragments spawned")
	_check(int(final_shatter.get("fragment_count", 0)) == peak_fragment_count, "physical fragments remain until the recorded floor inspection")
	var fragment_contract: Array[Dictionary] = []
	for entry: Dictionary in final_shatter.get("bodies", []):
		var body := instance_from_id(int(entry.id)) as RigidBody3D
		_check(body != null, "snapshot identifies an actual RigidBody3D")
		if body == null: continue
		_check(body.collision_mask == 2 and body.get_world_3d() == world.get_world_3d(), "fragment collides with WORLD2 in the actual gameplay world")
		var meshes := body.find_children("*", "MeshInstance3D", true, false)
		_check(not meshes.is_empty(), "rigid fragment has actual three-dimensional geometry")
		for mesh: MeshInstance3D in meshes:
			_check(mesh.layers == 1, "fragment renders in world layer one rather than the equipment overlay")
		fragment_contract.append({"id": body.get_instance_id(), "collision_mask": body.collision_mask,
			"mesh_count": meshes.size(), "global_transform": body.global_transform})
	var settled := _inspect_settled(final_shatter)
	_check(int(settled.below_floor) == 0, "no fragment fell through the physical floor")
	_check(int(settled.settled_count) >= ceili(float(peak_fragment_count) * .75), "at least three quarters of fragments contact the floor and settle")
	_check(all_ground_contacts.size() >= ceili(float(peak_fragment_count) * .75), "actual collision snapshots record floor contact")
	if stages.has("break") and stages.has("settled"):
		_check(_mean_height(stages["break"].shatter) - _mean_height(stages.settled.shatter) > .3, "actual rigid fragments fall from the carried shield toward the floor")
	var driver_record := {"original_pitch": driver.original_pitch, "before_hit": driver.before_hit,
		"after_hit": driver.after_hit, "hit_result": driver.hit_result}
	player.clear_shield_fragments()
	await physics_frame
	await process_frame
	var cleared := player.get_shield_shatter_snapshot()
	_check(int(cleared.get("fragment_count", -1)) == 0 and not bool(cleared.get("active", true)), "explicit fragment cleanup removes all physics bodies")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	Engine.physics_ticks_per_second = previous_hz
	Engine.max_physics_steps_per_frame = previous_steps
	AudioServer.set_bus_mute(0, audio_before)
	var preserved := session_before == ExpeditionSession.capture_snapshot() and cursor_before == Input.mouse_mode and fingerprint_before == STUDIO.PREVIEW.inventory_fingerprint(session_before.inventory)
	_check(preserved, "original expedition, inventory and cursor are restored")
	var sources_preserved := true
	for path: String in hashes:
		if hashes[path] != FileAccess.get_sha256(path): sources_preserved = false
	_check(sources_preserved, "consumed sources stay unchanged during capture")
	var manifest := {"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(),
		"resolution": [IMAGE_SIZE.x, IMAGE_SIZE.y], "fps": FPS, "physics_hz": 60, "duration_seconds": 8.0,
		"frame_count": records.size(), "saved_video_frames": 0 if stills_only else records.size(), "stills_only": stills_only,
		"capture_scope": "Actual production player, last shield block and world rigid bodies in the isolated studio; no desktop capture or external input.",
		"camera_motion": {"kind": "recorded inspection pitch only", "start_seconds": LOOK_START, "end_seconds": LOOK_END,
			"from_pitch": driver_record.original_pitch, "to_pitch": LOOK_PITCH, "curve": "smoothstep", "translation": "fixed player location", "debris_transforms_overridden": false},
		"floor": {"top_y": 0.0, "collision_layer": 2, "size": Vector3(80, .2, 80)},
		"source_sha256": hashes, "sources_unchanged_during_capture": sources_preserved, "session_inventory_cursor_preserved": preserved,
		"initial_shield": initial_damage, "initial_materials": starting_materials, "hit_tick": HIT_TICK,
		"before_hit": driver_record.before_hit, "after_hit": driver_record.after_hit, "hit_result": driver_record.hit_result,
		"stills": stills, "stages": stages, "frames": records, "settled": settled,
		"actual_fragment_contract": fragment_contract,
		"unique_floor_contacts": all_ground_contacts.size(), "cleanup": cleared, "failures": failures}
	var report := FileAccess.open(directory.path_join("capture_manifest.json"), FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: _check(false, "capture manifest saved")
	for failure: String in failures: push_error(failure)
	print("SHIELD SHATTER PREVIEW %s: one actual final block, %d fragments, six stills, %d frames; %s" % ["PASS" if failures.is_empty() else "FAIL", peak_fragment_count, 0 if stills_only else SHATTER_FRAMES, directory])
	quit(0 if failures.is_empty() else 1)


static func _add_physical_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "ShieldFragmentsWorldFloor"
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	floor_body.position.y = -.1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, .2, 80)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)


static func _inspect_settled(shatter: Dictionary) -> Dictionary:
	var settled := 0
	var below := 0
	var maximum_speed := 0.0
	var minimum_bottom := INF
	for body: Dictionary in shatter.get("bodies", []):
		var velocity: Vector3 = body.get("linear_velocity", Vector3.ZERO)
		var speed := velocity.length()
		var bottom := float(body.get("bottom_y", INF))
		maximum_speed = maxf(maximum_speed, speed)
		minimum_bottom = minf(minimum_bottom, bottom)
		if bottom < -.025: below += 1
		if bool(body.get("ground_contact", false)) and bottom < .15 and (bool(body.get("sleeping", false)) or speed < .15): settled += 1
	return {"settled_count": settled, "below_floor": below, "maximum_linear_speed": maximum_speed, "minimum_bottom_y": minimum_bottom}


static func _mean_height(shatter: Dictionary) -> float:
	var bodies: Array = shatter.get("bodies", [])
	if bodies.is_empty(): return 0.0
	var total := 0.0
	for body: Dictionary in bodies:
		var position: Vector3 = body.get("position", Vector3.ZERO)
		total += position.y
	return total / bodies.size()
