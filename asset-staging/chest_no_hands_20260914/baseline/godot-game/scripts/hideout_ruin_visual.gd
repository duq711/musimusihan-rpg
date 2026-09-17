extends Node3D
class_name HideoutRuinVisual

const MATERIALS := preload("res://scripts/hideout_ruin_materials.gd")
const ROOF := preload("res://scripts/hideout_ruin_roof.gd")
const CLOSURES := preload("res://scripts/hideout_ruin_closures.gd")
const SCATTER := preload("res://scripts/hideout_ruin_scatter.gd")
const MASONRY := preload("res://scripts/hideout_ruin_masonry.gd")
const KIT := {
	"edge": preload("res://assets/3d/hideout_ruins/broken_masonry_edge.glb"),
	"arch": preload("res://assets/3d/hideout_ruins/collapsed_arch.glb"),
	"rubble": preload("res://assets/3d/hideout_ruins/rubble_pile.glb"),
	"timber": preload("res://assets/3d/hideout_ruins/snapped_timber.glb"),
	"roots": preload("res://assets/3d/hideout_ruins/hanging_roots.glb"),
	"moss": preload("res://assets/3d/hideout_ruins/moss_clump.glb"),
	"spall": preload("res://assets/3d/hideout_ruins/ceiling_spall.glb"),
}
var _regions: Dictionary = {}
var _dressing: Dictionary = {}
var _serial := 0
var _roof_openings: Dictionary = {}
static var _overcast_clouds: NoiseTexture2D


static func apply_exploration_light(actor: DungeonPlayer) -> void:
	# The damp chapel has daylight through its broken roof. Keep the carried
	# flame local so its orange fill does not erase the grey/green masonry.
	actor.torch.light_color = Color(1.0, 0.80, 0.61)
	actor.torch.light_energy = 3.4
	actor.torch.set_meta("base_energy", 3.4)
	actor.torch_fill.light_color = Color(1.0, 0.68, 0.43)
	actor.torch_fill.light_energy = 1.3
	actor.torch_fill.set_meta("base_energy", 1.3)
	actor.torch_fill.omni_range = 5.2


func build(hideout: Node) -> void:
	_roof_openings = ROOF.build(hideout)
	CLOSURES.build(hideout)
	for id: String in hideout.region_nodes:
		var region: Node3D = hideout.region_nodes[id]
		MASONRY.weather_geometry(region)
		_weather_architecture(region)
		var dressing := Node3D.new()
		dressing.name = "RuinDressing_" + id
		region.add_child(dressing)
		_dressing[id] = dressing
		_regions[id] = {"prop_count": 0, "stain_count": 0, "leak_count": 0}
		var bounds: AABB = region.get_meta("streaming_bounds")
		_open_sky(id, bounds)
		var reflection := ReflectionProbe.new()
		reflection.name = "DampStoneReflections"
		reflection.position = bounds.get_center()
		reflection.origin_offset.y = 0.20 - bounds.get_center().y
		reflection.size = bounds.size
		reflection.interior = true
		reflection.box_projection = true
		reflection.max_distance = bounds.size.length()
		reflection.intensity = 1.2
		region.add_child(reflection)
	for water: MeshInstance3D in hideout.water_surfaces:
		water.material_override = MATERIALS.water_material()
	# Fractured silhouettes are authored in Blender. They occupy the margins;
	# the existing architectural physics and workstation interaction volumes
	# remain the authority for where the player can move and work.
	_central()
	_entrance()
	_sleeping_cell()
	_storage()
	_workshop()
	_flooded_store()
	_ossuary()
	_drain()
	for id: String in _dressing:
		var region: Node3D = hideout.region_nodes[id]
		var dressing: Node3D = _dressing[id]
		SCATTER.build(id, dressing, region.get_meta("streaming_bounds"))
		_regions[id]["scatter_count"] = int(dressing.get_meta("ruin_scatter_count", 0))


