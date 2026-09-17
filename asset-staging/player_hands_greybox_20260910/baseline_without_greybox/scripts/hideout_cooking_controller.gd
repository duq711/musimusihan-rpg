extends Node
class_name HideoutCookingController

signal opened()
signal cooking_started()
signal cooking_finished(result: Dictionary)
signal closed(reason: String, restore_controls: bool)

const COOKING := preload("res://scripts/camp_cooking_catalog.gd")
const OVERLAY := preload("res://scripts/hideout_cooking_overlay.gd")

var state := "closed"
var game: Node
var player: DungeonPlayer
var inventory: ExpeditionInventory
var visual: Node3D
var overlay: CampOverlay
var cooking_elapsed := 0.0
var cooking_duration := 0.0
var last_result: Dictionary = {}

var _recipe_id := ""
var _active_recipe: Dictionary = {}
var _resources_spent: Dictionary = {}
var _survival_advanced := 0.0
var _status := ""
var _operation_generation := 0
var _transaction_active := false


func setup(game_ref: Node, player_ref: DungeonPlayer, inventory_ref: ExpeditionInventory, visual_ref: Node3D) -> void:
	if game != game_ref or player != player_ref or inventory != inventory_ref or visual != visual_ref:
		close_kitchen("", false)
	_disconnect_inventory()
	game = game_ref
	player = player_ref
	inventory = inventory_ref
	visual = visual_ref
	_connect_inventory()
	refresh()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = OVERLAY.new()
	overlay.name = "HideoutCookingOverlay"
	add_child(overlay)
	overlay.action_requested.connect(_on_action_requested)
	overlay.leave_requested.connect(close_kitchen)
	overlay.hide_camp()
	_connect_inventory()
	refresh()


func _exit_tree() -> void:
	close_kitchen("", false)
	_disconnect_inventory()


func _process(delta: float) -> void:
	if is_open():
		var reason := _scene_failure()
		if not reason.is_empty():
			close_kitchen(_reason_message(reason), reason != "dead" and reason != "unavailable")
			return
	advance_cooking(delta)


func is_open() -> bool:
	return state != "closed"


func open_kitchen() -> Dictionary:
	if is_open() or _transaction_active:
		return _failure("already_open")
	if not is_inside_tree() or get_tree().paused:
		return _failure("paused")
	var reason := _scene_failure()
	if not reason.is_empty():
		return _failure(reason)
	_operation_generation += 1
	state = "planning"
	cooking_elapsed = 0.0
	cooking_duration = 0.0
	_survival_advanced = 0.0
	_recipe_id = ""
	_active_recipe = {}
	_resources_spent = {}
	last_result = {}
	_status = "불 위의 가마솥과 꼬치로 요리합니다. 완성한 음식은 바로 먹으며, 조리를 중단하면 사용한 재료는 반환되지 않습니다."
	refresh()
	if is_instance_valid(overlay):
		overlay.show_camp()
	opened.emit()
	return {"accepted": true, "message": "화롯불 부엌을 열었습니다."}


func start_recipe(recipe_id: String) -> Dictionary:
	var reason := _recipe_failure(recipe_id)
	if not reason.is_empty():
		return _failure(reason)
	var recipe := COOKING.get_recipe(recipe_id)
	var resources: Dictionary = (recipe.get("resources", {}) as Dictionary).duplicate(true)
	var previous_slots: Array[Dictionary] = inventory.slots.duplicate(true)
	_transaction_active = true
	for item_id: String in resources:
		if not inventory.remove_item(item_id, int(resources[item_id]), false):
			inventory.slots.assign(previous_slots)
			_transaction_active = false
			return _failure("resources_missing")
	# All ingredients are removed before listeners run. Commit the operation
	# first so a repeated click or inventory callback cannot spend them twice.
	_operation_generation += 1
	var operation := _operation_generation
	state = "cooking"
	_recipe_id = recipe_id
	_active_recipe = recipe
	_resources_spent = resources.duplicate(true)
	cooking_elapsed = 0.0
	cooking_duration = float(recipe.duration)
	_survival_advanced = 0.0
	last_result = {}
	_status = "%s 조리 중 · 완성하면 바로 먹습니다." % str(recipe.title)
	_transaction_active = false
	inventory.changed.emit()
	if operation != _operation_generation or state != "cooking":
		return {"accepted": true, "interrupted": true, "recipe_id": recipe_id, "action_id": COOKING.action_id(recipe_id), "resources_spent": resources, "message": "재료를 준비한 뒤 조리가 중단되었습니다."}
	refresh()
	cooking_started.emit()
	return {"accepted": true, "recipe_id": recipe_id, "action_id": COOKING.action_id(recipe_id), "duration": float(recipe.duration), "resources_spent": resources, "message": "%s 조리를 시작했습니다." % str(recipe.title)}


