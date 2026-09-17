extends SceneTree

const GEOMETRY := preload("res://scripts/cave_geometry.gd")
const LAYOUT := preload("res://scripts/cave_layout.gd")
const PREVIEW := preload("res://tests/art_direction_preview.gd")
var failures: Array[String] = []
var excluded: Array[RID] = []
var routes: Array[PackedVector2Array] = []
var geometry: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 853
	var original := ExpeditionSession.get_inventory()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	geometry = GEOMETRY.new()
	root.add_child(geometry)
	geometry.build()
	_check(await PREVIEW.await_geometry_ready(geometry), "grounded mine dressing must finish its asynchronous collision projection")
	var details: Node3D = geometry.get("art_details")
	_check(details != null, "actual production cave must construct its grounded detail system")
	if details == null:
		_finish()
		return
	var state: Dictionary = details.call("get_state_snapshot")
	print("CAVE ART DETAILS COUNTS: rocks=%d boards=%d wall=%d variants=%d source_batches=%d rendered=%d stone_tiles=%d vertices=%d" % [state.rock_count, state.board_count, state.get("wall_outcrop_count", 0), state.variant_count, state.source_batch_count, state.render_batch_count, state.merged_stone_tiles, state.merged_vertex_count])
	_check(state.ready and state.rock_count > 100 and state.board_count > 0, "real cave should receive varied grounded rock groups and abandoned boards")
	_check(details.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing must not add collision bodies to existing walking routes")
	for body in geometry.find_children("*", "StaticBody3D", true, false):
		if not str(body.name).begins_with("Collision_Terrain_"):
			excluded.append(body.get_rid())
	for corridor: Dictionary in LAYOUT.corridors():
		var points: PackedVector2Array = corridor.points
		for i in range(points.size() - 1):
			routes.append(PackedVector2Array([points[i], points[i + 1]]))
	var instances := 0
	var floor_bearings := 0
	var unique_meshes: Dictionary = {}
	var actual_origins: Dictionary = {}
	var array_cache: Dictionary = {}
	var tile_bounds: Dictionary = {}
	var batches := details.find_children("*", "MultiMeshInstance3D", true, false)
	_check(batches.size() == int(state.multimesh_count), "reported dressing batches must be real rendered MultiMeshes")
	_check(int(state.render_batch_count) < int(state.source_batch_count) / 3, "same-tile stone merging must substantially reduce actual submissions")
	for submission: Dictionary in details.call("get_render_batches"):
		var batch := details.get_node_or_null(NodePath(str(submission.name))) as GeometryInstance3D
		_check(batch != null, "each dressing submission must point to a real visible renderer node")
		if batch == null:
			continue
		var audit := preload("res://tests/cave_detail_submission_checks.gd").inspect(submission, batch, array_cache, false)
		_check(audit.mismatches == 0 and audit.instances == submission.transforms.size(), "merged stone must retain every transformed vertex, normal, color and original triangle index")
		var mesh: Mesh = submission.source_mesh
		if not submission.merged:
			_check(int(submission.variant) >= 12, "locally projected timber must remain unmerged MultiMesh geometry")
		if not unique_meshes.has(mesh.get_instance_id()):
			unique_meshes[mesh.get_instance_id()] = true
			_check(_is_closed_mesh(mesh), "dressing variants must be closed rock or timber solids, not floating texture planes")
		var material := batch.material_override
		_check(material is BaseMaterial3D or material is ShaderMaterial, "real dressing must use a production surface material")
		if material is ShaderMaterial:
			_check(not bool(material.get_shader_parameter("ground_surface")), "rock fragments must share actual bedrock shading instead of the mud shader")
		var vertices := _triangle_vertices(mesh)
		for index in range(submission.transforms.size()):
			instances += 1
			# The dummy renderer returns an empty MultiMesh buffer and identity
			# transforms. Audit the actual CPU submission here; the native
			# preview separately compares every transform with GPU readback.
			var transform: Transform3D = batch.global_transform * submission.transforms[index]
			if submission.merged:
				var box: AABB = submission.transforms[index] * mesh.get_aabb()
				tile_bounds[batch.name] = box if not tile_bounds.has(batch.name) else tile_bounds[batch.name].merge(box)
			var position := transform.origin
			var cell := _point_cell(position)
			if not actual_origins.has(cell):
				actual_origins[cell] = []
			actual_origins[cell].append({"origin": position, "transform": transform, "vertices": vertices})
			var radius := 0.0
			for vertex in vertices:
				var world := transform * vertex
				radius = maxf(radius, Vector2(world.x - position.x, world.z - position.z).length())
				_check(LAYOUT.bounds().has_point(Vector2(world.x, world.z)), "actual dressing vertices must remain within the preserved 131 by 139 metre mine")
			_check(_route_distance(Vector2(position.x, position.z)) - radius >= 1.30, "actual dressing footprint must keep authored walking routes clear")
	for tile_name in tile_bounds:
		var tile := details.get_node(NodePath(str(tile_name))) as MeshInstance3D
		var expected: AABB = tile_bounds[tile_name]
		_check(tile.custom_aabb.position.distance_to(expected.position) < 0.0001 and tile.custom_aabb.size.distance_to(expected.size) < 0.0001, "each original 16m stone tile must retain its conservative transformed AABB")
		_check(tile.visibility_range_end == 42.0 and tile.visibility_range_end_margin == 7.0, "merged stone must retain the existing long-range fade policy")
	_check(instances == int(state.rock_count) + int(state.board_count), "reported rock and board counts must match actual rendered solid instances")
	_check(unique_meshes.size() >= 8, "dressing must use multiple independently shaped solid meshes")
	for contact: Dictionary in state.contact_samples:
		var position := _vector(contact.position_godot)
		var instance := _find_actual_instance(actual_origins, position)
		_check(not instance.is_empty(), "reported contact must belong to an actual rendered instance")
		var point := _vector(contact.contact_point_godot)
		var terrain := _vector(contact.terrain_point_godot)
		if not instance.is_empty():
			var nearest_vertex := INF
			for vertex: Vector3 in instance.vertices:
				nearest_vertex = minf(nearest_vertex, point.distance_to(instance.transform * vertex))
			_check(nearest_vertex < 0.003, "contact reports must describe actual rendered bearing vertices, not an unrelated point on the ground")
		if contact.get("contact_type", "floor") == "wall":
			var normal := _vector(contact.contact_normal_godot)
			var hit := _terrain_hit(point + normal * 0.5, point - normal * 0.5)
			_check(not hit.is_empty() and terrain.distance_to(hit.get("position", Vector3.INF)) < 0.015, "wall outcrop bearings must match independent rays against actual rock triangles")
			_check((point - terrain).dot(normal) <= 0.005 and (point - terrain).length() < 0.12, "wall outcrops must embed their solid backs in the cave")
		else:
			var hit := _terrain_hit(point + Vector3.UP * 0.5, point - Vector3.UP * 0.5)
			_check(not hit.is_empty() and terrain.distance_to(hit.get("position", Vector3.INF)) < 0.015, "floor fragment bearings must match independent rays against actual ground triangles")
			_check(point.y <= terrain.y + 0.003 and terrain.y - point.y < 0.06, "each reported floor bearing must touch or slightly enter the ground")
			floor_bearings += 1
	_check(floor_bearings > 100, "the floor attachment audit must cover real ground fragments throughout the mine")
	var count_before := details.get_child_count()
	details.call("build", geometry)
	await physics_frame
	_check(details.get_child_count() == count_before and details.call("get_state_snapshot").rock_count == state.rock_count, "rebuilding dressing must not duplicate visual instances")
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse_mode, "grounded dressing must not consume inventory, advance an expedition or capture input")
	geometry.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot, "dressing cleanup must preserve the original expedition")
	if failures.is_empty():
		print("CAVE ART DETAILS PASS: %d submitted solid instances, %d distinct meshes, %d independently ray-verified floor bearings, attached wall outcrops, route clearance, rebuild and unchanged expedition; native transform readback verified separately" % [instances, unique_meshes.size(), floor_bearings])
	_finish()


