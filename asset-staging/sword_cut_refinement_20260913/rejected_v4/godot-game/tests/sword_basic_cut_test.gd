extends SceneTree
## Regression for the reported right-to-left cut and its abrupt reversal.
## The frozen pre-change delivery also protects the user's accepted reverse cut.
## Actual player clocks and imported BladeTip/HandGrip drive every trajectory.

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const DATA := preload("res://scripts/reference_sword_motion.gd")
const BASELINE_PATH := "res://tests/fixtures/sword_cut_baseline_20260913.json"
const STEP := 1.0 / 120.0
const BASIC := "right_diagonal"
const REVERSE := "left_reverse"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var was_paused := paused
	var production_hash := FileAccess.get_sha256(DATA.MANIFEST_PATH)
	var fixture_hash := FileAccess.get_sha256(BASELINE_PATH)
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA.MANIFEST_PATH))
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	_check(current is Dictionary and baseline is Dictionary, "Current and frozen pre-change deliveries must be readable JSON objects")
	if not current is Dictionary or not baseline is Dictionary:
		_finish()
		return
	_test_preserved_delivery(current, baseline)
	var decoded := DATA._decode_manifest(baseline)
	_check(bool(decoded.get("ok", false)) and DATA.is_available(), "Both real authored deliveries must decode before player comparison")
	if not bool(decoded.get("ok", false)) or not DATA.is_available():
		_finish()
		return
	var production_clips: Dictionary = DATA._clips
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "The cut test must not replace an existing test-room session")
	if sandbox.active:
		_finish()
		return
	sandbox.begin()
	paused = false
	for stowed: bool in [false, true]:
		for charged: bool in [false, true]:
			var context := "%s %s" % ["two hands" if stowed else "sword and shield", "charged" if charged else "short"]
			var cut: Array[Dictionary] = await _capture(stowed, charged, BASIC)
			_test_basic_cut(cut, context)
			var reverse: Array[Dictionary] = await _capture(stowed, charged, REVERSE)
			# Substitute only this process's immutable decoded data. Production
			# player code, meshes, initialization and clocks stay identical.
			DATA._clips = decoded.clips
			var expected: Array[Dictionary] = await _capture(stowed, charged, REVERSE)
			DATA._clips = production_clips
			_test_reverse_unchanged(reverse, expected, context)
	sandbox.finish()
	paused = was_paused
	_check(DATA._clips == production_clips, "In-memory reference comparison must restore the production motion cache")
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor and paused == was_paused, "Real-player trials must restore expedition, original inventory, cursor and pause")
	_check(FileAccess.get_sha256(DATA.MANIFEST_PATH) == production_hash and FileAccess.get_sha256(BASELINE_PATH) == fixture_hash, "The test must never modify the production or baseline delivery")
	_finish()


func _test_preserved_delivery(current: Dictionary, baseline: Dictionary) -> void:
	_check(current.has("clips") and baseline.has("clips"), "Both deliveries must contain animation clips")
	if not current.has("clips") or not baseline.has("clips"):
		return
	var actual: Dictionary = current.clips
	var expected: Dictionary = baseline.clips
	_check(actual.size() == expected.size(), "Refining one cut must not add or remove other clips")
	for name: String in expected:
		_check(actual.has(name), "Preserve existing motion clip: " + name)
		if not actual.has(name):
			continue
		if name != BASIC:
			# Full structural equality includes every timestamp, quaternion,
			# position, joint and metadata field, especially all of left_reverse.
			_check(actual[name] == expected[name], "Preserve the entire accepted clip exactly: " + name)
		else:
			var changed: Dictionary = actual[name].duplicate(true)
			var before: Dictionary = expected[name].duplicate(true)
			changed.erase("right_arm")
			before.erase("right_arm")
			(changed.tracks as Dictionary).erase("sword")
			(before.tracks as Dictionary).erase("sword")
			_check(changed == before, "Basic refinement must preserve timing, shield track and clip metadata")
	if actual.has(REVERSE) and expected.has(REVERSE):
		var actual_digest := JSON.stringify(actual[REVERSE], "", true, true).sha256_text()
		var baseline_digest := JSON.stringify(expected[REVERSE], "", true, true).sha256_text()
		_check(actual_digest == baseline_digest, "The complete reverse clip must retain its baseline digest")


