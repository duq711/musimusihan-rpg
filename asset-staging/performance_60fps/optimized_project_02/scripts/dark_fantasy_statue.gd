extends RefCounted

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")


static func create() -> Node3D:
	var root := Node3D.new()
	root.name = "CarvedSaintFigure"
	var stone := SURFACES.stone(Color(0.28, 0.295, 0.29), 3.2)
	var robe := MeshInstance3D.new()
	robe.name = "SaintRobe"
	robe.mesh = _robe_mesh()
	robe.material_override = stone
	root.add_child(robe)
	for side in [-1.0, 1.0]:
		var sleeve := MeshInstance3D.new()
		sleeve.name = "SaintArmL" if side < 0.0 else "SaintArmR"
		sleeve.mesh = _sleeve_mesh(Vector3(side * 0.37, 2.58, 0.0), Vector3(side * 0.57, 1.91, -0.11))
		sleeve.material_override = stone
		root.add_child(sleeve)
		var forearm := MeshInstance3D.new()
		forearm.name = "BrokenForearm"
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.095
		arm_mesh.bottom_radius = 0.115
		arm_mesh.height = 0.29
		arm_mesh.radial_segments = 12
		forearm.mesh = arm_mesh
		forearm.material_override = stone
		forearm.position = Vector3(side * 0.55, 2.16, -0.23)
		forearm.rotation = Vector3(PI * 0.43, 0.0, side * 0.21)
		root.add_child(forearm)
	return root


static func _robe_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 32:
		for radial in 64:
			var t0 := float(row) / 32.0
			var t1 := float(row + 1) / 32.0
			var a0 := float(radial) / 64.0 * TAU
			var a1 := float(radial + 1) / 64.0 * TAU
			_quad(surface, _robe_point(t0, a0), _robe_point(t0, a1), _robe_point(t1, a1), _robe_point(t1, a0))
	for radial in 64:
		var a0 := float(radial) / 64.0 * TAU
		var a1 := float(radial + 1) / 64.0 * TAU
		var edge0 := _robe_point(1.0, a0)
		var edge1 := _robe_point(1.0, a1)
		var inner0 := Vector3(edge0.x * 0.55, 2.65, edge0.z * 0.55)
		var inner1 := Vector3(edge1.x * 0.55, 2.65, edge1.z * 0.55)
		_quad(surface, edge0, edge1, inner1, inner0)
	surface.generate_normals()
	return surface.commit()


static func _robe_point(t: float, angle: float) -> Vector3:
	var radius := lerpf(0.48, 0.33, smoothstep(0.0, 0.58, t))
	if t > 0.58 and t <= 0.88:
		radius = lerpf(0.33, 0.43, smoothstep(0.58, 0.88, t))
	elif t > 0.88:
		radius = lerpf(0.43, 0.17, smoothstep(0.88, 1.0, t))
	var fold := (sin(angle * 13.0 + sin(t * 4.0) * 0.85) * 0.052 + sin(angle * 9.0 - t * 2.0) * 0.017) * (1.0 - t * 0.3)
	var y := 1.08 + t * 1.75 + sin(angle * 7.0) * 0.036 * pow(t, 12.0) - sin(angle * 5.0) * 0.027 * pow(1.0 - t, 6.0)
	return Vector3(sin(angle) * (radius + fold), y, cos(angle) * (radius * 0.62 + fold))


static func _sleeve_mesh(from: Vector3, to: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	for row in 12:
		for radial in 24:
			var points: Array[Vector3] = []
			for pair in [Vector2(row, radial), Vector2(row, radial + 1), Vector2(row + 1, radial + 1), Vector2(row + 1, radial)]:
				var t: float = pair.x / 12.0
				var angle: float = pair.y / 24.0 * TAU
				var radius := lerpf(0.18, 0.23, t) + sin(angle * 8.0 + t) * 0.024
				points.append(from.lerp(to, t) + along * Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
			_quad(surface, points[0], points[3], points[2], points[1])
	surface.generate_normals()
	return surface.commit()


static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.set_uv(Vector2(vertex.x, vertex.y))
		surface.add_vertex(vertex)
