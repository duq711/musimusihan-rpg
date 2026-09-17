extends SceneTree

const PREVIEW := preload("res://tests/health_panel_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_hash := PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag)
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox)
	var hashes := PREVIEW.collect_hashes()
	for path in hashes:
		_check(not str(hashes[path]).is_empty(), "Preview must fingerprint every production UI, background, font and shared helper: " + str(path))
	sandbox.begin()
	for shot in PREVIEW.shots():
		var viewport := PREVIEW.HELPERS.create_viewport(shot.size)
		root.add_child(viewport)
		var fixture := PREVIEW.create_fixture(viewport, shot)
		for frame in 3:
			await process_frame
		var report := PREVIEW.inspect_fixture(viewport, fixture, shot)
		for failure in report.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		if str(shot.action) == "injured":
			var bag: ExpeditionInventory = fixture.bag
			var overlay: InventoryOverlay = fixture.overlay
			var before := bag.count_item("healing_draught")
			_check(overlay.health_panel.treatment_popup.is_visible_in_tree(), "Injured reference capture must display the selected-part treatment popup.")
			overlay.health_panel.treatment_buttons.healing_draught.pressed.emit()
			_check(bag.count_item("healing_draught") == before and fixture.player.get_body_health_snapshot().parts.left_arm.health == 0, "Ordinary treatment on the selected blacked part must fail without consuming medicine.")
			overlay.health_panel.part_buttons.left_leg.pressed.emit()
			overlay.health_panel.treatment_buttons.splint.pressed.emit()
			_check(bag.count_item("splint") == 2 and not fixture.player.get_body_health_snapshot().parts.left_leg.conditions.has("fracture"), "Real health-panel splint must clear the selected leg fracture and consume one item.")
			var selected_before_close: String = fixture.player.get_selected_treatment_part()
			overlay.health_panel.popup_close_button.pressed.emit()
			_check(not overlay.health_panel.treatment_popup.is_visible_in_tree() and fixture.player.get_selected_treatment_part() == selected_before_close, "Closing the popup must preserve the real selected treatment target.")
		_check(Input.mouse_mode == mouse_before, "Preview actions must preserve the desktop cursor.")
		viewport.free()
		fixture.player.free()
		await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag) == original_hash and PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before, "Health UI preview must preserve the real expedition, inventory and sandbox.")
	_check(PREVIEW.collect_hashes() == hashes, "Preview preparation must keep all production source and presentation assets unchanged.")
	for failure in failures:
		push_error(failure)
	print("HEALTH PANEL PREVIEW TEST %s: production selection and medicine, zero rejection, surgery repair, fracture cure, responsive UI and isolated capture" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
