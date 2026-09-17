extends "res://scripts/bandage_use_visuals.gd"
## Timed presentation; inventory and health are committed by the player.
const DRINK_DURATION := 6.6
const DRINK_START := 3.0
const DRINK_END := 5.45
const POCKET_TIME := 6.15
const DRINK_MOUTH := Vector3(0.015, -0.085, -0.045)
var bottle: Node3D
var cork: MeshInstance3D
var liquid: MeshInstance3D
var liquid_source: Mesh
var liquid_material: StandardMaterial3D
var fill := 1.0
var stage := ""
var liquid_up := Vector3.UP
var liquid_level := 0.0
const MODEL_SCALE := 0.022
# A broad flask held across the palm; the index finger sits toward the neck.
const BOTTLE_SIZE := Vector3(0.90, 1.20, 0.90)
const BOTTLE_LIP := Vector3(0, 5.143, 0)
const BOTTLE_GRIP_OFFSET := Vector3(0.041383307, 0.014861340, -0.013416447)
const BOTTLE_HAND_BASIS := Basis(Vector3(-0.201049888, -0.864533583, -0.460608973), Vector3(0.843342693, 0.086453628, -0.530376161), Vector3(0.498349320, -0.495083280, 0.711716588))
const BOTTLE_FINGER_POSE := {
	"index": Vector3(0.306858534, 0.200822594, 1.000000000),
	"middle": Vector3(0.265295468, 0.297283276, 0.741470162),
	"ring": Vector3(0.165000000, 0.473946177, 0.365000000),
	"little": Vector3(0.020000000, 0.615249246, 0.310000000),
	"thumb": Vector3(0.233590444, 0.804491085, 0.575000000),
}

# Bottle-top axis and fingertip contact were fitted against the supplied left-hand skin.
const CAP_HAND_CENTER := Vector3(0.013384187, -0.063138651, -0.114266110)
const CAP_HAND_BASIS := Basis(Vector3(0.999975506, 0.006999143, 0.000000000), Vector3(-0.006998457, 0.999877523, 0.013998628), Vector3(0.000097978, -0.013998285, 0.999902014))
const CAP_FINGER_POSE := {
	"index": Vector3(0.533948664, 0.884146886, 0.624727228),
	"middle": Vector3(0.652432312, 0.796511932, 0.721119819),
	"ring": Vector3(0.600076350, 0.759318354, 0.678573156),
	"little": Vector3(0.549979131, 0.680524039, 0.622076560),
	"thumb": Vector3(0.796078899, 0.624578494, 0.667113122),
}
var cap_turn := 0.0
var cap_hand_turn := 0.0
var cap_lift := 0.0
var cap_grip_strength := 0.0

func setup() -> void:
	right_arm = ARM.new()
	add_child(right_arm)
	right_arm.setup(1)
	left_arm = ARM.new()
	add_child(left_arm)
	left_arm.setup(-1)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("res://assets/3d/items/potions/red_potion.glb", state) == OK)
	bottle = document.generate_scene(state)
	add_child(bottle)
	cork = bottle.find_child("Cork", true, false)
	liquid = bottle.find_child("Liquid", true, false)
	liquid_source = liquid.mesh
	liquid_material = StandardMaterial3D.new()
	liquid_material.albedo_color = Color(0.65, 0.025, 0.012, 0.92)
	liquid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	liquid_material.roughness = 0.18
	liquid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	liquid.material_override = liquid_material
	var glass: MeshInstance3D = bottle.find_child("Glass", true, false)
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.70, 0.86, 0.80, 0.16)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness = 0.12
	glass_material.cull_mode = BaseMaterial3D.CULL_BACK
	glass.material_override = glass_material
	clear()

func advance(delta: float) -> void:
	if not active or delta <= 0: return
	if elapsed + delta >= DRINK_DURATION: clear()
	else: set_time(elapsed + delta)

func equipment_hidden() -> bool:
	return active and elapsed >= STOW_END and elapsed < POCKET_TIME

