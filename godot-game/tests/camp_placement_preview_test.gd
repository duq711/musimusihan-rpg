extends SceneTree
const PREVIEW := preload("res://tests/camp_placement_preview.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag)
	var cursor := Input.mouse_mode
	var paused_before := paused
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox)
	var hashes := PREVIEW.collect_hashes()
	var failures: Array[String] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	for shot in PREVIEW.shots():
		var viewport := PREVIEW.HELPERS.create_viewport(shot.size)
		root.add_child(viewport)
		var fixture := await PREVIEW.create_fixture(viewport, shot)
		for frame in 4:
			await process_frame
		var report := PREVIEW.inspect_fixture(viewport, fixture, shot)
		for failure in report.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		if PREVIEW.collect_hashes() != hashes: failures.append(str(shot.id) + ": source changed during fixture")
		viewport.free()
		paused = false
		await process_frame
	sandbox.finish()
	paused = paused_before
	if ExpeditionSession.capture_snapshot() != original or PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag) != original_bag_hash or Input.mouse_mode != cursor or PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox) != sandbox_before:
		failures.append("Original expedition, inventory, sandbox or cursor changed")
	for failure in failures: push_error(failure)
	print("CAMP PLACEMENT PREVIEW TEST %s: actual floor contact, red/green placement, deployed tent, seated cooking and responsive menus" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
