extends RefCounted
class_name ExpeditionSession

const INVENTORY_SCRIPT := preload("res://scripts/inventory_model.gd")
const SPELL_CATALOG_SCRIPT := preload("res://scripts/spell_catalog.gd")
const STRESS_PROFILE := preload("res://scripts/stress_profile.gd")
const BODY_HEALTH := preload("res://scripts/body_health.gd")
const STARTING_CROWNS := 120
const MAX_NEED := 100.0
const HUNGER_FULL_DURATION_SECONDS := 5400.0
const THIRST_FULL_DURATION_SECONDS := 3600.0
const MAX_DRAIN_MULTIPLIER := 2.25
const CONDITION_DRAIN_BONUSES := {
	"bleeding": 0.60,
	"fracture": 0.35,
	"curse": 0.50,
	"paralysis": 0.20,
	"poison": 0.45,
}
const CONDITION_DEFAULT_DURATIONS := {
	"bleeding": 180.0,
	"fracture": 300.0,
	"curse": 240.0,
	"paralysis": 8.0,
	"poison": 90.0,
}
const CONDITION_DISPLAY_NAMES := {
	"bleeding": "출혈",
	"fracture": "골절",
	"curse": "저주",
	"paralysis": "마비",
	"poison": "중독",
}
const DEFAULT_MERCHANT_STOCK := {
	"surgery_kit": {"quantity": 3, "price": 65},
	"splint": {"quantity": 6, "price": 18},
	"antidote": {"quantity": 4, "price": 22},
	"purifying_salt": {"quantity": 4, "price": 28},
	"nerve_tonic": {"quantity": 4, "price": 24},
	"restoration_spellbook": {"quantity": 1, "price": 120},
	"alchemy_water": {"quantity": 24, "price": 2},
	"alchemy_wine": {"quantity": 24, "price": 5, "unlimited": true},
	"alchemy_spirits": {"quantity": 24, "price": 7, "unlimited": true},
	"alchemy_oil": {"quantity": 24, "price": 6},
	"alchemy_empty_bottle": {"quantity": 24, "price": 2, "unlimited": true},
	"alchemy_redroot": {"quantity": 36, "price": 3, "unlimited": true},
	"alchemy_dawnleaf": {"quantity": 36, "price": 2, "unlimited": true},
	"alchemy_moonwort": {"quantity": 36, "price": 4, "unlimited": true},
	"alchemy_bittermint": {"quantity": 36, "price": 2, "unlimited": true},
	"alchemy_ironbloom": {"quantity": 36, "price": 4},
	"iron_ingot": {"quantity": 24, "price": 6},
	"forge_charcoal": {"quantity": 16, "price": 3},
	"grip_leather": {"quantity": 10, "price": 5},
	"steel_fitting": {"quantity": 12, "price": 9},
	"silver_inlay": {"quantity": 8, "price": 12},
	"ember_rune": {"quantity": 4, "price": 24},
	"rune_fragment": {"quantity": 4, "price": 27},
	"linen_bandage": {"quantity": 8, "price": 7},
	"healing_draught": {"quantity": 4, "price": 18},
	"pilgrim_ration": {"quantity": 8, "price": 8},
	"boiled_rainwater": {"quantity": 10, "price": 9},
	"holy_oil_flask": {"quantity": 3, "price": 25},
	"lamp_oil": {"quantity": 6, "price": 9},
	"camp_kit": {"quantity": 4, "price": 18},
	"raw_meat": {"quantity": 6, "price": 10},
	"edible_mushroom": {"quantity": 8, "price": 5},
	"grave_key": {"quantity": 2, "price": 20},
	"round_shield": {"quantity": 1, "price": 35},
	"hunting_bow": {"quantity": 1, "price": 38},
	"chain_flail": {"quantity": 1, "price": 64},
	"wooden_arrow": {"quantity": 60, "price": 2},
	"weathered_staff": {"quantity": 1, "price": 42},
	"fire_spellbook": {"quantity": 1, "price": 34},
	"water_spellbook": {"quantity": 1, "price": 26},
	"ice_spellbook": {"quantity": 1, "price": 38},
	"stone_spellbook": {"quantity": 1, "price": 32},
	"healing_spellbook": {"quantity": 1, "price": 48},
}

static var _inventory: ExpeditionInventory
static var crowns := STARTING_CROWNS
static var merchant_stock: Dictionary = {}
static var journey_started := false
static var hunger := MAX_NEED
static var thirst := MAX_NEED
static var stress := 0.0
static var active_conditions: Dictionary = {}
static var learned_spells: Dictionary = {}
static var selected_spell := ""
static var body_health: Dictionary = {}


