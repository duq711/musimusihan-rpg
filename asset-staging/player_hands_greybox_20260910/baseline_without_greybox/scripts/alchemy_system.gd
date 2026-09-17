extends RefCounted
class_name AlchemySystem

const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const INVENTORY := preload("res://scripts/inventory_model.gd")
const TURN_SECONDS := 8.0
const AMBIENT_TEMPERATURE := 20.0
const GRIND_STROKES := 3
const MORTAR_CAPACITY := 4
const MAX_HANDFULS := 12
const BOTTLE_ITEM := "alchemy_empty_bottle"

var _bag: ExpeditionInventory
var recipe_id := "red_mending"
var stage := "empty"
var base_id := ""
var temperature := AMBIENT_TEMPERATURE
var heat := 0.0
var cauldron_lowered := false
var boil_turns := 0.0
var hourglass_remaining := 0.0
var hourglass_running := false
var mortar: Array[Dictionary] = []
var ingredients: Array[Dictionary] = []
var distill_progress := 0.0
var elapsed := 0.0
var last_message := "조제서를 읽고 기본 액체를 부으세요."
var last_result: Dictionary = {}
var history: Array[Dictionary] = []
var _stirs: Array[Dictionary] = []
var _scorch_seconds := 0.0
var _last_ingredient_time := 0.0
var _distill_start_turns := 0.0
var _distill_start_temperature := AMBIENT_TEMPERATURE
var _distill_seconds := 0.0
var _ever_distilled := false


func setup(bag: ExpeditionInventory) -> AlchemySystem:
	_bag = bag
	_reset_batch()
	return self


func select_recipe(id: String) -> Dictionary:
	if not CATALOG.RECIPES.has(id):
		return _reply(false, "조제서에 없는 제조법입니다.")
	if stage != "empty" and stage != "finished":
		return _reply(false, "진행 중인 약을 마무리하거나 비운 뒤 제조법을 바꾸세요.")
	_reset_batch()
	recipe_id = id
	return _reply(true, "%s 조제서를 펼쳤습니다." % CATALOG.recipe(id)["name"])


func pour_base(id: String) -> Dictionary:
	if stage != "empty" or not base_id.is_empty():
		return _reply(false, "솥을 먼저 비워야 기본 액체를 부을 수 있습니다.")
	if not CATALOG.BASES.has(id):
		return _reply(false, "선택할 수 없는 기본 액체입니다.")
	var base: Dictionary = CATALOG.BASES[id]
	if not _consume(str(base["item_id"])):
		return _reply(false, "%s이(가) 가방에 없습니다." % base["name"])
	base_id = id
	stage = "brewing"
	_record("base", {"id": id})
	_bag.changed.emit()
	return _reply(true, "%s 한 병을 솥에 부었습니다." % base["name"])


func add_herb(id: String, destination := "cauldron") -> Dictionary:
	if stage != "brewing":
		return _reply(false, "기본 액체를 부은 뒤 약초를 넣으세요.")
	if not CATALOG.HERBS.has(id) or destination not in ["cauldron", "mortar"]:
		return _reply(false, "약초 또는 넣을 도구를 확인하세요.")
	if ingredients.size() + mortar.size() >= MAX_HANDFULS:
		return _reply(false, "솥에 더 넣을 공간이 없습니다. 현재 약을 마무리하거나 비우세요.")
	if destination == "mortar" and mortar.size() >= MORTAR_CAPACITY:
		return _reply(false, "절구에는 네 줌까지만 들어갑니다. 내용물을 먼저 솥에 부으세요.")
	var herb: Dictionary = CATALOG.HERBS[id]
	if not _consume(str(herb["item_id"])):
		return _reply(false, "%s이(가) 가방에 없습니다." % herb["name"])
	var handful := {"id": id, "herb_id": id, "form": "whole", "ground": false, "strokes": 0}
	if destination == "mortar":
		mortar.append(handful)
		_record("mortar_add", {"id": id})
	else:
		_add_to_cauldron(handful)
	_bag.changed.emit()
	return _reply(true, "%s 한 줌을 %s에 넣었습니다." % [herb["name"], "절구" if destination == "mortar" else "솥"])


