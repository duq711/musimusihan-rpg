extends SceneTree

var room: Node3D
var player: DungeonPlayer
var chest: DungeonLootChest
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Chest hands preview requires a native display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	player = room.player
	player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room.run_feature("chest")
	for _frame in range(40):
		await physics_frame
		if player.is_on_floor():
			break
	player.set_physics_process(false)
	room.set_process(false)
	room.set_process_unhandled_input(true)
	root.grab_focus()
	await process_frame
	await process_frame
	chest = room.loot_chests[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	var near_position := player.position
	var near_pitch := player._pitch
	player.position.z += 1.0
	var distant_aim := chest.to_global(Vector3(0.0, 0.77, -0.595)) - player.camera.global_position
	player._pitch = atan2(distant_aim.y, Vector2(distant_aim.x, distant_aim.z).length())
	player.head.rotation.x = player._pitch
	await physics_frame
	player._update_interaction(0.0)
	_check(player.interaction_owner == chest and not chest.is_within_hand_reach(player), "distant closed chest must remain focusable with an approach prompt")
	await _interact()
	_check(not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "real distant E must not stretch the bare arms across the room")
	await _capture("chest_hands_approach.png")
	player.position = near_position
	player._pitch = near_pitch
	player.head.rotation.x = near_pitch
	await physics_frame
	player._update_interaction(0.0)
	_check(player.interaction_owner == chest, "real test fixture must aim at the closed chest interaction area")
	await _capture("chest_hands_ready.png")
	await _interact()
	_check(player.is_timed_interacting() and player.chest_equipment_stowed, "native E must begin actual opening and equipment stow")
	if not player.is_timed_interacting():
		await _finish()
		return
	_advance_to(0.08)
	await _capture("chest_hands_stow.png")
	_advance_to(0.26)
	await _capture("chest_hands_reach.png")
	_advance_to(0.48)
	await _capture("chest_hands_fidget.png")
	_check(not player.weapon_pivot.is_visible_in_tree() and not player.shield_pivot.is_visible_in_tree() and not player.torch_pivot.is_visible_in_tree(), "no carried equipment may remain in the bare-hand pose")
	for hand: Node3D in [player.chest_hands.left_hand, player.chest_hands.right_hand]:
		_check(hand.is_visible_in_tree() and not player.camera.is_position_behind(hand.global_position) and root.get_visible_rect().has_point(player.camera.unproject_position(hand.global_position)), "both actual hands must be inside the rendered camera view")
	_advance_to(0.65)
	await _capture("chest_hands_fingers.png")
	_advance_to(0.86)
	await _capture("chest_hands_lift.png")
	_check(chest.lid_pivot.rotation.x > 0.1, "actual visible lid must lift with the hands")
	await _interact()
	_check(not player.is_timed_interacting() and not player.chest_hands.active and not chest.opened and is_zero_approx(chest.lid_pivot.rotation.x) and not player.chest_equipment_stowed, "a second real E must cancel opening and restore both the lid and equipment")
	await _capture("chest_hands_cancelled.png")
	await _interact()
	_advance_to(0.50)
	var camera_rotation := player.camera.rotation
	player.camera.rotate_y(PI)
	player._update_interaction(0.0)
	_check(not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "looking away in captured native gameplay must cancel the actual ray-based interaction")
	player.camera.rotation = camera_rotation
	await _interact()
	_advance_to(1.0)
	_check(chest.opened and room.inventory_overlay.is_open() and paused and player.chest_equipment_stowed, "completed native opening must show the real search UI with gear still stowed")
	await _capture("chest_hands_search.png")
	await _key(KEY_I)
	_check(not paused and not room.inventory_overlay.is_open() and not player.chest_equipment_stowed and player.weapon_pivot.visible, "native inventory close must restore the current weapon")
	await _capture("chest_hands_restored.png")
	# Finally run a fresh opening with normal physics and the real clock,
	# without manual progress advancement or direct interaction calls.
	room.run_feature("chest")
	chest = room.loot_chests[0]
	player.set_physics_process(true)
	for _frame in range(4):
		await physics_frame
	await _key(KEY_E)
	_check(player.is_timed_interacting(), "native E with normal player physics must start a new repeatable opening")
	for _frame in range(120):
		await physics_frame
		if chest.opened or not player.is_timed_interacting():
			break
	player.set_physics_process(false)
	_check(chest.opened and room.inventory_overlay.is_open() and paused and player.chest_equipment_stowed, "unmodified real-time player physics must finish the 1.2-second opening and stow throughout search")
	await _key(KEY_I)
	await _key(KEY_F2)
	room._select_category("기본")
	await _capture("chest_hands_test_menu.png")
	_check(room.panel_open and paused, "native F2 must keep the repeatable real chest fixture accessible")
	if OS.get_environment("CHEST_HANDS_QA_INTERACTIVE") == "1":
		player.set_physics_process(true)
		player.set_process_unhandled_input(true)
		room.set_process(true)
		return
	await _finish()


func _advance_to(value: float) -> void:
	player.advance_timed_interaction(maxf(0.0, value * player.timed_interaction_duration - player.timed_interaction_elapsed))


func _interact() -> void:
	# Inject on an idle frame, even when the caller just awaited physics;
	# Godot tracks just-pressed state separately for those two frame clocks.
	await process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(Input.is_action_just_pressed("interact"), "native E event must reach the registered interact action")
	# Physics is frozen only for stable captures. Exercise its real ray and
	# action input path explicitly, not chest.interact() or a mock animation.
	player._update_interaction(0.0)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name)) == OK, "native capture saved: " + file_name)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("CHEST HANDS PREVIEW PASS: actual E, stow, bare-hand reach/fidget/lift, cancel, look-away, search, restore and F2 fixture")
		quit(0)
	else:
		for failure in failures:
			push_error("CHEST HANDS PREVIEW FAIL: " + failure)
		quit(1)
