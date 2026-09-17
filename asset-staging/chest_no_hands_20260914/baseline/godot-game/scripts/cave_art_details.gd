extends Node3D
## Grounded mine detritus. All placement rays hit actual imported Terrain_
## colliders; the coarse height field is only a ray starting-height hint.
## build() is awaitable and yields until the newly imported colliders exist.

signal details_built

const LAYOUT := preload("res://scripts/cave_layout.gd")
const ART_DIRECTION := preload("res://scripts/cave_art_direction.gd")
const ROCK_KIT_PATH := "res://assets/3d/abandoned_mine/art_rock_kit.glb"
const SEED := 139131 + 65017
const MAX_ROCKS := 2100
const MAX_BOARDS := 44
const MAX_WALL_OUTCROPS := 480
const ROCK_VARIANTS := 12
const BOARD_VARIANTS := 3
const ROUTE_CLEARANCE := 1.35
const TILE_SIZE := 16.0

var _geometry: Node3D
var _rng := RandomNumberGenerator.new()
var _ready_to_view := false
var _building := false
var _rock_count := 0
var _board_count := 0
var _wall_count := 0
var _batches: Dictionary = {}
var _render_batches: Array[Dictionary] = []
var _merged_tile_count := 0
var _multimesh_count := 0
var _merged_vertex_count := 0
var _meshes: Array[ArrayMesh] = []
var _routes: Array[PackedVector2Array] = []
var _occupied: Array[AABB] = []
var _wall_occupied: Array[Vector3] = []
var _contacts: Array[Dictionary] = []
var _reserved: Array[Vector2] = []
var _rock_material: Material
var _wood_material: Material
var _generation := 0


func build(geometry: Node3D) -> void:
	if _building or _ready_to_view:
		return
	_building = true
	_geometry = geometry
	_rng.seed = SEED
	_generation += 1
	var generation := _generation
	name = "GroundedMineDetails"
	global_transform = geometry.global_transform
	# Queries made during geometry._ready() can miss collision bodies that
	# have not reached the physics server yet. Never replace a miss with a
	# nominal y=0 placement; wait for the authoritative surfaces instead.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation != _generation or not is_instance_valid(_geometry):
		return
	for corridor: Dictionary in LAYOUT.corridors():
		var points: PackedVector2Array = corridor.points
		for i in range(points.size() - 1):
			_routes.append(PackedVector2Array([points[i], points[i + 1]]))
	for kind in ["chests", "traps", "enemies"]:
		for placement: Dictionary in LAYOUT.gameplay(kind):
			_reserved.append(Vector2(placement.position.x, placement.position.z))
	_reserved.append(Vector2(LAYOUT.spawn_position().x, LAYOUT.spawn_position().z))
	_reserved.append(Vector2(LAYOUT.extraction_position().x, LAYOUT.extraction_position().z))
	_rock_material = ART_DIRECTION.geological_material(false)
	_find_scene_materials_and_props(geometry.get("blender_mine") as Node)
	if _rock_material == null or _wood_material == null:
		push_error("Mine detail dressing requires the actual imported rock and oak materials")
		_building = false
		return
	if not _load_rock_meshes():
		push_error("The Blender fracture kit must contain twelve closed rock variants")
		_building = false
		return
	for i in range(BOARD_VARIANTS):
		_meshes.append(_fragment_mesh(i + 500, true))
	_scatter_wall_relief()
	_scatter_wall_foot_clusters()
	_scatter_shore_gravel()
	_create_multimeshes()
	_building = false
	_ready_to_view = true
	details_built.emit()


func _exit_tree() -> void:
	_generation += 1


func _find_scene_materials_and_props(node: Node) -> void:
	if node is MeshInstance3D:
		var visual := node as MeshInstance3D
		var label := str(visual.name)
		if visual.mesh and label.begins_with("Terrain_") and _rock_material == null:
			_rock_material = _detail_material(visual.get_active_material(0), false)
		if visual.mesh and label.contains("Mine_AgedOak"):
			if _wood_material == null:
				_wood_material = _detail_material(visual.get_active_material(0), true)
		if visual.mesh and visual.visible and label.begins_with("Mine_") and not label.contains("supported_oil_lantern"):
			var box := visual.mesh.get_aabb()
			var global_box := visual.global_transform * box
			var local_box := _geometry.global_transform.affine_inverse() * global_box
			if local_box.position.y < 0.7:
				_occupied.append(local_box.grow(0.18))
	for child in node.get_children():
		_find_scene_materials_and_props(child)


