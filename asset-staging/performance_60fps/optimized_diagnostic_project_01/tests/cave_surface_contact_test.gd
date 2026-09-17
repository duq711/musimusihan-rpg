extends SceneTree
## Probe the imported geometry against the real terrain collision, independently
## of the Blender placement calculations and the below-floor safety slab.
const GEOMETRY := preload("res://scripts/cave_geometry.gd")
var failures: Array[String] = []
var terrain_only_excludes: Array[RID] = []
var geometry: Node3D
var state: PhysicsDirectSpaceState3D
var vertices_by_group: Dictionary = {}
var contact_probe := SphereShape3D.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	geometry = GEOMETRY.new()
	root.add_child(geometry)
	geometry.build()
	await physics_frame
	await physics_frame
	state = geometry.get_world_3d().direct_space_state
	contact_probe.radius = 0.11
	for body in geometry.find_children("*", "StaticBody3D", true, false):
		if not str(body.name).begins_with("Collision_Terrain_"):
			terrain_only_excludes.append(body.get_rid())
	var checked_scans := 0
	var sampled_vertices := 0
	var sampled_face_points := 0
	for visual in geometry.find_children("RockScan_*", "MeshInstance3D", true, false):
		checked_scans += 1
		var floating := 0
		for surface in range(visual.mesh.get_surface_count()):
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step := maxi(1, vertices.size() / 40)
			for index in range(0, vertices.size(), step):
				var point: Vector3 = visual.global_transform * vertices[index]
				sampled_vertices += 1
				if not _near_terrain(point):
					floating += 1
			# A skin can have attached vertices while its broad faces bridge air.
			# Probe face interiors as well as vertices, especially every long face.
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_count := (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var face_step := maxi(1, triangle_count / 32)
			for triangle in triangle_count:
				var a: Vector3 = visual.global_transform * vertices[indices[triangle * 3] if not indices.is_empty() else triangle * 3]
				var b: Vector3 = visual.global_transform * vertices[indices[triangle * 3 + 1] if not indices.is_empty() else triangle * 3 + 1]
				var c: Vector3 = visual.global_transform * vertices[indices[triangle * 3 + 2] if not indices.is_empty() else triangle * 3 + 2]
				if triangle % face_step != 0 and maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) < .60:
					continue
				for point: Vector3 in [(a + b + c) / 3.0, (a + b) * .5, (b + c) * .5, (c + a) * .5]:
					sampled_face_points += 1
					if not _near_terrain(point):
						floating += 1
		_check(floating == 0, "%s has %d sampled vertices or face interiors detached from actual cave rock" % [visual.name, floating])
	_check(checked_scans == 132 and sampled_vertices > 4000, "all132 fitted scanned rock pieces must be independently probed")
	var info: Dictionary = geometry.get_build_info()
	var mineral_contacts := 0
	var formations: Dictionary = info.get("formation_contact", {})
	_check(not formations.is_empty(), "export must validate complete mineral components and skin faces")
	for entry: Dictionary in formations.get("assets", []):
		if entry.kind == "wall_skin":
			_check(float(entry.max_face_gap_m) <= .11, "Blender must validate every retained face interior: " + str(entry.name))
			continue
		for sample: Dictionary in entry.get("contact_samples", []):
			var point := _point(sample.point_godot)
			var surface := _point(sample.surface_godot)
			var hit := _terrain_ray(surface - Vector3.UP * .15, surface + Vector3.UP * .15)
			_check(not hit.is_empty() and hit.position.distance_to(surface) < .025, "mineral root needs real terrain bearing: " + str(entry.name))
			_check(float(sample.gap_m) <= .003, "mineral roots must be embedded, not hovering")
			_check(_actual_mineral_vertex_near(str(entry.name), point), "declared mineral root must be present in the actual imported mesh: " + str(entry.name))
			mineral_contacts += 1
	_check(mineral_contacts > 500, "root contact probes must cover the full mine's minerals")
	var contacts: Dictionary = info.get("prop_contact", {})
	_check(not contacts.is_empty(), "export must include measurable physical prop contacts")
	var ground: Array = contacts.get("ground_contacts", [])
	var supports: Array = contacts.get("timber_supports", [])
	var lamps: Array = contacts.get("wall_lanterns", [])
	_check(ground.size() >= 40 and supports.size() == 5 and lamps.size() == 52, "all ground assemblies, five timber frames and52 lamps must be fitted")
	for entry: Dictionary in ground:
		_validate_contact(str(entry.name), _point(entry.point_godot), _point(entry.surface_godot), Vector3.UP, .20)
	for support: Dictionary in supports:
		_check(support.foot_contacts.size() == 2 and support.roof_contacts.size() == 7, "each timber frame must carry the roof through both feet and seven packing contacts")
		for foot: Dictionary in support.foot_contacts:
			_validate_contact(str(support.name), _point(foot.point_godot), _point(foot.surface_godot), Vector3.UP, .35)
		for packing: Dictionary in support.roof_contacts:
			_validate_contact(str(support.name), _point(packing.point_godot), _point(packing.surface_godot), Vector3.UP, .35)
	for lamp: Dictionary in lamps:
		var normal := _point(lamp.wall_normal_godot).normalized()
		var anchor := _point(lamp.wall_anchor_godot)
		var hit := _terrain_ray(anchor - normal * .25, anchor + normal * .25)
		_check(not hit.is_empty() and hit.position.distance_to(anchor) < .06, "wall lamp anchor must hit actual cave rock: " + str(lamp.name))
		for bolt: Dictionary in lamp.anchor_contacts:
			_validate_contact(str(lamp.name), _point(bolt.point_godot), _point(bolt.surface_godot), normal, .16)
		var wick := _point(lamp.wick_godot)
		var light: OmniLight3D = geometry.torch_lights[int(lamp.light_index)]
		_check(light.global_position.distance_to(wick) < .01, "lamp lighting must follow its physical wick")
		_check(float(lamp.route_distance_m) >= 1.55, "wall lamp must clear the walking route")
	geometry.queue_free()
	await process_frame
	if failures.is_empty():
		print("CAVE SURFACE CONTACT TEST PASS: %d imported rock vertices + %d face interiors, %d mineral roots, %d ground contacts, %d ceiling-fitted frames and %d wall-mounted lamps" % [sampled_vertices, sampled_face_points, mineral_contacts, ground.size(), supports.size(), lamps.size()])
		quit(0)
	else:
		for failure in failures:
			push_error("CAVE SURFACE CONTACT TEST FAIL: " + failure)
		quit(1)

