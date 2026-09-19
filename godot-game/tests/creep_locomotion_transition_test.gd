extends SceneTree
## Inspect the actual production rig against independently sampled source clips.
const CREEP := preload("res://scripts/creep_enemy.gd")
const STEP := 1.0 / 60.0

var failures: Array[String] = []
var report: Array[Dictionary] = []
var stage: Node3D
var actor
var reference


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not CREEP.is_available():
		print("CREEP LOCOMOTION TRANSITION TEST PASS: licensed Creep absent; actual rig checks SKIPPED")
		quit()
		return
	var cursor := Input.mouse_mode
	var original_session := ExpeditionSession.capture_snapshot()
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	stage = Node3D.new()
	root.add_child(stage)
	_add_floor()
	reference = _new_actor(Vector3(4.0, 0.9, 0.0))
	for attack_index in range(2):
		actor = _new_actor(Vector3(0.0, 0.9, 0.0))
		await physics_frame
		_test_recovery_to_walk(attack_index)
		_test_speed_clock(attack_index)
		_test_walk_to_windup(attack_index)
		actor.queue_free()
		await process_frame
	for interruption: String in ["stagger", "execution", "death"]:
		actor = _new_actor(Vector3(0.0, 0.9, 0.0))
		await physics_frame
		_test_interruption(interruption)
		actor.queue_free()
		await process_frame
	stage.queue_free()
	await process_frame
	_check(Input.mouse_mode == cursor, "rig-only validation must preserve the desktop cursor")
	_check(ExpeditionSession.capture_snapshot() == original_session, "rig-only validation must not mutate the expedition")
	_check(FileAccess.get_sha256(CREEP.MODEL_PATH) == source_hash, "source animation/model bytes must remain unchanged")
	for failure in failures: push_error("CREEP LOCOMOTION TRANSITION: " + failure)
	print("CREEP LOCOMOTION TRANSITION REPORT: ", JSON.stringify(report))
	print("CREEP LOCOMOTION TRANSITION TEST %s: actual bite/punch recovery continuity, per-bone frame steps, source-walk convergence, velocity clock and hit/execution/ragdoll ownership" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = DungeonEnemy.WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 0.2, 16.0)
	collision.shape = box
	body.add_child(collision)
	body.position.y = -0.1
	stage.add_child(body)


func _new_actor(position: Vector3):
	var result = CREEP.new()
	result.position = position
	result.move_speed = 2.2
	stage.add_child(result)
	result.set_physics_process(false)
	return result


func _transition() -> Dictionary:
	return actor.get_creep_snapshot().get("locomotion_transition", {})


func _poses(skeleton: Skeleton3D, global_bones: bool = false) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		result.append(skeleton.get_bone_global_pose(bone) if global_bones else skeleton.get_bone_pose(bone))
	return result


func _source_pose(clip: String, sample: float) -> Array[Transform3D]:
	# This second rig bypasses the transition helper. Its AnimationPlayer
	# evaluates the original animation tracks at the reported playback time.
	var player: AnimationPlayer = reference.animation_player
	var animation := player.get_animation(clip)
	player.play(clip)
	player.seek(fposmod(sample, animation.length) if clip in ["walk", "idle"] else minf(sample, animation.length), true)
	return _poses(reference.skeleton)


func _assert_pose_matches(expected: Array[Transform3D], message: String, position_tolerance: float = 0.00005, angle_tolerance: float = 0.001) -> void:
	var skeleton: Skeleton3D = actor.skeleton
	_check(expected.size() == skeleton.get_bone_count(), message + ": bone count")
	for bone in mini(expected.size(), skeleton.get_bone_count()):
		var actual := skeleton.get_bone_pose(bone)
		# angle_to can report a small acos rounding error even for identical
		# float matrices. Preserve the existing tolerances for changed poses.
		if actual.is_finite() and actual.is_equal_approx(expected[bone]):
			continue
		var positional := actual.origin.distance_to(expected[bone].origin)
		var angular := actual.basis.get_rotation_quaternion().angle_to(expected[bone].basis.get_rotation_quaternion())
		var scaled := actual.basis.get_scale().distance_to(expected[bone].basis.get_scale())
		if positional > position_tolerance or angular > angle_tolerance or scaled > 0.0001 or not actual.is_finite():
			_check(false, "%s: %s position %.6fm rotation %.4fdeg scale %.6f" % [message, skeleton.get_bone_name(bone), positional, rad_to_deg(angular), scaled])
			return


