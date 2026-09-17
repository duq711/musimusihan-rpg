extends SceneTree

const AUDIO := preload("res://scripts/stress_audio.gd")
const PROFILE := preload("res://scripts/stress_profile.gd")

var failures: Array[String] = []


class CapturedPerception:
	extends StressPerception
	var simulated_capture := true
	func _has_input_capture() -> bool:
		# Headless DisplayServer measures VISIBLE even after requesting capture.
		# Only this test adapter supplies the missing display capability; the
		# production capture guard is checked independently below.
		return simulated_capture if DisplayServer.get_name() == "headless" else super._has_input_capture()


func _init() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("STRESS INPUT CAPTURE MEASUREMENT: display=", DisplayServer.get_name(), " requested=", Input.MOUSE_MODE_CAPTURED, " actual=", Input.mouse_mode)
	call_deferred("_run")


func _run() -> void:
	_test_synthesized_audio()
	await _test_thresholds_and_playback()
	await _test_noncombat_vision_and_rng()
	await _test_suspension_and_threshold_cleanup()
	await _test_wall_and_floor_safety()
	await _test_cadence_and_large_delta()
	await _test_real_input_capture_guard()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("STRESS PERCEPTION TEST PASS: bounded synthetic PCM/playback, thresholds, noncombat afterimage, RNG/session/aim isolation, wall/floor checks, pause/camp/safe-zone cleanup, and paced no-burst scheduling")
		if DisplayServer.get_name() == "headless":
			print("Headless fixture used a test-only capture adapter; the unmodified production capture guard was also verified.")
		quit(0)
	else:
		for failure in failures:
			push_error("STRESS PERCEPTION TEST FAIL: " + failure)
		quit(1)


func _fixture(use_adapter := true) -> Dictionary:
	paused = false
	ExpeditionSession.begin_new_journey()
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := _body(Vector3(0.0, -0.1, 0.0), Vector3(30.0, 0.2, 30.0))
	world.add_child(floor_body)
	var player := DungeonPlayer.new()
	player.setup(world, null, ExpeditionSession.get_inventory())
	player.position = Vector3(0.0, 0.9, 0.0)
	world.add_child(player)
	player.set_physics_process(false)
	var effects: StressPerception = CapturedPerception.new() if use_adapter else StressPerception.new()
	effects.setup(player)
	world.add_child(effects)
	effects.set_process(false)
	effects.rng.seed = 77621
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await physics_frame
	await process_frame
	return {"world": world, "floor": floor_body, "player": player, "effects": effects}


func _cleanup(fixture: Dictionary) -> void:
	paused = false
	fixture.effects.set_active(false)
	fixture.world.free()


func _test_synthesized_audio() -> void:
	seed(174711)
	var expected_global := randi()
	seed(174711)
	for kind: String in ["whisper", "footsteps"]:
		var stream := AUDIO.get_stream(kind)
		_check(stream is AudioStreamWAV and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo, "hallucinated sound must be a valid mono 16-bit PCM AudioStreamWAV: " + kind)
		_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.get_length() > 1.0 and stream.get_length() < 2.1, "sound must be a short non-looping phrase, not a sustained alarm: " + kind)
		_check(AUDIO.get_stream(kind) == stream, "generated audio must be cached rather than rebuilt for each perception")
		var peak := 0.0
		var energy := 0.0
		for offset in range(0, stream.data.size(), 2):
			var sample := float(stream.data.decode_s16(offset)) / 32768.0
			peak = maxf(peak, absf(sample))
			energy += sample * sample
		_check(peak > 0.1 and peak <= 0.4 and energy > 1.0, "synthesized PCM must be audible, finite and peak-limited below 0.4: " + kind)
		_check(absf(float(stream.data.decode_s16(0))) <= 1.0 and absf(float(stream.data.decode_s16(stream.data.size() - 2))) <= 1.0, "sound edges must fade to zero without click transients")
	_check(AUDIO.get_stream("scream") == null, "unknown sound types must not generate an unbounded or startling substitute")
	_check(randi() == expected_global, "procedural audio synthesis must not advance combat's global random stream")