func _open_sky(id: String, bounds: AABB) -> void:
	# A recessed piece of the diffuse overcast sky, seen only through actual
	# gaps in the stone shell. It gives each aperture depth and a light source.
	# There is no texture of the generated room and no change to its physics.
	for opening: Dictionary in _roof_openings.get(id, []):
		var sky := MeshInstance3D.new()
		sky.name = "OvercastSkyAboveBrokenVault"
		var plane := PlaneMesh.new()
		plane.size = opening.size * 1.55
		sky.mesh = plane
		var center: Vector3 = opening.center
		sky.position = Vector3(center.x, minf(float(opening.top_y) + 0.46, bounds.end.y + 0.15), center.z)
		var sky_material := StandardMaterial3D.new()
		sky_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sky_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		sky_material.albedo_color = Color.WHITE
		sky_material.albedo_texture = _cloud_texture()
		sky_material.emission_enabled = true
		sky_material.emission = Color(0.17, 0.22, 0.23)
		sky.material_override = sky_material
		sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_dressing[id].add_child(sky)
		_fractured_roof_lip(id, opening)


static func _cloud_texture() -> NoiseTexture2D:
	if _overcast_clouds == null:
		var noise := FastNoiseLite.new()
		noise.seed = 2468
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.012
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.34, 0.40, 0.43))
		ramp.set_color(1, Color(0.67, 0.73, 0.74))
		_overcast_clouds = NoiseTexture2D.new()
		_overcast_clouds.width = 256
		_overcast_clouds.height = 256
		_overcast_clouds.seamless = true
		_overcast_clouds.generate_mipmaps = true
		_overcast_clouds.noise = noise
		_overcast_clouds.color_ramp = ramp
	return _overcast_clouds


func _fractured_roof_lip(id: String, opening: Dictionary) -> void:
	var concept := preload("res://scripts/dungeon_concept_visual.gd")
	var center: Vector3 = opening.center
	var size_value: Vector2 = opening.size
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for axis in 2:
		var span := size_value.x if axis == 0 else size_value.y
		var segments := maxi(3, ceili(span / 0.47))
		for side in [-1.0, 1.0]:
			for segment in segments:
				var seed_value := segment + axis * 11 + (7 if side > 0.0 else 0)
				var length_value := span / float(segments) * (1.08 + sin(float(seed_value) * 1.8) * 0.12)
				var intrusion := 0.20 + 0.15 * (0.5 + sin(float(seed_value) * 2.7) * 0.5)
				var piece_size := Vector3(length_value, 0.18 + float(seed_value % 3) * 0.07, intrusion * 2.0)
				var along := -span * 0.5 + (float(segment) + 0.5) * span / float(segments)
				var at := Vector3(along, -0.06 - float(seed_value % 3) * 0.035, side * (size_value.y * 0.5 + 0.015))
				if axis == 1:
					at = Vector3(side * (size_value.x * 0.5 + 0.015), at.y, along)
				var angles := Vector3(sin(float(seed_value)) * 0.16, (PI * 0.5 if axis == 1 else 0.0) + sin(float(seed_value) * 1.3) * 0.26, cos(float(seed_value)) * 0.14)
				surface.append_from(concept.chipped_block(piece_size, seed_value), 0, Transform3D(Basis.from_euler(angles), at))
				count += 1
	var mesh := MeshInstance3D.new()
	mesh.name = "JaggedExposedRoofMasonry"
	mesh.mesh = surface.commit()
	mesh.material_override = MATERIALS.weathered(concept.stone_material(2), "stone")
	mesh.position = Vector3(center.x, float(opening.underside_y) + 0.09, center.z)
	mesh.set_meta("ruin_fractured_rim_pieces", count)
	_dressing[id].add_child(mesh)


func get_validation_snapshot() -> Dictionary:
	return {"regions": _regions.duplicate(true), "roof_openings": _roof_openings.duplicate(true), "blender_kit": "res://assets/3d/hideout_ruins/"}


func _roof_fringe(id: String) -> void:
	# The Blender spall is a cluster of fallen sheets. Use thin strips around
	# the cut edge, never a complete cluster across the center of the opening.
	for opening: Dictionary in _roof_openings.get(id, []):
		var center: Vector3 = opening.center
		var size_value: Vector2 = opening.size
		for side in [-1.0, 1.0]:
			_prop(id, "spall", Vector3(center.x, float(opening.underside_y) + 0.12, center.z + side * (size_value.y * 0.5 + 0.06)), Vector3((size_value.x + 0.65) / 4.0, 0.7, 0.22), Vector3(0, 3.0 * side, 0))
			_prop(id, "spall", Vector3(center.x + side * (size_value.x * 0.5 + 0.07), float(opening.underside_y) + 0.12, center.z), Vector3((size_value.y + 0.55) / 4.0, 0.7, 0.18), Vector3(0, 90.0 + side * 3.0, 0))


