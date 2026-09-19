extends SceneTree

var failures: Array[String] = []
var room: Node3D
var player: DungeonPlayer
var attacker: DungeonEnemy
var sandbox: Node
var original: ExpeditionInventory
var original_snapshot: Dictionary
var original_slots: Array
var original_equipment: Dictionary
var original_data: Dictionary


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	original = ExpeditionSession.get_inventory()
	original.set_equipment_durability("offhand", 42.0)
	original.set_equipment_tag("offhand", "원정 방패")
	original.add_item("round_shield", 1, false, {"item_id": "round_shield", "durability": 13.0, "item_tag": "예비 방패"})
	ExpeditionSession.crowns = 137
	ExpeditionSession.hunger = 57.0
	original_snapshot = ExpeditionSession.capture_snapshot()
	original_slots = original.slots.duplicate(true)
	original_equipment = original.equipment.duplicate(true)
	original_data = original.equipment_data.duplicate(true)
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "shield_damage:shatter")
	_check(entries.size() == 1 and entries[0].action == "shield_damage" and entries[0].payload == "shatter", "F2 must register a playable shield destruction fixture")
	await _open_trial()
	_test_zero_setter_and_exclusions()
	await _open_trial()
	_test_final_block(false)
	await _test_pause_and_physics()
	await _open_trial()
	_test_final_block(true)
	await _test_cleanup_and_restore()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("SHIELD SHATTER TEST %s: real final block and timed guard, item destruction, physical debris and floor contact, no duplicate break, hidden unusable zero-condition gear, F2/replay/reset and original session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _open_trial() -> void:
	room.run_feature("shield_damage:shatter")
	player = room.player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	attacker = null
	var count := 0
	for child in room.get_children():
		if child is DungeonEnemy and not child.is_queued_for_deletion():
			attacker = child as DungeonEnemy
			count += 1
			_check(attacker.is_physics_processing() and attacker.target == player, "destruction trial must enable a real production attacker")
			attacker.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(count == 1 and not paused and not room.panel_open, "destruction trial must resume one isolated duel")
	_check(room.inventory != original and room.inventory.equipment.offhand == "round_shield", "trial must equip only its isolated shield")
	_close(float(room.inventory.get_equipment_durability().current), 5.0, "destruction fixture must restore a shield with five condition")
	_check(int(player.get_shield_shatter_snapshot().get("fragment_count", -1)) == 0 and player.get_node_or_null("ShieldShatterDebris") == null, "reselecting the trial must remove all previous fragments immediately")
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.0)
	_check(player._has_shield_equipped() and player.shield_pivot.visible, "new trial shield must be usable and visible again")
	_check_original_untouched()


func _prepare_guard(held_seconds: float = 0.4) -> void:
	player.cancel_sword_attack()
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	player.health = player.MAX_HEALTH
	player.stamina = 100.0
	player.velocity = Vector3.ZERO
	player.advance_combat_state(held_seconds, true)
	player._update_viewmodel(0.3)


func _front() -> Vector3:
	return player.global_position - player.global_basis.z * 1.5


