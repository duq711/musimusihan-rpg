extends RefCounted
class_name AlchemyCatalog

# Original sanctuary recipes. Ingredient milestones describe cumulative, actual
# boiling turns before that handful enters the cauldron; turning the hourglass
# never advances these values.
const BASES := {
	"water": {"name": "맑은 물", "item_id": "alchemy_water", "boiling_point": 100.0},
	"wine": {"name": "붉은 포도주", "item_id": "alchemy_wine", "boiling_point": 90.0},
	"spirits": {"name": "곡물 증류주", "item_id": "alchemy_spirits", "boiling_point": 82.0},
	"oil": {"name": "약용 기름", "item_id": "alchemy_oil", "boiling_point": 125.0},
}
const HERBS := {
	"redroot": {"name": "핏뿌리", "item_id": "alchemy_redroot", "description": "붉은 수액을 품은 뿌리 · 회복약의 중심 재료"},
	"dawnleaf": {"name": "새벽잎", "item_id": "alchemy_dawnleaf", "description": "잎맥에 온기가 남은 약초 · 빻으면 진한 약성이 우러남"},
	"moonwort": {"name": "달쑥", "item_id": "alchemy_moonwort", "description": "은빛 잔털이 난 쑥 · 증류에 쓰는 향기로운 약초"},
	"bittermint": {"name": "쓴박하", "item_id": "alchemy_bittermint", "description": "서늘한 향의 잎 · 식힌 뒤 넣어 향을 보존"},
	"ironbloom": {"name": "쇠꽃", "item_id": "alchemy_ironbloom", "description": "철빛 꽃봉오리 · 지혈 연고의 재료"},
}
const RECIPES := {
	"red_mending": {
		"name": "붉은 봉합약", "description": "물을 바탕으로 뿌리를 달이고 빻은 잎을 우려내는 회복약.", "base": "water",
		"ingredients": {"redroot": 1, "dawnleaf": 2}, "finish": "bottle", "boil_target": 2.0, "finish_max_temp": 60.0,
		"steps": ["맑은 물 1병을 솥에 붓는다.", "핏뿌리 한 줌을 그대로 넣는다.", "솥을 내리고 풀무로 불을 살린다. 실제로 끓기 시작하면 모래시계 한 회전(8초) 동안 달인다.", "솥을 올린다. 새벽잎 두 줌을 절구에 넣고 세 번 빻아 솥에 붓는다.", "한 번 젓고 솥을 내려 다시 한 회전 끓인다.", "솥을 올리고 60°C 이하로 식혀 빈 병에 담는다."],
		"milestones": [{"herb": "redroot", "form": "whole", "boil_before": 0.0}, {"herb": "dawnleaf", "form": "ground", "boil_before": 1.0}, {"herb": "dawnleaf", "form": "ground", "boil_before": 1.0}],
		"stirs": 1, "stir_after": 3,
		"outputs": {"weak": "alchemy_red_mending_weak", "normal": "alchemy_red_mending_normal", "strong": "alchemy_red_mending_strong"},
	},
	"ember_cordial": {
		"name": "잿불 포도약", "description": "포도주에 통뿌리를 달인 뒤 식힌 박하를 섞는 깊은 회복약.", "base": "wine",
		"ingredients": {"redroot": 2, "bittermint": 1}, "finish": "bottle", "boil_target": 2.0, "finish_max_temp": 50.0,
		"steps": ["붉은 포도주 1병을 붓는다.", "핏뿌리 두 줌을 빻지 않고 넣는다.", "솥을 내려 끓이고 두 회전(16초) 달인다. 모래가 끝나면 직접 뒤집는다.", "솥을 올려 50°C 이하로 식힌다.", "쓴박하 한 줌을 절구에서 세 번 빻아 넣는다.", "두 번 젓고 더 끓이지 않은 채 병에 담는다."],
		"milestones": [{"herb": "redroot", "form": "whole", "boil_before": 0.0}, {"herb": "redroot", "form": "whole", "boil_before": 0.0}, {"herb": "bittermint", "form": "ground", "boil_before": 2.0, "max_temp": 50.0}],
		"stirs": 2, "stir_after": 3,
		"outputs": {"weak": "alchemy_ember_cordial_weak", "normal": "alchemy_ember_cordial_normal", "strong": "alchemy_ember_cordial_strong"},
	},
	"moon_distillate": {
		"name": "달쑥 지혈 정수", "description": "증류주에 약초를 달인 뒤 증기를 받아 만드는 지혈 정수.", "base": "spirits",
		"ingredients": {"moonwort": 2, "ironbloom": 1}, "finish": "distill", "boil_target": 1.0, "distill_turns": 1.5,
		"steps": ["곡물 증류주 1병을 붓는다.", "달쑥 두 줌을 절구에서 세 번 빻아 넣는다.", "쇠꽃 한 줌은 그대로 넣고 한 번 젓는다.", "끓기 시작한 뒤 한 회전(8초) 달인다.", "솥을 올려 끓임을 멈추고 증류기를 연결한다.", "솥을 내려 풀무로 불을 유지한다. 실제로 끓는 동안 1.5회전(12초) 증류하고 정수를 병에 받는다."],
		"milestones": [{"herb": "moonwort", "form": "ground", "boil_before": 0.0}, {"herb": "moonwort", "form": "ground", "boil_before": 0.0}, {"herb": "ironbloom", "form": "whole", "boil_before": 0.0}],
		"stirs": 1, "stir_after": 3,
		"outputs": {"weak": "alchemy_moon_distillate_weak", "normal": "alchemy_moon_distillate_normal", "strong": "alchemy_moon_distillate_strong"},
	},
	"pilgrim_tonic": {
		"name": "순례자의 냉침약", "description": "불을 쓰지 않고 빻은 잎과 박하를 물에 우려 갈증을 다스리는 약.", "base": "water",
		"ingredients": {"dawnleaf": 1, "bittermint": 2}, "finish": "bottle", "boil_target": 0.0, "finish_max_temp": 35.0, "steep_seconds": 8.0,
		"steps": ["맑은 물 1병을 붓는다. 솥을 불 위에 내리지 않는다.", "새벽잎 한 줌을 절구에서 세 번 빻아 넣는다.", "쓴박하 두 줌을 빻지 않고 넣는다.", "두 번 젓고 마지막 재료를 넣은 뒤 모래시계 한 회전(8초) 동안 냉침한다.", "35°C 이하의 차가운 약을 그대로 병에 담는다. 끓이거나 증류하면 약성이 손상된다."],
		"milestones": [{"herb": "dawnleaf", "form": "ground", "boil_before": 0.0}, {"herb": "bittermint", "form": "whole", "boil_before": 0.0}, {"herb": "bittermint", "form": "whole", "boil_before": 0.0}],
		"stirs": 2, "stir_after": 3,
		"outputs": {"weak": "alchemy_pilgrim_tonic_weak", "normal": "alchemy_pilgrim_tonic_normal", "strong": "alchemy_pilgrim_tonic_strong"},
	},
	"iron_salve": {
		"name": "쇠꽃 봉합유", "description": "뜨거운 약용 기름에 빻은 꽃을 달이고 식혀 바르는 지혈약.", "base": "oil",
		"ingredients": {"ironbloom": 2, "redroot": 1}, "finish": "bottle", "boil_target": 1.0, "finish_max_temp": 45.0,
		"steps": ["약용 기름 1병을 붓는다.", "쇠꽃 두 줌을 절구에서 세 번 빻아 솥에 붓는다.", "핏뿌리 한 줌을 그대로 넣고 두 번 젓는다.", "풀무로 강한 불을 유지해 125°C에서 한 회전(8초) 달인다.", "솥을 올리고 45°C 이하로 식힌 뒤 병에 담는다. 증류하지 않는다."],
		"milestones": [{"herb": "ironbloom", "form": "ground", "boil_before": 0.0}, {"herb": "ironbloom", "form": "ground", "boil_before": 0.0}, {"herb": "redroot", "form": "whole", "boil_before": 0.0}],
		"stirs": 2, "stir_after": 3,
		"outputs": {"weak": "alchemy_iron_salve_weak", "normal": "alchemy_iron_salve_normal", "strong": "alchemy_iron_salve_strong"},
	},
	"hearth_brandy": {
		"name": "화롯불 브랜디", "description": "포도주에 뿌리와 잎의 향을 입힌 판매용 증류주. 정제 1병은 36크라운, 특급 2병은 120크라운에 팔립니다.", "base": "wine", "product_type": "liquor",
		"ingredients": {"redroot": 1, "dawnleaf": 1}, "finish": "distill", "boil_target": 1.0, "distill_turns": 2.0,
		"steps": ["상인에게 포도주 1병·핏뿌리 1줌·새벽잎 1줌·빈 병을 산다. 정제 원가 12크라운, 특급 원가 14크라운.", "붉은 포도주 1병을 붓고 핏뿌리 한 줌을 그대로 넣는다.", "새벽잎 한 줌을 절구에서 세 번 빻아 넣고 한 번 젓는다.", "솥을 내리고 Space 풀무로 불을 살린다. 90°C에서 끓기 시작한 뒤 한 회전(8초) 달인다.", "솥을 올려 끓임을 멈추고 증류기를 연결한다.", "솥을 내리고 풀무를 보충해 끓는 불을 유지하며 두 회전(16초) 증류한다. 끝나면 빈 병에 받아 상인에게 판다. 특급은 빈 병 2개가 필요하다."],
		"milestones": [{"herb": "redroot", "form": "whole", "boil_before": 0.0}, {"herb": "dawnleaf", "form": "ground", "boil_before": 0.0}],
		"stirs": 1, "stir_after": 2,
		"outputs": {"weak": "liquor_hearth_brandy_weak", "normal": "liquor_hearth_brandy_normal", "strong": "liquor_hearth_brandy_strong"},
	},
	"moon_absinthe": {
		"name": "달쑥 압생트", "description": "달쑥과 박하의 향을 모은 고가의 판매용 증류주. 정제 1병은 51크라운, 특급 2병은 168크라운에 팔립니다.", "base": "spirits", "product_type": "liquor",
		"ingredients": {"moonwort": 2, "bittermint": 1}, "finish": "distill", "boil_target": 1.5, "distill_turns": 2.5,
		"steps": ["상인에게 곡물 증류주 1병·달쑥 2줌·쓴박하 1줌·빈 병을 산다. 정제 원가 19크라운, 특급 원가 21크라운.", "곡물 증류주 1병을 붓는다.", "달쑥 두 줌을 절구에서 세 번 빻아 넣고 쓴박하 한 줌은 그대로 넣는다.", "두 번 젓고 솥을 내린다. Space 풀무로 불을 살려 82°C에서 끓기 시작한 뒤 1.5회전(12초) 달인다.", "솥을 올려 끓임을 멈추고 증류기를 연결한다.", "솥을 내리고 풀무를 보충해 끓는 불을 유지하며 2.5회전(20초) 증류한다. 끝나면 빈 병에 받아 상인에게 판다. 특급은 빈 병 2개가 필요하다."],
		"milestones": [{"herb": "moonwort", "form": "ground", "boil_before": 0.0}, {"herb": "moonwort", "form": "ground", "boil_before": 0.0}, {"herb": "bittermint", "form": "whole", "boil_before": 0.0}],
		"stirs": 2, "stir_after": 3,
		"outputs": {"weak": "liquor_moon_absinthe_weak", "normal": "liquor_moon_absinthe_normal", "strong": "liquor_moon_absinthe_strong"},
	},
}

static func ordered_recipe_ids() -> Array[String]:
	var ids := medicine_recipe_ids()
	ids.append_array(liquor_recipe_ids())
	return ids


static func medicine_recipe_ids() -> Array[String]:
	return ["red_mending", "ember_cordial", "moon_distillate", "pilgrim_tonic", "iron_salve"]


static func liquor_recipe_ids() -> Array[String]:
	return ["hearth_brandy", "moon_absinthe"]


static func quality_label(recipe_id: String, quality: String) -> String:
	var names := {"weak": "묽은", "normal": "표준", "strong": "진한", "failed": "실패"}
	if str((RECIPES.get(recipe_id, {}) as Dictionary).get("product_type", "medicine")) == "liquor":
		names = {"weak": "미숙", "normal": "정제", "strong": "특급", "failed": "실패"}
	return str(names.get(quality, quality))


static func recipe(recipe_id: String) -> Dictionary:
	return (RECIPES.get(recipe_id, {}) as Dictionary).duplicate(true)
