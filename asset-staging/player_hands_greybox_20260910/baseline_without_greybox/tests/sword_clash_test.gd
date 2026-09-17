extends SceneTree

const SWORD_CLASH_GEOMETRY := preload("res://scripts/sword_clash_geometry.gd")

var failures: Array[String] = []


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
	_test_natural_swing_clash(player, armed_enemy)

	_align_blades(player, armed_enemy)
	_check(
		SWORD_CLASH_GEOMETRY.proxies_overlap(player.get_sword_clash_proxy(), armed_enemy.get_sword_clash_proxy(), DungeonPlayer.SWORD_CLASH_MARGIN),
		"aligned rendered blade proxies must overlap"
	)
	var player_health_before := player.health
	var enemy_health_before := armed_enemy.health
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	var clash_result := player.try_sword_clash(armed_enemy)
	_check(clash_result, "overlapping swords must clash while both attacks are active")
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "a sword clash must cancel the player strike into recovery")
	_check(armed_enemy.ai_state == DungeonEnemy.AIState.STAGGER, "a sword clash must stagger the attacking enemy")
	_check(is_equal_approx(player.health, player_health_before), "a sword clash must prevent player damage")
	_check(is_equal_approx(armed_enemy.health, enemy_health_before), "a sword clash must prevent enemy damage")
	_check(not player.try_sword_clash(armed_enemy), "one clash must not resolve repeatedly after both attacks are cancelled")

	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	armed_enemy.sword_blade.global_position += Vector3(4.0, 0.0, 0.0)
	_check(not player.try_sword_clash(armed_enemy), "separated sword models must not clash")
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "a missed clash must leave the player attack active")
	_check(armed_enemy.ai_state == DungeonEnemy.AIState.ACTIVE, "a missed clash must leave the enemy attack active")

	_align_blades(player, armed_enemy)
	player._set_combat_state(DungeonPlayer.CombatState.WINDUP)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	_check(not player.try_sword_clash(armed_enemy), "a player windup must not defend against an active enemy sword")
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	armed_enemy._set_state(DungeonEnemy.AIState.WINDUP)
	_check(not player.try_sword_clash(armed_enemy), "an enemy windup must not clash with the active player sword")

	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	unarmed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	_check(not player.try_sword_clash(unarmed_enemy), "an unarmed enemy attack must not trigger sword defense")

	# Exercise the actual enemy damage entry point: the overlap must be checked
	# before receive_attack, while a non-attacking player still takes the strike.
	player.global_position = Vector3.ZERO
	armed_enemy.global_position = Vector3(0.0, 0.0, -1.7)
	armed_enemy.rotation.y = PI
	_align_blades(player, armed_enemy)
	player.health = DungeonPlayer.MAX_HEALTH
	player.blocking = false
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	armed_enemy.state_time = DungeonEnemy.ATTACK_HIT_TIME
	armed_enemy._resolve_active_attack()
	_check(is_equal_approx(player.health, DungeonPlayer.MAX_HEALTH), "enemy attack resolution must skip damage when the sword models clash")
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "enemy-side clash resolution must cancel the player attack")
	_check(armed_enemy.ai_state == DungeonEnemy.AIState.STAGGER, "enemy-side clash resolution must stagger the enemy")

	player.health = DungeonPlayer.MAX_HEALTH
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	armed_enemy.state_time = DungeonEnemy.ATTACK_HIT_TIME
	armed_enemy._resolve_active_attack()
	_check(is_equal_approx(player.health, DungeonPlayer.MAX_HEALTH - armed_enemy.attack_damage), "an inactive player sword must not block normal enemy damage")
	var health_after_connected_attack := player.health
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	_check(not player.try_sword_clash(armed_enemy), "a sword overlap after enemy damage must not retroactively become a defense")
	_check(is_equal_approx(player.health, health_after_connected_attack), "late sword overlap must not rewrite already-applied damage")
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "late sword overlap must not show a false recovery response")

	# A spatially missed attack is resolved only once, but its still-rendered
	# blade remains eligible for a later clash during the same active swing.
	player.health = DungeonPlayer.MAX_HEALTH
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	armed_enemy.rotation.y = 0.0
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	armed_enemy.state_time = DungeonEnemy.ATTACK_HIT_TIME
	armed_enemy._resolve_active_attack()
	_check(armed_enemy.attack_has_resolved and not armed_enemy.attack_has_connected, "a missed enemy attack must resolve without reporting a connection")
	_check(armed_enemy.is_sword_attack_active(), "a missed enemy sword must remain clashable through the visible active swing")
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	_align_blades(player, armed_enemy)
	_check(player.try_sword_clash(armed_enemy), "a missed enemy swing must still clash if the rendered blades later overlap")

	# A rear sword wielder must not delay a normal forward player hit.
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	armed_enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	armed_enemy.global_position = Vector3(0.0, 0.0, 1.7)
	await physics_frame
	_check(not player._has_active_sword_opponent_in_melee_path(), "a rear active sword must not extend the forward player attack timing")
	armed_enemy.global_position = Vector3(0.0, 0.0, -1.7)
	await physics_frame
	_check(player._has_active_sword_opponent_in_melee_path(), "an active sword inside the actual forward melee path must receive the short clash grace window")

	_finish()


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
	enemy.global_position = Vector3(0.1, floor_height, -1.7)
	enemy.rotation.y = PI
	player.attack_hit_ids.clear()
	player.attack_charge = 0.0
	player.health = DungeonPlayer.MAX_HEALTH
	var enemy_health_before := enemy.health
	player._set_combat_state(DungeonPlayer.CombatState.WINDUP)
	player._update_viewmodel(1.0)
	enemy._set_state(DungeonEnemy.AIState.WINDUP)
	enemy._update_weapon_pose(1.0)
	enemy._update_visual_pose(1.0)
	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	for frame in range(12):
		player._update_combat(1.0 / 60.0)
		player._update_viewmodel(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if OS.get_environment("SWORD_CLASH_TRACE") == "1": print("CLASH FRAME ", frame, " PLAYER ", player.get_sword_clash_proxy(), " ENEMY ", enemy.get_sword_clash_proxy())
		player._resolve_active_attack()
		enemy._resolve_active_attack()
		if player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER:
			break
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "natural simultaneous swing animation must reach a sword clash before the player body hit")
	_check(enemy.ai_state == DungeonEnemy.AIState.STAGGER, "natural simultaneous swing animation must stagger the armed enemy")
	_check(is_equal_approx(player.health, DungeonPlayer.MAX_HEALTH), "natural simultaneous swing clash must prevent enemy damage")
	_check(is_equal_approx(enemy.health, enemy_health_before), "natural simultaneous swing clash must prevent player damage")


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