func _finish_attack(attack_index: int) -> Array[Transform3D]:
	actor.attack_index = attack_index - 1
	actor._set_state(DungeonEnemy.AIState.WINDUP)
	actor._set_state(DungeonEnemy.AIState.ACTIVE)
	actor._set_state(DungeonEnemy.AIState.RECOVERY)
	actor.state_time = float(CREEP.RECOVERIES[attack_index])
	actor.velocity = Vector3.ZERO
	actor._update_visual_pose(0.0)
	_check(actor.animation_clip == CREEP.ATTACKS[attack_index], "fixture must finish the actual source attack: " + CREEP.ATTACKS[attack_index])
	return _poses(actor.skeleton)


func _begin_transition(attack_index: int) -> void:
	var last_attack := _finish_attack(attack_index)
	actor._set_state(DungeonEnemy.AIState.CHASE)
	_assert_pose_matches(last_attack, "RECOVERY→CHASE must preserve every bone on entry", 0.00001, 0.0007)
	var state := _transition()
	_check(bool(state.get("active", false)), "attack recovery must start an active locomotion transition")
	_check(absf(float(state.get("elapsed", -1.0))) < 0.00001, "entry must not consume a frame of blend time")
	_check(absf(float(state.get("duration", -1.0)) - 0.28) < 0.00001, "recovery-to-walk must expose its 0.28-second blend duration")


func _test_recovery_to_walk(attack_index: int) -> void:
	_begin_transition(attack_index)
	var weighted_bones := _skin_weighted_bones()
	var prior_local := _poses(actor.skeleton)
	var prior_global := _poses(actor.skeleton, true)
	var maximum_angle := 0.0
	var maximum_distance := 0.0
	var maximum_world_distance := 0.0
	var maximum_weighted_distance := 0.0
	var maximum_step := {}
	var maximum_weighted_step := {}
	var changed := false
	for frame in range(24):
		actor.state_time += STEP
		actor.velocity = Vector3(0.0, 0.0, -2.2 * minf(float(frame + 1) / 12.0, 1.0))
		actor._update_visual_pose(STEP)
		var local := _poses(actor.skeleton)
		var global_bones := _poses(actor.skeleton, true)
		for bone in local.size():
			var angular := local[bone].basis.get_rotation_quaternion().angle_to(prior_local[bone].basis.get_rotation_quaternion())
			var distance := global_bones[bone].origin.distance_to(prior_global[bone].origin)
			var rig_world: Transform3D = actor.skeleton.global_transform
			var world_distance := (rig_world * global_bones[bone]).origin.distance_to((rig_world * prior_global[bone]).origin)
			maximum_angle = maxf(maximum_angle, angular)
			maximum_world_distance = maxf(maximum_world_distance, world_distance)
			if distance > maximum_distance:
				maximum_distance = distance
				maximum_step = _step_diagnostic(bone, frame + 1, prior_local[bone], local[bone], prior_global[bone], global_bones[bone], weighted_bones)
			if weighted_bones.has(bone) and distance > maximum_weighted_distance:
				maximum_weighted_distance = distance
				maximum_weighted_step = _step_diagnostic(bone, frame + 1, prior_local[bone], local[bone], prior_global[bone], global_bones[bone], weighted_bones)
			changed = changed or angular > 0.001 or distance > 0.0001
			_check(local[bone].is_finite() and global_bones[bone].is_finite(), "blend must keep real bone transforms finite")
		prior_local = local
		prior_global = global_bones
	_check(changed, "transition must move actual bones rather than only report an active state")
	_check(maximum_angle < deg_to_rad(22.0), "no individual joint may snap more than 22 degrees in one 60Hz transition frame (actual %.3f)" % rad_to_deg(maximum_angle))
	_check(maximum_world_distance < 0.16, "no actual bone may teleport more than 16cm in one fixed-root transition frame (actual %.5fm)" % maximum_world_distance)
	var state := _transition()
	_check(not bool(state.get("active", true)), "the locomotion blend must finish before 0.4 seconds")
	_check(actor.animation_clip == "walk", "finished transition must be sampling the actual walk clip")
	_assert_pose_matches(_source_pose("walk", float(state.get("walk_sample", -1.0))), "at 0.4 seconds the rig must converge to independently sampled source walking")
	var entry := {"attack": CREEP.ATTACKS[attack_index], "maximum_frame_joint_degrees": rad_to_deg(maximum_angle), "maximum_frame_skeleton_distance": maximum_distance, "maximum_frame_world_distance": maximum_world_distance, "maximum_step": _compact_step(maximum_step), "maximum_weighted_step": _compact_step(maximum_weighted_step), "direct_skin_bone_count": weighted_bones.size(), "transition": state}
	if maximum_world_distance >= 0.16 or maximum_angle >= deg_to_rad(22.0):
		entry["failure_diagnostics"] = {"maximum_step": maximum_step, "maximum_weighted_step": maximum_weighted_step}
	report.append(entry)


