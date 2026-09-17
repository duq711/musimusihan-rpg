extends Node3D
## Articulated first-person parts from the same GLB used by the full-body player.
## The root is the wrist: fingers point -Z and the back of the hand faces +Y.
## All mesh/material resources remain shared with the imported character.

const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const SOURCE_PIXEL_SCALE := 1.78 / 1392.0
const SOURCE_LEFT_DIGITS := [
	[Vector2(266, 787), Vector2(273, 819)],
	[Vector2(276, 794), Vector2(289, 832)],
	[Vector2(286, 793), Vector2(300, 824)],
	[Vector2(296, 785), Vector2(307, 812)],
	[Vector2(300, 765), Vector2(306, 794)],
]
const SOURCE_RIGHT_DIGITS := [
	[Vector2(710, 789), Vector2(699, 827)],
	[Vector2(720, 796), Vector2(711, 841)],
	[Vector2(730, 796), Vector2(723, 838)],
	[Vector2(739, 788), Vector2(735, 820)],
	[Vector2(695, 769), Vector2(684, 799)],
]

## Four fingers at indices 0..3, thumb at index 4; each holds [proximal, distal].
var finger_joints: Array[Array] = []
var hand_meshes: Array[MeshInstance3D] = []
var arm_meshes: Array[MeshInstance3D] = []

static var _source_parts: Dictionary = {}
var _side: int = 1
var _source_suffix := "L"
var _hand_space := Transform3D.IDENTITY
var _finger_rest: Array[Array] = []
var _upper_segment: Node3D
var _forearm_segment: Node3D
var _shoulder_rest := Vector3.ZERO
var _elbow_rest := Vector3.ZERO
var greybox_visual: Node3D
var greybox_enabled := false
var detailed_visual: Node3D
var detailed_enabled := false
var visual_profile := "original"
var _active_visual: Node3D
var _arm_visible := true


## side -1 is the player's left; side +1 is the player's right.
func setup(side: int) -> void:
	_clear_parts()
	_side = -1 if side < 0 else 1
	_cache_source_parts()
	if _source_parts.is_empty():
		return
	# Source suffixes describe the artwork, not anatomical sides. Inspect the
	# imported transform so the GLB root's 180-degree rotation is included.
	_source_suffix = _suffix_for_side(_side)
	var source_left := _source_suffix == "L"
	var wrist := _source_point(Vector2(281, 718), -0.074) if source_left else _source_point(Vector2(722, 730), -0.078)
	var hand_basis := Basis(Vector3.RIGHT, PI / 2.0)
	_hand_space = Transform3D(hand_basis, -(hand_basis * wrist))
	var shoulder := _source_point(Vector2(352, 366), 0.0) if source_left else _source_point(Vector2(673, 366), 0.0)
	var elbow := _source_point(Vector2(300, 573), -0.013) if source_left else _source_point(Vector2(719, 582), -0.025)
	_shoulder_rest = _hand_space * shoulder
	_elbow_rest = _hand_space * elbow
	_upper_segment = Node3D.new()
	_upper_segment.name = "UpperArmJoint"
	add_child(_upper_segment)
	_forearm_segment = Node3D.new()
	_forearm_segment.name = "ForearmJoint"
	add_child(_forearm_segment)
	var sleeve := _add_source_mesh("Gravebound_Sleeve_" + _source_suffix, _upper_segment, Transform3D.IDENTITY)
	var bracer := _add_source_mesh("Gravebound_Bracer_" + _source_suffix, _forearm_segment, Transform3D.IDENTITY)
	if sleeve != null:
		arm_meshes.append(sleeve)
	if bracer != null:
		arm_meshes.append(bracer)
	var glove := _add_source_mesh("Gravebound_FingerlessGlove_" + _source_suffix, self, Transform3D.IDENTITY)
	if glove != null:
		# The imported glove extends past the articulated knuckles. Keep its
		# wrist and shared surface, but expose the fingers when they hook/curl.
		glove.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.93)), Vector3.ZERO) * glove.transform
		hand_meshes.append(glove)
	var digits: Array = SOURCE_LEFT_DIGITS if source_left else SOURCE_RIGHT_DIGITS
	for index in range(5):
		_add_digit(index, digits[index][0], digits[index][1])
	set_meta("source_model", MODEL_PATH)
	set_meta("source_side", _source_suffix)
	set_meta("anatomical_side", _side)
	reset_pose()


