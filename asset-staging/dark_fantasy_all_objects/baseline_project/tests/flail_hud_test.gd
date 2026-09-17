extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := DungeonHUD.new()
	root.add_child(hud)
	await process_frame
	await process_frame
	_check(not hud.flail_panel.visible, "flail panel must start hidden")
	_test_states(hud)
	_test_exclusive_panels(hud)
	_test_layout(hud)
	hud.free()
	if failures.is_empty():
		print("FLAIL HUD TEST PASS: six states, real damage/range/cost, charge cap, return lockout, mutually exclusive weapon panels and slim meter layout")
		quit(0)
	else:
		for failure in failures:
			push_error("FLAIL HUD TEST FAIL: " + failure)
		quit(1)


func _test_states(hud: DungeonHUD) -> void:
	hud.update_flail(true, "ready", 0.0, 0.0)
	_check(hud.flail_panel.visible and hud.flail_title_label.text.contains("준비"), "equipped ready flail must show its ready panel")
	_check(hud.flail_detail_label.text.contains("근접 피해 32 · 기력 18") and hud.flail_detail_label.text.contains("회전 시작 기력 24"), "ready panel must show real melee damage and both action costs")
	_check(hud.flail_detail_label.text.contains("유지 추가 소모 없음"), "holding must not be described as a continuous stamina drain")
	_check(hud.flail_help_label.text.contains("LMB 휘두르기") and hud.flail_help_label.text.contains("RMB 길게 회전/놓아 던지기"), "ready panel must explain both mouse actions")
	_check(not hud.flail_charge_bar.visible, "idle flail must not imply an active charge")
	_check_text_fits(hud)
	for sample: Dictionary in [
		{"charge": -1.0, "damage": 28, "range": 6.0},
		{"charge": 0.0, "damage": 28, "range": 6.0},
		{"charge": 0.5, "damage": 44, "range": 10.0},
		{"charge": 1.0, "damage": 60, "range": 14.0},
		{"charge": 2.0, "damage": 60, "range": 14.0},
	]:
		var charge := float(sample.charge)
		hud.update_flail(true, "spinning", charge, 0.0)
		_check(hud.flail_charge_bar.visible and is_equal_approx(hud.flail_charge_bar.value, clampf(charge, 0.0, 1.0) * 100.0), "spin bar must display the clamped actual charge")
		_check(hud.flail_detail_label.text.contains("투척 피해 %d" % int(sample.damage)) and hud.flail_detail_label.text.contains("사거리 %.1fm" % float(sample.range)), "spin readout must match the shared damage/range curves")
		_check(hud.flail_title_label.text.contains("최대") == (charge >= 1.0), "maximum power must be marked only at full charge")
		_check(hud.flail_detail_label.text.contains("기력 24 지불") and hud.flail_detail_label.text.contains("유지 추가 소모 없음"), "spinning must show the once-paid cost without an ongoing drain")
		_check(hud.flail_help_label.text.contains("RMB 놓아 던지기") and hud.flail_help_label.text.contains("0.35초"), "spin instructions must explain release and the quick-click minimum windup")
		_check_text_fits(hud)
	for state: String in ["outbound", "returning"]:
		hud.update_flail(true, state, 1.0, 0.0)
		_check(hud.flail_title_label.text.contains("투척 중" if state == "outbound" else "회수 중"), "flight title must distinguish outbound and return phases")
		_check(hud.flail_detail_label.text.contains("재공격 불가") and hud.flail_detail_label.text.contains("회수 중에는 피해 없음") and hud.flail_detail_label.text.contains("무기 소모 없음"), "flight must explain the return lockout, no return damage and reusable weapon")
		_check(not hud.flail_charge_bar.visible and is_zero_approx(hud.flail_charge_bar.value), "flight must clear the previous spin meter")
		_check_text_fits(hud)
	hud.update_flail(true, "melee", 0.0, 0.0)
	_check(hud.flail_title_label.text.contains("근접 휘두르기") and not hud.flail_charge_bar.visible, "melee must have its own non-spin presentation")
	_check_text_fits(hud)
	hud.update_flail(true, "recovery", 1.0, 0.25)
	_check(hud.flail_title_label.text.contains("자세 회복") and hud.flail_help_label.text.contains("다시 공격"), "recovery must communicate when actions become available")
	_check_text_fits(hud)
	hud.update_flail(true, "recovery", 0.0, -1.0)
	_check(not hud.flail_title_label.text.contains("-1"), "recovery time must not display negative remaining time")
	hud.update_flail(true, "ready", 0.0, 0.0)
	_check(hud.flail_title_label.text.contains("준비") and not hud.flail_detail_label.text.contains("재공격 불가"), "cancel or completed return must clear stale lockout text")


func _test_exclusive_panels(hud: DungeonHUD) -> void:
	hud.update_archery(true, 12, 0.5, true, 0.0, 3.0)
	hud.update_flail(true, "spinning", 0.5, 0.0)
	_check(hud.flail_panel.visible and not hud.archery_panel.visible and not hud.magic_panel.visible, "flail must replace bow and staff panels")
	_check(not hud.bow_spread_reticle.visible and not hud._archery_reticle_should_show(true), "switching to flail must suppress stale bow reticle eligibility")
	_check(hud.control_legend_label.text.contains("RMB 회전/투척") and not hud.control_legend_label.text.contains("RMB 방패"), "flail controls must not advertise shield guarding")
	hud.update_archery(true, 12, 0.0, false, 0.0, 12.0)
	_check(hud.archery_panel.visible and not hud.flail_panel.visible, "bow must replace the flail panel in either call order")
	hud.update_flail(true, "ready", 0.0, 0.0)
	hud.update_magic([], "", true)
	_check(hud.magic_panel.visible and not hud.flail_panel.visible and not hud.archery_panel.visible, "staff must replace the flail panel")
	hud.update_flail(false, "ready", 0.0, 0.0)
	_check(hud.magic_panel.visible and not hud.flail_panel.visible, "unequipped flail refresh must not hide another active weapon panel")
	hud.update_flail(true, "ready", 0.0, 0.0)
	hud.update_flail(false, "ready", 0.0, 0.0)
	_check(not hud.flail_panel.visible, "unequipped or safe-zone flail must hide its panel")


func _test_layout(hud: DungeonHUD) -> void:
	_check(hud.flail_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "flail UI must not consume gameplay input")
	_check(hud.flail_detail_label.position.y >= hud.flail_title_label.position.y + hud.flail_title_label.size.y, "flail detail must sit below its title")
	_check(hud.flail_charge_bar.position.y >= hud.flail_detail_label.position.y + hud.flail_detail_label.size.y, "charge bar must sit below both detail rows")
	_check(hud.flail_charge_bar.size.y <= 6.0, "flail meter must remain slim after theme invalidation")
	_check(hud.flail_help_label.position.y >= hud.flail_charge_bar.position.y + hud.flail_charge_bar.size.y, "instruction row must not overlap the meter")
	_check(hud.flail_help_label.position.y + hud.flail_help_label.size.y <= hud.flail_panel.size.y - 8.0, "panel must contain all rows with bottom padding")


func _check_text_fits(hud: DungeonHUD) -> void:
	for label: Label in [hud.flail_title_label, hud.flail_detail_label, hud.flail_help_label]:
		_check(label.get_minimum_size().x <= 434.0, "flail text must fit without clipping: " + label.text)
	_test_layout(hud)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
