extends SceneTree

const ARM := preload("res://scripts/greybox_arm_visual.gd")
const PREVIEW := preload("res://tests/player_hands_detailed_preview.gd")
const EQUIPMENT_LAYER := 1 << 19
var failures: Array[String] = []
var _wrist_auditor := WristGeometryAudit.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_imported_rigs_and_actual_skin()
	await _test_player_runtime_and_preview()
	await _test_room_lifecycle()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER HANDS DETAILED %s: bilateral imported skin and handedness, real finger deformation, free/bow/chest gameplay, render layers, default fidelity and isolated F2/repeat/switch/reset/exit" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_imported_rigs_and_actual_skin() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var stage := Node3D.new()
	root.add_child(stage)
	stage.transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(1.0, 0.5, -1.0))
	for side in [-1, 1]:
		var arm := ARM.new()
		stage.add_child(arm)
		_check(arm.setup(side, "detailed"), "detailed source must load for side " + str(side))
		var skeleton := arm.skeleton as Skeleton3D
		_check(skeleton != null and skeleton.get_bone_count() == 16, "both imported hands must retain all sixteen deform bones")
		if skeleton == null: continue
		_check(skeleton.find_bone("wrist") >= 0, "imported rig must retain the wrist bone")
		for digit: String in ["index", "middle", "ring", "little", "thumb"]:
			for joint in 3:
				_check(skeleton.find_bone(digit + str(joint)) >= 0, "all five digits require three imported joints: " + digit)
		var thumb := skeleton.get_bone_global_rest(skeleton.find_bone("thumb0")).origin
		var index := skeleton.get_bone_global_rest(skeleton.find_bone("index0")).origin
		var little := skeleton.get_bone_global_rest(skeleton.find_bone("little0")).origin
		_check(thumb.x * side < -0.01 and (index.x - little.x) * side < -0.04, "actual skeleton anatomy must match left/right handedness in dorsal wrist space")
		_check(arm.global_basis.determinant() > 0.0, "handedness must come from actual bilateral geometry without a reflected runtime frame")
		var source_path := "res://assets/3d/player/hands_detailed/%s_hand_detailed.glb" % ("left" if side < 0 else "right")
		var source := (load(source_path) as PackedScene).instantiate()
		var source_meshes: Array[Mesh] = []
		for mesh in _meshes(source): source_meshes.append(mesh.mesh)
		var greybox_path := "res://assets/3d/player/hands_greybox/%s_hand_greybox.glb" % ("left" if side < 0 else "right")
		var greybox := (load(greybox_path) as PackedScene).instantiate()
		_check(_geometry_fingerprint(source) != _geometry_fingerprint(greybox), "detailed source must differ geometrically from the greybox, not only by materials")
		greybox.free()
		var previous_path := "res://assets/3d/player/sword_shield/%s_arm.glb" % ("left" if side < 0 else "right")
		var previous := (load(previous_path) as PackedScene).instantiate()
		var dense_hand := source.find_child("ContinuousAnatomicalHand*", true, false) as MeshInstance3D
		var previous_hand := previous.find_child("ContinuousAnatomicalHand*", true, false) as MeshInstance3D
		_check(dense_hand != null and previous_hand != null and _geometry_fingerprint(dense_hand) != _geometry_fingerprint(previous_hand), "the reference-based bare hand must contain actual reshaped skin geometry")
		previous.free()
		var skinned_count := 0
		var material_names: Array[String] = []
		var pbr := PBRMaterialAudit.new()
		for mesh in _meshes(arm):
			var original_mesh := source.find_child(str(mesh.name), true, false) as MeshInstance3D
			var rendered_source: Mesh = arm._wrist_cuff_deformer.source_mesh_for(mesh)
			_check(source_meshes.has(rendered_source), "every rendered part must retain its actual imported GLB source resource")
			if mesh.mesh != rendered_source:
				_check(original_mesh != null and original_mesh.mesh == rendered_source and str(mesh.name).begins_with("WristCuff") and mesh.skin == null, "only the authored unskinned cuff may use a private deforming mesh copy")
			_check(mesh.mesh.get_aabb().size.length() > 0.001, "skin, nail and garment details must have nonempty physical geometry")
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				_check(material != null, "every detailed surface needs an actual material")
				if material == null: continue
				if not material_names.has(material.resource_name): material_names.append(material.resource_name)
				_check(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "detailed geometry must respond to actual gameplay lighting")
				pbr.inspect_surface(mesh, rendered_source, surface, material)
			if mesh.skin != null:
				skinned_count += 1
				_check(mesh.skin.get_bind_count() > 0 and mesh.get_node_or_null(mesh.skeleton) == skeleton, "visible hand geometry must really bind to its sixteen-bone Skeleton3D")
				for bind in mesh.skin.get_bind_count():
					var bound_bone := mesh.skin.get_bind_bone(bind)
					if bound_bone < 0: bound_bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
					_check(bound_bone >= 0 and bound_bone < 16 and mesh.skin.get_bind_pose(bind).is_finite(), "every authored skin bind must map to an existing deform bone")
		_check(skinned_count > 0 and arm.arm_meshes.size() >= 2, "each imported detailed requires a skinned hand plus both real arm segments")
		for material_name: String in ["Detailed_Skin", "Detailed_Nail"]:
			_check(material_names.any(func(value: String) -> bool: return value.begins_with(material_name)), "detailed parts require their actual authored surface material: " + material_name)
		_check(bool(PREVIEW.inspect_hand_roles(arm).passed), "the whole articulated hand must be bare skin, with five real nails and its actual cuff/arm parts")
		var connected_skin := _bare_skin_connectivity(arm)
		_check(int(connected_skin.component_count) == 1 and int(connected_skin.source_vertex_count) > 100, "bare skin must form one actual continuous surface without detached glove stitches: " + str(connected_skin))
		for problem: String in pbr.finish(): _check(false, "PBR side %s: %s" % [side, problem])
		_check(arm.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual substitution must not add combat or interaction collisions")
		source.free()
		arm.reset_pose()
		_audit_wrist_cuff(arm, "source rest/%s" % side)
		var wrist := arm.global_transform
		var rest := _bone_poses(skeleton)
		var open_skin := _skin_samples(arm)
		var open_skin_surface := _skin_samples(arm, "Detailed_Skin")
		var nail_samples := {}
		for digit: String in ["thumb", "index", "middle", "ring", "little"]:
			var nail := arm.find_child("Nail_" + digit + "*", true, false) as MeshInstance3D
			_check(nail != null and nail.skin != null, "all five modeled nails must be real skinned geometry: " + digit)
			if nail != null:
				_check(_weighted_bone_names(nail, skeleton) == [digit + "2"], "each modeled nail must really attach to its own distal finger joint: " + digit)
				nail_samples[str(nail.name)] = _skin_samples(arm, "Detailed_Nail", str(nail.name))
		_check(open_skin_surface.size() > 50, "deformation checks require actual bare skin surface vertices")
		_check(open_skin.size() >= 100, "deformation audit needs actual weighted source vertices")
		arm.set_finger_curl(0, -0.5, -0.8)
		_check(_bone_poses(skeleton) != rest and _max_displacement(open_skin, _skin_samples(arm)) > 0.005, "finger curl must move weighted rendered skin, not only a reported pose value")
		arm.reset_pose()
		_check(_bone_poses(skeleton) == rest and _max_displacement(open_skin, _skin_samples(arm)) < 0.00001, "reset must restore the imported open skin exactly")
		arm.set_grip(1.0)
		var grip_skin := _skin_samples(arm)
		_check(_max_displacement(open_skin, grip_skin) > 0.015, "full grip must deform the actual detailed finger surface")
		_check(_max_displacement(open_skin_surface, _skin_samples(arm, "Detailed_Skin")) > 0.015, "sculpted skin and knuckle creases must follow real finger joints")
		for nail_name: String in nail_samples:
			var open_nail: PackedVector3Array = nail_samples[nail_name]
			_check(open_nail.size() > 8 and _max_displacement(open_nail, _skin_samples(arm, "Detailed_Nail", nail_name)) > 0.005, "each modeled nail must follow its own actual distal joint: " + nail_name)
		var segments_before := _transforms(arm.arm_meshes)
		var shoulder := wrist.origin + wrist.basis * Vector3(float(side) * 0.11, 0.18, 0.55)
		var elbow := wrist.origin + wrist.basis * Vector3(float(side) * 0.13, -0.04, 0.29)
		arm.fit_arm(shoulder, elbow)
		_check(_transforms(arm.arm_meshes) != segments_before and arm.global_transform.is_equal_approx(wrist), "arm fitting must move sleeve/forearm while preserving the wrist")
		_check(_max_displacement(grip_skin, _skin_samples(arm)) < 0.00001, "arm fitting must preserve the posed hand and equipment contact frame")
		_audit_wrist_cuff(arm, "fitted arm/%s" % side)
		var updates: int = arm.get_wrist_snapshot().update_count
		arm.fit_arm(shoulder, elbow)
		_check(int(arm.get_wrist_snapshot().update_count) == updates, "an unchanged arm fit must reuse the existing cuff geometry")
		arm.reset_pose()
		_audit_wrist_cuff(arm, "reset arm/%s" % side)
		arm.set_string_draw(1.0, 0.0)
		var hook := _skin_samples(arm)
		arm.set_string_draw(1.0, 1.0)
		_check(_max_displacement(hook, _skin_samples(arm)) > 0.01 and arm.global_transform.is_equal_approx(wrist), "bow release must open real detailed finger skin without moving its wrist")
		arm.set_relaxed_pose(0.0)
		var relaxed := _skin_samples(arm)
		arm.set_relaxed_pose(1.0)
		_check(_max_displacement(relaxed, _skin_samples(arm)) > 0.005, "free-hand openness must drive the real imported skeleton")
	stage.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "standalone detailed assembly and skin checks must preserve session and cursor")


