extends Node3D
## Runtime surface adapter for the actual Windows iteration_07 sleeve.
## Owns no motion clock or IK. The caller supplies the final sword-space FF/FU.
## Deliberately does not preload SwordLongGripVisual (which may own this node).

const SOURCE_SHA256 := "a0df768367d78a487573101e780b881869b52b17ddd6daeaaea9cbcf6b24f319"
const SOURCE_PATH := "res://assets/animations/reference_sword_motion/Overhead_Final.glb"
const SOURCE_BYTES := 18986536
const BONE_NAMES := ["SleeveHand", "SleeveWrist", "SleeveForearm", "SleeveElbow25", "SleeveElbow50", "SleeveElbow75", "SleeveUpper"]
const MESH_NAMES := ["RightArm_ContinuousSleeve_Surface", "RightArm_Forearm_Surface", "RightArm_WristCuff_Surface"]

var skeleton: Skeleton3D
var arm_meshes: Array[MeshInstance3D] = []
var _bones: Dictionary = {}
var _rests: Dictionary = {}
var _canonical_from_skeleton := Transform3D.IDENTITY
var _skeleton_from_canonical := Transform3D.IDENTITY
var _configured := false
var _error := "Actual Windows GLB has not been configured."
var _updates := 0
var _source_path := ""
var _source_animations: Array[String] = []


