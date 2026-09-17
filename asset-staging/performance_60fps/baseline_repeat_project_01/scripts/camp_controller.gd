extends Node
class_name DungeonCamp

signal opened()
signal rest_started()
signal rest_finished(result: Dictionary)
signal closed(reason: String, restore_controls: bool)

const VISUALS := preload("res://scripts/camp_visuals.gd")
const COOKING := preload("res://scripts/camp_cooking_catalog.gd")
const ACTIONS := {
	"rest": {"title": "경계 휴식", "duration": 8.0, "survival": 60.0, "health": 20.0, "stamina": 70.0, "warmth": 1, "resources": {}, "description": "체력 20 · 기력 70 회복. 게임 시간 60초가 지나며 상태이상 시간도 흐릅니다."},
	"meal": {"title": "식사 휴식", "duration": 14.0, "survival": 180.0, "health": 45.0, "stamina": 100.0, "warmth": 2, "resources": {"pilgrim_ration": 1, "boiled_rainwater": 1}, "description": "체력 45 · 기력 최대 · 포만감/수분 회복. 게임 시간 180초와 상태이상 시간이 흐릅니다."},
	"treat": {"title": "응급처치", "duration": 6.0, "survival": 30.0, "health": 18.0, "stamina": 0.0, "warmth": 1, "resources": {"linen_bandage": 1}, "description": "체력 18 회복 · 출혈 해소. 게임 시간 30초와 나머지 상태이상 시간이 흐릅니다."},
}
const OPEN_ENEMY_RADIUS := 8.0
const REST_ENEMY_RADIUS := 6.0
const WORLD_LAYER := 2
const INVENTORY_IDS := ["camp_kit", "pilgrim_ration", "boiled_rainwater", "linen_bandage", "raw_meat", "edible_mushroom"]

var state := "closed"
var warmth := 3
var kit_spent := false
var rest_elapsed := 0.0
var rest_duration := 0.0
var last_result: Dictionary = {}
var camp_visual: Node3D
var overlay: Node
var game: Node
var player: DungeonPlayer
var inventory: ExpeditionInventory

var _action_id := ""
var _camp_position := Vector3.ZERO
var _player_position := Vector3.ZERO
var _rest_start_health := 0.0
var _survival_advanced := 0.0
var _visual_time := 0.0
var _status := "평평하고 안전한 곳에서 짧게 쉬어갑니다."


func setup(game_ref: Node, player_ref: DungeonPlayer, inventory_ref: ExpeditionInventory) -> void:
	if inventory != inventory_ref and is_open():
		cancel_camp("", false)
	if inventory != null and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	game = game_ref
	player = player_ref
	inventory = inventory_ref
	if is_inside_tree() and inventory != null and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)
	refresh()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var overlay_script := load("res://scripts/camp_overlay.gd") as Script
	if overlay_script != null:
		overlay = overlay_script.new()
		add_child(overlay)
		overlay.action_requested.connect(start_action)
		overlay.leave_requested.connect(cancel_camp)
		overlay.hide_camp()
	if inventory != null and not inventory.changed.is_connected(refresh):
		inventory.changed.connect(refresh)


func _exit_tree() -> void:
	if inventory != null and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	_dispose_visual()


func _process(delta: float) -> void:
	if state == "closed":
		return
	if not get_tree().paused:
		_visual_time += maxf(0.0, delta)
		VISUALS.animate(camp_visual, _visual_time, warmth)
	advance_rest(delta)


func is_open() -> bool:
	return state != "closed"


func open_camp() -> Dictionary:
	if state != "closed":
		return _failure("already_open")
	if not is_inside_tree() or get_tree().paused:
		return _failure("paused")
	if is_instance_valid(game) and game.has_method("_camp_open_failure"):
		var scene_reason := str(game.call("_camp_open_failure"))
		if not scene_reason.is_empty():
			return _failure(scene_reason)
	var reason := _player_failure()
	if not reason.is_empty():
		return _failure(reason)
	if _enemy_near(OPEN_ENEMY_RADIUS):
		return _failure("enemy_nearby")
	var placement := _find_placement()
	if not bool(placement.get("accepted", false)):
		return _failure(str(placement.get("reason", "blocked_space")))
	_camp_position = placement.position
	_player_position = player.global_position
	warmth = 3
	kit_spent = false
	rest_elapsed = 0.0
	rest_duration = 0.0
	_action_id = ""
	last_result = {}
	_status = "첫 휴식·요리 시작 때 야영 도구 1개를 사용합니다. 요리는 완료하면 바로 먹으며, 중단하면 사용한 재료는 반환되지 않습니다."
	state = "planning"
	camp_visual = VISUALS.create_camp()
	game.add_child(camp_visual)
	camp_visual.global_position = _camp_position
	camp_visual.global_rotation.y = player.global_rotation.y
	refresh()
	if is_instance_valid(overlay):
		overlay.show_camp()
	opened.emit()
	return {"accepted": true, "position": _camp_position, "message": "야영 계획을 펼쳤습니다."}


