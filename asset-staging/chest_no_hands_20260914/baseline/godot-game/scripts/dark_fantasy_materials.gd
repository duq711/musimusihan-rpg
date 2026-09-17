extends RefCounted
class_name DarkFantasyMaterials

# Surface response shared by production objects and the six-view inspection
# gallery. Authored albedo/normal maps remain authoritative; procedural detail
# only supplies missing microsurface information, never replaces concept art.
const FAMILIES := ["oak", "iron", "leather", "linen", "stone", "bone"]
const OAK: Texture2D = preload("res://assets/ai/materials/concept_weathered_oak.png")
const IRON: Texture2D = preload("res://assets/ai/materials/concept_forged_steel.png")
const STONE: Texture2D = preload("res://assets/ai/materials/concept_limestone.png")
const CLOTH: Texture2D = preload("res://assets/ai/materials/concept_charcoal_linen.png")
const LEATHER: Texture2D = preload("res://assets/ai/materials/concept_black_leather.png")

static var _surface_maps: Dictionary = {}


static func create(family: String, tint: Color, texture: Texture2D = null, scale_value := 3.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 24.0
	material.uv1_scale = Vector3.ONE * scale_value
	return tune(material, family)


static func old_oak(tint := Color(0.48, 0.39, 0.29), scale_value := 2.5) -> StandardMaterial3D:
	return create("oak", _muted_tint(tint, 1.05), OAK, scale_value)


static func pitted_iron(tint := Color(0.29, 0.31, 0.30), scale_value := 3.0) -> StandardMaterial3D:
	return create("iron", _muted_tint(tint, 1.35), IRON, scale_value)


static func leather(tint := Color(0.14, 0.105, 0.077), scale_value := 4.0) -> StandardMaterial3D:
	return create("leather", _muted_tint(tint, 5.0), LEATHER, scale_value)


static func linen(tint := Color(0.23, 0.215, 0.18), scale_value := 5.0) -> StandardMaterial3D:
	return create("linen", _muted_tint(tint, 2.8), CLOTH, scale_value)


static func stone(tint := Color(0.38, 0.40, 0.37), scale_value := 2.0) -> StandardMaterial3D:
	return create("stone", _muted_tint(tint, 1.7), STONE, scale_value)


static func _muted_tint(tint: Color, gain: float) -> Color:
	var value := tint.get_luminance()
	var neutral := Color(value, value, value, tint.a)
	var result := neutral.lerp(tint, 0.22)
	return Color(minf(result.r * gain, 1.0), minf(result.g * gain, 1.0), minf(result.b * gain, 1.0), tint.a)


static func bone(tint := Color(0.51, 0.47, 0.37), scale_value := 4.0) -> StandardMaterial3D:
	var material := create("bone", tint, null, scale_value)
	material.albedo_texture = _maps_for("bone").patina
	return material


static func tune(material: StandardMaterial3D, family: String) -> StandardMaterial3D:
	assert(family in FAMILIES, "Unsupported dark-fantasy surface: %s" % family)
	material.set_meta("dark_fantasy_surface", family)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	var maps := _maps_for(family)
	if material.normal_texture == null:
		material.normal_enabled = true
		material.normal_texture = maps.normal
		material.normal_scale = 0.38 if family in ["linen", "leather"] else 0.52
	if material.roughness_texture == null:
		material.roughness_texture = maps.roughness
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	match family:
		"iron":
			material.roughness = 0.68
			material.metallic = 0.55
			material.metallic_specular = 0.48
		"oak":
			material.roughness = 0.94
			material.metallic = 0.0
			material.metallic_specular = 0.24
		"linen":
			material.roughness = 1.0
			material.metallic = 0.0
			material.metallic_specular = 0.12
		"leather":
			material.roughness = 0.93
			material.metallic = 0.0
			material.metallic_specular = 0.24
		"stone":
			material.roughness = 0.90
			material.metallic = 0.0
			material.metallic_specular = 0.30
		"bone":
			material.roughness = 0.91
			material.metallic = 0.0
			material.metallic_specular = 0.28
	return material


static func _maps_for(family: String) -> Dictionary:
	if _surface_maps.has(family):
		return _surface_maps[family]
	var noise := FastNoiseLite.new()
	noise.seed = 713 + FAMILIES.find(family) * 101
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.055 if family in ["stone", "iron"] else 0.16
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.48
	var normal := NoiseTexture2D.new()
	normal.width = 256
	normal.height = 256
	normal.seamless = true
	normal.generate_mipmaps = true
	normal.as_normal_map = true
	normal.bump_strength = 1.2 if family in ["linen", "bone"] else 2.2
	normal.noise = noise
	var roughness := NoiseTexture2D.new()
	roughness.width = 256
	roughness.height = 256
	roughness.seamless = true
	roughness.generate_mipmaps = true
	roughness.noise = noise
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.73, 0.73, 0.73))
	gradient.set_color(1, Color(1.0, 1.0, 1.0))
	roughness.color_ramp = gradient
	var patina := NoiseTexture2D.new()
	patina.width = 256
	patina.height = 256
	patina.seamless = true
	patina.generate_mipmaps = true
	patina.noise = noise
	var patina_gradient := Gradient.new()
	patina_gradient.set_color(0, Color(0.39, 0.38, 0.35))
	patina_gradient.set_color(1, Color(0.95, 0.93, 0.87))
	patina.color_ramp = patina_gradient
	var result := {"normal": normal, "roughness": roughness, "patina": patina}
	_surface_maps[family] = result
	return result
