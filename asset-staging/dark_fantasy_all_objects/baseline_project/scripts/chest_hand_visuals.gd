extends Node3D
class_name ChestHandVisuals

const PLAYER_APPEARANCE := preload("res://scripts/player_appearance.gd")
const MAX_FOREARM_LENGTH := 0.58
const MAX_UPPER_ARM_LENGTH := 0.78
const WRIST_LOCAL := Vector3(0.0, 0.034, 0.202)

var active := false
var left_hand: Node3D
var right_hand: Node3D
var progress := 0.0
var phase := "idle"
var _player: Node3D
var _chest: Node3D
var _camera: Camera3D
var _skin: StandardMaterial3D
var _skin_detail: StandardMaterial3D
var _nail: StandardMaterial3D
var _cloth: StandardMaterial3D
var _cuff: StandardMaterial3D
var _finger_joints: Dictionary = {}
var _thumb_joints: Dictionary = {}
var _sleeves: Dictionary = {}
var _upper_sleeves: Dictionary = {}
var _elbows: Dictionary = {}
var _built := false


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
		(_sleeves[side] as Node3D).visible = hands_visible
		(_upper_sleeves[side] as Node3D).visible = hands_visible
		(_elbows[side] as Node3D).visible = hands_visible
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
	for sleeve in _sleeves.values():
		(sleeve as Node3D).visible = false
	for sleeve in _upper_sleeves.values():
		(sleeve as Node3D).visible = false
	for elbow in _elbows.values():
		(elbow as Node3D).visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	# All motion is derived from the player's real interaction progress. There
	# is no independent process, tween, collision, or gameplay state here.
	set_process(false)
	set_physics_process(false)
	_skin = PLAYER_APPEARANCE.skin_material()
	_skin_detail = _material(Color(0.39, 0.305, 0.255), 0.91)
	_nail = _material(Color(0.55, 0.46, 0.395), 0.69)
	_cloth = PLAYER_APPEARANCE.cloth_material()
	_cuff = PLAYER_APPEARANCE.leather_material()
	left_hand = _build_hand(-1)
	right_hand = _build_hand(1)
	_build_sleeve(-1)
	_build_sleeve(1)


func _build_hand(side: int) -> Node3D:
	var hand := Node3D.new()
	hand.name = "LeftBareHand" if side == -1 else "RightBareHand"
	add_child(hand)
	var palm := MeshInstance3D.new()
	palm.name = "BarePalm"
	palm.mesh = _palm_mesh()
	palm.material_override = _cuff
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.add_child(palm)
	var wrist := _capsule(0.024, 0.085, _cuff)
	wrist.name = "BareWrist"
	wrist.position = Vector3(0.0, 0.034, 0.203)
	wrist.rotation.x = PI * 0.5
	hand.add_child(wrist)
	var fingers: Array = []
	var lengths := [0.075, 0.084, 0.078, 0.064]
	for index in 4:
		var root_joint := Node3D.new()
		root_joint.name = "Finger%d" % index
		root_joint.position = Vector3(float(side) * (float(index) - 1.5) * 0.022, 0.034, 0.081)
		root_joint.rotation.y = float(side) * (float(index) - 1.5) * -0.045
		hand.add_child(root_joint)
		var joints := _build_digit(root_joint, float(lengths[index]), 0.0087 if index < 3 else 0.0076, 3)
		fingers.append(joints)
		var crease := _box(Vector3(0.012, 0.0011, 0.0018), _skin_detail)
		crease.name = "KnuckleCrease"
		crease.position = Vector3(0.0, 0.0085, -0.006)
		root_joint.add_child(crease)
		var tendon := _capsule(0.0017, 0.048, _cuff)
		tendon.name = "HandTendon%d" % index
		tendon.position = Vector3(root_joint.position.x * 0.70, 0.055, 0.12)
		tendon.rotation.x = PI * 0.5
		hand.add_child(tendon)
	_finger_joints[side] = fingers
	var thumb := Node3D.new()
	thumb.name = "Thumb"
	thumb.position = Vector3(-float(side) * 0.035, 0.02, 0.136)
	thumb.rotation = Vector3(-0.26, float(side) * 0.90, float(side) * 0.28)
	hand.add_child(thumb)
	_thumb_joints[side] = _build_digit(thumb, 0.068, 0.011, 2)
	return hand


func _build_digit(root_joint: Node3D, length: float, radius: float, count: int) -> Array:
	var joints: Array = [root_joint]
	var fractions := [0.44, 0.32, 0.24] if count == 3 else [0.56, 0.44]
	var current := root_joint
	for index in count:
		var segment_length := length * float(fractions[index])
		var segment_radius := radius * (1.0 - float(index) * 0.12)
		var bone := _capsule(segment_radius, segment_length + segment_radius * 0.30, _cuff if index == 0 else _skin)
		bone.name = "BareFingerSegment%d" % index
		bone.position.z = -segment_length * 0.5
		bone.rotation.x = PI * 0.5
		current.add_child(bone)
		if index + 1 < count:
			var next_joint := Node3D.new()
			next_joint.name = "Middle" if index == 0 else "Tip"
			next_joint.position.z = -segment_length
			current.add_child(next_joint)
			joints.append(next_joint)
			current = next_joint
		else:
			var nail := _box(Vector3(segment_radius * 1.34, 0.0018, segment_length * 0.58), _nail)
			nail.name = "NaturalFingernail"
			nail.position = Vector3(0.0, segment_radius * 0.89, -segment_length * 0.55)
			current.add_child(nail)
	return joints


