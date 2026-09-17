extends SceneTree
## Validate capture safety and production editor routing without claiming pixels.
const PREVIEW := preload("res://tests/item_detail_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := PREVIEW.PRESERVATION.inventory_fingerprint(original_bag)
	var mouse_before := Input.mouse_mode
	var paused_before := paused
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.PRESERVATION.sandbox_snapshot(sandbox)
	var hashes := PREVIEW.collect_source_hashes()
	sandbox.begin()
	check(PREVIEW.shots().size() == 5, "Capture set must contain exactly five bounded production UI examples.")
	for shot in PREVIEW.shots():
		var viewport := PREVIEW.create_viewport(shot.size)
		root.add_child(viewport)
		var bag := PREVIEW.create_inventory()
		var overlay := PREVIEW.create_overlay(viewport, bag)
		check(bag != original_bag and bag != ExpeditionSession.get_inventory(), "The capture bag must be independent of both original and sandbox journey inventories.")
		var action := PREVIEW.configure_shot(overlay, shot)
		for frame in 3:
			await process_frame
		var state := PREVIEW.inspect_shot(viewport, overlay, shot, action)
		for failure in state.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		check(not state.harness_changes_presentation and state.production_portrait_retained, "Capture must retain actual item presentation and the production portrait.")
		check(PREVIEW.execution_isolated(overlay), "No overlay, portrait or child node may poll gameplay or external input during capture.")
		check(Input.mouse_mode == mouse_before, "Editor preparation must not change the desktop cursor.")
		if str(shot.action) == "discard_editor":
			var dropped: Array[Dictionary] = []
			overlay.item_discarded.connect(func(stack: Dictionary) -> void: dropped.append(stack.duplicate(true)))
			var before_quantity := bag.count_item("linen_bandage")
			overlay.item_detail_window.discard_confirm_button.pressed.emit()
			check(dropped.size() == 1 and dropped[0].id == "linen_bandage" and dropped[0].quantity == 2 and bag.count_item("linen_bandage") == before_quantity - 2, "Preview quantity editor must route its real confirmation to inventory removal and the actual drop signal.")
		elif str(shot.item_id) == "patched_mail":
			overlay.item_detail_window.equip_button.pressed.emit()
			check(bag.equipment.body == "patched_mail" and overlay.item_detail_window.equip_button.disabled and overlay.item_detail_window.equip_button.text == "장착 중", "Preview equipment action must route to real equipped state.")
		viewport.free()
		await process_frame
	sandbox.finish()
	paused = paused_before
	var restored := ExpeditionSession.capture_snapshot()
	check(restored == original and restored.inventory == original_bag and PREVIEW.PRESERVATION.inventory_fingerprint(original_bag) == original_bag_hash, "Preview must restore all original journey state and the exact inventory reference/content.")
	check(PREVIEW.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before and Input.mouse_mode == mouse_before, "Preview must restore sandbox state and preserve the desktop cursor.")
	check(PREVIEW.collect_source_hashes() == hashes, "Production and capture sources must remain unchanged during this test.")
	for path in hashes:
		check(not str(hashes[path]).is_empty(), "Capture must fingerprint an existing source: " + str(path))
	for failure in failures:
		push_error(failure)
	print("ITEM DETAIL PREVIEW TEST %s: actual production details/editors, isolated input, responsive bounds, portrait and session preservation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
