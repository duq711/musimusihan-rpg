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
var observed_meshes: Dictionary = {}
var shield_surface_id: int = 0
var grip_markers: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_item_instances()
	ExpeditionSession.begin_new_journey()
	original = ExpeditionSession.get_inventory()
	original.set_equipment_durability("offhand", 42.0)
	original.set_equipment_tag("offhand", "원정 방패")
	original.add_item("round_shield", 1, false, {"item_id": "round_shield", "durability": 13.0, "item_tag": "예비 방패"})
	ExpeditionSession.crowns = 137
	ExpeditionSession.hunger = 57.0
	ExpeditionSession.thirst = 39.0
	ExpeditionSession.ensure_journey()
	_check(ExpeditionSession.get_inventory() == original, "ordinary session reuse must retain the same inventory")
	_close(float(original.get_equipment_durability().current), 42.0, "ordinary session reuse must retain equipped durability")
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
	_check(sandbox.active and room.inventory != original and paused, "shield damage trials must use a paused isolated inventory")
	for stage: String in ["high", "medium", "low", "wear"]:
		var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "shield_damage:" + stage)
		_check(entries.size() == 1 and entries[0].action == "shield_damage" and entries[0].payload == stage and entries[0].category == "기본", "each damage preset must be uniquely registered and executable: " + stage)
		await _open_trial(stage)
		var expected := float({"high": 75.0, "medium": 50.0, "low": 20.0, "wear": 75.0}[stage])
		_check_stage("high" if stage == "wear" else stage, expected)
		_check_original_untouched()
	if is_instance_valid(attacker):
		_test_blocked_wear()
		_test_wear_exclusions()
		_test_condition_notification()
		await _test_pause_reset_and_restore()
	else:
		sandbox.finish()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("SHIELD DAMAGE TEST %s: per-item durability, actual shield hits and timed guard, three first-person stages, exclusions, motion-safe signals, F2/reset and original expedition restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_item_instances() -> void:
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	var changed_events: Array = []
	var condition_events: Array = []
	bag.changed.connect(func() -> void: changed_events.append(true))
	bag.equipment_condition_changed.connect(func(slot_name: String) -> void: condition_events.append(slot_name))
	var legacy := bag.get_equipment_instance("offhand")
	legacy["item_tag"] = "오래된 방패"
	legacy["custom"] = {"owner": "traveler"}
	var initial := bag.get_equipment_durability()
	_close(float(initial.current), 100.0, "legacy shield without condition metadata must start intact")
	_check(initial.stage == "high" and float(initial.maximum) == 100.0, "catalog maximum must define a fresh shield")
	for sample: Array in [[101.0, 100.0, "high"], [66.67, 66.67, "high"], [66.66, 66.66, "medium"], [33.34, 33.34, "medium"], [33.33, 33.33, "low"], [-1.0, 0.0, "low"]]:
		var state := bag.set_equipment_durability("offhand", float(sample[0]))
		_close(float(state.current), float(sample[1]), "durability setter must clamp the actual item")
		_check(state.stage == sample[2], "stage boundary must be derived from the current ratio: " + str(sample[0]))
	var event_count := condition_events.size()
	bag.set_equipment_durability("offhand", 0.0)
	bag.damage_equipment_durability("offhand", -9.0)
	bag.damage_equipment_durability("offhand", INF)
	bag.set_equipment_durability("offhand", NAN)
	_check(condition_events.size() == event_count and changed_events.is_empty(), "unchanged/invalid wear must not emit condition or broad inventory changes")
	_check(bag.equipment.offhand == "round_shield", "zero durability must never delete or unequip the shield")
	bag.set_equipment_durability("offhand", 23.0, false)
	_check(condition_events.size() == event_count, "fixture setter must support explicit silent initialization")
	var damaged := bag.damage_equipment_durability("offhand", 5.0)
	_close(float(damaged.current), 18.0, "wear must subtract from the same item")
	_check(condition_events.size() == event_count + 1 and condition_events.back() == "offhand" and changed_events.is_empty(), "wear must publish only the dedicated offhand condition signal")
	bag.set_equipment_durability("offhand", 66.6668, false)
	event_count = condition_events.size()
	bag.damage_equipment_durability("offhand", 0.0003)
	_check(condition_events.size() == event_count + 1 and bag.get_equipment_durability().stage == "medium", "even tiny wear across a stage boundary must refresh the actual visual")
	bag.set_equipment_durability("offhand", 18.0, false)
	_check(legacy.item_tag == "오래된 방패" and legacy.custom == {"owner": "traveler"}, "condition edits must preserve unrelated nested item metadata")
	_check(bag.get_equipment_durability("weapon").is_empty() and bag.set_equipment_durability("weapon", 5.0).is_empty(), "non-durable weapons must not acquire accidental condition state")
	bag.add_item("round_shield", 1, false, {"item_id": "round_shield", "durability": 81.0, "item_tag": "두 번째"})
	_check(_equip_tagged_shield(bag, "두 번째"), "second shield must be equipped through the real inventory transfer")
	_close(float(bag.get_equipment_durability().current), 81.0, "same item ID replacement must bring its own condition")
	_check(_equip_tagged_shield(bag, "오래된 방패"), "first shield must retain its tag in the bag")
	_close(float(bag.get_equipment_durability().current), 18.0, "same item ID swap must restore the first shield's wear")
	_check(bool(bag.unequip("offhand").get("accepted", false)), "shield must transfer to the bag normally")
	_check(bag.get_equipment_durability().is_empty(), "an empty offhand has no durability")
	_check(_equip_tagged_shield(bag, "오래된 방패"), "unequipped shield must be reusable")
	_close(float(bag.get_equipment_durability().current), 18.0, "bag storage must preserve condition")
	bag.seed_default_loadout()
	_close(float(bag.get_equipment_durability().current), 100.0, "a new loadout must receive a fresh shield")


func _open_trial(stage: String) -> void:
	room.run_feature("shield_damage:" + stage)
	player = room.player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	attacker = null
	var count := 0
	for child in room.get_children():
		if child is DungeonEnemy and not child.is_queued_for_deletion():
			count += 1
			attacker = child as DungeonEnemy
			_check(attacker.is_physics_processing() == (stage == "wear"), "only wear trial should start the production attacker's AI")
			attacker.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(count == 1 and not paused and not room.panel_open, "preset must resume a single repeatable production combat fixture")
	_check(room.inventory.equipment.offhand == "round_shield" and room.inventory.equipment.weapon == "rusted_sword", "damage preset must use real sword and shield equipment")
	_check(player.health == player.MAX_HEALTH and player.stamina == player.MAX_STAMINA, "preset selection must recover the test player")
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.0)


