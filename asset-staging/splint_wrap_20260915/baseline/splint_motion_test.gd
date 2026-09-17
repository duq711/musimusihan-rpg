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
	var accepted := player.use_consumable("splint", inventory)
	_check(accepted.accepted and accepted.condition_cleared == "fracture" and player.splint_hands.active, "eligible use must cure fracture and start splint")
	_check(player.health == health and inventory.count_item("splint") == before - 1, "splint spends one without healing HP")
	_check(not player.use_consumable("splint", inventory).accepted, "absent fracture must reject repeat use")
	paused = true
	player.advance_bandage_motion(1.0)
	_check(player.splint_hands.elapsed == 0.0, "pause freezes presentation")
	paused = false
	var previous := Vector3.ZERO
	var maximum_step := 0.0
	var wrist_gap := 0.0
	for i in 515:
		player._update_viewmodel(1.0 / 60.0)
		var motion: Node3D = player.splint_hands
		if i > 0: maximum_step = maxf(maximum_step, previous.distance_to(motion.right_arm.position))
		previous = motion.right_arm.position
		for arm: Node3D in [motion.left_arm, motion.right_arm]:
			var adapter: Node3D = arm._active_visual
			var hand: Vector3 = adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(adapter.skeleton.find_bone("wrist")).origin
			var sleeve: Vector3 = adapter._forearm.global_transform * adapter._wrist_fit_anchor
			wrist_gap = maxf(wrist_gap, hand.distance_to(sleeve))
		if i == 60: _check(not player.weapon_pivot.visible and motion.visible, "equipment stows before working hands appear")
		if i == 222: _check(motion.tightened == 1, "first strap tightens independently")
		if i == 288: _check(motion.tightened == 2, "second strap tightens independently")
		if i == 360: _check(motion.tightened == 3, "all straps close before final check")
	_check(wrist_gap < 0.001, "hands must remain attached to sleeves")
	_check(maximum_step < 0.055, "hand transfers must be continuous")
	player._update_viewmodel(0.2)
	_check(not player.is_bandage_motion_active() and player.weapon_pivot.visible, "completion returns equipment")
	_check(player.health == health and inventory.count_item("splint") == before - 1, "animation must not duplicate effect or consumption")
	player.apply_condition("fracture", -1.0, "left_arm")
	player.use_consumable("splint", inventory)
	player._update_viewmodel(3.4)
	player.prepare_for_inventory()
	_check(not player.splint_hands.active, "inventory interruption clears splint")
	player.select_treatment_part("right_leg")
	player.apply_condition("fracture", -1.0, "right_leg")
	_check(player.use_consumable("splint", inventory).accepted and not player.splint_hands.active, "other limbs retain cure without incorrect left arm motion")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "original session and cursor are preserved")
	for failure in failures: push_error(failure)
	print("SPLINT MOTION TEST %s: wrist gap %.6f, maximum hand step %.4f" % ["PASS" if failures.is_empty() else "FAIL", wrist_gap, maximum_step])
	quit(0 if failures.is_empty() else 1)
