extends SceneTree

var failures: Array[String] = []
var room: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Camp placement room tests require run_headless_tests.sh.")
		quit(2)
		return
	root.gui_disable_input = true
	AudioServer.set_bus_mute(0, true)
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("black_salt", 3)
	ExpeditionSession.hunger = 43.0
	ExpeditionSession.apply_condition("curse", 93.0, "right_arm")
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.camp.set_process(false)
	room.run_feature("camp_placement")
	await _settle()
	_check(sandbox.active and room.inventory != original and not paused and not room.panel_open, "catalog selection must enter an isolated, playable placement fixture")
	_check(room.get_node_or_null("CampPlacementObstacle") is StaticBody3D and room.get_node_or_null("CampPlacementInstructions") != null, "placement fixture must include a physical obstacle and executable instructions")
	var kits: int = room.inventory.count_item("camp_kit")
	_key(KEY_C)
	_check(room.camp.state == "closed" and room.inventory.count_item("camp_kit") == kits, "C must neither install a camp nor consume its kit")
	_aim(-40.0)
	_start_from_bag()
	_check(room.camp.state == "placing" and not paused and not room.inventory_overlay.is_open(), "actual inventory Install button must close inventory and begin live placement")
	_check(room.inventory.count_item("camp_kit") == kits and bool(room.camp.placement_snapshot.accepted), "valid floor preview must remain free before confirmation")
	_check(bool(room.camp.preview_visual.get_meta("placement_valid", false)), "valid physical placement must drive the green preview")
	var obstacle_direction: Vector3 = Vector3(-3.2, 0.7, 9.0) - room.player.camera.global_position
	room.player.rotation.y = atan2(-obstacle_direction.x, -obstacle_direction.z)
	_aim(rad_to_deg(atan2(obstacle_direction.y, Vector2(obstacle_direction.x, obstacle_direction.z).length())))
	room.camp.update_placement()
	_check(not bool(room.camp.placement_snapshot.accepted) and not bool(room.camp.preview_visual.get_meta("placement_valid", true)), "the actual fixture obstacle must turn the placement preview red")
	_click_install()
	_check(room.camp.state == "placing" and room.inventory.count_item("camp_kit") == kits, "a solid obstacle must refuse confirmation without consuming the kit")
	room.player.rotation.y = 0.0
	_aim(35.0)
	room.camp.update_placement()
	_check(not bool(room.camp.placement_snapshot.accepted) and not bool(room.camp.preview_visual.get_meta("placement_valid", true)), "aiming away from the floor must drive the red preview")
	_click_install()
	_check(room.camp.state == "placing" and room.inventory.count_item("camp_kit") == kits and room.camp.camp_visual == null, "invalid red confirmation must not create or charge a camp")
	var torch_before: bool = room.player.torch_enabled
	room.handle_torch_action()
	_check(room.camp.state == "closed" and room.camp.preview_visual == null and room.inventory.count_item("camp_kit") == kits and room.player.torch_enabled == torch_before, "F handler must cancel placement without spending supplies or toggling the torch")
	_aim(-40.0)
	_start_from_bag()
	_click_install()
	_check(room.camp.state == "deployed" and not paused and not room.player.camping and room.inventory.count_item("camp_kit") == kits - 1, "valid LMB must install once while keeping the player standing")
	var camp_visual: Node3D = room.camp.camp_visual
	_click_install()
	_check(room.inventory.count_item("camp_kit") == kits - 1 and room.camp.camp_visual == camp_visual, "repeated confirm must not spend another kit or duplicate the camp")
	_check(not bool(room.camp.begin_placement().accepted), "another installation must be rejected until the existing camp is dismantled")
	await physics_frame
	await process_frame
	var tent := camp_visual.get_node("Tent/TentInteraction") as Area3D
	var from: Vector3 = room.player.camera.global_position
	var target := tent.global_position + Vector3(0, 0.55, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + from.direction_to(target) * 3.0, DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = room.player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.get("collider") == tent, "the deployed tent must be reachable through the actual player's three-meter interaction layer")
	if not hit.is_empty():
		var owner: Node = hit.collider.get_meta("interaction_owner")
		_check(owner == room.camp and str(owner.get_interaction_prompt()).contains("E"), "tent Area must point at the production E interaction owner")
		var stand_position: Vector3 = room.player.global_position
		var camera_height: float = room.player.head.position.y
		var entered: Dictionary = owner.interact(room.player)
		_check(bool(entered.accepted) and room.camp.state == "planning" and paused and room.player.camping, "the exact interaction owner used by E must open the seated camp plan")
		_check(room.player.global_position != stand_position and room.player.head.position.y < camera_height and not room.player.weapon_pivot.visible, "tent interaction must physically seat the player and stow the weapon")
		if bool(entered.accepted):
			room.camp.overlay.category_buttons.cooking.pressed.emit()
			var meat: int = room.inventory.count_item("raw_meat")
			var health: float = room.player.health
			room.camp.overlay.action_buttons["cook:roast_meat"].pressed.emit()
			_check(room.camp.state == "resting" and not paused and room.inventory.count_item("raw_meat") == meat - 1, "actual recipe button must start live cooking and commit one meat")
			room.camp.advance_rest(4.0)
			_check(room.player.health == health, "unfinished cooking must not grant food or healing")
			room.camp.advance_rest(4.0)
			_check(room.camp.state == "planning" and paused and bool(room.camp.last_result.get("cooked_and_eaten", false)) and room.player.health > health, "completed cooking must feed and heal the actual player once")
			room.camp.overlay.leave_button.pressed.emit()
			_check(room.camp.state == "deployed" and room.camp.camp_visual == camp_visual and not paused and not room.player.camping, "standing up must leave the camp available for later tent interaction")
			_check(room.player.global_position.is_equal_approx(stand_position), "standing up must restore the safe approach position")
	_key(KEY_F2)
	_check(room.panel_open and paused and room.camp.state == "closed" and room.camp.camp_visual == null and room.camp.preview_visual == null, "F2 must completely clean the deployed camp while preserving the trial menu pause")
	room.run_feature("camp_placement")
	await _settle()
	_aim(-40.0)
	_start_from_bag()
	_key(KEY_F2)
	_check(room.camp.state == "closed" and room.camp.preview_visual == null and room.inventory.count_item("camp_kit") == kits, "F2 during an unconfirmed preview must restore free, repeatable placement")
	room.run_feature("camp_placement")
	await _settle()
	_aim(-40.0)
	_start_from_bag()
	room.run_feature("movement")
	_check(room.camp.state == "closed" and room.get_node_or_null("CampPlacementObstacle") == null, "switching trial must remove placement state and fixture obstacles")
	_check(original == sandbox.saved_session.inventory and ExpeditionSession.get_inventory() != original, "placement and cooking must keep the original bag outside the trial")
	room.cancel_camp("", false)
	paused = false
	room.suspend_stress_effects()
	room.free()
	current_scene = null
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == original_snapshot, "all placement, consumption and cooking must restore the exact original session and inventory identity")
	Input.mouse_mode = mouse_before
	for failure in failures:
		push_error("CAMP PLACEMENT ROOM FAIL: " + failure)
	print("CAMP PLACEMENT ROOM %s: actual inventory action, physics red/green preview, confirm/F cancellation, tent interaction, seated cooking, stand-up, F2 and sandbox restore" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _settle() -> void:
	room.player.set_physics_process(true)
	for frame in 60:
		await physics_frame
		if room.player.is_on_floor(): break
	room.player.set_physics_process(false)
	_check(room.player.is_on_floor(), "trial player must stand on the real floor")


func _aim(pitch_degrees: float) -> void:
	room.player._pitch = deg_to_rad(pitch_degrees)
	room.player.head.rotation.x = room.player._pitch


func _start_from_bag() -> void:
	room._open_inventory()
	var index := -1
	for i in room.inventory.slots.size():
		if str(room.inventory.slots[i].id) == "camp_kit":
			index = i
			break
	room.inventory_overlay._on_inventory_slot_pressed(index)
	_check(room.inventory_overlay.use_button.text.contains("설치") and not room.inventory_overlay.use_button.disabled, "owned camp kit must expose an enabled Install action")
	room.inventory_overlay.use_button.pressed.emit()


func _click_install() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	room.handle_camp_placement_input(event)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	room._unhandled_input(event)


func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
