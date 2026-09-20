extends SceneTree

const CAMP_OVERLAY := preload("res://scripts/camp_overlay.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_snapshot_and_signals()
	await _test_responsive_layout()
	_test_control_legends()
	if failures.is_empty():
		print("CAMP HUD TEST PASS: data-driven actions, costs, resources, progress, risk/refund warnings, pure UI signals, small-viewport scroll and weapon control legends")
		quit(0)
	else:
		for failure in failures:
			push_error("CAMP HUD TEST FAIL: " + failure)
		quit(1)


func _snapshot() -> Dictionary:
	return {
		"state": "planning", "health": 51.0, "max_health": 100.0,
		"stamina": 27.0, "max_stamina": 100.0, "hunger": 62.0, "thirst": 44.0,
		"conditions": "출혈", "warmth": 3, "kit_spent": true, "progress": 0.0,
		"inventory_counts": {"camp_kit": 1, "pilgrim_ration": 2, "boiled_rainwater": 1, "linen_bandage": 0},
		"status": "보급과 주변을 확인하세요.",
		"actions": [
			{"id": "short_rest", "title": "숨 고르기", "description": "기력을 회복하고 잠깐 몸을 녹입니다.", "cost": "온기 1", "duration": 4.0, "enabled": true, "reason": ""},
			{"id": "meal", "title": "식사하기", "description": "식량과 물로 체력과 생존 수치를 회복합니다.", "cost": "식량 1 · 물 1 · 온기 1", "duration": 6.0, "enabled": true, "reason": ""},
			{"id": "treat", "title": "상처 돌보기", "description": "붕대로 상처를 감고 출혈을 멈춥니다.", "cost": "붕대 1 · 온기 1", "duration": 5.0, "enabled": false, "reason": "붕대가 부족합니다."},
		],
	}


func _test_snapshot_and_signals() -> void:
	var overlay := CAMP_OVERLAY.new() as CampOverlay
	root.add_child(overlay)
	await process_frame
	_check(overlay.process_mode == Node.PROCESS_MODE_ALWAYS and overlay.layer == 85, "camp UI must remain responsive on its dedicated layer during planning pause")
	_check(not overlay.overlay_root.visible, "camp UI must start hidden")
	var snapshot := _snapshot()
	overlay.set_snapshot(snapshot)
	overlay.show_camp()
	await process_frame
	_check(overlay.stats_label.text.contains("51/100") and overlay.stats_label.text.contains("27/100") and overlay.stats_label.text.contains("출혈"), "camp must display actual player status")
	_check(overlay.resources_label.text.contains("온기 3") and overlay.resources_label.text.contains("야영 도구 1") and overlay.resources_label.text.contains("사용 완료"), "resources must show actual quantities and the already-paid installation")
	_check(overlay.action_buttons.size() == 3 and overlay.action_buttons.treat.disabled, "camp must build all provided actions and respect availability")
	_check(overlay.action_costs.meal.text.contains("식량 1 · 물 1 · 온기 1") and overlay.action_costs.meal.text.contains("6.0초"), "action card must show supplied costs and durations without guessing")
	_check(overlay.action_reasons.treat.text == "붕대가 부족합니다.", "disabled action must show the actual reason")
	_check(overlay.risk_label.text.contains("시간이 멈춥니다"), "planning UI must distinguish paused preparation")
	_check(overlay.leave_button.text == "일어서기 · Esc", "planning leave button must explain standing up without removing the camp")
	var requested: Array[String] = []
	var left: Array[bool] = []
	overlay.action_requested.connect(func(id: String) -> void: requested.append(id))
	overlay.leave_requested.connect(func() -> void: left.append(true))
	var button_before := overlay.action_buttons.short_rest as Button
	snapshot.actions[0].enabled = false
	overlay._on_action_pressed("short_rest")
	_check(requested == ["short_rest"], "overlay must deep-copy snapshots and emit only the requested action ID")
	overlay._on_action_pressed("treat")
	overlay._on_action_pressed("unknown")
	_check(requested.size() == 1, "unavailable or unknown actions must never emit requests")
	paused = true
	overlay.set_snapshot(_snapshot())
	_check(overlay.action_buttons.short_rest == button_before, "snapshot refresh must preserve existing buttons and focus")
	overlay._on_action_pressed("meal")
	_check(paused and requested == ["short_rest", "meal"], "UI action requests must not mutate the game pause state")
	paused = false
	snapshot = _snapshot()
	snapshot.state = "resting"
	snapshot.progress = 0.6
	snapshot.kit_spent = true
	snapshot.warmth = 2
	snapshot.inventory_counts.camp_kit = 0
	snapshot.status = "몸을 녹이는 중입니다."
	overlay.set_snapshot(snapshot)
	_check(is_equal_approx(overlay.progress_bar.value, 0.6) and overlay.status_label.text == snapshot.status, "resting progress and status must follow the core snapshot")
	_check(overlay.progress_bar.visible and not overlay.action_list.visible, "active rest must put progress in view instead of filling the panel with unavailable cards")
	_check(overlay.resources_label.text.contains("온기 2") and overlay.resources_label.text.contains("야영 도구 사용 완료"), "spent kit and remaining warmth must refresh live")
	_check(overlay.risk_label.text.contains("던전이 진행") and overlay.risk_label.text.contains("적 접근·피격"), "actual rest must warn that danger and dungeon time continue")
	_check(overlay.leave_button.text.contains("휴식 중단") and overlay.leave_button.text.contains("반환 없음"), "interrupt button must clearly disclose non-refundable supplies")
	for button: Button in overlay.action_buttons.values():
		_check(button.disabled, "every other action must be disabled during an active rest")
	overlay._on_action_pressed("meal")
	_check(requested.size() == 2, "active rest must reject repeated requests even through direct callbacks")
	overlay._on_leave_requested()
	_check(left.size() == 1 and overlay.overlay_root.visible, "leave must emit a request and let the game own closing/cleanup")
	overlay.hide_camp()
	overlay._on_action_pressed("short_rest")
	overlay._on_leave_requested()
	_check(left.size() == 1 and requested.size() == 2, "hidden overlay must not emit stale actions")
	snapshot.state = "planning"
	snapshot.progress = 2.0
	snapshot.actions = [snapshot.actions[0]]
	overlay.set_snapshot(snapshot)
	_check(overlay.action_buttons.size() == 1 and is_zero_approx(overlay.progress_bar.value), "action set changes and completion must clear removed actions and stale progress")
	_check(overlay.action_list.visible and not overlay.progress_bar.visible, "returning to planning must restore actions and hide inactive progress")
	overlay.free()


func _test_responsive_layout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var overlay := CAMP_OVERLAY.new() as CampOverlay
	viewport.add_child(overlay)
	overlay.set_snapshot(_snapshot())
	overlay.show_camp()
	await process_frame
	await process_frame
	_check(overlay.panel_root.position.is_equal_approx(Vector2(730, 70)) and overlay.panel_root.size.is_equal_approx(Vector2(510, 580)), "1280x720 camp panel must stay on the right and preserve the fire view")
	_check(overlay.overlay_root.color.a <= 0.15 and overlay.overlay_root.mouse_filter == Control.MOUSE_FILTER_STOP, "backdrop must keep the 3D fire visible while blocking stray attacks")
	for size: Vector2i in [Vector2i(640, 360), Vector2i(480, 320), Vector2i(1280, 720)]:
		viewport.size = size
		overlay._update_layout()
		await process_frame
		await process_frame
		var panel_rect := overlay.panel_root.get_rect()
		_check(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 and panel_rect.end.x <= size.x and panel_rect.end.y <= size.y, "camp panel must remain inside resized viewport: %s" % size)
		var leave_rect := overlay.leave_button.get_global_rect()
		_check(leave_rect.end.y <= size.y and leave_rect.end.x <= size.x and leave_rect.position.y >= 0.0, "leave button must stay reachable without scrolling on small viewports")
		_check(overlay.action_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "camp layout must not require horizontal scrolling")
		if size.y <= 360:
			_check(overlay.action_scroll.get_v_scroll_bar().max_value > overlay.action_scroll.size.y, "small viewport must allow vertical scrolling through every action and status")
	viewport.free()


func _test_control_legends() -> void:
	var hud := DungeonHUD.new()
	root.add_child(hud)
	for weapon: String in ["melee", "staff", "bow", "flail"]:
		hud.update_magic([], "", weapon == "staff")
		hud.update_archery(weapon == "bow", 12, 0.0, false, 0.0, 12.0)
		hud.update_flail(weapon == "flail", "ready", 0.0, 0.0)
		_check(not hud.control_legend_label.text.contains("C 야영"), "weapon legends must not advertise the removed direct C installation")
		_check(hud.control_legend_label.get_minimum_size().x <= 577.0, "camp shortcut must fit the existing weapon legend width: " + weapon)
	hud.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