func _weather_architecture(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D and child.mesh != null and child.visible:
			var mesh := child as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var family := str(source.get_meta("dark_fantasy_surface", ""))
				var kind := ""
				if family == "stone":
					kind = "floor" if str(root.get_meta("architecture_kind", "")) == "wet_flagstone_floor" else "stone"
				elif family == "oak":
					kind = "wood"
				if not kind.is_empty():
					var weathered := MATERIALS.weathered(source, kind)
					if mesh.material_override != null:
						mesh.material_override = weathered
					else:
						mesh.set_surface_override_material(surface, weathered)
		_weather_architecture(child)


func _prop(id: String, kind: String, at: Vector3, scale_value := Vector3.ONE, rotation_value := Vector3.ZERO) -> Node3D:
	var prop := (KIT[kind] as PackedScene).instantiate() as Node3D
	_serial += 1
	prop.name = "Blender_%s_%03d" % [kind, _serial]
	prop.set_meta("ruin_prop", kind)
	prop.position = at
	prop.scale = scale_value
	if kind == "moss":
		# The exported fronds represent close detail. Keep them at moss scale
		# while the irregular surface growth supplies the larger damp patches.
		prop.scale *= Vector3(0.35, 0.55, 0.35)
	prop.rotation_degrees = rotation_value
	_dressing[id].add_child(prop)
	for mesh: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 46.0
		mesh.visibility_range_end_margin = 4.0
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(surface)
			var slot := original.resource_name if original != null else "ruin_stone"
			mesh.set_surface_override_material(surface, MATERIALS.ruin_material(slot))
	_regions[id].prop_count += 1
	return prop


func _stain(id: String, kind: String, at: Vector3, size_value: Vector2, yaw := 0.0, floor_patch := false) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Seepage_%s_%d" % [kind, _serial]
	_serial += 1
	if floor_patch:
		var plane := PlaneMesh.new()
		plane.size = size_value
		mesh.mesh = plane
	else:
		var quad := QuadMesh.new()
		quad.size = size_value
		mesh.mesh = quad
	mesh.position = at
	mesh.rotation_degrees.y = yaw
	mesh.material_override = MATERIALS.stain_material(kind)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dressing[id].add_child(mesh)
	_regions[id].stain_count += 1


func _pool(id: String, at: Vector3, size_value: Vector2, ripple := false) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "DripImpactRipples" if ripple else "IrregularSeepagePool"
	var plane := PlaneMesh.new()
	plane.size = size_value
	mesh.mesh = plane
	mesh.position = at
	mesh.material_override = MATERIALS.ripple_material() if ripple else MATERIALS.water_material()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dressing[id].add_child(mesh)


func _leak(id: String, at: Vector3, width := 0.32, pool_size := Vector2(2.4, 2.0), intensity := 1.8) -> void:
	var drips := CPUParticles3D.new()
	drips.name = "RuinLeak_" + id + "_" + str(_regions[id].leak_count)
	drips.set_meta("ruin_leak", true)
	drips.position = at
	drips.amount = 32 if id == "flooded_store" else 22
	drips.lifetime = sqrt(2.0 * maxf(at.y - 0.08, 0.1) / 6.0)
	drips.preprocess = drips.lifetime
	drips.randomness = 0.7
	drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drips.emission_box_extents = Vector3(width, 0.01, width * 0.32)
	drips.direction = Vector3.DOWN
	drips.spread = 1.0
	drips.gravity = Vector3(0, -6.0, 0)
	drips.initial_velocity_min = 0.0
	drips.initial_velocity_max = 0.15
	drips.scale_amount_min = 0.65
	drips.scale_amount_max = 1.15
	var droplet := SphereMesh.new()
	droplet.radius = 0.009
	droplet.height = 0.085
	droplet.radial_segments = 6
	droplet.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.66, 0.69, 0.66, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic_specular = 0.9
	material.emission_enabled = true
	material.emission = Color(0.21, 0.23, 0.21)
	droplet.material = material
	drips.mesh = droplet
	_dressing[id].add_child(drips)
	_regions[id].leak_count += 1
	_pool(id, Vector3(at.x, 0.058, at.z), pool_size)
	_pool(id, Vector3(at.x, 0.067, at.z), Vector2.ONE * 1.05, true)
	_pool(id, Vector3(at.x - width * 0.65, 0.068, at.z + width * 0.45), Vector2.ONE * 0.64, true)
	var light := OmniLight3D.new()
	light.name = "ColdLightThroughRupture"
	light.position = at - Vector3(0, 0.25, 0)
	light.light_color = Color(0.62, 0.70, 0.69)
	light.light_energy = intensity
	light.light_specular = 0.65
	light.omni_range = 8.0 if id == "central" else 6.2
	light.omni_attenuation = 0.62
	light.shadow_enabled = false
	_dressing[id].add_child(light)


func _central() -> void:
	# Detached curved runs and slumped piles replace the two upright, regular
	# block towers. Keep the hearth causeway and transverse crossing clear.
	_prop("central", "arch", Vector3(-6.1, 0.14, 0.55), Vector3(0.80, 1.12, 1.0), Vector3(3, 68, 9))
	_prop("central", "arch", Vector3(5.75, 0.17, -0.8), Vector3(0.76, 1.25, 0.95), Vector3(-4, -28, -11))
	_prop("central", "rubble", Vector3(-6.25, 0.05, 2.9), Vector3(1.05, 1.03, 0.88), Vector3(0, 25, 4))
	_prop("central", "rubble", Vector3(6.1, 0.08, 2.75), Vector3(0.97, 1.18, 0.92), Vector3(0, -29, -6))
	_prop("central", "rubble", Vector3(-6.65, 0.03, -1.9), Vector3(0.74, 0.88, 0.72), Vector3(0, 63, 0))
	_prop("central", "rubble", Vector3(6.35, 0.04, -2.4), Vector3(0.76, 1.0, 0.72), Vector3(0, -18, 0))
	_prop("central", "edge", Vector3(6.7, 0.17, -0.75), Vector3(0.68, 0.62, 0.68), Vector3(0, -90, 23))
	for side in [-1.0, 1.0]:
		_prop("central", "moss", Vector3(side * 5.45, 0.03, 2.4), Vector3(1.8, 1.0, 1.8), Vector3(0, side * 19, 0))
		_stain("central", "leak", Vector3(side * 7.97, 2.75, -0.6), Vector2(4.0, 4.4), -side * 90)
		_stain("central", "moss", Vector3(side * 7.95, 0.7, 0.4), Vector2(5.5, 1.45), -side * 90)
	for opening: Dictionary in _roof_openings.get("central", []):
		var center: Vector3 = opening.center
		var size: Vector2 = opening.size
		var ceiling_y := float(opening.underside_y) + 0.12
		# The Blender spall is a filled patch. Four narrow edge placements
		# produce broken lips around the opening without capping its center.
		for side in [-1.0, 1.0]:
			_prop("central", "spall", Vector3(center.x, ceiling_y, center.z + side * size.y * 0.5), Vector3(size.x * 0.29, 1.10, 0.19), Vector3(side * 8, side * 5, -side * 4))
			_prop("central", "spall", Vector3(center.x + side * size.x * 0.5, ceiling_y - 0.035, center.z), Vector3(size.y * 0.28, 0.9, 0.17), Vector3(side * 6, 90 + side * 7, side * 3))
		_prop("central", "roots", Vector3(center.x - 0.22, ceiling_y - 0.12, center.z + size.y * 0.42), Vector3(size.x * 0.30, 1.02, 0.9), Vector3(2, 13, 6))
		_prop("central", "roots", Vector3(center.x + size.x * 0.40, ceiling_y - 0.10, center.z - 0.12), Vector3(size.y * 0.23, 0.68, 0.85), Vector3(-4, 91, -7))
		_leak("central", Vector3(center.x, float(opening.underside_y) - 0.22, center.z), 0.48, Vector2(3.2, 3.7), 2.7)
	_prop("central", "timber", Vector3(-6.3, 0.36, 1.4), Vector3(0.89, 0.9, 0.9), Vector3(9, 64, -10))
	_prop("central", "timber", Vector3(6.05, 0.32, 1.9), Vector3(0.71, 0.9, 0.85), Vector3(-8, -37, 13))


func _entrance() -> void:
	_prop("entrance", "edge", Vector3(3.55, 0.02, 17.0), Vector3(0.64, 0.94, 0.7), Vector3(0, -90, 0))
	_prop("entrance", "rubble", Vector3(2.8, 0.01, 18.0), Vector3(0.65, 0.8, 0.9), Vector3(0, 90, 0))
	_prop("entrance", "rubble", Vector3(-2.75, 0.01, 18.8), Vector3(0.62, 0.65, 0.7))
	_prop("entrance", "timber", Vector3(2.8, 1.5, 16.7), Vector3(0.85, 1, 1), Vector3(0, 0, 66))
	_roof_fringe("entrance")
	_prop("entrance", "roots", Vector3(2.2, 4.18, 17.0), Vector3(0.75, 0.58, 0.9))
	_prop("entrance", "moss", Vector3(2.9, 0.03, 15.5), Vector3(1.1, 1, 1.4))
	_stain("entrance", "leak", Vector3(3.97, 2.35, 17.1), Vector2(4.7, 3.65), -90)
	_stain("entrance", "mold", Vector3(-3.96, 1.1, 18.4), Vector2(3.0, 2.1), 90)
	_leak("entrance", Vector3(2.15, 4.0, 17.2), 0.3, Vector2(2.4, 3.0), 2.2)


func _sleeping_cell() -> void:
	_roof_fringe("sleep")
	_prop("sleep", "roots", Vector3(-13.8, 4.12, 8.05), Vector3(0.6, 0.5, 0.8))
	_prop("sleep", "rubble", Vector3(-14.5, 0.01, 8.3), Vector3(0.5, 0.5, 0.45))
	_prop("sleep", "moss", Vector3(-14.2, 0.02, 5.1), Vector3(0.8, 0.7, 0.8))
	_stain("sleep", "mold", Vector3(-14.98, 2.8, 7.6), Vector2(2.4, 2.5), 90)
	_stain("sleep", "leak", Vector3(-13.7, 2.2, 8.99), Vector2(2.5, 3.7), 180)
	_stain("sleep", "salt", Vector3(-14.97, 0.8, 5.0), Vector2(3.1, 1.25), 90)
	_leak("sleep", Vector3(-14.4, 3.98, 8.2), 0.13, Vector2(1.6, 1.1), 1.5)
	# A second small drip has a practical catch bucket beside the wash basin.
	_leak("sleep", Vector3(-9.15, 3.98, 2.7), 0.06, Vector2(0.65, 0.65), 0.4)


func _storage() -> void:
	_prop("storage", "edge", Vector3(14.6, 0.01, 7.8), Vector3(0.6, 0.97, 0.55), Vector3(0, -90, 0))
	_prop("storage", "rubble", Vector3(13.5, 0.02, 7.7), Vector3(0.8, 1.2, 0.75), Vector3(0, -18, 0))
	_prop("storage", "timber", Vector3(13.45, 1.45, 7.1), Vector3(0.9, 1, 1), Vector3(8, 24, 61))
	_roof_fringe("storage")
	_prop("storage", "roots", Vector3(13.8, 4.15, 7.85), Vector3(0.7, 0.7, 0.7))
	_prop("storage", "moss", Vector3(12.6, 0.02, 6.9), Vector3(1.6, 1, 1.4))
	_stain("storage", "leak", Vector3(14.98, 2.2, 7.1), Vector2(3.2, 3.6), -90)
	_stain("storage", "mold", Vector3(12.5, 1.0, 8.98), Vector2(4.3, 1.8), 180)
	_leak("storage", Vector3(13.1, 3.98, 7.2), 0.38, Vector2(3.1, 2.8), 2.1)


func _workshop() -> void:
	_prop("workshop", "rubble", Vector3(14.4, 0.01, -7.3), Vector3(0.65, 0.65, 0.65))
	_prop("workshop", "timber", Vector3(14.2, 0.9, -7.7), Vector3(0.7, 0.85, 0.8), Vector3(0, 10, 35))
	_roof_fringe("workshop")
	_prop("workshop", "roots", Vector3(14.5, 4.14, -3.1), Vector3(0.55, 0.45, 0.8))
	_prop("workshop", "moss", Vector3(15.1, 0.02, -6.8), Vector3(0.9, 0.8, 1.0))
	_stain("workshop", "soot", Vector3(11.0, 2.7, -7.98), Vector2(4.0, 2.65))
	_stain("workshop", "mold", Vector3(14.1, 1.3, -7.97), Vector2(2.3, 2.5))
	_stain("workshop", "leak", Vector3(14.65, 2.3, -2.02), Vector2(2.15, 3.4), 180)
	_leak("workshop", Vector3(14.7, 4.0, -3.5), 0.21, Vector2(1.5, 1.6), 1.8)


func _flooded_store() -> void:
	_prop("flooded_store", "edge", Vector3(-14.3, 0.02, -7.35), Vector3(0.64, 1.17, 0.68))
	_prop("flooded_store", "rubble", Vector3(-13.0, 0.02, -7.0), Vector3(1.0, 1.45, 0.85), Vector3(0, 12, 0))
	_roof_fringe("flooded_store")
	_prop("flooded_store", "roots", Vector3(-12.65, 4.12, -6.8), Vector3(0.95, 0.9, 1.0))
	_prop("flooded_store", "moss", Vector3(-12.6, 0.06, -6.1), Vector3(1.7, 1.35, 1.5))
	_prop("flooded_store", "moss", Vector3(-14.5, 0.04, -3.2), Vector3(1.0, 1.0, 1.7))
	_stain("flooded_store", "moss", Vector3(-14.98, 0.9, -5.0), Vector2(5.3, 1.8), 90)
	_stain("flooded_store", "leak", Vector3(-12.4, 2.2, -7.98), Vector2(4.8, 3.8))
	_stain("flooded_store", "mold", Vector3(-14.97, 2.6, -6.8), Vector2(2.0, 2.6), 90)
	_stain("flooded_store", "salt", Vector3(-14.95, 1.5, -4.9), Vector2(5.2, 0.8), 90)
	_leak("flooded_store", Vector3(-12.4, 3.97, -6.5), 0.52, Vector2(4.4, 3.9), 2.8)


func _ossuary() -> void:
	_prop("ossuary", "edge", Vector3(4.6, 0.01, -20.5), Vector3(0.8, 1.22, 0.9), Vector3(0, -45, 0))
	_prop("ossuary", "rubble", Vector3(3.6, 0.01, -20.3), Vector3(1.1, 1.5, 1.1), Vector3(0, 15, 0))
	_prop("ossuary", "rubble", Vector3(-4.3, 0.01, -18.8), Vector3(0.85, 0.7, 0.95))
	_roof_fringe("ossuary")
	_prop("ossuary", "roots", Vector3(3.5, 4.47, -19.3), Vector3(1.0, 0.8, 0.8))
	_prop("ossuary", "moss", Vector3(3.8, 0.03, -18.5), Vector3(1.7, 1.1, 1.3))
	_stain("ossuary", "leak", Vector3(3.4, 2.4, -21.98), Vector2(4.3, 4.0))
	_stain("ossuary", "mold", Vector3(-3.5, 1.05, -21.97), Vector2(4.0, 1.9))
	_leak("ossuary", Vector3(3.1, 4.3, -19.1), 0.46, Vector2(3.7, 3.4), 2.4)


func _drain() -> void:
	# The original sealed collision remains at x=24.6. A recessed dark fill,
	# surviving pointed arch and deep overlapping debris replace the visible
	# plain rectangle with an unmistakably collapsed, impassable tunnel end.
	var concept := preload("res://scripts/dungeon_concept_visual.gd")
	var portal := Node3D.new()
	portal.name = "FracturedBlockedDrainArch"
	portal.position = Vector3(23.95, 0.02, -5.0)
	portal.rotation_degrees.y = 90.0
	portal.set_meta("pointed_arch_masonry", true)
	portal.set_meta("ruin_prop", "blocked_drain_arch")
	_dressing["drain"].add_child(portal)
	concept.add_pointed_ring(portal, Vector3(0, 1.17, 0), 1.10, 1.42, 0.30, 0.46)
	for side in [-1.0, 1.0]:
		for row in 3:
			var jamb := MeshInstance3D.new()
			jamb.name = "BrokenDrainJamb_%s_%d" % [str(side), row]
			jamb.mesh = concept.chipped_block(Vector3(0.37, 0.405, 0.48), row + 2)
			jamb.position = Vector3(side * (1.14 + float(row % 2) * 0.035), 0.20 + row * 0.385, 0.0)
			jamb.rotation_degrees.z = side * float(row - 1) * 2.5
			portal.add_child(jamb)
	for mesh: MeshInstance3D in portal.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = MATERIALS.weathered(concept.stone_material(1), "stone")
		mesh.visibility_range_end = 32.0
	# Fill the upper corners and shoulders around the surviving arch. The
	# dark recess should describe the pointed tunnel opening, not a rectangle
	# pasted across the end wall. Merge all chipped blocks into one draw mesh.
	var spandrel_surface := SurfaceTool.new()
	spandrel_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 8:
		var row_y := 0.21 + float(row) * 0.42
		var void_half_width := 0.96
		if row_y > 1.17:
			var normalized_height := clampf((row_y - 1.17) / 1.42, 0.0, 1.0)
			var curve_t := clampf((1.3 - sqrt(maxf(1.69 - 1.2 * normalized_height, 0.0))) / 0.6, 0.0, 1.0)
			void_half_width = maxf(0.0, 1.10 * (1.0 - curve_t) * (1.0 + 0.70 * curve_t) - 0.12)
		var side_width := 1.68 - void_half_width
		var columns := maxi(1, ceili(side_width / 0.53))
		var width := side_width / float(columns)
		for side in [-1.0, 1.0]:
			for column in columns:
				var stone_size := Vector3(width - 0.012, 0.412, 0.28)
				var x: float = side * (void_half_width + (float(column) + 0.5) * width)
				var at := Vector3(x, row_y, 0.10 + sin(float(row * 5 + column * 2)) * 0.012)
				spandrel_surface.append_from(concept.chipped_block(stone_size, row + column), 0, Transform3D(Basis.IDENTITY, at))
	var spandrels := MeshInstance3D.new()
	spandrels.name = "BrokenDrainSpandrelMasonry"
	spandrels.mesh = spandrel_surface.commit()
	spandrels.material_override = MATERIALS.weathered(concept.stone_material(1), "stone")
	spandrels.visibility_range_end = 32.0
	spandrels.set_meta("ruin_arch_spandrels", true)
	portal.add_child(spandrels)
	_regions["drain"].prop_count += 1
	var recess := MeshInstance3D.new()
	recess.name = "SoilInCollapsedDrain"
	var recess_mesh := BoxMesh.new()
	recess_mesh.size = Vector3(0.06, 3.35, 3.35)
	recess.mesh = recess_mesh
	recess.position = Vector3(24.17, 1.665, -5.0)
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.012, 0.016, 0.013)
	soil.roughness = 1.0
	soil.metallic_specular = 0.08
	recess.material_override = soil
	_dressing["drain"].add_child(recess)
	_prop("drain", "edge", Vector3(24.04, 0.05, -6.18), Vector3(0.24, 0.82, 0.35), Vector3(0, 90, -8))
	_prop("drain", "edge", Vector3(24.06, 0.05, -3.92), Vector3(0.26, 0.84, 0.32), Vector3(0, -90, 11))
	_prop("drain", "rubble", Vector3(24.0, 2.38, -5.0), Vector3(0.66, 0.68, 0.46), Vector3(0, 90, 5))
	_prop("drain", "rubble", Vector3(23.60, 0.11, -5.1), Vector3(0.75, 1.5, 0.72), Vector3(0, 90, 8))
	_prop("drain", "rubble", Vector3(23.88, 0.75, -5.45), Vector3(0.62, 1.25, 0.55), Vector3(0, 90, -16))
	_prop("drain", "arch", Vector3(22.95, 0.04, -5.0), Vector3(0.58, 1.3, 0.54), Vector3(0, 90, 0))
	_prop("drain", "timber", Vector3(23.49, 1.62, -5.2), Vector3(0.63, 0.8, 0.65), Vector3(0, 90, 43))
	_prop("drain", "timber", Vector3(23.76, 1.02, -4.75), Vector3(0.57, 0.7, 0.65), Vector3(0, 90, -31))
	for side in [-1.0, 1.0]:
		_prop("drain", "spall", Vector3(21.5, 3.45, -5.0 + side * 0.45), Vector3(0.49, 0.78, 0.15), Vector3(side * 8, side * 7, -side * 6))
	_prop("drain", "roots", Vector3(21.65, 3.31, -5.22), Vector3(0.7, 0.53, 0.8), Vector3(0, 74, -8))
	_prop("drain", "moss", Vector3(21.0, 0.02, -6.2), Vector3(1.2, 1, 0.65))
	_stain("drain", "leak", Vector3(21.5, 1.8, -6.68), Vector2(4.5, 2.85))
	_stain("drain", "moss", Vector3(21.5, 0.7, -3.32), Vector2(5.0, 1.3), 180)
	_leak("drain", Vector3(21.6, 3.12, -5.0), 0.25, Vector2(2.5, 2.3), 1.2)