func _prepare_guard(held_seconds: float = 0.4, stamina: float = 100.0) -> void:
	player.cancel_sword_attack()
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	player.health = player.MAX_HEALTH
	player.stamina = stamina
	player.velocity = Vector3.ZERO
	player.advance_combat_state(held_seconds, true)


func _front() -> Vector3:
	return player.global_position - player.global_basis.z * 1.5


func _test_blocked_wear() -> void:
	var bag: ExpeditionInventory = room.inventory
	bag.set_equipment_durability("offhand", 75.0)
	for index in range(9):
		_prepare_guard()
		var result := player.receive_attack(20.0, _front())
		_check(bool(result.get("shield_guard", false)) and bool(result.get("blocked", false)), "wear must be produced by actual frontal shield blocking")
		_close(player.health, player.MAX_HEALTH, "wear must preserve existing full health protection")
		_close(player.stamina, 76.4, "wear must preserve ordinary shield stamina cost")
		var expected := 75.0 - (index + 1) * 5.0
		_check_stage("high" if expected > 66.6667 else ("medium" if expected > 33.3333 else "low"), expected)
		_check(player.blocking and player.combat_state == DungeonPlayer.CombatState.READY, "condition notifications must not interrupt sustained guard")
	bag.set_equipment_durability("offhand", 2.0)
	_prepare_guard(0.4, 1.0)
	var last := player.receive_attack(20.0, _front())
	_check(bool(last.get("blocked", false)) and not player.blocking, "last positive stamina must fully block then lower the worn shield")
	_check_stage("low", 0.0)
	_prepare_guard(0.1, 50.0)
	var timed := player.receive_attack(20.0, _front())
	_check(bool(timed.get("parried", false)) and bool(timed.get("shield_guard", false)), "zero-condition shield must retain its timed guard")
	_close(player.stamina, 58.0, "zero-condition timed guard must preserve stamina refund")
	bag.set_equipment_durability("offhand", 75.0)
	_prepare_guard(0.1, 50.0)
	var condition_events: Array = []
	var record_condition := func(slot_name: String) -> void: condition_events.append(slot_name)
	bag.equipment_condition_changed.connect(record_condition)
	attacker.global_position = _front()
	attacker.rotation.y = player.rotation.y + PI
	attacker.velocity = Vector3.ZERO
	attacker.target = player
	attacker.attack_damage = 20.0
	attacker.inflicted_condition = ""
	attacker._set_state(DungeonEnemy.AIState.ACTIVE)
	attacker.state_time = DungeonEnemy.ATTACK_HIT_TIME
	attacker._resolve_active_attack()
	# STAGGER entry clears the enemy's per-swing flags. Verify the actual
	# parry effects instead of expecting ACTIVE-state flags to survive it.
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "actual timed enemy strike must stun the attacker")
	_close(player.health, player.MAX_HEALTH, "actual timed shield strike must block all health damage")
	_close(player.stamina, 58.0, "actual timed shield strike must refund stamina once")
	_check(condition_events == ["offhand"], "actual timed shield strike must wear the equipped shield exactly once")
	_check_stage("high", 70.0)
	attacker._resolve_active_attack()
	_check_stage("high", 70.0)
	_close(player.stamina, 58.0, "rechecking a stunned swing must not repeat its stamina refund")
	_check(condition_events == ["offhand"], "rechecking a stunned swing must not repeat shield wear")
	bag.equipment_condition_changed.disconnect(record_condition)


