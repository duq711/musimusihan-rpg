extends Node
class_name DungeonCamp

signal opened()
signal rest_started()
signal rest_finished(result: Dictionary)
signal closed(reason: String, restore_controls: bool)
signal placement_started()
signal placement_updated(snapshot: Dictionary)
signal deployed()

const VISUALS := preload("res://scripts/camp_visuals.gd")
const COOKING := preload("res://scripts/camp_cooking_catalog.gd")
const PLACEMENT := preload("res://scripts/camp_placement_probe.gd")
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
var placement_snapshot: Dictionary = {}
var preview_visual: Node3D

var _action_id := ""
var _camp_position := Vector3.ZERO
var _camp_yaw := 0.0
var _player_position := Vector3.ZERO
var _return_transform := Transform3D.IDENTITY
var _has_return_position := false
var _rest_start_health := 0.0
var _survival_advanced := 0.0
var _visual_time := 0.0
var _status := "평평하고 안전한 곳에서 짧게 쉬어갑니다."


func setup(game_ref: Node, player_ref: DungeonPlayer, inventory_ref: ExpeditionInventory) -> void:
	if inventory != inventory_ref and state != "closed":
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
		overlay.leave_requested.connect(leave_camp)
		if overlay.has_signal("pack_requested"):
			overlay.pack_requested.connect(cancel_camp)
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
	if state == "placing":
		if not get_tree().paused: update_placement()
		return
	if not get_tree().paused:
		_visual_time += maxf(0.0, delta)
		VISUALS.animate(camp_visual, _visual_time, warmth)
	advance_rest(delta)


func is_open() -> bool:
	return state in ["placing", "planning", "resting"]


func begin_placement() -> Dictionary:
	if state != "closed":
		return _failure("already_deployed" if state == "deployed" else "already_open")
	if not is_inside_tree() or get_tree().paused:
		return _failure("paused")
	var scene_reason := _scene_failure()
	if not scene_reason.is_empty(): return _failure(scene_reason)
	var reason := _player_failure()
	if not reason.is_empty(): return _failure(reason)
	if inventory == null or inventory.count_item("camp_kit") < 1: return _failure("no_kit")
	state = "placing"
	kit_spent = false
	last_result = {}
	preview_visual = VISUALS.create_preview()
	game.add_child(preview_visual)
	update_placement()
	placement_started.emit()
	return {"accepted": true, "placing": true, "message": "야영할 바닥을 조준하세요 · 왼쪽 클릭 설치 · F 취소"}


func update_placement() -> Dictionary:
	if state != "placing": return _failure("not_placing")
	if not is_instance_valid(player):
		cancel_camp("", false)
		return _failure("unavailable")
	placement_snapshot = _find_placement()
	var reason := "paused" if get_tree().paused else _scene_failure()
	if reason.is_empty(): reason = _player_failure()
	if reason.is_empty() and (inventory == null or inventory.count_item("camp_kit") < 1): reason = "no_kit"
	if not reason.is_empty():
		placement_snapshot["accepted"] = false
		placement_snapshot["reason"] = reason
	placement_snapshot["message"] = "천막과 모닥불 설치 · 야영 도구 1개" if placement_snapshot.accepted else _reason_message(str(placement_snapshot.reason))
	if is_instance_valid(preview_visual):
		preview_visual.global_position = placement_snapshot.position
		preview_visual.global_rotation.y = float(placement_snapshot.yaw)
		VISUALS.set_preview_valid(preview_visual, bool(placement_snapshot.accepted))
	placement_updated.emit(placement_snapshot.duplicate(true))
	return placement_snapshot.duplicate(true)


