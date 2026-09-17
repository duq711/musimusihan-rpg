extends RefCounted
class_name ExpeditionInventory

signal changed

const MAX_SLOTS := 30
const EQUIPMENT_ORDER: Array[String] = ["head", "body", "weapon", "offhand", "utility"]
const EQUIPMENT_LABELS := {
	"head": "머리",
	"body": "몸통",
	"weapon": "주무기",
	"offhand": "보조 장비",
	"utility": "도구"
}

# Glyphs remain available as a text fallback. Atlas coordinates and UI spans
# render the authored item art without changing the compact stack model used
# for inventory rules.
const ITEM_DEFINITIONS := {
	"rusted_sword": {
		"name": "녹슨 장검", "glyph": "†", "category": "equipment", "equip_slot": "weapon", "weapon_type": "melee",
		"atlas_cell": Vector2i(2, 0), "ui_span": Vector2i(2, 3),
		"weight": 3.2, "value": 18, "stack_max": 1, "rarity": "common",
		"summary": "피해 22 · 강공격 38", "description": "성소 입구에서 지급받은 무딘 장검입니다."
	},
	"hunting_bow": {
		"name": "사냥꾼의 활", "glyph": "⌒", "category": "equipment", "equip_slot": "weapon", "weapon_type": "bow", "ammo_type": "wooden_arrow",
		"icon_path": "res://assets/ui/hunting_bow.svg", "ui_span": Vector2i(2, 3),
		"weight": 1.8, "value": 38, "stack_max": 1, "rarity": "uncommon",
		"summary": "당길수록 피해 18~46 · 기력 22/초", "description": "LMB로 당기고 놓아 발사합니다. 0.1초 이하로 당겼다 바로 놓으면 화살이 앞으로 날지 않고 아래로 떨어집니다. 더 당길수록 발사 속도와 기본 피해가 증가하며, 1초간 끝까지 당기면 최대 속도 42m/s와 피해 46이 됩니다. 짧게 당기면 방향이 흩어지고, 완전히 당기면 발사 방향 오차와 반동이 최소화됩니다. 중력 낙하는 유지됩니다. 당김·유지 중 기력이 초당 22 소모되며, 기력이 바닥나면 현재 당긴 힘으로 화살 1발을 자동 발사합니다. 수동·자동 발사 모두 화살 1개를 쓰고 추가 기력 비용은 없습니다. RMB·메뉴·장비 교체로 취소하면 화살은 보존하지만 이미 사용한 기력은 돌아오지 않습니다. 기력이 0이면 새로 당길 수 없고, 양손 활을 든 동안 방패 가드는 불가합니다."
	},
	"chain_flail": {
		"name": "사슬철퇴", "glyph": "✹", "category": "equipment", "equip_slot": "weapon", "weapon_type": "flail",
		"icon_path": "res://assets/ui/chain_flail.svg", "ui_span": Vector2i(2, 3),
		"weight": 4.8, "value": 64, "stack_max": 1, "rarity": "uncommon",
		"summary": "근접 32 · 회전 투척 28~60", "description": "LMB로 휘둘러 피해 32를 주며 기력 18을 씁니다. RMB를 누르면 기력 24를 한 번 소모하고 옆에서 철구를 회전시킵니다. 유지 중 추가 기력 소모는 없으며 1.2초에 최대 회전이 됩니다. RMB를 놓으면 던지고, 짧게 눌러도 최소 0.35초 회전한 뒤 자동으로 던집니다. 회전량에 따라 투척 피해 28~60과 사거리 6~14m가 증가합니다. 철구는 자동 회수되며 돌아오는 동안 피해를 주지 않고 재공격할 수 없습니다. 무기는 소모되지 않습니다. 메뉴·인벤토리·포커스 상실·장비 교체·피격으로 취소해도 사용한 기력은 반환되지 않습니다. 양손 무기로 취급되어 방패 가드는 불가합니다."
	},
	"wooden_arrow": {
		"name": "나무 화살", "glyph": "↟", "category": "ammunition",
		"icon_path": "res://assets/ui/wooden_arrow.svg", "ui_span": Vector2i(1, 2),
		"weight": 0.06, "value": 2, "stack_max": 30, "rarity": "common",
		"summary": "활 탄약 · 묶음 최대 30개", "description": "깃을 단 곧은 나무 화살입니다. 활 발사 시 가방에서 자동으로 1개씩 소모되며 별도 장착은 필요 없습니다."
	},
	"round_shield": {
		"name": "철테 원형 방패", "glyph": "◉", "category": "equipment", "equip_slot": "offhand",
		"atlas_cell": Vector2i(3, 0), "ui_span": Vector2i(2, 2),
		"weight": 4.4, "value": 24, "stack_max": 1, "rarity": "common",
		"summary": "정면 방어 · 내구도 3", "description": "낡은 참나무 판에 철테를 두른 원형 방패입니다."
	},
	"wanderer_hood": {
		"name": "방랑자의 두건", "glyph": "⌃", "category": "equipment", "equip_slot": "head",
		"atlas_cell": Vector2i(0, 0), "ui_span": Vector2i(2, 2),
		"weight": 0.8, "value": 13, "stack_max": 1, "rarity": "common",
		"summary": "방어 등급 1", "description": "습기와 먼지를 막아 주는 두꺼운 모직 두건입니다."
	},
	"patched_mail": {
		"name": "누비 쇄자갑", "glyph": "▥", "category": "equipment", "equip_slot": "body",
		"atlas_cell": Vector2i(1, 0), "ui_span": Vector2i(2, 3),
		"weight": 5.6, "value": 31, "stack_max": 1, "rarity": "uncommon",
		"summary": "방어 등급 3 · 이동 -2%", "description": "여러 주인의 손을 거친 쇄자갑입니다. 아직 목숨값은 합니다."
	},
	"field_torch": {
		"name": "원정용 횃불", "glyph": "♨", "category": "equipment", "equip_slot": "utility",
		"atlas_cell": Vector2i(0, 1), "ui_span": Vector2i(1, 2),
		"weight": 1.1, "value": 8, "stack_max": 1, "rarity": "common",
		"summary": "F · 점화/소등", "description": "송진을 먹인 천을 감은 기본 원정 장비입니다."
	},
	"weathered_staff": {
		"name": "풍화된 수습생 지팡이", "glyph": "⚚", "category": "equipment", "equip_slot": "weapon", "weapon_type": "staff",
		"icon_path": "res://assets/ui/weathered_staff.svg", "ui_span": Vector2i(1, 3),
		"weight": 2.4, "value": 42, "stack_max": 1, "rarity": "uncommon",
		"summary": "마법 시전 전용 · 1~5 선택", "description": "금이 간 청록 수정이 박힌 초보 마법사용 느릅나무 지팡이입니다."
	},
	"fire_spellbook": {
		"name": "잿불의 입문 마법서", "glyph": "▣", "category": "consumable", "effect": "learn_spell", "spell_id": "fire_bolt", "unique_learning": true,
		"icon_path": "res://assets/ui/fire_spellbook.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.75, "value": 34, "stack_max": 1, "rarity": "uncommon",
		"summary": "초보 화염탄 영구 습득", "description": "첫 불씨를 잃지 않는 법이 거친 필체로 기록되어 있습니다."
	},
	"water_spellbook": {
		"name": "흐르는 물의 입문 마법서", "glyph": "▣", "category": "consumable", "effect": "learn_spell", "spell_id": "water_bolt", "unique_learning": true,
		"icon_path": "res://assets/ui/water_spellbook.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.7, "value": 26, "stack_max": 1, "rarity": "uncommon",
		"summary": "물의 화살 영구 습득", "description": "종이 사이로 희미한 물결 소리가 흐르는 초급 마법서입니다."
	},
	"ice_spellbook": {
		"name": "서리 봉인의 입문 마법서", "glyph": "▣", "category": "consumable", "effect": "learn_spell", "spell_id": "ice_shard", "unique_learning": true,
		"icon_path": "res://assets/ui/ice_spellbook.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.8, "value": 38, "stack_max": 1, "rarity": "rare",
		"summary": "서리 파편 영구 습득", "description": "표지의 은빛 문양이 손끝의 열을 천천히 빼앗습니다."
	},
	"stone_spellbook": {
		"name": "잠든 돌의 입문 마법서", "glyph": "▣", "category": "consumable", "effect": "learn_spell", "spell_id": "stone_shard", "unique_learning": true,
		"icon_path": "res://assets/ui/stone_spellbook.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.9, "value": 32, "stack_max": 1, "rarity": "uncommon",
		"summary": "돌 탄환 영구 습득", "description": "돌가루로 눌러 쓴 주문식이 무겁게 이어지는 초급 마법서입니다."
	},
	"healing_spellbook": {
		"name": "온기의 초급 치유서", "glyph": "▣", "category": "consumable", "effect": "learn_spell", "spell_id": "healing_light", "unique_learning": true,
		"icon_path": "res://assets/ui/healing_spellbook.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.65, "value": 48, "stack_max": 1, "rarity": "rare",
		"summary": "초급 치유 영구 습득", "description": "상처 위에 온기를 모으는 기초 치유식이 적혀 있습니다."
	},
	"healing_draught": {
		"name": "핏빛 회복약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 32.0,
		"atlas_cell": Vector2i(1, 1), "ui_span": Vector2i(1, 1),
		"weight": 0.5, "value": 12, "stack_max": 5, "rarity": "uncommon",
		"summary": "체력 32 회복", "description": "쓴 약초와 응고제를 달인 붉은 물약입니다."
	},
	"holy_oil_flask": {
		"name": "성유 화염병", "glyph": "♨", "category": "consumable", "effect": "attack_item",
		"atlas_cell": Vector2i(2, 1), "ui_span": Vector2i(1, 1),
		"weight": 0.7, "value": 17, "stack_max": 4, "rarity": "uncommon",
		"summary": "피해 30 · 방어 파괴", "description": "깨지는 순간 푸른 불길이 번지는 봉헌용 성유입니다."
	},
	"linen_bandage": {
		"name": "누런 붕대", "glyph": "▰", "category": "consumable", "effect": "bandage", "amount": 18.0,
		"atlas_cell": Vector2i(3, 1), "ui_span": Vector2i(1, 1),
		"weight": 0.25, "value": 5, "stack_max": 6, "rarity": "common",
		"summary": "체력 18 회복", "description": "소금물 냄새가 밴 두꺼운 붕대입니다."
	},
	"pilgrim_ration": {
		"name": "마른 순례자 식량", "glyph": "▤", "category": "consumable", "effect": "restore_hunger", "amount": 32.0,
		"icon_path": "res://assets/ui/pilgrim_ration.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.35, "value": 8, "stack_max": 5, "rarity": "common",
		"summary": "포만감 32 회복", "description": "검은 빵과 말린 뿌리채소를 천에 싸 둔 오래가는 원정 식량입니다."
	},
	"boiled_rainwater": {
		"name": "끓인 빗물병", "glyph": "◒", "category": "consumable", "effect": "restore_thirst", "amount": 38.0,
		"icon_path": "res://assets/ui/boiled_rainwater.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.65, "value": 9, "stack_max": 4, "rarity": "common",
		"summary": "수분 38 회복", "description": "은신처 화로에서 한 번 끓인 빗물을 도기병에 담았습니다."
	},
	"lamp_oil": {
		"name": "등불 기름", "glyph": "◈", "category": "supply",
		"atlas_cell": Vector2i(0, 2), "ui_span": Vector2i(1, 1),
		"weight": 0.6, "value": 7, "stack_max": 5, "rarity": "common",
		"summary": "원정 보급품", "description": "검댕이 적은 정제 기름입니다."
	},
	"raw_meat": {
		"name": "손질한 생고기", "glyph": "◖", "category": "supply",
		"icon_path": "res://assets/ui/raw_meat.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.45, "value": 10, "stack_max": 6, "rarity": "common",
		"summary": "야영 요리 재료 · 구이 / 스튜", "description": "원정용으로 손질해 싸 둔 생고기입니다. 안전한 곳에서 C로 야영한 뒤 요리 탭에서 고기구이나 스튜로 조리해 먹습니다. 생으로 먹거나 가방에서 바로 사용하는 물품은 아닙니다."
	},
	"edible_mushroom": {
		"name": "식용 버섯", "glyph": "♧", "category": "supply",
		"icon_path": "res://assets/ui/edible_mushroom.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.15, "value": 5, "stack_max": 8, "rarity": "common",
		"summary": "야영 요리 재료 · 수프 / 스튜", "description": "먹을 수 있는 것으로 골라 둔 버섯입니다. 야영에서 물과 함께 수프로 끓이거나 고기와 함께 스튜에 넣습니다. 요리가 완료되면 바로 먹으며 가방에서 생으로 먹을 수는 없습니다."
	},
	"camp_kit": {
		"name": "휴대 야영 도구", "glyph": "♨", "category": "supply",
		"icon_path": "res://assets/ui/camp_kit.svg", "ui_span": Vector2i(1, 2),
		"weight": 0.5, "value": 18, "stack_max": 3, "rarity": "common",
		"summary": "C · 야영 준비 · 모닥불 온기 3", "description": "부싯돌과 마른 불쏘시개, 접은 방수포를 묶은 야영 도구입니다. 던전에서 C로 야영을 준비하고 첫 휴식 때 1개를 소비해 모닥불 온기 3을 마련합니다. 인벤토리에서 직접 사용하는 물품은 아닙니다. 실제 휴식 중에는 던전의 시간이 흐르며 적 접근이나 피격으로 즉시 중단됩니다. 이미 소비한 물품은 반환되지 않습니다."
	},
	"black_salt": {
		"name": "검은 소금", "glyph": "✦", "category": "treasure", "raid_loot": true,
		"atlas_cell": Vector2i(1, 2), "ui_span": Vector2i(1, 1),
		"weight": 0.35, "value": 18, "stack_max": 8, "rarity": "uncommon",
		"summary": "회수 가치 18 크라운", "description": "죽은 자의 혀 밑에서 자란다는 금지된 재료입니다."
	},
	"silver_chalice": {
		"name": "핏자국 은잔", "glyph": "♜", "category": "treasure", "raid_loot": true,
		"atlas_cell": Vector2i(2, 2), "ui_span": Vector2i(1, 2),
		"weight": 1.4, "value": 25, "stack_max": 2, "rarity": "rare",
		"summary": "회수 가치 25 크라운", "description": "아무리 닦아도 안쪽의 검붉은 얼룩이 지워지지 않습니다."
	},
	"rune_fragment": {
		"name": "청록 룬 파편", "glyph": "◆", "category": "treasure", "raid_loot": true,
		"atlas_cell": Vector2i(3, 2), "ui_span": Vector2i(1, 1),
		"weight": 0.2, "value": 27, "stack_max": 8, "rarity": "rare",
		"summary": "회수 가치 27 크라운", "description": "봉인의 맥박이 아직 희미하게 남아 있습니다."
	},
	"grave_key": {
		"name": "납골당 열쇠", "glyph": "⚿", "category": "key",
		"atlas_cell": Vector2i(0, 3), "ui_span": Vector2i(1, 1),
		"weight": 0.15, "value": 9, "stack_max": 3, "rarity": "uncommon",
		"summary": "퀘스트 물품", "description": "뼈 가루가 홈마다 굳어 있는 무거운 열쇠입니다."
	},
	"reliquary": {
		"name": "검은 성물함", "glyph": "✥", "category": "treasure", "raid_loot": true,
		"atlas_cell": Vector2i(1, 3), "ui_span": Vector2i(2, 2),
		"weight": 2.2, "value": 64, "stack_max": 1, "rarity": "legendary",
		"summary": "회수 가치 64 크라운", "description": "뚜껑 안쪽에서 낮은 기도 소리가 새어 나옵니다."
	}
}

