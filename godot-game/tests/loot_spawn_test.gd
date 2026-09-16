extends SceneTree

const CATALOG := preload("res://scripts/loot_spawn_catalog.gd")
const ROOM_PATH := "res://test_room.tscn"
const MAP_PATHS := {"reliquary": "res://main.tscn", "blackwater_cave": "res://cave_dungeon.tscn"}
const VARIANTS := ["wooden_barrel_01", "wooden_crate_01", "wooden_crate_02", "treasure_chest"]

var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	var before := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	_test_sampling()
	for map_id: String in CATALOG.map_ids():
		await _test_map(map_id)
	await _test_trials()
	await _clear_scene()
	if sandbox.active:
		sandbox.finish()
	ExpeditionSession.restore_snapshot(before)
	_check(ExpeditionSession.capture_snapshot() == before, "loot automation must restore the caller's complete expedition snapshot")
	Input.mouse_mode = mouse_before
	if failures.is_empty():
		print("LOOT SPAWN PASS: seeded and random authored occupancy, every candidate's ground/body/approach clearance, real supplied-model opening, visit stability, repeated F2 trials, reset and complete session restoration")
		quit(0)
	else:
		for failure in failures:
			push_error("LOOT SPAWN FAIL: " + failure)
		quit(1)


func _test_sampling() -> void:
	print("LOOT SPAWN CHECK: authored occupancy sampling")
	_check(CATALOG.candidates("unknown").is_empty() and CATALOG.roll("unknown", 1).is_empty(), "unknown maps must not scatter fallback loot")
	for map_id: String in CATALOG.map_ids():
		var sites := CATALOG.candidates(map_id)
		var limits := CATALOG.occupancy_limits(map_id)
		var occupied := {}
		var vacant := {}
		var signatures := {}
		var site_ids := {}
		for site: Dictionary in sites:
			_check(not site_ids.has(site.id), "candidate IDs must be unique in " + map_id)
			site_ids[site.id] = true
			_check(not str(site.context).is_empty() and not str(site.room_id).is_empty(), "each site must explain its authored storage use: " + str(site.id))
			_check(VARIANTS.has(site.model_variant) and float(site.chance) > 0.0 and float(site.chance) < 1.0, "each site needs a supplied model and optional initial occupancy: " + str(site.id))
			for stack: Dictionary in site.items:
				_check(not ExpeditionInventory.get_item_definition(str(stack.id)).is_empty() and int(stack.quantity) > 0, "candidate contents must use real positive catalog stacks: " + str(site.id))
		for seed_value in range(256):
			var selected := CATALOG.roll(map_id, seed_value)
			_check(selected == CATALOG.roll(map_id, seed_value), "the same visit seed must reproduce exact sites and content")
			_check(selected.size() >= limits.x and selected.size() <= limits.y and selected.size() < sites.size(), "every sampled visit must preserve density limits and at least one vacancy")
			var selected_ids := {}
			for site: Dictionary in selected:
				_check(sites.has(site) and not selected_ids.has(site.id), "rolls may only select unique exact authored candidate records")
				selected_ids[site.id] = true
				occupied[site.id] = true
			for site: Dictionary in sites:
				if not selected_ids.has(site.id):
					vacant[site.id] = true
			signatures[str(selected_ids.keys())] = true
		_check(occupied.size() == sites.size() and vacant.size() == sites.size(), "every authored site must sometimes be present and sometimes absent: " + map_id)
		_check(signatures.size() >= 8, "different visits must exhibit multiple materially different site combinations: " + map_id)
		var fresh_signatures := {}
		for _iteration in range(32):
			fresh_signatures[str(CATALOG.roll(map_id))] = true
		_check(fresh_signatures.size() > 1, "ordinary unseeded entry must produce varying occupancy: " + map_id)
		var mutable := CATALOG.candidates(map_id)
		mutable[0].items[0].quantity = 999999
		_check(CATALOG.candidates(map_id) == sites, "candidate consumers must not mutate the authoritative contents")


