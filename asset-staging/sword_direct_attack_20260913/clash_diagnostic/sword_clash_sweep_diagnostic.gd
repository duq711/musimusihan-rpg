extends SceneTree

const SWORD_CLASH_GEOMETRY := preload("res://scripts/sword_clash_geometry.gd")

var failures: Array[String] = []
var _candidate := Vector3(0.25, 24, -1.1)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_box_geometry()
	_check(is_equal_approx(DungeonPlayer.ATTACK_HIT_TIME, 0.055), "normal player attacks must retain their original hit timing")

	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "main scene must load for sword-clash validation")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame

	var player := get_first_node_in_group("player") as DungeonPlayer
	var armed_enemy: DungeonEnemy = null
	var unarmed_enemy: DungeonEnemy = null
	for enemy_node in get_nodes_in_group("enemy"):
		var enemy := enemy_node as DungeonEnemy
		enemy.set_physics_process(false)
		if enemy.sword_blade != null:
			armed_enemy = enemy
		else:
			unarmed_enemy = enemy
	_check(player != null, "player must spawn for sword-clash validation")
	_check(armed_enemy != null, "an armed enemy must expose its modeled sword blade")
	_check(unarmed_enemy != null, "the unarmed skeleton variant must remain available")
	if player == null or armed_enemy == null or unarmed_enemy == null:
		_finish()
		return
	player.set_physics_process(false)
	_check(game.process_physics_priority > player.process_physics_priority, "game combat resolution must run after actor pose updates")
	_check(player.sword_blade != null, "player must expose the modeled sword blade")
	_check(unarmed_enemy.sword_blade == null, "the anatomical skeleton must not gain an invisible sword proxy")
	var initial_enemy_health := armed_enemy.health
	var trials := [Vector3(0.75, 24, -1.1)]
	var found := false
	for trial: Vector3 in trials:
		_candidate = trial
		armed_enemy.health = initial_enemy_health
		armed_enemy.visual_time = 0.0
		player.cancel_sword_attack()
		player._camera_shake = 0.0
		player.camera.position = Vector3.ZERO
		player.camera.rotation = Vector3.ZERO
		player._pitch = 0.0
		player._motion_clock = 0.0
		player._motion_speed = 0.0
		player._motion_look_sway = Vector2.ZERO
		player._motion_previous_look = Vector2.ZERO
		player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
		player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
		player.reset_reference_movement_motion()
		player._update_viewmodel(1.5)
		failures.clear()
		_test_natural_swing_clash(player, armed_enemy)
		print("NATURAL TRIAL x=", trial.x, " z=", trial.z, " lead_frames=", int(trial.y), " failures=", failures.size())
		if failures.is_empty():
			found = true
			break
	print("NATURAL SEARCH ", "FOUND" if found else "NO MATCH IN REQUESTED X=0.75 PLACEMENT")
	quit(0 if found else 1)


func _test_box_geometry() -> void:
	var identity_axes := PackedVector3Array([Vector3.RIGHT, Vector3.UP, Vector3.BACK])
	var turned_axes := PackedVector3Array([Vector3.UP, Vector3.LEFT, Vector3.BACK])
	var horizontal := _box_proxy(Vector3.ZERO, identity_axes, Vector3(1.0, 0.05, 0.01))
	var crossing := _box_proxy(Vector3.ZERO, turned_axes, Vector3(1.0, 0.05, 0.01))
	var separated := _box_proxy(Vector3(0.0, 0.0, 0.08), turned_axes, Vector3(1.0, 0.05, 0.01))
	var face_touching := _box_proxy(Vector3(0.0, 0.0, 0.02), identity_axes, Vector3(1.0, 0.05, 0.01))
	var margin_gap := _box_proxy(Vector3(0.0, 0.0, 0.03), identity_axes, Vector3(1.0, 0.05, 0.01))
	var end_touching := _box_proxy(Vector3(2.0, 0.0, 0.0), identity_axes, Vector3(1.0, 0.05, 0.01))
	_check(SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, crossing, 0.0), "crossing oriented blade boxes must overlap")
	_check(not SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, separated, 0.02), "parallel blade faces with a visible thickness gap must remain separate")
	_check(SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, face_touching, 0.0), "blade boxes touching exactly at their faces must overlap")
	_check(not SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, margin_gap, 0.009), "a gap outside the configured margin must remain separate")
	_check(SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, margin_gap, 0.011), "the configured contact margin must bridge only its declared gap")
	_check(SWORD_CLASH_GEOMETRY.proxies_overlap(horizontal, end_touching, 0.0), "collinear blade boxes touching at their endpoints must overlap")
	_check(not SWORD_CLASH_GEOMETRY.proxies_overlap({}, horizontal, 0.0), "an empty blade proxy must never clash")


