extends SceneTree

const VISUALS := preload("res://scripts/dark_fantasy_effect_visual.gd")
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.capture_snapshot()
	var inventory := ExpeditionSession.get_inventory()
	var mouse := Input.mouse_mode
	seed(78534)
	var expected_random := randi()
	seed(78534)
	for id in ["fire_bolt", "water_bolt", "ice_shard", "stone_shard"]:
		var definition := SpellCatalog.get_spell_definition(id)
		var projectile := MagicProjectile.new()
		projectile.configure(id, definition, null, Vector3(0.4, 0.2, -1).normalized())
		projectile.set_physics_process(false)
		root.add_child(projectile)
		projectile.set_physics_process(false)
		var collision := projectile.get_node("ProjectileCollision") as CollisionShape3D
		var sweep := projectile.get_node("ProjectileSweep") as ShapeCast3D
		_check(is_equal_approx((collision.shape as SphereShape3D).radius, float(definition.radius)) and sweep.shape == collision.shape, "concept geometry must retain the exact shared projectile collision/sweep sphere: " + id)
		_check(is_equal_approx(projectile.speed, float(definition.speed)) and is_equal_approx(projectile.damage, float(definition.damage)), "appearance must retain real spell speed and damage: " + id)
		_check((-projectile._visual_root.global_basis.z).dot(projectile.direction) > 0.999, "new longitudinal shapes must remain aligned with the actual travel direction: " + id)
		var core := projectile.find_child("ElementCore", true, false) as MeshInstance3D
		_check(core.mesh is ArrayMesh and core.mesh.get_faces().size() > 60, "element must use actual authored faceted/rippled geometry: " + id)
		_check(_outward_normals(core.mesh, id == "ice_shard") and _closed_edges(core.mesh), "element surfaces must be physically closed with outward normals and renderer-facing winding, including the concave ice shoulder: " + id)
		if id == "ice_shard":
			var size := core.mesh.get_aabb().size
			_check(size.z > size.x * 2.0 and core.mesh.get_aabb().position.z < 0.0, "ice must have a pointed splinter silhouette on the forward axis")
		if id == "stone_shard":
			_check(core.material_override is StandardMaterial3D and core.material_override.albedo_texture != null and not core.material_override.emission_enabled, "stone must use the real dark rough stone surface without a magic glow")
		else:
			_check(core.material_override is ShaderMaterial and core.material_override.has_meta("dark_fantasy_element"), "fire, water and ice must use their actual shaded elemental surfaces")
		if id in ["fire_bolt", "ice_shard"]:
			var authored := VISUALS.COAL_TEXTURE if id == "fire_bolt" else VISUALS.ICE_TEXTURE
			_check((core.material_override as ShaderMaterial).get_shader_parameter("concept_surface") == authored and authored.get_width() >= 1024, "actual elemental shader must bind the new generated coal/ice material image rather than an unrelated procedural substitute: " + id)
		var light := projectile.find_child("ElementLight", true, false) as OmniLight3D
		_check(light.light_energy <= 0.75 and projectile.find_child("ElementHalo", true, false) == null, "an opaque saturated additive halo must not cover the target")
		projectile.free()
	var perception := StressPerception.new()
	perception.call("_build_ghost", Vector3(2, 0, 3))
	_check(perception.ghost.position == Vector3(2, 0, 3) and perception.ghost.get_meta("perception_only"), "shrouded afterimage must retain its requested location and noncombat identity")
	_check(perception.ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "ragged ghost must never acquire a combat or interaction collider")
	var shroud := perception.ghost.find_child("RaggedHoodedShroud", true, false) as MeshInstance3D
	_check(shroud != null and shroud.mesh is ArrayMesh and shroud.mesh.get_faces().size() > 2000 and perception._ghost_material.albedo_color.a == 0.0, "ragged hood/cloak must be real geometry under the existing initially invisible fade material")
	_check(is_equal_approx(perception._ghost_remaining, StressPerception.GHOST_DURATION), "appearance must preserve the bounded hallucination duration")
	perception.free()
	var room: Node3D = load("res://scripts/test_room.gd").new()
	room.call("_spawn_archery_accuracy_target")
	room.call("_build_flail_station_markers")
	var target := room.get_node("ArcheryAccuracyTarget") as StaticBody3D
	var shapes := target.find_children("*", "CollisionShape3D", true, false)
	_check(target.position == Vector3(0, 2.5, -3) and target.collision_layer == 2 and shapes.size() == 1 and (shapes[0].shape as BoxShape3D).size == Vector3(5.4, 5, 0.25), "weathered target must retain its exact world-layer collider, centre and eight-metre targeting fixture")
	_check(target.find_children("TargetWeatheredPlank*", "MeshInstance3D", true, false).size() == 9 and target.find_children("RearCrossBrace*", "MeshInstance3D", true, false).size() == 2, "target concept must create individual timbers and both actual rear braces")
	_check(target.find_children("TargetRing*", "MeshInstance3D", true, false).size() == 5, "faded paint must preserve all five production scoring marks")
	for lane in ["FlailNearLane", "FlailFarLane"]:
		var marker := room.get_node(lane) as MeshInstance3D
		_check(marker.position == Vector3(-3 if lane == "FlailNearLane" else 3, 0.015, 5) and (marker.mesh as BoxMesh).size == Vector3(1.8, 0.015, 1.4), "weathered lane must preserve exact footprint and near/far instruction distances")
		_check(marker.find_children("*", "CollisionObject3D", true, false).is_empty() and marker.find_children("LaneInsetBorder*", "MeshInstance3D", true, false).size() == 4, "inlaid lane borders must remain decoration without affecting movement")
	room.free()
	_check(randi() == expected_random, "deterministic appearance construction must not consume the global combat random stream")
	_check(original == ExpeditionSession.capture_snapshot() and inventory == ExpeditionSession.get_inventory() and mouse == Input.mouse_mode, "effect and training art must preserve every expedition field, original inventory and cursor")
	if failures.is_empty():
		print("DARK FANTASY EFFECTS PASS: actual elemental geometry/outward normals, exact spell sweeps/stats/directions, noncombat hooded fade and unchanged real training colliders/distances/session/RNG")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _outward_normals(mesh: Mesh, longitudinal := false) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(0, vertices.size(), 3):
		var normal := normals[index]
		var center := (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3.0
		if longitudinal:
			center.z = 0.0
		var winding := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
		if normal.dot(center) < -0.00001 or winding.dot(normal) >= 0.0:
			return false
	return true


func _closed_edges(mesh: Mesh) -> bool:
	var faces := mesh.get_faces()
	var edges := {}
	for index in range(0, faces.size(), 3):
		for edge in range(3):
			var first := str(Vector3i((faces[index + edge] * 1000000.0).round()))
			var second := str(Vector3i((faces[index + (edge + 1) % 3] * 1000000.0).round()))
			var key := first + "|" + second if first < second else second + "|" + first
			edges[key] = int(edges.get(key, 0)) + 1
	for count in edges.values():
		if int(count) != 2:
			return false
	return true


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
