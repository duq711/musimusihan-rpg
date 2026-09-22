extends SceneTree
## Hood removal plus the exposed anatomical neckline and continuous shoulder joins.
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := APPEARANCE.create_body()
	root.add_child(body)
	for retired: String in ["Gravebound_PointHood", "Gravebound_InnerNeckCowl", "Gravebound_Mantle_L", "Gravebound_Mantle_R", "Gravebound_MantleBack"]:
		if body.find_child(retired, true, false) != null:
			failures.append("Removed hood or neck cloth remains in the imported model: " + retired)
	# Absence checks must not pass on an empty or incomplete import.
	for retained: String in ["Gravebound_AnatomicalHead", "Gravebound_Eyes", "Gravebound_QuiltedTorso", "Gravebound_FP_L_Arm", "Gravebound_FP_R_Arm", "Gravebound_FP_L_Hand", "Gravebound_FP_R_Hand"]:
		var part := body.find_child(retained, true, false) as MeshInstance3D
		if part == null or part.mesh == null or part.mesh.get_surface_count() == 0:
			failures.append("Removing neck cloth must preserve the actual head, torso and limbs: " + retained)
	_check_neck_and_shoulders(body)
	body.free()
	for failure in failures:
		push_error(failure)
	print("PLAYER COWL REMOVAL " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check_neck_and_shoulders(body: Node3D) -> void:
	var torso := body.find_child("Gravebound_QuiltedTorso", true, false) as MeshInstance3D
	if torso == null or torso.mesh == null:
		return # The retained-part checks above report incomplete imports.
	var torso_seam := _shoulder_seam(body, torso)
	var high_neck_vertices := 0
	var covered_neck_samples := {}
	# Probe the neck interior in the body's frame. A broad closed torso cap
	# used to intersect the neck here even though the removed cowl was absent.
	var neck_samples: Array[Vector3] = [Vector3(0, 1.55, 0)]
	for step in 8:
		var angle := TAU * float(step) / 8.0
		neck_samples.append(Vector3(cos(angle) * .035, 1.55, sin(angle) * .035))
	for surface in torso.mesh.get_surface_count():
		var arrays := torso.mesh.surface_get_arrays(surface)
		var local_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var points := PackedVector3Array()
		for vertex in local_vertices:
			var point := body.to_local(torso.to_global(vertex))
			points.append(point)
			if point.y > 1.470:
				high_neck_vertices += 1
				if absf(point.x) > .091 or absf(point.z) > .080:
					failures.append("Upper neckline is wider than the fitted human neck")
					return
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else points.size()
		for offset in range(0, count, 3):
			var a := points[indices[offset] if not indices.is_empty() else offset]
			var b := points[indices[offset + 1] if not indices.is_empty() else offset + 1]
			var c := points[indices[offset + 2] if not indices.is_empty() else offset + 2]
			if maxf(a.y, maxf(b.y, c.y)) < 1.445:
				continue
			for sample in neck_samples.size():
				var hit: Variant = Geometry3D.ray_intersects_triangle(neck_samples[sample], Vector3.DOWN, a, b, c)
				if hit != null and hit.y > 1.445:
					covered_neck_samples[sample] = true
	if high_neck_vertices == 0:
		failures.append("The fitted neckline must exist; deleting the upper chest is not a repair")
	if not covered_neck_samples.is_empty():
		failures.append("The upper torso must have a real neck opening rather than a cap through the neck")
	for side: String in ["L", "R"]:
		var sleeve := body.find_child("Gravebound_FP_" + side + "_Arm", true, false) as MeshInstance3D
		if sleeve == null or sleeve.mesh == null:
			continue
		var sleeve_seam := _shoulder_seam(body, sleeve)
		var shared := 0
		var smooth := true
		var first := true
		var join_bounds := AABB()
		for key in sleeve_seam:
			if not torso_seam.has(key):
				continue
			shared += 1
			var point: Vector3 = sleeve_seam[key][0]
			if first:
				join_bounds = AABB(point, Vector3.ZERO)
				first = false
			else:
				join_bounds = join_bounds.expand(point)
			var sleeve_normal: Vector3 = sleeve_seam[key][1]
			var torso_normal: Vector3 = torso_seam[key][1]
			smooth = smooth and sleeve_normal.dot(torso_normal) > .985
		if shared < 20 or join_bounds.size.y < .075 or join_bounds.size.z < .10:
			failures.append("Shoulder must join the chest across its front and back, not end in a separate capped sleeve: " + side)
		if not smooth:
			failures.append("Shoulder and chest normals must meet smoothly without a stump-shaped shading seam: " + side)


func _shoulder_seam(body: Node3D, part: MeshInstance3D) -> Dictionary:
	var result := {}
	var normal_basis := body.global_basis.inverse() * part.global_basis
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in vertices.size():
			var point := body.to_local(part.to_global(vertices[index]))
			if point.y < 1.30 or absf(point.x) < .10:
				continue
			# Match the actual shared seam even when shoulder breadth changes.
			# UV or material splits must not hide a real gap.
			var key := Vector3i(roundi(point.x * 1000000), roundi(point.y * 1000000), roundi(point.z * 1000000))
			result[key] = [point, (normal_basis * normals[index]).normalized()]
	return result
