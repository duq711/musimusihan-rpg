extends SceneTree

const RENDERER := preload("res://scripts/first_person_renderer.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_window_pixel_budget()
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	inventory.add_item("weathered_staff", 1)
	var surface := SubViewport.new()
	surface.size = Vector2i(960, 540)
	surface.own_world_3d = true
	surface.gui_disable_input = true
	root.add_child(surface)
	var stage := Node3D.new()
	surface.add_child(stage)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.fog_enabled = true
	world_environment.environment.glow_enabled = true
	world_environment.environment.ambient_light_color = Color(0.32, 0.41, 0.5)
	stage.add_child(world_environment)
	var wall := StaticBody3D.new()
	wall.collision_layer = DungeonPlayer.WORLD_LAYER
	wall.position = Vector3(0, 1.5, -0.56)
	var box := BoxShape3D.new()
	box.size = Vector3(8, 5, 0.12)
	var collision := CollisionShape3D.new()
	collision.shape = box
	wall.add_child(collision)
	var wall_mesh := MeshInstance3D.new()
	var visible_box := BoxMesh.new()
	visible_box.size = box.size
	wall_mesh.mesh = visible_box
	wall.add_child(wall_mesh)
	stage.add_child(wall)
	var player := DungeonPlayer.new()
	player.position.y = 1.0
	player.setup(stage, null, inventory)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	await physics_frame
	await physics_frame
	var renderer: Node = player.viewmodel_renderer
	renderer.sync_view()
	_check(renderer.viewport.world_3d == player.get_world_3d(), "equipment must share real world lighting and positions")
	_check(renderer.viewport != surface and renderer.viewport.transparent_bg, "equipment must have its own transparent depth buffer")
	_check(renderer.overlay.custom_viewport == surface and renderer.overlay.layer == 0, "nested previews must composite below the normal HUD")
	_check(renderer.display.mouse_filter == Control.MOUSE_FILTER_IGNORE and renderer.viewport.gui_disable_input, "equipment compositing must never intercept gameplay or menu input")
	_check(renderer.camera.cull_mask == RENDERER.EQUIPMENT_LAYER and (player.camera.cull_mask & RENDERER.EQUIPMENT_LAYER) == 0, "world and equipment cameras must not draw the same weapon twice")
	_check((wall_mesh.layers & renderer.camera.cull_mask) == 0 and (wall_mesh.layers & player.camera.cull_mask) != 0, "the wall must occlude the world but never write the equipment depth buffer")
	var sword_center: Vector3 = player.sword_blade.global_transform * player.sword_blade.mesh.get_aabb().get_center()
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, sword_center, DungeonPlayer.WORLD_LAYER)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	_check(hit.get("collider") == wall, "regression fixture must reproduce a real wall between the eye and carried sword")
	for carried: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		_check_geometry_layers(carried, RENDERER.EQUIPMENT_LAYER)
		_check_material_depth(carried)
	_check_geometry_layers(player.chest_hands, 1)
	_check(player.torch.light_cull_mask & 1 != 0 and player.torch_fill.light_cull_mask & 1 != 0, "the actual torch must continue lighting world geometry")
	_check(renderer.equipment_lights.size() == 3, "torch spot/fill and staff light must have real light sources visible to the equipment camera")
	for light: Light3D in renderer.equipment_lights:
		_check((light.layers & renderer.camera.cull_mask) != 0 and light.light_cull_mask == RENDERER.EQUIPMENT_LAYER, "equipment lights must be camera-visible and illuminate only carried meshes")
		_check((light.layers & player.camera.cull_mask) == 0 and not light.shadow_enabled, "equipment lights must not relight the world or be blocked by a wall behind the viewmodel")
	var equipment_fill := renderer.camera.get_node("EquipmentTorchFillLight") as OmniLight3D
	var world_torch_mask := player.torch.light_cull_mask
	player.torch_fill.light_color = Color(1.0, 0.68, 0.4)
	player._update_torch(0.1)
	renderer.sync_view()
	_check(equipment_fill.light_color == player.torch_fill.light_color and equipment_fill.light_energy == player.torch_fill.light_energy and equipment_fill.global_transform.is_equal_approx(player.torch_fill.global_transform), "equipment lighting must follow actual torch tint, flicker and flame position")
	player.set_torch_enabled(false)
	renderer.sync_view()
	_check(not equipment_fill.visible and not renderer.camera.get_node("EquipmentTorchForwardLight").visible, "turning off the torch must also turn off its equipment illumination")
	player.set_torch_enabled(true)
	renderer.sync_view()
	_check(equipment_fill.visible and player.torch.light_cull_mask == world_torch_mask, "turning the torch back on must restore equipment light without mutating world light masks")
	var sword_proxy := player.get_sword_clash_proxy()
	var sword_transform := player.sword_blade.global_transform
	player.camera.fov = 88
	player.head.rotation = Vector3(-0.24, 0.13, 0)
	player.position = Vector3(3, 1.4, 2)
	var posed_transform := player.sword_blade.global_transform
	renderer.sync_view()
	_check(renderer.camera.global_transform.is_equal_approx(player.camera.global_transform) and renderer.camera.fov == 88, "equipment camera must exactly follow translation, pitch, yaw and FOV")
	_check(player.sword_blade.global_transform == posed_transform and posed_transform != sword_transform and not sword_proxy.is_empty(), "renderer synchronization must not alter real sword geometry or its clash proxy")
	surface.size = Vector2i(2560, 1664)
	renderer.sync_view()
	_check(surface.size == Vector2i(2560, 1664) and is_equal_approx(surface.scaling_3d_scale, 0.5), "Retina must retain native UI dimensions while limiting only world 3D pixels")
	_check(surface.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and renderer.viewport.size == Vector2i(1280, 832), "world reconstruction and separate transparent equipment must both respect the Retina rendering budget")
	_check(not renderer.viewport.use_taa and renderer.camera.fov == player.camera.fov and renderer.camera.global_transform.is_equal_approx(player.camera.global_transform), "resolution budgeting must retain flame transparency and exact camera/weapon projection")
	_check(player.sword_blade.global_transform == posed_transform, "resolution changes must not move the physical sword contact frame")
	surface.size_2d_override = Vector2i(640, 360)
	surface.size_2d_override_stretch = true
	renderer.sync_view()
	_check(surface.get_visible_rect().size == Vector2(640, 360) and is_equal_approx(surface.scaling_3d_scale, 0.5) and renderer.viewport.size == Vector2i(1280, 832), "logical UI coordinates must not conceal the actual Retina render cost")
	surface.size_2d_override = Vector2i.ZERO
	surface.size = Vector2i(640, 640)
	renderer.sync_view()
	_check(renderer.viewport.size == surface.size, "equipment image must resize with the actual rendering surface")
	_check(is_equal_approx(surface.scaling_3d_scale, 1.0) and surface.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "returning to the original pixel budget must restore the original world rendering mode")
	_check(renderer.camera.environment != world_environment.environment and not renderer.camera.environment.fog_enabled and world_environment.environment.fog_enabled, "transparent equipment rendering must remove distant fog without mutating the game environment")
	_check(renderer.camera.environment.ambient_light_color == world_environment.environment.ambient_light_color, "carried gear must retain the world's ambient light colour")
	_check(not renderer.camera.environment.glow_enabled and world_environment.environment.glow_enabled, "transparent equipment must skip duplicate full-screen bloom while preserving world glow and actual emissive flame geometry")
	var session_before := ExpeditionSession.capture_snapshot()
	player.configure_safe_zone(true)
	_check(not player.weapon_pivot.visible and not player.shield_pivot.visible and player.torch_pivot.visible, "safe zone equipment visibility must remain intact")
	player.configure_safe_zone(false)
	player.set_camping(true)
	_check(not player.weapon_pivot.visible and not player.shield_pivot.visible and not player.torch_pivot.visible, "camping must still stow every carried model")
	renderer.sync_view()
	_check(not renderer.overlay.visible and renderer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "stowing all equipment must stop the otherwise empty full-screen equipment render pass")
	player.set_camping(false)
	player.set_chest_container_open(true)
	_check(not player.weapon_pivot.visible and not player.torch_pivot.visible, "chest looting must hide the overlay's actual equipment")
	player.set_chest_container_open(false)
	_check(player.weapon_pivot.visible and player.shield_pivot.visible and player.torch_pivot.visible, "closing a chest must restore the actual equipment")
	renderer.sync_view()
	_check(renderer.overlay.visible and renderer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "restoring carried equipment must resume its real depth rendering")
	_check(ExpeditionSession.capture_snapshot() == session_before, "presentation transitions must not change the expedition or equipment inventory")
	for item_id in ["hunting_bow", "chain_flail", "weathered_staff", "rusted_sword"]:
		_check(_equip(inventory, item_id), "real inventory equip must work for " + item_id)
		player._update_viewmodel(0.1)
		renderer.sync_view()
		_check_geometry_layers(player.weapon_pivot, RENDERER.EQUIPMENT_LAYER)
		_check(player.weapon_pivot.visible, "changing to " + item_id + " must not lose the equipment overlay")
	var world_arrow: Node3D = load("res://scripts/archery_visuals.gd").create_arrow()
	stage.add_child(world_arrow)
	_check_geometry_layers(world_arrow, 1)
	var world_flail: Node3D = load("res://scripts/flail_visuals.gd").create_head()
	stage.add_child(world_flail)
	_check_geometry_layers(world_flail, 1)
	var other_camera := Camera3D.new()
	stage.add_child(other_camera)
	other_camera.current = true
	renderer.sync_view()
	_check(not renderer.overlay.visible and renderer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "switching to a different camera must hide and stop the equipment overlay")
	player.camera.current = true
	renderer.sync_view()
	_check(renderer.overlay.visible, "returning to the player camera must restore its equipment")
	paused = true
	surface.size = Vector2i(800, 450)
	await process_frame
	await process_frame
	_check(renderer.viewport.size == surface.size, "paused inventory and test menus must still allow correct viewport resizing")
	paused = false
	var renderer_ref: WeakRef = weakref(renderer)
	var viewport_ref: WeakRef = weakref(renderer.viewport)
	var canvas_ref: WeakRef = weakref(renderer.overlay)
	surface.queue_free()
	await process_frame
	_check(renderer_ref.get_ref() == null and viewport_ref.get_ref() == null and canvas_ref.get_ref() == null, "scene exits must free the extra camera, texture viewport and canvas together")
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original, "original expedition must be restored after the regression test")
	if failures.is_empty():
		print("FIRST PERSON RENDERER TEST PASS: reproduced wall occlusion, separate equipment depth, all loadouts, real world anchors/lights/projectiles, chest/camp/safe-zone visibility, resize/pause/camera changes and cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error("FIRST PERSON RENDERER TEST FAIL: " + failure)
		quit(1)


func _check_window_pixel_budget() -> void:
	# Never add this fixture to the tree: sizing a detached Window tests the
	# shipped canvas-items math without creating any native window or input.
	var fixture := Window.new()
	fixture.visible = false
	fixture.size = Vector2i(2560, 1664)
	fixture.content_scale_size = Vector2i(1280, 720)
	fixture.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var budget := RENDERER.RESOLUTION_BUDGET
	_check(fixture.get_visible_rect().size == Vector2(1280, 720), "fixture must reproduce the real game's logical canvas size on Retina")
	_check(budget.render_size_for(fixture) == Vector2i(2560, 1664) and is_equal_approx(budget.scale_for(budget.render_size_for(fixture)), 0.5), "canvas-items stretching must budget native world pixels while leaving UI scaling unchanged")
	fixture.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	_check(budget.render_size_for(fixture) == Vector2i(1280, 720), "already scaled viewport-mode rendering must not be reduced twice")
	fixture.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	fixture.content_scale_factor = 2.0
	_check(budget.render_size_for(fixture) == Vector2i(2560, 1664), "UI-only content scale must not change the 3D pixel budget")
	fixture.free()


func _check_geometry_layers(node: Node, expected: int) -> void:
	if node is VisualInstance3D and not node is Light3D:
		_check((node as VisualInstance3D).layers == expected, "geometry must be in the correct rendering pass: " + str(node.get_path()))
	for child in node.get_children():
		_check_geometry_layers(child, expected)


func _check_material_depth(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface_index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface_index)
			if material is BaseMaterial3D:
				_check(not (material as BaseMaterial3D).no_depth_test, "opaque equipment must retain self depth rather than use an always-visible material: " + node.name)
	for child in node.get_children():
		_check_material_depth(child)


func _equip(inventory: ExpeditionInventory, item_id: String) -> bool:
	for index in inventory.slots.size():
		if inventory.slots[index].id == item_id:
			return bool(inventory.equip_from_slot(index).get("accepted", false))
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
