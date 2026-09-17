extends SceneTree

var room: Node3D
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Flail preview requires a rendering display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	# Keep incidental desktop input out of this deterministic render harness.
	# All attacks below still enter through the production mouse handlers.
	room.set_process_unhandled_input(false)
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room.run_feature("flail")
	room.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	room.player._update_combat(0.0)
	room.player._update_viewmodel(1.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _capture("flail_ready.png")
	_check(room.player.flail_visual_root.visible and not room.player.shield_pivot.visible, "equipped flail must render without a shield")
	_check(room.hud.flail_panel.visible and not room.hud.archery_panel.visible, "ready HUD must show the flail controls")
	if OS.get_environment("FLAIL_QA_INTERACTIVE") == "1":
		room.set_process_unhandled_input(true)
		room.player.set_process_unhandled_input(true)
		room.player.set_physics_process(true)
		return
	_mouse(MOUSE_BUTTON_LEFT, true)
	_check(room.player.flail_state == "melee", "LMB must start the melee animation")
	room.player._update_flail(0.1)
	room.player._update_viewmodel(1.0)
	await _capture("flail_melee_windup.png")
	room.player._update_flail(0.11)
	room.player._update_viewmodel(1.0)
	await _capture("flail_melee_hit.png")
	_check(is_equal_approx(room.flail_near_target.health, 168.0), "LMB must deal exactly 32 damage to the real 2m target")
	room.player._update_flail(0.5)
	room._recover_player()
	room._teleport(Vector3(3, 1, 5))
	_mouse(MOUSE_BUTTON_RIGHT, true)
	var positions: Array[Vector3] = []
	for step in [0.08, 0.08, 0.14, 0.3, 0.6]:
		room.player._update_flail(step)
		room.player._update_viewmodel(1.0)
		positions.append(room.player.flail_visual_root.get_node("Head").position)
		await _capture("flail_spin_%d.png" % positions.size())
	_check(positions[0].distance_to(positions[1]) > 0.1 and positions[1].distance_to(positions[2]) > 0.1, "RMB must visibly rotate the iron head at the player's side")
	_check(is_equal_approx(room.player.get_flail_charge(), 1.0) and is_equal_approx(room.player.stamina, 76.0), "full rotation must cap power and charge stamina only once")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	var projectile: FlailProjectile = room.player.flail_projectile
	_check(is_instance_valid(projectile), "RMB release must launch a physical flail head")
	if is_instance_valid(projectile):
		projectile.set_physics_process(false)
		room.player._update_flail(0.0)
		room.player._update_viewmodel(1.0)
		# Match the game: move the player's hand before the projectile joins it.
		projectile._physics_process(0.1)
		await _capture("flail_outbound.png")
		var chain_start := projectile.get_node("Chain/Start") as Node3D
		var chain_end := projectile.get_node("Chain/End") as Node3D
		_check(chain_start.global_position.distance_to(room.player.get_flail_chain_anchor()) < 0.01 and chain_end.global_position.distance_to(projectile.global_position) < 0.01, "rendered chain must join the handle and thrown head")
		for step in range(20):
			projectile._physics_process(0.025)
			if projectile.phase == "returning":
				break
		room.player._update_flail(0.0)
		await _capture("flail_impact_return.png")
		_check(is_equal_approx(room.flail_far_target.health, 140.0) and is_equal_approx(room.flail_last_damage, 60.0), "full throw must hit the actual 8m target for 60 damage")
		_check(not room.player.flail_visual_root.get_node("Head").visible, "outbound and returning iron head must not duplicate the held head")
		for step in range(80):
			if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
				break
			projectile._physics_process(0.025)
		room.player._update_flail(0.3)
		await process_frame
		room.player._update_viewmodel(1.0)
		await _capture("flail_recovered.png")
		_check(room.player.flail_state == "ready" and room.player.flail_visual_root.get_node("Head").visible and is_equal_approx(room.flail_far_target.health, 140.0), "return must restore the held head without applying more damage")
	room._recover_player()
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_check(room.player.flail_state == "spinning" and room.player.flail_projectile == null, "quick RMB click must visibly spin before throwing")
	room.player._update_flail(0.35)
	_check(is_instance_valid(room.player.flail_projectile), "quick click must launch after its minimum rotation")
	room._show_test_panel()
	await _capture("flail_test_menu.png")
	_check(room.player.flail_state == "ready" and room.player.flail_projectile == null, "test menu must safely cancel and recover the thrown head")
	room._hide_test_panel()
	room._open_inventory()
	await _capture("flail_inventory.png")
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("FLAIL PREVIEW PASS: rendered LMB impact, side rotation, release, connected chain, 8m impact, harmless return, quick click, menu and inventory")
		quit(0)
	else:
		for failure in failures:
			push_error("FLAIL PREVIEW FAIL: " + failure)
		quit(1)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	room.player._unhandled_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name))
	_check(result == OK, "could not save rendered preview: " + file_name)