func _detail_material(source: Material, wood: bool) -> Material:
	if source == null:
		return null
	if wood:
		# Loose fragments have generated UVs, so use the same physical timber
		# grain through metric triplanar projection in gameplay and the gallery.
		# The placed MultiMesh already supplies a dark weathered instance color.
		# A second dark material tint previously crushed its visible grain.
		var timber := preload("res://scripts/dark_fantasy_materials.gd").old_oak(Color(0.88, 0.91, 0.93), 0.65)
		timber.albedo_color = Color(0.52, 0.61, 0.79)
		timber.vertex_color_use_as_albedo = true
		timber.uv1_triplanar_sharpness = 5.0
		timber.normal_scale = 0.85
		return timber
	# A parent's world-position rock shader can be reused directly. It keeps
	# tiny chips the same mineral/color family as their surrounding cliff.
	if source is ShaderMaterial:
		return source
	var material := source.duplicate() as BaseMaterial3D
	if material:
		material.vertex_color_use_as_albedo = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.roughness = 0.92 if wood else 0.76
		material.uv1_triplanar = true
		material.uv1_triplanar_sharpness = 5.0
		material.uv1_scale = Vector3.ONE * (1.7 if wood else 1.2)
	return material


func _load_rock_meshes() -> bool:
	var kit := load(ROCK_KIT_PATH) as PackedScene
	if kit == null:
		return false
	var source := kit.instantiate()
	var variants: Dictionary = {}
	for node in source.find_children("ErodedBedrock_*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual.mesh == null:
			continue
		var transform_value := visual.transform
		var parent := visual.get_parent()
		while parent != null and parent != source:
			if parent is Node3D:
				transform_value = parent.transform * transform_value
			parent = parent.get_parent()
		var mesh := ArrayMesh.new()
		var unique: Dictionary = {}
		for surface in range(visual.mesh.get_surface_count()):
			var arrays: Array = visual.mesh.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var normal_basis := transform_value.basis.inverse().transposed()
			for index in range(vertices.size()):
				vertices[index] = transform_value * vertices[index]
				normals[index] = (normal_basis * normals[index]).normalized()
				unique[vertices[index]] = true
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var points := PackedVector3Array()
		for point: Vector3 in unique:
			points.append(point)
		mesh.set_meta("unique_vertices", points)
		mesh.set_meta("bearing_vertices", _ground_bearings(points))
		mesh.set_meta("wall_bearing_vertices", _wall_bearings(points))
		mesh.resource_name = str(visual.name)
		variants[str(visual.name)] = mesh
	var names := variants.keys()
	names.sort()
	for label: String in names:
		_meshes.append(variants[label])
	source.free()
	return _meshes.size() == ROCK_VARIANTS


func _ground_bearings(points: PackedVector3Array) -> PackedVector3Array:
	var lowest := INF
	for point in points:
		lowest = minf(lowest, point.y)
	var selected: Dictionary = {}
	# The final Blender mesh has a planar base. Select the actual outer
	# vertices of that base rather than an invented box or rounded origin.
	for direction in range(12):
		var angle := float(direction) * TAU / 12.0
		var axis := Vector2(cos(angle), sin(angle))
		var farthest := -INF
		var bearing := Vector3.ZERO
		for point in points:
			if point.y > lowest + 0.0005:
				continue
			var distance := Vector2(point.x, point.z).dot(axis)
			if distance > farthest:
				farthest = distance
				bearing = point
		selected[bearing] = true
	var result := PackedVector3Array()
	for point: Vector3 in selected:
		result.append(point)
	return result


func _wall_bearings(points: PackedVector3Array) -> PackedVector3Array:
	# Critical rear vertices cover the whole back in sixteen cells. Taking
	# the frontmost rear vertex per cell embeds the closed stone across its
	# support face; at most sixteen expensive world rays are needed.
	var cells: Dictionary = {}
	for point in points:
		if point.z > -0.055:
			continue
		var cell := Vector2i(clampi(int((point.x + 0.5) * 4.0), 0, 3), clampi(int(point.y * 4.0), 0, 3))
		if not cells.has(cell) or point.z > cells[cell].z:
			cells[cell] = point
	var result := PackedVector3Array()
	for point: Vector3 in cells.values():
		result.append(point)
	return result


func _mesh_points(variant: int) -> PackedVector3Array:
	var mesh := _meshes[variant]
	if mesh.has_meta("unique_vertices"):
		return mesh.get_meta("unique_vertices")
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _scatter_wall_foot_clusters() -> void:
	for room: Dictionary in LAYOUT.rooms():
		var polygon: PackedVector2Array = room.polygon
		var mined := str(room.geology) == "mined"
		for i in range(polygon.size()):
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var edge := b - a
			if edge.length() < 0.30:
				continue
			var inward := Vector2(-edge.y, edge.x).normalized()
			var midpoint := (a + b) * 0.5
			if not Geometry2D.is_point_in_polygon(midpoint + inward * 0.16, polygon):
				inward = -inward
			var steps := maxi(1, int(edge.length() / 1.85))
			for step in range(steps):
				if _rock_count >= MAX_ROCKS:
					return
				# Unequal groups and broad gaps read as sloughed-off stone,
				# rather than an evenly repeated row of round decorative rocks.
				if _rng.randf() < 0.20:
					continue
				var t := (float(step) + _rng.randf_range(0.18, 0.82)) / float(steps)
				var survey := a.lerp(b, t)
				var origin := survey + inward * 1.7
				var hint := float(_geometry.floor_height(origin))
				var wall := _terrain_ray(Vector3(origin.x, hint + 0.42, origin.y), Vector3(survey.x - inward.x * 2.0, hint + 0.42, survey.y - inward.y * 2.0))
				if wall.is_empty() or absf(wall.normal.y) > 0.72:
					continue
				var normal := Vector2(wall.normal.x, wall.normal.z).normalized()
				var anchor := Vector2(wall.position.x, wall.position.z)
				var tangent := Vector2(-normal.y, normal.x)
				if _wall_count < MAX_WALL_OUTCROPS and _rng.randf() < 0.30:
					_place_wall_outcrop(wall.position, wall.normal)
				var number := _rng.randi_range(4, 10)
				for fragment in range(number):
					var radius := _rng.randf_range(0.07, 0.26)
					if fragment == 0:
						radius = _rng.randf_range(0.24, 0.43)
					var along := _rng.randf_range(-0.85, 0.85)
					var into_room := radius * 0.55 + pow(_rng.randf(), 2.0) * 0.63
					var point := anchor + normal * into_room + tangent * along
					var scale_value := Vector3(radius * _rng.randf_range(1.7, 2.3), radius * _rng.randf_range(0.55, 1.35), radius * _rng.randf_range(1.1, 1.85))
					_place_fragment(point, scale_value, _rng.randi_range(0, ROCK_VARIANTS - 1), false)
				if mined and _board_count < MAX_BOARDS and _rng.randf() < 0.095:
					var point := anchor + normal * 0.9 + tangent * _rng.randf_range(-0.4, 0.4)
					_place_fragment(point, Vector3(_rng.randf_range(0.12, 0.20), _rng.randf_range(0.026, 0.049), _rng.randf_range(0.65, 1.35)), ROCK_VARIANTS + _rng.randi_range(0, BOARD_VARIANTS - 1), true)


func _scatter_wall_relief() -> void:
	# Large-scale fractures need actual silhouette depth above eye level.
	# Sample discontinuous patches over the wall height, never repeated bands.
	# Every chamber gets its own budget so the earliest rooms cannot consume
	# all the relief intended for the rest of the mine.
	for room: Dictionary in LAYOUT.rooms():
		var polygon: PackedVector2Array = room.polygon
		var room_count := 0
		var offset := _rng.randi_range(0, polygon.size() - 1)
		for edge_index in range(polygon.size()):
			if _wall_count >= MAX_WALL_OUTCROPS or room_count >= 26:
				break
			var i := (edge_index + offset) % polygon.size()
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var edge := b - a
			if edge.length() < 0.40 or _rng.randf() < 0.18:
				continue
			var inward := Vector2(-edge.y, edge.x).normalized()
			if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + inward * 0.16, polygon):
				inward = -inward
			var sites := maxi(1, int(edge.length() / 2.2))
			for site in range(sites):
				var survey := a.lerp(b, (float(site) + _rng.randf_range(0.15, 0.85)) / sites)
				var origin := survey + inward * 1.8
				var floor_hint := float(_geometry.floor_height(origin))
				var roof_hint := float(_geometry.ceiling_height(origin))
				var max_height := minf(4.8, roof_hint - floor_hint - 0.55)
				if max_height < 1.0:
					continue
				var attempts := _rng.randi_range(1, 3)
				for attempt in range(attempts):
					if _wall_count >= MAX_WALL_OUTCROPS or room_count >= 26:
						break
					var height := floor_hint + _rng.randf_range(0.85, max_height)
					var wall := _terrain_ray(Vector3(origin.x, height, origin.y), Vector3(survey.x - inward.x * 2.1, height, survey.y - inward.y * 2.1))
					if wall.is_empty() or absf(wall.normal.y) > 0.66:
						continue
					var previous := _wall_count
					_place_wall_outcrop(wall.position, wall.normal, true)
					room_count += _wall_count - previous


