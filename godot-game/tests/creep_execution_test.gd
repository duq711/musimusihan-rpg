extends SceneTree
## Production leg loss, grounded recovery and player-owned downward stab.
## No fabricated crawl state, input injection or desktop camera is used.
const CREEP := preload("res://scripts/creep_enemy.gd")
const PARTS := preload("res://scripts/creep_dismemberment.gd")
const MOTION := preload("res://scripts/creep_execution_motion.gd")
const STANDING_MOTION := preload("res://scripts/sword_shield_execution_motion.gd")
const HELPERS := preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []
var view: SubViewport
var stage: Node3D
var player: DungeonPlayer
var actor
var defeats := 0
var report: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not CREEP.is_available() or not ResourceLoader.exists(PARTS.MODEL_PATH):
		print("CREEP EXECUTION TEST PASS: licensed Creep absent; rig/contact checks SKIPPED")
		quit(); return
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var source_hash := FileAccess.get_sha256(CREEP.MODEL_PATH)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	view = HELPERS.create_viewport()
	root.add_child(view)
	var fixture := HELPERS.populate_viewport(view)
	stage = fixture.stage
	player = fixture.player
	fixture.chest.position = Vector3(20, 0, 20)
	_add_floor()
	await _standing_regression()
	for legs: Array in [["left_leg"], ["right_leg"], ["left_leg", "right_leg"]]:
		if not await _prepare_crawler(legs):
			continue
		if legs.size() == 1 and legs[0] == "left_leg":
			await _gates_and_interruptions()
		await _complete_stab(legs)
	player.cancel_sword_attack()
	view.queue_free()
	await process_frame
	sandbox.finish()
	_check(before == ExpeditionSession.capture_snapshot(), "isolated execution restores original expedition and inventory")
	_check(cursor == Input.mouse_mode, "execution tests never change cursor mode")
	_check(source_hash == FileAccess.get_sha256(CREEP.MODEL_PATH), "execution preserves licensed source model bytes")
	var path := "res://artifacts/visual_qa/creep_execution"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var file := FileAccess.open(path + "/physics_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": report, "failures": failures}, "\t") + "\n")
	for failure in failures:
		push_error("CREEP EXECUTION TEST FAIL: " + failure)
	print("CREEP EXECUTION TEST %s: actual severance/grounded recovery, charge, immediate thrust, one strong deep-contact flinch, buried hold, planted pelvis/legs, one contact kill, missing limbs, ragdoll, cancellation, renderer/session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, .2, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.1
	stage.add_child(floor_body)


func _reset_player(shield_mode := "held") -> void:
	player.cancel_sword_attack()
	player.inventory_model.equipment.weapon = "rusted_sword"
	player.inventory_model.equipment.offhand = "" if shield_mode == "none" else "round_shield"
	player.inventory_model.changed.emit()
	player.reset_shield_carry()
	player._shield_stowed = shield_mode == "stowed"
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player.velocity = Vector3.ZERO
	player.blocking = false
	player.safe_zone_mode = false
	player.camping = false
	player.position = Vector3(0, .9, 0)
	player.rotation = Vector3.ZERO
	player._pitch = 0
	player.head.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
	ExpeditionSession.active_conditions.clear()
	player._update_viewmodel(.1)


func _aim_at_crawler(shield_mode := "held", distance := 1.5) -> void:
	_reset_player(shield_mode)
	var point: Vector3 = actor.get_aim_point()
	player.global_position = Vector3(point.x, actor.global_position.y, point.z + distance)
	player.head.look_at(point, Vector3.UP)
	player._pitch = player.head.rotation.x
	player._update_viewmodel(.1)
	actor.target = player
	actor.velocity = Vector3.ZERO
	actor.set_physics_process(false)
	actor._set_state(DungeonEnemy.AIState.IDLE)
	player.viewmodel_renderer.sync_view()


func _strike(region: String) -> void:
	actor.receive_located_hit(18.0, actor.global_position + Vector3(0, 0, -3), .5, false, actor.dismemberment.hit_point_for_region(region))


func _prepare_crawler(legs: Array) -> bool:
	_reset_player()
	if is_instance_valid(actor): actor.free()
	actor = CREEP.new()
	actor.max_health = 500
	actor.health = 500
	actor.position = Vector3(0, .9, -2)
	stage.add_child(actor)
	actor.set_physics_process(false)
	# No attack target until physical recovery finishes; no forced pose/state.
	actor.target = null
	defeats = 0
	actor.defeated.connect(func(_actor): defeats += 1)
	for frame in 3: await physics_frame
	_strike(legs[0])
	_check(not actor.is_crawling() and not actor.is_knocked_down(), "one ordinary leg hit cannot fabricate a crawl target")
	_strike(legs[0])
	_check(actor.knockdown_phase == "falling" and actor.ragdoll.temporary, "second localized hit starts the real living ragdoll")
	_check(not actor.is_execution_vulnerable() and not actor.begin_execution(player), "airborne/falling severed creature cannot be executed before ground recovery")
	actor.set_physics_process(true)
	var recovery_seen := false
	var finished := false
	for frame in 1200:
		await physics_frame
		if legs.size() == 2 and frame == 12:
			_strike(legs[1]); _strike(legs[1])
		if actor.knockdown_phase == "recovering":
			recovery_seen = true
			_check(not actor.is_execution_vulnerable(), "ground-pose recovery blend is still ineligible")
		if not actor.is_knocked_down() and actor.crawl.blend >= .999:
			finished = true
			break
	_check(recovery_seen and finished, str(legs) + ": real fall reaches grounded recovered crawl")
	if not finished: return false
	actor.set_physics_process(false)
	_check(actor.health > actor.max_health * .30 and defeats == 0, "high-health recovered crawler is living and has no premature reward")
	_check(actor.ragdoll.phase == "living" and actor.ragdoll.parts.is_empty(), "temporary ragdoll has handed control back before stab")
	_check(actor.get_execution_profile() == "crawl_stab", "recovered missing-leg creature selects downward stab choreography")
	_aim_at_crawler()
	await physics_frame
	await physics_frame
	return true


func _charge_release() -> bool:
	var started := player.begin_sword_attack()
	if not bool(started.accepted): return false
	player.advance_combat_state(STANDING_MOTION.CHARGE_SECONDS + .02)
	player.attack_release_requested = true
	player.advance_combat_state(.01)
	return player.is_execution_active()


func _standing_regression() -> void:
	_reset_player()
	actor = CREEP.new()
	actor.position = Vector3(0, .9, -1.4)
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.target = player
	actor.max_health = 100
	actor.health = 100
	actor._set_state(DungeonEnemy.AIState.STAGGER, 8.0)
	_check(not actor.is_execution_vulnerable(), "intact high-health Creep does not inherit crawler vulnerability")
	actor.health = 30
	_check(actor.is_execution_vulnerable() and actor.get_execution_profile() == "shield_cut", "standing low-health stagger retains original execution profile")
	await physics_frame
	await physics_frame
	_check(player.get_execution_target() == actor, "standing low-health stagger remains targetable with a shield")
	player._shield_stowed = true
	_check(player.get_execution_target() == null, "standing execution still requires the held shield")
	actor._set_state(DungeonEnemy.AIState.IDLE)
	_check(not actor.is_execution_vulnerable(), "standing low-health Creep still requires active stagger")
	actor.free()
	actor = null


func _gates_and_interruptions() -> void:
	for shield_mode: String in ["held", "stowed", "none"]:
		_aim_at_crawler(shield_mode)
		_check(actor.is_execution_vulnerable() and player.get_execution_target() == actor, "high-health idle crawler is targetable with shield mode: " + shield_mode)
		_check(_charge_release(), "real heavy release can reserve crawler with shield mode: " + shield_mode)
		_check(player.get_execution_snapshot().get("profile") == "crawl_stab", "player selects crawler stab with shield mode: " + shield_mode)
		player.prepare_for_inventory()
		_check(not player.is_execution_active() and actor.health > 0 and actor.ai_state != DungeonEnemy.AIState.EXECUTION, "inventory/F2 cancels both sides before impact")
	_aim_at_crawler()
	var before_hp: float = actor.health
	player.begin_sword_attack()
	player.attack_release_requested = true
	player.advance_combat_state(.05)
	_check(not player.is_execution_active(), "short click remains an ordinary sword attack")
	player.cancel_sword_attack()
	_check(actor.health == before_hp and defeats == 0, "no unconditional kill from a short click")
	_aim_at_crawler()
	player.stamina = STANDING_MOTION.STAMINA_COST - 1
	_check(not _charge_release() and actor.ai_state != DungeonEnemy.AIState.EXECUTION, "insufficient stamina cannot reserve or execute")
	_aim_at_crawler("held", 4.0)
	_check(player.get_execution_target() == null, "crawler beyond melee range cannot be targeted")
	for chest_distance: float in [.8, 1.8]:
		_aim_at_crawler("held", chest_distance)
		var root_offset: Vector3 = actor.global_position - player.global_position
		root_offset.y = 0.0
		_check(root_offset.length() < STANDING_MOTION.MAX_DISTANCE, "chest reach fixture is still within the old actor-root range: " + str(chest_distance))
		_check(player.get_execution_target() == null, "actual low-chest distance rejects too-near or overextended stabbing: " + str(chest_distance))
	_aim_at_crawler()
	_check(player.get_execution_target() == actor, "normal chest reach restores eligibility after near/far rejection")
	player.head.rotation.y = PI / 2
	_check(player.get_execution_target() == null, "crawler outside camera aim cone cannot be targeted")
	_aim_at_crawler()
	var wall := _wall()
	stage.add_child(wall)
	await physics_frame
	await physics_frame
	_check(player.get_execution_target() == null, "wall between player and low torso blocks acquisition")
	wall.free()
	await physics_frame
	_aim_at_crawler("stowed")
	var render_before := _renderer_state()
	_check(_charge_release(), "interruption fixture starts from a real charged release")
	player.advance_execution(.30)
	player._update_viewmodel(0)
	player.viewmodel_renderer.sync_view()
	_check(_mirror_lights_hidden(), "world-contact approach disables equipment mirror lights to avoid double lighting")
	player.receive_environment_damage(1, "crawl stab interruption")
	player.viewmodel_renderer.sync_view()
	_check(not player.is_execution_active() and actor.health == before_hp and actor.ai_state != DungeonEnemy.AIState.EXECUTION, "incoming damage cancels before the blade contact")
	_check(_renderer_state() == render_before, "interruption restores original overlay, world-camera equipment mask and mirror-light visibility")
	player.advance_execution(3.0)
	_check(actor.health == before_hp and defeats == 0, "cancelled action has no delayed lethal callback")
	var start: Vector3 = actor.global_position
	player.global_position = actor.global_position + Vector3(0, 0, -6)
	actor.target = player
	actor.set_physics_process(true)
	for frame in 100: await physics_frame
	actor.set_physics_process(false)
	_check(actor.global_position.distance_to(start) > .10 and str(actor.animation_clip).begins_with("crawl"), "cancelled living creature resumes real crawl AI instead of standing or freezing")
	_aim_at_crawler("none")
	_check(_charge_release(), "pause fixture starts")
	paused = true
	player.advance_combat_state(4.0)
	for frame in 4: await process_frame
	_check(is_zero_approx(player.execution_elapsed) and actor.health == before_hp, "paused test menu freezes execution clock and damage")
	paused = false
	player.prepare_for_inventory()
	_aim_at_crawler("none")
	_check(_charge_release(), "blocked-impact fixture starts")
	wall = _wall()
	stage.add_child(wall)
	await physics_frame
	await physics_frame
	player.advance_execution(MOTION.HIT_SECONDS + .01)
	_check(not player.is_execution_active() and actor.health == before_hp, "new obstruction before impact cancels the stab kill")
	wall.free()
	await physics_frame
	_aim_at_crawler("none")
	_check(_charge_release(), "range-loss fixture starts")
	player.position.z += 4
	player.advance_execution(MOTION.HIT_SECONDS + .01)
	_check(not player.is_execution_active() and actor.health == before_hp, "target leaving valid contact range cancels before damage")
	for cancel_time: float in [MOTION.INITIAL_CONTACT + .02, MOTION.HIT_SECONDS - .04]:
		_aim_at_crawler("none")
		var before_cancel_stab := _bone_poses()
		_check(_charge_release(), "post-contact cancellation fixture starts at: " + str(cancel_time))
		player.advance_execution(cancel_time)
		player._update_viewmodel(0)
		var interrupted_pose := _bone_poses()
		var active_recoil: Dictionary = actor.get_crawl_execution_reaction_snapshot()
		if cancel_time < MOTION.DEEP_THRUST_START:
			_check(_poses_match(before_cancel_stab, interrupted_pose) and actor.health == before_hp, "shallow stab cancellation fixture stays still and alive before the deep reaction")
		else:
			_check(float(active_recoil.get("deep_weight", 0)) > .1 and not _poses_match(before_cancel_stab, interrupted_pose) and actor.health == before_hp, "deep stab cancellation fixture samples an actual living flinch before the kill")
		player.prepare_for_inventory()
		_check(not player.is_execution_active() and actor.ai_state != DungeonEnemy.AIState.EXECUTION and actor.health == before_hp, "inventory cancellation after either contact stage releases both sides without killing")
		_check(str(actor.animation_clip).begins_with("crawl"), "cancelling either contact stage returns ownership to the crawling animation")
		if cancel_time > MOTION.DEEP_THRUST_START:
			_check(not _poses_match(interrupted_pose, _bone_poses()), "cancellation clears the deep contact contraction instead of leaving the rig frozen")
		player.advance_execution(MOTION.DURATION + 1)
		_check(actor.health == before_hp and defeats == 0, "cancelling shallow or deep contact prevents a delayed kill")
	_aim_at_crawler("none")
	_check(_charge_release(), "removed-target fixture starts")
	stage.remove_child(actor)
	player.advance_execution(.2)
	_check(not player.is_execution_active() and actor.health == before_hp, "target removal releases the player without killing a detached actor")
	stage.add_child(actor)
	actor.cancel_execution(player)
	actor.set_physics_process(false)


func _complete_stab(legs: Array) -> void:
	var shield_mode := "held" if legs.size() == 2 else "stowed"
	_aim_at_crawler(shield_mode)
	await physics_frame
	await physics_frame
	var clips_before: PackedStringArray = actor.animation_player.get_animation_list()
	var missing_before: Array = actor.dismemberment.severed.duplicate()
	var render_before := _renderer_state()
	var entry := _bone_poses()
	var untouched: float = actor.health
	var before_stamina := player.stamina
	_check(_charge_release(), str(legs) + ": charged sword begins the crawler execution")
	if not player.is_execution_active(): return
	_check(bool(actor.get_meta("execution_contact_on_skin", false)), "stab anchor comes from an actual posed torso skin triangle, not an anatomical capsule approximation")
	_check(is_equal_approx(before_stamina - player.stamina, STANDING_MOTION.STAMINA_COST), "stab spends its stamina exactly once")
	_check(_poses_match(entry, _bone_poses()), "reservation preserves the exact crawling entry pose")
	var motion_metrics := {
		"maximum_tip_step": 0.0, "minimum_skin_error": INF, "previous_tip": Vector3.ZERO, "samples": 0,
		"actor_transform": actor.global_transform, "visual_transform": actor.visual_root.global_transform,
		"lower_bones": _lower_bone_world_poses(), "contact_anchor": player.get_execution_snapshot().contact_point,
		"first_chest_angle": 0.0, "first_head_angle": 0.0, "deep_chest_angle": 0.0, "deep_head_angle": 0.0,
		"reaction_episodes": 0, "reaction_was_active": false,
	}
	_sample_living_stab_until(MOTION.PREPARE_END, untouched, entry, motion_metrics)
	var prepared: Dictionary = player.get_execution_snapshot()
	var prepared_tip: Vector3 = prepared.blade_tip
	var skin_point: Vector3 = prepared.contact_point
	_check(prepared_tip.distance_to(skin_point) > .12 and prepared_tip.y > skin_point.y, "preparation visibly raises the actual blade clear of the prone torso")
	var chamber_tip := prepared_tip
	var stab_axis: Vector3 = player.weapon_pivot.global_basis.y.normalized()
	_check(stab_axis.y < -.25, "prepared blade points down toward the crawling target")
	_sample_living_stab_until(MOTION.PREPARE_END + .02, untouched, entry, motion_metrics)
	var immediate_tip: Vector3 = player.get_execution_snapshot().blade_tip
	_check((immediate_tip - prepared_tip).dot(stab_axis) > .006, "actual sword starts thrusting immediately after preparation without a held delay")
	_sample_living_stab_until(MOTION.PREPARE_END + .04, untouched, entry, motion_metrics)
	var continuing_tip: Vector3 = player.get_execution_snapshot().blade_tip
	_check((continuing_tip - immediate_tip).dot(stab_axis) > .006, "the next early frame continues the thrust instead of stopping to aim again")
	_sample_living_stab_until(MOTION.INITIAL_CONTACT, untouched, entry, motion_metrics)
	var initial_contact: Dictionary = player.get_execution_snapshot()
	var initial_tip: Vector3 = initial_contact.blade_tip
	var initial_depth := (initial_tip - skin_point).dot(stab_axis)
	_check(initial_depth > .02 and initial_depth < .08, "first actual thrust makes a shallow two-to-eight centimeter penetration")
	_check(actor.health == untouched and defeats == 0 and not bool(initial_contact.hit_committed), "shallow initial penetration is not the lethal second push")
	_check(float(motion_metrics.minimum_skin_error) < .025, "actual tip crosses the posed torso skin before the first penetration")
	_check((initial_tip - chamber_tip).slide(stab_axis).length() < .02, "first thrust follows the prepared blade axis")
	_sample_living_stab_until(MOTION.DEEP_THRUST_START, untouched, entry, motion_metrics)
	var resisted: Dictionary = player.get_execution_snapshot()
	var resisted_tip: Vector3 = resisted.blade_tip
	_check(resisted_tip.distance_to(initial_tip) < .02, "shallow penetration pauses with resistance before the extra push")
	_check(_poses_match(entry, _bone_poses()), "initial penetration and its brief resistance do not produce the strong flinch reserved for the deep push")
	_check(float(motion_metrics.first_chest_angle) < deg_to_rad(.2) and float(motion_metrics.first_head_angle) < deg_to_rad(.2), "actual chest and head stay still throughout the shallow stab")
	_sample_living_stab_until(lerpf(MOTION.DEEP_THRUST_START, MOTION.HIT_SECONDS, .5), untouched, entry, motion_metrics)
	var pushing: Dictionary = player.get_execution_snapshot()
	var pushing_tip: Vector3 = pushing.blade_tip
	var pushing_blade := _measure_actual_blade_world(skin_point, stab_axis)
	_check((pushing_tip - skin_point).dot(stab_axis) > initial_depth + .025, "a second visible push moves the actual blade farther into the torso")
	_check((pushing_tip - initial_tip).slide(stab_axis).length() < .02, "deeper push retains the initial entry axis")
	_check(_poses_match(entry, _bone_poses()), "target keeps its prone pose during the early deep push before the single decisive contraction")
	_check(not player.begin_sword_attack().accepted and not player.request_primary_weapon().accepted, "active stab excludes ordinary attacks and equipment transitions")
	player._resolve_active_attack()
	_check(actor.health == untouched, "ordinary attack resolver cannot add a second execution hit")
	_sample_living_stab_until(MOTION.HIT_SECONDS - .001, untouched, entry, motion_metrics)
	_check(actor.health == untouched and defeats == 0, "one millisecond before the deep contact target is still alive")
	var last_living_pose := _bone_poses()
	_check(float(motion_metrics.deep_chest_angle) > deg_to_rad(11.0) and float(motion_metrics.deep_head_angle) > deg_to_rad(16.0), "late deep penetration produces one strong actual chest and head contraction before death")
	_check(int(motion_metrics.reaction_episodes) == 1, "actual living rig has exactly one flinch episode, during the deep push")
	_check(not _poses_match(entry, last_living_pose), "decisive stab preserves the visible recoil rather than resetting to the starting pose")
	player.advance_execution(.002)
	player._update_viewmodel(0)
	var contact: Dictionary = player.get_execution_snapshot()
	player.viewmodel_renderer.sync_view()
	_check(_mirror_lights_hidden(), "actual blade contact keeps all equipment mirror lights disabled")
	var blade_tip: Vector3 = contact.blade_tip
	var final_depth := (blade_tip - skin_point).dot(stab_axis)
	var actual_blade := _measure_actual_blade_world(skin_point, stab_axis)
	var measured_length := float(actual_blade.length_m)
	_check(measured_length > .20 and measured_length < 3.0, "half-blade measurement reads a finite plausible span from the actual rendered blade vertices")
	_check((actual_blade.tip_world as Vector3).distance_to(blade_tip) < .002, "execution blade-tip snapshot agrees with the actual furthest rendered blade vertex")
	_check(absf(float(contact.get("blade_length_m", -1)) - measured_length) < .002, "reserved blade length agrees with independent world-vertex measurement")
	_check(absf(final_depth - float(contact.get("penetration_m", -1))) < .002, "actual deep contact reaches the reserved insertion distance")
	var torso_depth := _inspect_torso_penetration(skin_point, stab_axis, actual_blade.tip_world)
	_check(bool(torso_depth.verified_closed_segment), "half-blade assessment has actual unambiguous torso entry and exit surfaces")
	var skin_entry_depth := float(torso_depth.get("entry_depth_m", INF))
	var buried_fraction := (float(actual_blade.tip_depth_m) - skin_entry_depth) / maxf(.001, measured_length)
	_check(buried_fraction >= .50 and buried_fraction <= .60, "roughly half of the actual rendered blade lies beyond the real posed skin entry at deepest contact")
	_check(float(pushing_blade.tip_depth_m) < float(actual_blade.tip_depth_m) - .05, "actual rendered blade continues appreciably farther in after the middle of the deep push")
	var contact_hands: Dictionary = player.get_first_person_motion_snapshot()
	var contact_joint: Dictionary = contact_hands.joint_landmarks.get("sword", {})
	var contact_grip: Dictionary = contact_hands.hand_contacts.get("sword", {})
	_check(not contact_grip.is_empty() and float(contact_grip.get("error", INF)) < .01, "deepest stab preserves the actual sword-hand grip contact")
	_check(not contact_joint.is_empty(), "deep contact exposes actual arm joint landmarks for reach review")
	# This synchronous clock fixture does not run move_and_slide approach.
	# Report reach here; the embedded preview checks the 2.5cm shoulder limit
	# after actual production movement, avoiding a fabricated headless approach.
	_check(blade_tip.y < initial_tip.y - .025 and (blade_tip - initial_tip).slide(stab_axis).length() < .02, "lethal extra push travels down along the same insertion axis")
	_check(actor.health == 0 and actor.ai_state == DungeonEnemy.AIState.DEAD and defeats == 1, "deep contact emits one lethal defeat through production death")
	_check(actor.ragdoll.phase == "reaction" and _poses_close(actor.ragdoll.initial_pose, last_living_pose, .001), "corpse ragdoll begins continuously from the actual final living recoil pose")
	_check(not _poses_match(actor.ragdoll.initial_pose, entry), "death does not discard the contact reaction and snap back to the reserved starting pose")
	_check(actor.dismemberment.severed == missing_before, "execution does not recreate any detached limb")
	actor.ragdoll.set_physics_process(false)
	actor.ragdoll._physics_process(actor.ragdoll.REACTION_SECONDS)
	_check(actor.ragdoll.phase == "simulating" and not actor.ragdoll.temporary, "death enters the existing permanent physical ragdoll")
	for region: String in legs:
		for bone: String in PARTS.REGION_BONES[region]:
			_check(not actor.ragdoll.parts.has(bone), "missing leg has no recreated corpse body: " + bone)
	var contact_time := player.execution_elapsed
	var maximum_hold_tip_drift := 0.0
	var minimum_held_blade_fraction := INF
	var maximum_held_blade_fraction := -INF
	while player.execution_elapsed < MOTION.WITHDRAW_START - .00001 and player.is_execution_active():
		var step := minf(.01, MOTION.WITHDRAW_START - player.execution_elapsed)
		player.advance_execution(step)
		player._update_viewmodel(step)
		var held: Dictionary = player.get_execution_snapshot()
		var held_tip: Vector3 = held.blade_tip
		var held_blade := _measure_actual_blade_world(skin_point, stab_axis)
		var held_fraction := (float(held_blade.tip_depth_m) - skin_entry_depth) / maxf(.001, float(held_blade.length_m))
		minimum_held_blade_fraction = minf(minimum_held_blade_fraction, held_fraction)
		maximum_held_blade_fraction = maxf(maximum_held_blade_fraction, held_fraction)
		_check(held_fraction >= .50 and held_fraction <= .60, "the actual rendered blade retains half-length insertion past the contact surface throughout the buried hold")
		_check(absf(float(held_blade.length_m) - measured_length) < .002, "deep hold does not scale or stretch the blade to fabricate half-length insertion")
		maximum_hold_tip_drift = maxf(maximum_hold_tip_drift, held_tip.distance_to(blade_tip))
		_check(held_tip.distance_to(blade_tip) < .002, "actual sword remains buried at its deep world position during the post-impact pause")
		_check(stab_axis.angle_to(player.weapon_pivot.global_basis.y.normalized()) < deg_to_rad(1.0), "buried pause keeps the sword on its insertion axis")
		_check(defeats == 1 and actor.health == 0 and bool(held.hit_committed), "post-impact pause cannot repeat the execution kill")
	var held_seconds := player.execution_elapsed - contact_time
	_check(held_seconds > .30 and held_seconds < .80, "deep contact is followed by a short readable hold before actual extraction begins")
	var withdrawal_start: Dictionary = player.get_execution_snapshot()
	var previous_tip: Vector3 = withdrawal_start.blade_tip
	var previous_depth := (previous_tip - skin_point).dot(stab_axis)
	var maximum_withdrawal_axis_error := 0.0
	var maximum_withdrawal_rotation := 0.0
	while player.execution_elapsed < MOTION.WITHDRAW_END - .00001 and player.is_execution_active():
		var step := minf(.01, MOTION.WITHDRAW_END - player.execution_elapsed)
		player.advance_execution(step)
		player._update_viewmodel(step)
		var withdrawal: Dictionary = player.get_execution_snapshot()
		var tip: Vector3 = withdrawal.blade_tip
		var depth := (tip - skin_point).dot(stab_axis)
		var axis_error := (tip - blade_tip).slide(stab_axis).length()
		var rotation_error := stab_axis.angle_to(player.weapon_pivot.global_basis.y.normalized())
		maximum_withdrawal_axis_error = maxf(maximum_withdrawal_axis_error, axis_error)
		maximum_withdrawal_rotation = maxf(maximum_withdrawal_rotation, rotation_error)
		_check(depth <= previous_depth + .002, "withdrawal pulls the actual blade out continuously instead of pushing it back in")
		_check(tip.distance_to(previous_tip) < .08, "withdrawal has no per-frame blade teleport")
		_check(defeats == 1 and actor.health == 0 and bool(withdrawal.hit_committed), "withdrawal preserves exactly one committed kill")
		previous_tip = tip
		previous_depth = depth
	_check(previous_depth < -.15, "blade is visibly clear of the body before returning to ready")
	_check(maximum_withdrawal_axis_error < .02 and maximum_withdrawal_rotation < deg_to_rad(2.0), "blade withdrawal preserves its insertion line and orientation")
	_check(float(motion_metrics.maximum_tip_step) < .25, "blade does not teleport during preparation and either thrust")
	player.advance_execution(MOTION.DURATION + 1)
	player._update_viewmodel(.1)
	player.viewmodel_renderer.sync_view()
	_check(not player.is_execution_active() and player.combat_state == DungeonPlayer.CombatState.READY, "complete preparation, two-stage thrust and withdrawal return to usable combat")
	_check(player.camera.position.is_zero_approx() and player.camera.rotation.is_zero_approx(), "completion restores camera offsets")
	_check(_renderer_state() == render_before, "completion restores overlay, world-camera equipment mask and mirror-light visibility")
	actor.receive_hit(1000, player.global_position, 1, false)
	actor._die()
	_check(defeats == 1 and not actor.finish_execution(player), "corpse hits and repeated finish/death cannot duplicate rewards")
	_check(actor.animation_player.get_animation_list() == clips_before, "all imported clips remain unchanged")
	report.append({"legs": legs, "shield_mode": shield_mode, "maximum_tip_step": motion_metrics.maximum_tip_step, "skin_contact_error": motion_metrics.minimum_skin_error, "first_chest_angle": motion_metrics.first_chest_angle, "first_head_angle": motion_metrics.first_head_angle, "deep_chest_angle": motion_metrics.deep_chest_angle, "deep_head_angle": motion_metrics.deep_head_angle, "reaction_episodes": motion_metrics.reaction_episodes, "buried_hold_seconds": held_seconds, "buried_hold_maximum_tip_drift": maximum_hold_tip_drift, "initial_contact": initial_contact, "initial_depth": initial_depth, "deep_push_depth": final_depth, "posed_torso_penetration": torso_depth, "measured_blade": actual_blade, "mid_push_blade": pushing_blade, "actual_skin_buried_fraction": buried_fraction, "held_blade_fraction_min": minimum_held_blade_fraction, "held_blade_fraction_max": maximum_held_blade_fraction, "deep_contact_arm": contact_joint, "deep_contact_grip": contact_grip, "withdrawal_axis_error": maximum_withdrawal_axis_error, "withdrawal_rotation_error": maximum_withdrawal_rotation, "withdrawal_final_depth": previous_depth, "contact": contact, "defeats": defeats, "missing_parts": missing_before, "ragdoll_bodies": actor.ragdoll.parts.size()})


func _measure_actual_blade_world(skin_point: Vector3, axis: Vector3) -> Dictionary:
	# Project actual visible blade vertices onto the stabbing line in world
	# space. Do not reuse the production tip/length helper or authored ratio.
	var minimum := INF
	var maximum := -INF
	var tip := Vector3.ZERO
	var base := Vector3.ZERO
	var vertices_seen := 0
	for surface in player.sword_blade.mesh.get_surface_count():
		var vertices: PackedVector3Array = player.sword_blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var world_point := player.sword_blade.to_global(vertex)
			var projection := (world_point - skin_point).dot(axis)
			vertices_seen += 1
			if projection < minimum:
				minimum = projection
				base = world_point
			if projection > maximum:
				maximum = projection
				tip = world_point
	_check(vertices_seen > 0 and is_finite(minimum) and is_finite(maximum), "independent blade measurement visits actual finite mesh vertices")
	return {"length_m": maximum - minimum, "base_depth_m": minimum, "tip_depth_m": maximum, "base_world": base, "tip_world": tip, "vertices": vertices_seen}


func _inspect_torso_penetration(skin_point: Vector3, axis: Vector3, blade_tip: Vector3) -> Dictionary:
	# Test the visible CPU-skinned torso at the actual deepest reaction pose,
	# before any permanent ragdoll physics tick can change that pose. Capsule
	# collision and a chosen numeric depth alone cannot establish skin exit.
	var ray_start := skin_point - axis * .10
	var ray_end := skin_point + axis * 1.0
	var raw_hits: Array[Dictionary] = []
	var mesh_count := 0
	var triangle_count := 0
	for part: MeshInstance3D in actor.visual_meshes:
		if part.name != "CreepPart_torso" or not part.is_visible_in_tree(): continue
		mesh_count += 1
		var posed: ArrayMesh = actor.dismemberment._bake_world_mesh(part, Vector3.ZERO)
		var faces := posed.get_faces()
		triangle_count += faces.size() / 3
		for index in range(0, faces.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(ray_start, ray_end, faces[index], faces[index + 1], faces[index + 2])
			if hit is Vector3:
				var normal := (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).normalized()
				raw_hits.append({"depth_m": (hit - skin_point).dot(axis), "normal_dot_axis": normal.dot(axis), "position": hit})
	raw_hits.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.depth_m) < float(second.depth_m))
	var crossings: Array[Dictionary] = []
	for hit: Dictionary in raw_hits:
		if crossings.is_empty() or absf(float(hit.depth_m) - float(crossings.back().depth_m)) > .001:
			crossings.append({"depth_m": hit.depth_m, "normal_dot_axis": hit.normal_dot_axis, "position": hit.position, "triangle_hits": 1, "consistent_winding": true})
		else:
			var crossing: Dictionary = crossings.back()
			crossing.triangle_hits += 1
			if float(crossing.normal_dot_axis) * float(hit.normal_dot_axis) <= 0:
				crossing.consistent_winding = false
	var result := {"verified_closed_segment": false, "unverified_reason": "", "mesh_count": mesh_count, "triangle_count": triangle_count, "raw_hit_count": raw_hits.size(), "crossings": crossings, "actual_tip_depth_m": (blade_tip - skin_point).dot(axis)}
	_check(mesh_count > 0 and triangle_count > 0, "deep penetration inspection reads the actual visible posed torso triangles")
	if crossings.size() != 2:
		result.unverified_reason = "Expected two distinct torso surfaces; open, folded or missing geometry requires visual review."
		return result
	var entry: Dictionary = crossings[0]
	var exit_surface: Dictionary = crossings[1]
	var normal_product := float(entry.normal_dot_axis) * float(exit_surface.normal_dot_axis)
	if not bool(entry.consistent_winding) or not bool(exit_surface.consistent_winding) or normal_product >= 0 or minf(absf(float(entry.normal_dot_axis)), absf(float(exit_surface.normal_dot_axis))) < .05 or absf(float(entry.depth_m)) > .08:
		result.unverified_reason = "Near-contact entry and opposing exit normals are ambiguous; no inside-body claim is made."
		return result
	result.verified_closed_segment = true
	result.entry_depth_m = entry.depth_m
	result.exit_depth_m = exit_surface.depth_m
	result.remaining_to_exit_m = float(exit_surface.depth_m) - float(result.actual_tip_depth_m)
	_check(float(result.actual_tip_depth_m) > float(entry.depth_m) + .01, "deep blade tip passes the actual posed torso entry surface")
	_check(float(result.actual_tip_depth_m) < float(exit_surface.depth_m) - .01, "deep blade tip stays inside the actual opposing torso surface with a one-centimeter margin")
	return result


