extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const REGIONS: Array[String] = ["left_arm", "right_arm", "left_leg", "right_leg", "both_legs", "head", "distributed"]

var failures: Array[String] = []
var room: Node3D
var defeat_count := 0
var asset_checks_executed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	original.equipment["weapon"] = "hunting_bow"
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 61.0
	ExpeditionSession.set_stress(37.5)
	var before := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	# Only unrelated player/survival work is frozen. Timers, enemy damage,
	# detached-part physics and the real F2 pause path continue normally.
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original, "trial has a separate expedition and inventory")
	_test_catalog()
	if CREEP.is_available():
		asset_checks_executed = true
		for region in REGIONS:
			await _test_trial(region)
		await _test_reselection_cancellation_reset()
	else:
		_test_missing_asset()
	_check(original.slots == original_slots and original.equipment == original_equipment, "trial damage, rewards and loadouts leave the original inventory untouched")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "exit restores the exact expedition and original inventory identity")
	for failure in failures:
		push_error("CREEP DISMEMBERMENT TRIAL TEST FAIL: " + failure)
	var coverage := "five localized cuts, surviving both-leg loss, crawling and F2 pose pause, distributed-hit comparison, single head-death reward, real timers and partial-cut pause/cancel/reset, session restoration" if asset_checks_executed else "catalog, absent-asset guidance and session restoration; actual cuts SKIPPED"
	print("CREEP DISMEMBERMENT TRIAL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + coverage)
	quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	for region in REGIONS:
		var feature_id := "creep_dismemberment:" + region
		var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == feature_id)
		_check(matching.size() == 1, "exactly one catalog entry: " + feature_id)
		if matching.size() == 1:
			var entry: Dictionary = matching[0]
			_check(entry.category == "기본" and entry.action == "creep_dismemberment" and entry.payload == region, "entry dispatches its actual localized trial: " + feature_id)
			if region in ["left_leg", "right_leg", "both_legs"]:
				_check(str(entry.detail).contains("기어"), "leg trial describes the new crawling behavior: " + feature_id)


func _test_missing_asset() -> void:
	print("CREEP DISMEMBERMENT ASSET CHECKS SKIPPED: licensed model is absent; validating public-clone behavior.")
	var original_actors: Array = _room_enemies()
	for region in REGIONS:
		room.run_feature("creep_dismemberment:" + region)
		_check(room.panel_open and paused and room.enemies_alive == 2, "absent asset leaves the default encounter paused: " + region)
		_check(_room_enemies() == original_actors and _find_creep() == null and room.creep_dismemberment_timer == null, "absent asset creates neither a Creep nor a pending localized hit: " + region)
		_check(room.status_label.text.contains("설치"), "absent asset gives setup guidance: " + region)


