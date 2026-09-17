extends RefCounted
const FIRE_SHADER = preload("res://assets/vfx/spatial_fire/torch_fire.gdshader")
const CLOTH_BASE := 0.44
const CLOTH_TOP := 0.81
static var noise_texture: NoiseTexture3D
static func create() -> Node3D:
	if noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.06
		noise.fractal_octaves = 3
		noise.fractal_lacunarity = 3.0
		noise.fractal_gain = 0.5
		noise.fractal_weighted_strength = 1.0
		noise.domain_warp_enabled = false
		noise.domain_warp_fractal_octaves = 1
		noise_texture = NoiseTexture3D.new()
		noise_texture.width = 64; noise_texture.height = 64; noise_texture.depth = 64
		noise_texture.noise = noise
		noise_texture.seamless = true; noise_texture.invert = true; noise_texture.normalize = false
		noise_texture.seamless_blend_skirt = 0.25
	var root := Node3D.new()
	root.set_meta("raymarched_fire", true)
	var volume := MeshInstance3D.new()
	volume.name = "RaymarchedFire"
	var box := BoxMesh.new()
	box.size = Vector3(3.4, 3.8, 3.4)
	# Offset geometry without shifting the shader's local origin at the wick.
	var arrays := box.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in points.size():points[i].y += 1.65
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	volume.mesh = mesh
	volume.scale = Vector3(0.14, 0.25, 0.14)
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new(); material.shader = FIRE_SHADER
	material.set_shader_parameter("sample_noise", noise_texture)
	material.set_shader_parameter("billboard", false)
	material.set_shader_parameter("fire_height", 3.2)
	material.set_shader_parameter("oil_cloth_height", (CLOTH_TOP - CLOTH_BASE) / volume.scale.y)
	material.set_shader_parameter("raymarch_steps", 24)
	material.set_shader_parameter("sample_jitter", false)
	material.set_shader_parameter("jitter_multiplier", 0.3)
	material.set_shader_parameter("emission_strength", 0.9)
	material.set_shader_parameter("core_glow_multiplier", 4.0)
	material.set_shader_parameter("color_smoke", Vector3.ZERO)
	material.set_shader_parameter("taper_factor", 0.55)
	material.set_shader_parameter("time_scale", 0.018)
	material.set_shader_parameter("sharpness_cutoff", 2.3)
	volume.material_override = material
	root.add_child(volume)
	return root