func _skin_weighted_bones() -> Dictionary:
	# Classify by positive weights in the rendered meshes, not bone naming.
	var result := {}
	var rig: Skeleton3D = actor.skeleton
	for mesh: MeshInstance3D in actor.visual_meshes:
		if mesh.mesh == null or mesh.skin == null or not mesh.is_visible_in_tree():
			continue
		var skin := mesh.skin
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_WEIGHTS] == null or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bindings: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for index in mini(weights.size(), bindings.size()):
				if weights[index] <= 0.000001:
					continue
				var binding := bindings[index]
				if binding < 0 or binding >= skin.get_bind_count():
					continue
				var bone := rig.find_bone(skin.get_bind_name(binding))
				if bone < 0: bone = skin.get_bind_bone(binding)
				if bone < 0 or bone >= rig.get_bone_count():
					continue
				if not result.has(bone):
					result[bone] = {"positive_weight_entries": 0, "meshes": []}
				result[bone].positive_weight_entries += 1
				if str(mesh.name) not in result[bone].meshes:
					result[bone].meshes.append(str(mesh.name))
	return result


func _step_diagnostic(bone: int, frame: int, local_before: Transform3D, local_after: Transform3D, global_before: Transform3D, global_after: Transform3D, weighted_bones: Dictionary) -> Dictionary:
	var rig: Skeleton3D = actor.skeleton
	var rig_scale := rig.global_basis.get_scale()
	var weighted_descendants: Array[String] = []
	for candidate: int in weighted_bones:
		var ancestor := rig.get_bone_parent(candidate)
		while ancestor >= 0:
			if ancestor == bone:
				weighted_descendants.append(rig.get_bone_name(candidate))
				break
			ancestor = rig.get_bone_parent(ancestor)
	var parent := rig.get_bone_parent(bone)
	return {
		"bone": rig.get_bone_name(bone), "bone_index": bone, "parent": rig.get_bone_name(parent) if parent >= 0 else "",
		"frame_1_based": frame, "elapsed_seconds": frame * STEP, "sample": float(actor.animation_sample),
		"direct_skin_weights": weighted_bones.get(bone, {}), "weighted_descendants": weighted_descendants,
		"affects_rendered_skin": weighted_bones.has(bone) or not weighted_descendants.is_empty(),
		"skeleton_distance": global_after.origin.distance_to(global_before.origin),
		"world_distance": (rig.global_transform * global_after).origin.distance_to((rig.global_transform * global_before).origin),
		"local_before": _transform_report(local_before), "local_after": _transform_report(local_after),
		"skeleton_before": _transform_report(global_before), "skeleton_after": _transform_report(global_after),
		"rig_world": _transform_report(rig.global_transform), "rig_scale": [rig_scale.x, rig_scale.y, rig_scale.z], "transition": _transition(),
	}


