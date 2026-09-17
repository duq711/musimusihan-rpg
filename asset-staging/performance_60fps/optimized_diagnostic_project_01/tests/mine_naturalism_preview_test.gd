extends SceneTree

const PREVIEW := preload("res://tests/mine_naturalism_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(PREVIEW.selected_shots("").size() == 5, "naturalism preview must include all five requested inspection subjects by default")
	var selected := PREVIEW.selected_shots(" water_steps,entry_rock_attachment,water_steps ")
	_check(selected.size() == 2 and selected[0].name == "water_steps", "naturalism selection must preserve order and avoid duplicate captures")
	_check(PREVIEW.selected_shots("missing,water_steps").is_empty(), "unknown naturalism shots must fail rather than claim a partial capture")
	var baseline := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	baseline.fill(Color.BLACK)
	_check(not PREVIEW.inspect_pixels(baseline).passed, "black images must never count as visual evidence")
	baseline.fill_rect(Rect2i(16, 16, 96, 80), Color(0.18, 0.13, 0.09, 1.0))
	_check(PREVIEW.inspect_pixels(baseline).passed, "images with substantial visible tonal detail must pass the readability gate")
	_check(not PREVIEW.compare_water_pixels(baseline, baseline).passed, "identical water images must fail footstep visual verification")
	var changed := baseline.duplicate() as Image
	changed.fill_rect(Rect2i(46, 63, 32, 4), Color(0.24, 0.21, 0.17, 1.0))
	_check(PREVIEW.compare_water_pixels(baseline, changed).passed, "visible localized changes inside the water comparison region must be detected")
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 379
	ExpeditionSession.stress = 17.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var inventory := ExpeditionSession.get_inventory()
	var mouse_mode := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var player := PREVIEW.populate_viewport(viewport)
	var geometry: Node = viewport.find_child("CaveGeometry", true, false)
	var water: Node = geometry.get("water_system")
	_check(water != null and not water.is_physics_processing(), "native naturalism preview must freeze real water physics for matched-clock comparisons")
	_check(not geometry.is_processing(), "matched-clock water captures must also freeze cave lantern flicker")
	_check(viewport.gui_disable_input and viewport.own_world_3d and not viewport.use_taa, "naturalism captures need an input-free isolated world without temporal-history differences")
	_check(not player.is_physics_processing() and not player.is_processing_unhandled_input() and player.game == null and player.hud == null, "naturalism actor must not process input, move the camera or bind a gameplay scene")
	await physics_frame
	await physics_frame
	for shot in PREVIEW.SHOTS:
		PREVIEW.configure_shot(player, shot)
		_check(not player.weapon_pivot.visible and not player.shield_pivot.visible and not player.torch_pivot.visible, "naturalism inspection must expose the actual environment while retaining its real carried lighting")
	var state: Dictionary = PREVIEW.generate_walk_ripples(water)
	_check(not state.is_empty() and state.ripple_count >= 3 and state.last_pool == "lower_west_water", "visual water comparison must use the production foot-contact path inside the actual lower-west pool")
	var original_events: PackedVector4Array = water.call("get_ripple_events")
	var empty_events := PackedVector4Array()
	empty_events.resize(original_events.size())
	for index in empty_events.size():
		empty_events[index] = Vector4(0.0, 0.0, -100.0, 0.0)
	PREVIEW.set_rendered_ripples(water, empty_events)
	for surface: MeshInstance3D in water.get("surfaces"):
		var material := surface.material_override as ShaderMaterial
		_check(material.get_shader_parameter("ripple_events") == empty_events and is_equal_approx(material.get_shader_parameter("water_clock"), float(state.clock)), "baseline must remove only ripple history while preserving actual water time")
	PREVIEW.set_rendered_ripples(water, original_events)
	_check(water.call("get_ripple_events") == original_events and water.call("get_state_snapshot") == state, "matched-clock visual baseline must not mutate simulation history or counters")
	_check(Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot and ExpeditionSession.get_inventory() == inventory, "naturalism construction and actual ripple simulation must preserve the live cursor and expedition")
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot, "naturalism preview cleanup must preserve the original expedition")
	if failures.is_empty():
		print("MINE NATURALISM PREVIEW STRUCTURE PASS: five actual environment poses, real footstep path, matched-clock ripple-only comparison, readable-pixel and unchanged-image gates, isolated input and expedition; no rendered pixel verification claimed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