func _test_thresholds_and_playback() -> void:
	var fixture := await _fixture()
	var effects: StressPerception = fixture.effects
	effects.set_active(true)
	for value: float in [0.0, 39.99, 40.0, 59.99]:
		effects.update_stress(value)
		_check(not effects.trigger_event("whisper") and not effects.trigger_event("footsteps") and not effects.trigger_event("vision"), "stress below 60 must not generate hallucinations")
		_check(effects.vignette_layer.visible == (value >= 40.0), "only the very subtle vignette may begin at stress 40")
		if value >= 40.0:
			var strength := float((effects.vignette_rect.material as ShaderMaterial).get_shader_parameter("intensity"))
			_check(strength > 0.0 and strength < 0.08 and effects.vignette_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE and effects.vignette_layer.layer < 1, "early unease must be transparent, input-transparent and behind the normal HUD")
	effects.update_stress(60.0)
	var events: Array[String] = []
	effects.perception_triggered.connect(func(kind: String) -> void: events.append(kind))
	for kind: String in ["whisper", "footsteps"]:
		_check(effects.trigger_event(kind), "stress 60 must permit the actual audio effect: " + kind)
		_check(effects.audio_player.stream == AUDIO.get_stream(kind) and effects.audio_player.playing and effects.audio_player.volume_db <= -20.0, "triggered hallucination must play the quiet cached stream through a real 3D audio player")
		var offset: Vector3 = effects.audio_player.global_position - fixture.player.camera.global_position
		_check(absf(offset.dot(fixture.player.head.global_basis.x)) >= 2.4 and offset.length() < 5.0, "perceived sound must come softly from a spatialized side/rear position")
		_check(not effects.trigger_event(kind), "a sound already in progress must not layer duplicate noise")
		effects.clear_effects()
	_check(events == ["whisper", "footsteps"] and effects.event_count == 2 and effects.last_event == "footsteps", "accepted effects must emit and count exactly once")
	effects.update_stress(79.99)
	_check(not effects.trigger_event("vision"), "vision must remain unavailable below stress 80")
	effects.update_stress(80.0)
	_check(effects.trigger_event("vision") and is_instance_valid(effects.ghost), "stress 80 must create a real peripheral silhouette on safe ground")
	_check(not effects.trigger_event("vision"), "only one afterimage may be visible at a time")
	effects.update_stress(-100.0)
	_check(is_zero_approx(effects.stress_value) and effects.ghost == null and not effects.vignette_layer.visible, "low clamped stress must clear all perception effects immediately")
	effects.update_stress(999.0)
	_check(is_equal_approx(effects.stress_value, 100.0), "perception stress must clamp to the shared maximum")
	_cleanup(fixture)


