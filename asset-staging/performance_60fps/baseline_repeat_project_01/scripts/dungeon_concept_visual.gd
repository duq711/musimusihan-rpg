extends RefCounted
class_name DungeonConceptVisual

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
static var _stone_variants: Dictionary = {}
static var _blocks: Dictionary = {}


static func stone_material(index := 0) -> StandardMaterial3D:
	var variant := posmod(index, 7)
	if not _stone_variants.has(variant):
		var lightness := 0.22 + float(variant) * 0.018
		_stone_variants[variant] = SURFACES.stone(Color(lightness * 0.94, lightness, lightness * 0.98), 1.7)
	return _stone_variants[variant]


static func chipped_block(size: Vector3, variant := 0) -> ArrayMesh:
	var cache_key := "%s:%d" % [str(size), posmod(variant, 7)]
	if _blocks.has(cache_key):
		return _blocks[cache_key]
	var source := BoxMesh.new()
	source.size = size
	source.subdivide_width = 5
	source.subdivide_height = 5
	source.subdivide_depth = 5
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var radius := minf(0.065, minf(size.x, minf(size.y, size.z)) * 0.18)
	var half := size * 0.5
	for index in vertices.size():
		var point := vertices[index]
		var inner := point.clamp(-half + Vector3.ONE * radius, half - Vector3.ONE * radius)
		var normal := (point - inner).normalized()
		var wear := 0.64 + 0.36 * sin(point.dot(Vector3(19.1, 27.3, 15.7)) + float(variant) * 2.31)
		vertices[index] = inner + normal * radius * (1.0 - wear * 0.25)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := _rebuild_normals(arrays)
	_blocks[cache_key] = mesh
	return mesh


