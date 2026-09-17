extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.ensure_journey()
	var snapshot := ExpeditionSession.capture_snapshot()
	var original_inventory := ExpeditionSession.get_inventory()
	var mouse_mode := Input.mouse_mode
	var chest := DungeonLootChest.new()
	chest.configure("Surface reference", [{"id": "healing_potion", "count": 1}])
	root.add_child(chest)
	await process_frame
	var model := chest.get_node("ReliquaryChestVisual") as Node3D
	var joinery := model.get_node_or_null("AgedChestJoinery") as Node3D
	_check(joinery != null, "Live chest uses reference joinery")
	if joinery != null:
		_check(joinery.find_children("VerticalOakBoard*", "MeshInstance3D", false, false).size() == 20, "Front and rear use ten vertical boards each")
		_check(joinery.find_children("SideOakBoard*", "MeshInstance3D", false, false).size() == 12, "Both sides have separate planks")
		_check(joinery.find_children("UndersideOakBrace*", "MeshInstance3D", false, false).size() == 3, "Bottom view has production floor braces")
		var rivets := joinery.get_node("HandForgedRivets") as MultiMeshInstance3D
		_check(rivets.multimesh.instance_count >= 70, "Visible metal fasteners share one instanced draw")
		for transform_value in rivets.get_meta("rivet_transforms"):
			_check((transform_value as Transform3D).is_finite(), "All production rivet transforms are finite")
	var board := model.find_child("VerticalOakBoard*", true, false) as MeshInstance3D
	if board != null:
		_check(board.material_override.get_meta("dark_fantasy_surface", "") == "oak", "Live boards use shared oak shading")
	_check(chest.rune_material.emission_energy_multiplier <= 0.4, "Lock seal follows subdued verdigris reference")
	_check(chest.lid_pivot.find_children("LidSlat*", "Node3D", true, false).size() == 7, "All seven actual contact slats still move with the hinge")
	var child_count := model.get_child_count()
	DungeonLootChest.apply_concept_surface(model)
	_check(model.get_child_count() == child_count, "Repeated styling does not duplicate geometry")
	_check(chest.state == DungeonLootChest.ChestState.CLOSED and not chest.opened, "Styling preserves chest state")
	_check(ExpeditionSession.get_inventory() == original_inventory, "Styling never replaces expedition inventory")
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse_mode, "Styling leaves expedition and input state unchanged")
	chest.queue_free()
	await process_frame
	if failures.is_empty():
		print("DARK FANTASY CHEST TEST PASS: real joinery, underside, instanced fasteners, hinge frames and session safety")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY CHEST TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
