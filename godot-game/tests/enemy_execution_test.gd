extends SceneTree

const ENEMY := preload("res://scripts/enemy.gd")
const CREEP := preload("res://scripts/creep_enemy.gd")

var failures: Array[String] = []
var world: Node3D
var executor: DungeonPlayer
var stranger: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cursor := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DungeonEnemy.WORLD_LAYER
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	executor = DungeonPlayer.new()
	executor.position = Vector3(0.0, 0.9, 1.2)
	world.add_child(executor)
	executor.set_physics_process(false)
	executor.set_process_unhandled_input(false)
	stranger = Node3D.new()
	stranger.position = executor.position
	world.add_child(stranger)
	var enemy := ENEMY.new() as DungeonEnemy
	enemy.position = Vector3(0.0, 0.9, 0.0)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.target = executor
	await physics_frame
	_test_eligibility(enemy)
	_test_reservation_and_clock(enemy)
	_test_lost_owner(enemy)
	_test_finish_once(enemy)
	if CREEP.is_available():
		var creep = CREEP.new()
		creep.position = Vector3(3.0, 0.9, 0.0)
		world.add_child(creep)
		creep.set_physics_process(false)
		creep.ragdoll.set_physics_process(false)
		creep.target = executor
		await physics_frame
		_test_eligibility(creep)
		_test_reservation_and_clock(creep)
		_test_lost_owner(creep)
		_test_creep_pose_and_death(creep)
	else:
		print("ENEMY EXECUTION: licensed Creep is missing; source-pose/ragdoll checks SKIPPED.")
	world.queue_free()
	await process_frame
	_check(Input.mouse_mode == cursor, "execution tests preserve cursor mode")
	_check(ExpeditionSession.capture_snapshot() == session_before, "isolated actors leave the expedition unchanged")
	for failure in failures:
		push_error("ENEMY EXECUTION TEST FAIL: " + failure)
	print("ENEMY EXECUTION TEST %s: eligibility, reservation, owner loss, clock, gravity, one defeat and existing Creep death path" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _vulnerable(actor: DungeonEnemy) -> void:
	actor.max_health = 100.0
	actor.health = 30.0
	actor.velocity = Vector3.ZERO
	actor._set_state(DungeonEnemy.AIState.STAGGER)


func _test_eligibility(actor: DungeonEnemy) -> void:
	_vulnerable(actor)
	_check(actor.is_execution_vulnerable(), "exactly 30 percent health with active stagger is eligible")
	actor.health = 30.001
	_check(not actor.is_execution_vulnerable(), "high health with active stagger is ineligible")
	actor.health = 20.0
	for state in [DungeonEnemy.AIState.IDLE, DungeonEnemy.AIState.CHASE, DungeonEnemy.AIState.WINDUP, DungeonEnemy.AIState.ACTIVE, DungeonEnemy.AIState.RECOVERY]:
		actor._set_state(state)
		_check(not actor.is_execution_vulnerable(), "low health without stagger is ineligible: %s" % state)
	_vulnerable(actor)
	actor.state_time = actor.stagger_duration
	_check(not actor.is_execution_vulnerable() and not actor.begin_execution(executor), "expired stagger is rejected even before its next AI tick")
	actor.state_time -= 0.001
	_check(actor.is_execution_vulnerable(), "positive remaining stagger permits execution")
	actor.max_health = 0.0
	_check(not actor.is_execution_vulnerable(), "zero maximum health is ineligible")
	_vulnerable(actor)
	actor.health = 0.0
	_check(not actor.is_execution_vulnerable(), "zero health is never a living execution target")
	_vulnerable(actor)
	_check(not actor.begin_execution(null) and not actor.begin_execution(actor), "null/self executors cannot reserve a target")
	var detached := Node3D.new()
	_check(not actor.begin_execution(detached), "an executor outside the scene cannot reserve a target")
	detached.free()
	executor.health = 0.0
	_check(not actor.begin_execution(executor), "a dead player cannot reserve a target")
	executor.health = executor.MAX_HEALTH


func _test_reservation_and_clock(actor: DungeonEnemy) -> void:
	_vulnerable(actor)
	actor.global_position = executor.global_position + Vector3(0.0, 0.0, -1.2)
	var entry := actor.visual_root.transform
	_check(actor.begin_execution(executor), "vulnerable target accepts one owner")
	_check(actor.ai_state == DungeonEnemy.AIState.EXECUTION and not actor.is_execution_vulnerable(), "reserved target leaves the vulnerable pool")
	_check(not actor.begin_execution(executor) and not actor.begin_execution(stranger), "neither repeated nor competing reservation succeeds")
	_check(actor.visual_root.transform.is_equal_approx(entry), "execution begins from the current visual position")
	_check(not actor.finish_execution(stranger), "a different owner cannot finish an execution")
	actor.cancel_execution(stranger)
	_check(actor.ai_state == DungeonEnemy.AIState.EXECUTION, "a different owner cannot cancel an execution")
	var hp := executor.health
	actor._resolve_active_attack()
	_check(not actor._attempt_attack() and not actor.is_sword_attack_active() and executor.health == hp, "execution disables both contact resolution and direct enemy attack")
	actor.position.y = 4.0
	var before := actor.position
	actor.velocity = Vector3(4.0, -0.1, -3.0)
	actor._physics_process(0.1)
	_check(is_equal_approx(before.x, actor.position.x) and is_equal_approx(before.z, actor.position.z), "execution freezes planar body movement")
	_check(actor.velocity.y < -0.1 and actor.position.y < before.y, "execution retains gravity")
	_check(is_zero_approx(actor._execution_elapsed) and is_zero_approx(actor.state_time), "enemy physics does not advance the player-owned clock")
	actor.advance_execution_pose(0.30)
	var press := actor.visual_root.transform
	actor._physics_process(0.05)
	actor._update_weapon_pose(1.0)
	actor._update_visual_pose(1.0)
	_check(actor.visual_root.transform.is_equal_approx(press) and is_equal_approx(actor._execution_elapsed, 0.30), "ordinary pose/AI updates hold the same player-clock pose")
	actor.advance_execution_pose(0.66)
	_check(actor.visual_root.position.y < press.origin.y, "enemy lowers while the player raises the sword")
	var lowered := actor.visual_root.transform
	actor.advance_execution_pose(0.15)
	_check(actor.visual_root.transform.is_equal_approx(lowered), "late older clock samples cannot rewind execution")
	actor.advance_execution_pose(NAN)
	_check(actor.visual_root.transform.is_equal_approx(lowered), "invalid clock values cannot corrupt a target transform")
	actor.receive_hit(1.0, executor.global_position, 1.0, false)
	_check(actor.health == 29.0 and actor.ai_state == DungeonEnemy.AIState.EXECUTION and is_zero_approx(actor.velocity.x) and is_zero_approx(actor.velocity.z), "nonfatal damage keeps the reservation and cannot push the locked actor")
	actor.cancel_execution(executor)
	_check(actor.ai_state == DungeonEnemy.AIState.STAGGER and is_equal_approx(actor.stagger_duration, actor.STAGGER_SECONDS), "owner cancellation restores ordinary finite stagger")
	_check(actor.visual_root.transform.is_equal_approx(entry), "cancellation restores the visual root instead of leaving it sunken")
	_check(actor.is_execution_vulnerable() and actor.begin_execution(stranger), "cancellation releases the reservation for a new owner")
	actor.cancel_execution(stranger)
	actor._physics_process(actor.STAGGER_SECONDS + 0.01)
	_check(actor.ai_state not in [DungeonEnemy.AIState.STAGGER, DungeonEnemy.AIState.EXECUTION, DungeonEnemy.AIState.DEAD], "cancelled execution returns to ordinary AI when stagger expires")
	actor.position.y = 0.9


func _test_lost_owner(actor: DungeonEnemy) -> void:
	for loss in ["removed", "queued", "freed"]:
		_vulnerable(actor)
		var lost := Node3D.new()
		world.add_child(lost)
		_check(actor.begin_execution(lost), "owner-loss fixture reserves the real actor: " + loss)
		match loss:
			"removed":
				world.remove_child(lost)
			"queued":
				lost.queue_free()
			"freed":
				lost.free()
		actor._physics_process(0.01)
		_check(actor.ai_state == DungeonEnemy.AIState.STAGGER and actor.is_execution_vulnerable(), "owner loss automatically releases the actor: " + loss)
		if loss == "removed":
			lost.free()
	_vulnerable(actor)
	_check(actor.begin_execution(executor), "player death fixture reserves the target")
	executor.health = 0.0
	actor.advance_execution_pose(0.15)
	_check(actor.ai_state == DungeonEnemy.AIState.STAGGER and not actor.finish_execution(executor), "player death auto-cancels instead of finishing a kill")
	executor.health = executor.MAX_HEALTH
	_vulnerable(actor)
	_check(actor.begin_execution(executor), "dead-state fixture reserves the target")
	executor.combat_state = DungeonPlayer.CombatState.DEAD
	actor._physics_process(0.01)
	_check(actor.ai_state == DungeonEnemy.AIState.STAGGER, "a dead combat state auto-releases even if a debug fixture restored player HP")
	executor.combat_state = DungeonPlayer.CombatState.READY


func _test_finish_once(actor: DungeonEnemy) -> void:
	_vulnerable(actor)
	var defeats := [0]
	actor.defeated.connect(func(_enemy: DungeonEnemy): defeats[0] += 1)
	_check(actor.begin_execution(executor), "finish fixture reserves the real actor")
	actor.advance_execution_pose(0.819)
	_check(actor.health == 30.0 and defeats[0] == 0, "pre-contact choreography never damages or awards a defeat")
	actor.health = 1000.0
	_check(actor.finish_execution(executor), "finish kills even when health was raised beyond the starting maximum")
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and actor.collision_layer == 0 and actor.collision_mask == 0, "execution uses the production death and collision cleanup")
	_check(defeats[0] == 1, "production defeat/reward signal is emitted exactly once")
	_check(not actor.finish_execution(executor) and not actor.begin_execution(stranger), "the corpse cannot be finished or reserved again")
	actor.cancel_execution(executor)
	actor.receive_hit(1000.0, executor.global_position, 1.0, false)
	actor._die()
	_check(defeats[0] == 1 and actor.ai_state == DungeonEnemy.AIState.DEAD, "cancel, corpse damage and repeated death calls cannot duplicate rewards or revive")