class PBRMaterialAudit extends RefCounted:
	# Sample the texels used by the real imported surfaces, rather than a swatch
	# elsewhere in the atlas. Imported image copies are released after each hand.
	var problems: Array[String] = []
	var images := {}
	var skin_samples: Array[Vector4] = []
	var skin_normals: Array[Vector2] = []
	var checked_materials := {}

	func inspect_surface(mesh: MeshInstance3D, imported_source: Mesh, surface: int, material: BaseMaterial3D) -> void:
		var context := "%s/%d/%s" % [mesh.name, surface, material.resource_name]
		var base := material.albedo_texture
		var normal := material.normal_texture
		var roughness: Texture2D
		var roughness_channel := BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if material is StandardMaterial3D:
			roughness = material.roughness_texture
			roughness_channel = material.roughness_texture_channel
		elif material is ORMMaterial3D:
			roughness = material.orm_texture
		if not checked_materials.has(material.get_instance_id()):
			checked_materials[material.get_instance_id()] = true
			if base == null or normal == null or roughness == null:
				problems.append(context + " must bind actual base color, tangent normal and roughness textures")
			if not material.normal_enabled or not is_finite(material.normal_scale) or material.normal_scale <= 0.0:
				problems.append(context + " must enable its actual tangent normal map")
			if roughness_channel != BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
				problems.append(context + " must read glTF packed roughness from the green channel")
		var base_image := _read_image(base, context)
		var normal_image := _read_image(normal, context)
		var roughness_image := _read_image(roughness, context)
		# The cuff runtime can synthesize tangents for old untextured assets.
		# Inspect the imported resource itself so that fallback cannot conceal a
		# missing UV-derived frame in a new normal-mapped GLB.
		var arrays := imported_source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.size() != vertices.size() or uv.is_empty():
			problems.append(context + " must provide authored UV coordinates for every rendered vertex")
			return
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point: Vector2 in uv:
			if not point.is_finite():
				problems.append(context + " contains an invalid UV")
				return
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		if (maximum - minimum).x * (maximum - minimum).y < 0.0000001:
			problems.append(context + " UVs collapse the material atlas")
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var triangle_count := (indices.size() if not indices.is_empty() else uv.size()) / 3
		var mapped_triangles := 0
		for triangle in triangle_count:
			var a := indices[triangle * 3] if not indices.is_empty() else triangle * 3
			var b := indices[triangle * 3 + 1] if not indices.is_empty() else triangle * 3 + 1
			var c := indices[triangle * 3 + 2] if not indices.is_empty() else triangle * 3 + 2
			if absf((uv[b] - uv[a]).cross(uv[c] - uv[a])) > 0.0000000001: mapped_triangles += 1
		if mapped_triangles == 0: problems.append(context + " must map actual triangle areas onto its texture")
		_inspect_source_tangent_frame(arrays, context, str(mesh.name).begins_with("WristCuff"))
		if not material.resource_name.begins_with("Detailed_Skin") or base_image == null or normal_image == null or roughness_image == null: return
		var sample_count := mini(2048, uv.size())
		for sample in sample_count:
			var point: Vector2 = uv[sample * uv.size() / sample_count]
			point = point * Vector2(material.uv1_scale.x, material.uv1_scale.y) + Vector2(material.uv1_offset.x, material.uv1_offset.y)
			point = Vector2(fposmod(point.x, 1.0), fposmod(point.y, 1.0)) if material.texture_repeat else point.clamp(Vector2.ZERO, Vector2.ONE)
			var color := _pixel(base_image, point) * material.albedo_color
			var normal_color := _pixel(normal_image, point)
			var roughness_value := _pixel(roughness_image, point).g * material.roughness
			skin_samples.append(Vector4(color.r, color.g, color.b, roughness_value))
			skin_normals.append(Vector2(normal_color.r, normal_color.g))

	func _inspect_source_tangent_frame(arrays: Array, context: String, is_cuff: bool) -> void:
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		if tangents.size() != vertices.size() * 4 or normals.size() != vertices.size():
			problems.append(context + " imported GLB must carry its own complete tangent/normal frame; runtime fallback is insufficient")
			return
		var invalid_frames := 0
		for vertex in vertices.size():
			var tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])
			var sign_value := tangents[vertex * 4 + 3]
			if not tangent.is_finite() or not normals[vertex].is_finite() or not is_finite(sign_value) or absf(tangent.length() - 1.0) > 0.003 or absf(normals[vertex].length() - 1.0) > 0.003 or absf(tangent.dot(normals[vertex])) > 0.003 or absf(absf(sign_value) - 1.0) > 0.0001:
				invalid_frames += 1
		if invalid_frames > 0:
			problems.append("%s imported tangent frames must be finite, unit length and orthogonal with valid handedness (%d invalid)" % [context, invalid_frames])
		if not is_cuff: return
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var triangle_count := (indices.size() if not indices.is_empty() else vertices.size()) / 3
		var checked := 0
		var mismatched := 0
		var minimum_dots := Vector2(INF, INF)
		var maximum_dots := Vector2(-INF, -INF)
		for triangle in triangle_count:
			var a := indices[triangle * 3] if not indices.is_empty() else triangle * 3
			var b := indices[triangle * 3 + 1] if not indices.is_empty() else triangle * 3 + 1
			var c := indices[triangle * 3 + 2] if not indices.is_empty() else triangle * 3 + 2
			var edge1 := vertices[b] - vertices[a]
			var edge2 := vertices[c] - vertices[a]
			var delta1 := uv[b] - uv[a]
			var delta2 := uv[c] - uv[a]
			var determinant := delta1.cross(delta2)
			if absf(determinant) < 0.0000000001: continue
			var normal := (normals[a] + normals[b] + normals[c]).normalized()
			# Compare clear, mildly curved triangles. Sharp island corners may use
			# an averaged MikkTSpace direction rather than one triangle's gradient.
			if absf(edge1.cross(edge2).normalized().dot(normal)) < 0.9: continue
			var texture_u := (edge1 * delta2.y - edge2 * delta1.y) / determinant
			var texture_v := (edge2 * delta1.x - edge1 * delta2.x) / determinant
			texture_u = (texture_u - normal * normal.dot(texture_u)).normalized()
			texture_v = (texture_v - normal * normal.dot(texture_v)).normalized()
			if absf(texture_u.dot(texture_v)) > 0.95: continue
			var tangent := Vector3.ZERO
			var bitangent := Vector3.ZERO
			for vertex in [a, b, c]:
				var vertex_tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])
				tangent += vertex_tangent
				# Godot Forward+ reconstructs its bitangent from cross(N,T)*w.
				bitangent += normals[vertex].cross(vertex_tangent) * tangents[vertex * 4 + 3]
			tangent = (tangent - normal * normal.dot(tangent)).normalized()
			bitangent = (bitangent - normal * normal.dot(bitangent)).normalized()
			checked += 1
			# Godot's normal-map +Y opposes stored image-UV +V. Its own
			# SurfaceTool MikkTSpace callback explicitly negates fvBiTangent:
			# godotengine/godot@5b4e0cb0f scene/resources/surface_tool.cpp:1072.
			# Compare both signed directions; abs(dot) would hide a real flip.
			var dots := Vector2(tangent.dot(texture_u), bitangent.dot(-texture_v))
			minimum_dots = minimum_dots.min(dots)
			maximum_dots = maximum_dots.max(dots)
			if dots.x < 0.5 or dots.y < 0.1: mismatched += 1
		if checked < 20 or mismatched > 0:
			problems.append("%s cuff source tangents must follow actual UV derivatives (%d clear triangles, %d reversed or unrelated frames; U/normal-map-Y dot min=%s max=%s)" % [context, checked, mismatched, minimum_dots, maximum_dots])
		else:
			print("PBR CUFF SOURCE FRAME: %s; %d imported frames, %d UV-derivative comparisons, signed U/normal-map-Y min=%s; no runtime tangent fallback" % [context, vertices.size(), checked, minimum_dots])

	func _read_image(texture: Texture2D, context: String) -> Image:
		if texture == null: return null
		var id := texture.get_instance_id()
		if images.has(id): return images[id]
		if not texture.resource_path.is_empty() and not texture.resource_path.begins_with("res://"):
			problems.append(context + " texture must load from the portable project or embedded GLB")
		var image := texture.get_image()
		if image == null or image.is_empty():
			problems.append(context + " bound texture has no readable imported image")
			images[id] = null
			return null
		if image.is_compressed() and image.decompress() != OK:
			problems.append(context + " bound texture could not be decoded")
			images[id] = null
			return null
		if image.get_width() < 1024 or image.get_height() < 1024:
			problems.append(context + " requires the authored detail atlas rather than a constant fallback texture")
		images[id] = image
		return image

	func finish() -> Array[String]:
		if skin_samples.size() < 100:
			problems.append("real skin UVs must supply enough color, normal and roughness samples")
		else:
			var mean := Vector4.ZERO
			var low := Vector4(INF, INF, INF, INF)
			var high := Vector4(-INF, -INF, -INF, -INF)
			var normal_low := Vector2(INF, INF)
			var normal_high := Vector2(-INF, -INF)
			var chroma := 0.0
			for sample: Vector4 in skin_samples:
				mean += sample
				for channel in 4:
					low[channel] = minf(low[channel], sample[channel])
					high[channel] = maxf(high[channel], sample[channel])
				chroma += maxf(sample.x, maxf(sample.y, sample.z)) - minf(sample.x, minf(sample.y, sample.z))
			for sample: Vector2 in skin_normals:
				normal_low = normal_low.min(sample)
				normal_high = normal_high.max(sample)
			mean /= skin_samples.size()
			if chroma / skin_samples.size() < 0.025 or mean.x < 0.08:
				problems.append("rendered skin texels must carry visible skin color rather than the old neutral grey")
			if (Vector3(high.x, high.y, high.z) - Vector3(low.x, low.y, low.z)).length() < 0.03:
				problems.append("skin color must vary across the actual used UVs")
			if (normal_high - normal_low).length() < 0.025:
				problems.append("skin normal map must contain actual non-flat surface detail at used UVs")
			if high.w - low.w < 0.025 or mean.w < 0.1 or mean.w > 0.98:
				problems.append("skin roughness must vary across used UVs and retain a non-mirror surface")
		images.clear()
		return problems

	static func _pixel(image: Image, uv: Vector2) -> Color:
		return image.get_pixel(clampi(floori(uv.x * image.get_width()), 0, image.get_width() - 1), clampi(floori(uv.y * image.get_height()), 0, image.get_height() - 1))