func _scatter_shore_gravel() -> void:
	for pool: Dictionary in LAYOUT.pools():
		var polygon: PackedVector2Array = pool.polygon
		for i in range(polygon.size()):
			if _rock_count >= MAX_ROCKS:
				return
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var direction := b - a
			if direction.length() < 0.25:
				continue
			var bank := Vector2(-direction.y, direction.x).normalized()
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + bank * 0.1, polygon):
				bank = -bank
			if _rng.randf() < 0.42:
				continue
			var center := a.lerp(b, _rng.randf_range(0.2, 0.8)) + bank * _rng.randf_range(0.08, 0.30)
			for j in range(_rng.randi_range(2, 5)):
				var radius := _rng.randf_range(0.045, 0.16)
				var point := center + direction.normalized() * _rng.randf_range(-0.38, 0.38) + bank * _rng.randf_range(0.01, 0.24)
				_place_fragment(point, Vector3(radius * 2.0, radius * _rng.randf_range(0.45, 0.95), radius * 1.6), _rng.randi_range(0, ROCK_VARIANTS - 1), false)


func _place_fragment(point: Vector2, size: Vector3, variant: int, board: bool) -> void:
	if not board and _rock_count >= MAX_ROCKS:
		return
	var radius := Vector2(size.x, size.z).length() * 0.5
	if _route_distance(point) - radius < ROUTE_CLEARANCE:
		return
	for reserved in _reserved:
		if point.distance_to(reserved) < 1.5 + radius:
			return
	if not LAYOUT.bounds().grow(-0.25 - radius).has_point(point):
		return
	var floor := _floor_hit(point)
	if floor.is_empty() or floor.normal.y < 0.70:
		return
	var position_value: Vector3 = floor.position
	for box in _occupied:
		if box.grow(radius).has_point(position_value + Vector3.UP * 0.12):
			return
	var yaw := _rng.randf_range(-PI, PI)
	var alignment := Basis(Quaternion(Vector3.UP, floor.normal))
	var basis_value := alignment * Basis(Vector3.UP, yaw)
	basis_value = basis_value * Basis.from_scale(size)
	# A tilted fragment's upper vertices can overhang its nominal footprint.
	# Protect the walking line using the complete transformed solid.
	radius = maxf(radius, _horizontal_radius(basis_value, variant))
	if _route_distance(point) - radius < ROUTE_CLEARANCE or not LAYOUT.bounds().grow(-radius).has_point(point):
		return
	for reserved in _reserved:
		if point.distance_to(reserved) < 1.5 + radius:
			return
	for box in _occupied:
		if box.grow(radius).has_point(position_value + Vector3.UP * 0.12):
			return
	var bottom: PackedVector3Array = _meshes[variant].get_meta("bearing_vertices")
	var shift := 100.0
	var bearing: Dictionary = {}
	for local in bottom:
		var offset := basis_value * local
		var sample := _floor_hit(point + Vector2(offset.x, offset.z))
		if sample.is_empty() or sample.normal.y < 0.56:
			return
		var correction: float = sample.position.y - (position_value.y + offset.y)
		if correction < shift:
			shift = correction
			bearing = {"offset": offset, "surface": sample.position, "normal": sample.normal}
	# Every corner is slightly buried. A surface miss never creates a floating
	# instance, and no new collider is added to the preserved walking routes.
	position_value.y += shift - 0.018
	var contact: Vector3 = position_value + bearing.offset
	var route_margin := _route_distance(point) - radius
	var tile := Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))
	var key := "%d_%d_%d" % [variant, tile.x, tile.y]
	if not _batches.has(key):
		_batches[key] = {"variant": variant, "transforms": [], "colors": []}
	_batches[key].transforms.append(Transform3D(basis_value, position_value))
	var shade := _rng.randf_range(0.74, 1.07)
	var tint := Color(0.58, 0.53, 0.44) if board else Color(0.43, 0.48, 0.49)
	_batches[key].colors.append(Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0))
	_contacts.append({"kind": "aged_board" if board else "rock_fragment", "variant": variant,
		"position_godot": [position_value.x, position_value.y, position_value.z],
		"contact_point_godot": [contact.x, contact.y, contact.z],
		"terrain_point_godot": [bearing.surface.x, bearing.surface.y, bearing.surface.z],
		"contact_type": "floor", "ground_gap_m": contact.y - float(bearing.surface.y), "route_distance_m": route_margin})
	if board:
		_board_count += 1
	else:
		_rock_count += 1