static func capture_snapshot() -> Dictionary:
	# Keep the original bag (and its signal connections) alive while a separate
	# journey is used by the test room. Capturing must not start a new journey.
	return {
		"inventory": _inventory,
		"crowns": crowns,
		"merchant_stock": merchant_stock.duplicate(true),
		"journey_started": journey_started,
		"hunger": hunger,
		"thirst": thirst,
		"stress": stress,
		"active_conditions": active_conditions.duplicate(true),
		"learned_spells": learned_spells.duplicate(true),
		"selected_spell": selected_spell,
		"body_health": body_health.duplicate(true),
	}


static func restore_snapshot(snapshot: Dictionary) -> void:
	# This is an in-memory round trip for capture_snapshot(), not a save-file
	# loader. Copy dictionaries again so a restored session cannot edit its backup.
	_inventory = snapshot["inventory"] as ExpeditionInventory
	crowns = int(snapshot["crowns"])
	merchant_stock = (snapshot["merchant_stock"] as Dictionary).duplicate(true)
	journey_started = bool(snapshot["journey_started"])
	hunger = float(snapshot["hunger"])
	thirst = float(snapshot["thirst"])
	stress = float(snapshot["stress"])
	active_conditions = (snapshot["active_conditions"] as Dictionary).duplicate(true)
	learned_spells = (snapshot["learned_spells"] as Dictionary).duplicate(true)
	selected_spell = str(snapshot["selected_spell"])
	body_health = (snapshot.get("body_health", {}) as Dictionary).duplicate(true)


static func begin_new_journey(reset_magic_progress := true) -> void:
	_inventory = INVENTORY_SCRIPT.new() as ExpeditionInventory
	_inventory.seed_default_loadout()
	crowns = STARTING_CROWNS
	merchant_stock = DEFAULT_MERCHANT_STOCK.duplicate(true)
	hunger = MAX_NEED
	thirst = MAX_NEED
	stress = 0.0
	active_conditions.clear()
	body_health = BODY_HEALTH.create_state()
	if reset_magic_progress:
		learned_spells.clear()
		selected_spell = ""
	journey_started = true


static func ensure_journey() -> void:
	if not journey_started or _inventory == null:
		begin_new_journey()
	elif body_health.is_empty():
		body_health = BODY_HEALTH.create_state()


static func get_inventory() -> ExpeditionInventory:
	ensure_journey()
	return _inventory


static func advance_survival(delta: float, stress_context: Dictionary = {}) -> Dictionary:
	ensure_journey()
	if not is_finite(delta) or bool(stress_context.get("paused", false)):
		return get_survival_snapshot()
	var conditions_paused := bool(stress_context.get("safe_zone", false))
	var remaining_seconds := maxf(0.0, delta)
	while remaining_seconds > 0.00001:
		_remove_expired_conditions()
		var segment := remaining_seconds
		if not conditions_paused:
			for duration_value in active_conditions.values():
				segment = minf(segment, maxf(0.0, float(duration_value)))
			var bleed_locations: Array = body_health.condition_parts.get("bleeding", ["thorax"])
			if not BODY_HEALTH.is_dead(body_health) and active_conditions.has("bleeding") and not bleed_locations.is_empty() and str(bleed_locations[0]) in BODY_HEALTH.VITAL_PARTS:
				segment = minf(segment, float(body_health.parts[str(bleed_locations[0])]) / 0.5)
		if segment <= 0.00001:
			_remove_expired_conditions()
			if active_conditions.is_empty():
				segment = remaining_seconds
			else:
				break
		var multiplier := get_survival_drain_multiplier()
		# Split at low-supply thresholds as well as condition expiry. A large
		# elapsed-time step must accumulate the same stress as small frame steps.
		if not stress_context.is_empty():
			if hunger > STRESS_PROFILE.NEED_THRESHOLD + 0.00001:
				segment = minf(segment, (hunger - STRESS_PROFILE.NEED_THRESHOLD) / (MAX_NEED / HUNGER_FULL_DURATION_SECONDS * multiplier))
			if thirst > STRESS_PROFILE.NEED_THRESHOLD + 0.00001:
				segment = minf(segment, (thirst - STRESS_PROFILE.NEED_THRESHOLD) / (MAX_NEED / THIRST_FULL_DURATION_SECONDS * multiplier))
			add_stress(STRESS_PROFILE.gain_per_second(stress_context, hunger, thirst, active_conditions.size()) * segment)
		hunger = maxf(0.0, hunger - MAX_NEED / HUNGER_FULL_DURATION_SECONDS * multiplier * segment)
		thirst = maxf(0.0, thirst - MAX_NEED / THIRST_FULL_DURATION_SECONDS * multiplier * segment)
		if absf(hunger - STRESS_PROFILE.NEED_THRESHOLD) < 0.00001:
			hunger = STRESS_PROFILE.NEED_THRESHOLD
		if absf(thirst - STRESS_PROFILE.NEED_THRESHOLD) < 0.00001:
			thirst = STRESS_PROFILE.NEED_THRESHOLD
		for condition_id in active_conditions.keys():
			if conditions_paused:
				continue
			var damage_rate := 0.5 if str(condition_id) == "bleeding" else (1.0 if str(condition_id) == "poison" else 0.0)
			if damage_rate > 0.0 and not BODY_HEALTH.is_dead(body_health):
				var target := "stomach" if str(condition_id) == "poison" else "thorax"
				var locations: Array = body_health.condition_parts.get(condition_id, [])
				if not locations.is_empty():
					target = str(locations[0])
				BODY_HEALTH.damage(body_health, target, damage_rate * segment)
			active_conditions[condition_id] = maxf(0.0, float(active_conditions[condition_id]) - segment)
		remaining_seconds -= segment
	_remove_expired_conditions()
	return get_survival_snapshot()


