extends RefCounted
class_name FlailVisuals

const IRON_TEXTURE: Texture2D = preload("res://assets/ai/materials/pitted_black_iron.png")
const MAX_CHAIN_LINKS := 320
const LINK_SPACING := 0.055


static func create_flail() -> Node3D:
	var flail := Node3D.new()
	flail.name = "ChainFlail"
	var iron := _material(Color(0.39, 0.41, 0.44), 0.52, 0.8, IRON_TEXTURE)
	var leather := _material(Color(0.16, 0.085, 0.05), 0.94)
	var handle := _cylinder(0.027, 0.031, 0.45, leather)
	handle.name = "LeatherHandle"
	handle.position.y = 0.015
	flail.add_child(handle)
	for index in range(9):
		var wrap := _cylinder(0.032, 0.032, 0.018, leather)
		wrap.name = "LeatherWrap%d" % index
		wrap.position.y = -0.18 + index * 0.045
		wrap.rotation.z = 0.07
		flail.add_child(wrap)
	for side in [-1, 1]:
		var collar := _cylinder(0.04, 0.04, 0.045, iron)
		collar.name = "IronCollar%d" % side
		collar.position.y = 0.015 + side * 0.23
		flail.add_child(collar)
	var anchor := Marker3D.new()
	anchor.name = "ChainAnchor"
	anchor.position = Vector3(0.0, 0.28, 0.0)
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
	var iron := _material(Color(0.34, 0.37, 0.40), 0.49, 0.86, IRON_TEXTURE)
	var edge := _material(Color(0.59, 0.61, 0.64), 0.38, 0.84, IRON_TEXTURE)
	var core := MeshInstance3D.new()
	core.name = "IronBall"
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	sphere.radial_segments = 16
	sphere.rings = 8
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
		var spike := _cylinder(0.0, 0.034, 0.09, edge)
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
	links.material_override = _material(Color(0.48, 0.49, 0.51), 0.45, 0.84, IRON_TEXTURE)
	chain.add_child(links)
	for marker_name in ["Start", "End"]:
		var marker := Marker3D.new()
		marker.name = marker_name
		chain.add_child(marker)
	return chain


static func update_chain(chain: Node3D, from: Vector3, to: Vector3, sag := 0.0) -> void:
	if not is_instance_valid(chain) or not from.is_finite() or not to.is_finite():
		return
	var links := chain.get_node_or_null("Links") as MultiMeshInstance3D
	if links == null:
		return
	(chain.get_node("Start") as Node3D).position = from
	(chain.get_node("End") as Node3D).position = to
	var distance := from.distance_to(to)
	if distance < 0.00001:
		links.multimesh.visible_instance_count = 0
		return
	var count := clampi(ceili(distance / LINK_SPACING) + 1, 2, MAX_CHAIN_LINKS)
	links.multimesh.visible_instance_count = count
	var sag_amount := maxf(sag, 0.0)
	var spacing_scale := clampf(distance / (count - 1) / LINK_SPACING, 0.3, 2.0)
	for index in range(count):
		var ratio := float(index) / (count - 1)
		var point := from.lerp(to, ratio) + Vector3.DOWN * (sin(ratio * PI) * sag_amount)
		var tangent := (to - from) + Vector3.DOWN * (cos(ratio * PI) * PI * sag_amount)
		var along := Basis(Quaternion(Vector3.UP, tangent.normalized()))
		var alternating := Basis(Vector3.UP, PI / 2.0 if index % 2 else 0.0)
		var ring := Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, spacing_scale * 1.5, 1.0))
		links.multimesh.set_instance_transform(index, Transform3D(along * alternating * ring, point))


static func set_head_position(flail: Node3D, position_value: Vector3) -> void:
	if not is_instance_valid(flail):
		return
	var head := flail.get_node_or_null("Head") as Node3D
	var anchor := flail.get_node_or_null("ChainAnchor") as Node3D
	var chain := flail.get_node_or_null("Chain") as Node3D
	if head != null and anchor != null and chain != null:
		head.position = position_value
		update_chain(chain, anchor.position, position_value, 0.035)


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
	mesh.radial_segments = 8
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
