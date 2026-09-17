extends Node3D
## Optional, separately authored blockout using the production wrist convention.
## Only presentation changes: the caller owns the real grip/contact and timing.

const LEGACY_FIT := preload("res://scripts/player_arm_visual.gd")
const LEFT_PATH := "res://assets/3d/player/hands_greybox/left_hand_greybox.glb"
const RIGHT_PATH := "res://assets/3d/player/hands_greybox/right_hand_greybox.glb"
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const CONTACT_OFFSET := Vector3(0.0, 0.019, -0.0035)

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


static func sources_available() -> bool:
	return ResourceLoader.exists(LEFT_PATH) and ResourceLoader.exists(RIGHT_PATH)


func setup(side: int) -> bool:
	if _ready_for_pose:
		return _side == (-1 if side < 0 else 1)
	_side = -1 if side < 0 else 1
	_source_path = LEFT_PATH if _side < 0 else RIGHT_PATH
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
	for part: Node3D in [_forearm, _upper_arm, _cuff]:
		_part_rests[part.get_instance_id()] = LEGACY_FIT._accumulated_transform(self).affine_inverse() * LEGACY_FIT._accumulated_transform(part)
	_ready_for_pose = true
	set_meta("source_model", _source_path)
	set_meta("anatomical_side", _side)
	set_meta("greybox", true)
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
	if not _ready_for_pose:
		return
	var angles := [proximal, distal * 0.58, distal * 0.42]
	for joint in 3:
		var bone := skeleton.find_bone(digit + str(joint))
		var joint_rotation := Quaternion(Vector3.RIGHT, float(angles[joint]))
		if joint == 0 and digit == "thumb":
			joint_rotation = Quaternion(Vector3.UP, opposition) * joint_rotation
		skeleton.set_bone_pose_rotation(bone, (_rests[bone] * joint_rotation).normalized())


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
	var forearm_fit := LEGACY_FIT._fit_segment(Vector3(0, 0, 0.26), Vector3.ZERO, elbow, Vector3.ZERO)
	_apply_part_fit(_forearm, forearm_fit)
	_apply_part_fit(_upper_arm, LEGACY_FIT._fit_segment(Vector3(0, 0, 0.60), Vector3(0, 0, 0.26), shoulder, elbow))
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
	for part: Node3D in [_forearm, _upper_arm, _cuff]:
		_apply_part_fit(part, Transform3D.IDENTITY)
	grip_amount = 0.0
	string_hook_amount = 0.0


func get_source_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for part: MeshInstance3D in arm_meshes + hand_meshes:
		result.append(part.mesh)
	return result


func get_snapshot() -> Dictionary:
	var visible_meshes := 0
	for part: MeshInstance3D in arm_meshes + hand_meshes:
		if part.is_visible_in_tree():
			visible_meshes += 1
	return {"ready": _ready_for_pose, "side": _side, "source_model": _source_path, "bone_count": skeleton.get_bone_count() if is_instance_valid(skeleton) else 0, "visible_mesh_count": visible_meshes, "grip_amount": grip_amount, "string_hook_amount": string_hook_amount}