static func get_survival_drain_multiplier() -> float:
	ensure_journey()
	var multiplier := 1.0
	for condition_id in active_conditions:
		multiplier += float(CONDITION_DRAIN_BONUSES.get(str(condition_id), 0.0))
	return minf(MAX_DRAIN_MULTIPLIER, multiplier)


static func get_survival_snapshot() -> Dictionary:
	ensure_journey()
	return {
		"hunger": hunger,
		"thirst": thirst,
		"stress": stress,
		"stress_maximum": STRESS_PROFILE.MAX_STRESS,
		"stress_stage": STRESS_PROFILE.stage_name(stress),
		"maximum": MAX_NEED,
		"drain_multiplier": get_survival_drain_multiplier(),
		"conditions": active_conditions.duplicate(true),
		"body_health": BODY_HEALTH.snapshot(body_health, active_conditions),
	}


static func restore_needs(hunger_amount := 0.0, thirst_amount := 0.0) -> Dictionary:
	ensure_journey()
	var previous_hunger := hunger
	var previous_thirst := thirst
	hunger = clampf(hunger + maxf(0.0, hunger_amount), 0.0, MAX_NEED)
	thirst = clampf(thirst + maxf(0.0, thirst_amount), 0.0, MAX_NEED)
	return {
		"hunger": hunger - previous_hunger,
		"thirst": thirst - previous_thirst,
		"snapshot": get_survival_snapshot(),
	}


static func set_stress(value: float) -> float:
	ensure_journey()
	if is_finite(value):
		stress = clampf(value, 0.0, STRESS_PROFILE.MAX_STRESS)
	return stress


static func add_stress(amount: float) -> float:
	ensure_journey()
	var previous := stress
	if is_finite(amount):
		set_stress(stress + maxf(0.0, amount))
	return stress - previous


static func relieve_stress(amount: float) -> float:
	ensure_journey()
	var previous := stress
	if is_finite(amount):
		set_stress(stress - maxf(0.0, amount))
	return previous - stress


static func get_stress_snapshot() -> Dictionary:
	ensure_journey()
	return {"stress": stress, "maximum": STRESS_PROFILE.MAX_STRESS, "stage": STRESS_PROFILE.stage_name(stress), "stage_index": STRESS_PROFILE.stage_index(stress)}


static func apply_condition(condition_id: String, duration := -1.0, part: String = "") -> bool:
	ensure_journey()
	if not CONDITION_DRAIN_BONUSES.has(condition_id):
		return false
	var resolved_duration := duration
	if resolved_duration <= 0.0:
		resolved_duration = float(CONDITION_DEFAULT_DURATIONS.get(condition_id, 180.0))
	active_conditions[condition_id] = maxf(float(active_conditions.get(condition_id, 0.0)), resolved_duration)
	if condition_id in ["bleeding", "fracture"]:
		var target := part
		if not BODY_HEALTH.PART_MAX_HEALTH.has(target):
			target = "left_leg" if condition_id == "fracture" else "thorax"
		if condition_id == "fracture" and target not in ["left_arm", "right_arm", "left_leg", "right_leg"]:
			target = "left_leg"
		var locations: Array = body_health.condition_parts.get(condition_id, [])
		if target not in locations:
			locations.append(target)
		body_health.condition_parts[condition_id] = locations
	return true