var slots: Array[Dictionary] = []
var equipment: Dictionary = {
	"head": "",
	"body": "",
	"weapon": "",
	"offhand": "",
	"utility": ""
}


static func get_item_definition(item_id: String) -> Dictionary:
	var value: Variant = ITEM_DEFINITIONS.get(item_id, {})
	return value as Dictionary if value is Dictionary else {}


static func get_item_name(item_id: String) -> String:
	return str(get_item_definition(item_id).get("name", item_id))


func seed_default_loadout() -> void:
	slots.clear()
	equipment = {
		"head": "wanderer_hood",
		"body": "patched_mail",
		"weapon": "rusted_sword",
		"offhand": "round_shield",
		"utility": "field_torch"
	}
	add_item("healing_draught", 2, false)
	add_item("holy_oil_flask", 1, false)
	add_item("linen_bandage", 1, false)
	add_item("pilgrim_ration", 1, false)
	add_item("boiled_rainwater", 1, false)
	add_item("hunting_bow", 1, false)
	add_item("wooden_arrow", 12, false)
	add_item("chain_flail", 1, false)
	add_item("camp_kit", 1, false)
	add_item("raw_meat", 1, false)
	add_item("edible_mushroom", 2, false)
	changed.emit()


func add_item(item_id: String, quantity := 1, notify := true) -> int:
	var definition := get_item_definition(item_id)
	if definition.is_empty() or quantity <= 0:
		return quantity
	var remaining := quantity
	var stack_max := maxi(1, int(definition.get("stack_max", 1)))
	if stack_max > 1:
		for slot in slots:
			if str(slot.get("id", "")) != item_id:
				continue
			var room := stack_max - int(slot.get("quantity", 0))
			if room <= 0:
				continue
			var moved := mini(room, remaining)
			slot["quantity"] = int(slot.get("quantity", 0)) + moved
			remaining -= moved
			if remaining <= 0:
				break
	while remaining > 0 and slots.size() < MAX_SLOTS:
		var stack_quantity := mini(stack_max, remaining)
		slots.append({"id": item_id, "quantity": stack_quantity})
		remaining -= stack_quantity
	if notify and remaining != quantity:
		changed.emit()
	return remaining


