extends SceneTree
## Check actual exported PBR roles and face-corner colors, not only a manifest.
const GEOMETRY := preload("res://scripts/cave_geometry.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var cave := GEOMETRY.new()
	root.add_child(cave)
	cave.build()
	var ground: BaseMaterial3D
	var rock: BaseMaterial3D
	var active_ground: ShaderMaterial
	var active_rock: ShaderMaterial
	var active_ground_surfaces := 0
	var active_rock_surfaces := 0
	var audited_textures: Dictionary = {}
	var earth_samples := 0
	var mineral_samples := 0
	var earth_mean := Vector3.ZERO
	var mineral_mean := Vector3.ZERO
	var earth_low := 10.0
	var earth_high := 0.0
	for visual: MeshInstance3D in cave.blender_mine.find_children("Terrain_*", "MeshInstance3D", true, false):
		for surface in visual.mesh.get_surface_count():
			# Preserve validation of the photographed Blender source even when
			# production art direction overrides the active rendering material.
			var material := visual.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null or not material.resource_name.begins_with("Mine_Continuous_"):
				continue
			var soil := material.resource_name == "Mine_Continuous_Ground"
			var active := visual.get_active_material(surface) as ShaderMaterial
			_check(active != null, "the actual rendered soil and stone surfaces must use the production art direction shader")
			if active != null:
				_check(bool(active.get_shader_parameter("ground_surface")) == soil, "the active shader must preserve the imported face's soil or stone role")
				if soil:
					active_ground = active
					active_ground_surfaces += 1
				else:
					active_rock = active
					active_rock_surfaces += 1
			if soil:
				ground = material
			elif material.resource_name == "Mine_Continuous_Mine_Limestone":
				rock = material
			var arrays := visual.mesh.surface_get_arrays(surface)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			_check(not colors.is_empty(), "real imported terrain must carry mineral/soil corner colors")
			for index in range(0, colors.size(), 23):
				var c := colors[index]
				if soil:
					earth_mean += Vector3(c.r, c.g, c.b)
					earth_low = minf(earth_low, c.r)
					earth_high = maxf(earth_high, c.r)
					earth_samples += 1
				else:
					mineral_mean += Vector3(c.r, c.g, c.b)
					mineral_samples += 1
	_check(ground != null and rock != null, "both fine earth and bedrock materials must be imported")
	if ground and rock:
		_check(ground.albedo_texture != null and rock.albedo_texture != null and ground.albedo_texture != rock.albedo_texture, "soil and stone must use different actual photographic color maps")
		_check(ground.normal_texture != null and rock.normal_texture != null and ground.normal_texture != rock.normal_texture, "soil and stone must use different actual detail normal maps")
		_check(ground.vertex_color_use_as_albedo and rock.vertex_color_use_as_albedo, "both imported materials must retain their actual spatial tint")
		_check(ground.roughness > rock.roughness + 0.1, "fine soil must be more matte than mineral rock")
		_check(ground.normal_scale < rock.normal_scale * 0.6, "soil grain must have subtler relief than fractured rock")
	_check(active_ground_surfaces > 10 and active_rock_surfaces > 10, "the art direction must apply across actual ground and walls rather than one showcase object")
	if active_ground != null and active_rock != null:
		for role in [active_ground, active_rock]:
			for map_name in ["albedo_map", "normal_map", "roughness_map", "height_map", "fracture_albedo", "fracture_normal"]:
				var texture := role.get_shader_parameter(map_name) as Texture2D
				_check(texture != null and texture.get_width() >= 128 and texture.get_height() >= 128, "the active photographed material must bind a usable " + map_name)
			# Inspect every texture actually bound to the production shader,
			# including secondary fracture maps. A mipmap import flag alone
			# does not prove the imported resource contains the mip chain.
			for uniform: Dictionary in role.shader.get_shader_uniform_list():
				var value: Variant = role.get_shader_parameter(str(uniform.name))
				if not value is Texture2D:
					continue
				var texture := value as Texture2D
				if audited_textures.has(texture.get_instance_id()):
					continue
				audited_textures[texture.get_instance_id()] = true
				var image := texture.get_image()
				_check(image != null and not image.is_empty() and image.has_mipmaps(), "the actual imported shader texture must contain mip levels to avoid distant sparkling: " + texture.resource_path)
		_check(active_ground.get_shader_parameter("albedo_map") != active_rock.get_shader_parameter("albedo_map"), "actual visible soil and stone must retain distinct photographic color inputs")
		_check(active_ground.get_shader_parameter("normal_map") != active_rock.get_shader_parameter("normal_map"), "actual visible soil and stone must retain distinct relief inputs")
		_check(float(active_ground.get_shader_parameter("normal_strength")) < float(active_rock.get_shader_parameter("normal_strength")), "active fine-grained soil must have subtler relief than fractured rock")
		_check(float(active_ground.get_shader_parameter("dry_roughness")) > float(active_rock.get_shader_parameter("dry_roughness")), "active dry earth must remain more matte than mineral stone")
		_check(float(active_ground.get_shader_parameter("metric_scale")) > 0.0 and float(active_rock.get_shader_parameter("metric_scale")) > 0.0, "active mapping must retain a finite positive metre-based texture scale")
		var soil_tint: Color = active_ground.get_shader_parameter("base_tint")
		var rock_tint: Color = active_rock.get_shader_parameter("base_tint")
		_check(soil_tint.r > soil_tint.b and soil_tint != rock_tint, "active earth must remain distinguishable from the cool mineral tint")
	_check(earth_samples > 100 and mineral_samples > 100, "test must sample actual ground and wall geometry")
	if earth_samples > 0 and mineral_samples > 0:
		earth_mean /= earth_samples
		mineral_mean /= mineral_samples
		_check(earth_mean.x > earth_mean.z * 1.4, "earth colors must stay umber rather than inherit the shared rock tint")
		_check(mineral_mean.z > mineral_mean.x * 1.05, "wall colors must retain cooler mineral character under warm lamps")
		_check(earth_high - earth_low > 0.06, "actual soil colors must include broad damp/dry patches, not a uniform multiplier")
	var info := cave.get_build_info().get("continuous_geology", {}) as Dictionary
	_check(float(info.get("ground_tile_m", 0)) > 0 and float(info.get("ground_tile_m", 0)) < float(info.get("rock_tile_m", 0)) * 0.65, "grain scale must distinguish fine soil from rock fractures")
	cave.queue_free()
	await process_frame
	if failures.is_empty():
		print("CAVE GEOLOGY MATERIAL TEST PASS: preserved photographed Blender sources plus actual active soil/rock shader maps, relief, roughness and distinct tint (%d earth, %d rock color samples; %d soil, %d rock active surfaces; %d unique imported texture mip chains)" % [earth_samples, mineral_samples, active_ground_surfaces, active_rock_surfaces, audited_textures.size()])
		quit(0)
	else:
		for failure in failures:
			push_error("CAVE GEOLOGY MATERIAL TEST FAIL: " + failure)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
