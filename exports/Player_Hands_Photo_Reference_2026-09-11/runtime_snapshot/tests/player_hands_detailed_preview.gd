extends SceneTree
## Actual opt-in player hands, driven by normal bow/chest functions in a private
## SubViewport. This launch path requires the audited windowless renderer.

const BASE := preload("res://tests/player_arm_preview.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_hands_detailed"
const POSE_IDS := ["free_hands", "bow_draw", "bow_release", "chest_touch", "chest_lift"]
const SOURCE_FILES := [
	"res://assets/3d/player/hands_detailed/left_hand_detailed.glb",
	"res://assets/3d/player/hands_detailed/right_hand_detailed.glb",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_basecolor.png",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_basecolor.png.import",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_normal.png",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_normal.png.import",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_roughness.png",
	"res://assets/3d/player/hands_detailed/left_hand_detailed_reference_hands_roughness.png.import",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_basecolor.png",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_basecolor.png.import",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_normal.png",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_normal.png.import",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_roughness.png",
	"res://assets/3d/player/hands_detailed/right_hand_detailed_reference_hands_roughness.png.import",
	"res://assets/3d/player/hands_greybox/left_hand_greybox.glb",
	"res://assets/3d/player/hands_greybox/right_hand_greybox.glb",
	"res://scripts/greybox_arm_visual.gd",
	"res://scripts/wrist_cuff_deformer.gd",
	"res://scripts/player_arm_visual.gd",
	"res://scripts/player.gd",
	"res://scripts/chest_hand_visuals.gd",
	"res://tests/player_arm_preview.gd",
	"res://tests/player_hands_detailed_preview.gd",
]
var failures: Array[String] = []
var captures: Array[Dictionary] = []
static var _skin_join_sources: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Detailed captures require the audited tests/run_embedded_preview.sh renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_HANDS_DETAILED_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_HANDS_DETAILED_QA_ITERATION must name a new plain output folder.")
		quit(2)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Detailed capture folder already exists; choose a new iteration.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create detailed capture folder.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var original := ExpeditionSession.capture_snapshot()
	var original_contents := inventory_contents(original.get("inventory") as ExpeditionInventory)
	var cursor := Input.mouse_mode
	var hashes := source_hashes()
	for path: String in SOURCE_FILES:
		if str(hashes[path]).length() != 64: failures.append("Missing capture source: " + path)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	for pose_id: String in POSE_IDS:
		if not configure_pose(fixture, pose_id):
			failures.append("Could not configure production detailed pose: " + pose_id)
			continue
		var inspection := inspect_pose(fixture, pose_id)
		if not inspection.passed: failures.append("Production detailed state failed: " + pose_id)
		await _capture(viewport, output_path, pose_id, inspection, fixture)
		if pose_id == "free_hands":
			# Switch just the real geometry at this exact production pose and camera,
			# without advancing the action clock or manufacturing comparison hands.
			var player := fixture.player as DungeonPlayer
			var before := [player.left_support_arm.global_transform, player.right_relaxed_arm.global_transform, player.camera.global_transform]
			if not player.set_hands_visual_profile("greybox"):
				failures.append("Could not select preserved greybox for comparison.")
			else:
				player.viewmodel_renderer.sync_view()
				var exact_pose := before == [player.left_support_arm.global_transform, player.right_relaxed_arm.global_transform, player.camera.global_transform]
				if not exact_pose: failures.append("Greybox comparison changed the production pose or camera.")
				await _capture(viewport, output_path, "free_hands_greybox", {"pose": "free_hands", "profile": "greybox", "same_pose_and_camera": exact_pose, "greybox": player.get_hands_greybox_snapshot(), "passed": exact_pose and player.hands_greybox_enabled}, fixture)
			player.set_hands_visual_profile("detailed")
	(fixture.player as DungeonPlayer).cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == original and inventory_contents(original.get("inventory") as ExpeditionInventory) == original_contents and Input.mouse_mode == cursor
	if not preserved: failures.append("Detailed preview changed original inventory, expedition or cursor.")
	var sources_preserved := source_hashes() == hashes
	if not sources_preserved: failures.append("Detailed sources changed during capture.")
	var manifest := {
		"display_driver": DisplayServer.get_name(),
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"capture_kind": "Actual DungeonPlayer opt-in detailed arms and timed DungeonLootChest contact in an isolated SubViewport",
		"desktop_capture": false,
		"external_input": false,
		"expedition_inventory_and_cursor_preserved": preserved,
		"source_sha256": hashes,
		"sources_unchanged_during_capture": sources_preserved,
		"captures": captures,
		"failures": failures,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: failures.append("Could not save detailed capture manifest.")
	for failure in failures: push_error(failure)
	print("PLAYER HANDS DETAILED PREVIEW %s: %d actual poses; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)


func _capture(viewport: SubViewport, output_path: String, pose_id: String, inspection: Dictionary, fixture: Dictionary) -> void:
	for _frame in 12: await process_frame
	RenderingServer.force_draw(false)
	if inspection.get("profile", "detailed") == "greybox":
		inspection["skin_cuff_joins"] = {"applicable": false, "reason": "Preserved greybox comparison has its original rigid cuff; detailed skin join is not active."}
	else:
		var joins := inspect_active_skin_cuff_joins(fixture.player)
		inspection["skin_cuff_joins"] = joins
		inspection.passed = inspection.passed and joins.passed
		if not joins.passed: failures.append("Actual rendered skin and cuff surfaces separate: " + pose_id)
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		failures.append("Actual renderer returned no pixels: " + pose_id)
		return
	var file_name := pose_id + ".png"
	if rendered.save_png(output_path.path_join(file_name)) != OK:
		failures.append("Could not save detailed capture: " + pose_id)
		return
	inspection["image"] = file_name
	inspection["image_sha256"] = FileAccess.get_sha256(output_path.path_join(file_name))
	captures.append(inspection)
	print("PLAYER HANDS DETAILED CAPTURE: " + output_path.path_join(file_name))


static func create_viewport() -> SubViewport:
	var viewport := BASE.create_viewport()
	viewport.name = "PlayerHandsDetailedPreviewViewport"
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	return BASE.populate_viewport(viewport)


static func inspect_hand_roles(arm: Node3D) -> Dictionary:
	var skin_surfaces := 0
	var nail_digits: Array[String] = []
	var cuff_surfaces := 0
	var forearm_surfaces := 0
	var upperarm_surfaces := 0
	var passed := arm != null
	if arm == null: return {"passed": false}
	for mesh: MeshInstance3D in arm.get("hand_meshes") + arm.get("arm_meshes"):
		var name_text := str(mesh.name)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material == null:
				passed = false
				continue
			if mesh.skin != null:
				if name_text.begins_with("Nail_"):
					passed = passed and material.resource_name.begins_with("Detailed_Nail")
					for digit: String in ["thumb", "index", "middle", "ring", "little"]:
						if name_text.begins_with("Nail_" + digit) and not nail_digits.has(digit): nail_digits.append(digit)
				else:
					passed = passed and material.resource_name.begins_with("Detailed_Skin")
					skin_surfaces += 1
			elif name_text.begins_with("WristCuff"):
				cuff_surfaces += 1
			elif name_text.begins_with("Forearm"):
				forearm_surfaces += 1
			elif name_text.begins_with("UpperArm"):
				upperarm_surfaces += 1
	passed = passed and skin_surfaces > 0 and nail_digits.size() == 5 and cuff_surfaces > 0 and forearm_surfaces > 0 and upperarm_surfaces > 0
	return {"passed": passed, "skin_surfaces": skin_surfaces, "nail_digits": nail_digits, "cuff_surfaces": cuff_surfaces, "forearm_surfaces": forearm_surfaces, "upperarm_surfaces": upperarm_surfaces}


static func inspect_active_hand_roles(player: DungeonPlayer) -> Dictionary:
	var hands: Array[Dictionary] = []
	var passed := true
	for wrapper: Node3D in [player.left_support_arm, player.right_relaxed_arm, player._legacy_weapon_arm, player.torch_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]:
		var arm := wrapper.get("detailed_visual") as Node3D
		if arm == null or not arm.is_visible_in_tree(): continue
		var report := inspect_hand_roles(arm)
		report["arm"] = str(wrapper.name)
		hands.append(report)
		passed = passed and bool(report.passed)
	return {"passed": passed and hands.size() >= 2, "hands": hands}


static func inspect_active_skin_cuff_joins(player: DungeonPlayer) -> Dictionary:
	var hands: Array[Dictionary] = []
	var passed := true
	for wrapper: Node3D in [player.left_support_arm, player.right_relaxed_arm, player._legacy_weapon_arm, player.torch_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]:
		var arm := wrapper.get("detailed_visual") as Node3D
		if arm == null or not arm.is_visible_in_tree(): continue
		var report := inspect_skin_cuff_join(arm)
		report["arm"] = str(wrapper.name)
		hands.append(report)
		passed = passed and bool(report.passed)
	return {"passed": passed and hands.size() >= 2, "hands": hands}


static func inspect_skin_cuff_join(arm: Node3D) -> Dictionary:
	# Compare the actual skinned proximal surface with the same source cuff
	# triangles after fitting. The skin has small thumb influences, so hold its
	# current finger pose constant when measuring separation added by arm fitting.
	var source := _skin_join_source(arm)
	var report: Dictionary = arm.call("get_wrist_snapshot")
	var skeleton := arm.get("skeleton") as Skeleton3D
	var inverse := arm.global_transform.affine_inverse()
	var skin_cache := {}
	var cuff_cache := {}
	var maximum_source_gap := 0.0
	var maximum_posed_gap := 0.0
	var maximum_fixed_pose_gap := 0.0
	var maximum_added_gap := 0.0
	var maximum_surface_shift := 0.0
	var maximum_skin_motion := 0.0
	var posed_skin_points: Array[Vector3] = []
	var outside_fixed_span := 0
	var finite := true
	for pair: Dictionary in source.pairs:
		var skin_key: String = pair.skin_key
		var skin_source: Dictionary = source.skins[skin_key]
		if not skin_cache.has(skin_key):
			var mesh := arm.find_child(skin_source.mesh_name, true, false) as MeshInstance3D
			var matrices: Array[Transform3D] = []
			for bind in mesh.skin.get_bind_count():
				var bone := mesh.skin.get_bind_bone(bind)
				if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
				matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
			var amounts: Array[float] = []
			for shape in mesh.get_blend_shape_count(): amounts.append(mesh.get_blend_shape_value(shape))
			skin_cache[skin_key] = {"matrices": matrices, "amounts": amounts, "transform": inverse * mesh.global_transform}
		var state: Dictionary = skin_cache[skin_key]
		var vertex: int = pair.skin_vertex
		var point: Vector3 = skin_source.vertices[vertex]
		for shape in state.amounts.size():
			if absf(state.amounts[shape]) < 0.000001: continue
			var delta: Vector3 = skin_source.shapes[shape][vertex]
			if skin_source.normalized: delta -= skin_source.vertices[vertex]
			point += delta * float(state.amounts[shape])
		var skinned := Vector3.ZERO
		for influence in int(skin_source.stride):
			var entry := vertex * int(skin_source.stride) + influence
			skinned += (state.matrices[skin_source.bones[entry]] * point) * float(skin_source.weights[entry])
		var skin_point: Vector3 = state.transform * skinned
		posed_skin_points.append(skin_point)
		maximum_skin_motion = maxf(maximum_skin_motion, skin_point.distance_to(pair.rest_skin))
		var cuff_key: String = pair.cuff_mesh + ":" + str(pair.cuff_surface)
		if not cuff_cache.has(cuff_key):
			var mesh := arm.find_child(pair.cuff_mesh, true, false) as MeshInstance3D
			cuff_cache[cuff_key] = {"vertices": mesh.mesh.surface_get_arrays(pair.cuff_surface)[Mesh.ARRAY_VERTEX], "transform": inverse * mesh.global_transform}
		var cuff: Dictionary = cuff_cache[cuff_key]
		var ids: Vector3i = pair.cuff_indices
		var bary: Vector3 = pair.barycentric
		var cuff_point: Vector3 = cuff.transform * (cuff.vertices[ids.x] * bary.x + cuff.vertices[ids.y] * bary.y + cuff.vertices[ids.z] * bary.z)
		var posed_gap := skin_point.distance_to(cuff_point)
		var fixed_pose_gap := skin_point.distance_to(pair.rest_cuff)
		maximum_source_gap = maxf(maximum_source_gap, (pair.rest_skin as Vector3).distance_to(pair.rest_cuff))
		maximum_posed_gap = maxf(maximum_posed_gap, posed_gap)
		maximum_fixed_pose_gap = maxf(maximum_fixed_pose_gap, fixed_pose_gap)
		maximum_added_gap = maxf(maximum_added_gap, posed_gap - fixed_pose_gap)
		maximum_surface_shift = maxf(maximum_surface_shift, cuff_point.distance_to(pair.rest_cuff))
		if float(pair.support_max_z) > float(report.blend_start_z) + 0.000001: outside_fixed_span += 1
		finite = finite and skin_point.is_finite() and cuff_point.is_finite()
	# Also measure the nearest actual outer surface, independently of the fixed
	# correspondence. Sliding along a surface may preserve a join; a gap already
	# present in the posed skin is still a defect even if arm fitting adds none.
	var current_triangles: Array[Dictionary] = []
	for triangle: Dictionary in source.triangles:
		var key: String = triangle.mesh_name + ":" + str(triangle.surface)
		if not cuff_cache.has(key):
			var mesh := arm.find_child(triangle.mesh_name, true, false) as MeshInstance3D
			cuff_cache[key] = {"vertices": mesh.mesh.surface_get_arrays(triangle.surface)[Mesh.ARRAY_VERTEX], "transform": inverse * mesh.global_transform}
		var cuff: Dictionary = cuff_cache[key]
		var ids: Vector3i = triangle.indices
		var a: Vector3 = cuff.transform * cuff.vertices[ids.x]
		var b: Vector3 = cuff.transform * cuff.vertices[ids.y]
		var c: Vector3 = cuff.transform * cuff.vertices[ids.z]
		current_triangles.append({"a": a, "b": b, "c": c, "minimum": a.min(b).min(c), "maximum": a.max(b).max(c)})
	var maximum_nearest_gap := 0.0
	for skin_point: Vector3 in posed_skin_points:
		var nearest_squared := INF
		for triangle: Dictionary in current_triangles:
			var nearest_box := skin_point.clamp(triangle.minimum, triangle.maximum)
			if skin_point.distance_squared_to(nearest_box) >= nearest_squared: continue
			var bary := _closest_triangle_barycentric(skin_point, triangle.a, triangle.b, triangle.c)
			var contact: Vector3 = triangle.a * bary.x + triangle.b * bary.y + triangle.c * bary.z
			nearest_squared = minf(nearest_squared, skin_point.distance_squared_to(contact))
		maximum_nearest_gap = maxf(maximum_nearest_gap, sqrt(nearest_squared))
	# The authored overlap is 0.157–0.429 mm. A generous 0.6 mm source seating
	# limit includes triangulation; fitting may add only the existing 50 µm
	# geometry tolerance. No condition assumes the skin boundary is pure wrist.
	var passed: bool = bool(report.enabled) and finite and source.pairs.size() >= 32 and maximum_source_gap < 0.0006 and maximum_nearest_gap < 0.001 and maximum_added_gap < 0.00005 and maximum_surface_shift < 0.00005 and outside_fixed_span == 0
	return {"passed": passed, "sample_count": source.pairs.size(), "skin_proximal_z_m": source.proximal_z, "maximum_source_gap_m": maximum_source_gap, "maximum_posed_correspondence_gap_m": maximum_posed_gap, "maximum_actual_nearest_outer_gap_m": maximum_nearest_gap, "maximum_skin_boundary_motion_m": maximum_skin_motion, "maximum_same_finger_pose_fixed_cuff_gap_m": maximum_fixed_pose_gap, "maximum_fit_added_gap_m": maximum_added_gap, "maximum_cuff_surface_shift_m": maximum_surface_shift, "support_triangles_outside_fixed_span": outside_fixed_span}


static func _skin_join_source(arm: Node3D) -> Dictionary:
	var path := str((arm.call("get_snapshot") as Dictionary).source_model)
	if _skin_join_sources.has(path): return _skin_join_sources[path]
	var inverse := arm.global_transform.affine_inverse()
	var skins := {}
	var proximal_z := -INF
	for mesh: MeshInstance3D in arm.get("hand_meshes"):
		if mesh.skin == null or str(mesh.name).begins_with("Nail_"): continue
		for surface in mesh.mesh.get_surface_count():
			if not mesh.get_active_material(surface).resource_name.begins_with("Detailed_Skin"): continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var transform := inverse * mesh.global_transform
			for point: Vector3 in vertices: proximal_z = maxf(proximal_z, (transform * point).z)
			var shapes: Array[PackedVector3Array] = []
			for values: Array in mesh.mesh.surface_get_blend_shape_arrays(surface): shapes.append(values[Mesh.ARRAY_VERTEX])
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			skins[str(mesh.name) + ":" + str(surface)] = {"mesh_name": str(mesh.name), "vertices": vertices, "bones": bones, "weights": arrays[Mesh.ARRAY_WEIGHTS], "stride": bones.size() / maxi(1, vertices.size()), "shapes": shapes, "normalized": (mesh.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, "transform": transform}
	var triangles: Array[Dictionary] = []
	var wrist: Dictionary = arm.call("get_wrist_snapshot")
	for surface: Dictionary in wrist.surfaces:
		var mesh := surface.mesh as MeshInstance3D
		var original: Mesh = arm.get("_wrist_cuff_deformer").source_mesh_for(mesh)
		var arrays := original.surface_get_arrays(surface.surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var transform: Transform3D = surface.mesh_to_adapter
		var normal_basis := transform.basis.inverse().transposed()
		for start in range(0, indices.size(), 3):
			var ids := Vector3i(indices[start], indices[start + 1], indices[start + 2])
			var a := transform * vertices[ids.x]
			var b := transform * vertices[ids.y]
			var c := transform * vertices[ids.z]
			if (b - a).cross(c - a).length_squared() < 0.00000000000000000001: continue
			var minimum_z := minf(a.z, minf(b.z, c.z))
			var maximum_z := maxf(a.z, maxf(b.z, c.z))
			var center := (a + b + c) / 3.0
			var normal := (normal_basis * (normals[ids.x] + normals[ids.y] + normals[ids.z])).normalized()
			if normal.dot(Vector3(center.x, center.y, 0.0).normalized()) < 0.2: continue
			triangles.append({"mesh_name": str(mesh.name), "surface": surface.surface, "indices": ids, "a": a, "b": b, "c": c, "min_z": minimum_z, "max_z": maximum_z})
	var pairs: Array[Dictionary] = []
	for skin_key: String in skins:
		var skin: Dictionary = skins[skin_key]
		for vertex in skin.vertices.size():
			var point: Vector3 = skin.transform * skin.vertices[vertex]
			if point.z < proximal_z - 0.001: continue
			var closest := INF
			var pair := {}
			for triangle: Dictionary in triangles:
				if float(triangle.min_z) > proximal_z + 0.002 or float(triangle.max_z) < proximal_z - 0.003: continue
				var bary := _closest_triangle_barycentric(point, triangle.a, triangle.b, triangle.c)
				var contact: Vector3 = triangle.a * bary.x + triangle.b * bary.y + triangle.c * bary.z
				var distance := point.distance_squared_to(contact)
				if distance >= closest: continue
				closest = distance
				pair = {"skin_key": skin_key, "skin_vertex": vertex, "rest_skin": point, "rest_cuff": contact, "cuff_mesh": triangle.mesh_name, "cuff_surface": triangle.surface, "cuff_indices": triangle.indices, "barycentric": bary, "support_max_z": triangle.max_z}
			if not pair.is_empty(): pairs.append(pair)
	var result := {"skins": skins, "pairs": pairs, "triangles": triangles, "proximal_z": proximal_z}
	_skin_join_sources[path] = result
	return result


static func _closest_triangle_barycentric(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return Vector3(1, 0, 0)
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var value := d1 / (d1 - d3)
		return Vector3(1.0 - value, value, 0)
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var value := d2 / (d2 - d6)
		return Vector3(1.0 - value, 0, value)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		var value := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - value, value)
	var inverse := 1.0 / (va + vb + vc)
	return Vector3(1.0 - (vb + vc) * inverse, vb * inverse, vc * inverse)


static func configure_pose(fixture: Dictionary, pose_id: String) -> bool:
	if not POSE_IDS.has(pose_id): return false
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	var base_pose := "idle" if pose_id == "free_hands" else "bow_draw" if pose_id == "bow_release" else pose_id
	if not BASE.configure_pose(fixture, base_pose): return false
	if not player.set_hands_detailed_enabled(true): return false
	player.set_torch_enabled(false)
	fixture["arrows_before_release"] = bag.count_item("wooden_arrow")
	fixture["action_result"] = {}
	if pose_id == "free_hands":
		for slot: String in ["weapon", "offhand"]:
			if not str(bag.equipment.get(slot, "")).is_empty() and not bool(bag.unequip(slot).get("accepted", false)): return false
	elif pose_id == "bow_release":
		fixture.action_result = player.release_bow_shot()
		if not bool(fixture.action_result.get("accepted", false)): return false
		# A capture records the real release frame without advancing projectiles
		# through a fixture that is deliberately not simulating gameplay input.
		for projectile in player.get_tree().get_nodes_in_group("arrow_projectile"):
			projectile.set_physics_process(false)
		# Progress the same cooldown/recoil clock as gameplay so this image shows
		# the actual finger release, not the still-hooked first instant of a shot.
		player.advance_action_timers(0.12)
	player._update_viewmodel(0.12 if pose_id == "bow_release" else 1.0)
	player._update_torch(0.0)
	player.viewmodel_renderer.sync_view()
	return true


static func inspect_pose(fixture: Dictionary, pose_id: String) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	var result := {
		"pose": pose_id,
		"detailed": player.get_hands_detailed_snapshot(),
		"weapon": str(bag.equipment.get("weapon", "")),
		"offhand": str(bag.equipment.get("offhand", "")),
		"bow_drawing": player.bow_drawing,
		"bow_draw_ratio": player.get_bow_draw_ratio(),
		"arrow_count": bag.count_item("wooden_arrow"),
		"chest_phase": player.chest_hands.phase,
		"passed": POSE_IDS.has(pose_id) and player.hands_detailed_enabled and not player.is_physics_processing() and not player.is_processing_unhandled_input(),
	}
	result["bare_hand_roles"] = inspect_active_hand_roles(player)
	result["skin_cuff_joins"] = inspect_active_skin_cuff_joins(player)
	result.passed = result.passed and result.bare_hand_roles.passed and result.skin_cuff_joins.passed
	if pose_id == "free_hands":
		result.passed = result.passed and result.weapon.is_empty() and result.offhand.is_empty() and player.left_support_arm.is_visible_in_tree() and player.right_relaxed_arm.is_visible_in_tree()
	elif pose_id == "bow_draw":
		result.passed = result.passed and player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), 1.0)
	elif pose_id == "bow_release":
		var hand_report: Dictionary = player._legacy_weapon_arm.get("detailed_visual").get_snapshot()
		result["string_hook_amount"] = hand_report.string_hook_amount
		result.passed = result.passed and not player.bow_drawing and result.arrow_count == int(fixture.arrows_before_release) - 1 and float(hand_report.string_hook_amount) < 0.95
	elif pose_id.begins_with("chest_"):
		var contact_errors: Array[float] = []
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side == -1 else player.chest_hands.right_hand
			var contact: Transform3D = fixture.chest.get_hand_contact_transform(side, player.get_timed_interaction_progress())
			contact_errors.append(hand.global_position.distance_to(contact.origin))
		result["hand_contact_distances"] = contact_errors
		result.passed = result.passed and player.is_timed_interacting() and player.chest_equipment_stowed and contact_errors.max() < 0.025
	return result


static func inventory_contents(inventory: ExpeditionInventory) -> Dictionary:
	if inventory == null: return {}
	return {"slots": inventory.slots.duplicate(true), "equipment": inventory.equipment.duplicate(true), "equipment_data": inventory.equipment_data.duplicate(true)}


static func source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_FILES: result[path] = FileAccess.get_sha256(path)
	return result
