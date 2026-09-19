extends Node3D
## One world-space burst of the actual shield, with physical world collisions.
const FRAGMENTS_PATH := "res://assets/3d/player/shield_damage/round_shield_fragments.glb"
const SURFACES := preload("res://scripts/sword_shield_arm_visual.gd")
const WOOD := preload("res://shaders/shield_fracture_wood.gdshader")
const LIFETIME := 24.0
static var _pieces: Array[Dictionary] = []
var age := 0.0
var bodies: Array[RigidBody3D] = []

class Fragment extends RigidBody3D:
	var ground_contact := false
	var contact_count := 0
	var local_bounds: AABB
	var collision_points := PackedVector3Array()

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		contact_count += state.get_contact_count()
		var touching_floor := false
		for index in state.get_contact_count():
			# Collision mask permits level geometry only, never the player or AI.
			# As in the corpse rig, Godot contact normals are world vectors;
			# "local" identifies this body's contact side, not a rotated frame.
			var normal := state.get_contact_local_normal(index).normalized()
			if normal.y > 0.3:
				ground_contact = true
				touching_floor = true
		# Rolling resistance at a real floor contact stops thin pieces from
		# endlessly rocking under the solver. Airborne rotation stays untouched.
		if touching_floor: state.angular_velocity *= exp(-12.0 * state.step)


static func prepare() -> void:
	if not _pieces.is_empty(): return
	var packed := load(FRAGMENTS_PATH) as PackedScene
	if packed == null: return
	var source := packed.instantiate() as Node3D
	for mesh: MeshInstance3D in source.find_children("ShieldFragment_*", "MeshInstance3D", true, false):
		var local := mesh.transform
		var ancestor := mesh.get_parent() as Node3D
		while ancestor != null and ancestor != source:
			local = ancestor.transform * local
			ancestor = ancestor.get_parent() as Node3D
		SURFACES.prepare_materials(mesh)
		var materials: Array[Material] = []
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index)
			if material != null and material.resource_name == "FP_ShieldFractureOak":
				var grain := ShaderMaterial.new()
				grain.resource_name = "FragmentGrowthRings"
				grain.shader = WOOD
				grain.set_shader_parameter("wood_coordinates", local)
				material = grain
			materials.append(material)
		# Precompute convex hulls before the breaking hit, avoiding collision
		# generation during the impact frame. Pieces do not collide each other.
		var shape: Shape3D = mesh.mesh.create_convex_shape(true, false)
		var bounds := mesh.mesh.get_aabb()
		if shape == null:
			var box := BoxShape3D.new()
			box.size = bounds.size.max(Vector3.ONE * .025)
			shape = box
		# Preserve the full hull; backends that support a margin use 2 mm.
		shape.margin = .002
		_pieces.append({"name": str(mesh.name), "mesh": mesh.mesh, "transform": local,
			"materials": materials, "shape": shape, "bounds": bounds})
	source.free()


func launch(shield_transform: Transform3D, inherited_velocity: Vector3, forward: Vector3) -> void:
	prepare()
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	var forward_flat := Vector3(forward.x, 0, forward.z).normalized()
	var right := forward_flat.cross(Vector3.UP).normalized()
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = .88
	physics_material.bounce = .05
	for index in _pieces.size():
		var piece: Dictionary = _pieces[index]
		var body := Fragment.new()
		body.name = piece.name
		body.mass = .09 if str(piece.name).ends_with("metal") else .13
		# A minimum rotational inertia keeps very thin pieces from gaining
		# extreme spin through small contact impulses in the discrete solver.
		var extent: Vector3 = (piece.bounds as AABB).size
		var minimum_inertia := .004 if str(piece.name).ends_with("metal") else .001
		body.inertia = (Vector3(extent.y * extent.y + extent.z * extent.z,
			extent.x * extent.x + extent.z * extent.z,
			extent.x * extent.x + extent.y * extent.y) * (body.mass / 12.0)).max(Vector3.ONE * minimum_inertia)
		body.collision_layer = 0
		body.collision_mask = 2
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 4
		body.linear_damp = .24
		body.angular_damp = 1.4
		body.physics_material_override = physics_material
		body.local_bounds = piece.bounds
		var display := MeshInstance3D.new()
		display.mesh = piece.mesh
		display.layers = 1
		for surface in piece.materials.size(): display.set_surface_override_material(surface, piece.materials[surface])
		body.add_child(display)
		var collider := CollisionShape3D.new()
		collider.shape = piece.shape
		if collider.shape is BoxShape3D: collider.position = (piece.bounds as AABB).get_center()
		if collider.shape is ConvexPolygonShape3D:
			body.collision_points = (collider.shape as ConvexPolygonShape3D).points
		else:
			var collision_bounds := AABB(collider.position - (collider.shape as BoxShape3D).size * .5, (collider.shape as BoxShape3D).size)
			for corner in 8: body.collision_points.append(collision_bounds.get_endpoint(corner))
		body.add_child(collider)
		add_child(body)
		body.global_transform = shield_transform * (piece.transform as Transform3D)
		# Deterministic but varied initial impulses; all following movement is
		# gravity, rotation, world collision and friction from the physics engine.
		var seed := float(index) * 2.3999632
		var radial := body.global_position - shield_transform.origin
		var lateral := right * (sin(seed) * 1.05 + radial.dot(right) * 1.3)
		body.linear_velocity = inherited_velocity * .35 + forward_flat * (1.10 + .55 * cos(seed * .71)) + lateral + Vector3.UP * (1.5 + .8 * sin(seed * 1.31))
		body.angular_velocity = Vector3(sin(seed) * 5, cos(seed * 1.7) * 4, sin(seed * .63) * 6)
		bodies.append(body)


func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME: queue_free()


func snapshot() -> Dictionary:
	var entries: Array[Dictionary] = []
	for body: Fragment in bodies:
		if not is_instance_valid(body): continue
		var bottom := INF
		for point: Vector3 in body.collision_points: bottom = minf(bottom, (body.global_transform * point).y)
		entries.append({"id": body.get_instance_id(), "position": body.global_position,
			"linear_velocity": body.linear_velocity, "angular_velocity": body.angular_velocity,
			"sleeping": body.sleeping, "ground_contact": body.ground_contact,
			"contact_count": body.contact_count, "bottom_y": bottom})
	return {"fragment_count": entries.size(), "age": age, "bodies": entries, "active": not entries.is_empty()}
