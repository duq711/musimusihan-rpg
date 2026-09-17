extends RefCounted
class_name HideoutRuinMaterials

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const WEATHER_SHADER: Shader = preload("res://shaders/hideout_ruin_weather.gdshader")
const STAIN_SHADER: Shader = preload("res://shaders/hideout_ruin_stain.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/hideout_ruin_water.gdshader")
const DAMP_SCAN: Texture2D = preload("res://assets/ai/hideout_ruins/surface_damp_limestone.png")

static var _weather_cache: Dictionary = {}
static var _ruin_cache: Dictionary = {}
static var _stain_cache: Dictionary = {}
static var _water: ShaderMaterial
static var _ripple: ShaderMaterial
static var _fracture_normal: NoiseTexture2D
static var _wood_patina_albedo: NoiseTexture2D


static func weathered(source: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	# The existing shared dungeon materials and their maps stay immutable.
	# An opaque StandardMaterial3D base also remains eligible for stone batching.
	if source == null:
		source = StandardMaterial3D.new()
	if source.get_meta("hideout_ruin_kind", "") == kind:
		return source
	var key := "%d:%s" % [source.get_instance_id(), kind]
	if _weather_cache.has(key):
		return _weather_cache[key] as StandardMaterial3D
	var result := source.duplicate() as StandardMaterial3D
	result.resource_name = "HideoutWeathered_%s" % kind
	result.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	if kind in ["stone", "floor"]:
		# Continuous world sampling avoids the same local blotch repeating on
		# every identical masonry block. Larger chips survive the room camera.
		result.uv1_world_triplanar = result.uv1_triplanar
		if kind == "stone":
			result.uv1_scale = source.uv1_scale * 0.55
		result.normal_scale = maxf(source.normal_scale, 0.92 if kind == "stone" else 0.76)
		if not result.detail_enabled and result.detail_normal == null and result.detail_albedo == null:
			result.detail_enabled = true
			result.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			result.detail_normal = _pitted_detail_normal()
	result.set_meta("hideout_ruin_kind", kind)
	result.set_meta("hideout_ruin_source", source)
	if kind == "wood":
		# Curved barrel staves rely on StandardMaterial3D's original local
		# triplanar/culling path. Keep that authored oak response intact instead
		# of replacing it with the masonry finish's world-normal reconstruction.
		if not result.detail_enabled and result.detail_normal == null and result.detail_albedo == null and result.detail_mask == null:
			result.detail_enabled = true
			result.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			result.detail_albedo = _wood_patina_mask()
		_weather_cache[key] = result
		return result
	var weather := ShaderMaterial.new()
	weather.shader = WEATHER_SHADER
	weather.set_shader_parameter("ruin_scan", DAMP_SCAN)
	weather.resource_name = "HideoutWeatherCoat_%s" % kind
	weather.set_shader_parameter("surface_kind", 1 if kind == "floor" else (2 if kind == "wood" else 0))
	weather.set_shader_parameter("weather_strength", 0.82 if kind == "wood" else 1.0)
	weather.set_shader_parameter("source_albedo", result.albedo_texture)
	weather.set_shader_parameter("source_normal", result.normal_texture)
	weather.set_shader_parameter("source_roughness", result.roughness_texture)
	weather.set_shader_parameter("source_detail_normal", result.detail_normal)
	weather.set_shader_parameter("has_albedo", result.albedo_texture != null)
	weather.set_shader_parameter("has_normal", result.normal_enabled and result.normal_texture != null)
	weather.set_shader_parameter("has_roughness", result.roughness_texture != null)
	weather.set_shader_parameter("has_detail_normal", result.detail_enabled and result.detail_normal != null)
	weather.set_shader_parameter("base_color", result.albedo_color)
	weather.set_shader_parameter("uses_vertex_color", result.vertex_color_use_as_albedo)
	weather.set_shader_parameter("source_triplanar", result.uv1_triplanar)
	weather.set_shader_parameter("source_world_triplanar", result.uv1_world_triplanar)
	weather.set_shader_parameter("source_uv_scale", result.uv1_scale)
	weather.set_shader_parameter("source_uv_offset", result.uv1_offset)
	weather.set_shader_parameter("source_normal_strength", result.normal_scale)
	weather.set_shader_parameter("source_roughness_value", result.roughness)
	weather.set_shader_parameter("source_metallic", result.metallic)
	weather.set_shader_parameter("source_specular", result.metallic_specular)
	var channel := Vector4(1.0, 0.0, 0.0, 0.0)
	match result.roughness_texture_channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: channel = Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: channel = Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: channel = Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: channel = Vector4(0.3333, 0.3333, 0.3333, 0.0)
	weather.set_shader_parameter("source_roughness_channel", channel)
	weather.render_priority = 1
	weather.next_pass = source.next_pass
	result.next_pass = weather
	_weather_cache[key] = result
	return result


static func _pitted_detail_normal() -> NoiseTexture2D:
	if _fracture_normal == null:
		var noise := FastNoiseLite.new()
		noise.seed = 20260908
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.016
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		noise.fractal_gain = 0.58
		_fracture_normal = NoiseTexture2D.new()
		_fracture_normal.width = 256
		_fracture_normal.height = 256
		_fracture_normal.seamless = true
		_fracture_normal.generate_mipmaps = true
		_fracture_normal.as_normal_map = true
		_fracture_normal.bump_strength = 5.8
		_fracture_normal.noise = noise
	return _fracture_normal


static func _wood_patina_mask() -> NoiseTexture2D:
	if _wood_patina_albedo == null:
		var noise := FastNoiseLite.new()
		noise.seed = 20260909
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.009
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.fractal_gain = 0.58
		var patina := Gradient.new()
		# Light-valued sRGB multipliers retain readable oak under dim light.
		# Their limited olive/grey range marks damp grain without black paint.
		patina.set_color(0, Color(0.64, 0.70, 0.59, 1.0))
		patina.set_color(1, Color.WHITE)
		patina.add_point(0.28, Color(0.75, 0.79, 0.70, 1.0))
		patina.add_point(0.44, Color(0.87, 0.87, 0.84, 1.0))
		patina.add_point(0.60, Color(0.98, 0.98, 0.96, 1.0))
		_wood_patina_albedo = NoiseTexture2D.new()
		_wood_patina_albedo.width = 256
		_wood_patina_albedo.height = 256
		_wood_patina_albedo.seamless = true
		_wood_patina_albedo.generate_mipmaps = true
		_wood_patina_albedo.noise = noise
		_wood_patina_albedo.color_ramp = patina
	return _wood_patina_albedo


static func ruin_material(slot: String) -> StandardMaterial3D:
	if _ruin_cache.has(slot):
		return _ruin_cache[slot] as StandardMaterial3D
	var material: StandardMaterial3D
	var kind := "stone"
	match slot:
		"ruin_timber", "ruin_root":
			material = SURFACES.old_oak(Color(0.89, 0.81, 0.67), 2.1)
			kind = "wood"
		"ruin_moss":
			material = SURFACES.create("stone", Color(0.52, 0.64, 0.40), SURFACES.STONE, 4.4)
			material.roughness = 1.0
			material.metallic_specular = 0.12
			material.normal_scale = 0.84
		"ruin_mortar":
			material = SURFACES.create("stone", Color(0.45, 0.48, 0.44), SURFACES.STONE, 3.7)
			material.roughness = 0.98
		_:
			material = SURFACES.create("stone", Color(0.65, 0.68, 0.63), SURFACES.STONE, 2.2)
	material.resource_name = slot
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_world_triplanar = true
	var result := material if slot == "ruin_moss" else weathered(material, kind)
	result.set_meta("hideout_ruin_slot", slot)
	_ruin_cache[slot] = result
	return result


static func stain_material(kind: String) -> ShaderMaterial:
	if _stain_cache.has(kind):
		return _stain_cache[kind] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = STAIN_SHADER
	material.resource_name = "HideoutStain_%s" % kind
	var kinds := ["moss", "mold", "leak", "soot", "salt"]
	material.set_shader_parameter("stain_kind", maxi(kinds.find(kind), 0))
	material.set_shader_parameter("opacity", 0.48 if kind == "moss" else (0.16 if kind == "salt" else 0.56))
	material.render_priority = 3
	material.set_meta("hideout_ruin_stain", kind)
	_stain_cache[kind] = material
	return material


static func water_material() -> ShaderMaterial:
	if _water == null:
		_water = ShaderMaterial.new()
		_water.shader = WATER_SHADER
		_water.resource_name = "HideoutSeepageWater"
		_water.set_shader_parameter("ripple_only", false)
		_water.set_shader_parameter("opacity", 0.76)
		_water.render_priority = 2
	return _water


static func ripple_material() -> ShaderMaterial:
	if _ripple == null:
		_ripple = ShaderMaterial.new()
		_ripple.shader = WATER_SHADER
		_ripple.resource_name = "HideoutDripImpactRipples"
		_ripple.set_shader_parameter("ripple_only", true)
		_ripple.set_shader_parameter("opacity", 0.70)
		_ripple.render_priority = 4
	return _ripple
