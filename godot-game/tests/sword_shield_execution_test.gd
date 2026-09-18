extends SceneTree
## Exercises the production charge/release, reservation, damage and hand rig.
const HELPERS := preload("res://tests/player_arm_preview.gd")
const MOTION := preload("res://scripts/sword_shield_execution_motion.gd")
var failures: Array[String] = []
var view: SubViewport
var stage: Node3D
var player: DungeonPlayer
var enemy: DungeonEnemy
var defeats := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	view = HELPERS.create_viewport()
	root.add_child(view)
	var fixture := HELPERS.populate_viewport(view)
	stage = fixture.stage
	player = fixture.player
	fixture.chest.position = Vector3(20, 0, 20)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 0.2, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	await _prepare()
	_check(player.get_execution_target() == enemy, "low-health staggered enemy should be targetable")
	# A real enemy strike must enter the existing shield-parry path first.
	enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	player.advance_combat_state(0.10, true)
	enemy.state_time = DungeonEnemy.ATTACK_HIT_TIME
	enemy._resolve_active_attack()
	_check(enemy.ai_state == DungeonEnemy.AIState.STAGGER and player.health == player.MAX_HEALTH, "actual shield parry stuns without damage")
	_check(_charge_release(), "heavy attack after just guard should reserve the enemy")
	_check(player.stamina == player.MAX_STAMINA - MOTION.STAMINA_COST, "execution spends stamina exactly once")
	var untouched := enemy.health
	player.advance_execution(MOTION.HIT_SECONDS - 0.001)
	player._update_viewmodel(0.0)
	_check(enemy.health == untouched and defeats == 0, "no damage or defeat before the blade contact")
	_check(not player.begin_sword_attack().accepted and not player.request_primary_weapon().accepted, "execution excludes attacks and shield stow")
	player._resolve_active_attack()
	_check(enemy.health == untouched, "normal sword hit resolver cannot deal a second execution hit")
	player.advance_execution(0.002)
	_check(enemy.health == 0.0 and defeats == 1, "the contact kills even a high absolute remaining HP value")
	player.advance_execution(0.1)
	_check(defeats == 1, "contact cannot emit defeat twice")
	player.advance_execution(2.0)
	_check(not player.is_execution_active() and player.combat_state == DungeonPlayer.CombatState.READY, "execution recovers to usable combat")
	_check(player.camera.position == Vector3.ZERO and player.camera.rotation == Vector3.ZERO, "camera offsets are restored")
	await _prepare()
	player.begin_sword_attack()
	player.attack_release_requested = true
	player.advance_combat_state(0.05)
	_check(not player.is_execution_active(), "short click remains a normal attack")
	player.advance_combat_state(0.30)
	player._resolve_active_attack()
	_check(enemy.health > 0.0, "ordinary damage is not an unconditional kill")
	await _prepare()
	enemy.health = enemy.max_health * 0.31
	_check(not _charge_release(), "high health plus stun cannot execute")
	await _prepare()
	enemy._set_state(DungeonEnemy.AIState.IDLE)
	_check(not _charge_release(), "low health without vulnerability cannot execute")
	await _prepare()
	enemy.stagger_duration = 0.1
	enemy.state_time = 0.11
	_check(not _charge_release(), "expired stun cannot execute even before AI updates")
	await _prepare()
	player._shield_stowed = true
	_check(not _charge_release(), "a packed shield is not a held shield")
	await _prepare()
	player.stamina = MOTION.STAMINA_COST - 1.0
	_check(not _charge_release(), "insufficient stamina cannot reserve a target")
	await _prepare()
	enemy.position.z = -3.0
	await physics_frame
	_check(player.get_execution_target() == null, "distant target is rejected")
	enemy.position = Vector3(1.5, 0.9, -0.5)
	await physics_frame
	_check(player.get_execution_target() == null, "side target is rejected")
	await _prepare()
	var wall := _wall()
	stage.add_child(wall)
	await physics_frame
	await physics_frame
	_check(player.get_execution_target() == null, "world obstruction prevents target acquisition")
	wall.free()
	await _prepare()
	_check(_charge_release(), "cancellation trial begins normally")
	player.advance_execution(0.3)
	player._update_viewmodel(0)
	player.receive_environment_damage(1, "execution interruption")
	_check(not player.is_execution_active() and enemy.health > 0 and enemy.ai_state != DungeonEnemy.AIState.EXECUTION, "incoming damage cancels both participants")
	player.advance_execution(5)
	_check(enemy.health > 0, "cancelled execution has no delayed lethal callback")
	await _prepare()
	_check(_charge_release(), "pause trial begins")
	paused = true
	player.advance_combat_state(4)
	_check(is_zero_approx(player.execution_elapsed) and enemy.health > 0, "pause freezes execution time and damage")
	paused = false
	player.prepare_for_inventory()
	_check(not player.is_execution_active() and enemy.ai_state != DungeonEnemy.AIState.EXECUTION, "inventory/F2 cancellation releases the target")
	await _prepare()
	_check(_charge_release(), "equipment trial begins")
	player.inventory_model.equipment.offhand = ""
	player.inventory_model.changed.emit()
	_check(not player.is_execution_active() and enemy.health > 0, "unequipping the shield interrupts before damage")
	await _prepare()
	_check(_charge_release(), "removed target trial begins")
	enemy.free()
	player.advance_execution(1.0)
	_check(not player.is_execution_active(), "removed target releases player without dereferencing a freed instance")
	enemy = null
	await _prepare()
	_check(_charge_release(), "blocked impact trial begins")
	wall = _wall()
	stage.add_child(wall)
	await physics_frame
	await physics_frame
	player.advance_execution(1.0)
	_check(not player.is_execution_active() and enemy.health > 0, "an obstruction appearing before contact cancels the kill")
	wall.free()
	await _test_motion_and_step()
	player.cancel_sword_attack()
	view.queue_free()
	await process_frame
	sandbox.finish()
	_check(before == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "session and cursor must be preserved")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD EXECUTION TEST %s: production parry/charge, contact kill, gating, cancellation, pause, collision, arm contacts and session preservation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _prepare() -> void:
	player.cancel_sword_attack()
	if is_instance_valid(enemy): enemy.free()
	player.inventory_model.equipment.weapon = "rusted_sword"
	player.inventory_model.equipment.offhand = "round_shield"
	player.inventory_model.changed.emit()
	player.reset_shield_carry()
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player.position = Vector3(0, 0.9, 0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player._pitch = 0
	player.head.rotation = Vector3.ZERO
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
	player._update_viewmodel(0.1)
	ExpeditionSession.active_conditions.clear()
	enemy = DungeonEnemy.new()
	enemy.configure("처형 조건 시험", 1000, 10, 0, Color.WHITE)
	enemy.position = Vector3(0, 0.9, -1.4)
	enemy.rotation.y = PI
	enemy.set_physics_process(false)
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(player, null, null)
	enemy.health = 250
	enemy._set_state(DungeonEnemy.AIState.STAGGER, 8.0)
	defeats = 0
	enemy.defeated.connect(func(_actor: DungeonEnemy) -> void: defeats += 1)
	await physics_frame
	await physics_frame


func _charge_release() -> bool:
	var started := player.begin_sword_attack()
	if not bool(started.accepted): return false
	player.advance_combat_state(0.42)
	player.attack_release_requested = true
	player.advance_combat_state(0.01)
	return player.is_execution_active()


func _wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = DungeonPlayer.WORLD_LAYER
	wall.collision_mask = 0
	wall.position = Vector3(0, 1.1, -0.7)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 2.2, 0.15)
	shape.shape = box
	wall.add_child(shape)
	return wall