func _position_equipment() -> void:
	var tucked := smoothstep(0.0, STOW_END, elapsed) * (1.0 - smoothstep(POCKET_TIME, DRINK_DURATION, elapsed))
	var offset := Transform3D(Basis(Vector3.RIGHT, -0.55 * tucked), Vector3(0.02, -1.10, 0.12) * tucked)
	for entry: Dictionary in _carried:
		if is_instance_valid(entry.node): entry.node.global_transform = get_parent().global_transform * offset * entry.camera

func _grip(arm: Node3D) -> Vector3:
	var rig: Skeleton3D = arm._active_visual.skeleton
	var point := Vector3.ZERO
	for bone: String in ["middle1", "ring1", "thumb2"]:
		point += to_local(rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin)) / 3.0
	return point

func set_time(seconds: float) -> void:
	elapsed = clampf(seconds, 0, DRINK_DURATION)
	_position_equipment()
	visible = elapsed >= STOW_END and elapsed < POCKET_TIME
	var lift := smoothstep(0.4, 0.85, elapsed)
	var sip := smoothstep(2.5, DRINK_START, elapsed) * (1.0 - smoothstep(DRINK_END, 5.95, elapsed))
	var drink := clampf((elapsed - DRINK_START) / (DRINK_END - DRINK_START), 0, 1)
	var gulp := sin(drink * TAU * 4.0) * sin(PI * drink)
	fill = 1.0 - smoothstep(0.0, 1.0, drink)
	# Aim the neck back into the face. A modest upward base angle keeps the
	# bottle foreshortened toward the mouth instead of hanging neck-down.
	var tilt := (1.72 + 0.16 * drink + 0.025 * gulp) * sip
	var bottle_basis := Basis(Vector3.RIGHT, tilt).rotated(Vector3.FORWARD, -0.06 * sip)
	# Open the stopper close to the chest, framing the hands and cuffs.
	var position_target := Vector3(0.06, -0.12, -0.25).lerp(DRINK_MOUTH - bottle_basis * (BOTTLE_LIP * BOTTLE_SIZE * MODEL_SCALE), sip)
	position_target += Vector3(0.003 * gulp, -0.006 * gulp, 0.004 * gulp) * (1.0 - sip)
	position_target.y -= 0.55 * (1.0 - lift + smoothstep(5.75, POCKET_TIME, elapsed))
	bottle.transform = Transform3D(bottle_basis * Basis.from_scale(BOTTLE_SIZE * MODEL_SCALE), position_target)
	var hand_basis := bottle_basis * BOTTLE_HAND_BASIS
	right_arm.transform = Transform3D(hand_basis, position_target - hand_basis * GRIP)
	for digit: String in BOTTLE_FINGER_POSE:
		right_arm.set_digit_flexion(digit, BOTTLE_FINGER_POSE[digit])
	right_arm.position += position_target + bottle_basis * BOTTLE_GRIP_OFFSET - _grip(right_arm)
	right_arm.fit_arm(to_global(Vector3(0.60, -0.60, 0.02)), right_arm._active_visual.global_position + global_basis * hand_basis.z * 0.25)
	_animate_cap(bottle_basis)
	liquid_up = (BOTTLE_SIZE * (bottle_basis.inverse() * Vector3.UP)).normalized()
	liquid_up = (liquid_up + Vector3(0.045 * sin(elapsed * 9), 0, 0.065 * sin(elapsed * 11 + 0.6)) * sip).normalized()
	_rebuild_liquid()
	stage = "병 꺼내기" if elapsed < 0.9 else ("마개 돌려 열기" if elapsed < 2.5 else ("꿀꺽 마시기" if elapsed < DRINK_END else "빈 병 내리기"))


