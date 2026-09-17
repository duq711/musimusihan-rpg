extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const DROP := preload("res://scripts/dropped_item.gd")
var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("rusted_sword", 1, false, {"item_tag": "원래 원정", "smithing": {"quality": 71.0, "runes": ["ember_rune"]}})
	ExpeditionSession.crowns = 761
	ExpeditionSession.hunger = 54.0
	ExpeditionSession.thirst = 38.0
	ExpeditionSession.stress = 23.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	await physics_frame
	room.player.set_physics_process(false)
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "inventory_details")
	_check(entries.size() == 1 and entries[0].action == "inventory_details" and entries[0].category == "기본", "item details must have exactly one executable Basic catalog entry")
	room.run_feature("inventory_details")
	await physics_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and bag != original and paused and room.inventory_overlay.is_open(), "details fixture must open the actual inventory inside the paused isolated session")
	_check(bag.count_item("rusted_sword") == 1 and bag.count_item("patched_mail") == 1 and bag.count_item("linen_bandage") > 0, "details fixture must supply real catalog weapon, armor and non-equippable stacks")
	var sword_index := _find_slot(bag, "rusted_sword")
	var sword_data := {"item_id": "rusted_sword", "item_tag": "되찾을 검", "smithing": {"quality": 79.0, "grip": "balanced_grip", "sockets": 1, "runes": ["ember_rune"]}}
	bag.slots[sword_index]["instance"] = sword_data.duplicate(true)
	bag.changed.emit()
	_ui_discard(room, "inventory", sword_index, 1)
	var dropped := _only_drop(room)
	_check(bag.count_item("rusted_sword") == 0 and is_instance_valid(dropped), "actual detail discard confirmation must remove the selected stack and emit a real scene drop")
	if is_instance_valid(dropped):
		_check(dropped.stack.instance == sword_data and dropped.stack.quantity == 1, "dropped sword must preserve exact nested smithing and item-tag metadata")
		_check(dropped.get_interaction_prompt().contains("되찾을 검"), "the real pickup prompt must identify the package's item tag")
		_close_bag(room)
		var result := await _collect_real_area(room, dropped)
		_check(bool(result.get("accepted", false)) and int(result.get("moved", 0)) == 1, "E interaction entry point must recover the actual dropped sword")
		await process_frame
		_check(_drops(room).is_empty(), "fully collected drops must remove their visual and interaction area")
		sword_index = _find_slot(bag, "rusted_sword")
		_check(sword_index >= 0 and bag.slots[sword_index].instance == sword_data, "recovered sword must retain its exact tag and upgrades")
		if sword_index >= 0:
			bag.equip_from_slot(sword_index)
			room._open_inventory()
			_ui_discard(room, "equipment", -1, 1, "weapon")
			dropped = _only_drop(room)
			_check(str(bag.equipment.weapon).is_empty() and is_instance_valid(dropped), "equipped-item discard must clear the actual weapon slot and spawn one package")
			if is_instance_valid(dropped):
				_check(dropped.stack.instance == sword_data, "equipped-item discard must preserve the equipped instance")
				_close_bag(room)
				await _collect_real_area(room, dropped)
				await process_frame

	await _check_partial_recovery(room)
	await _check_wall_and_failed_placement(room)
	_close_bag(room)
	_f2_room(room)
	_check(room.panel_open and paused, "F2 after the detail flow must return to the paused test menu")
	room.run_feature("inventory_details")
	await physics_frame
	_ui_discard(room, "inventory", _find_slot(room.inventory, "rusted_sword"), 1)
	_check(_drops(room).size() == 1, "repeated detail trial must still exercise actual world drops")
	_f2_room(room)
	room.run_feature("inventory_details")
	_check(_drops(room).is_empty(), "reselecting the detail fixture must clear previous scene-local dropped packages")
	_ui_discard(room, "inventory", _find_slot(room.inventory, "rusted_sword"), 1)
	_f2_room(room)
	room.reset_room()
	await process_frame
	_check(_drops(room).is_empty() and room.panel_open and paused, "test-room reset must clear dropped objects and retain the paused reset menu")
	_check(original.slots == original_slots and sandbox.saved_session == snapshot, "discard, pickup, equipment and reset trials must preserve the original expedition")

	# The hideout owns a separate world root and a separate inventory host. Use
	# the real connected scene to ensure both hosts subscribe to the same signal.
	room.run_feature("hideout")
	if await _wait_for_scene(HIDEOUT_PATH):
		var hideout := current_scene
		hideout.player.set_physics_process(false)
		await physics_frame
		hideout._open_inventory()
		var hideout_bag: ExpeditionInventory = hideout.inventory
		hideout_bag.add_item("rusted_sword", 1, true, sword_data)
		_ui_discard(hideout, "inventory", _find_slot(hideout_bag, "rusted_sword"), 1)
		var hideout_drop := _only_drop(hideout)
		_check(is_instance_valid(hideout_drop) and hideout_drop.get_parent() == hideout.world_root, "hideout inventory must place the actual dropped item into its 3D world")
		if is_instance_valid(hideout_drop):
			_close_bag(hideout)
			var recovered := await _collect_real_area(hideout, hideout_drop)
			_check(bool(recovered.get("accepted", false)), "hideout drop must use the same real pickup interaction")
			await process_frame
			hideout._open_inventory()
			_ui_discard(hideout, "inventory", _find_slot(hideout_bag, "rusted_sword"), 1)
			_close_bag(hideout)
		var lingering := _only_drop(hideout)
		var f2 := InputEventKey.new()
		f2.keycode = KEY_F2
		f2.pressed = true
		sandbox._input(f2)
		if await _wait_for_scene(ROOM_PATH):
			room = current_scene as Node3D
			_check(not is_instance_valid(lingering) and _drops(room).is_empty(), "F2 scene return must free hideout-local dropped items")
			_check(room.panel_open and paused, "F2 from the hideout must retain the paused isolated trial menu")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and original.slots == original_slots, "leaving all item-detail trials must restore the exact original inventory object, contents and complete expedition snapshot")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("ITEM DROP TEST ROOM PASS: real detail discard buttons, tagged upgraded weapon and equipped drops, real pickup areas, partial/full bag recovery, wall-safe placement, atomic failure rollback, hideout and dungeon hosts, F2 repetition, reset and original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_partial_recovery(room: Node) -> void:
	_close_bag(room)
	room._teleport(Vector3(0.0, 1.0, 9.0))
	var bag: ExpeditionInventory = room.inventory
	var data := {"item_tag": "분할 회수"}
	bag.slots.clear()
	bag.add_item("linen_bandage", 4, false, data)
	for index in range(ExpeditionInventory.MAX_SLOTS - 1):
		bag.add_item("rusted_sword", 1, false)
	bag.changed.emit()
	room._open_inventory()
	_ui_discard(room, "inventory", 0, 4)
	var dropped := _only_drop(room)
	if not is_instance_valid(dropped):
		return
	# Leave one place in an existing matching tagged stack, with all bag slots
	# occupied. Only that one item may move; the other three remain in-world.
	bag.add_item("linen_bandage", 5, true, data)
	_close_bag(room)
	var partial := await _collect_real_area(room, dropped)
	_check(partial.get("moved", 0) == 1 and partial.get("remaining", 0) == 3 and dropped.stack.quantity == 3, "full bag must collect only the available matching-stack capacity and retain the remainder: %s" % str(partial))
	_check(dropped.stack.instance == data and bag.slots[_find_slot(bag, "linen_bandage")].instance == data, "partial tagged-stack recovery must preserve metadata on both portions")
	var full := await _collect_real_area(room, dropped)
	_check(not bool(full.get("accepted", true)) and dropped.stack.quantity == 3, "fully blocked pickup must keep all remaining world items")
	bag.remove_from_slot(_find_slot(bag, "rusted_sword"), 1)
	var last := await _collect_real_area(room, dropped)
	_check(last.get("moved", 0) == 3 and bag.count_item("linen_bandage") == 9, "freeing one bag slot must recover the exact remaining quantity")
	await process_frame
	_check(_drops(room).is_empty(), "last partial pickup must free the package")


func _check_wall_and_failed_placement(room: Node) -> void:
	_close_bag(room)
	room._teleport(Vector3(0.0, 1.0, -16.1))
	await physics_frame
	room._open_inventory()
	_ui_discard(room, "inventory", _find_slot(room.inventory, "rusted_sword"), 1)
	var dropped := _only_drop(room)
	_check(is_instance_valid(dropped), "discarding at a wall must find a nearby valid floor point")
	if is_instance_valid(dropped):
		_check(dropped.global_position.z >= -16.45 and dropped.global_position.y > 0.0 and dropped.global_position.y < 0.08, "dropped package must remain in front of the colliding wall and above the real floor")
		_close_bag(room)
		await _collect_real_area(room, dropped)
		await process_frame
	# A player with no nearby supporting floor must get the exact removed
	# stack/equipment back. This also covers a full bag and a partial stack.
	room.player.position = Vector3(0.0, 100.0, 0.0)
	room._open_inventory()
	var bag: ExpeditionInventory = room.inventory
	var before := bag.slots.duplicate(true)
	_ui_discard(room, "inventory", _find_slot(bag, "linen_bandage"), 2)
	_check(bag.slots == before and _drops(room).is_empty(), "failed floor placement must atomically restore a partially discarded tagged stack")
	_ui_discard(room, "inventory", _find_slot(bag, "rusted_sword"), 1)
	_check(bag.slots == before and _drops(room).is_empty(), "failed floor placement must restore a fully discarded stack at its original position")
	var equipment := bag.equipment.duplicate(true)
	bag.get_equipment_instance("body")
	var equipment_data := bag.equipment_data.duplicate(true)
	_ui_discard(room, "equipment", -1, 1, "body")
	_check(bag.equipment == equipment and bag.equipment_data == equipment_data and bag.slots == before, "failed equipped-item drop must restore equipment atomically without requiring spare bag capacity")
	_close_bag(room)
	room._teleport(Vector3(0.0, 1.0, 9.0))
	await physics_frame


func _ui_discard(host: Node, source: String, index: int, quantity: int, slot := "") -> void:
	var overlay: InventoryOverlay = host.inventory_overlay
	overlay.open_item_details(source, index, slot)
	_check(overlay.item_detail_window.visible, "discard test must operate the real open item detail window")
	overlay.item_detail_window.discard_button.pressed.emit()
	# Enter the amount as the user does. SpinBox updates its displayed text on
	# a later frame after a programmatic value change; immediate confirm calls
	# apply(), which otherwise re-applies the stale initial text of one item.
	overlay.item_detail_window.discard_quantity.get_line_edit().text = str(quantity)
	overlay.item_detail_window.discard_confirm_button.pressed.emit()


func _collect_real_area(host: Node, dropped: Node3D) -> Dictionary:
	await physics_frame
	await physics_frame
	var actor: DungeonPlayer = host.player
	var target := dropped.global_position + Vector3.UP * 0.20
	actor.camera.look_at(target, Vector3.UP)
	var query := PhysicsRayQueryParameters3D.create(actor.camera.global_position, actor.camera.global_position + -actor.camera.global_basis.z * 3.0, DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and is_instance_valid(hit.get("collider")) and hit.collider.get_meta("interaction_owner", null) == dropped, "actual player's interaction ray must resolve the dropped package's real E interaction Area")
	if hit.is_empty():
		return {}
	# Headless cannot capture the mouse. Drive only that input boundary through
	# the same real interaction-owner entry point used by DungeonPlayer's E.
	var owner := hit.collider.get_meta("interaction_owner", null) as Node
	if owner == null or not owner.has_method("interact"):
		return {}
	return owner.interact(actor)


func _close_bag(host: Node) -> void:
	for attempt in range(4):
		if not host.inventory_overlay.is_open():
			return
		host._close_inventory()
	_check(not host.inventory_overlay.is_open(), "detail window, quantity step and inventory must close without trapping gameplay pause")


func _f2_room(room: Node) -> void:
	for attempt in range(4):
		if room.panel_open:
			return
		var f2 := InputEventKey.new()
		f2.keycode = KEY_F2
		f2.pressed = true
		room._unhandled_input(f2)
	_check(room.panel_open, "F2 must finish closing nested item UI and reach the test menu")


func _find_slot(bag: ExpeditionInventory, item_id: String) -> int:
	for index in range(bag.slots.size()):
		if str(bag.slots[index].get("id", "")) == item_id:
			return index
	return -1


func _drops(host: Node) -> Array[Node]:
	var result: Array[Node] = []
	for item in get_nodes_in_group("dropped_item"):
		if host.is_ancestor_of(item) and not item.is_queued_for_deletion():
			result.append(item)
	return result


func _only_drop(host: Node) -> Node3D:
	var items := _drops(host)
	_check(items.size() == 1, "a discard must create exactly one recoverable package")
	return items[0] as Node3D if items.size() == 1 else null


func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "item drop scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
