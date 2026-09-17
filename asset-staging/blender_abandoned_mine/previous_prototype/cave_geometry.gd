extends Node3D
## Continuous, closed rock shell carved from a connected chamber/corridor field.
## Visual shell and collision use the same vertices; no invisible box corridors.

const LAYOUT := preload("res://scripts/cave_layout.gd")
const ROCK_SHADER := preload("res://assets/cave_rock.gdshader")
const FLOOR_TEXTURE := preload("res://assets/ai/materials/wet_flagstone.png")
const OAK_TEXTURE := preload("res://assets/ai/materials/ancient_oak.png")
const WALL_TEXTURE := preload("res://assets/ai/materials/ossuary_wall.png")
const FLAME_TEXTURE := preload("res://assets/ai/vfx/torch_flame.png")
const TORCH_SCENE := preload("res://assets/3d/dark_fantasy/iron_cage_torch.glb")
const GRID_X := 88
const GRID_Z := 94

var chamber_data: Array[Dictionary] = LAYOUT.rooms()
var passage_data: Array[Dictionary] = LAYOUT.corridors()
var torch_lights: Array[OmniLight3D] = []
var rock: ShaderMaterial
var wet_rock: ShaderMaterial
var stone: StandardMaterial3D
var wood: StandardMaterial3D
var iron: StandardMaterial3D
var cloth: StandardMaterial3D
var bone: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _built := false
var _clock := 0.0
var _segments: Array[Dictionary] = []
var _wall_normals: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "CaveGeometry"
	set_meta("footprint_metres", Vector2(LAYOUT.WIDTH, LAYOUT.DEPTH))
	_rng.seed = LAYOUT.SEED
	_noise.seed = LAYOUT.SEED
	_noise.frequency = 0.24
	_noise.fractal_octaves = 3
	for passage in passage_data:
		var points := LAYOUT.corridor_points(passage)
		for i in range(points.size() - 1):
			_segments.append({"a": points[i], "b": points[i + 1], "radius": passage.width * 0.5})
	_materials()
	_carve_shell()
	_dress_chambers()
	_dress_passages()

func _process(delta: float) -> void:
	_clock += delta
	for index in range(torch_lights.size()):
		var light := torch_lights[index]
		light.light_energy = float(light.get_meta("base_energy")) * (0.95 + sin(_clock * 7.1 + index * 2.3) * 0.035 + sin(_clock * 11.7 + index) * 0.025)

func _materials() -> void:
	rock = ShaderMaterial.new()
	rock.shader = ROCK_SHADER
	wet_rock = rock.duplicate() as ShaderMaterial
	wet_rock.set_shader_parameter("wetness", 0.85)
	wet_rock.set_shader_parameter("rock_dark", Color(0.065, 0.073, 0.06))
	stone = _material(Color(0.42, 0.39, 0.33), 0.86, WALL_TEXTURE)
	wood = _material(Color(0.36, 0.25, 0.14), 0.94, OAK_TEXTURE)
	iron = _material(Color(0.075, 0.065, 0.047), 0.63)
	iron.metallic = 0.7
	cloth = _material(Color(0.21, 0.025, 0.019), 0.95)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	bone = _material(Color(0.51, 0.44, 0.30), 0.88)

func _material(color: Color, roughness: float, texture: Texture2D = null) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	if texture:
		result.albedo_texture = texture
		result.uv1_triplanar = true
		result.uv1_world_triplanar = true
		result.uv1_scale = Vector3.ONE * 0.5
		result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return result

func signed_distance(point: Vector2) -> float:
	var distance := 1000.0
	for room in chamber_data:
		var relative: Vector2 = (point - room.center) / room.radii
		distance = minf(distance, (relative.length() - 1.0) * minf(room.radii.x, room.radii.y))
	for segment in _segments:
		var axis: Vector2 = segment.b - segment.a
		var fraction := clampf((point - segment.a).dot(axis) / axis.length_squared(), 0.0, 1.0)
		distance = minf(distance, point.distance_to(segment.a + axis * fraction) - segment.radius)
	return distance + _noise.get_noise_2d(point.x, point.y) * 1.0