func _terrain_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 2, excluded)
	query.hit_back_faces = true
	return geometry.get_world_3d().direct_space_state.intersect_ray(query)


func _route_distance(point: Vector2) -> float:
	var distance := INF
	for segment in routes:
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])))
	return distance


func _is_closed_mesh(mesh: Mesh) -> bool:
	var vertices := _triangle_vertices(mesh)
	if vertices.size() < 12 or vertices.size() % 3 != 0:
		return false
	var edges: Dictionary = {}
	for triangle in range(0, vertices.size(), 3):
		for edge in range(3):
			var a := str(vertices[triangle + edge])
			var b := str(vertices[triangle + (edge + 1) % 3])
			var key := a + "|" + b if a < b else b + "|" + a
			edges[key] = int(edges.get(key, 0)) + 1
	for count: int in edges.values():
		if count != 2:
			return false
	return true


func _triangle_vertices(mesh: Mesh) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			result.append_array(vertices)
		else:
			for index in indices:
				result.append(vertices[index])
	return result


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _point_cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x * 10.0), floori(point.y * 10.0), floori(point.z * 10.0))


func _find_actual_instance(origins: Dictionary, point: Vector3) -> Dictionary:
	# MultiMesh transforms use float32. Look across cell boundaries and
	# compare actual distances rather than rounding to a fragile string key.
	var cell := _point_cell(point)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				for candidate: Dictionary in origins.get(cell + Vector3i(x, y, z), []):
					if candidate.origin.distance_to(point) < 0.002:
						return candidate
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
