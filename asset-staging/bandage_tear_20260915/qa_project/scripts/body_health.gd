extends RefCounted
class_name BodyHealth

const PART_ORDER: Array[String] = ["head", "thorax", "stomach", "left_arm", "right_arm", "left_leg", "right_leg"]
const PART_MAX_HEALTH := {"head": 35.0, "thorax": 85.0, "stomach": 70.0, "left_arm": 60.0, "right_arm": 60.0, "left_leg": 65.0, "right_leg": 65.0}
const PART_NAMES := {"head": "머리", "thorax": "가슴", "stomach": "복부", "left_arm": "왼팔", "right_arm": "오른팔", "left_leg": "왼다리", "right_leg": "오른다리"}
const MAX_HEALTH := 440.0
const VITAL_PARTS: Array[String] = ["head", "thorax"]


static func create_state() -> Dictionary:
	return {"parts": PART_MAX_HEALTH.duplicate(true), "selected_part": "", "condition_parts": {}}


static func total_health(state: Dictionary) -> float:
	var total := 0.0
	var parts: Dictionary = state.get("parts", {})
	for part in PART_ORDER:
		total += clampf(float(parts.get(part, PART_MAX_HEALTH[part])), 0.0, float(PART_MAX_HEALTH[part]))
	return total


static func is_dead(state: Dictionary) -> bool:
	var parts: Dictionary = state.get("parts", {})
	for part in VITAL_PARTS:
		if float(parts.get(part, PART_MAX_HEALTH[part])) <= 0.0:
			return true
	return false


static func snapshot(state: Dictionary, conditions: Dictionary = {}) -> Dictionary:
	var parts := {}
	var values: Dictionary = state.get("parts", PART_MAX_HEALTH)
	var locations: Dictionary = state.get("condition_parts", {})
	for part in PART_ORDER:
		var local_conditions := {}
		for condition in conditions:
			if part in locations.get(condition, []):
				local_conditions[condition] = conditions[condition]
		var value := clampf(float(values.get(part, PART_MAX_HEALTH[part])), 0.0, float(PART_MAX_HEALTH[part]))
		parts[part] = {"health": value, "max_health": PART_MAX_HEALTH[part], "name": PART_NAMES[part], "blacked": value <= 0.0, "conditions": local_conditions}
	return {"parts": parts, "health": total_health(state), "max_health": MAX_HEALTH, "selected_part": str(state.get("selected_part", "")), "conditions": conditions.duplicate(true), "dead": is_dead(state)}


static func set_total_for_debug(state: Dictionary, value: float) -> void:
	if not is_finite(value):
		return
	var ratio := clampf(value, 0.0, MAX_HEALTH) / MAX_HEALTH
	var assigned := 0.0
	for part in PART_ORDER:
		var part_value := float(PART_MAX_HEALTH[part]) * ratio if part != PART_ORDER.back() else clampf(value, 0.0, MAX_HEALTH) - assigned
		state.parts[part] = part_value
		assigned += part_value


static func damage(state: Dictionary, part: String, amount: float) -> Dictionary:
	if not PART_MAX_HEALTH.has(part) or not is_finite(amount) or amount <= 0.0 or is_dead(state):
		return {"accepted": false, "damage": 0.0, "part": part, "blacked": false, "dead": is_dead(state)}
	var before := total_health(state)
	var previous := float(state.parts[part])
	var direct := minf(previous, amount)
	state.parts[part] = maxf(0.0, previous - direct)
	var excess := amount - direct
	# Damage to a destroyed non-vital part remains dangerous. Spread overflow
	# proportionally across still-living parts without reviving or damaging zeroes.
	if excess > 0.0 and not is_dead(state):
		var living_total := total_health(state)
		var fraction := minf(1.0, excess / living_total) if living_total > 0.0 else 0.0
		for other in PART_ORDER:
			if float(state.parts[other]) > 0.0:
				state.parts[other] = maxf(0.0, float(state.parts[other]) * (1.0 - fraction))
	return {"accepted": true, "damage": before - total_health(state), "part": part, "blacked": float(state.parts[part]) <= 0.0, "dead": is_dead(state)}


static func heal_capacity(state: Dictionary, part: String = "") -> float:
	if is_dead(state) or (not part.is_empty() and not PART_MAX_HEALTH.has(part)):
		return 0.0
	var capacity := 0.0
	for target in PART_ORDER:
		if not part.is_empty() and target != part:
			continue
		var value := float(state.parts[target])
		if value > 0.0:
			capacity += maxf(0.0, float(PART_MAX_HEALTH[target]) - value)
	return capacity


static func heal(state: Dictionary, amount: float, part: String = "") -> float:
	if not is_finite(amount) or amount <= 0.0 or heal_capacity(state, part) <= 0.0:
		return 0.0
	var remaining := amount
	for target in PART_ORDER:
		if not part.is_empty() and target != part:
			continue
		var value := float(state.parts[target])
		if value <= 0.0:
			continue
		var restored := minf(remaining, maxf(0.0, float(PART_MAX_HEALTH[target]) - value))
		state.parts[target] = value + restored
		remaining -= restored
		if remaining <= 0.0:
			break
	return amount - remaining


static func repair_target(state: Dictionary, part: String = "") -> String:
	if is_dead(state) or (not part.is_empty() and not PART_MAX_HEALTH.has(part)):
		return ""
	for target in PART_ORDER:
		if (part.is_empty() or target == part) and float(state.parts[target]) <= 0.0:
			return target
	return ""


static func repair(state: Dictionary, part: String = "") -> float:
	var target := repair_target(state, part)
	if target.is_empty():
		return 0.0
	state.parts[target] = 1.0
	return 1.0


static func impairment_count(state: Dictionary, parts: Array[String], conditions: Dictionary) -> int:
	var fractured: Array = (state.get("condition_parts", {}) as Dictionary).get("fracture", ["left_leg"]) if conditions.has("fracture") else []
	var count := 0
	for part in parts:
		if float(state.parts[part]) <= 0.0 or part in fractured:
			count += 1
	return count