func ceiling_height(point: Vector2) -> float:
	var height := 4.5
	for room in chamber_data:
		var relative: Vector2 = (point - room.center) / room.radii
		var weight := smoothstep(1.15, 0.0, relative.length())
		height = maxf(height, lerpf(4.5, room.height, weight))
	return height + _noise.get_noise_2d(point.x + 137, point.y) * 0.85

func floor_height(point: Vector2) -> float:
	return _noise.get_noise_2d(point.x * 0.65, point.y * 0.65) * 0.075

func _carve_shell() -> void:
	var floor_surface := SurfaceTool.new()
	var roof_surface := SurfaceTool.new()
	var wall_surface := SurfaceTool.new()
	for surface in [floor_surface, roof_surface, wall_surface]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dx := LAYOUT.WIDTH / GRID_X
	var dz := LAYOUT.DEPTH / GRID_Z
	var samples := PackedFloat32Array()
	samples.resize((GRID_X + 1) * (GRID_Z + 1))
	for z in range(GRID_Z + 1):
		for x in range(GRID_X + 1):
			samples[z * (GRID_X + 1) + x] = signed_distance(Vector2(-LAYOUT.WIDTH * 0.5 + x * dx, -LAYOUT.DEPTH * 0.5 + z * dz))
	for z in range(GRID_Z):
		for x in range(GRID_X):
			var p := Vector2(-LAYOUT.WIDTH * 0.5 + x * dx, -LAYOUT.DEPTH * 0.5 + z * dz)
			var corners: Array[Vector2] = [p, p + Vector2(dx, 0), p + Vector2(dx, dz), p + Vector2(0, dz)]
			var indices := [z * (GRID_X + 1) + x, z * (GRID_X + 1) + x + 1, (z + 1) * (GRID_X + 1) + x + 1, (z + 1) * (GRID_X + 1) + x]
			for triangle in [[0, 1, 2], [0, 2, 3]]:
				var polygon: Array[Vector2] = []
				var boundary: Array[Vector2] = []
				for j in range(3):
					var a: int = triangle[j]
					var b: int = triangle[(j + 1) % 3]
					var da: float = samples[indices[a]]
					var db: float = samples[indices[b]]
					if da <= 0:
						polygon.append(corners[a])
					if (da <= 0) != (db <= 0):
						var edge: Vector2 = corners[a].lerp(corners[b], da / (da - db))
						polygon.append(edge)
						boundary.append(edge)
				for j in range(1, polygon.size() - 1):
					var a := polygon[0]
					var b := polygon[j]
					var c := polygon[j + 1]
					_tri(floor_surface, _floor(a), _floor(b), _floor(c))
					_tri(roof_surface, _roof(c), _roof(b), _roof(a))
				if boundary.size() == 2:
					_wall_strip(wall_surface, boundary[0], boundary[1])
	_finish_surface(floor_surface, "CavernFloor", wet_rock)
	_finish_surface(roof_surface, "CavernCeiling", rock)
	_finish_surface(wall_surface, "CarvedRockWalls", rock)
	# Exact surveyed footprint. The slab is below the rough traversable floor.
	_box("DungeonFootprint", Vector3(0, -0.7, 0), Vector3(LAYOUT.WIDTH, 1, LAYOUT.DEPTH), rock, true)

func _floor(point: Vector2) -> Vector3:
	return Vector3(point.x, floor_height(point), point.y)

func _roof(point: Vector2) -> Vector3:
	return Vector3(point.x, ceiling_height(point), point.y)