func confirm_placement() -> Dictionary:
	if state != "placing": return _failure("not_placing")
	if get_tree().paused: return _failure("paused")
	var scene_reason := _scene_failure()
	if not scene_reason.is_empty(): return _failure(scene_reason)
	# Never trust a green preview from an earlier frame or a changed bag.
	var placement := update_placement()
	if not bool(placement.accepted): return _failure(str(placement.reason))
	if not inventory.remove_item("camp_kit", 1, false): return _failure("no_kit")
	_camp_position = placement.position
	_camp_yaw = float(placement.yaw)
	warmth = 3
	kit_spent = true
	state = "deployed"
	rest_elapsed = 0.0
	rest_duration = 0.0
	_action_id = ""
	_status = "야영지를 설치했습니다. 천막을 바라보고 E로 앉으세요."
	_dispose_preview()
	placement_snapshot.clear()
	camp_visual = VISUALS.create_camp(self)
	game.add_child(camp_visual)
	camp_visual.global_position = _camp_position
	camp_visual.global_rotation.y = _camp_yaw
	# Commit before observers are notified so repeated requests cannot spend twice.
	inventory.changed.emit()
	if state == "deployed":
		refresh()
		deployed.emit()
	return {"accepted": true, "position": _camp_position, "kit_spent": true, "message": _status}


func get_interaction_prompt() -> String:
	return "E · 천막에 앉기" if state == "deployed" else ""


func interact(actor: Node) -> Dictionary:
	if actor != player: return _failure("unavailable")
	var result := open_camp()
	if not bool(result.get("accepted", false)) and is_instance_valid(player.hud):
		player.hud.show_event(str(result.get("message", "지금은 천막에 앉을 수 없습니다.")), 1.8)
	return result


func open_camp() -> Dictionary:
	if state != "deployed": return _failure("not_deployed")
	if not is_inside_tree() or get_tree().paused: return _failure("paused")
	var scene_reason := _scene_failure()
	if not scene_reason.is_empty(): return _failure(scene_reason)
	var reason := _player_failure()
	if not reason.is_empty(): return _failure(reason)
	var seat := PLACEMENT.seat_position(_camp_position, _camp_yaw)
	if player.global_position.distance_to(seat) > 3.5: return _failure("out_of_reach")
	var placement := _validate_fixed_placement()
	if not bool(placement.get("accepted", false)):
		return _failure(str(placement.get("reason", "blocked_space")))
	if not PLACEMENT.walking_path_clear(player, game, player.global_position, seat):
		return _failure("blocked_access")
	_return_transform = player.global_transform
	_has_return_position = true
	player.global_position = seat
	player.global_rotation.y = _camp_yaw
	player.velocity = Vector3.ZERO
	_player_position = seat
	_status = "천막에 앉았습니다. 요리·휴식을 마치면 일어서거나 야영지를 정리할 수 있습니다."
	state = "planning"
	refresh()
	if is_instance_valid(overlay): overlay.show_camp()
	opened.emit()
	return {"accepted": true, "position": _camp_position, "seat_position": seat, "message": _status}


func _scene_failure() -> String:
	if is_instance_valid(game) and game.has_method("_camp_open_failure"):
		return str(game.call("_camp_open_failure"))
	return ""


func _validate_fixed_placement() -> Dictionary:
	var placement := PLACEMENT.validate(player, game, _camp_position, _camp_yaw, _camp_exclusions())
	return _validate_dangers(placement)


