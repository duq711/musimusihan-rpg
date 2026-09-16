extends RefCounted
## Physical surface erosion for this hideout only. Original catalog meshes,
## panel backings, light-occlusion boxes and gameplay shapes remain immutable.
## Call after roof apertures and before material weathering and stone batching.

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _noise: FastNoiseLite


static func weather_geometry(root: Node) -> int:
	var changed := 0
	if root is MeshInstance3D and str(root.name) in ["BondedMasonryBlocks", "FlagstoneSlabs"]:
		var instance := root as MeshInstance3D
		if not instance.has_meta("hideout_eroded_geometry") and instance.mesh is ArrayMesh and instance.mesh.get_surface_count() == 1:
			var source := instance.mesh as ArrayMesh
			var kind := "wall"
			var cursor := instance.get_parent()
			while cursor != null:
				if cursor.has_meta("architecture_kind"):
					var architecture := str(cursor.get_meta("architecture_kind"))
					if architecture == "wet_flagstone_floor":
						kind = "floor"
					elif architecture == "crypt_ceiling":
						kind = "ceiling"
					break
				cursor = cursor.get_parent()
			var at := _authored_position(instance)
			var variant := posmod(int(round(at.x * 3.7 + at.z * 2.3)), 5)
			var eroded := erode_mesh(source, kind, variant)
			if eroded != null:
				var material := instance.get_active_material(0) as StandardMaterial3D
				instance.mesh = eroded
				if material != null:
					instance.material_override = _vertex_material(material)
				instance.set_meta("hideout_eroded_geometry", {"kind": kind, "source_mesh": source, "variant": variant, "max_displacement": eroded.get_meta("hideout_erosion_max_displacement", 0.0)})
				changed += 1
	for child in root.get_children():
		changed += weather_geometry(child)
	return changed


static func erode_mesh(source: ArrayMesh, kind: String, variant := 0) -> ArrayMesh:
	if source == null or source.get_surface_count() != 1 or source.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES or kind not in ["wall", "floor", "ceiling"]:
		return null
	variant = posmod(variant, 5)
	var key := "%d:%s:%d" % [source.get_instance_id(), kind, variant]
	if _meshes.has(key):
		return _meshes[key] as ArrayMesh
	var arrays: Array = source.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return null
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	var bounds := source.get_aabb()
	var extent := bounds.size
	var surface_axis := 1 if kind != "wall" else (0 if extent.x < extent.z else 2)
	var first_axis := 1 if surface_axis == 0 else 0
	var second_axis := 1 if surface_axis == 2 else 2
	var center := bounds.get_center()
	var offset := Vector3(17.3, 4.9, 12.1) * float(variant + 1)
	var strength := 0.44 if kind == "floor" else (1.1 if kind == "ceiling" else 1.0)
	var limit := 0.027 if kind == "floor" else 0.067
	var maximum := 0.0
	for index in vertices.size():
		var point := vertices[index]
		var sample := point + offset
		# A shared positional field preserves coincident face corners. Coarse
		# chips alter the actual triangulated silhouette, fine scars break the
		# original uniformly rounded surfaces, and fissures cut shallow facets.
		var coarse := _sample(sample * 2.8)
		var fine := _sample(sample * 12.7 + Vector3(0.0, 16.2, 0.0))
		var ridge := absf(_sample(sample * 4.8 + Vector3(9.1, 0.0, 2.7)))
		var scar := pow(clampf(1.0 - ridge * 5.0, 0.0, 1.0), 3.0)
		var relief := (coarse * 0.038 + fine * 0.016 - scar * 0.030) * strength
		var orientation := signf(point[surface_axis] - center[surface_axis])
		var delta := Vector3.ZERO
		delta[surface_axis] = relief * orientation
		delta[first_axis] = _sample(sample * 5.1 + Vector3(7.0, 1.0, 0.0)) * 0.013 * strength
		delta[second_axis] = _sample(sample * 5.7 + Vector3(0.0, 3.0, 11.0)) * 0.013 * strength
		# Original boundary seals still close adjacent rooms. Anchor the outer
		# six centimeters of each assembled panel to that unchanged perimeter.
		var edge_distance := minf(minf(point[first_axis] - bounds.position[first_axis], bounds.end[first_axis] - point[first_axis]), minf(point[second_axis] - bounds.position[second_axis], bounds.end[second_axis] - point[second_axis]))
		delta *= smoothstep(0.0, 0.065, edge_distance)
		delta = delta.limit_length(limit)
		vertices[index] = point + delta
		maximum = maxf(maximum, delta.length())
		# Multiplicative muted mineral variations are local to the copied mesh;
		# the original catalog material/mesh never receives vertex-color edits.
		var variation := clampf(0.91 + _sample(sample * 1.9) * 0.15 + fine * 0.045 - scar * 0.055, 0.70, 1.07)
		colors[index] = Color(variation * 0.97, variation, variation * 0.98, 1.0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var provisional := ArrayMesh.new()
	provisional.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(provisional, 0)
	tool.generate_normals()
	if arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty():
		tool.generate_tangents()
	var mesh := tool.commit()
	mesh.resource_name = "HideoutEroded_%s_%d" % [kind, variant]
	mesh.surface_set_material(0, source.surface_get_material(0))
	mesh.set_meta("hideout_erosion_max_displacement", maximum)
	mesh.set_meta("hideout_erosion_source", source)
	mesh.set_meta("hideout_erosion_vertex_count", vertices.size())
	_meshes[key] = mesh
	return mesh


static func _sample(point: Vector3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 481729
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return _noise.get_noise_3dv(point)


static func _vertex_material(source: StandardMaterial3D) -> StandardMaterial3D:
	var key := source.get_instance_id()
	if not _materials.has(key):
		var material := source.duplicate() as StandardMaterial3D
		material.resource_name = "HideoutMineralVariance_" + source.resource_name
		material.vertex_color_use_as_albedo = true
		_materials[key] = material
	return _materials[key] as StandardMaterial3D


static func _authored_position(node: Node3D) -> Vector3:
	var transform := node.transform
	var cursor := node.get_parent()
	while cursor is Node3D:
		transform = (cursor as Node3D).transform * transform
		cursor = cursor.get_parent()
	return transform.origin
