extends Node3D
## Production supplied hands and their review profiles share the real skinned
## source. The root remains the gameplay wrist: fingers -Z, dorsal surface +Y.
## "original" means the current shipped hands, including after testroom reset.

const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const DETAILED_LEFT_PATH := "res://assets/3d/player/hands_detailed/left_hand_detailed.glb"
const DETAILED_RIGHT_PATH := "res://assets/3d/player/hands_detailed/right_hand_detailed.glb"
const CONTACT_OFFSET := Vector3(0.0, 0.019, -0.0035)

## Kept as an empty compatibility diagnostic. Finger motion now belongs to the
## actual Skeleton3D, exposed through detailed_visual and get_joint_snapshot().
var finger_joints: Array[Array] = []
var hand_meshes: Array[MeshInstance3D] = []
var arm_meshes: Array[MeshInstance3D] = []
var greybox_visual: Node3D
var greybox_enabled := false
var detailed_visual: Node3D
var detailed_enabled := false
var visual_profile := "original"
var _side := 1
var _active_visual: Node3D
var _arm_visible := true
var _render_layers := 1


## side -1 is the player's left; side +1 is the player's right.
func setup(side: int) -> void:
	var previous_layers := hand_meshes[0].layers if not hand_meshes.is_empty() and is_instance_valid(hand_meshes[0]) else _render_layers
	_clear_parts()
	_render_layers = previous_layers
	_side = -1 if side < 0 else 1
	set_meta("body_model", MODEL_PATH)
	set_meta("anatomical_side", _side)
	set_meta("source_side", "R" if _side < 0 else "L")
	if not set_visual_profile("original"):
		push_error("The production player arm could not load its supplied skinned hand: " + _production_source_path())
		return
	reset_pose()


func set_finger_curl(index: int, proximal_radians: float, distal_radians: float) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_finger_curl", index, proximal_radians, distal_radians)


func set_grip(amount: float, thumb_amount: float = -1.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_grip", amount, thumb_amount)


func set_torch_grip() -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_torch_grip")


func set_string_draw(grip_ratio: float, release_ratio: float = 0.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_string_draw", grip_ratio, release_ratio)


func set_relaxed_pose(openness: float = 0.0) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("set_relaxed_pose", openness)


## Sleeve fitting stays inside the adapter. This wrapper, its equipment parent,
## the gameplay wrist, combat collision and chest contact frames never move.
func fit_arm(shoulder_world: Vector3, elbow_world: Vector3) -> void:
	if is_instance_valid(_active_visual):
		_active_visual.call("fit_arm", shoulder_world, elbow_world)


func set_arm_visible(enabled: bool) -> void:
	_arm_visible = enabled
	for adapter: Node3D in [detailed_visual, greybox_visual]:
		if is_instance_valid(adapter): adapter.call("set_arm_visible", enabled)


func set_render_layers(value: int) -> void:
	_render_layers = value
	for adapter: Node3D in [detailed_visual, greybox_visual]:
		if is_instance_valid(adapter): adapter.call("set_render_layers", value)


func reset_pose() -> void:
	if is_instance_valid(_active_visual): _active_visual.call("reset_pose")


## Actual imported source resources for the active profile. The flexible cuff
## reports its imported source even when an instance owns a deforming copy.
func get_source_meshes() -> Array[Mesh]:
	return _active_visual.call("get_source_meshes") if is_instance_valid(_active_visual) else []


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


func get_wrist_snapshot() -> Dictionary:
	return _active_visual.call("get_wrist_snapshot") if is_instance_valid(_active_visual) else {"enabled": false, "surfaces": []}


func set_visual_profile(profile: String) -> bool:
	if profile not in ["original", "greybox", "detailed"]: return false
	# Layer20 is assigned by the real viewmodel renderer after initial setup;
	# chest hands remain on world layer1. Carry that live assignment to a newly
	# instantiated comparison, rather than assuming every arm is a viewmodel.
	if not hand_meshes.is_empty() and is_instance_valid(hand_meshes[0]):
		_render_layers = hand_meshes[0].layers
	var selected: Node3D = greybox_visual if profile == "greybox" else detailed_visual
	if not is_instance_valid(selected):
		# The imported adapter uses the static fitting helpers below. Resolve it
		# lazily here so that there is no circular preload of these two scripts.
		var adapter_script := load("res://scripts/greybox_arm_visual.gd") as Script
		if adapter_script == null: return false
		var candidate := adapter_script.new() as Node3D
		candidate.name = "GreyboxArmVisual" if profile == "greybox" else "SuppliedHandVisual"
		add_child(candidate)
		var source_profile := "greybox" if profile == "greybox" else "detailed"
		if not bool(candidate.call("setup", _side, source_profile)):
			candidate.free()
			return false
		# The supplied pair is authored in the existing imported wrist space.
		# Preserve the 86 mm gameplay palm contact and all equipment anchors.
		candidate.position = CONTACT_OFFSET
		if profile == "greybox": greybox_visual = candidate
		else: detailed_visual = candidate
		selected = candidate
	visual_profile = profile
	greybox_enabled = profile == "greybox"
	detailed_enabled = profile == "detailed"
	_active_visual = selected
	for adapter: Node3D in [detailed_visual, greybox_visual]:
		if not is_instance_valid(adapter): continue
		adapter.visible = adapter == selected
		adapter.call("set_render_layers", _render_layers)
		adapter.call("set_arm_visible", _arm_visible)
	hand_meshes.assign(selected.get("hand_meshes"))
	arm_meshes.assign(selected.get("arm_meshes"))
	set_meta("source_model", str(selected.get_meta("source_model", "")))
	set_meta("visual_profile", profile)
	set_meta("supplied_hand", profile != "greybox")
	return true


func _production_source_path() -> String:
	return DETAILED_LEFT_PATH if _side < 0 else DETAILED_RIGHT_PATH


func _clear_parts() -> void:
	# Public arrays reference children owned by these adapters. Free the owner
	# exactly once instead of individually freeing shared hand mesh references.
	for adapter: Node3D in [detailed_visual, greybox_visual]:
		if is_instance_valid(adapter): adapter.free()
	detailed_visual = null
	greybox_visual = null
	_active_visual = null
	greybox_enabled = false
	detailed_enabled = false
	visual_profile = "original"
	_arm_visible = true
	_render_layers = 1
	finger_joints.clear()
	hand_meshes.clear()
	arm_meshes.clear()
	for key: String in ["source_model", "visual_profile", "supplied_hand", "string_hook_amount"]:
		if has_meta(key): remove_meta(key)


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
