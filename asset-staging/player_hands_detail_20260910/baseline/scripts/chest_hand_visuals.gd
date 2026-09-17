extends Node3D
class_name ChestHandVisuals

const PLAYER_ARM_VISUAL := preload("res://scripts/player_arm_visual.gd")
const MAX_FOREARM_LENGTH := 0.31
const WRIST_LOCAL := Vector3(0.0, -0.014, 0.155)

var active := false
var left_hand: Node3D
var right_hand: Node3D
var progress := 0.0
var phase := "idle"
var _player: Node3D
var _chest: Node3D
var _camera: Camera3D
var _arms: Dictionary = {}
var _built := false
var greybox_enabled := false


func setup(player_ref: Node3D) -> void:
	_player = player_ref
	_camera = player_ref.find_child("PlayerCamera", true, false) as Camera3D if is_instance_valid(player_ref) else null
	_ensure_built()
	clear()


func begin(chest_ref: Node3D) -> void:
	clear()
	if not is_instance_valid(_player) or not is_instance_valid(_camera) or not is_instance_valid(chest_ref):
		return
	if not chest_ref.has_method("get_hand_contact_transform"):
		return
	_chest = chest_ref
	active = true
	visible = true
	set_progress(0.0)


func set_progress(value: float) -> void:
	if not active:
		return
	if not is_finite(value):
		return
	if not is_instance_valid(_chest) or _chest.is_queued_for_deletion() or not is_instance_valid(_camera):
		clear()
		return
	progress = clampf(value, 0.0, 1.0)
	if progress < 0.16:
		phase = "stow"
	elif progress < 0.32:
		phase = "reach"
	elif progress < 0.78:
		phase = "fidget"
	elif progress < 0.94:
		phase = "lift"
	elif progress < 1.0:
		phase = "withdraw"
	else:
		phase = "complete"
	var hands_visible := progress >= 0.16 and progress < 1.0
	for side in [-1, 1]:
		var hand := left_hand if side == -1 else right_hand
		hand.visible = hands_visible
		if hands_visible and is_inside_tree() and _camera.is_inside_tree() and _chest.is_inside_tree():
			_pose_hand(hand, side)


func clear() -> void:
	active = false
	progress = 0.0
	phase = "idle"
	_chest = null
	visible = false
	if is_instance_valid(left_hand):
		left_hand.visible = false
	if is_instance_valid(right_hand):
		right_hand.visible = false


func set_greybox_enabled(enabled: bool) -> bool:
	_ensure_built()
	for side in [-1, 1]:
		if not bool((_arms[side] as Node3D).call("set_greybox_enabled", enabled)):
			for restore_side in [-1, 1]:
				(_arms[restore_side] as Node3D).call("set_greybox_enabled", greybox_enabled)
			return false
	greybox_enabled = enabled
	if active:
		set_progress(progress)
	return true


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	# All motion is derived from the player's real interaction progress. There
	# is no independent process, tween, collision, or gameplay state here.
	set_process(false)
	set_physics_process(false)
	left_hand = _build_hand(-1)
	right_hand = _build_hand(1)


func _build_hand(side: int) -> Node3D:
	# Keep the real chest contact frame unchanged; only its visual model changes.
	var hand := Node3D.new()
	hand.name = "LeftBareHand" if side == -1 else "RightBareHand"
	add_child(hand)
	var arm := PLAYER_ARM_VISUAL.new()
	arm.name = "CharacterArm"
	hand.add_child(arm)
	arm.setup(side)
	arm.position = WRIST_LOCAL
	_arms[side] = arm
	return hand


func _pose_hand(hand: Node3D, side: int) -> void:
	var contact: Transform3D = _chest.call("get_hand_contact_transform", side, progress)
	contact.basis = contact.basis.orthonormalized()
	var amount := smoothstep(0.16, 0.32, progress)
	if progress >= 0.94:
		amount *= 1.0 - smoothstep(0.94, 1.0, progress)
	var rest := _camera.global_transform * Vector3(float(side) * 0.34, -0.67, -0.19)
	var fidget_weight := smoothstep(0.30, 0.35, progress) * (1.0 - smoothstep(0.74, 0.79, progress))
	var beat := (progress - 0.32) * TAU * 5.0 + (0.0 if side == 1 else PI * 0.72)
	# Stay on the actual wood/latch rather than playing a camera-space pose.
	# These millimetre-scale motions lift the fingertips away from the surface,
	# never move the whole arm in a wide circle through the chest.
	contact.origin += contact.basis.y * ((sin(beat) + 1.0) * 0.004 * fidget_weight)
	contact.origin += contact.basis.x * (sin(beat * 0.7) * 0.006 * fidget_weight)
	var resting_basis := _camera.global_basis.orthonormalized()
	hand.global_transform = Transform3D(resting_basis.slerp(contact.basis, amount), rest.lerp(contact.origin, amount))
	var arm: Node3D = _arms[side]
	var lift_grip := smoothstep(0.76, 0.84, progress) * (1.0 - smoothstep(0.94, 1.0, progress))
	for index in 4:
		var tapping := sin(beat + float(index) * 0.85) * fidget_weight
		arm.call("set_finger_curl", index, -0.14 - amount * 0.07 - tapping * 0.09 - lift_grip * 0.18, -0.26 - tapping * 0.12 - lift_grip * 0.42)
	arm.call("set_finger_curl", 4, -0.22 - sin(beat * 0.83) * 0.13 * fidget_weight - lift_grip * 0.18, -0.28 - sin(beat + 0.4) * 0.16 * fidget_weight)
	_pose_sleeve(hand, side)


func _pose_sleeve(hand: Node3D, side: int) -> void:
	var wrist := hand.global_transform * WRIST_LOCAL
	# The shoulder sits below and just behind the camera, outside the viewport.
	# A bent upper sleeve continues to it so the visible forearm never ends in
	# a chopped cylinder halfway across the image at ordinary opening range.
	var shoulder := _camera.global_transform * Vector3(float(side) * 0.32, -0.48, 0.08)
	var wanted_elbow := shoulder.lerp(wrist, 0.49)
	wanted_elbow += _camera.global_basis * Vector3(float(side) * 0.12, -0.13, 0.0)
	var elbow := wrist + (wanted_elbow - wrist).limit_length(MAX_FOREARM_LENGTH)
	# Keep the actual shoulder behind the camera. Clamping this start toward
	# the elbow exposes a floating, capped sleeve at normal chest reach.
	(_arms[side] as Node3D).call("fit_arm", shoulder, elbow)
