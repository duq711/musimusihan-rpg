extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const FIDELITY := preload("res://tests/sword_long_grip_test.gd")
var failures: Array[String] = []
var hilt_triangles: Array[Dictionary] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	await process_frame
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.4)
	_check(bool(player.request_primary_weapon().accepted), "actual shield stow must start the two-hand grip")
	player._update_viewmodel(1.1)
	_check(player._shield_stowed and not player.shield_pivot.visible and player._sword_support_progress() == 1.0 and player.sword_support_arm.visible, "actual stow must finish with the support hand on the lower hilt")
	_check(FileAccess.get_sha256(FIDELITY.SOURCE_PATH) == player.SWORD_LONG_GRIP.SOURCE_SHA256, "original sword and hand GLB bytes must remain untouched")
	var samples: Array[Dictionary] = []
	for variant: String in player.SWORD_ATTACK_VARIANTS:
		player.stamina = player.MAX_STAMINA
		_check(bool(player.begin_sword_attack(variant).accepted), "actual two-hand attack must start: " + variant)
		for frame in range(115):
			if frame == 27: player.attack_release_requested = true
			player.advance_combat_state(1.0 / 60.0, false)
			player._update_viewmodel(1.0 / 60.0)
			player._resolve_active_attack()
			if frame % 10 == 0 or frame in [27, 36, 45, 55]:
				samples.append(_contact_snapshot(player, variant, frame))
		_check(player.combat_state == DungeonPlayer.CombatState.READY and player._shield_stowed and player.sword_support_arm.visible, "each real attack must return to the completed two-hand carry state: " + variant)
	var hilt: Array[Dictionary] = []
	for name: String in ["GripLeather", "GripLeather_Extension"]:
		var part := player.sword_visual_root.find_child(name, true, false) as MeshInstance3D
		_check(part != null, "actual sword leather surface must be available: " + name)
		if part == null: continue
		var local := player.weapon_pivot.global_transform.affine_inverse() * part.global_transform
		for surface in range(part.mesh.get_surface_count()):
			var arrays := part.mesh.surface_get_arrays(surface)
			var points: Array = []
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]: points.append(_vec(local * point))
			hilt.append({"name": name, "vertices": points, "triangles": Array(arrays[Mesh.ARRAY_INDEX])})
	_prepare_hilt_triangles(hilt)
	var summary := {}
	for sample: Dictionary in samples:
		for patch: String in sample.patches:
			var xyz: Array = sample.patches[patch]
			var gap := _surface_gap(Vector3(xyz[0], xyz[1], xyz[2]))
			var limit := 0.0062 if patch == "middle" else 0.0020
			if patch == "middle_proximal": limit = 0.0068
			if patch.ends_with("_palm"): limit = 0.024 if patch == "little_palm" else 0.0115
			_check(gap >= -0.001 and gap <= limit, "actual support skin must hug the unchanged hilt: %s %s frame %d gap %.3f mm (limit %.1f)" % [sample.variant, patch, sample.frame, gap * 1000.0, limit * 1000.0])
			var range_value: Dictionary = summary.get(patch, {"minimum_gap_m": INF, "maximum_gap_m": -INF})
			range_value.minimum_gap_m = minf(range_value.minimum_gap_m, gap)
			range_value.maximum_gap_m = maxf(range_value.maximum_gap_m, gap)
			summary[patch] = range_value
	failures.append_array(FIDELITY.audit_source_fidelity(player))
	var corrective: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(player.SWORD_LONG_GRIP.THUMB_CORRECTIVE_PATH))
	_check(corrective.changes.size() == 3437 and int(corrective.source_vertex_count) == 14177, "thumb correction must stay confined to the reviewed original vertex set")
	var right_thumb_points: Array = []
	var glove := player.weapon_arm.find_child("RightHand_Glove", true, false) as MeshInstance3D
	var glove_vertices: PackedVector3Array = glove.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var thumb_penetrations := 0
	var thumb_touching := 0
	var thumb_minimum := INF
	var source_model := player.SWORD_LONG_GRIP.SOURCE.instantiate() as Node3D
	var original_glove := source_model.find_child("RightHand_Glove", true, false) as MeshInstance3D
	var original_arrays := original_glove.mesh.surface_get_arrays(0)
	var original_vertices: PackedVector3Array = original_arrays[Mesh.ARRAY_VERTEX]
	var original_indices: PackedInt32Array = original_arrays[Mesh.ARRAY_INDEX]
	var normalizer := player.SWORD_LONG_GRIP.SOURCE_READY.affine_inverse() * FIDELITY._relative_transform(original_glove, source_model.get_parent())
	var reference_mapping := FIDELITY.authored_thumb_mapping(original_arrays, corrective)
	var maximum_edge_ratio := 0.0
	var maximum_displacement_difference := 0.0
	for edge in range(original_indices.size()):
		var a_index := original_indices[edge]
		var b_index := original_indices[edge - edge % 3 + (edge + 1) % 3]
		var before_a := normalizer * original_vertices[a_index]
		var before_b := normalizer * original_vertices[b_index]
		var before_length := before_a.distance_to(before_b)
		var after_length := glove_vertices[a_index].distance_to(glove_vertices[b_index])
		if before_length > 0.000001: maximum_edge_ratio = maxf(maximum_edge_ratio, after_length / before_length)
		maximum_displacement_difference = maxf(maximum_displacement_difference, (glove_vertices[a_index] - before_a).distance_to(glove_vertices[b_index] - before_b))
	_check(maximum_edge_ratio < 3.0 and maximum_displacement_difference < 0.01, "rendered thumb triangles must remain continuous after import: max edge ratio %.3f adjacent displacement %.3f mm" % [maximum_edge_ratio, maximum_displacement_difference * 1000.0])
	for index in original_vertices.size():
		if not reference_mapping.has(index) or not bool(reference_mapping[index].contact_sample): continue
		var point := glove_vertices[index]
		right_thumb_points.append(_vec(point))
		var gap := _surface_gap(point)
		thumb_minimum = minf(thumb_minimum, gap)
		if gap < -0.001: thumb_penetrations += 1
		if gap >= -0.0005 and gap <= 0.002: thumb_touching += 1
	source_model.free()
	_check(right_thumb_points.size() == 1379 and thumb_penetrations == 0 and thumb_minimum >= -0.0005 and thumb_touching >= 5, "actual rendered thumb must touch the original hilt without deep penetration: samples %d min %.3f mm penetrating %d touching %d" % [right_thumb_points.size(), thumb_minimum * 1000.0, thumb_penetrations, thumb_touching])
	# Optional authoring evidence; standalone regression never depends on an
	# asset-staging directory or writes outside the configured report path.
	var output := OS.get_environment("SWORD_TWO_HAND_CONTACT_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "requested contact report must be writable")
		if file != null:
			file.store_string(JSON.stringify({"samples": samples, "hilt": hilt, "right_thumb_points": right_thumb_points, "summary": summary, "edge_continuity": {"maximum_edge_ratio": maximum_edge_ratio, "maximum_displacement_difference_m": maximum_displacement_difference}}, "\t"))
			file.close()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "two-hand contact validation must preserve expedition and cursor")
	for failure in failures: push_error(failure)
	print("SWORD TWO HAND GRIP %s: %d actual skin-contact samples, scoped thumb/source fidelity and unchanged expedition" % ["PASS" if failures.is_empty() else "FAIL", samples.size()])
	quit(0 if failures.is_empty() else 1)