static func _rebuild_normals(arrays: Array) -> ArrayMesh:
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var provisional := ArrayMesh.new()
	provisional.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(provisional, 0)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func _block(parent: Node3D, title: String, position: Vector3, size: Vector3, variant := 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = chipped_block(size, variant)
	node.material_override = stone_material(variant)
	node.position = position
	parent.add_child(node)
	return node


static func _replace_original_meshes(root: Node3D, meta_name: String) -> Node3D:
	if root.has_meta(meta_name):
		return null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false
	var art := Node3D.new()
	art.name = meta_name.to_pascal_case()
	root.add_child(art)
	root.set_meta(meta_name, true)
	return art


static func apply_archway(model: Node3D) -> void:
	var art := _replace_original_meshes(model, "pointed_arch_masonry")
	if art == null:
		return
	for side in [-1.0, 1.0]:
		for row in 7:
			for column in 2:
				_block(art, "Jamb_%s_%d_%d" % [str(side), row, column], Vector3(side * (1.10 + float(column) * 0.47), 0.16 + float(row) * 0.405, 0.0), Vector3(0.465, 0.397, 0.42), row + column)
		for front in [-1.0, 1.0]:
			for row in 5:
				_block(art, "CarvedJambMoulding", Vector3(side * 0.92, 0.37 + row * 0.36, front * 0.23), Vector3(0.12, 0.352, 0.11), row)
		_block(art, "ArchFoot", Vector3(side * 1.30, 0.09, 0), Vector3(1.03, 0.18, 0.60), 3)
		_block(art, "ArchFootMoulding", Vector3(side * 1.30, 0.23, 0), Vector3(0.96, 0.09, 0.53), 4)
		_block(art, "ArchImpost", Vector3(side * 1.16, 2.025, 0), Vector3(0.62, 0.13, 0.60), 4)
		_block(art, "UpperJambClosure", Vector3(side * 1.335, 2.85, 0), Vector3(0.95, 0.16, 0.41), 2)
	for index in 8:
		_block(art, "Coping_%d" % index, Vector3(-1.75 + index * 0.50, 3.03, 0), Vector3(0.492, 0.23, 0.44), index)
	for front in [-1.0, 1.0]:
		add_pointed_ring(art, Vector3(0, 1.99, front * 0.23), 0.86, 1.03, 0.17, 0.13)
	add_pointed_ring(art, Vector3(0, 1.99, 0), 1.00, 1.13, 0.25, 0.47)
	for side in [-1.0, 1.0]:
		for row in 3:
			var t := float(row) / 3.0
			_block(art, "Spandrel", Vector3(side * (1.18 - t * 0.17), 2.34 + row * 0.25, 0), Vector3(0.34 + t * 0.26, 0.245, 0.38), row)


static func add_pointed_ring(parent: Node3D, origin: Vector3, width: float, rise: float, thickness: float, depth: float) -> void:
	for side in [-1.0, 1.0]:
		for index in 10:
			var source := BoxMesh.new()
			source.size = Vector3.ONE
			source.subdivide_width = 3
			var arrays := source.get_mesh_arrays()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices.size():
				var p := vertices[vertex]
				var t := (float(index) + 0.025 + (p.x + 0.5) * 0.95) / 10.0
				if side > 0:
					t = (float(index) + 0.025 + (0.5 - p.x) * 0.95) / 10.0
				var center := Vector2(width * (1.0 - t) * (1.0 + 0.70 * t), rise * (1.30 * t - 0.30 * t * t))
				var tangent := Vector2(width * (-0.30 - 1.40 * t), rise * (1.30 - 0.60 * t))
				var outward := Vector2(tangent.y, -tangent.x).normalized()
				var q := center + outward * p.y * thickness
				vertices[vertex] = Vector3(side * q.x, q.y, p.z * depth)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var node := MeshInstance3D.new()
			node.name = "PointedVoussoir"
			node.mesh = _rebuild_normals(arrays)
			node.material_override = stone_material(index)
			node.position = origin
			parent.add_child(node)


static func apply_pillar(model: Node3D) -> void:
	var art := _replace_original_meshes(model, "clustered_column_masonry")
	if art == null:
		return
	_block(art, "CapitalStoneCore", Vector3(0, 2.81, 0), Vector3(0.66, 0.58, 0.66), 1)
	for data in [[0.11, 0.92, 0.22], [0.28, 0.84, 0.10], [0.39, 0.72, 0.12], [0.51, 0.68, 0.10], [2.59, 0.72, 0.12], [2.77, 0.79, 0.18], [2.94, 0.89, 0.12], [3.06, 0.94, 0.10]]:
		_block(art, "CarvedColumnMoulding", Vector3.UP * float(data[0]), Vector3(data[1], data[2], data[1]), int(float(data[0]) * 11))
	for row in 4:
		for index in 5:
			var angle := float(index) * TAU / 4.0
			var center := Vector3.ZERO if index == 4 else Vector3(cos(angle), 0, sin(angle)) * 0.18
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.165 if index < 4 else 0.25
			mesh.bottom_radius = mesh.top_radius * 1.01
			mesh.height = 0.496
			mesh.radial_segments = 20
			var drum := MeshInstance3D.new()
			drum.name = "ClusteredColumnDrum"
			drum.mesh = mesh
			drum.position = center + Vector3.UP * (0.80 + float(row) * 0.505)
			drum.material_override = stone_material(row + index)
			art.add_child(drum)


static func apply_stairs(model: Node3D) -> void:
	var art := _replace_original_meshes(model, "worn_step_masonry")
	if art == null:
		return
	for step in 10:
		var height := 0.20 * float(step + 1)
		var z := 1.71 - float(step) * 0.38
		for column in 3:
			_block(art, "WornTread", Vector3(-0.67 + column * 0.67, height * 0.5, z), Vector3(0.665, height, 0.414), step + column)
		for side in [-1.0, 1.0]:
			for row in step + 1:
					_block(art, "StairSideMasonry", Vector3(side * 1.10, 0.10 + float(row) * 0.20, z), Vector3(0.25, 0.198, 0.375), step + row)


static func apply_portal(model: Node3D) -> void:
	if model.has_meta("pointed_portal_masonry"):
		return
	model.set_meta("pointed_portal_masonry", true)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if str(mesh.name).begins_with("Voussoir"):
			mesh.visible = false
		elif mesh.visible and (str(mesh.name).begins_with("Threshold") or str(mesh.name).begins_with("Pier")):
			var bounds := mesh.mesh.get_aabb()
			mesh.mesh = chipped_block(bounds.size, str(mesh.name).hash())
			mesh.position += mesh.basis * bounds.get_center()
			mesh.material_override = stone_material(str(mesh.name).hash())
	add_pointed_ring(model, Vector3(0, 2.23, 0), 1.06, 1.18, 0.42, 0.65)
	for front in [-1.0, 1.0]:
		add_pointed_ring(model, Vector3(0, 2.23, front * 0.34), 0.93, 1.10, 0.11, 0.12)
		for side in [-1.0, 1.0]:
			_block(model, "PortalJambMoulding", Vector3(side * 0.91, 1.25, front * 0.34), Vector3(0.13, 1.95, 0.11), 3)
		_block(model, "PortalKeystone", Vector3(0, 3.48, front * 0.35), Vector3(0.21, 0.28, 0.14), 4)


static func create_architecture(size: Vector3, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case() + "Concept"
	root.set_meta("architecture_kind", kind)
	if kind == "broken_altar":
		_add_altar(root, size)
	elif kind == "wet_flagstone_floor" or kind == "crypt_ceiling":
		_add_paving(root, size, kind == "crypt_ceiling")
	else:
		_add_masonry(root, size)
	return root


static func _add_masonry(root: Node3D, size: Vector3) -> void:
	var along_x := size.x >= size.z
	var backing_size := size * (Vector3(1.0, 1.0, 0.75) if along_x else Vector3(0.75, 1.0, 1.0))
	_add_mortar_core(root, backing_size)
	_add_mortar_perimeter(root, size, 2 if along_x else 0)
	var span := size.x if along_x else size.z
	var depth := size.z if along_x else size.x
	var columns := maxi(1, ceili(span / 0.75))
	var rows := maxi(1, ceili(size.y / 0.43))
	var pitch_x := span / float(columns)
	var pitch_y := size.y / float(rows)
	# Single combined mesh retains visual joints without hundreds of draw calls.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows:
		for column in columns + (row % 2):
			var left := maxf(-span * 0.5, -span * 0.5 + (column - float(row % 2) * 0.5) * pitch_x)
			var right := minf(span * 0.5, -span * 0.5 + (column + 1 - float(row % 2) * 0.5) * pitch_x)
			if right - left < 0.025:
				continue
			var block_size := Vector3(right - left - 0.016, pitch_y - 0.015, depth)
			var at := Vector3((left + right) * 0.5, -size.y * 0.5 + (row + 0.5) * pitch_y, 0)
			if not along_x:
				block_size = Vector3(depth, pitch_y - 0.015, right - left - 0.016)
				at = Vector3(0, at.y, (left + right) * 0.5)
			tool.append_from(chipped_block(block_size, row + column), 0, Transform3D(Basis.IDENTITY, at))
	var mesh := MeshInstance3D.new()
	mesh.name = "BondedMasonryBlocks"
	mesh.mesh = tool.commit()
	mesh.material_override = stone_material(2)
	root.add_child(mesh)


static func _add_paving(root: Node3D, size: Vector3, ceiling: bool) -> void:
	_add_mortar_core(root, size * Vector3(1.0, 0.75, 1.0))
	_add_mortar_perimeter(root, size, 1)
	var columns := maxi(1, ceili(size.x / 0.83))
	var rows := maxi(1, ceili(size.z / 0.95))
	var pitch := Vector2(size.x / columns, size.z / rows)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows:
		for column in columns:
			var at := Vector3(-size.x * 0.5 + (column + 0.5) * pitch.x, 0, -size.z * 0.5 + (row + 0.5) * pitch.y)
			tool.append_from(chipped_block(Vector3(pitch.x - 0.012, size.y, pitch.y - 0.012), row + column), 0, Transform3D(Basis.IDENTITY, at))
	var slabs := MeshInstance3D.new()
	slabs.name = "FlagstoneSlabs"
	slabs.mesh = tool.commit()
	slabs.material_override = stone_material(1)
	root.add_child(slabs)
	if ceiling:
		var ribs := maxi(2, ceili(size.x / 3.0))
		for rib in ribs:
			_block(root, "CeilingRib", Vector3(-size.x * 0.5 + (rib + 0.5) * size.x / ribs, -size.y * 0.5 - 0.025, 0), Vector3(0.19, 0.09, size.z), rib)


static func _add_mortar_core(root: Node3D, size: Vector3) -> void:
	# Recessed mortar closes the visual joints inside the unchanged collider.
	var node := MeshInstance3D.new()
	node.name = "RecessedMortarCore"
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = SURFACES.stone(Color(0.10, 0.115, 0.11), 2.0)
	root.add_child(node)


static func _add_mortar_perimeter(root: Node3D, size: Vector3, normal_axis: int) -> void:
	# Adjacent room panels meet at the original box boundary. A recessed core
	# alone leaves a diagonal escape path behind their worn edges. This narrow
	# opaque border reaches that boundary without changing the room or collider.
	var first_axis := 1 if normal_axis == 0 else 0
	var second_axis := 1 if normal_axis == 2 else 2
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis: int in [first_axis, second_axis]:
		var strip_size := size
		strip_size[axis] = minf(0.028, size[axis] * 0.04)
		var box := BoxMesh.new()
		box.size = strip_size
		for side in [-1.0, 1.0]:
			var at := Vector3.ZERO
			at[axis] = side * (size[axis] - strip_size[axis]) * 0.5
			tool.append_from(box, 0, Transform3D(Basis.IDENTITY, at))
	var node := MeshInstance3D.new()
	node.name = "MortarBoundarySeal"
	node.mesh = tool.commit()
	node.material_override = SURFACES.stone(Color(0.10, 0.115, 0.11), 2.0)
	root.add_child(node)


static func _add_altar(root: Node3D, size: Vector3) -> void:
	_block(root, "AltarCore", Vector3.ZERO, size * Vector3(0.88, 0.74, 0.87), 0)
	for side in [-1.0, 1.0]:
		_block(root, "AltarMoulding", Vector3(0, side * size.y * 0.43, 0), Vector3(size.x, size.y * 0.14, size.z), 4)
		_block(root, "AltarInnerMoulding", Vector3(0, side * size.y * 0.32, 0), Vector3(size.x * 0.96, size.y * 0.07, size.z * 0.96), 2)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_block(root, "AltarCarvedPier", Vector3(x * size.x * 0.42, 0, z * size.z * 0.40), Vector3(size.x * 0.09, size.y * 0.61, size.z * 0.13), 3)
	for front in [-1.0, 1.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = size.y * 0.18
		ring.outer_radius = size.y * 0.197
		ring.rings = 32
		ring.ring_segments = 6
		var medallion := MeshInstance3D.new()
		medallion.name = "WornAltarMedallion"
		medallion.mesh = ring
		medallion.material_override = stone_material(3)
		medallion.rotation.x = PI * 0.5
		medallion.position.z = front * size.z * 0.44
		root.add_child(medallion)


static func arch_wedge(half_width: float, rise: float, index: int, count: int) -> ArrayMesh:
	var source := BoxMesh.new()
	source.size = Vector3.ONE
	source.subdivide_width = 3
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices.size():
		var p := vertices[vertex]
		var angle := PI * (float(index) + 0.03 + (0.5 - p.x) * 0.94) / float(count)
		vertices[vertex] = Vector3(cos(angle) * (half_width + p.y * 0.38), sin(angle) * (rise + p.y * 0.38), p.z * 0.62)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return _rebuild_normals(arrays)


static func irregular_patch(size: Vector2, relief := 0.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 48:
		var a0 := float(index) * TAU / 48.0
		var a1 := float(index + 1) * TAU / 48.0
		for angle in [a0, a1, -1.0]:
			var radius := 0.48 * (0.90 + sin(angle * 5.0 + 0.8) * 0.065 + sin(angle * 11.0) * 0.035)
			var point := Vector3(cos(angle) * radius * size.x, sin(angle) * radius * size.y, 0) if angle >= 0 else Vector3(0, 0, relief)
			surface.set_normal(Vector3.FORWARD)
			surface.set_uv(Vector2(point.x / size.x + 0.5, point.y / size.y + 0.5))
			surface.add_vertex(point)
	return surface.commit()
