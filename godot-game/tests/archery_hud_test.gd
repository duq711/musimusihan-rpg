extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := DungeonHUD.new()
	root.add_child(hud)
	await process_frame
	await process_frame
	_test_projection_and_readout(hud)
	_test_draw_reticle_lifecycle(hud)
	await _test_viewport_projection()
	_test_damage_stamina_readout(hud)
	_test_slack_and_exhaustion_readout(hud)
	_test_visibility_gates(hud)
	_test_panel_layout(hud)
	hud.free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("ARCHERY HUD TEST PASS: slack drop warning, exhaustion auto-release guidance, compact/enlarged/contracting crosshair, viewport/FOV projection, cancel reset, damage/stamina readouts and layout/visibility regression")
		quit(0)
	else:
		for failure in failures:
			push_error("ARCHERY HUD TEST FAIL: " + failure)
		quit(1)


func _test_projection_and_readout(hud: DungeonHUD) -> void:
	hud.update_archery(true, 12, 0.0, true, 0.0, 12.0, 76.0)
	var weak_radius := hud.bow_spread_radius
	var expected_radius := 4.0 + hud.get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(38.0)) * tan(deg_to_rad(12.0))
	_check(is_equal_approx(weak_radius, expected_radius), "drawing spread must add the projected cone to the compact center gap")
	_check_reticle_shape(hud, expected_radius, 15.0, "draw start")
	_check(hud.bow_accuracy_label.text.contains("바로 아래로 떨어짐") and not hud.bow_accuracy_label.text.contains("±"), "zero draw must warn about a straight-down drop instead of claiming a forward spread cone")
	_check(hud.archery_title_label.text.contains("피해 18") and hud.arrow_count_label.text == "화살 12발", "accuracy feedback must preserve actual damage and ammunition readouts")
	_check(hud.bow_stamina_label.text.contains("기력 -22/초"), "weak draw must show the continuous stamina drain rather than an upfront shot cost")
	var weak_color := (hud.bow_spread_ticks[0].get_node("Ink") as ColorRect).color
	_check(weak_color.r > weak_color.g and weak_color.g > weak_color.b, "weak draw must have an amber warning color")
	hud.update_archery(true, 12, 0.5, true, 0.0, 3.0, 76.0)
	var middle_radius := hud.bow_spread_radius
	_check(middle_radius < weak_radius and middle_radius > 4.0, "half draw must visibly contract the aiming ticks")
	_check_reticle_shape(hud, middle_radius, 12.0, "half draw")
	_check(hud.bow_accuracy_label.text.contains("±3.0°") and is_equal_approx(hud.bow_draw_bar.value, 50.0), "half draw must display its real spread and charge")
	hud.update_archery(true, 12, 1.0, true, 0.0, 0.0, 76.0)
	_check(is_equal_approx(hud.bow_spread_radius, 4.0), "full draw must retain only the small center aiming gap")
	_check_reticle_shape(hud, 4.0, 9.0, "full draw")
	_check(hud.bow_accuracy_label.text.contains("정조준") and not hud.bow_accuracy_label.text.contains("±"), "full draw must clearly indicate a steady aim")
	_check(hud.archery_title_label.text.contains("100%") and hud.archery_title_label.text.contains("최대 피해 46"), "full draw must clearly identify its maximum base damage")
	var full_color := (hud.bow_spread_ticks[0].get_node("Ink") as ColorRect).color
	_check(full_color.g > full_color.r and full_color.g > full_color.b, "full draw must turn the ticks pale green")
	_check(hud.bow_spread_ticks[0].position.x + hud.bow_spread_ticks[0].size.x == -hud.bow_spread_radius, "left tick inner edge must match the cone radius")
	_check(hud.bow_spread_ticks[1].position.x == hud.bow_spread_radius, "right tick inner edge must match the cone radius")
	_check(hud.bow_spread_ticks[2].position.y + hud.bow_spread_ticks[2].size.y == -hud.bow_spread_radius, "top tick inner edge must match the cone radius")
	_check(hud.bow_spread_ticks[3].position.y == hud.bow_spread_radius, "bottom tick inner edge must match the cone radius")
	hud.update_archery(true, 12, 0.0, true, 0.0, 12.0, 90.0)
	_check(hud.bow_spread_radius < weak_radius, "a wider vertical camera FOV must reduce the projected spread radius")
	_check(hud.bow_spread_reticle.mouse_filter == Control.MOUSE_FILTER_IGNORE, "reticle must not intercept gameplay input")


