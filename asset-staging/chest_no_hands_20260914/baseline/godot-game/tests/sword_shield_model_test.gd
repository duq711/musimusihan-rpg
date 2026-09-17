extends SceneTree
const SHIELD_PREVIEW := preload("res://tests/sword_shield_preview.gd")
const PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const STATIC_GRIP := preload("res://tests/sword_long_grip_test.gd")
var failures: Array[String] = []
var _surface_cache: Dictionary = {}
var _world_surface_cache: Dictionary = {}
var _thumb_source: Dictionary = {}
var _skin_patch_sources: Dictionary = {}
var _shield_metrics: Array[Dictionary] = []
var _palmar_sources: Dictionary = {}

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var fingerprint := PREVIEW.inventory_fingerprint(original.inventory)
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	await physics_frame
	var player := fixture.player as DungeonPlayer
	if not PREVIEW.configure_pose(fixture, "shield_guard"): failures.append("Cannot equip and guard with actual sword/shield")
	for arm in [player.shield_arm]:
		if not arm.get_meta("continuous_skin", false): failures.append("Production arm must use continuous anatomical skin")
		var rig := arm.get("skeleton") as Skeleton3D
		if rig == null or rig.get_bone_count() != 16: failures.append("Missing real sixteen-bone hand skeleton")
		else:
			# Inspect the actual equipment role and rest anatomy independently of
			# file names/metadata: fingers -Z, dorsal face +Y means right thumb -X.
			var side := 1 if arm == player.weapon_arm else -1
			var thumb := rig.get_bone_global_rest(rig.find_bone("thumb0")).origin
			var index := rig.get_bone_global_rest(rig.find_bone("index0")).origin
			var little := rig.get_bone_global_rest(rig.find_bone("little0")).origin
			if thumb.x * side > -0.01: failures.append("Actual right-hand thumb must lie on -X and left-hand thumb on +X in dorsal wrist space")
			if (index.x - little.x) * side > -0.04: failures.append("The index-to-little knuckle row must have the same real handedness as its thumb")
			for name in ["index0", "middle1", "thumb1"]:
				var bone := rig.find_bone(name)
				if rig.get_bone_pose_rotation(bone).angle_to(rig.get_bone_rest(bone).basis.get_rotation_quaternion()) < 0.0001: failures.append("Real joints did not curl away from their imported rest pose: " + name)
		if arm.get("_forearm") == null or arm.get("_upper_arm") == null: failures.append("Both imported sleeve joints must be fitted, including the right-hand source")
		if arm.get("_cuff") == null: failures.append("The flexible anatomical cuff must be fitted with its real forearm")
		for mesh: MeshInstance3D in arm.get("hand_meshes"):
			if mesh.skin == null or mesh.skin.get_bind_count() != 16: failures.append("Visible continuous hand must really deform with its sixteen-bone skin")
	var top := player.shield_model.find_child("RearGripTop", true, false) as Node3D
	var bottom := player.shield_model.find_child("RearGripBottom", true, false) as Node3D
	var grip_axis := (top.global_position - bottom.global_position).normalized()
	if player.shield_arm.global_basis.x.dot(grip_axis) < 0.99: failures.append("Actual left-hand knuckle row must align with the modeled strap, including its slant")
	failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
	# A valid grip may show its back, edge or palm as the camera/weapon turns.
	# Inspect real knuckles and opposed skin along the physical handle axes;
	# the independent surface checks below verify that pads, not nails, face it.
	_check_anatomical_grip_axis(player.shield_arm, grip_axis, "shield")
	failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
	var cuff_clearance := (player.shield_arm.global_position-player.shield_pivot.global_position).dot(player.shield_pivot.global_basis.z)
	if cuff_clearance < 0.04: failures.append("The anatomical cuff needs real clearance behind the shield board: " + str(cuff_clearance))
	if player.sword_blade == null or player.sword_blade.mesh.get_aabb().size.x > 0.08: failures.append("Visible modeled blade must have reference-like slender proportions")
	if not bool(player.receive_attack(18, player.global_position + Vector3(0,0,-2)).get("blocked", false)): failures.append("Production shield did not block")
	var poses := {}
	for id in SHIELD_PREVIEW.POSES:
		if not SHIELD_PREVIEW.configure_pose(fixture, id): failures.append("Failed actual reference pose " + id)
		_check_anatomical_grip_axis(player.shield_arm, (top.global_position - bottom.global_position).normalized(), "shield/" + id)
		failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
		_check_actual_shield_surface(player, id)
		poses[id] = player.weapon_pivot.transform
		if player.get_first_person_motion_snapshot().visible_arm_count != 2: failures.append("Reference pose left an extra arm visible")
		var forearm := player.shield_arm.get("_forearm") as Node3D
		var elbow := forearm.to_global(Vector3(0,0,0.26))
		if player.camera.to_local(elbow).z > -0.05: failures.append("Shield elbow crossed the camera, exaggerating forearm perspective: " + id)
	if poses.guard.is_equal_approx(poses.impact): failures.append("Actual shield impact must raise the supporting sword")
	SHIELD_PREVIEW.configure_pose(fixture, "idle")
	fixture.sequence_time = 0.0
	fixture.sequence_events = {}
	var phases := {}
	for frame in 52:
		if not SHIELD_PREVIEW.advance_sequence(fixture, 0.05): failures.append("Real guard did not absorb the sequence attack")
		phases[player.combat_state] = true
		var forearm := player.shield_arm.get("_forearm") as Node3D
		if player.camera.to_local(forearm.to_global(Vector3(0,0,0.26))).z > -0.05: failures.append("Continuous shield movement brought the elbow through the camera at frame " + str(frame))
	if fixture.sequence_events.size() != 4 or not phases.has(player.CombatState.ACTIVE) or not phases.has(player.CombatState.RECOVERY): failures.append("Continuous production clock must play guard, impact, attack and recovery")
	if not is_equal_approx(player.health, player.MAX_HEALTH): failures.append("Normal shield guard must prevent all health damage throughout the actual sequence")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	if ExpeditionSession.capture_snapshot() != original or fingerprint != PREVIEW.inventory_fingerprint(original.inventory) or cursor != Input.mouse_mode: failures.append("Model and sequence checks changed the original expedition or cursor")
	for failure in failures: push_error(failure)
	print("SHIELD ACTUAL POWER GRIP ", JSON.stringify(_shield_metrics))
	print("SWORD SHIELD MODEL ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_anatomical_grip_axis(arm: Node3D, toward_guard: Vector3, role: String) -> void:
	var rig := arm.get("skeleton") as Skeleton3D
	if rig == null: return
	var index := rig.to_global(rig.get_bone_global_pose(rig.find_bone("index0")).origin)
	var little := rig.to_global(rig.get_bone_global_pose(rig.find_bone("little0")).origin)
	if (index - little).dot(toward_guard) < 0.04: failures.append("Actual index knuckle must lie nearer the upper handle anchor than the little knuckle: " + role)
	var report: Dictionary = arm.call("get_combat_grip_snapshot")
	var thumb_pad := arm.to_global(report.contacts.thumb.actual)
	var little_pad := arm.to_global(report.contacts.little.actual)
	if (thumb_pad - little_pad).dot(toward_guard) < 0.04: failures.append("The real opposed thumb skin must close on the index/upper-anchor side of the modeled handle: " + role)
	if arm.global_basis.determinant() < 0.99: failures.append("The hand contact must rotate its actual anatomy without reflecting or collapsing its dorsal/palmar frame: " + role)


func _actual_skin_patch(arm: Node3D, digit: String, kind: String) -> Dictionary:
	var rig := arm.get("skeleton") as Skeleton3D
	var part: MeshInstance3D
	for candidate: MeshInstance3D in arm.get("hand_meshes"):
		if str(candidate.name).begins_with("ContinuousAnatomicalHand"): part = candidate
	if rig == null or part == null or part.skin == null: return {}
	var source_key := "%d:%s:%s" % [part.get_instance_id(), digit, kind]
	_thumb_source = _skin_patch_sources.get(source_key, {})
	if _thumb_source.is_empty():
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if normals.size() != vertices.size(): return {}
		var stride := joints.size() / vertices.size()
		var bones: Array[int] = []
		var binds: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = rig.find_bone(str(part.skin.get_bind_name(bind)))
			bones.append(bone)
			binds.append(part.skin.get_bind_pose(bind))
		var distal := rig.find_bone(digit + "2")
		var lengths := {"little": 0.0176, "ring": 0.02104, "middle": 0.022, "index": 0.02024, "thumb": 0.025}
		var weighted_bone := distal
		var rest_pad := rig.get_bone_global_rest(distal) * Vector3(0, float(lengths[digit]) * 0.82, -0.006)
		if kind == "middle":
			weighted_bone = rig.find_bone(digit + "1")
			rest_pad = rig.get_bone_global_rest(weighted_bone) * Vector3(0, rig.get_bone_rest(distal).origin.length() * 0.55, -0.007)
		elif kind == "proximal":
			weighted_bone = rig.find_bone(digit + "0")
			var middle := rig.find_bone(digit + "1")
			rest_pad = rig.get_bone_global_rest(weighted_bone) * Vector3(0, rig.get_bone_rest(middle).origin.length() * 0.85, -0.007)
		elif kind == "palm":
			weighted_bone = rig.find_bone("wrist")
			var mcp := rig.get_bone_global_rest(rig.find_bone(digit + "0")).origin
			rest_pad = Vector3(mcp.x, -0.016, mcp.z + 0.018)
		var candidates: Array[Dictionary] = []
		for vertex in vertices.size():
			if kind == "palm" and normals[vertex].y > -0.3: continue
			var influence := 0.0
			for slot in stride:
				var entry := vertex * stride + slot
				if bones[joints[entry]] == weighted_bone: influence += weights[entry]
			if influence > 0.55: candidates.append({"index": vertex, "distance": vertices[vertex].distance_squared_to(rest_pad)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
		if candidates.size() < 20: return {}
		var indices: Array[int] = []
		for index in 20: indices.append(int(candidates[index].index))
		_thumb_source = {"vertices": vertices, "normals": normals, "joints": joints, "weights": weights, "stride": stride, "bones": bones, "binds": binds, "indices": indices}
		_skin_patch_sources[source_key] = _thumb_source
	var matrices: Array[Transform3D] = []
	for bind in _thumb_source.binds.size(): matrices.append(rig.get_bone_global_pose(_thumb_source.bones[bind]) * (_thumb_source.binds[bind] as Transform3D))
	var points: Array[Vector3] = []
	var mean := Vector3.ZERO
	var normal := Vector3.ZERO
	for vertex: int in _thumb_source.indices:
		var position := Vector3.ZERO
		var direction := Vector3.ZERO
		for slot in int(_thumb_source.stride):
			var entry := vertex * int(_thumb_source.stride) + slot
			var weight := float(_thumb_source.weights[entry])
			if weight <= 0.0: continue
			var transform := matrices[_thumb_source.joints[entry]]
			position += transform * (_thumb_source.vertices[vertex] as Vector3) * weight
			direction += transform.basis.inverse().transposed() * (_thumb_source.normals[vertex] as Vector3) * weight
		var world_point := part.to_global(position)
		points.append(world_point)
		mean += world_point
		normal += (part.global_basis.inverse().transposed() * direction).normalized()
	mean /= points.size()
	var report: Dictionary = arm.call("get_combat_grip_snapshot")
	var expected: Vector3 = report.contacts[digit].proximal_actual if kind == "proximal" else report.contacts[digit].actual if kind == "middle" else report.contacts[digit].palm_actual if kind == "palm" else report.contacts[digit].distal_actual
	if mean.distance_to(arm.to_global(expected)) > 0.00002: failures.append("Independent model-level skinning must agree with the real %s/%s contact report in world space" % [digit, kind])
	return {"points": points, "mean": mean, "normal": normal.normalized()}


func _check_actual_shield_surface(player: DungeonPlayer, pose_id: String) -> void:
	var arm := player.shield_arm as Node3D
	var mesh := player.shield_model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	if mesh == null:
		failures.append("Shield contact needs the actual imported merged model")
		return
	var measurements := {"pose": pose_id, "contacts": {}}
	for digit: String in ["little", "ring", "middle", "index", "thumb"]:
		# All five real shortened distal pads now contact the padded loop.
		var pad := _actual_skin_patch(arm, digit, "distal")
		if pad.is_empty():
			failures.append("Missing independently weighted shield load-bearing surface patch: " + digit)
			continue
		var surface := _closest_shield_grip_surface(mesh, pad.mean)
		var deepest := 0.0
		for point: Vector3 in pad.points: deepest = minf(deepest, float(_closest_shield_grip_surface(mesh, point).signed_distance))
		var facing := (pad.normal as Vector3).dot(-(surface.normal as Vector3))
		measurements.contacts[digit] = {"gap_mm": float(surface.distance) * 1000.0, "mean_signed_mm": float(surface.signed_distance) * 1000.0, "deepest_mm": deepest * 1000.0, "pad_facing": facing}
		var context := pose_id + "/" + digit
		if float(surface.distance) > 0.004: failures.append("Actual shield load-bearing surface floats over 4mm from the real curved loop: " + context)
		if float(surface.signed_distance) < -0.0005: failures.append("Actual shield contact mean penetrates the real leather loop by over 0.5mm: " + context)
		if deepest < -0.001: failures.append("Actual shield skin sample penetrates the real leather loop by over 1mm: " + context)
		if facing < 0.4: failures.append("Actual load-bearing skin face must oppose its closest real strap face: " + context)
	var palmar_triangles := _actual_palmar_triangles(arm)
	for digit: String in ["little", "ring", "middle", "index"]:
		var distal := _actual_skin_patch(arm, digit, "distal")
		var palm := _actual_skin_patch(arm, digit, "palm")
		if distal.is_empty() or palm.is_empty():
			failures.append("Shield closure needs real distal and palmar skin: " + digit)
			continue
		var nearest_palm := _closest_triangle_surface(palmar_triangles, distal.mean)
		var gap := float(nearest_palm.distance)
		var deepest := float(nearest_palm.signed_distance)
		for point: Vector3 in distal.points: deepest = minf(deepest, float(_closest_triangle_surface(palmar_triangles, point).signed_distance))
		if gap > 0.035: failures.append("Shield distal joint must close within 35mm of its actual deformed palmar surface, not a fixed patch center: " + pose_id + "/" + digit)
		if deepest < -0.001: failures.append("Closed shield fingertip samples must stay outside the actual deformed palmar skin: " + pose_id + "/" + digit)
		measurements.contacts[digit]["nearest_palm_gap_mm"] = gap * 1000.0
		measurements.contacts[digit]["nearest_palm_signed_mm"] = deepest * 1000.0
		measurements.contacts[digit]["fixed_palm_center_gap_mm"] = (distal.mean as Vector3).distance_to(palm.mean) * 1000.0
	_shield_metrics.append(measurements)


func _closest_shield_grip_surface(mesh: MeshInstance3D, point: Vector3) -> Dictionary:
	# The two side arcs of the padded closed ellipse use the preserved bound-edge
	# material. Ignoring those triangles would measure an incomplete hand grip.
	var leather := _closest_surface(mesh, point, "FP_ShieldEnarmes")
	var edge := _closest_surface(mesh, point, "FP_ShieldLeatherEdge")
	return edge if float(edge.distance) < float(leather.distance) else leather


func _actual_palmar_triangles(arm: Node3D) -> Array[Dictionary]:
	# A particular MCP's twenty-point palm center is not the nearest surface
	# when a fingertip curls over another part of the palm. Keep the same
	# physical 35mm closure limit, measured against actual posed triangles.
	var rig := arm.get("skeleton") as Skeleton3D
	var part: MeshInstance3D
	for candidate: MeshInstance3D in arm.get("hand_meshes"):
		if str(candidate.name).begins_with("ContinuousAnatomicalHand"): part = candidate
	if rig == null or part == null or part.skin == null: return []
	var key := part.get_instance_id()
	if not _palmar_sources.has(key):
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var stride: int = joints.size() / vertices.size()
		var bones: Array[int] = []
		var binds: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = rig.find_bone(str(part.skin.get_bind_name(bind)))
			bones.append(bone)
			binds.append(part.skin.get_bind_pose(bind))
		var wrist := rig.find_bone("wrist")
		var eligible: Dictionary = {}
		for vertex in vertices.size():
			if normals[vertex].y > -0.3: continue
			var weight := 0.0
			for slot in stride:
				var entry: int = vertex * stride + slot
				if bones[joints[entry]] == wrist: weight += weights[entry]
			if weight > 0.55: eligible[vertex] = true
		var triangles: Array[Vector3i] = []
		for offset in range(0, indices.size() - 2, 3):
			var ia := indices[offset]
			var ib := indices[offset + 1]
			var ic := indices[offset + 2]
			if eligible.has(ia) and eligible.has(ib) and eligible.has(ic): triangles.append(Vector3i(ia, ib, ic))
		if triangles.size() < 20: failures.append("Actual palm surface needs independently selected wrist-weighted palmar triangles")
		_palmar_sources[key] = {"vertices": vertices, "normals": normals, "joints": joints, "weights": weights, "stride": stride, "bones": bones, "binds": binds, "triangles": triangles}
	var source: Dictionary = _palmar_sources[key]
	var matrices: Array[Transform3D] = []
	for bind in source.binds.size(): matrices.append(rig.get_bone_global_pose(source.bones[bind]) * (source.binds[bind] as Transform3D))
	var posed: Dictionary = {}
	var posed_normals: Dictionary = {}
	var triangles: Array[Dictionary] = []
	for triangle: Vector3i in source.triangles:
		for vertex in [triangle.x, triangle.y, triangle.z]:
			if posed.has(vertex): continue
			var position := Vector3.ZERO
			var normal := Vector3.ZERO
			for slot in int(source.stride):
				var entry: int = vertex * int(source.stride) + slot
				var weight := float(source.weights[entry])
				if weight <= 0.0: continue
				var transform: Transform3D = matrices[source.joints[entry]]
				position += transform * (source.vertices[vertex] as Vector3) * weight
				normal += transform.basis.inverse().transposed() * (source.normals[vertex] as Vector3) * weight
			posed[vertex] = part.to_global(position)
			posed_normals[vertex] = (part.global_basis.inverse().transposed() * normal).normalized()
		var a: Vector3 = posed[triangle.x]
		var b: Vector3 = posed[triangle.y]
		var c: Vector3 = posed[triangle.z]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 0.000000000001: continue
		normal = normal.normalized()
		if normal.dot(posed_normals[triangle.x] + posed_normals[triangle.y] + posed_normals[triangle.z]) < 0.0: normal = -normal
		triangles.append({"a": a, "b": b, "c": c, "normal": normal, "bounds": AABB(a, Vector3.ZERO).expand(b).expand(c)})
	return triangles


func _closest_triangle_surface(triangles: Array[Dictionary], point: Vector3) -> Dictionary:
	var best := INF
	var closest := Vector3.ZERO
	var outward := Vector3.ZERO
	for triangle: Dictionary in triangles:
		var bounds: AABB = triangle.bounds
		if point.distance_squared_to(point.clamp(bounds.position, bounds.end)) > best: continue
		var candidate := _closest_triangle(point, triangle.a, triangle.b, triangle.c)
		var squared := point.distance_squared_to(candidate)
		if squared < best:
			best = squared
			closest = candidate
			outward = triangle.normal
	return {"distance": sqrt(best), "signed_distance": (point - closest).dot(outward), "normal": outward}


func _closest_surface(part: MeshInstance3D, world_point: Vector3, material_name: String = "") -> Dictionary:
	var mesh := part.mesh as ArrayMesh
	if mesh == null: return {"distance": INF, "signed_distance": -INF, "normal": Vector3.ZERO}
	var key := "%d:%s" % [mesh.get_instance_id(), material_name]
	if not _surface_cache.has(key):
		var triangles: Array[Dictionary] = []
		for surface in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			if not material_name.is_empty():
				var material := mesh.surface_get_material(surface)
				if material == null or material.resource_name != material_name: continue
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count - 2, 3):
				var ia := indices[offset] if not indices.is_empty() else offset
				var ib := indices[offset + 1] if not indices.is_empty() else offset + 1
				var ic := indices[offset + 2] if not indices.is_empty() else offset + 2
				var a := vertices[ia]
				var b := vertices[ib]
				var c := vertices[ic]
				var normal := (b - a).cross(c - a)
				if normal.length_squared() < 0.000000000001: continue
				normal = normal.normalized()
				# Use the imported rendered normals to resolve winding, including
				# any reflected geometry. Never infer outside from a node name.
				if normals.size() == vertices.size() and normal.dot(normals[ia] + normals[ib] + normals[ic]) < 0.0: normal = -normal
				triangles.append({"a": a, "b": b, "c": c, "normal": normal, "bounds": AABB(a, Vector3.ZERO).expand(b).expand(c)})
		_surface_cache[key] = triangles
	# The shortened grip carries a real nonuniform node scale. A closest point
	# computed in unscaled mesh space is not a world-space closest point.
	# Cache transformed real triangles once per pose, then reuse for all pads.
	if not _world_surface_cache.has(key) or _world_surface_cache[key].transform != part.global_transform:
		var transformed: Array[Dictionary] = []
		var normal_matrix := part.global_basis.inverse().transposed()
		for triangle: Dictionary in _surface_cache[key]:
			var a := part.to_global(triangle.a)
			var b := part.to_global(triangle.b)
			var c := part.to_global(triangle.c)
			transformed.append({"a": a, "b": b, "c": c, "normal": (normal_matrix * (triangle.normal as Vector3)).normalized(), "bounds": AABB(a, Vector3.ZERO).expand(b).expand(c)})
		_world_surface_cache[key] = {"transform": part.global_transform, "triangles": transformed}
	var point := world_point
	var best := INF
	var closest := Vector3.ZERO
	var outward := Vector3.ZERO
	for triangle: Dictionary in _world_surface_cache[key].triangles:
		var bounds: AABB = triangle.bounds
		var bounded := point.clamp(bounds.position, bounds.end)
		if point.distance_squared_to(bounded) > best: continue
		var candidate := _closest_triangle(point, triangle.a, triangle.b, triangle.c)
		var squared := point.distance_squared_to(candidate)
		if squared < best:
			best = squared
			closest = candidate
			outward = triangle.normal
	return {"distance": world_point.distance_to(closest) if is_finite(best) else INF, "signed_distance": (world_point - closest).dot(outward), "normal": outward}


func _closest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Voronoi-region closest point on a real triangle, including its edges.
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)
