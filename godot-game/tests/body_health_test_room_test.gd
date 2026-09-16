extends SceneTree

const EXPECTED_MAXIMA := {"head": 35.0, "thorax": 85.0, "stomach": 70.0, "left_arm": 60.0, "right_arm": 60.0, "left_leg": 65.0, "right_leg": 65.0}
var failures: Array[String] = []
var room: Node3D
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("black_salt", 3)
	ExpeditionSession.body_health.parts.left_leg = 12.0
	ExpeditionSession.body_health.selected_part = "stomach"
	ExpeditionSession.apply_condition("curse", 93.0, "right_arm")
	ExpeditionSession.crowns = 381
	ExpeditionSession.hunger = 43.0
	var original_slots := original.slots.duplicate(true)
	var original_snapshot := ExpeditionSession.capture_snapshot()
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original and room.panel_open and paused, "body-health trials must begin in an isolated paused expedition")
	_check(float(room.player.MAX_HEALTH) == 440.0, "seven required body-part maxima must total 440")
	for id in ["body_health", "body_surgery", "body_restoration"]:
		var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == id)
		_check(entries.size() == 1 and entries[0].category == "생존" and entries[0].action == "body_health", "body-health trial must have one executable survival entry: " + id)
	for condition in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "condition:" + condition)
		_check(entries.size() == 1, "conditions must remain generated once from their authoritative catalog: " + condition)
	_check_bandage_trial()
	_check_splint_trial()
	_check_storage_equipment_trial()
	_check_dungeon_hud_trial()
	_check_timed_use_trial()
	room.run_feature("body_health")
	_check(room.inventory_overlay.is_open() and paused and room.inventory_overlay.health_panel.is_visible_in_tree(), "body fixture must open the actual inventory health tab")
	_check(room.inventory_overlay.combined_loadout_panel.is_visible_in_tree() and room.inventory_overlay.combined_loadout_panel.inventory_buttons.size() == 30 and room.inventory_overlay.combined_loadout_panel.equipment_buttons.size() == ExpeditionInventory.EQUIPMENT_ORDER.size(), "The executable body trial must expose real equipment and all storage alongside treatment.")
	var body: Dictionary = room.player.get_body_health_snapshot()
	_check(body.parts.size() == 7 and is_equal_approx(float(body.health), 405.0), "body fixture must apply real five-point damage independently to all seven parts")
	for part in EXPECTED_MAXIMA:
		_check(body.parts[part].max_health == EXPECTED_MAXIMA[part] and body.parts[part].health == EXPECTED_MAXIMA[part] - 5.0, "body fixture must retain the exact requested maximum and actual damage for " + part)
	room.inventory_overlay.health_panel.part_buttons.right_arm.pressed.emit()
	_check(room.player.get_body_health_snapshot().selected_part == "right_arm", "real health-panel part button must select the production treatment target")
	_f2_menu()
	room._select_category("생존")
	var controls: Control = room.status_controls
	_check(controls.sliders.health.max_value == 440.0 and controls.spin_boxes.health.max_value == 440.0 and controls.body_part_selector.item_count == 7, "status controls must show total maximum 440 and seven real selectable parts")
	_select_control_part(controls, "right_arm")
	controls.body_damage_button.pressed.emit()
	_check(_part_health("right_arm") == 45.0, "the real selected-part damage button must remove ten health from only that part")
	controls.body_blackout_button.pressed.emit()
	_check(_part_health("right_arm") == 0.0 and room.player.combat_state != DungeonPlayer.CombatState.DEAD, "non-vital blackout button must deplete the selected arm without killing the actor")
	var before_pause := ExpeditionSession.body_health.duplicate(true)
	await create_timer(0.04, true).timeout
	_check(paused and ExpeditionSession.body_health == before_pause, "body values must stay fixed while the F2 menu is paused")
	controls.body_reset_button.pressed.emit()
	_check(room.player.health == 440.0 and _part_health("right_arm") == 60.0 and controls.hint_label.text.contains("시험 초기화"), "explicit debug recovery must restore blacked parts and explain that it bypasses normal treatment")
	room.run_feature("body_surgery")
	_check(_part_health("left_arm") == 0.0 and room.player.get_body_health_snapshot().selected_part == "left_arm", "surgery fixture must prepare a selected real zero-health arm")
	var medicine_count: int = room.inventory.count_item("healing_draught")
	_use_inventory_treatment("healing_draught")
	_check(_part_health("left_arm") == 0.0 and room.inventory.count_item("healing_draught") == medicine_count, "normal medicine must neither revive nor be consumed for the selected zero-health limb")
	var surgery_count: int = room.inventory.count_item("surgery_kit")
	_use_inventory_treatment("surgery_kit")
	_check(_part_health("left_arm") == 1.0 and room.inventory.count_item("surgery_kit") == surgery_count - 1, "actual surgery item action must consume one kit and restore exactly one limb health")
	_use_inventory_treatment("healing_draught")
	_check(_part_health("left_arm") > 1.0 and room.inventory.count_item("healing_draught") == medicine_count - 1, "ordinary health-panel treatment must work after surgical restoration")
	_f2_menu()
	room.run_feature("body_surgery")
	_check(_part_health("left_arm") == 0.0 and room.inventory.count_item("surgery_kit") == 2, "reselecting surgery must restore its exact initial injury and consumable stock")
	_f2_menu()
	room.run_feature("body_restoration")
	_check(_part_health("right_leg") == 0.0 and room.inventory.equipment.weapon == "weathered_staff" and ExpeditionSession.get_selected_spell() == "restorative_light", "restoration trial must ready a real staff, high-tier spell and selected zero-health leg")
	_close_bag()
	var stamina_before: float = room.player.stamina
	var ordinary: Dictionary = room.player.cast_spell("healing_light")
	_check(not bool(ordinary.get("accepted", true)) and _part_health("right_leg") == 0.0 and room.player.stamina == stamina_before, "ordinary healing magic must fail without stamina cost on a selected blacked part")
	var restored: Dictionary = room.player.cast_spell("restorative_light")
	_check(bool(restored.get("accepted", false)) and _part_health("right_leg") == 1.0 and room.player.stamina < stamina_before, "actual advanced spell must spend its real casting cost and restore exactly one health")
	room._open_inventory()
	room.inventory_overlay.open_health_tab()
	_use_inventory_treatment("healing_draught")
	_check(_part_health("right_leg") > 1.0, "normal medicine must heal a part restored by advanced magic")
	await _check_condition_trials()
	await _check_vital_death_and_scene_return()
	_check(original.slots == original_slots and sandbox.saved_session == original_snapshot, "all body, condition and recovery trials must leave the saved original expedition untouched")
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == original_snapshot and original.slots == original_slots, "leaving must restore original bag identity, exact nested body/condition state and all expedition values")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("BODY HEALTH TEST ROOM PASS: real seven-part damage, health-tab treatment selection, normal healing rejection, surgery and advanced magic restoration, condition effects/treatments, debug controls, vital death, repeated stock, scene persistence, F2/reset and complete original-session restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_storage_equipment_trial() -> void:
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "storage_equipment")
	_check(entries.size() == 1 and entries[0].action == "storage_equipment", "Storage equipment must have one executable trial.")
	for item_id in ["leather_waist_pouch", "pilgrim_waist_pouch", "expedition_backpack", "wanderer_backpack"]:
		var items: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:" + item_id)
		_check(items.size() == 1, "Each storage item must be auto-registered once: " + item_id)
	room.run_feature("storage_equipment")
	_check(paused and room.inventory_overlay.is_open() and room.inventory != sandbox.saved_session.inventory, "Storage trial must open the production overlay inside its paused sandbox.")
	var bag: ExpeditionInventory = room.inventory
	var supplies := bag.count_item("linen_bandage")
	for slot: String in ["waist_pouch", "backpack"]:
		var item_id := "pilgrim_waist_pouch" if slot == "waist_pouch" else "wanderer_backpack"
		var previous := str(bag.equipment[slot])
		var index := -1
		for n in bag.slots.size():
			if str(bag.slots[n].id) == item_id:
				index = n
		_check(index >= 0 and room.inventory_overlay.open_item_details("inventory", index), "Trial must supply an inspectable replacement: " + item_id)
		room.inventory_overlay.item_detail_window.equip_button.pressed.emit()
		_check(str(bag.equipment[slot]) == item_id and bag.count_item(previous) == 1 and bag.count_item("linen_bandage") == supplies, "Trial equipment action must swap real storage and retain contents.")
		room.inventory_overlay._dismiss_item_details()
	_f2_menu()
	room.run_feature("storage_equipment")
	_check(room.inventory == bag and str(bag.equipment.waist_pouch) == "leather_waist_pouch" and str(bag.equipment.backpack) == "expedition_backpack" and bag.count_item("pilgrim_waist_pouch") == 1 and bag.count_item("wanderer_backpack") == 1, "F2 repeat must restore the two original containers and exactly one replacement of each, retaining sandbox bag identity.")
	_f2_menu()


