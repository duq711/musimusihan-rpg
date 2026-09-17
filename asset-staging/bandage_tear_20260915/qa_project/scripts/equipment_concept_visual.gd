extends RefCounted
## Equipment-only art; the player's completed body, arms and grip frames stay owned
## by their appearance code. Every call is shared by gameplay and the art gallery.
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")


static func apply_sword(model: Node3D) -> void:
	if model.has_meta("concept_equipment"):
		return
	model.set_meta("concept_equipment", "rusted_longsword")
	var iron := SURFACES.pitted_iron(Color(0.47, 0.48, 0.46), 3.2)
	var leather := SURFACES.leather(Color(0.12, 0.095, 0.070), 5.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var label := str(node.name)
		if label.begins_with("RustBloom") or label.begins_with("GuardLeft") or label.begins_with("GuardRight"):
			node.visible = false
		elif label.begins_with("Grip"):
			node.material_override = leather
		else:
			node.material_override = iron
	var blade := model.find_child("PittedBlade", true, false) as MeshInstance3D
	if blade:
		# Match the existing gameplay blade's exact extents while giving its edges
		# a physically beveled cross section instead of a rectangular slab.
		blade.mesh = _blade_mesh()
		var steel := SURFACES.pitted_iron(Color(0.66, 0.68, 0.66), 5.0)
		steel.albedo_color = Color(0.79, 0.82, 0.80)
		steel.metallic = 0.65
		steel.roughness = 0.57
		steel.normal_scale = 0.12
		blade.material_override = steel
	for label in ["FullerFront", "FullerBack"]:
		var fuller := model.find_child(label, true, false) as MeshInstance3D
		if fuller:
			fuller.scale.z = 0.3
			fuller.position.z = signf(fuller.position.z) * 0.0165
	var pommel := model.find_child("Pommel", true, false) as MeshInstance3D
	if pommel:
		var shape := CylinderMesh.new()
		shape.top_radius = 0.049
		shape.bottom_radius = 0.049
		shape.height = 0.044
		shape.radial_segments = 8
		pommel.mesh = shape
		pommel.scale = Vector3.ONE
		pommel.position.y = -0.374
		pommel.rotation.x = PI * 0.5


static func apply_shield(model: Node3D) -> void:
	if model.has_meta("concept_equipment"):
		return
	model.set_meta("concept_equipment", "weathered_round_shield")
	var oak := SURFACES.old_oak(Color(0.30, 0.28, 0.24), 2.4)
	oak.normal_scale = 0.28
	var iron := SURFACES.pitted_iron(Color(0.40, 0.42, 0.40), 3.4)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var label := str(node.name)
		if label == "WoodenCore" or label.begins_with("PlankSeam") or label in ["VerticalBrace", "HorizontalBrace"]:
			node.visible = false
		elif label.begins_with("Rear"):
			node.material_override = SURFACES.leather()
			if label in ["RearGrip", "RearArmStrap"]:
				# Keep mounting frames used by the hand pose, and give the leather
				# real clearance from the back instead of solid rectangular blocks.
				node.mesh = _leather_loop(0.31 if label == "RearGrip" else 0.34, 0.041 if label == "RearGrip" else 0.066)
		else:
			node.material_override = iron
		if label == "IronRim":
			node.mesh = _shield_rim()
			node.transform = Transform3D.IDENTITY
		elif label == "Boss":
			node.position.z = 0.051
			node.scale = Vector3(0.21, 0.21, 0.10)
		elif label.begins_with("Rivet"):
			var angle := TAU * float(label.trim_prefix("Rivet").to_int()) / 8.0
			node.position = Vector3(cos(angle) * 0.117, sin(angle) * 0.117, 0.050)
			node.scale = Vector3(0.012, 0.012, 0.009)
	var boss_mount := CylinderMesh.new()
	boss_mount.top_radius = 0.130
	boss_mount.bottom_radius = 0.130
	boss_mount.height = 0.012
	boss_mount.radial_segments = 48
	var boss_plate := _add(model, "ConceptBossMount", boss_mount, iron, Vector3(0, 0, 0.040))
	boss_plate.rotation.x = PI * 0.5
	# Separate closed boards continue around both faces and the thin cut edges.
	for index in range(8):
		var x0 := -0.455 + float(index) * 0.11375 + 0.002
		var x1 := minf(0.455, x0 + 0.10975)
		var points := PackedVector2Array()
		for step in range(9):
			var x := lerpf(x0, x1, float(step) / 8.0)
			points.append(Vector2(x, sqrt(maxf(0.0, 0.455 * 0.455 - x * x))))
		for step in range(8, -1, -1):
			var x := lerpf(x0, x1, float(step) / 8.0)
			points.append(Vector2(x, -sqrt(maxf(0.0, 0.455 * 0.455 - x * x))))
		_add(model, "ConceptOakPlank%02d" % index, _extrude(points, 0.075), oak)
	for y in [-0.22, 0.22]:
		var brace := BoxMesh.new()
		brace.size = Vector3(0.65, 0.055, 0.045)
		_add(model, "ConceptRearBatten", brace, oak, Vector3(0, y, -0.060))
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		var rivet := SphereMesh.new()
		rivet.radius = 0.008
		rivet.height = 0.010
		rivet.radial_segments = 8
		rivet.rings = 4
		var node := _add(model, "ConceptRimRivet%02d" % index, rivet, iron, Vector3(cos(angle) * 0.460, sin(angle) * 0.460, 0.052))
		node.rotation.x = PI * 0.5
	for strap_name in ["RearGrip", "RearArmStrap"]:
		var strap := model.find_child(strap_name, true, false) as MeshInstance3D
		if strap:
			for sign_value in [-1.0, 1.0]:
				var mount := BoxMesh.new()
				mount.size = Vector3(0.061 if strap_name == "RearGrip" else 0.082, 0.040, 0.012)
				_add(strap, "ConceptStrapMount", mount, iron, Vector3(0, sign_value * 0.148, -0.002))


static func apply_torch(model: Node3D) -> void:
	if model.has_meta("concept_equipment"):
		return
	model.set_meta("concept_equipment", "iron_cage_torch")
	var iron := SURFACES.pitted_iron(Color(0.34, 0.35, 0.32), 4.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var label := str(node.name)
		if label.begins_with("Charred"):
			node.material_override = SURFACES.old_oak(Color(0.28, 0.24, 0.18), 3.0)
		elif label.begins_with("Leather"):
			node.material_override = SURFACES.leather(Color(0.09, 0.074, 0.053))
		elif label.begins_with("Iron") or label.begins_with("Cage") or label == "FuelCup":
			node.material_override = iron
	for index in range(6):
		var angle := TAU * float(index) / 6.0
		var prong := model.find_child("CageProng%02d" % index, true, false) as MeshInstance3D
		if prong == null:
			var shape := BoxMesh.new()
			shape.size = Vector3(0.018, 0.34, 0.018)
			prong = _add(model, "CageProng%02d" % index, shape, iron)
		prong.position = Vector3(cos(angle) * 0.115, 1.07, sin(angle) * 0.115)
		prong.rotation = Vector3(sin(angle) * 0.12, 0.0, -cos(angle) * 0.12)
		var rivet := SphereMesh.new()
		rivet.radius = 0.010
		rivet.height = 0.020
		rivet.radial_segments = 8
		rivet.rings = 4
		_add(model, "ConceptCageRivet%02d" % index, rivet, iron, Vector3(cos(angle) * 0.139, 1.22, sin(angle) * 0.139))


static func apply_wall_mount(model: Node3D, wall_depth := 0.28) -> void:
	if model.has_meta("concept_wall_mount"):
		return
	model.set_meta("concept_wall_mount", true)
	var iron := SURFACES.pitted_iron(Color(0.23, 0.235, 0.22), 4.0)
	var plate := BoxMesh.new()
	plate.size = Vector3(0.13, 0.96, 0.028)
	_add(model, "ConceptWallBackplate", plate, iron, Vector3(0, 0.57, -wall_depth))
	for index in range(2):
		var anchor_y := 0.32 + float(index) * 0.42
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step in range(13):
			var t := float(step) / 12.0
			points.append(Vector3(0, anchor_y + sin(t * PI) * (-0.09 if index == 0 else 0.07), lerpf(-0.035, -wall_depth, t)))
			radii.append(0.019)
		_add(model, "ConceptWallCurvedStay%d" % index, _tube(points, radii, 10), iron)
		var collar := TorusMesh.new()
		collar.inner_radius = 0.035
		collar.outer_radius = 0.058
		collar.rings = 32
		collar.ring_segments = 8
		_add(model, "ConceptWallHandleCollar%d" % index, collar, iron, Vector3(0, anchor_y, 0))
	for y in [0.15, 0.99]:
		var rivet := SphereMesh.new()
		rivet.radius = 0.023
		rivet.height = 0.046
		rivet.radial_segments = 10
		rivet.rings = 6
		var fastener := _add(model, "ConceptWallFastener", rivet, iron, Vector3(0, y, -wall_depth + 0.015))
		fastener.scale.z = 0.45


static func apply_staff(model: Node3D) -> void:
	if model.has_meta("concept_equipment"):
		return
	model.set_meta("concept_equipment", "weathered_staff")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var label := str(node.name)
		if label == "StaffShaft" or label.begins_with("CrystalProng"):
			node.material_override = SURFACES.old_oak(Color(0.38, 0.31, 0.23), 3.4)
			if label.begins_with("CrystalProng"):
				node.visible = false
			else:
				var path := PackedVector3Array()
				var radii := PackedFloat32Array()
				for step in range(19):
					var t := float(step) / 18.0
					path.append(Vector3(sin(t * 5.1) * 0.008, -0.65 + t * 1.30, sin(t * 9.0) * 0.004))
					radii.append(lerpf(0.048, 0.034, t) * (1.0 + sin(t * 27.0) * 0.04))
				node.mesh = _tube(path, radii, 14)
		elif label == "StaffLeatherGrip":
			node.material_override = SURFACES.leather()
		elif label.begins_with("StaffIronBand"):
			node.material_override = SURFACES.pitted_iron()
	var crystal := model.find_child("CrackedFocusCrystal", true, false) as MeshInstance3D
	if crystal:
		var mesh := SphereMesh.new()
		mesh.radius = 0.044
		mesh.height = 0.25
		mesh.radial_segments = 6
		mesh.rings = 2
		crystal.mesh = mesh
		crystal.scale = Vector3.ONE
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.16, 0.29, 0.25)
		material.roughness = 0.31
		material.metallic = 0.13
		material.emission_enabled = true
		material.emission = Color(0.10, 0.30, 0.24)
		material.emission_energy_multiplier = 0.65
		crystal.material_override = material
	for index in range(4):
		var angle := TAU * float(index) / 4.0 + 0.35
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step in range(13):
			var t := float(step) / 12.0
			var radial := 0.027 + sin(t * PI * 0.70) * 0.052
			points.append(Vector3(cos(angle) * radial, 0.75 + t * (0.29 + 0.014 * sin(float(index) * 2.0)), sin(angle) * radial))
			radii.append(lerpf(0.022, 0.011, t))
		_add(model, "ConceptFocusBranch%02d" % index, _tube(points, radii, 10), SURFACES.old_oak(Color(0.42, 0.36, 0.29), 4.2))
	for index in range(11):
		var ring := TorusMesh.new()
		ring.inner_radius = 0.056
		ring.outer_radius = 0.060
		ring.rings = 20
		ring.ring_segments = 6
		var wrap := _add(model, "ConceptStaffWrap%02d" % index, ring, SURFACES.leather(), Vector3(0, -0.437 + float(index) * 0.03, 0))
		wrap.rotation.z = 0.16


static func _shield_rim() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 96:
		var a := TAU * float(index) / 96.0
		var b := TAU * float(index + 1) / 96.0
		var ra := Vector3(cos(a), sin(a), 0)
		var rb := Vector3(cos(b), sin(b), 0)
		var normal := (ra + rb).normalized()
		for side in [-1.0, 1.0]:
			var depth := Vector3(0, 0, 0.047 * side)
			_quad_normal(surface, ra * 0.496 + depth, rb * 0.496 + depth, rb * 0.450 + depth, ra * 0.450 + depth, Vector3(0, 0, side))
		for radius in [0.450, 0.496]:
			_quad_normal(surface, ra * radius + Vector3(0, 0, -0.047), rb * radius + Vector3(0, 0, -0.047), rb * radius + Vector3(0, 0, 0.047), ra * radius + Vector3(0, 0, 0.047), normal * (-1.0 if radius < 0.46 else 1.0))
	return surface.commit()


static func _quad_normal(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for triangle in [[a, b, c], [a, c, d]]:
		if (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).dot(normal) > 0:
			triangle.reverse()
		for vertex: Vector3 in triangle:
			surface.set_normal(normal)
			surface.set_uv(Vector2(vertex.x, vertex.y))
			surface.add_vertex(vertex)


static func _leather_loop(length_value: float, width: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in range(20):
		var t0 := float(step) / 20.0
		var t1 := float(step + 1) / 20.0
		var rings: Array[PackedVector3Array] = []
		for t in [t0, t1]:
			var y: float = (t - 0.5) * length_value
			var z: float = -sin(t * PI) * 0.09
			rings.append(PackedVector3Array([Vector3(-width / 2, y, z - 0.006), Vector3(width / 2, y, z - 0.006), Vector3(width / 2, y, z + 0.006), Vector3(-width / 2, y, z + 0.006)]))
		for side in range(4):
			var other := (side + 1) % 4
			_out_tri(surface, rings[0][side], rings[1][other], rings[0][other])
			_out_tri(surface, rings[0][side], rings[1][side], rings[1][other])
		if step == 0:
			_out_tri(surface, rings[0][0], rings[0][2], rings[0][1])
			_out_tri(surface, rings[0][0], rings[0][3], rings[0][2])
		if step == 19:
			_out_tri(surface, rings[1][0], rings[1][1], rings[1][2])
			_out_tri(surface, rings[1][0], rings[1][2], rings[1][3])
	surface.generate_normals()
	return surface.commit()


static func _tube(points: PackedVector3Array, radii: PackedFloat32Array, sides: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(points.size() - 1):
		for side in range(sides):
			var a0 := TAU * float(side) / float(sides)
			var a1 := TAU * float(side + 1) / float(sides)
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			var a := points[row] + n0 * radii[row]
			var b := points[row] + n1 * radii[row]
			var c := points[row + 1] + n1 * radii[row + 1]
			var d := points[row + 1] + n0 * radii[row + 1]
			_out_tri(surface, a, c, b)
			_out_tri(surface, a, d, c)
			if row == 0:
				_out_tri(surface, points[row], a, b)
			if row == points.size() - 2:
				_out_tri(surface, points[row + 1], c, d)
	surface.generate_normals()
	return surface.commit()


static func _blade_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys := [0.04, 0.73, 0.96, 1.085]
	var widths := [0.058, 0.068, 0.050, 0.0]
	for side in [-1.0, 1.0]:
		for row in range(3):
			for half in [-1.0, 1.0]:
				var a := Vector3(0.0, ys[row], side * 0.017)
				var b := Vector3(half * widths[row], ys[row], 0.0)
				var c := Vector3(half * widths[row + 1], ys[row + 1], 0.0)
				var d := Vector3(0.0, ys[row + 1], side * (0.017 if row < 2 else 0.0))
				if side * half > 0:
					_tri(surface, a, c, b)
					_tri(surface, a, d, c)
				else:
					_tri(surface, a, b, c)
					_tri(surface, a, c, d)
	_tri(surface, Vector3(-0.058, 0.04, 0), Vector3(0, 0.04, 0.017), Vector3(0.058, 0.04, 0))
	_tri(surface, Vector3(-0.058, 0.04, 0), Vector3(0.058, 0.04, 0), Vector3(0, 0.04, -0.017))
	surface.generate_normals()
	return surface.commit()


static func _extrude(points: PackedVector2Array, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(points)
	for index in range(0, triangles.size(), 3):
		var a := points[triangles[index]]
		var b := points[triangles[index + 1]]
		var c := points[triangles[index + 2]]
		_tri(surface, Vector3(a.x, a.y, depth * 0.5), Vector3(c.x, c.y, depth * 0.5), Vector3(b.x, b.y, depth * 0.5))
		_tri(surface, Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(c.x, c.y, -depth * 0.5))
	for index in range(points.size()):
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		_tri(surface, Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(b.x, b.y, depth * 0.5))
		_tri(surface, Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(a.x, a.y, depth * 0.5))
	surface.generate_normals()
	return surface.commit()


static func _tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for vertex in [a, b, c]:
		surface.set_uv(Vector2(vertex.x, vertex.y))
		surface.add_vertex(vertex)


static func _add(parent: Node3D, label: String, mesh: Mesh, material: Material, position := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = position
	parent.add_child(node)
	return node


static func _out_tri(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	_tri(surface, a, c, b)