func start_action(id: String) -> Dictionary:
	var reason := _action_failure(id)
	if not reason.is_empty():
		return _failure(reason)
	var action := get_action_definition(id)
	var resources := _required_resources(id)
	var previous_slots: Array[Dictionary] = inventory.slots.duplicate(true)
	for item_id: String in resources:
		if not inventory.remove_item(item_id, int(resources[item_id]), false):
			inventory.slots.assign(previous_slots)
			return _failure("resources_missing")
	# Commit state before notifying inventory/UI listeners; re-entrant requests
	# now see an active rest and cannot consume resources or start twice.
	warmth -= int(action.warmth)
	kit_spent = true
	state = "resting"
	_action_id = id
	rest_elapsed = 0.0
	rest_duration = float(action.duration)
	_survival_advanced = 0.0
	_rest_start_health = player.health
	last_result = {}
	_status = "%s %s · 위험이 다가오면 즉시 중단됩니다." % [str(action.title), "조리 중" if id.begins_with("cook:") else "중"]
	inventory.changed.emit()
	if state != "resting" or _action_id != id:
		return {"accepted": true, "interrupted": true, "action_id": id, "resources_spent": resources.duplicate(true), "warmth_spent": int(action.warmth), "message": "보급품을 준비한 뒤 휴식이 중단되었습니다."}
	refresh()
	rest_started.emit()
	return {"accepted": true, "action_id": id, "duration": rest_duration, "resources_spent": resources.duplicate(true), "warmth_spent": int(action.warmth), "message": _status}


func advance_rest(delta: float) -> void:
	if state != "resting" or not is_inside_tree() or get_tree().paused or not is_finite(delta):
		return
	if not is_instance_valid(player) or player.combat_state == DungeonPlayer.CombatState.DEAD or player.health <= 0.0:
		cancel_camp("사망하여 야영을 중단했습니다.", false)
		return
	if player.health < _rest_start_health - 0.00001:
		cancel_camp("피격으로 야영을 중단했습니다.")
		return
	if _enemy_near(REST_ENEMY_RADIUS):
		cancel_camp("적이 가까이 다가와 야영을 중단했습니다.")
		return
	if _unsafe_trap_near(_camp_position):
		cancel_camp("가까운 함정이 활성화되어 야영을 중단했습니다.")
		return
	if player.global_position.distance_to(_player_position) > 0.5 or player.current_trap != null or player.safe_zone_mode:
		cancel_camp("야영 장소를 벗어나 휴식을 중단했습니다.")
		return
	var elapsed := minf(maxf(0.0, delta), maxf(0.0, rest_duration - rest_elapsed))
	if elapsed <= 0.0:
		return
	rest_elapsed = minf(rest_duration, rest_elapsed + elapsed)
	var target_survival := float(get_action_definition(_action_id).survival) * rest_elapsed / rest_duration
	var survival_delta := maxf(0.0, target_survival - _survival_advanced)
	_survival_advanced = target_survival
	ExpeditionSession.advance_survival(survival_delta)
	_refresh_player_hud()
	if rest_elapsed >= rest_duration - 0.000001:
		_finish_rest()
	else:
		refresh()


