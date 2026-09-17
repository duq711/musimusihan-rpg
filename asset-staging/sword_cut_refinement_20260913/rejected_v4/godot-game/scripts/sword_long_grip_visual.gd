extends Node3D
## The supplied camera-relative GLB contains an authored, rigid hand pose.
## Normalize its vertices once to the existing sword frame so production
## combat curves and the rendered blade's collision bounds remain valid.

const SOURCE := preload("res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb")
const THUMB_CORRECTIVE_PATH := "res://assets/3d/player/sword_hold_long_grip/RightHand_ThumbCorrective.json"
const THUMB_CORRECTIVE_SHA256 := "e16e6939c3c23e58af25edbae7ff7fc73f46c6336c2ab36eaf986f60d6138a11"
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
var _continuous_sleeve: Node3D
var _continuous_sleeve_status := {"ok": false, "error": "Finished Windows sleeve GLB has not been received."}


func setup(side: int = 1) -> void:
	assert(side == 1, "The supplied long-grip pose contains only a right arm.")
	if not arm_meshes.is_empty() or not hand_meshes.is_empty():
		return
	_ensure_source_cache()
	for source_name: String in ARM_PARTS:
		var part := _make_part(source_name, source_name)
		add_child(part)
		if source_name == "RightHand_Glove":
			hand_meshes.append(part)
		else:
			arm_meshes.append(part)
	_forearm = get_node("RightArm_Forearm_Surface") as MeshInstance3D
	_upper_arm = get_node("RightArm_UpperArm_Surface") as MeshInstance3D
	_cuff = get_node("RightArm_WristCuff_Surface") as MeshInstance3D
	set_meta("source_model", SOURCE.resource_path)
	set_meta("source_sha256", SOURCE_SHA256)
	set_meta("hand_side", 1)
	set_meta("anatomical_side", 1)
	set_meta("authored_static_pose", true)
	set_meta("imported_static_grip", true)
	set_meta("grip_local", GRIP_CENTER)
	set_meta("thumb_corrective", THUMB_CORRECTIVE_PATH)
	_setup_continuous_sleeve()


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
	# There are no fingers or bones to animate in this export. Keep the exact
	# authored contact instead of stretching or reopening the supplied fist.
	grip_amount = clampf(amount, 0.0, 1.0)