func _test_zero_setter_and_exclusions() -> void:
	var bag: ExpeditionInventory = room.inventory
	var before: Dictionary = player.get_shield_shatter_snapshot()
	bag.set_equipment_durability("offhand", 0.0)
	player._update_viewmodel(0.0)
	_check(bag.equipment.offhand == "round_shield" and not player._has_shield_equipped() and not player.shield_pivot.visible, "setting zero must keep the data item but hide and disable its shield")
	_prepare_guard()
	var zero_hit := player.receive_attack(20.0, _front())
	_check(not bool(zero_hit.get("shield_guard", false)), "an already-zero item must not provide shield protection")
	_close(float(zero_hit.get("damage", -1.0)), 4.0, "already-zero shield must leave the existing sword guard rules in effect")
	_check(bag.equipment.offhand == "round_shield", "an already-zero item must not be auto-destroyed by an unrelated sword guard")
	_check(int(player.get_shield_shatter_snapshot().get("spawn_count", -1)) == int(before.get("spawn_count", 0)), "a data-only zero edit and sword guard must not spawn destruction effects")
	bag.set_equipment_durability("offhand", 5.0)
	_prepare_guard()
	var rear := player.receive_attack(4.0, player.global_position + player.global_basis.z * 1.5)
	_check(not bool(rear.get("blocked", false)), "a rear hit must remain unblocked")
	_close(float(bag.get_equipment_durability().current), 5.0, "rear damage must not destroy a shield")
	_prepare_guard()
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	_check(player.request_primary_weapon().accepted, "exclusion test must stow the actual shield")
	player.advance_combat_state(0.4, true)
	var packed := player.receive_attack(21.0, _front())
	_check(not bool(packed.get("shield_guard", false)), "packed shield must not receive the sword-only block")
	_close(float(bag.get_equipment_durability().current), 5.0, "a stowed shield must not wear or shatter")
	_check(int(player.get_shield_shatter_snapshot().get("fragment_count", -1)) == 0, "excluded hits must not create physical fragments")


func _test_final_block(timed: bool) -> void:
	if not is_instance_valid(attacker):
		_check(false, "destruction fixture has no actual attacker")
		return
	var bag: ExpeditionInventory = room.inventory
	var stored_shields := bag.count_item("round_shield")
	var previous_spawn_count := int(player.get_shield_shatter_snapshot().get("spawn_count", 0))
	_prepare_guard(0.1 if timed else 0.4)
	player.stamina = 50.0 if timed else 100.0
	attacker.global_position = _front()
	attacker.rotation.y = player.rotation.y + PI
	attacker.velocity = Vector3.ZERO
	attacker.target = player
	_check(is_equal_approx(attacker.attack_damage, 21.0), "fixture must use its actual 21-damage warden attack")
	attacker.inflicted_condition = ""
	attacker._set_state(DungeonEnemy.AIState.ACTIVE)
	attacker.state_time = DungeonEnemy.ATTACK_HIT_TIME
	attacker._resolve_active_attack()
	_close(player.health, player.MAX_HEALTH, "the attack that breaks the shield must still be completely blocked")
	_close(player.stamina, 58.0 if timed else 75.22, "breaking must preserve the final strike's existing stamina rule")
	_check((attacker.ai_state == DungeonEnemy.AIState.STAGGER) == timed, "breaking on a just guard must retain its real attacker stun")
	_check(str(bag.equipment.get("offhand", "")) == "" and bag.get_equipment_durability().is_empty(), "broken shield must be removed from its equipment slot")
	_check(bag.count_item("round_shield") == stored_shields, "destroyed item must not be silently returned to the inventory")
	_check(not player._has_shield_equipped() and not player.blocking and not player.shield_pivot.visible, "destruction must end shield guard and hide the original shield")
	var snapshot: Dictionary = player.get_shield_shatter_snapshot()
	_check(int(snapshot.get("spawn_count", -1)) == previous_spawn_count + 1, "a final hit must create exactly one shatter event")
	_check(bool(snapshot.get("active", false)) and int(snapshot.get("fragment_count", 0)) >= 20 and int(snapshot.get("fragment_count", 99)) <= 32, "shatter must create a bounded set of real physical fragments")
	_check_fragment_nodes(snapshot)
	attacker._resolve_active_attack()
	_check(int(player.get_shield_shatter_snapshot().get("spawn_count", -1)) == previous_spawn_count + 1, "rechecking the same enemy swing must not duplicate fragments")
	_prepare_guard()
	var next_hit := player.receive_attack(20.0, _front())
	_check(not bool(next_hit.get("shield_guard", false)), "later attacks must not reuse the destroyed shield")
	_close(float(next_hit.get("damage", -1.0)), 4.0, "subsequent guard must use the remaining sword's chip-damage rule")
	_check(int(player.get_shield_shatter_snapshot().get("spawn_count", -1)) == previous_spawn_count + 1, "later sword guards must not re-shatter the missing shield")
	player.advance_combat_state(0.01, false)
	player._update_viewmodel(1.0)
	_check(player._left_hand_role() == "sword_support" and player.sword_support_arm.visible, "the released left hand must transition to the existing two-handed sword grip")
	_check_original_untouched()


