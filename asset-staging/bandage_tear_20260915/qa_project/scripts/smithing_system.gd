extends RefCounted
class_name SmithingSystem

signal changed

const RECIPES := {
	"iron_longsword": {"name": "단조 장검", "item_id": "forged_longsword", "cost": {"iron_ingot": 3, "forge_charcoal": 2}},
	"iron_arming_sword": {"name": "단조 한손검", "item_id": "forged_arming_sword", "cost": {"iron_ingot": 2, "forge_charcoal": 1}},
}
const GRIPS := {
	"leather_grip": {"name": "가죽 손잡이", "cost": {"grip_leather": 2}, "summary": "공격 기력 -12%"},
	"balanced_grip": {"name": "균형 손잡이", "cost": {"grip_leather": 2, "steel_fitting": 1}, "summary": "공격 기력 -22%"},
}
const REINFORCEMENTS := {
	"steel_edge": {"name": "강철 칼날 보강", "cost": {"iron_ingot": 1, "steel_fitting": 1}, "summary": "피해 +5"},
	"silver_edge": {"name": "은 상감 칼날", "cost": {"silver_inlay": 2}, "summary": "피해 +8"},
}
const RUNES := {
	"rune_fragment": {"name": "청록 룬 파편", "summary": "피해 +3 · 적중 시 체력 +2"},
	"ember_rune": {"name": "잿불 룬 돌조각", "summary": "타격 피해 +6"},
}
const MIN_WORK_HEAT := 700.0
const MAX_WORK_HEAT := 1000.0
const MAX_SOCKETS := 2
const CANCEL_POLICY := "작업을 버리면 투입한 철과 숯은 회수되지 않습니다. 완성 무기와 개조는 가방에 보존됩니다."

var inventory: ExpeditionInventory
var stage := "idle"
var recipe_id := ""
var temperature := 20.0
var side := 0
var sections: Array = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
var quality := 100.0
var hammer_count := 0
var selected_uid := ""
var last_message := "철과 숯을 준비하고 제작법을 선택하십시오."
var _serial := 0


func setup(inventory_ref: ExpeditionInventory) -> SmithingSystem:
	inventory = inventory_ref
	return self


static func trial_supplies() -> Dictionary:
	return {"iron_ingot": 12, "forge_charcoal": 8, "grip_leather": 8, "steel_fitting": 8, "silver_inlay": 6, "rune_fragment": 4, "ember_rune": 4}


func start(id: String = "iron_longsword") -> Dictionary:
	if stage not in ["idle", "finished"]:
		return _reject("busy", "먼저 진행 중인 무기를 완성하거나 작업을 버리십시오.")
	if not RECIPES.has(id):
		return _reject("unknown_recipe", "없는 제작법입니다.")
	var cost: Dictionary = RECIPES[id].cost
	if not _can_pay(cost):
		return _reject("missing_materials", "철 주괴와 대장간 숯이 부족합니다. 은신처 상인에게 구매할 수 있습니다.")
	_pay(cost)
	recipe_id = id
	stage = "fire"
	temperature = 20.0
	side = 0
	sections = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	quality = 100.0
	hammer_count = 0
	return _accept("철과 숯을 화로에 넣었습니다. 풀무로 700~1000°C까지 달구십시오.")


func pump_bellows() -> Dictionary:
	if stage != "fire":
		return _reject("wrong_station", "화로에 철이 있을 때 풀무를 당길 수 있습니다.")
	temperature = minf(1200.0, temperature + 150.0)
	if temperature > MAX_WORK_HEAT:
		quality = maxf(20.0, quality - 6.0)
		return _accept("과열되었습니다! 잠시 기다려 식히십시오. 품질이 감소했습니다.")
	return _accept("풀무를 당겨 불을 키웠습니다. 철 온도 %d°C" % roundi(temperature))


func tick(delta: float) -> void:
	if delta <= 0.0 or stage not in ["fire", "anvil"]:
		return
	temperature = maxf(20.0, temperature - delta * (10.0 if stage == "anvil" else 3.5))


