extends SceneTree

const PREVIEW := preload("res://tests/reference_sword_motion_preview.gd")
const ARM_PREVIEW := preload("res://tests/player_arm_preview.gd")
const MOTION_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var inventory := before.get("inventory") as ExpeditionInventory
	var contents := MOTION_PREVIEW.inventory_fingerprint(inventory)
	var cursor := Input.mouse_mode
	var sources := PREVIEW.source_hashes()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(PREVIEW.sequence_ids_for_scope("cut_refinement") == ["right_diagonal", "left_reverse"], "focused capture must contain only the requested two cuts")
	_check(PREVIEW.contact_ids_for_scope("cut_refinement") == ["right_diagonal", "left_reverse"], "focused selected frames must not require unrecorded movement or overhead poses")
	_check(PREVIEW.sequence_ids_for_scope("two_hand").has("shield_stow") and PREVIEW.sequence_ids_for_scope("two_hand").has("overhead"), "focused scope must leave the existing full two-hand review available")
	_check(PREVIEW.sequence_ids_for_scope("") == PREVIEW.SEQUENCE_IDS and PREVIEW.contact_ids_for_scope("") == PREVIEW.CONTACT_IDS, "default review must retain every existing sequence and selected pose")
	sandbox.begin()
	for variant: String in PREVIEW.sequence_ids_for_scope("cut_refinement"):
		await _exercise_capture_fixture(variant)
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == before and MOTION_PREVIEW.inventory_fingerprint(inventory) == contents and Input.mouse_mode == cursor and not sandbox.active, "cut fixture and teardown must restore the original expedition, nested inventory and cursor")
	_check(PREVIEW.source_hashes() == sources, "cut review must not change production models, trajectories or capture sources")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD CUT PREVIEW %s: two production cuts after real shield stow, both-hand capture records, input isolation and expedition/source preservation; no pixel claim" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _exercise_capture_fixture(variant: String) -> void:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	await physics_frame
	await physics_frame
	_check(ARM_PREVIEW.configure_pose(fixture, "idle"), "cut review must use the real idle fixture before stowing")
	player.set_torch_enabled(false)
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.0)
	var camera := player.camera.transform
	_check(viewport.size == PREVIEW.IMAGE_SIZE and viewport.gui_disable_input and not viewport.physics_object_picking, "cut review viewport must retain its original framing and external input isolation")
	_check(not player.is_processing() and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "capture fixture must disable automatic player and hardware input processing")
	_check(not PREVIEW.two_hand_grip_ready(player), "equipped shield must not count as a finished two-hand capture")
	var action := player.request_primary_weapon()
	_check(bool(action.get("accepted", false)), "capture must begin a real primary-weapon shield stow")
	for step in range(72):
		player.advance_action_timers(STEP)
		player.advance_combat_state(STEP, false)
		player._update_viewmodel(STEP)
	_check(PREVIEW.two_hand_grip_ready(player), "capture prerequisite must observe the completed left sword grip and hidden shield")
	_check(player.camera.transform.is_equal_approx(camera), "two-hand preparation must preserve the production camera")
	var attack := player.begin_sword_attack(variant)
	_check(bool(attack.get("accepted", false)), "focused capture must start the production attack: " + variant)
	var saw_active := false
	var saw_ready := false
	for frame in range(100):
		if frame == 27: player.attack_release_requested = true
		player.advance_action_timers(STEP)
		player.advance_combat_state(STEP, false)
		player._update_viewmodel(STEP)
		player._resolve_active_attack()
		var snapshot := player.get_first_person_motion_snapshot()
		var transform := player.weapon_pivot.transform
		var hand := player.sword_support_arm.global_transform
		var record := PREVIEW._frame_record(player, snapshot, frame, "headless_unrendered")
		_check(record.sword_variant == variant and not record.shield_visible and is_equal_approx(float(record.sword_support_progress), 1.0), "captured state must identify the real two-hand cut: " + variant)
		_check(record.left_sword_arm.has("wrist") and record.left_sword_hand_transform.has("rotation_xyzw") and record.right_arm.has("wrist"), "frame records must expose both real hands for contact and finishing-pose review")
		_check(PREVIEW.two_hand_grip_ready(player) and not record.automatic_physics_processing and not record.unhandled_input_processing, "every captured cut frame must retain its grip and input isolation")
		_check(player.weapon_pivot.transform.is_equal_approx(transform) and player.sword_support_arm.global_transform.is_equal_approx(hand) and player.camera.transform.is_equal_approx(camera), "frame inspection must never reposition the sword, hands or camera")
		saw_active = saw_active or player.combat_state == DungeonPlayer.CombatState.ACTIVE
		if saw_active and player.combat_state == DungeonPlayer.CombatState.READY:
			saw_ready = true
	_check(saw_active and saw_ready, "capture duration must include the actual strike, finish and return: " + variant)
	player.cancel_sword_attack()
	viewport.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