func _place_wall_outcrop(wall_point: Vector3, wall_normal: Vector3, broad: bool = false) -> void:
	if _wall_count >= MAX_WALL_OUTCROPS or _rock_count >= MAX_ROCKS:
		return
	var normal := Vector3(wall_normal.x, 0, wall_normal.z).normalized()
	var tangent := Vector3(normal.z, 0, -normal.x)
	var size := Vector3(_rng.randf_range(0.72, 1.38), _rng.randf_range(0.60, 1.35), _rng.randf_range(0.70, 1.25))
	if broad:
		size = Vector3(_rng.randf_range(1.05, 1.95), _rng.randf_range(0.65, 1.65), _rng.randf_range(0.72, 1.12))
	var variant := _rng.randi_range(0, ROCK_VARIANTS - 1)
	var basis_value := Basis(tangent, Vector3.UP, normal) * Basis.from_scale(size)
	var position_value := wall_point + Vector3.UP * _rng.randf_range(0.18, 0.80) - Vector3.UP * size.y * 0.22
	if broad:
		position_value = wall_point - Vector3.UP * size.y * 0.42
	for other in _wall_occupied:
		if other.distance_to(position_value) < 0.65:
			return
	var radius := maxf(Vector2(size.x, size.z).length() * 0.55, _horizontal_radius(basis_value, variant))
	var point := Vector2(position_value.x, position_value.z)
	if _route_distance(point) - radius < ROUTE_CLEARANCE:
		return
	for reserved in _reserved:
		if point.distance_to(reserved) < 1.5 + radius:
			return
	for box in _occupied:
		if box.grow(radius).has_point(position_value):
			return
	var source := _mesh_points(variant)
	var rear: PackedVector3Array = _meshes[variant].get_meta("wall_bearing_vertices")
	var shift := 1000.0
	var bearing: Dictionary = {}
	var unique_rear: Dictionary = {}
	for vertex in rear:
		# The entire rear half is embedded, not just the deepest vertex. This
		# leaves a closed rock attached to the irregular host across its back.
		if vertex.z > -0.055 or unique_rear.has(vertex):
			continue
		unique_rear[vertex] = true
		var candidate := position_value + basis_value * vertex
		var hit := _terrain_ray(candidate + normal * 1.6, candidate - normal * 1.2)
		if hit.is_empty() or hit.normal.dot(normal) < 0.46:
			return
		var correction: float = (hit.position - candidate).dot(normal) - 0.065
		if correction < shift:
			shift = correction
			bearing = {"vertex": vertex, "surface": hit.position, "normal": hit.normal}
	if bearing.is_empty():
		return
	position_value += normal * shift
	var front_extent := -1000.0
	for vertex in source:
		var position := position_value + basis_value * vertex
		front_extent = maxf(front_extent, (position - bearing.surface).dot(normal))
	# A solid closed fragment can protrude, but never becomes a large slab
	# bridging a passage or a plate with an empty underside.
	if front_extent < 0.18 or front_extent > 0.67:
		return
	point = Vector2(position_value.x, position_value.z)
	var route_margin := _route_distance(point) - radius
	if route_margin < ROUTE_CLEARANCE or not LAYOUT.bounds().grow(-radius).has_point(point):
		return
	var contact: Vector3 = position_value + basis_value * bearing.vertex
	var tile := Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))
	var key := "%d_%d_%d" % [variant, tile.x, tile.y]
	if not _batches.has(key):
		_batches[key] = {"variant": variant, "transforms": [], "colors": []}
	_batches[key].transforms.append(Transform3D(basis_value, position_value))
	var shade := _rng.randf_range(0.83, 1.03)
	_batches[key].colors.append(Color(0.43 * shade, 0.48 * shade, 0.49 * shade, 1.0))
	_contacts.append({"kind": "wall_outcrop", "contact_type": "wall", "variant": variant,
		"position_godot": [position_value.x, position_value.y, position_value.z],
		"contact_point_godot": [contact.x, contact.y, contact.z],
		"terrain_point_godot": [bearing.surface.x, bearing.surface.y, bearing.surface.z],
		"contact_normal_godot": [normal.x, normal.y, normal.z],
		"wall_gap_m": (contact - bearing.surface).dot(normal),
		"exposed_depth_m": front_extent, "route_distance_m": route_margin,
		"embedded_rear_vertices": unique_rear.size(), "broad_wall_relief": broad})
	_wall_occupied.append(position_value)
	_wall_count += 1
	_rock_count += 1


