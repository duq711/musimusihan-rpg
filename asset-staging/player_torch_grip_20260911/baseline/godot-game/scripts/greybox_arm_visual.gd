extends Node3D
## Shared imported-skin adapter for the blockout and detailed hand profiles.
## The default profile and public name preserve the original greybox contract.
## Only presentation changes: the caller owns the real grip/contact and timing.

const LEGACY_FIT := preload("res://scripts/player_arm_visual.gd")
const WRIST_CUFF_DEFORMER := preload("res://scripts/wrist_cuff_deformer.gd")
const LEFT_PATH := "res://assets/3d/player/hands_greybox/left_hand_greybox.glb"
const RIGHT_PATH := "res://assets/3d/player/hands_greybox/right_hand_greybox.glb"
const DETAILED_LEFT_PATH := "res://assets/3d/player/hands_detailed/left_hand_detailed.glb"
const DETAILED_RIGHT_PATH := "res://assets/3d/player/hands_detailed/right_hand_detailed.glb"
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const CONTACT_OFFSET := Vector3(0.0, 0.019, -0.0035)
const FINGER_LIMITS := Vector3(PI * 0.5, PI * 110.0 / 180.0, PI * 80.0 / 180.0)
const THUMB_LIMITS := Vector3(PI / 3.0, PI * 70.0 / 180.0, PI * 80.0 / 180.0)
const SUPPLIED_FINGER_LIMITS := Vector3(PI / 3.0, PI / 4.0, PI / 4.0)
const SUPPLIED_THUMB_LIMITS := Vector3(PI * 25.0 / 180.0, PI * 35.0 / 180.0, PI / 4.0)

var skeleton: Skeleton3D
var arm_meshes: Array[MeshInstance3D] = []
var hand_meshes: Array[MeshInstance3D] = []
var grip_amount := 0.0
var string_hook_amount := 0.0
var _side := 1
var _model: Node3D
var _forearm: Node3D
var _upper_arm: Node3D
var _cuff: Node3D
var _rests: Array[Quaternion] = []
var _part_rests: Dictionary = {}
var _source_path := ""
var _ready_for_pose := false
var _profile := "greybox"
var _joint_angles: Dictionary = {}
var _correctives: Dictionary = {}
var _thumb_opposition := 0.0
var _wrist_cuff_deformer := WRIST_CUFF_DEFORMER.new()
var _wrist_fit_anchor := Vector3.ZERO


static func sources_available(profile := "greybox") -> bool:
	if profile == "detailed":
		return ResourceLoader.exists(DETAILED_LEFT_PATH) and ResourceLoader.exists(DETAILED_RIGHT_PATH)
	return profile == "greybox" and ResourceLoader.exists(LEFT_PATH) and ResourceLoader.exists(RIGHT_PATH)


