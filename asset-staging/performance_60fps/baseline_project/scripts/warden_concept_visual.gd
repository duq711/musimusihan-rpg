extends RefCounted
## Six-view concept reconstruction for the existing enemy rig. The weapon proxy,
## animation pivots and collision remain the original production objects.
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
static var _iron: StandardMaterial3D
static var _edge: StandardMaterial3D
static var _cloth: StandardMaterial3D
static var _leather: StandardMaterial3D


static func apply(model: Node3D) -> void:
	if model.has_meta("warden_concept_version"):
		return
	model.set_meta("warden_concept_version", 1)
	_prepare_materials()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if not str(node.name).begins_with("Weapon"):
			node.visible = false
	var torso := model.find_child("TorsoPivot", true, false) as Node3D
	var head := model.find_child("HeadPivot", true, false) as Node3D
	_build_head(head)
	_build_torso(torso)
	for side: int in [-1, 1]:
		var arm := model.find_child("ArmLPivot" if side < 0 else "ArmRPivot", true, false) as Node3D
		var leg := model.find_child("LegLPivot" if side < 0 else "LegRPivot", true, false) as Node3D
		_build_arm(arm, side)
		_build_leg(leg, side)


static func _prepare_materials() -> void:
	if _iron != null:
		return
	_iron = SURFACES.pitted_iron(Color(0.52, 0.53, 0.50), 3.3)
	_iron.roughness = 0.78
	_iron.normal_scale = 0.22
	_iron.vertex_color_use_as_albedo = true
	_edge = SURFACES.pitted_iron(Color(0.64, 0.54, 0.38), 4.0)
	_edge.roughness = 0.77
	_cloth = SURFACES.linen(Color(0.17, 0.165, 0.145), 22.0)
	_cloth.albedo_texture = null
	_cloth.albedo_color = Color(0.13, 0.145, 0.14)
	_cloth.normal_scale = 0.15
	_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth.vertex_color_use_as_albedo = true
	_leather = SURFACES.leather(Color(0.16, 0.15, 0.13), 4.0)


static func _build_head(head: Node3D) -> void:
	var hood := _profile([-0.22, -0.06, 0.10, 0.19, 0.27], [0.205, 0.202, 0.19, 0.135, 0.0], [0.225, 0.24, 0.245, 0.19, 0.0], -2.51, 2.51, 56, 6, 0.014)
	_add(head, "ConceptFoldedHood", hood, _cloth, Vector3(0.0, 0.0, -0.028))
	for side: int in [-1, 1]:
		var edge_points: Array[Vector3] = []
		for level in range(17):
			var t := float(level) / 16.0
			var y := lerpf(-0.22, 0.27, t)
			var radius := 0.205 * pow(1.0 - t, 0.45)
			edge_points.append(Vector3(side * radius * 0.59, y, -0.185 - sin(t * PI) * 0.025))
		_add(head, "ConceptHoodRolledSeam%d" % side, _tube(edge_points, 0.010, 8), _cloth)
	# A collar drapes forward beneath the skull and folds back into the cloak.
	_add(head, "ConceptCowlDrapery", _profile([-0.29, -0.24, -0.18], [0.23, 0.27, 0.18], [0.19, 0.215, 0.15], -PI, PI, 40, 4, 0.015), _cloth, Vector3(0, 0, -0.02))
	var skull := preload("res://scripts/dark_fantasy_skull.gd").create(0.29, Color(0.29, 0.28, 0.235))
	skull.name = "ConceptAnatomicalSkull"
	skull.position = Vector3(0.0, -0.008, -0.063)
	head.add_child(skull)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.31, 0.78, 0.73)
	glow.emission_enabled = true
	glow.emission = Color(0.08, 0.53, 0.46)
	glow.emission_energy_multiplier = 1.5
	for side: int in [-1, 1]:
		var sphere := SphereMesh.new()
		sphere.radius = 0.006
		sphere.height = 0.012
		sphere.radial_segments = 12
		sphere.rings = 6
		_add(head, "ConceptFaintEye%d" % side, sphere, glow, Vector3(side * 0.048, 0.035, -0.169))


