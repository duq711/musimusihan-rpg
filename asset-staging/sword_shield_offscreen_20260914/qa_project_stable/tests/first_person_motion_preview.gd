extends SceneTree
## Production first-person states in an isolated renderer. No desktop capture,
## native window, hardware input sampling/injection, cursor change, or sound.
const ARM_PREVIEW := preload("res://tests/player_arm_preview.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/first_person_motion"
const POSE_IDS := [
	"sword_idle", "sword_windup", "sword_charge", "sword_strike", "sword_recovery",
	"shield_idle", "shield_guard", "shield_impact",
	"bow_idle", "bow_half", "bow_full", "bow_release",
	"flail_idle", "flail_melee", "flail_spin", "flail_throw", "flail_return",
	"staff_idle", "staff_cast", "torch_safe", "torch_walk", "torch_sprint",
	"chest_touch", "chest_lift",
]
const SEQUENCE_IDS := ["sword_cycle", "bow_draw_release", "flail_spin_throw_return"]
const SEQUENCE_FPS := 12
const SEQUENCE_SECONDS := 2.0
const SOURCE_FILES := [
	"res://scripts/sword_long_grip_visual.gd",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb.import",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_Arm_Leather_BaseColor.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_Arm_Leather_Normal.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_Glove_Reference_BaseColor.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_Glove_Reference_Normal.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_Glove_Reference_Roughness.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_weapon_material_atlas_v2.png",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static_weapon_material_normal_v2.png",
	"res://scripts/player.gd", "res://scripts/player_arm_visual.gd",
	"res://scripts/chest_hand_visuals.gd", "res://scripts/archery_visuals.gd",
	"res://scripts/flail_visuals.gd", "res://scripts/flail_projectile.gd",
	"res://scripts/first_person_renderer.gd", "res://scripts/inventory_model.gd",
	"res://scripts/render_resolution_budget.gd", "res://scripts/player_appearance.gd",
	"res://scripts/equipment_concept_visual.gd", "res://scripts/flame_visuals.gd",
	"res://scripts/dark_fantasy_materials.gd", "res://scripts/dungeon_concept_visual.gd",
	"res://scripts/dark_fantasy_effect_visual.gd", "res://scripts/loot_chest.gd",
	"res://scripts/arrow_projectile.gd", "res://scripts/magic_projectile.gd",
	"res://scripts/bow_shot_profile.gd", "res://scripts/flail_profile.gd",
	"res://scripts/spell_catalog.gd", "res://scripts/sword_clash_geometry.gd",
	"res://scripts/expedition_session.gd", "res://scripts/test_room_sandbox.gd",
	"res://scripts/stress_profile.gd",
	"res://assets/3d/player/gravebound_player.glb",
	"res://scripts/first_person_motion.gd", "res://scripts/sword_shield_arm_visual.gd",
	"res://assets/3d/player/sword_shield/left_arm.glb", "res://assets/3d/player/sword_shield/right_arm.glb",
	"res://assets/3d/player/sword_shield/longsword.glb", "res://assets/3d/player/sword_shield/round_shield.glb",
	"res://assets/ai/sword_shield/worn_charcoal_leather.png", "res://assets/ai/sword_shield/weathered_hand_skin.png",
	"res://assets/3d/player/sword_shield/textures/leather_normal.jpg",
	"res://assets/3d/player/sword_shield/textures/linen_albedo.jpg", "res://assets/3d/player/sword_shield/textures/linen_normal.jpg",
	"res://assets/3d/abandoned_mine/textures/rough_wood_albedo_2k.jpg", "res://assets/3d/abandoned_mine/textures/rough_wood_normal_gl_2k.jpg",
	"res://assets/3d/dark_fantasy/rusted_longsword.glb",
	"res://assets/3d/dark_fantasy/weathered_round_shield.glb",
	"res://assets/3d/dark_fantasy/iron_cage_torch.glb",
	"res://assets/3d/dark_fantasy/reliquary_chest.glb",
	"res://assets/ai/materials/ancient_oak.png", "res://assets/ai/materials/pitted_black_iron.png",
	"res://assets/ai/materials/concept_weathered_oak.png", "res://assets/ai/materials/concept_forged_steel.png",
	"res://assets/ai/materials/concept_limestone.png", "res://assets/ai/materials/concept_charcoal_linen.png",
	"res://assets/ai/materials/concept_black_leather.png", "res://assets/ai/materials/concept_ember_coal.png",
	"res://assets/ai/materials/concept_frosted_ice.png",
	"res://assets/ai/vfx/torch_flame.png", "res://assets/ai/vfx/rune_trap.png",
	"res://tests/player_arm_preview.gd",
	"res://tests/first_person_motion_preview.gd",
	"res://assets/ai/first_person_motion/sword_target.png",
	"res://assets/ai/first_person_motion/shield_target.png",
	"res://assets/ai/first_person_motion/bow_target.png",
	"res://assets/ai/first_person_motion/flail_target.png",
	"res://assets/ai/first_person_motion/utility_target.png",
]
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var sequences: Array[Dictionary] = []
var output_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use tests/run_embedded_preview.sh first_person_motion_preview.gd; native windows and dummy images are not accepted.")
		quit(2)
		return
	var iteration := OS.get_environment("FIRST_PERSON_MOTION_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("FIRST_PERSON_MOTION_QA_ITERATION must name a new plain output folder.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Existing motion captures are preserved: " + output_path)
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Isolated capture must not replace an active test-room session.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_path)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var previous_cursor := Input.mouse_mode
	var previous_session := ExpeditionSession.capture_snapshot()
	var previous_inventory := previous_session.get("inventory") as ExpeditionInventory
	var previous_inventory_fingerprint := inventory_fingerprint(previous_inventory)
	var hashes := source_hashes()
	for source_path: String in SOURCE_FILES:
		if str(hashes.get(source_path, "")).length() != 64:
			failures.append("Missing consumed capture source: " + source_path)
	sandbox.begin()
	for pose_id: String in POSE_IDS:
		var viewport := create_viewport()
		root.add_child(viewport)
		var fixture := populate_viewport(viewport)
		await physics_frame
		await physics_frame
		var configured := configure_pose(fixture, pose_id)
		var inspection := inspect_pose(fixture, pose_id)
		if not configured or not bool(inspection.passed):
			failures.append("Could not configure the actual production state: " + pose_id)
		for frame in range(10):
			await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		if pixels == null or pixels.is_empty() or pixels.save_png(output_path.path_join(pose_id + ".png")) != OK:
			failures.append("Actual renderer did not save pixels: " + pose_id)
		inspection["image"] = pose_id + ".png"
		captures.append(inspection)
		(fixture.player as DungeonPlayer).cancel_timed_interaction()
		(fixture.player as DungeonPlayer).cancel_flail_action()
		viewport.queue_free()
		await process_frame
	if OS.get_environment("FIRST_PERSON_MOTION_QA_SEQUENCE") == "1":
		for sequence_id: String in SEQUENCE_IDS:
			await _capture_sequence(sequence_id)
	sandbox.finish()
	var final_inventory_fingerprint := inventory_fingerprint(previous_inventory)
	var inventory_preserved := final_inventory_fingerprint == previous_inventory_fingerprint
	var preserved := Input.mouse_mode == previous_cursor and ExpeditionSession.capture_snapshot() == previous_session and inventory_preserved
	var unchanged := source_hashes() == hashes
	if not preserved: failures.append("Original expedition or cursor changed.")
	if not unchanged: failures.append("Production source changed during capture.")
	var manifest := {"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "capture_kind": "Actual DungeonPlayer first-person states from production actions and viewmodel functions", "image_size": [1280, 720], "desktop_capture": false, "hardware_input": false, "expedition_and_cursor_preserved": preserved, "source_sha256": hashes, "sources_unchanged_during_capture": unchanged, "captures": captures, "sequences": sequences, "failures": failures}
	manifest["original_inventory_contents_preserved"] = inventory_preserved
	manifest["original_inventory_sha256_before"] = previous_inventory_fingerprint
	manifest["original_inventory_sha256_after"] = final_inventory_fingerprint
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: failures.append("Could not write motion capture manifest.")
	for failure in failures: push_error(failure)
	print("FIRST PERSON MOTION PREVIEW %s: %d production poses; isolated input, original expedition and cursor preserved; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)


func _capture_sequence(sequence_id: String) -> void:
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	if not begin_sequence(fixture, sequence_id):
		failures.append("Production action clock cannot configure sequence: " + sequence_id)
		viewport.queue_free()
		await process_frame
		return
	var relative_folder := "sequences/" + sequence_id
	var folder := output_path.path_join(relative_folder)
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for frame in range(roundi(SEQUENCE_SECONDS * SEQUENCE_FPS) + 1):
		if frame > 0: advance_sequence(fixture, 1.0 / float(SEQUENCE_FPS))
		for warmup in range(3): await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var image_name := "frame_%03d.png" % frame
		if pixels == null or pixels.is_empty() or pixels.save_png(folder.path_join(image_name)) != OK:
			failures.append("Missing real sequence pixels: " + sequence_id + "/" + image_name)
		var inspection := inspect_sequence(fixture)
		inspection["image"] = relative_folder.path_join(image_name)
		inspection["frame"] = frame
		frames.append(inspection)
	sequences.append({"id": sequence_id, "fps": SEQUENCE_FPS, "duration_seconds": SEQUENCE_SECONDS, "frame_count": frames.size(), "frames": frames})
	(fixture.player as DungeonPlayer).cancel_flail_action()
	viewport.queue_free()
	await process_frame


static func begin_sequence(fixture: Dictionary, sequence_id: String) -> bool:
	var player := fixture.player as DungeonPlayer
	if not SEQUENCE_IDS.has(sequence_id) or not player.has_method("advance_action_timers") or not player.has_method("advance_combat_state"):
		return false
	var idle_id := "sword_idle" if sequence_id == "sword_cycle" else "bow_idle" if sequence_id == "bow_draw_release" else "flail_idle"
	if not configure_pose(fixture, idle_id): return false
	fixture["sequence_id"] = sequence_id
	fixture["sequence_idle_id"] = idle_id
	fixture["sequence_time"] = 0.0
	fixture["sequence_released"] = false
	match sequence_id:
		"sword_cycle": player._try_begin_attack()
		"bow_draw_release":
			if not bool(player.begin_bow_draw().get("accepted", false)): return false
		"flail_spin_throw_return":
			if not bool(player.begin_flail_spin().get("accepted", false)): return false
	return true


static func advance_sequence(fixture: Dictionary, duration: float) -> void:
	var player := fixture.player as DungeonPlayer
	var remaining := maxf(duration, 0.0)
	while remaining > 0.00001:
		var delta := minf(remaining, 1.0 / 60.0)
		var now := float(fixture.sequence_time)
		var release_time := 0.45 if fixture.sequence_id == "sword_cycle" else 1.1 if fixture.sequence_id == "bow_draw_release" else 0.75
		if not bool(fixture.sequence_released) and now >= release_time - 0.000001:
			fixture.sequence_released = true
			match str(fixture.sequence_id):
				"sword_cycle": player.attack_release_requested = true
				"bow_draw_release": fixture.action_result = player.release_bow_shot()
				"flail_spin_throw_return": fixture.action_result = player.release_flail_throw()
			_freeze_projectiles(fixture)
		# The exact production clock/presentation ordering is shared with the
		# running player. Movement and interaction Input queries are never called.
		player.call("advance_action_timers", delta)
		player.call("advance_combat_state", delta, false)
		player._update_viewmodel(delta)
		player._resolve_active_attack()
		player._update_torch(delta)
		player._update_stamina(delta)
		for child in fixture.stage.get_children():
			if (child is ArrowProjectile or child is MagicProjectile or child is FlailProjectile) and not child.is_queued_for_deletion():
				child.set_physics_process(false)
				child.set_process(false)
				child._physics_process(delta)
		fixture.sequence_time = now + delta
		remaining -= delta
	player.viewmodel_renderer.sync_view()


static func inspect_sequence(fixture: Dictionary) -> Dictionary:
	var result := inspect_pose(fixture, str(fixture.sequence_idle_id))
	result["sequence"] = str(fixture.sequence_id)
	result["time_seconds"] = snappedf(float(fixture.sequence_time), 0.0001)
	result["released"] = bool(fixture.sequence_released)
	result["arrows"] = (fixture.inventory as ExpeditionInventory).count_item("wooden_arrow")
	var player := fixture.player as DungeonPlayer
	if is_instance_valid(player.flail_projectile):
		result["projectile_position"] = str(player.flail_projectile.global_position)
		result["projectile_phase"] = str(player.flail_projectile.phase)
	return result


static func inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null:
		return "no_inventory"
	# capture_snapshot intentionally keeps this object's identity. Hash its nested
	# contents now so accidental edits cannot also mutate the expected reference.
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text()


static func source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in SOURCE_FILES:
		hashes[path] = FileAccess.get_sha256(path)
	# The baseline predates this production motion module. Its later presence is
	# recorded explicitly, rather than making a baseline load depend on new code.
	var motion_path := "res://scripts/first_person_motion.gd"
	hashes[motion_path] = FileAccess.get_sha256(motion_path) if FileAccess.file_exists(motion_path) else "absent_before_motion_implementation"
	return hashes


static func create_viewport() -> SubViewport:
	var viewport := ARM_PREVIEW.create_viewport()
	viewport.name = "FirstPersonMotionIsolatedViewport"
	viewport.audio_listener_enable_2d = false
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	var fixture := ARM_PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)
	fixture.inventory.add_item("weathered_staff")
	(fixture.chest as DungeonLootChest).position = Vector3(9, 0, 9)
	fixture["action_result"] = {}
	return fixture


static func configure_pose(fixture: Dictionary, pose_id: String) -> bool:
	if not POSE_IDS.has(pose_id): return false
	seed(8127)
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	if not ARM_PREVIEW.configure_pose(fixture, "idle"): return false
	# Use actual inventory transactions; a sword-only pose must not silently
	# retain a shield just because the older arm fixture supplied one by default.
	if not pose_id.begins_with("shield_") and not str(bag.equipment.get("offhand", "")).is_empty():
		if not bool(bag.unequip("offhand").get("accepted", false)): return false
	if pose_id.begins_with("shield_") and str(bag.equipment.get("offhand", "")) != "round_shield":
		var shield_index := -1
		for index in bag.slots.size():
			if str(bag.slots[index].id) == "round_shield": shield_index = index; break
		if shield_index < 0 or not bool(bag.equip_from_slot(shield_index).get("accepted", false)): return false
	player.set_torch_enabled(pose_id.begins_with("torch_"))
	player.bow_shot_rng.seed = 8127
	player.health = 100
	player.stamina = 100
	player.state_time = 0
	player._camera_shake = 0
	player._shield_impact = 0
	var weapon := "rusted_sword"
	if pose_id.begins_with("bow_"): weapon = "hunting_bow"
	elif pose_id.begins_with("flail_"): weapon = "chain_flail"
	elif pose_id.begins_with("staff_"): weapon = "weathered_staff"
	if not ARM_PREVIEW._equip_weapon(bag, weapon): return false
	if pose_id.begins_with("chest_"):
		(fixture.chest as DungeonLootChest).position = Vector3.ZERO
		var configured := ARM_PREVIEW.configure_pose(fixture, pose_id)
		player.set_torch_enabled(false)
		player.viewmodel_renderer.sync_view()
		return configured
	# Hiding a chest mesh does not remove its real collision. Keep that unused
	# fixture away from the projectile lane so an outbound throw stays outbound.
	(fixture.chest as DungeonLootChest).position = Vector3(9, 0, 9)
	# Settle the real idle presentation first, then run the named action.
	_sample_view(player, 0.3)
	match pose_id:
		"sword_windup", "sword_charge", "sword_strike", "sword_recovery":
			player._try_begin_attack()
			player.state_time = 0.9 if pose_id == "sword_charge" else 0.18
			player.attack_charge = clampf((player.state_time - 0.24), 0.0, 1.0)
			_sample_view(player, 0.12)
			if pose_id in ["sword_strike", "sword_recovery"]:
				player._commit_attack()
				player.state_time = 0.08
				_sample_view(player, 0.06)
				if pose_id == "sword_recovery":
					player.state_time = 0.17
					player._resolve_active_attack()
					player.state_time = 0.2
					_sample_view(player, 0.1)
		"shield_guard", "shield_impact":
			player.blocking = true
			player.block_time = 0.1
			_sample_view(player, 0.22)
			if pose_id == "shield_impact":
				fixture.action_result = player.receive_attack(18, player.global_position + Vector3(0, 0, -2))
				_sample_view(player, 0.025)
		"bow_half", "bow_full", "bow_release":
			fixture.action_result = player.begin_bow_draw()
			if not bool(fixture.action_result.get("accepted", false)): return false
			player._advance_bow_draw(0.5 if pose_id == "bow_half" else player.BOW_DRAW_DURATION)
			_sample_view(player, 0.2)
			if pose_id == "bow_release":
				fixture.action_result = player.release_bow_shot()
				_freeze_projectiles(fixture)
				_sample_view(player, 0.03, true)
		"flail_melee":
			fixture.action_result = player.begin_flail_melee()
			player._update_flail(0.2)
			_sample_view(player, 0.06)
		"flail_spin", "flail_throw", "flail_return":
			fixture.action_result = player.begin_flail_spin()
			player._update_flail(1.0)
			_sample_view(player, 0.12)
			if pose_id != "flail_spin":
				fixture.action_result = player.release_flail_throw()
				var projectile := player.flail_projectile as Node3D
				if not is_instance_valid(projectile): return false
				projectile.set_physics_process(false)
				projectile._physics_process(0.10 if pose_id == "flail_throw" else float(projectile.max_distance) / float(projectile.speed) + 0.001)
				if pose_id == "flail_return":
					var distance := projectile.global_position.distance_to(player.get_flail_chain_anchor())
					projectile._physics_process(maxf(0, distance - 2.5) / float(player.FLAIL_PROFILE.RETURN_SPEED))
				player._update_flail(0)
				_sample_view(player, 0.045)
		"staff_cast":
			# Caller owns the isolated sandbox; the original learned spells remain
			# on its saved snapshot and are restored after capture.
			ExpeditionSession.learn_spell("fire_bolt")
			fixture.action_result = player.cast_spell("fire_bolt")
			_freeze_projectiles(fixture)
			_sample_view(player, 0.05, true)
		"torch_safe", "torch_walk", "torch_sprint":
			player.configure_safe_zone(true)
			if pose_id != "torch_safe":
				player.velocity = Vector3(0, 0, -player.SPRINT_SPEED if pose_id == "torch_sprint" else -player.WALK_SPEED)
				player._bob_time = 1.1
			_sample_view(player, 0.35)
	player._update_torch(0)
	player.viewmodel_renderer.sync_view()
	return true


static func _sample_view(player: DungeonPlayer, duration: float, advance_timers: bool = false) -> void:
	var remaining := duration
	while remaining > 0.00001:
		var delta := minf(remaining, 1.0 / 60.0)
		if advance_timers and player.has_method("advance_action_timers"):
			player.call("advance_action_timers", delta)
		player._update_viewmodel(delta)
		player._update_torch(delta)
		remaining -= delta
	player.viewmodel_renderer.sync_view()


static func _freeze_projectiles(fixture: Dictionary) -> void:
	for child in fixture.stage.get_children():
		if child is ArrowProjectile or child is MagicProjectile or child is FlailProjectile:
			child.set_physics_process(false)
			child.set_process(false)


static func inspect_pose(fixture: Dictionary, pose_id: String) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var result := {
		"pose": pose_id, "combat_state": player.combat_state, "state_time": player.state_time,
		"weapon_id": str(fixture.inventory.equipment.weapon), "offhand_id": str(fixture.inventory.equipment.offhand), "torch_enabled": player.torch_enabled, "attack_charge": player.attack_charge,
		"blocking": player.blocking, "shield_impact": player._shield_impact,
		"bow_draw": player.get_bow_draw_ratio(), "bow_recoil": player._bow_recoil, "bow_cooldown": player.bow_cooldown,
		"flail_state": player.flail_state, "flail_action_time": player.flail_action_time,
		"flail_spin_phase": player.flail_spin_phase, "staff_cast_recoil": player._cast_recoil,
		"safe_zone": player.safe_zone_mode, "velocity": str(player.velocity),
		"stamina": player.stamina, "health": player.health,
		"weapon_transform": str(player.weapon_pivot.transform), "shield_transform": str(player.shield_pivot.transform),
		"torch_transform": str(player.torch_pivot.transform), "camera_transform": str(player.camera.global_transform),
		"chest_phase": str(player.chest_hands.phase), "chest_progress": player.get_timed_interaction_progress(),
		"input_disabled": not player.is_physics_processing() and not player.is_processing_input() and not player.is_processing_unhandled_input(),
		"passed": POSE_IDS.has(pose_id),
	}
	result.passed = result.passed and result.input_disabled
	if player.has_method("get_first_person_motion_snapshot"):
		result["production_motion"] = player.call("get_first_person_motion_snapshot")
	if pose_id.begins_with("chest_"):
		result["chest_inspection"] = ARM_PREVIEW.inspect_pose(fixture, pose_id)
		result.passed = result.passed and result.chest_inspection.passed
	elif pose_id == "sword_windup" or pose_id == "sword_charge": result.passed = result.passed and player.combat_state == player.CombatState.WINDUP
	elif pose_id == "sword_strike": result.passed = result.passed and player.combat_state == player.CombatState.ACTIVE
	elif pose_id == "sword_recovery": result.passed = result.passed and player.combat_state == player.CombatState.RECOVERY
	elif pose_id.begins_with("shield_") and pose_id != "shield_idle": result.passed = result.passed and player.blocking
	elif pose_id == "bow_half": result.passed = result.passed and is_equal_approx(player.get_bow_draw_ratio(), 0.5)
	elif pose_id == "bow_full": result.passed = result.passed and is_equal_approx(player.get_bow_draw_ratio(), 1.0)
	elif pose_id == "bow_release": result.passed = result.passed and not player.bow_drawing and player._bow_recoil > 0
	elif pose_id == "flail_melee": result.passed = result.passed and player.flail_state == "melee"
	elif pose_id == "flail_spin": result.passed = result.passed and player.flail_state == "spinning"
	elif pose_id == "flail_throw": result.passed = result.passed and player.flail_state == "outbound"
	elif pose_id == "flail_return": result.passed = result.passed and player.flail_state == "returning"
	elif pose_id == "staff_cast": result.passed = result.passed and player._cast_recoil > 0 and bool(fixture.action_result.get("accepted", false))
	return result