func _validate_dangers(placement: Dictionary) -> Dictionary:
	if not bool(placement.accepted): return placement
	var center: Vector3 = placement.position
	if _enemy_near(OPEN_ENEMY_RADIUS, center):
		placement["accepted"] = false
		placement["reason"] = "enemy_nearby"
	var basis := Basis(Vector3.UP, float(placement.yaw))
	for offset: Vector3 in PLACEMENT.floor_samples():
		if _unsafe_trap_near(center + basis * offset):
			placement["accepted"] = false
			placement["reason"] = "unsafe_ground"
			break
	return placement


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
		leave_camp("피격으로 야영을 중단했습니다.")
		return
	if _enemy_near(REST_ENEMY_RADIUS, _camp_position):
		leave_camp("적이 가까이 다가와 야영을 중단했습니다.")
		return
	if _unsafe_trap_near(_camp_position):
		leave_camp("가까운 함정이 활성화되어 야영을 중단했습니다.")
		return
	if player.global_position.distance_to(_player_position) > 0.5 or player.current_trap != null or player.safe_zone_mode:
		leave_camp("야영 장소를 벗어나 휴식을 중단했습니다.")
		return
	var elapsed := minf(maxf(0.0, delta), maxf(0.0, rest_duration - rest_elapsed))
	if elapsed <= 0.0:
		return
	rest_elapsed = minf(rest_duration, rest_elapsed + elapsed)
	var target_survival := float(get_action_definition(_action_id).survival) * rest_elapsed / rest_duration
	var survival_delta := maxf(0.0, target_survival - _survival_advanced)
	_survival_advanced = target_survival
	ExpeditionSession.advance_survival(survival_delta)
	player.sync_body_health_from_session()
	if player.combat_state == DungeonPlayer.CombatState.DEAD:
		cancel_camp("부상이 악화되어 야영 중 사망했습니다.", false)
		return
	# Periodic wounds continue during rest. They do not pretend to be a new
	# external attack on the next update; actual hits interrupt through player.
	_rest_start_health = player.health
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


func leave_camp(reason := "", restore_controls := true) -> void:
	if state not in ["planning", "resting"]: return
	_record_interruption(reason)
	state = "deployed"
	if is_instance_valid(overlay): overlay.hide_camp()
	_restore_player_position()
	refresh()
	closed.emit(reason, restore_controls)


func cancel_camp(reason := "", restore_controls := true) -> void:
	if state == "closed":
		return
	_record_interruption(reason)
	state = "closed"
	if is_instance_valid(overlay):
		overlay.hide_camp()
	_restore_player_position()
	_dispose_visual()
	placement_snapshot.clear()
	closed.emit(reason, restore_controls)


func _record_interruption(reason: String) -> void:
	if state == "resting":
		last_result = {"accepted": false, "cancelled": true, "action_id": _action_id, "survival_seconds": _survival_advanced, "elapsed": rest_elapsed, "message": reason if not reason.is_empty() else "휴식을 중단했습니다. 이미 사용한 물품과 온기는 반환되지 않습니다."}
	_action_id = ""
	rest_elapsed = 0.0
	rest_duration = 0.0


func _restore_player_position() -> void:
	if not _has_return_position: return
	_has_return_position = false
	if not is_instance_valid(player) or not player.is_inside_tree(): return
	# A newly introduced obstacle cannot turn standing up into a wall teleport.
	if PLACEMENT.walking_path_clear(player, game, player.global_position, _return_transform.origin):
		player.global_transform = _return_transform
	player.velocity = Vector3.ZERO


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
	# One presentation snapshot shares its physical eligibility calculation.
	# start_action calls _action_failure without this value and revalidates.
	var common_reason := _common_action_failure()
	for id: String in ordered_action_ids():
		var definition := get_action_definition(id)
		var cooking := id.begins_with("cook:")
		var reason := _action_failure(id, common_reason)
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


func _common_action_failure() -> String:
	if state != "planning":
		return "busy" if state == "resting" else "not_open"
	if not kit_spent: return "not_deployed"
	var reason := _player_failure()
	if not reason.is_empty():
		return reason
	if player.global_position.distance_to(_player_position) > 0.3 or Vector2(player.velocity.x, player.velocity.z).length() > 0.2:
		return "moving"
	var placement := _validate_fixed_placement()
	if not bool(placement.get("accepted", false)):
		return str(placement.get("reason", "blocked_space"))
	return ""


func _action_failure(id: String, common_reason := "_revalidate") -> String:
	var reason := _common_action_failure() if common_reason == "_revalidate" else common_reason
	if not reason.is_empty(): return reason
	var action := get_action_definition(id)
	if action.is_empty(): return "invalid_action"
	if warmth < int(action.warmth):
		return "no_warmth"
	var useful: bool = player.get_healable_health_capacity() > 0.0
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
	return (get_action_definition(id).get("resources", {}) as Dictionary).duplicate(true)