func _contact_snapshot(player: DungeonPlayer, variant: String, frame: int) -> Dictionary:
	var arm: Node3D = player.sword_support_arm
	var grip: Dictionary = arm.call("get_combat_grip_snapshot")
	var local := player.weapon_pivot.global_transform.affine_inverse() * arm.global_transform
	var patches: Dictionary = {}
	for patch: String in grip.contact_patch_specs:
		patches[patch] = _vec(local * (arm.call("_digit_pad", patch) as Vector3))
	var errors: Dictionary = {}
	for digit: String in grip.contacts: errors[digit] = grip.contacts[digit].error
	return {"variant": variant, "frame": frame, "phase": player.combat_state, "time": player.state_time, "patches": patches, "solver_errors": errors, "tension": grip.tension, "wrist_in_weapon": _vec(local.origin), "orientation": [_vec(local.basis.x), _vec(local.basis.y), _vec(local.basis.z)]}

func _vec(value: Vector3) -> Array[float]: return [value.x, value.y, value.z]

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


func _prepare_hilt_triangles(parts: Array[Dictionary]) -> void:
	for part: Dictionary in parts:
		var vertices: Array[Vector3] = []
		for point: Array in part.vertices: vertices.append(Vector3(point[0], point[1], point[2]))
		var indices: Array = part.triangles
		for index in range(0, indices.size(), 3):
			var a := vertices[int(indices[index])]
			var b := vertices[int(indices[index + 1])]
			var c := vertices[int(indices[index + 2])]
			var normal := (b - a).cross(c - a).normalized()
			var center := (a + b + c) / 3.0
			if normal.dot(Vector3(center.x, 0.0, center.z)) < 0.0: normal = -normal
			hilt_triangles.append({"a": a, "b": b, "c": c, "normal": normal, "minimum_y": minf(a.y, minf(b.y, c.y)), "maximum_y": maxf(a.y, maxf(b.y, c.y))})


func _surface_gap(point: Vector3) -> float:
	var closest := INF
	var signed_gap := INF
	for triangle: Dictionary in hilt_triangles:
		if point.y < float(triangle.minimum_y) - 0.01 or point.y > float(triangle.maximum_y) + 0.01: continue
		var nearest := _nearest_triangle(point, triangle.a, triangle.b, triangle.c)
		var squared := point.distance_squared_to(nearest)
		if squared >= closest: continue
		closest = squared
		signed_gap = sqrt(squared) * (1.0 if (point - nearest).dot(triangle.normal) >= 0.0 else -1.0)
	return signed_gap


func _nearest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
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
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / (d4 - d3 + d5 - d6))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)