func setup(side: int, profile := "greybox") -> bool:
	if profile not in ["greybox", "detailed"]:
		return false
	if _ready_for_pose:
		return _side == (-1 if side < 0 else 1) and _profile == profile
	_side = -1 if side < 0 else 1
	_profile = profile
	_source_path = (DETAILED_LEFT_PATH if _side < 0 else DETAILED_RIGHT_PATH) if profile == "detailed" else (LEFT_PATH if _side < 0 else RIGHT_PATH)
	if not ResourceLoader.exists(_source_path):
		return false
	var packed := load(_source_path) as PackedScene
	if packed == null:
		return false
	_model = packed.instantiate() as Node3D
	if _model == null:
		return false
	add_child(_model)
	skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.get_bone_count() != 16 or skeleton.find_bone("wrist") < 0:
		return _reject_model()
	for digit: String in DIGITS:
		for joint in 3:
			if skeleton.find_bone(digit + str(joint)) < 0:
				return _reject_model()
	for bone in skeleton.get_bone_count():
		_rests.append(skeleton.get_bone_pose_rotation(bone))
	_forearm = _model.find_child("Forearm*", true, false) as Node3D
	_upper_arm = _model.find_child("UpperArm*", true, false) as Node3D
	_cuff = _model.find_child("WristCuff*", true, false) as Node3D
	if _forearm == null or _upper_arm == null or _cuff == null:
		return _reject_model()
	_collect_meshes(_model)
	if hand_meshes.is_empty() or arm_meshes.is_empty():
		return _reject_model()
	_cache_joint_correctives()
	for part: Node3D in [_forearm, _upper_arm, _cuff]:
		_part_rests[part.get_instance_id()] = LEGACY_FIT._accumulated_transform(self).affine_inverse() * LEGACY_FIT._accumulated_transform(part)
	if profile == "detailed":
		var skeleton_to_adapter := LEGACY_FIT._accumulated_transform(self).affine_inverse() * LEGACY_FIT._accumulated_transform(skeleton)
		var anatomical_wrist := skeleton_to_adapter * skeleton.get_bone_global_rest(skeleton.find_bone("wrist")).origin
		_wrist_cuff_deformer.setup(self, _cuff, anatomical_wrist)
		if _wrist_cuff_deformer.enabled:
			_wrist_fit_anchor = anatomical_wrist
	_ready_for_pose = true
	set_meta("source_model", _source_path)
	set_meta("anatomical_side", _side)
	set_meta("greybox", profile == "greybox")
	set_meta("detailed", profile == "detailed")
	set_meta("visual_profile", profile)
	reset_pose()
	return true


func _reject_model() -> bool:
	if is_instance_valid(_model):
		_model.free()
	_model = null
	skeleton = null
	_rests.clear()
	arm_meshes.clear()
	hand_meshes.clear()
	return false


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part.skin != null:
			hand_meshes.append(part)
		else:
			arm_meshes.append(part)
	for child in node.get_children():
		_collect_meshes(child)


func set_render_layers(value: int) -> void:
	for part: MeshInstance3D in arm_meshes + hand_meshes:
		part.layers = value


func _pose_digit(digit: String, proximal: float, distal: float, opposition := 0.0) -> void:
	if not _ready_for_pose or not DIGITS.has(digit) or not is_finite(proximal) or not is_finite(distal) or not is_finite(opposition):
		return
	# Preserve the authored gameplay poses at this compatibility boundary.
	# Individual joint controls below have no coupled distal/proximal motion.
	if digit == "thumb":
		_thumb_opposition = clampf(opposition, -0.8, 0.8)
	var angles := Vector3(proximal, distal * 0.58, distal * 0.42)
	for joint in 3:
		_apply_joint_angle(digit, joint, angles[joint])


func joint_limits(digit: String) -> Vector3:
	# Supplied anatomy already has 32–51 degrees of PIP flexion in its rest
	# shape. These are additional rotations, so preserve its authored curl.
	if _profile == "detailed":
		return SUPPLIED_THUMB_LIMITS if digit == "thumb" else SUPPLIED_FINGER_LIMITS
	return THUMB_LIMITS if digit == "thumb" else FINGER_LIMITS


func set_joint_flexion(digit: String, joint: int, amount: float) -> bool:
	if not _ready_for_pose or not DIGITS.has(digit) or joint < 0 or joint > 2 or not is_finite(amount):
		return false
	_apply_joint_angle(digit, joint, -joint_limits(digit)[joint] * clampf(amount, 0.0, 1.0))
	return true


func set_digit_flexion(digit: String, amounts: Vector3) -> bool:
	if not _ready_for_pose or not DIGITS.has(digit) or not amounts.is_finite():
		return false
	for joint in 3:
		set_joint_flexion(digit, joint, amounts[joint])
	return true


