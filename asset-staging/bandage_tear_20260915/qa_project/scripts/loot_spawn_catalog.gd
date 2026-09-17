extends RefCounted
## Dungeon-only storage sites, sampled once per scene entry. The hideout is a
## home base and has no random loot candidates; its fixed personal stash is separate.
## Positions and facing
## belong to the level; only occupancy is random. `chance` is the initial roll
## probability, followed by a density cap and a minimum useful loot count.

const CAVE_LAYOUT := preload("res://scripts/cave_layout.gd")


static func map_ids() -> Array[String]:
	return ["reliquary", "blackwater_cave"]


static func occupancy_limits(map_id: String) -> Vector2i:
	return Vector2i(2, 4) if map_ids().has(map_id) else Vector2i.ZERO


static func candidates(map_id: String) -> Array[Dictionary]:
	match map_id:
		"reliquary":
			return _reliquary_sites()
		"blackwater_cave":
			return _cave_sites()
	return []


static func roll(map_id: String, seed_value: int = -1) -> Array[Dictionary]:
	var sites := candidates(map_id)
	var selected: Array[Dictionary] = []
	if sites.is_empty():
		return selected
	var rng := RandomNumberGenerator.new()
	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value
	var occupied: Dictionary = {}
	var vacant: Array[int] = []
	for index in range(sites.size()):
		if rng.randf() < float(sites[index].chance):
			occupied[index] = true
		else:
			vacant.append(index)
	var limits := occupancy_limits(map_id)
	# A vacancy is always left among the authored sites. Fallback choices use
	# the same local RNG so no particular supply or treasure site is guaranteed.
	var maximum := mini(limits.y, sites.size() - 1)
	var minimum := mini(limits.x, maximum)
	while occupied.size() < minimum and not vacant.is_empty():
		var vacant_index := rng.randi_range(0, vacant.size() - 1)
		occupied[vacant[vacant_index]] = true
		vacant.remove_at(vacant_index)
	while occupied.size() > maximum:
		var keys := occupied.keys()
		occupied.erase(keys[rng.randi_range(0, keys.size() - 1)])
	# Preserve authored ordering for stable scene inspection and replay.
	for index in range(sites.size()):
		if occupied.has(index):
			selected.append(sites[index].duplicate(true))
	return selected


static func _site(id: String, room_id: String, title: String, context: String, position: Vector3, yaw: float, variant: String, chance: float, items: Array) -> Dictionary:
	return {
		"id": id,
		"room_id": room_id,
		"title": title,
		"subtitle": context,
		"context": context,
		"position": position,
		"yaw": yaw,
		"model_variant": variant,
		"chance": chance,
		"items": items.duplicate(true),
		# Front is model-local -Z. This open floor point is close enough for the
		# actual timed hand interaction while leaving the storage against a wall.
		"approach_position": position + Vector3.FORWARD.rotated(Vector3.UP, yaw) * 1.35 + Vector3.UP,
	}


static func _reliquary_sites() -> Array[Dictionary]:
	# The previous two containers' combined reward stacks are divided between
	# six believable storage uses. More candidate sites do not duplicate loot.
	return [
		_site("pilgrim_supplies", "entrance", "순례자의 보급 상자", "입구 회랑 서쪽 벽 · 순례자가 내려놓은 장비", Vector3(-8.9, 0, 14.6), -PI / 2, "wooden_crate_01", 0.70, [
			{"id": "linen_bandage", "quantity": 2}, {"id": "weathered_staff", "quantity": 1},
			{"id": "camp_kit", "quantity": 1}, {"id": "water_spellbook", "quantity": 1},
			{"id": "stone_spellbook", "quantity": 1},
			{"id": "surgery_kit", "quantity": 1}, {"id": "splint", "quantity": 1},
		]),
		_site("pilgrim_provisions", "entrance", "순례자의 식량 보관통", "입구 회랑 남쪽 벽 · 식수와 식량을 모아 둔 자리", Vector3(6.0, 0, 15.4), 0.0, "wooden_barrel_01", 0.58, [
			{"id": "lamp_oil", "quantity": 2}, {"id": "raw_meat", "quantity": 2},
			{"id": "edible_mushroom", "quantity": 3}, {"id": "boiled_rainwater", "quantity": 2},
		]),
		_site("altar_attendant_cache", "nave", "제단지기의 보관 상자", "부서진 제단 서쪽 벽 · 의식 도구를 보관하던 자리", Vector3(-8.8, 0, 0.1), -PI / 2, "wooden_crate_02", 0.52, [
			{"id": "black_salt", "quantity": 1}, {"id": "chain_flail", "quantity": 1},
			{"id": "purifying_salt", "quantity": 1}, {"id": "nerve_tonic", "quantity": 1},
		]),
		_site("corridor_guard_supplies", "nave", "회랑 경비대의 장비 상자", "문 안쪽 동쪽 벽 · 통로를 비워 둔 경비 장비 적치장", Vector3(8.9, 0, 6.1), PI / 2, "wooden_crate_02", 0.60, [
			{"id": "hunting_bow", "quantity": 1}, {"id": "wooden_arrow", "quantity": 18},
		]),
		_site("eastern_offerings", "sanctum", "봉인된 성물 상자", "심층 성물실 동쪽 벽 · 귀환문 옆에 봉헌물을 모아 둔 자리", Vector3(8.7, 0, -12.6), PI / 2, "treasure_chest", 0.54, [
			{"id": "silver_chalice", "quantity": 1}, {"id": "rune_fragment", "quantity": 2},
			{"id": "reliquary", "quantity": 1},
		]),
		_site("western_scriptures", "sanctum", "성소의 봉헌 문서함", "심층 성물실 서쪽 벽 · 봉헌 문서를 보관하던 자리", Vector3(-8.8, 0, -12.6), -PI / 2, "treasure_chest", 0.60, [
			{"id": "healing_draught", "quantity": 1}, {"id": "fire_spellbook", "quantity": 1},
			{"id": "ice_spellbook", "quantity": 1}, {"id": "healing_spellbook", "quantity": 1},
			{"id": "restoration_spellbook", "quantity": 1}, {"id": "antidote", "quantity": 1},
		]),
	]