func _test_map(map_id: String) -> void:
	print("LOOT SPAWN CHECK: actual map and all candidate geometry ", map_id, " at ", Time.get_ticks_msec(), " ms")
	var started_ms := Time.get_ticks_msec()
	ExpeditionSession.begin_new_journey()
	var map := (load(str(MAP_PATHS[map_id])) as PackedScene).instantiate() as Node3D
	map.loot_spawn_seed = 73
	root.add_child(map)
	print("LOOT SPAWN LOAD: ", map_id, " actual scene ready in ", Time.get_ticks_msec() - started_ms, " ms")
	current_scene = map
	_freeze_actors(map)
	await physics_frame
	await physics_frame
	var selection: Array = map.loot_spawn_selection.duplicate(true)
	_check(selection == CATALOG.roll(map_id, 73), "actual map entry must use its own visit RNG: " + map_id)
	_check(map.loot_chests.size() == selection.size(), "actual occupied sites must each instantiate exactly one chest: " + map_id)
	var chest_ids := {}
	for chest: DungeonLootChest in map.loot_chests:
		var id := str(chest.get_meta("loot_site_id", ""))
		chest_ids[id] = chest.get_instance_id()
		var matched: Array = selection.filter(func(site: Dictionary) -> bool: return str(site.id) == id)
		_check(matched.size() == 1, "each runtime container must identify exactly one selected authored site")
		if matched.size() != 1:
			continue
		var site: Dictionary = matched[0]
		_check(chest.position.is_equal_approx(site.position) and is_equal_approx(chest.rotation.y, float(site.yaw)) and chest.visual_variant == site.model_variant, "runtime placement, facing and supplied model must match the authored site: " + id)
		_check(not chest.opened and not chest.container.items.is_empty() and chest.container.identified_stack_count() == 0, "occupied containers must start closed with real concealed contents: " + id)
		map.player.position = site.approach_position
		_check(chest.is_within_hand_reach(map.player), "authored approach must be reachable with real chest interaction: " + id)
		chest.interact(map.player)
		map.player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION + 0.01)
		_check(chest.opened and map.inventory_overlay.is_open() and map.active_loot_chest == chest and paused, "every occupied supplied model must open its actual paused loot UI: " + id)
		map._close_inventory()
		var remaining := chest.container.items.duplicate(true)
		chest.interact(map.player)
		_check(map.inventory_overlay.is_open() and chest.container.items == remaining, "reopening a site must preserve its current contents: " + id)
		map._close_inventory()
	map._spawn_loot_chests()
	_check(map.loot_spawn_selection == selection and map.loot_chests.size() == chest_ids.size(), "setup repeat and all container openings must not reroll or duplicate a live visit")
	for chest: DungeonLootChest in map.loot_chests:
		_check(chest_ids[str(chest.get_meta("loot_site_id"))] == chest.get_instance_id(), "a visit must keep each existing container instance")
	await _check_all_candidate_geometry(map, map_id)
	await _clear_scene()
	var repeated := (load(str(MAP_PATHS[map_id])) as PackedScene).instantiate() as Node3D
	repeated.loot_spawn_seed = 73
	root.add_child(repeated)
	current_scene = repeated
	_freeze_actors(repeated)
	_check(repeated.loot_spawn_selection == selection, "a new scene with an explicit replay seed must reproduce placement")
	for chest: DungeonLootChest in repeated.loot_chests:
		_check(not chest.opened and not chest.container.ever_opened, "a new scene entry must create fresh unopened containers")
	await _clear_scene()