func _check_fragment_nodes(snapshot: Dictionary) -> void:
	var debris := player.get_node_or_null("ShieldShatterDebris")
	_check(debris != null, "physical debris must be owned by the actual player cleanup lifecycle")
	if debris == null:
		return
	var bodies: Array[RigidBody3D] = []
	for child in debris.get_children():
		if child is RigidBody3D: bodies.append(child as RigidBody3D)
	_check(bodies.size() == int(snapshot.get("fragment_count", -1)), "snapshot must count the actual physical bodies")
	for body in bodies:
		_check(body.collision_layer == 0 and body.collision_mask == 2, "fragments must collide only with world geometry, never player or enemies")
		_check(body.mass > 0.0 and not body.freeze, "fragments must be dynamic rigid bodies")
		var has_shape := false
		var has_mesh := false
		for child in body.get_children():
			if child is CollisionShape3D:
				var shape := child as CollisionShape3D
				has_shape = has_shape or (not shape.disabled and (shape.shape is ConvexPolygonShape3D or shape.shape is BoxShape3D))
			if child is MeshInstance3D:
				var visual := child as MeshInstance3D
				has_mesh = has_mesh or (visual.mesh != null and visual.visible and visual.layers == 1)
		_check(has_shape and has_mesh, "each body needs a real collision shape and visible 3D fragment")


func _test_pause_and_physics() -> void:
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.physical_keycode = KEY_F2
	f2.pressed = true
	room._unhandled_input(f2)
	_check(paused and room.panel_open, "F2 must pause the debris trial")
	await process_frame
	var suspended: Dictionary = player.get_shield_shatter_snapshot()
	await create_timer(0.08, true).timeout
	var still: Dictionary = player.get_shield_shatter_snapshot()
	_check(still.get("bodies", []) == suspended.get("bodies", []), "F2 pause must freeze actual fragment positions and velocities")
	_close(float(still.get("age", -1.0)), float(suspended.get("age", -2.0)), "F2 pause must freeze fragment lifetime")
	room._unhandled_input(f2)
	_check(not paused and not room.panel_open, "F2 must resume the same physical fragments")
	var initial_positions: Dictionary = {}
	for body: Dictionary in still.get("bodies", []): initial_positions[int(body.id)] = body.position
	var observed_contacts: Dictionary = {}
	var moved := false
	var lowest_y := INF
	for tick in range(540):
		await physics_frame
		var current: Dictionary = player.get_shield_shatter_snapshot()
		for body: Dictionary in current.get("bodies", []):
			var position: Vector3 = body.position
			lowest_y = minf(lowest_y, position.y)
			if initial_positions.has(int(body.id)):
				moved = moved or position.distance_to(initial_positions[int(body.id)]) > 0.05
			if bool(body.get("ground_contact", false)): observed_contacts[int(body.id)] = true
	var final: Dictionary = player.get_shield_shatter_snapshot()
	var fragments: Array = final.get("bodies", [])
	_check(moved and not fragments.is_empty(), "fragments must move physically and remain until their lifetime expires")
	_check(observed_contacts.size() >= ceili(fragments.size() * 0.8), "most fragments must make actual floor contact, rather than disappear or fall through it")
	var settled := 0
	for body: Dictionary in fragments:
		var velocity: Vector3 = body.get("linear_velocity", Vector3.INF)
		if bool(body.get("sleeping", false)) or velocity.length() < 0.2:
			settled += 1
	_check(settled >= ceili(fragments.size() * 0.8), "most physical fragments must settle after their fall")
	var debris := player.get_node_or_null("ShieldShatterDebris")
	if debris != null:
		for child in debris.get_children():
			if not child is RigidBody3D: continue
			var body := child as RigidBody3D
			var query := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.2, body.global_position + Vector3.DOWN * 4.0, 2)
			var floor_hit := body.get_world_3d().direct_space_state.intersect_ray(query)
			_check(not floor_hit.is_empty(), "settled debris must remain over actual world floor collision")
			if not floor_hit.is_empty():
				var bottom := _body_bottom_y(body)
				var floor_y := (floor_hit.position as Vector3).y
				_check(bottom >= floor_y - 0.025, "%s collider must not penetrate deeply below the floor (bottom %.4f, floor %.4f)" % [body.name, bottom, floor_y])
	print("SHIELD SHATTER PHYSICS: contacts=%d/%d settled=%d lowest_center_y=%.4f" % [observed_contacts.size(), fragments.size(), settled, lowest_y])