func _test_draw_reticle_lifecycle(hud: DungeonHUD) -> void:
	hud.update_archery(true, 12, 0.0, false, 0.0, 12.0)
	_check_reticle_shape(hud, 4.0, 9.0, "loaded idle bow")
	_check(hud.bow_accuracy_label.text.contains("바로 아래로 떨어짐"), "compact idle aim must explain that immediately releasing will drop the arrow")
	_check(hud.crosshair.text == "·" and hud.bow_spread_reticle.get_child_count() == 4, "the original center dot and four cross ticks must remain the reticle shape")
	var previous_radius := hud.bow_spread_radius
	var previous_length := hud.bow_spread_tick_length
	hud.update_archery(true, 12, 0.0, true, 0.0, 12.0)
	_check(hud.bow_spread_radius > previous_radius and hud.bow_spread_tick_length > previous_length, "pressing draw must immediately enlarge both the gap and tick length")
	previous_radius = hud.bow_spread_radius
	previous_length = hud.bow_spread_tick_length
	for step in range(1, 101):
		var charge := float(step) / 100.0
		var spread := BowShotProfile.spread_degrees(charge)
		hud.update_archery(true, 12, charge, true, 0.0, spread)
		_check(hud.bow_spread_radius < previous_radius and hud.bow_spread_tick_length < previous_length, "both reticle dimensions must strictly contract on every charge step through 100%%: %d" % step)
		_check(is_equal_approx(hud.bow_spread_tick_length, lerpf(15.0, 9.0, charge)), "tick length must interpolate from 15 to 9 pixels with draw charge")
		if step < 100:
			_check(hud.bow_spread_radius > 4.0, "the reticle must not reach the compact gap before full draw: %d" % step)
		previous_radius = hud.bow_spread_radius
		previous_length = hud.bow_spread_tick_length
	_check_reticle_shape(hud, 4.0, 9.0, "exact 100% draw")
	for charge: float in [0.9, 0.95, 0.97, 0.99, 0.999]:
		hud.update_archery(true, 12, charge, true, 0.0, BowShotProfile.spread_degrees(charge))
		_check(hud.bow_spread_radius > 4.0 and hud.bow_spread_tick_length > 9.0, "late draw must remain larger than full draw even when the projected spread is below 4 pixels")
	for charge: float in [1.0, 1.5, 2.0]:
		# Full draw has no launch spread, even if stale caller data still carries
		# the weak-shot cone. Continued holding must preserve the original shape.
		hud.update_archery(true, 12, charge, true, 0.0, 12.0)
		_check_reticle_shape(hud, 4.0, 9.0, "full or over-full hold")
	for stale_charge: float in [0.0, 0.5, 1.0, 2.0]:
		hud.update_archery(true, 12, 0.0, true, 0.0, 12.0)
		hud.update_archery(true, 12, stale_charge, false, 0.0, 12.0)
		_check_reticle_shape(hud, 4.0, 9.0, "cancel with stale charge")
		_check(hud.bow_accuracy_label.text.contains("바로 아래로 떨어짐"), "idle warning must reset to immediate-drop behavior regardless of stale charge")
	for gate: Dictionary in [
		{"equipped": true, "arrows": 12, "cooldown": 0.55},
		{"equipped": true, "arrows": 0, "cooldown": 0.0},
		{"equipped": false, "arrows": 12, "cooldown": 0.0},
	]:
		hud.update_archery(true, 12, 0.25, true, 0.0, BowShotProfile.spread_degrees(0.25))
		hud.update_archery(bool(gate.equipped), int(gate.arrows), 0.25, false, float(gate.cooldown), 12.0)
		_check_reticle_shape(hud, 4.0, 9.0, "release, exhaustion or weapon switch")
		_check(not hud._archery_reticle_should_show(true), "non-aiming states must keep their existing visibility gates")


