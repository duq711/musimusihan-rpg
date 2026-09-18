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
	print("CREEP EXECUTION TEST %s: actual severance/grounded recovery, charge, one contact kill, missing limbs, ragdoll, cancellation, renderer/session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
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
	var previous_tip := Vector3.ZERO
	var maximum_step := 0.0
	var surface_tip := Vector3.ZERO
	var contact_error := INF
	for frame in range(1, 75):
		player.advance_execution(.01)
		player._update_viewmodel(.01)
		var snap: Dictionary = player.get_execution_snapshot()
		var tip: Vector3 = snap.get("blade_tip", Vector3(INF, INF, INF))
		_check(tip.is_finite(), "authored actual blade-tip path stays finite")
		if frame > 1: maximum_step = maxf(maximum_step, tip.distance_to(previous_tip))
		previous_tip = tip
		_check(actor.health == untouched and defeats == 0, "pre-contact frames never deal damage or award defeat")
		_check(_poses_match(entry, _bone_poses()), "living target does not stand or swivel during the downward stab")
		_check(bool(snap.get("world_contact", false)), "stab uses the actual world depth during its full approach")
		var hands: Dictionary = player.get_first_person_motion_snapshot().hand_contacts
		var sword_contact: Dictionary = hands.get("sword", {})
		_check(not sword_contact.is_empty() and float(sword_contact.get("error", INF)) < .01, "right hand remains physically attached to sword grip")
		if frame == 74:
			surface_tip = tip
			contact_error = float(snap.get("contact_error", INF))
	_check(contact_error < .025, "actual blade tip reaches torso skin before penetrating")
	_check(maximum_step < .25, "blade does not teleport during the authored stab trajectory")
	_check(not player.begin_sword_attack().accepted and not player.request_primary_weapon().accepted, "active stab excludes ordinary attacks and equipment transitions")
	player._resolve_active_attack()
	_check(actor.health == untouched, "ordinary attack resolver cannot add a second execution hit")
	player.advance_execution(MOTION.HIT_SECONDS - player.execution_elapsed - .001)
	_check(actor.health == untouched and defeats == 0, "one millisecond before contact target is still alive")
	player.advance_execution(.002)
	player._update_viewmodel(0)
	var contact: Dictionary = player.get_execution_snapshot()
	player.viewmodel_renderer.sync_view()
	_check(_mirror_lights_hidden(), "actual blade contact keeps all equipment mirror lights disabled")
	var blade_tip: Vector3 = contact.get("blade_tip", Vector3(INF, INF, INF))
	var skin_point: Vector3 = contact.get("contact_point", Vector3(INF, INF, INF))
	_check(absf(float(contact.get("contact_error", INF)) - .10) < .025, "contact penetrates approximately ten centimeters beyond actual torso skin")
	_check(blade_tip.y < surface_tip.y - .035 and blade_tip.y < skin_point.y, "lethal blade travel is downward into the prone torso")
	_check(actor.health == 0 and actor.ai_state == DungeonEnemy.AIState.DEAD and defeats == 1, "actual contact emits one lethal defeat through production death")
	_check(actor.ragdoll.phase == "reaction" and _poses_match(actor.ragdoll.initial_pose, entry), "corpse ragdoll starts from the held crawling contact pose")
	_check(actor.dismemberment.severed == missing_before, "execution does not recreate any detached limb")
	actor.ragdoll.set_physics_process(false)
	actor.ragdoll._physics_process(actor.ragdoll.REACTION_SECONDS)
	_check(actor.ragdoll.phase == "simulating" and not actor.ragdoll.temporary, "death enters the existing permanent physical ragdoll")
	for region: String in legs:
		for bone: String in PARTS.REGION_BONES[region]:
			_check(not actor.ragdoll.parts.has(bone), "missing leg has no recreated corpse body: " + bone)
	player.advance_execution(MOTION.DURATION + 1)
	player._update_viewmodel(.1)
	player.viewmodel_renderer.sync_view()
	_check(not player.is_execution_active() and player.combat_state == DungeonPlayer.CombatState.READY, "full stab returns to usable combat")
	_check(player.camera.position.is_zero_approx() and player.camera.rotation.is_zero_approx(), "completion restores camera offsets")
	_check(_renderer_state() == render_before, "completion restores overlay, world-camera equipment mask and mirror-light visibility")
	actor.receive_hit(1000, player.global_position, 1, false)
	actor._die()
	_check(defeats == 1 and not actor.finish_execution(player), "corpse hits and repeated finish/death cannot duplicate rewards")
	_check(actor.animation_player.get_animation_list() == clips_before, "all imported clips remain unchanged")
	report.append({"legs": legs, "shield_mode": shield_mode, "maximum_tip_step": maximum_step, "skin_contact_error": contact_error, "contact": contact, "defeats": defeats, "missing_parts": missing_before, "ragdoll_bodies": actor.ragdoll.parts.size()})


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
