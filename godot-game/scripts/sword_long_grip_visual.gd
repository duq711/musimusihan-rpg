extends Node3D
## Keep the authored sword frame and blade geometry, with the new FP arms
## skinned right hand fitted to that same grip. Existing combat curves and
## blade collision bounds remain owned by the production animation driver.

const SOURCE := preload("res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb")
const CONTINUOUS_SLEEVE := preload("res://scripts/reference_continuous_sleeve.gd")
const SOURCE_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const GRIP_CENTER := Vector3(0.0, -0.108, 0.002)
# Original sleeve vertex correspondence recovers its authored joint axis.
# The supplied export holds both segments straight; these coordinates are
# independently normalized into the same sword frame as the imported mesh.
const REST_WRIST := Vector3(0.0679751875, -0.1080001335, 0.0524637313)
const REST_ELBOW := Vector3(0.2366280243, -0.1080001099, 0.2503430693)
const REST_SHOULDER := Vector3(0.4571740416, -0.1080000789, 0.5091083575)
const REST_FOREARM_LENGTH := 0.26
const REST_UPPER_LENGTH := 0.34
const SOURCE_READY := Transform3D(Basis(
	Vector3(0.6734562112, -0.1673592395, 0.7200327879),
	Vector3(0.1384824613, 0.9853534854, 0.0995039315),
	Vector3(-0.7261403196, 0.0327005009, 0.6867691389)
), Vector3(0.3249563841, -0.0035816696, -0.5892537756))
const ARM_PARTS := ["RightArm_Forearm_Surface", "RightArm_UpperArm_Surface", "RightArm_WristCuff_Surface", "RightHand_Glove"]

static var _normalized_meshes: Dictionary = {}
var arm_meshes: Array[MeshInstance3D] = []
var hand_meshes: Array[MeshInstance3D] = []
var _forearm: MeshInstance3D
var _upper_arm: MeshInstance3D
var _cuff: MeshInstance3D
var grip_amount := 1.0
var _fitted_elbow := REST_ELBOW
var _fitted_shoulder := REST_SHOULDER
var _fp_arm: Node3D
var _continuous_sleeve: Node3D
var _continuous_sleeve_status := {"ok": false, "error": "Finished Windows sleeve GLB has not been received."}


func setup(side: int = 1) -> void:
	assert(side == 1, "The supplied long-grip pose contains only a right arm.")
	if not arm_meshes.is_empty() or not hand_meshes.is_empty():
		return
	_fp_arm = preload("res://scripts/supplied_fp_arm.gd").new()
	_fp_arm.name = "SuppliedRightArm"
	add_child(_fp_arm)
	_fp_arm.setup(1)
	# Preserve the existing authored wrist and blade paths. Rotate the new
	# anatomical hand into that frame, then place its palm on the real handle.
	var x := Vector3.DOWN
	var z := (REST_ELBOW-REST_WRIST).normalized()
	z = (z-x*z.dot(x)).normalized()
	var orientation := Basis(x,z.cross(x).normalized(),z)
	_fp_arm.transform = Transform3D(orientation,GRIP_CENTER-orientation*_fp_arm.GRIP_CENTER)
	_fp_arm.set_combat_grip("sword",.91)
	arm_meshes.assign(_fp_arm.arm_meshes)
	hand_meshes.assign(_fp_arm.hand_meshes)
	set_meta("source_model",_fp_arm.get_meta("source_model"))
	set_meta("anatomical_side",1)
	set_meta("imported_static_grip",true)
	set_meta("supplied_fp_arms",true)
	set_meta("grip_local",GRIP_CENTER)


func _setup_continuous_sleeve() -> void:
	if not FileAccess.file_exists(CONTINUOUS_SLEEVE.SOURCE_PATH):
		return
	# The immutable static source remains the hand/blade source. Only the
	# finished sleeve may replace the three disconnected visible arm parts.
	if FileAccess.get_sha256(CONTINUOUS_SLEEVE.SOURCE_PATH) != CONTINUOUS_SLEEVE.SOURCE_SHA256:
		_continuous_sleeve_status = {"ok": false, "error": "Finished sleeve source SHA-256 does not match the Windows delivery."}
		return
	var packed := load(CONTINUOUS_SLEEVE.SOURCE_PATH) as PackedScene
	var adapter := CONTINUOUS_SLEEVE.new()
	adapter.name = "ReferenceContinuousSleeve"
	add_child(adapter)
	_continuous_sleeve_status = adapter.setup(packed)
	if not bool(_continuous_sleeve_status.ok):
		adapter.free()
		return
	if not adapter.apply_segments(Transform3D.IDENTITY, Transform3D.IDENTITY, REST_WRIST, REST_ELBOW):
		_continuous_sleeve_status = {"ok": false, "error": "Finished sleeve could not initialize its original bind pose."}
		adapter.free()
		return
	_continuous_sleeve = adapter
	for part: MeshInstance3D in arm_meshes:
		part.visible = false
	arm_meshes.clear()
	for part: MeshInstance3D in adapter.arm_meshes:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm_meshes.append(part)