func _test_viewport_projection() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var hud := DungeonHUD.new()
	viewport.add_child(hud)
	await process_frame
	var charge := 0.25
	var spread := BowShotProfile.spread_degrees(charge)
	hud.update_archery(true, 12, charge, true, 0.0, spread, 76.0)
	var short_radius := hud.bow_spread_radius
	var expected := 4.0 + 180.0 / tan(deg_to_rad(38.0)) * tan(deg_to_rad(spread))
	_check_reticle_shape(hud, expected, 13.5, "360px viewport")
	viewport.size = Vector2i(1280, 720)
	hud._update_archery_reticle_geometry()
	_check(is_equal_approx(hud.bow_spread_radius - 4.0, 2.0 * (short_radius - 4.0)), "resizing viewport height must reproject the expanded gap without scaling its compact center gap")
	var tall_radius := hud.bow_spread_radius
	viewport.size = Vector2i(640, 720)
	hud._update_archery_reticle_geometry()
	_check(is_equal_approx(hud.bow_spread_radius, tall_radius), "width-only resize must not change a vertical-FOV reticle")
	hud.update_archery(true, 12, charge, true, 0.0, spread, 90.0)
	expected = 4.0 + 360.0 * tan(deg_to_rad(spread))
	_check_reticle_shape(hud, expected, 13.5, "90 degree FOV")
	_check(hud.bow_spread_radius < tall_radius, "wider camera FOV must reduce drawing projection at fixed viewport height")
	for drawing: bool in [false, true]:
		hud.update_archery(true, 12, 1.0, drawing, 0.0, 12.0, 90.0)
		_check_reticle_shape(hud, 4.0, 9.0, "idle or full draw after resize")
	viewport.free()


func _check_reticle_shape(hud: DungeonHUD, radius: float, length: float, context: String) -> void:
	_check(is_equal_approx(hud.bow_spread_radius, radius), "reticle gap must match the expected size: " + context)
	_check(is_equal_approx(hud.bow_spread_tick_length, length), "reticle ticks must match the expected length: " + context)
	_check(hud.bow_spread_ticks.size() == 4, "crosshair must keep exactly four aiming ticks: " + context)
	if hud.bow_spread_ticks.size() != 4:
		return
	var positions: Array[Vector2] = [Vector2(-radius - length, -2.0), Vector2(radius, -2.0), Vector2(-2.0, -radius - length), Vector2(-2.0, radius)]
	for index in range(4):
		var tick := hud.bow_spread_ticks[index]
		var expected_size := Vector2(length, 4.0) if index < 2 else Vector2(4.0, length)
		_check(tick.position.is_equal_approx(positions[index]) and tick.size.is_equal_approx(expected_size), "cross tick geometry must preserve its original orientation and 4px thickness: %s tick %d" % [context, index])
		_check(tick.mouse_filter == Control.MOUSE_FILTER_IGNORE, "resizing reticle ticks must not intercept gameplay input")


func _test_damage_stamina_readout(hud: DungeonHUD) -> void:
	for sample: Dictionary in [
		{"charge": -0.2, "damage": 18, "percent": 0},
		{"charge": 0.0, "damage": 18, "percent": 0},
		{"charge": 0.5, "damage": 32, "percent": 50},
		{"charge": 1.0, "damage": 46, "percent": 100},
		{"charge": 1.5, "damage": 46, "percent": 100},
	]:
		var charge := float(sample.charge)
		hud.update_archery(true, 12, charge, true, 0.0, BowShotProfile.spread_degrees(charge))
		_check(hud.archery_title_label.text.contains("피해 %d" % int(sample.damage)), "draw readout must follow the actual clamped damage curve")
		_check(hud.archery_title_label.text.contains("시위 %d%%" % int(sample.percent)), "draw readout must keep clamped charge visible alongside damage")
		_check(hud.archery_title_label.text.contains("최대") == (charge >= 1.0), "maximum damage indicator must appear only at full draw")
		_check(hud.bow_stamina_label.text.contains("기력 -22/초"), "holding must keep displaying stamina drain at every charge, including full draw")
		_check(hud.bow_stamina_label.text.contains("완전 당김도 소모") == (charge >= 1.0), "full draw must explicitly warn that holding still drains stamina")
		_check(hud.bow_stamina_label.text.contains("고갈 시") and hud.bow_stamina_label.text.contains("자동 발사"), "every draw stage must warn that exhaustion releases the arrow automatically")
		_check_text_fits(hud)
	hud.update_archery(true, 12, 0.0, false, 0.0, 12.0)
	_check(hud.archery_title_label.text.contains("피해 18~46"), "ready bow must advertise its damage range")
	_check(hud.bow_stamina_label.text.contains("당김·유지 기력 22/초") and hud.bow_stamina_label.text.contains("발사 추가 소모 없음"), "ready bow must explain both the holding cost and the absence of an extra release cost")
	_check(not hud.bow_stamina_label.text.contains("기력 -"), "canceled or released draw must not continue displaying active stamina drain")
	_check_text_fits(hud)
	hud.update_archery(true, 12, 0.0, false, 0.5, 12.0)
	_check(not hud.bow_stamina_label.text.contains("기력 -"), "recovery must not display active stamina drain")
	_check_text_fits(hud)
	hud.update_archery(true, 0, 0.0, false, 0.0, 12.0)
	_check(hud.archery_title_label.text.contains("화살 없음") and not hud.bow_stamina_label.text.contains("기력 -"), "empty ammunition must retain its warning without implying an active draw")
	_check_text_fits(hud)