func move_to_anvil() -> Dictionary:
	if stage != "fire":
		return _reject("wrong_station", "화로에서 달군 철을 모루로 옮깁니다.")
	if temperature < MIN_WORK_HEAT:
		return _reject("too_cold", "아직 차갑습니다. 풀무를 더 당겨 700°C 이상 달구십시오.")
	if temperature > MAX_WORK_HEAT:
		return _reject("too_hot", "철이 과열되었습니다. 1000°C 이하로 식힌 뒤 옮기십시오.")
	stage = "anvil"
	return _accept("집게로 철을 모루에 올렸습니다. 칼날의 세 구간을 고르게 두드리고 뒤집으십시오.")


func hammer(section: int, timing_accuracy: float = 1.0) -> Dictionary:
	if stage != "anvil":
		return _reject("wrong_station", "모루에서만 망치질할 수 있습니다.")
	if section < 0 or section > 2 or not is_finite(timing_accuracy):
		return _reject("invalid_section", "칼날의 뿌리·중앙·끝 중 한 구간을 선택하십시오.")
	if temperature < MIN_WORK_HEAT:
		return _reject("too_cold", "철이 식었습니다. 화로로 돌아가 다시 달구십시오.")
	if float(sections[side][section]) >= 1.0:
		return _reject("section_complete", "이 구간은 충분히 펴졌습니다. 다른 구간을 두드리거나 칼을 뒤집으십시오.")
	var accuracy := clampf(timing_accuracy, 0.0, 1.0)
	sections[side][section] = minf(1.0, float(sections[side][section]) + lerpf(0.16, 0.5, accuracy))
	temperature = maxf(20.0, temperature - 18.0)
	quality = maxf(20.0, quality - (1.0 - accuracy) * 4.0)
	hammer_count += 1
	return _accept("%s %s을 두드렸습니다. %d%%" % ["앞면" if side == 0 else "뒷면", ["뿌리", "중앙", "끝"][section], roundi(float(sections[side][section]) * 100)])


func flip_blade() -> Dictionary:
	if stage != "anvil":
		return _reject("wrong_station", "모루에서 칼날을 뒤집으십시오.")
	side = 1 - side
	return _accept("집게로 칼날을 뒤집었습니다. %s" % ("앞면" if side == 0 else "뒷면"))


func return_to_fire() -> Dictionary:
	if stage != "anvil":
		return _reject("wrong_station", "모루에 있는 칼날만 다시 가열할 수 있습니다.")
	stage = "fire"
	return _accept("칼날을 화로에 되돌렸습니다. 단조 진행은 보존됩니다.")


func shaping_complete() -> bool:
	for face in sections:
		for progress in face:
			if float(progress) < 1.0:
				return false
	return true


func quench() -> Dictionary:
	if stage not in ["anvil", "fire"]:
		return _reject("wrong_station", "가열한 칼날을 물에 담그십시오.")
	if not shaping_complete():
		return _reject("unfinished_blade", "앞뒤 칼날의 세 구간을 모두 단조한 뒤 담금질하십시오.")
	if temperature < MIN_WORK_HEAT:
		return _reject("too_cold", "담금질 전에 700~1000°C로 다시 달구십시오.")
	if temperature > MAX_WORK_HEAT:
		return _reject("too_hot", "과열 상태입니다. 1000°C 이하로 식힌 뒤 담금질하십시오.")
	quality = clampf(quality - absf(temperature - 850.0) / 30.0, 20.0, 100.0)
	temperature = 20.0
	stage = "quenched"
	return _accept("칼날을 물에 담가 굳혔습니다. 손잡이를 조립해 무기를 완성하십시오.")


func finish() -> Dictionary:
	if stage != "quenched":
		return _reject("not_quenched", "단조와 담금질을 먼저 마치십시오.")
	var id := str(RECIPES[recipe_id].item_id)
	if not inventory.can_add(id, 1):
		return _reject("inventory_full", "가방이 가득 찼습니다. 빈자리를 만든 뒤 완성품을 받으십시오.")
	var instance := _new_instance(id)
	instance["smithing"] = _blank_mods()
	instance.smithing["quality"] = snappedf(quality, 0.1)
	if inventory.add_item(id, 1, true, instance) != 0:
		return _reject("inventory_full", "가방이 가득 찼습니다. 완성품은 작업대에 남아 있습니다.")
	stage = "finished"
	selected_uid = str(instance.uid)
	var result := _accept("%s 완성! 품질 %d · 가방에서 장착할 수 있습니다." % [RECIPES[recipe_id].name, roundi(quality)])
	result["item_id"] = id
	result["uid"] = selected_uid
	return result