func _test_player_runtime_and_preview() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var contents := PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory)
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d, "detailed preview must isolate world, external input, picking and audio")
	_check(not player.hands_detailed_enabled and player.hands_visual_profile == "original" and fixture.inventory != original.get("inventory"), "detailed must default off and QA must use the original appearance with a private inventory")
	await physics_frame
	await physics_frame
	var wrappers := [player._legacy_weapon_arm, player.torch_arm, player.left_support_arm, player.right_relaxed_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]
	var baseline := _legacy_state(wrappers)
	var bag_before := PREVIEW.inventory_contents(fixture.inventory)
	var anchors := _gameplay_anchors(player)
	_check(player.set_hands_detailed_enabled(true), "player-local opt-in must load both available detailed assets")
	_check(PREVIEW.inventory_contents(fixture.inventory) == bag_before and _gameplay_anchors(player) == anchors, "presentation toggle alone must preserve inventory, weapon hit/muzzle and equipment anchors")
	for wrapper: Node3D in wrappers:
		var detailed := wrapper.get("detailed_visual") as Node3D
		_check(detailed != null and detailed.visible, "every generic gameplay arm must connect to its actual detailed child")
		if detailed == null: continue
		var expected_layer := 1 if player.chest_hands.is_ancestor_of(wrapper) else EQUIPMENT_LAYER
		for mesh in _meshes(detailed): _check(mesh.layers == expected_layer, "late-created detailed must keep equipment layer20 or chest world layer1")
	_check(player.set_hands_detailed_enabled(false) and _legacy_state(wrappers) == baseline, "turning preview off must restore original mesh/material identities and visibility")
	_check(player.set_hands_greybox_enabled(true) and player.hands_visual_profile == "greybox" and not player.hands_detailed_enabled, "the previous greybox must remain available for comparison")
	for wrapper: Node3D in wrappers:
		_check(not bool((wrapper.get("greybox_visual").call("get_wrist_snapshot") as Dictionary).get("enabled", false)), "the unmarked preserved greybox must retain its original rigid cuff behavior")
	_check(player.set_hands_detailed_enabled(false) and player.hands_visual_profile == "greybox", "disabling inactive detail must preserve an explicitly selected greybox")
	_check(player.set_hands_detailed_enabled(true) and player.hands_visual_profile == "detailed" and not player.hands_greybox_enabled, "detailed and greybox appearances must be mutually exclusive")
	for wrapper: Node3D in wrappers:
		_check(wrapper.get("detailed_visual").visible and not wrapper.get("greybox_visual").visible, "switching to detail must hide comparison geometry without overlaying duplicate hands")
	_check(player.set_hands_greybox_enabled(false) and player.hands_visual_profile == "detailed", "disabling inactive greybox must preserve selected detailed hands")
	_check(player.set_hands_visual_profile("original") and _legacy_state(wrappers) == baseline, "explicit original profile must restore the default source appearances")
	for pose_id: String in PREVIEW.POSE_IDS:
		_check(PREVIEW.configure_pose(fixture, pose_id), "capture must configure actual gameplay: " + pose_id)
		_check(bool(PREVIEW.inspect_pose(fixture, pose_id).passed), "capture must inspect actual gameplay state: " + pose_id)
		if pose_id == "free_hands":
			_check(player.left_support_arm.get("detailed_visual").is_visible_in_tree() and player.right_relaxed_arm.get("detailed_visual").is_visible_in_tree(), "unarmed gameplay must show both real detailed hands")
		elif pose_id == "bow_draw":
			var detailed := player._legacy_weapon_arm.get("detailed_visual") as Node3D
			var pose_before := _bone_poses(detailed.get("skeleton"))
			player._legacy_weapon_arm.set_string_draw(1.0, 1.0)
			_check(_bone_poses(detailed.get("skeleton")) != pose_before, "actual bow wrapper must forward finger release into detailed bones")
			player._update_character_arms()
		elif pose_id.begins_with("chest_"):
			for side in [-1, 1]:
				_check(player.chest_hands._arms[side].get("detailed_visual").is_visible_in_tree(), "actual timed chest interaction must display both detailed hands")
		var active_wrappers: Array = [player.chest_hands._arms[-1], player.chest_hands._arms[1]] if pose_id.begins_with("chest_") else [player.left_support_arm, player.right_relaxed_arm] if pose_id == "free_hands" else [player.left_support_arm, player._legacy_weapon_arm]
		for wrapper: Node3D in active_wrappers:
			if wrapper.is_visible_in_tree(): _audit_wrist_cuff(wrapper.get("detailed_visual"), pose_id + "/" + str(wrapper.name))
		var before := _gameplay_anchors(player)
		var bag_contents := PREVIEW.inventory_contents(fixture.inventory)
		player._update_character_arms()
		_check(_gameplay_anchors(player) == before and PREVIEW.inventory_contents(fixture.inventory) == bag_contents, "detailed updates must preserve combat geometry and bag: " + pose_id)
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory) == contents and Input.mouse_mode == cursor, "preview poses and cleanup must preserve original nested inventory, session and cursor")


