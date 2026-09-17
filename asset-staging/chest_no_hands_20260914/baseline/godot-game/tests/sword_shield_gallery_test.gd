extends SceneTree

const GALLERY := preload("res://scripts/dark_fantasy_gallery.gd")
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const MULTIVIEW_PREVIEW := preload("res://tests/sword_shield_multiview_preview.gd")
const IDS: Array[String] = ["rusted_longsword", "weathered_round_shield"]
const MATERIAL_PROPERTIES: Array[String] = ["albedo_color", "albedo_texture", "normal_enabled", "normal_texture", "normal_scale", "roughness", "roughness_texture", "metallic", "metallic_specular", "uv1_scale", "vertex_color_use_as_albedo", "texture_filter"]
var failures: Array[String] = []
var checked_atlas_mipmaps: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(MULTIVIEW_PREVIEW.IDS == IDS, "renderer comparison and live inspector must select the same two production objects")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	var sword := original.get_equipment_instance("weapon")
	sword["uid"] = "six_view_original_sword"
	sword["smithing"] = {"quality": 0.84, "grip": "balanced", "reinforcement": "silver", "sockets": 1, "runes": ["ember"], "drill_progress": 0.25}
	original.add_item("wooden_arrow", 13)
	ExpeditionSession.crowns = 397
	ExpeditionSession.hunger = 53.0
	ExpeditionSession.thirst = 44.0
	var original_contents := _inventory_contents(original)
	var saved := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var gallery := GALLERY.new()
	root.add_child(gallery)
	for id in IDS:
		_check(gallery.select_object(id), "current sword/shield must be selectable: " + id)
		_check_production_model(gallery, id)
		_check_six_views(gallery)
		_check(ExpeditionSession.capture_snapshot() == saved and _inventory_contents(original) == original_contents and Input.mouse_mode == mouse_mode, "six-view construction must preserve original contents, session and cursor")
	_check(checked_atlas_mipmaps.size() >= 2, "both actual weapon albedo and normal atlas resources must be checked for imported mipmaps")
	gallery.free()
	await process_frame
	await _test_room_flow(original, saved, original_contents)
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("SWORD SHIELD GALLERY %s: exact production scenes/materials and varied vertex AO, six real view buttons, front boss/rear straps, F2/close/reset cleanup and deep original restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check_production_model(gallery: Control, id: String) -> void:
	var entry := CATALOG.get_entry(id)
	var packed: PackedScene = DungeonPlayer.SWORD_SCENE if id == IDS[0] else DungeonPlayer.SHIELD_SCENE
	_check(str(entry.get("asset_path", "")) == packed.resource_path and str(entry.get("factory_type", "")) == "sword_shield", "catalog must track the currently equipped scene: " + id)
	var actual: Node3D = gallery.object_root
	_check(actual != null and str(actual.get_meta("production_scene", "")) == packed.resource_path, "gallery must instantiate the exact production packed scene: " + id)
	if actual == null: return
	# Invoke the actual viewmodel constructor independently, including the
	# player's grip overrides; compare imported meshes and effective materials.
	var player := DungeonPlayer.new()
	player.weapon_pivot = Node3D.new()
	player.add_child(player.weapon_pivot)
	player.camera = Camera3D.new()
	player.add_child(player.camera)
	var expected: Node3D
	if id == IDS[0]:
		player._build_sword_visual(null, null, null)
		expected = player.sword_visual_root
	else:
		player._build_shield(null, null)
		expected = player.shield_model
	_check(actual.transform.is_equal_approx(expected.transform), "gallery must preserve the model's production orientation: " + id)
	var meshes := actual.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty() and meshes.size() == expected.find_children("*", "MeshInstance3D", true, false).size(), "six-view model must contain every production mesh and no extra hand: " + id)
	if id == IDS[1]: _check_vertex_ao(meshes, id)
	else: _check_imported_sword_materials(meshes)
	for mesh: MeshInstance3D in meshes:
		var source := expected.get_node_or_null(actual.get_path_to(mesh)) as MeshInstance3D
		_check(source != null and mesh.mesh == source.mesh and mesh.transform.is_equal_approx(source.transform), "gallery must share the actual imported mesh and transform: " + id + "/" + str(mesh.name))
		if source == null or source.mesh == null: continue
		for surface in source.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			var source_material := source.get_active_material(surface) as StandardMaterial3D
			_check(material != null and source_material != null, "production material must remain available: " + id)
			if material == null or source_material == null: continue
			for property in MATERIAL_PROPERTIES:
				_check(material.get(property) == source_material.get(property), "gallery must use the player's effective material: " + id + "/" + str(mesh.name) + "/" + property)
			if id == IDS[1] and material.resource_name.begins_with("FP_Shield"):
				_check_atlas_mipmaps(material.albedo_texture, id + " albedo")
				_check_atlas_mipmaps(material.normal_texture, id + " normal")
	_check(actual.find_children("*", "Skeleton3D", true, false).is_empty() and actual.find_children("*", "Camera3D", true, false).is_empty(), "equipment inspection must not include player arms or gameplay cameras")
	if id == IDS[1]:
		_check_shield_rim_uv(actual)
		var rear := actual.find_child("RearGrip", true, false) as Node3D
		_check(rear != null, "real rear strap contact must exist")
		if rear != null:
			_check(rear.global_position.z > gallery.object_bounds.get_center().z, "rear straps must face the +Z back camera, leaving the boss at the -Z front")
	player.free()