func _check_condition_trials() -> void:
	for condition_id in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		_f2_menu()
		room._recover_player()
		ExpeditionSession.clear_conditions()
		room.player.select_treatment_part("left_leg" if condition_id == "fracture" else "left_arm")
		room.run_feature("condition:" + condition_id)
		var body: Dictionary = room.player.get_body_health_snapshot()
		var selected := str(body.selected_part)
		_check(ExpeditionSession.has_condition(condition_id) and body.conditions.has(condition_id), "condition fixture must apply the real condition to the expedition and health snapshot: " + condition_id)
		if condition_id in ["bleeding", "fracture"]:
			_check(body.parts[selected].conditions.has(condition_id), "local injuries must be attached to the actually selected body part: " + condition_id)
		var treatment := _condition_treatment(condition_id)
		_check(not treatment.is_empty() and room.inventory.count_item(treatment) == 2, "condition fixture must derive and restock a real matching treatment from the item catalog: " + condition_id)
		if condition_id == "fracture":
			_check(room.player.get_body_movement_multiplier() < 1.0, "real fractured leg must impair production movement")
		elif condition_id == "paralysis":
			_check(room.player.is_paralyzed(), "real paralysis must activate the production action/movement lock")
		elif condition_id == "curse":
			_check(ExpeditionSession.get_survival_drain_multiplier() > 1.0, "real curse must increase the actual survival drain")
			room.player.apply_body_damage("left_arm", 20.0)
			_check(room.player.restore_health(10.0, "left_arm") == 5.0 and _part_health("left_arm") == 45.0, "real curse must halve ordinary healing on the damaged body")
		var before := ExpeditionSession.capture_snapshot()
		ExpeditionSession.advance_survival(2.0, {"safe_zone": false, "paused": true})
		_check(ExpeditionSession.capture_snapshot() == before, "paused survival must not tick condition timers or body damage: " + condition_id)
		if condition_id in ["bleeding", "poison"]:
			room._hide_test_panel()
			var health_before: float = room.player.health
			ExpeditionSession.advance_survival(2.0, {"safe_zone": false})
			room.player.sync_body_health_from_session()
			_check(room.player.health < health_before, "actual survival tick must apply condition damage to the body: " + condition_id)
			room._show_test_panel()
		room._hide_test_panel()
		room._open_inventory()
		room.inventory_overlay.open_health_tab()
		if not treatment.is_empty():
			_use_inventory_treatment(treatment)
			_check(not ExpeditionSession.has_condition(condition_id) and room.inventory.count_item(treatment) == 1, "real health-tab treatment must clear its condition and spend exactly one matching item: " + condition_id)
		if condition_id == "fracture":
			_check(room.player.get_body_movement_multiplier() == 1.0, "splint treatment must remove the actual fracture movement penalty")
		elif condition_id == "paralysis":
			_check(not room.player.is_paralyzed(), "nerve treatment must remove the actual paralysis lock")
		elif condition_id == "curse":
			_check(room.player.restore_health(10.0, "left_arm") == 10.0, "purifying treatment must remove the real healing penalty")