## Negative local-X angles curl toward the palm (-Y). Angles are radians.
func set_finger_curl(index: int, proximal_radians: float, distal_radians: float) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_finger_curl", index, proximal_radians, distal_radians)
		return
	if index < 0 or index >= finger_joints.size():
		return
	var proximal: Node3D = finger_joints[index][0]
	var distal: Node3D = finger_joints[index][1]
	var proximal_rest: Transform3D = _finger_rest[index][0]
	var distal_rest: Transform3D = _finger_rest[index][1]
	proximal.transform = proximal_rest * Transform3D(Basis(Vector3.RIGHT, proximal_radians), Vector3.ZERO)
	distal.transform = distal_rest * Transform3D(Basis(Vector3.RIGHT, distal_radians), Vector3.ZERO)


## amount 0 opens the hand, 1 wraps the digits around a held handle.
func set_grip(amount: float, thumb_amount: float = -1.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_grip", amount, thumb_amount)
		return
	var grip := clampf(amount, 0.0, 1.0)
	for index in range(mini(4, finger_joints.size())):
		set_finger_curl(index, -1.05 * grip, -1.40 * grip)
	if finger_joints.size() < 5:
		return
	var thumb_grip := grip if thumb_amount < 0.0 else clampf(thumb_amount, 0.0, 1.0)
	set_finger_curl(4, -0.65 * thumb_grip, -0.95 * thumb_grip)
	var thumb: Node3D = finger_joints[4][0]
	var thumb_rest: Transform3D = _finger_rest[4][0]
	thumb.basis = thumb_rest.basis * Basis(Vector3.UP, -_side * 0.62 * thumb_grip) * Basis(Vector3.RIGHT, -0.65 * thumb_grip)


## Right-hand archery hook: three fingers hold the string while thumb/little
## finger remain loose. Release opens the real joints without moving the nock.
func set_string_draw(grip_ratio: float, release_ratio: float = 0.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_string_draw", grip_ratio, release_ratio)
		return
	var draw := clampf(grip_ratio, 0.0, 1.0)
	var release := smoothstep(0.0, 1.0, clampf(release_ratio, 0.0, 1.0))
	set_grip(0.0)
	for digit in 3:
		var index := digit if _side > 0 else 3 - digit
		set_finger_curl(index, lerpf(-0.43 - draw * 0.20, -0.05, release), lerpf(-1.20 - draw * 0.18, -0.08, release))
	var little := 3 if _side > 0 else 0
	set_finger_curl(little, lerpf(-0.30, -0.08, release), lerpf(-0.42, -0.10, release))
	set_finger_curl(4, -0.12, -0.15)
	set_meta("string_hook_amount", (1.0 - release) * draw)


## A relaxed off hand counterbalances one-handed weapons and opens to assist
## casting. It shares the same fingers and materials as the equipped hands.
func set_relaxed_pose(openness: float = 0.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_relaxed_pose", openness)
		return
	var opening := clampf(openness, 0.0, 1.0)
	set_grip(0.0)
	for index in 4:
		set_finger_curl(index, lerpf(-0.24 - float(index) * 0.025, -0.035, opening), lerpf(-0.36 - float(index) * 0.025, -0.08, opening))
	set_finger_curl(4, lerpf(-0.18, -0.04, opening), -0.12)


## Fit only the sleeve/bracer to world-space arm anchors. The wrist root, hand,
## parent contact frame, weapon pivot and muzzle are never moved or clamped.
func fit_arm(shoulder_world: Vector3, elbow_world: Vector3) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("fit_arm", shoulder_world, elbow_world)
		return
	if _upper_segment == null or _forearm_segment == null:
		return
	if not shoulder_world.is_finite() or not elbow_world.is_finite():
		return
	var world_to_wrist := _accumulated_transform(self).affine_inverse()
	var shoulder: Vector3 = world_to_wrist * shoulder_world
	var elbow: Vector3 = world_to_wrist * elbow_world
	_upper_segment.transform = _fit_segment(_shoulder_rest, _elbow_rest, shoulder, elbow)
	_forearm_segment.transform = _fit_segment(_elbow_rest, Vector3.ZERO, elbow, Vector3.ZERO)


## Hides only the sleeve and bracer, leaving the hand/digits visible.
func set_arm_visible(enabled: bool) -> void:
	_arm_visible = enabled
	if is_instance_valid(_active_visual):
		_active_visual.call("set_arm_visible", enabled)
		return
	for part in arm_meshes:
		part.visible = enabled


## Restore open digits and the imported arm rest pose without moving the root.
func reset_pose() -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("reset_pose")
		return
	if _upper_segment != null:
		_upper_segment.transform = Transform3D.IDENTITY
	if _forearm_segment != null:
		_forearm_segment.transform = Transform3D.IDENTITY
	set_grip(0.0)


## Original GLB Mesh references, in arm_meshes then hand_meshes order (13 total).
func get_source_meshes() -> Array[Mesh]:
	if is_instance_valid(_active_visual):
		return _active_visual.call("get_source_meshes")
	var result: Array[Mesh] = []
	for part in arm_meshes:
		result.append(part.mesh)
	for part in hand_meshes:
		result.append(part.mesh)
	return result


## Retain this exact wrist, parent contact and original source resources.
## Review profiles replace only visible geometry below the wrist.
func set_greybox_enabled(enabled: bool) -> bool:
	return set_visual_profile("greybox" if enabled else ("original" if greybox_enabled else visual_profile))


func set_detailed_enabled(enabled: bool) -> bool:
	return set_visual_profile("detailed" if enabled else ("original" if detailed_enabled else visual_profile))


func set_joint_flexion(digit: String, joint: int, amount: float) -> bool:
	return is_instance_valid(_active_visual) and bool(_active_visual.call("set_joint_flexion", digit, joint, amount))


func set_digit_flexion(digit: String, amounts: Vector3) -> bool:
	return is_instance_valid(_active_visual) and bool(_active_visual.call("set_digit_flexion", digit, amounts))


func get_joint_snapshot() -> Dictionary:
	return _active_visual.call("get_joint_snapshot") if is_instance_valid(_active_visual) else {"ready": false, "corrective_available": false}


func set_visual_profile(profile: String) -> bool:
	if profile not in ["original", "greybox", "detailed"]:
		return false
	var selected: Node3D = greybox_visual if profile == "greybox" else detailed_visual if profile == "detailed" else null
	if profile != "original" and not is_instance_valid(selected):
		var adapter_script := load("res://scripts/greybox_arm_visual.gd") as Script
		if adapter_script == null:
			return false
		var candidate := adapter_script.new() as Node3D
		candidate.name = "DetailedArmVisual" if profile == "detailed" else "GreyboxArmVisual"
		add_child(candidate)
		if not bool(candidate.call("setup", _side, profile)):
			candidate.free()
			return false
		# Align the skinned palm with the legacy 86 mm gameplay contact.
		# Imported geometry uses (0, -19, -82.5) mm in wrist space.
		candidate.position = Vector3(0.0, 0.019, -0.0035)
		if profile == "detailed":
			detailed_visual = candidate
		else:
			greybox_visual = candidate
		selected = candidate
	visual_profile = profile
	greybox_enabled = profile == "greybox"
	detailed_enabled = profile == "detailed"
	_active_visual = selected
	for adapter: Node3D in [greybox_visual, detailed_visual]:
		if not is_instance_valid(adapter):
			continue
		adapter.visible = adapter == selected
		# Carried arms may be enabled after the renderer's initial layer pass;
		# chest arms keep their own world layer for real chest occlusion.
		if not hand_meshes.is_empty():
			adapter.call("set_render_layers", hand_meshes[0].layers)
		adapter.call("set_arm_visible", _arm_visible)
	for part: MeshInstance3D in arm_meshes:
		part.visible = profile == "original" and _arm_visible
	for part: MeshInstance3D in hand_meshes:
		part.visible = profile == "original"
	return true


func _add_digit(index: int, first_pixel: Vector2, last_pixel: Vector2) -> void:
	var middle_pixel := first_pixel.lerp(last_pixel, 0.52)
	var first: Vector3 = _hand_space * _source_point(first_pixel, -0.113)
	var middle: Vector3 = _hand_space * _source_point(middle_pixel, -0.117)
	var last: Vector3 = _hand_space * _source_point(last_pixel, -0.113)
	var proximal_frame := Transform3D(Basis.looking_at(middle - first, Vector3.UP), first)
	var distal_frame := Transform3D(Basis.looking_at(last - middle, Vector3.UP), middle)
	var proximal := Node3D.new()
	proximal.name = "ThumbProximal" if index == 4 else "Finger%dProximal" % index
	add_child(proximal)
	proximal.transform = proximal_frame
	# The source artwork places skin strips above the glove's curved surface.
	# Seat their real roots into the palm before articulation so open hands
	# remain connected, too. The wrist and equipment contact frame stay fixed.
	proximal.position.y -= 0.026
	var distal := Node3D.new()
	distal.name = "ThumbDistal" if index == 4 else "Finger%dDistal" % index
	proximal.add_child(distal)
	distal.transform = proximal_frame.affine_inverse() * distal_frame
	finger_joints.append([proximal, distal])
	_finger_rest.append([proximal.transform, distal.transform])
	var prefix := "Gravebound_Finger_" + _source_suffix + str(index)
	var first_mesh := _add_source_mesh(prefix + "a", proximal, proximal_frame)
	var last_mesh := _add_source_mesh(prefix + "b", distal, distal_frame)
	if first_mesh != null:
		hand_meshes.append(first_mesh)
	if last_mesh != null:
		hand_meshes.append(last_mesh)


func _add_source_mesh(part_name: String, parent: Node3D, joint_frame: Transform3D) -> MeshInstance3D:
	if not _source_parts.has(part_name):
		push_error("Player arm is missing character part: " + part_name)
		return null
	var source: Dictionary = _source_parts[part_name]
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = source["mesh"] as Mesh
	part.material_override = source["material_override"] as Material
	var overrides: Array = source["surface_overrides"]
	for index in range(overrides.size()):
		if overrides[index] != null:
			part.set_surface_override_material(index, overrides[index] as Material)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.set_meta("source_part", part_name)
	part.set_meta("source_model", MODEL_PATH)
	parent.add_child(part)
	var source_transform: Transform3D = source["transform"]
	part.transform = joint_frame.affine_inverse() * _hand_space * source_transform
	return part


func _clear_parts() -> void:
	if is_instance_valid(greybox_visual):
		greybox_visual.free()
	if is_instance_valid(detailed_visual):
		detailed_visual.free()
	greybox_visual = null
	greybox_enabled = false
	detailed_visual = null
	detailed_enabled = false
	visual_profile = "original"
	_active_visual = null
	_arm_visible = true
	for part in arm_meshes:
		if is_instance_valid(part):
			part.free()
	for part in hand_meshes:
		if is_instance_valid(part):
			part.free()
	for joints in finger_joints:
		if is_instance_valid(joints[0]):
			(joints[0] as Node3D).free()
	if is_instance_valid(_upper_segment):
		_upper_segment.free()
	if is_instance_valid(_forearm_segment):
		_forearm_segment.free()
	_upper_segment = null
	_forearm_segment = null
	arm_meshes.clear()
	hand_meshes.clear()
	finger_joints.clear()
	_finger_rest.clear()


static func _cache_source_parts() -> void:
	if not _source_parts.is_empty():
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("The player arm requires the production character GLB.")
		return
	var source := packed.instantiate()
	_collect_source_parts(source, Transform3D.IDENTITY)
	source.free()


static func _collect_source_parts(node: Node, parent_transform: Transform3D) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var part_name := String(part.name)
		if part_name.begins_with("Gravebound_Sleeve_") or part_name.begins_with("Gravebound_Bracer_") or part_name.begins_with("Gravebound_FingerlessGlove_") or part_name.begins_with("Gravebound_Finger_"):
			var overrides: Array[Material] = []
			for index in range(part.get_surface_override_material_count()):
				overrides.append(part.get_surface_override_material(index))
			_source_parts[part_name] = {"mesh": part.mesh, "transform": current_transform, "material_override": part.material_override, "surface_overrides": overrides}
	for child in node.get_children():
		_collect_source_parts(child, current_transform)


static func _suffix_for_side(side: int) -> String:
	for suffix in ["L", "R"]:
		var part_name: String = "Gravebound_FingerlessGlove_" + suffix
		if not _source_parts.has(part_name):
			continue
		var source: Dictionary = _source_parts[part_name]
		var mesh: Mesh = source["mesh"]
		var source_transform: Transform3D = source["transform"]
		var center: Vector3 = source_transform * mesh.get_aabb().get_center()
		if center.x * side > 0.0:
			return suffix
	return "R" if side < 0 else "L"


static func _source_point(pixel: Vector2, depth: float) -> Vector3:
	# Blender Z-up, glTF axis conversion, then the model root's Y rotation.
	return Vector3(-(pixel.x - 512.0) * SOURCE_PIXEL_SCALE, (1454.0 - pixel.y) * SOURCE_PIXEL_SCALE, depth)


static func _accumulated_transform(node: Node3D) -> Transform3D:
	# Also works on detached rigs, without querying global_transform off-tree.
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


static func _segment_frame(start: Vector3, end: Vector3) -> Transform3D:
	var direction := (end - start).normalized()
	var reference := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var lateral := reference.cross(direction).normalized()
	return Transform3D(Basis(lateral, direction, lateral.cross(direction).normalized()), start)


static func _fit_segment(rest_start: Vector3, rest_end: Vector3, target_start: Vector3, target_end: Vector3) -> Transform3D:
	var rest_length := rest_start.distance_to(rest_end)
	var target_length := target_start.distance_to(target_end)
	if rest_length < 0.0001 or target_length < 0.0001:
		return Transform3D.IDENTITY
	var rest_frame := _segment_frame(rest_start, rest_end)
	var target_frame := _segment_frame(target_start, target_end)
	var axial_scale := Basis.from_scale(Vector3(1.0, target_length / rest_length, 1.0))
	return target_frame * Transform3D(axial_scale, Vector3.ZERO) * rest_frame.affine_inverse()
