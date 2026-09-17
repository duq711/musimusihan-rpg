extends RefCounted
class_name FlameVisuals

static var _flow: NoiseTexture2D
static var _flame_shader: Shader
static var _steam: Texture2D


static func attach(sprite: Sprite3D) -> void:
	if sprite.has_meta("dimensional_flame") or sprite.texture == null:
		return
	sprite.set_meta("dimensional_flame", true)
	# The original generated flame supplies fine side detail. Additive blending
	# removes its black matte, while a vertical billboard leaves a true top view.
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var side := StandardMaterial3D.new()
	side.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	side.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	side.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	side.cull_mode = BaseMaterial3D.CULL_DISABLED
	side.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	side.albedo_texture = sprite.texture
	side.albedo_color = Color(1, 1, 1, 0.70)
	side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	sprite.material_override = side
	var height := float(sprite.texture.get_height()) * sprite.pixel_size
	var width := float(sprite.texture.get_width()) * sprite.pixel_size
	var root := Node3D.new()
	root.name = "DimensionalFlameTongues"
	sprite.add_child(root)
	for index in 5:
		var tongue := MeshInstance3D.new()
		tongue.name = "FlowingFireTongue_%d" % index
		tongue.mesh = _tongue_mesh(height * (0.69 + float(index % 3) * 0.105), width * 0.21, index)
		var material := ShaderMaterial.new()
		material.shader = _shader()
		material.set_shader_parameter("flow", _flow_texture())
		material.set_shader_parameter("phase", float(index) * 1.31)
		tongue.material_override = material
		tongue.position.y = -height * 0.46
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tongue)


static func _tongue_mesh(height: float, radius: float, index: int) -> ArrayMesh:
	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = 18
	source.rings = 16
	var arrays := source.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var angle := float(index) * TAU / 5.0
	for vertex in points.size():
		var p := points[vertex]
		var t := (p.y + 1.0) * 0.5
		var taper := pow(1.0 - t, 0.60)
		var drift := sin(t * 8.0 + angle) * radius * 0.28 * t
		points[vertex] = Vector3(p.x * radius * taper + cos(angle) * (radius * 0.46 + drift), t * height, p.z * radius * taper + sin(angle) * (radius * 0.46 + drift))
		uvs[vertex].y = t
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func _flow_texture() -> NoiseTexture2D:
	if _flow == null:
		var noise := FastNoiseLite.new()
		noise.seed = 583
		noise.frequency = 0.035
		noise.fractal_octaves = 4
		_flow = NoiseTexture2D.new()
		_flow.width = 256
		_flow.height = 256
		_flow.seamless = true
		_flow.noise = noise
	return _flow


static func _shader() -> Shader:
	if _flame_shader == null:
		_flame_shader = Shader.new()
		_flame_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D flow : repeat_enable, filter_linear_mipmap;
uniform float phase = 0.0;
void vertex() {
    VERTEX.x += sin(TIME * 5.7 + UV.y * 13.0 + phase) * 0.008 * UV.y;
    VERTEX.z += cos(TIME * 4.1 + UV.y * 11.0 + phase) * 0.006 * UV.y;
}
void fragment() {
    float n = texture(flow, vec2(UV.x * 2.0 + phase, UV.y * 2.8 - TIME * 0.65)).r;
    float thread = smoothstep(0.35, 0.76, n);
    float fade = smoothstep(0.0, 0.07, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
    vec3 heat = mix(vec3(1.0, 0.63, 0.065), vec3(0.80, 0.055, 0.002), UV.y);
    ALBEDO = heat;
    EMISSION = heat * 0.6;
    ALPHA = thread * fade * 0.27;
}
"""
	return _flame_shader


static func steam_texture() -> Texture2D:
	if _steam != null:
		return _steam
	var noise := FastNoiseLite.new()
	noise.seed = 751
	noise.frequency = 0.044
	noise.fractal_octaves = 4
	var raster := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var centered := Vector2(float(x) / 127.0 - 0.5, float(y) / 127.0 - 0.5)
			var feather := pow(maxf(0.0, 1.0 - centered.length() * 2.0), 1.5)
			var curled_x := float(x) + sin(float(y) * 0.084) * 11.0
			var n := noise.get_noise_2d(curled_x, float(y) * 0.52) * 0.5 + 0.5
			var wisps := smoothstep(0.30, 0.66, n)
			raster.set_pixel(x, y, Color(0.84, 0.82, 0.76, feather * wisps))
	_steam = ImageTexture.create_from_image(raster)
	return _steam


static func droplet_mesh() -> ArrayMesh:
	var source := SphereMesh.new()
	source.radius = 0.026
	source.height = 0.085
	source.radial_segments = 10
	source.rings = 6
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var p := vertices[index]
		var taper := 1.0 - smoothstep(-0.017, 0.0425, p.y) * 0.75
		vertices[index] = Vector3(p.x * taper, p.y, p.z * taper)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return preload("res://scripts/dungeon_concept_visual.gd")._rebuild_normals(arrays)
