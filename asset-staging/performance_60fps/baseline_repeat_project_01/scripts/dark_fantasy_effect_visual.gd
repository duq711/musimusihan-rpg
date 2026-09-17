extends RefCounted
## Visual geometry only; projectile sweep radius and every combat value stay
## on MagicProjectile. Local deterministic formulas never consume combat RNG.

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const FLAMES := preload("res://scripts/flame_visuals.gd")
const COAL_TEXTURE: Texture2D = preload("res://assets/ai/materials/concept_ember_coal.png")
const ICE_TEXTURE: Texture2D = preload("res://assets/ai/materials/concept_frosted_ice.png")
static var _materials: Dictionary = {}


static func populate_projectile(parent: Node3D, element: String, radius: float) -> void:
	var core := MeshInstance3D.new()
	core.name = "ElementCore"
	match element:
		"ice":
			core.mesh = _ice_mesh(radius)
			core.material_override = _element_shader("ice")
		"stone":
			core.mesh = _rock_mesh(radius, 11, 7, Vector3(1.1, 0.88, 1.0), 0.12, false)
			core.material_override = SURFACES.stone(Color(0.24, 0.23, 0.205), 5.0)
		"water":
			core.mesh = _rock_mesh(radius, 48, 32, Vector3(0.78, 0.78, 1.45), 0.012, true)
			core.material_override = _element_shader("water")
		_:
			core.mesh = _rock_mesh(radius, 26, 17, Vector3.ONE, 0.045, true)
			core.material_override = _element_shader("fire")
	parent.add_child(core)
	if element in ["fire", "water"]:
		for index in range(12):
			var angle := float(index) * 2.399963
			var y := -0.8 + float(index) * 0.145
			var radial := sqrt(maxf(0.0, 1.0 - y * y))
			var particle := MeshInstance3D.new()
			particle.name = "Ember%02d" % index if element == "fire" else "SurfaceDroplet%02d" % index
			var sphere := SphereMesh.new()
			sphere.radius = radius * (0.017 + 0.005 * float(index % 3))
			sphere.height = sphere.radius * 2.0
			sphere.radial_segments = 6
			sphere.rings = 3
			particle.mesh = sphere
			particle.position = Vector3(cos(angle) * radial, y, sin(angle) * radial) * radius * 1.21
			particle.material_override = _ember_material() if element == "fire" else core.material_override
			particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(particle)
	if element == "fire":
		# Reuse the same genuine flowing-flame material as production torches.
		# Thin tongues reach the old visual halo envelope without changing hits.
		for index in range(6):
			var tongue := MeshInstance3D.new()
			tongue.name = "CoalFlameTongue%02d" % index
			tongue.mesh = FLAMES._tongue_mesh(radius * 1.5, radius * 0.24, index)
			var material := ShaderMaterial.new()
			material.shader = FLAMES._shader()
			material.set_shader_parameter("flow", FLAMES._flow_texture())
			material.set_shader_parameter("phase", float(index) * 1.31)
			tongue.material_override = material
			var angle := float(index) * TAU / 6.0
			tongue.position = Vector3(cos(angle) * radius * 0.74, -radius * 0.24, sin(angle) * radius * 0.74)
			tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(tongue)
	var light := OmniLight3D.new()
	light.name = "ElementLight"
	light.light_color = Color(1.0, 0.24, 0.035) if element == "fire" else Color(0.34, 0.49, 0.56)
	light.light_energy = 0.75 if element == "fire" else (0.16 if element != "stone" else 0.0)
	light.omni_range = 2.0 if element != "stone" else 1.1
	light.shadow_enabled = false
	parent.add_child(light)


