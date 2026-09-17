extends SceneTree

const MOTION := preload("res://scripts/first_person_motion.gd")
const PREVIEW := preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_curves()
	await _test_actual_hand_contacts_and_interrupts()
	await _test_frame_rate_independence()
	if failures.is_empty():
		print("FIRST PERSON MOTION PASS: phase-continuous sword curves, impact clock, actual two-hand bow/string and shield contacts, release, interruption, two-arm ownership, frame-rate consistency, pause and aim isolation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_curves() -> void:
	_check(is_equal_approx(MOTION.SWORD_HIT_TIME, DungeonPlayer.ATTACK_HIT_TIME), "solo sword contact checkpoint must share its unchanged combat hit time")
	for charge in [0.0, 0.5, 1.0]:
		for shield in [false, true]:
			var active_end := 0.30 if shield else 0.16
			_check(MOTION.sword("windup", 0.22, charge, false, shield).is_equal_approx(MOTION.sword("active", 0.0, charge, false, shield)), "solo and paired windup must flow continuously into active swing")
			_check(MOTION.sword("active", active_end, charge, false, shield).is_equal_approx(MOTION.sword("recovery", 0.0, charge, false, shield)), "solo and paired active swing must flow continuously into recovery at their own combat boundary")
			_check(MOTION.sword("recovery", lerpf(0.47, 0.68, charge), charge, false, shield).is_equal_approx(MOTION.sword("ready", 0.0, charge, false, shield)), "solo and paired recovery must return to the authored ready pose without a pop")
	for draw in [0.05, 0.5, 1.0]:
		_check(MOTION.bow(draw).is_equal_approx(MOTION.bow(0.0, 0.0, draw)), "short and full draws must begin release at their own exact preceding pose")
	var before := MOTION.sword("active", 0.025, 0.0, false, false)
	var contact := MOTION.sword("active", DungeonPlayer.ATTACK_HIT_TIME, 0.0, false, false)
	var after := MOTION.sword("active", 0.12, 0.0, false, false)
	_check(not before.is_equal_approx(contact) and not contact.is_equal_approx(after), "active sword must move through actual windup, impact and follow-through rather than chase one endpoint")
	_check(before.origin.x > 0.0 and contact.origin.x > 0.0 and after.origin.x > 0.0, "slash must keep the real right wrist on the right as its blade crosses the view")
	var one_step := lerpf(0.0, 1.0, MOTION.damping(8.0, 1.0))
	var many_steps := 0.0
	for _step in 120:
		many_steps = lerpf(many_steps, 1.0, MOTION.damping(8.0, 1.0 / 120.0))
	_check(is_equal_approx(one_step, many_steps), "pose damping must preserve the same response across frame rates")
	_check(not MOTION.flail("outbound", 0.16, 0, 1).is_equal_approx(MOTION.flail("ready", 0, 0, 0)), "flail throw must have a real extended wrist pose")
	_check(not MOTION.staff(0.165).is_equal_approx(MOTION.staff(0.0)), "staff cast must visibly extend and return using its real recoil clock")


func _fixture() -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	PREVIEW.configure_pose(fixture, "idle")
	fixture["viewport"] = viewport
	var player := fixture.player as DungeonPlayer
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.set_torch_enabled(false)
	(fixture.inventory as ExpeditionInventory).unequip("offhand")
	return fixture


func _test_actual_hand_contacts_and_interrupts() -> void:
	var session_before := ExpeditionSession.capture_snapshot()
	var cursor_before := Input.mouse_mode
	var fixture := _fixture()
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	await physics_frame
	player._update_viewmodel(1.0 / 60.0)
	_check(player.get_first_person_motion_snapshot().visible_arm_count == 1 and not player.shield_pivot.visible, "unequipped shield and stowed torch must not leave duplicate arms in the sword-only view")
	_check(not player.left_support_arm.visible, "resting left hand stays stowed until a real action needs it")
	_check(_equip(bag, "hunting_bow"), "real inventory must equip the bow")
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._update_viewmodel(1.0 / 60.0)
	var left_wrist := player.camera.unproject_position(player.left_support_arm.global_position)
	var right_wrist := player.camera.unproject_position(player.weapon_arm.global_position)
	var view_size := player.camera.get_viewport().get_visible_rect().size
	_check(right_wrist.x - left_wrist.x > view_size.x * 0.075, "undrawn bow must leave readable screen separation between the actual left grip wrist and right nock wrist")
	_check(player.begin_bow_draw().accepted, "actual bow draw must start")
	var arrow_count := player.get_arrow_count()
	player._advance_bow_draw(1.0)
	player._update_viewmodel(1.0 / 60.0)
	var snapshot := player.get_first_person_motion_snapshot()
	_check(snapshot.visible_arm_count == 2 and snapshot.left_hand_role == "bow", "full draw must use exactly the anatomical left support hand and right drawing hand")
	_check(snapshot.hand_contacts.bow_grip.error < 0.00001 and snapshot.hand_contacts.bow_string.error < 0.00001, "both actual hand contact frames must remain on the visible grip and string nock")
	var anchors: Dictionary = DungeonPlayer.ARCHERY_VISUALS.bow_hand_anchors(player.bow_visual_root)
	_check((snapshot.hand_contacts.bow_string.actual as Vector3).distance_to(player.bow_visual_root.to_global(anchors.string)) < 0.00001, "draw hand must follow the same string vertex used by rendered bow geometry")
	var aim_before := player.head.global_basis
	var blade_before := player.sword_blade.global_transform
	var muzzle_before := player.staff_muzzle.global_transform
	player._update_character_arms()
	_check(player.head.global_basis == aim_before and player.sword_blade.global_transform == blade_before and player.staff_muzzle.global_transform == muzzle_before, "arm fitting must never move gameplay aim, real sword clash geometry or spell muzzle")
	var release := player.release_bow_shot(Vector3.FORWARD)
	_check(release.accepted and player.get_arrow_count() == arrow_count - 1, "animated release must use the real one-arrow transaction")
	var arrow := release.projectile as Node3D
	arrow.set_physics_process(false)
	player.advance_action_timers(0.12)
	player._update_viewmodel(0.12)
	snapshot = player.get_first_person_motion_snapshot()
	_check(snapshot.hand_contacts.has("bow_release") and not snapshot.hand_contacts.has("bow_string"), "released right hand must follow through separately from the snapped string")
	_check(player.head.global_basis == aim_before, "release animation must preserve the head-owned projectile aim")
	player.prepare_for_inventory()
	player._update_viewmodel(1.0 / 60.0)
	_check(not player.bow_drawing and player._bow_release_draw == 0.0 and player.get_arrow_count() == arrow_count - 1, "inventory interruption must clear release state without a second shot")
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	_check(_equip(bag, "chain_flail"), "real inventory must equip the chain flail")
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._update_viewmodel(0.0)
	var ball := player.flail_visual_root.get_node("Head") as Node3D
	var resting_ball := ball.position
	_check(player.begin_flail_spin().accepted, "actual flail spin must start")
	_check(ball.position.distance_to(resting_ball) < 0.00001, "beginning a real spin must preserve the preceding hanging ball position")
	player._update_flail(0.3)
	player._update_viewmodel(0.3)
	var spinning_ball := ball.position
	var spinning_wrist := player.weapon_pivot.transform
	player.cancel_flail_action()
	_check(ball.position.distance_to(spinning_ball) < 0.00001 and player.weapon_pivot.transform.is_equal_approx(spinning_wrist), "cancelling a spin must retain ball and wrist contact before settling")
	player._update_viewmodel(0.09)
	_check(ball.position.distance_to(resting_ball) > 0.00001, "cancelled flail must settle over time instead of teleporting to rest")
	player._update_viewmodel(0.10)
	_check(ball.position.distance_to(resting_ball) < 0.00001 and player.flail_state == "ready" and not is_instance_valid(player.flail_projectile), "cancelled flail must finish settling without throwing or retaining an attack")
	_check(_equip(bag, "rusted_sword") and _equip(bag, "round_shield"), "real equipment transactions must restore sword and shield")
	player.blocking = true
	player._update_viewmodel(1.0)
	snapshot = player.get_first_person_motion_snapshot()
	_check(snapshot.visible_arm_count == 2 and snapshot.left_hand_role == "shield" and snapshot.hand_contacts.shield.error < 0.00001, "shield guard must use its actual rear grip with one left arm and one sword arm")
	var rear := player.shield_model.find_child("RearGrip", true, false) as Node3D
	_check((snapshot.hand_contacts.shield.actual as Vector3).distance_to(rear.global_position) < 0.00001, "shield glove must be centered on the rendered rear strap, not a detached decorative offset")
	player._begin_chest_hands(fixture.chest)
	player._chest_stow_amount = 0.3
	player._update_viewmodel(1.0 / 60.0)
	_check(player.get_first_person_motion_snapshot().visible_arm_count == 0, "partial chest stowing must hide every carried arm while the two actual chest hands take over")
	player.set_chest_container_open(false)
	player.configure_safe_zone(true)
	player.set_torch_enabled(true)
	player._update_viewmodel(1.0)
	snapshot = player.get_first_person_motion_snapshot()
	_check(snapshot.visible_arm_count == 2 and snapshot.left_hand_role == "torch" and player.torch.visible and player.torch_fill.visible, "safe-zone torch pose must show a left torch hand and relaxed right hand while retaining actual lights")
	_check(player.camera.to_local(player.right_relaxed_arm.global_position).y < -0.55, "right hand retains the user-requested lowered resting pose")
	var frozen := snapshot.duplicate(true)
	paused = true
	player.advance_action_timers(0.5)
	player.advance_combat_state(0.5, false)
	player._update_viewmodel(0.5)
	_check(player.get_first_person_motion_snapshot() == frozen, "paused trial or inventory menus must freeze all motion clocks and contact poses")
	paused = false
	arrow.free()
	(fixture.viewport as SubViewport).queue_free()
	await process_frame
	_check(Input.mouse_mode == cursor_before and ExpeditionSession.capture_snapshot() == session_before, "motion fixtures must preserve original expedition and cursor state")


func _test_frame_rate_independence() -> void:
	var poses: Array[Transform3D] = []
	for fps in [30, 60, 120]:
		var fixture := _fixture()
		var player := fixture.player as DungeonPlayer
		player._motion_clock = 0.0
		player._motion_speed = 0.0
		player._motion_equip_elapsed = MOTION.EQUIP_DURATION
		player._motion_look_sway = Vector2.ZERO
		player._motion_previous_look = Vector2(player.rotation.y, player._pitch)
		player.velocity = Vector3(0, 0, -player.SPRINT_SPEED)
		for _frame in fps:
			player._update_viewmodel(1.0 / float(fps))
		poses.append(player.weapon_pivot.transform)
		(fixture.viewport as SubViewport).queue_free()
		await process_frame
	_check(poses[0].origin.distance_to(poses[1].origin) < 0.00001 and poses[1].origin.distance_to(poses[2].origin) < 0.00001, "one second of actual sprint motion must end at the same position at30/60/120fps")
	_check(poses[0].basis.is_equal_approx(poses[2].basis), "actual sprint rotation must remain frame-rate independent")


func _equip(bag: ExpeditionInventory, item_id: String) -> bool:
	var slot := str(ExpeditionInventory.get_item_definition(item_id).get("equip_slot", ""))
	if str(bag.equipment.get(slot, "")) == item_id:
		return true
	for index in bag.slots.size():
		if str(bag.slots[index].id) == item_id:
			return bool(bag.equip_from_slot(index).accepted)
	return false


func _check_relaxed_wrist_visible(player: DungeonPlayer, arm: Node3D) -> void:
	var point := player.camera.unproject_position(arm.global_position)
	var size := player.camera.get_viewport().get_visible_rect().size
	_check(not player.camera.is_position_behind(arm.global_position) and point.x > size.x * 0.12 and point.x < size.x * 0.88 and point.y > size.y * 0.55 and point.y < size.y * 0.90, "relaxed hand must show its wrist and palm inside the lower view rather than only clipped fingertips")
	var toward_camera := arm.global_position.direction_to(player.camera.global_position)
	_check(arm.global_basis.y.normalized().dot(toward_camera) > 0.4, "the sourced +Y back of each free hand must face the viewer instead of presenting a thin edge")
	_check((-arm.global_basis.z).dot(player.camera.global_basis.y) > 0.35, "the sourced -Z free fingers must rise gently into view instead of pointing below the wrist")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
