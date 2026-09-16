extends SceneTree
const ORC := preload("res://scripts/orc_enemy.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room); current_scene = room
	await process_frame
	room.set_process(false)
	check(room.feature_entries.filter(func(e): return e.id == "orc" and e.action == "orc").size() == 1, "one executable orc catalog entry")
	room.run_feature("orc")
	var orc = find_orc(room)
	check(orc != null, "actual production orc spawned")
	if orc != null:
		orc.set_physics_process(false); room.player.set_physics_process(false)
		await physics_frame
		check(room.enemies_alive == 1 and room.enemy_ai_enabled and not room.panel_open, "trial is a live duel")
		check(orc.target == room.player and orc.game == room and orc.hud == room.hud, "AI/reward wiring")
		check(orc.skeleton.get_bone_count() > 100 and orc.visual_meshes.size() > 10, "actual supplied skinned mesh and bones")
		check(orc.animation_player.get_animation_list().size() == 12, "all twelve supplied clips retained")
		var b: int = orc.skeleton.find_bone("ork_RightHand")
		orc._set_state(DungeonEnemy.AIState.IDLE);orc.state_time=.2;orc._update_visual_pose(0)
		var hand: Transform3D=orc.skeleton.get_bone_global_pose(b)
		orc._set_state(DungeonEnemy.AIState.CHASE);orc.state_time=.4;orc._update_visual_pose(0)
		check(orc.animation_clip == "run" and not hand.is_equal_approx(orc.skeleton.get_bone_global_pose(b)), "source animation actually moves the rig")
		for attack in 3:
			orc._set_state(DungeonEnemy.AIState.WINDUP);orc.state_time=.7;orc._update_visual_pose(0)
			var end: float=orc.animation_sample
			check(orc.animation_clip == ORC.ATTACKS[attack], "three attack clips cycle")
			orc._set_state(DungeonEnemy.AIState.ACTIVE)
			check(is_equal_approx(end,orc.animation_sample), "windup to active sample continuity")
			orc.state_time=.09;orc._update_visual_pose(0)
			check(is_equal_approx(orc.animation_sample, orc.animation_player.get_animation(orc.animation_clip).length * ORC.STRIKE_TIMES[orc.animation_clip].y), "hit occurs on the inspected source strike frame")
			orc.state_time=.24;orc._update_visual_pose(0);end=orc.animation_sample
			orc._set_state(DungeonEnemy.AIState.RECOVERY)
			check(is_equal_approx(end,orc.animation_sample), "active to recovery sample continuity")
		orc.global_position = room.player.global_position - room.player.global_basis.z * 1.5
		orc.rotation.y = room.player.rotation.y + PI
		await physics_frame
		room.player.advance_combat_state(.4,true)
		var hp: float=room.player.health
		orc._set_state(DungeonEnemy.AIState.ACTIVE);orc.state_time=.09;orc._resolve_active_attack()
		check(orc.attack_has_resolved and orc.attack_has_connected and room.player.health == hp, "actual axe hit is blocked by the real shield")
		room.player.advance_combat_state(.01,false);room.player.advance_combat_state(.01,true)
		orc._set_state(DungeonEnemy.AIState.ACTIVE);orc.state_time=.09;orc._resolve_active_attack()
		check(orc.ai_state == DungeonEnemy.AIState.STAGGER and orc.animation_clip == "gethit", "just guard interrupts orc and plays hit reaction")
		room.player.advance_combat_state(.3,false)
		orc._set_state(DungeonEnemy.AIState.ACTIVE);orc.state_time=.09;orc._resolve_active_attack()
		check(room.player.health < hp, "unguarded attack damages player")
		orc.receive_hit(10,room.player.global_position,0,false)
		check(orc.health == orc.max_health-10 and orc.animation_clip == "gethit", "player damage and source hit clip")
		var loot: int=room.loot_count
		orc.receive_hit(1000,room.player.global_position,0,false)
		check(orc.ai_state == DungeonEnemy.AIState.DEAD and orc.animation_clip == "death" and orc.collision_layer == 0, "death disables attack/collision and starts authored death")
		check(room.enemies_alive == 0 and room.loot_count == loot+1, "death triggers actual reward and encounter completion")
		orc._physics_process(6)
		check(is_equal_approx(orc.animation_sample,orc.animation_player.get_animation("death").length), "death finishes and holds final frame")
		orc.receive_hit(1000,Vector3.ZERO,0,false)
		check(room.loot_count == loot+1,"death reward occurs only once")
		room._show_test_panel();check(paused,"F2 pauses trial")
		room.run_feature("orc");var fresh=find_orc(room)
		check(fresh != orc and fresh.health == fresh.max_health and room.player.health == room.player.MAX_HEALTH,"reselection respawns orc and heals player")
		room._show_test_panel();room._refresh_targets()
		check(find_orc(room) == null and room.enemies_alive == 2,"reset restores default encounters")
	room.suspend_stress_effects();room.queue_free();current_scene=null;paused=false
	await process_frame
	sandbox.finish()
	check(ExpeditionSession.capture_snapshot() == before and Input.mouse_mode == cursor,"original expedition and cursor restored")
	for f in failures:push_error(f)
	print("ORC ENEMY TEST "+("PASS" if failures.is_empty() else "FAIL")+": production skin, clips, combat, guard, hit, death, reward, repeat/reset and session restoration")
	quit(0 if failures.is_empty() else 1)
func find_orc(room):
	for n in room.get_children():
		if n is ORC and not n.is_queued_for_deletion():return n
	return null