func _apply_joint_angle(digit: String, joint: int, radians: float) -> void:
	var limit := joint_limits(digit)[joint]
	var angle := clampf(radians, -limit, 0.0)
	var angles: Vector3 = _joint_angles.get(digit, Vector3.ZERO)
	angles[joint] = angle
	_joint_angles[digit] = angles
	var bone := skeleton.find_bone(digit + str(joint))
	var joint_rotation := Quaternion(Vector3.RIGHT, angle)
	if joint == 0 and digit == "thumb":
		joint_rotation = Quaternion(Vector3.UP, _thumb_opposition) * joint_rotation
	if angle == 0.0 and (joint != 0 or digit != "thumb" or _thumb_opposition == 0.0):
		skeleton.set_bone_pose_rotation(bone, _rests[bone])
	else:
		skeleton.set_bone_pose_rotation(bone, (_rests[bone] * joint_rotation).normalized())
	var key := "Joint_%s_%d" % [digit, joint]
	for binding: Dictionary in _correctives.get(key, []):
		(binding.mesh as MeshInstance3D).set_blend_shape_value(int(binding.index), -angle / limit)


func _cache_joint_correctives() -> void:
	_correctives.clear()
	for mesh: MeshInstance3D in hand_meshes:
		for index in mesh.mesh.get_blend_shape_count():
			var key := str(mesh.mesh.get_blend_shape_name(index))
			for digit: String in DIGITS:
				for joint in 3:
					if key == "Joint_%s_%d" % [digit, joint]:
						if not _correctives.has(key):
							_correctives[key] = []
						_correctives[key].append({"mesh": mesh, "index": index})


func get_joint_snapshot() -> Dictionary:
	var limits := {}
	var flexion := {}
	var morph_values := {}
	for digit: String in DIGITS:
		limits[digit] = joint_limits(digit)
		flexion[digit] = -(_joint_angles.get(digit, Vector3.ZERO) as Vector3) / joint_limits(digit)
	for key: String in _correctives:
		var first: Dictionary = _correctives[key][0]
		morph_values[key] = (first.mesh as MeshInstance3D).get_blend_shape_value(int(first.index))
	return {"ready": _ready_for_pose, "limits_radians": limits, "angles_radians": _joint_angles.duplicate(true), "flexion": flexion, "morph_values": morph_values, "morph_count": _correctives.size(), "corrective_available": _correctives.size() == 15}


func set_finger_curl(index: int, proximal_radians: float, distal_radians: float) -> void:
	if index < 0 or index > 4 or not is_finite(proximal_radians) or not is_finite(distal_radians):
		return
	# The original artwork reverses the four-finger index order on the left.
	var digit := str(DIGITS[3 - index if _side < 0 and index < 4 else index])
	_pose_digit(digit, proximal_radians, distal_radians)


func set_grip(amount: float, thumb_amount: float = -1.0) -> void:
	if not is_finite(amount) or not is_finite(thumb_amount):
		return
	grip_amount = clampf(amount, 0.0, 1.0)
	string_hook_amount = 0.0
	for digit: String in DIGITS.slice(0, 4):
		_pose_digit(digit, -1.05 * grip_amount, -1.40 * grip_amount)
	var thumb := grip_amount if thumb_amount < 0.0 else clampf(thumb_amount, 0.0, 1.0)
	_pose_digit("thumb", -0.65 * thumb, -0.95 * thumb, -_side * 0.62 * thumb)


func set_string_draw(grip_ratio: float, release_ratio: float = 0.0) -> void:
	if not is_finite(grip_ratio) or not is_finite(release_ratio):
		return
	var draw := clampf(grip_ratio, 0.0, 1.0)
	var release := smoothstep(0.0, 1.0, clampf(release_ratio, 0.0, 1.0))
	set_grip(0.0)
	for digit: String in ["index", "middle", "ring"]:
		_pose_digit(digit, lerpf(-0.43 - draw * 0.20, -0.05, release), lerpf(-1.20 - draw * 0.18, -0.08, release))
	_pose_digit("little", lerpf(-0.30, -0.08, release), lerpf(-0.42, -0.10, release))
	_pose_digit("thumb", -0.12, -0.15)
	string_hook_amount = (1.0 - release) * draw
	set_meta("string_hook_amount", string_hook_amount)