func _test_room_lifecycle() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	var sword := original.get_equipment_instance("weapon")
	sword["uid"] = "detailed_original_sword"
	sword["smithing"] = {"quality": 0.83, "reinforcement": "silver", "runes": ["ember"], "drill_progress": 0.25}
	original.add_item("wooden_arrow", 11)
	ExpeditionSession.crowns = 519
	ExpeditionSession.hunger = 51.5
	ExpeditionSession.thirst = 42.25
	ExpeditionSession.stress = 37.0
	var contents := PREVIEW.inventory_contents(original)
	var snapshot := ExpeditionSession.capture_snapshot()
	var signals := [0]
	var observer := func() -> void: signals[0] += 1
	original.changed.connect(observer)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_hands_detailed")
	_check(entries.size() == 1 and entries[0].action == "player_hands_detailed" and entries[0].category == "기본", "detailed requires one executable basic-category testroom entry")
	_check(sandbox.active and paused and room.panel_open and room.inventory != original and room.player.hands_visual_profile == "original", "testroom must begin isolated, paused and with the default player appearance")
	var previous_chest := 0
	for iteration in 2:
		room.run_feature("player_hands_detailed")
		var player := room.player as DungeonPlayer
		player.set_physics_process(false)
		await physics_frame
		await physics_frame
		var chest := room.arm_motion_chest as DungeonLootChest
		var bag := room.inventory as ExpeditionInventory
		_check(player.hands_detailed_enabled and not paused and not room.panel_open and is_instance_valid(chest) and not chest.opened, "detailed trial must resume actual gameplay and prepare a real closed chest")
		_check(chest.get_instance_id() != previous_chest, "reselecting detailed must create a fresh closed chest")
		previous_chest = chest.get_instance_id()
		_check(str(bag.equipment.get("weapon", "")).is_empty() and str(bag.equipment.get("offhand", "")).is_empty() and player.left_support_arm.is_visible_in_tree() and player.right_relaxed_arm.is_visible_in_tree(), "trial must really unequip carried weapons and expose both actual free hands: iteration %d weapon=%s offhand=%s left=%s right=%s support_root=%s stowed=%s torch=%s role=%s" % [iteration, bag.equipment.get("weapon", ""), bag.equipment.get("offhand", ""), player.left_support_arm.is_visible_in_tree(), player.right_relaxed_arm.is_visible_in_tree(), player.support_arm_root.visible, player.chest_equipment_stowed, player.torch_enabled, player._left_hand_role()])
		room._teleport(chest.position + Vector3(0.0, 1.0, 1.6))
		var direction := chest.to_global(Vector3(0.0, 0.77, -0.595)) - player.camera.global_position
		player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		player.head.rotation.x = player._pitch
		var bag_before := PREVIEW.inventory_contents(bag)
		chest.interact(player)
		player.advance_timed_interaction(chest.OPEN_DURATION * 0.55)
		_check(player.is_timed_interacting() and player.chest_equipment_stowed and player.chest_hands.phase == "fidget", "trial chest must invoke production timed opening and its actual contact phase")
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side < 0 else player.chest_hands.right_hand
			var contact := chest.get_hand_contact_transform(side, 0.55)
			_check(hand.global_position.distance_to(contact.origin) < 0.015 and player.chest_hands._arms[side].get("detailed_visual").is_visible_in_tree(), "both detailed hands must reach the real chest contact transforms")
		_check(PREVIEW.inventory_contents(bag) == bag_before, "chest hand animation must preserve selected inventory and metadata")
		await _press_f2()
		_check(paused and room.panel_open and not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "F2 must cancel detailed chest contact and return to paused menu")
		var hunger := ExpeditionSession.hunger
		await create_timer(0.03, true).timeout
		_check(is_equal_approx(ExpeditionSession.hunger, hunger), "detailed F2 menu must pause survival")
		_check(sandbox.saved_session == snapshot and PREVIEW.inventory_contents(original) == contents and signals[0] == 0, "repeated trials must never mutate or signal the original inventory")
	room.run_feature("player_arm_motion")
	_check(room.player.hands_visual_profile == "original", "selecting another feature must restore the original profile and clear both preview variants")
	await _press_f2()
	room.run_feature("player_hands_greybox")
	_check(room.player.hands_greybox_enabled and not room.player.hands_detailed_enabled, "the testroom greybox entry must remain independently executable after detailed trials")
	await _press_f2()
	room.run_feature("player_hands_detailed")
	var old_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != old_bag and room.player.hands_visual_profile == "original" and paused and room.panel_open and sandbox.saved_session == snapshot, "reset must restore the original profile and replace only the isolated test inventory")
	room.run_feature("player_hands_detailed")
	_check(room.player.hands_detailed_enabled and is_instance_valid(room.arm_motion_chest), "detailed trial must remain executable after reset")
	await _press_f2()
	room.leave_room()
	await _wait_for_main_menu()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and PREVIEW.inventory_contents(original) == contents, "exit must restore exact original inventory identity, nested metadata and expedition state")
	_check(original.changed.is_connected(observer), "original inventory signal connections must survive detailed trial lifecycle")
	original.changed.emit()
	_check(signals[0] == 1, "restored original inventory must still notify its existing observers")
	original.changed.disconnect(observer)