func _test_motion_and_step() -> void:
	await _prepare()
	enemy.position.z = -2.0
	await physics_frame
	_check(_charge_release(), "approach trial starts within range")
	var start_position := player.position
	var previous_pose := player.weapon_pivot.transform
	for frame in range(1, 94):
		player.advance_combat_state(1.0 / 60.0)
		player.advance_movement(1.0 / 60.0, Vector2(1, -1), true)
		player._update_viewmodel(1.0 / 60.0)
		var pose := player.weapon_pivot.transform
		_check(pose.origin.is_finite() and pose.basis.is_finite(), "motion must stay finite")
		_check(pose.origin.distance_to(previous_pose.origin) < 0.20, "hands must follow a continuous motion")
		var snap := player.get_first_person_motion_snapshot()
		_check(snap.visible_arm_count == 2 and snap.left_hand_role == "shield", "both hands remain visible with shield held")
		for key: String in ["sword", "shield"]:
			var contact: Dictionary = snap.hand_contacts.get(key, {})
			_check(not contact.is_empty() and float(contact.get("error", INF)) < 0.01, "hand stays attached to " + key)
		previous_pose = pose
	_check(player.position.distance_to(start_position) > 0.3 and absf(player.position.x) < 0.02, "authored step uses collision movement and ignores player strafe")
	_check(defeats == 1 and not player.is_execution_active(), "full frame-by-frame action must finish exactly once")


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