func grind() -> Dictionary:
	if stage != "brewing" or mortar.is_empty():
		return _reply(false, "절구에 약초를 먼저 넣으세요.")
	var already_ground := true
	for handful in mortar:
		if int(handful["strokes"]) < GRIND_STROKES:
			already_ground = false
			handful["strokes"] = int(handful["strokes"]) + 1
			handful["form"] = "ground" if int(handful["strokes"]) >= GRIND_STROKES else "bruised"
			handful["ground"] = int(handful["strokes"]) >= GRIND_STROKES
	if already_ground:
		return _reply(false, "절구의 약초는 이미 곱게 빻았습니다.")
	_record("grind")
	var minimum := GRIND_STROKES
	for handful in mortar:
		minimum = mini(minimum, int(handful["strokes"]))
	return _reply(true, "절구를 찧었습니다. %d / %d회 · %s" % [minimum, GRIND_STROKES, "곱게 빻음" if minimum == GRIND_STROKES else "아직 거친 약초"])


func pour_mortar() -> Dictionary:
	if stage != "brewing" or mortar.is_empty():
		return _reply(false, "솥에 부을 절구 내용물이 없습니다.")
	var count := mortar.size()
	for handful in mortar:
		_add_to_cauldron(handful)
	mortar.clear()
	return _reply(true, "절구의 약초 %d줌을 솥에 모두 부었습니다." % count)


func pump_bellows() -> Dictionary:
	if stage not in ["brewing", "distilling"]:
		return _reply(false, "솥에 기본 액체를 먼저 부으세요.")
	heat = minf(100.0, heat + 28.0)
	_record("bellows")
	return _reply(true, "풀무를 당겨 불길을 키웠습니다. 불은 시간이 지나면 약해집니다.")


func set_cauldron_lowered(lowered: bool) -> Dictionary:
	if stage not in ["brewing", "distilling"]:
		return _reply(false, "지금은 달일 약이 없습니다.")
	cauldron_lowered = lowered
	_record("lower" if lowered else "raise")
	return _reply(true, "솥을 불 위로 내렸습니다." if lowered else "솥을 올려 가열을 멈춥니다. 내용물은 천천히 식습니다.")


func turn_hourglass() -> Dictionary:
	# The hourglass is independent of both the cauldron and recipe progression.
	hourglass_remaining = TURN_SECONDS
	hourglass_running = true
	_record("hourglass")
	return _reply(true, "모래시계를 뒤집었습니다. 한 회전은 8초입니다.")


func stir() -> Dictionary:
	if stage != "brewing" or ingredients.is_empty():
		return _reply(false, "솥에 약초를 넣은 뒤 저으세요.")
	_stirs.append({"ingredient_count": ingredients.size(), "boil_turns": boil_turns})
	_record("stir")
	return _reply(true, "솥을 천천히 한 번 저었습니다. 지금까지 %d회." % _stirs.size())


func start_distillation() -> Dictionary:
	if stage != "brewing" or ingredients.is_empty():
		return _reply(false, "달일 약초를 넣은 뒤 증류기를 연결하세요.")
	if not mortar.is_empty():
		return _reply(false, "절구에 약초가 남아 있습니다. 먼저 솥에 붓거나 배치를 비우세요.")
	stage = "distilling"
	_ever_distilled = true
	_distill_start_turns = boil_turns
	_distill_start_temperature = temperature
	_record("distill")
	return _reply(true, "증류기를 연결했습니다. 솥을 내려 끓는 동안에만 정수가 모입니다.")


