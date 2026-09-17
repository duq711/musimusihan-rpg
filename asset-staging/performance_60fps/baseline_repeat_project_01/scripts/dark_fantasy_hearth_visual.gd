extends RefCounted
class_name DarkFantasyHearthVisual

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const COAL: Texture2D = preload("res://assets/ai/materials/concept_ember_coal.png")


static func charred_material() -> StandardMaterial3D:
	var material := SURFACES.create("oak", Color(0.52, 0.52, 0.52), COAL, 1.4)
	material.normal_scale = 0.60
	material.roughness = 1.0
	material.metallic_specular = 0.06
	return material


static func charred_log(length: float, radius: float) -> ArrayMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.92
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 14
	cylinder.rings = 4
	var arrays := cylinder.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var p := vertices[index]
		var taper := 0.92 + 0.08 * cos(p.y * 39.0 + atan2(p.z, p.x) * 7.0)
		vertices[index] = Vector3(p.y, -p.x * taper, p.z * taper)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh, 0)
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


static func create_vessel(radius: float, height: float, iron: Material, round_belly: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "OpenIronVessel"
	var wall := minf(0.022, radius * 0.12)
	var profile: Array[Vector2] = []
	var outer: Array[Vector2]
	if round_belly:
		outer = [Vector2(radius * 0.59, -height * 0.5), Vector2(radius * 0.82, -height * 0.38), Vector2(radius, -height * 0.05), Vector2(radius * 0.96, height * 0.25), Vector2(radius * 0.83, height * 0.5)]
	else:
		outer = [Vector2(radius * 0.89, -height * 0.5), Vector2(radius * 0.95, -height * 0.36), Vector2(radius, height * 0.5)]
	profile.append(Vector2(0, -height * 0.5))
	profile.append_array(outer)
	for index in range(outer.size() - 1, -1, -1):
		var p := outer[index]
		profile.append(Vector2(maxf(0.0, p.x - wall), maxf(p.y, -height * 0.5 + wall)))
	profile.append(Vector2(0, -height * 0.5 + wall))
	var body := MeshInstance3D.new()
	body.name = "HollowVesselBody"
	body.mesh = _revolved_shell(profile)
	body.material_override = iron
	root.add_child(body)
	var rim := MeshInstance3D.new()
	rim.name = "RolledVesselRim"
	var torus := TorusMesh.new()
	torus.inner_radius = outer[-1].x - wall * 0.95
	torus.outer_radius = outer[-1].x + wall * 0.35
	torus.rings = 48
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = iron
	rim.position.y = height * 0.5
	root.add_child(rim)
	return root


static func _revolved_shell(profile: Array[Vector2]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in profile.size() - 1:
		for segment in 48:
			var a0 := TAU * float(segment) / 48.0
			var a1 := TAU * float(segment + 1) / 48.0
			var a := Vector3(cos(a0) * profile[row].x, profile[row].y, sin(a0) * profile[row].x)
			var b := Vector3(cos(a1) * profile[row].x, profile[row].y, sin(a1) * profile[row].x)
			var c := Vector3(cos(a1) * profile[row + 1].x, profile[row + 1].y, sin(a1) * profile[row + 1].x)
			var d := Vector3(cos(a0) * profile[row + 1].x, profile[row + 1].y, sin(a0) * profile[row + 1].x)
			# Godot uses clockwise front faces: outer normals point away from
			# the vessel, while the reversed inner profile faces the cavity.
			for point in [a, c, d, a, b, c]:
				surface.set_uv(Vector2(point.x, point.y))
				surface.add_vertex(point)
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


static func add_curved_handle(root: Node3D, title: String, points: PackedVector3Array, radius: float, iron: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size() - 1:
		var from := points[index]
		var to := points[index + 1]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = from.distance_to(to) + radius * 0.25
		cylinder.radial_segments = 8
		surface.append_from(cylinder, 0, Transform3D(Basis(Quaternion(Vector3.UP, (to - from).normalized())), (from + to) * 0.5))
	var handle := MeshInstance3D.new()
	handle.name = title
	handle.mesh = surface.commit()
	handle.material_override = iron
	root.add_child(handle)
	return handle


static func add_pot_bail(root: Node3D, radius: float, height: float, iron: Material) -> void:
	var points := PackedVector3Array()
	for index in 25:
		var angle := PI * float(index) / 24.0
		points.append(Vector3(cos(angle) * radius * 0.91, height * 0.26 + sin(angle) * radius * 0.90, 0))
	add_curved_handle(root, "CurvedPotBail", points, radius * 0.032, iron)
	for side in [-1.0, 1.0]:
		var hook := TorusMesh.new()
		hook.inner_radius = radius * 0.065
		hook.outer_radius = radius * 0.10
		hook.rings = 20
		hook.ring_segments = 6
		var eye := MeshInstance3D.new()
		eye.name = "BailAttachmentEye"
		eye.mesh = hook
		eye.material_override = iron
		eye.position = Vector3(side * radius * 0.91, height * 0.26, 0)
		eye.rotation.z = PI * 0.5
		root.add_child(eye)


static func add_cup_handle(root: Node3D, radius: float, height: float, iron: Material) -> void:
	var points := PackedVector3Array()
	for index in 19:
		var angle := PI * float(index) / 18.0
		points.append(Vector3(radius * 0.96 + sin(angle) * radius * 0.68, cos(angle) * height * 0.29, 0))
	add_curved_handle(root, "CurvedCupHandle", points, radius * 0.10, iron)
