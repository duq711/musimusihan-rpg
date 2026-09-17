extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://boot.tscn", "project must start at the threaded loading boot scene")
	_check(not ResourceLoader.exists("res://launcher.tscn"), "removed mode launcher must stay absent")
	_check(not ResourceLoader.exists("res://turn_based.tscn"), "removed turn-based scene must stay absent")
	_check(not InputMap.has_action("mode_select"), "removed mode-select input must stay absent")
	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "main.tscn must load")
	if packed == null:
		_finish()
		return

	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame

	var player := get_first_node_in_group("player") as DungeonPlayer
	var enemies := get_nodes_in_group("enemy")
	var traps := get_nodes_in_group("trap")
	_check(player != null, "player must spawn")
	_check(enemies.size() == 2, "two enemies must spawn")
	_check(traps.size() == 2, "two traps must spawn")
	_check(game.enemies_alive == 2, "game must track both enemies")
	if player == null or enemies.is_empty() or traps.is_empty():
		_finish()
		return
	_check(player.shield_pivot != null, "first-person shield model must spawn")
	_check(player.torch_pivot != null and player.torch_flame != null, "equipped torch model must spawn")
	_check(player.torch != null and player.torch_fill != null, "torch forward and fill lights must spawn")
	_check(player.torch_enabled and player.torch.visible and player.torch_fill.visible, "equipped torch must start lit")
	player.toggle_torch()
	_check(not player.torch_enabled and not player.torch.visible and not player.torch_fill.visible, "torch toggle must extinguish both lights")
	player.toggle_torch()
	_check(player.torch_enabled and player.torch.visible and player.torch_fill.visible, "torch toggle must relight both lights")

	# Directional guard: a strike arriving from the viewed direction during the
	# first 0.2 seconds is a parry and must not reduce health.
	var initial_health := player.health
	player.blocking = true
	player.block_time = 0.1
	var front := -player.global_transform.basis.z
	var parry_result := player.receive_attack(20.0, player.global_position + front * 1.5)
	_check(bool(parry_result.get("parried", false)), "front attack in parry window must parry")
	_check(is_equal_approx(player.health, initial_health), "parry must prevent health damage")

	# A normal environment hit bypasses guard and updates the health model.
	player.blocking = false
	player.receive_environment_damage(5.0, "test")
	_check(is_equal_approx(player.health, initial_health - 5.0), "environment damage must reduce health")

	# A held shield fully blocks the front arc while still spending stamina.
	var health_before_block := player.health
	player.stamina = 100.0
	player.blocking = true
	player.block_time = 0.4
	var block_result := player.receive_attack(20.0, player.global_position + front * 1.5)
	_check(bool(block_result.get("blocked", false)), "raised shield must block a frontal strike")
	_check(not bool(block_result.get("parried", false)), "late guard must be a block, not a just guard")
	_check(is_equal_approx(player.health, health_before_block) and is_zero_approx(float(block_result.damage)), "held shield must fully prevent frontal health damage")
	_check(player.stamina < 100.0, "shield block must spend stamina")

	var health_before_rear := player.health
	player.blocking = true
	player.block_time = 0.4
	var rear_result := player.receive_attack(10.0, player.global_position - front * 1.5)
	_check(not bool(rear_result.get("blocked", false)), "shield must not block a rear strike")
	_check(is_equal_approx(player.health, health_before_rear - 10.0), "rear strike must deal full damage")
	player.blocking = false

	# Combat state must enter windup and consume stamina when committed.
	var stamina_before := player.stamina
	player._try_begin_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.WINDUP, "attack must enter windup")
	player.state_time = 0.24
	player.attack_release_requested = true
	player._update_combat(0.01)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "released attack must enter active state")
	_check(player.stamina < stamina_before, "committed attack must consume stamina")
	player._set_combat_state(DungeonPlayer.CombatState.READY)

	# Trap interaction must wait for the timed inspection before the minigame.
	var trap := traps[0] as RuneTrap
	var safe_value := (trap.success_start + trap.success_end) * 0.5
	_check(trap.is_value_in_success_zone(safe_value), "trap green zone must accept its midpoint")
	trap.interact(player)
	_check(trap.state == RuneTrap.TrapState.INSPECTING, "trap interaction must start timed inspection")
	_check(player.is_timed_interacting(), "trap inspection must use the player's timed interaction")
	player.advance_timed_interaction(RuneTrap.INSPECT_DURATION * 0.5)
	_check(trap.state == RuneTrap.TrapState.INSPECTING, "trap minigame must stay closed before inspection completes")
	player.advance_timed_interaction(RuneTrap.INSPECT_DURATION)
	_check(trap.state == RuneTrap.TrapState.DISARMING, "completed inspection must start trap minigame")
	trap.needle_value = safe_value
	trap.confirm_disarm()
	await process_frame
	_check(trap.state == RuneTrap.TrapState.DISARMED, "green-zone confirm must disarm trap")
	_check(game.traps_disarmed == 1, "game must count successful disarm")

	# Enemy death must feed the extraction/loot loop.
	var enemy := enemies[0] as DungeonEnemy
	enemy.receive_hit(999.0, player.global_position, 1.0, true)
	await process_frame
	_check(enemy.ai_state == DungeonEnemy.AIState.DEAD, "lethal hit must kill enemy")
	_check(game.enemies_alive == 1, "game must decrement living enemy count")
	_check(game.loot_count >= 2, "enemy and trap rewards must enter raid loot count")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("SMOKE TEST PASS: combat, guard, torch, trap, loot, and scene bootstrap")
		quit(0)
		return
	for failure in failures:
		push_error("SMOKE TEST FAIL: %s" % failure)
	quit(1)