func bottle() -> Dictionary:
	if stage not in ["brewing", "distilling"]:
		return _reply(false, "병에 담을 내용물이 없습니다. 새 배치를 시작하세요.")
	if stage == "distilling" and distill_progress < 1.0:
		return _reply(false, "증류가 끝나지 않았습니다. 솥을 내려 불을 유지하세요.")
	var recipe := CATALOG.recipe(recipe_id)
	var liquor := str(recipe.get("product_type", "medicine")) == "liquor"
	if liquor and (stage != "distilling" or not _ever_distilled):
		return _reply(false, "술은 증류를 마친 뒤 병에 담을 수 있습니다. 증류기를 연결하세요.")
	var grade := _grade(true)
	var quality := str(grade["quality"])
	if quality == "failed":
		stage = "finished"
		cauldron_lowered = false
		last_result = {"accepted": true, "quality": "failed", "item_id": "", "quantity": 0, "score": grade["score"], "mistakes": grade["mistakes"]}
		_record("failed")
		return _reply(true, "제조 실패 · 배합이 망가져 버렸습니다. 사용한 재료는 돌려받지 못합니다.", last_result)
	var item_id := str((recipe["outputs"] as Dictionary)[quality])
	var quantity := 2 if quality == "strong" else 1
	if _bag == null or _bag.count_item(BOTTLE_ITEM) < quantity:
		return _reply(false, "완성품을 담을 빈 약병 %d개가 필요합니다. 내용물은 솥에 남아 있습니다." % quantity)
	# Capacity is evaluated after the empty bottle leaves the bag; no mutation or
	# partial output is committed if all finished doses do not fit.
	var candidate := INVENTORY.new()
	candidate.slots.assign(_bag.slots.duplicate(true))
	candidate.remove_item(BOTTLE_ITEM, quantity, false)
	if not candidate.can_add(item_id, quantity):
		return _reply(false, "완성품을 전부 담을 가방 공간이 부족합니다. 내용물과 빈 병은 보존됩니다.")
	candidate.add_item(item_id, quantity, false)
	_bag.slots.assign(candidate.slots)
	stage = "finished"
	cauldron_lowered = false
	last_result = {"accepted": true, "quality": quality, "item_id": item_id, "quantity": quantity, "score": grade["score"], "mistakes": grade["mistakes"]}
	_record("bottle", {"quality": quality, "item_id": item_id, "quantity": quantity})
	_bag.changed.emit()
	return _reply(true, "%s %d병을 완성했습니다." % [INVENTORY.get_item_name(item_id), quantity], last_result)


func discard() -> Dictionary:
	_reset_batch()
	return _reply(true, "솥과 절구를 비웠습니다. 사용한 재료는 돌려받지 못합니다. 새 배치를 시작하세요.")


func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# Small fixed upper steps keep thermal integration and deadlines stable even
	# during a long rendered frame or deterministic headless time advancement.
	var remaining := minf(delta, 3600.0)
	while remaining > 0.000001:
		var step := minf(remaining, 0.05)
		remaining -= step
		elapsed += step
		if hourglass_running:
			hourglass_remaining = maxf(0.0, hourglass_remaining - step)
			if hourglass_remaining <= 0.00001:
				hourglass_running = false
				hourglass_remaining = 0.0
		if stage not in ["brewing", "distilling"]:
			continue
		heat = maxf(0.0, heat - 2.0 * step)
		if cauldron_lowered:
			var target := AMBIENT_TEMPERATURE + heat * 1.4
			temperature = move_toward(temperature, target, (4.0 + heat * 0.12) * step)
		else:
			temperature = move_toward(temperature, AMBIENT_TEMPERATURE, 10.0 * step)
		if _is_boiling():
			if stage == "brewing":
				boil_turns += step / TURN_SECONDS
			else:
				_distill_seconds += step
				var required := float(CATALOG.recipe(recipe_id).get("distill_turns", 1.5)) * TURN_SECONDS
				distill_progress = minf(1.0, _distill_seconds / required)
		if stage == "brewing" and temperature > _boiling_point() + 18.0:
			_scorch_seconds += step