static func create_sword() -> Node3D:
	_ensure_source_cache()
	var sword := Node3D.new()
	sword.name = "LongGripSwordVisual"
	sword.set_meta("source_model", SOURCE.resource_path)
	sword.set_meta("source_sha256", SOURCE_SHA256)
	sword.set_meta("authored_static_pose", true)
	sword.set_meta("imported_static_grip", true)
	for source_name: String in _normalized_meshes:
		if source_name.begins_with("Sword_"):
			sword.add_child(_make_part(source_name, source_name.trim_prefix("Sword_")))
	for marker_name: String in ["BladeTip", "HandGrip"]:
		var marker := Marker3D.new()
		marker.name = marker_name
		marker.position = Vector3(0.0, 1.035, 0.0) if marker_name == "BladeTip" else GRIP_CENTER
		sword.add_child(marker)
	return sword


func set_grip(amount: float, _thumb_amount: float = -1.0) -> void:
	# This held-sword adapter keeps its new rig at the setup grip; the separate
	# reaching-hand adapter handles finger opening during the draw motion.
	grip_amount = clampf(amount, 0.0, 1.0)


func fit_arm(shoulder_world: Vector3, elbow_world: Vector3, preserve_authored_elbow: bool = false) -> void:
	if is_instance_valid(_fp_arm): _fp_arm.fit_arm(shoulder_world,elbow_world)
	_fitted_elbow=to_local(elbow_world)
	_fitted_shoulder=to_local(shoulder_world)


static func _fit_segment(rest_start: Vector3, rest_end: Vector3, target_start: Vector3, target_end: Vector3) -> Transform3D:
	var rest_delta := rest_end - rest_start
	var target_delta := target_end - target_start
	if minf(rest_delta.length(), target_delta.length()) < 0.00001:
		return Transform3D.IDENTITY
	var axis := rest_delta.normalized()
	var axial_change := target_delta.length() / rest_delta.length() - 1.0
	var axial_scale := Basis(
		Vector3.RIGHT + axis * axis.x * axial_change,
		Vector3.UP + axis * axis.y * axial_change,
		Vector3.BACK + axis * axis.z * axial_change
	)
	# The shortest rotation avoids the reference-axis roll changes of a look-at
	# frame, while axial scaling keeps the two actual sleeve endpoints joined.
	var target_axis := target_delta.normalized()
	var cross := axis.cross(target_axis)
	var dot := clampf(axis.dot(target_axis), -1.0, 1.0)
	var rotation := Quaternion.IDENTITY
	# Quaternion(from, to) treats tiny angles as identity. That leaves visible
	# segments short of their shared endpoint while the guard starts to rise.
	if cross.length() > 0.000000001:
		rotation = Quaternion(cross.normalized(), atan2(cross.length(), dot))
	elif dot < 0.0:
		var perpendicular := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP).normalized()
		rotation = Quaternion(perpendicular, PI)
	var orientation := Basis(rotation) * axial_scale
	return Transform3D(orientation, target_start - orientation * rest_start)


func get_snapshot() -> Dictionary:
	var data: Dictionary = _fp_arm.get_snapshot()
	data.merge({"grip_local":GRIP_CENTER,"grip_amount":grip_amount,"rest_wrist":REST_WRIST,"rest_elbow":REST_ELBOW,"rest_shoulder":REST_SHOULDER,"fitted_elbow":_fitted_elbow,"fitted_shoulder":_fitted_shoulder,"animation_driver":"production_player_joint_fit"})
	return data


static func _ensure_source_cache() -> void:
	if not _normalized_meshes.is_empty():
		return
	var source := SOURCE.instantiate() as Node3D
	_cache_node(source, Transform3D.IDENTITY)
	source.free()


static func _cache_node(node: Node, parent_transform: Transform3D) -> void:
	var source_transform := parent_transform
	if node is Node3D:
		source_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		_normalized_meshes[str(part.name)] = _bake_mesh(part, SOURCE_READY.affine_inverse() * source_transform)
	for child in node.get_children():
		_cache_node(child, source_transform)


static func _make_part(source_name: String, part_name: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = _normalized_meshes[source_name] as ArrayMesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.set_meta("source_node", source_name)
	return part


static func _bake_mesh(source: MeshInstance3D, normalization: Transform3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.resource_name = str(source.name) + "_CanonicalSwordFrame"
	var normal_basis := normalization.basis.inverse().transposed()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():
			vertices[index] = normalization * vertices[index]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in normals.size():
				normals[index] = (normal_basis * normals[index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for index in range(0, tangents.size(), 4):
				var tangent := (normalization.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])).normalized()
				tangents[index] = tangent.x
				tangents[index + 1] = tangent.y
				tangents[index + 2] = tangent.z
				tangents[index + 3] *= signf(normalization.basis.determinant())
			arrays[Mesh.ARRAY_TANGENT] = tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# Embedded texture and material resources remain the supplied export.
		result.surface_set_material(surface, source.get_active_material(surface))
	return result