func _skin_samples(arm: Node3D, material_filter := "", mesh_filter := "") -> PackedVector3Array:
	var samples := PackedVector3Array()
	var skeleton := arm.get("skeleton") as Skeleton3D
	if skeleton == null: return samples
	for mesh in _meshes(arm):
		if mesh.skin == null: continue
		if not mesh_filter.is_empty() and str(mesh.name) != mesh_filter: continue
		var matrices: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
			if bone < 0: return PackedVector3Array()
			matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			if not material_filter.is_empty() and not mesh.get_active_material(surface).resource_name.begins_with(material_filter): continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty() or bones.size() != weights.size(): continue
			var stride := bones.size() / vertices.size()
			for vertex in range(0, vertices.size(), maxi(1, vertices.size() / 256)):
				var point := Vector3.ZERO
				for slot in stride:
					var entry := vertex * stride + slot
					if weights[entry] > 0.0: point += (matrices[bones[entry]] * vertices[vertex]) * weights[entry]
				samples.append(mesh.to_global(point))
	return samples


func _bare_skin_connectivity(arm: Node3D) -> Dictionary:
	# UV seams legitimately duplicate imported vertices. Compare actual distances
	# within one micrometre, including adjacent grid cells: rounding a position
	# alone can split a seam whose two copies straddle a cell boundary.
	const WELD_DISTANCE := 0.000001
	var buckets := {}
	var positions: Array[Vector3] = []
	var parents: Array[int] = []
	var triangle_count := 0
	var welded_pairs := 0
	for part: MeshInstance3D in arm.get("hand_meshes"):
		if str(part.name).begins_with("Nail_"): continue
		var to_arm := arm.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface)
			if material == null or not material.resource_name.begins_with("Detailed_Skin"): continue
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var mapped := PackedInt32Array()
			for vertex: Vector3 in vertices:
				var point := to_arm * vertex
				var cell := Vector3i(floori(point.x / WELD_DISTANCE), floori(point.y / WELD_DISTANCE), floori(point.z / WELD_DISTANCE))
				var point_id := positions.size()
				positions.append(point)
				parents.append(point_id)
				for x in range(-1, 2):
					for y in range(-1, 2):
						for z in range(-1, 2):
							for candidate: int in buckets.get(cell + Vector3i(x, y, z), []):
								if point.distance_squared_to(positions[candidate]) > WELD_DISTANCE * WELD_DISTANCE: continue
								var root_a := _component_root(parents, point_id)
								var root_b := _component_root(parents, candidate)
								parents[maxi(root_a, root_b)] = mini(root_a, root_b)
								welded_pairs += 1
				if not buckets.has(cell): buckets[cell] = []
				buckets[cell].append(point_id)
				mapped.append(point_id)
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for triangle in range(0, count, 3):
				triangle_count += 1
				var a := mapped[indices[triangle] if not indices.is_empty() else triangle]
				for offset in [1, 2]:
					var b := mapped[indices[triangle + offset] if not indices.is_empty() else triangle + offset]
					var root_a := _component_root(parents, a)
					var root_b := _component_root(parents, b)
					parents[maxi(root_a, root_b)] = mini(root_a, root_b)
	var components := {}
	for vertex in parents.size(): components[_component_root(parents, vertex)] = true
	return {"component_count": components.size(), "source_vertex_count": positions.size(), "triangle_count": triangle_count, "coincident_pairs": welded_pairs, "weld_distance_m": WELD_DISTANCE}


