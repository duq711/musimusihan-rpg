extends RefCounted
class_name CampCookingCatalog

# Authoritative recipes: the camp menu, resource payment and test-room
# supplies all read this catalog. A finished dish is eaten at the fire.
const RECIPES := {
	"roast_meat": {
		"recipe_id": "roast_meat", "title": "모닥불 고기구이", "duration": 8.0,
		"survival": 60.0, "warmth": 1, "resources": {"raw_meat": 1},
		"health": 18.0, "stamina": 35.0, "hunger": 40.0, "thirst": 0.0, "stress": 12.0,
		"description": "생고기를 꼬치에 꿰어 구운 뒤 바로 먹습니다. 체력 18 · 기력 35 · 포만감 40 회복, 스트레스 12 완화. 게임 시간 60초가 흐릅니다."
	},
	"mushroom_soup": {
		"recipe_id": "mushroom_soup", "title": "따뜻한 버섯수프", "duration": 10.0,
		"survival": 90.0, "warmth": 1, "resources": {"edible_mushroom": 2, "boiled_rainwater": 1},
		"health": 12.0, "stamina": 30.0, "hunger": 30.0, "thirst": 45.0, "stress": 16.0,
		"description": "식용 버섯을 물에 푹 끓여 바로 먹습니다. 체력 12 · 기력 30 · 포만감 30 · 수분 45 회복, 스트레스 16 완화. 게임 시간 90초가 흐릅니다."
	},
	"trail_stew": {
		"recipe_id": "trail_stew", "title": "고기·버섯 스튜", "duration": 14.0,
		"survival": 120.0, "warmth": 2, "resources": {"raw_meat": 1, "edible_mushroom": 1, "boiled_rainwater": 1},
		"health": 35.0, "stamina": 65.0, "hunger": 65.0, "thirst": 35.0, "stress": 24.0,
		"description": "고기와 버섯을 함께 끓여 든든하게 먹습니다. 체력 35 · 기력 65 · 포만감 65 · 수분 35 회복, 스트레스 24 완화. 게임 시간 120초가 흐릅니다."
	}
}


static func ordered_recipe_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in RECIPES:
		ids.append(id)
	return ids


static func get_recipe(id: String) -> Dictionary:
	return (RECIPES.get(id, {}) as Dictionary).duplicate(true)


static func action_id(recipe_id: String) -> String:
	return "cook:" + recipe_id
