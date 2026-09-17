extends SceneTree
## Actual Windows asset comparison only. No synthetic skin or motion fixture.
## Provide CONTINUOUS_SLEEVE_GLB and CONTINUOUS_SLEEVE_SAMPLES after receipt.

const ADAPTER := preload("res://scripts/reference_continuous_sleeve.gd")
const LONG_GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const TOLERANCE := 0.00003
var failures: Array[String] = []
var max_bone_error := 0.0
var max_vertex_error := 0.0
var compared_vertices := 0
var compared_keys := 0
var actual_delivery_checked := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var asset_path := OS.get_environment("CONTINUOUS_SLEEVE_GLB").strip_edges()
	var samples_path := OS.get_environment("CONTINUOUS_SLEEVE_SAMPLES").strip_edges()
	if asset_path.is_empty() and samples_path.is_empty():
		print("REFERENCE CONTINUOUS SLEEVE SKIP: actual_delivery_checked=false; received GLB and arm_pose_samples.json paths are required")
		quit(0)
		return
	if asset_path.is_empty() or samples_path.is_empty() or not FileAccess.file_exists(asset_path) or not FileAccess.file_exists(samples_path):
		_check(false, "Both explicit actual-delivery paths must exist.")
		_finish()
		return
	var original_hash := FileAccess.get_sha256(asset_path)
	var samples_hash := FileAccess.get_sha256(samples_path)
	_check(original_hash == ADAPTER.SOURCE_SHA256, "Test must compare the exact final iteration_07 GLB.")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(samples_path))
	if not parsed is Dictionary or not parsed.get("frames") is Array or parsed.frames.size() != 187:
		_check(false, "Actual Windows delivery requires the 187 evaluated 120 Hz overhead samples.")
		_finish()
		return
	var frames: Array = parsed.frames
	var packed := load(asset_path) as PackedScene
	if packed == null:
		_check(false, "Received GLB must be imported as a PackedScene before its playback test.")
		_finish()
		return
	var world := Node3D.new()
	root.add_child(world)
	var native := packed.instantiate() as Node3D
	world.add_child(native)
	native.process_mode = Node.PROCESS_MODE_DISABLED
	var source_rigs: Array[Skeleton3D] = []
	var source_meshes: Array[MeshInstance3D] = []
	ADAPTER._collect(native, source_rigs, source_meshes)
	var players: Array[AnimationPlayer] = []
	_find_players(native, players)
	var adapter := ADAPTER.new()
	world.add_child(adapter)
	var configured: Dictionary = adapter.setup(packed)
	_check(bool(configured.ok), "Actual sleeve adapter must configure: " + str(configured.error))
	if not bool(configured.ok) or source_rigs.size() != 1 or players.size() != 1:
		_check(source_rigs.size() == 1 and players.size() == 1, "Native comparison requires the actual single Skeleton/AnimationPlayer.")
		world.free()
		_finish()
		return
	var rig := source_rigs[0]
	var animation := _native_animation(players[0])
	if animation.is_empty():
		world.free()
		_finish()
		return
	var player := players[0]
	player.play(animation)
	actual_delivery_checked = true
	var skins: Dictionary = {}
	for part: MeshInstance3D in source_meshes:
		if str(part.name) in ADAPTER.MESH_NAMES:
			skins[str(part.name)] = _read_skin(part, rig)
	_check(skins.size() == 3, "All three actual weighted sleeve meshes must be compared.")
	# Native keys provide the oracle. Compare all seven transforms at all 187
	# source times; compare every skin vertex at selected actual extreme keys.
	var vertex_keys := _vertex_keys(frames)
	for index in frames.size():
		var row: Dictionary = frames[index]
		var time := float(row.get("time_seconds", -1))
		_check(is_equal_approx(time, float(index) / 120.0), "Actual sample times must remain 120 Hz source seconds.")
		player.seek(time, true)
		var sword := _pose(row.sword)
		var joints: Dictionary = row.right_arm
		var inverse := sword.affine_inverse()
		var elbow := inverse * _vector(joints.elbow)
		var shoulder := inverse * _vector(joints.shoulder)
		var forearm := LONG_GRIP._fit_segment(LONG_GRIP.REST_WRIST, LONG_GRIP.REST_ELBOW, LONG_GRIP.REST_WRIST, elbow)
		var upper := LONG_GRIP._fit_segment(LONG_GRIP.REST_ELBOW, LONG_GRIP.REST_SHOULDER, elbow, shoulder)
		adapter.transform = sword
		_check(adapter.apply_segments(forearm, upper, LONG_GRIP.REST_WRIST, elbow), "Actual key must update all sleeve surfaces.")
		for bone_name: String in ADAPTER.BONE_NAMES:
			var expected := rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone_name))
			var actual := adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(adapter.skeleton.find_bone(bone_name))
			var error := _matrix_error(expected, actual)
			max_bone_error = maxf(max_bone_error, error)
			if error > TOLERANCE:
				_check(false, "Native bone mismatch at exact key %d / %s: %.9f" % [index, bone_name, error])
		compared_keys += 1
		if index in vertex_keys:
			for mesh_name: String in skins:
				_compare_skin(skins[mesh_name], rig, adapter.skeleton, index, mesh_name)
	_check(compared_vertices > 0, "Native comparison must evaluate real weighted mesh vertices.")
	_check(adapter.get_children().size() == 1 and adapter.skeleton.get_children().size() == 3, "Runtime adapter must contain only one Skeleton and three skins, with no duplicate sword, glove, shield, or animator.")
	world.free()
	await process_frame
	_check(FileAccess.get_sha256(asset_path) == original_hash and FileAccess.get_sha256(samples_path) == samples_hash, "Native comparison must preserve received GLB and motion bytes.")
	_finish()