func _component_root(parents: Array[int], vertex: int) -> int:
	var result := vertex
	while parents[result] != result:
		parents[result] = parents[parents[result]]
		result = parents[result]
	return result


func _geometry_fingerprint(node: Node) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for part in _meshes(node):
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			hash.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
			hash.update((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	return hash.finish().hex_encode()


func _audit_wrist_cuff(arm: Node3D, context: String) -> void:
	failures.append_array(_wrist_auditor.inspect(arm, context))


class WristGeometryAudit extends RefCounted:
	var failures: Array[String] = []
	var _wrist_sources: Dictionary = {}

	func inspect(arm: Node3D, context: String) -> Array[String]:
		failures.clear()
		_audit_wrist_cuff(arm, context)
		return failures.duplicate()

	func _audit_wrist_cuff(arm: Node3D, context: String) -> void:
		_check(arm != null and arm.has_method("get_wrist_snapshot"), "the actual detailed arm must expose its flexible cuff: " + context)
		if arm == null or not arm.has_method("get_wrist_snapshot"): return
		var report: Dictionary = arm.call("get_wrist_snapshot")
		_check(bool(report.get("enabled", false)), "the authored detailed cuff must enable its real geometry transition: " + context)
		if not bool(report.get("enabled", false)): return
		var source := _wrist_source(arm)
		if source.is_empty(): return
		var join_report := PREVIEW.inspect_skin_cuff_join(arm)
		_check(bool(join_report.passed), "actual posed skin and cuff outer surface must remain joined: " + context + " " + JSON.stringify(join_report))
		if OS.get_environment("PLAYER_WRIST_QA_DIAGNOSTIC") == "1":
			print("SKIN CUFF JOIN DIAGNOSTIC: " + JSON.stringify({"context": context, "join": join_report}))
		var forearm := arm.find_child("Forearm*", true, false) as Node3D
		var adapter_inverse := arm.global_transform.affine_inverse()
		# Derive the endpoint target from the actual rendered forearm, independently
		# of the deformer snapshot's reported fit or computed vertex buffers.
		var forearm_fit := adapter_inverse * forearm.global_transform * (source.forearm_rest as Transform3D).affine_inverse()
		var skeleton := arm.get("skeleton") as Skeleton3D
		var wrist_point := adapter_inverse * skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("wrist")).origin
		_check((forearm_fit * wrist_point).distance_to(wrist_point) < 0.00005, "the fitted forearm must pivot at the actual source wrist bone while preserving its hand contact: " + context)
		var fit_rotation := forearm_fit.basis.orthonormalized().get_rotation_quaternion().normalized()
		if fit_rotation.w < 0.0: fit_rotation = -fit_rotation
		var fit_axis := fit_rotation.get_axis()
		var bend_direction := Vector3(-fit_axis.y, fit_axis.x, 0.0).normalized()
		if bend_direction.length_squared() < 0.5: bend_direction = Vector3.RIGHT
		var start := float(report.blend_start_z)
		var end := float(report.blend_end_z)
		var fixed_count := 0
		var following_count := 0
		var section_pairs := 0
		var endpoint_error := 0.0
		var section_error := 0.0
		var minimum_inner_scale := 1.0
		var invalid_compressions := 0
		var rest_error := 0.0
		var invalid_normals := 0
		var collapsed_triangles := 0
		var reversed_surfaces := 0
		var reversed_samples: Array[Dictionary] = []
		var minimum_area_ratio := INF
		_check(is_finite(start) and is_finite(end) and end > start, "the actual cuff needs a finite transition band: " + context)
		for mesh_name: String in source.meshes:
			var original: Dictionary = source.meshes[mesh_name]
			var mesh := arm.find_child(mesh_name, true, false) as MeshInstance3D
			_check(mesh != null and mesh.mesh != original.mesh and mesh.skin == null, "flexible cuff vertices must belong to an instance copy without altering the sixteen-bone hand: " + context)
			if mesh == null: continue
			var to_adapter := adapter_inverse * mesh.global_transform
			for surface in (original.surfaces as Array).size():
				var saved: Dictionary = original.surfaces[surface]
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var rest_vertices: PackedVector3Array = saved.vertices
				var rest_normals: PackedVector3Array = saved.normals
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				_check(vertices.size() == rest_vertices.size() and normals.size() == vertices.size(), "the transition must retain its authored surface topology and real normals: " + context)
				if vertices.size() != rest_vertices.size() or normals.size() != vertices.size(): continue
				var sections := {}
				for vertex in vertices.size():
					var rest: Vector3 = (original.to_adapter as Transform3D) * rest_vertices[vertex]
					var current := to_adapter * vertices[vertex]
					rest_error = maxf(rest_error, current.distance_to(rest))
					if not current.is_finite() or not normals[vertex].is_finite() or absf(normals[vertex].length() - 1.0) > 0.03: invalid_normals += 1
					if rest.z <= start:
						fixed_count += 1
						endpoint_error = maxf(endpoint_error, current.distance_to(rest))
					elif rest.z >= end:
						following_count += 1
						endpoint_error = maxf(endpoint_error, current.distance_to(forearm_fit * rest))
					else:
						# Recover each section from its actual outside geometry. This
						# avoids reproducing the runtime rotation/pressure formula.
						var key := roundi(rest.z * 1000000.0)
						if not sections.has(key): sections[key] = []
						sections[key].append({"rest": rest, "current": current})
				for section: Array in sections.values():
					var section_report := _inspect_elastic_section(section, bend_direction, wrist_point)
					section_pairs += int(section_report.samples)
					section_error = maxf(section_error, float(section_report.error))
					minimum_inner_scale = minf(minimum_inner_scale, float(section_report.minimum_inner_scale))
					invalid_compressions += int(section_report.invalid)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var triangle_vertices := indices.size() if not indices.is_empty() else vertices.size()
				for triangle in range(0, triangle_vertices, 3):
					var a := int(indices[triangle]) if not indices.is_empty() else triangle
					var b := int(indices[triangle + 1]) if not indices.is_empty() else triangle + 1
					var c := int(indices[triangle + 2]) if not indices.is_empty() else triangle + 2
					var rest_cross := (rest_vertices[b] - rest_vertices[a]).cross(rest_vertices[c] - rest_vertices[a])
					var rest_area := rest_cross.length()
					if rest_area < 0.000000000001: continue
					var current_cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
					var area := current_cross.length()
					minimum_area_ratio = minf(minimum_area_ratio, area / rest_area)
					if not is_finite(area) or area / rest_area < 0.01: collapsed_triangles += 1
					var original_alignment := rest_cross.normalized().dot((rest_normals[a] + rest_normals[b] + rest_normals[c]).normalized())
					if absf(original_alignment) > 0.4:
						var current_alignment := current_cross.normalized().dot((normals[a] + normals[b] + normals[c]).normalized())
						if original_alignment * current_alignment <= 0.0:
							reversed_surfaces += 1
							if reversed_samples.size() < 3:
								reversed_samples.append({"mesh": mesh_name, "surface": surface, "triangle": triangle / 3, "rest_vertices": _vectors([rest_vertices[a], rest_vertices[b], rest_vertices[c]]), "current_vertices": _vectors([vertices[a], vertices[b], vertices[c]]), "rest_normals": _vectors([rest_normals[a], rest_normals[b], rest_normals[c]]), "current_normals": _vectors([normals[a], normals[b], normals[c]]), "mesh_to_adapter_origin": _vectors([(original.to_adapter as Transform3D).origin]), "mesh_to_adapter_basis": _vectors([(original.to_adapter as Transform3D).basis.x, (original.to_adapter as Transform3D).basis.y, (original.to_adapter as Transform3D).basis.z]), "rest_alignment": original_alignment, "current_alignment": current_alignment})
				var imported_arrays: Array = (original.mesh as Mesh).surface_get_arrays(surface)
				_check(imported_arrays[Mesh.ARRAY_VERTEX] == saved.vertices and imported_arrays[Mesh.ARRAY_NORMAL] == saved.normals and imported_arrays[Mesh.ARRAY_INDEX] == saved.indices, "posing must never mutate the imported cuff resource or original surface data: " + context)
		_check(fixed_count >= 16 and following_count >= 16 and section_pairs >= 16, "the real cuff must contain fixed, transitional and forearm-following geometry: " + context)
		_check(endpoint_error < 0.00005, "actual cuff endpoints must remain seated in the hand and fitted forearm: " + context + " max_error=" + str(endpoint_error))
		_check(section_error < 0.00005 and invalid_compressions == 0 and minimum_inner_scale >= 0.45, "elastic fitting must preserve the outside and perpendicular width while compressing the inside monotonically within its allowed depth: " + context + " max_error=" + str(section_error) + " invalid=" + str(invalid_compressions) + " min_inner_scale=" + str(minimum_inner_scale))
		if forearm_fit.is_equal_approx(Transform3D.IDENTITY):
			_check(rest_error < 0.00005, "identity fitting and reset must restore every actual cuff vertex: " + context + " max_error=" + str(rest_error))
		if OS.get_environment("PLAYER_WRIST_QA_DIAGNOSTIC") == "1" and (reversed_surfaces > 0 or context.contains("wrist_side")):
			var rotation := forearm_fit.basis.orthonormalized().get_rotation_quaternion()
			print("WRIST FIT DIAGNOSTIC: " + JSON.stringify({"context": context, "side": (arm.call("get_snapshot") as Dictionary).side, "fit_origin": _vectors([forearm_fit.origin]), "fit_basis": _vectors([forearm_fit.basis.x, forearm_fit.basis.y, forearm_fit.basis.z]), "quaternion_xyzw": [rotation.x, rotation.y, rotation.z, rotation.w], "rotation_degrees": rad_to_deg(rotation.get_angle()), "minimum_jacobian": report.minimum_jacobian_determinant, "invalid_vertices": report.invalid_vertex_count, "reversed_surfaces": reversed_surfaces, "reversed_samples": reversed_samples}))
		_check(invalid_normals == 0 and collapsed_triangles == 0 and reversed_surfaces == 0 and float(report.minimum_jacobian_determinant) > 0.0 and int(report.invalid_vertex_count) == 0, "fitted cuff surfaces must retain finite normals and avoid collapse or foldover: " + context + " invalid_normals=" + str(invalid_normals) + " reversed=" + str(reversed_surfaces) + " min_area_ratio=" + str(minimum_area_ratio) + " min_jacobian=" + str(report.minimum_jacobian_determinant) + " invalid_vertices=" + str(report.invalid_vertex_count) + " side=" + str((arm.call("get_snapshot") as Dictionary).side) + " bend_degrees=" + str(rad_to_deg(acos(clampf(forearm_fit.basis.z.normalized().dot(Vector3.BACK), -1.0, 1.0)))) + " axial_scale=" + str(forearm_fit.basis.z.length()))


	func _inspect_elastic_section(points: Array, bend: Vector3, wrist: Vector3) -> Dictionary:
		var result := {"samples": 0, "error": 0.0, "minimum_inner_scale": 1.0, "invalid": 0}
		var outside: Array = points.filter(func(point: Dictionary) -> bool: return (point.rest as Vector3).dot(bend) >= wrist.dot(bend))
		if outside.size() < 3:
			result.invalid = 1
			return result
		var a: Dictionary = outside[0]
		var b := a
		var maximum_distance := 0.0
		for candidate: Dictionary in outside:
			var distance := (candidate.rest as Vector3).distance_squared_to(a.rest)
			if distance > maximum_distance:
				maximum_distance = distance
				b = candidate
		var c := a
		var maximum_area := 0.0
		for candidate: Dictionary in outside:
			var area := ((b.rest as Vector3) - (a.rest as Vector3)).cross((candidate.rest as Vector3) - (a.rest as Vector3)).length_squared()
			if area > maximum_area:
				maximum_area = area
				c = candidate
		if maximum_area < 0.0000000001:
			result.invalid = 1
			return result
		var rest_x := ((b.rest as Vector3) - (a.rest as Vector3)).normalized()
		var rest_z := rest_x.cross((c.rest as Vector3) - (a.rest as Vector3)).normalized()
		var current_x := ((b.current as Vector3) - (a.current as Vector3)).normalized()
		var current_z := current_x.cross((c.current as Vector3) - (a.current as Vector3)).normalized()
		var rotation := Basis(current_x, current_z.cross(current_x), current_z) * Basis(rest_x, rest_z.cross(rest_x), rest_z).transposed()
		var translation: Vector3 = (a.current as Vector3) - rotation * (a.rest as Vector3)
		var inside: Array[Vector2] = []
		for point: Dictionary in points:
			var rest: Vector3 = point.rest
			var recovered: Vector3 = rotation.transposed() * ((point.current as Vector3) - translation)
			var delta := recovered - rest
			var before := (rest - wrist).dot(bend)
			var after := (recovered - wrist).dot(bend)
			result.samples += 1
			result.error = maxf(float(result.error), (delta - bend * delta.dot(bend)).length())
			if before >= 0.0:
				result.error = maxf(float(result.error), delta.length())
			elif before < -0.0001:
				inside.append(Vector2(before, after))
				result.minimum_inner_scale = minf(float(result.minimum_inner_scale), after / before)
				if after < before - 0.00005 or after > 0.00005: result.invalid += 1
		inside.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
		for index in range(1, inside.size()):
			if inside[index].y < inside[index - 1].y - 0.00005: result.invalid += 1
		return result


	func _wrist_source(arm: Node3D) -> Dictionary:
		var path := str((arm.call("get_snapshot") as Dictionary).source_model)
		if _wrist_sources.has(path): return _wrist_sources[path]
		var model := (load(path) as PackedScene).instantiate()
		var cuff := model.find_child("WristCuff*", true, false) as Node3D
		var forearm := model.find_child("Forearm*", true, false) as Node3D
		_check(cuff != null and forearm != null, "the imported detailed source needs the actual cuff and forearm")
		if cuff == null or forearm == null:
			model.free()
			return {}
		var result := {"forearm_rest": _source_transform(forearm), "meshes": {}}
		for mesh: MeshInstance3D in _meshes(cuff):
			var surfaces := []
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				surfaces.append({"vertices": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(), "normals": (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate(), "indices": arrays[Mesh.ARRAY_INDEX]})
			result.meshes[str(mesh.name)] = {"mesh": mesh.mesh, "to_adapter": _source_transform(mesh), "surfaces": surfaces}
		model.free()
		_wrist_sources[path] = result
		return result


	func _source_transform(node: Node3D) -> Transform3D:
		var result := node.transform
		var ancestor := node.get_parent()
		while ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
			ancestor = ancestor.get_parent()
		return result

	func _vectors(values: Array) -> Array:
		var result := []
		for value: Vector3 in values: result.append([value.x, value.y, value.z])
		return result

	func _meshes(node: Node) -> Array[MeshInstance3D]:
		var result: Array[MeshInstance3D] = []
		if node is MeshInstance3D: result.append(node)
		for child in node.get_children(): result.append_array(_meshes(child))
		return result

	func _check(condition: bool, message: String) -> void:
		if not condition: failures.append(message)


func _weighted_bone_names(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Array[String]:
	var result: Array[String] = []
	if mesh.skin == null: return result
	var names: Array[String] = []
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
		names.append(skeleton.get_bone_name(bone) if bone >= 0 else "missing")
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for entry in weights.size():
			if weights[entry] > 0.00001 and not result.has(names[bones[entry]]): result.append(names[bones[entry]])
	result.sort()
	return result


func _max_displacement(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty(): return INF
	var maximum := 0.0
	for index in a.size(): maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum


func _bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result


func _transforms(parts: Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for part: Node3D in parts: result.append(part.global_transform)
	return result


func _legacy_state(wrappers: Array) -> Array:
	var result := []
	for wrapper: Node3D in wrappers:
		for mesh: MeshInstance3D in wrapper.get("arm_meshes") + wrapper.get("hand_meshes"):
			var materials: Array[Material] = []
			for surface in mesh.mesh.get_surface_count(): materials.append(mesh.get_active_material(surface))
			result.append([mesh, mesh.mesh, materials, mesh.visible])
	return result


func _gameplay_anchors(player: DungeonPlayer) -> Array[Transform3D]:
	return [player.sword_blade.global_transform, player.staff_muzzle.global_transform, player.weapon_pivot.global_transform, player.shield_pivot.global_transform, player.torch_pivot.global_transform]


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_for_main_menu() -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://main_menu.tscn" and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "detailed lifecycle timed out returning to main menu")


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