func setup(source: PackedScene) -> Dictionary:
	if _configured:
		return get_snapshot()
	if source == null or source.resource_path.is_empty():
		return _failure("An actual received GLB PackedScene is required.")
	var path := source.resource_path
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != SOURCE_SHA256:
		return _failure("Continuous sleeve GLB does not match the approved iteration_07 bytes.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != SOURCE_BYTES:
		return _failure("Continuous sleeve GLB size differs from the Windows delivery.")
	file.close()
	# Keep the complete source hierarchy only while reading import-space frames.
	# Production receives a new Skeleton and the three actual skin meshes alone.
	var imported := source.instantiate() as Node3D
	if imported == null:
		return _failure("Continuous sleeve source root is not Node3D.")
	imported.process_mode = Node.PROCESS_MODE_DISABLED
	imported.visible = false
	add_child(imported)
	for animator: AnimationPlayer in imported.find_children("*", "AnimationPlayer", true, false):
		for animation: StringName in animator.get_animation_list():
			if str(animation) != "RESET" and not str(animation) in _source_animations:
				_source_animations.append(str(animation))
	var rigs: Array[Skeleton3D] = []
	var meshes: Array[MeshInstance3D] = []
	_collect(imported, rigs, meshes)
	if rigs.size() != 1:
		imported.free()
		return _failure("Expected exactly one imported sleeve Skeleton3D.")
	var source_rig := rigs[0]
	if source_rig.get_bone_count() != BONE_NAMES.size():
		imported.free()
		return _failure("Expected the seven authored sleeve bones.")
	for bone_name: String in BONE_NAMES:
		if source_rig.find_bone(bone_name) < 0:
			imported.free()
			return _failure("Missing authored sleeve bone: " + bone_name)
	var selected: Dictionary = {}
	for part: MeshInstance3D in meshes:
		if str(part.name) in MESH_NAMES:
			if selected.has(str(part.name)) or part.mesh == null or part.skin == null or part.get_node_or_null(part.skeleton) != source_rig:
				var invalid_name := str(part.name)
				imported.free()
				return _failure("Missing, duplicate, or detached sleeve skin: " + invalid_name)
			selected[str(part.name)] = part
	if selected.size() != MESH_NAMES.size():
		imported.free()
		return _failure("All three actual continuous sleeve/detail skins are required.")
	_canonical_from_skeleton = _relative_transform(source_rig, self)
	if not _valid_transform(_canonical_from_skeleton):
		imported.free()
		return _failure("Imported sleeve coordinate frame is invalid.")
	_skeleton_from_canonical = _canonical_from_skeleton.affine_inverse()
	skeleton = Skeleton3D.new()
	skeleton.name = "ContinuousSleeveSkeleton"
	skeleton.transform = _canonical_from_skeleton
	for bone in source_rig.get_bone_count():
		skeleton.add_bone(source_rig.get_bone_name(bone))
	for bone in source_rig.get_bone_count():
		skeleton.set_bone_parent(bone, source_rig.get_bone_parent(bone))
		skeleton.set_bone_rest(bone, source_rig.get_bone_rest(bone))
	add_child(skeleton)
	skeleton.reset_bone_poses()
	for bone_name: String in BONE_NAMES:
		var bone := skeleton.find_bone(bone_name)
		_bones[bone_name] = bone
	for mesh_name: String in MESH_NAMES:
		var original: MeshInstance3D = selected[mesh_name]
		for bind in original.skin.get_bind_count():
			var bone := original.skin.get_bind_bone(bind)
			if bone < 0: bone = source_rig.find_bone(str(original.skin.get_bind_name(bind)))
			if bone < 0 or bone >= source_rig.get_bone_count() or not _valid_transform(original.skin.get_bind_pose(bind)):
				imported.free()
				_clear_runtime()
				return _failure("Invalid imported skin bind in " + mesh_name)
			var bone_name := source_rig.get_bone_name(bone)
			var bind_rest := original.skin.get_bind_pose(bind).affine_inverse()
			if _rests.has(bone_name) and not (bind_rest as Transform3D).is_equal_approx(_rests[bone_name]):
				imported.free()
				_clear_runtime()
				return _failure("Sleeve detail meshes use incompatible bind coordinate frames.")
			# The imported default bone rest may be the first animated pose.
			# Skin inverse bind, not that default pose, defines deformation zero.
			_rests[bone_name] = bind_rest
		var part := MeshInstance3D.new()
		part.name = mesh_name
		part.mesh = original.mesh
		part.skin = original.skin
		part.transform = _skeleton_from_canonical * _relative_transform(original, self)
		part.material_override = original.material_override
		part.material_overlay = original.material_overlay
		part.cast_shadow = original.cast_shadow
		part.layers = original.layers
		part.extra_cull_margin = original.extra_cull_margin
		for surface in original.mesh.get_surface_count():
			part.set_surface_override_material(surface, original.get_surface_override_material(surface))
		skeleton.add_child(part)
		part.skeleton = part.get_path_to(skeleton)
		arm_meshes.append(part)
	imported.free()
	if _rests.size() != BONE_NAMES.size():
		_clear_runtime()
		return _failure("All seven authored skin inverse binds must be present.")
	_source_path = path
	_configured = true
	_error = ""
	return get_snapshot()


func apply_segments(forearm: Transform3D, upper: Transform3D, wrist: Vector3, elbow: Vector3) -> bool:
	if not _configured or not _valid_transform(forearm) or not _valid_transform(upper) or not wrist.is_finite() or not elbow.is_finite():
		return false
	var transforms := segment_deformations(forearm, upper, wrist, elbow)
	if transforms.is_empty(): return false
	# Received skin vertex buffers use canonical coordinates. Solve the actual
	# skin product K * P * inverseBind = D, with K the Skeleton frame below us.
	# The rigid GLB control nodes' extra axis rotation must not be applied here.
	for bone_name: String in BONE_NAMES:
		var deformation: Transform3D = transforms[bone_name]
		skeleton.set_bone_global_pose(int(_bones[bone_name]), _skeleton_from_canonical * deformation * (_rests[bone_name] as Transform3D))
	_updates += 1
	return true


static func segment_deformations(forearm: Transform3D, upper: Transform3D, wrist: Vector3, elbow: Vector3) -> Dictionary:
	if not _valid_transform(forearm) or not _valid_transform(upper) or not wrist.is_finite() or not elbow.is_finite():
		return {}
	var forearm_rotation := forearm.basis.orthonormalized().get_rotation_quaternion()
	var upper_rotation := upper.basis.orthonormalized().get_rotation_quaternion()
	var output := {"SleeveHand": Transform3D.IDENTITY, "SleeveForearm": forearm, "SleeveUpper": upper}
	var wrist_basis := Basis(Quaternion.IDENTITY.slerp(forearm_rotation, 0.5))
	output["SleeveWrist"] = Transform3D(wrist_basis, wrist - wrist_basis * wrist)
	# Recover the bind elbow from FF rather than maintaining a second copy of
	# the original model constants. The caller's fit_segment maps E0 to elbow.
	var rest_elbow := forearm.affine_inverse() * elbow
	for item: Array in [["SleeveElbow25", 0.25], ["SleeveElbow50", 0.5], ["SleeveElbow75", 0.75]]:
		var basis := Basis(forearm_rotation.slerp(upper_rotation, float(item[1])))
		output[str(item[0])] = Transform3D(basis, elbow - basis * rest_elbow)
	return output


func get_snapshot() -> Dictionary:
	var mesh_names: Array[String] = []
	var mesh_instance_ids: Array[int] = []
	for part: MeshInstance3D in arm_meshes:
		mesh_names.append(str(part.name))
		mesh_instance_ids.append(part.get_instance_id())
	return {"ok": _configured, "error": _error, "source_path": _source_path, "source_sha256": SOURCE_SHA256 if _configured else "",
		"mesh_count": arm_meshes.size(), "bone_count": _bones.size(), "updates": _updates,
		"mesh_names": mesh_names, "mesh_instance_ids": mesh_instance_ids, "bone_names": _bones.keys(),
		"source_animation_names": _source_animations.duplicate(), "runtime_animation_players": 0,
		"clock_owner": "production_player", "canonical_from_skeleton": _canonical_from_skeleton}


func bone_point_to_global(bone_name: String, canonical_point: Vector3) -> Vector3:
	if not _configured or not _bones.has(bone_name) or not canonical_point.is_finite():
		return Vector3(NAN, NAN, NAN)
	var pose := skeleton.get_bone_global_pose(int(_bones[bone_name]))
	return skeleton.global_transform * pose * (_rests[bone_name] as Transform3D).affine_inverse() * canonical_point


func _failure(message: String) -> Dictionary:
	_error = message
	return get_snapshot()


func _clear_runtime() -> void:
	if is_instance_valid(skeleton): skeleton.free()
	skeleton = null
	arm_meshes.clear()
	_bones.clear()
	_rests.clear()
	_configured = false


static func _valid_transform(value: Transform3D) -> bool:
	return value.is_finite() and absf(value.basis.determinant()) > 0.0000001


static func _collect(node: Node, rigs: Array[Skeleton3D], meshes: Array[MeshInstance3D]) -> void:
	if node is Skeleton3D: rigs.append(node as Skeleton3D)
	if node is MeshInstance3D: meshes.append(node as MeshInstance3D)
	for child in node.get_children(): _collect(child, rigs, meshes)


static func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	# setup also supports an arm constructed before entering SceneTree.
	var value := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current != null:
		if current is Node3D: value = (current as Node3D).transform * value
		current = current.get_parent()
	return value