func _test_trial(region: String) -> void:
	room._show_test_panel()
	room.run_feature("creep_dismemberment:" + region)
	var creep = _find_creep()
	_check(creep != null, "trial spawns the actual Creep: " + region)
	if creep == null:
		return
	var initial: Dictionary = creep.dismemberment.snapshot()
	_check(initial.enabled and initial.severed.is_empty() and initial.detached_bodies == 0, "new actor has its complete body: " + region)
	_check(not paused and not room.panel_open and room.enemies_alive == 1, "trial resumes a single live encounter: " + region)
	_check(creep.health == creep.max_health and room.player.health == room.player.MAX_HEALTH, "trial heals both participants: " + region)
	_check(is_equal_approx(creep.max_health, 118.0 if region == "both_legs" else 82.0), "only the four-hit fixture gets its documented survival health allowance: " + region)
	_check(creep.target == room.player and creep.game == room and creep.hud == room.hud, "trial retains the production combat and reward connections: " + region)
	_check(not creep.is_physics_processing(), "AI waits during scripted local hits: " + region)
	var timer: Timer = room.creep_dismemberment_timer
	_check(is_instance_valid(timer) and not timer.is_stopped() and is_equal_approx(timer.wait_time, 0.8) and timer.process_mode == Node.PROCESS_MODE_PAUSABLE, "trial owns a real pausable 0.8-second timer: " + region)
	if not is_instance_valid(timer):
		return
	var loot_before: int = room.loot_count
	var fragments_before: int = room.inventory.count_item("rune_fragment")
	var defeats_before := defeat_count
	creep.defeated.connect(_on_creep_defeated)
	if region == "left_arm":
		await _press_f2()
		var time_left := timer.time_left
		await _advance_frames(60)
		_check(paused and room.panel_open and is_equal_approx(timer.time_left, time_left) and creep.health == creep.max_health, "F2 pauses the pending first hit for longer than its full countdown")
		await _press_f2()
	var first_hit := await _wait_for_hit_count(1)
	_check(first_hit, "timer applies its first actual hit: " + region)
	if not first_hit:
		room._show_test_panel()
		return
	var first: Dictionary = creep.dismemberment.snapshot()
	var first_region := "left_arm" if region == "distributed" else ("left_leg" if region == "both_legs" else region)
	_check(is_equal_approx(float(first.damage.get(first_region, 0.0)), 18.0) and first.severed.is_empty() and first.detached_bodies == 0, "one 18-damage hit accumulates only its region without an early cut: " + region)
	_check(is_equal_approx(creep.health, creep.max_health - 18.0) and not creep.is_physics_processing(), "ordinary health damage occurs while the AI waits for hit two: " + region)
	if region == "left_arm":
		await _press_f2()
		var between_hits := timer.time_left
		await _advance_frames(60)
		_check(is_equal_approx(timer.time_left, between_hits) and creep.dismemberment.snapshot().damage == first.damage and room.creep_dismemberment_hit_count == 1, "F2 freezes the partially accumulated trial without an early second hit")
		await _press_f2()
	if region == "both_legs":
		_check(await _wait_for_hit_count(2), "the four-hit fixture finishes the first leg before targeting the second")
		var partial: Dictionary = creep.dismemberment.snapshot()
		_check(partial.severed.size() == 1 and "left_leg" in partial.severed and partial.detached_bodies == 1 and is_zero_approx(float(partial.damage.get("right_leg", 0.0))), "two real hits remove only the left leg, without a premature right-leg hit")
		_check(not creep.is_physics_processing() and creep.is_crawling(), "AI remains on hold, but actual leg loss already selects crawling")
		await _press_f2()
		var partial_time := timer.time_left
		var partial_bodies := _physical_transforms(creep)
		await _advance_frames(60)
		_check(is_equal_approx(timer.time_left, partial_time) and room.creep_dismemberment_hit_count == 2 and creep.dismemberment.snapshot().severed == partial.severed and _physical_transforms(creep) == partial_bodies, "F2 pauses the partially completed both-leg trial and its detached-part physics")
		await _press_f2()
	var completed := await _wait_for_completion()
	_check(completed, "the final ordinary hit completes the trial: " + region)
	if not completed:
		room._show_test_panel()
		return
	var result: Dictionary = creep.dismemberment.snapshot()
	_check(room.creep_dismemberment_target == null and room.creep_dismemberment_timer == null, "completed fixture releases timer and target references: " + region)
	if region == "distributed":
		_check(result.severed.is_empty() and result.detached_bodies == 0 and is_equal_approx(float(result.damage.get("left_arm", 0.0)), 18.0) and is_equal_approx(float(result.damage.get("right_arm", 0.0)), 18.0), "the same total damage spread across two arms causes no dismemberment")
	elif region == "both_legs":
		_check(result.severed.size() == 2 and "left_leg" in result.severed and "right_leg" in result.severed and result.detached_bodies == 2, "four real hits detach both legs as two independent physical parts")
		_check(is_equal_approx(float(result.damage.get("left_leg", 0.0)), 36.0) and is_equal_approx(float(result.damage.get("right_leg", 0.0)), 36.0), "both legs accumulate their own 36 damage through ordinary localized hits")
	else:
		_check(result.severed.size() == 1 and region in result.severed and result.detached_bodies == 1, "only the repeatedly hit region detaches as a physical part: " + region)
	if region == "head":
		_check(creep.ai_state == DungeonEnemy.AIState.DEAD and room.enemies_alive == 0, "head removal immediately ends the living encounter")
		_check(defeat_count == defeats_before + 1 and room.loot_count == loot_before + 1 and room.inventory.count_item("rune_fragment") == fragments_before + 1, "head removal awards exactly one ordinary defeat reward")
		creep.receive_located_hit(1000.0, creep.global_position + Vector3.LEFT, 1.0, true, creep.global_position)
		_check(defeat_count == defeats_before + 1 and room.loot_count == loot_before + 1, "further corpse hits cannot duplicate head-cut rewards")
	else:
		var expected_damage := 72.0 if region == "both_legs" else 36.0
		_check(creep.ai_state != DungeonEnemy.AIState.DEAD and is_equal_approx(creep.health, creep.max_health - expected_damage) and room.enemies_alive == 1, "limb loss or distributed hits preserve the damaged live enemy: " + region)
		_check(creep.is_physics_processing() and room.enemy_ai_enabled, "real AI resumes after all scheduled hits: " + region)
		_check(defeat_count == defeats_before and room.loot_count == loot_before and room.inventory.count_item("rune_fragment") == fragments_before, "a living dismembered enemy grants no kill or reward: " + region)
	if region in ["left_leg", "right_leg", "both_legs"]:
		await _test_crawl_trial(creep, region)
	await _advance_frames(6)
	if region == "left_arm":
		await _press_f2()
		var bodies: Dictionary = _physical_transforms(creep)
		_check(not bodies.is_empty(), "living cut produced a real rigid body before pause")
		await _advance_frames(16)
		_check(bodies == _physical_transforms(creep), "F2 freezes detached-part physics while the Creep is alive")
		await _press_f2()
		await _advance_frames(12)
		_check(bodies != _physical_transforms(creep), "resuming releases the severed part back into real physics")
	room._show_test_panel()