func fit_arm(shoulder_world: Vector3, elbow_world: Vector3, preserve_authored_elbow: bool = false) -> void:
	if not is_instance_valid(_forearm) or not is_instance_valid(_upper_arm):
		return
	var shoulder := to_local(shoulder_world)
	var elbow := to_local(elbow_world)
	if not shoulder.is_finite() or not elbow.is_finite():
		return
	# A two-bone solver adds a small bend at full extension to avoid a singular
	# elbow. At the exact source rest shoulder, retain the authored straight
	# sleeves instead. This also makes returning to the source pose exact.
	# Explicit Windows elbow keys can bend here while the shoulder stays at
	# rest. Only the legacy procedural solver needs the source-rest override.
	if not preserve_authored_elbow and shoulder.distance_to(REST_SHOULDER) < 0.00001:
		shoulder = REST_SHOULDER
		elbow = REST_ELBOW
	_forearm.transform = _fit_segment(REST_WRIST, REST_ELBOW, REST_WRIST, elbow)
	_upper_arm.transform = _fit_segment(REST_ELBOW, REST_SHOULDER, elbow, shoulder)
	# This short leather joint turns with the sleeve around the fixed wrist.
	# Leaving its open rear rim in the sword frame exposes a hollow cuff beside
	# the arm in reverse/overhead cuts. Its original geometry is never stretched.
	var cuff_basis := _forearm.basis.orthonormalized()
	_cuff.transform = Transform3D(cuff_basis, REST_WRIST - cuff_basis * REST_WRIST)
	if is_instance_valid(_continuous_sleeve):
		_continuous_sleeve.call("apply_segments", _forearm.transform, _upper_arm.transform, REST_WRIST, elbow)
	_fitted_elbow = elbow
	_fitted_shoulder = shoulder
	# The authored glove stays locked to the sword; the leather sleeve articulates.


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
	var sleeve: Dictionary = _continuous_sleeve.call("get_snapshot") if is_instance_valid(_continuous_sleeve) else _continuous_sleeve_status.duplicate(true)
	return {
		"source_model": SOURCE.resource_path,
		"source_sha256": SOURCE_SHA256,
		"authored_static_pose": true,
		"animations": 0,
		"skeleton": bool(sleeve.get("ok", false)),
		"skeleton_bone_count": int(sleeve.get("bone_count", 0)),
		"animation_driver": "production_player_joint_fit" if bool(sleeve.get("ok", false)) else "rigid_segment_fit",
		"continuous_sleeve": sleeve,
		"arm_mesh_count": arm_meshes.size(),
		"hand_mesh_count": hand_meshes.size(),
		"normalized_mesh_count": _normalized_meshes.size(),
		"grip_local": GRIP_CENTER,
		"thumb_corrective": THUMB_CORRECTIVE_PATH,
		"thumb_corrective_sha256": THUMB_CORRECTIVE_SHA256,
		"grip_amount": grip_amount,
		"source_ready": SOURCE_READY,
		"sleeve_motion": "windows_continuous_skin_fitted_to_shoulder" if bool(sleeve.get("ok", false)) else "segments_fitted_to_shoulder",
		"rest_wrist": REST_WRIST,
		"rest_elbow": REST_ELBOW,
		"rest_shoulder": REST_SHOULDER,
		"fitted_elbow": _fitted_elbow,
		"fitted_shoulder": _fitted_shoulder,
	}


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
		if str(source.name) == "RightHand_Glove" and surface == 0:
			_apply_thumb_corrective(arrays)
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


static func _apply_thumb_corrective(arrays: Array) -> void:
	# Import optimization can reorder GLB vertices. Match the imported source
	# positions and corner normals, never the accessor's integer indices.
	assert(FileAccess.get_sha256(THUMB_CORRECTIVE_PATH) == THUMB_CORRECTIVE_SHA256)
	var corrective: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THUMB_CORRECTIVE_PATH))
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert(corrective.source_sha256 == SOURCE_SHA256 and int(corrective.source_vertex_count) == vertices.size())
	var by_position := {}
	for entry: Dictionary in corrective.changes:
		var original := Vector3(entry.source_position[0], entry.source_position[1], entry.source_position[2])
		var key := Vector3i((original / 0.00001).floor())
		if not by_position.has(key): by_position[key] = []
		by_position[key].append(entry)
	var corrected_count := 0
	for index in vertices.size():
		var key := Vector3i((vertices[index] / 0.00001).floor())
		var best: Dictionary = {}
		var best_score := INF
		# Position compression changes interior coordinates by a few microns.
		# A local 5 um search remains far smaller than an authored skin edge.
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for entry: Dictionary in by_position.get(key + Vector3i(dx, dy, dz), []):
						var original := Vector3(entry.source_position[0], entry.source_position[1], entry.source_position[2])
						var distance_squared := original.distance_squared_to(vertices[index])
						if distance_squared > 0.000005 * 0.000005: continue
						var original_normal := Vector3(entry.source_normal[0], entry.source_normal[1], entry.source_normal[2])
						var score := distance_squared + (1.0 - original_normal.dot(normals[index])) * 0.000000000001
						if score < best_score:
							best_score = score
							best = entry
		if best.is_empty(): continue
		vertices[index] = Vector3(best.position[0], best.position[1], best.position[2])
		normals[index] = Vector3(best.normal[0], best.normal[1], best.normal[2])
		corrected_count += 1
	assert(corrected_count == corrective.changes.size(), "The static thumb must map exactly onto the actual imported vertices.")
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
