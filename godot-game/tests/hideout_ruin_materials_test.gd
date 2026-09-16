extends SceneTree

const MATERIALS := preload("res://scripts/hideout_ruin_materials.gd")
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const VIEWS := preload("res://scripts/hideout_ruin_views.gd")
const KIT_NAMES := ["broken_masonry_edge", "collapsed_arch", "rubble_pile", "snapped_timber", "hanging_roots", "moss_clump", "ceiling_spall"]
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_inventory := ExpeditionSession.get_inventory()
	var original_session := ExpeditionSession.capture_snapshot()
	var original_mouse := Input.mouse_mode
	_test_source_preservation()
	_test_material_channels()
	_test_concept_images()
	_test_blender_exports()
	_check(ExpeditionSession.get_inventory() == original_inventory and ExpeditionSession.capture_snapshot() == original_session and Input.mouse_mode == original_mouse, "material and geometry inspection cannot alter journey, inventory identity, or cursor")
	# Shared NoiseTexture resources finish their normal-map workers before exit.
	for frame in 16:
		await process_frame
	if failures.is_empty():
		print("HIDEOUT RUIN MATERIALS TEST PASS: immutable source materials, shared pitted detail, weather/stain/water shaders, eight separate concepts and seven static Blender meshes")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT RUIN MATERIALS TEST FAIL: " + failure)
		quit(1)