func _finish_rest() -> void:
	if state != "resting":
		return
	var id := _action_id
	var action := get_action_definition(id)
	var cooking := id.begins_with("cook:")
	state = "planning"
	var healed := player.restore_health(float(action.health))
	var before_stamina := player.stamina
	player.stamina = minf(DungeonPlayer.MAX_STAMINA, player.stamina + float(action.stamina))
	var restored_stamina := player.stamina - before_stamina
	var needs := {"hunger": 0.0, "thirst": 0.0}
	var cleared := false
	if id == "meal":
		needs = ExpeditionSession.restore_needs(float(ExpeditionInventory.get_item_definition("pilgrim_ration").get("amount", 0.0)), float(ExpeditionInventory.get_item_definition("boiled_rainwater").get("amount", 0.0)))
	elif id == "treat":
		cleared = ExpeditionSession.clear_condition("bleeding")
	elif cooking:
		needs = ExpeditionSession.restore_needs(float(action.hunger), float(action.thirst))
	var stress_relieved := ExpeditionSession.relieve_stress(float(action.get("stress", StressProfile.CAMP_RELIEF.get(id, 0.0))))
	_status = "%s 완료 · 체력 +%d · 기력 +%d · 스트레스 -%d%s" % [action.title, roundi(healed), roundi(restored_stamina), roundi(stress_relieved), " · 출혈 해소" if cleared else ""]
	if cooking:
		_status = "%s 조리·식사 완료 · 체력 +%d · 기력 +%d · 포만감 +%d · 수분 +%d · 스트레스 -%d" % [action.title, roundi(healed), roundi(restored_stamina), roundi(float(needs.hunger)), roundi(float(needs.thirst)), roundi(stress_relieved)]
	last_result = {"accepted": true, "completed": true, "action_id": id, "health_restored": healed, "stamina_restored": restored_stamina, "hunger_restored": float(needs.hunger), "thirst_restored": float(needs.thirst), "stress_relieved": stress_relieved, "bleeding_cleared": cleared, "survival_seconds": _survival_advanced, "elapsed": rest_elapsed, "message": _status}
	if cooking:
		last_result["recipe_id"] = str(action.recipe_id)
		last_result["cooked_and_eaten"] = true
	_refresh_player_hud()
	refresh()
	rest_finished.emit(last_result.duplicate(true))


func cancel_camp(reason := "", restore_controls := true) -> void:
	if state == "closed":
		return
	var was_resting := state == "resting"
	state = "closed"
	if was_resting:
		last_result = {"accepted": false, "cancelled": true, "action_id": _action_id, "survival_seconds": _survival_advanced, "elapsed": rest_elapsed, "message": reason if not reason.is_empty() else "휴식을 중단했습니다. 이미 사용한 물품과 온기는 반환되지 않습니다."}
	if is_instance_valid(overlay):
		overlay.hide_camp()
	_dispose_visual()
	closed.emit(reason, restore_controls)


func refresh() -> void:
	if is_instance_valid(camp_visual):
		VISUALS.set_cooking(camp_visual, _action_id.trim_prefix("cook:"), clampf(rest_elapsed / rest_duration, 0.0, 1.0) if rest_duration > 0.0 else 0.0, state == "resting" and _action_id.begins_with("cook:"))
	if is_instance_valid(overlay):
		overlay.set_snapshot(get_snapshot())


func get_snapshot() -> Dictionary:
	var counts: Dictionary = {}
	for id: String in INVENTORY_IDS:
		counts[id] = inventory.count_item(id) if inventory != null else 0
	var conditions: Array[String] = []
	for id: String in ExpeditionSession.active_conditions:
		conditions.append(ExpeditionSession.get_condition_display_name(id))
	var actions: Array[Dictionary] = []
	for id: String in ordered_action_ids():
		var definition := get_action_definition(id)
		var cooking := id.begins_with("cook:")
		var reason := _action_failure(id)
		var cost_parts: Array[String] = ["온기 %d" % int(definition.warmth)]
		var resources := _required_resources(id)
		var ingredient_parts: Array[String] = []
		for item_id: String in resources:
			cost_parts.append("%s %d" % [ExpeditionInventory.get_item_name(item_id), int(resources[item_id])])
			ingredient_parts.append("%s %d / %d" % [ExpeditionInventory.get_item_name(item_id), inventory.count_item(item_id) if inventory != null else 0, int(resources[item_id])])
		var description := str(definition.description)
		if not cooking:
			description += " 스트레스 %d 완화." % roundi(float(StressProfile.CAMP_RELIEF.get(id, 0.0)))
		actions.append({"id": id, "title": str(definition.title), "category": "cooking" if cooking else "rest", "recipe_id": str(definition.get("recipe_id", "")), "description": description, "cost": " · ".join(cost_parts), "duration": float(definition.duration), "resources": resources, "ingredient_text": "보유 / 필요 · " + " · ".join(ingredient_parts), "enabled": reason.is_empty(), "reason": _reason_message(reason) if not reason.is_empty() else ""})
	return {"state": state, "active_action_id": _action_id, "action_title": str(get_action_definition(_action_id).get("title", "")), "is_cooking": state == "resting" and _action_id.begins_with("cook:"), "recipe_id": _action_id.trim_prefix("cook:") if _action_id.begins_with("cook:") else "", "health": player.health if is_instance_valid(player) else 0.0, "max_health": DungeonPlayer.MAX_HEALTH, "stamina": player.stamina if is_instance_valid(player) else 0.0, "max_stamina": DungeonPlayer.MAX_STAMINA, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress, "max_stress": StressProfile.MAX_STRESS, "stress_stage": StressProfile.stage_name(ExpeditionSession.stress), "conditions": " · ".join(conditions) if not conditions.is_empty() else "안정", "warmth": warmth, "kit_spent": kit_spent, "inventory_counts": counts, "progress": clampf(rest_elapsed / rest_duration, 0.0, 1.0) if rest_duration > 0.0 else 0.0, "status": _status, "actions": actions}