func _sample_living_stab_until(stop_time: float, untouched: float, entry: Array[Transform3D], metrics: Dictionary) -> void:
	while player.execution_elapsed < stop_time - .00001 and player.is_execution_active():
		var step := minf(.01, stop_time - player.execution_elapsed)
		player.advance_execution(step)
		player._update_viewmodel(step)
		var snap: Dictionary = player.get_execution_snapshot()
		var tip: Vector3 = snap.get("blade_tip", Vector3(INF, INF, INF))
		_check(tip.is_finite(), "authored actual blade-tip path stays finite")
		if int(metrics.samples) > 0:
			metrics.maximum_tip_step = maxf(metrics.maximum_tip_step, tip.distance_to(metrics.previous_tip))
		metrics.previous_tip = tip
		metrics.samples += 1
		metrics.minimum_skin_error = minf(metrics.minimum_skin_error, float(snap.get("contact_error", INF)))
		_check(actor.health == untouched and defeats == 0, "pre-deep-contact frames never deal lethal damage or award defeat")
		_check_living_reaction(entry, metrics, snap)
		_check(bool(snap.get("world_contact", false)), "stab uses actual world depth through preparation and both thrusts")
		var hands: Dictionary = player.get_first_person_motion_snapshot().hand_contacts
		var sword_contact: Dictionary = hands.get("sword", {})
		_check(not sword_contact.is_empty() and float(sword_contact.get("error", INF)) < .01, "right hand remains physically attached to sword grip")
	_check(player.is_execution_active() and absf(player.execution_elapsed - stop_time) < .0001, "production execution reaches the requested choreography stage: " + str(stop_time))