func _test_crawl_trial(creep, region: String) -> void:
	_check(creep.is_crawling(), "actual loss of either leg enters crawling: " + region)
	await _advance_frames(45)
	var crawl_state: Dictionary = creep.crawl.snapshot()
	_check(bool(crawl_state.active) and float(crawl_state.blend) > 0.95 and str(creep.animation_clip).begins_with("crawl"), "surviving leg-loss trial uses the fully blended production crawl pose: " + region)
	await _press_f2()
	var held_pose: Dictionary = creep.crawl.snapshot().duplicate(true)
	var held_position: Vector3 = creep.position
	await _advance_frames(24)
	_check(creep.crawl.snapshot() == held_pose and creep.position == held_position, "F2 freezes the actual crawl motion and movement: " + region)
	await _press_f2()
	await _advance_frames(12)
	_check(creep.is_crawling() and (creep.crawl.snapshot() != held_pose or creep.position != held_position), "resuming continues the production crawl motion: " + region)


func _test_reselection_cancellation_reset() -> void:
	var prior = _find_creep()
	room.player.apply_body_damage("left_arm", 24.0)
	room.run_feature("creep_dismemberment:left_arm")
	var fresh = _find_creep()
	_check(fresh != null and fresh != prior and (not is_instance_valid(prior) or prior.is_queued_for_deletion()), "reselection removes the prior actor and all its detached children")
	if fresh == null:
		return
	_check(fresh.dismemberment.snapshot().severed.is_empty() and fresh.health == fresh.max_health and room.player.health == room.player.MAX_HEALTH, "reselection restores the complete actor and heals the player")
	var old_timer: Timer = room.creep_dismemberment_timer
	room.run_feature("creep_dismemberment:right_arm")
	_check(fresh.is_queued_for_deletion() and old_timer.is_stopped() and old_timer.is_queued_for_deletion(), "reselection before a hit cancels the old actor and timer")
	var pending = _find_creep()
	await _wait_for_hit_count(1)
	var damage_before: Dictionary = pending.dismemberment.snapshot().damage.duplicate(true)
	var loot_before: int = room.loot_count
	room.run_feature("torch")
	_check(room.creep_dismemberment_timer == null and room.creep_dismemberment_target == null, "switching entries cancels the pending second hit")
	await _advance_frames(60)
	_check(is_instance_valid(pending) and pending.dismemberment.snapshot().damage == damage_before and pending.dismemberment.snapshot().severed.is_empty() and room.loot_count == loot_before, "cancelled trial cannot later cut the retained enemy or award loot")
	_check(pending.is_physics_processing(), "cancellation does not leave the retained enemy's AI frozen")
	room.run_feature("creep_dismemberment:both_legs")
	var partly_cut = _find_creep()
	_check(await _wait_for_hit_count(2), "cancellation case reaches the intermediate one-leg cut")
	var partial_damage: Dictionary = partly_cut.dismemberment.snapshot().damage.duplicate(true)
	room.run_feature("torch")
	await _advance_frames(110)
	_check(room.creep_dismemberment_timer == null and partly_cut.dismemberment.snapshot().damage == partial_damage and partly_cut.dismemberment.snapshot().severed.size() == 1 and partly_cut.is_crawling() and partly_cut.is_physics_processing(), "cancelling between legs prevents later right-leg hits and releases the retained crawler")
	room.run_feature("creep_dismemberment:head")
	var reset_target = _find_creep()
	var reset_timer: Timer = room.creep_dismemberment_timer
	room.reset_room()
	_check(reset_target.is_queued_for_deletion() and reset_timer.is_stopped() and reset_timer.is_queued_for_deletion(), "reset cancels pending decapitation and removes the old Creep")
	_check(room.panel_open and paused and room.enemies_alive == 2 and room.creep_dismemberment_timer == null and _find_creep() == null, "reset restores the paused default encounters")
	room._hide_test_panel()
	await _advance_frames(60)
	_check(room.enemies_alive == 2 and room.loot_count == 0 and _find_creep() == null, "resuming after reset cannot fire a stale cut or reward")
	room._show_test_panel()


func _wait_for_hit_count(count: int) -> bool:
	for frame in 220:
		if room.creep_dismemberment_hit_count >= count:
			return true
		await _advance_frames(1)
	return false


func _wait_for_completion() -> bool:
	for frame in 220:
		if room.creep_dismemberment_timer == null:
			return true
		await _advance_frames(1)
	return false


func _physical_transforms(node: Node) -> Dictionary:
	var result := {}
	for child in node.get_children():
		if child is RigidBody3D:
			result[child.get_instance_id()] = child.global_transform
		result.merge(_physical_transforms(child))
	return result


func _advance_frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _on_creep_defeated(_creep) -> void:
	defeat_count += 1


func _room_enemies() -> Array:
	return room.get_children().filter(func(actor: Node) -> bool: return actor is DungeonEnemy and not actor.is_queued_for_deletion())


func _find_creep():
	for actor in _room_enemies():
		if actor is CREEP:
			return actor
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
