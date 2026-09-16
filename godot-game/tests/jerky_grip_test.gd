extends SceneTree
## Contact is measured from the real skinned hand, independently of the motion's
## grip anchor. The ray is tested against the supplied irregular food triangles.
const MOTION := preload("res://scripts/jerky_eat_visuals.gd")
const SAMPLES := [0.9, 1.4, 2.65, 3.8, 5.6, 6.65]
const PAD_VERTICES := [156, 17] # Supplied right index pad, thumb pad.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	# Avoid an accidentally correct test that only works at the world origin.
	holder.transform = Transform3D(Basis.from_euler(Vector3(0.13, -0.38, 0.09)), Vector3(1.2, 0.8, -2.0))
	var motion := MOTION.new()
	holder.add_child(motion)
	motion.setup()
	motion.begin()
	var hand: MeshInstance3D = motion.right_arm._active_visual.hand_meshes[0]
	var original_hand_mesh := hand.mesh
	var arrays := original_hand_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == 2031, "contact indices must match the supplied right-hand skin")
	for seconds: float in SAMPLES:
		motion.set_time(seconds)
		_check(motion.visible and motion.right_arm.visible, "the held hand stays visible at %.2f" % seconds)
		_check(hand.mesh == original_hand_mesh and hand.visible, "the complete original hand remains attached at %.2f" % seconds)
		_check(motion.right_arm.scale.is_equal_approx(Vector3.ONE), "hand scale is not shortened to hide intersections")
		for part: MeshInstance3D in motion.right_arm._active_visual.arm_meshes:
			_check(part.visible and part.mesh != null, "the connected sleeve/forearm is retained")
		var food_arrays := motion.food.mesh.surface_get_arrays(0)
		var food_bounds := motion.food.mesh.get_aabb()
		for vertex_index: int in PAD_VERTICES:
			var point := motion.food.to_local(_skin_point(motion.right_arm, vertex_index))
			var interval := _vertical_interval(food_arrays, point)
			_check(interval.x < INF, "the food remains between thumb and index at %.2f" % seconds)
			if interval.x == INF: continue
			var distance := maxf(interval.x - point.y, point.y - interval.y)
			_check(distance >= -0.0015 and distance < 0.002, "pad %d stays within 2 mm of the food at %.2f; distance %.6f" % [vertex_index, seconds, distance])
		# Check every supplied hand vertex that could be inside the food volume;
		# this catches the relaxed fingers entering the strip between the bites.
		for vertex_index in vertices.size():
			var point := motion.food.to_local(_skin_point(motion.right_arm, vertex_index))
			if not food_bounds.has_point(point): continue
			var interval := _vertical_interval(food_arrays, point)
			if interval.x == INF: continue
			var penetration := minf(point.y - interval.x, interval.y - point.y)
			_check(penetration <= 0.0015, "hand vertex %d penetrates the food by %.6f at %.2f" % [vertex_index, penetration, seconds])
	motion.clear()
	holder.free()
	for failure in failures: push_error(failure)
	print("JERKY GRIP TEST %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _skin_point(arm: Node3D, vertex_index: int) -> Vector3:
	var visual: Node3D = arm._active_visual
	var rig: Skeleton3D = visual.skeleton
	var part: MeshInstance3D = visual.hand_meshes[0]
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var point := Vector3.ZERO
	for j in 4:
		var k := vertex_index * 4 + j
		var binding := bones[k]
		var bone := part.skin.get_bind_bone(binding)
		if bone < 0: bone = rig.find_bone(part.skin.get_bind_name(binding))
		point += (rig.get_bone_global_pose(bone) * part.skin.get_bind_pose(binding) * vertices[vertex_index]) * weights[k]
	return rig.to_global(point)

func _vertical_interval(arrays: Array, point: Vector3) -> Vector2:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var result := Vector2(INF, -INF)
	for i in range(0, count, 3):
		var a := vertices[indices[i] if not indices.is_empty() else i]
		var b := vertices[indices[i + 1] if not indices.is_empty() else i + 1]
		var c := vertices[indices[i + 2] if not indices.is_empty() else i + 2]
		# Barycentric intersection in XZ avoids the general ray helper's
		# fixed epsilon rejecting the source's millimetre-sized triangles.
		var u := Vector2(b.x - a.x, b.z - a.z)
		var v := Vector2(c.x - a.x, c.z - a.z)
		var r := Vector2(point.x - a.x, point.z - a.z)
		var determinant := u.cross(v)
		if absf(determinant) < 0.000000000001: continue
		var weight_b := r.cross(v) / determinant
		var weight_c := u.cross(r) / determinant
		if weight_b < 0.0 or weight_c < 0.0 or weight_b + weight_c > 1.0: continue
		var y := a.y + weight_b * (b.y - a.y) + weight_c * (c.y - a.y)
		result.x = minf(result.x, y)
		result.y = maxf(result.y, y)
	return result