func _check_vital_death_and_scene_return() -> void:
	_f2_menu()
	room._recover_player()
	ExpeditionSession.clear_conditions()
	room._select_category("생존")
	_select_control_part(room.status_controls, "head")
	room.status_controls.body_blackout_button.pressed.emit()
	_check(_part_health("head") == 0.0 and room.player.combat_state == DungeonPlayer.CombatState.DEAD and not room.panel_open and paused, "depleting a vital part through the trial must enter the real death result and reveal its overlay")
	_f2_menu()
	_check(room.player.health == 440.0 and room.player.combat_state == DungeonPlayer.CombatState.READY, "F2 after vital death must use the actual test-room recovery")
	room.player.apply_body_damage("left_leg", 65.0)
	room.player.apply_condition("fracture", 145.0, "right_leg")
	room.player.select_treatment_part("left_leg")
	var trial_body := ExpeditionSession.body_health.duplicate(true)
	var trial_bag: ExpeditionInventory = room.inventory
	room.run_feature("hideout")
	if not await _wait_for_scene("res://hideout.tscn"):
		return
	var hideout := current_scene
	hideout.player.set_physics_process(false)
	_check(ExpeditionSession.body_health == trial_body and hideout.inventory == trial_bag and hideout.player.get_body_health_snapshot().parts.left_leg.health == 0.0, "connected hideout scene must retain the real sandbox limb injury, selected treatment part and bag")
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	if not await _wait_for_scene("res://test_room.tscn"):
		return
	room = current_scene as Node3D
	room.set_process(false)
	room.player.set_physics_process(false)
	_check(room.panel_open and paused and room.inventory == trial_bag and ExpeditionSession.body_health == trial_body, "F2 return must preserve sandbox body state without replacing or healing it")
	room.reset_room()
	_check(room.inventory != trial_bag and room.player.health == 440.0 and ExpeditionSession.active_conditions.is_empty(), "reset must replace only the sandbox loadout and clear its body injuries/conditions")
	for part in EXPECTED_MAXIMA:
		_check(_part_health(part) == EXPECTED_MAXIMA[part], "reset must refill each body part independently: " + part)