func snapshot() -> Dictionary:
	var grade := _grade(false)
	var recipe := CATALOG.recipe(recipe_id)
	return {
		"recipe_id": recipe_id, "stage": stage, "base_id": base_id, "temperature": temperature, "heat": heat,
		"cauldron_lowered": cauldron_lowered, "boiling": _is_boiling(), "boil_turns": boil_turns,
		"hourglass_remaining": hourglass_remaining, "hourglass_running": hourglass_running,
		"mortar": mortar.duplicate(true), "ingredients": ingredients.duplicate(true), "quality": grade["quality"],
		"distill_progress": distill_progress, "last_message": last_message, "last_result": last_result.duplicate(true),
		"history": history.duplicate(true), "turn_seconds": TURN_SECONDS, "boiling_point": _boiling_point(),
		"recipe_steps": recipe.get("steps", []).duplicate(), "mistakes": grade["mistakes"], "score": grade["score"],
		"finish_method": recipe.get("finish", "bottle"), "distill_ready": stage == "distilling" and distill_progress >= 1.0,
		"elapsed": elapsed, "stirs": _stirs.size(), "steep_seconds": maxf(0.0, elapsed - _last_ingredient_time),
	}


static func trial_supplies() -> Dictionary:
	var result := {BOTTLE_ITEM: 8}
	for base: Dictionary in CATALOG.BASES.values():
		result[str(base["item_id"])] = 4
	for herb: Dictionary in CATALOG.HERBS.values():
		result[str(herb["item_id"])] = 12
	return result


func _consume(item_id: String) -> bool:
	return _bag != null and _bag.remove_item(item_id, 1, false)


func _add_to_cauldron(handful: Dictionary) -> void:
	var entry := handful.duplicate(true)
	entry["boil_turns"] = boil_turns
	entry["temperature"] = temperature
	entry["elapsed"] = elapsed
	ingredients.append(entry)
	_last_ingredient_time = elapsed
	_record("ingredient", entry)


func _boiling_point() -> float:
	return float((CATALOG.BASES.get(base_id, {}) as Dictionary).get("boiling_point", 100.0))


func _is_boiling() -> bool:
	return stage in ["brewing", "distilling"] and cauldron_lowered and temperature >= _boiling_point()