func _check_imported_sword_materials(meshes: Array) -> void:
	var source := DungeonPlayer.SWORD_SCENE.instantiate() as Node3D
	_check(meshes.size() == 7, "gallery must show all seven supplied sword surfaces, including both handle extensions")
	for part: MeshInstance3D in meshes:
		var reference := source.find_child("Sword_" + str(part.name), true, false) as MeshInstance3D
		_check(reference != null, "gallery sword must correspond to a supplied original surface: " + str(part.name))
		if reference == null: continue
		_check(part.mesh.get_surface_count() == reference.mesh.get_surface_count(), "gallery must preserve every embedded material surface")
		for surface in reference.mesh.get_surface_count():
			_check(part.get_active_material(surface) == reference.get_active_material(surface), "gallery must retain the newly supplied embedded sword material")
	source.free()


func _check_atlas_mipmaps(texture: Texture2D, context: String) -> void:
	_check(texture != null, "production atlas must be bound to the rendered material: " + context)
	if texture == null or checked_atlas_mipmaps.has(texture.resource_path): return
	checked_atlas_mipmaps[texture.resource_path] = true
	var imported_image: Image = texture.get_image()
	_check(imported_image != null and not imported_image.is_empty() and imported_image.has_mipmaps(), "actual imported atlas must contain mip levels, not only a mipmap-enabled material filter: " + context + "/" + texture.resource_path)


func _check_shield_rim_uv(model: Node3D) -> void:
	var rim_triangles := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var to_model := model.global_transform.affine_inverse() * mesh.global_transform
		var normal_basis := to_model.basis.inverse().transposed()
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null or material.resource_name != "FP_ShieldIron": continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var complete := arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array and arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array
			_check(complete, "imported shield iron must expose indexed triangles, normals and actual UVs")
			if not complete: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			complete = not indices.is_empty() and indices.size() % 3 == 0 and normals.size() == vertices.size() and uvs.size() == vertices.size()
			_check(complete, "imported shield iron must have complete triangle and UV arrays")
			if not complete: continue
			for offset in range(0, indices.size(), 3):
				var ia := indices[offset]
				var ib := indices[offset + 1]
				var ic := indices[offset + 2]
				var planar_rim := true
				var points: Array[Vector3] = []
				for vertex in [ia, ib, ic]:
					if vertex < 0 or vertex >= vertices.size():
						_check(false, "shield triangle index must address a real imported vertex")
						planar_rim = false
						break
					var point: Vector3 = to_model * vertices[vertex]
					var normal: Vector3 = (normal_basis * normals[vertex]).normalized()
					points.append(point)
					# All three vertices must lie on the broad planar ring. Rivet
					# sides, curved crowns and polar triangles are not this surface.
					if Vector2(point.x, point.y).length() <= 0.39 or absf(normal.z) <= 0.99:
						planar_rim = false
				if not planar_rim: continue
				if absf(points[0].z - points[1].z) > 0.000001 or absf(points[0].z - points[2].z) > 0.000001: continue
				var face_normal := (points[1] - points[0]).cross(points[2] - points[0])
				if face_normal.length_squared() <= 0.000000000001 or absf(face_normal.normalized().z) <= 0.99: continue
				rim_triangles += 1
				var uv_area := absf((uvs[ib] - uvs[ia]).cross(uvs[ic] - uvs[ia])) * 0.5
				_check(is_finite(uv_area) and uv_area > 0.0000000001, "broad iron rim triangle must have two-dimensional UV area instead of stretching one atlas row: " + str(mesh.name) + "/" + str(offset))
	_check(rim_triangles > 0, "UV regression must inspect actual broad front/back iron rim triangles")


func _check_vertex_ao(meshes: Array, id: String) -> void:
	var colored_surfaces := 0
	var varied_surfaces := 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if not arrays[Mesh.ARRAY_COLOR] is PackedColorArray: continue
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.is_empty(): continue
			colored_surfaces += 1
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check(colors.size() == vertices.size(), "imported AO must supply a COLOR value for every surface vertex: " + id)
			var darkest := 1.0
			var brightest := 0.0
			var valid_colors := true
			for color: Color in colors:
				for channel in [color.r, color.g, color.b, color.a]:
					if not is_finite(channel) or channel < 0.0 or channel > 1.0: valid_colors = false
				var brightness := (color.r + color.g + color.b) / 3.0
				darkest = minf(darkest, brightness)
				brightest = maxf(brightest, brightness)
			_check(valid_colors, "imported vertex AO colors must remain finite and normalized: " + id)
			if brightest - darkest > 0.01: varied_surfaces += 1
	_check(colored_surfaces > 0 and varied_surfaces > 0, "actual imported GLB COLOR data must contain multiple AO brightness values within a surface, not only uniform material tint: " + id)