static func _build_torso(torso: Node3D) -> void:
	_add(torso, "ConceptForgedCuirass", _profile([-0.34, -0.25, -0.09, 0.09, 0.25, 0.32], [0.23, 0.27, 0.32, 0.33, 0.30, 0.21], [0.15, 0.175, 0.205, 0.225, 0.20, 0.135], -PI, PI, 48, 4, 0.004), _iron)
	# Folded chevrons across the breastplate remain surface relief, not floating
	# ornaments. Small rivets catch the same directional light as the plate.
	for side: int in [-1, 1]:
		var points: Array[Vector3] = [Vector3(side * 0.22, 0.27, -0.153), Vector3(side * 0.16, 0.16, -0.212), Vector3(0, 0.10, -0.239)]
		_add(torso, "ConceptBreastplateSeam%d" % side, _tube(points, 0.0055, 6), _edge)
		for index in range(5):
			_rivet(torso, Vector3(side * (0.20 + sin(float(index) * 0.6) * 0.025), 0.22 - index * 0.105, -0.185 - sin(float(index) * 0.6) * 0.035), 0.008)
	_add(torso, "ConceptGorget", _profile([0.30, 0.36, 0.40], [0.205, 0.18, 0.14], [0.145, 0.13, 0.12], -PI, PI, 40, 3), _iron)
	_add(torso, "ConceptWaistBelt", _profile([-0.415, -0.355], [0.26, 0.265], [0.19, 0.19], -PI, PI, 48, 2), _leather)
	_add(torso, "ConceptBeltBuckle", _buckle(), _edge, Vector3(0.0, -0.385, -0.20))
	for side: int in [-1, 1]:
		for row in range(4):
			var angle := side * 0.87
			var top := -0.42 - row * 0.09
			var panel := _profile([top, top - 0.10], [0.30 + row * 0.012, 0.315 + row * 0.012], [0.195, 0.205], angle - 0.33 + PI, angle + 0.33 + PI, 12, 2)
			_add(torso, "ConceptOverlappingTasset%d_%d" % [side, row], panel, _iron)
			_rivet(torso, Vector3(side * 0.265, top - 0.025, -0.16), 0.006)
	_add(torso, "ConceptLongTornCloak", _drapery(0.31, -1.08, 0.27, 0.44, 0.24, 0.36, 31, 31, false), _cloth)
	_add(torso, "ConceptTornFrontTabard", _drapery(-0.41, -1.04, 0.22, 0.28, -0.18, -0.16, 25, 23, true), _cloth)
	for side: int in [-1, 1]:
		_rivet(torso, Vector3(side * 0.25, 0.28, 0.21), 0.016)


static func _build_arm(arm: Node3D, side: int) -> void:
	_add(arm, "ConceptQuiltedSleeve", _profile([-0.11, -0.27, -0.45, -0.65, -0.70], [0.10, 0.105, 0.078, 0.063, 0.055], [0.095, 0.09, 0.075, 0.064, 0.052], -PI, PI, 28, 4, 0.009), _cloth)
	_add(arm, "ConceptPauldronDome", _profile([0.105, 0.07, -0.025, -0.12], [0.0, 0.118, 0.143, 0.132], [0.0, 0.127, 0.156, 0.14], -PI, PI, 48, 6, 0.001), _iron, Vector3(-side * 0.025, 0, 0))
	for index in range(3):
		var y := -0.105 - index * 0.063
		var r := 0.134 - index * 0.016
		_add(arm, "ConceptShoulderLame%d" % index, _profile([y, y - 0.068], [r, r - 0.007], [r * 1.1, r], -PI, PI, 40, 3), _iron, Vector3(-side * 0.018, 0, 0))
		var rim: Array[Vector3] = []
		for arc in range(25):
			var theta := TAU * float(arc) / 24.0
			rim.append(Vector3(sin(theta) * (r - 0.007), y - 0.068, cos(theta) * r * 0.88))
		_add(arm, "ConceptRolledPauldronEdge%d" % index, _tube(rim, 0.0038, 6), _edge)
	_add(arm, "ConceptElbowCop", _profile([-0.35, -0.405, -0.46], [0.066, 0.102, 0.07], [0.08, 0.108, 0.076], -PI, PI, 28, 3), _iron)
	_add(arm, "ConceptTaperedVambrace", _profile([-0.445, -0.50, -0.64, -0.70], [0.085, 0.081, 0.063, 0.059], [0.084, 0.079, 0.067, 0.060], -PI, PI, 32, 4), _iron)
	_add(arm, "ConceptGauntletPalm", _profile([-0.68, -0.73, -0.79], [0.056, 0.069, 0.055], [0.055, 0.045, 0.036], -PI, PI, 24, 3), _leather)
	for digit in range(4):
		var x := -0.043 + digit * 0.027
		for section in range(3):
			var y := -0.775 - section * 0.026
			var r := 0.014 - section * 0.0018
			_add(arm, "ConceptArticulatedFinger%d_%d" % [digit, section], _profile([y, y - 0.032], [r, r * 0.78], [r, r * 0.82], -PI, PI, 12, 2), _iron, Vector3(x, 0, -0.020 - section * 0.005))
	var thumb := _add(arm, "ConceptGauntletThumb", _profile([-0.73, -0.765, -0.805], [0.019, 0.018, 0.013], [0.02, 0.018, 0.013], -PI, PI, 12, 2), _iron, Vector3(-side * 0.061, 0, -0.042))
	thumb.rotation.z = side * -0.13


