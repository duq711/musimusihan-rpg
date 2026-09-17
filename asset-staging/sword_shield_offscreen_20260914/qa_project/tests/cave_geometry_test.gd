extends SceneTree

const GEOMETRY := preload("res://scripts/cave_geometry.gd")
const LAYOUT := preload("res://scripts/cave_layout.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var cave := GEOMETRY.new()
	root.add_child(cave)
	cave.build()
	await physics_frame
	await physics_frame
	_check(cave.get_node_or_null("BlenderMine") != null, "the playable mine must import the actual Blender-built environment")
	_check(cave.get_meta("footprint_metres", Vector2.ZERO) == Vector2(131, 139), "the Blender importer must preserve the exact 131 by 139 metre survey")
	var footprint := cave.get_node_or_null("DungeonFootprint") as StaticBody3D
	_check(footprint != null, "an exact below-floor footprint must bound the surveyed site")
	if footprint:
		var collision := footprint.find_child("*", false, false) as CollisionShape3D
		for child in footprint.get_children():
			if child is CollisionShape3D:
				collision = child
		var box_shape := collision.shape as BoxShape3D if collision != null else null
		_check(box_shape != null and is_equal_approx(box_shape.size.x, 131) and is_equal_approx(box_shape.size.z, 139), "survey fallback collision must remain exactly 131 by 139 metres")
	var continuous_material_count := 0
	var visible_lamp_cages := 0
	var actual_bounds := AABB(Vector3(-65.5, -1.2, -69.5), Vector3(131, 1, 139))
	for mesh_node in cave.find_children("*", "MeshInstance3D", true, false):
		var visual := mesh_node as MeshInstance3D
		if str(visual.name).contains("_supported_oil_lantern_") and not str(visual.name).contains("AgedOak"):
			visible_lamp_cages += 1
			_check(visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "small lamp cages must not cast enlarged self-shadow patterns")
		if visual.mesh:
			actual_bounds = actual_bounds.merge(visual.global_transform * visual.mesh.get_aabb())
			for surface in range(visual.mesh.get_surface_count()):
				# Runtime art direction overrides the shading, while the imported
				# photographic color and vertex tint remain preserved in the mesh.
				var material := visual.mesh.surface_get_material(surface) as BaseMaterial3D
				if material and material.resource_name.begins_with("Mine_Continuous_"):
					continuous_material_count += 1
					_check(material.vertex_color_use_as_albedo and material.albedo_texture != null and material.normal_texture != null, "smooth geological tint must preserve real photographic color and normal textures in Godot: %s colors=%s albedo=%s normal=%s" % [material.resource_name, material.vertex_color_use_as_albedo, material.albedo_texture != null, material.normal_texture != null])
	_check(visible_lamp_cages > 0, "the shadow configuration must apply to the actual imported lamp cages")
	_check(continuous_material_count > 0, "the imported mine must use continuous geological color rather than sawtooth face-color seams")
	_check(actual_bounds.position.x >= -65.51 and actual_bounds.end.x <= 65.51 and actual_bounds.position.z >= -69.51 and actual_bounds.end.z <= 69.51, "all imported rock, water and props must fit the requested footprint: " + str(actual_bounds))
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var state := cave.get_world_3d().direct_space_state
	var samples := 0
	for link: Dictionary in LAYOUT.corridors():
		var points := LAYOUT.corridor_points(link)
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b) / 0.5))
			for step in range(steps + 1):
				var p := a.lerp(b, float(step) / steps)
				var pos := Vector3(p.x, 1.2, p.y)
				_check(cave.signed_distance(p) < -1, "each route must stay inside the actual carved cave: " + str(link.id))
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform.origin = pos
				query.collision_mask = 2
				var hits := state.intersect_shape(query, 1)
				_check(hits.is_empty(), "player capsule clearance on %s at %s: %s" % [link.id, p, str(hits[0].collider.name) if not hits.is_empty() else ""])
				var ground := state.intersect_ray(PhysicsRayQueryParameters3D.create(pos, pos - Vector3(0, 2, 0), 2))
				_check(not ground.is_empty() and ground.get("collider") != footprint, "each passage sample needs actual Blender ground, not the below-floor fallback")
				samples += 1
	for room: Dictionary in LAYOUT.rooms():
		var origin := Vector3(room.center.x, 1.8, room.center.y)
		var roof := state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0, 24, 0), 2))
		_check(not roof.is_empty(), "the underground chamber must have a real enclosing roof: " + str(room.id))
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var wall := state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 150, 2))
			_check(not wall.is_empty(), "carved walls must prevent leaving the mine from " + str(room.id))
	for island: Dictionary in LAYOUT.islands():
		# These are finite boulders/islets with visible air above them. A 2D
		# hole accidentally extruded to the ceiling must fail this regression.
		var center := Vector2.ZERO
		for point: Vector2 in island.polygon:
			center += point
		center /= float(island.polygon.size())
		var probe_height := 12.0 if island.id == "grand_quarry_rock_island" else 4.0
		var top := state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(center.x, probe_height, center.y), Vector3(center.x, -0.5, center.y), 2))
		_check(not top.is_empty(), "each finite island must have an actual Blender rock crown: " + str(island.id))
		if top.is_empty():
			continue
		var crown: Vector3 = top.position
		_check(crown.y > 0.15 and crown.y < float(island.height) + 0.5, "the boulder crown must stay near its finite authored height: %s at %.2fm" % [island.id, crown.y])
		var above := crown + Vector3.UP * 0.3
		var overhead := state.intersect_ray(PhysicsRayQueryParameters3D.create(above, above + Vector3.UP * 24.0, 2))
		_check(not overhead.is_empty(), "a rock island must retain the cave roof above it: " + str(island.id))
		if not overhead.is_empty():
			_check(float(overhead.position.y) - crown.y > 0.8, "rock islands must leave a visible gap below the ceiling: " + str(island.id))
	_check(not cave.torch_lights.is_empty(), "the mine needs actual lamps that light the imported environment")
	for lamp: OmniLight3D in cave.torch_lights:
		_check(lamp.light_energy > 0 and lamp.omni_range > 0, "each mine light must illuminate a real fixture")
	var children_before := cave.get_child_count()
	cave.build()
	_check(cave.get_child_count() == children_before, "repeated builds must not duplicate imported meshes, lamps or collisions")
	cave.queue_free()
	await process_frame
	if failures.is_empty():
		print("CAVE GEOMETRY TEST PASS: actual Blender import, exact footprint, %d capsule route samples, source ground, roof, enclosing walls and lamps" % samples)
		quit(0)
	else:
		for failure in failures:
			push_error("CAVE GEOMETRY TEST FAIL: " + failure)
		quit(1)

func _check(ok: bool, detail: String) -> void:
	if not ok and not failures.has(detail):
		failures.append(detail)
