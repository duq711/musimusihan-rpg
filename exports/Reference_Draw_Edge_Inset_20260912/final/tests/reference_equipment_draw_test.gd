extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const REF := preload("res://scripts/reference_sword_motion.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var p: DungeonPlayer = fixture.player
	var bag: ExpeditionInventory = fixture.inventory
	p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	p.set_torch_enabled(false)
	await process_frame
	_check(REF.has_right_arm("equip") and REF.has_track("equip", "shield"), "draw must contain actual sword/shield and right-arm samples")
	# Real inventory signal, not an assigned animation clock, starts the draw.
	bag.unequip("weapon")
	var slot := -1
	for i in bag.slots.size():
		if str(bag.slots[i].get("id", "")) == "rusted_sword": slot = i; break
	_check(slot >= 0 and bool(bag.equip_from_slot(slot).get("accepted", false)), "inventory must equip the actual sword")
	_check(p._equipment_draw_active() and p._sword_draw_elapsed == 0.0, "real equipment change must start draw exactly once")
	p._update_viewmodel(.1)
	bag.add_item("wooden_arrow", 1)
	_check(is_equal_approx(p._sword_draw_elapsed, .1), "unrelated inventory events must not restart an advancing draw")
	var stamina := p.stamina
	var aim := p.camera.transform
	var max_upper := 0.0
	for i in 181:
		p._update_viewmodel(1.0/120.0)
		var state := p.get_first_person_motion_snapshot()
		_check(state.hand_contacts.sword.error < .00001, "sword grip must remain rigid throughout draw")
		if state.joint_landmarks.has("shield"):
			max_upper = maxf(max_upper, state.joint_landmarks.shield.upper_length)
			_check(state.hand_contacts.shield.error < .00001, "shield grip must remain on its handle")
		var arm: Dictionary = state.joint_landmarks.sword
		_check(absf(arm.upper_length-.34)<.004 and absf(arm.forearm_length-.26)<.004, "draw right arm must retain anatomical segment lengths")
		if state.joint_landmarks.has("draw_reach"):
			var reaching: Dictionary = state.joint_landmarks.draw_reach
			_check(absf(reaching.upper_length-.34)<.001 and absf(reaching.forearm_length-.26)<.001, "every reaching frame must preserve both arm segment lengths")
		if i == 15:
			_check(p.right_relaxed_arm.visible and not p.weapon_arm.visible, "reaching phase must show one open right hand")
			_check(not p._draw_reach_overrides.is_empty(), "reaching glove material must be isolated to the temporary right hand")
			var back := p.camera.global_basis.inverse() * p.right_relaxed_arm.global_basis.y
			_check(back.z > .80, "draw must show broad hand back toward camera instead of its edge")
			var joints: Dictionary = state.joint_landmarks.draw_reach
			_check(joints.upper_length < .50 and absf(joints.forearm_length-.26)<.001, "reaching sleeve must keep natural segment lengths")
			_check((joints.elbow-joints.wrist).normalized().dot(p.right_relaxed_arm.global_basis.z)>.99, "forearm must continue along the reaching wrist")
			var time := p._sword_draw_elapsed
			paused = true
			p._update_viewmodel(.5)
			_check(p._sword_draw_elapsed == time, "pause must freeze equip clock")
			paused = false
	_check(not p._equipment_draw_active() and not p.right_relaxed_arm.visible and p.weapon_arm.visible, "closed grip must replace the hidden reaching hand and settle")
	_check(p._draw_reach_overrides.is_empty(), "temporary glove overrides must be restored after draw")
	_check(p.weapon_pivot.basis.y.dot(Vector3.UP)>.97 and p.weapon_pivot.transform.origin.distance_to(REF.sample("idle",0).origin)<.005, "draw must return to the existing idle")
	_check(p.stamina==stamina and p.camera.transform.is_equal_approx(aim), "presentation must not spend stamina or alter aim")
	print("DRAW MAX SHIELD UPPER ",max_upper)
	_check(max_upper < .50, "shield upper sleeve must not stretch during draw")
	# The real reaching wrist must travel down-left throughout, without a hold
	# or an initial lift toward the middle of the screen.
	p.begin_equipment_draw()
	var last_wrist := p.camera.to_local(p.right_relaxed_arm.global_position)
	var reached_visible_left_inset := false
	for i in 25:
		p._update_viewmodel(.018)
		var wrist := p.camera.to_local(p.right_relaxed_arm.global_position)
		_check(wrist.x < last_wrist.x - .0001 and wrist.y < last_wrist.y - .0001, "every reaching interval must move the actual wrist left and down without stopping or reversing")
		last_wrist = wrist
		var palm: Vector3 = p.get_first_person_motion_snapshot().hand_contacts.draw_reach.actual
		var screen := p.camera.unproject_position(palm) / p.camera.get_viewport().get_visible_rect().size
		if screen.x < .20 and screen.x > .05 and screen.y > .0 and screen.y < 1.0:
			reached_visible_left_inset = true
	_check(reached_visible_left_inset, "palm must pass just inside the left edge before disappearing below the frame")
	_check(last_wrist.x < -.15 and last_wrist.y < -.60, "reach must finish at the left hip below frame")
	p._update_viewmodel(.07)
	var drawn_grip := p.camera.to_local(p.get_first_person_motion_snapshot().hand_contacts.sword.actual)
	_check(drawn_grip.x < -.45 and drawn_grip.y < -.25, "the held sword must start being drawn from the same inset lower-left position")
	# Sample the rendered hand's actual rig, not only the curve function.
	var fingers: Dictionary = {}
	p.begin_equipment_draw()
	var previous_time := 0.0
	for sample_time: float in [0.0, .09, .17, .24, .36]:
		p._update_viewmodel(sample_time - previous_time)
		fingers[sample_time] = p.right_relaxed_arm.call("get_joint_snapshot").flexion.duplicate(true)
		previous_time = sample_time
	for digit: String in ["little", "ring", "middle", "index"]:
		_check(fingers[.09][digit].y < fingers[0.0][digit].y - .25, "reach must open the actual %s finger before grasp" % digit)
		_check(fingers[.36][digit].x > fingers[.09][digit].x + .40, "grasp must curl the actual %s knuckle, not just its tip" % digit)
		_check(fingers[.36][digit].z > fingers[.09][digit].z + .20, "grasp must curl the actual %s fingertip" % digit)
	_check(fingers[.17].little.x > fingers[.17].ring.x and fingers[.17].ring.x > fingers[.17].middle.x and fingers[.17].middle.x > fingers[.17].index.x, "fingers must begin wrapping little-to-index instead of closing in unison")
	_check(fingers[.17].thumb.x < .02 and fingers[.24].thumb.x > .10, "thumb must follow the initial finger curl to secure the hilt")
	var paused_fingers: Dictionary = p.right_relaxed_arm.call("get_joint_snapshot").flexion.duplicate(true)
	paused = true; p._update_viewmodel(.3)
	_check(p.right_relaxed_arm.call("get_joint_snapshot").flexion == paused_fingers, "pause must freeze the actual finger pose")
	paused = false
	p.begin_equipment_draw()
	for i in 36: p._update_viewmodel(.01)
	var replay: Dictionary = p.right_relaxed_arm.call("get_joint_snapshot").flexion
	for digit: String in replay:
		_check((replay[digit] as Vector3).is_equal_approx(fingers[.36][digit]), "replaying at another frame rate must reproduce the actual %s pose" % digit)
	p._update_viewmodel(2.0)
	# Adding the shield uses its own draw track without replaying the sword.
	bag.unequip("offhand")
	var shield_slot := -1
	for i in bag.slots.size():
		if str(bag.slots[i].get("id", "")) == "round_shield": shield_slot = i; break
	_check(shield_slot >= 0 and bool(bag.equip_from_slot(shield_slot).get("accepted",false)), "actual inventory must equip the shield")
	_check(p._equipment_draw_active() and not p._draw_sword and p._draw_shield, "offhand-only equipment change must not replay sword draw")
	p._update_viewmodel(.7)
	_check(p.weapon_pivot.transform.origin.distance_to(REF.sample("idle",0).origin)<.005, "sword must stay in carry during shield-only draw")
	p._update_viewmodel(1)
	p.begin_equipment_draw();p._update_viewmodel(.75)
	var single_step := p.weapon_pivot.transform
	p.begin_equipment_draw()
	for i in 90: p._update_viewmodel(1.0/120.0)
	_check(p.weapon_pivot.transform.is_equal_approx(single_step), "draw sampling must be independent of render update rate")
	p._update_viewmodel(1)
	for t in [.12,.60,1.15]:
		p.cancel_sword_attack(); p.blocking=false
		p.begin_equipment_draw()
		p._update_viewmodel(t)
		var before := p.weapon_pivot.transform
		_check(p.begin_sword_attack("right_diagonal").accepted, "draw must allow real attack interruption")
		p._update_viewmodel(0.0)
		_check(not p._equipment_draw_active() and p.weapon_pivot.transform.is_equal_approx(before), "attack handoff must begin at preceding draw pose")
	p.cancel_sword_attack(); p.begin_equipment_draw(); p._update_viewmodel(.75)
	var before_guard := p.weapon_pivot.transform
	p.blocking = true
	p._update_viewmodel(0)
	_check(not p._equipment_draw_active() and p.weapon_pivot.transform.is_equal_approx(before_guard), "guard interrupt must preserve initial draw pose")
	p.blocking=false;p.cancel_sword_attack();p.begin_equipment_draw();p._update_viewmodel(.5)
	bag.unequip("weapon");p._update_viewmodel(.02)
	_check(not p._equipment_draw_active() and not p.sword_visual_root.visible, "removing weapon cancels draw and hides weapon")
	viewport.queue_free();await process_frame
	_check(ExpeditionSession.capture_snapshot()==snapshot and Input.mouse_mode==cursor, "draw tests preserve session and cursor")
	for f in failures:push_error(f)
	print("REFERENCE EQUIPMENT DRAW %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