func _check_living_reaction(entry: Array[Transform3D], metrics: Dictionary, sword_snapshot: Dictionary) -> void:
	var poses := _bone_poses()
	var reaction: Dictionary = actor.get_crawl_execution_reaction_snapshot()
	var first_weight := float(reaction.get("first_weight", 0.0))
	var deep_weight := float(reaction.get("deep_weight", 0.0))
	var anchor: Vector3 = metrics.contact_anchor
	var tip: Vector3 = sword_snapshot.blade_tip
	var axis: Vector3 = player.weapon_pivot.global_basis.y.normalized()
	# Read actual rig transforms: metadata alone cannot prove that the visible
	# creature moved, stayed grounded, or transferred its pose into the corpse.
	var chest: int = actor.skeleton.find_bone("Chest")
	var head: int = actor.skeleton.find_bone("Head")
	_check(chest >= 0 and head >= 0, "source rig contains the actual chest and head for impact verification")
	if chest < 0 or head < 0: return
	var chest_angle := entry[chest].basis.get_rotation_quaternion().angle_to(poses[chest].basis.get_rotation_quaternion())
	var head_angle := entry[head].basis.get_rotation_quaternion().angle_to(poses[head].basis.get_rotation_quaternion())
	if player.execution_elapsed <= MOTION.DEEP_THRUST_START:
		metrics.first_chest_angle = maxf(metrics.first_chest_angle, chest_angle)
		metrics.first_head_angle = maxf(metrics.first_head_angle, head_angle)
		_check(_poses_match(entry, poses), "no visible impact contraction occurs during the initial shallow stab")
	var reaction_is_active := chest_angle > deg_to_rad(1.0) or head_angle > deg_to_rad(1.0)
	if reaction_is_active and not bool(metrics.reaction_was_active):
		metrics.reaction_episodes += 1
	metrics.reaction_was_active = reaction_is_active
	_check(absf(first_weight) < .000001, "first penetration does not request a separate flinch")
	if deep_weight > .05:
		metrics.deep_chest_angle = maxf(metrics.deep_chest_angle, chest_angle)
		metrics.deep_head_angle = maxf(metrics.deep_head_angle, head_angle)
	if player.execution_elapsed < MOTION.PREPARE_END or (tip - anchor).dot(axis) < -.001:
		_check(_poses_match(entry, poses), "target cannot flinch before the real blade crosses its skin")
	if first_weight + deep_weight <= .000001:
		_check(_poses_match(entry, poses), "outside the deep contact pulse the living target retains its reserved prone pose")
	elif first_weight + deep_weight > .05:
		_check(chest_angle > .001 and head_angle > .001, "positive recoil visibly changes actual chest and head bones")
	_check(actor.global_transform.is_equal_approx(metrics.actor_transform), "impact does not translate or swivel the creature navigation root")
	_check(actor.visual_root.global_transform.is_equal_approx(metrics.visual_transform), "impact does not offset the entire model away from the grounded body")
	var current_lower := _lower_bone_world_poses()
	for name_value: String in metrics.lower_bones:
		var before: Transform3D = metrics.lower_bones[name_value]
		_check(before.is_equal_approx(current_lower[name_value]), "impact preserves the planted pelvis and lower limb in world space: " + name_value)
	var reported_anchor: Vector3 = reaction.get("contact_anchor", Vector3(INF, INF, INF))
	_check(reported_anchor.distance_to(anchor) < .001, "reaction stays centered on the original actual torso skin contact")