func advance_cooking(delta: float) -> void:
	# The hideout keeps the world paused while this always-processing controller
	# advances only the recipe clock, with the same survival cost as camp food.
	if state != "cooking" or _transaction_active or not is_inside_tree() or not is_finite(delta):
		return
	var reason := _scene_failure()
	if not reason.is_empty():
		close_kitchen(_reason_message(reason), reason != "dead" and reason != "unavailable")
		return
	var elapsed := minf(maxf(0.0, delta), maxf(0.0, cooking_duration - cooking_elapsed))
	if elapsed <= 0.0:
		return
	cooking_elapsed = minf(cooking_duration, cooking_elapsed + elapsed)
	var target_survival := float(_active_recipe.survival) * cooking_elapsed / cooking_duration
	var survival_delta := maxf(0.0, target_survival - _survival_advanced)
	_survival_advanced = target_survival
	ExpeditionSession.advance_survival(survival_delta)
	_refresh_player_hud()
	if cooking_elapsed >= cooking_duration - 0.000001:
		_finish_cooking()
	else:
		refresh()


func close_kitchen(reason := "", restore_controls := true) -> void:
	if state == "closed":
		return
	var was_cooking := state == "cooking"
	_operation_generation += 1
	state = "closed"
	if was_cooking:
		last_result = {"accepted": false, "cancelled": true, "completed": false, "cooked_and_eaten": false, "recipe_id": _recipe_id, "action_id": COOKING.action_id(_recipe_id), "resources_spent": _resources_spent.duplicate(true), "survival_seconds": _survival_advanced, "elapsed": cooking_elapsed, "message": reason if not reason.is_empty() else "조리를 중단했습니다. 사용한 재료는 반환되지 않습니다."}
	if is_instance_valid(overlay):
		overlay.hide_camp()
	_update_visual()
	closed.emit(reason, restore_controls)


func refresh() -> void:
	_update_visual()
	if is_instance_valid(overlay):
		overlay.set_snapshot(get_snapshot())


func get_snapshot() -> Dictionary:
	var counts: Dictionary = {}
	var actions: Array[Dictionary] = []
	for recipe_id: String in COOKING.ordered_recipe_ids():
		var recipe := COOKING.get_recipe(recipe_id)
		var resources: Dictionary = (recipe.get("resources", {}) as Dictionary).duplicate(true)
		var cost_parts: Array[String] = []
		var ingredient_parts: Array[String] = []
		for item_id: String in resources:
			var count := inventory.count_item(item_id) if inventory != null else 0
			counts[item_id] = count
			cost_parts.append("%s %d" % [ExpeditionInventory.get_item_name(item_id), int(resources[item_id])])
			ingredient_parts.append("%s %d / %d" % [ExpeditionInventory.get_item_name(item_id), count, int(resources[item_id])])
		var reason := _recipe_failure(recipe_id)
		actions.append({"id": COOKING.action_id(recipe_id), "recipe_id": recipe_id, "category": "cooking", "title": str(recipe.title), "description": str(recipe.description), "duration": float(recipe.duration), "resources": resources, "cost": " · ".join(cost_parts), "ingredient_text": "보유 / 필요 · " + " · ".join(ingredient_parts), "enabled": reason.is_empty(), "reason": "" if reason.is_empty() else _reason_message(reason)})
	var conditions: Array[String] = []
	for condition_id: String in ExpeditionSession.active_conditions:
		conditions.append(ExpeditionSession.get_condition_display_name(condition_id))
	return {"state": "resting" if state == "cooking" else state, "kitchen_state": state, "is_cooking": state == "cooking", "recipe_id": _recipe_id, "active_action_id": COOKING.action_id(_recipe_id) if not _recipe_id.is_empty() else "", "action_title": str(_active_recipe.get("title", "")), "health": player.health if is_instance_valid(player) else 0.0, "max_health": DungeonPlayer.MAX_HEALTH, "stamina": player.stamina if is_instance_valid(player) else 0.0, "max_stamina": DungeonPlayer.MAX_STAMINA, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress, "max_stress": StressProfile.MAX_STRESS, "stress_stage": StressProfile.stage_name(ExpeditionSession.stress), "conditions": " · ".join(conditions) if not conditions.is_empty() else "안정", "inventory_counts": counts, "progress": _progress(), "survival_seconds": _survival_advanced, "status": _status, "actions": actions}


