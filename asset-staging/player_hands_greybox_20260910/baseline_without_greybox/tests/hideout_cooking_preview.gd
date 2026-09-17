extends SceneTree
## Isolated production hearth and recipe UI. Embedded renderer only; no native
## window, hardware input, mouse capture, audible sound or live journey entry.
const HIDEOUT := preload("res://scripts/hideout.gd")
const CONTROLLER := preload("res://scripts/hideout_cooking_controller.gd")
const SOURCES := ["res://scripts/hideout.gd", "res://scripts/hideout_cooking_controller.gd", "res://scripts/hideout_cooking_overlay.gd", "res://scripts/hideout_cooking_visual.gd", "res://scripts/camp_cooking_catalog.gd", "res://scripts/camp_overlay.gd", "res://scripts/camp_visuals.gd", "res://scripts/player.gd", "res://tests/hideout_cooking_preview.gd"]

class KitchenHost extends Node3D:
	var brazier_lit := true

var failures: Array[String] = []
var captures: Array[Dictionary] = []
var output := ""
var canvas: SubViewport
var kitchen: Node
var camera: Camera3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use run_embedded_preview.sh hideout_cooking_preview.gd.")
		quit(2)
		return
	var iteration := OS.get_environment("HIDEOUT_COOKING_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	output = ProjectSettings.globalize_path("res://artifacts/visual_qa/hideout_cooking/" + iteration)
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Use a new cooking capture folder.")
		quit(2)
		return
	var mouse_before := Input.mouse_mode
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_slots: Array = original_bag.slots.duplicate(true) if original_bag != null else []
	var hashes := {}
	for source in SOURCES:
		hashes[source] = FileAccess.get_sha256(source)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	AudioServer.set_bus_mute(0, true)
	root.gui_disable_input = true
	root.physics_object_picking = false
	canvas = SubViewport.new()
	canvas.name = "IsolatedHearthCookingUI"
	canvas.size = Vector2i(1280, 720)
	canvas.own_world_3d = true
	canvas.physics_object_picking = false
	canvas.audio_listener_enable_3d = false
	canvas.audio_listener_enable_2d = false
	canvas.msaa_3d = Viewport.MSAA_4X
	canvas.use_taa = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var host := KitchenHost.new()
	canvas.add_child(host)
	var builder := HIDEOUT.new()
	builder._build_materials()
	builder._build_world()
	var world: Node3D = builder.world_root
	var equipment: Node3D = builder.cooking_world
	builder.remove_child(world)
	builder.free()
	_stop_execution(world)
	host.add_child(world)
	var bag := ExpeditionSession.get_inventory()
	for recipe_id in CampCookingCatalog.ordered_recipe_ids():
		var recipe := CampCookingCatalog.get_recipe(recipe_id)
		for item in recipe.resources:
			bag.add_item(item, int(recipe.resources[item]) * 3)
	var player := DungeonPlayer.new()
	player.configure_safe_zone(true)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	host.add_child(player)
	_stop_execution(player)
	camera = player.camera
	camera.fov = 70.0
	camera.current = true
	_configure_camera(player, Vector3(3.2, 2.0, 5.3), Vector3(0.0, 0.9, 2.2))
	player.health = 35.0
	player.stamina = 20.0
	ExpeditionSession.hunger = 15.0
	ExpeditionSession.thirst = 20.0
	ExpeditionSession.set_stress(55.0)
	kitchen = CONTROLLER.new()
	canvas.add_child(kitchen)
	kitchen.setup(host, player, bag, equipment)
	kitchen.set_process(false)
	await _capture("01_hearth_equipment")
	kitchen.open_kitchen()
	# Fit the actual hearth in the left half beside the production recipe panel.
	_configure_camera(player, Vector3(2.7, 1.9, 5.0), Vector3(0.8, 1.0, 2.2))
	await _capture("02_recipe_menu")
	var button: Button = kitchen.overlay.action_buttons["cook:roast_meat"]
	var click := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = click
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame
	var clicked: bool = kitchen.state == "cooking"
	if not clicked:
		failures.append("Actual recipe button local click did not start cooking.")
	kitchen.advance_cooking(5.0)
	await _capture("03_roast_meat")
	kitchen.advance_cooking(3.0)
	if not bool(kitchen.last_result.get("cooked_and_eaten", false)):
		failures.append("Actual cooked meal did not complete and recover the player.")
	await _capture("04_meal_eaten")
	kitchen.start_recipe("trail_stew")
	kitchen.advance_cooking(9.0)
	await _capture("05_stew_cooking")
	kitchen.close_kitchen()
	kitchen.open_kitchen()
	canvas.size = Vector2i(720, 480)
	await _capture("06_small_menu")
	var panel: Control = kitchen.overlay.panel_root
	var leave: Button = kitchen.overlay.leave_button
	if not Rect2(Vector2.ZERO, Vector2(canvas.size)).encloses(leave.get_global_rect()):
		failures.append("Small cooking menu strands the exit button offscreen.")
	if panel.get_global_rect().end.y > 480.5:
		failures.append("Small cooking panel extends past the viewport.")
	kitchen.close_kitchen("Capture complete", false)
	canvas.free()
	sandbox.finish()
	var preserved: bool = ExpeditionSession.capture_snapshot() == original and ExpeditionSession.capture_snapshot().inventory == original_bag and (original_bag == null or original_bag.slots == original_slots) and Input.mouse_mode == mouse_before
	if not preserved:
		failures.append("Original expedition, bag contents or cursor changed.")
	for source in SOURCES:
		if FileAccess.get_sha256(source) != hashes[source]:
			failures.append("Source changed while capturing: " + source)
	var manifest := {"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "actual_production_world_and_ui": true, "desktop_capture": false, "hardware_input": false, "local_recipe_button_click": clicked, "expedition_and_cursor_preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	await process_frame
	for failure in failures:
		push_error(failure)
	print("HIDEOUT COOKING PREVIEW %s: %d actual hearth/UI captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)

func _capture(id: String) -> void:
	for frame in 16:
		await process_frame
	RenderingServer.force_draw(false)
	var captured := canvas.get_texture().get_image()
	var filename := id + ".png"
	if captured == null or captured.is_empty() or captured.save_png(output.path_join(filename)) != OK:
		failures.append("Failed real rendering: " + id)
		return
	captures.append({"id": id, "file": filename, "sha256": FileAccess.get_sha256(output.path_join(filename)), "viewport_size": [canvas.size.x, canvas.size.y], "state": kitchen.get_snapshot()})
	print("HIDEOUT COOKING CAPTURE: " + filename)

func _stop_execution(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_stop_execution(child)


func _configure_camera(player: DungeonPlayer, at: Vector3, target: Vector3) -> void:
	# The production handheld torch illuminates the utensils in ordinary play.
	# Keep its authored spot/fill lights, hiding carried geometry only.
	player.global_position = at - Vector3(0.0, 0.67, 0.0)
	var direction := target - at
	player.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.head.rotation = Vector3(player._pitch, 0.0, 0.0)
	player.camera.rotation = Vector3.ZERO
	for carried: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		carried.show()
		_hide_carried_geometry(carried)
	player.viewmodel_renderer.sync_view()


func _hide_carried_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		node.hide()
	for child in node.get_children():
		_hide_carried_geometry(child)