static func _build_leg(leg: Node3D, _side: int) -> void:
	_add(leg, "ConceptClothLeg", _profile([-0.05, -0.25, -0.45, -0.77], [0.125, 0.115, 0.083, 0.068], [0.115, 0.105, 0.082, 0.075], -PI, PI, 28, 4, 0.007), _cloth)
	_add(leg, "ConceptThighPlate", _profile([-0.14, -0.28, -0.41], [0.126, 0.112, 0.095], [0.118, 0.11, 0.091], -PI, PI, 28, 3), _iron)
	_add(leg, "ConceptKneeCop", _profile([-0.375, -0.43, -0.49], [0.092, 0.116, 0.085], [0.091, 0.125, 0.09], -PI, PI, 32, 3), _iron, Vector3(0, 0, -0.025))
	_add(leg, "ConceptFittedGreave", _profile([-0.46, -0.60, -0.78, -0.83], [0.096, 0.09, 0.068, 0.072], [0.106, 0.10, 0.079, 0.083], -PI, PI, 32, 4), _iron, Vector3(0, 0, -0.018))
	_add(leg, "ConceptBootLeather", _boot_mesh(-0.94, -0.77, false), _leather)
	_add(leg, "ConceptBootSole", _boot_mesh(-0.955, -0.925, true), _leather)
	var underside := _surface(36, 5, func(u: float, v: float) -> Vector3:
		var theta := TAU * u
		var toe := maxf(0.0, -cos(theta))
		return Vector3(sin(theta) * (0.082 + toe * 0.012) * v, -0.956, cos(theta) * (0.125 + toe * 0.095) * v - 0.045))
	_add(leg, "ConceptClosedSoleUnderside", underside, _leather)
	for index in range(4):
		var z := -0.05 - index * 0.065
		var y := -0.79 - index * 0.027
		_add(leg, "ConceptLayeredSabaton%d" % index, _profile([y, y - 0.047], [0.086 - index * 0.004, 0.09 - index * 0.004], [0.045, 0.049], -PI, PI, 28, 2), _iron, Vector3(0, 0, z))
	for index in range(8):
		var tread := BoxMesh.new()
		tread.size = Vector3(0.12, 0.012, 0.018)
		_add(leg, "ConceptSoleTread%d" % index, tread, _leather, Vector3(0, -0.958, -0.25 + index * 0.041))


static func _profile(ys: Array, widths: Array, depths: Array, start: float, end: float, sectors: int, subdivisions: int, folds: float = 0.0) -> ArrayMesh:
	var rows := (ys.size() - 1) * subdivisions
	return _surface(sectors, rows, func(u: float, v: float) -> Vector3:
		var level := v if float(ys[0]) < float(ys[-1]) else 1.0 - v
		var scaled := level * float(ys.size() - 1)
		var segment := mini(ys.size() - 2, floori(scaled))
		var t := scaled - segment
		var theta := lerpf(start, end, u)
		var w := lerpf(float(widths[segment]), float(widths[segment + 1]), t)
		var d := lerpf(float(depths[segment]), float(depths[segment + 1]), t)
		var pleat := folds * (sin(theta * 11.0 + v * 3.0) + 0.35 * sin(theta * 23.0 - v * 8.0))
		var ridge := maxf(0.0, -cos(theta))
		return Vector3(sin(theta) * (w + pleat), lerpf(float(ys[segment]), float(ys[segment + 1]), t), cos(theta) * (d + pleat) - pow(ridge, 14) * 0.010))


