extends RefCounted
## Localized missing ceiling panels, retaining the exact original solid physics.
## Run after room construction and before weather materials/static batching.
const CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const OPENINGS := {
	"central": [{"xz": Vector2(3.4, 3.0), "size": Vector2(2.7, 3.1)}, {"xz": Vector2(-4.0, -1.0), "size": Vector2(2.3, 2.5)}],
	"entrance": [{"xz": Vector2(2.0, 17.0), "size": Vector2(1.5, 1.9)}],
	"sleep": [{"xz": Vector2(-13.8, 8.1), "size": Vector2(1.25, 1.05)}],
	"storage": [{"xz": Vector2(13.5, 7.5), "size": Vector2(1.7, 1.4)}],
	"workshop": [{"xz": Vector2(14.0, -3.0), "size": Vector2(1.75, 1.2)}],
	"flooded_store": [{"xz": Vector2(-12.8, -6.7), "size": Vector2(2.0, 1.8)}],
	"ossuary": [{"xz": Vector2(3.4, -19.0), "size": Vector2(2.05, 2.4)}],
	"drain": [{"xz": Vector2(21.5, -5.0), "size": Vector2(1.6, 0.9)}],
}


static func build(hideout: Node) -> Dictionary:
	var result := {}
	for room_id: String in OPENINGS:
		var region: Node3D = hideout.region_nodes.get(room_id)
		if region == null:
			continue
		# Batches submit immutable transforms. Never hide a source while its
		# already-submitted copy would keep covering the aperture.
		assert(not region.has_meta("static_stone_batches_built"), "Cut ruin roof openings before stone batching")
		for child in region.get_children():
			if not child is StaticBody3D or not str(child.name).contains("Ceiling"):
				continue
			var body := child as StaticBody3D
			var architecture: Node3D
			var collider: CollisionShape3D
			for part in body.get_children():
				if part is Node3D and str(part.get_meta("architecture_kind", "")) == "crypt_ceiling":
					architecture = part
				elif part is CollisionShape3D and part.shape is BoxShape3D:
					collider = part
			if architecture == null or collider == null:
				continue
			if architecture.has_meta("ruin_roof_openings"):
				result[room_id] = architecture.get_meta("ruin_roof_openings").duplicate(true)
				continue
			var size: Vector3 = collider.shape.size
			var body_xz := Vector2(body.position.x, body.position.z)
			var footprint := Rect2(body_xz - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			var panels: Array[Rect2] = [footprint]
			var holes: Array[Dictionary] = []
			for request: Dictionary in OPENINGS[room_id]:
				var opening := Rect2(request.xz - request.size * 0.5, request.size)
				# Keep a ring within the authored room; never cut a neighboring
				# wall, a ceiling seam, or a streaming-region boundary.
				opening = opening.intersection(footprint.grow(-0.24))
				if not opening.has_area():
					continue
				var remaining: Array[Rect2] = []
				for panel in panels:
					remaining.append_array(subtract_opening(panel, opening))
				panels = remaining
				var center := opening.get_center()
				holes.append({"center": Vector3(center.x, body.position.y, center.y), "size": opening.size, "underside_y": body.position.y - size.y * 0.5, "top_y": body.position.y + size.y * 0.5, "ceiling_body": str(body.name)})
			if holes.is_empty():
				continue
			# Removing only the slabs is insufficient: the recessed mortar,
			# perimeter seal and whole-panel shadow box would still close it.
			# The original concept root/metadata and original collider survive.
			for part in architecture.get_children():
				architecture.remove_child(part)
				part.free()
			var fragments: Array[Dictionary] = []
			for index in panels.size():
				var panel := panels[index]
				var panel_size := Vector3(panel.size.x, size.y, panel.size.y)
				var panel_xz := panel.get_center() - body_xz
				var fragment := CONCEPT.create_architecture(panel_size, "crypt_ceiling")
				fragment.name = "UncollapsedCeilingPanel_%02d" % index
				fragment.position = Vector3(panel_xz.x, 0.0, panel_xz.y)
				fragment.set_meta("ruin_roof_fragment", panel_size)
				architecture.add_child(fragment)
				fragments.append({"center": Vector3(panel.get_center().x, body.position.y, panel.get_center().y), "size": panel_size})
			architecture.set_meta("ruin_roof_openings", holes.duplicate(true))
			architecture.set_meta("ruin_roof_fragments", fragments)
			architecture.set_meta("ruin_roof_original_size", size)
			result[room_id] = holes
	return result


static func subtract_opening(panel: Rect2, opening: Rect2) -> Array[Rect2]:
	var cut := panel.intersection(opening)
	if not cut.has_area():
		return [panel]
	# Four non-overlapping rectangular panels around the aperture. Repeating
	# this partition also supports the two independent central-hall leaks.
	var candidates: Array[Rect2] = [
		Rect2(panel.position, Vector2(cut.position.x - panel.position.x, panel.size.y)),
		Rect2(Vector2(cut.end.x, panel.position.y), Vector2(panel.end.x - cut.end.x, panel.size.y)),
		Rect2(Vector2(cut.position.x, panel.position.y), Vector2(cut.size.x, cut.position.y - panel.position.y)),
		Rect2(Vector2(cut.position.x, cut.end.y), Vector2(cut.size.x, panel.end.y - cut.end.y)),
	]
	var result: Array[Rect2] = []
	for candidate in candidates:
		if candidate.size.x > 0.001 and candidate.size.y > 0.001:
			result.append(candidate)
	return result