func _test_noncombat_vision_and_rng() -> void:
	var fixture := await _fixture()
	var effects: StressPerception = fixture.effects
	var player: DungeonPlayer = fixture.player
	var enemy := DungeonEnemy.new()
	enemy.configure("실제 적 대조군", 80.0, 18.0, 2.0, Color(0.2, 0.15, 0.1))
	enemy.setup(player, null, fixture.world)
	enemy.position = Vector3(0.0, 0.9, 7.0)
	fixture.world.add_child(enemy)
	enemy.set_physics_process(false)
	await physics_frame
	await process_frame
	var before_session := ExpeditionSession.capture_snapshot()
	var before_slots := ExpeditionSession.get_inventory().slots.duplicate(true)
	var before_player := Vector2(player.health, player.stamina)
	var before_aim := player.head.global_basis
	var before_camera := player.camera.transform
	var bow_rng := player.bow_shot_rng.state
	var enemy_state := enemy.ai_state
	var enemy_count := get_nodes_in_group("enemy").size()
	seed(973311)
	var expected_global := randi()
	seed(973311)
	effects.update_stress(85.0)
	effects.set_active(true)
	_check(effects.trigger_event("vision"), "noncombat fixture must generate a safe actual silhouette")
	if is_instance_valid(effects.ghost):
		_check(not _contains_combat_node(effects.ghost) and not effects.ghost.has_method("receive_hit") and bool(effects.ghost.get_meta("perception_only", false)), "afterimage must contain no collider, area, enemy class/group or damage receiver")
		_check(effects.ghost.global_position.distance_to(player.global_position) > 3.0 and effects.ghost.global_position.distance_to(player.global_position) < 5.0, "afterimage must remain 3–5m away rather than appear against the camera")
		effects.advance(0.25)
		_check(effects._ghost_material.albedo_color.a > 0.0 and effects._ghost_material.albedo_color.a <= 0.6201 and not effects._ghost_material.no_depth_test, "afterimage must softly fade in while retaining normal world depth occlusion")
		effects.advance(1.41)
		_check(effects.ghost == null, "the afterimage must fade away within two seconds")
	_check(effects.trigger_event("footsteps"), "independence fixture must also play actual audio")
	_check(randi() == expected_global and player.bow_shot_rng.state == bow_rng, "perceptual event selection and placement must not consume global or bow combat randomness")
	_check(ExpeditionSession.capture_snapshot() == before_session and ExpeditionSession.get_inventory().slots == before_slots, "perception must never change stress, survival state, inventories or saved expedition state")
	_check(Vector2(player.health, player.stamina).is_equal_approx(before_player) and player.head.global_basis.is_equal_approx(before_aim) and player.camera.transform.is_equal_approx(before_camera), "perception must not damage the player, consume stamina, shake the camera or alter aim")
	_check(enemy.health == 80.0 and enemy.ai_state == enemy_state and enemy.target == player and get_nodes_in_group("enemy").size() == enemy_count, "perceived figures and sounds must not change real enemy health, AI, targets or group counts")
	_cleanup(fixture)


func _test_suspension_and_threshold_cleanup() -> void:
	for gate: String in ["paused", "capture", "camping", "safe_zone", "dead", "inactive"]:
		var fixture := await _fixture()
		var effects: StressPerception = fixture.effects
		effects.set_active(true)
		effects.update_stress(90.0)
		effects.trigger_event("whisper")
		effects.trigger_event("vision")
		var count := effects.event_count
		match gate:
			"paused": paused = true
			"capture":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				(effects as CapturedPerception).simulated_capture = false
			"camping": fixture.player.camping = true
			"safe_zone": fixture.player.safe_zone_mode = true
			"dead": fixture.player.combat_state = DungeonPlayer.CombatState.DEAD
			"inactive": effects.set_active(false)
		effects.advance(50.0)
		_check(effects.ghost == null and not effects.audio_player.playing and effects.audio_player.stream == null and not effects.vignette_layer.visible, "suspension must immediately clear the visual, audio and vignette: " + gate)
		_check(not effects.trigger_event("whisper") and not effects.trigger_event("vision") and effects.event_count == count and is_equal_approx(effects.stress_value, 90.0), "suspension must reject new perceptions without changing real stress: " + gate)
		_cleanup(fixture)
	var fixture := await _fixture()
	var effects: StressPerception = fixture.effects
	effects.set_active(true)
	effects.update_stress(90.0)
	effects.trigger_event("vision")
	effects.trigger_event("whisper")
	effects.update_stress(79.0)
	_check(effects.ghost == null and effects.audio_player.playing, "dropping below 80 must immediately remove only the no-longer-supported vision")
	effects.update_stress(59.0)
	_check(not effects.audio_player.playing and effects.vignette_layer.visible, "dropping below 60 must stop hallucinated audio while retaining mild unease")
	effects.update_stress(39.0)
	_check(not effects.vignette_layer.visible, "dropping below 40 must remove the vignette")
	_cleanup(fixture)