static func _cave_sites() -> Array[Dictionary]:
	# Reuse the authoritative Blender/Godot gameplay reservations. The mine's
	# scattered rock and timber dressing already leaves these five sites clear.
	var profiles := {
		"entry_supplies": ["남쪽 갱도의 원정 보급품", "남쪽 진입 갱도 · 진입로 가장자리에 내려놓은 원정 보급", -PI / 2, "wooden_crate_01", 0.72, [
			{"id": "linen_bandage", "quantity": 3}, {"id": "lamp_oil", "quantity": 3},
			{"id": "pilgrim_ration", "quantity": 3}, {"id": "boiled_rainwater", "quantity": 3},
			{"id": "camp_kit", "quantity": 1}, {"id": "hunting_bow", "quantity": 1},
			{"id": "wooden_arrow", "quantity": 18},
		]],
		# The curved southern rim blocks a player's capsule; face the open
		# northern dry pocket while preserving the reserved container position.
		"drowned_cache": ["익사한 광부의 유품 보관통", "상부 침수 갱도 · 물길에서 떨어진 마른 가장자리의 유품", 0.0, "wooden_barrel_01", 0.58, [
			{"id": "silver_chalice", "quantity": 1}, {"id": "water_spellbook", "quantity": 1},
			{"id": "weathered_staff", "quantity": 1}, {"id": "boiled_rainwater", "quantity": 2},
		]],
		"foreman_cache": ["감독관의 잠긴 궤짝", "감독관 작업실 · 작업대 옆 장비 보관 구역", PI, "wooden_crate_02", 0.66, [
			{"id": "stone_spellbook", "quantity": 1}, {"id": "chain_flail", "quantity": 1},
			{"id": "rune_fragment", "quantity": 3}, {"id": "lamp_oil", "quantity": 2},
		]],
		"store_cache": ["폐창고의 운송 상자", "동쪽 자재 창고 · 기존 화물 더미 옆의 하역 자리", PI, "wooden_crate_01", 0.70, [
			{"id": "reliquary", "quantity": 1}, {"id": "healing_draught", "quantity": 2},
			{"id": "healing_spellbook", "quantity": 1}, {"id": "black_salt", "quantity": 2},
		]],
		"shrine_treasure": ["기둥 성소의 봉헌물", "기둥 성소 · 중앙 참배 길을 비운 동쪽 기둥 옆 봉헌 자리", PI / 2, "treasure_chest", 0.52, [
			{"id": "silver_chalice", "quantity": 2}, {"id": "rune_fragment", "quantity": 4},
			{"id": "fire_spellbook", "quantity": 1}, {"id": "ice_spellbook", "quantity": 1},
		]],
	}
	var result: Array[Dictionary] = []
	for placement: Dictionary in CAVE_LAYOUT.gameplay("chests"):
		var profile: Array = profiles[str(placement.id)]
		result.append(_site(str(placement.id), str(placement.room_id), str(profile[0]), str(profile[1]), placement.position, float(profile[2]), str(profile[3]), float(profile[4]), profile[5]))
	return result