func _condition_treatment(condition_id: String) -> String:
	for id in ExpeditionInventory.ITEM_DEFINITIONS:
		var definition := ExpeditionInventory.get_item_definition(id)
		if str(definition.get("condition", "")) == condition_id and definition.get("effect", "") in ["bandage", "cure_condition"]:
			return str(id)
	return ""


func _part_health(id: String) -> float:
	return float(room.player.get_body_health_snapshot().parts[id].health)


func _select_control_part(controls: Control, id: String) -> void:
	for index in range(controls.body_part_selector.item_count):
		if str(controls.body_part_selector.get_item_metadata(index)) == id:
			controls.body_part_selector.select(index)
			controls.body_part_selector.item_selected.emit(index)
			return
	_check(false, "missing actual body-part control option: " + id)


func _close_bag() -> void:
	for attempt in range(5):
		if not room.inventory_overlay.is_open():
			return
		room._close_inventory()
	_check(not room.inventory_overlay.is_open(), "health and nested inventory UI must close back to active play")


func _f2_menu() -> void:
	for attempt in range(5):
		if room.panel_open:
			return
		var f2 := InputEventKey.new()
		f2.keycode = KEY_F2
		f2.pressed = true
		room._unhandled_input(f2)
	_check(room.panel_open and paused, "F2 must return from the real treatment UI to the paused trial menu")


func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "body-health scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check_bandage_trial() -> void:
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "bandage_forearm")
	_check(entries.size() == 1 and entries[0].action == "bandage_forearm", "bandage motion must expose one executable room entry")
	for repeat in 2:
		room.run_feature("bandage_forearm")
		_check(room.player.is_bandage_motion_active() and not paused, "room trial must start real treatment animation")
		_check(_part_health("left_arm") == 54.0 and room.inventory.count_item("linen_bandage") == 2, "trial must apply 24 damage, spend one actual bandage, and heal 18")
		_check(not ExpeditionSession.has_condition("bleeding"), "trial must cure the actual selected-arm bleeding")
		room.player._update_viewmodel(1.0)
		_f2_menu()
		_check(not room.player.is_bandage_motion_active(), "F2 must clear temporary treatment hands")
	room.run_feature("bandage_forearm")
	room._recover_player()
	_check(not room.player.is_bandage_motion_active() and _part_health("left_arm") == 60.0, "recovery must clear presentation and restore the damaged trial arm")
	_f2_menu()


