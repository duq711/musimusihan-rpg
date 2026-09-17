extends RefCounted

static var _boxes: Dictionary = {}
static var _exact_meshes: Dictionary = {}
static var _mesh_signatures: Dictionary = {}
const REPLACED_SURFACES := ["BondedMasonryBlocks", "FlagstoneSlabs", "RecessedMortarCore", "MortarBoundarySeal"]


static func add(root: Node3D, size: Vector3) -> MeshInstance3D:
	if root.has_node("SolidArchitectureShadow"):
		return root.get_node("SolidArchitectureShadow") as MeshInstance3D
	# This root represents one opaque solid panel, never an entire room,
	# doorway or arch. Its dimensions are the authoritative original box.
	var key := str(size)
	if not _boxes.has(key):
		var box := BoxMesh.new()
		box.size = size
		_boxes[key] = box
	var shadow := MeshInstance3D.new()
	shadow.name = "SolidArchitectureShadow"
	shadow.mesh = _boxes[key]
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shadow.set_meta("solid_architecture_shadow", size)
	for child in root.get_children():
		if child is MeshInstance3D and str(child.name) in REPLACED_SURFACES:
			var surface := child as MeshInstance3D
			shadow.layers = surface.layers
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ornamented ribs keep their original independent silhouettes/shadows.
	root.add_child(shadow)
	return shadow


static func add_exact(root: Node3D) -> MeshInstance3D:
	if root.has_node("ExactArchitectureShadow"):
		return root.get_node("ExactArchitectureShadow") as MeshInstance3D
	var sources: Array[MeshInstance3D] = []
	var transforms: Array[Transform3D] = []
	var signatures: Array[String] = []
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not node.visible or node.mesh == null:
			continue
		var material := node.get_active_material(0) as StandardMaterial3D
		# Only the fixed opaque stone assemblies use this path. Keep unknown
		# material/vertex deformation or mixed settings on their original path.
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			return null
		if not sources.is_empty() and node.layers != sources[0].layers:
			return null
		var placement := _relative_transform(node, root)
		sources.append(node)
		transforms.append(placement)
		signatures.append(_mesh_signature(node.mesh) + ":" + var_to_str(placement))
	if sources.is_empty():
		return null
	var key := "|".join(signatures).sha256_text()
	if not _exact_meshes.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in sources.size():
			var mesh := sources[index].mesh
			for surface in mesh.get_surface_count():
				tool.append_from(mesh, surface, transforms[index])
		var merged := tool.commit()
		merged.surface_set_material(0, null)
		_exact_meshes[key] = merged
	var shadow := MeshInstance3D.new()
	shadow.name = "ExactArchitectureShadow"
	shadow.mesh = _exact_meshes[key]
	shadow.layers = sources[0].layers
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	shadow.set_meta("exact_architecture_shadow", true)
	shadow.set_meta("source_mesh_count", sources.size())
	# The visible geometry remains independently materialed and instanced.
	# Its later MultiMesh batch inherits OFF, avoiding duplicate shadows.
	for source in sources:
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)
	return shadow


static func _mesh_signature(mesh: Mesh) -> String:
	var id := mesh.get_instance_id()
	if not _mesh_signatures.has(id):
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		for surface in mesh.get_surface_count():
			hashing.update(var_to_bytes(mesh.surface_get_arrays(surface)))
		_mesh_signatures[id] = hashing.finish().hex_encode()
	return _mesh_signatures[id]


static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var value := node.transform
	var cursor := node.get_parent()
	while cursor != ancestor:
		value = (cursor as Node3D).transform * value
		cursor = cursor.get_parent()
	return value
