extends SceneTree
const PREVIEW := preload("res://tests/first_person_motion_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var original_inventory := before.get("inventory") as ExpeditionInventory
	var original_contents := PREVIEW.inventory_fingerprint(original_inventory)
	_test_inventory_fingerprint()
	var hashes := PREVIEW.source_hashes()
	for source: String in PREVIEW.SOURCE_FILES:
		_check(str(hashes.get(source, "")).length() == 64, "consumed capture dependencies must exist and have content hashes: " + source)
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var ids := {}
	for id: String in PREVIEW.POSE_IDS:
		_check(not ids.has(id), "pose names must be unique: " + id)
		ids[id] = true
		var viewport := PREVIEW.create_viewport()
		root.add_child(viewport)
		var fixture := PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		_check(PREVIEW.configure_pose(fixture, id), "actual production action must configure: " + id)
		var result := PREVIEW.inspect_pose(fixture, id)
		_check(result.passed, "actual production action and input isolation must match pose: " + id)
		_check(viewport.size == Vector2i(1280, 720) and viewport.gui_disable_input and not viewport.physics_object_picking, "motion fixture must use an isolated screenshot viewport")
		if id == "bow_release":
			_check(fixture.inventory.count_item("wooden_arrow") == 11, "release pose must consume one real arrow rather than synthesize a weapon pose")
		if id == "shield_impact":
			_check(bool(fixture.action_result.get("blocked", false)), "shield impact must use the real blocked receive_attack path")
		(fixture.player as DungeonPlayer).cancel_timed_interaction()
		(fixture.player as DungeonPlayer).cancel_flail_action()
		viewport.queue_free()
		await process_frame
	await _test_production_sequences()
	sandbox.finish()
	_check(PREVIEW.inventory_fingerprint(original_inventory) == original_contents, "capture actions must preserve nested original slots, equipment and weapon instance contents independently of inventory identity")
	_check(ids.size() == 24, "all 24 production motion states must be captured")
	_check(ExpeditionSession.capture_snapshot() == before and Input.mouse_mode == cursor and not sandbox.active, "motion construction, gameplay posing and cleanup must preserve the original session and cursor")
	for failure in failures: push_error(failure)
	print("FIRST PERSON MOTION PREVIEW %s: 24 production action states, real resources/contact, isolated input and complete original session preservation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


func _test_inventory_fingerprint() -> void:
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	bag.get_equipment_instance("weapon")["smithing"] = {"quality": 0.8, "runes": ["ember"], "drill_progress": 0.25}
	var baseline := PREVIEW.inventory_fingerprint(bag)
	var data: Dictionary = bag.equipment_data.weapon.smithing
	data.runes.append("frost")
	_check(PREVIEW.inventory_fingerprint(bag) != baseline, "nested rune edits must be detected even when the original bag object is unchanged")
	data.runes.pop_back()
	data.drill_progress = 0.5
	_check(PREVIEW.inventory_fingerprint(bag) != baseline, "partial unique-weapon modifications must be included in the preservation fingerprint")
	data.drill_progress = 0.25
	bag.slots[0].quantity = int(bag.slots[0].quantity) + 1
	_check(PREVIEW.inventory_fingerprint(bag) != baseline, "resource changes on the same inventory reference must be detected")
	bag.slots[0].quantity = int(bag.slots[0].quantity) - 1
	var original_utility: String = bag.equipment.utility
	bag.equipment.utility = ""
	_check(PREVIEW.inventory_fingerprint(bag) != baseline, "equipment changes on the same inventory reference must be detected")
	bag.equipment.utility = original_utility
	_check(PREVIEW.inventory_fingerprint(bag) == baseline, "restoring identical inventory contents must restore its fingerprint")
	_check(PREVIEW.inventory_fingerprint(null) == "no_inventory", "capture must preserve a session that has not created an inventory")


func _test_production_sequences() -> void:
	for sequence_id: String in PREVIEW.SEQUENCE_IDS:
		var viewport := PREVIEW.create_viewport()
		root.add_child(viewport)
		var fixture := PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		var player: DungeonPlayer = fixture.player
		_check(PREVIEW.begin_sequence(fixture, sequence_id), "sequence must use an available production action clock: " + sequence_id)
		if not fixture.has("sequence_id"):
			viewport.queue_free()
			await process_frame
			continue
		var states := {}
		var flail_phases := {}
		var max_draw := 0.0
		for frame in range(roundi(PREVIEW.SEQUENCE_FPS * PREVIEW.SEQUENCE_SECONDS)):
			PREVIEW.advance_sequence(fixture, 1.0 / float(PREVIEW.SEQUENCE_FPS))
			states[player.combat_state] = true
			flail_phases[player.flail_state] = true
			max_draw = maxf(max_draw, player.get_bow_draw_ratio())
			_check(PREVIEW.inspect_sequence(fixture).input_disabled, "sequence must never enable external player input")
		match sequence_id:
			"sword_cycle":
				for phase in [player.CombatState.WINDUP, player.CombatState.ACTIVE, player.CombatState.RECOVERY, player.CombatState.READY]:
					_check(states.has(phase), "sword sequence must actually traverse windup, attack, recovery and ready")
			"bow_draw_release":
				_check(max_draw >= 1 and not player.bow_drawing and fixture.inventory.count_item("wooden_arrow") == 11, "bow sequence must reach full draw and release exactly one real arrow")
				_check(player._bow_recoil <= 0, "bow release recoil must decay through the production timer")
			"flail_spin_throw_return":
				for phase in ["spinning", "outbound", "returning"]:
					_check(flail_phases.has(phase), "flail sequence must use actual rotation, outgoing and returning projectile phases")
		player.cancel_flail_action()
		viewport.queue_free()
		await process_frame
