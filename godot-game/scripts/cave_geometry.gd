extends Node3D
## Authored Blender geometry and photographed PBR, never the old primitive cave.
const LAYOUT := preload("res://scripts/cave_layout.gd")
const MODEL_PATH := "res://assets/3d/abandoned_mine/abandoned_mine.glb"
const MANIFEST_PATH := "res://assets/3d/abandoned_mine/build_manifest.json"
const SAMPLE_PATH := "res://assets/3d/abandoned_mine/terrain_samples.bin"
const ART_DIRECTION := preload("res://scripts/cave_art_direction.gd")
const WATER_SYSTEM := preload("res://scripts/cave_water.gd")
var art_details: Node3D
var art_lighting: Node3D
var water_system: Node3D
var torch_lights: Array[OmniLight3D] = []
var blender_mine: Node3D
var _built := false
var _clock := 0.0
var _build_info: Dictionary = {}
var _sample_width := 0
var _sample_depth := 0
var _origin := Vector2.ZERO
var _spacing := Vector2.ONE
var _floors := PackedFloat32Array()
var _ceilings := PackedFloat32Array()
var _distances := PackedFloat32Array()
var _collision_shapes: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "CaveGeometry"
	set_meta("footprint_metres", Vector2(LAYOUT.WIDTH, LAYOUT.DEPTH))
	set_meta("asset_pipeline", "Blender sculpt / photographed PBR / abandoned mining equipment")
	_read_samples()
	var packed := load(MODEL_PATH) as PackedScene
	assert(packed != null, "The authored Blender mine GLB must be imported before play")
	if packed == null:
		return
	blender_mine = packed.instantiate() as Node3D
	blender_mine.name = "BlenderMine"
	add_child(blender_mine)
	_configure_import(blender_mine)
	ART_DIRECTION.apply_materials(blender_mine)
	water_system = WATER_SYSTEM.new()
	water_system.name = "CaveWater"
	add_child(water_system)
	water_system.build(self)
	_collision_shapes.clear()
	_add_survey_base()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(parsed is Dictionary, "The Blender mine build manifest must be present")
	if parsed is Dictionary:
		_build_info = parsed
		for entry: Dictionary in _build_info.get("lights", []):
			_add_lantern_light(entry)
	art_details = preload("res://scripts/cave_art_details.gd").new()
	add_child(art_details)
	art_details.build(self)
	art_lighting = preload("res://scripts/cave_art_lighting.gd").new()
	art_lighting.name = "CaveArtLighting"
	add_child(art_lighting)
	art_lighting.build(self)
	for room: Dictionary in LAYOUT.rooms():
		var marker := Marker3D.new()
		marker.name = "Chamber_" + str(room.id)
		marker.position = LAYOUT.room_position(room.id)
		marker.set_meta("title", room.title)
		add_child(marker)

func _configure_import(node: Node) -> void:
	if node is MeshInstance3D:
		var visual := node as MeshInstance3D
		var label := str(visual.name)
		# The flame sits inside a small open cage. Avoid magnifying its thin
		# bars into giant point-light silhouettes; the wooden stake still casts.
		if label.contains("_supported_oil_lantern_") and not label.contains("AgedOak"):
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if label.begins_with("collision_") or bool(visual.get_meta("collision_only", false)):
			visual.hide()
			_attach_box_collision(visual)
		elif label.begins_with("Terrain_") or label.begins_with("RockScan_") or label.begins_with("RockFormation_") or label.begins_with("GiantBeast_"):
			_attach_surface_collision(visual)
		elif label.begins_with("Water_"):
			# Retain the source asset; the live water uses the same six footprints.
			visual.hide()
		# Preserve the exported photographic albedo, normal, roughness and UVs.
		if visual.mesh:
			for surface_index in range(visual.mesh.get_surface_count()):
				var material := visual.get_active_material(surface_index)
				if material is BaseMaterial3D:
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if material.resource_name.begins_with("Mine_Continuous_"):
						# A shared glTF material can first appear on a white-tint chunk.
						# Retain COLOR_0 on every chunk, including its colored neighbors.
						material.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_configure_import(child)