func _actual_mineral_vertex_near(label: String, point: Vector3) -> bool:
	var key := "mineral:" + label
	if not vertices_by_group.has(key):
		var visual := geometry.find_child(label, true, false) as MeshInstance3D
		if visual == null:
			# The glTF importer converts Blender's dot-numbered object names
			# to underscores (verified against the actual imported singleton).
			visual = geometry.find_child(label.replace(".", "_"), true, false) as MeshInstance3D
		var points := PackedVector3Array()
		if visual and visual.mesh:
			for surface in visual.mesh.get_surface_count():
				var arrays := visual.mesh.surface_get_arrays(surface)
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					points.append(visual.global_transform * vertex)
		vertices_by_group[key] = points
	for vertex: Vector3 in vertices_by_group[key]:
		if vertex.distance_squared_to(point) < .000025:
			return true
	return false

func _point(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _terrain_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 2, terrain_only_excludes)
	query.hit_back_faces = true
	return state.intersect_ray(query)

func _near_terrain(point: Vector3) -> bool:
	# A sphere checks distance in every direction, including convex corners
	# where three axis-aligned rays can all miss a nearby triangle vertex.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = contact_probe
	query.transform.origin = point
	query.collision_mask = 2
	query.exclude = terrain_only_excludes
	return not state.intersect_shape(query, 1).is_empty()

func _validate_contact(group_name: String, point: Vector3, surface: Vector3, axis: Vector3, mesh_tolerance: float) -> void:
	var hit := _terrain_ray(surface - axis * .25, surface + axis * .25)
	_check(not hit.is_empty() and hit.position.distance_to(surface) < .065, "prop contact must meet the actual terrain: " + group_name)
	_check(point.distance_to(surface) < .16, "prop contact must leave no visible unsupported gap: " + group_name)
	if not vertices_by_group.has(group_name):
		var group := geometry.find_child(group_name, true, false)
		var vertices := PackedVector3Array()
		if group:
			for visual in group.find_children("*", "MeshInstance3D", true, false):
				if not visual.visible or visual.mesh == null:
					continue
				for index in range(visual.mesh.get_surface_count()):
					var arrays: Array = visual.mesh.surface_get_arrays(index)
					for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
						vertices.append(visual.global_transform * vertex)
		vertices_by_group[group_name] = vertices
	var geometry_near := false
	for vertex: Vector3 in vertices_by_group[group_name]:
		if vertex.distance_to(point) <= mesh_tolerance:
			geometry_near = true
			break
	_check(geometry_near, "actual visible prop must reach its declared physical contact: " + group_name)

func _check(ok: bool, detail: String) -> void:
	if not ok and not failures.has(detail):
		failures.append(detail)
