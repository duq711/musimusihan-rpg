extends RefCounted
## A separate short blade in the existing right-hand sword grip frame.
## Gameplay reach and assassination eligibility remain owned by the player.

const GRIP_CENTER := Vector3(0.0, -0.108, 0.002)
const BLADE_LENGTH := 0.32


static func create_dagger() -> Node3D:
	var dagger := Node3D.new()
	dagger.name = "IronDaggerVisual"
	dagger.set_meta("weapon_family", "dagger")
	dagger.set_meta("grip_local", GRIP_CENTER)
	dagger.set_meta("blade_length_m", BLADE_LENGTH)
	dagger.set_meta("source_model", "procedural_iron_dagger")
	var steel := _material("Dagger_BladeSteel", Color(0.36, 0.40, 0.43), 0.81, 0.36)
	var fittings := _material("Dagger_WornIron", Color(0.18, 0.19, 0.18), 0.76, 0.56)
	var leather := _material("Dagger_GripLeather", Color(0.13, 0.075, 0.04), 0.0, 0.87)
	var binding := _material("Dagger_LeatherBinding", Color(0.19, 0.115, 0.063), 0.0, 0.92)
	_add_part(dagger, "PittedBlade", _blade_mesh(), steel)
	var guard := _cylinder(0.011, 0.011, 0.112, 12)
	var guard_part := _add_part(dagger, "Crossguard", guard, fittings, Vector3(0, -0.012, 0.002))
	guard_part.rotation.z = PI * 0.5
	_add_part(dagger, "GripFerrule", _cylinder(0.023, 0.022, 0.016, 20), fittings, Vector3(0, -0.030, 0.002))
	_add_part(dagger, "LeatherGrip", _cylinder(0.0215, 0.023, 0.155, 24), leather, GRIP_CENTER)
	_add_part(dagger, "GripBinding", _binding_mesh(), binding)
	_add_part(dagger, "PommelCollar", _cylinder(0.024, 0.024, 0.009, 20), fittings, Vector3(0, -0.187, 0.002))
	_add_part(dagger, "IronPommel", _cylinder(0.025, 0.019, 0.018, 12), fittings, Vector3(0, -0.200, 0.002))
	for marker_name: String in ["BladeTip", "HandGrip"]:
		var marker := Marker3D.new()
		marker.name = marker_name
		marker.position = Vector3(0.0, BLADE_LENGTH, 0.0) if marker_name == "BladeTip" else GRIP_CENTER
		dagger.add_child(marker)
	return dagger


static func _material(label: String, color: Color, metalness: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.metallic = metalness
	material.roughness = roughness
	return material


static func _add_part(parent: Node3D, label: String, mesh: Mesh, material: Material, location := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = location
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _cylinder(top_radius: float, bottom_radius: float, height: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func _blade_mesh() -> ArrayMesh:
	# Closed diamond sections keep both cutting edges and the central ridge
	# visible from either side; the final four faces meet one real 3D tip.
	var sections: Array[Vector3] = [
		Vector3(0.0, 0.016, 0.0045),
		Vector3(0.028, 0.021, 0.006),
		Vector3(0.205, 0.015, 0.0045),
		Vector3(0.270, 0.009, 0.003),
	]
	var rings: Array[PackedVector3Array] = []
	for section: Vector3 in sections:
		rings.append(PackedVector3Array([
			Vector3(-section.y, section.x, 0),
			Vector3(0, section.x, section.z),
			Vector3(section.y, section.x, 0),
			Vector3(0, section.x, -section.z),
		]))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index in range(rings.size() - 1):
		for side in range(4):
			var next := (side + 1) % 4
			_triangle(tool, rings[ring_index][side], rings[ring_index + 1][side], rings[ring_index][next])
			_triangle(tool, rings[ring_index][next], rings[ring_index + 1][side], rings[ring_index + 1][next])
	var tip := Vector3(0, BLADE_LENGTH, 0)
	for side in range(4):
		_triangle(tool, rings[-1][side], tip, rings[-1][(side + 1) % 4])
	_triangle(tool, rings[0][0], rings[0][1], rings[0][2])
	_triangle(tool, rings[0][0], rings[0][2], rings[0][3])
	var mesh := tool.commit()
	mesh.resource_name = "IronDagger_DoubleEdgedBlade_32cm"
	return mesh


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot front faces use clockwise winding; the visible normal is opposite
	# the right-handed cross product of the submitted triangle order.
	var normal := (c - a).cross(b - a).normalized()
	for point: Vector3 in [a, b, c]:
		tool.set_normal(normal)
		tool.add_vertex(point)


static func _binding_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 160
	var sides := 5
	var rings: Array[PackedVector3Array] = []
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var angle := TAU * 8.0 * t
		var radial := Vector3(cos(angle), 0, sin(angle))
		var center := Vector3(0, lerpf(-0.181, -0.036, t), 0.002) + radial * lerpf(0.0229, 0.0215, t)
		var ring := PackedVector3Array()
		for side in range(sides):
			var around := TAU * float(side) / float(sides)
			ring.append(center + (radial * cos(around) + Vector3.UP * sin(around)) * 0.00065)
		rings.append(ring)
	for index in range(steps):
		for side in range(sides):
			var next := (side + 1) % sides
			_triangle(tool, rings[index][side], rings[index + 1][side], rings[index][next])
			_triangle(tool, rings[index][next], rings[index + 1][side], rings[index + 1][next])
	var first_center := Vector3(0.0229, -0.181, 0.002)
	var last_center := Vector3(0.0215, -0.036, 0.002)
	for side in range(sides):
		var next := (side + 1) % sides
		_triangle(tool, first_center, rings[0][side], rings[0][next])
		_triangle(tool, last_center, rings[-1][next], rings[-1][side])
	var mesh := tool.commit()
	mesh.resource_name = "IronDagger_LeatherWrap"
	return mesh