func cancel() -> Dictionary:
	if stage in ["idle", "finished"]:
		stage = "idle"
		return _accept("작업대를 정리했습니다.")
	stage = "idle"
	recipe_id = ""
	temperature = 20.0
	sections = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	return _accept("미완성 철을 폐기했습니다. 이미 투입한 철과 숯은 소모됩니다.")


func weapons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if inventory == null:
		return result
	var equipped_id := str(inventory.equipment.get("weapon", ""))
	if str(ExpeditionInventory.get_item_definition(equipped_id).get("weapon_type", "")) == "melee":
		var data := inventory.get_equipment_instance("weapon")
		_ensure_instance(data, equipped_id)
		result.append(_weapon_snapshot(equipped_id, data, true))
	for stack in inventory.slots:
		var id := str(stack.get("id", ""))
		if str(ExpeditionInventory.get_item_definition(id).get("weapon_type", "")) != "melee":
			continue
		if not stack.has("instance"):
			stack["instance"] = _new_instance(id)
		var instance: Dictionary = stack["instance"]
		_ensure_instance(instance, id)
		result.append(_weapon_snapshot(id, instance, false))
	return result


func select_weapon(id: String) -> Dictionary:
	for weapon in weapons():
		if str(weapon.uid) == id or str(weapon.id) == id:
			selected_uid = str(weapon.uid)
			return _accept("%s을 작업대에 고정했습니다." % weapon.name)
	return _reject("not_owned", "소유한 검을 선택하십시오.")


func replace_grip(id: String = "leather_grip") -> Dictionary:
	return _upgrade(id, GRIPS, "grip")


func reinforce_blade(id: String = "steel_edge") -> Dictionary:
	return _upgrade(id, REINFORCEMENTS, "reinforcement")


func drill_socket(alignment: float = 1.0) -> Dictionary:
	if stage not in ["idle", "finished"]:
		return _reject("busy", "단조 중인 작업을 먼저 끝내십시오.")
	var instance := _selected_instance()
	if instance.is_empty():
		return _reject("not_owned", "먼저 소유한 검을 작업대에 고정하십시오.")
	var mods: Dictionary = instance.smithing
	if int(mods.sockets) >= MAX_SOCKETS:
		return _reject("socket_limit", "룬 구멍은 무기당 두 개까지 뚫을 수 있습니다.")
	if not is_finite(alignment) or alignment < 0.4:
		return _reject("misaligned", "천공 위치가 빗나갔습니다. 표시된 중앙을 맞추십시오.")
	if float(mods.drill_progress) <= 0.0:
		if not _can_pay({"steel_fitting": 1}):
			return _reject("missing_materials", "천공에 사용할 강철 부속 1개가 필요합니다.")
		_pay({"steel_fitting": 1})
	mods.drill_progress = minf(1.0, float(mods.drill_progress) + 1.0 / 3.0)
	if float(mods.drill_progress) >= 0.999:
		mods.sockets = int(mods.sockets) + 1
		mods.drill_progress = 0.0
		inventory.changed.emit()
		return _accept("칼날에 룬 구멍을 뚫었습니다. 빈 구멍에 돌조각을 넣으십시오.")
	inventory.changed.emit()
	return _accept("송곳을 돌려 칼날을 파고 있습니다. 천공 %d%%" % roundi(float(mods.drill_progress) * 100))


func insert_rune(id: String = "rune_fragment") -> Dictionary:
	if stage not in ["idle", "finished"]:
		return _reject("busy", "단조 중인 작업을 먼저 끝내십시오.")
	if not RUNES.has(id):
		return _reject("unknown_rune", "사용할 수 없는 룬입니다.")
	var instance := _selected_instance()
	if instance.is_empty():
		return _reject("not_owned", "먼저 소유한 검을 작업대에 고정하십시오.")
	var mods: Dictionary = instance.smithing
	if (mods.runes as Array).size() >= int(mods.sockets):
		return _reject("no_socket", "빈 룬 구멍이 없습니다. 먼저 칼날을 천공하십시오.")
	if not _can_pay({id: 1}):
		return _reject("missing_materials", "선택한 룬 돌조각이 가방에 없습니다.")
	_pay({id: 1})
	(mods.runes as Array).append(id)
	inventory.changed.emit()
	return _accept("%s을 구멍에 고정했습니다. %s" % [RUNES[id].name, RUNES[id].summary])


