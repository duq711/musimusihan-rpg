extends SceneTree

var room: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Archery preview requires a rendering display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	# Isolate desktop input before the first rendered frame, including the
	# ready screenshot. The harness still uses the production input handlers.
	room.set_process_unhandled_input(false)
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room.run_feature("archery_accuracy")
	room.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	room.player._update_viewmodel(1.0)
	room.player._update_combat(0.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _capture("archery_ready.png")
	var resting_shape := _reticle_shape()
	if not is_equal_approx(room.hud.bow_spread_radius, 4.0) or not is_equal_approx(room.hud.bow_spread_tick_length, 9.0) or room.player.bow_drawing or room.player.get_arrow_count() != 30:
		push_error("Ready bow must use the original compact crosshair before a fresh draw")
		quit(1)
		return
	if room.hud.bow_draw_bar.size.y > 6.0:
		push_error("Bow draw meter must not overlap its controls legend")
		quit(1)
		return
	if OS.get_environment("ARCHERY_QA_INTERACTIVE") == "1":
		room.set_process_unhandled_input(true)
		room.player.set_process_unhandled_input(true)
		room.player.set_physics_process(true)
		print("ARCHERY INTERACTIVE READY: LMB draw/release, RMB cancel, F2 menu")
		return
	# Send real mouse-button objects directly through the input handler.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	room.player._unhandled_input(press)
	if not room.player.bow_drawing:
		push_error("Rendered LMB press did not start bow draw")
		quit(1)
		return
	room.player._update_combat(0.0)
	room.player._update_viewmodel(1.0)
	await _capture("archery_accuracy_weak.png")
	var starting_radius: float = room.hud.bow_spread_radius
	if not room.hud.bow_spread_reticle.visible or starting_radius < 80.0 or not is_equal_approx(room.hud.bow_spread_tick_length, 15.0):
		push_error("LMB press must visibly expand the compact crosshair into a wide draw reticle")
		quit(1)
		return
	room.player._update_combat(0.25)
	room.player._update_viewmodel(1.0)
	await _capture("archery_accuracy_quarter.png")
	var quarter_radius: float = room.hud.bow_spread_radius
	room.player._update_combat(0.25)
	room.player._update_viewmodel(1.0)
	await _capture("archery_accuracy_half.png")
	if not is_equal_approx(room.player.stamina, 89.0) or not is_equal_approx(room.player.get_bow_damage(), 32.0):
		push_error("Half draw must display 32 damage and consume 11 stamina over half a second")
		quit(1)
		return
	var half_radius: float = room.hud.bow_spread_radius
	room.player._update_combat(0.4)
	room.player._update_viewmodel(1.0)
	await _capture("archery_accuracy_near_full.png")
	var near_full_radius: float = room.hud.bow_spread_radius
	if not (starting_radius > quarter_radius and quarter_radius > half_radius and half_radius > near_full_radius and near_full_radius > 4.0):
		push_error("Drawing must keep narrowing the rendered reticle all the way to full draw")
		quit(1)
		return
	room.player._update_combat(0.1)
	room.player._update_viewmodel(1.0)
	await _capture("archery_drawn.png")
	if not room.player.bow_drawing or not is_equal_approx(room.player.get_bow_draw_ratio(), 1.0) or room.hud.bow_spread_radius >= half_radius:
		push_error("Full-draw render must be steady and contract the actual spread reticle")
		quit(1)
		return
	if _reticle_shape() != resting_shape:
		push_error("Full draw must restore the exact original compact crosshair geometry")
		quit(1)
		return
	if not is_equal_approx(room.player.stamina, 78.0) or not is_equal_approx(room.player.get_bow_damage(), 46.0):
		push_error("Full draw must cap damage at 46 and consume 22 stamina over one second")
		quit(1)
		return
	room.player._update_combat(1.0)
	room.player._update_viewmodel(1.0)
	await _capture("archery_full_hold.png")
	if not is_equal_approx(room.player.stamina, 56.0) or not is_equal_approx(room.player.get_bow_damage(), 46.0) or _reticle_shape() != resting_shape:
		push_error("Maintaining full draw must keep draining stamina without raising maximum damage")
		quit(1)
		return
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	room.player._unhandled_input(release)
	if room.player.bow_drawing or room.player.get_arrow_count() != 29 or not is_equal_approx(room.player.stamina, 56.0):
		push_error("Rendered LMB release did not fire exactly one arrow")
		quit(1)
		return
	room.player._update_combat(0.0)
	room.player._update_viewmodel(1.0)
	await _capture("archery_fired.png")
	room._recover_player()
	room.player._unhandled_input(press)
	room.player._update_combat(0.35)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	room.player._unhandled_input(cancel)
	room.player._update_viewmodel(1.0)
	await _capture("archery_reticle_cancelled.png")
	if room.player.bow_drawing or _reticle_shape() != resting_shape or room.player.get_arrow_count() != 29:
		push_error("RMB must restore the compact crosshair without firing an arrow")
		quit(1)
		return
	room._recover_player()
	room.player._unhandled_input(press)
	room.player._update_combat(5.0)
	room.player._update_viewmodel(1.0)
	var exhausted_shot := _latest_arrow()
	if room.player.bow_drawing or not is_zero_approx(room.player.stamina) or room.player.get_arrow_count() != 28 or _reticle_shape() != resting_shape or exhausted_shot == null or not is_equal_approx(exhausted_shot.charge, 1.0):
		push_error("Stamina exhaustion must automatically release exactly one full-draw arrow")
		quit(1)
		return
	room.player._unhandled_input(release)
	room.player._update_combat(0.0)
	if room.player.get_arrow_count() != 28:
		push_error("LMB release after exhaustion must not fire a second arrow")
		quit(1)
		return
	await _capture("archery_stamina_exhausted.png")
	if not await _preview_slack_drop(press, release):
		quit(1)
		return
	room._show_test_panel()
	room.run_feature("archery_power")
	room.player._unhandled_input(press)
	room.player._update_combat(1.0)
	room.player._update_viewmodel(1.0)
	room.player._unhandled_input(release)
	for _frame in range(90):
		await physics_frame
		if room.archery_power_last_damage > 0.0:
			break
	if not is_equal_approx(room.archery_power_last_damage, 46.0):
		push_error("Power fixture must show an actual full-draw 46-damage torso impact")
		quit(1)
		return
	room.player._update_combat(0.0)
	room.player._update_viewmodel(1.0)
	await _capture("archery_power_hit.png")
	room._show_test_panel()
	await _capture("archery_test_menu.png")
	room._hide_test_panel()
	room._open_inventory()
	await _capture("archery_inventory.png")
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	print("ARCHERY PREVIEW PASS: rendered draw reticle, quick-tap floor drop, automatic full/low-stamina release, no duplicate shot, manual cancellation, damage and menu/inventory screenshots")
	quit(0)


func _reticle_shape() -> Array[Rect2]:
	var shape: Array[Rect2] = []
	for tick: ColorRect in room.hud.bow_spread_ticks:
		shape.append(Rect2(tick.position, tick.size))
	return shape


func _latest_arrow() -> ArrowProjectile:
	var latest: ArrowProjectile
	for child in room.get_children():
		if child is ArrowProjectile and not child.is_queued_for_deletion():
			latest = child
	return latest


func _preview_slack_drop(press: InputEventMouseButton, release: InputEventMouseButton) -> bool:
	room._show_test_panel()
	room.run_feature("archery_power")
	room.player._unhandled_input(press)
	room.player._update_combat(0.05)
	room.player._update_viewmodel(1.0)
	await _capture("archery_slack_draw.png")
	room.player._unhandled_input(release)
	room.player._update_combat(0.0)
	var arrow := _latest_arrow()
	if arrow == null or not arrow.velocity.is_equal_approx(Vector3.DOWN) or not is_zero_approx(arrow.speed) or room.player.get_arrow_count() != 29:
		push_error("A 50ms click must drop one physical arrow straight down without forward launch speed")
		return false
	var start := arrow.global_position
	# Look down after release to inspect the real falling arrow; moving the
	# camera must not redirect the already-released projectile.
	room.player._pitch = deg_to_rad(-65.0)
	room.player.head.rotation.x = room.player._pitch
	room.player._update_viewmodel(1.0)
	for _frame in range(15):
		await physics_frame
	await _capture("archery_slack_falling.png")
	for _frame in range(90):
		await physics_frame
		if arrow.impacted:
			break
	var floor_ref: WeakRef = arrow.get("_stuck_target")
	if not arrow.impacted or floor_ref == null or floor_ref.get_ref() != room.get_node("TestFloor"):
		push_error("The unpowered arrow must hit the actual test-room floor")
		return false
	if Vector2(arrow.global_position.x - start.x, arrow.global_position.z - start.z).length() > 0.001 or arrow.global_position.y >= start.y - 0.5 or not is_zero_approx(room.archery_power_last_damage):
		push_error("An unpowered arrow must land directly below its release point without reaching the 8m target")
		return false
	await _capture("archery_slack_grounded.png")
	room._recover_player()
	room.player.stamina = 1.1
	room.player._unhandled_input(press)
	room.player._update_combat(1.0)
	var exhausted_arrow := _latest_arrow()
	if exhausted_arrow == null or exhausted_arrow == arrow or not is_equal_approx(exhausted_arrow.charge, 0.05) or not exhausted_arrow.velocity.is_equal_approx(Vector3.DOWN):
		push_error("Low-stamina automatic release must use the actual 50ms draw instead of granting full power")
		return false
	room.player._unhandled_input(release)
	room.player._update_combat(0.0)
	room.player._update_viewmodel(1.0)
	if room.player.get_arrow_count() != 28 or room.player.bow_drawing or not is_zero_approx(room.player.stamina):
		push_error("Low-stamina exhaustion must consume exactly one arrow and end drawing at zero stamina")
		return false
	await _capture("archery_low_stamina_release.png")
	return true


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name))
	if result != OK:
		push_error("Could not save archery preview: " + file_name)
		quit(1)