func _test_slack_and_exhaustion_readout(hud: DungeonHUD) -> void:
	for charge: float in [-0.5, 0.0, 0.05, 0.1]:
		hud.update_archery(true, 12, charge, true, 0.0, BowShotProfile.spread_degrees(charge))
		_check(hud.bow_accuracy_label.text.contains("힘 부족") and hud.bow_accuracy_label.text.contains("바로 아래로 떨어짐"), "all slack draws through 10% inclusive must warn of a straight-down release")
		_check(not hud.bow_accuracy_label.text.contains("±") and not hud.bow_accuracy_label.text.contains("정조준"), "slack release must not be described as either a forward spread cone or a steady shot")
		_check(hud.bow_stamina_label.text.contains("현재 힘으로 자동 발사"), "weak auto-release guidance must explain that exhaustion uses current draw power")
		_check_text_fits(hud)
	for charge: float in [0.100001, 0.25, 0.5, 0.9]:
		var spread := BowShotProfile.spread_degrees(charge)
		hud.update_archery(true, 12, charge, true, 0.0, spread)
		_check(not hud.bow_accuracy_label.text.contains("힘 부족") and not hud.bow_accuracy_label.text.contains("바로 아래로"), "the drop-only warning must stop immediately above the slack threshold")
		_check(hud.bow_accuracy_label.text.contains("±%.1f°" % spread), "powered shots must continue displaying their actual launch spread")
		_check_text_fits(hud)
	hud.update_archery(true, 12, 1.0, true, 0.0, 0.0)
	_check(hud.bow_accuracy_label.text.contains("정조준"), "full draw must preserve its steady-aim indication")
	_check(hud.bow_stamina_label.text.contains("완전 당김도 소모") and hud.bow_stamina_label.text.contains("고갈 시 자동 발사"), "full hold must show both ongoing drain and exhaustion auto-release")
	_check_text_fits(hud)
	# The player owns automatic release. Verify its resulting ammo/cooldown
	# presentation without introducing a second firing simulation in the HUD.
	hud.update_archery(true, 11, 0.0, false, 0.55, 12.0)
	_check(hud.arrow_count_label.text == "화살 11발" and hud.archery_title_label.text.contains("다음 화살 준비"), "automatic release must present the real consumed arrow and shot recovery")
	_check(not hud.bow_stamina_label.text.contains("기력 -") and not hud._archery_reticle_should_show(true), "automatic release must clear active holding feedback")
	_check_reticle_shape(hud, 4.0, 9.0, "exhaustion auto-release recovery")
	_check_text_fits(hud)
	var bow_description := str(ExpeditionInventory.ITEM_DEFINITIONS.hunting_bow.description)
	_check(bow_description.contains("0.1초 이하") and bow_description.contains("아래로 떨어집니다"), "bow item description must explain immediate-drop behavior")
	_check(bow_description.contains("현재 당긴 힘으로 화살 1발을 자동 발사") and not bow_description.contains("자동 취소"), "bow item description must describe exhaustion as one charged release rather than cancellation")
	_check(bow_description.contains("추가 기력 비용은 없습니다") and bow_description.contains("취소하면 화살은 보존"), "item description must distinguish no release surcharge from voluntary cancellation")


