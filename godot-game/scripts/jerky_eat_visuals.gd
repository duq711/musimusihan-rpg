extends "res://scripts/bandage_use_visuals.gd"
## Presentation only. DungeonPlayer commits the food effect after the full action.
## Reference: kaJqMSBgi00, 1:45–1:53: draw, bite, lower, second bite, put away.
const EAT_DURATION := 8.0
const POCKET_TIME := 7.55
const EAT_MOUTH := Vector3(0.0, -0.13, -0.07)
const BITE_TIMES := Vector2(2.80, 5.80)
const FOOD_SCENE := preload("res://assets/3d/items/beef_jerky/beef_jerky_variants.glb")
# Calibrated against the supplied right hand, in the wrist's local space.
var food_in_hand := Transform3D(Basis(Vector3(0.052640656, -0.986006268, 0.158179013), Vector3(0.311346431, 0.166708245, 0.935559598), Vector3(-0.948837373, 0.0, 0.315765164)), Vector3(-0.020170543, -0.118799206, -0.096766052))
const FOOD_GRIP_X := -0.055
const FINGER_POSE := {
	"index": Vector3(0.707306505, 1.0, 0.822281024),
	"middle": Vector3(0.652432312, 0.796511932, 0.721119819),
	"ring": Vector3(0.600076350, 0.759318354, 0.678573156),
	"little": Vector3(0.549979131, 0.680524039, 0.622076560),
	"thumb": Vector3(0.853546361, 0.109133584, 1.0),
}
var food: MeshInstance3D
var food_meshes: Array[Mesh] = []
var bite_count := 0
var stage := ""
var mouth_contact := false
var bite_tip := Vector3.ZERO
var source_bounds := AABB()

func setup() -> void:
	right_arm = ARM.new()
	add_child(right_arm)
	right_arm.setup(1)
	left_arm = ARM.new()
	add_child(left_arm)
	left_arm.setup(-1)
	left_arm.visible = false
	var source := FOOD_SCENE.instantiate()
	food = source.find_child("Jerky_01_long_torn_strip", true, false)
	assert(food != null, "The original irregular jerky strip must be present")
	food.get_parent().remove_child(food)
	source.free()
	add_child(food)
	food.transform = Transform3D.IDENTITY
	source_bounds = food.mesh.get_aabb()
	food_meshes.append(food.mesh)
	food_meshes.append(_bitten_mesh(food.mesh, source_bounds.end.x - 0.052))
	food_meshes.append(_bitten_mesh(food.mesh, source_bounds.end.x - 0.102))
	clear()

func advance(delta: float) -> void:
	if not active or delta <= 0.0: return
	if elapsed + delta >= EAT_DURATION: clear()
	else: set_time(elapsed + delta)

func clear() -> void:
	super.clear()
	bite_count = 0
	mouth_contact = false
	stage = ""
	if is_instance_valid(food) and not food_meshes.is_empty():
		food.mesh = food_meshes[0]

func equipment_hidden() -> bool:
	return active and elapsed >= STOW_END and elapsed < POCKET_TIME

func _position_equipment() -> void:
	var tucked := smoothstep(0.0, STOW_END, elapsed) * (1.0 - smoothstep(POCKET_TIME, EAT_DURATION, elapsed))
	var offset := Transform3D(Basis(Vector3.RIGHT, -0.55 * tucked), Vector3(0.02, -1.10, 0.12) * tucked)
	for entry: Dictionary in _carried:
		if is_instance_valid(entry.node): entry.node.global_transform = get_parent().global_transform * offset * entry.camera

