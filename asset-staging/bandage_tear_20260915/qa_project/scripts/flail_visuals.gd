extends RefCounted
class_name FlailVisuals

const IRON_TEXTURE: Texture2D = preload("res://assets/ai/materials/pitted_black_iron.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const MAX_CHAIN_LINKS := 320
const LINK_SPACING := 0.055
const HANDLE_GRIP := Vector3(0.0, -0.10, 0.0)
const CHAIN_ANCHOR := Vector3(0.0, 0.28, 0.0)
const HELD_CHAIN_LENGTH := 0.55


static func create_flail() -> Node3D:
	var flail := Node3D.new()
	flail.name = "ChainFlail"
	var iron := AGED_SURFACES.pitted_iron(Color(0.31, 0.32, 0.30))
	var leather := AGED_SURFACES.leather(Color(0.125, 0.103, 0.079))
	var handle := _cylinder(0.027, 0.031, 0.45, leather)
	handle.name = "LeatherHandle"
	handle.position.y = 0.015
	flail.add_child(handle)
	var shaft := _cylinder(0.029, 0.031, 0.24, AGED_SURFACES.old_oak(Color(0.43, 0.40, 0.32)))
	shaft.name = "ExposedOakHandle"
	shaft.position.y = 0.115
	flail.add_child(shaft)
	var grip := Marker3D.new()
	grip.name = "FlailGrip"
	grip.position = HANDLE_GRIP
	flail.add_child(grip)
	for index in range(7):
		var wrap := _cylinder(0.032, 0.032, 0.025, leather)
		wrap.name = "LeatherWrap%d" % index
		wrap.position.y = -0.18 + index * 0.031
		wrap.rotation.z = 0.07
		flail.add_child(wrap)
	for side in [-1, 1]:
		var collar := _cylinder(0.04, 0.04, 0.045, iron)
		collar.name = "IronCollar%d" % side
		collar.position.y = 0.015 + side * 0.23
		flail.add_child(collar)
		for rivet_index in 6:
			var angle := float(rivet_index) * TAU / 6.0
			var rivet := _cylinder(0.006, 0.008, 0.009, iron)
			rivet.name = "CollarRivet%d" % rivet_index
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			rivet.position = direction * 0.041
			rivet.basis = Basis(Quaternion(Vector3.UP, direction))
			collar.add_child(rivet)
	var anchor := Marker3D.new()
	anchor.name = "ChainAnchor"
	anchor.position = CHAIN_ANCHOR
	flail.add_child(anchor)
	var attachment := MeshInstance3D.new()
	attachment.name = "HandleEyelet"
	attachment.mesh = _link_mesh()
	attachment.material_override = iron
	attachment.rotation.x = PI / 2.0
	attachment.position = anchor.position
	flail.add_child(attachment)
	flail.add_child(create_head())
	flail.add_child(create_chain())
	set_head_position(flail, Vector3(0.15, -0.16, -0.62))
	return flail


static func create_head() -> Node3D:
	var head := Node3D.new()
	head.name = "Head"
	var iron := AGED_SURFACES.pitted_iron(Color(0.30, 0.315, 0.30))
	var edge := AGED_SURFACES.pitted_iron(Color(0.39, 0.395, 0.36))
	var core := MeshInstance3D.new()
	core.name = "IronBall"
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	sphere.radial_segments = 24
	sphere.rings = 12
	core.mesh = sphere
	core.material_override = iron
	head.add_child(core)
	var directions: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				directions.append(Vector3(x, y, z).normalized())
	for index in range(directions.size()):
		var direction := directions[index]
		var spike := _cylinder(0.002, 0.034, 0.075, edge)
		spike.name = "Spike%d" % index
		spike.position = direction * 0.155
		spike.basis = Basis(Quaternion(Vector3.UP, direction))
		head.add_child(spike)
	return head


static func create_chain() -> Node3D:
	var chain := Node3D.new()
	chain.name = "Chain"
	# One instanced mesh retains real interlocking metal loops without hundreds
	# of scene nodes or draw calls as the thrown chain extends across the room.
	var links := MultiMeshInstance3D.new()
	links.name = "Links"
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = _link_mesh()
	instances.instance_count = MAX_CHAIN_LINKS
	instances.visible_instance_count = 0
	links.multimesh = instances
	links.material_override = AGED_SURFACES.pitted_iron(Color(0.39, 0.395, 0.37))
	chain.add_child(links)
	for marker_name in ["Start", "End"]:
		var marker := Marker3D.new()
		marker.name = marker_name
		chain.add_child(marker)
	return chain


static func update_chain(chain: Node3D, from: Vector3, to: Vector3, sag := 0.0) -> void:
	if not is_instance_valid(chain) or not from.is_finite() or not to.is_finite() or not is_finite(sag):
		return
	var links := chain.get_node_or_null("Links") as MultiMeshInstance3D
	if links == null:
		return
	var sag_amount := maxf(sag, 0.0)
	# The chain lives in its parent's coordinate system. An unchanged local
	# curve keeps the exact submitted links through movement and visibility
	# changes; throws or a new curve still replace every affected transform.
	if chain.has_meta("submitted_chain_from") and chain.get_meta("submitted_chain_from") == from and chain.get_meta("submitted_chain_to") == to and float(chain.get_meta("submitted_chain_sag")) == sag_amount:
		return
	chain.set_meta("submitted_chain_from", from)
	chain.set_meta("submitted_chain_to", to)
	chain.set_meta("submitted_chain_sag", sag_amount)
	(chain.get_node("Start") as Node3D).position = from
	(chain.get_node("End") as Node3D).position = to
	var distance := from.distance_to(to)
	if distance < 0.00001:
		links.multimesh.visible_instance_count = 0
		return
	# A rigid orbit can vary by a few floating-point ulps. Do not add/remove a
	# whole link when its radius lands exactly on a link-spacing boundary.
	var count := clampi(ceili(maxf(0.0, distance / LINK_SPACING - 0.00001)) + 1, 2, MAX_CHAIN_LINKS)
	links.multimesh.visible_instance_count = count
	var spacing_scale := clampf(distance / (count - 1) / LINK_SPACING, 0.3, 2.0)
	for index in range(count):
		var ratio := float(index) / (count - 1)
		var point := from.lerp(to, ratio) + Vector3.DOWN * (sin(ratio * PI) * sag_amount)
		var tangent := (to - from) + Vector3.DOWN * (cos(ratio * PI) * PI * sag_amount)
		var along := Basis(Quaternion(Vector3.UP, tangent.normalized()))
		var alternating := Basis(Vector3.UP, PI / 2.0 if index % 2 else 0.0)
		var ring := Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, spacing_scale * 1.5, 1.0))
		links.multimesh.set_instance_transform(index, Transform3D(along * alternating * ring, point))


