extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_unstarted_journey_round_trip()
	_test_active_journey_round_trip()
	_test_flail_loadout_round_trip()
	_test_camping_supplies_round_trip()
	_finish()


func _test_unstarted_journey_round_trip() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	_check(not ExpeditionSession.journey_started, "capturing the title-screen session must not start a journey")
	_check(snapshot.get("inventory") == null, "capturing an unstarted journey must preserve its null inventory")
	_check(snapshot.size() == 10 and snapshot.has("stress"), "the snapshot must include all ten mutable expedition fields, including stress")
	_check(ExpeditionSession.stress == 0.0, "an unstarted journey must begin without stress")
	_check(not bool(snapshot.get("journey_started", true)), "the snapshot must retain the unstarted flag")
	_check((snapshot.get("merchant_stock", {}) as Dictionary).is_empty(), "capturing an unstarted session must not populate merchant stock")

	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 9999
	ExpeditionSession.hunger = 5.0
	ExpeditionSession.thirst = 7.0
	ExpeditionSession.set_stress(90.0)
	ExpeditionSession.apply_condition("curse")
	ExpeditionSession.learn_spell("stone_shard")
	ExpeditionSession.restore_snapshot(snapshot)

	var restored := ExpeditionSession.capture_snapshot()
	_check(restored == snapshot, "leaving the test room must restore every unstarted-session field exactly")
	_check(not ExpeditionSession.journey_started, "restoring the title screen must not leave an active journey")
	_check(restored.get("inventory") == null, "restoring an unstarted session must discard the sandbox inventory reference")
	_check(ExpeditionSession.active_conditions.is_empty() and ExpeditionSession.learned_spells.is_empty(), "sandbox ailments and learned spells must not leak into an unstarted session")
	_check(ExpeditionSession.selected_spell.is_empty(), "the sandbox spell selection must not leak into an unstarted session")
	_check(ExpeditionSession.stress == 0.0, "trial hallucination stress must not leak into an unstarted journey")


func _test_active_journey_round_trip() -> void:
	ExpeditionSession.begin_new_journey()
	var original_inventory := ExpeditionSession.get_inventory()
	original_inventory.add_item("black_salt", 3)
	original_inventory.add_item("wooden_arrow", 17)
	original_inventory.equipment["weapon"] = "hunting_bow"
	var original_arrows := original_inventory.count_item("wooden_arrow")
	var original_slots := original_inventory.slots.duplicate(true)
	var original_equipment := original_inventory.equipment.duplicate(true)
	ExpeditionSession.crowns = 257
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 3
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["price"] = 11
	ExpeditionSession.hunger = 42.5
	ExpeditionSession.thirst = 17.25
	ExpeditionSession.set_stress(37.5)
	ExpeditionSession.apply_condition("bleeding", 23.0)
	ExpeditionSession.apply_condition("curse", 87.0)
	ExpeditionSession.learn_spell("fire_bolt")
	ExpeditionSession.learn_spell("healing_light")
	ExpeditionSession.select_spell("healing_light")
	var snapshot := ExpeditionSession.capture_snapshot()
	_check(snapshot.get("inventory") == original_inventory, "a snapshot must retain the original inventory instance")

	# These mutations exercise capture-time copies, including nested stock data.
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 0
	ExpeditionSession.active_conditions["bleeding"] = 1.0
	ExpeditionSession.learned_spells["fire_bolt"] = false
	_check(int((snapshot["merchant_stock"] as Dictionary)["linen_bandage"]["quantity"]) == 3, "captured merchant entries must be deeply isolated from live changes")
	_check(float((snapshot["active_conditions"] as Dictionary)["bleeding"]) == 23.0, "captured conditions must be isolated from live changes")
	_check(bool((snapshot["learned_spells"] as Dictionary)["fire_bolt"]), "captured magic progress must be isolated from live changes")

	ExpeditionSession.begin_new_journey()
	var sandbox_inventory := ExpeditionSession.get_inventory()
	_check(ExpeditionSession.stress == 0.0, "a fresh isolated journey must reset stress independently of the saved original value")
	_check(sandbox_inventory != original_inventory, "the test room must receive a separate inventory instance")
	sandbox_inventory.remove_item("wooden_arrow", 1)
	sandbox_inventory.equipment["weapon"] = "rusted_sword"
	_check(original_inventory.count_item("wooden_arrow") == original_arrows and original_inventory.equipment.weapon == "hunting_bow", "sandbox arrow consumption and equipment swaps must not alter the original archer loadout")
	sandbox_inventory.slots.clear()
	sandbox_inventory.equipment.clear()
	ExpeditionSession.crowns = 9999
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 99
	ExpeditionSession.hunger = 1.0
	ExpeditionSession.thirst = 2.0
	ExpeditionSession.set_stress(95.0)
	ExpeditionSession.relieve_stress(18.0)
	ExpeditionSession.apply_condition("fracture", 300.0)
	ExpeditionSession.learn_spell("water_bolt")
	ExpeditionSession.select_spell("water_bolt")
	_check(original_inventory.slots == original_slots and original_inventory.equipment == original_equipment, "sandbox inventory edits must not alter the original bag or equipment")

	ExpeditionSession.restore_snapshot(snapshot)
	_check(ExpeditionSession.get_inventory() == original_inventory, "leaving the test room must restore original inventory identity")
	_check(original_inventory.slots == original_slots and original_inventory.equipment == original_equipment, "the restored inventory contents and equipment must remain unchanged")
	_check(original_inventory.count_item("wooden_arrow") == original_arrows and original_inventory.equipment.weapon == "hunting_bow", "leaving the test room must restore arrow stack quantities and the equipped bow")
	_check(ExpeditionSession.crowns == 257, "leaving the test room must restore the original wallet")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == 3 and ExpeditionSession.get_buy_price("linen_bandage") == 11, "leaving the test room must restore nested stock quantities and prices")
	_check(is_equal_approx(ExpeditionSession.hunger, 42.5) and is_equal_approx(ExpeditionSession.thirst, 17.25), "leaving the test room must restore hunger and thirst")
	_check(is_equal_approx(ExpeditionSession.stress, 37.5), "leaving the test room must restore exact original stress after trial accumulation and recovery")
	_check(ExpeditionSession.active_conditions == {"bleeding": 23.0, "curse": 87.0}, "leaving the test room must restore ailments and their exact remaining durations")
	_check(ExpeditionSession.learned_spells == {"fire_bolt": true, "healing_light": true}, "leaving the test room must restore only the originally learned spells")
	_check(ExpeditionSession.selected_spell == "healing_light", "leaving the test room must restore the original spell selection")
	_check(ExpeditionSession.journey_started, "leaving the test room must keep an existing journey active")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "an active-session round trip must restore all snapshot fields")

	# A restored session must not share mutable dictionaries with its backup.
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 1
	ExpeditionSession.active_conditions.clear()
	ExpeditionSession.learned_spells.clear()
	ExpeditionSession.set_stress(100.0)
	_check(int((snapshot["merchant_stock"] as Dictionary)["linen_bandage"]["quantity"]) == 3, "restored nested merchant data must not alias the saved snapshot")
	_check((snapshot["active_conditions"] as Dictionary).size() == 2, "restored conditions must not alias the saved snapshot")
	_check((snapshot["learned_spells"] as Dictionary).size() == 2, "restored spell progress must not alias the saved snapshot")
	_check(is_equal_approx(float(snapshot.stress), 37.5), "restored stress changes must leave the reusable saved value untouched")
	ExpeditionSession.restore_snapshot(snapshot)
	_check(ExpeditionSession.capture_snapshot() == snapshot, "the same snapshot must remain reusable after restored-session changes")