func _test_wear_exclusions() -> void:
	var bag: ExpeditionInventory = room.inventory
	bag.set_equipment_durability("offhand", 50.0)
	for direction: Vector3 in [player.global_basis.z, player.global_basis.x]:
		_prepare_guard()
		var hit := player.receive_attack(4.0, player.global_position + direction * 1.5)
		_check(not bool(hit.get("blocked", false)), "side/rear attacks must remain unblocked")
		_check_stage("medium", 50.0)
	_prepare_guard(0.4, 0.0)
	player.receive_attack(4.0, _front())
	_check_stage("medium", 50.0)
	_prepare_guard()
	player.advance_combat_state(0.01, false)
	player.receive_attack(4.0, _front())
	_check_stage("medium", 50.0)
	_prepare_guard()
	player.receive_environment_damage(4.0, "shield damage test")
	_check_stage("medium", 50.0)
	_prepare_guard()
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	_check(player.request_primary_weapon().accepted, "test must pack the shield through the production primary action")
	player.advance_combat_state(0.4, true)
	var packed := player.receive_attack(20.0, _front())
	_check(not bool(packed.get("shield_guard", false)), "stowed shield must not catch a sword-only guard")
	_check_stage("medium", 50.0)
	player.reset_shield_carry()
	_check(bool(bag.unequip("offhand").get("accepted", false)), "test must remove the actual shield")
	_prepare_guard()
	var weapon_only := player.receive_attack(20.0, _front())
	_close(float(weapon_only.get("damage", 0.0)), 4.0, "weapon-only block must retain chip damage")
	for index in range(bag.slots.size()):
		if str(bag.slots[index].get("id", "")) == "round_shield":
			_check(bool(bag.equip_from_slot(index).get("accepted", false)), "stored shield must re-equip")
			break
	_check_stage("medium", 50.0)


func _test_condition_notification() -> void:
	var bag: ExpeditionInventory = room.inventory
	player.reset_shield_carry()
	_prepare_guard()
	player._update_viewmodel(0.25)
	var shield_pose := player.shield_pivot.transform
	var sword_pose := player.weapon_pivot.transform
	var timer := player._sword_draw_elapsed
	var block_time := player.block_time
	bag.set_equipment_durability("offhand", 20.0)
	_check(player.blocking and is_equal_approx(player.block_time, block_time), "condition-only edit must preserve current guard timing")
	_close(player._sword_draw_elapsed, timer, "condition-only edit must not restart weapon drawing")
	_check(player.shield_pivot.transform.is_equal_approx(shield_pose) and player.weapon_pivot.transform.is_equal_approx(sword_pose), "condition signal must not move either held prop")
	_check_stage("low", 20.0)
	var previous := bag
	var replacement := ExpeditionInventory.new()
	replacement.seed_default_loadout()
	replacement.set_equipment_durability("offhand", 50.0)
	player.bind_inventory(replacement)
	previous.set_equipment_durability("offhand", 75.0)
	var current: Dictionary = player.get_shield_damage_snapshot()
	_check(current.stage == "medium" and current.visual_stage == "medium", "rebinding inventory must refresh condition and disconnect the previous bag's signal")
	player.bind_inventory(previous)
	_check_stage("high", 75.0)


