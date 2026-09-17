extends SceneTree
const PREVIEW := preload("res://tests/splint_motion_preview.gd")
const FIXTURE := preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := FIXTURE.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.create_fixture(viewport)
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	var initial: Transform3D = player.weapon_pivot.transform
	var before := inventory.count_item("splint")
	var health := player.health
	var accepted := player.begin_item_use("splint", inventory)
	_check(accepted.accepted and accepted.started and player.splint_hands.active, "eligible use starts timed splint")
	_check(player.health == health and inventory.count_item("splint") == before, "splint starts without healing or early consumption")
	_check(not player.begin_item_use("splint", inventory).accepted, "busy treatment rejects repeat use")
	paused = true
	player.advance_bandage_motion(1.0)
	_check(player.splint_hands.elapsed == 0.0, "pause freezes presentation")
	paused = false
	var previous := Vector3.ZERO
	var maximum_step := 0.0
	var wrist_gap := 0.0
	var maximum_step_time := 0.0
	var prior_frame := Transform3D.IDENTITY
	var prior_roll := Vector3.ZERO
	var prior_contact := Vector3.ZERO
	var prior_hand := Basis.IDENTITY
	for i in 431:
		player._update_viewmodel(1.0 / 60.0)
		player.advance_item_use(1.0 / 60.0)
		var motion: Node3D = player.splint_hands
		if i > 0 and previous.distance_to(motion.right_arm.position) > maximum_step:
			maximum_step = previous.distance_to(motion.right_arm.position)
			maximum_step_time = motion.elapsed
			if maximum_step > 0.05:
				print("SPLINT_DIAGNOSTIC ", motion.elapsed, " roll_step=", prior_roll.distance_to(motion.roll.position), " contact_step=", prior_contact.distance_to(motion._point(motion.winding)), " sleeve_angle=", prior_frame.basis.orthonormalized().get_rotation_quaternion().angle_to(motion._cloth_frame.basis.orthonormalized().get_rotation_quaternion()), " hand_angle=", prior_hand.get_rotation_quaternion().angle_to(motion.right_arm.basis.get_rotation_quaternion()), " scale_before=", prior_frame.basis.get_scale(), " scale_after=", motion._cloth_frame.basis.get_scale())
		previous = motion.right_arm.position
		prior_frame = motion._cloth_frame
		prior_roll = motion.roll.position
		prior_contact = motion._point(motion.winding)
		prior_hand = motion.right_arm.basis
		for arm: Node3D in [motion.left_arm, motion.right_arm]:
			var adapter: Node3D = arm._active_visual
			var hand: Vector3 = adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(adapter.skeleton.find_bone("wrist")).origin
			var sleeve: Vector3 = adapter._forearm.global_transform * adapter._wrist_fit_anchor
			wrist_gap = maxf(wrist_gap, hand.distance_to(sleeve))
		if i == 60: _check(not player.weapon_pivot.visible and motion.visible, "equipment stows before working hands appear")
		if i == 110: _check(motion.winding < 0.001 and not motion.cloth.visible, "place a bare wooden stick before wrapping")
		if i == 130: _check(motion.support_seated and motion.winding > 0, "wrapping begins only after support is seated")
		if i == 222: _check(motion.winding > TAU and motion.cloth.visible and motion.roll.visible, "actual cloth grows around arm and wood as the roll circles")
		if i == 360: _check(motion.pressed and not motion.roll.visible and is_equal_approx(motion.winding, TAU * 3.0), "press dressing after three wraps")
	_check(wrist_gap < 0.001, "hands must remain attached to sleeves")
	_check(maximum_step < 0.055, "hand transfers must be continuous")
	player._update_viewmodel(0.2)
	player.advance_item_use(0.2)
	_check(not player.is_bandage_motion_active() and player.weapon_pivot.visible, "completion returns equipment")
	_check(player.health == health and inventory.count_item("splint") == before - 1, "timed completion consumes once without healing HP")
	player.apply_condition("fracture", -1.0, "left_arm")
	player.begin_item_use("splint", inventory)
	player._update_viewmodel(3.4)
	player.prepare_for_inventory()
	_check(inventory.count_item("splint") == before - 1 and ExpeditionSession.condition_affects_part("fracture", "left_arm"), "interruption preserves supply and fracture")
	_check(not player.splint_hands.active, "inventory interruption clears splint")
	player.select_treatment_part("right_leg")
	player.apply_condition("fracture", -1.0, "right_leg")
	_check(player.begin_item_use("splint", inventory).accepted and not player.splint_hands.active, "other limbs start timer without incorrect left arm motion")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "original session and cursor are preserved")
	for failure in failures: push_error(failure)
	print("SPLINT MOTION TEST %s: wrist gap %.6f, maximum hand step %.4f at %.3fs" % ["PASS" if failures.is_empty() else "FAIL", wrist_gap, maximum_step, maximum_step_time])
	quit(0 if failures.is_empty() else 1)
