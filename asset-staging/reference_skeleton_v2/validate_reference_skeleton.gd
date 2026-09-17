extends SceneTree

const MODEL := "res://out/reference_skeleton_3d.glb"
const REQUIRED_PATHS := [
	"VisualRoot",
	"VisualRoot/TorsoPivot",
	"VisualRoot/TorsoPivot/HeadPivot",
	"VisualRoot/TorsoPivot/ArmLPivot",
	"VisualRoot/TorsoPivot/ArmLPivot/ElbowLPivot",
	"VisualRoot/TorsoPivot/ArmLPivot/ElbowLPivot/WristLPivot",
	"VisualRoot/TorsoPivot/ArmRPivot",
	"VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot",
	"VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot/WristRPivot",
	"VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot/WristRPivot/WeaponPivot",
	"VisualRoot/LegLPivot",
	"VisualRoot/LegLPivot/KneeLPivot",
	"VisualRoot/LegRPivot",
	"VisualRoot/LegRPivot/KneeRPivot",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("Model did not import as PackedScene: %s" % MODEL)
		quit(1)
		return
	var instance := packed.instantiate() as Node3D
	get_root().add_child(instance)
	for path in REQUIRED_PATHS:
		if instance.get_node_or_null(path) == null:
			failures.append("missing pivot %s" % path)

	var all_nodes := _descendants(instance)
	var meshes: Array[MeshInstance3D] = []
	var collisions := 0
	var forbidden_visuals: Array[String] = []
	var bounds_found := false
	var bounds := AABB()
	for node in all_nodes:
		if node is CollisionObject3D or node is CollisionShape3D:
			collisions += 1
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			meshes.append(mesh_node)
			var mesh_name := String(mesh_node.name)
			if not mesh_name.begins_with("Bone"):
				forbidden_visuals.append(mesh_name)
			var world_bounds := mesh_node.global_transform * mesh_node.get_aabb()
			bounds = world_bounds if not bounds_found else bounds.merge(world_bounds)
			bounds_found = true
			_validate_material(mesh_node, failures)

	if meshes.size() < 260:
		failures.append("expected at least 260 detailed bone meshes, found %d" % meshes.size())
	if collisions != 0:
		failures.append("expected no collision nodes, found %d" % collisions)
	if not forbidden_visuals.is_empty():
		failures.append("non-bone/possible equipment meshes found: %s" % ", ".join(forbidden_visuals))
	_validate_exact_prefix(meshes, "BoneRibL", 12, failures)
	_validate_exact_prefix(meshes, "BoneRibR", 12, failures)
	_validate_exact_prefix(meshes, "BoneToothUpper", 14, failures)
	_validate_exact_prefix(meshes, "BoneToothLower", 14, failures)
	for side in ["L", "R"]:
		_validate_exact_prefix(meshes, "BoneHand%sMetacarpal" % side, 5, failures)
		_validate_exact_prefix(meshes, "BoneFinger%s_" % side, 14, failures)
		_validate_exact_prefix(meshes, "BoneFoot%sMetatarsal" % side, 5, failures)
		_validate_exact_prefix(meshes, "BoneToe%s_" % side, 14, failures)

	for required_mesh in ["BoneSkullCranium", "BoneJaw", "BoneSternum", "BonePelvisSacrum", "BonePatellaL", "BonePatellaR", "BoneTibiaL", "BoneTibiaR", "BoneFibulaL", "BoneFibulaR"]:
		if not _has_named_mesh(meshes, required_mesh):
			failures.append("missing anatomy mesh %s" % required_mesh)

	var weapon := instance.get_node_or_null("VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot/WristRPivot/WeaponPivot")
	if weapon != null:
		for child in weapon.get_children():
			if child is MeshInstance3D:
				failures.append("WeaponPivot has direct geometry instead of remaining a compatibility pivot")

	if not bounds_found:
		failures.append("model has no bounds")
	else:
		if bounds.position.y < -0.045 or bounds.position.y > 0.070:
			failures.append("feet must rest at y=0; minimum y is %.3f" % bounds.position.y)
		if bounds.size.y < 1.84 or bounds.size.y > 2.00:
			failures.append("height %.3fm is outside 1.84..2.00m" % bounds.size.y)
		if bounds.size.z < 0.40:
			failures.append("model depth %.3fm is too flat to be a real 3D character" % bounds.size.z)

	var skull := _find_mesh(meshes, "BoneSkullCranium")
	if skull != null:
		var skull_bounds := skull.global_transform * skull.get_aabb()
		if skull_bounds.size.x < 0.20 or skull_bounds.size.z < 0.17:
			failures.append("cranium is too small: %s" % skull_bounds.size)
	var nasal := _find_mesh(meshes, "BoneSkullNasalCavity")
	if nasal != null:
		var nasal_material := nasal.mesh.surface_get_material(0) as StandardMaterial3D
		if nasal_material != null:
			print("nasal cavity material albedo=%s roughness=%.2f" % [nasal_material.albedo_color, nasal_material.roughness])

	print("reference_skeleton_3d.glb meshes=%d bounds=(%.3f, %.3f, %.3f) min_y=%.3f" % [meshes.size(), bounds.size.x, bounds.size.y, bounds.size.z, bounds.position.y])
	if failures.is_empty():
		print("Reference skeleton contract validation passed.")
		instance.free()
		quit(0)
	else:
		push_error("Reference skeleton validation failures:\n - %s" % "\n - ".join(failures))
		instance.free()
		quit(1)


func _validate_material(mesh_node: MeshInstance3D, failures: Array[String]) -> void:
	var material := mesh_node.material_override as StandardMaterial3D
	if material == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		material = mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
	if material == null:
		failures.append("%s has no StandardMaterial3D" % mesh_node.name)
		return
	if material.metallic > 0.01:
		failures.append("%s unexpectedly uses metallic bone" % mesh_node.name)
	if material.emission_enabled:
		failures.append("%s has forbidden emission/glow" % mesh_node.name)
	if material.roughness < 0.84:
		failures.append("%s is too glossy for weathered bone" % mesh_node.name)


func _validate_exact_prefix(meshes: Array[MeshInstance3D], prefix: String, expected: int, failures: Array[String]) -> void:
	var count := 0
	for mesh in meshes:
		if String(mesh.name).begins_with(prefix):
			count += 1
	if count != expected:
		failures.append("%s expected %d meshes, found %d" % [prefix, expected, count])


func _has_named_mesh(meshes: Array[MeshInstance3D], target: String) -> bool:
	return _find_mesh(meshes, target) != null


func _find_mesh(meshes: Array[MeshInstance3D], target: String) -> MeshInstance3D:
	for mesh in meshes:
		if String(mesh.name) == target:
			return mesh
	return null


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