func _build_sleeve(side: int) -> void:
	var sleeve := Node3D.new()
	sleeve.name = "LeftClothForearm" if side == -1 else "RightClothForearm"
	add_child(sleeve)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.037
	mesh.bottom_radius = 0.049
	mesh.height = 1.0
	mesh.radial_segments = 12
	var arm := MeshInstance3D.new()
	arm.name = "ClothSleeve"
	arm.mesh = mesh
	arm.material_override = _cloth
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sleeve.add_child(arm)
	for index in 3:
		var seam := _box(Vector3(0.062, 0.008, 0.063), _cuff)
		seam.name = "ClothCuffFold%d" % index
		seam.position.y = 0.43 - float(index) * 0.027
		sleeve.add_child(seam)
	_sleeves[side] = sleeve
	var upper := Node3D.new()
	upper.name = "LeftUpperSleeve" if side == -1 else "RightUpperSleeve"
	add_child(upper)
	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.052
	upper_mesh.bottom_radius = 0.078
	upper_mesh.height = 1.0
	upper_mesh.radial_segments = 12
	var upper_visual := MeshInstance3D.new()
	upper_visual.name = "ContinuousUpperSleeve"
	upper_visual.mesh = upper_mesh
	upper_visual.material_override = _cloth
	upper_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	upper.add_child(upper_visual)
	_upper_sleeves[side] = upper
	var elbow := _capsule(0.052, 0.115, _cloth)
	elbow.name = "LeftSleeveElbow" if side == -1 else "RightSleeveElbow"
	add_child(elbow)
	_elbows[side] = elbow


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
	var fingers: Array = _finger_joints[side]
	for index in fingers.size():
		var joints: Array = fingers[index]
		var tapping := sin(beat + float(index) * 0.85) * fidget_weight
		(joints[0] as Node3D).rotation.x = -0.14 - amount * 0.07 - tapping * 0.09
		(joints[1] as Node3D).rotation.x = -0.26 - tapping * 0.12
		(joints[2] as Node3D).rotation.x = -0.16 - tapping * 0.10
	var thumb: Array = _thumb_joints[side]
	(thumb[0] as Node3D).rotation.x = -0.22 - sin(beat * 0.83) * 0.13 * fidget_weight
	(thumb[1] as Node3D).rotation.x = -0.28 - sin(beat + 0.4) * 0.16 * fidget_weight
	_pose_sleeve(hand, side)


func _pose_sleeve(hand: Node3D, side: int) -> void:
	var wrist := hand.global_transform * WRIST_LOCAL
	# The shoulder sits below and just behind the camera, outside the viewport.
	# A bent upper sleeve continues to it so the visible forearm never ends in
	# a chopped cylinder halfway across the image at ordinary opening range.
	var shoulder := _camera.global_transform * Vector3(float(side) * 0.33, -0.64, 0.12)
	var wanted_elbow := shoulder.lerp(wrist, 0.49)
	wanted_elbow += _camera.global_basis * Vector3(float(side) * 0.14, -0.13, 0.0)
	var elbow := wrist + (wanted_elbow - wrist).limit_length(MAX_FOREARM_LENGTH)
	var upper_start := elbow + (shoulder - elbow).limit_length(MAX_UPPER_ARM_LENGTH)
	_pose_arm_segment(_sleeves[side] as Node3D, elbow, wrist)
	_pose_arm_segment(_upper_sleeves[side] as Node3D, upper_start, elbow)
	var joint := _elbows[side] as Node3D
	joint.global_position = elbow
	joint.global_basis = (_sleeves[side] as Node3D).global_basis.orthonormalized()


func _pose_arm_segment(segment: Node3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	var length := maxf(direction.length(), 0.025)
	if direction.length_squared() < 0.00001:
		direction = Vector3.UP
	direction = direction.normalized()
	var reference := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.96 else Vector3.FORWARD
	var axis_x := reference.cross(direction).normalized()
	var axis_z := axis_x.cross(direction).normalized()
	segment.global_transform = Transform3D(Basis(axis_x, direction, axis_z), (start + end) * 0.5)
	segment.scale = Vector3(1.0, length, 1.0)


func _palm_mesh() -> ArrayMesh:
	# Tapered flattened rings form a broad palm and narrow wrist, not a sphere.
	var stations := [Vector3(0.034, 0.015, 0.077), Vector3(0.042, 0.021, 0.098), Vector3(0.038, 0.020, 0.143), Vector3(0.026, 0.015, 0.178), Vector3(0.024, 0.014, 0.197)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for ring in stations.size() - 1:
		for segment in 16:
			var a := _palm_vertex(stations[ring], segment)
			var b := _palm_vertex(stations[ring], segment + 1)
			var c := _palm_vertex(stations[ring + 1], segment)
			var d := _palm_vertex(stations[ring + 1], segment + 1)
			for vertex in [a, c, b, b, c, d]:
				surface.add_vertex(vertex)
	for cap in [0, stations.size() - 1]:
		var center := Vector3(0.0, 0.034, stations[cap].z)
		for segment in 16:
			var a := _palm_vertex(stations[cap], segment)
			var b := _palm_vertex(stations[cap], segment + 1)
			for vertex in [center, a, b] if cap == 0 else [center, b, a]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	surface.index()
	return surface.commit()


func _palm_vertex(station: Vector3, segment: int) -> Vector3:
	var angle := float(segment) * TAU / 16.0
	return Vector3(cos(angle) * station.x, 0.034 + sin(angle) * station.y, station.z)


func _capsule(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.01)
	mesh.radial_segments = 10
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _box(dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