func _body_bottom_y(body: RigidBody3D) -> float:
	var result := INF
	for child in body.get_children():
		if not child is CollisionShape3D: continue
		var collision := child as CollisionShape3D
		if collision.shape is ConvexPolygonShape3D:
			for point: Vector3 in (collision.shape as ConvexPolygonShape3D).points:
				result = minf(result, (collision.global_transform * point).y)
		elif collision.shape is BoxShape3D:
			var half := (collision.shape as BoxShape3D).size * 0.5
			for x: float in [-1.0, 1.0]:
				for y: float in [-1.0, 1.0]:
					for z: float in [-1.0, 1.0]:
						result = minf(result, (collision.global_transform * (half * Vector3(x, y, z))).y)
	return result


func _test_cleanup_and_restore() -> void:
	var expiring := player.get_node_or_null("ShieldShatterDebris")
	_check(expiring != null, "expiry check needs the actual last-hit debris")
	if expiring != null:
		expiring.age = expiring.LIFETIME - .02
		for tick in 4: await physics_frame
		await process_frame
		_check(player.get_node_or_null("ShieldShatterDebris") == null and int(player.get_shield_shatter_snapshot().fragment_count) == 0, "lifetime expiry must remove every actual body and leave a safe empty snapshot")
	await _open_trial()
	_test_final_block(false)
	room.run_feature("shield_damage:low")
	_check(player.get_node_or_null("ShieldShatterDebris") == null and int(player.get_shield_shatter_snapshot().get("fragment_count", -1)) == 0, "changing fixture must remove old debris immediately")
	_close(float(room.inventory.get_equipment_durability().current), 20.0, "another shield preset must restore its real usable condition")
	await _open_trial()
	_test_final_block(false)
	var old_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(player.get_node_or_null("ShieldShatterDebris") == null and int(player.get_shield_shatter_snapshot().get("fragment_count", -1)) == 0, "test reset must clear every fragment")
	_check(room.inventory != old_bag and room.inventory != original and paused and room.panel_open, "reset must create only a fresh isolated inventory")
	_close(float(room.inventory.get_equipment_durability().current), 100.0, "test reset must restore an intact shield")
	await _open_trial()
	_test_final_block(false)
	_check_original_untouched()
	room.leave_room()
	_check(player.get_node_or_null("ShieldShatterDebris") == null, "scene exit must clean physical fragments before loading")
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "exit must restore the exact original inventory")
	_check(ExpeditionSession.capture_snapshot() == original_snapshot, "exit must restore all original session fields")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "trial destruction must never delete or damage original shield instances")


func _check_original_untouched() -> void:
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "trial fragments and destroyed equipment must leave the original inventory untouched")
	_check(sandbox.saved_session == original_snapshot, "test session must preserve its original restoration snapshot")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "shield destruction scene transition timed out: " + path)


func _close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.002, "%s (actual %.4f, expected %.4f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