static func ordered_action_ids() -> Array[String]:
	var result: Array[String] = ["rest", "meal", "treat"]
	for recipe_id: String in COOKING.ordered_recipe_ids():
		result.append(COOKING.action_id(recipe_id))
	return result


static func get_action_definition(id: String) -> Dictionary:
	if id.begins_with("cook:"):
		return COOKING.get_recipe(id.trim_prefix("cook:"))
	return (ACTIONS.get(id, {}) as Dictionary).duplicate(true)


func _action_failure(id: String) -> String:
	if state != "planning":
		return "busy" if state == "resting" else "not_open"
	var action := get_action_definition(id)
	if action.is_empty():
		return "invalid_action"
	var reason := _player_failure()
	if not reason.is_empty():
		return reason
	if player.global_position.distance_to(_player_position) > 0.3 or Vector2(player.velocity.x, player.velocity.z).length() > 0.2:
		return "moving"
	if _enemy_near(OPEN_ENEMY_RADIUS):
		return "enemy_nearby"
	var placement := _find_placement()
	if not bool(placement.get("accepted", false)):
		return str(placement.get("reason", "blocked_space"))
	if warmth < int(action.warmth):
		return "no_warmth"
	var useful := player.health < DungeonPlayer.MAX_HEALTH
	if id in ["rest", "meal"]:
		useful = useful or player.stamina < DungeonPlayer.MAX_STAMINA or not ExpeditionSession.active_conditions.is_empty() or ExpeditionSession.stress > 0.0
	if id == "meal":
		useful = useful or ExpeditionSession.hunger < ExpeditionSession.MAX_NEED or ExpeditionSession.thirst < ExpeditionSession.MAX_NEED
	elif id == "treat":
		useful = useful or ExpeditionSession.has_condition("bleeding")
	elif id.begins_with("cook:"):
		useful = useful or player.stamina < DungeonPlayer.MAX_STAMINA or ExpeditionSession.hunger < ExpeditionSession.MAX_NEED or (float(action.thirst) > 0.0 and ExpeditionSession.thirst < ExpeditionSession.MAX_NEED) or ExpeditionSession.stress > 0.0
	if not useful:
		return "no_effect"
	if inventory == null:
		return "resources_missing"
	for item_id: String in _required_resources(id):
		if inventory.count_item(item_id) < int(_required_resources(id)[item_id]):
			return "no_kit" if item_id == "camp_kit" else "resources_missing"
	return ""


func _required_resources(id: String) -> Dictionary:
	var resources: Dictionary = (get_action_definition(id).get("resources", {}) as Dictionary).duplicate(true)
	if not kit_spent:
		resources["camp_kit"] = 1
	return resources


func _player_failure() -> String:
	if not is_instance_valid(player) or player.health <= 0.0 or player.combat_state == DungeonPlayer.CombatState.DEAD:
		return "dead"
	if player.safe_zone_mode:
		return "safe_zone"
	if player.current_trap != null or player.is_timed_interacting():
		return "trapped"
	if player.combat_state != DungeonPlayer.CombatState.READY or player.blocking or player.bow_drawing or player._is_flail_busy():
		return "busy"
	if not player.is_on_floor():
		return "airborne"
	return ""