static func clear_condition(condition_id: String) -> bool:
	ensure_journey()
	if not active_conditions.has(condition_id):
		return false
	active_conditions.erase(condition_id)
	body_health.condition_parts.erase(condition_id)
	return true


static func condition_affects_part(condition_id: String, part: String = "") -> bool:
	if not has_condition(condition_id):
		return false
	if part.is_empty() or condition_id not in ["bleeding", "fracture"]:
		return true
	return part in body_health.condition_parts.get(condition_id, ["left_leg" if condition_id == "fracture" else "thorax"])


static func clear_condition_from_part(condition_id: String, part: String = "") -> bool:
	if not condition_affects_part(condition_id, part):
		return false
	if condition_id not in ["bleeding", "fracture"]:
		return clear_condition(condition_id)
	var locations: Array = body_health.condition_parts.get(condition_id, ["left_leg" if condition_id == "fracture" else "thorax"])
	var target := str(locations[0]) if part.is_empty() and not locations.is_empty() else part
	locations.erase(target)
	if locations.is_empty():
		return clear_condition(condition_id)
	body_health.condition_parts[condition_id] = locations
	return true


static func clear_conditions() -> void:
	ensure_journey()
	active_conditions.clear()
	body_health.condition_parts.clear()


static func has_condition(condition_id: String) -> bool:
	ensure_journey()
	return active_conditions.has(condition_id) and float(active_conditions[condition_id]) > 0.0


static func get_condition_display_name(condition_id: String) -> String:
	return str(CONDITION_DISPLAY_NAMES.get(condition_id, condition_id))


static func learn_spell(spell_id: String) -> bool:
	ensure_journey()
	if not SPELL_CATALOG_SCRIPT.is_valid_spell(spell_id) or is_spell_learned(spell_id):
		return false
	learned_spells[spell_id] = true
	if selected_spell.is_empty():
		selected_spell = spell_id
	return true


static func learn_spell_from_book(item_id: String, source_inventory: ExpeditionInventory = null) -> Dictionary:
	ensure_journey()
	var inventory := source_inventory if source_inventory != null else _inventory
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty() or str(definition.get("effect", "")) != "learn_spell":
		return {"accepted": false, "reason": "not_spellbook", "message": "이 물품에는 배울 수 있는 주문이 없습니다."}
	var spell_id := str(definition.get("spell_id", ""))
	if not SPELL_CATALOG_SCRIPT.is_valid_spell(spell_id):
		return {"accepted": false, "reason": "invalid_spell", "message": "해독할 수 없는 마법서입니다."}
	if is_spell_learned(spell_id):
		return {"accepted": false, "reason": "already_learned", "message": "%s은(는) 이미 익힌 주문입니다." % SPELL_CATALOG_SCRIPT.get_spell_name(spell_id)}
	if inventory == null or inventory.count_item(item_id) <= 0:
		return {"accepted": false, "reason": "not_owned", "message": "가방에서 해당 마법서를 찾을 수 없습니다."}
	if not inventory.remove_item(item_id, 1):
		return {"accepted": false, "reason": "not_owned", "message": "가방에서 해당 마법서를 찾을 수 없습니다."}
	learned_spells[spell_id] = true
	if selected_spell.is_empty():
		selected_spell = spell_id
	return {
		"accepted": true,
		"spell_learned": spell_id,
		"message": "%s을(를) 익혔습니다." % SPELL_CATALOG_SCRIPT.get_spell_name(spell_id),
	}


static func is_spell_learned(spell_id: String) -> bool:
	ensure_journey()
	return bool(learned_spells.get(spell_id, false))


static func get_learned_spell_ids() -> Array[String]:
	ensure_journey()
	var result: Array[String] = []
	for spell_id in SPELL_CATALOG_SCRIPT.ordered_spell_ids():
		if is_spell_learned(spell_id):
			result.append(spell_id)
	return result


static func select_spell(spell_id: String) -> bool:
	ensure_journey()
	if not is_spell_learned(spell_id):
		return false
	selected_spell = spell_id
	return true


static func get_selected_spell() -> String:
	ensure_journey()
	if not selected_spell.is_empty() and is_spell_learned(selected_spell):
		return selected_spell
	var known := get_learned_spell_ids()
	selected_spell = known[0] if not known.is_empty() else ""
	return selected_spell


