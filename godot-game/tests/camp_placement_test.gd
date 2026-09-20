extends SceneTree
## Placement transactions and physical access use the production controller.

const CAMP := preload("res://scripts/camp_controller.gd")
const PROBE := preload("res://scripts/camp_placement_probe.gd")
var failures: Array[String] = []

class FixtureWorld extends Node3D:
	var camp: DungeonCamp
	var scene_failure := ""
	func _camp_open_failure() -> String: return scene_failure
	func cancel_camp(reason := "", restore_controls := true) -> void:
		camp.cancel_camp(reason, restore_controls)

class WetSurface extends Node3D:
	func sample_surface(_point: Vector3) -> Dictionary:
		return {"height": 0.08, "depth": 0.08}

class CountingCamp extends "res://scripts/camp_controller.gd":
	var fixed_checks := 0
	func _validate_fixed_placement() -> Dictionary:
		fixed_checks += 1
		return super._validate_fixed_placement()

class EventHUD extends "res://scripts/hud.gd":
	var last_event := ""
	func show_event(text_value: String, _duration := 1.8) -> void:
		last_event = text_value


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Camp placement tests require the headless runner.")
		quit(2)
		return
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var before := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var bag := ExpeditionSession.get_inventory()
	bag.remove_item("camp_kit", bag.count_item("camp_kit"), false)
	bag.add_item("camp_kit", 2)
	var world := FixtureWorld.new()
	root.add_child(world)
	var floor_body := _box(Vector3(0, -0.10, 0), Vector3(30, 0.20, 30))
	world.add_child(floor_body)
	var player := DungeonPlayer.new()
	player.setup(world, null, bag)
	player.position = Vector3(0, 0.91, 0)
	world.add_child(player)
	player.set_physics_process(false)
	for _frame in range(20):
		await physics_frame
		await process_frame
		player._physics_process(1.0 / 60.0)
		if player.is_on_floor(): break
	_check(player.is_on_floor(), "Placement fixture has a real grounded player")
	var camp := CountingCamp.new()
	world.camp = camp
	camp.setup(world, player, bag)
	world.add_child(camp)
	camp.set_process(false)
	camp.opened.connect(func() -> void:
		player.set_camping(true)
		paused = true)
	camp.rest_started.connect(func() -> void: paused = false)
	camp.rest_finished.connect(func(_result: Dictionary) -> void: paused = true)
	camp.closed.connect(func(_reason: String, restore_controls: bool) -> void:
		player.set_camping(false)
		if restore_controls: paused = false)
	player._pitch = deg_to_rad(-40)
	player.head.rotation.x = player._pitch
	_check(not camp.open_camp().accepted and bag.count_item("camp_kit") == 2, "Legacy open cannot bypass item placement or spend a kit")
	_check(camp.begin_placement().accepted and camp.state == "placing", "Using a kit begins preview only")
	_check(camp.placement_snapshot.accepted and is_instance_valid(camp.preview_visual) and bag.count_item("camp_kit") == 2, "Valid preview does not consume the kit")
	camp.cancel_camp("F 취소")
	_check(camp.state == "closed" and not is_instance_valid(camp.preview_visual) and bag.count_item("camp_kit") == 2, "Preview cancellation discards preview without consumption")
	player.head.rotation.x = 0
	player._pitch = 0
	_check(camp.begin_placement().accepted and not camp.placement_snapshot.accepted, "A horizontal aim with no floor in reach remains an invalid preview")
	player._pitch = deg_to_rad(-40)
	player.head.rotation.x = player._pitch
	var placement := camp.update_placement()
	_check(placement.accepted, "Re-aiming at the floor updates the same preview to valid")
	world.scene_failure = "moving"
	_check(not camp.update_placement().accepted and camp.placement_snapshot.reason == "moving" and not camp.confirm_placement().accepted and bag.count_item("camp_kit") == 2, "Scene eligibility makes preview and confirmation reject movement consistently")
	world.scene_failure = ""
	_check(camp.update_placement().accepted, "Stopping movement restores the valid preview")
	var center: Vector3 = placement.position
	var obstruction := _box(center + Vector3(1.05, 0.7, -0.35), Vector3(0.25, 1.4, 0.25))
	world.add_child(obstruction)
	await physics_frame
	await process_frame
	_check(not camp.confirm_placement().accepted and bag.count_item("camp_kit") == 2 and camp.state == "placing", "Commit rechecks the tent footprint after a previously green preview")
	obstruction.free()
	await physics_frame
	await process_frame
	var cave := Node3D.new()
	cave.name = "CaveGeometry"
	world.add_child(cave)
	var water := WetSurface.new()
	water.name = "CaveWater"
	cave.add_child(water)
	_check(camp.update_placement().reason == "wet_ground" and not camp.confirm_placement().accepted and bag.count_item("camp_kit") == 2, "Water contact rejects preview and commit without spending")
	cave.free()
	_check(camp.confirm_placement().accepted and camp.state == "deployed" and camp.kit_spent and bag.count_item("camp_kit") == 1, "Valid confirmation consumes one kit and creates a deployed campsite")
	_check(not camp.is_open() and not camp.overlay.overlay_root.visible and is_instance_valid(camp.camp_visual), "Deployment leaves gameplay active with the campsite in the world")
	_check(not camp.confirm_placement().accepted and not camp.begin_placement().accepted and bag.count_item("camp_kit") == 1, "Repeated confirmation and a second camp cannot consume another kit")
	var area: Node = camp.camp_visual.find_child("TentInteraction", true, false)
	_check(is_instance_valid(area) and area.get_meta("interaction_owner", null) == camp, "The real tent exposes this controller as its interaction owner")
	var standing := player.global_transform
	var seat := PROBE.seat_position(center, float(placement.yaw))
	# This barrier sits between the player and seat, outside the deployed site.
	var wall := _box((standing.origin + seat) * 0.5 + Vector3(0, 0.05, 0), Vector3(1.4, 1.8, 0.08))
	world.add_child(wall)
	await physics_frame
	await process_frame
	var event_hud := EventHUD.new()
	player.hud = event_hud
	var blocked := camp.interact(player)
	_check(not blocked.accepted and player.global_transform == standing and camp.state == "deployed", "Blocked access cannot teleport the player through a wall into the seat")
	_check(not event_hud.last_event.is_empty() and event_hud.last_event == str(blocked.message), "A rejected tent interaction reports its actual reason through the player's HUD")
	player.hud = null
	event_hud.free()
	wall.free()
	await physics_frame
	await process_frame
	player.health = 300
	player.stamina = 20
	_check(camp.interact(player).accepted and camp.state == "planning" and player.global_position.is_equal_approx(seat), "Tent interaction moves the player to the validated seat and opens planning")
	camp.fixed_checks = 0
	camp.get_snapshot()
	_check(camp.fixed_checks == 1, "One action-menu snapshot performs one shared fixed-footprint check")
	_check(camp.start_action("rest").accepted and bag.count_item("camp_kit") == 1, "A placed camp starts real rest without charging another kit")
	_check(camp.fixed_checks == 2, "Starting an action revalidates geometry after the prior menu snapshot")
	camp.advance_rest(1.0)
	camp.leave_camp("일어서기")
	_check(camp.state == "deployed" and is_instance_valid(camp.camp_visual) and bag.count_item("camp_kit") == 1, "Standing up interrupts rest but retains the deployed camp and spent kit")
	_check(player.global_transform.is_equal_approx(standing) and not player.camping and not paused, "Standing up restores the saved approach position and live controls")
	_check(camp.open_camp().accepted and bag.count_item("camp_kit") == 1, "The same deployed camp can be entered again without a kit")
	camp.cancel_camp("야영지 정리")
	_check(camp.state == "closed" and not is_instance_valid(camp.camp_visual) and bag.count_item("camp_kit") == 1, "Packing removes the campsite without refunding the consumed kit")
	paused = false
	world.free()
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == before and Input.mouse_mode == mouse_before, "Placement tests restore the original expedition and cursor")
	for failure in failures: push_error("CAMP PLACEMENT TEST FAIL: " + failure)
	print("CAMP PLACEMENT TEST %s: live preview, no-spend cancellation, commit revalidation, water/obstacles, one kit, tent access and persistent seated camp" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _box(at: Vector3, extent: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extent
	collision.shape = shape
	body.add_child(collision)
	return body


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
