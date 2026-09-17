extends "res://scripts/bandage_use_visuals.gd"
## Timed presentation; inventory and health are committed by the player.
const DRINK_DURATION := 5.8
const DRINK_END := 4.65
const DRINK_MOUTH := Vector3(0.015, -0.085, -0.075)
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
	return active and elapsed >= STOW_END and elapsed < 5.35

func _position_equipment() -> void:
	var tucked := smoothstep(0.0, STOW_END, elapsed) * (1.0 - smoothstep(5.35, DRINK_DURATION, elapsed))
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
	visible = elapsed >= STOW_END and elapsed < 5.35
	var lift := smoothstep(0.4, 0.85, elapsed)
	var sip := smoothstep(1.4, 2.0, elapsed) * (1.0 - smoothstep(DRINK_END, 5.15, elapsed))
	var drink := clampf((elapsed - 2.0) / (DRINK_END - 2.0), 0, 1)
	var gulp := sin(drink * TAU * 4.0) * sin(PI * drink)
	fill = 1.0 - smoothstep(0.0, 1.0, drink)
	var tilt := (2.20 + 0.17 * drink + 0.035 * gulp) * sip
	var bottle_basis := Basis(Vector3.RIGHT, tilt).rotated(Vector3.FORWARD, -0.13 * sip)
	var position_target := Vector3(0.10, -0.13, -0.42).lerp(DRINK_MOUTH - bottle_basis * (BOTTLE_LIP * BOTTLE_SIZE * MODEL_SCALE), sip)
	position_target += Vector3(0.003 * gulp, -0.006 * gulp, 0.004 * gulp) * (1.0 - sip)
	position_target.y -= 0.55 * (1.0 - lift + smoothstep(4.95, 5.35, elapsed))
	bottle.transform = Transform3D(bottle_basis * Basis.from_scale(BOTTLE_SIZE * MODEL_SCALE), position_target)
	var hand_basis := bottle_basis * BOTTLE_HAND_BASIS
	right_arm.transform = Transform3D(hand_basis, position_target - hand_basis * GRIP)
	for digit: String in BOTTLE_FINGER_POSE:
		right_arm.set_digit_flexion(digit, BOTTLE_FINGER_POSE[digit])
	right_arm.position += position_target + bottle_basis * BOTTLE_GRIP_OFFSET - _grip(right_arm)
	right_arm.fit_arm(to_global(Vector3(0.60, -0.60, 0.02)), right_arm._active_visual.global_position + global_basis * hand_basis.z * 0.25)
	var pull := smoothstep(0.90, 1.35, elapsed)
	cork.position = Vector3(-4.0 * pull, 4.795 + 4.0 * pull, 0)
	# Carry the removed cork out of view instead of popping the left hand away.
	var cap_withdraw := smoothstep(1.25, 1.65, elapsed)
	cork.global_position += global_basis * Vector3(-0.48, -0.30, 0) * cap_withdraw
	cork.visible = elapsed < 1.65
	left_arm.visible = elapsed < 1.65
	if left_arm.visible:
		left_arm.transform = Transform3D(_hand_basis(Vector3(-0.65, -0.65, 0.20).normalized(), Vector3.UP), position_target)
		for digit: String in ["index", "middle", "ring", "little", "thumb"]:
			left_arm.set_digit_flexion(digit, Vector3(0.55, 0.60, 0.55))
		left_arm.position += to_local(cork.global_position) - _grip(left_arm)
		left_arm.fit_arm(to_global(Vector3(-0.60, -0.55, 0.02)), to_global(Vector3(-0.38, -0.32, -0.08)))
	liquid_up = (BOTTLE_SIZE * (bottle_basis.inverse() * Vector3.UP)).normalized()
	liquid_up = (liquid_up + Vector3(0.045 * sin(elapsed * 9), 0, 0.065 * sin(elapsed * 11 + 0.6)) * sip).normalized()
	_rebuild_liquid()
	stage = "병 꺼내기" if elapsed < 0.9 else ("마개 열기" if elapsed < 1.5 else ("꿀꺽 마시기" if elapsed < DRINK_END else "빈 병 내리기"))

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