static func get_magic_snapshot() -> Dictionary:
	return {
		"learned": get_learned_spell_ids(),
		"selected": get_selected_spell(),
	}


static func _remove_expired_conditions() -> void:
	for condition_id in active_conditions.keys():
		if float(active_conditions[condition_id]) <= 0.00001:
			active_conditions.erase(condition_id)
			if not body_health.is_empty():
				body_health.condition_parts.erase(condition_id)


static func get_stock_quantity(item_id: String) -> int:
	ensure_journey()
	var stock_entry: Variant = merchant_stock.get(item_id, {})
	return int((stock_entry as Dictionary).get("quantity", 0)) if stock_entry is Dictionary else 0


static func is_stock_unlimited(item_id: String) -> bool:
	ensure_journey()
	var stock_entry: Variant = merchant_stock.get(item_id, {})
	return bool((stock_entry as Dictionary).get("unlimited", false)) if stock_entry is Dictionary else false


static func get_buy_price(item_id: String) -> int:
	ensure_journey()
	var stock_entry: Variant = merchant_stock.get(item_id, {})
	if stock_entry is Dictionary:
		return maxi(1, int((stock_entry as Dictionary).get("price", 1)))
	return maxi(1, int(ExpeditionInventory.get_item_definition(item_id).get("value", 1)))


static func get_sell_price(item_id: String) -> int:
	var definition := ExpeditionInventory.get_item_definition(item_id)
	return maxi(1, floori(float(definition.get("value", 1)) * 0.6))


static func buy_item(item_id: String, quantity := 1) -> Dictionary:
	ensure_journey()
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if quantity <= 0 or definition.is_empty():
		return {"accepted": false, "reason": "invalid_item"}
	if bool(definition.get("unique_learning", false)):
		var spell_id := str(definition.get("spell_id", ""))
		if is_spell_learned(spell_id):
			return {"accepted": false, "reason": "already_learned"}
		if _inventory.count_item(item_id) > 0:
			return {"accepted": false, "reason": "already_owned"}
	if not is_stock_unlimited(item_id) and get_stock_quantity(item_id) < quantity:
		return {"accepted": false, "reason": "out_of_stock"}
	var total_price := get_buy_price(item_id) * quantity
	if crowns < total_price:
		return {"accepted": false, "reason": "not_enough_crowns", "price": total_price}
	if not _inventory.can_add(item_id, quantity):
		return {"accepted": false, "reason": "inventory_full"}
	var remainder := _inventory.add_item(item_id, quantity, false)
	if remainder > 0:
		var added_quantity := quantity - remainder
		if added_quantity > 0:
			_inventory.remove_item(item_id, added_quantity, false)
		return {"accepted": false, "reason": "inventory_full"}
	crowns -= total_price
	var entry := merchant_stock[item_id] as Dictionary
	if not bool(entry.get("unlimited", false)):
		entry["quantity"] = int(entry.get("quantity", 0)) - quantity
	_inventory.changed.emit()
	return {
		"accepted": true,
		"item_id": item_id,
		"quantity": quantity,
		"price": total_price,
		"crowns": crowns,
	}


static func sell_item(item_id: String, quantity := 1) -> Dictionary:
	ensure_journey()
	if quantity <= 0 or ExpeditionInventory.get_item_definition(item_id).is_empty():
		return {"accepted": false, "reason": "invalid_item"}
	if _inventory.count_item(item_id) < quantity:
		return {"accepted": false, "reason": "not_owned"}
	if _inventory.count_sellable_item(item_id) < quantity:
		return {"accepted": false, "reason": "protected_weapon"}
	if not _inventory.remove_sellable_item(item_id, quantity, false):
		return {"accepted": false, "reason": "not_owned"}
	var total_price := get_sell_price(item_id) * quantity
	crowns += total_price
	if not merchant_stock.has(item_id):
		merchant_stock[item_id] = {
			"quantity": 0,
			"price": maxi(1, int(ExpeditionInventory.get_item_definition(item_id).get("value", 1))),
		}
	var entry := merchant_stock[item_id] as Dictionary
	if not bool(entry.get("unlimited", false)):
		entry["quantity"] = int(entry.get("quantity", 0)) + quantity
	_inventory.changed.emit()
	return {
		"accepted": true,
		"item_id": item_id,
		"quantity": quantity,
		"price": total_price,
		"crowns": crowns,
	}