static func _drapery(top: float, bottom: float, top_width: float, bottom_width: float, top_z: float, bottom_z: float, columns: int, rows: int, front: bool) -> ArrayMesh:
	return _surface(columns, rows, func(u: float, v: float) -> Vector3:
		var across := u * 2.0 - 1.0
		var ragged := 0.04 * sin(u * 23.0 + 1.2) + 0.027 * sin(u * 143.0 + 2.0) + 0.018 * sin(u * 267.0)
		var w := lerpf(top_width, bottom_width, v)
		var y := lerpf(top, bottom + ragged, v)
		var folds := sin(u * 43.0 + v * 1.2) * (0.018 + v * 0.02) + sin(u * 17.0 - v * 2.2) * 0.012
		var wrap := absf(across) * absf(across) * (0.08 if front else -0.11)
		return Vector3(across * w, y, lerpf(top_z, bottom_z, v) + folds + wrap), true)


static func _boot_mesh(low: float, high: float, sole: bool) -> ArrayMesh:
	return _surface(36, 6, func(u: float, v: float) -> Vector3:
		var theta := TAU * u
		var toe := maxf(0.0, -cos(theta))
		var x := sin(theta) * (0.082 + toe * 0.012) * (1.0 if sole else 1.0 - v * 0.08)
		var z := cos(theta) * (0.125 + toe * 0.095) - 0.045
		var y := lerpf(low, high - toe * (0.0 if sole else 0.079), v)
		return Vector3(x, y, z))


static func _surface(columns: int, rows: int, point: Callable, torn: bool = false) -> ArrayMesh:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows):
		for column in range(columns):
			if torn and row > rows * 0.70 and ((column * 17 + row * 7) % 59 == 0 or (row == rows - 1 and column % 7 == 0)):
				continue
			var u0 := float(column) / columns
			var u1 := float(column + 1) / columns
			var v0 := float(row) / rows
			var v1 := float(row + 1) / rows
			var uv := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
			for corner in [0, 2, 1, 0, 3, 2]:
				var at: Vector3 = point.call(uv[corner].x, uv[corner].y)
				var mottling := 0.76 + 0.18 * sin(at.x * 71.0 + at.y * 43.0) * sin(at.z * 89.0 - at.x * 13.0)
				builder.set_color(Color(mottling, mottling * 0.98, mottling * 0.94))
				builder.set_uv(uv[corner] * Vector2(2.0, 3.0))
				builder.add_vertex(at)
	builder.generate_normals()
	builder.generate_tangents()
	return builder.commit()


static func _tube(points: Array[Vector3], radius: float, sides: int) -> ArrayMesh:
	return _surface(sides, points.size() - 1, func(u: float, v: float) -> Vector3:
		var t := v * (points.size() - 1)
		var index := mini(points.size() - 2, floori(t))
		var center := points[index].lerp(points[index + 1], t - index)
		var tangent := (points[index + 1] - points[index]).normalized()
		var axis := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x := tangent.cross(axis).normalized()
		var z := x.cross(tangent).normalized()
		return center + (x * cos(u * TAU) + z * sin(u * TAU)) * radius)


static func _buckle() -> ArrayMesh:
	var points: Array[Vector3] = [Vector3(-0.035, -0.022, 0), Vector3(0.035, -0.022, 0), Vector3(0.035, 0.022, 0), Vector3(-0.035, 0.022, 0), Vector3(-0.035, -0.022, 0)]
	return _tube(points, 0.006, 8)


static func _rivet(parent: Node3D, at: Vector3, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.1
	sphere.radial_segments = 10
	sphere.rings = 5
	var node := _add(parent, "ConceptHandForgedRivet", sphere, _edge, at)
	node.rotation.x = PI * 0.5


static func _add(parent: Node3D, label: String, mesh: Mesh, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