func _test_wall_and_floor_safety() -> void:
	var fixture := await _fixture()
	var effects: StressPerception = fixture.effects
	# A room-wide wall blocks every peripheral spawn direction. A silhouette
	# must not be placed or rendered beyond the wall.
	fixture.world.add_child(_body(Vector3(0.0, 1.0, -1.6), Vector3(20.0, 2.0, 0.15)))
	await physics_frame
	await process_frame
	effects.set_active(true)
	effects.update_stress(100.0)
	_check(not effects.trigger_event("vision") and effects.ghost == null and effects.event_count == 0, "walls must block an apparition rather than allow a silhouette to show through geometry")
	_cleanup(fixture)
	fixture = await _fixture()
	effects = fixture.effects
	effects.set_active(true)
	effects.update_stress(100.0)
	_check(effects.trigger_event("vision"), "visibility recheck fixture must begin with an unobstructed afterimage")
	fixture.world.add_child(_body(Vector3(0.0, 1.0, -1.6), Vector3(20.0, 2.0, 0.15)))
	await physics_frame
	await process_frame
	effects.advance(0.1)
	_check(effects.ghost == null, "a newly obstructed afterimage must be removed immediately, even before its normal fade timeout")
	_cleanup(fixture)
	fixture = await _fixture()
	effects = fixture.effects
	fixture.floor.free()
	await physics_frame
	await process_frame
	effects.set_active(true)
	effects.update_stress(100.0)
	_check(not effects.trigger_event("vision") and effects.ghost == null, "an apparition must never float over a missing floor")
	_cleanup(fixture)


func _test_cadence_and_large_delta() -> void:
	var fixture := await _fixture()
	var effects: StressPerception = fixture.effects
	effects.set_active(true)
	effects.update_stress(60.0)
	effects.advance(1.99)
	_check(effects.event_count == 0, "entering an audio threshold must allow about two seconds before the first event")
	effects.advance(0.02)
	_check(effects.event_count == 1, "first audio event must occur shortly after the entry delay")
	effects.advance(13.9)
	_check(effects.event_count == 1, "stress 60 must leave nearly fourteen seconds between audio events")
	effects.advance(0.11)
	_check(effects.event_count == 2, "audio must resume after the stress-specific interval")
	effects.update_stress(100.0)
	var before := effects.event_count
	effects.advance(1000.0)
	_check(effects.event_count <= before + 1, "a large frame must never produce an audio/vision burst or catch-up event loop")
	_cleanup(fixture)
	var tallies: Array[Vector2i] = []
	for value: float in [80.0, 100.0]:
		fixture = await _fixture()
		effects = fixture.effects
		var kinds: Array[String] = []
		effects.perception_triggered.connect(func(kind: String) -> void: kinds.append(kind))
		effects.set_active(true)
		effects.update_stress(value)
		for _frame in range(240):
			effects.advance(0.25)
		var audio_count := kinds.count("whisper") + kinds.count("footsteps")
		var vision_count := kinds.count("vision")
		tallies.append(Vector2i(audio_count, vision_count))
		_cleanup(fixture)
	_check(tallies[1].x > tallies[0].x and tallies[1].y > tallies[0].y and tallies[0].y > 0, "higher stress must increase both actual audio and vision frequency without removing their cooldowns")


func _test_real_input_capture_guard() -> void:
	var fixture := await _fixture(false)
	var effects: StressPerception = fixture.effects
	effects.update_stress(100.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	effects.set_active(true)
	_check(not effects.trigger_event("whisper") and not effects.trigger_event("vision") and not effects.vignette_layer.visible, "unmodified production effects must refuse all events without captured mouse input")
	_cleanup(fixture)


func _contains_combat_node(node: Node) -> bool:
	if node is DungeonEnemy or node is CollisionObject3D or node is Area3D or node.is_in_group("enemy"):
		return true
	for child in node.get_children():
		if _contains_combat_node(child):
			return true
	return false


func _body(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	return body


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