func _attach_surface_collision(visual: MeshInstance3D) -> void:
	if visual.mesh == null:
		return
	var key := visual.mesh.get_instance_id()
	if not _collision_shapes.has(key):
		var shape := visual.mesh.create_trimesh_shape()
		shape.backface_collision = true
		_collision_shapes[key] = shape
	var body := StaticBody3D.new()
	body.name = "Collision_" + str(visual.name)
	body.collision_layer = 2
	body.collision_mask = 5
	add_child(body)
	body.global_transform = visual.global_transform
	var collider := CollisionShape3D.new()
	collider.shape = _collision_shapes[key]
	body.add_child(collider)

func _attach_box_collision(visual: MeshInstance3D) -> void:
	if visual.mesh == null:
		return
	var box := visual.mesh.get_aabb()
	var body := StaticBody3D.new()
	body.name = "Proxy_" + str(visual.name)
	body.collision_layer = 2
	body.collision_mask = 5
	add_child(body)
	body.global_transform = visual.global_transform
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.position = box.get_center()
	collider.shape = shape
	body.add_child(collider)

func _add_survey_base() -> void:
	var base := StaticBody3D.new()
	base.name = "DungeonFootprint"
	base.position.y = -1.2
	base.collision_layer = 2
	base.collision_mask = 5
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(LAYOUT.WIDTH, 0.4, LAYOUT.DEPTH)
	collision.shape = shape
	base.add_child(collision)
	add_child(base)

func _add_lantern_light(entry: Dictionary) -> void:
	var light := OmniLight3D.new()
	light.name = "MineLanternLight_%02d" % torch_lights.size()
	var position_data: Array = entry.position
	light.position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	light.light_color = Color(1.0, 0.73, 0.40)
	light.light_energy = float(entry.energy) * 1.35
	light.set_meta("base_energy", light.light_energy)
	light.omni_range = float(entry.range)
	light.omni_attenuation = 1.6
	light.shadow_enabled = true
	light.light_size = 0.08
	light.light_volumetric_fog_energy = 0.22
	light.shadow_blur = 1.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 10.0
	preload("res://scripts/cave_light_budget.gd").configure(light)
	add_child(light)
	torch_lights.append(light)

func _process(delta: float) -> void:
	_clock += delta
	var camera := get_viewport().get_camera_3d()
	for i in range(torch_lights.size()):
		var light := torch_lights[i]
		if preload("res://scripts/cave_light_budget.gd").needs_flicker_update(light, camera):
			light.light_energy = preload("res://scripts/cave_light_budget.gd").flicker_energy(float(light.get_meta("base_energy")), _clock, i)

func _read_samples() -> void:
	var file := FileAccess.open(SAMPLE_PATH, FileAccess.READ)
	assert(file != null, "The Blender terrain measurement file must exist")
	if file == null:
		return
	_sample_width = file.get_32()
	_sample_depth = file.get_32()
	_origin = Vector2(file.get_float(), file.get_float())
	_spacing = Vector2(file.get_float(), file.get_float())
	var byte_count := _sample_width * _sample_depth * 4
	_floors = file.get_buffer(byte_count).to_float32_array()
	_ceilings = file.get_buffer(byte_count).to_float32_array()
	_distances = file.get_buffer(byte_count).to_float32_array()

func _sample(values: PackedFloat32Array, point: Vector2, fallback: float) -> float:
	if values.is_empty() or _sample_width < 2:
		return fallback
	var x := clampi(roundi((point.x - _origin.x) / _spacing.x), 0, _sample_width - 1)
	var z := clampi(roundi((point.y - _origin.y) / _spacing.y), 0, _sample_depth - 1)
	return values[z * _sample_width + x]

func signed_distance(point: Vector2) -> float:
	return -_sample(_distances, point, -100.0)

func floor_height(point: Vector2) -> float:
	return _sample(_floors, point, 0.0)

func ceiling_height(point: Vector2) -> float:
	return _sample(_ceilings, point, 4.0)

func get_build_info() -> Dictionary:
	return _build_info.duplicate(true)
