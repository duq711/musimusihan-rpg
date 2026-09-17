extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const GAME := preload("res://scripts/game.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var input_owner := GAME.new()
	input_owner._register_inputs()
	input_owner.free()
	var key := InputEventKey.new()
	key.keycode = KEY_1; key.physical_keycode = KEY_1; key.pressed = true
	_check(key.is_action_pressed("primary_weapon"), "physical 1 must map to primary weapon")
	var viewport := PREVIEW.create_viewport(); root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var p: DungeonPlayer = fixture.player
	var bag: ExpeditionInventory = fixture.inventory
	p.set_physics_process(false); p.set_process_unhandled_input(false)
	await process_frame
	p._sword_draw_elapsed = p.SWORD_DRAW_DURATION; p._update_viewmodel(0)
	var equipment := bag.equipment.duplicate(true)
	var equipment_data := bag.equipment_data.duplicate(true)
	var sword_before := p.weapon_pivot.transform
	var aim := p.camera.transform
	var from := p.shield_pivot.transform
	_check(p.handle_primary_weapon_input(key), "actual primary key input must be consumed before spell selection")
	_check(p._shield_stowing() and not p._has_shield_equipped(), "stow must immediately remove shield guard while retaining the moving object")
	_check(p.shield_pivot.transform.is_equal_approx(from), "stow must begin at the visible shield pose without a jump")
	key.echo = true
	_check(not p.handle_primary_weapon_input(key), "key repeat must not trigger another transition")
	key.echo = false
	var previous_x := p.shield_pivot.position.x
	for i in 65:
		p._update_viewmodel(.02)
		_check(p.weapon_pivot.position.distance_to(sword_before.origin) < .02, "support hand must approach the existing sword position without lifting or recentering it")
		_check(p.shield_pivot.position.x <= previous_x + .00001, "shield must travel left continuously")
		previous_x = p.shield_pivot.position.x
		if p._shield_stowing():
			_check(p.shield_pivot.visible and p.shield_arm.visible, "shield and its gripping hand must stay together during stow")
			_check(p.get_first_person_motion_snapshot().hand_contacts.shield.error < .00001, "moving shield grip must retain the actual left hand")
		if i == 8:
			var time := p._shield_stow_elapsed
			p.handle_primary_weapon_input(key)
			_check(p._shield_stow_elapsed == time, "rapid repeated 1 must not restart stow")
			paused = true; p._update_viewmodel(.5)
			_check(p._shield_stow_elapsed == time and not p.request_primary_weapon().accepted, "pause must freeze the transition and reject new requests")
			paused = false
	_check(not p.shield_pivot.visible and not p.shield_arm.visible and p.weapon_pivot.visible and p.weapon_arm.visible, "completed stow must leave the sword only")
	_check(p._left_hand_role() == "sword_support" and p.sword_support_arm.visible, "left hand must take the lower sword grip")
	_check(p.shield_pivot.position.x < from.origin.x - 1.0, "shield must end well beyond the left edge")
	_check(p.weapon_pivot.position.distance_to(sword_before.origin) < .02 and p.camera.transform.is_equal_approx(aim), "two hand carry must preserve the existing sword position and camera aim")
	bag.add_item("wooden_arrow", 1); p._update_viewmodel(.1)
	_check(p._shield_stowed and not p.shield_pivot.visible, "unrelated inventory events must not restore a stowed shield")
	_check(bag.equipment == equipment and bag.equipment_data == equipment_data, "stowing must not remove, duplicate or alter equipped items")
	_check(p.begin_sword_attack("right_diagonal").accepted, "the remaining sword must still attack")
	for i in 95:
		if i == 27: p.attack_release_requested = true
		p.advance_combat_state(1.0 / 60.0, false)
		p._update_viewmodel(1.0 / 60.0)
		var support: Dictionary = p.get_first_person_motion_snapshot().hand_contacts.get("sword_support", {})
		_check(not support.is_empty() and float(support.get("grip_error", 1)) < .00001, "left hand must stay on the sword throughout attacks")
	p.cancel_sword_attack()
	_check(p.sword_support_arm.get_meta("anatomical_side") == -1, "support must use anatomical left geometry")
	_check(p.sword_support_arm.get_meta("source_model") == p.shield_arm.get_meta("source_model"), "returning left hand must retain the shield hand model")
	var joint: Dictionary = p.get_first_person_motion_snapshot().joint_landmarks.get("sword_support", {})
	_check(absf(float(joint.get("forearm_length", 0)) - .26) < .0001 and absf(float(joint.get("upper_length", 0)) - .34) < .0001, "left arm lengths must remain stable")
	_check(p.begin_sword_attack("overhead").get("reason") == "shield_required", "presentation change must preserve existing attack availability")
	bag.unequip("offhand")
	var slot := -1
	for i in bag.slots.size():
		if str(bag.slots[i].get("id", "")) == "round_shield": slot = i; break
	_check(slot >= 0 and bag.equip_from_slot(slot).accepted, "actual shield re-equipping must work")
	_check(not p._shield_stowed and p._has_shield_equipped(), "real equipment replacement must reset carried state")
	p._sword_draw_elapsed = p.SWORD_DRAW_DURATION; p.blocking = true; p._update_viewmodel(.3)
	_check(p.request_primary_weapon().accepted and not p.blocking and not p._has_shield_equipped(), "stowing from guard must release the shield defense")
	viewport.queue_free(); await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "tests must preserve original expedition and OS cursor")
	for message in failures: push_error(message)
	print("PRIMARY SHIELD STOW %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