func _native_animation(player: AnimationPlayer) -> StringName:
	var candidates: Array[StringName] = []
	for name: StringName in player.get_animation_list():
		if str(name) == "RESET": continue
		var animation := player.get_animation(name)
		var has_sleeve := false
		for track in animation.get_track_count():
			if "SleeveForearm" in str(animation.track_get_path(track)): has_sleeve = true
		if has_sleeve and absf(animation.length - 1.55) < 0.00001: candidates.append(name)
	_check(candidates.size() == 1, "Exactly one real 1.55-second sleeve animation must exist for native comparison.")
	return candidates[0] if candidates.size() == 1 else &""


func _read_skin(part: MeshInstance3D, rig: Skeleton3D) -> Dictionary:
	var binds: Array[Transform3D] = []
	var bone_names: Array[String] = []
	for bind in part.skin.get_bind_count():
		var bone := part.skin.get_bind_bone(bind)
		if bone < 0: bone = rig.find_bone(str(part.skin.get_bind_name(bind)))
		_check(bone >= 0, "Every actual skin bind must resolve to a native bone.")
		binds.append(part.skin.get_bind_pose(bind))
		bone_names.append(rig.get_bone_name(bone))
	var surfaces: Array[Dictionary] = []
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		_check(not vertices.is_empty() and joints.size() == weights.size() and joints.size() % vertices.size() == 0, "Real skin surface arrays must contain complete weights.")
		surfaces.append({"vertices": vertices, "joints": joints, "weights": weights, "stride": joints.size() / vertices.size()})
	return {"binds": binds, "bone_names": bone_names, "surfaces": surfaces}


func _compare_skin(source: Dictionary, native: Skeleton3D, adapted: Skeleton3D, key: int, mesh_name: String) -> void:
	var native_matrices: Array[Transform3D] = []
	var adapter_matrices: Array[Transform3D] = []
	for bind in source.binds.size():
		var bone_name: String = source.bone_names[bind]
		native_matrices.append(native.global_transform * native.get_bone_global_pose(native.find_bone(bone_name)) * (source.binds[bind] as Transform3D))
		adapter_matrices.append(adapted.global_transform * adapted.get_bone_global_pose(adapted.find_bone(bone_name)) * (source.binds[bind] as Transform3D))
	var worst := 0.0
	for surface: Dictionary in source.surfaces:
		for vertex in surface.vertices.size():
			var expected := Vector3.ZERO
			var actual := Vector3.ZERO
			var weight_sum := 0.0
			for slot in int(surface.stride):
				var address: int = vertex * int(surface.stride) + slot
				var weight := float(surface.weights[address])
				if weight <= 0.0: continue
				var bind := int(surface.joints[address])
				weight_sum += weight
				expected += (native_matrices[bind] * (surface.vertices[vertex] as Vector3)) * weight
				actual += (adapter_matrices[bind] * (surface.vertices[vertex] as Vector3)) * weight
			_check(absf(weight_sum - 1.0) < 0.0001, "Actual skin weights must sum to one.")
			worst = maxf(worst, actual.distance_to(expected))
			compared_vertices += 1
	max_vertex_error = maxf(max_vertex_error, worst)
	_check(worst < TOLERANCE, "Actual native skin mismatch at key %d / %s: %.9fm" % [key, mesh_name, worst])


func _vertex_keys(frames: Array) -> Array[int]:
	var keys: Array[int] = [0, 37, 74, 84, 111, 148, 186]
	var minimum_cosine := 2.0
	var extreme := 0
	for index in frames.size():
		var arm: Dictionary = frames[index].right_arm
		var elbow := _vector(arm.elbow)
		var cosine := (elbow - _vector(arm.wrist)).normalized().dot((_vector(arm.shoulder) - elbow).normalized())
		if cosine < minimum_cosine:
			minimum_cosine = cosine
			extreme = index
	if not extreme in keys: keys.append(extreme)
	return keys


func _finish() -> void:
	for failure in failures: push_error(failure)
	print("REFERENCE CONTINUOUS SLEEVE %s: actual_delivery_checked=%s; source_keys=%d; real_skin_vertices=%d; max_bone_error=%.9f; max_vertex_error_m=%.9f" % ["PASS" if failures.is_empty() else "FAIL", str(actual_delivery_checked), compared_keys, compared_vertices, max_bone_error, max_vertex_error])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


static func _pose(value: Dictionary) -> Transform3D:
	var rotation: Array = value.rotation_xyzw
	return Transform3D(Basis(Quaternion(rotation[0], rotation[1], rotation[2], rotation[3])), _vector(value.position))


static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _matrix_error(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))


static func _find_players(node: Node, players: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer: players.append(node as AnimationPlayer)
	for child in node.get_children(): _find_players(child, players)