func _finish_cooking() -> void:
	if state != "cooking" or _transaction_active:
		return
	_transaction_active = true
	# Leave the active state before applying effects or emitting the completion
	# signal. A listener can never award the same dish a second time.
	state = "planning"
	var healed := player.restore_health(float(_active_recipe.health))
	var before_stamina := player.stamina
	player.stamina = minf(DungeonPlayer.MAX_STAMINA, player.stamina + float(_active_recipe.stamina))
	var restored_stamina := player.stamina - before_stamina
	var needs := ExpeditionSession.restore_needs(float(_active_recipe.hunger), float(_active_recipe.thirst))
	var stress_relieved := ExpeditionSession.relieve_stress(float(_active_recipe.stress))
	_status = "%s 조리·식사 완료 · 체력 +%d · 기력 +%d · 포만감 +%d · 수분 +%d · 스트레스 -%d" % [_active_recipe.title, roundi(healed), roundi(restored_stamina), roundi(float(needs.hunger)), roundi(float(needs.thirst)), roundi(stress_relieved)]
	last_result = {"accepted": true, "completed": true, "cooked_and_eaten": true, "recipe_id": _recipe_id, "action_id": COOKING.action_id(_recipe_id), "resources_spent": _resources_spent.duplicate(true), "health_restored": healed, "stamina_restored": restored_stamina, "hunger_restored": float(needs.hunger), "thirst_restored": float(needs.thirst), "stress_relieved": stress_relieved, "survival_seconds": _survival_advanced, "elapsed": cooking_elapsed, "message": _status}
	_refresh_player_hud()
	_transaction_active = false
	refresh()
	cooking_finished.emit(last_result.duplicate(true))


func _recipe_failure(recipe_id: String) -> String:
	if _transaction_active or state == "cooking":
		return "busy"
	if state != "planning":
		return "not_open"
	var recipe := COOKING.get_recipe(recipe_id)
	if recipe.is_empty() or float(recipe.get("duration", 0.0)) <= 0.0:
		return "invalid_recipe"
	var reason := _scene_failure()
	if not reason.is_empty():
		return reason
	var useful := (float(recipe.health) > 0.0 and player.health < DungeonPlayer.MAX_HEALTH) or (float(recipe.stamina) > 0.0 and player.stamina < DungeonPlayer.MAX_STAMINA) or (float(recipe.hunger) > 0.0 and ExpeditionSession.hunger < ExpeditionSession.MAX_NEED) or (float(recipe.thirst) > 0.0 and ExpeditionSession.thirst < ExpeditionSession.MAX_NEED) or (float(recipe.stress) > 0.0 and ExpeditionSession.stress > 0.0)
	if not useful:
		return "no_effect"
	if inventory == null:
		return "resources_missing"
	for item_id: String in recipe.resources:
		if inventory.count_item(item_id) < int(recipe.resources[item_id]):
			return "resources_missing"
	return ""


func _scene_failure() -> String:
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion():
		return "unavailable"
	if not is_instance_valid(player) or player.health <= 0.0 or player.combat_state == DungeonPlayer.CombatState.DEAD or player.is_queued_for_deletion():
		return "dead"
	if not player.is_inside_tree() or not player.safe_zone_mode:
		return "unavailable"
	if not bool(game.get("brazier_lit")):
		return "fire_unlit"
	return ""


func _on_action_requested(action_id: String) -> void:
	if action_id.begins_with("cook:"):
		start_recipe(action_id.trim_prefix("cook:"))


func _progress() -> float:
	return clampf(cooking_elapsed / cooking_duration, 0.0, 1.0) if cooking_duration > 0.0 else 0.0


func _update_visual() -> void:
	if is_instance_valid(visual) and visual.has_method("set_cooking"):
		visual.call("set_cooking", _recipe_id, _progress(), state == "cooking")


func _refresh_player_hud() -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(player.hud):
		player.hud.update_stamina(player.stamina, DungeonPlayer.MAX_STAMINA)
	player._refresh_survival_hud()


func _connect_inventory() -> void:
	if is_inside_tree() and inventory != null and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)


func _disconnect_inventory() -> void:
	if inventory != null and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)


func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "message": _reason_message(reason)}


func _reason_message(reason: String) -> String:
	return str({"already_open": "이미 화롯불 부엌을 열었습니다.", "paused": "다른 메뉴를 닫은 뒤 요리하세요.", "dead": "쓰러진 상태에서는 요리할 수 없습니다.", "unavailable": "은신처 화롯불 곁에서 요리할 수 있습니다.", "fire_unlit": "화롯불을 먼저 밝혀야 요리할 수 있습니다.", "busy": "조리 중에는 다른 요리를 시작할 수 없습니다.", "not_open": "먼저 화롯불 부엌을 여세요.", "invalid_recipe": "알 수 없는 요리입니다.", "no_effect": "회복할 상태가 없습니다.", "resources_missing": "요리 재료가 부족합니다. 보유 / 필요 수량을 확인하세요."}.get(reason, "지금은 요리할 수 없습니다."))