func set_time(seconds: float) -> void:
	elapsed = clampf(seconds, 0.0, EAT_DURATION)
	_position_equipment()
	visible = elapsed >= STOW_END and elapsed < POCKET_TIME
	left_arm.visible = false
	var draw := smoothstep(0.42, 1.18, elapsed)
	var first := smoothstep(1.85, 2.55, elapsed) * (1.0 - smoothstep(2.96, 3.58, elapsed))
	var second := smoothstep(4.68, 5.45, elapsed) * (1.0 - smoothstep(5.96, 6.57, elapsed))
	var bite := first + second
	var pocket := smoothstep(6.88, POCKET_TIME, elapsed)
	bite_count = int(elapsed >= BITE_TIMES.x) + int(elapsed >= BITE_TIMES.y)
	food.mesh = food_meshes[bite_count]
	# Independent small finger settling keeps the strip firmly pinched; the
	# ring/little fingers can relax without moving the thumb/index contact.
	var settle := sin(elapsed * 3.2) * 0.035 * (1.0 - bite)
	for digit: String in FINGER_POSE:
		var pose: Vector3 = FINGER_POSE[digit]
		if digit == "ring" or digit == "little": pose += Vector3(0.3, 1.0, 0.5) * settle
		right_arm.set_digit_flexion(digit, pose)
	var exposed_tip := source_bounds.end.x - (0.052 if elapsed >= 3.58 else 0.0)
	if elapsed >= 6.57: exposed_tip -= 0.050
	# The exposed end approaches lips below the eye camera. The forearm stays
	# connected to its low, right-side elbow throughout both bites.
	var idle_axis := Vector3(-0.82, 0.44, 0.37).normalized()
	var eating_axis := Vector3(-0.42, -0.70, 0.58).normalized()
	var axis := idle_axis.slerp(eating_axis, bite).normalized()
	var forearm_direction := Vector3(0.75, -0.48, 0.55).normalized()
	var radial := (forearm_direction - axis * axis.dot(forearm_direction)).normalized()
	var normal := Basis(axis, -atan2(food_in_hand.basis.z.z, food_in_hand.basis.y.z)) * radial
	var food_basis := Basis(axis, normal, axis.cross(normal)).orthonormalized()
	var idle_grip := Vector3(0.16, -0.075, -0.32)
	var chew := sin(elapsed * 10.5) * 0.0025 * (1.0 - bite) * draw
	idle_grip += Vector3(sin(elapsed * 2.4) * 0.006, chew, cos(elapsed * 2.0) * 0.003)
	var origin := (idle_grip - food_basis * Vector3(FOOD_GRIP_X, 0.004, 0.0)).lerp(EAT_MOUTH - food_basis * Vector3(exposed_tip, 0.004, 0.0), bite)
	origin += Vector3(0.19, -0.48, 0.04) * (1.0 - draw + pocket)
	# A short outward tug after contact suggests teeth tearing tough fibres.
	var tug := (smoothstep(2.78, 2.92, elapsed) - smoothstep(2.92, 3.12, elapsed)) + (smoothstep(5.78, 5.93, elapsed) - smoothstep(5.93, 6.14, elapsed))
	origin -= axis * 0.010 * tug
	food.transform = Transform3D(food_basis, origin)
	right_arm.transform = food.transform * food_in_hand.affine_inverse()
	right_arm.fit_arm(to_global(Vector3(0.58, -0.62, 0.10)), to_global(Vector3(0.48, -0.39, 0.05)))
	bite_tip = food.transform * Vector3(exposed_tip, 0.004, 0.0)
	mouth_contact = bite > 0.999
	stage = "육포 꺼내기" if elapsed < 1.4 else ("첫 한입" if elapsed < 3.58 else ("씹으며 손 내리기" if elapsed < 4.68 else ("두 번째 한입" if elapsed < 6.57 else "손 내리기")))

func _bite_distance(point: Vector3, cutoff: float) -> float:
	# Several rounded teeth marks and uneven pulled fibres across the width.
	var teeth := 0.003 * cos(point.z * 540.0) + 0.0017 * sin(point.z * 970.0 + 0.7)
	return point.x - cutoff - teeth

func _bitten_mesh(source: Mesh, cutoff: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface_index in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size(): indices.append(i)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rim: Array[Vector3] = []
		for i in range(0, indices.size(), 3):
			var polygon: Array[Dictionary] = []
			for edge in 3:
				var ai := indices[i + edge]
				var bi := indices[i + (edge + 1) % 3]
				var a := vertices[ai]
				var b := vertices[bi]
				var da := _bite_distance(a, cutoff)
				var db := _bite_distance(b, cutoff)
				if da <= 0.0: polygon.append({"p": a, "n": normals[ai], "uv": uvs[ai]})
				if (da < 0 and db > 0) or (da > 0 and db < 0):
					var ratio := da / (da - db)
					var point := a.lerp(b, ratio)
					polygon.append({"p": point, "n": normals[ai].lerp(normals[bi], ratio).normalized(), "uv": uvs[ai].lerp(uvs[bi], ratio)})
					rim.append(point)
			for j in range(1, polygon.size() - 1):
				for vertex: Dictionary in [polygon[0], polygon[j], polygon[j + 1]]:
					surface.set_normal(vertex.n)
					surface.set_uv(vertex.uv)
					surface.add_vertex(vertex.p)
		# Close the bitten cross section; the original material/UVs stay on the
		# unbitten surface, rather than stretching or shrinking the whole strip.
		if rim.size() >= 3:
			var center := Vector3.ZERO
			for point in rim: center += point / float(rim.size())
			rim.sort_custom(func(a: Vector3, b: Vector3) -> bool: return atan2(a.z - center.z, a.y - center.y) < atan2(b.z - center.z, b.y - center.y))
			for i in rim.size():
				for point: Vector3 in [center, rim[i], rim[(i + 1) % rim.size()]]:
					surface.set_normal(Vector3.RIGHT)
					surface.set_uv(Vector2(0.46 + point.z * 2.0, 0.45 + point.y * 3.0))
					surface.add_vertex(point)
		surface.generate_tangents()
		surface.set_material(source.surface_get_material(surface_index))
		surface.commit(result)
	return result