func can_add(item_id: String, quantity := 1) -> bool:
	var definition := get_item_definition(item_id)
	if definition.is_empty() or quantity <= 0:
		return false
	var remaining := quantity
	var stack_max := maxi(1, int(definition.get("stack_max", 1)))
	for slot in slots:
		if str(slot.get("id", "")) == item_id:
			remaining -= maxi(0, stack_max - int(slot.get("quantity", 0)))
			if remaining <= 0:
				return true
	var free_slots := MAX_SLOTS - slots.size()
	return free_slots * stack_max >= remaining


func remove_item(item_id: String, quantity := 1, notify := true) -> bool:
	if quantity <= 0 or count_item(item_id) < quantity:
		return false
	var remaining := quantity
	for index in range(slots.size() - 1, -1, -1):
		if str(slots[index].get("id", "")) != item_id:
			continue
		var available := int(slots[index].get("quantity", 0))
		var removed := mini(available, remaining)
		slots[index]["quantity"] = available - removed
		remaining -= removed
		if int(slots[index].get("quantity", 0)) <= 0:
			slots.remove_at(index)
		if remaining <= 0:
			break
	if notify:
		changed.emit()
	return true


func remove_from_slot(index: int, quantity := 1, notify := true) -> Dictionary:
	if index < 0 or index >= slots.size() or quantity <= 0:
		return {}
	var stack := slots[index]
	var moved := mini(quantity, int(stack.get("quantity", 0)))
	var result := {"id": str(stack.get("id", "")), "quantity": moved}
	slots[index]["quantity"] = int(stack.get("quantity", 0)) - moved
	if int(slots[index].get("quantity", 0)) <= 0:
		slots.remove_at(index)
	if notify:
		changed.emit()
	return result