func _check_six_views(gallery: Control) -> void:
	var transforms: Array[Transform3D] = []
	for index in GALLERY.VIEWS.size():
		gallery.view_buttons[index].pressed.emit()
		_check(gallery.selected_view == GALLERY.VIEWS[index] and gallery.view_buttons[index].button_pressed, "each live direction button must select its requested view")
		var camera: Camera3D = gallery.camera
		var bounds: AABB = gallery.object_bounds
		_check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and (camera.position - bounds.get_center()).normalized().is_equal_approx(GALLERY.DIRECTIONS[index]), "six views must use the true distinct orthographic model axes")
		_check(not transforms.has(camera.transform), "different direction labels must never reuse one camera pose")
		transforms.append(camera.transform)
		var projected_min := Vector2(INF, INF)
		var projected_max := Vector2(-INF, -INF)
		for endpoint in 8:
			var point := camera.unproject_position(bounds.get_endpoint(endpoint))
			projected_min = projected_min.min(point)
			projected_max = projected_max.max(point)
			_check(point.is_finite() and point.x >= 0.0 and point.y >= 0.0 and point.x <= gallery.viewport.size.x and point.y <= gallery.viewport.size.y, "complete current mesh bounds must fit every direction without fixed model dimensions")
		var visible_extent := projected_max - projected_min
		_check(maxf(visible_extent.x, visible_extent.y) >= gallery.viewport.size.y * 0.75, "axial inspection must fill the viewer with the visible guard/pommel profile, not the hidden blade length")


func _test_room_flow(original: ExpeditionInventory, saved: Dictionary, original_contents: Dictionary) -> void:
	var room := (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var sandbox := root.get_node("TestRoomSandbox")
	var trial: ExpeditionInventory = room.inventory
	_check(sandbox.active and trial != original and paused and room.panel_open, "inspection must enter the ordinary isolated paused trial")
	var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "dark_fantasy_gallery" and entry.action == "dark_fantasy_gallery")
	_check(matches.size() == 1, "test room must expose one executable six-direction gallery action")
	for index in IDS.size():
		var trial_before := ExpeditionSession.capture_snapshot()
		var trial_contents := _inventory_contents(trial)
		room.run_feature("dark_fantasy_gallery")
		await process_frame
		var gallery: Control = room.art_gallery
		_check(is_instance_valid(gallery) and paused and not room.panel_open, "real gallery must open while gameplay stays paused")
		if not is_instance_valid(gallery): continue
		var entries := CATALOG.entries()
		for selected in entries.size():
			if str(entries[selected].id) == IDS[index]: gallery.selector.item_selected.emit(selected)
		_check(gallery.object_id == IDS[index], "live object selector must open the requested current equipment model")
		_check_production_model(gallery, IDS[index])
		_check_six_views(gallery)
		_check(ExpeditionSession.capture_snapshot() == trial_before and _inventory_contents(trial) == trial_contents and sandbox.saved_session == saved and _inventory_contents(original) == original_contents, "inspection must preserve both trial and original unique item metadata")
		var viewport_ref: WeakRef = weakref(gallery.viewport)
		if index == 0:
			var event := InputEventKey.new()
			event.keycode = KEY_F2
			event.physical_keycode = KEY_F2
			event.pressed = true
			room._unhandled_input(event)
		else: gallery.close_button.pressed.emit()
		await process_frame
		_check(room.panel_open and paused and not is_instance_valid(room.art_gallery) and viewport_ref.get_ref() == null, "F2 and return must free the viewer and restore the paused trial menu")
	room.run_feature("dark_fantasy_gallery")
	room.art_gallery.select_object(IDS[1])
	var reset_viewport: WeakRef = weakref(room.art_gallery.viewport)
	room.reset_room()
	await process_frame
	_check(reset_viewport.get_ref() == null and not is_instance_valid(room.art_gallery) and room.inventory != trial and room.panel_open and paused and sandbox.saved_session == saved, "reset must free the equipment viewer and replace only the trial bag")
	room.run_feature("dark_fantasy_gallery")
	room.art_gallery.select_object(IDS[0])
	var final_viewport: WeakRef = weakref(room.art_gallery.viewport)
	room.leave_room()
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://main_menu.tscn" and not sandbox.active and not loading: break
		await process_frame
	_check(final_viewport.get_ref() == null and not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved and _inventory_contents(original) == original_contents, "exit must free the equipment viewer and restore exact original inventory, equipped IDs and nested enhancement data")


func _inventory_contents(inventory: ExpeditionInventory) -> Dictionary:
	return {"slots": inventory.slots.duplicate(true), "equipment": inventory.equipment.duplicate(true), "equipment_data": inventory.equipment_data.duplicate(true)}


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