func _test_source_preservation() -> void:
	var source := SURFACES.stone(Color(0.34, 0.39, 0.36), 1.7)
	var original_pass := StandardMaterial3D.new()
	source.next_pass = original_pass
	var before := _material_snapshot(source)
	var stone := MATERIALS.weathered(source, "stone")
	_check(stone != source and MATERIALS.weathered(source, "stone") == stone, "weathering duplicates once and reuses exactly the same cached material")
	_check(_material_snapshot(source) == before, "weathering must leave every stored source property and texture reference unchanged")
	_check(stone.albedo_texture == source.albedo_texture and stone.normal_texture == source.normal_texture and stone.roughness_texture == source.roughness_texture, "weathering retains the actual authored albedo, normal and roughness map resources")
	_check(stone.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and stone is StandardMaterial3D, "weathered base remains an opaque StandardMaterial3D for production stone batching")
	_check(stone.next_pass is ShaderMaterial and (stone.next_pass as ShaderMaterial).shader == MATERIALS.WEATHER_SHADER and stone.next_pass.next_pass == original_pass, "the weather shader is a next pass and retains an existing source pass without mutating it")
	var finish := stone.next_pass as ShaderMaterial
	_check(finish.get_shader_parameter("ruin_scan") == MATERIALS.DAMP_SCAN and MATERIALS.DAMP_SCAN.get_width() >= 1000, "the generated fracture/moss scan is bound to the actual production stone finish")
	_check(finish.get_shader_parameter("source_albedo") == stone.albedo_texture and finish.get_shader_parameter("source_normal") == stone.normal_texture and finish.get_shader_parameter("source_roughness") == stone.roughness_texture and finish.get_shader_parameter("source_detail_normal") == stone.detail_normal, "the opaque finishing pass actually receives every preserved base and detail surface map")
	_check(finish.get_shader_parameter("source_uv_scale") == stone.uv1_scale and finish.get_shader_parameter("source_uv_offset") == stone.uv1_offset and finish.get_shader_parameter("base_color") == stone.albedo_color, "the opaque finish samples the actual cloned texture coordinates and tint")
	_check(stone.detail_enabled and stone.detail_normal is NoiseTexture2D and (stone.detail_normal as NoiseTexture2D).as_normal_map and stone.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MUL, "pitted detail is an actual shared normal map and cannot replace the base albedo")
	_check(stone.normal_scale >= source.normal_scale and stone.uv1_world_triplanar, "coarse weathering strengthens original normal response and prevents repeated local stone patterns")
	_check(MATERIALS.weathered(stone, "stone") == stone, "a repeated hierarchy pass cannot stack the same weather effect again")
	var floor := MATERIALS.weathered(source, "floor")
	_check(floor != stone and floor.uv1_scale == source.uv1_scale and floor.detail_normal == stone.detail_normal, "floor has its own cache entry, preserves floor scale, and shares the pitted normal map")
	_check(_material_snapshot(source) == before, "requesting multiple material kinds still cannot modify the global source")
	var oak_source := SURFACES.old_oak()
	var oak_pass := StandardMaterial3D.new()
	oak_source.next_pass = oak_pass
	var oak_before := _material_snapshot(oak_source)
	var oak := MATERIALS.weathered(oak_source, "wood")
	_check(oak != oak_source and oak == MATERIALS.weathered(oak_source, "wood") and oak.next_pass == oak_pass, "curved wooden props retain the original StandardMaterial3D rendering path and existing pass chain")
	_check(_material_snapshot(oak_source) == oak_before and oak.albedo_color == oak_source.albedo_color and oak.albedo_texture == oak_source.albedo_texture and oak.normal_texture == oak_source.normal_texture and oak.normal_scale == oak_source.normal_scale and oak.uv1_scale == oak_source.uv1_scale and oak.cull_mode == oak_source.cull_mode, "wood keeps its authored texture, tint, normals, UV and culling so curved barrel staves cannot be blackened by masonry shading")
	_check(oak.detail_enabled and oak.detail_albedo is NoiseTexture2D and oak.detail_normal == oak_source.detail_normal and oak.detail_blend_mode == BaseMaterial3D.BLEND_MODE_MUL, "wood corrosion only multiplies a real detail color map while retaining the standard normal path")
	var other_oak := MATERIALS.weathered(SURFACES.old_oak(Color(0.5, 0.4, 0.3)), "wood")
	_check(oak.detail_albedo == other_oak.detail_albedo, "different original oak tints share one bounded patina texture")
	var patina := oak.detail_albedo as NoiseTexture2D
	_check(patina != null and not patina.as_normal_map and patina.seamless and patina.generate_mipmaps and patina.noise != null and patina.color_ramp != null, "wood patina is seamless color detail with real multiscale noise and mipmaps")
	if patina != null and patina.color_ramp != null:
		var darkest := patina.color_ramp.sample(0.0)
		var clear := patina.color_ramp.sample(1.0)
		_check(darkest.r >= 0.58 and darkest.g >= 0.58 and darkest.b >= 0.58 and darkest.a == 1.0 and clear == Color.WHITE and clear.get_luminance() - darkest.get_luminance() > 0.2, "patina has visible irregular variation without any black or transparent multiplication values")
	var authored_detail := SURFACES.stone()
	authored_detail.detail_enabled = true
	authored_detail.detail_albedo = SURFACES.OAK
	authored_detail.detail_normal = SURFACES.IRON
	authored_detail.detail_blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var detailed := MATERIALS.weathered(authored_detail, "stone")
	_check(detailed.detail_albedo == authored_detail.detail_albedo and detailed.detail_normal == authored_detail.detail_normal and detailed.detail_blend_mode == authored_detail.detail_blend_mode, "existing artist-authored detail channels and blend operation remain authoritative")
	var detailed_wood := MATERIALS.weathered(authored_detail, "wood")
	_check(detailed_wood.detail_albedo == authored_detail.detail_albedo and detailed_wood.detail_normal == authored_detail.detail_normal and detailed_wood.detail_blend_mode == authored_detail.detail_blend_mode, "wood patina cannot replace enabled artist-authored detail channels or their blend operation")
	var reserved_wood := SURFACES.old_oak()
	reserved_wood.detail_mask = SURFACES.OAK
	var reserved_result := MATERIALS.weathered(reserved_wood, "wood")
	_check(not reserved_result.detail_enabled and reserved_result.detail_mask == reserved_wood.detail_mask and reserved_result.detail_albedo == null, "a reserved artist-authored detail mask is preserved even when its detail layer is disabled")
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	instance.material_override = stone
	_check(instance.material_overlay == null, "the production material needs no material_overlay that would break stone batching")
	instance.free()