func _compact_step(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {}
	return {"bone": value.bone, "frame_1_based": value.frame_1_based, "world_distance_m": value.world_distance, "rig_scale": value.rig_scale, "affects_rendered_skin": value.affects_rendered_skin}


func _transform_report(value: Transform3D) -> Dictionary:
	return {"origin": [value.origin.x, value.origin.y, value.origin.z],
		"basis_x": [value.basis.x.x, value.basis.x.y, value.basis.x.z],
		"basis_y": [value.basis.y.x, value.basis.y.y, value.basis.y.z],
		"basis_z": [value.basis.z.x, value.basis.z.y, value.basis.z.z]}


func _clock_advance(speed: float, frames: int) -> float:
	var clip: Animation = actor.animation_player.get_animation("walk")
	var total := 0.0
	for frame in range(frames):
		var before := float(_transition().get("walk_sample", 0.0))
		actor.velocity = Vector3(0.0, 0.0, -speed)
		actor.state_time += STEP
		actor._update_visual_pose(STEP)
		var after := float(_transition().get("walk_sample", 0.0))
		total += fposmod(after - before, clip.length)
	return total


func _test_speed_clock(attack_index: int) -> void:
	var stopped := _clock_advance(0.0, 30)
	var walking := _clock_advance(2.2, 30)
	_check(stopped < 0.03, "zero actual velocity must not keep a full-speed walk cycle running (advanced %.5fs)" % stopped)
	_check(walking > 0.45 and walking < 0.55, "2.2m/s actual velocity must advance about half a source second in half a second (actual %.5fs)" % walking)
	_check(float(_transition().get("walk_speed", -1.0)) > 0.0, "snapshot must report live locomotion speed")
	report.append({"clock_after_attack": CREEP.ATTACKS[attack_index], "stopped_advance": stopped, "walking_advance": walking})


func _test_walk_to_windup(attack_index: int) -> void:
	var walk_pose := _poses(actor.skeleton)
	actor.attack_index = attack_index - 1
	actor._set_state(DungeonEnemy.AIState.WINDUP)
	_assert_pose_matches(walk_pose, "active walking→WINDUP must preserve the moving pose on entry", 0.00001, 0.0007)
	for frame in range(10):
		actor.state_time += STEP
		actor.velocity = Vector3.ZERO
		actor._update_visual_pose(STEP)
	_check(not bool(_transition().get("active", true)), "walk-to-attack blend must finish before the 0.30-second shortest windup/contact window")
	_assert_pose_matches(_source_pose(CREEP.ATTACKS[attack_index], float(actor.animation_sample)), "windup must converge to the original attack before contact")


func _test_interruption(interruption: String) -> void:
	_begin_transition(1)
	for frame in range(6):
		actor.state_time += STEP
		actor.velocity = Vector3(0.0, 0.0, -1.1)
		actor._update_visual_pose(STEP)
	_check(bool(_transition().get("active", false)), "interruption must happen while the attack-to-walk blend is still active")
	if interruption == "death":
		var dying_pose := _poses(actor.skeleton)
		actor.receive_hit(10000.0, actor.global_position + Vector3.FORWARD * 2.0, 1.0, false)
		actor.ragdoll.set_physics_process(false)
		_check(actor.ai_state == DungeonEnemy.AIState.DEAD and actor.ragdoll.phase != "living", "fatal interruption must transfer ownership to the actual ragdoll controller")
		_check(not bool(_transition().get("active", true)), "death must clear the pending standing blend")
		_assert_pose_matches(dying_pose, "ragdoll entry must preserve the interrupted skin pose")
		for frame in range(24):
			actor.state_time += STEP
			actor._update_visual_pose(STEP)
		_assert_pose_matches(dying_pose, "standing animation updates must not overwrite the paused ragdoll-owned pose")
		return
	actor._set_state(DungeonEnemy.AIState.STAGGER)
	_check(not bool(_transition().get("active", true)), "hit reaction must clear the locomotion blend immediately")
	if interruption == "stagger":
		for frame in range(24):
			actor.state_time += STEP
			actor._update_visual_pose(STEP)
			_assert_pose_matches(_source_pose("hit", float(actor.animation_sample)), "standing blend must not reappear over the hit clip")
		return
	var executor := Node3D.new()
	stage.add_child(executor)
	executor.global_position = actor.global_position + Vector3(0.0, 0.0, 1.1)
	actor.health = actor.max_health * 0.2
	_check(actor.begin_execution(executor), "interrupted and staggered creature must reserve a real standing execution")
	_check(actor.ai_state == DungeonEnemy.AIState.EXECUTION and not bool(_transition().get("active", true)), "execution must exclusively own the rig without a stale standing blend")
	actor.advance_execution_pose(0.22)
	var execution_pose := _poses(actor.skeleton)
	for frame in range(24):
		actor.state_time += STEP
		actor._update_visual_pose(STEP)
	_assert_pose_matches(execution_pose, "unrelated standing delta/state time must not overwrite an execution-controlled pose")
	actor.cancel_execution(executor)
	_check(actor.ai_state == DungeonEnemy.AIState.STAGGER and not bool(_transition().get("active", true)), "execution cancellation must return to reaction without resurrecting an old blend")
	executor.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