func _check_all_candidate_geometry(map: Node3D, map_id: String) -> void:
	var excluded: Array[RID] = []
	for chest: DungeonLootChest in map.loot_chests:
		excluded.append(chest.get_rid())
	for site: Dictionary in CATALOG.candidates(map_id):
		var started_ms := Time.get_ticks_msec()
		var probe := DungeonLootChest.new().configure("배치 충돌 검증", [])
		probe.configure_visual(str(site.model_variant))
		probe.position = site.position
		probe.rotation.y = float(site.yaw)
		map.add_child(probe)
		print("LOOT SPAWN LOAD: ", site.id, " actual supplied model ready in ", Time.get_ticks_msec() - started_ms, " ms")
		var exclusions := excluded.duplicate()
		exclusions.append(probe.get_rid())
		await physics_frame
		var state := map.get_world_3d().direct_space_state
		var bounds := probe.visual_bounds()
		# Check the full footprint, including corners, above the contact plane.
		for offset: Vector3 in [Vector3.ZERO, Vector3(bounds.position.x * 0.9, 0, bounds.position.z * 0.9), Vector3(bounds.end.x * 0.9, 0, bounds.position.z * 0.9), Vector3(bounds.position.x * 0.9, 0, bounds.end.z * 0.9), Vector3(bounds.end.x * 0.9, 0, bounds.end.z * 0.9)]:
			var at := probe.to_global(offset)
			var ground_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.25, at - Vector3.UP * 0.35, 2, exclusions)
			var ground := state.intersect_ray(ground_query)
			_check(not ground.is_empty() and absf(float(ground.position.y) - at.y) < 0.12, "every candidate footprint must rest on authored ground: " + map_id + "/" + str(site.id))
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(0.05, bounds.size.x - 0.04), maxf(0.05, bounds.size.y - 0.08), maxf(0.05, bounds.size.z - 0.04))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(probe.global_basis, probe.to_global(bounds.get_center() + Vector3.UP * 0.02))
		query.collision_mask = 2
		query.exclude = exclusions
		var hits := state.intersect_shape(query, 8)
		_check(hits.is_empty(), "a candidate's actual model bounds must not overlap scenery: " + map_id + "/" + str(site.id) + " " + _collider_names(hits))
		probe._set_lid_pull(1.0)
		var open_lid_bounds := DungeonLootChest._mesh_bounds(probe.lid_pivot, probe)
		shape.size = Vector3(maxf(0.01, open_lid_bounds.size.x - 0.02), maxf(0.01, open_lid_bounds.size.y - 0.02), maxf(0.01, open_lid_bounds.size.z - 0.02))
		query.transform = Transform3D(probe.global_basis, probe.to_global(open_lid_bounds.get_center()))
		hits = state.intersect_shape(query, 8)
		_check(hits.is_empty(), "a fully open lid must stay clear of surrounding scenery: " + map_id + "/" + str(site.id) + " " + _collider_names(hits))
		probe._set_lid_pull(0.0)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.43
		capsule.height = 1.78
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, site.approach_position)
		hits = state.intersect_shape(query, 8)
		_check(hits.is_empty(), "every candidate needs real standing room in front: " + map_id + "/" + str(site.id) + " " + _collider_names(hits))
		var approach: Vector3 = site.approach_position
		var sight := PhysicsRayQueryParameters3D.create(approach + Vector3.UP * 0.55, probe.to_global(bounds.get_center()), 2, exclusions)
		_check(state.intersect_ray(sight).is_empty(), "the approach must have a clear line to the container: " + map_id + "/" + str(site.id))
		if map_id == "blackwater_cave":
			var water: Node = map.cave_geometry.water_system
			_check(water.call("sample_surface", site.position).is_empty() and water.call("sample_surface", approach).is_empty(), "mine storage and its standing point must remain on a dry bank: " + str(site.id))
		probe.free()
		await physics_frame