func _test_material_channels() -> void:
	for slot in ["ruin_stone", "ruin_timber", "ruin_moss", "ruin_root", "ruin_mortar"]:
		var material := MATERIALS.ruin_material(slot)
		_check(material == MATERIALS.ruin_material(slot), "Blender material slots share cached resources: " + slot)
		_check(material.vertex_color_use_as_albedo and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null, "Blender kit retains vertex tints and actual existing albedo/normal maps: " + slot)
		_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.get_meta("hideout_ruin_slot", "") == slot, "Blender slot remains opaque and identifiable: " + slot)
		if material.next_pass is ShaderMaterial:
			_check(bool((material.next_pass as ShaderMaterial).get_shader_parameter("uses_vertex_color")), "the opaque kit finish preserves Blender COLOR_0 tint: " + slot)
	for kind in ["moss", "mold", "leak", "soot", "salt"]:
		var stain := MATERIALS.stain_material(kind)
		_check(stain == MATERIALS.stain_material(kind) and stain.shader == MATERIALS.STAIN_SHADER, "wall stains use a cached real shader: " + kind)
		_check(float(stain.get_shader_parameter("opacity")) > 0.0 and float(stain.get_shader_parameter("opacity")) < 1.0, "wall stains blend with actual wall surfaces: " + kind)
	var water := MATERIALS.water_material()
	var ripple := MATERIALS.ripple_material()
	_check(water == MATERIALS.water_material() and ripple == MATERIALS.ripple_material() and water != ripple, "ponds and impacts cache distinct materials")
	_check(water.shader == MATERIALS.WATER_SHADER and ripple.shader == MATERIALS.WATER_SHADER and not bool(water.get_shader_parameter("ripple_only")) and bool(ripple.get_shader_parameter("ripple_only")), "ambient water and actual impact planes select separate modes of the real water shader")


func _test_concept_images() -> void:
	var hashes: Array[String] = []
	_check(VIEWS.ordered_ids().size() == 8, "the canonical hideout catalog defines eight rooms")
	for room_id in VIEWS.ordered_ids():
		var path := "res://assets/ai/hideout_ruins/concept_%s.png" % room_id
		_check(FileAccess.file_exists(path) and ResourceLoader.exists(path, "Texture2D"), "each canonical room has its own generated target PNG: " + room_id)
		if not FileAccess.file_exists(path):
			continue
		var texture := load(path) as Texture2D
		_check(texture != null and texture.get_width() >= 1000 and texture.get_height() >= 700, "room target image is a full-resolution reference: " + room_id)
		var digest := FileAccess.get_sha256(path)
		_check(digest.length() == 64 and digest not in hashes, "each room reference is its own distinct image rather than the same image reused: " + room_id)
		hashes.append(digest)


func _test_blender_exports() -> void:
	var total_triangles := 0
	for asset_name in KIT_NAMES:
		var path := "res://assets/3d/hideout_ruins/%s.glb" % asset_name
		var scene := load(path) as PackedScene
		_check(scene != null, "the Blender export is a loadable game scene: " + asset_name)
		if scene == null:
			continue
		var model := scene.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect_static_meshes(model, meshes)
		_check(meshes.size() == 1, "kit asset stays one joined static mesh: " + asset_name)
		for instance in meshes:
			_check(instance.mesh != null and instance.mesh.get_surface_count() <= 2, "kit asset has a compact material/draw-call budget: " + asset_name)
			if instance.mesh == null:
				continue
			total_triangles += int(instance.mesh.get_faces().size() / 3.0)
			var bounds := instance.transform * instance.mesh.get_aabb()
			_check(bounds.size.length() > 0.3 and bounds.size.length() < 7.0, "kit export scale is meters suitable for the actual hideout: " + asset_name)
			if asset_name in ["hanging_roots", "ceiling_spall"]:
				_check(bounds.position.y < -0.4 and bounds.end.y < 0.15, "top-anchored ceiling accents hang downward in Godot Y-up coordinates: " + asset_name)
			else:
				_check(bounds.position.y > -0.20 and bounds.end.y > 0.1, "floor accents remain grounded with only small contact overlap: " + asset_name)
		model.free()
	_check(total_triangles > 5000 and total_triangles < 18000, "the full seven-mesh Blender kit remains within the authored triangle budget")


func _collect_static_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	_check(not node is Camera3D and not node is Light3D and not node is CollisionObject3D and not node is CollisionShape3D and node.get_script() == null, "decorative Blender exports cannot add actors, lights, cameras, collisions or scripts")
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_static_meshes(child, meshes)


func _material_snapshot(material: StandardMaterial3D) -> Dictionary:
	var result := {}
	for property in material.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE:
			result[str(property.name)] = material.get(str(property.name))
	return result.duplicate(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