func _test_flail_loadout_round_trip() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	_check(original.count_item("chain_flail") == 1, "a new journey must include one starter chain flail")
	original.equipment["weapon"] = "chain_flail"
	var original_slots := original.slots.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	var trial := ExpeditionSession.get_inventory()
	trial.remove_item("chain_flail", 1)
	trial.equipment["weapon"] = "rusted_sword"
	_check(trial != original and original.slots == original_slots and original.equipment.weapon == "chain_flail", "trial flail loadout changes must not touch the original inventory object or equipment")
	ExpeditionSession.restore_snapshot(snapshot)
	_check(ExpeditionSession.get_inventory() == original and original.count_item("chain_flail") == 1 and original.equipment.weapon == "chain_flail", "leaving a flail trial must restore the same inventory object and equipped flail")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "flail trials must not add or leak persistent projectile or action state")


func _test_camping_supplies_round_trip() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	_check(original.count_item("camp_kit") == 1, "new journey must include a starter camping kit")
	original.add_item("camp_kit", 1)
	original.add_item("pilgrim_ration", 1)
	ExpeditionSession.hunger = 36.0
	ExpeditionSession.thirst = 41.0
	ExpeditionSession.set_stress(84.0)
	ExpeditionSession.apply_condition("bleeding", 83.0)
	var snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	ExpeditionSession.begin_new_journey()
	var trial := ExpeditionSession.get_inventory()
	ExpeditionSession.set_stress(90.0)
	trial.remove_item("camp_kit", 1)
	trial.remove_item("pilgrim_ration", 1)
	trial.remove_item("boiled_rainwater", 1)
	trial.remove_item("linen_bandage", 1)
	ExpeditionSession.advance_survival(180.0)
	ExpeditionSession.restore_needs(32.0, 38.0)
	ExpeditionSession.clear_condition("bleeding")
	ExpeditionSession.relieve_stress(30.0)
	_check(original.slots == original_slots and original.count_item("camp_kit") == 2, "trial camping costs must not mutate the saved original supply stacks")
	ExpeditionSession.restore_snapshot(snapshot)
	_check(ExpeditionSession.get_inventory() == original and original.slots == original_slots, "camping trials must restore the original inventory identity and all supply quantities")
	_check(ExpeditionSession.hunger == 36.0 and ExpeditionSession.thirst == 41.0 and ExpeditionSession.active_conditions == {"bleeding": 83.0}, "camping recovery and elapsed time must not leak into original needs or ailments")
	_check(ExpeditionSession.stress == 84.0, "trial camping relief must not change the original stress")
	_check(ExpeditionSession.capture_snapshot() == snapshot and snapshot.size() == 10, "scene-local camping must preserve the ten expedition fields without persisting temporary effects")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("TEST ROOM SESSION TEST PASS: inventory identity, stress accumulation/recovery isolation, camping supplies, bow and arrows, chain flail, wallet, deep stock copies, needs, ailments, magic, and unstarted-session restoration")
		quit(0)
		return
	for failure in failures:
		push_error("TEST ROOM SESSION TEST FAIL: %s" % failure)
	quit(1)
