extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const DATA := preload("res://scripts/reference_sword_motion.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))
func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	for clip in DATA.ATTACK_CLIPS:
		var end: float = DATA.clip_metadata(clip).duration_seconds
		var start := end - .12
		var previous := DATA.sample(clip, start)
		var shortest := _angle(previous, DATA.sample(clip, end))
		var travel := 0.0
		for i in 48:
			var current := DATA.sample(clip, start + .12 * float(i + 1) / 48.0)
			travel += _angle(previous, current); previous = current
		_check(travel < shortest + 2.0, "recovery must take the short arc, without an extra revolution: " + clip + " travel=" + str(travel))
	var viewport := PREVIEW.create_viewport();root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var p: DungeonPlayer = fixture.player
	p.set_physics_process(false);p.set_process_unhandled_input(false)
	await process_frame
	for paired in [true, false]:
		for clip in (DATA.ATTACK_CLIPS if paired else ["right_diagonal"]):
			p.cancel_sword_attack();p.reset_shield_carry();p.stamina=p.MAX_STAMINA
			p._sword_draw_elapsed=p.SWORD_DRAW_DURATION;p._update_viewmodel(.4)
			if not paired:
				p.request_primary_weapon();p._update_viewmodel(1.1)
			_check(p.begin_sword_attack(clip).accepted, "real attack must start")
			var previous := p.weapon_pivot.transform
			var was_recovery := false
			var recovered := false
			var peak_angle := 0.0
			var boundary_step := 0.0
			for frame in 105:
				if frame == 27: p.attack_release_requested=true
				p.advance_combat_state(1.0/60.0,false);p._update_viewmodel(1.0/60.0);p._resolve_active_attack()
				var current := p.weapon_pivot.transform
				if p.combat_state == p.CombatState.RECOVERY:
					peak_angle=maxf(peak_angle,_angle(previous,current));was_recovery=true
				elif was_recovery and p.combat_state == p.CombatState.READY:
					boundary_step=current.origin.distance_to(previous.origin);was_recovery=false;recovered=true
				previous=current
			_check(recovered, "real attack must complete active and recovery phases")
			_check(peak_angle < 20.0, "recovery angular spike: " + clip + " " + str(peak_angle))
			_check(boundary_step < .02, "recovery-to-idle position jump: " + clip + " " + str(boundary_step))
			print("RECOVERY METRIC ",paired," ",clip," peak_deg=",peak_angle," boundary_m=",boundary_step)
	viewport.queue_free();await process_frame
	_check(ExpeditionSession.capture_snapshot()==original and Input.mouse_mode==cursor,"preserve expedition and cursor")
	for message in failures: push_error(message)
	print("SWORD RECOVERY CONTINUITY %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