func _lower_bone_world_poses() -> Dictionary:
	var result := {}
	for name_value: String in ["Torso", "Leg1.L", "Leg2.L", "Leg3.L", "Foot.L", "Leg1.R", "Leg2.R", "Leg3.R", "Foot.R"]:
		var bone: int = actor.skeleton.find_bone(name_value)
		_check(bone >= 0, "lower-body verification uses an existing source bone: " + name_value)
		if bone >= 0:
			result[name_value] = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(bone)
	return result


func _poses_close(first: Array[Transform3D], second: Array[Transform3D], tolerance: float) -> bool:
	if first.size() != second.size(): return false
	for bone in first.size():
		if first[bone].origin.distance_to(second[bone].origin) > tolerance: return false
		if first[bone].basis.get_rotation_quaternion().angle_to(second[bone].basis.get_rotation_quaternion()) > tolerance: return false
		if first[bone].basis.get_scale().distance_to(second[bone].basis.get_scale()) > tolerance: return false
	return true


func _wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = DungeonPlayer.WORLD_LAYER
	wall.collision_mask = 0
	wall.position = player.global_position.lerp(actor.get_aim_point(), .5)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, .15)
	collision.shape = box
	wall.add_child(collision)
	return wall


func _renderer_state() -> Dictionary:
	var mirror_visibility: Array[bool] = []
	for light: Light3D in player.viewmodel_renderer.equipment_lights:
		mirror_visibility.append(light.visible)
	return {"camera_cull_mask": player.camera.cull_mask, "overlay": player.viewmodel_renderer.overlay.visible, "mirror_lights": mirror_visibility}


func _mirror_lights_hidden() -> bool:
	if player.viewmodel_renderer.equipment_lights.is_empty(): return false
	for light: Light3D in player.viewmodel_renderer.equipment_lights:
		if light.visible: return false
	return true


func _bone_poses() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for bone in actor.skeleton.get_bone_count():
		poses.append(actor.skeleton.get_bone_pose(bone))
	return poses


func _poses_match(first: Array[Transform3D], second: Array[Transform3D]) -> bool:
	if first.size() != second.size(): return false
	for bone in first.size():
		if not first[bone].is_equal_approx(second[bone]): return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
