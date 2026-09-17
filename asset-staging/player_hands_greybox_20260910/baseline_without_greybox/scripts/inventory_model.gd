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
	"alchemy_water": {
		"name": "연금술용 맑은 물", "glyph": "◒", "category": "supply", "icon_path": "res://assets/ui/alchemy_water.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.5, "value": 2, "stack_max": 12, "rarity": "common",
		"summary": "연금술 기본 액체 · 물", "description": "은신처 연금술 작업대에서 사용하는 재료입니다. 가방에서 바로 마시지 않고 솥에 붓거나 완성약을 담는 데 씁니다."
	},
	"alchemy_wine": {
		"name": "연금술용 포도주", "glyph": "◒", "category": "supply", "icon_path": "res://assets/ui/alchemy_wine.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.5, "value": 5, "stack_max": 12, "rarity": "common",
		"summary": "연금술 기본 액체 · 포도주", "description": "은신처 연금술 작업대에서 사용하는 재료입니다. 가방에서 바로 마시지 않고 솥에 붓거나 완성약을 담는 데 씁니다."
	},
	"alchemy_spirits": {
		"name": "연금술용 곡물 증류주", "glyph": "◒", "category": "supply", "icon_path": "res://assets/ui/alchemy_spirits.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.5, "value": 7, "stack_max": 12, "rarity": "common",
		"summary": "연금술 기본 액체 · 증류주", "description": "은신처 연금술 작업대에서 사용하는 재료입니다. 가방에서 바로 마시지 않고 솥에 붓거나 완성약을 담는 데 씁니다."
	},
	"alchemy_oil": {
		"name": "연금술용 약용 기름", "glyph": "◒", "category": "supply", "icon_path": "res://assets/ui/alchemy_oil.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.5, "value": 6, "stack_max": 12, "rarity": "common",
		"summary": "연금술 기본 액체 · 기름", "description": "은신처 연금술 작업대에서 사용하는 재료입니다. 가방에서 바로 마시지 않고 솥에 붓거나 완성약을 담는 데 씁니다."
	},
	"alchemy_empty_bottle": {
		"name": "빈 약병", "glyph": "◒", "category": "supply", "icon_path": "res://assets/ui/alchemy_empty_bottle.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.1, "value": 2, "stack_max": 12, "rarity": "common",
		"summary": "물약·증류주 병입 · 보통 1병 · 최고 품질 2병", "description": "은신처 연금술·증류 작업대에서 완성된 물약이나 판매용 술을 담습니다. 최고 품질이면 한 번에 2병을 만드므로 빈 병도 2개가 필요합니다."
	},
	"alchemy_redroot": {
		"name": "핏뿌리", "glyph": "♧", "category": "supply", "icon_path": "res://assets/ui/alchemy_redroot.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.05, "value": 3, "stack_max": 24, "rarity": "common",
		"summary": "연금술 약초 · 통째 투입 / 절구 빻기", "description": "한 개가 한 줌입니다. 조제서에 맞춰 그대로 넣거나 절구에서 세 번 빻아 솥에 붓습니다. 작업대에 넣는 즉시 가방에서 소비됩니다."
	},
	"alchemy_dawnleaf": {
		"name": "새벽잎", "glyph": "♧", "category": "supply", "icon_path": "res://assets/ui/alchemy_dawnleaf.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.05, "value": 2, "stack_max": 24, "rarity": "common",
		"summary": "연금술 약초 · 통째 투입 / 절구 빻기", "description": "한 개가 한 줌입니다. 조제서에 맞춰 그대로 넣거나 절구에서 세 번 빻아 솥에 붓습니다. 작업대에 넣는 즉시 가방에서 소비됩니다."
	},
	"alchemy_moonwort": {
		"name": "달쑥", "glyph": "♧", "category": "supply", "icon_path": "res://assets/ui/alchemy_moonwort.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.05, "value": 4, "stack_max": 24, "rarity": "common",
		"summary": "연금술 약초 · 통째 투입 / 절구 빻기", "description": "한 개가 한 줌입니다. 조제서에 맞춰 그대로 넣거나 절구에서 세 번 빻아 솥에 붓습니다. 작업대에 넣는 즉시 가방에서 소비됩니다."
	},
	"alchemy_bittermint": {
		"name": "쓴박하", "glyph": "♧", "category": "supply", "icon_path": "res://assets/ui/alchemy_bittermint.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.05, "value": 2, "stack_max": 24, "rarity": "common",
		"summary": "연금술 약초 · 통째 투입 / 절구 빻기", "description": "한 개가 한 줌입니다. 조제서에 맞춰 그대로 넣거나 절구에서 세 번 빻아 솥에 붓습니다. 작업대에 넣는 즉시 가방에서 소비됩니다."
	},
	"alchemy_ironbloom": {
		"name": "쇠꽃", "glyph": "♧", "category": "supply", "icon_path": "res://assets/ui/alchemy_ironbloom.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.05, "value": 4, "stack_max": 24, "rarity": "common",
		"summary": "연금술 약초 · 통째 투입 / 절구 빻기", "description": "한 개가 한 줌입니다. 조제서에 맞춰 그대로 넣거나 절구에서 세 번 빻아 솥에 붓습니다. 작업대에 넣는 즉시 가방에서 소비됩니다."
	},
	"liquor_hearth_brandy_weak": {
		"name": "미숙 화롯불 브랜디", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_hearth_brandy.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 20, "stack_max": 6, "rarity": "common",
		"summary": "판매용 증류주 · 상인 매입 12크라운", "description": "향이 거칠게 남은 브랜디입니다. 은신처에서 직접 증류한 교역품으로 상인에게 판매할 수 있습니다. 조제 순서와 빻기·젓기·끓이는 시간을 맞추면 품질과 판매가가 높아집니다."
	},
	"liquor_hearth_brandy_normal": {
		"name": "정제 화롯불 브랜디", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_hearth_brandy.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 60, "stack_max": 6, "rarity": "uncommon",
		"summary": "판매용 증류주 · 상인 매입 36크라운", "description": "따뜻한 뿌리 향이 담긴 정제 브랜디입니다. 상인에게 36크라운에 팔 수 있습니다. 재료와 빈 병을 모두 사면 제조 원가는 12크라운입니다."
	},
	"liquor_hearth_brandy_strong": {
		"name": "특급 화롯불 브랜디", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_hearth_brandy.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 100, "stack_max": 6, "rarity": "rare",
		"summary": "판매용 증류주 · 상인 매입 60크라운", "description": "향을 고르게 모은 특급 브랜디입니다. 한 번의 증류로 2병을 만들며 상인에게 합계 120크라운에 팔 수 있습니다. 재료와 빈 병 2개의 원가는 합계 14크라운입니다."
	},
	"liquor_moon_absinthe_weak": {
		"name": "미숙 달쑥 압생트", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_moon_absinthe.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 30, "stack_max": 6, "rarity": "common",
		"summary": "판매용 증류주 · 상인 매입 18크라운", "description": "쑥 향이 거칠게 남은 압생트입니다. 은신처에서 직접 증류한 교역품으로 상인에게 판매할 수 있습니다. 조제 순서와 빻기·젓기·끓이는 시간을 맞추면 품질과 판매가가 높아집니다."
	},
	"liquor_moon_absinthe_normal": {
		"name": "정제 달쑥 압생트", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_moon_absinthe.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 85, "stack_max": 6, "rarity": "uncommon",
		"summary": "판매용 증류주 · 상인 매입 51크라운", "description": "달쑥과 박하 향이 어우러진 정제 압생트입니다. 상인에게 51크라운에 팔 수 있습니다. 재료와 빈 병을 모두 사면 제조 원가는 19크라운입니다."
	},
	"liquor_moon_absinthe_strong": {
		"name": "특급 달쑥 압생트", "glyph": "◒", "category": "treasure", "product_type": "liquor",
		"icon_path": "res://assets/ui/liquor_moon_absinthe.svg", "ui_span": Vector2i(1, 1), "weight": 0.4, "value": 140, "stack_max": 6, "rarity": "rare",
		"summary": "판매용 증류주 · 상인 매입 84크라운", "description": "은빛 쑥의 향을 맑게 모은 특급 압생트입니다. 한 번의 증류로 2병을 만들며 상인에게 합계 168크라운에 팔 수 있습니다. 재료와 빈 병 2개의 원가는 합계 21크라운입니다."
	},
	"alchemy_red_mending_weak": {
		"name": "묽은 붉은 봉합약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 18.0,
		"icon_path": "res://assets/ui/alchemy_red_mending.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 8, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 18 회복", "description": "은신처에서 직접 조제한 묽은 약입니다. 가방에서 사용하면 체력을 18 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_red_mending_normal": {
		"name": "표준 붉은 봉합약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 32.0,
		"icon_path": "res://assets/ui/alchemy_red_mending.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 16, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 32 회복", "description": "은신처에서 직접 조제한 표준 약입니다. 가방에서 사용하면 체력을 32 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_red_mending_strong": {
		"name": "진한 붉은 봉합약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 48.0,
		"icon_path": "res://assets/ui/alchemy_red_mending.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 26, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 48 회복", "description": "은신처에서 직접 조제한 진한 약입니다. 가방에서 사용하면 체력을 48 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_ember_cordial_weak": {
		"name": "묽은 잿불 포도약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 24.0,
		"icon_path": "res://assets/ui/alchemy_ember_cordial.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 8, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 24 회복", "description": "은신처에서 직접 조제한 묽은 약입니다. 가방에서 사용하면 체력을 24 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_ember_cordial_normal": {
		"name": "표준 잿불 포도약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 40.0,
		"icon_path": "res://assets/ui/alchemy_ember_cordial.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 16, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 40 회복", "description": "은신처에서 직접 조제한 표준 약입니다. 가방에서 사용하면 체력을 40 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_ember_cordial_strong": {
		"name": "진한 잿불 포도약", "glyph": "✚", "category": "consumable", "effect": "heal", "amount": 58.0,
		"icon_path": "res://assets/ui/alchemy_ember_cordial.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 26, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 58 회복", "description": "은신처에서 직접 조제한 진한 약입니다. 가방에서 사용하면 체력을 58 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_moon_distillate_weak": {
		"name": "묽은 달쑥 지혈 정수", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 8.0,
		"icon_path": "res://assets/ui/alchemy_moon_distillate.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 8, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 8 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 묽은 약입니다. 가방에서 사용하면 체력을 8 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_moon_distillate_normal": {
		"name": "표준 달쑥 지혈 정수", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 16.0,
		"icon_path": "res://assets/ui/alchemy_moon_distillate.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 16, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 16 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 표준 약입니다. 가방에서 사용하면 체력을 16 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_moon_distillate_strong": {
		"name": "진한 달쑥 지혈 정수", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 26.0,
		"icon_path": "res://assets/ui/alchemy_moon_distillate.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 26, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 26 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 진한 약입니다. 가방에서 사용하면 체력을 26 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_pilgrim_tonic_weak": {
		"name": "묽은 순례자의 냉침약", "glyph": "✚", "category": "consumable", "effect": "restore_thirst", "amount": 24.0,
		"icon_path": "res://assets/ui/alchemy_pilgrim_tonic.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 8, "stack_max": 6, "rarity": "uncommon",
		"summary": "수분 24 회복", "description": "은신처에서 직접 조제한 묽은 약입니다. 가방에서 사용하면 수분을 24 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_pilgrim_tonic_normal": {
		"name": "표준 순례자의 냉침약", "glyph": "✚", "category": "consumable", "effect": "restore_thirst", "amount": 40.0,
		"icon_path": "res://assets/ui/alchemy_pilgrim_tonic.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 16, "stack_max": 6, "rarity": "uncommon",
		"summary": "수분 40 회복", "description": "은신처에서 직접 조제한 표준 약입니다. 가방에서 사용하면 수분을 40 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_pilgrim_tonic_strong": {
		"name": "진한 순례자의 냉침약", "glyph": "✚", "category": "consumable", "effect": "restore_thirst", "amount": 58.0,
		"icon_path": "res://assets/ui/alchemy_pilgrim_tonic.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 26, "stack_max": 6, "rarity": "uncommon",
		"summary": "수분 58 회복", "description": "은신처에서 직접 조제한 진한 약입니다. 가방에서 사용하면 수분을 58 회복합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_iron_salve_weak": {
		"name": "묽은 쇠꽃 봉합유", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 12.0,
		"icon_path": "res://assets/ui/alchemy_iron_salve.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 8, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 12 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 묽은 약입니다. 가방에서 사용하면 체력을 12 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_iron_salve_normal": {
		"name": "표준 쇠꽃 봉합유", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 24.0,
		"icon_path": "res://assets/ui/alchemy_iron_salve.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 16, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 24 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 표준 약입니다. 가방에서 사용하면 체력을 24 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"alchemy_iron_salve_strong": {
		"name": "진한 쇠꽃 봉합유", "glyph": "✚", "category": "consumable", "effect": "bandage", "amount": 36.0,
		"icon_path": "res://assets/ui/alchemy_iron_salve.svg", "ui_span": Vector2i(1, 1), "weight": 0.25, "value": 26, "stack_max": 6, "rarity": "uncommon",
		"summary": "체력 36 회복 · 출혈 해소", "description": "은신처에서 직접 조제한 진한 약입니다. 가방에서 사용하면 체력을 36 회복합니다. 출혈도 해소합니다. 제조 순서와 빻기·불 조절·마무리에 따라 품질이 달라집니다."
	},
	"forged_longsword": {
		"name": "단조 장검", "glyph": "†", "category": "equipment", "equip_slot": "weapon", "weapon_type": "melee",
		"icon_path": "res://assets/ui/forged_longsword.svg", "ui_span": Vector2i(2, 3),
		"weight": 3.0, "value": 48, "stack_max": 1, "rarity": "uncommon",
		"summary": "피해 31~57 · 품질에 따른 추가 피해", "description": "은신처에서 직접 단조한 장검입니다. 품질과 개조는 무기마다 별도로 보존됩니다."
	},
	"forged_arming_sword": {
		"name": "단조 한손검", "glyph": "†", "category": "equipment", "equip_slot": "weapon", "weapon_type": "melee",
		"icon_path": "res://assets/ui/forged_arming_sword.svg", "ui_span": Vector2i(2, 3),
		"weight": 2.3, "value": 38, "stack_max": 1, "rarity": "uncommon",
		"summary": "피해 29~52 · 기력 -10%", "description": "짧고 균형 잡힌 단조 한손검입니다. 손잡이·칼날·룬 개조를 지원합니다."
	},
	"iron_ingot": {
		"name": "철 주괴", "glyph": "▰", "category": "supply",
		"icon_path": "res://assets/ui/iron_ingot.svg", "ui_span": Vector2i(1, 1),
		"weight": 1.0, "value": 6, "stack_max": 12, "rarity": "uncommon",
		"summary": "대장간 · 칼날 단조 / 보강", "description": "화로에서 달구어 모루에서 두드리는 철 주괴입니다."
	},
	"forge_charcoal": {
		"name": "대장간 숯", "glyph": "♨", "category": "supply",
		"icon_path": "res://assets/ui/forge_charcoal.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.2, "value": 3, "stack_max": 12, "rarity": "uncommon",
		"summary": "대장간 · 화로 연료", "description": "풀무로 산소를 공급하면 강한 열을 내는 숯입니다."
	},
	"grip_leather": {
		"name": "손잡이 가죽", "glyph": "▤", "category": "supply",
		"icon_path": "res://assets/ui/grip_leather.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.15, "value": 5, "stack_max": 8, "rarity": "uncommon",
		"summary": "손잡이 교체 · 기력 감소", "description": "칼자루에 감는 질긴 가죽입니다."
	},
	"steel_fitting": {
		"name": "강철 부속", "glyph": "✦", "category": "supply",
		"icon_path": "res://assets/ui/steel_fitting.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.3, "value": 9, "stack_max": 8, "rarity": "uncommon",
		"summary": "칼날 보강 / 균형 손잡이 / 룬 구멍", "description": "칼날 보강과 천공에 필요한 작은 강철 부속입니다."
	},
	"silver_inlay": {
		"name": "은 상감 조각", "glyph": "◇", "category": "supply",
		"icon_path": "res://assets/ui/silver_inlay.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.2, "value": 12, "stack_max": 8, "rarity": "uncommon",
		"summary": "은 칼날 보강 · 피해 증가", "description": "칼날 가장자리에 박아 넣는 은 조각입니다."
	},
	"ember_rune": {
		"name": "잿불 룬 돌조각", "glyph": "◆", "category": "supply",
		"icon_path": "res://assets/ui/ember_rune.svg", "ui_span": Vector2i(1, 1),
		"weight": 0.15, "value": 24, "stack_max": 8, "rarity": "uncommon",
		"summary": "빈 룬 구멍에 삽입 · 타격 피해 +6", "description": "대장간에서 칼에 구멍을 파고 넣으면 타격에 잿불의 힘이 더해집니다."
	},
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
		"summary": "룬 구멍에 삽입 · 피해 +3 / 적중 시 체력 +2", "description": "회수하거나 대장간에서 칼의 빈 룬 구멍에 넣습니다. 무기 적중 시 체력을 2 회복합니다."
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
# The legacy equipment ID stays a string; instance payload follows each weapon.
var equipment_data: Dictionary = {}
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
	equipment_data.clear()
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


func add_item(item_id: String, quantity := 1, notify := true, instance_data: Dictionary = {}) -> int:
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
		var new_stack := {"id": item_id, "quantity": stack_quantity}
		if stack_max == 1 and quantity == 1 and not instance_data.is_empty():
			new_stack["instance"] = instance_data.duplicate(true)
		slots.append(new_stack)
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
	var result := stack.duplicate(true)
	result["quantity"] = moved
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
	var previous_data := get_equipment_instance(equipment_slot).duplicate(true)
	var next_stack := remove_from_slot(index, 1, false)
	equipment[equipment_slot] = item_id
	equipment_data[equipment_slot] = (next_stack.get("instance", {}) as Dictionary).duplicate(true)
	equipment_data[equipment_slot]["item_id"] = item_id
	if not previous.is_empty():
		var remainder := add_item(previous, 1, false, previous_data)
		if remainder > 0:
			# This should be unreachable because removing the new equipment frees a
			# slot, but keep the swap atomic if a future capacity rule changes.
			equipment[equipment_slot] = previous
			equipment_data[equipment_slot] = previous_data
			add_item(item_id, 1, false, next_stack.get("instance", {}))
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
	var instance := get_equipment_instance(equipment_slot).duplicate(true)
	equipment[equipment_slot] = ""
	equipment_data.erase(equipment_slot)
	add_item(item_id, 1, false, instance)
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


func get_equipment_instance(slot_name: String) -> Dictionary:
	var item_id := str(equipment.get(slot_name, ""))
	if item_id.is_empty():
		return {}
	var data: Dictionary = equipment_data.get(slot_name, {})
	# Direct legacy loadout assignments must never inherit the prior item's upgrades.
	if str(data.get("item_id", "")) != item_id:
		data = {"item_id": item_id}
		equipment_data[slot_name] = data
	return data


func equipped_smithing_stats() -> Dictionary:
	return smithing_stats(str(equipment.get("weapon", "")), get_equipment_instance("weapon"))


static func smithing_stats(id: String, instance: Dictionary) -> Dictionary:
	var data: Dictionary = instance.get("smithing", {})
	var light := 27.0
	var heavy := 53.0
	var stamina_scale := 1.0
	if id == "forged_longsword":
		light = 31.0
		heavy = 57.0
	elif id == "forged_arming_sword":
		light = 29.0
		heavy = 52.0
		stamina_scale = 0.9
	var bonus := maxf(0.0, float(data.get("quality", 0.0)) / 100.0 * 8.0)
	match str(data.get("grip", "")):
		"leather_grip": stamina_scale *= 0.88
		"balanced_grip": stamina_scale *= 0.78
	match str(data.get("reinforcement", "")):
		"steel_edge": bonus += 5.0
		"silver_edge": bonus += 8.0
	var heal := 0.0
	var fire := 0.0
	for rune in data.get("runes", []):
		if str(rune) == "rune_fragment":
			bonus += 3.0
			heal += 2.0
		elif str(rune) == "ember_rune":
			fire += 6.0
	return {"light_damage": light + bonus + fire, "heavy_damage": heavy + bonus + fire, "stamina_scale": stamina_scale, "life_on_hit": heal, "fire_damage": fire}


static func smithing_description(instance: Dictionary) -> String:
	var mods: Dictionary = instance.get("smithing", {})
	if mods.is_empty():
		return ""
	var grip := str(mods.get("grip", ""))
	var edge := str(mods.get("reinforcement", ""))
	var sockets := int(mods.get("sockets", 0))
	var quality_value := float(mods.get("quality", 0.0))
	if quality_value <= 0.0 and grip.is_empty() and edge.is_empty() and sockets <= 0:
		return ""
	var grip_name := str({"leather_grip": "가죽", "balanced_grip": "균형"}.get(grip, "기본"))
	var edge_name := str({"steel_edge": "강철 보강", "silver_edge": "은 상감"}.get(edge, "기본"))
	var rune_names: Array[String] = []
	for rune in mods.get("runes", []):
		rune_names.append("청록(적중 회복2)" if str(rune) == "rune_fragment" else "잿불(피해6)")
	return "품질 %d · 손잡이 %s\n칼날 %s\n룬 %d/%d · %s" % [roundi(quality_value), grip_name, edge_name, rune_names.size(), sockets, "없음" if rune_names.is_empty() else " + ".join(rune_names)]


static func is_smithing_protected(stack: Dictionary) -> bool:
	# Aggregate merchant stock has no per-instance buyback payload. Keep worked
	# weapons out of that transaction so their paid-for properties cannot vanish.
	var id := str(stack.get("id", ""))
	if str(get_item_definition(id).get("weapon_type", "")) != "melee":
		return false
	var instance: Dictionary = stack.get("instance", {})
	var mods: Dictionary = instance.get("smithing", {})
	return float(mods.get("quality", 0.0)) > 0.0 or not str(mods.get("grip", "")).is_empty() or not str(mods.get("reinforcement", "")).is_empty() or int(mods.get("sockets", 0)) > 0 or float(mods.get("drill_progress", 0.0)) > 0.0 or not (mods.get("runes", []) as Array).is_empty()


func count_sellable_item(item_id: String) -> int:
	var total := 0
	for stack in slots:
		if str(stack.get("id", "")) == item_id and not is_smithing_protected(stack):
			total += int(stack.get("quantity", 0))
	return total


func remove_sellable_item(item_id: String, quantity: int, notify := true) -> bool:
	if quantity <= 0 or count_sellable_item(item_id) < quantity:
		return false
	var remaining := quantity
	for index in range(slots.size() - 1, -1, -1):
		if str(slots[index].get("id", "")) != item_id or is_smithing_protected(slots[index]):
			continue
		var moved := mini(remaining, int(slots[index].get("quantity", 0)))
		remove_from_slot(index, moved, false)
		remaining -= moved
		if remaining == 0:
			break
	if notify:
		changed.emit()
	return true
