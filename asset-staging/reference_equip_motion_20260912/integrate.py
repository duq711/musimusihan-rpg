from pathlib import Path
import shutil
root=Path.cwd();game=root/'godot-game'
shutil.copy2(root/'asset-staging/reference_equip_motion_20260912/iteration_01/motion_manifest.json',game/'assets/animations/reference_sword_motion/motion_manifest.json')
p=game/'scripts/player.gd';s=p.read_text()
s=s.replace('var _motion_equip_elapsed := MOTION.EQUIP_DURATION','''var _motion_equip_elapsed := MOTION.EQUIP_DURATION
const SWORD_DRAW_DURATION := 1.5
var _sword_draw_elapsed := SWORD_DRAW_DURATION
var _draw_sword := false
var _draw_shield := false
var _displayed_offhand := ""''')
s=s.replace('''	if _displayed_weapon_type == weapon_type and _displayed_weapon_identity == identity:
		return''','''	var offhand := "" if inventory_model == null else str(inventory_model.equipment.get("offhand", ""))
	var weapon_changed := _displayed_weapon_type != weapon_type or _displayed_weapon_identity != identity
	var shield_added := offhand == "round_shield" and _displayed_offhand != offhand
	_displayed_offhand = offhand
	if not weapon_changed:
		if shield_added and _motion_initialized:
			begin_equipment_draw(false, true)
		return''')
s=s.replace('''	_refresh_magic_hud()


func _refresh_magic_hud()''','''	_refresh_magic_hud()
	_sword_draw_elapsed = SWORD_DRAW_DURATION
	if _motion_initialized and weapon_type == "melee" and not safe_zone_mode:
		begin_equipment_draw(true, _has_shield_equipped())


func begin_equipment_draw(sword: bool = true, shield: bool = true) -> bool:
	# Shared by actual inventory changes and the test-room replay. This is only
	# presentation: no item duplication, attack clock or stamina transaction.
	if not _has_melee_weapon_equipped() or safe_zone_mode or camping or not REFERENCE_MOTION.has_track("equip"):
		return false
	_draw_sword = sword
	_draw_shield = shield and _has_shield_equipped()
	if not _draw_sword and not _draw_shield: return false
	_sword_draw_elapsed = 0.0
	_motion_equip_elapsed = MOTION.EQUIP_DURATION
	_reference_pose_key = "draw"
	_reference_pose_handoff_active = false
	_reference_locomotion_valid = false
	_update_viewmodel(0.0)
	return true


func _equipment_draw_active() -> bool:
	return _sword_draw_elapsed < SWORD_DRAW_DURATION and _has_melee_weapon_equipped() and not safe_zone_mode and not camping and not chest_equipment_stowed


func _equipment_draw_reaching() -> bool:
	return _equipment_draw_active() and _draw_sword and _sword_draw_elapsed < 0.46


func _refresh_magic_hud()''')
s=s.replace('''	_motion_clock += delta
	_motion_equip_elapsed''','''	# Actions may interrupt presentation immediately; the existing pose handoff
	# blends from the actual drawn position without delaying gameplay contact.
	if combat_state != CombatState.READY or blocking or safe_zone_mode or camping:
		_sword_draw_elapsed = SWORD_DRAW_DURATION
	else:
		_sword_draw_elapsed = minf(SWORD_DRAW_DURATION, _sword_draw_elapsed + delta)
	_motion_clock += delta
	_motion_equip_elapsed''')
s=s.replace('var reference_locomotion := reference_enabled and phase == "ready"','var reference_locomotion := reference_enabled and not _equipment_draw_active() and phase == "ready"')
s=s.replace('''	target.origin += movement.position
	target.basis = target.basis * Basis.from_euler(movement.rotation)''','''	if _equipment_draw_active():
		movement.position = Vector3.ZERO
		movement.rotation = Vector3.ZERO
		if _draw_sword:
			target = REFERENCE_MOTION.sample("equip", _sword_draw_elapsed)
			_reference_arm_target = REFERENCE_MOTION.sample_right_arm("equip", _sword_draw_elapsed)
	target.origin += movement.position
	target.basis = target.basis * Basis.from_euler(movement.rotation)''')
s=s.replace('''		if reference_enabled:
			shield_pivot.transform''','''		if _equipment_draw_active() and _draw_shield:
			shield_target = REFERENCE_MOTION.sample("equip", _sword_draw_elapsed, "shield")
		if reference_enabled:
			shield_pivot.transform''')
s=s.replace('''	var key := ("guard" if guard_owned else "locomotion") if phase == "ready" else phase''','''	var key := ("guard" if guard_owned else "locomotion") if phase == "ready" else phase
	if _equipment_draw_active(): key = "draw"''')
s=s.replace('''		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping''','''		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping and not _equipment_draw_reaching()''')
s=s.replace('''		right_relaxed_arm.visible = (safe_zone_mode or _equipped_weapon_type() == "unarmed")''','''		right_relaxed_arm.visible = (safe_zone_mode or _equipped_weapon_type() == "unarmed" or _equipment_draw_reaching())''')
s=s.replace('''		right_relaxed_arm.call("set_relaxed_pose", 0.0)
	for arm:''','''		right_relaxed_arm.call("set_relaxed_pose", 0.0)
		if _equipment_draw_reaching():
			var t := _sword_draw_elapsed
			var reach := Vector3(0.30, -0.25, -0.48).lerp(Vector3(0.08, -0.18, -0.48), MOTION.smooth_phase(t / 0.12))
			reach = reach.lerp(Vector3(-0.04, -0.72, -0.30), MOTION.smooth_phase((t - 0.14) / 0.26))
			_place_hand_contact(right_relaxed_arm, camera.to_global(reach), camera.global_basis * Basis.from_euler(Vector3(0.75, -0.65, 0.40)), "draw_reach")
			right_relaxed_arm.call("set_relaxed_pose", 0.85)
	for arm:''')
s=s.replace('"equip_progress": _motion_equip_elapsed / MOTION.EQUIP_DURATION,','"equip_progress": _motion_equip_elapsed / MOTION.EQUIP_DURATION, "sword_draw_progress": _sword_draw_elapsed / SWORD_DRAW_DURATION, "sword_draw_active": _equipment_draw_active(), "sword_draw_reaching": _equipment_draw_reaching(),')
p.write_text(s)
p=game/'scripts/test_room_catalog.gd';s=p.read_text();line='\t\t_entry("motion_sword_draw", "기본", "영상 참고 검·방패 꺼내기", "아래로 손 뻗기 → 비스듬히 발검 → 검 세우기와 방패 들기 · F2 재선택으로 반복 · LMB/RMB 전환 확인", "reference_sword_motion", "draw"),\n';s=s.replace('\t\t_entry("motion_sword_run",',line+'\t\t_entry("motion_sword_run",');p.write_text(s)
p=game/'scripts/test_room.gd';s=p.read_text();s=s.replace('''	var guide := str({
		"run":''','''	if family == "draw":
		player.begin_equipment_draw(true, true)
	else:
		player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	var guide := str({
		"draw": "아래로 손 뻗기 → 비스듬히 검 뽑기 → 검·방패 대기 · LMB/RMB 전환 · F2 재선택으로 다시 꺼내기",
		"run":''');p.write_text(s)
