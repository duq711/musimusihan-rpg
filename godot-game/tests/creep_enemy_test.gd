extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const WARDEN := preload("res://scripts/enemy.gd")
const SOURCE_CLIPS := ["idle", "walk", "bite", "punch", "hit", "death"]

var failures: Array[String] = []
var asset_checks_executed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Give the isolated trial a real inventory to preserve, including identity.
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	var original_slots := original.slots.duplicate(true)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 61.0
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	_check(sandbox.active and room.inventory != original, "trial owns a separate expedition and inventory")
	_check(room.feature_entries.filter(func(entry): return entry.id == "creep" and entry.action == "creep").size() == 1, "one executable Creep catalog entry")
	room.run_feature("creep")
	if CREEP.is_available():
		await _test_installed_asset(room)
	else:
		_test_missing_asset(room)
	_check(original.slots == original_slots, "Creep trial rewards and loadout changes leave original bag untouched")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "trial exit restores exact original expedition and inventory identity")
	_check(Input.mouse_mode == cursor, "trial exit preserves cursor mode")
	for failure in failures:
		push_error("CREEP ENEMY TEST FAIL: " + failure)
	var coverage := "installed rig, source clips, timed contacts, shield/parry, death rewards, repeat/reset, session restoration" if asset_checks_executed else "missing-asset fallback, catalog notice, reset and session restoration; asset-dependent checks SKIPPED"
	print("CREEP ENEMY TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + coverage)
	quit(0 if failures.is_empty() else 1)


func _test_missing_asset(room) -> void:
	print("CREEP ASSET CHECKS SKIPPED: licensed model is not installed; testing public-clone fallback instead.")
	_check(_find_creep(room) == null, "missing asset must not instantiate an unusable Creep")
	_check(room.panel_open and paused and room.enemies_alive == 2, "missing asset keeps the menu open and preserves existing trial encounters")
	_check(not room.status_label.text.is_empty() and (room.status_label.text.contains("설치") or room.status_label.text.contains("에셋")), "missing asset gives an actionable installation notice")
	var previous_count: int = room.enemies_alive
	room._spawn_enemy("Creep fallback check", Vector3(0, 1, -3), 82, 21, 2.2, Color.WHITE, "", "creep")
	var fallback: DungeonEnemy
	for actor in room.get_children():
		if actor is DungeonEnemy and actor.display_name == "Creep fallback check":
			fallback = actor
	_check(fallback != null and fallback.get_script() == WARDEN and is_instance_valid(fallback.model_root), "production factory supplies a real warden when licensed Creep is unavailable")
	_check(room.enemies_alive == previous_count + 1, "missing asset fallback still contributes one real encounter")
	room._show_test_panel()
	room._refresh_targets()
	_check(_find_creep(room) == null and room.enemies_alive == 2, "missing-asset trial remains resettable to the default encounters")


func _test_installed_asset(room) -> void:
	var creep = _find_creep(room)
	_check(creep != null, "fixture spawns the actual production Creep")
	if creep == null:
		return
	asset_checks_executed = true
	creep.set_physics_process(false)
	room.player.set_physics_process(false)
	await physics_frame
	_check(room.enemies_alive == 1 and room.enemy_ai_enabled and not room.panel_open, "trial starts a live one-enemy duel")
	_check(creep.target == room.player and creep.game == room and creep.hud == room.hud, "Creep is wired to actual player combat and encounter rewards")
	_test_source_model(creep)
	_test_animation_continuity(creep)
	creep.global_position = room.player.global_position - room.player.global_basis.z * 1.2
	creep.rotation.y = room.player.rotation.y + PI
	await physics_frame
	_test_combat(room, creep)
	_test_death(room, creep)
	room._show_test_panel()
	_check(paused, "F2 menu pauses the Creep trial")
	room.run_feature("creep")
	var fresh = _find_creep(room)
	_check(fresh != null and fresh != creep and fresh.health == fresh.max_health and room.player.health == room.player.MAX_HEALTH, "reselection respawns Creep and restores player health")
	room._show_test_panel()
	room._refresh_targets()
	_check(_find_creep(room) == null and room.enemies_alive == 2, "reset removes Creep and restores the two default encounters")


func _test_source_model(creep) -> void:
	_check(is_instance_valid(creep.skeleton) and creep.skeleton.get_bone_count() > 20, "supplied model retains a usable skeleton")
	_check(not creep.visual_meshes.is_empty(), "supplied model contains actual 3D mesh surfaces")
	_check(is_instance_valid(creep.animation_player), "supplied model retains its AnimationPlayer")
	if not is_instance_valid(creep.skeleton) or not is_instance_valid(creep.animation_player):
		return
	for clip in SOURCE_CLIPS:
		_check(creep.animation_player.has_animation(clip), "source clip retained: " + clip)
		if creep.animation_player.has_animation(clip):
			var animation: Animation = creep.animation_player.get_animation(clip)
			_check(animation.length > 0.0 and animation.get_track_count() > 0, "source clip has real animation tracks: " + clip)
	var textured_surface := false
	var skinned_surface := false
	for mesh: MeshInstance3D in creep.visual_meshes:
		skinned_surface = skinned_surface or mesh.skin != null
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material is BaseMaterial3D:
				textured_surface = textured_surface or material.albedo_texture != null
	_check(skinned_surface and textured_surface, "game uses skinned geometry with the supplied color texture")
	creep._set_state(DungeonEnemy.AIState.IDLE)
	creep.state_time = 0.2
	creep._update_visual_pose(0.0)
	var idle_poses: Array[Transform3D] = []
	for bone in creep.skeleton.get_bone_count():
		idle_poses.append(creep.skeleton.get_bone_global_pose(bone))
	creep._set_state(DungeonEnemy.AIState.CHASE)
	creep.state_time = 0.4
	creep._update_visual_pose(0.0)
	var changed := false
	for bone in idle_poses.size():
		changed = changed or not idle_poses[bone].is_equal_approx(creep.skeleton.get_bone_global_pose(bone))
	_check(creep.animation_clip == "walk" and changed, "chasing actually deforms source bones rather than only changing a clip name")
	var snapshot: Dictionary = creep.get_creep_snapshot()
	_check(snapshot.archetype == "creep" and snapshot.source == CREEP.MODEL_PATH and snapshot.bones == creep.skeleton.get_bone_count(), "diagnostics report the installed production rig")


func _test_animation_continuity(creep) -> void:
	creep.attack_index = -1
	for cycle in 4:
		var index := cycle % 2
		creep._set_state(DungeonEnemy.AIState.WINDUP)
		_check(creep.attack_index == index and creep.animation_clip == CREEP.ATTACKS[index], "bite and punch alternate across repeated attack cycles")
		creep.state_time = CREEP.WINDUPS[index]
		creep._update_visual_pose(0.0)
		var previous: float = creep.animation_sample
		creep._set_state(DungeonEnemy.AIState.ACTIVE)
		_check(is_equal_approx(previous, creep.animation_sample), "windup-to-active preserves the source animation sample")
		creep.state_time = CREEP.ACTIVE_TIMES[index]
		creep._update_visual_pose(0.0)
		previous = creep.animation_sample
		creep._set_state(DungeonEnemy.AIState.RECOVERY)
		_check(is_equal_approx(previous, creep.animation_sample), "active-to-recovery preserves the source animation sample")
		creep.state_time = CREEP.RECOVERIES[index]
		creep._update_visual_pose(0.0)
		var duration: float = CREEP.WINDUPS[index] + CREEP.ACTIVE_TIMES[index] + CREEP.RECOVERIES[index]
		_check(is_equal_approx(creep.animation_sample, duration) and creep.animation_player.get_animation(CREEP.ATTACKS[index]).length >= duration, "attack recovery completes one source cycle without replaying subsequent attacks")


func _start_attack(creep, index: int) -> void:
	creep.attack_index = index - 1
	creep._set_state(DungeonEnemy.AIState.WINDUP)
	creep._set_state(DungeonEnemy.AIState.ACTIVE)


func _test_combat(room, creep) -> void:
	room._recover_player()
	room.player.advance_combat_state(0.4, true)
	var hp: float = room.player.health
	var stamina: float = room.player.stamina
	_start_attack(creep, 0)
	creep.state_time = 0.179
	creep._resolve_active_attack()
	_check(room.player.health == hp and room.player.stamina == stamina and not creep.attack_has_resolved, "bite cannot damage or consume guard stamina before its contact frame")
	creep.state_time = 0.18
	creep._resolve_active_attack()
	_check(creep.attack_has_resolved and creep.attack_has_connected and room.player.health == hp and room.player.stamina < stamina, "real shield blocks bite at the authored contact frame")
	stamina = room.player.stamina
	creep._resolve_active_attack()
	_check(room.player.stamina == stamina, "repeated evaluation cannot apply the same bite twice")
	room.player.advance_combat_state(0.01, false)
	room.player.advance_combat_state(0.01, true)
	_start_attack(creep, 1)
	creep.state_time = 0.06
	creep._resolve_active_attack()
	_check(creep.ai_state == DungeonEnemy.AIState.STAGGER and creep.animation_clip == "hit", "just guard interrupts the first punch and plays authored hit reaction")
	stamina = room.player.stamina
	creep.state_time = 0.34
	creep._resolve_active_attack()
	_check(room.player.health == hp and room.player.stamina == stamina, "interrupted punch cannot deliver its second contact")
	room._recover_player()
	room.player.advance_combat_state(0.3, false)
	_start_attack(creep, 1)
	creep.state_time = 0.06
	creep._resolve_active_attack()
	_check(is_equal_approx(hp - room.player.health, creep.attack_damage * 0.5) and creep.resolved_contacts == 1 and not creep.attack_has_resolved, "first unguarded punch deals half the configured encounter damage")
	var after_first: float = room.player.health
	creep.state_time = 0.339
	creep._resolve_active_attack()
	_check(room.player.health == after_first, "second punch cannot damage before its distinct contact frame")
	creep.state_time = 0.34
	creep._resolve_active_attack()
	_check(is_equal_approx(hp - room.player.health, creep.attack_damage) and creep.resolved_contacts == 2 and creep.attack_has_resolved, "both punches together deal exactly one configured attack's damage")
	var after_second: float = room.player.health
	creep._resolve_active_attack()
	_check(room.player.health == after_second, "second punch cannot apply damage twice")
	creep.state_time = 0.45
	creep._resolve_active_attack()
	_check(creep.ai_state == DungeonEnemy.AIState.RECOVERY and creep.animation_clip == "punch", "punch completes into its authored recovery")
	room._recover_player()
	room.player.advance_combat_state(0.3, false)
	_start_attack(creep, 0)
	creep.state_time = 0.18
	creep._resolve_active_attack()
	_check(is_equal_approx(hp - room.player.health, creep.attack_damage), "unguarded bite deals one configured attack's damage")
	_check(not creep.is_sword_attack_active(), "unarmed creature does not expose a nonexistent sword clash proxy")
	creep._set_state(DungeonEnemy.AIState.RECOVERY)
	creep.state_time = CREEP.RECOVERIES[0]
	creep._physics_process(0.001)
	_check(creep.ai_state == DungeonEnemy.AIState.WINDUP and creep.animation_clip == "punch", "close-range repeat goes directly to the next attack without a one-frame walk pose")
	creep._set_state(DungeonEnemy.AIState.STAGGER, 0.01)
	creep.state_time = creep.stagger_duration
	creep._physics_process(0.001)
	_check(creep.ai_state == DungeonEnemy.AIState.WINDUP and creep.animation_clip == "bite", "close-range hit recovery also avoids an intermediate walking pose")


func _test_death(room, creep) -> void:
	creep.receive_hit(10.0, room.player.global_position, 0.0, false)
	_check(creep.health == creep.max_health - 10.0 and creep.animation_clip == "hit", "player damage uses source hit reaction")
	var loot: int = room.loot_count
	creep.receive_hit(1000.0, room.player.global_position, 0.0, false)
	_check(creep.ai_state == DungeonEnemy.AIState.DEAD and creep.animation_clip == "death" and creep.collision_layer == 0 and creep.collision_mask == 0, "death disables attacks/collision and starts the authored death clip")
	_check(room.enemies_alive == 0 and room.loot_count == loot + 1, "actual death awards loot and releases the encounter seal")
	creep._physics_process(6.0)
	var end: float = creep.animation_player.get_animation("death").length
	_check(is_equal_approx(creep.animation_sample, end), "death reaches its authored final pose")
	creep._physics_process(2.0)
	_check(is_equal_approx(creep.animation_sample, end), "dead creature holds the final pose without looping")
	creep.receive_hit(1000.0, Vector3.ZERO, 0.0, false)
	_check(room.loot_count == loot + 1 and room.enemies_alive == 0, "repeated hits on corpse cannot duplicate rewards")


func _find_creep(room):
	for actor in room.get_children():
		if actor is CREEP and not actor.is_queued_for_deletion():
			return actor
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