func _grade(finishing: bool) -> Dictionary:
	if stage == "finished" and not last_result.is_empty():
		return {"quality": last_result["quality"], "score": last_result["score"], "mistakes": last_result["mistakes"].duplicate()}
	var recipe := CATALOG.recipe(recipe_id)
	var mistakes: Array[String] = []
	var penalty := 0.0
	if not base_id.is_empty() and base_id != str(recipe.get("base", "")):
		penalty += 70.0
		mistakes.append("기본 액체가 조제서와 다릅니다.")
	var milestones: Array = recipe.get("milestones", [])
	for index in range(ingredients.size()):
		var entry := ingredients[index]
		if index >= milestones.size():
			penalty += 25.0
			mistakes.append("약초를 필요 이상으로 넣었습니다.")
			continue
		var expected: Dictionary = milestones[index]
		if str(entry["id"]) != str(expected["herb"]):
			penalty += 25.0
			mistakes.append("%d번째 약초의 종류 또는 투입 순서가 다릅니다." % (index + 1))
		if str(entry["form"]) != str(expected["form"]):
			penalty += 12.0
			mistakes.append("%d번째 약초의 빻기 상태가 다릅니다." % (index + 1))
		var timing_error := absf(float(entry["boil_turns"]) - float(expected.get("boil_before", 0.0)))
		if timing_error > 0.35:
			penalty += minf(30.0, (timing_error - 0.35) * 20.0)
			mistakes.append("%d번째 약초를 넣기 전 끓인 시간이 다릅니다." % (index + 1))
		if float(entry["temperature"]) > float(expected.get("max_temp", 999.0)) + 3.0:
			penalty += 18.0
			mistakes.append("%d번째 약초를 충분히 식히지 않고 넣었습니다." % (index + 1))
	if finishing:
		var missing := maxi(0, milestones.size() - ingredients.size())
		if missing > 0:
			penalty += missing * 30.0
			mistakes.append("약초가 %d줌 부족합니다." % missing)
		if not mortar.is_empty():
			penalty += mortar.size() * 20.0
			mistakes.append("절구의 약초를 솥에 붓지 않았습니다.")
		var actual_turns := _distill_start_turns if _ever_distilled else boil_turns
		var boil_error := absf(actual_turns - float(recipe.get("boil_target", 0.0)))
		if boil_error > 0.35:
			penalty += minf(50.0, (boil_error - 0.35) * 20.0)
			mistakes.append("달인 시간이 조제서와 다릅니다 (%.1f / %.1f회전)." % [actual_turns, recipe.get("boil_target", 0.0)])
		if (str(recipe.get("finish", "bottle")) == "distill") != _ever_distilled:
			penalty += 65.0
			mistakes.append("직접 담기와 증류 중 잘못된 마무리 방법을 사용했습니다.")
		if not _ever_distilled and temperature > float(recipe.get("finish_max_temp", 999.0)) + 3.0:
			penalty += 20.0
			mistakes.append("완성약을 충분히 식히지 않았습니다.")
		var effective_stirs := 0
		for stirring in _stirs:
			if int(stirring["ingredient_count"]) >= int(recipe.get("stir_after", 0)):
				effective_stirs += 1
			else:
				penalty += 4.0
		if effective_stirs < int(recipe.get("stirs", 0)):
			penalty += (int(recipe.get("stirs", 0)) - effective_stirs) * 12.0
			mistakes.append("모든 약초를 넣은 뒤 저은 횟수가 부족합니다.")
		if _stirs.size() > int(recipe.get("stirs", 0)) + 2:
			penalty += 12.0
			mistakes.append("약을 지나치게 많이 저었습니다.")
		if elapsed - _last_ingredient_time + 0.05 < float(recipe.get("steep_seconds", 0.0)):
			penalty += 25.0
			mistakes.append("마지막 약초를 넣은 뒤 충분히 우려내지 않았습니다.")
	if _scorch_seconds > 2.0:
		penalty += minf(70.0, (_scorch_seconds - 2.0) * 3.0)
		mistakes.append("지나치게 강한 불에 약초가 눋습니다.")
	var quality := "strong" if penalty < 10.0 else ("normal" if penalty < 28.0 else ("weak" if penalty < 55.0 else "failed"))
	return {"quality": quality, "score": maxf(0.0, 100.0 - penalty), "mistakes": mistakes}


func _record(action: String, details: Dictionary = {}) -> void:
	var entry := {"action": action, "elapsed": elapsed, "temperature": temperature, "boil_turns": boil_turns}
	entry.merge(details, true)
	history.append(entry)
	if history.size() > 120:
		history.pop_front()


func _reply(accepted: bool, message: String, data: Dictionary = {}) -> Dictionary:
	last_message = message
	var reply := data.duplicate(true)
	reply["accepted"] = accepted
	reply["message"] = message
	return reply


func _reset_batch() -> void:
	stage = "empty"
	base_id = ""
	temperature = AMBIENT_TEMPERATURE
	heat = 0.0
	cauldron_lowered = false
	boil_turns = 0.0
	hourglass_remaining = 0.0
	hourglass_running = false
	mortar.clear()
	ingredients.clear()
	distill_progress = 0.0
	elapsed = 0.0
	last_result.clear()
	history.clear()
	_stirs.clear()
	_scorch_seconds = 0.0
	_last_ingredient_time = 0.0
	_distill_start_turns = 0.0
	_distill_start_temperature = AMBIENT_TEMPERATURE
	_distill_seconds = 0.0
	_ever_distilled = false
