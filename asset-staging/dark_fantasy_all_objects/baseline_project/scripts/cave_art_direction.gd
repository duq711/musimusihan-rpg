extends RefCounted
## Shared production art direction; native previews use precisely these settings.
const GEOLOGY := preload("res://shaders/mine_geology.gdshader")
const TEXTURES := "res://assets/3d/abandoned_mine/textures/"
static var _materials: Dictionary = {}

static func geological_material(soil: bool) -> ShaderMaterial:
	var key := "soil" if soil else "rock"
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.resource_name = "Mine_Art_Earth" if soil else "Mine_Art_DampBedrock"
	material.shader = GEOLOGY
	var source := "brown_mud_rocks_01" if soil else "dark_rock_02"
	for channel: String in ["albedo", "normal", "roughness", "height"]:
		var filename := "normal_gl" if channel == "normal" else channel
		material.set_shader_parameter(channel + "_map", load(TEXTURES + source + "_" + filename + "_2k.jpg"))
	material.set_shader_parameter("fracture_albedo", load(TEXTURES + "rock_boulder_dry_albedo_2k.jpg"))
	material.set_shader_parameter("fracture_normal", load(TEXTURES + "rock_boulder_dry_normal_gl_2k.jpg"))
	material.set_shader_parameter("ground_surface", soil)
	material.set_shader_parameter("base_tint", Color(0.69,0.61,0.49) if soil else Color(0.76,0.80,0.82))
	material.set_shader_parameter("metric_scale", 1.08 if soil else 1.65)
	material.set_shader_parameter("normal_strength", 0.19 if soil else 0.95)
	material.set_shader_parameter("dry_roughness", 0.94 if soil else 0.79)
	material.set_shader_parameter("wet_roughness", 0.48 if soil else 0.34)
	material.set_shader_parameter("fracture_mix", 0.0 if soil else 0.42)
	_materials[key] = material
	return material

static func apply_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var label := str(node.name)
		for surface in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(surface)
			if source == null:
				continue
			var soil := source.resource_name.contains("Ground")
			if label.begins_with("Terrain_") or label.begins_with("RockScan_") or label.begins_with("RockFormation_") or label.begins_with("Scree_") or label.begins_with("MineralCluster_") or label.begins_with("CalciteCeiling_"):
				node.set_surface_override_material(surface, geological_material(soil))
			elif source is BaseMaterial3D and source.resource_name.contains("AgedOak"):
				var aged := source.duplicate() as BaseMaterial3D
				aged.albedo_color = Color(0.46,0.40,0.31)
				aged.roughness = 0.9
				node.set_surface_override_material(surface, aged)
	for child in node.get_children():
		apply_materials(child)

static func configure_player_lighting(player: Node) -> void:
	# Metadata also drives the player's normal animation, including flicker.
	player.torch.set_meta("base_energy", 1.70)
	player.torch_fill.set_meta("base_energy", 0.85)
	player.torch.light_energy = 1.70
	player.torch_fill.light_energy = 0.85
	player.torch.light_color = Color(1.0,0.85,0.67)
	player.torch_fill.light_color = Color(1.0,0.76,0.52)
	player.torch.spot_range = 10.0
	player.torch.spot_angle = 65.0
	player.torch.spot_attenuation = 1.4
	player.torch_fill.omni_range = 4.7
	player.torch_fill.omni_attenuation = 1.3

static func make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.009,0.014,0.019)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46,0.57,0.68)
	e.ambient_light_energy = 0.72
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.05
	e.ssao_power = 1.1
	e.ssil_enabled = false
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.65
	e.fog_enabled = true
	e.fog_light_color = Color(0.12,0.19,0.23)
	e.fog_light_energy = 0.4
	e.fog_density = 0.006
	e.fog_height = -0.25
	e.fog_height_density = 0.09
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.011
	e.volumetric_fog_albedo = Color(0.42,0.52,0.58)
	e.volumetric_fog_emission = Color(0.016,0.026,0.036)
	e.volumetric_fog_emission_energy = 0.15
	e.volumetric_fog_length = 35.0
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_strength = 0.72
	e.glow_bloom = 0.015
	return e
