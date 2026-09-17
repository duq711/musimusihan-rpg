extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var packed := load("res://hideout.tscn") as PackedScene
	_check(packed != null, "3D hideout scene must load")
	if packed == null:
		_finish()
		return
	var hideout := packed.instantiate() as SanctuaryHideout
	root.add_child(hideout)
	current_scene = hideout
	await process_frame
	await physics_frame

	_check(hideout.world_root is Node3D, "hideout must build a traversable Node3D world")
	_check(hideout.player is DungeonPlayer, "hideout must spawn the realtime first-person player")
	_check(hideout.player.safe_zone_mode, "hideout player must use safe-zone mode")
	_check(not hideout.player.weapon_pivot.visible and not hideout.player.shield_pivot.visible, "safe-zone player must stow sword and shield")
	_check(hideout.player.torch_pivot.visible, "safe-zone player must retain the exploration torch")
	_check(hideout.hideout_hud is HideoutHUD, "hideout must use its contextual safe-zone HUD")
	_check(hideout.inventory == ExpeditionSession.get_inventory(), "hideout must retain the active expedition inventory")

	var regions := get_nodes_in_group("hideout_stream_region")
	_check(regions.size() == 8, "hideout must expose eight independently groupable streaming regions")
	for expected_id in ["central", "entrance", "sleep", "storage", "workshop", "flooded_store", "ossuary", "drain"]:
		_check(hideout.region_nodes.has(expected_id), "missing streaming region %s" % expected_id)
	var anchors := hideout.find_child("OpenWorldAnchors", true, false)
	_check(anchors != null, "hideout must expose open-world spawn and exit anchors")
	if anchors != null:
		_check(anchors.find_child("WorldExit_ChapelRuins", true, false) != null, "main chapel world exit anchor must exist")
		_check(anchors.find_child("WorldExit_Drainage", true, false) != null, "future drainage shortcut anchor must exist")

	_check(hideout.find_child("OnlyWarmHearth", true, false) != null, "central living hearth must exist")
	_check(hideout.find_child("BedrollInteraction", true, false) is HideoutInteractable, "resting bed must be interactive")
	_check(hideout.find_child("StashInteraction", true, false) is HideoutInteractable, "personal stash must be interactive")
	_check(hideout.find_child("MapTableInteraction", true, false) == null, "the central physical expedition map must be removed")
	var entrance_interaction := hideout.find_child("EntranceTravelInteraction", true, false) as HideoutInteractable
	_check(entrance_interaction != null, "the chapel entrance must expose a travel interaction")
	if entrance_interaction != null:
		_check(entrance_interaction.action_id == "travel", "the chapel entrance interaction must open expedition travel")
	_check(hideout.find_child("OssuaryGateInteraction", true, false) is HideoutInteractable, "future hideout expansion must be inspectable")
	_check(hideout.find_child("DrainGateInteraction", true, false) is HideoutInteractable, "future open-world shortcut must be inspectable")
	_check(hideout.water_surfaces.size() >= 3, "wet hideout must use shared animated shallow-water surfaces")
	_check(hideout.flicker_lights.size() >= 4, "hearth and sparse torches must have living light")
	_check(get_nodes_in_group("enemy").is_empty(), "safe hideout must not spawn hostile encounters")
	_check(_capsule_path_is_clear(hideout, Vector3(0.0, 1.0, 17.0), Vector3(0.0, 1.0, 6.0)), "entrance must connect to the central hall")
	_check(_capsule_path_is_clear(hideout, Vector3(-6.4, 1.0, 5.0), Vector3(-10.0, 1.0, 5.0)), "central hall must connect to the sleeping cell")
	_check(_capsule_path_is_clear(hideout, Vector3(6.4, 1.0, 5.0), Vector3(10.0, 1.0, 5.0)), "central hall must connect to the storage room")
	_check(_capsule_path_is_clear(hideout, Vector3(6.4, 1.0, -5.0), Vector3(10.0, 1.0, -5.0)), "central hall must connect to the workshop")
	_check(_capsule_path_is_clear(hideout, Vector3(-6.4, 1.0, -5.0), Vector3(-10.0, 1.0, -5.0)), "central hall must connect to the flooded store")
	_check(not _capsule_path_is_clear(hideout, Vector3(0.0, 1.0, -8.7), Vector3(0.0, 1.0, -12.0)), "sealed ossuary gate must stop the player")
	_check(not _capsule_path_is_clear(hideout, Vector3(14.4, 1.0, -5.0), Vector3(17.8, 1.0, -5.0)), "sealed drainage gate must stop the player")

	if entrance_interaction != null:
		hideout.player.global_position = Vector3(0.0, 1.0, 17.2)
		hideout.player.rotation.y = PI
		await physics_frame
		var viewport_center := hideout.get_viewport().get_visible_rect().size * 0.5
		var click_event := InputEventMouseButton.new()
		click_event.button_index = MOUSE_BUTTON_LEFT
		click_event.position = viewport_center
		click_event.pressed = true
		hideout._unhandled_input(click_event)
		_check(hideout.destination_panel.visible and hideout.hideout_mode == SanctuaryHideout.HideoutMode.MAP, "the chapel entrance must open the destination overlay")
		_send_escape(hideout)
		_check(not hideout.destination_panel.visible and hideout.hideout_mode == SanctuaryHideout.HideoutMode.RUNNING, "Escape from the travel map must return to the realtime hideout")
		_check(hideout.get_viewport().gui_get_focus_owner() == null, "closing the travel map must release GUI focus before gameplay resumes")
		await _send_space_through_input()
		_check(not hideout.destination_panel.visible and hideout.hideout_mode == SanctuaryHideout.HideoutMode.RUNNING, "jumping after Escape must not reopen the expedition map")

	_finish()


func _capsule_path_is_clear(hideout: SanctuaryHideout, from: Vector3, to: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [hideout.player.get_rid()]
	var result := hideout.player.get_world_3d().direct_space_state.cast_motion(query)
	return result.size() >= 1 and is_equal_approx(result[0], 1.0)


func _send_escape(hideout: SanctuaryHideout) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	hideout._unhandled_input(event)


func _send_space_through_input() -> void:
	var pressed_event := InputEventKey.new()
	pressed_event.keycode = KEY_SPACE
	pressed_event.physical_keycode = KEY_SPACE
	pressed_event.pressed = true
	Input.parse_input_event(pressed_event)
	await process_frame
	var released_event := InputEventKey.new()
	released_event.keycode = KEY_SPACE
	released_event.physical_keycode = KEY_SPACE
	released_event.pressed = false
	Input.parse_input_event(released_event)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("HIDEOUT 3D TEST PASS: world, safe player, lived-in interactions, and open-world anchors")
		quit(0)
		return
	for failure in failures:
		push_error("HIDEOUT 3D TEST FAIL: %s" % failure)
	quit(1)