func snapshot() -> Dictionary:
	var available := weapons()
	var selected: Dictionary = {}
	for weapon in available:
		if str(weapon.uid) == selected_uid:
			selected = weapon
	var materials: Dictionary = {}
	for id in trial_supplies():
		materials[id] = 0 if inventory == null else inventory.count_item(str(id))
	var mods: Dictionary = selected.get("smithing", {})
	return {"stage": stage, "recipe_id": recipe_id, "temperature": temperature, "side": side, "sections": sections.duplicate(true), "quality": quality, "hammer_count": hammer_count, "shaping_complete": shaping_complete(), "selected_weapon": selected, "weapons": available, "materials": materials, "drill_progress": float(mods.get("drill_progress", 0.0)), "message": last_message, "cancel_policy": CANCEL_POLICY}


func _upgrade(id: String, catalog: Dictionary, field: String) -> Dictionary:
	if stage not in ["idle", "finished"]:
		return _reject("busy", "단조 중인 작업을 먼저 끝내십시오.")
	if not catalog.has(id):
		return _reject("unknown_upgrade", "없는 개조법입니다.")
	var instance := _selected_instance()
	if instance.is_empty():
		return _reject("not_owned", "먼저 소유한 검을 작업대에 고정하십시오.")
	var mods: Dictionary = instance.smithing
	if str(mods.get(field, "")) == id:
		return _reject("already_installed", "이미 같은 부품이 장착되어 있습니다.")
	if not _can_pay(catalog[id].cost):
		return _reject("missing_materials", "개조 재료가 부족합니다. 은신처 상인에게 구매하십시오.")
	_pay(catalog[id].cost)
	mods[field] = id
	inventory.changed.emit()
	return _accept("%s 장착 완료. %s · 교체한 부품은 소모됩니다." % [catalog[id].name, catalog[id].summary])


func _selected_instance() -> Dictionary:
	if inventory == null or selected_uid.is_empty():
		return {}
	var equipped := inventory.get_equipment_instance("weapon")
	if str(equipped.get("uid", "")) == selected_uid:
		return equipped
	for stack in inventory.slots:
		var instance: Dictionary = stack.get("instance", {})
		if str(instance.get("uid", "")) == selected_uid:
			return instance
	return {}


func _new_instance(item_id: String) -> Dictionary:
	_serial += 1
	return {"item_id": item_id, "uid": "%d-%d-%d" % [get_instance_id(), Time.get_ticks_usec(), _serial]}


func _ensure_instance(data: Dictionary, item_id: String) -> void:
	if not data.has("uid"):
		data.merge(_new_instance(item_id), false)
	if not data.has("smithing"):
		data["smithing"] = _blank_mods()


func _blank_mods() -> Dictionary:
	return {"quality": 0.0, "grip": "", "reinforcement": "", "sockets": 0, "runes": [], "drill_progress": 0.0}


func _weapon_snapshot(id: String, instance: Dictionary, equipped: bool) -> Dictionary:
	return {"id": id, "uid": str(instance.uid), "name": ExpeditionInventory.get_item_name(id), "equipped": equipped, "smithing": (instance.smithing as Dictionary).duplicate(true)}


func _can_pay(cost: Dictionary) -> bool:
	if inventory == null:
		return false
	for id in cost:
		if inventory.count_item(str(id)) < int(cost[id]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for id in cost:
		inventory.remove_item(str(id), int(cost[id]), false)
	inventory.changed.emit()


func _accept(message: String) -> Dictionary:
	last_message = message
	changed.emit()
	return {"accepted": true, "reason": "", "message": message}


func _reject(reason: String, message: String) -> Dictionary:
	last_message = message
	changed.emit()
	return {"accepted": false, "reason": reason, "message": message}