func _player_failure() -> String:
	if not is_instance_valid(player) or player.health <= 0.0 or player.combat_state == DungeonPlayer.CombatState.DEAD:
		return "dead"
	if player.safe_zone_mode:
		return "safe_zone"
	if player.current_trap != null or player.is_timed_interacting():
		return "trapped"
	if player.combat_state != DungeonPlayer.CombatState.READY or player.blocking or player.bow_drawing or player._is_flail_busy() or player.is_item_use_active() or player.is_paralyzed():
		return "busy"
	if not player.is_on_floor():
		return "airborne"
	return ""


func _enemy_near(radius: float, center := Vector3.INF) -> bool:
	if not is_instance_valid(player) or not is_inside_tree():
		return false
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate is DungeonEnemy and is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.health > 0.0 and candidate.ai_state != DungeonEnemy.AIState.DEAD:
			if player.global_position.distance_to(candidate.global_position) < radius or (center != Vector3.INF and center.distance_to(candidate.global_position) < radius):
				return true
	return false


func _find_placement() -> Dictionary:
	return _validate_dangers(PLACEMENT.aim(player, game))


func _camp_exclusions() -> Array[RID]:
	var result: Array[RID] = []
	if is_instance_valid(camp_visual): _collect_collision_rids(camp_visual, result)
	return result


func _collect_collision_rids(node: Node, result: Array[RID]) -> void:
	if node is CollisionObject3D: result.append(node.get_rid())
	for child in node.get_children(): _collect_collision_rids(child, result)


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
	_dispose_preview()
	if is_instance_valid(camp_visual):
		camp_visual.hide()
		camp_visual.queue_free()
	camp_visual = null


func _dispose_preview() -> void:
	if is_instance_valid(preview_visual):
		preview_visual.hide()
		preview_visual.queue_free()
	preview_visual = null


func _failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "message": _reason_message(reason)}


func _reason_message(reason: String) -> String:
	if reason == "no_ground": return "5m 안의 바닥을 조준하세요."
	if reason == "wet_ground": return "물에 잠긴 곳에는 야영할 수 없습니다."
	if reason == "not_placing": return "가방에서 야영 도구를 먼저 사용하세요."
	if reason == "not_deployed": return "먼저 야영 도구로 천막을 설치하세요."
	if reason == "already_deployed": return "설치한 야영지를 먼저 정리하세요."
	if reason == "out_of_reach": return "천막 가까이 다가가세요."
	if reason == "blocked_access": return "천막 좌석으로 가는 길이 막혀 있습니다."
	if reason == "unsafe_ground":
		return "야영 자리 가까이에 아직 해제되지 않은 함정이 있습니다."
	if reason == "resources_missing":
		return "필요한 보급이나 요리 재료가 부족합니다. 보유 / 필요 수량을 확인하세요."
	return str({"already_open": "이미 야영 중입니다.", "paused": "다른 메뉴를 닫은 뒤 야영하세요.", "dead": "쓰러진 상태에서는 야영할 수 없습니다.", "safe_zone": "은신처에서는 야영할 필요가 없습니다.", "trapped": "함정이나 상호작용을 먼저 끝내세요.", "busy": "현재 동작이 끝난 뒤 야영하세요.", "moving": "제자리에 멈추어 야영하세요.", "unavailable": "이 장소에서는 야영할 수 없습니다.", "airborne": "땅에 발을 딛고 야영하세요.", "enemy_nearby": "8m 안에 적이 있어 야영할 수 없습니다.", "uneven_ground": "앞쪽에 넓고 평평한 바닥이 필요합니다.", "blocked_space": "앞쪽 야영 공간이 막혀 있습니다.", "not_open": "먼저 야영 계획을 여세요.", "invalid_action": "알 수 없는 야영 행동입니다.", "no_warmth": "불씨의 온기가 부족합니다. 야영을 정리하세요.", "no_effect": "회복할 상태가 없습니다.", "no_kit": "야영 도구 1개가 필요합니다.", "resources_missing": "필요한 식량·물·붕대가 부족합니다."}.get(reason, "지금은 야영할 수 없습니다."))