func _wall_strip(surface: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var outward := Vector2(-(b - a).y, (b - a).x).normalized()
	if signed_distance((a + b) * 0.5 + outward * 0.15) < 0:
		outward = -outward
	for level in range(6):
		var t0 := float(level) / 6.0
		var t1 := float(level + 1) / 6.0
		var v0 := _wall_vertex(a, outward, t0)
		var v1 := _wall_vertex(b, outward, t0)
		var v2 := _wall_vertex(b, outward, t1)
		var v3 := _wall_vertex(a, outward, t1)
		# Orient both geometry and normals toward the playable cavity.
		var normal := (v2 - v0).cross(v1 - v0).normalized()
		if normal.dot(Vector3(outward.x, 0, outward.y)) < 0:
			_tri(surface, v0, v1, v2)
			_tri(surface, v0, v2, v3)
		else:
			_tri(surface, v2, v1, v0)
			_tri(surface, v3, v2, v0)

func _wall_vertex(point: Vector2, outward: Vector2, amount: float) -> Vector3:
	# Adjacent triangles share this direction so their displaced rock edges seal.
	var key := point.snapped(Vector2.ONE * 0.0001)
	if not _wall_normals.has(key):
		var gradient := Vector2(signed_distance(point + Vector2(0.1, 0)) - signed_distance(point - Vector2(0.1, 0)), signed_distance(point + Vector2(0, 0.1)) - signed_distance(point - Vector2(0, 0.1)))
		_wall_normals[key] = gradient.normalized() if gradient.length_squared() > 0.00001 else outward
	outward = _wall_normals[key]
	var y := lerpf(floor_height(point), ceiling_height(point), amount)
	var swell := sin(amount * PI) * (0.35 + _noise.get_noise_3d(point.x, y * 1.3, point.y) * 0.6)
	var offset := point + outward * swell
	return Vector3(offset.x, y, offset.y)

func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func _finish_surface(surface: SurfaceTool, label: String, material: Material) -> void:
	surface.index()
	surface.generate_normals()
	var mesh := surface.commit()
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 2
	body.collision_mask = 5
	add_child(body)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	collision.shape = shape
	body.add_child(collision)

func _dress_chambers() -> void:
	for room in chamber_data:
		var center := Vector3(room.center.x, 0, room.center.y)
		var marker := Marker3D.new()
		marker.name = "Chamber_" + str(room.id)
		marker.position = center
		marker.set_meta("title", room.title)
		add_child(marker)
		for i in range(16):
			var angle := TAU * float(i) / 16.0 + 0.11
			var edge: Vector2 = room.center + Vector2(cos(angle), sin(angle)) * room.radii * 0.92
			# Leave passage mouths open; rocks live only near actual rock boundary.
			if signed_distance(edge) < -3.1:
				continue
			var pos := Vector3(edge.x, 0, edge.y)
			var size := Vector3(_rng.randf_range(0.7, 1.9), _rng.randf_range(0.4, 1.3), _rng.randf_range(0.7, 1.9))
			if _distance_to_route(edge) < maxf(size.x, size.z) + 1.3:
				continue
			_boulder(pos + Vector3(0, size.y * 0.35, 0), size, true)
			if i % 3 == 0:
				_stalactite(pos + Vector3(0, ceiling_height(edge) - 0.4, 0), _rng.randf_range(1.0, 2.5))
		# Two focal pools of warm light per chamber, surrounded by real darkness.
		_torch(center + Vector3(-room.radii.x * 0.64, 2.4, -room.radii.y * 0.32), 10.5)
		_torch(center + Vector3(room.radii.x * 0.64, 2.5, room.radii.y * 0.35), 10.5)
		if room.id in ["flooded", "west_shrine"]:
			_pool(center + Vector3(1.5, 0.10, 0), room.radii * Vector2(0.65, 0.55))
		if room.id in ["entrance", "mine"]:
			for z in [-5.5, 2.5]:
				_timber_frame(center + Vector3(0, 0, z), 7.8)
			for j in range(4):
				_box("AbandonedCrate", center + Vector3(room.radii.x * 0.56 + (j % 2) * 1.2, 0.5 + (j / 2) * 0.84, -5), Vector3(1.05, 0.95, 1.0), wood, true)
		if room.id == "mine":
			_mine_rails(center)
		if room.id == "chapel":
			_chapel(center)
		if room.id == "crypt":
			_crypt(center)
		if room.id == "reliquary":
			_arch(center + Vector3(0, 0, 8.0), 5.2, 6.3)
			for x in [-8.0, 8.0]:
				_banner(center + Vector3(x, 5.8, -2.5))
				_torch(center + Vector3(x, 2.0, -3.0), 10.0)
		if room.id in ["crypt", "east_cache", "west_shrine"]:
			for j in range(5):
				_bones(center + Vector3(-7 + j * 0.75, 0.1, -4 - j * 0.33))

func _dress_passages() -> void:
	for passage in passage_data:
		var bend: Vector2 = passage.bend
		var points := LAYOUT.corridor_points(passage)
		var direction := (points[2] - points[0]).normalized()
		var side := Vector2(-direction.y, direction.x)
		var pos: Vector2 = bend + side * (passage.width * 0.5 - 0.6)
		_torch(Vector3(pos.x, 2.3, pos.y), 8.0)
		if passage.from == "entrance":
			var frame := _timber_frame(Vector3(bend.x, 0, bend.y), passage.width - 0.9)
			frame.rotation.y = atan2(direction.x, direction.y)

func _distance_to_route(point: Vector2) -> float:
	var result := INF
	for segment in _segments:
		var axis: Vector2 = segment.b - segment.a
		var t := clampf((point - segment.a).dot(axis) / axis.length_squared(), 0.0, 1.0)
		result = minf(result, point.distance_to(segment.a + axis * t))
	return result

func _box(label: String, pos: Vector3, size: Vector3, material: Material, solid := false, parent: Node3D = self) -> Node3D:
	var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
	holder.name = label
	holder.position = pos
	parent.add_child(holder)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	holder.add_child(visual)
	if solid:
		holder.set("collision_layer", 2)
		holder.set("collision_mask", 5)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		holder.add_child(collision)
	return holder

func _boulder(pos: Vector3, size: Vector3, solid: bool) -> void:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in range(vertices.size()):
		var v := vertices[index]
		vertices[index] = v * (1.0 + _noise.get_noise_3d(v.x * 8 + pos.x, v.y * 8, v.z * 8 + pos.z) * 0.32)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visual.mesh = mesh
	visual.material_override = rock
	visual.position = pos
	visual.scale = size
	visual.name = "FallenLimestone"
	add_child(visual)
	if solid:
		visual.create_convex_collision()
		for child in visual.get_children():
			if child is StaticBody3D:
				child.collision_layer = 2
				child.collision_mask = 5

func _stalactite(pos: Vector3, length: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = length * 0.24
	mesh.bottom_radius = 0.035
	mesh.height = length
	mesh.radial_segments = 7
	var visual := MeshInstance3D.new()
	visual.name = "Stalactite"
	visual.mesh = mesh
	visual.material_override = wet_rock
	visual.position = pos - Vector3(0, length * 0.5, 0)
	visual.rotation.z = _rng.randf_range(-0.16, 0.16)
	add_child(visual)

func _torch(pos: Vector3, radius: float) -> void:
	var model := TORCH_SCENE.instantiate() as Node3D
	model.name = "CaveIronTorch"
	model.position = pos - Vector3(0, 0.2, 0)
	model.scale = Vector3.ONE * 0.5
	add_child(model)
	# Freestanding iron standards make every light visibly supported.
	_box("TorchStandard", Vector3(pos.x, (pos.y - 0.25) * 0.5, pos.z), Vector3(0.13, pos.y - 0.25, 0.13), iron)
	_box("TorchFoot", Vector3(pos.x, 0.09, pos.z), Vector3(0.6, 0.18, 0.6), iron)
	var flame := Sprite3D.new()
	flame.name = "AmberFlame"
	flame.texture = FLAME_TEXTURE
	flame.pixel_size = 0.00042
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.position = pos + Vector3(0, 0.3, 0)
	flame.shaded = false
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	add_child(flame)
	var light := OmniLight3D.new()
	light.name = "TorchLight_%02d" % torch_lights.size()
	light.position = pos + Vector3(0, 0.4, 0)
	light.light_color = Color(1.0, 0.49, 0.19)
	light.light_energy = 2.7
	light.set_meta("base_energy", 2.7)
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.shadow_enabled = true
	light.distance_fade_enabled = true
	light.distance_fade_begin = 28.0
	light.distance_fade_length = 12.0
	light.distance_fade_shadow = 23.0
	add_child(light)
	torch_lights.append(light)

func _pool(pos: Vector3, radii: Vector2) -> void:
	var water := ShaderMaterial.new()
	water.shader = preload("res://assets/cave_water.gdshader")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a := TAU * i / 64.0
		var b := TAU * (i + 1) / 64.0
		var ra := 0.94 + sin(a * 5.0) * 0.045 + cos(a * 9.0) * 0.015
		var rb := 0.94 + sin(b * 5.0) * 0.045 + cos(b * 9.0) * 0.015
		_tri(surface, Vector3.ZERO, Vector3(cos(a) * radii.x * ra, 0, sin(a) * radii.y * ra), Vector3(cos(b) * radii.x * rb, 0, sin(b) * radii.y * rb))
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "ShallowBlackWater"
	visual.mesh = surface.commit()
	visual.material_override = water
	visual.position = pos
	add_child(visual)
	var light := OmniLight3D.new()
	light.name = "WaterBounce_%d" % get_child_count()
	light.position = pos + Vector3(0, 1.5, 0)
	light.light_color = Color(0.19, 0.40, 0.40)
	light.light_energy = 0.32
	light.omni_range = 11
	add_child(light)

func _timber_frame(pos: Vector3, width: float) -> Node3D:
	var frame := Node3D.new()
	frame.name = "MineTimberSupport"
	frame.position = pos
	add_child(frame)
	for x in [-width * 0.5, width * 0.5]:
		_box("OakUpright", Vector3(x, 2.0, 0), Vector3(0.45, 4.0, 0.52), wood, true, frame)
		for y in [0.5, 3.5]:
			_box("IronBinding", Vector3(x, y, 0), Vector3(0.48, 0.16, 0.55), iron, false, frame)
	_box("OakLintel", Vector3(0, 4.0, 0), Vector3(width + 0.8, 0.5, 0.58), wood, true, frame)
	return frame

func _mine_rails(center: Vector3) -> void:
	for x in [-1.0, 1.0]:
		_box("RustedMineRail", center + Vector3(x, 0.07, 0), Vector3(0.08, 0.12, 19), iron)
	for j in range(14):
		_box("SunkenRailSleeper", center + Vector3(0, 0.018, -9 + j * 1.4), Vector3(2.7, 0.045, 0.22), wood)

func _arch(pos: Vector3, half_width: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		_box("RuinedArchPier", pos + Vector3(side * half_width, 1.6, 0), Vector3(0.85, 3.2, 1.1), stone, true)
	var step := PI / 32.0
	for i in range(33):
		var angle := step * i
		var tangent := Vector2(-half_width * sin(angle), (height - 3.2) * cos(angle))
		# Wedge-sized courses overlap slightly, preserving a continuous arch
		# at both wide chapel and narrower reliquary proportions.
		var course_length := tangent.length() * step * 1.10 + 0.04
		var block := _box("AncientArchStone", pos + Vector3(cos(angle) * half_width, 3.2 + sin(angle) * (height - 3.2), 0), Vector3(course_length, 0.7, 1.1), stone)
		block.rotation.z = atan2(tangent.y, tangent.x)

func _chapel(center: Vector3) -> void:
	# Thin inset stones preserve a level floor across all chapel entrances.
	var paving := _material(Color(0.44, 0.41, 0.34), 0.47, FLOOR_TEXTURE)
	_box("ChapelFlagstones", center + Vector3(0, 0.005, 0), Vector3(22, 0.06, 24), paving, true)
	for z in [7.0, -6.5]:
		_arch(center + Vector3(0, 0, z), 8.0, 8.0)
	for side in [-1.0, 1.0]:
		for z in [5.0, -4.0]:
			_banner(center + Vector3(side * 7.8, 6.8, z))
		_torch(center + Vector3(side * 5.5, 2.2, -7.5), 12)
	_box("DesecratedAltar", center + Vector3(0, 0.65, -6.0), Vector3(3.6, 1.3, 1.5), stone, true)
	_box("AltarSlab", center + Vector3(0, 1.37, -6.0), Vector3(3.9, 0.18, 1.8), stone)
	for x in [-1.3, -0.9, 1.1, 1.45]:
		_candle(center + Vector3(x, 1.48, -6.0))
	# Broken gallery edges suggest the buried upper floor without false stairs.
	for side in [-1.0, 1.0]:
		_box("CollapsedGallery", center + Vector3(side * 11.5, 4.3, -1), Vector3(2.5, 0.65, 16), wood, true)
		for z in [-8.0, -1.0, 6.0]:
			_box("GalleryPost", center + Vector3(side * 10.3, 2.1, z), Vector3(0.45, 4.2, 0.45), wood, true)

func _banner(pos: Vector3) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(8):
		for y in range(14):
			var points: Array[Vector3] = []
			for corner in [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]:
				var px: float = (corner.x / 8.0 - 0.5) * 1.65
				var py: float = -corner.y / 14.0 * 3.1
				if corner.y == 14:
					py += 0.20 + 0.17 * sin(corner.x * 2.0)
				points.append(Vector3(px, py, sin(corner.x * 1.8) * 0.1 * (corner.y / 14.0)))
			_tri(surface, points[0], points[1], points[2])
			_tri(surface, points[0], points[2], points[3])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "TatteredCrimsonBanner"
	mesh.mesh = surface.commit()
	mesh.material_override = cloth
	mesh.position = pos
	add_child(mesh)
	_box("BannerCrossbar", pos + Vector3(0, 0.05, 0), Vector3(2.0, 0.07, 0.07), iron)
	_box("BannerPole", pos + Vector3(0, -pos.y * 0.5, 0.14), Vector3(0.065, pos.y, 0.065), iron)
	var gold := _material(Color(0.48, 0.31, 0.08), 0.65)
	_box("BannerSigilVertical", pos + Vector3(0, -1.2, 0.14), Vector3(0.11, 1.1, 0.025), gold)
	_box("BannerSigilCross", pos + Vector3(0, -0.96, 0.15), Vector3(0.65, 0.10, 0.025), gold)

func _candle(pos: Vector3) -> void:
	_box("AltarCandle", pos + Vector3(0, 0.16, 0), Vector3(0.09, 0.32, 0.09), bone)
	var glow := _material(Color(1.0, 0.57, 0.11), 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.36, 0.045)
	glow.emission_energy_multiplier = 3.0
	_box("CandleFlame", pos + Vector3(0, 0.37, 0), Vector3(0.045, 0.09, 0.045), glow)

func _crypt(center: Vector3) -> void:
	for side in [-1.0, 1.0]:
		for j in range(4):
			var pos := center + Vector3(side * 10.5, 0, -7 + j * 4.5)
			if _distance_to_route(Vector2(pos.x, pos.z)) < 2.6:
				continue
			_box("StoneSarcophagus", pos + Vector3(0, 0.45, 0), Vector3(1.7, 0.9, 2.6), stone, true)
			var lid := _box("ShiftedTombLid", pos + Vector3(0.23, 0.99, 0.14), Vector3(1.9, 0.18, 2.8), stone)
			lid.rotation.y = 0.10 * side
			_bones(pos + Vector3(0, 1.12, 0))

func _bones(pos: Vector3) -> void:
	for j in range(3):
		var fragment := _box("ScatteredBone", pos + Vector3(j * 0.18, 0, 0), Vector3(0.065, 0.065, 0.65), bone)
		fragment.rotation.y = j * 1.1
