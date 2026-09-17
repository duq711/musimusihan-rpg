extends SceneTree

const OVERLAY := preload("res://scripts/camp_overlay.gd")
const VISUALS := preload("res://scripts/camp_visuals.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_recipe_ui()
	await _test_small_viewport()
	_test_progress_driven_visuals()
	if failures.is_empty():
		print("COOKING HUD TEST PASS: rest/cooking categories, exact ingredients/recovery/duration, recipe-only signals, real progress/interrupt messages, responsive layout, deterministic pot/spit/steam and cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error("COOKING HUD TEST FAIL: " + failure)
		quit(1)


func _snapshot() -> Dictionary:
	return {
		"state": "planning", "health": 35.0, "max_health": 100.0, "stamina": 25.0, "max_stamina": 100.0,
		"hunger": 20.0, "thirst": 25.0, "stress": 60.0, "conditions": "안정", "warmth": 3, "kit_spent": false,
		"inventory_counts": {"camp_kit": 1, "raw_meat": 2, "edible_mushroom": 1, "boiled_rainwater": 0},
		"active_action_id": "", "action_title": "", "is_cooking": false, "recipe_id": "", "progress": 0.0, "status": "",
		"actions": [
			{"id": "rest", "category": "rest", "title": "경계 휴식", "description": "체력 20", "cost": "온기 1", "duration": 8.0, "enabled": true, "reason": ""},
			{"id": "meal", "category": "rest", "title": "식사 휴식", "description": "체력 45", "cost": "온기 2", "duration": 14.0, "enabled": true, "reason": ""},
			{"id": "treat", "category": "rest", "title": "응급처치", "description": "체력 18", "cost": "온기 1", "duration": 6.0, "enabled": false, "reason": "붕대 부족"},
			{"id": "cook:roast_meat", "category": "cooking", "recipe_id": "roast_meat", "title": "고기구이", "description": "체력 12 · 포만감 35 · 스트레스 8 완화", "cost": "온기 1", "duration": 12.0, "ingredient_text": "생고기 2 / 1 · 야영 도구 1 / 1", "enabled": true, "reason": ""},
			{"id": "cook:mushroom_soup", "category": "cooking", "recipe_id": "mushroom_soup", "title": "버섯수프", "description": "수분 40 · 포만감 24", "cost": "온기 1", "duration": 16.0, "ingredient_text": "식용 버섯 1 / 1 · 물 0 / 1", "enabled": false, "reason": "물이 부족합니다."},
			{"id": "cook:trail_stew", "category": "cooking", "recipe_id": "trail_stew", "title": "고기·버섯 스튜", "description": "체력 32 · 포만감 60", "cost": "온기 2", "duration": 20.0, "ingredient_text": "생고기 2 / 1 · 식용 버섯 1 / 1", "enabled": true, "reason": ""},
		],
	}


func _test_recipe_ui() -> void:
	var overlay := OVERLAY.new() as CampOverlay
	root.add_child(overlay)
	var snapshot := _snapshot()
	overlay.set_snapshot(snapshot)
	overlay.show_camp()
	await process_frame
	_check(overlay.category_tabs.visible and overlay.category_buttons.size() == 2, "planning must clearly separate rest and cooking categories")
	_check(overlay.action_buttons.size() == 6 and overlay.action_cards.size() == 6, "all supplied actions must keep their actual buttons even across tabs")
	_check(overlay.action_cards.rest.visible and not overlay.action_cards["cook:roast_meat"].visible, "rest tab must not mix in recipe cards")
	var requested: Array[String] = []
	overlay.action_requested.connect(func(id: String) -> void: requested.append(id))
	overlay._on_action_pressed("cook:roast_meat")
	_check(requested.is_empty(), "hidden recipe cards must not send stale action requests")
	(overlay.category_buttons.cooking as Button).pressed.emit()
	_check(overlay.selected_category == "cooking" and overlay.cooking_hint_label.visible, "cooking tab must select actual recipes and explain automatic eating")
	_check(not overlay.action_cards.rest.visible and overlay.action_cards["cook:roast_meat"].visible, "cooking tab must hide rest cards without deleting recipe buttons")
	_check(overlay.cooking_hint_label.text.contains("완성 즉시 먹습니다") and overlay.cooking_hint_label.text.contains("완성 전"), "cooking must explain when food is eaten and recovery occurs")
	_check(overlay.action_ingredients["cook:roast_meat"].text == snapshot.actions[3].ingredient_text, "recipe cards must show exact have/need ingredient text")
	_check(overlay.action_details["cook:roast_meat"].text == snapshot.actions[3].description and overlay.action_costs["cook:roast_meat"].text.contains("12.0초"), "recovery and duration must be copied from core recipe data")
	_check(overlay.resources_label.text.contains("생고기 2") and overlay.resources_label.text.contains("식용 버섯 1"), "available cooking resources must be visible")
	_check(overlay.action_buttons["cook:mushroom_soup"].disabled and overlay.action_reasons["cook:mushroom_soup"].text == "물이 부족합니다.", "missing ingredients must retain the exact core failure reason")
	overlay._on_action_pressed("rest")
	overlay._on_action_pressed("cook:mushroom_soup")
	overlay._on_action_pressed("cook:roast_meat")
	_check(requested == ["cook:roast_meat"], "cooking selection must emit only its available real action ID")
	var previous_button: Button = overlay.action_buttons["cook:roast_meat"]
	snapshot.inventory_counts.raw_meat = 1
	snapshot.actions[3].ingredient_text = "생고기 1 / 1 · 야영 도구 1 / 1"
	overlay.set_snapshot(snapshot)
	_check(overlay.action_buttons["cook:roast_meat"] == previous_button and overlay.action_ingredients["cook:roast_meat"].text.contains("생고기 1 / 1"), "resource refresh must preserve buttons and their current focus")
	snapshot.state = "resting"
	snapshot.is_cooking = true
	snapshot.recipe_id = "roast_meat"
	snapshot.active_action_id = "cook:roast_meat"
	snapshot.action_title = "고기구이"
	snapshot.progress = 0.4
	overlay.set_snapshot(snapshot)
	_check(overlay.title_label.text.contains("조리 중") and is_equal_approx(overlay.progress_bar.value, 0.4), "active cooking must display real progress rather than a second timer")
	_check(overlay.activity_label.text.contains("고기구이") and overlay.activity_label.text.contains("40%") and overlay.activity_label.text.contains("7.2초"), "active recipe and remaining time must follow the supplied duration and progress")
	_check(not overlay.action_list.visible and not overlay.category_tabs.visible and overlay.progress_bar.visible, "active cooking must put progress and interruption in view")
	_check(overlay.risk_label.text.contains("적 접근·피격") and overlay.risk_label.text.contains("재료는 반환되지"), "cooking must explicitly warn about real danger and lost ingredients")
	_check(overlay.leave_button.text.contains("조리 중단") and overlay.leave_button.text.contains("반환 없음"), "interrupt button must disclose cooking cost loss")
	overlay.select_category("rest")
	overlay._on_action_pressed("cook:trail_stew")
	_check(overlay.selected_category == "cooking" and requested.size() == 1, "active cooking must reject both repeated activity and category changes")
	snapshot.state = "planning"
	snapshot.is_cooking = false
	snapshot.active_action_id = ""
	snapshot.action_title = ""
	overlay.set_snapshot(snapshot)
	_check(overlay.selected_category == "cooking" and overlay.action_list.visible and not overlay.progress_bar.visible, "completion must return to recipe selection without stale progress")
	overlay.hide_camp()
	overlay._on_action_pressed("cook:trail_stew")
	_check(requested.size() == 1, "hidden cooking UI must not emit actions")
	overlay.free()


func _test_small_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var overlay := OVERLAY.new() as CampOverlay
	viewport.add_child(overlay)
	overlay.set_snapshot(_snapshot())
	overlay.show_camp()
	overlay.select_category("cooking")
	for frame in 3:
		await process_frame
	_check(overlay.panel_root.get_rect().end.x <= 640 and overlay.panel_root.get_rect().end.y <= 360, "recipe panel must stay within a small viewport: %s" % overlay.panel_root.get_rect())
	_check(overlay.leave_button.get_global_rect().end.y <= 360, "interrupt/leave control must remain reachable without scrolling: %s" % overlay.leave_button.get_global_rect())
	_check(overlay.action_scroll.get_v_scroll_bar().max_value > overlay.action_scroll.size.y, "small viewport must allow scrolling to all three recipes")
	viewport.free()


func _test_progress_driven_visuals() -> void:
	var camp := VISUALS.create_camp() as Node3D
	root.add_child(camp)
	var tools := camp.get_node("CookingTools") as Node3D
	_check(not tools.visible, "ordinary camp must start with cooking tools hidden")
	VISUALS.set_cooking(camp, "roast_meat", 0.1, true)
	var skewer := tools.get_node("RoastingSpit/SpitSkewer") as Node3D
	var meat := skewer.get_node("MeatChunk0") as MeshInstance3D
	var raw_color := (meat.material_override as StandardMaterial3D).albedo_color
	var raw_rotation := skewer.rotation
	_check(tools.visible and tools.get_node("RoastingSpit").visible and not tools.get_node("SoupPot").visible, "roasting must put meat and skewer over the actual fire")
	VISUALS.set_cooking(camp, "roast_meat", 0.8, true)
	_check(not raw_color.is_equal_approx((meat.material_override as StandardMaterial3D).albedo_color) and not raw_rotation.is_equal_approx(skewer.rotation), "real progress must visibly brown and rotate the meat")
	_check(meat.get_child(0).visible, "later roast progress must reveal cooked char marks")
	VISUALS.set_cooking(camp, "mushroom_soup", 0.2, true)
	var pot := tools.get_node("SoupPot") as Node3D
	var spoon := pot.get_node("StirringSpoon") as Node3D
	var old_spoon := spoon.transform
	var old_bubble: Transform3D = pot.get_node("SoupBubble0").transform
	_check(pot.visible and not tools.get_node("RoastingSpit").visible and pot.has_node("CookingPot") and pot.has_node("SoupSurface"), "soup must replace the spit with an actual pot and broth")
	VISUALS.set_cooking(camp, "mushroom_soup", 0.35, true)
	_check(not spoon.transform.is_equal_approx(old_spoon) and not pot.get_node("SoupBubble0").transform.is_equal_approx(old_bubble), "soup stirring and bubbles must follow actual progress")
	var exact_spoon := spoon.transform
	var exact_steam: Transform3D = tools.get_node("CookingSteam/SteamPuff0").transform
	VISUALS.set_cooking(camp, "mushroom_soup", 0.35, true)
	_check(spoon.transform.is_equal_approx(exact_spoon) and tools.get_node("CookingSteam/SteamPuff0").transform.is_equal_approx(exact_steam), "same paused progress must reproduce identical geometry with no independent clock")
	var soup_color: Color = pot.get_node("SoupSurface").material_override.albedo_color
	VISUALS.set_cooking(camp, "cook:trail_stew", 0.5, true)
	_check(pot.visible and not soup_color.is_equal_approx(pot.get_node("SoupSurface").material_override.albedo_color), "stew must show its distinct broth while accepting the actual cooking action prefix")
	VISUALS.set_cooking(camp, "trail_stew", 0.5, false)
	_check(not tools.visible and not pot.visible and not tools.get_node("RoastingSpit").visible, "completion or interruption must hide all cooking props immediately")
	VISUALS.set_cooking(camp, "unknown", 0.5, true)
	_check(not tools.visible, "unknown recipe cannot leave a previous visual running")
	VISUALS.animate(camp, 1.0, 2)
	_check(camp.get_node("Flame").visible and camp.get_node("CampfireLight").light_energy > 0.0, "existing campfire animation must still work after cooking cleanup")
	_check(_collision_count(camp) == 0, "cooking visuals must not add physics, hazards or gameplay collisions")
	camp.free()


func _collision_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D else 0
	for child in node.get_children():
		count += _collision_count(child)
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