func _test_pause_reset_and_restore() -> void:
	var bag: ExpeditionInventory = room.inventory
	bag.set_equipment_durability("offhand", 50.0)
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.physical_keycode = KEY_F2
	f2.pressed = true
	room._unhandled_input(f2)
	_check(paused and room.panel_open, "F2 must pause the actual shield wear fixture")
	var state_time := attacker.state_time
	attacker.set_physics_process(true)
	await create_timer(0.03, true).timeout
	_close(attacker.state_time, state_time, "F2 must freeze the actual attacker's clock")
	_close(float(bag.get_equipment_durability().current), 50.0, "paused combat must not wear the shield")
	attacker.set_physics_process(false)
	await _open_trial("wear")
	_check_stage("high", 75.0)
	_check_original_untouched()
	var old_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != old_bag and room.inventory != original and paused and room.panel_open, "reset must replace only the sandbox loadout and return to its menu")
	_close(float(room.inventory.get_equipment_durability().current), 100.0, "full test reset must restore fresh shield condition")
	await _open_trial("low")
	_check_stage("low", 20.0)
	_check_original_untouched()
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "leaving must restore the exact original inventory object")
	_check(ExpeditionSession.capture_snapshot() == original_snapshot, "leaving must restore the full original session")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "trial wear and transfers must preserve every original shield instance and item metadata")


func _check_stage(expected: String, current: float) -> void:
	var state: Dictionary = player.get_shield_damage_snapshot()
	_close(float(state.get("current", -1.0)), current, "actual equipped condition must match the expected value")
	_check(str(state.get("stage", "")) == expected and str(state.get("visual_stage", "")) == expected, "actual first-person shield stage must track its equipped item: " + expected)
	var surface := player.shield_model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	_check(surface != null and surface.mesh != null, "damage stage must use an actual three-dimensional shield mesh")
	if surface == null or surface.mesh == null:
		return
	if shield_surface_id == 0:
		shield_surface_id = surface.get_instance_id()
	_check(surface.get_instance_id() == shield_surface_id, "stage changes must preserve the original shield node and attachment hierarchy")
	_check(int(state.get("mesh_id", 0)) == surface.mesh.get_instance_id(), "damage snapshot must describe the mesh that is actually installed")
	_check(surface.mesh.get_surface_count() > 0 and int(state.get("vertex_count", 0)) > 0, "stage must contain renderable mesh geometry")
	var expected_source := "res://assets/3d/player/sword_shield/round_shield.glb" if expected == "high" else "res://assets/3d/player/shield_damage/round_shield_" + expected + ".glb"
	_check(str(state.get("source_path", "")) == expected_source, "stage must use its production model source")
	for other_stage: String in observed_meshes:
		if other_stage != expected:
			_check(surface.mesh != observed_meshes[other_stage], "different condition stages must replace actual geometry, not only a reported label")
	observed_meshes[expected] = surface.mesh
	# Inspect every rendered surface, including cut faces: a Boolean cutter
	# left behind as geometry can otherwise pass the stage/mesh identity checks.
	var radius := _mesh_max_xy_radius(surface.mesh)
	_check(radius <= 0.435, "shield %s must not contain cutter geometry outside the 0.435 m disc (actual radius %.6f m)" % [expected, radius])
	if observed_meshes.has("high"):
		var intact_radius := _mesh_max_xy_radius(observed_meshes["high"] as Mesh)
		_check(radius <= intact_radius + 0.0005, "damage must remove material without expanding the intact shield silhouette (stage %s, actual %.6f m, intact %.6f m)" % [expected, radius, intact_radius])
	for marker_name: String in ["RearGrip", "RearGripTop", "RearGripBottom", "RearArmStrap"]:
		var marker := player.shield_model.find_child(marker_name, true, false) as Node3D
		_check(marker != null, "stage must preserve its authored hand/arm attachment: " + marker_name)
		if marker == null:
			continue
		if not grip_markers.has(marker_name):
			grip_markers[marker_name] = marker.transform
		_check(marker.transform.is_equal_approx(grip_markers[marker_name]), "changing damage stage must not shift the existing grip marker: " + marker_name)


func _mesh_max_xy_radius(mesh: Mesh) -> float:
	var maximum := 0.0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if not vertex.is_finite():
				return INF
			maximum = maxf(maximum, Vector2(vertex.x, vertex.y).length())
	return maximum


func _equip_tagged_shield(bag: ExpeditionInventory, tag: String) -> bool:
	for index in range(bag.slots.size()):
		var instance: Dictionary = bag.slots[index].get("instance", {})
		if str(bag.slots[index].get("id", "")) == "round_shield" and str(instance.get("item_tag", "")) == tag:
			return bool(bag.equip_from_slot(index).get("accepted", false))
	return false


func _check_original_untouched() -> void:
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "sandbox condition changes must not mutate original equipment or stacks")
	_check(sandbox.saved_session == original_snapshot, "sandbox must preserve the original reusable session snapshot")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "shield condition scene transition timed out: " + path)


func _close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.002, "%s (actual %.4f, expected %.4f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