func _check_dungeon_hud_trial() -> void:
	var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "dungeon_combat_hud")
	_check(matches.size() == 1 and matches[0].action == "dungeon_combat_hud", "Unique executable combat HUD trial")
	_f2_menu()
	room.run_feature("dungeon_combat_hud")
	var panel: Control = room.hud.combat_panel
	_check(room.hud.combat_enabled and not paused and panel.bag == room.inventory and panel.player == room.player, "Trial uses real combat HUD, player and sandbox inventory")
	_check("hunger" in panel.warnings and "curse" in panel.warnings and panel.body_snapshot.parts.left_arm.health == 20, "Trial prepares real low needs, curse and damaged arm")
	var count: int = room.inventory.count_item("pilgrim_ration")
	_check(panel.activate_slot(5).accepted, "Trial food starts timed use")
	room.player.advance_item_use(20)
	panel.refresh()
	_check(room.inventory.count_item("pilgrim_ration") == count - 1 and "hunger" not in panel.warnings, "Trial hotbar uses real food and removes warning")
	_f2_menu()
	room.run_feature("dungeon_combat_hud")
	_check(room.inventory.count_item("pilgrim_ration") == 3 and ExpeditionSession.hunger == 15, "F2 repeat resets exact stock and needs")
	_f2_menu()


func _check_splint_trial() -> void:
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "splint_forearm")
	_check(entries.size() == 1 and entries[0].action == "splint_forearm", "splint must have one executable trial")
	room.run_feature("splint_forearm")
	_check(room.player.splint_hands.active and room.inventory.count_item("splint") == 3, "trial starts real timed splint without early consumption")
	_check(ExpeditionSession.condition_affects_part("fracture", "left_arm"), "trial fracture stays until completion")
	_f2_menu()
	_check(not room.player.splint_hands.active and not room.player.is_item_use_active(), "F2 must cancel splint and timer")
	room.run_feature("splint_forearm")
	_check(room.player.splint_hands.active and room.inventory.count_item("splint") == 3, "repeat must restock and replay")
	room.player.advance_item_use(7.2)
	_check(room.inventory.count_item("splint") == 2 and not ExpeditionSession.condition_affects_part("fracture", "left_arm"), "completion spends one and cures fracture")
	_f2_menu()


func _use_inventory_treatment(id: String) -> void:
	room.inventory_overlay.health_panel.treatment_buttons[id].pressed.emit()
	if room.player.is_item_use_active():
		_check(not room.inventory_overlay.is_open() and not paused, "Starting an item closes inventory and resumes real timed use")
		room.player.advance_item_use(30)
		room._open_inventory()
		room.inventory_overlay.open_health_tab()


func _check_timed_use_trial() -> void:
	var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "timed_item_use")
	_check(matches.size() == 1 and matches[0].action == "timed_item_use", "Unique timed-use catalog entry")
	_f2_menu()
	room.run_feature("timed_item_use")
	var count: int = room.inventory.count_item("healing_draught")
	var hp: float = room.player.get_body_health_snapshot().parts.left_arm.health
	room.hud.combat_panel.activate_slot(3)
	room.player.advance_item_use(1)
	_check(room.hud.item_use_progress.visible and room.inventory.count_item("healing_draught") == count, "Trial displays countdown without early consumption")
	var torch: bool = room.player.torch_enabled
	room.player.handle_torch_action()
	_check(not room.player.is_item_use_active() and room.player.torch_enabled == torch and room.player.get_body_health_snapshot().parts.left_arm.health == hp, "Trial F cancels without torch toggle or healing")
	room._open_inventory()
	room._on_consumable_requested("healing_draught")
	_check(not room.inventory_overlay.is_open() and room.player.is_item_use_active() and not paused, "Production inventory starts timed use and returns to gameplay")
	_f2_menu()
	_check(not room.player.is_item_use_active() and room.inventory.count_item("healing_draught") == count, "F2 cancels uncommitted item")
	room.run_feature("timed_item_use")
	_check(room.inventory.count_item("healing_draught") == 3 and room.player.get_body_health_snapshot().parts.left_arm.health == hp, "Trial reset restores exact stock and injury")
	_f2_menu()
