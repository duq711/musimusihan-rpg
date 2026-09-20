extends SceneTree

const CAMP_TEST := preload("res://tests/camp_test_helpers.gd")

var room: Node3D
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cooking preview requires a native display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room.run_feature("cooking")
	for _frame in range(40):
		await physics_frame
		if room.player.is_on_floor() and room.player.trap_lockout <= 0.0:
			break
	room.player.set_physics_process(false)
	room.set_process(false)
	room.camp.set_process(false)
	root.grab_focus()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _capture("cooking_test_fixture.png")
	CAMP_TEST.deploy_and_open(room.camp)
	_check(room.camp.is_open() and paused and room.player.camping, "real placement and tent interaction must open the actual paused camp")
	if not room.camp.is_open():
		await _finish()
		return
	var overlay: CampOverlay = room.camp.overlay
	await _click(overlay.category_buttons.cooking.get_global_rect().get_center())
	_check(overlay.selected_category == "cooking", "actual cooking tab click must reveal recipe cards")
	await _capture("cooking_recipes.png")
	_check(overlay.action_ingredients["cook:mushroom_soup"].text.contains("식용 버섯 4 / 2"), "recipe must display exact owned and required mushroom quantities")
	var initial_kit: int = room.inventory.count_item("camp_kit")
	await _click_action("cook:roast_meat")
	_check(room.camp.state == "resting" and not paused and room.camp.get_snapshot().is_cooking, "actual roast button must begin live cooking")
	room.camp.advance_rest(2.0)
	await _capture("cooking_roast_raw.png")
	var tools_root: Node3D = room.camp.camp_visual.get_node("CookingTools")
	var skewer: Node3D = tools_root.get_node("RoastingSpit/SpitSkewer")
	var previous_rotation := skewer.rotation.x
	room.camp.advance_rest(4.0)
	await _capture("cooking_roast_browned.png")
	_check(tools_root.is_visible_in_tree() and tools_root.get_node("RoastingSpit").is_visible_in_tree() and not tools_root.get_node("SoupPot").is_visible_in_tree() and skewer.rotation.x != previous_rotation, "actual roast must turn and brown on its own spit")
	_check_visual_in_view(skewer)
	room.camp.advance_rest(2.0)
	_check(room.camp.state == "planning" and paused and room.camp.last_result.cooked_and_eaten and room.camp.warmth == 2, "finishing the roast must eat once and return to paused planning")
	_check(not tools_root.visible and room.inventory.count_item("raw_meat") == 2, "finished food must consume actual meat and leave no ongoing cooking geometry")
	await _capture("cooking_roast_eaten.png")
	await _click_action("cook:mushroom_soup")
	room.camp.advance_rest(5.0)
	await _capture("cooking_mushroom_soup.png")
	_check(tools_root.get_node("SoupPot").is_visible_in_tree() and not tools_root.get_node("RoastingSpit").is_visible_in_tree(), "soup must use an actual pot instead of the meat spit")
	_check_visual_in_view(tools_root.get_node("SoupPot/CookingPot"))
	room.camp.advance_rest(5.0)
	_check(room.camp.warmth == 1 and room.inventory.count_item("edible_mushroom") == 2 and room.inventory.count_item("boiled_rainwater") == 2 and room.inventory.count_item("camp_kit") == initial_kit, "soup must spend two mushrooms and one water, without buying another camp kit")
	_check(overlay.action_buttons["cook:trail_stew"].disabled, "insufficient warmth must visibly disable the costly stew")
	await _capture("cooking_remaining_warmth.png")
	room.cancel_camp("새 야영지 설치")
	CAMP_TEST.deploy_and_open(room.camp)
	await _click(overlay.category_buttons.cooking.get_global_rect().get_center())
	await _click_action("cook:trail_stew")
	room.camp.advance_rest(7.0)
	await _capture("cooking_hearty_stew.png")
	_check(room.camp.get_snapshot().recipe_id == "trail_stew" and not paused, "second camp must run the real hearty stew recipe")
	room.camp.advance_rest(7.0)
	_check(room.player.health == 100.0 and ExpeditionSession.hunger == 100.0 and room.inventory.count_item("raw_meat") == 1 and room.inventory.count_item("edible_mushroom") == 1 and room.inventory.count_item("boiled_rainwater") == 1 and room.inventory.count_item("camp_kit") == 0, "all three real recipes must apply capped nutrition and exact shared inventory costs")
	await _capture("cooking_stew_eaten.png")
	# Small-screen recipe choice remains usable; ingredients are deliberately
	# insufficient for this soup and the actual button must stay disabled.
	root.content_scale_size = Vector2i(640, 480)
	root.size = Vector2i(640, 480)
	await process_frame
	await process_frame
	overlay.action_scroll.ensure_control_visible(overlay.action_buttons["cook:mushroom_soup"])
	await _capture("cooking_small_viewport.png")
	_check(root.get_visible_rect().encloses(overlay.leave_button.get_global_rect()), "small-screen leave control must stay reachable")
	_check(overlay.action_buttons["cook:mushroom_soup"].disabled, "missing mushrooms must prevent another recipe")
	await _key(KEY_ESCAPE)
	_check(not room.camp.is_open() and room.camp.state == "deployed" and room.player.weapon_pivot.visible, "Escape must stand up and preserve the installed camp")
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await process_frame
	room.run_feature("cooking")
	CAMP_TEST.deploy_and_open(room.camp)
	await _click(overlay.category_buttons.cooking.get_global_rect().get_center())
	await _click_action("cook:roast_meat")
	room.camp.advance_rest(2.0)
	var meat_after_start: int = room.inventory.count_item("raw_meat")
	await _key(KEY_F2)
	_check(room.panel_open and paused and room.camp.state == "closed" and room.camp.camp_visual == null and room.inventory.count_item("raw_meat") == meat_after_start and room.player.health == 35.0, "actual F2 must cancel cooking without free food, healing, refunds or orphan props")
	await _capture("cooking_cancelled_test_menu.png")
	# Exercise the ordinary frame-driven camp process too. Accelerate only
	# this native QA clock: macOS may return focus to the user's open editor,
	# which correctly cancels an unattended cook. Gameplay durations stay 8s.
	room.run_feature("cooking")
	root.grab_focus()
	await process_frame
	await process_frame
	CAMP_TEST.deploy_and_open(room.camp)
	_check(room.camp.is_open() and paused, "repeat fixture must reopen actual camp before real-time verification")
	await _click(overlay.category_buttons.cooking.get_global_rect().get_center())
	room.camp.set_process(true)
	Engine.time_scale = 16.0
	await _click_action("cook:roast_meat")
	_check(room.camp.state == "resting" and not paused, "real-time roast must start through the visible recipe button")
	var deadline := Time.get_ticks_msec() + 12000
	while room.camp.state == "resting" and Time.get_ticks_msec() < deadline:
		await process_frame
	room.camp.set_process(false)
	Engine.time_scale = 1.0
	_check(room.camp.state == "planning" and room.camp.last_result.get("cooked_and_eaten", false) and paused, "native frame-driven cooking must finish with the accelerated QA clock and no manual progress calls: state=%s result=%s focused=%s" % [room.camp.state, room.camp.last_result, root.has_focus()])
	await _capture("cooking_realtime_complete.png")
	if OS.get_environment("COOKING_QA_INTERACTIVE") == "1":
		room.player.set_physics_process(true)
		room.player.set_process_unhandled_input(true)
		room.set_process(true)
		room.camp.set_process(true)
		return
	await _finish()


func _click_action(id: String) -> void:
	var overlay: CampOverlay = room.camp.overlay
	var button: Button = overlay.action_buttons[id]
	overlay.action_scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	await _click(button.get_global_rect().get_center())


func _check_visual_in_view(visual: Node3D) -> void:
	var screen: Vector2 = room.player.camera.unproject_position(visual.global_position)
	_check(root.get_visible_rect().has_point(screen) and not room.camp.overlay.panel_root.get_global_rect().has_point(screen), "real cooking food must remain visible beside its recipe panel")


func _click(at: Vector2) -> void:
	Input.warp_mouse(at)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame


func _key(code: Key) -> void:
	await process_frame
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
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
	Engine.time_scale = 1.0
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("COOKING PREVIEW PASS: actual placement/tent entry, recipe tab/clicks, rendered roasting and boiling, three meals, finite resources, small viewport, F2 cancellation and frame-driven cooking")
		quit(0)
	else:
		for failure in failures:
			push_error("COOKING PREVIEW FAIL: " + failure)
		quit(1)