func _test_visibility_gates(hud: DungeonHUD) -> void:
	hud.update_archery(true, 12, 0.0, false, 0.0, 12.0)
	_check(hud._archery_reticle_should_show(true), "loaded idle bow must allow its aiming reticle")
	_check(not hud._archery_reticle_should_show(false), "inventory or unlocked mouse must suppress aiming ticks")
	paused = true
	_check(not hud._archery_reticle_should_show(true), "paused F2 menu must suppress aiming ticks even if the mouse was still captured")
	paused = false
	hud.show_overlay("시험", "결과 화면")
	_check(not hud._archery_reticle_should_show(true) and not hud.bow_spread_reticle.visible, "result/death overlay must immediately hide aiming ticks")
	hud.hide_overlay()
	_check(hud._archery_reticle_should_show(true), "closing an overlay must restore eligibility to aim")
	hud.show_trap_meter("함정", 0.4, 0.6)
	_check(not hud._archery_reticle_should_show(true), "trap minigame must not retain bow aiming ticks")
	hud.hide_trap_meter()
	hud.show_interaction_progress("보급 상자", 1.0)
	_check(not hud._archery_reticle_should_show(true), "timed interaction must suppress bow aiming ticks")
	hud.hide_interaction_progress()
	_check(hud._archery_reticle_should_show(true), "finishing interactions must restore eligibility to aim")
	hud.update_archery(true, 0, 0.0, false, 0.0, 12.0)
	_check(not hud._archery_reticle_should_show(true), "empty ammunition must hide the reticle")
	hud.update_archery(true, 12, 0.0, false, 0.5, 12.0)
	_check(not hud._archery_reticle_should_show(true), "nocking cooldown must hide the reticle")
	hud.update_archery(false, 12, 0.0, false, 0.0, 12.0)
	_check(not hud.archery_panel.visible and not hud.bow_spread_reticle.visible and not hud._archery_reticle_should_show(true), "safe zones and switching away from bow must hide all bow aiming feedback")
	hud.update_magic([], "", true)
	_check(hud.magic_panel.visible, "staff HUD must still work after the bow is hidden")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.update_archery(true, 12, 0.0, false, 0.0, 12.0)
		_check(hud.bow_spread_reticle.visible and not hud.magic_panel.visible, "captured gameplay must show the reticle and replace the staff panel")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud._process(0.0)
		_check(not hud.bow_spread_reticle.visible, "HUD processing must clear a reticle after inventory unlocks the mouse")


func _test_panel_layout(hud: DungeonHUD) -> void:
	_check(hud.bow_draw_bar.size.y <= 6.0, "draw meter must stay slim after theme minimum-size invalidation")
	_check(hud.bow_accuracy_label.position.y >= hud.archery_title_label.position.y + hud.archery_title_label.size.y, "accuracy text must not overlap the title")
	_check(hud.bow_stamina_label.position.y >= hud.bow_accuracy_label.position.y + hud.bow_accuracy_label.size.y, "continuous cost must have its own non-overlapping row")
	_check(hud.bow_draw_bar.position.y >= hud.bow_stamina_label.position.y + hud.bow_stamina_label.size.y, "meter must sit below the stamina text")
	_check(hud.bow_draw_bar.position.y + hud.bow_draw_bar.size.y <= hud.archery_help_label.position.y, "draw meter must not overlap the instruction row")
	_check(hud.archery_help_label.position.y + hud.archery_help_label.size.y <= hud.archery_panel.size.y - 8.0, "bow panel must contain all four text rows and the slim meter with bottom padding")
	_check(hud.archery_title_label.position.x + hud.archery_title_label.size.x <= hud.arrow_count_label.position.x, "damage title must not overlap ammunition count")


func _check_text_fits(hud: DungeonHUD) -> void:
	_check(hud.archery_title_label.get_minimum_size().x <= 310.0, "damage and empty-ammo titles must fit their reserved width")
	for label: Label in [hud.bow_accuracy_label, hud.bow_stamina_label, hud.archery_help_label]:
		_check(label.get_minimum_size().x <= 434.0, "archery text must fit the panel without clipping: " + label.text)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
