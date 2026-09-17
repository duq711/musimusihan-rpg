extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	await _test_dungeon_readout()
	await _test_inventory_readout()
	await _test_camp_readout()
	ExpeditionSession.restore_snapshot(original)
	if failures.is_empty():
		print("STRESS HUD TEST PASS: thresholds, warning colors, clamping, five-row HUD, five-column live inventory, camp snapshots and small-screen scrolling; normal meters unchanged")
		quit(0)
	else:
		for failure in failures:
			push_error("STRESS HUD TEST FAIL: " + failure)
		quit(1)


func _test_dungeon_readout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var hud := DungeonHUD.new()
	viewport.add_child(hud)
	await process_frame
	_check(is_zero_approx(hud.stress_bar.value), "stress must start empty rather than looking like a full beneficial resource")
	hud.update_health(72.0, 110.0)
	hud.update_stamina(27.0, 125.0)
	hud.update_survival(62.0, 44.0)
	hud.update_conditions({"bleeding": 2.0}, 1.3)
	var expected_stages := ["안정", "안정", "불안", "불안", "동요", "동요", "극심", "극심"]
	var values := [0.0, 39.9, 40.0, 59.9, 60.0, 79.9, 80.0, 100.0]
	for index in values.size():
		var value: float = values[index]
		hud.update_stress(value)
		_check(is_equal_approx(hud.stress_bar.value, value) and is_equal_approx(hud.stress_bar.max_value, 100.0), "HUD stress meter must preserve live value and maximum")
		_check(hud.stress_label.text == "스트레스 %d / 100 · %s" % [roundi(value), expected_stages[index]], "HUD must show the correct threshold stage at %.1f" % value)
		var fill := hud.stress_bar.get_theme_stylebox("fill") as StyleBoxFlat
		_check(fill.bg_color.is_equal_approx(DungeonHUD.stress_color(value).darkened(0.15)), "HUD bar must use the shared severity palette")
		var caption_color := hud.stress_label.get_theme_color("font_color")
		_check(minf(caption_color.r, minf(caption_color.g, caption_color.b)) >= 0.9, "overlaid stress caption must stay pale and legible on every severity fill")
	_check(DungeonHUD.stress_color(0.0).b > DungeonHUD.stress_color(0.0).r and DungeonHUD.stress_color(80.0).r > DungeonHUD.stress_color(80.0).g, "stress must change from purple to a high-danger warm warning, not a healthy green")
	hud.update_stress(-5.0)
	_check(is_zero_approx(hud.stress_bar.value) and hud.stress_label.text.contains("0 / 100 · 안정"), "negative stress must clamp to a stable zero")
	hud.update_stress(180.0)
	_check(is_equal_approx(hud.stress_bar.value, 100.0) and hud.stress_label.text.contains("100 / 100 · 극심"), "stress cannot visually overflow its maximum")
	hud.update_stress(40.0, 50.0)
	_check(is_equal_approx(hud.stress_bar.max_value, 50.0) and hud.stress_label.text.contains("40 / 50 · 극심"), "custom maxima must normalize stage and color consistently")
	hud.update_stress(25.0, 100.0, "제공된 단계")
	_check(hud.stress_label.text.ends_with("제공된 단계"), "HUD must preserve an explicitly supplied stage caption")
	hud.update_stress(85.0)
	_check(hud.health_bar.value == 72.0 and hud.health_bar.max_value == 110.0 and hud.stamina_bar.value == 27.0 and hud.stamina_bar.max_value == 125.0, "stress updates must not replace health or stamina")
	_check(hud.hunger_bar.value == 62.0 and hud.thirst_bar.value == 44.0 and hud.condition_label.text.contains("출혈"), "stress updates must preserve needs and real conditions")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(640, 360)]:
		viewport.size = size
		await process_frame
		await process_frame
		var previous_end := 0.0
		for bar: ProgressBar in [hud.health_bar, hud.stamina_bar, hud.hunger_bar, hud.thirst_bar, hud.stress_bar]:
			_check(bar.position.y >= previous_end, "all five survival bars must be separate rows")
			previous_end = bar.get_rect().end.y
		_check(hud.state_label.position.y >= maxf(previous_end, hud.stress_label.get_rect().end.y), "weapon state must remain below stress: state=%s, stress bar=%s, label=%s" % [hud.state_label.get_rect(), hud.stress_bar.get_rect(), hud.stress_label.get_rect()])
		_check(hud.condition_label.position.y >= hud.state_label.get_rect().end.y, "real condition row must remain below weapon state")
		var panel := hud.stress_bar.get_parent() as Control
		_check(panel.get_global_rect().end.y <= size.y and hud.condition_label.get_rect().end.y <= panel.size.y, "expanded survival panel must contain all rows on a small viewport")
		_check(hud.stress_label.get_minimum_size().x <= hud.stress_label.size.x, "full stress caption must fit without clipping")
	viewport.free()