func _capture(stowed: bool, charged: bool, variant: String) -> Array[Dictionary]:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	(fixture.chest as Node3D).position = Vector3(12, 0, 12)
	await process_frame
	player.position = Vector3(0, 1, 2)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._pitch = 0.0
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.set_torch_enabled(false)
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.4)
	if stowed:
		_check(bool(player.request_primary_weapon().accepted), "Actual primary-weapon input must start shield stowing")
		player._update_viewmodel(1.1)
	player._motion_clock = 0.0
	player._update_viewmodel(0.2)
	_check(viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "Cut fixtures must never sample hardware input")
	var tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
	var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
	var records: Array[Dictionary] = []
	_check(tip != null and grip != null, "Cut trajectory requires the imported sword's real blade and grip markers")
	var start := player.begin_sword_attack(variant)
	_check(bool(start.accepted), "Real player must accept the requested cut: " + variant)
	if tip != null and grip != null and bool(start.accepted):
		player.attack_release_requested = not charged
		var idle_time := 0.0
		for frame in 420:
			var delta := STEP
			if player.combat_state == player.CombatState.ACTIVE:
				# Land exactly on body contact and active end, independent of FPS.
				for checkpoint: float in [player.get_melee_hit_time(), player.get_melee_active_duration()]:
					var remaining := checkpoint - player.state_time
					if remaining > 0.0000001:
						delta = minf(delta, remaining)
			player.advance_combat_state(delta, false)
			player._update_viewmodel(delta)
			records.append({"phase": player.combat_state, "time": player.state_time, "pose": player.weapon_pivot.transform,
				"tip": player.camera.to_local(tip.global_position), "grip": player.camera.to_local(grip.global_position),
				"charge": player.attack_charge})
			player._resolve_active_attack()
			if player.combat_state == player.CombatState.READY:
				idle_time += delta
				if idle_time >= 0.12:
					break
		_check(player.combat_state == player.CombatState.READY, "Actual cut must finish and settle back to READY")
	viewport.queue_free()
	await process_frame
	return records