func _test_trials() -> void:
	print("LOOT SPAWN CHECK: four model fixtures and repeated test-room map visits")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 11)
	ExpeditionSession.crowns = 821
	ExpeditionSession.hunger = 51.0
	ExpeditionSession.thirst = 38.0
	ExpeditionSession.set_stress(27.0)
	ExpeditionSession.apply_condition("curse", 79.0)
	var snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and paused and room.panel_open and bag != original, "loot trials must start in the paused isolated test session")
	var equipment := bag.equipment.duplicate(true)
	for variant: String in VARIANTS:
		var feature_id := "loot_container:" + variant
		_check(room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == feature_id and entry.action == "loot_container" and entry.payload == variant).size() == 1, "each supplied model requires exactly one executable trial: " + variant)
		room.run_feature(feature_id)
		room.player.set_physics_process(false)
		await physics_frame
		await physics_frame
		_check(not paused and not room.panel_open and room.loot_chests.size() == 1 and room.enemies_alive == 0, "model trial must prepare one actual chest and resume play")
		var chest: DungeonLootChest = room.loot_chests[0]
		var chest_id := chest.get_instance_id()
		_check(chest.visual_variant == variant and is_instance_valid(chest.supplied_visual) and chest.is_within_hand_reach(room.player), "model trial must expose its actual imported mesh at a reachable location")
		var camera: Camera3D = room.player.camera
		var focus := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 4.0, 16)
		focus.collide_with_areas = true
		focus.collide_with_bodies = false
		var hit := room.get_world_3d().direct_space_state.intersect_ray(focus)
		_check(not hit.is_empty() and hit.collider.get_meta("interaction_owner", null) == chest, "model trial's initial camera must aim at its real interaction area: " + variant)
		chest.interact(room.player)
		room.player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.86)
		_check(room.player.is_timed_interacting() and not room.player.chest_hands.active, "model trial must run real timed opening with no chest hands")
		_send_f2(room)
		_check(room.panel_open and paused and not room.player.is_timed_interacting() and not chest.opened and not room.player.chest_hands.active, "F2 during opening must cancel unfinished hands and pause the trial")
		var hunger := ExpeditionSession.hunger
		await create_timer(0.04, true).timeout
		_check(ExpeditionSession.hunger == hunger, "the model trial menu must pause survival")
		room.run_feature(feature_id)
		room.player.set_physics_process(false)
		chest = room.loot_chests[0]
		_check(chest.get_instance_id() != chest_id and not chest.opened and bag.equipment == equipment, "reselection must recreate a closed model while preserving current gear")
		chest.interact(room.player)
		room.player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION + 0.01)
		_check(chest.opened and room.active_loot_chest == chest and room.inventory_overlay.is_open(), "supplied model trial must open its real container")
		chest.container.identify_all()
		var bandages := bag.count_item("linen_bandage")
		room.inventory_overlay._on_container_slot_pressed(0)
		room.inventory_overlay.transfer_button.pressed.emit()
		_check(bag.count_item("linen_bandage") == bandages + 2, "model trial must transfer its actual concealed loot to the trial bag")
		room._close_inventory()
		room._show_test_panel()
	for map_id: String in CATALOG.map_ids():
		for _iteration in range(2):
			print("LOOT SPAWN CHECK: test-room visit ", map_id, " ", _iteration + 1)
			var feature_id := "loot_spawn:" + map_id
			_check(room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == feature_id and entry.action == "scene" and entry.payload == MAP_PATHS[map_id]).size() == 1, "each map must expose the actual production entry in the trial catalog")
			room.run_feature(feature_id)
			if not await _wait_for_scene(str(MAP_PATHS[map_id])):
				return
			var map := current_scene as Node3D
			_freeze_actors(map)
			_check(map.inventory == bag and map.loot_spawn_seed == -1 and preload("res://tests/loot_test_helpers.gd").valid_count(map), "trial map visits must use the production random entry with the existing isolated bag")
			_check(sandbox.saved_session == snapshot and original.slots == original_slots, "all model and map trial actions must preserve the original expedition")
			_send_f2(sandbox)
			if not await _wait_for_scene(ROOM_PATH):
				return
			room = current_scene as Node3D
			_check(room.panel_open and paused and room.inventory == bag, "F2 from either production map must restore the paused test menu and current trial bag")
	room.reset_room()
	_check(room.panel_open and paused and room.inventory != bag and sandbox.saved_session == snapshot, "reset must recreate only the trial bag and fixtures while preserving the saved original")
	room.run_feature("loot_container:treasure_chest")
	_check(room.loot_chests.size() == 1 and not room.loot_chests[0].opened, "the supplied chest must remain runnable after reset")
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "trial exit must restore original inventory identity and every saved field")


func _freeze_actors(map: Node) -> void:
	map.set_process(false)
	map.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_process(false)
		enemy.set_physics_process(false)


func _send_f2(receiver: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.pressed = true
	if receiver == sandbox:
		receiver._input(event)
	else:
		receiver._unhandled_input(event)


func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "loot trial scene transition timed out: " + path)
	return false


func _clear_scene() -> void:
	paused = false
	if is_instance_valid(current_scene):
		if current_scene.has_method("suspend_stress_effects"):
			current_scene.suspend_stress_effects()
		current_scene.queue_free()
		current_scene = null
	await process_frame


func _collider_names(hits: Array) -> String:
	var names: Array[String] = []
	for hit: Dictionary in hits:
		names.append(str(hit.collider.name))
	return str(names)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