func _test_inventory_readout() -> void:
	ExpeditionSession.hunger = 62.0
	ExpeditionSession.thirst = 44.0
	var inventory := ExpeditionSession.get_inventory()
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame
	overlay.open_inventory(inventory, func() -> Dictionary: return {"stamina": 27.0, "max_stamina": 125.0})
	var slots_before := inventory.slots.duplicate(true)
	for value: float in [0.0, 40.0, 60.0, 80.0, 100.0]:
		ExpeditionSession.set_stress(value)
		overlay.refresh_status_readout()
		await process_frame
		_check(overlay.stress_value_label.text == "%d / 100" % roundi(value) and overlay.stress_bar.value == value, "inventory must show real session stress at every stage")
		_check(overlay.stress_value_label.get_theme_color("font_color").is_equal_approx(DungeonHUD.stress_color(value)), "inventory severity colors must match the HUD")
		_check(overlay.stress_value_label.get_minimum_size().x <= overlay.stress_value_label.size.x and overlay.stress_value_label.get_rect().end.x <= (overlay.stress_value_label.get_parent() as Control).size.x, "even 100 / 100 must fit the compact fifth column")
	paused = true
	ExpeditionSession.set_stress(84.0)
	overlay.refresh_status_readout()
	_check(paused and overlay.is_open() and overlay.stress_bar.value == 84.0, "paused inventory must refresh stress without changing pause ownership")
	paused = false
	_check(overlay.stamina_bar.value == 27.0 and overlay.stamina_bar.max_value == 125.0 and overlay.hunger_bar.value == 62.0 and overlay.thirst_bar.value == 44.0, "adding stress must preserve all normal inventory meters")
	_check(inventory.slots == slots_before and ExpeditionSession.stress == 84.0, "UI reads must not consume supplies or alter stress")
	for container_mode: bool in [false, true]:
		if container_mode:
			overlay.open_container(inventory, LootContainer.new().configure("스트레스 배치", []))
		await process_frame
		await process_frame
		_check(overlay.status_footer.size == Vector2(784, 44), "fifth readout must preserve the two-pane footer size")
		var previous_end := 0.0
		for node_name: String in ["WeightReadout", "StaminaReadout", "HungerReadout", "ThirstReadout", "StressReadout"]:
			var readout := overlay.status_footer.get_node(node_name) as Control
			_check(is_equal_approx(readout.position.x, previous_end) and readout.get_rect().end.x <= 784.01, "five columns must fill the footer without overlapping or entering the chest pane")
			previous_end = readout.get_rect().end.x
			var title := readout.get_node("Title") as Label
			var value := readout.get_node("Value") as Label
			_check(title.get_rect().end.x <= value.position.x and value.get_rect().end.x <= readout.size.x, "footer titles and values must have distinct bounded regions: %s title=%s, value=%s, column=%s" % [node_name, title.get_rect(), value.get_rect(), readout.size])
			_check(title.get_minimum_size().x <= title.size.x and value.get_minimum_size().x <= value.size.x, "five-column labels must retain readable complete text")
			var meter := readout.get_node_or_null("Meter") as ProgressBar
			if meter != null:
				_check(meter.size.y <= 6.01 and meter.get_rect().end.x <= readout.size.x and meter.get_rect().end.y <= 44.0, "footer meter must remain a slim line contained in its own column")
	var stress_readout := overlay.status_footer.get_node("StressReadout") as Control
	_check((stress_readout.get_node("Icon") as Label).text == "↑" and stress_readout.tooltip_text.contains("높을수록 불안정") and stress_readout.tooltip_text.contains("60부터 환청") and stress_readout.tooltip_text.contains("80부터 환영"), "stress readout must explain that increasing values are dangerous")
	overlay.close()
	overlay.free()


func _test_camp_readout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var overlay := CampOverlay.new()
	viewport.add_child(overlay)
	var snapshot := {"state": "planning", "health": 51.0, "max_health": 100.0, "stamina": 27.0, "max_stamina": 100.0, "hunger": 62.0, "thirst": 44.0, "conditions": "출혈", "stress": 85.0, "max_stress": 100.0, "stress_stage": "극심", "warmth": 3, "kit_spent": false, "inventory_counts": {"camp_kit": 1}, "actions": [{"id": "rest", "title": "숨 고르기", "description": "완료 시 스트레스 -18", "cost": "온기 1", "duration": 4.0, "enabled": true}]}
	overlay.set_snapshot(snapshot)
	overlay.show_camp()
	await process_frame
	_check(overlay.stress_label.text.contains("85/100 · 극심") and overlay.stress_label.text.contains("높을수록 불안정"), "camp must show actual stress, stage, and danger direction")
	_check(overlay.stats_label.text.contains("51/100") and overlay.stats_label.text.contains("출혈") and overlay.resources_label.text.contains("온기 3"), "camp stress must preserve health, conditions and resources")
	_check(overlay.action_details.rest.text == "완료 시 스트레스 -18", "camp must preserve the core's completion-only relief description")
	snapshot.state = "resting"
	snapshot.progress = 0.6
	snapshot.stress = 67.0
	snapshot.erase("stress_stage")
	overlay.set_snapshot(snapshot)
	_check(overlay.stress_label.text.contains("67/100 · 동요") and overlay.progress_bar.value == 0.6 and not overlay.action_list.visible, "active rest must update stress stage without resetting action progress")
	_check(snapshot.stress == 67.0 and ExpeditionSession.stress == 84.0, "camp UI must never apply stress relief itself")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(480, 320)]:
		viewport.size = size
		overlay._update_layout()
		await process_frame
		await process_frame
		_check(overlay.stress_label.get_global_rect().position.y >= overlay.stats_label.get_global_rect().end.y, "camp stress line must not overlap existing status")
		_check(overlay.stress_label.size.x <= overlay.action_scroll.size.x and overlay.action_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "camp stress must wrap inside the vertical scroller")
		_check(overlay.leave_button.get_global_rect().end.y <= size.y and overlay.leave_button.get_global_rect().end.x <= size.x, "camp interruption must remain reachable with the added stress row")
		if size.y <= 360:
			_check(overlay.action_scroll.get_v_scroll_bar().max_value > overlay.action_scroll.size.y or overlay.status_label.get_global_rect().end.y <= overlay.action_scroll.get_global_rect().end.y, "small camp viewport must either show all resting content or allow vertical scrolling")
	snapshot.stress = 500.0
	overlay.set_snapshot(snapshot)
	_check(overlay.stress_label.text.contains("100/100 · 극심"), "camp stress must clamp to its maximum")
	viewport.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