func _test_basic_cut(records: Array[Dictionary], context: String) -> void:
	var active: Array[Dictionary] = []
	var recovery: Array[Dictionary] = []
	for record: Dictionary in records:
		if record.phase == DungeonPlayer.CombatState.ACTIVE:
			active.append(record)
		elif record.phase == DungeonPlayer.CombatState.RECOVERY:
			recovery.append(record)
	_check(active.size() > 4 and recovery.size() > 4, context + ": actual ACTIVE and RECOVERY samples are required")
	if active.size() <= 4 or recovery.size() <= 4:
		return
	var contact: Dictionary = _nearest(active, 0.145)
	_check(absf(float(contact.time) - 0.145) < 0.000001, context + ": inspect the real 145 ms body-contact checkpoint")
	_check((active[0].tip as Vector3).x > 0.0 and (active[-1].tip as Vector3).x < 0.0, context + ": blade tip must cross from the right to the left during the cut")
	# A blade still pointing right of its own grip at body contact caused the
	# reported club-like chop. This is a direction relation, not one fixed pose.
	_check((contact.tip as Vector3).x < (contact.grip as Vector3).x, context + ": cutting tip must already lead the gripping hand toward the left at contact")
	var before_contact: Dictionary = _nearest(active, 0.12)
	var after_contact: Dictionary = _nearest(active, 0.17)
	_check((before_contact.tip as Vector3).x > (contact.tip as Vector3).x and (contact.tip as Vector3).x > (after_contact.tip as Vector3).x, context + ": blade must keep moving left through contact instead of stopping or changing direction")
	var post_contact_degrees := 0.0
	var previous: Transform3D = contact.pose
	for record: Dictionary in active:
		if float(record.time) <= float(contact.time):
			continue
		post_contact_degrees += _angle(previous, record.pose)
		previous = record.pose
	# The old path spun ~172 degrees immediately after contact. Allow broad
	# follow-through variation while rejecting another near half-turn flip.
	_check(post_contact_degrees < 135.0, context + ": post-contact follow-through must not flip the sword nearly half a turn (degrees=%s)" % post_contact_degrees)
	var finish: Transform3D = active[-1].pose
	var resumed_at := INF
	var peak_recovery_angle := 0.0
	var peak_recovery_translation := 0.0
	previous = finish
	for record: Dictionary in recovery:
		var pose: Transform3D = record.pose
		peak_recovery_angle = maxf(peak_recovery_angle, _angle(previous, pose))
		peak_recovery_translation = maxf(peak_recovery_translation, previous.origin.distance_to(pose.origin))
		if resumed_at == INF and (finish.origin.distance_to(pose.origin) > 0.002 or _angle(finish, pose) > 0.5):
			resumed_at = float(record.time)
		previous = pose
	var recovery_duration := lerpf(0.47, 0.68, float(contact.charge))
	_check(resumed_at < recovery_duration * 0.25, context + ": recovery must start settling within its first quarter instead of holding a frozen finish")
	_check(peak_recovery_angle < 15.0 and peak_recovery_translation < 0.08, context + ": actual 120 Hz recovery must not contain an angular or positional snap")
	for index in range(1, records.size()):
		if records[index - 1].phase == DungeonPlayer.CombatState.RECOVERY and records[index].phase == DungeonPlayer.CombatState.READY:
			var a: Transform3D = records[index - 1].pose
			var b: Transform3D = records[index].pose
			_check(a.origin.distance_to(b.origin) < 0.03 and _angle(a, b) < 6.0, context + ": recovery must join idle without a position or orientation jump")
	print("BASIC CUT METRIC ", context, " contact_tip=", contact.tip, " contact_grip=", contact.grip,
		" post_contact_deg=", post_contact_degrees, " recovery_resumes_s=", resumed_at, " recovery_peak_deg=", peak_recovery_angle)


func _test_reverse_unchanged(actual: Array[Dictionary], baseline: Array[Dictionary], context: String) -> void:
	_check(not actual.is_empty() and actual.size() == baseline.size(), context + ": baseline and production reverse cuts must have equal actual sample counts")
	var max_position := 0.0
	var max_angle := 0.0
	for index in mini(actual.size(), baseline.size()):
		var a: Dictionary = actual[index]
		var b: Dictionary = baseline[index]
		_check(a.phase == b.phase and is_equal_approx(a.time, b.time) and is_equal_approx(a.charge, b.charge), context + ": reverse cut must retain its production clock at frame %d" % index)
		max_position = maxf(max_position, (a.pose as Transform3D).origin.distance_to((b.pose as Transform3D).origin))
		max_position = maxf(max_position, (a.tip as Vector3).distance_to(b.tip))
		max_position = maxf(max_position, (a.grip as Vector3).distance_to(b.grip))
		max_angle = maxf(max_angle, _angle(a.pose, b.pose))
	_check(max_position < 0.00001 and max_angle < 0.06, context + ": actual reverse sword/grip/blade poses must match the frozen delivery throughout preparation, contact, follow-through and return")
	print("REVERSE PRESERVATION METRIC ", context, " samples=", actual.size(), " max_position_m=", max_position, " max_angle_deg=", max_angle)


func _nearest(records: Array[Dictionary], time: float) -> Dictionary:
	var result: Dictionary = records[0]
	for record: Dictionary in records:
		if absf(float(record.time) - time) < absf(float(result.time) - time):
			result = record
	return result


func _angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("SWORD BASIC CUT %s: actual blade sweep, post-contact reversal, recovery and unchanged reverse cut; expedition and source preservation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
