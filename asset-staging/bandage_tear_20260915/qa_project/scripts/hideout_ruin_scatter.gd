extends RefCounted
## Static, deterministic decorative chips. Bounds and points are region-local;
## gameplay collision, room transforms, and interaction areas remain untouched.

const CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const MATERIALS := preload("res://scripts/hideout_ruin_materials.gd")
const NODE_NAME := "RuinScatteredStoneChips"
const EDGE_INSET := 0.65
const COUNTS := {"central": 45, "entrance": 32, "sleep": 31, "storage": 36, "workshop": 32, "flooded_store": 39, "ossuary": 43, "drain": 28}


static func build(region_id: String, dressing: Node3D, bounds: AABB) -> void:
	if dressing == null or not COUNTS.has(region_id) or dressing.has_node(NODE_NAME):
		return
	var inset := Rect2(Vector2(bounds.position.x, bounds.position.z) + Vector2.ONE * EDGE_INSET,
		Vector2(bounds.size.x, bounds.size.z) - Vector2.ONE * EDGE_INSET * 2.0)
	if region_id == "entrance":
		# The staircase rises after this vestibule. Keep flat chips on its floor.
		inset.size.y = minf(inset.end.y, 19.15) - inset.position.y
	if inset.size.x <= 0.5 or inset.size.y <= 0.5:
		return
	var rng := RandomNumberGenerator.new()
	var seed_value := 202609093 + int(region_id.hash())
	rng.seed = seed_value
	var anchors: Array[Vector3] = []
	for child in dressing.get_children():
		if child is Node3D and str(child.get_meta("ruin_prop", "")) in ["edge", "arch", "rubble"]:
			anchors.append(dressing.transform * (child as Node3D).position)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array()
	var sizes := PackedVector3Array()
	var wanted := int(COUNTS[region_id])
	var into_dressing := dressing.transform.affine_inverse()
	for attempt in 4096:
		if points.size() >= wanted:
			break
		var candidate := _candidate(rng, inset, anchors)
		if _reserved(region_id, candidate):
			continue
		var crowded := false
		for previous in points:
			if Vector2(previous.x, previous.z).distance_to(candidate) < 0.115:
				crowded = true
				break
		if crowded:
			continue
		var width := rng.randf_range(0.08, 0.28)
		var size_value := Vector3(width, rng.randf_range(0.03, 0.08), rng.randf_range(0.07, minf(width * 1.1, 0.24)))
		var chip := CONCEPT.chipped_block(size_value, rng.randi_range(0, 6))
		var orientation := Basis.from_euler(Vector3(rng.randf_range(-0.055, 0.055), rng.randf_range(-PI, PI), rng.randf_range(-0.055, 0.055)))
		var rotated_bounds := Transform3D(orientation, Vector3.ZERO) * chip.get_aabb()
		var position := Vector3(candidate.x, 0.014 - rotated_bounds.position.y, candidate.y)
		tool.append_from(chip, 0, into_dressing * Transform3D(orientation, position))
		points.append(position)
		sizes.append(size_value)
	if points.is_empty():
		return
	var merged := tool.commit()
	# Match the Blender kit's vertex-tinted limestone slot. All geometry above
	# came from the original chipped-block mesh and is now one joined surface.
	var arrays := merged.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index in vertices.size():
		var grain := 0.82 + 0.14 * sin(vertices[index].dot(Vector3(21.7, 13.4, 17.1)))
		colors[index] = Color(0.68 * grain, 0.70 * grain, 0.64 * grain, 1.0)
	arrays[Mesh.ARRAY_COLOR] = colors
	merged.clear_surfaces()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh := MeshInstance3D.new()
	mesh.name = NODE_NAME
	mesh.mesh = merged
	mesh.material_override = MATERIALS.ruin_material("ruin_stone")
	mesh.layers = 1
	mesh.visibility_range_end = 42.0
	mesh.visibility_range_end_margin = 4.0
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("ruin_scatter", true)
	mesh.set_meta("ruin_scatter_region", region_id)
	mesh.set_meta("ruin_scatter_count", points.size())
	mesh.set_meta("ruin_scatter_seed", seed_value)
	mesh.set_meta("ruin_scatter_centers", points)
	mesh.set_meta("ruin_scatter_sizes", sizes)
	mesh.set_meta("ruin_scatter_boundary_margin", 0.45)
	dressing.add_child(mesh)
	dressing.set_meta("ruin_scatter_count", points.size())


static func _candidate(rng: RandomNumberGenerator, inset: Rect2, anchors: Array[Vector3]) -> Vector2:
	var point: Vector2
	if not anchors.is_empty() and rng.randf() < 0.52:
		var anchor := anchors[rng.randi_range(0, anchors.size() - 1)]
		var angle := rng.randf_range(-PI, PI)
		var radius := rng.randf_range(0.36, 1.36)
		point = Vector2(anchor.x, anchor.z) + Vector2(cos(angle), sin(angle)) * radius
	else:
		point = Vector2(rng.randf_range(inset.position.x, inset.end.x), rng.randf_range(inset.position.y, inset.end.y))
		var strip := rng.randf_range(0.0, minf(0.72, minf(inset.size.x, inset.size.y) * 0.21))
		match rng.randi_range(0, 3):
			0: point.x = inset.position.x + strip
			1: point.x = inset.end.x - strip
			2: point.y = inset.position.y + strip
			3: point.y = inset.end.y - strip
	return point.clamp(inset.position, inset.end)


static func _reserved(region_id: String, p: Vector2) -> bool:
	match region_id:
		"central":
			return absf(p.x) < 2.0 or absf(p.y - 5.0) < 1.35 or absf(p.y + 5.0) < 1.35
		"entrance":
			return absf(p.x) < 1.60
		"sleep":
			return absf(p.y - 5.0) < 0.85 or Rect2(-14.9, 5.4, 4.7, 2.9).has_point(p) \
				or Rect2(-14.7, 2.2, 2.3, 1.9).has_point(p) or Rect2(-10.1, 1.9, 1.7, 1.8).has_point(p)
		"storage":
			return absf(p.y - 5.0) < 0.85 or Rect2(10.6, 2.1, 2.1, 6.8).has_point(p)
		"workshop":
			return absf(p.y + 5.0) < 0.95 or Rect2(9.5, -8.1, 5.2, 2.3).has_point(p) \
				or Rect2(9.05, -4.0, 4.2, 2.5).has_point(p) or Rect2(14.2, -4.0, 1.6, 2.1).has_point(p)
		"flooded_store":
			return absf(p.y + 5.0) < 0.85 or Rect2(-10.65, -7.9, 2.1, 1.8).has_point(p)
		"ossuary":
			return absf(p.x) < 1.85
		"drain":
			return absf(p.y + 5.0) < 0.85
	return true