func _test_natural_swing_clash(player: DungeonPlayer, enemy: DungeonEnemy) -> void:
	var floor_height := player.global_position.y
	player.global_position = Vector3(0.0, floor_height, 0.0)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	# A close exchange, with both actors facing one another's attack path.
	# Overlapping active windows are required; identical phase starts are not.
	enemy.global_position = Vector3(_candidate.x, floor_height, _candidate.z)
	enemy.rotation.y = atan2(enemy.global_position.x, enemy.global_position.z)
	player.velocity = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	player.attack_hit_ids.clear()
	player.cancel_sword_attack()
	player.stamina = DungeonPlayer.MAX_STAMINA
	player.health = DungeonPlayer.MAX_HEALTH
	var enemy_health_before := enemy.health
	enemy._set_state(DungeonEnemy.AIState.WINDUP)
	enemy._update_weapon_pose(1.0)
	enemy._update_visual_pose(1.0)
	# Respond during the enemy's actual 0.7-second windup. This lets the player
	# lead the crossing slightly without editing either actor's hit deadline.
	for _frame in range(int(_candidate.y)):
		enemy._physics_process(1.0 / 60.0)
	# Start/release through production input boundaries. Directly setting ACTIVE
	# skips the attack's retained sword/shield clock and its actual preparation.
	var started := player.begin_sword_attack("right_diagonal")
	player._sword_direct_entry = OS.get_environment("CLASH_DIAGNOSTIC_DIRECT") == "1"
	_check(bool(started.accepted), "natural clash fixture must begin an actual basic sword attack")
	if not bool(started.accepted):
		return
	player.attack_release_requested = true
	for _frame in range(30):
		player.advance_action_timers(1.0 / 60.0)
		player.advance_combat_state(1.0 / 60.0, false)
		player._update_viewmodel(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		player._resolve_active_attack()
		enemy._resolve_active_attack()
		if player.combat_state != DungeonPlayer.CombatState.WINDUP:
			break
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and is_zero_approx(player.state_time), "real release must commit at the start of the natural active swing")
	_check(is_equal_approx(player.get_melee_hit_time(), 0.145) and is_equal_approx(player.get_melee_active_duration(), 0.30), "natural clash must use the retained production sword/shield clock")
	if player.combat_state != DungeonPlayer.CombatState.ACTIVE:
		return
	var natural_blades_overlapped := false
	var clash_player_time := INF
	var clash_enemy_time := INF
	for frame in range(12):
		player.advance_action_timers(1.0 / 60.0)
		player.advance_combat_state(1.0 / 60.0, false)
		player._update_viewmodel(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if OS.get_environment("SWORD_CLASH_TRACE") == "1": print("CLASH FRAME ", frame, " TIMES ", player.state_time, "/", enemy.state_time, " CENTERS ", player.get_sword_clash_proxy().get("center"), "/", enemy.get_sword_clash_proxy().get("center"), " ACTORS ", player.global_position, "/", enemy.global_position)
		if player.is_sword_attack_active() and enemy.is_sword_attack_active() and SWORD_CLASH_GEOMETRY.proxies_overlap(player.get_sword_clash_proxy(), enemy.get_sword_clash_proxy(), DungeonPlayer.SWORD_CLASH_MARGIN):
			natural_blades_overlapped = true
			clash_player_time = player.state_time
			clash_enemy_time = enemy.state_time
		player._resolve_active_attack()
		enemy._resolve_active_attack()
		if player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER:
			break
	print("NATURAL DIAGNOSTIC direct=", player._sword_direct_entry, " overlap=", natural_blades_overlapped, " player_t=", clash_player_time, " enemy_t=", clash_enemy_time, " player_state=", player.combat_state, " enemy_state=", enemy.ai_state, " health=", player.health, "/", enemy.health)
	_check(natural_blades_overlapped, "natural close-range attacks must overlap their rendered blade models")
	_check(clash_player_time < player.get_melee_hit_time() and clash_enemy_time < DungeonEnemy.ATTACK_HIT_TIME, "natural blade contact must occur before either body's damage deadline")
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "natural swing animation must cancel the player strike into clash recovery")
	_check(enemy.ai_state == DungeonEnemy.AIState.STAGGER, "natural swing animation must stagger the armed enemy")
	_check(is_equal_approx(player.health, DungeonPlayer.MAX_HEALTH), "natural swing clash must prevent enemy damage")
	_check(is_equal_approx(enemy.health, enemy_health_before), "natural swing clash must prevent player damage")


func _align_blades(player: DungeonPlayer, enemy: DungeonEnemy) -> void:
	var player_proxy := player.get_sword_clash_proxy()
	var enemy_proxy := enemy.get_sword_clash_proxy()
	var player_center: Vector3 = player_proxy["center"]
	var enemy_center: Vector3 = enemy_proxy["center"]
	enemy.sword_blade.global_position += player_center - enemy_center


func _box_proxy(center: Vector3, axes: PackedVector3Array, half_extents: Vector3) -> Dictionary:
	return {
		"center": center,
		"axes": axes,
		"half_extents": half_extents,
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("SWORD CLASH TEST PASS: modeled blade overlap, attack timing, damage cancellation, and unarmed exclusion")
		quit(0)
		return
	for failure in failures:
		push_error("SWORD CLASH TEST FAIL: %s" % failure)
	quit(1)
