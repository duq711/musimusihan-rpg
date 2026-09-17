extends RefCounted
## The imported assemblies retain their exact meshes, UVs and transforms. Six-view
## concept matching changes the aged surface response on named prop materials.
const SURFACE := preload("res://shaders/mine_prop_surface.gdshader")
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
static var _cache: Dictionary = {}

static func apply(root: Node3D) -> void:
	_apply_node(root)

static func _apply_node(node: Node, belongs_to_prop: bool = false) -> void:
	belongs_to_prop = belongs_to_prop or str(node.name).begins_with("Mine_")
	if node is MeshInstance3D and belongs_to_prop and node.mesh:
		for surface in node.mesh.get_surface_count():
			var source := node.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var family := _family(source.resource_name)
			if family.is_empty():
				continue
			node.set_surface_override_material(surface, _material(source, family))
			node.set_meta("mine_prop_concept", true)
	for child in node.get_children():
		_apply_node(child, belongs_to_prop)

static func _family(label: String) -> String:
	if label.contains("AgedOak"): return "oak"
	if label.contains("RustedIron"): return "iron"
	if label.contains("AgedIvoryBone"): return "bone"
	if label.contains("HempRope"): return "rope"
	if label.contains("DustyCanvas"): return "linen"
	if label.contains("LanternSmokeGlass"): return "glass"
	if label.contains("Calcite") or label.contains("Limestone") or label.contains("DarkGallery"): return "stone"
	return ""

static func _material(source: StandardMaterial3D, family: String) -> ShaderMaterial:
	var key := "%d:%s" % [source.get_instance_id(), family]
	if _cache.has(key): return _cache[key]
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.resource_name = "Concept_" + source.resource_name
	material.set_meta("mine_prop_family", family)
	material.set_meta("authored_surface", source.resource_name)
	material.set_shader_parameter("base_color", source.albedo_color)
	material.set_shader_parameter("has_albedo", source.albedo_texture != null)
	material.set_shader_parameter("albedo_map", source.albedo_texture)
	var normal := source.normal_texture
	var roughness := source.roughness_texture
	var channel := source.roughness_texture_channel
	if family != "glass" and (normal == null or roughness == null):
		var fallback := SURFACES.create("linen" if family == "rope" else family, Color.WHITE)
		if normal == null: normal = fallback.normal_texture
		if roughness == null:
			roughness = fallback.roughness_texture
			channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.set_shader_parameter("has_normal", normal != null)
	material.set_shader_parameter("normal_map", normal)
	material.set_shader_parameter("has_roughness", roughness != null)
	material.set_shader_parameter("roughness_map", roughness)
	var channels := [Vector4(1,0,0,0),Vector4(0,1,0,0),Vector4(0,0,1,0),Vector4(0,0,0,1),Vector4(0.3333,0.3333,0.3333,0)]
	material.set_shader_parameter("roughness_channel", channels[clampi(channel,0,4)])
	var tint := Color.WHITE
	var saturation := 0.2
	var depth := 0.85
	var rough := 0.92
	var metal := 0.0
	match family:
		"oak": tint = Color(0.46,0.44,0.405); depth = 0.95
		"iron": tint = Color(0.54,0.56,0.55); saturation = 0.16; depth = 1.15; rough = 0.80; metal = 0.48
		"stone": tint = Color(0.31,0.335,0.34); saturation = 0.12; depth = 0.98; rough = 0.88
		"bone": tint = Color(0.48,0.48,0.43); saturation = 0.20; depth = 0.75
		"rope": tint = Color(0.75,0.76,0.70); saturation = 0.25; depth = 0.33
		"linen": tint = Color(0.61,0.64,0.60); saturation = 0.10; depth = 0.28
		"glass": tint = Color(0.55,0.61,0.62); saturation = 0.06; depth = 0.04; rough = 0.62
	material.set_shader_parameter("surface_tint", tint)
	material.set_shader_parameter("saturation", saturation)
	material.set_shader_parameter("normal_strength", depth)
	material.set_shader_parameter("roughness_value", rough)
	material.set_shader_parameter("metallic_value", metal)
	material.set_shader_parameter("dust_amount", 0.12 if family == "iron" else 0.19)
	_cache[key] = material
	return material