func count_item(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if str(slot.get("id", "")) == item_id:
			total += int(slot.get("quantity", 0))
	return total


func equip_from_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {"accepted": false, "reason": "invalid_slot"}
	var item_id := str(slots[index].get("id", ""))
	var definition := get_item_definition(item_id)
	var equipment_slot := str(definition.get("equip_slot", ""))
	if equipment_slot.is_empty() or not equipment.has(equipment_slot):
		return {"accepted": false, "reason": "not_equipment"}
	var previous := str(equipment.get(equipment_slot, ""))
	remove_from_slot(index, 1, false)
	equipment[equipment_slot] = item_id
	if not previous.is_empty():
		var remainder := add_item(previous, 1, false)
		if remainder > 0:
			# This should be unreachable because removing the new equipment frees a
			# slot, but keep the swap atomic if a future capacity rule changes.
			equipment[equipment_slot] = previous
			add_item(item_id, 1, false)
			return {"accepted": false, "reason": "full"}
	changed.emit()
	return {"accepted": true, "slot": equipment_slot, "equipped": item_id, "unequipped": previous}


func unequip(equipment_slot: String) -> Dictionary:
	if not equipment.has(equipment_slot):
		return {"accepted": false, "reason": "invalid_slot"}
	var item_id := str(equipment.get(equipment_slot, ""))
	if item_id.is_empty():
		return {"accepted": false, "reason": "empty"}
	if not can_add(item_id, 1):
		return {"accepted": false, "reason": "full"}
	equipment[equipment_slot] = ""
	add_item(item_id, 1, false)
	changed.emit()
	return {"accepted": true, "slot": equipment_slot, "item": item_id}


func total_weight() -> float:
	var weight := 0.0
	for slot in slots:
		var definition := get_item_definition(str(slot.get("id", "")))
		weight += float(definition.get("weight", 0.0)) * int(slot.get("quantity", 0))
	for equipment_slot in EQUIPMENT_ORDER:
		var item_id := str(equipment.get(equipment_slot, ""))
		if not item_id.is_empty():
			weight += float(get_item_definition(item_id).get("weight", 0.0))
	return weight


func raid_loot_value() -> int:
	var total := 0
	for slot in slots:
		var definition := get_item_definition(str(slot.get("id", "")))
		if bool(definition.get("raid_loot", false)):
			total += int(definition.get("value", 0)) * int(slot.get("quantity", 0))
	return total


func raid_loot_count() -> int:
	var total := 0
	for slot in slots:
		var definition := get_item_definition(str(slot.get("id", "")))
		if bool(definition.get("raid_loot", false)):
			total += int(slot.get("quantity", 0))
	return total