static func set_head_position(flail: Node3D, position_value: Vector3, sag := 0.035) -> void:
	if not is_instance_valid(flail) or not position_value.is_finite() or not is_finite(sag):
		return
	var head := flail.get_node_or_null("Head") as Node3D
	var anchor := flail.get_node_or_null("ChainAnchor") as Node3D
	var chain := flail.get_node_or_null("Chain") as Node3D
	if head != null and anchor != null and chain != null:
		head.position = position_value
		update_chain(chain, anchor.position, position_value, sag)


static func flail_hand_anchors(flail: Node3D) -> Dictionary:
	if not is_instance_valid(flail):
		return {}
	var grip := flail.get_node_or_null("FlailGrip") as Marker3D
	var anchor := flail.get_node_or_null("ChainAnchor") as Marker3D
	var head := flail.get_node_or_null("Head") as Node3D
	if grip == null or anchor == null or head == null:
		return {}
	return {"grip": grip.position, "chain_anchor": anchor.position, "head": head.position, "head_attached": head.visible}


static func flail_head_pose(anchor: Vector3, state: String, action_time: float, spin_phase: float) -> Vector3:
	# Presentation only: the caller supplies the real combat clock and orbit
	# phase. The projectile, attack clock, collision radius and damage stay in
	# the production player/projectile systems.
	var at := anchor if anchor.is_finite() else CHAIN_ANCHOR
	var rest := Vector3(-0.22, -0.43, -0.27).normalized() * HELD_CHAIN_LENGTH
	if not is_finite(action_time) or not is_finite(spin_phase):
		return at + rest
	var elapsed := maxf(0.0, action_time)
	match state:
		"spinning":
			# Revolve above and left of the raised wrist, leaving a clear view of
			# the links between the real eyelet and ball throughout the orbit.
			# A spherical entry from the hanging ball preserves chain length.
			var axis := Vector3(-0.74341, -0.38118, -0.54959).normalized()
			var radial := Vector3.UP.cross(axis).normalized()
			var cone_angle := deg_to_rad(18.0)
			var orbit := (axis * cos(cone_angle) + Basis(axis, spin_phase) * radial * sin(cone_angle)) * HELD_CHAIN_LENGTH
			return at + rest.slerp(orbit, _smooth_ratio(elapsed / 0.24))
		"melee":
			var back := Basis(Vector3.UP, -0.22) * Basis(Vector3.RIGHT, -0.90) * rest
			# The forward tilted handle changes the local aiming axes. Continue
			# beyond its eyelet at impact so the ball clears the gripping wrist.
			var contact := Vector3(-0.47310, 0.87681, 0.08588).normalized() * HELD_CHAIN_LENGTH
			var follow := Vector3(-0.84, 0.42, -0.34).normalized() * HELD_CHAIN_LENGTH
			if elapsed <= 0.12:
				return at + rest.slerp(back, _smooth_ratio(elapsed / 0.12))
			if elapsed <= 0.20:
				return at + back.slerp(contact, _smooth_ratio((elapsed - 0.12) / 0.08))
			if elapsed <= 0.38:
				return at + contact.slerp(follow, _smooth_ratio((elapsed - 0.20) / 0.18))
			return at + follow.slerp(rest, _smooth_ratio((elapsed - 0.38) / 0.27))
		"recovery":
			# The returned real projectile has just reached the eyelet. Let the
			# held ball settle from the catch rather than reappear at full reach.
			return at + rest * lerpf(0.10, 1.0, _smooth_ratio(elapsed / 0.25))
	return at + rest


static func _smooth_ratio(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func set_head_visible(flail: Node3D, enabled: bool) -> void:
	if not is_instance_valid(flail):
		return
	for child_name in ["Head", "Chain"]:
		var child := flail.get_node_or_null(child_name) as Node3D
		if child != null:
			child.visible = enabled


static func _link_mesh() -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.016
	mesh.outer_radius = 0.026
	mesh.rings = 12
	mesh.ring_segments = 6
	return mesh


static func _cylinder(top: float, bottom: float, height_value: float, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height_value
	mesh.radial_segments = 12
	instance.mesh = mesh
	instance.material_override = material
	return instance


static func _material(color_value: Color, roughness: float, metallic := 0.0, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness
	material.metallic = metallic
	if texture != null:
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * 3.0
	return material