func _test_creep_pose_and_death(creep) -> void:
	_vulnerable(creep)
	var hash_before := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var clips_before: PackedStringArray = creep.animation_player.get_animation_list()
	var head: int = creep.skeleton.find_bone("Head")
	var entry: Transform3D = creep.skeleton.get_bone_pose(head)
	_check(creep.begin_execution(executor), "Creep reserves through the shared production API")
	_check(creep.skeleton.get_bone_pose(head).is_equal_approx(entry), "Creep begins from the current skeletal pose without a snap")
	creep.advance_execution_pose(0.30)
	_check(creep.animation_clip == "hit" and creep.animation_sample > 0.0 and not creep.skeleton.get_bone_pose(head).is_equal_approx(entry), "Creep execution samples real hit animation tracks")
	var press_sample: float = creep.animation_sample
	creep.advance_execution_pose(0.66)
	_check(creep.animation_sample > press_sample and creep.visual_root.position.y < creep.visual_base_position.y, "Creep recoil and body lowering follow the player's preparation phase")
	creep.cancel_execution(executor)
	_check(creep.ragdoll.phase == "living" and creep.ragdoll.parts.is_empty(), "cancelling living Creep never creates a corpse")
	_vulnerable(creep)
	_check(creep.begin_execution(executor), "Creep can restart after cancellation")
	creep.advance_execution_pose(0.82)
	var contact_pose: Array[Transform3D] = []
	for bone in creep.skeleton.get_bone_count():
		contact_pose.append(creep.skeleton.get_bone_pose(bone))
	var defeats := [0]
	creep.defeated.connect(func(_enemy: DungeonEnemy): defeats[0] += 1)
	_check(creep.finish_execution(executor), "Creep execution finishes through its original death override")
	_check(creep.health == 0.0 and creep.ai_state == DungeonEnemy.AIState.DEAD and defeats[0] == 1, "Creep has one real defeat and zero health")
	_check(creep.ragdoll.phase == "reaction" and _poses_match(creep.ragdoll.initial_pose, contact_pose), "ragdoll starts from the execution contact pose without a snap")
	creep.ragdoll.set_physics_process(false)
	creep._physics_process(1.0)
	creep.advance_execution_pose(1.55)
	creep._update_visual_pose(1.0)
	_check(is_zero_approx(creep.ragdoll.reaction_time) and _poses_match(creep.ragdoll.initial_pose, contact_pose), "dead enemy/execution updates do not drive or overwrite the separate ragdoll")
	creep.ragdoll._physics_process(creep.ragdoll.REACTION_SECONDS)
	_check(creep.ragdoll.phase == "simulating" and creep.ragdoll.parts.size() == 20 and creep.ragdoll.joints.size() == 19, "execution death reaches the existing connected physical ragdoll")
	_check(not creep.finish_execution(executor), "repeat Creep completion is rejected")
	creep.receive_hit(1000.0, executor.global_position, 1.0, false)
	creep._die()
	_check(defeats[0] == 1 and creep.ragdoll.phase == "simulating", "corpse hits and repeated death do not restart Creep ragdoll or rewards")
	_check(creep.animation_player.get_animation_list() == clips_before and FileAccess.get_sha256(CREEP.MODEL_PATH) == hash_before, "execution preserves all source clips and licensed model bytes")


func _poses_match(first: Array[Transform3D], second: Array[Transform3D]) -> bool:
	if first.size() != second.size():
		return false
	for bone in first.size():
		if not first[bone].is_equal_approx(second[bone]):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