func _animate_cap(bottle_basis: Basis) -> void:
	# Two short turns with a relaxed regrip. The stopper keeps its progress
	# while the fingers open and the wrist returns for the second turn.
	var first := smoothstep(0.98, 1.40, elapsed)
	var reset := smoothstep(1.44, 1.66, elapsed)
	var second := smoothstep(1.70, 2.14, elapsed)
	var release := smoothstep(1.39, 1.49, elapsed) * (1.0 - smoothstep(1.57, 1.70, elapsed))
	cap_turn = 0.85 * first + 0.95 * second
	cap_hand_turn = 0.85 * first * (1.0 - reset) + 0.95 * second
	cap_lift = 0.0015 * first + 0.002 * second + 0.062 * smoothstep(2.17, 2.42, elapsed)
	var withdraw := smoothstep(2.42, 2.80, elapsed)
	var retreat := Vector3(-0.50, -0.32, 0.02) * withdraw
	cork.position = Vector3(0, 4.795 + cap_lift / (MODEL_SCALE * BOTTLE_SIZE.y), 0)
	cork.rotation = Vector3(0, cap_turn, 0)
	cork.global_position += global_basis * retreat
	cork.visible = elapsed < 2.80
	left_arm.visible = elapsed < 2.80
	cap_grip_strength = smoothstep(0.76, 0.98, elapsed) * (1.0 - 0.80 * release)
	if not left_arm.visible: return
	# The thumb and index close first; the other fingers settle after them.
	var digit_index := 0
	for digit: String in CAP_FINGER_POSE:
		var lag := 0.0 if digit == "thumb" or digit == "index" else 0.025 * digit_index
		var close := smoothstep(0.76 + lag, 0.98 + lag, elapsed)
		var open_pose: Vector3 = CAP_FINGER_POSE[digit] - Vector3(0.25, 0.34, 0.25)
		var pose: Vector3 = open_pose.lerp(CAP_FINGER_POSE[digit], close)
		pose -= Vector3(0.14, 0.22, 0.16) * release
		left_arm.set_digit_flexion(digit, pose)
		digit_index += 1
	var approach := 1.0 - smoothstep(0.54, 0.98, elapsed)
	var hand_basis := bottle_basis * Basis(Vector3.UP, -1.65 + cap_hand_turn) * CAP_HAND_BASIS
	var contact := to_local(cork.global_position) + bottle_basis * Vector3(0, 0.016, 0)
	# Approach from the upper left; opening fingers gives the wrist room to reset.
	contact += Vector3(-0.22, 0.10, 0.04) * approach
	contact += bottle_basis * Vector3(-0.004, 0.004, 0.003) * release
	left_arm.transform = Transform3D(hand_basis, contact - hand_basis * CAP_HAND_CENTER)
	# Continue the sleeve out of frame along the wrist instead of showing the
	# elbow bending across the bottle during each short turn.
	var elbow := left_arm.global_position + global_basis * (hand_basis.z * 0.43 + Vector3(-0.035, -0.025, 0.015))
	left_arm.fit_arm(to_global(Vector3(-0.60, -0.55, 0.02)), elbow)

func _rebuild_liquid() -> void:
	liquid.visible = fill > 0.001
	if not liquid.visible: return
	var arrays := liquid_source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var low := INF
	var high := -INF
	for point in vertices:
		low = minf(low, point.dot(liquid_up))
		high = maxf(high, point.dot(liquid_up))
	liquid_level = lerpf(low, high, fill)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	for i in range(0, indices.size(), 3):
		var polygon: Array[Vector3] = []
		for edge in 3:
			var a := vertices[indices[i + edge]]
			var b := vertices[indices[i + (edge + 1) % 3]]
			var da := a.dot(liquid_up) - liquid_level
			var db := b.dot(liquid_up) - liquid_level
			if da <= 0: polygon.append(a)
			if (da < 0 and db > 0) or (da > 0 and db < 0):
				var cut := a.lerp(b, da / (da - db))
				polygon.append(cut)
				rim.append(cut)
		for j in range(1, polygon.size() - 1):
			for point in [polygon[0], polygon[j], polygon[j + 1]]: surface.add_vertex(point)
	if rim.size() >= 3:
		var u := liquid_up.cross(Vector3.RIGHT if absf(liquid_up.x) < 0.9 else Vector3.FORWARD).normalized()
		var v := liquid_up.cross(u)
		var flat := PackedVector2Array()
		for point in rim: flat.append(Vector2(point.dot(u), point.dot(v)))
		var hull := Geometry2D.convex_hull(flat)
		var center := Vector3.ZERO
		for point in rim: center += point / rim.size()
		for i in hull.size() - 1:
			for point in [center, u * hull[i + 1].x + v * hull[i + 1].y + liquid_up * liquid_level, u * hull[i].x + v * hull[i].y + liquid_up * liquid_level]: surface.add_vertex(point)
	surface.generate_normals()
	liquid.mesh = surface.commit()