func _enemy_near(radius: float) -> bool:
	if not is_instance_valid(player) or not is_inside_tree():
		return false
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate is DungeonEnemy and is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.health > 0.0 and candidate.ai_state != DungeonEnemy.AIState.DEAD:
			if player.global_position.distance_to(candidate.global_position) < radius:
				return true
	return false


func _find_placement() -> Dictionary:
	var feet := player.global_position - Vector3.UP * 0.9
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# Leave the right-hand camp menu clear while keeping both fire and bedroll
	# in the player's resting view. Placement checks use this same real center.
	var center := feet + forward * 1.6 - player.global_basis.x * 0.55
	var floor_height := 0.0
	for offset: Vector3 in [Vector3.ZERO, Vector3(-0.7, 0, 0), Vector3(0.7, 0, 0), Vector3(0, 0, -0.7), Vector3(0, 0, 0.7)]:
		var query := PhysicsRayQueryParameters3D.create(center + offset + Vector3.UP * 0.65, center + offset + Vector3.DOWN * 0.85, WORLD_LAYER, [player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.85:
			return {"accepted": false, "reason": "uneven_ground"}
		var hit_height := float((hit.position as Vector3).y)
		if offset == Vector3.ZERO:
			floor_height = hit_height
		if absf(hit_height - floor_height) > 0.1 or absf(hit_height - feet.y) > 0.3:
			return {"accepted": false, "reason": "uneven_ground"}
	center.y = floor_height
	if _unsafe_trap_near(center):
		return {"accepted": false, "reason": "unsafe_ground"}
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var space_query := PhysicsShapeQueryParameters3D.new()
	space_query.shape = shape
	space_query.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * 0.65)
	space_query.collision_mask = WORLD_LAYER | 4
	space_query.exclude = [player.get_rid()]
	space_query.collide_with_areas = false
	if not player.get_world_3d().direct_space_state.intersect_shape(space_query, 16).is_empty():
		return {"accepted": false, "reason": "blocked_space"}
	return {"accepted": true, "position": center}


func _unsafe_trap_near(center: Vector3) -> bool:
	if not is_inside_tree():
		return false
	for candidate in get_tree().get_nodes_in_group("trap"):
		if candidate is RuneTrap and is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			if candidate.state in [RuneTrap.TrapState.ARMED, RuneTrap.TrapState.INSPECTING, RuneTrap.TrapState.DISARMING] and center.distance_to(candidate.global_position) < 1.5:
				return true
	return false


func _refresh_player_hud() -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(player.hud):
		player.hud.update_stamina(player.stamina, DungeonPlayer.MAX_STAMINA)
	player._refresh_survival_hud()


func _dispose_visual() -> void:
	if is_instance_valid(camp_visual):
		camp_visual.hide()
		camp_visual.queue_free()
	camp_visual = null


func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "message": _reason_message(reason)}


func _reason_message(reason: String) -> String:
	if reason == "unsafe_ground":
		return "야영 자리 가까이에 아직 해제되지 않은 함정이 있습니다."
	if reason == "resources_missing":
		return "필요한 보급이나 요리 재료가 부족합니다. 보유 / 필요 수량을 확인하세요."
	return str({"already_open": "이미 야영 중입니다.", "paused": "다른 메뉴를 닫은 뒤 야영하세요.", "dead": "쓰러진 상태에서는 야영할 수 없습니다.", "safe_zone": "은신처에서는 야영할 필요가 없습니다.", "trapped": "함정이나 상호작용을 먼저 끝내세요.", "busy": "현재 동작이 끝난 뒤 야영하세요.", "moving": "제자리에 멈추어 야영하세요.", "unavailable": "이 장소에서는 야영할 수 없습니다.", "airborne": "땅에 발을 딛고 야영하세요.", "enemy_nearby": "8m 안에 적이 있어 야영할 수 없습니다.", "uneven_ground": "앞쪽에 넓고 평평한 바닥이 필요합니다.", "blocked_space": "앞쪽 야영 공간이 막혀 있습니다.", "not_open": "먼저 야영 계획을 여세요.", "invalid_action": "알 수 없는 야영 행동입니다.", "no_warmth": "불씨의 온기가 부족합니다. 야영을 정리하세요.", "no_effect": "회복할 상태가 없습니다.", "no_kit": "야영 도구 1개가 필요합니다.", "resources_missing": "필요한 식량·물·붕대가 부족합니다."}.get(reason, "지금은 야영할 수 없습니다."))