static func _element_shader(element: String) -> ShaderMaterial:
	if _materials.has(element):
		return _materials[element] as ShaderMaterial
	var shader := Shader.new()
	var shared := """
shader_type spatial;
varying vec3 local_point;
varying vec3 local_normal;
uniform sampler2D concept_surface:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
float hash3(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) { vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z); }
vec3 concept_tex(float scale){vec3 w=pow(abs(normalize(local_normal)),vec3(4.0));w/=w.x+w.y+w.z;return texture(concept_surface,local_point.yz*scale).rgb*w.x+texture(concept_surface,local_point.xz*scale).rgb*w.y+texture(concept_surface,local_point.xy*scale).rgb*w.z;}
void vertex() { local_point=VERTEX; local_normal=NORMAL; }
"""
	match element:
		"fire":
			shader.code = shared + """
void fragment() {
 vec3 coal=concept_tex(4.0); float heat=max(coal.r-max(coal.g,coal.b),0.0);
 float grain=dot(coal,vec3(0.2126,0.7152,0.0722));
 ALBEDO=coal*0.85; ROUGHNESS=0.97;
 NORMAL=normalize(NORMAL+vec3(dFdx(grain),dFdy(grain),0.0)*2.0);
 EMISSION=vec3(1.0,0.18,0.015)*min(heat*9.5,1.8)*(0.88+0.12*sin(TIME*4.0+local_point.y*38.0));
}
"""
		"water":
			shader.code = shared + """
void fragment() {
 vec3 p=local_point*75.0; float ripple=noise3(p+vec3(TIME*0.4,0,TIME*0.3));
 float fine=noise3(p*3.3); float rim=pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0),3.0);
 ALBEDO=mix(vec3(0.003,0.008,0.011),vec3(0.035,0.060,0.072),ripple*0.8+fine*0.2);
 NORMAL=normalize(NORMAL+vec3(dFdx(ripple),dFdy(ripple),0.0)*3.0);
 ROUGHNESS=0.09+fine*0.12; METALLIC=0.38; SPECULAR=0.65; EMISSION=vec3(0.13,0.19,0.22)*rim;
}
"""
		_:
			shader.code = shared + """
void fragment() {
 vec3 ice=concept_tex(3.8); float grain=dot(ice,vec3(0.2126,0.7152,0.0722));
 ALBEDO=ice*vec3(0.52,0.70,0.78);
 ROUGHNESS=0.50+grain*0.12; SPECULAR=0.38; METALLIC=0.02; EMISSION=vec3(0.002,0.005,0.007);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	if element == "fire":
		material.set_shader_parameter("concept_surface", COAL_TEXTURE)
	elif element == "ice":
		material.set_shader_parameter("concept_surface", ICE_TEXTURE)
	material.set_meta("dark_fantasy_element", element)
	_materials[element] = material
	return material


static func _ember_material() -> StandardMaterial3D:
	if _materials.has("ember"):
		return _materials.ember as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.64, 0.17, 0.025)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.18, 0.015)
	material.emission_energy_multiplier = 2.0
	_materials.ember = material
	return material


static func _rock_mesh(radius: float, sides: int, rows: int, stretch: Vector3, roughness: float, smooth: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows):
		for side in range(sides):
			var a := _rock_vertex(radius, row, side, sides, rows, stretch, roughness)
			var b := _rock_vertex(radius, row, side + 1, sides, rows, stretch, roughness)
			var c := _rock_vertex(radius, row + 1, side + 1, sides, rows, stretch, roughness)
			var d := _rock_vertex(radius, row + 1, side, sides, rows, stretch, roughness)
			_face(surface, a, b, c, (a + b + c) / 3.0, smooth, stretch)
			_face(surface, a, c, d, (a + c + d) / 3.0, smooth, stretch)
	return surface.commit()


static func _rock_vertex(radius: float, row: int, side: int, sides: int, rows: int, stretch: Vector3, roughness: float) -> Vector3:
	var latitude := PI * float(row) / float(rows)
	var angle := TAU * float(side % sides) / float(sides)
	var direction := Vector3(sin(latitude) * cos(angle), cos(latitude), sin(latitude) * sin(angle))
	var irregularity := 1.0 + roughness * sin(float(side % sides) * 12.73 + float(row) * 7.17)
	if row == 0 or row == rows:
		irregularity = 1.0
	return direction * radius * stretch * irregularity


static func _ice_mesh(radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var widths := [0.0, 0.10, 0.21, 0.27, 0.43, 0.50, 0.66, 0.62, 0.0]
	var depths := [-1.65, -1.3, -0.95, -0.55, -0.15, 0.35, 0.80, 0.95, 1.08]
	for row in range(widths.size() - 1):
		for side in range(9):
			var a := _ice_vertex(radius, row, side, widths, depths)
			var b := _ice_vertex(radius, row, side + 1, widths, depths)
			var c := _ice_vertex(radius, row + 1, side + 1, widths, depths)
			var d := _ice_vertex(radius, row + 1, side, widths, depths)
			var first_center := (a + b + c) / 3.0
			var second_center := (a + c + d) / 3.0
			_face(surface, a, b, c, Vector3(first_center.x, first_center.y, 0), false)
			_face(surface, a, c, d, Vector3(second_center.x, second_center.y, 0), false)
	return surface.commit()


static func _ice_vertex(radius: float, row: int, side: int, widths: Array, depths: Array) -> Vector3:
	var angle := TAU * float(side % 9) / 9.0 + float(row) * 0.09
	var irregularity := 0.88 + 0.12 * sin(float(side % 9) * 8.79 + float(row) * 3.1)
	return Vector3(cos(angle) * float(widths[row]) * irregularity, sin(angle) * float(widths[row]) * irregularity, float(depths[row])) * radius


static func _face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, smooth := false, stretch := Vector3.ONE) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000000000001:
		return
	if normal.dot(outward) < 0.0:
		normal = -normal
	else:
		var swapped := b
		b = c
		c = swapped
	normal = normal.normalized()
	for vertex in [a, b, c]:
		surface.set_normal((vertex / (stretch * stretch)).normalized() if smooth else normal)
		surface.add_vertex(vertex)


static func create_shroud() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Uneven strips fold around the torso and taper into separate trailing rags.
	for row in range(12):
		for side in range(36):
			var a := _cloth_vertex(row, side)
			var b := _cloth_vertex(row, side + 1)
			var c := _cloth_vertex(row + 1, side + 1)
			var d := _cloth_vertex(row + 1, side)
			surface.set_color(Color(0.72 + 0.20 * sin(float(side) * 1.7), 0.78 + 0.16 * sin(float(side) * 1.7), 0.80 + 0.15 * sin(float(side) * 1.7)))
			_face(surface, a, b, c, Vector3(a.x, 0, a.z), false)
			_face(surface, a, c, d, Vector3(a.x, 0, a.z), false)
	# A deep open hood replaces the old visible spherical head. Its front gap
	# faces -Z like the production silhouette; the cavity stays completely dark.
	for row in range(9):
		for side in range(24):
			var a := _hood_vertex(row, side)
			var b := _hood_vertex(row, side + 1)
			var c := _hood_vertex(row + 1, side + 1)
			var d := _hood_vertex(row + 1, side)
			surface.set_color(Color(0.76, 0.80, 0.82))
			_face(surface, a, b, c, (a + b + c) / 3.0 - Vector3(0, 1.4, 0), false)
			_face(surface, a, c, d, (a + c + d) / 3.0 - Vector3(0, 1.4, 0), false)
	return surface.commit()


static func _cloth_vertex(row: int, side: int) -> Vector3:
	var t := float(row) / 12.0
	var angle := TAU * float(side % 36) / 36.0
	var rag := 0.11 + 0.105 * sin(float(side % 36) * 2.31)
	var height := lerpf(rag, 1.36, t)
	var width := lerpf(0.075, 0.25, sin(t * PI * 0.84))
	var shoulder := exp(-pow((t - 0.78) * 7.0, 2.0)) * 0.085
	var folds := (0.019 * sin(angle * 10.0 + t * 4.0) + 0.011 * sin(angle * 17.0 - t * 7.0)) * sin(t * PI)
	return Vector3(sin(angle) * (width + shoulder + folds) + 0.024 * sin(t * 5.0), height, cos(angle) * (width * 0.59 + folds) + 0.07 * sin(t * PI))


static func _hood_vertex(row: int, side: int) -> Vector3:
	var t := float(row) / 9.0
	var angle := lerpf(-2.35, 2.35, float(side) / 24.0)
	var radius := sin((0.17 + t * 0.83) * PI) * (0.19 + 0.012 * cos(angle * 6.0))
	return Vector3(sin(angle) * radius, 1.19 + t * 0.46, cos(angle) * radius * 0.92 + 0.012)
