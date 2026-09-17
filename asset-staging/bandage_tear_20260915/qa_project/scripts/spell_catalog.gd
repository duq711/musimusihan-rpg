extends RefCounted
class_name SpellCatalog

const SPELL_ORDER: Array[String] = [
	"fire_bolt",
	"water_bolt",
	"ice_shard",
	"stone_shard",
	"healing_light",
	"restorative_light",
]

const SPELLS := {
	"fire_bolt": {
		"name": "초보 화염탄",
		"short_name": "불",
		"cast_type": "projectile",
		"element": "fire",
		"stamina_cost": 22.0,
		"damage": 30.0,
		"speed": 16.0,
		"cooldown": 0.55,
		"radius": 0.15,
		"knockback": 0.42,
		"color": Color(1.0, 0.25, 0.055),
		"description": "응축한 불씨를 직선으로 쏘아 보내는 초급 공격 마법입니다.",
	},
	"water_bolt": {
		"name": "물의 화살",
		"short_name": "물",
		"cast_type": "projectile",
		"element": "water",
		"stamina_cost": 14.0,
		"damage": 18.0,
		"speed": 19.0,
		"cooldown": 0.38,
		"radius": 0.12,
		"knockback": 0.28,
		"color": Color(0.12, 0.56, 1.0),
		"description": "빠르게 뭉친 물줄기를 발사하는 저비용 초급 마법입니다.",
	},
	"ice_shard": {
		"name": "서리 파편",
		"short_name": "얼음",
		"cast_type": "projectile",
		"element": "ice",
		"stamina_cost": 18.0,
		"damage": 23.0,
		"speed": 17.0,
		"cooldown": 0.50,
		"radius": 0.13,
		"knockback": 0.34,
		"color": Color(0.43, 0.91, 1.0),
		"description": "차가운 결정 파편을 만들어 표적에게 날리는 초급 마법입니다.",
	},
	"stone_shard": {
		"name": "돌 탄환",
		"short_name": "돌",
		"cast_type": "projectile",
		"element": "stone",
		"stamina_cost": 26.0,
		"damage": 38.0,
		"speed": 12.0,
		"cooldown": 0.80,
		"radius": 0.19,
		"knockback": 0.88,
		"color": Color(0.58, 0.39, 0.20),
		"description": "무거운 돌 조각을 날려 큰 충격을 주는 느린 초급 마법입니다.",
	},
	"healing_light": {
		"name": "초급 치유",
		"short_name": "치유",
		"cast_type": "heal",
		"tier": 1,
		"element": "light",
		"stamina_cost": 28.0,
		"heal_amount": 32.0,
		"cooldown": 1.0,
		"color": Color(0.43, 1.0, 0.57),
		"description": "선택한 부위의 체력을 32 회복합니다. 체력이 0인 부위는 고위 회복이나 수술로 먼저 복구해야 합니다.",
	},
	"restorative_light": {
		"name": "고위 재생",
		"short_name": "재생",
		"cast_type": "heal",
		"tier": 3,
		"repair_blackout": true,
		"element": "light",
		"stamina_cost": 55.0,
		"heal_amount": 0.0,
		"cooldown": 2.5,
		"color": Color(0.86, 0.96, 0.61),
		"description": "살아 있는 시전자의 손상 부위 하나를 체력 0에서 1로 복구하는 고위 마법입니다. 이후 회복약이나 초급 치유로 체력을 채우세요. 상태이상은 별도로 치료해야 합니다.",
	},
}


static func get_spell_definition(spell_id: String) -> Dictionary:
	var value: Variant = SPELLS.get(spell_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func get_spell_name(spell_id: String) -> String:
	return str(get_spell_definition(spell_id).get("name", spell_id))


static func is_valid_spell(spell_id: String) -> bool:
	return SPELLS.has(spell_id)


static func ordered_spell_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(SPELL_ORDER)
	return result