func set_relaxed_pose(openness: float = 0.0) -> void:
	if not is_finite(openness):
		return
	var opening := clampf(openness, 0.0, 1.0)
	set_grip(0.0)
	for index in 4:
		_pose_digit(str(DIGITS[index]), lerpf(-0.24 - index * 0.025, -0.035, opening), lerpf(-0.36 - index * 0.025, -0.08, opening))
	_pose_digit("thumb", lerpf(-0.18, -0.04, opening), -0.12)


func fit_arm(shoulder_world: Vector3, elbow_world: Vector3) -> void:
	if not _ready_for_pose or not shoulder_world.is_finite() or not elbow_world.is_finite():
		return
	var inverse := LEGACY_FIT._accumulated_transform(self).affine_inverse()
	var shoulder := inverse * shoulder_world
	var elbow := inverse * elbow_world
	# The flexible model spans the actual anatomical wrist, which is offset
	# from the legacy contact origin. Keep both that wrist and the elbow fixed.
	# Unmarked assets retain the historical zero-origin rigid fitting contract.
	var forearm_fit := LEGACY_FIT._fit_segment(Vector3(0, 0, 0.26), _wrist_fit_anchor, elbow, _wrist_fit_anchor)
	_apply_part_fit(_forearm, forearm_fit)
	_apply_part_fit(_upper_arm, LEGACY_FIT._fit_segment(Vector3(0, 0, 0.60), Vector3(0, 0, 0.26), shoulder, elbow))
	if _wrist_cuff_deformer.enabled:
		_apply_part_fit(_cuff, Transform3D.IDENTITY)
		_wrist_cuff_deformer.apply_fit(forearm_fit)
	else:
		_apply_part_fit(_cuff, Transform3D(forearm_fit.basis.orthonormalized(), Vector3.ZERO))


func _apply_part_fit(part: Node3D, fitted: Transform3D) -> void:
	var parent_from_self := LEGACY_FIT._accumulated_transform(part.get_parent() as Node3D).affine_inverse() * LEGACY_FIT._accumulated_transform(self)
	part.transform = parent_from_self * fitted * (_part_rests[part.get_instance_id()] as Transform3D)


func set_arm_visible(enabled: bool) -> void:
	for part: MeshInstance3D in arm_meshes:
		part.visible = enabled


func reset_pose() -> void:
	if not _ready_for_pose:
		return
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone, _rests[bone])
	_thumb_opposition = 0.0
	_joint_angles.clear()
	for digit: String in DIGITS:
		_joint_angles[digit] = Vector3.ZERO
	for bindings: Array in _correctives.values():
		for binding: Dictionary in bindings:
			(binding.mesh as MeshInstance3D).set_blend_shape_value(int(binding.index), 0.0)
	for part: Node3D in [_forearm, _upper_arm, _cuff]:
		_apply_part_fit(part, Transform3D.IDENTITY)
	_wrist_cuff_deformer.apply_fit(Transform3D.IDENTITY)
	grip_amount = 0.0
	string_hook_amount = 0.0


func get_source_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for part: MeshInstance3D in arm_meshes + hand_meshes:
		result.append(_wrist_cuff_deformer.source_mesh_for(part))
	return result


func get_wrist_snapshot() -> Dictionary:
	var snapshot := _wrist_cuff_deformer.get_snapshot()
	snapshot["forearm_pivot"] = _wrist_fit_anchor
	return snapshot


func get_snapshot() -> Dictionary:
	var visible_meshes := 0
	for part: MeshInstance3D in arm_meshes + hand_meshes:
		if part.is_visible_in_tree():
			visible_meshes += 1
	return {"ready": _ready_for_pose, "profile": _profile, "side": _side, "source_model": _source_path, "bone_count": skeleton.get_bone_count() if is_instance_valid(skeleton) else 0, "visible_mesh_count": visible_meshes, "grip_amount": grip_amount, "string_hook_amount": string_hook_amount}