func _terrain_ray(from: Vector3, to: Vector3) -> Dictionary:
	var excluded: Array[RID] = []
	for attempt in range(12):
		var query := PhysicsRayQueryParameters3D.create(_geometry.to_global(from), _geometry.to_global(to), 2, excluded)
		query.hit_back_faces = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.collider as Node
		if collider != null and str(collider.name).begins_with("Collision_Terrain_"):
			return {"position": _geometry.to_local(hit.position), "normal": (_geometry.global_basis.transposed() * hit.normal).normalized()}
		excluded.append(hit.rid)
	return {}


func _floor_hit(point: Vector2) -> Dictionary:
	var hint := float(_geometry.floor_height(point))
	return _terrain_ray(Vector3(point.x, hint + 0.95, point.y), Vector3(point.x, hint - 2.0, point.y))


func _route_distance(point: Vector2) -> float:
	var result := 1000.0
	for segment in _routes:
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		result = minf(result, point.distance_to(closest))
	return result


func _horizontal_radius(basis_value: Basis, variant: int) -> float:
	var vertices := _mesh_points(variant)
	var radius := 0.0
	for vertex in vertices:
		var offset := basis_value * vertex
		radius = maxf(radius, Vector2(offset.x, offset.z).length())
	return radius + 0.002


func _create_multimeshes() -> void:
	var rock_tiles: Dictionary = {}
	for key: String in _batches:
		var batch: Dictionary = _batches[key]
		if int(batch.variant) < ROCK_VARIANTS:
			var tile := key.substr(key.find("_") + 1)
			if not rock_tiles.has(tile):
				rock_tiles[tile] = [] as Array[String]
			rock_tiles[tile].append(key)
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _meshes[int(batch.variant)]
		multimesh.instance_count = batch.transforms.size()
		for i in range(multimesh.instance_count):
			multimesh.set_instance_transform(i, batch.transforms[i])
			multimesh.set_instance_color(i, batch.colors[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "GroundedDetritus_" + key
		instance.multimesh = multimesh
		instance.material_override = _wood_material
		instance.visibility_range_end = 42.0
		instance.visibility_range_end_margin = 7.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(instance)
		_multimesh_count += 1
		_render_batches.append({"name": str(instance.name), "variant": int(batch.variant),
			"transforms": batch.transforms.duplicate(true), "source_mesh": multimesh.mesh,
			"merged": false, "colors": batch.colors.duplicate()})
	for tile: String in rock_tiles:
		var keys: Array[String] = rock_tiles[tile]
		var merged := preload("res://scripts/cave_detail_batching.gd").merge(_meshes, _batches, keys)
		var instance := MeshInstance3D.new()
		instance.name = "GroundedStoneTile_" + tile
		instance.mesh = merged.mesh
		instance.material_override = _rock_material
		# Preserve the union of the original conservative instance bounds.
		instance.custom_aabb = merged.bounds
		instance.visibility_range_end = 42.0
		instance.visibility_range_end_margin = 7.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(instance)
		_merged_tile_count += 1
		_merged_vertex_count += int(merged.vertices)
		for key in keys:
			var batch: Dictionary = _batches[key]
			var ranges: Array[Dictionary] = []
			for placement: Dictionary in merged.instances:
				if placement.key == key:
					ranges.append(placement)
			_render_batches.append({"name": str(instance.name), "variant": int(batch.variant),
				"transforms": batch.transforms.duplicate(true), "source_mesh": _meshes[int(batch.variant)],
				"merged": true, "ranges": ranges, "colors": batch.colors.duplicate()})


func _fragment_mesh(seed_value: int, board: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + seed_value * 1543
	var vertices := PackedVector3Array()
	var rings := 3
	var sides := 6
	for ring in range(rings):
		for side in range(sides):
			var angle := float(side) * TAU / sides
			var radius := rng.randf_range(0.40, 0.51)
			if ring == 1:
				radius *= rng.randf_range(0.94, 1.08)
			elif ring == 2:
				radius *= rng.randf_range(0.35, 0.85)
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			var y := 0.0 if ring == 0 else (rng.randf_range(0.25, 0.46) if ring == 1 else rng.randf_range(0.64, 1.0))
			if board:
				x = [-0.5, 0.5, 0.5, 0.5, -0.5, -0.5][side] + rng.randf_range(-0.045, 0.035)
				z = [-0.5, -0.5, -0.18, 0.5, 0.5, 0.19][side] + rng.randf_range(-0.055, 0.055)
				y = 0.0 if ring == 0 else (0.42 if ring == 1 else rng.randf_range(0.78, 1.0))
			vertices.append(Vector3(x, y, z))
	var faces: Array[PackedInt32Array] = []
	faces.append(PackedInt32Array([0, 5, 4, 3, 2, 1]))
	for ring in range(rings - 1):
		for side in range(sides):
			var next := (side + 1) % sides
			faces.append(PackedInt32Array([ring * sides + side, ring * sides + next, (ring + 1) * sides + next, (ring + 1) * sides + side]))
	faces.append(PackedInt32Array([12, 13, 14, 15, 16, 17]))
	var output := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var center := Vector3(0, 0.40, 0)
	for face in faces:
		for index in range(1, face.size() - 1):
			var a := vertices[face[0]]
			var b := vertices[face[index]]
			var c := vertices[face[index + 1]]
			var normal := (c - a).cross(b - a).normalized()
			if normal.dot((a + b + c) / 3.0 - center) < 0:
				var swap := b
				b = c
				c = swap
				normal = -normal
			for point in [a, b, c]:
				output.append(point)
				normals.append(normal)
				uv.append(Vector2(point.x, point.z))
				colors.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = output
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("bearing_vertices", vertices.slice(0, sides))
	return mesh


func get_state_snapshot() -> Dictionary:
	return {"ready": _ready_to_view, "rock_count": _rock_count, "board_count": _board_count,
		"wall_outcrop_count": _wall_count, "floor_rock_count": _rock_count - _wall_count,
		"variant_count": _meshes.size(), "multimesh_count": _multimesh_count,
		"source_batch_count": _batches.size(), "merged_stone_tiles": _merged_tile_count,
		"render_batch_count": _multimesh_count + _merged_tile_count,
		"merged_vertex_count": _merged_vertex_count,
		"contact_samples": _contacts.duplicate(true), "no_collision_bodies": true,
		"surface_source": "Actual Terrain_ collision triangles", "route_clearance_m": ROUTE_CLEARANCE,
		"rock_mesh_source": ROCK_KIT_PATH, "blender_rock_variants": ROCK_VARIANTS}


func state_snapshot() -> Dictionary:
	return get_state_snapshot()


func get_render_batches() -> Array[Dictionary]:
	# The dummy headless renderer returns identity for MultiMesh readback.
	# Expose the exact immutable values submitted to the real renderer so
	# physics tests can audit placement without inventing a parallel scene.
	# Merged submissions additionally identify the exact vertex/index range
	# receiving each original source transform; no invisible stand-ins exist.
	return _render_batches.duplicate(true)
