extends RefCounted

const ARCHITECTURE_MARKERS := ["architecture_kind", "pointed_arch_masonry", "clustered_column_masonry", "worn_step_masonry", "pointed_portal_masonry"]
const SETTINGS := ["layers", "cast_shadow", "gi_mode", "lod_bias", "visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin", "visibility_range_fade_mode", "ignore_occlusion_culling"]


static func build(region: Node3D) -> int:
	if region.has_meta("static_stone_batches_built"):
		return 0
	var groups := {}
	_collect(region, region, false, true, groups)
	var batch_count := 0
	var source_count := 0
	for key in groups:
		var sources: Array = groups[key]
		if sources.size() < 3:
			continue
		var exemplar := sources[0] as MeshInstance3D
		var batch := MultiMeshInstance3D.new()
		batch.name = "StaticStoneBatch_%d" % batch_count
		batch.material_override = exemplar.get_active_material(0)
		for setting in SETTINGS:
			batch.set(setting, exemplar.get(setting))
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = exemplar.mesh
		instances.instance_count = sources.size()
		var transforms: Array[Transform3D] = []
		var paths: Array[String] = []
		var bounds := AABB()
		for index in sources.size():
			var source := sources[index] as MeshInstance3D
			var transform_value := relative_transform(source, region)
			instances.set_instance_transform(index, transform_value)
			transforms.append(transform_value)
			paths.append(_relative_path(source, region))
			var instance_bounds := transform_value * source.mesh.get_aabb()
			bounds = instance_bounds if index == 0 else bounds.merge(instance_bounds)
			source.set_meta("static_stone_batch_source", true)
			# Keep authored nodes and their immutable meshes for inspection;
			# only their redundant rendering instance is hidden.
			source.visible = false
		instances.custom_aabb = bounds
		batch.multimesh = instances
		batch.set_meta("submitted_transforms", transforms)
		batch.set_meta("source_paths", paths)
		region.add_child(batch)
		batch_count += 1
		source_count += sources.size()
	region.set_meta("static_stone_batches_built", batch_count)
	region.set_meta("static_stone_batched_instances", source_count)
	return batch_count


static func _collect(node: Node, region: Node3D, architecture: bool, parent_visible: bool, groups: Dictionary) -> void:
	for marker in ARCHITECTURE_MARKERS:
		architecture = architecture or node.has_meta(marker)
	var visible := parent_visible and (not node is Node3D or (node as Node3D).visible)
	if architecture and visible and node is MeshInstance3D and not node.has_meta("exact_architecture_shadow") and not node.has_meta("solid_architecture_shadow"):
		var instance := node as MeshInstance3D
		var rigid := not instance.mesh is ArrayMesh or (instance.mesh as ArrayMesh).get_blend_shape_count() == 0
		# Dynamic child transforms, transparent effects, huge panels, blend
		# shapes and skeletons keep their original independent render paths.
		if instance.get_child_count() == 0 and instance.mesh != null and instance.mesh.get_surface_count() == 1 and rigid and instance.skin == null and instance.mesh.get_aabb().size.length() < 4.0:
			var material := instance.get_active_material(0) as StandardMaterial3D
			if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and instance.material_overlay == null:
				var key := str(instance.mesh.get_instance_id()) + ":" + str(material.get_instance_id())
				for setting in SETTINGS:
					key += ":" + str(instance.get(setting))
				if not groups.has(key):
					groups[key] = []
				groups[key].append(instance)
	for child in node.get_children():
		_collect(child, region, architecture, visible, groups)


static func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor and cursor != null:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	assert(cursor == ancestor, "Static stone must stay inside its authored region")
	return result


static func _relative_path(node: Node, ancestor: Node) -> String:
	var names: Array[String] = []
	var cursor := node
	while cursor != ancestor:
		names.push_front(str(cursor.name))
		cursor = cursor.get_parent()
	return "/".join(names)
