extends CharacterBody3D
class_name DungeonPlayer

signal died
signal item_use_finished(result: Dictionary)
signal attack_landed(damage: float, headshot: bool)
signal spell_cast(spell_id: String, stamina_spent: float)
signal arrow_fired(draw_ratio: float, stamina_spent: float)
signal flail_thrown(charge: float)
signal execution_started(enemy: DungeonEnemy)
signal execution_finished(enemy: DungeonEnemy, killed: bool)
signal timed_interaction_started(owner: Node, duration: float)
signal timed_interaction_finished(owner: Node)
signal timed_interaction_cancelled(owner: Node)

const PLAYER_LAYER := 1
const WORLD_LAYER := 2
const ENEMY_LAYER := 4
const INTERACT_LAYER := 16
const LOCATED_HIT_QUERY := preload("res://scripts/located_hit_query.gd")

const SWORD_SCENE := preload("res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb")
const DAGGER_VISUAL := preload("res://scripts/dagger_visual.gd")
const DAGGER_MOTION := preload("res://scripts/dagger_motion.gd")
const SWORD_LONG_GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const SWORD_SHIELD_ARM := preload("res://scripts/sword_shield_arm_visual.gd")
const SHIELD_SCENE := preload("res://assets/3d/player/sword_shield/round_shield.glb")
const SHIELD_DAMAGE := preload("res://scripts/shield_damage_visual.gd")
const SHIELD_SHATTER := preload("res://scripts/shield_shatter.gd")
const SHIELD_WEAR_PER_BLOCKED_DAMAGE := 0.25
const TORCH_SCENE := preload("res://assets/3d/wooden_torch/wooden_torch.glb")
const TORCH_GRIP := preload("res://scripts/torch_grip_pose.gd")
const TORCH_FIRE := preload("res://scripts/torch_flipbook_fire.gd")
const ANCIENT_OAK_TEXTURE := preload("res://assets/ai/materials/ancient_oak.png")
const PITTED_IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const SWORD_CLASH_GEOMETRY := preload("res://scripts/sword_clash_geometry.gd")
const SPELL_CATALOG_SCRIPT := preload("res://scripts/spell_catalog.gd")
const MAGIC_PROJECTILE_SCRIPT := preload("res://scripts/magic_projectile.gd")
const ARROW_PROJECTILE_SCRIPT := preload("res://scripts/arrow_projectile.gd")
const ARCHERY_VISUALS := preload("res://scripts/archery_visuals.gd")
const BOW_SHOT_PROFILE := preload("res://scripts/bow_shot_profile.gd")
const BOW_DRAW_DURATION := BOW_SHOT_PROFILE.DRAW_DURATION
const BOW_SHOT_COOLDOWN := 0.55
const BOW_DRAW_STAMINA_PER_SECOND := BOW_SHOT_PROFILE.STAMINA_DRAIN_PER_SECOND
const BOW_RECOIL_DURATION := 0.24
const FLAIL_PROFILE := preload("res://scripts/flail_profile.gd")
const FLAIL_VISUALS := preload("res://scripts/flail_visuals.gd")
const FLAIL_PROJECTILE := preload("res://scripts/flail_projectile.gd")
const CHEST_HAND_VISUALS := preload("res://scripts/chest_hand_visuals.gd")
const PLAYER_APPEARANCE := preload("res://scripts/player_appearance.gd")
const PLAYER_ARM_VISUAL := preload("res://scripts/player_arm_visual.gd")
const FIRST_PERSON_RENDERER := preload("res://scripts/first_person_renderer.gd")
const EQUIPMENT_CONCEPT := preload("res://scripts/equipment_concept_visual.gd")
const FLAME_VISUALS := preload("res://scripts/flame_visuals.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const REFERENCE_MOTION := preload("res://scripts/reference_sword_motion.gd")
const REFERENCE_ARM := preload("res://scripts/reference_sword_arm.gd")
const BODY_HEALTH := preload("res://scripts/body_health.gd")
const REAR_TAKEDOWN_MOTION := preload("res://scripts/rear_takedown_motion.gd")
const CREEP_EXECUTION_MOTION := preload("res://scripts/creep_execution_motion.gd")
const EXECUTION_MOTION := preload("res://scripts/sword_shield_execution_motion.gd")

const SWORD_CLASH_MARGIN := 0.02

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.2
const JUMP_VELOCITY := 5.2
const MAX_HEALTH := BODY_HEALTH.MAX_HEALTH
const MAX_STAMINA := 100.0
const JUST_GUARD_WINDOW := 0.20
const ATTACK_HIT_TIME := 0.055
const SWORD_CLASH_GRACE_END := 0.11
const SWORD_ATTACK_VARIANTS: Array[String] = ["right_diagonal", "left_reverse", "overhead"]
const SWORD_DIRECT_ENTRY_SECONDS := 0.10

enum CombatState { READY, WINDUP, ACTIVE, RECOVERY, GUARD_BREAK, DEAD, EXECUTION }

var execution_elapsed := 0.0
var _execution_target: DungeonEnemy
var _execution_hit_committed := false
var _execution_sword_entry := Transform3D.IDENTITY
var _execution_shield_entry := Transform3D.IDENTITY
var _execution_shield_rest := Transform3D.IDENTITY
var _execution_weapon_identity := ""
var _execution_profile := "shield_cut"
var _execution_contact_point := Vector3.ZERO
var _execution_stab_direction := Vector3.DOWN
var _execution_blade_tip := Vector3.ZERO
var _execution_blade_length := 0.0
var _execution_penetration := 0.0
var _rear_neck_contact := Vector3.ZERO
var _rear_stab_contact_committed := false
var _rear_entry_yaw := 0.0
var _rear_entry_pitch := 0.0
var _rear_stab_basis := Basis.IDENTITY
var _rear_arm_entry: Dictionary = {}
var _rear_approach_obstruction_m := 0.0
var _rear_approach_offset := Vector3.ZERO
var _rear_approach_progress := 0.0

var _body_health_state: Dictionary = BODY_HEALTH.create_state()
var _body_health_session_bound := false
var _last_body_health := MAX_HEALTH
# Explicit assignments are reserved for QA/reset fixtures. Actual recovery
# calls restore_health, which cannot heal destroyed parts or revive the dead.
var health: float:
	get:
		return BODY_HEALTH.total_health(_body_state())
	set(value):
		BODY_HEALTH.set_total_for_debug(_body_state(), value)
		_last_body_health = BODY_HEALTH.total_health(_body_state())
var stamina := MAX_STAMINA
var combat_state := CombatState.READY
var state_time := 0.0
var attack_charge := 0.0
var attack_release_requested := false
var attack_hit_ids: Dictionary = {}
var sword_attack_variant := "right_diagonal"
var sword_attack_mode := "cycle"
var _sword_next_attack_index := 0
var _sword_attack_uses_cycle := false
var _sword_attack_had_shield := false
var _sword_attack_coordinated := false
var _sword_direct_entry := false
var _sword_entry_pose := Transform3D.IDENTITY
var _sword_entry_shield_pose := Transform3D.IDENTITY
var _sword_entry_shield_clock := 0.0
var _sword_entry_arm: Dictionary = {}
var _sword_clash_recovering := false
var _sword_clash_weapon_pose := Transform3D.IDENTITY
var _sword_clash_shield_pose := Transform3D.IDENTITY
var blocking := false
var block_time := 0.0
var stamina_regen_delay := 0.0
var trap_lockout := 0.0
var current_trap: Node = null

# Public so headless tests and later difficulty options can accelerate authored
# interaction times without bypassing the same completion/cancellation path.
@export_range(0.0, 4.0, 0.05) var interaction_duration_scale := 1.0
@export var safe_zone_mode := false
var camping := false
var _pre_camp_pitch := 0.0
var timed_interaction_owner: Node = null
var timed_interaction_duration := 0.0
var timed_interaction_elapsed := 0.0
var timed_interaction_title := ""
var chest_hands: Node3D
var _item_use: Dictionary = {}
var _item_use_inventory: ExpeditionInventory
var last_item_use_result: Dictionary = {}

var bandage_hands: Node3D
var splint_hands: Node3D
var potion_hands: Node3D
var jerky_hands: Node3D
var chest_equipment_stowed := false
var _chest_stow_amount := 0.0
var _chest_carried_poses: Dictionary = {}

var game: Node
var hud: DungeonHUD
var inventory_model: ExpeditionInventory
var player_body: Node3D
var head: Node3D
var camera: Camera3D
var viewmodel_renderer: Node
var weapon_arm: Node3D
var _legacy_weapon_arm: Node3D
var _sword_weapon_arm: Node3D
var shield_arm: Node3D
var torch_arm: Node3D
var support_arm_root: Node3D
var left_support_arm: Node3D
var right_relaxed_arm: Node3D
var shield_model: Node3D
var _shield_debris: Node3D
var _shield_shatter_count := 0
var _shield_wear_resolving := false
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const SHIELD_CORNER_OFFSET := Vector3(-0.23, -0.40, 0.0)
var _shield_raise_progress := 0.0
var _joint_landmarks: Dictionary = {}
var _motion_clock := 0.0
var _motion_equip_elapsed := MOTION.EQUIP_DURATION
const SWORD_DRAW_DURATION := 1.5
var _sword_draw_elapsed := SWORD_DRAW_DURATION
var _draw_sword := false
var _draw_shield := false
var _displayed_offhand := ""
var _draw_reach_material: StandardMaterial3D
var _draw_reach_overrides: Dictionary = {}
const SHIELD_STOW_DURATION := 0.55
const SWORD_SUPPORT_DURATION := 0.48
const SWORD_SUPPORT_GRIP := Vector3(0.0, -0.235, 0.002)
var sword_support_arm: Node3D
var _shield_stowed := false
var _suppress_automatic_torch_hand := false
var _shield_stow_elapsed := SHIELD_STOW_DURATION
var _shield_stow_from := Transform3D.IDENTITY
var _motion_initialized := false
var _motion_flail_phase := "ready"
var _motion_flail_elapsed := 0.0
var _motion_flail_transition_from := Transform3D.IDENTITY
var _motion_speed := 0.0
var _motion_look_sway := Vector2.ZERO
var _motion_previous_look := Vector2.ZERO
# Only observed move_and_slide results establish the floor state. Preview
# fixtures without physics must not be mistaken for airborne characters.
var _movement_ground_known := false
var _movement_grounded := false
var _movement_phase := "grounded"
var _movement_phase_time := 0.0
var _movement_run_time := 0.0
var _movement_jump_pending := false
var _movement_landing_count := 0
var _movement_landing_strength := 0.0
var _reference_locomotion_valid := false
var _reference_locomotion_key := ""
var _reference_locomotion_elapsed := 0.0
var _reference_locomotion_from := Transform3D.IDENTITY
var _reference_locomotion_pose := Transform3D.IDENTITY
var _reference_shield_valid := false
var _reference_shield_from := Transform3D.IDENTITY
var _reference_shield_pose := Transform3D.IDENTITY
var _reference_pose_key := ""
var _reference_pose_handoff_active := false
var _reference_pose_handoff_elapsed := 0.0
var _reference_pose_weapon_from := Transform3D.IDENTITY
var _reference_pose_shield_from := Transform3D.IDENTITY
var _reference_arm_target: Dictionary = {}
var _reference_arm_rendered: Dictionary = {}
var _reference_arm_locomotion_from: Dictionary = {}
var _reference_arm_handoff_from: Dictionary = {}
var _reference_arm_clash_from: Dictionary = {}
var _reference_arm_previous_bend := Vector3.ZERO
var _bow_release_anchor := Vector3.ZERO
var _bow_release_draw := 0.0
var _hand_contacts: Dictionary = {}
var hands_greybox_enabled := false
var hands_detailed_enabled := false
var hands_visual_profile := "original"
var finger_joint_review_active := false
var _finger_joint_review_values: Dictionary = {}
var _finger_joint_review_profile := "original"
var _finger_joint_review_view := "dorsal"
var weapon_pivot: Node3D
var dagger_visual_root: Node3D
var _dagger_contact_resolved := false
var sword_visual_root: Node3D
var sword_blade: MeshInstance3D
var staff_visual_root: Node3D
var staff_muzzle: Marker3D
var staff_crystal: MeshInstance3D
var staff_light: OmniLight3D
var bow_visual_root: Node3D
var bow_drawing := false
var bow_draw_time := 0.0
var bow_draw_stamina_spent := 0.0
var bow_cooldown := 0.0
var _bow_recoil := 0.0
var bow_recoil_strength := 0.0
var _bow_recoil_side := 0.0
var bow_shot_rng := RandomNumberGenerator.new()
var flail_visual_root: Node3D
var flail_state := "ready"
var flail_spin_time := 0.0
var flail_spin_phase := 0.0
var flail_action_time := 0.0
var flail_cooldown := 0.0
var flail_projectile: Node3D
var _flail_release_pending := false
var _flail_release_aim := Vector3.ZERO
var _flail_melee_hit_done := false
var _flail_cancel_from := Vector3.ZERO
var _flail_cancel_remaining := 0.0
var _flail_cancel_weapon_pose := Transform3D.IDENTITY
var shield_pivot: Node3D
var torch: SpotLight3D
var torch_fill: OmniLight3D
var torch_pivot: Node3D
var torch_flame: Node3D
var torch_enabled := true
var _torch_draw_elapsed := 0.0
var interaction_owner: Node = null
var gravity := 18.0

var _pitch := 0.0
var _bob_time := 0.0
var _camera_shake := 0.0
var _shield_impact := 0.0
var _torch_time := 0.0
var _spell_visual_time := 0.0
var _cast_recoil := 0.0
var _displayed_weapon_type := ""
var _displayed_weapon_identity := ""
var _smithing_visual_signature := ""
var spell_cooldown := 0.0


func _init() -> void:
	# Keep arrow dispersion independent of enemy AI, damage shake and VFX RNG.
	# Tests can seed this generator without changing production shot behavior.
	bow_shot_rng.randomize()


func setup(game_ref: Node, hud_ref: DungeonHUD, inventory_ref: ExpeditionInventory = null) -> void:
	game = game_ref
	hud = hud_ref
	if is_instance_valid(hud): hud.item_use_player = self
	bind_inventory(inventory_ref)


func bind_inventory(model: ExpeditionInventory) -> void:
	_body_health_state = _body_state().duplicate(true)
	if inventory_model != null and inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.disconnect(_on_inventory_changed)
	if inventory_model != null and inventory_model.equipment_condition_changed.is_connected(_on_equipment_condition_changed):
		inventory_model.equipment_condition_changed.disconnect(_on_equipment_condition_changed)
	inventory_model = model
	_body_health_session_bound = model != null and ExpeditionSession.journey_started and model == ExpeditionSession.get_inventory()
	if _body_health_session_bound:
		_body_health_state = ExpeditionSession.body_health
		_last_body_health = health
	if inventory_model != null and not inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.connect(_on_inventory_changed)
	if inventory_model != null and not inventory_model.equipment_condition_changed.is_connected(_on_equipment_condition_changed):
		inventory_model.equipment_condition_changed.connect(_on_equipment_condition_changed)
	_sync_equipped_weapon()


func _exit_tree() -> void:
	clear_shield_fragments()
	cancel_execution()
	cancel_item_use()
	cancel_timed_interaction()
	set_chest_container_open(false)
	cancel_flail_action()
	if inventory_model != null and inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.disconnect(_on_inventory_changed)
	if inventory_model != null and inventory_model.equipment_condition_changed.is_connected(_on_equipment_condition_changed):
		inventory_model.equipment_condition_changed.disconnect(_on_equipment_condition_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_execution()
		cancel_item_use()
		cancel_timed_interaction("상호작용을 중단했습니다")
		cancel_bow_draw()
		cancel_flail_action()


func get_inventory_status_snapshot() -> Dictionary:
	return {
		"health": health,
		"max_health": MAX_HEALTH,
		"body_health": get_body_health_snapshot(),
		"stamina": stamina,
		"max_stamina": MAX_STAMINA,
		"stress": ExpeditionSession.stress,
		"max_stress": StressProfile.MAX_STRESS,
		"stress_stage": StressProfile.stage_name(ExpeditionSession.stress)
	}


func configure_safe_zone(enabled: bool) -> void:
	if enabled and camping and is_instance_valid(game) and game.has_method("cancel_camp"):
		game.cancel_camp("안전 지대로 이동하여 야영을 정리했습니다")
	safe_zone_mode = enabled
	if enabled:
		cancel_timed_interaction()
		set_chest_container_open(false)
		cancel_bow_draw()
		cancel_flail_action()
		cancel_sword_attack()
	_refresh_carried_visibility()


func set_camping(enabled: bool) -> void:
	if enabled: cancel_item_use()
	if camping == enabled:
		return
	if enabled:
		prepare_for_inventory()
		_pre_camp_pitch = _pitch
	camping = enabled
	velocity = Vector3.ZERO
	_pitch = deg_to_rad(-26.0) if camping else _pre_camp_pitch
	if is_instance_valid(head):
		head.rotation.x = _pitch
	_refresh_carried_visibility()
	if is_instance_valid(hud) and hud.is_inside_tree():
		hud.crosshair.visible = not camping
		_refresh_magic_hud()


func _interrupt_camp(reason: String) -> void:
	if camping and is_instance_valid(game) and game.has_method("cancel_camp"):
		game.cancel_camp(reason)


func _ready() -> void:
	add_to_group("player")
	name = "Player"
	collision_layer = PLAYER_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	_build_body()
	_build_viewmodel()
	if hud:
		hud.update_health(health, MAX_HEALTH)
		hud.update_stamina(stamina, MAX_STAMINA)
		hud.update_torch(torch_enabled)
	_refresh_survival_hud()
	_sync_equipped_weapon()
	_refresh_magic_hud()


func _build_body() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.78
	collision.shape = capsule
	add_child(collision)

	player_body = PLAYER_APPEARANCE.create_body()
	player_body.position.y = -0.89
	add_child(player_body)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.67, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.current = true
	camera.fov = 76.0
	camera.near = 0.05
	camera.cull_mask &= ~PLAYER_APPEARANCE.BODY_LAYER
	head.add_child(camera)

func _build_viewmodel() -> void:
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.46, -0.42, -0.78)
	weapon_pivot.rotation = Vector3(deg_to_rad(-9), deg_to_rad(-15), deg_to_rad(-8))
	camera.add_child(weapon_pivot)

	var dark_steel := _textured_material(Color(0.55, 0.58, 0.58), PITTED_IRON_TEXTURE, 0.42, 0.84, 3.2)
	var blade_steel := _material(Color(0.36, 0.39, 0.40), 0.36, 0.58)
	var rusted_steel := _textured_material(Color(0.48, 0.20, 0.11), PITTED_IRON_TEXTURE, 0.48, 0.74, 4.2)
	var leather := _material(Color(0.16, 0.075, 0.035), 0.88, 0.05)

	_build_sword_visual(dark_steel, blade_steel, rusted_steel)
	_build_staff_visual(dark_steel, leather)
	bow_visual_root = ARCHERY_VISUALS.create_bow()
	bow_visual_root.name = "HuntingBowVisual"
	weapon_pivot.add_child(bow_visual_root)
	bow_visual_root.visible = false
	flail_visual_root = FLAIL_VISUALS.create_flail()
	flail_visual_root.name = "ChainFlailVisual"
	weapon_pivot.add_child(flail_visual_root)
	flail_visual_root.visible = false
	_legacy_weapon_arm = _add_character_arm(weapon_pivot, Vector3(0.0, -0.17, 0.015), 1)
	_sword_weapon_arm = SWORD_LONG_GRIP.new()
	_sword_weapon_arm.name = "LongGripSwordArm"
	weapon_pivot.add_child(_sword_weapon_arm)
	_sword_weapon_arm.setup(1)
	weapon_arm = _sword_weapon_arm

	_build_shield(dark_steel, leather)
	_build_equipped_torch(dark_steel)
	support_arm_root = Node3D.new()
	support_arm_root.name = "FreeHandPresentation"
	camera.add_child(support_arm_root)
	left_support_arm = _add_character_arm(support_arm_root, Vector3(-0.36, -0.34, -0.44), -1)
	left_support_arm.name = "LeftSupportArm"
	sword_support_arm = _add_sword_shield_arm(support_arm_root, -1)
	sword_support_arm.name = "LeftSwordGripArm"
	sword_support_arm.set("long_grip_surface", true)
	sword_support_arm.visible = false
	right_relaxed_arm = _add_character_arm(support_arm_root, Vector3(0.38, -0.38, -0.42), 1)
	right_relaxed_arm.name = "RightRelaxedArm"
	right_relaxed_arm.visible = false
	chest_hands = CHEST_HAND_VISUALS.new()
	chest_hands.name = "ChestHands"
	chest_hands.setup(self)
	add_child(chest_hands)
	bandage_hands = preload("res://scripts/bandage_use_visuals.gd").new()
	bandage_hands.name = "BandageUseHands"
	camera.add_child(bandage_hands)
	bandage_hands.visible = false
	splint_hands = preload("res://scripts/splint_use_visuals.gd").new()
	splint_hands.name = "SplintUseHands"
	camera.add_child(splint_hands)
	splint_hands.visible = false
	potion_hands = preload("res://scripts/potion_drink_visuals.gd").new()
	potion_hands.name = "PotionDrinkHands"
	camera.add_child(potion_hands)
	potion_hands.visible = false
	jerky_hands = preload("res://scripts/jerky_eat_visuals.gd").new()
	jerky_hands.name = "JerkyEatHands"
	camera.add_child(jerky_hands)
	jerky_hands.visible = false
	viewmodel_renderer = FIRST_PERSON_RENDERER.new()
	viewmodel_renderer.name = "FirstPersonRenderer"
	add_child(viewmodel_renderer)
	viewmodel_renderer.setup(camera, [weapon_pivot, shield_pivot, torch_pivot, support_arm_root, bandage_hands, splint_hands, potion_hands, jerky_hands])
	configure_safe_zone(safe_zone_mode)


func _build_sword_visual(dark_steel: StandardMaterial3D, blade_steel: StandardMaterial3D, rusted_steel: StandardMaterial3D) -> void:
	sword_visual_root = SWORD_LONG_GRIP.create_sword()
	sword_visual_root.name = "RustedLongswordVisual"
	weapon_pivot.add_child(sword_visual_root)
	dagger_visual_root = DAGGER_VISUAL.create_dagger()
	weapon_pivot.add_child(dagger_visual_root)
	dagger_visual_root.visible = false
	sword_blade = sword_visual_root.find_child("PittedBlade", true, false) as MeshInstance3D


func _build_staff_visual(iron: StandardMaterial3D, leather: StandardMaterial3D) -> void:
	staff_visual_root = Node3D.new()
	staff_visual_root.name = "WeatheredStaffVisual"
	staff_visual_root.position = Vector3(0.10, -0.54, -0.10)
	staff_visual_root.rotation.z = deg_to_rad(-7.0)
	weapon_pivot.add_child(staff_visual_root)

	var staff_wood := _textured_material(Color(0.34, 0.20, 0.095), ANCIENT_OAK_TEXTURE, 0.93, 0.01, 3.4)
	var shaft := _cylinder_mesh(0.038, 0.052, 1.30, staff_wood)
	shaft.name = "StaffShaft"
	shaft.position.y = 0.25
	staff_visual_root.add_child(shaft)
	var grip := _cylinder_mesh(0.058, 0.058, 0.36, leather)
	grip.name = "StaffLeatherGrip"
	grip.position.y = -0.28
	staff_visual_root.add_child(grip)
	for band_y in [-0.39, -0.14, 0.73]:
		var band := _cylinder_mesh(0.068, 0.068, 0.055, iron)
		band.name = "StaffIronBand"
		band.position.y = band_y
		staff_visual_root.add_child(band)

	var prong_left := _cylinder_mesh(0.018, 0.025, 0.28, staff_wood)
	prong_left.name = "CrystalProngLeft"
	prong_left.position = Vector3(-0.07, 0.88, 0)
	prong_left.rotation.z = deg_to_rad(-31.0)
	staff_visual_root.add_child(prong_left)
	var prong_right := _cylinder_mesh(0.018, 0.025, 0.28, staff_wood)
	prong_right.name = "CrystalProngRight"
	prong_right.position = Vector3(0.07, 0.88, 0)
	prong_right.rotation.z = deg_to_rad(31.0)
	staff_visual_root.add_child(prong_right)

	var crystal_material := _material(Color(0.18, 0.74, 0.68), 0.18, 0.12)
	crystal_material.emission_enabled = true
	crystal_material.emission = Color(0.08, 0.9, 0.75)
	crystal_material.emission_energy_multiplier = 1.45
	staff_crystal = _sphere_mesh(0.075, crystal_material)
	staff_crystal.name = "CrackedFocusCrystal"
	staff_crystal.position = Vector3(0, 0.98, 0)
	staff_crystal.scale = Vector3(0.66, 1.18, 0.66)
	staff_visual_root.add_child(staff_crystal)

	staff_light = OmniLight3D.new()
	staff_light.name = "StaffFocusLight"
	staff_light.position = staff_crystal.position
	staff_light.light_color = Color(0.23, 0.94, 0.82)
	staff_light.light_energy = 0.45
	staff_light.omni_range = 1.6
	staff_light.shadow_enabled = false
	staff_visual_root.add_child(staff_light)

	staff_muzzle = Marker3D.new()
	staff_muzzle.name = "SpellMuzzle"
	staff_muzzle.position = Vector3(0, 1.01, -0.06)
	staff_visual_root.add_child(staff_muzzle)
	staff_visual_root.visible = false
	EQUIPMENT_CONCEPT.apply_staff(staff_visual_root)


func _build_shield(iron: StandardMaterial3D, leather: StandardMaterial3D) -> void:
	shield_pivot = Node3D.new()
	shield_pivot.name = "ShieldPivot"
	shield_pivot.position = Vector3(-0.72, -0.76, -0.82)
	shield_pivot.rotation = Vector3(deg_to_rad(-18), deg_to_rad(18), deg_to_rad(-12))
	camera.add_child(shield_pivot)

	shield_model = SHIELD_SCENE.instantiate() as Node3D
	SHIELD_SHATTER.prepare()
	shield_model.name = "WeatheredRoundShieldVisual"
	# The owner sees its actual rear straps; the boss faces the opponent.
	shield_model.rotation.y = PI
	shield_pivot.add_child(shield_model)
	_prepare_sword_shield_materials(shield_model)
	shield_arm = _add_sword_shield_arm(shield_pivot, -1)


func _build_equipped_torch(_iron: StandardMaterial3D) -> void:
	# Utility-slot torch: it remains equipped alongside sword and shield until the
	# later shop/loadout pass introduces real equipment slots and fuel condition.
	torch_pivot = Node3D.new()
	torch_pivot.name = "EquippedTorch"
	torch_pivot.position = TORCH_GRIP.STOW_POSITION
	torch_pivot.rotation_degrees = TORCH_GRIP.STOW_ROTATION
	camera.add_child(torch_pivot)

	var torch_model := TORCH_SCENE.instantiate() as Node3D
	torch_model.name = "WoodenTorchVisual"
	torch_pivot.add_child(torch_model)
	for part in torch_model.find_children("*", "MeshInstance3D", true, false):
		for surface in part.mesh.get_surface_count():
			var source_material = part.get_active_material(surface)
			if source_material is StandardMaterial3D:
				var wood_material = source_material.duplicate()
				wood_material.metallic = 0.0
				wood_material.metallic_texture = null
				wood_material.roughness = 0.9
				wood_material.roughness_texture = null
				part.set_surface_override_material(surface, wood_material)
	torch_flame = TORCH_FIRE.create()
	torch_flame.name = "Flame"
	torch_flame.position.y = TORCH_FIRE.CLOTH_BASE
	torch_pivot.add_child(torch_flame)
	torch_arm = _add_character_arm(torch_pivot, Vector3(0.0, 0.12, 0.0), -1)

	torch_fill = OmniLight3D.new()
	torch_fill.name = "TorchFillLight"
	torch_fill.light_color = Color(1.0, 0.49, 0.25)
	torch_fill.light_energy = 2.4
	torch_fill.omni_range = 7.2
	torch_fill.shadow_enabled = false
	torch_flame.add_child(torch_fill)

	torch = SpotLight3D.new()
	torch.name = "TorchForwardLight"
	torch.position = Vector3(-0.16, -0.03, -0.08)
	torch.spot_range = 19.0
	torch.spot_angle = 60.0
	torch.light_energy = 4.9
	torch.light_color = Color(1.0, 0.64, 0.40)
	torch.shadow_enabled = true
	camera.add_child(torch)
	set_torch_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	if combat_state == CombatState.DEAD or camping or is_paralyzed():
		return
	if is_execution_active():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and current_trap == null:
		rotate_y(-event.relative.x * 0.00215)
		_pitch = clampf(_pitch - event.relative.y * 0.00215, deg_to_rad(-82), deg_to_rad(78))
		head.rotation.x = _pitch
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		cancel_bow_draw()
		cancel_flail_action()
		if combat_state in [CombatState.WINDUP, CombatState.ACTIVE, CombatState.RECOVERY]:
			cancel_sword_attack()
		return
	if is_item_use_active():
		return
	if safe_zone_mode:
		return
	if is_timed_interacting():
		return
	if is_instance_valid(hud) and hud.combat_enabled and is_instance_valid(hud.combat_panel):
		if event is InputEventKey and event.pressed and event.alt_pressed and not event.echo:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var spell_index: int = hud.combat_panel.KEYS.find(key)
			if spell_index >= 0:
				select_spell_by_slot(spell_index)
				get_viewport().set_input_as_handled()
				return
		if hud.combat_panel.handle_shortcut(event):
			get_viewport().set_input_as_handled()
			return
	if handle_primary_weapon_input(event):
		get_viewport().set_input_as_handled()
		return
	if _is_flail_equipped():
		if event.is_action_pressed("attack"):
			begin_flail_melee()
		elif event.is_action_pressed("block"):
			begin_flail_spin()
		elif event.is_action_released("block"):
			release_flail_throw()
		return
	if event is InputEventKey and event.pressed and not event.echo and current_trap == null:
		for spell_index in range(SPELL_CATALOG_SCRIPT.SPELL_ORDER.size()):
			if event.is_action_pressed("spell_%d" % (spell_index + 1)):
				select_spell_by_slot(spell_index)
				return
	if event.is_action_pressed("attack"):
		if _is_bow_equipped():
			begin_bow_draw()
		elif _is_staff_equipped():
			_try_cast_selected_spell()
		elif _has_melee_weapon_equipped():
			_try_begin_attack()
		elif hud:
			hud.show_event("먼저 주무기를 장착하십시오", 0.8)
	elif event.is_action_released("attack") and bow_drawing:
		release_bow_shot()
	elif event.is_action_pressed("block") and _is_bow_equipped():
		cancel_bow_draw()
	elif event.is_action_released("attack") and combat_state == CombatState.WINDUP and _has_melee_weapon_equipped():
		attack_release_requested = true


func _physics_process(delta: float) -> void:
	sync_body_health_from_session()
	advance_item_use(delta)
	if combat_state == CombatState.DEAD or camping or get_tree().paused:
		return
	if safe_zone_mode:
		ExpeditionSession.relieve_stress(StressProfile.SAFE_RECOVERY_RATE * maxf(0.0, delta))
		_refresh_survival_hud()
	if timed_interaction_owner != null and not is_instance_valid(timed_interaction_owner):
		_clear_timed_interaction_state()
	advance_action_timers(delta)
	_update_combat(delta)
	_update_movement(delta)
	_update_interaction(delta)
	_update_viewmodel(delta)
	_update_torch(delta)
	_update_stamina(delta)


func advance_action_timers(delta: float) -> void:
	if delta <= 0.0 or camping or combat_state == CombatState.DEAD or (is_inside_tree() and get_tree().paused):
		return
	trap_lockout = maxf(0.0, trap_lockout - delta)
	stamina_regen_delay = maxf(0.0, stamina_regen_delay - delta)
	spell_cooldown = maxf(0.0, spell_cooldown - delta)
	bow_cooldown = maxf(0.0, bow_cooldown - delta)
	_bow_recoil = maxf(0.0, _bow_recoil - delta)
	if _bow_recoil <= 0.0:
		bow_recoil_strength = 0.0
	_cast_recoil = maxf(0.0, _cast_recoil - delta)


func _update_movement(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		request_jump()
	var movement := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	advance_movement(delta, movement, Input.is_action_pressed("sprint"))


func request_jump() -> Dictionary:
	# Gameplay and headless physics trials use this exact acceptance path.
	var reason := ""
	if is_paralyzed() or get_body_movement_multiplier() < 1.0:
		reason = "injured"
	elif camping or combat_state == CombatState.DEAD:
		reason = "unavailable"
	elif is_inside_tree() and get_tree().paused:
		reason = "paused"
	elif not is_on_floor() or _movement_jump_pending:
		reason = "not_grounded"
	elif current_trap != null or is_timed_interacting() or bow_drawing or _is_flail_busy() or combat_state != CombatState.READY:
		reason = "busy"
	elif stamina < 12.0:
		reason = "not_enough_stamina"
	if not reason.is_empty():
		return {"accepted": false, "reason": reason, "stamina_spent": 0.0}
	velocity.y = JUMP_VELOCITY
	_consume_stamina(12.0)
	_movement_jump_pending = true
	_set_movement_phase("takeoff")
	return {"accepted": true, "reason": "", "stamina_spent": 12.0}


func advance_movement(delta: float, movement_input: Vector2, sprint_requested: bool = false) -> void:
	# Shared production movement; test callers supply intent, never fake floor
	# flags, landing events, resource costs or the result of move_and_slide.
	if delta <= 0.0 or camping or combat_state == CombatState.DEAD or (is_inside_tree() and get_tree().paused):
		return
	if is_execution_active():
		_advance_execution_movement(delta)
		return
	_movement_phase_time += delta
	if not is_on_floor() and not _movement_jump_pending:
		velocity.y -= gravity * delta
	var movement := movement_input.limit_length(1.0)
	if current_trap != null or is_timed_interacting() or is_paralyzed():
		movement = Vector2.ZERO
	if is_paralyzed():
		velocity.x = 0.0
		velocity.z = 0.0
	var local_direction := Vector3(movement.x, 0, movement.y)
	var direction := (global_transform.basis * local_direction).normalized()
	var speed := WALK_SPEED
	var sprinting := get_body_movement_multiplier() >= 1.0 and not is_timed_interacting() and not bow_drawing and not _is_flail_busy() and sprint_requested and movement.y < -0.15 and stamina > 0.0
	if sprinting and combat_state == CombatState.READY and not blocking and current_trap == null:
		speed = SPRINT_SPEED
		_consume_stamina(17.0 * delta)
	if movement.y > 0.1:
		speed *= 0.72
	elif absf(movement.x) > 0.1:
		speed *= 0.86
	if combat_state != CombatState.READY:
		speed *= 0.56
	if blocking:
		speed *= 0.48
	if bow_drawing:
		speed *= 0.55
	if _is_flail_busy():
		speed *= 0.65
	speed *= get_body_movement_multiplier()
	var acceleration := 18.0 if direction != Vector3.ZERO else 24.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	var vertical_before_collision := velocity.y
	move_and_slide()
	_observe_movement_floor(vertical_before_collision)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if _movement_grounded and planar_speed > 0.01:
		_movement_run_time += delta * clampf(planar_speed / WALK_SPEED, 0.0, 1.0)
	if is_on_floor() and planar_speed > 0.3:
		_bob_time += delta * (10.5 if sprinting else 7.3)
		head.position.y = 0.67 + sin(_bob_time) * minf(planar_speed / WALK_SPEED, 1.0) * 0.025
	else:
		head.position.y = lerpf(head.position.y, 0.67, minf(delta * 8.0, 1.0))


func _observe_movement_floor(vertical_before_collision: float) -> void:
	var grounded_now := is_on_floor()
	var landed := _movement_ground_known and not _movement_grounded and grounded_now
	_movement_ground_known = true
	_movement_grounded = grounded_now
	if grounded_now:
		if landed:
			_movement_landing_count += 1
			_movement_landing_strength = clampf(-vertical_before_collision / JUMP_VELOCITY, 0.15, 1.0)
			_set_movement_phase("land")
		elif _movement_phase != "land" or _movement_phase_time >= _movement_clip_duration("land", 0.24):
			_set_movement_phase("grounded")
	else:
		if _movement_jump_pending:
			_set_movement_phase("takeoff")
		elif _movement_phase != "takeoff" or _movement_phase_time >= _movement_clip_duration("takeoff", 0.16) or velocity.y <= 0.0:
			_set_movement_phase("air")
	_movement_jump_pending = false


func _set_movement_phase(phase: String) -> void:
	if _movement_phase != phase:
		_movement_phase = phase
		_movement_phase_time = 0.0


func _movement_clip_duration(clip: String, fallback: float) -> float:
	var metadata := REFERENCE_MOTION.clip_metadata(clip)
	return float(metadata.get("duration_seconds", fallback))


func reset_reference_movement_motion(reset_landing_count: bool = false) -> void:
	_movement_ground_known = false
	_movement_grounded = false
	_movement_phase = "grounded"
	_movement_phase_time = 0.0
	_movement_run_time = 0.0
	_movement_jump_pending = false
	_movement_landing_strength = 0.0
	_reference_locomotion_valid = false
	_reference_shield_valid = false
	_reference_locomotion_key = ""
	_reference_locomotion_elapsed = 0.0
	_reference_pose_key = ""
	_reference_pose_handoff_active = false
	_reference_pose_handoff_elapsed = 0.0
	_reference_arm_target.clear()
	_reference_arm_rendered.clear()
	_reference_arm_locomotion_from.clear()
	_reference_arm_handoff_from.clear()
	_reference_arm_clash_from.clear()
	_reference_arm_previous_bend = Vector3.ZERO
	if reset_landing_count:
		_movement_landing_count = 0


func _update_combat(delta: float) -> void:
	if is_paralyzed():
		blocking = false
		return
	advance_combat_state(delta, Input.is_action_pressed("block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func advance_combat_state(delta: float, block_requested: bool = false) -> void:
	if camping or combat_state == CombatState.DEAD or delta <= 0.0 or is_paralyzed():
		if is_paralyzed():
			blocking = false
		return
	# The normal dungeon controller processes while paused. Never let held bow
	# stamina (or charge time) advance through that inherited processing mode.
	if is_inside_tree() and get_tree().paused:
		return
	if safe_zone_mode:
		cancel_bow_draw()
		cancel_flail_action()
		cancel_sword_attack()
		return
	if is_execution_active():
		advance_execution(delta)
		return
	state_time += delta
	_update_flail(delta)
	var wants_block := block_requested and not _is_bow_equipped() and not _is_flail_equipped() and current_trap == null and not is_timed_interacting()
	if bow_drawing:
		if not _is_bow_equipped() or current_trap != null or is_timed_interacting() or combat_state != CombatState.READY or get_arrow_count() <= 0:
			cancel_bow_draw()
		else:
			_advance_bow_draw(delta)
	_refresh_archery_hud()
	if combat_state == CombatState.READY:
		if wants_block and stamina > 0.0:
			if not blocking:
				block_time = 0.0
			blocking = true
			block_time += delta
		else:
			blocking = false
			block_time = 0.0
	elif combat_state != CombatState.GUARD_BREAK:
		blocking = false

	match combat_state:
		CombatState.READY:
			if hud:
				if blocking:
					var guard_caption := "방패 가드 · 피해 완전 차단" if _has_shield_equipped() else "무기 가드"
					if block_time <= JUST_GUARD_WINDOW:
						guard_caption += " · 저스트 가드"
					hud.update_weapon_state(guard_caption, Color(0.52, 0.75, 0.78))
				elif wants_block and _has_shield_equipped() and stamina <= 0.0:
					hud.update_weapon_state("기력 부족 · 방패를 들 수 없습니다", Color(0.9, 0.58, 0.3))
				elif _is_flail_equipped():
					var captions := {"ready": "사슬철퇴 준비", "melee": "철퇴 휘두르기", "spinning": "옆으로 회전 · %d%%" % roundi(get_flail_charge() * 100.0), "outbound": "철퇴 투척 중", "returning": "사슬 회수 중", "recovery": "철퇴 자세 회복"}
					hud.update_weapon_state(str(captions.get(flail_state, "사슬철퇴")), Color(0.78, 0.80, 0.86))
				elif _is_bow_equipped():
					if bow_drawing:
						var damage_caption := "최대 피해" if get_bow_draw_ratio() >= 1.0 else "피해"
						hud.update_weapon_state("시위 %d%% · %s %d" % [roundi(get_bow_draw_ratio() * 100), damage_caption, roundi(get_bow_damage())], Color(0.91, 0.72, 0.4))
					elif bow_cooldown > 0.0:
						hud.update_weapon_state("다음 화살 준비 · %.1f초" % bow_cooldown, Color(0.67, 0.62, 0.5))
					else:
						hud.update_weapon_state("활 준비 · 화살 %d발" % get_arrow_count(), Color(0.83, 0.74, 0.51))
				elif _is_staff_equipped():
					var selected_spell := ExpeditionSession.get_selected_spell()
					if selected_spell.is_empty():
						hud.update_weapon_state("지팡이 준비 · 배운 주문 없음", Color(0.35, 0.77, 0.72))
					elif spell_cooldown > 0.0:
						hud.update_weapon_state("%s · 재정렬 %.1f초" % [SPELL_CATALOG_SCRIPT.get_spell_name(selected_spell), spell_cooldown], Color(0.45, 0.62, 0.66))
					else:
						hud.update_weapon_state("%s · 시전 준비" % SPELL_CATALOG_SCRIPT.get_spell_name(selected_spell), Color(0.38, 0.83, 0.72))
				elif not _has_melee_weapon_equipped():
					hud.update_weapon_state("주무기 없음", Color(0.58, 0.55, 0.5))
				else:
					hud.update_weapon_state("무기 준비", Color(0.72, 0.77, 0.78))
		CombatState.WINDUP:
			attack_charge = clampf((state_time - 0.24) / 1.0, 0.0, 1.0)
			if hud:
				hud.update_weapon_state("공격 준비  %d%%" % roundi(attack_charge * 100.0), Color(0.92, 0.68, 0.34))
			if (attack_release_requested and state_time >= _sword_minimum_windup_seconds()) or state_time >= 1.24:
				_commit_attack()
		CombatState.ACTIVE:
			pass
		CombatState.RECOVERY:
			if hud:
				hud.update_weapon_state("자세 회복 중", Color(0.58, 0.55, 0.5))
			var recovery := DAGGER_MOTION.RECOVERY_SECONDS if is_dagger_equipped() else lerpf(0.47, 0.68, attack_charge)
			if state_time >= recovery:
				_set_combat_state(CombatState.READY)
		CombatState.GUARD_BREAK:
			if hud:
				hud.update_weapon_state("가드 붕괴", Color(0.9, 0.24, 0.14))
			if state_time >= 1.05:
				_set_combat_state(CombatState.READY)


func set_sword_attack_mode(mode: String) -> bool:
	# Selecting a trial while its menu is paused is safe; an existing windup
	# retains its chosen variation until it finishes or is explicitly cancelled.
	if mode != "cycle" and not SWORD_ATTACK_VARIANTS.has(mode):
		return false
	if combat_state != CombatState.READY:
		return false
	sword_attack_mode = mode
	_sword_next_attack_index = 0
	_sword_attack_uses_cycle = false
	sword_attack_variant = get_next_sword_attack_variant()
	return true


func get_next_sword_attack_variant() -> String:
	if not _uses_coordinated_sword_motion():
		return SWORD_ATTACK_VARIANTS[0]
	if sword_attack_mode == "cycle":
		return SWORD_ATTACK_VARIANTS[_sword_next_attack_index % SWORD_ATTACK_VARIANTS.size()]
	return sword_attack_mode


func _uses_coordinated_sword_motion() -> bool:
	if is_dagger_equipped():
		return false
	# Attack presentation/timing is independent of shield defense. Retain the
	# chosen clock throughout a swing even if the support hand changes roles.
	if combat_state in [CombatState.WINDUP, CombatState.ACTIVE, CombatState.RECOVERY]:
		return _sword_attack_coordinated
	return _has_shield_equipped() or _sword_support_requested()


func begin_sword_attack(variant: String = "") -> Dictionary:
	if is_paralyzed():
		return _sword_attack_failure("paralyzed")
	if not variant.is_empty() and not SWORD_ATTACK_VARIANTS.has(variant):
		return _sword_attack_failure("invalid_variant")
	if not _has_melee_weapon_equipped():
		return _sword_attack_failure("sword_required")
	if combat_state == CombatState.DEAD:
		return _sword_attack_failure("dead")
	if safe_zone_mode:
		return _sword_attack_failure("safe_zone")
	if is_inside_tree() and get_tree().paused:
		return _sword_attack_failure("paused")
	if camping or combat_state != CombatState.READY or current_trap != null or is_timed_interacting() or is_item_use_active():
		return _sword_attack_failure("busy")
	# A parry can flow into a heavy counter without waiting another input tick
	# for RMB release. Ordinary guarded attacks keep their existing restriction.
	if blocking and get_execution_target() == null:
		return _sword_attack_failure("busy")
	if stamina < get_melee_stamina_cost(0.0):
		return _sword_attack_failure("not_enough_stamina")
	var selected := get_next_sword_attack_variant() if variant.is_empty() else variant
	if not _uses_coordinated_sword_motion() and selected != SWORD_ATTACK_VARIANTS[0]:
		return _sword_attack_failure("shield_required")
	sword_attack_variant = selected
	_sword_attack_had_shield = _has_shield_equipped()
	if _sword_attack_had_shield and is_instance_valid(shield_pivot):
		_sword_entry_shield_pose = shield_pivot.transform
		_sword_entry_shield_clock = _motion_clock
	_sword_attack_coordinated = _uses_coordinated_sword_motion()
	# Charge is an input/combat clock, not a second lift of the weapon. Start
	# the visible cut from the pose the player is already holding, in both stances.
	_sword_direct_entry = _sword_attack_coordinated and REFERENCE_MOTION.has_right_arm(selected) and is_instance_valid(weapon_pivot)
	if _sword_direct_entry:
		_sword_entry_pose = weapon_pivot.transform
		_sword_entry_arm = _reference_arm_for_pivot(_reference_arm_rendered, _sword_entry_pose)
	_sword_attack_uses_cycle = variant.is_empty() and sword_attack_mode == "cycle" and _sword_attack_coordinated
	attack_charge = 0.0
	attack_release_requested = false
	_dagger_contact_resolved = false
	attack_hit_ids.clear()
	blocking = false
	_set_combat_state(CombatState.WINDUP)
	return {"accepted": true, "variant": sword_attack_variant, "stamina_spent": 0.0}


func _sword_minimum_windup_seconds() -> float:
	if is_dagger_equipped():
		return DAGGER_MOTION.WINDUP_SECONDS
	# A released forehand begins on this combat tick; held input still charges.
	return 0.0 if _sword_direct_entry and sword_attack_variant == "right_diagonal" else 0.22


func _sword_attack_failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "stamina_spent": 0.0}


func _try_begin_attack() -> void:
	var result := begin_sword_attack()
	if bool(result.accepted) or not is_instance_valid(hud):
		return
	if str(result.reason) == "sword_required":
		hud.show_event("먼저 근접 무기를 장착하십시오", 0.8)
	elif str(result.reason) == "not_enough_stamina":
		hud.show_event("기력이 부족합니다", 0.8)


func cancel_sword_attack(reset_cycle: bool = true) -> void:
	cancel_execution()
	_sword_direct_entry = false
	_sword_entry_arm.clear()
	_sword_clash_recovering = false
	_sword_attack_uses_cycle = false
	_sword_attack_had_shield = false
	attack_release_requested = false
	attack_charge = 0.0
	attack_hit_ids.clear()
	blocking = false
	block_time = 0.0
	_shield_impact = 0.0
	_shield_raise_progress = 0.0
	if reset_cycle:
		_sword_next_attack_index = 0
		sword_attack_variant = get_next_sword_attack_variant()
	if combat_state != CombatState.DEAD:
		_set_combat_state(CombatState.READY)


func _commit_attack() -> void:
	# A delayed release after a menu, equipment change, or death cannot revive
	# a cancelled windup, and a second commit cannot spend stamina twice.
	if combat_state != CombatState.WINDUP:
		return
	if not _has_melee_weapon_equipped() or safe_zone_mode or camping or current_trap != null or is_timed_interacting():
		cancel_sword_attack()
		return
	if is_inside_tree() and get_tree().paused:
		return
	if _sword_attack_had_shield and not _has_shield_equipped():
		cancel_sword_attack()
		return
	if not is_dagger_equipped() and state_time >= EXECUTION_MOTION.CHARGE_SECONDS and _try_begin_execution():
		return
	var cost := get_melee_stamina_cost(attack_charge)
	_consume_stamina(cost)
	if _sword_attack_uses_cycle:
		_sword_next_attack_index = (_sword_next_attack_index + 1) % SWORD_ATTACK_VARIANTS.size()
	_sword_attack_uses_cycle = false
	_set_combat_state(CombatState.ACTIVE)


func is_execution_active() -> bool:
	return combat_state == CombatState.EXECUTION


func get_rear_takedown_profile() -> String:
	if inventory_model == null: return ""
	var definition := ExpeditionInventory.get_item_definition(str(inventory_model.equipment.get("weapon", "")))
	return REAR_TAKEDOWN_MOTION.weapon_profile(definition)


func _rear_takedown_block_reason() -> String:
	if get_rear_takedown_profile() != "rear_sword": return "unsupported_weapon"
	if health <= 0.0 or combat_state == CombatState.DEAD: return "dead"
	if not is_inside_tree() or get_tree().paused: return "paused"
	if safe_zone_mode: return "safe_zone"
	if combat_state != CombatState.READY or camping or chest_equipment_stowed or is_paralyzed() or current_trap != null or is_timed_interacting() or is_item_use_active(): return "busy"
	return ""


func get_rear_takedown_target() -> DungeonEnemy:
	if not _rear_takedown_block_reason().is_empty() or not is_instance_valid(camera): return null
	var best: DungeonEnemy
	var best_score := INF
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as DungeonEnemy
		if enemy == null or not enemy.can_begin_rear_takedown(self, get_rear_takedown_profile()): continue
		var direction := camera.global_position.direction_to(enemy.get_aim_point())
		var alignment := (-camera.global_basis.z).dot(direction)
		if alignment < cos(deg_to_rad(35.0)) or not _rear_takedown_has_clear_path(enemy): continue
		var score := global_position.distance_to(enemy.global_position) + (1.0 - alignment) * 3.0
		if score < best_score:
			best = enemy
			best_score = score
	return best


func _rear_takedown_has_clear_path(enemy: DungeonEnemy) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree() or enemy.get_world_3d() != get_world_3d(): return false
	if not _has_clear_melee_path(enemy): return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, enemy.get_aim_point(), WORLD_LAYER | ENEMY_LAYER)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == enemy


func begin_rear_takedown() -> Dictionary:
	var reason := _rear_takedown_block_reason()
	if not reason.is_empty(): return {"accepted": false, "reason": reason}
	var cost := REAR_TAKEDOWN_MOTION.STAMINA_COST * get_body_attack_stamina_multiplier()
	if stamina < cost: return {"accepted": false, "reason": "not_enough_stamina"}
	var enemy := get_rear_takedown_target()
	if enemy == null: return {"accepted": false, "reason": "unaware_rear_target_required"}
	if not enemy.begin_rear_takedown(self, get_rear_takedown_profile()): return {"accepted": false, "reason": "target_changed"}
	var contacts := enemy.get_rear_takedown_contacts()
	if contacts.is_empty():
		enemy.cancel_execution(self)
		return {"accepted": false, "reason": "contact_unavailable"}
	_execution_target = enemy
	_execution_profile = "rear_sword"
	_execution_hit_committed = false
	_rear_stab_contact_committed = false
	execution_elapsed = 0.0
	_execution_sword_entry = weapon_pivot.transform
	_execution_shield_entry = shield_pivot.transform
	_execution_weapon_identity = _displayed_weapon_identity
	_execution_contact_point = contacts.back
	_rear_neck_contact = contacts.neck
	# Thrust from the right middle guard: the hilt stays below eye level and
	# outside the face, instead of drawing the cuff through the camera.
	var forward := (contacts.direction as Vector3).normalized().rotated(Vector3.UP, deg_to_rad(20.0))
	_execution_stab_direction = (forward * cos(deg_to_rad(12.0)) + Vector3.UP * sin(deg_to_rad(12.0))).normalized()
	_rear_stab_basis = REAR_TAKEDOWN_MOTION.stab_basis(_execution_stab_direction)
	_rear_arm_entry = _reference_arm_rendered.duplicate(true)
	var geometry := _get_execution_blade_geometry()
	_execution_blade_tip = geometry.tip
	_execution_blade_length = geometry.length
	_execution_penetration = geometry.length * REAR_TAKEDOWN_MOTION.PENETRATION_RATIO
	_rear_entry_yaw = rotation.y
	_rear_entry_pitch = _pitch
	var approach := enemy.global_position - global_position
	approach.y = 0.0
	_rear_approach_offset = approach
	_rear_approach_progress = 0.0
	_rear_approach_obstruction_m = 0.0
	_sword_attack_uses_cycle = false
	_sword_direct_entry = false
	_sword_draw_elapsed = SWORD_DRAW_DURATION
	_motion_equip_elapsed = MOTION.EQUIP_DURATION
	blocking = false
	block_time = 0.0
	_shield_impact = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_consume_stamina(cost)
	stamina_regen_delay = REAR_TAKEDOWN_MOTION.DURATION + .15
	_set_combat_state(CombatState.EXECUTION)
	viewmodel_renderer.set_world_contact_enabled(true)
	if hud:
		hud.set_prompt("")
		hud.show_event("검 · 후방 제압", .7)
	execution_started.emit(enemy)
	return {"accepted": true, "profile": _execution_profile, "stamina_spent": cost}


func get_execution_target() -> DungeonEnemy:
	if is_dagger_equipped():
		return null
	if not is_inside_tree() or not is_instance_valid(camera) or not _has_melee_weapon_equipped():
		return null
	if safe_zone_mode or camping or is_paralyzed() or is_item_use_active() or is_timed_interacting() or current_trap != null:
		return null
	var best: DungeonEnemy
	var best_score := INF
	var forward := -camera.global_basis.z
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as DungeonEnemy
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get_world_3d() != get_world_3d() or not enemy.is_execution_vulnerable():
			continue
		if enemy.get_execution_profile() != "crawl_stab" and not _has_shield_equipped():
			continue
		if enemy.get_execution_profile() == "crawl_stab":
			var reach := enemy.get_aim_point() - global_position
			reach.y = 0.0
			if reach.length() < CREEP_EXECUTION_MOTION.MIN_DISTANCE or reach.length() > CREEP_EXECUTION_MOTION.MAX_DISTANCE:
				continue
		var offset := enemy.global_position - global_position
		if absf(offset.y) > 0.8:
			continue
		offset.y = 0.0
		var distance := offset.length()
		var alignment := forward.dot(camera.global_position.direction_to(enemy.get_aim_point()))
		if distance > EXECUTION_MOTION.MAX_DISTANCE or alignment < cos(deg_to_rad(25.0)) or not _execution_has_clear_path(enemy):
			continue
		var score := distance + (1.0 - alignment) * 4.0
		if score < best_score:
			best = enemy
			best_score = score
	return best


func _execution_has_clear_path(enemy: DungeonEnemy) -> bool:
	if enemy.get_execution_profile() != "crawl_stab" and not _has_clear_melee_path(enemy):
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, enemy.get_aim_point(), WORLD_LAYER | ENEMY_LAYER)
	ray.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.get("collider") == enemy


func _try_begin_execution() -> bool:
	var cost := EXECUTION_MOTION.STAMINA_COST * get_body_attack_stamina_multiplier()
	if stamina < cost:
		return false
	var enemy := get_execution_target()
	if enemy == null or not enemy.begin_execution(self):
		return false
	_execution_target = enemy
	_execution_profile = enemy.get_execution_profile()
	_execution_hit_committed = false
	execution_elapsed = 0.0
	_execution_sword_entry = weapon_pivot.transform
	_execution_shield_entry = shield_pivot.transform
	_execution_shield_rest = CHOREOGRAPHY.shield(0, 0, "ready", 0, 0, "overhead")
	_execution_shield_rest.origin += _shield_corner_offset()
	_execution_weapon_identity = _displayed_weapon_identity
	_execution_blade_length = 0.0
	_execution_penetration = 0.0
	if _execution_profile == "crawl_stab":
		_execution_contact_point = enemy.call("get_crawl_execution_contact")
		var blade_geometry := _get_execution_blade_geometry()
		_execution_blade_tip = blade_geometry.tip
		_execution_blade_length = blade_geometry.length
		_execution_penetration = _execution_blade_length * CREEP_EXECUTION_MOTION.PENETRATION_RATIO
		var raised_hand := camera.to_global(Vector3(.24, -.10, -.30))
		_execution_stab_direction = raised_hand.direction_to(_execution_contact_point)
		if is_instance_valid(viewmodel_renderer):
			viewmodel_renderer.set_world_contact_enabled(true)
	_sword_attack_uses_cycle = false
	_sword_direct_entry = false
	_sword_draw_elapsed = SWORD_DRAW_DURATION
	_motion_equip_elapsed = MOTION.EQUIP_DURATION
	blocking = false
	block_time = 0.0
	_shield_impact = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_consume_stamina(cost)
	stamina_regen_delay = _execution_duration() + 0.15
	_set_combat_state(CombatState.EXECUTION)
	if hud:
		hud.set_prompt("")
		hud.show_event("포복 크리프 · 내려찌르기" if _execution_profile == "crawl_stab" else "검·방패 처형", 0.7)
	execution_started.emit(enemy)
	return true


func advance_execution(delta: float) -> void:
	if not is_execution_active() or delta <= 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if _execution_profile == "rear_sword":
		_advance_rear_takedown(delta)
		return
	var target_valid := is_instance_valid(_execution_target) and not _execution_target.is_queued_for_deletion() and _execution_target.is_inside_tree() and _execution_target.get_world_3d() == get_world_3d()
	if not _has_melee_weapon_equipped() or (_execution_profile != "crawl_stab" and not _has_shield_equipped()) or safe_zone_mode or camping or is_paralyzed() or health <= 0.0 or current_trap != null or is_item_use_active() or _execution_weapon_identity != _displayed_weapon_identity:
		cancel_execution()
		return
	if not _execution_hit_committed and (not target_valid or _execution_target.ai_state != DungeonEnemy.AIState.EXECUTION):
		cancel_execution()
		return
	var hit_time := _execution_hit_time()
	var duration := _execution_duration()
	execution_elapsed = minf(duration, execution_elapsed + delta)
	state_time = execution_elapsed
	if not _execution_hit_committed:
		_execution_target.advance_execution_pose(minf(execution_elapsed, hit_time))
		if execution_elapsed >= hit_time:
			var offset := _execution_target.global_position - global_position
			if offset.length() > EXECUTION_MOTION.MAX_DISTANCE or not _execution_has_clear_path(_execution_target):
				cancel_execution()
				return
			if _execution_profile == "crawl_stab":
				# Resolve the actual blade pose on the gameplay clock, even if a long
				# tick crosses contact without a render callback in between.
				_apply_crawl_execution_view(hit_time)
				var tip := weapon_pivot.to_global(_execution_blade_tip)
				var contact_hit: Dictionary = _execution_target.call("query_located_hit", tip - _execution_stab_direction * .30, tip, .025)
				if contact_hit.is_empty():
					cancel_execution()
					return
			var remaining_health := _execution_target.health
			_execution_hit_committed = _execution_target.finish_execution(self)
			if not _execution_hit_committed:
				cancel_execution()
				return
			attack_landed.emit(remaining_health, true)
			if hud:
				hud.show_hit(true)
				hud.show_event("처형 성공", 0.8)
	if _execution_hit_committed and _execution_profile == "crawl_stab" and target_valid \
			and is_instance_valid(_execution_target) and not _execution_target.is_queued_for_deletion() \
			and execution_elapsed >= CREEP_EXECUTION_MOTION.WITHDRAW_START:
		# Use the actual blade position on the gameplay clock, not a death timer.
		# A long tick past extraction still releases exactly once.
		_apply_crawl_execution_view(execution_elapsed)
		var blade_depth := (weapon_pivot.to_global(_execution_blade_tip) - _execution_contact_point).dot(_execution_stab_direction)
		if execution_elapsed >= CREEP_EXECUTION_MOTION.WITHDRAW_END or blade_depth <= -CREEP_EXECUTION_MOTION.WITHDRAW_CLEARANCE:
			_execution_target.call("release_execution_ragdoll", self)
	if hud:
		hud.update_weapon_state(_execution_phase(), Color(0.95, 0.62, 0.32))
	if execution_elapsed >= duration or is_equal_approx(execution_elapsed, duration):
		cancel_execution()


func _advance_rear_takedown(delta: float) -> void:
	var valid := is_instance_valid(_execution_target) and not _execution_target.is_queued_for_deletion() and _execution_target.is_inside_tree() and _execution_target.get_world_3d() == get_world_3d()
	if get_rear_takedown_profile() != "rear_sword" or safe_zone_mode or camping or chest_equipment_stowed or is_paralyzed() or health <= 0.0 or current_trap != null or is_item_use_active() or is_timed_interacting() or _execution_weapon_identity != _displayed_weapon_identity:
		cancel_execution()
		return
	var offset := _execution_target.global_position - global_position if valid else Vector3(INF, INF, INF)
	if not _execution_hit_committed and (not valid or _execution_target.ai_state != DungeonEnemy.AIState.EXECUTION or Vector2(offset.x, offset.z).length() > 1.65 or absf(offset.y) > .90 or not _rear_takedown_has_clear_path(_execution_target)):
		cancel_execution()
		return
	var next_elapsed := minf(REAR_TAKEDOWN_MOTION.DURATION, execution_elapsed + delta)
	# Sweep preparation and deep contact in order, including a long frame
	# crossing both insertion and withdrawal. Never skip a blocked retreat.
	if execution_elapsed < REAR_TAKEDOWN_MOTION.PREPARE_END and next_elapsed >= REAR_TAKEDOWN_MOTION.PREPARE_END:
		_move_rear_takedown_approach(REAR_TAKEDOWN_MOTION.PREPARE_END)
		if _rear_approach_obstruction_m > .04:
			cancel_execution()
			return
	if not _rear_stab_contact_committed and next_elapsed >= REAR_TAKEDOWN_MOTION.STAB_HIT:
		_move_rear_takedown_approach(REAR_TAKEDOWN_MOTION.STAB_HIT)
		if _rear_approach_obstruction_m > .04:
			cancel_execution()
			return
		_execution_target.advance_execution_pose(REAR_TAKEDOWN_MOTION.STAB_HIT)
		var contacts := _execution_target.get_rear_takedown_contacts()
		if not contacts.is_empty(): _rear_neck_contact = contacts.neck
		_apply_rear_takedown_view(REAR_TAKEDOWN_MOTION.STAB_HIT)
		var tip := weapon_pivot.to_global(_execution_blade_tip)
		var heel := weapon_pivot.to_global(_execution_blade_tip - Vector3.UP * _execution_blade_length)
		var torso_hit: Dictionary = _execution_target.call("query_located_hit", heel, tip, .045)
		var wrist := weapon_pivot.transform * SWORD_LONG_GRIP.wrist_local(1.0)
		var shoulder := SWORD_LONG_GRIP.SOURCE_READY * SWORD_LONG_GRIP.REST_SHOULDER
		if torso_hit.is_empty() or str(torso_hit.get("region", "")) != "torso" or wrist.distance_to(shoulder) > REFERENCE_ARM.MAX_REACH + .04:
			cancel_execution()
			return
		_rear_stab_contact_committed = true
		var remaining_health := _execution_target.health
		_execution_hit_committed = _execution_target.finish_rear_takedown(self)
		if not _execution_hit_committed:
			cancel_execution()
			return
		attack_landed.emit(remaining_health, true)
		if hud:
			hud.show_hit(true)
			hud.show_event("후방 제압 · 처치", 1.0)
	_move_rear_takedown_approach(next_elapsed)
	if _rear_approach_obstruction_m > .04:
		cancel_execution()
		return
	if not _execution_hit_committed:
		_execution_target.advance_execution_pose(next_elapsed)
		var contacts := _execution_target.get_rear_takedown_contacts()
		if not contacts.is_empty(): _rear_neck_contact = contacts.neck
	elif valid and next_elapsed >= REAR_TAKEDOWN_MOTION.HOLD_END:
		_apply_rear_takedown_view(next_elapsed)
		var depth := (weapon_pivot.to_global(_execution_blade_tip) - _execution_contact_point).dot(_execution_stab_direction)
		if depth <= -REAR_TAKEDOWN_MOTION.WITHDRAW_CLEARANCE + .002:
			_execution_target.call("release_execution_ragdoll", self)
	execution_elapsed = next_elapsed
	state_time = execution_elapsed
	if hud: hud.update_weapon_state(_execution_phase(), Color(.95, .62, .32))
	if execution_elapsed >= REAR_TAKEDOWN_MOTION.DURATION: cancel_execution()


func _move_rear_takedown_approach(elapsed: float) -> void:
	# Store the original target vector, and accumulate travelled metres. This
	# works when starting closer than the final stance as well as farther away.
	var initial_distance := _rear_approach_offset.length()
	var preparation := initial_distance - REAR_TAKEDOWN_MOTION.STAB_DISTANCE
	var lunge := REAR_TAKEDOWN_MOTION.STAB_DISTANCE - REAR_TAKEDOWN_MOTION.CONTACT_DISTANCE
	var travelled := preparation * smoothstep(0, REAR_TAKEDOWN_MOTION.PREPARE_END, elapsed) + lunge * (smoothstep(REAR_TAKEDOWN_MOTION.PREPARE_END, REAR_TAKEDOWN_MOTION.STAB_HIT, elapsed) - smoothstep(REAR_TAKEDOWN_MOTION.HOLD_END, REAR_TAKEDOWN_MOTION.WITHDRAW_END, elapsed))
	if absf(travelled - _rear_approach_progress) > .000001:
		var step := _rear_approach_offset.normalized() * (travelled - _rear_approach_progress)
		var before := global_position
		move_and_collide(step)
		_rear_approach_obstruction_m += maxf(0.0, step.length() - (global_position - before).dot(step.normalized()))
		_rear_approach_progress = travelled


func _apply_rear_takedown_view(elapsed: float) -> void:
	# The actual character step is collision-tested by the coordinator; this
	# function only aims the view and applies the sword/upper-body lean.
	var focus := _execution_contact_point.lerp(_rear_neck_contact, .42)
	# Turn the stance slightly left so the right shoulder follows the thrust
	# line instead of folding the forearm across the centre of the chest.
	focus -= Vector3(cos(_rear_entry_yaw), 0, -sin(_rear_entry_yaw)) * .16
	var toward := focus - head.global_position
	var blend := smoothstep(0, REAR_TAKEDOWN_MOTION.PREPARE_END, elapsed)
	rotation.y = lerp_angle(_rear_entry_yaw, atan2(-toward.x, -toward.z), blend)
	_pitch = lerpf(_rear_entry_pitch, atan2(toward.y, Vector2(toward.x, toward.z).length()), blend)
	head.rotation.x = _pitch
	camera.position = REAR_TAKEDOWN_MOTION.camera_offset(elapsed)
	camera.rotation = Vector3.ZERO
	weapon_pivot.transform = REAR_TAKEDOWN_MOTION.sword(elapsed, _execution_sword_entry, camera.to_local(_execution_contact_point), camera.global_basis.inverse() * _execution_stab_direction, camera.to_local(_rear_neck_contact), _execution_blade_tip, _execution_blade_length, camera.global_basis.inverse() * _rear_stab_basis)
	shield_pivot.transform = REAR_TAKEDOWN_MOTION.shield(elapsed, _execution_shield_entry)


func _advance_execution_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _execution_profile != "rear_sword" and is_instance_valid(_execution_target) and not _execution_hit_committed:
		var toward := (_execution_contact_point if _execution_profile == "crawl_stab" else _execution_target.global_position) - global_position
		toward.y = 0.0
		var distance := toward.length()
		if distance > 0.001:
			rotation.y = lerp_angle(rotation.y, atan2(-toward.x, -toward.z), minf(1.0, delta * 12.0))
			var contact_distance := CREEP_EXECUTION_MOTION.CONTACT_DISTANCE if _execution_profile == "crawl_stab" else EXECUTION_MOTION.CONTACT_DISTANCE
			if execution_elapsed < 0.30 and distance > contact_distance:
				var speed := minf(2.8, (distance - contact_distance) / maxf(delta, 0.30 - execution_elapsed))
				velocity.x = toward.x / distance * speed
				velocity.z = toward.z / distance * speed
	var vertical_before_collision := velocity.y
	move_and_slide()
	_observe_movement_floor(vertical_before_collision)


func cancel_execution() -> void:
	if not is_execution_active() and _execution_target == null:
		return
	var enemy := _execution_target if is_instance_valid(_execution_target) else null
	var killed := _execution_hit_committed
	_execution_target = null
	if is_instance_valid(enemy):
		enemy.cancel_execution(self)
	velocity.x = 0.0
	velocity.z = 0.0
	if is_instance_valid(camera):
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO
	if is_instance_valid(viewmodel_renderer):
		viewmodel_renderer.set_world_contact_enabled(false)
	if is_execution_active():
		_set_combat_state(CombatState.READY)
	# The existing 100ms handoff returns from the actual last pose after either
	# interruption or completion; no teleporting of hands or forced mouse mode.
	_reference_pose_key = "execution"
	_reference_locomotion_valid = false
	_reference_shield_valid = false
	_shield_raise_progress = 0.0
	execution_finished.emit(enemy, killed)


func _update_execution_viewmodel() -> void:
	if _execution_profile == "rear_sword":
		_apply_rear_takedown_view(execution_elapsed)
	elif _execution_profile == "crawl_stab":
		_apply_crawl_execution_view(execution_elapsed)
	else:
		weapon_pivot.transform = EXECUTION_MOTION.sword(execution_elapsed, _execution_sword_entry)
		shield_pivot.transform = EXECUTION_MOTION.shield(execution_elapsed, _execution_shield_entry, _execution_shield_rest)
		camera.position = EXECUTION_MOTION.camera_offset(execution_elapsed)
		camera.rotation = EXECUTION_MOTION.camera_rotation(execution_elapsed)
	if _execution_profile == "rear_sword":
		_reference_arm_target = REAR_TAKEDOWN_MOTION.arm(weapon_pivot.transform, execution_elapsed, _rear_arm_entry, _reference_arm_previous_bend)
	else:
		_reference_arm_target = _reference_arm_for_pivot({}, weapon_pivot.transform)
	_refresh_carried_visibility()
	_update_character_arms()


func _apply_crawl_execution_view(elapsed: float) -> void:
	camera.position = CREEP_EXECUTION_MOTION.camera_offset(elapsed)
	camera.rotation = CREEP_EXECUTION_MOTION.camera_rotation(elapsed)
	var target_local := camera.to_local(_execution_contact_point)
	var direction_local := camera.global_basis.inverse() * _execution_stab_direction
	weapon_pivot.transform = CREEP_EXECUTION_MOTION.sword(elapsed, _execution_sword_entry, target_local, direction_local, _execution_blade_tip, _execution_penetration)
	shield_pivot.transform = CREEP_EXECUTION_MOTION.shield(elapsed, _execution_shield_entry)


func _get_execution_blade_geometry() -> Dictionary:
	var blade_frame := weapon_pivot.global_transform.affine_inverse() * sword_blade.global_transform
	var tip := Vector3.ZERO
	var highest := -INF
	var lowest := INF
	for surface in sword_blade.mesh.get_surface_count():
		var vertices: PackedVector3Array = sword_blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := blade_frame * vertex
			lowest = minf(lowest, point.y)
			if point.y > highest:
				highest = point.y
				tip = point
	return {"tip": tip, "length": highest - lowest}


func _execution_hit_time() -> float:
	if _execution_profile == "rear_sword": return REAR_TAKEDOWN_MOTION.STAB_HIT
	return CREEP_EXECUTION_MOTION.HIT_SECONDS if _execution_profile == "crawl_stab" else EXECUTION_MOTION.HIT_SECONDS


func _execution_duration() -> float:
	if _execution_profile == "rear_sword": return REAR_TAKEDOWN_MOTION.DURATION
	return CREEP_EXECUTION_MOTION.DURATION if _execution_profile == "crawl_stab" else EXECUTION_MOTION.DURATION


func _execution_phase() -> String:
	if _execution_profile == "rear_sword": return REAR_TAKEDOWN_MOTION.phase(execution_elapsed)
	return CREEP_EXECUTION_MOTION.phase(execution_elapsed) if _execution_profile == "crawl_stab" else EXECUTION_MOTION.phase(execution_elapsed)


func get_execution_snapshot() -> Dictionary:
	var tip := weapon_pivot.to_global(_execution_blade_tip) if is_instance_valid(weapon_pivot) else Vector3.ZERO
	return {"active": is_execution_active(), "elapsed": execution_elapsed, "phase": _execution_phase(), "profile": _execution_profile, "stab_contact_committed": _rear_stab_contact_committed, "stab_direction": _execution_stab_direction, "neck_contact": _rear_neck_contact, "lateral_cut_contact": _execution_contact_point, "hit_committed": _execution_hit_committed, "target_id": _execution_target.get_instance_id() if is_instance_valid(_execution_target) else 0, "contact_point": _execution_contact_point, "blade_tip": tip, "blade_length_m": _execution_blade_length, "penetration_m": _execution_penetration, "blade_fraction": _execution_penetration / _execution_blade_length if _execution_blade_length > 0.0 else 0.0, "contact_error": tip.distance_to(_execution_contact_point), "world_contact": is_instance_valid(viewmodel_renderer) and viewmodel_renderer.world_contact_enabled}


func get_melee_hit_time() -> float:
	if is_dagger_equipped():
		return DAGGER_MOTION.HIT_SECONDS
	return CHOREOGRAPHY.HIT_SECONDS if _uses_coordinated_sword_motion() else ATTACK_HIT_TIME


func get_melee_active_duration() -> float:
	if is_dagger_equipped():
		return DAGGER_MOTION.ACTIVE_SECONDS
	return CHOREOGRAPHY.ACTIVE_SECONDS if _uses_coordinated_sword_motion() else 0.16


func _resolve_active_attack() -> void:
	if camping or combat_state != CombatState.ACTIVE:
		return
	# Inventory changes can occur while the scene is paused. Never let a swing
	# survive after the sword was replaced or unequipped.
	if not _has_melee_weapon_equipped():
		_set_combat_state(CombatState.READY)
		return
	if _try_overlapping_sword_clash():
		return
	# Keep the original solo hit timing, but give a nearby unresolved enemy sword
	# enough of the shared active window to reach the rendered player blade.
	var waiting_for_sword_clash := not is_dagger_equipped() and state_time < SWORD_CLASH_GRACE_END and _has_active_sword_opponent_in_melee_path()
	if state_time >= get_melee_hit_time() and attack_hit_ids.is_empty() and not waiting_for_sword_clash and (not is_dagger_equipped() or not _dagger_contact_resolved):
		_dagger_contact_resolved = is_dagger_equipped()
		_perform_melee_hit()
	if combat_state == CombatState.ACTIVE and state_time >= get_melee_active_duration():
		_set_combat_state(CombatState.RECOVERY)


func _perform_melee_hit() -> void:
	var hits := _query_melee_hits()
	var landed := false
	for result: Dictionary in hits:
		var candidate := result.get("collider") as Node
		if candidate == null or not candidate.has_method("receive_hit"):
			continue
		var instance_id := candidate.get_instance_id()
		if attack_hit_ids.has(instance_id):
			continue
		if not _has_clear_melee_path(candidate):
			continue
		var contact := _located_melee_contact(candidate, get_melee_reach())
		if candidate.has_method("query_located_hit") and contact.is_empty():
			continue
		attack_hit_ids[instance_id] = true
		var aim_point: Vector3 = candidate.call("get_aim_point") if candidate.has_method("get_aim_point") else candidate.global_position
		var aim_direction := camera.global_position.direction_to(aim_point)
		var headshot: bool = (-camera.global_transform.basis.z).dot(aim_direction) > 0.991 and aim_point.y > candidate.global_position.y + 0.35
		if not contact.is_empty():
			headshot = str(contact.get("region", "")) == "head"
		var damage := get_melee_damage(attack_charge)
		if headshot:
			damage *= 1.42
		var assassinated := false
		if is_dagger_equipped() and candidate.has_method("receive_dagger_assassination"):
			var remaining_health := float(candidate.get("health"))
			assassinated = bool(candidate.call("receive_dagger_assassination", global_position))
			if assassinated:
				damage = remaining_health
				headshot = false
		if assassinated:
			if hud: hud.show_event("후방 암살 · 한 번에 처치", 1.4)
		elif not contact.is_empty() and candidate.has_method("receive_located_hit"):
			candidate.call("receive_located_hit", damage, global_position, attack_charge, headshot, contact.position)
		else:
			candidate.call("receive_hit", damage, global_position, attack_charge, headshot)
		apply_smithing_on_hit()
		landed = true
		attack_landed.emit(damage, headshot)
		if hud:
			hud.show_hit(headshot)
		_camera_shake = maxf(_camera_shake, 0.055)
		if is_dagger_equipped():
			break # A short thrust contacts the nearest target, never a cleaving sweep.
	if not landed:
		_check_wall_strike()


func get_melee_reach() -> float:
	return 1.05 if is_dagger_equipped() else lerpf(2.12, 2.40, attack_charge)


func get_dagger_assassination_target() -> DungeonEnemy:
	if not is_dagger_equipped() or safe_zone_mode or not is_inside_tree() or not is_instance_valid(camera):
		return null
	for hit: Dictionary in _query_dagger_hits():
		var candidate := hit.get("collider") as DungeonEnemy
		if candidate != null and candidate.can_receive_dagger_assassination(global_position) and _has_clear_melee_path(candidate):
			return candidate
	return null


func _query_dagger_hits() -> Array[Dictionary]:
	var from := camera.global_position
	var to := from - camera.global_basis.z * get_melee_reach()
	var excluded: Array[RID] = []
	for actor in get_tree().get_nodes_in_group("enemy"):
		if actor is CollisionObject3D and actor.get_world_3d() != get_world_3d():
			excluded.append(actor.get_rid())
	var located := LOCATED_HIT_QUERY.collect(get_tree(), from, to, .04, excluded)
	# Exclude anatomical navigation capsules: only the actual posed body can
	# receive a stab. A wall or a nearer ordinary enemy still blocks that ray.
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER | ENEMY_LAYER, located.excluded)
	query.collide_with_areas = false
	var hit := LOCATED_HIT_QUERY.nearer(get_world_3d().direct_space_state.intersect_ray(query), located.hit, from, to)
	var hits: Array[Dictionary] = []
	if not hit.is_empty() and hit.get("collider") is DungeonEnemy:
		hits.append(hit)
	return hits


func _query_melee_hits() -> Array[Dictionary]:
	if is_dagger_equipped():
		return _query_dagger_hits()
	var shape := SphereShape3D.new()
	shape.radius = lerpf(0.7, 0.82, attack_charge)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position + (-camera.global_transform.basis.z * lerpf(1.42, 1.58, attack_charge)))
	query.collision_mask = ENEMY_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 12)
	_append_located_melee_hit(hits, lerpf(2.12, 2.40, attack_charge))
	return hits


func _located_melee_contact(target: Node, reach: float) -> Dictionary:
	if not target.has_method("query_located_hit"):
		return {}
	var from := camera.global_position
	var to := from - camera.global_basis.z * reach
	var contact: Dictionary = target.call("query_located_hit", from, to, 0.04 if is_dagger_equipped() else 0.10)
	if not contact.is_empty():
		var wall := PhysicsRayQueryParameters3D.create(from, contact.position, WORLD_LAYER)
		wall.collide_with_areas = false
		if not get_world_3d().direct_space_state.intersect_ray(wall).is_empty():
			return {}
	return contact


func _append_located_melee_hit(hits: Array[Dictionary], reach: float) -> void:
	var from := camera.global_position
	var contacts := LOCATED_HIT_QUERY.collect(get_tree(), from, from - camera.global_basis.z * reach, 0.10)
	var contact: Dictionary = contacts.hit
	if contact.is_empty():
		return
	for hit in hits:
		if hit.get("collider") == contact.collider:
			return
	# Arms outside the navigation capsule remain directly targetable.
	hits.append(contact)


func is_sword_attack_active() -> bool:
	return combat_state == CombatState.ACTIVE and sword_blade != null and _has_melee_weapon_equipped() and not is_dagger_equipped()


func get_sword_clash_proxy() -> Dictionary:
	return SWORD_CLASH_GEOMETRY.blade_proxy(sword_blade)


func try_sword_clash(attacker: Node) -> bool:
	if not is_sword_attack_active() or attacker == null or not is_instance_valid(attacker):
		return false
	if not attacker.has_method("is_sword_attack_active") or not bool(attacker.call("is_sword_attack_active")):
		return false
	if not attacker.has_method("get_sword_clash_proxy") or not attacker.has_method("receive_sword_clash"):
		return false
	var attacker_proxy: Dictionary = attacker.call("get_sword_clash_proxy")
	if not SWORD_CLASH_GEOMETRY.proxies_overlap(get_sword_clash_proxy(), attacker_proxy, SWORD_CLASH_MARGIN):
		return false
	if not bool(attacker.call("receive_sword_clash", global_position)):
		return false

	attack_hit_ids[attacker.get_instance_id()] = true
	if REFERENCE_MOTION.is_available():
		# The collision was against these rendered, already composed pivots.
		# Keep the exact contact pose for both solo and paired sword recovery.
		_sword_clash_recovering = true
		_sword_clash_weapon_pose = weapon_pivot.transform
		_sword_clash_shield_pose = shield_pivot.transform if is_instance_valid(shield_pivot) else Transform3D.IDENTITY
		_reference_arm_clash_from = _reference_arm_rendered.duplicate(true)
		_reference_pose_handoff_active = false
	elif _has_shield_equipped():
		_sword_clash_recovering = true
		_sword_clash_weapon_pose = CHOREOGRAPHY.sword("active",state_time,attack_charge,sword_attack_variant)
		_sword_clash_shield_pose = CHOREOGRAPHY.shield(_shield_raise_progress,_shield_impact,"active",state_time,attack_charge,sword_attack_variant)
	_set_combat_state(CombatState.RECOVERY)
	_camera_shake = maxf(_camera_shake, 0.08)
	if hud:
		hud.show_event("검격을 튕겨냈습니다", 0.85)
	return true


func _try_overlapping_sword_clash() -> bool:
	if not is_sword_attack_active():
		return false
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if try_sword_clash(enemy):
			return true
	return false


func _has_active_sword_opponent_in_melee_path() -> bool:
	for result: Dictionary in _query_melee_hits():
		var enemy := result.get("collider") as Node
		if enemy == null or not enemy.has_method("is_sword_attack_active"):
			continue
		if not _has_clear_melee_path(enemy):
			continue
		if bool(enemy.call("is_sword_attack_active")):
			return true
	return false


func _has_clear_melee_path(candidate: Node) -> bool:
	var target_position: Vector3 = candidate.global_position + Vector3(0, 0.35, 0)
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target_position, WORLD_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _check_wall_strike() -> void:
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z * (get_melee_reach() if is_dagger_equipped() else 2.05))
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_camera_shake = maxf(_camera_shake, 0.025)


func _update_interaction(delta: float) -> void:
	if is_execution_active():
		interaction_owner = null
		if hud: hud.set_prompt("")
		return
	if get_rear_takedown_target() != null:
		interaction_owner = null
		var enough := stamina >= REAR_TAKEDOWN_MOTION.STAMINA_COST * get_body_attack_stamina_multiplier()
		if hud: hud.set_prompt("[E] 검 · 후방 제압" if enough else "후방 제압 · 기력 부족")
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed("interact"):
			begin_rear_takedown()
		return
	if combat_state in [CombatState.READY, CombatState.WINDUP] and get_execution_target() != null:
		interaction_owner = null
		if hud:
			var enough_stamina := stamina >= EXECUTION_MOTION.STAMINA_COST * get_body_attack_stamina_multiplier()
			hud.set_prompt("[LMB 길게 → 놓기] 처형" if enough_stamina else "처형 · 기력 부족")
		return
	if combat_state == CombatState.READY and not is_paralyzed() and not camping and not is_timed_interacting() and current_trap == null and get_dagger_assassination_target() != null:
		interaction_owner = null
		if hud: hud.set_prompt("[LMB] 후방 암살" if stamina >= get_melee_stamina_cost(0.0) else "후방 암살 · 기력 부족")
		return
	if is_paralyzed():
		if is_instance_valid(hud):
			hud.set_prompt("")
		return
	if current_trap != null:
		if hud:
			hud.set_prompt("")
		if Input.is_action_just_pressed("interact") and trap_lockout <= 0.0 and current_trap.has_method("confirm_disarm"):
			current_trap.call("confirm_disarm")
		return

	interaction_owner = null
	if camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if is_timed_interacting():
			cancel_timed_interaction()
		if hud:
			hud.set_prompt("")
		return
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z * 3.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, INTERACT_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider := result.get("collider") as CollisionObject3D
		if collider and collider.has_meta("interaction_owner"):
			var possible_owner: Variant = collider.get_meta("interaction_owner")
			if possible_owner is Node and is_instance_valid(possible_owner):
				interaction_owner = possible_owner
	if is_timed_interacting():
		if Input.is_action_just_pressed("interact"):
			cancel_timed_interaction("상호작용을 중단했습니다")
		elif interaction_owner != timed_interaction_owner:
			cancel_timed_interaction("시선이 벗어나 상호작용이 중단되었습니다")
		else:
			if hud:
				hud.set_prompt("")
			advance_timed_interaction(delta)
		return
	if interaction_owner:
		if interaction_owner is DungeonLootChest and not interaction_owner.is_within_hand_reach(self):
			if hud:
				hud.set_prompt("상자를 열려면 조금 더 가까이 다가가세요")
			return
		var text_value := "[E] 조사"
		if interaction_owner.has_method("get_interaction_prompt"):
			text_value = str(interaction_owner.call("get_interaction_prompt"))
		if hud:
			hud.set_prompt(text_value)
		if Input.is_action_just_pressed("interact"):
			if interaction_owner.has_method("interact"):
				interaction_owner.call("interact", self)
			elif interaction_owner.has_method("begin_disarm"):
				# Compatibility path for any older interactable that has not yet
				# adopted the shared interact(player) entry point.
				interaction_owner.call("begin_disarm", self)
	elif hud:
		hud.set_prompt("")


func begin_timed_interaction(owner: Node, base_duration: float, title_text: String) -> bool:
	if is_paralyzed():
		return false
	if not is_inside_tree() or get_tree().paused or not is_finite(base_duration):
		return false
	if timed_interaction_owner != null and not is_instance_valid(timed_interaction_owner):
		_clear_timed_interaction_state()
	if owner == null or not is_instance_valid(owner) or is_timed_interacting():
		return false
	if camping or current_trap != null or combat_state == CombatState.DEAD or combat_state != CombatState.READY or bow_drawing or _is_flail_busy():
		return false
	timed_interaction_owner = owner
	timed_interaction_duration = maxf(0.0, base_duration * maxf(0.0, interaction_duration_scale))
	timed_interaction_elapsed = 0.0
	timed_interaction_title = title_text
	owner.tree_exiting.connect(_on_timed_interaction_owner_exiting, CONNECT_ONE_SHOT)
	blocking = false
	velocity.x = 0.0
	velocity.z = 0.0
	if owner is DungeonLootChest:
		_begin_chest_opening()
	if hud:
		hud.set_prompt("")
		hud.show_interaction_progress(timed_interaction_title, timed_interaction_duration)
	timed_interaction_started.emit(owner, timed_interaction_duration)
	if timed_interaction_duration <= 0.0:
		advance_timed_interaction(0.0)
	return true


func advance_timed_interaction(delta: float) -> void:
	if not is_inside_tree() or get_tree().paused or not is_finite(delta):
		return
	if timed_interaction_owner == null:
		return
	if not is_instance_valid(timed_interaction_owner):
		_clear_timed_interaction_state()
		return
	timed_interaction_elapsed = minf(timed_interaction_duration, timed_interaction_elapsed + maxf(0.0, delta))
	if timed_interaction_owner is DungeonLootChest:
		var progress := 1.0 if timed_interaction_duration <= 0.0 else get_timed_interaction_progress()
		timed_interaction_owner.set_opening_progress(progress)
		_chest_stow_amount = smoothstep(0.0, 0.16, progress)
		_apply_chest_equipment_pose()
	if hud:
		hud.update_interaction_progress(timed_interaction_elapsed, timed_interaction_duration)
	if timed_interaction_elapsed < timed_interaction_duration:
		return
	var completed_owner := timed_interaction_owner
	_clear_timed_interaction_state()
	if is_instance_valid(completed_owner):
		if completed_owner.has_method("complete_timed_interaction"):
			completed_owner.call("complete_timed_interaction", self)
		elif completed_owner.has_method("interact"):
			completed_owner.call("interact", self)
		timed_interaction_finished.emit(completed_owner)


func cancel_timed_interaction(reason := "") -> void:
	if timed_interaction_owner == null:
		return
	var cancelled_owner := timed_interaction_owner
	_clear_timed_interaction_state()
	if is_instance_valid(cancelled_owner):
		if cancelled_owner.has_method("cancel_timed_interaction"):
			cancelled_owner.call("cancel_timed_interaction", self)
		timed_interaction_cancelled.emit(cancelled_owner)
	if not reason.is_empty() and hud:
		hud.show_event(reason, 1.0)


func is_timed_interacting() -> bool:
	return timed_interaction_owner != null and is_instance_valid(timed_interaction_owner)


func get_timed_interaction_progress() -> float:
	if not is_timed_interacting() or timed_interaction_duration <= 0.0:
		return 0.0
	return clampf(timed_interaction_elapsed / timed_interaction_duration, 0.0, 1.0)


func _clear_timed_interaction_state() -> void:
	if is_instance_valid(timed_interaction_owner) and timed_interaction_owner.tree_exiting.is_connected(_on_timed_interaction_owner_exiting):
		timed_interaction_owner.tree_exiting.disconnect(_on_timed_interaction_owner_exiting)
	timed_interaction_owner = null
	timed_interaction_duration = 0.0
	timed_interaction_elapsed = 0.0
	timed_interaction_title = ""
	set_chest_container_open(false)
	if hud:
		hud.hide_interaction_progress()


func prepare_for_inventory() -> void:
	cancel_item_use()
	cancel_bandage_motion()
	reset_reference_movement_motion()
	_interrupt_camp("가방을 열어 야영을 중단했습니다")
	cancel_bow_draw()
	cancel_flail_action()
	cancel_timed_interaction()
	set_chest_container_open(false)
	cancel_sword_attack()
	velocity.x = 0.0
	velocity.z = 0.0


func _on_timed_interaction_owner_exiting() -> void:
	cancel_timed_interaction()


func _begin_chest_opening() -> void:
	cancel_item_use()
	cancel_bandage_motion()
	_capture_chest_carried_poses()
	chest_equipment_stowed = true
	_chest_stow_amount = 0.0
	if is_instance_valid(chest_hands):
		chest_hands.clear()
	_apply_chest_equipment_pose()


func set_chest_container_open(enabled: bool) -> void:
	if is_instance_valid(chest_hands):
		chest_hands.clear()
	if enabled:
		_capture_chest_carried_poses()
		chest_equipment_stowed = true
		_chest_stow_amount = 1.0
		_apply_chest_equipment_pose()
		return
	chest_equipment_stowed = false
	_chest_stow_amount = 0.0
	var restoring_carried := not _chest_carried_poses.is_empty()
	for carried: Node3D in [weapon_pivot, shield_pivot, torch_pivot, torch]:
		if is_instance_valid(carried) and _chest_carried_poses.has(carried.get_instance_id()):
			carried.transform = _chest_carried_poses[carried.get_instance_id()]
	_chest_carried_poses.clear()
	_refresh_carried_visibility()
	if restoring_carried and REFERENCE_MOTION.right_arm_available() and not _reference_arm_rendered.is_empty():
		_reference_arm_target = _reference_arm_rendered.duplicate(true)
		_update_character_arms()


func _capture_chest_carried_poses() -> void:
	if not _chest_carried_poses.is_empty():
		return
	for carried: Node3D in [weapon_pivot, shield_pivot, torch_pivot, torch]:
		if is_instance_valid(carried):
			_chest_carried_poses[carried.get_instance_id()] = carried.transform


func _apply_chest_equipment_pose() -> void:
	for carried: Node3D in [weapon_pivot, shield_pivot, torch_pivot, torch]:
		if not is_instance_valid(carried) or not _chest_carried_poses.has(carried.get_instance_id()):
			continue
		var rest: Transform3D = _chest_carried_poses[carried.get_instance_id()]
		var shift := Vector3(0.0, -0.70, 0.12) if carried == torch else Vector3(0.12 if carried == weapon_pivot else -0.12, -1.05, 0.30)
		carried.transform = rest
		carried.position += shift * _chest_stow_amount
		if carried != torch:
			carried.rotate_x(deg_to_rad(24.0) * _chest_stow_amount)
	_refresh_carried_visibility()


func _refresh_carried_visibility() -> void:
	var treating: bool = is_bandage_motion_active() and bool(_active_treatment_hands().equipment_hidden())
	var tucked := treating or (chest_equipment_stowed and _chest_stow_amount >= 0.999)
	if is_instance_valid(weapon_pivot):
		weapon_pivot.visible = not camping and not safe_zone_mode and not tucked
	if is_instance_valid(shield_pivot):
		shield_pivot.visible = not camping and not safe_zone_mode and not tucked and _shield_visible_in_hand() and not _is_bow_equipped() and not _is_flail_equipped()
	if is_instance_valid(torch_pivot):
		torch_pivot.visible = not camping and not tucked and (torch_enabled or _torch_draw_elapsed > 0.0)
	if is_instance_valid(support_arm_root):
		support_arm_root.visible = not camping and not chest_equipment_stowed and not treating
	_refresh_hand_visibility()


func begin_trap_disarm(trap: Node, title_text: String, zone_start: float, zone_end: float) -> bool:
	if is_paralyzed():
		return false
	if camping or current_trap != null or combat_state == CombatState.DEAD:
		return false
	current_trap = trap
	cancel_bow_draw()
	cancel_flail_action()
	cancel_sword_attack()
	trap_lockout = 0.22
	blocking = false
	velocity.x = 0.0
	velocity.z = 0.0
	if hud:
		hud.show_trap_meter(title_text, zone_start, zone_end)
	return true


func finish_trap_disarm() -> void:
	current_trap = null
	trap_lockout = 0.2
	if hud:
		hud.hide_trap_meter()


func _is_flail_equipped() -> bool:
	return _equipped_weapon_type() == "flail"


func _is_flail_busy() -> bool:
	return flail_state != "ready"


func get_flail_charge() -> float:
	return FLAIL_PROFILE.charge_for_time(flail_spin_time)


func get_flail_chain_anchor() -> Vector3:
	if is_instance_valid(flail_visual_root) and flail_visual_root.is_inside_tree():
		return (flail_visual_root.get_node("ChainAnchor") as Node3D).global_position
	return camera.global_position if is_instance_valid(camera) and camera.is_inside_tree() else global_position


func _flail_use_failure(require_ready := true) -> String:
	if is_paralyzed():
		return "paralyzed"
	if camping:
		return "busy"
	if combat_state == CombatState.DEAD:
		return "dead"
	if safe_zone_mode:
		return "safe_zone"
	if not _is_flail_equipped():
		return "flail_required"
	if not is_inside_tree() or not is_instance_valid(camera):
		return "cannot_attack_here"
	if get_tree().paused:
		return "paused"
	if combat_state != CombatState.READY or current_trap != null or is_timed_interacting() or bow_drawing:
		return "busy"
	if require_ready and (_is_flail_busy() or flail_cooldown > 0.0):
		return "busy"
	return ""


func _flail_failure(reason: String) -> Dictionary:
	if reason == "not_enough_stamina" and is_instance_valid(hud):
		hud.show_event("사슬철퇴를 휘두를 기력이 부족합니다", 0.9)
	return {"accepted": false, "reason": reason, "stamina_spent": 0.0}


func begin_flail_melee() -> Dictionary:
	var reason := _flail_use_failure()
	if not reason.is_empty():
		return _flail_failure(reason)
	var cost := FLAIL_PROFILE.MELEE_STAMINA * get_body_attack_stamina_multiplier()
	if stamina < cost:
		return _flail_failure("not_enough_stamina")
	_flail_cancel_remaining = 0.0
	flail_state = "melee"
	flail_action_time = 0.0
	_flail_melee_hit_done = false
	blocking = false
	_consume_stamina(cost)
	_refresh_flail_hud()
	return {"accepted": true, "stamina_spent": cost}


func begin_flail_spin() -> Dictionary:
	var reason := _flail_use_failure()
	if not reason.is_empty():
		return _flail_failure(reason)
	var cost := FLAIL_PROFILE.SPIN_STAMINA * get_body_attack_stamina_multiplier()
	if stamina < cost:
		return _flail_failure("not_enough_stamina")
	_flail_cancel_remaining = 0.0
	flail_state = "spinning"
	flail_spin_time = 0.0
	flail_spin_phase = 0.0
	_flail_release_pending = false
	_flail_release_aim = Vector3.ZERO
	blocking = false
	_consume_stamina(cost)
	_update_flail_pose()
	_refresh_flail_hud()
	return {"accepted": true, "stamina_spent": cost}


func release_flail_throw(aim_direction := Vector3.ZERO) -> Dictionary:
	if flail_state != "spinning" or _flail_release_pending:
		return _flail_failure("not_spinning")
	var reason := _flail_use_failure(false)
	if not reason.is_empty():
		cancel_flail_action()
		return _flail_failure(reason)
	if flail_spin_time < FLAIL_PROFILE.MIN_SPIN_DURATION - 0.000001:
		# Even a short click first performs a visible side rotation. Queue only
		# this release, and never grant a long-frame stall extra throw charge.
		_flail_release_pending = true
		_flail_release_aim = aim_direction
		return {"accepted": true, "queued": true, "stamina_spent": 0.0}
	return _launch_flail_throw(aim_direction)


func _launch_flail_throw(aim_direction: Vector3) -> Dictionary:
	var reason := _flail_use_failure(false)
	if not reason.is_empty():
		cancel_flail_action()
		return _flail_failure(reason)
	var projectile_parent: Node = game if is_instance_valid(game) else get_parent()
	if projectile_parent == null:
		cancel_flail_action()
		return _flail_failure("cannot_attack_here")
	var charge := get_flail_charge()
	var direction := aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else -head.global_basis.z
	var projectile: Node3D = FLAIL_PROJECTILE.new()
	projectile.configure(self, direction, charge)
	var damage := FLAIL_PROFILE.throw_damage(charge) * get_body_attack_multiplier()
	projectile.damage = damage
	projectile.hit_target.connect(_on_flail_projectile_hit)
	projectile.returned.connect(_on_flail_returned.bind(projectile))
	flail_projectile = projectile
	flail_state = "outbound"
	_flail_release_pending = false
	projectile_parent.add_child(projectile)
	projectile.global_position = camera.global_position + direction * 0.45
	projectile.check_spawn_path(camera.global_position)
	_update_flail_pose()
	flail_thrown.emit(charge)
	_refresh_flail_hud()
	return {"accepted": true, "queued": false, "projectile": projectile, "charge": charge, "damage": damage, "range": FLAIL_PROFILE.throw_range(charge), "stamina_spent": 0.0}


func _update_flail(delta: float) -> void:
	if not is_inside_tree() or get_tree().paused:
		return
	if not _is_flail_equipped() or combat_state != CombatState.READY or safe_zone_mode or current_trap != null or is_timed_interacting():
		if _is_flail_busy() or is_instance_valid(flail_projectile):
			cancel_flail_action()
		_refresh_flail_hud()
		return
	var elapsed := maxf(delta, 0.0)
	match flail_state:
		"melee":
			flail_action_time += elapsed
			if not _flail_melee_hit_done and flail_action_time >= FLAIL_PROFILE.MELEE_HIT_TIME:
				_flail_melee_hit_done = true
				_perform_flail_melee_hit()
			if flail_state == "melee" and flail_action_time >= FLAIL_PROFILE.MELEE_DURATION:
				flail_state = "ready"
		"spinning":
			if _flail_release_pending:
				elapsed = minf(elapsed, maxf(0.0, FLAIL_PROFILE.MIN_SPIN_DURATION - flail_spin_time))
			flail_spin_time = minf(FLAIL_PROFILE.FULL_SPIN_DURATION, flail_spin_time + elapsed)
			flail_spin_phase = fposmod(flail_spin_phase + FLAIL_PROFILE.spin_rate(get_flail_charge()) * elapsed, TAU)
			if _flail_release_pending and flail_spin_time >= FLAIL_PROFILE.MIN_SPIN_DURATION - 0.000001:
				_launch_flail_throw(_flail_release_aim)
		"outbound", "returning":
			if not is_instance_valid(flail_projectile) or flail_projectile.is_queued_for_deletion():
				flail_projectile = null
				flail_state = "recovery"
				flail_cooldown = FLAIL_PROFILE.RECOVERY_DURATION
			else:
				flail_state = str(flail_projectile.get("phase"))
		"recovery":
			flail_cooldown = maxf(0.0, flail_cooldown - elapsed)
			if flail_cooldown <= 0.0:
				flail_state = "ready"
				flail_spin_time = 0.0
	_update_flail_pose()
	_refresh_flail_hud()


func _perform_flail_melee_hit() -> void:
	var damage := FLAIL_PROFILE.MELEE_DAMAGE * get_body_attack_multiplier()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.70
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position - head.global_basis.z * 1.55)
	query.collision_mask = ENEMY_LAYER
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 12)
	_append_located_melee_hit(hits, 2.25)
	for result: Dictionary in hits:
		var target := result.get("collider") as Node3D
		if not is_instance_valid(target) or not target.has_method("receive_hit") or not _has_clear_melee_path(target):
			continue
		var contact := _located_melee_contact(target, 2.25)
		if target.has_method("query_located_hit") and contact.is_empty():
			continue
		if not contact.is_empty() and target.has_method("receive_located_hit"):
			target.call("receive_located_hit", damage, global_position, 0.5, false, contact.position)
		else:
			target.call("receive_hit", damage, global_position, 0.5, false)
		attack_landed.emit(damage, false)
		if is_instance_valid(hud):
			hud.show_hit(false)


func _on_flail_projectile_hit(_target: Node, amount: float, headshot: bool) -> void:
	attack_landed.emit(amount, headshot)
	if is_instance_valid(hud):
		hud.show_hit(headshot)


func _on_flail_returned(projectile: Node3D) -> void:
	if flail_projectile != projectile:
		return
	flail_projectile = null
	flail_state = "recovery"
	flail_cooldown = FLAIL_PROFILE.RECOVERY_DURATION
	flail_spin_time = 0.0
	_update_flail_pose()
	_refresh_flail_hud()


func cancel_flail_action(reset_cooldown := true) -> void:
	if flail_state != "ready" and is_instance_valid(flail_visual_root) and is_instance_valid(weapon_pivot):
		var contacts: Dictionary = FLAIL_VISUALS.flail_hand_anchors(flail_visual_root)
		_flail_cancel_from = contacts.head if bool(contacts.head_attached) else (contacts.chain_anchor as Vector3).lerp(FLAIL_VISUALS.flail_head_pose(contacts.chain_anchor, "ready", 0, 0), 0.1)
		_flail_cancel_remaining = 0.18
		_flail_cancel_weapon_pose = weapon_pivot.transform
	if is_instance_valid(flail_projectile):
		flail_projectile.abort()
	flail_projectile = null
	flail_spin_time = 0.0
	flail_spin_phase = 0.0
	flail_action_time = 0.0
	_flail_release_pending = false
	_flail_release_aim = Vector3.ZERO
	_flail_melee_hit_done = false
	if reset_cooldown:
		flail_cooldown = 0.0
	flail_state = "recovery" if flail_cooldown > 0.0 else "ready"
	_update_flail_pose()
	_refresh_flail_hud()


func _update_flail_pose(delta: float = 0.0) -> void:
	if not is_instance_valid(flail_visual_root):
		return
	var attached := flail_state not in ["outbound", "returning"]
	FLAIL_VISUALS.set_head_visible(flail_visual_root, attached)
	if not attached:
		return
	var contacts: Dictionary = FLAIL_VISUALS.flail_hand_anchors(flail_visual_root)
	var elapsed := flail_action_time if flail_state == "melee" else flail_spin_time if flail_state == "spinning" else FLAIL_PROFILE.RECOVERY_DURATION - flail_cooldown if flail_state == "recovery" else 0.0
	var ball_position: Vector3 = FLAIL_VISUALS.flail_head_pose(contacts.chain_anchor, flail_state, elapsed, flail_spin_phase)
	if _flail_cancel_remaining > 0.0 and flail_state in ["ready", "recovery"]:
		_flail_cancel_remaining = maxf(0.0, _flail_cancel_remaining - maxf(delta, 0.0))
		ball_position = _flail_cancel_from.lerp(ball_position, MOTION.smooth_phase(1.0 - _flail_cancel_remaining / 0.18))
	FLAIL_VISUALS.set_head_position(flail_visual_root, ball_position, 0.008 if flail_state == "spinning" else 0.035)


func _refresh_flail_hud() -> void:
	if is_instance_valid(hud) and hud.is_inside_tree() and hud.has_method("update_flail"):
		hud.update_flail(_is_flail_equipped() and not safe_zone_mode and not camping, flail_state, get_flail_charge(), flail_cooldown)


func _is_bow_equipped() -> bool:
	return _equipped_weapon_type() == "bow"


func get_arrow_count() -> int:
	return inventory_model.count_item("wooden_arrow") if inventory_model != null else 0


func get_bow_draw_ratio() -> float:
	# One second split across physics frames can land a fraction below 1.0.
	# Treat that rounding residue as full draw, including damage/accuracy/HUD.
	if bow_draw_time >= BOW_DRAW_DURATION - 0.000001:
		return 1.0
	return clampf(bow_draw_time / BOW_DRAW_DURATION, 0.0, 1.0)


func get_bow_spread_degrees() -> float:
	return BOW_SHOT_PROFILE.spread_degrees(get_bow_draw_ratio())


func get_bow_damage() -> float:
	return BOW_SHOT_PROFILE.damage_for_draw(get_bow_draw_ratio()) * get_body_attack_multiplier()


func _advance_bow_draw(delta: float) -> void:
	if not bow_drawing or (is_inside_tree() and get_tree().paused):
		return
	# Damage caps at full draw, but maintaining the string remains an exertion.
	# Charge and cost use elapsed simulation time, never render-frame counts.
	var elapsed := maxf(0.0, delta)
	var stamina_per_second := BOW_DRAW_STAMINA_PER_SECOND * get_body_attack_stamina_multiplier()
	var spent := minf(maxf(0.0, stamina), stamina_per_second * elapsed)
	if spent > 0.0:
		_consume_stamina(spent)
		bow_draw_stamina_spent += spent
		bow_draw_time = minf(BOW_DRAW_DURATION, bow_draw_time + spent / stamina_per_second)
	if stamina <= 0.000001:
		stamina = 0.0
		# Exhaustion releases the string at the charge actually paid for. The
		# normal shot path validates weapon, ammo, pause and combat state, then
		# clears drawing before signals, so holding/releasing LMB cannot repeat it.
		var shot := release_bow_shot()
		if hud:
			hud.update_stamina(stamina, MAX_STAMINA)
			if bool(shot.get("accepted", false)):
				hud.show_event("기력 소진 · 시위를 놓아 자동 발사", 1.1)


func _bow_use_failure(require_stamina := true) -> String:
	if is_paralyzed():
		return "paralyzed"
	if camping:
		return "busy"
	if combat_state == CombatState.DEAD:
		return "dead"
	if safe_zone_mode:
		return "safe_zone"
	if not _is_bow_equipped():
		return "bow_required"
	if is_inside_tree() and get_tree().paused:
		return "paused"
	if combat_state != CombatState.READY or blocking or current_trap != null or is_timed_interacting():
		return "busy"
	if bow_cooldown > 0.0:
		return "cooldown"
	if get_arrow_count() <= 0:
		return "no_ammo"
	if require_stamina and stamina <= 0.0:
		return "not_enough_stamina"
	return ""


func begin_bow_draw() -> Dictionary:
	var reason := _bow_use_failure()
	if not reason.is_empty():
		return _bow_failure(reason)
	if bow_drawing:
		return _bow_failure("already_drawing")
	bow_drawing = true
	bow_draw_time = 0.0
	bow_draw_stamina_spent = 0.0
	blocking = false
	_refresh_archery_hud()
	return {"accepted": true}


func cancel_bow_draw() -> void:
	bow_drawing = false
	bow_draw_time = 0.0
	bow_draw_stamina_spent = 0.0
	_bow_recoil = 0.0
	bow_recoil_strength = 0.0
	_bow_recoil_side = 0.0
	_bow_release_draw = 0.0
	_bow_release_anchor = Vector3.ZERO
	if is_instance_valid(camera):
		camera.rotation = Vector3.ZERO
	if is_instance_valid(bow_visual_root):
		ARCHERY_VISUALS.set_bow_draw(bow_visual_root, 0.0)
	_refresh_archery_hud()


func release_bow_shot(aim_direction := Vector3.ZERO) -> Dictionary:
	if not bow_drawing:
		return _bow_failure("not_drawing")
	# Stamina is required to start drawing, not to let go of an already drawn
	# string. This also permits the one automatic release when stamina reaches 0.
	var reason := _bow_use_failure(false)
	if not reason.is_empty():
		cancel_bow_draw()
		return _bow_failure(reason)
	var draw_ratio := get_bow_draw_ratio()
	var release_anchor := _bow_string_anchor_for_draw(draw_ratio)
	# Report exertion already paid during this draw; release never charges twice.
	var cost := bow_draw_stamina_spent
	var projectile_parent: Node = game if is_instance_valid(game) else get_parent()
	if not is_inside_tree() or camera == null or projectile_parent == null:
		cancel_bow_draw()
		return _bow_failure("cannot_shoot_here")
	# Start close to the crosshair, then sweep the short camera-to-tip segment too.
	# A barrel/viewmodel beyond a thin wall must never let a shot bypass the wall.
	# The camera's short recoil rotation is cosmetic. The player's head owns
	# gameplay aim, so neither forced rapid shots nor the next draw inherit it.
	var camera_direction := -head.global_transform.basis.z
	var aimed_direction: Vector3 = aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else camera_direction.normalized()
	var projectile := ARROW_PROJECTILE_SCRIPT.new() as ArrowProjectile
	projectile.hit_target.connect(_on_arrow_projectile_hit)
	# Validate everything before consuming. No damage can happen until the arrow
	# transaction succeeds, even when the muzzle is already touching a collider.
	if not inventory_model.remove_item("wooden_arrow", 1):
		projectile.free()
		cancel_bow_draw()
		return _bow_failure("no_ammo")
	# Only an accepted shot samples RNG. A failed/cancelled draw cannot reroll
	# the spread, spend resources, or secretly change the next release.
	var slack := BOW_SHOT_PROFILE.is_slack_draw(draw_ratio)
	var direction := Vector3.DOWN if slack else BOW_SHOT_PROFILE.sample_direction(aimed_direction, draw_ratio, bow_shot_rng)
	var spread := BOW_SHOT_PROFILE.spread_degrees(draw_ratio)
	var origin := camera.global_position + (aimed_direction if slack else direction) * 0.18
	projectile.configure(self, direction, draw_ratio)
	var damage := BOW_SHOT_PROFILE.damage_for_draw(draw_ratio) * get_body_attack_multiplier()
	projectile.damage = damage
	cancel_bow_draw()
	bow_cooldown = BOW_SHOT_COOLDOWN
	_bow_release_anchor = release_anchor
	_bow_release_draw = draw_ratio
	_bow_recoil = BOW_RECOIL_DURATION
	bow_recoil_strength = BOW_SHOT_PROFILE.recoil_strength(draw_ratio)
	var lateral_deviation := (direction - aimed_direction).dot(camera.global_basis.x)
	_bow_recoil_side = clampf(lateral_deviation / maxf(sin(deg_to_rad(spread)), 0.001), -1.0, 1.0)
	projectile_parent.add_child(projectile)
	projectile.global_position = origin
	projectile.check_spawn_path(camera.global_position)
	arrow_fired.emit(draw_ratio, cost)
	_refresh_archery_hud()
	return {
		"accepted": true, "projectile": projectile, "draw_ratio": draw_ratio,
		"stamina_spent": cost, "arrows_spent": 1,
		"draw_stamina_spent": cost, "release_stamina_spent": 0.0,
		"base_damage": damage,
		"slack_drop": slack, "launch_speed": projectile.speed,
		"aim_direction": aimed_direction, "shot_direction": direction,
		"spread_degrees": spread, "recoil_strength": bow_recoil_strength,
	}


func _on_arrow_projectile_hit(_target: Node, damage: float, headshot: bool) -> void:
	attack_landed.emit(damage, headshot)
	if hud:
		hud.show_hit(headshot)


func _bow_failure(reason: String) -> Dictionary:
	if hud:
		match reason:
			"no_ammo":
				hud.show_event("화살이 없습니다 · 가방에 나무 화살을 준비하세요", 1.1)
			"not_enough_stamina":
				hud.show_event("활을 쏠 기력이 부족합니다", 0.9)
	return {"accepted": false, "reason": reason, "stamina_spent": 0.0, "arrows_spent": 0}


func _refresh_archery_hud() -> void:
	if hud != null:
		var camera_fov := camera.fov if is_instance_valid(camera) else 76.0
		hud.update_archery(_is_bow_equipped() and not safe_zone_mode and not camping, get_arrow_count(), get_bow_draw_ratio(), bow_drawing, bow_cooldown, get_bow_spread_degrees(), camera_fov)


func select_spell_by_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SPELL_CATALOG_SCRIPT.SPELL_ORDER.size():
		return false
	if not _is_staff_equipped():
		if hud:
			hud.show_event("주문을 선택하려면 마법사 지팡이를 장착하십시오", 0.9)
		return false
	var spell_id := str(SPELL_CATALOG_SCRIPT.SPELL_ORDER[slot_index])
	if not ExpeditionSession.select_spell(spell_id):
		if hud:
			hud.show_event("[%d] 아직 익히지 못한 주문입니다" % (slot_index + 1), 0.85)
		return false
	_refresh_magic_hud()
	if hud:
		hud.show_event("[%d] %s 선택" % [slot_index + 1, SPELL_CATALOG_SCRIPT.get_spell_name(spell_id)], 0.7)
	return true


func cast_spell(spell_id: String, aim_direction := Vector3.ZERO) -> Dictionary:
	if is_paralyzed():
		return _spell_failure("paralyzed")
	if camping:
		return _spell_failure("busy")
	var definition := SPELL_CATALOG_SCRIPT.get_spell_definition(spell_id)
	if definition.is_empty():
		return _spell_failure("invalid_spell")
	if not ExpeditionSession.is_spell_learned(spell_id):
		return _spell_failure("not_learned")
	if not _is_staff_equipped():
		return _spell_failure("staff_required")
	if combat_state == CombatState.DEAD:
		return _spell_failure("dead")
	if safe_zone_mode:
		return _spell_failure("safe_zone")
	if combat_state != CombatState.READY or blocking or current_trap != null or is_timed_interacting():
		return _spell_failure("busy")
	if spell_cooldown > 0.0:
		return _spell_failure("cooldown")
	var cast_type := str(definition.get("cast_type", ""))
	var treatment_part := get_selected_treatment_part()
	var repairs_blackout := bool(definition.get("repair_blackout", false))
	var repair_part := BODY_HEALTH.repair_target(_body_state(), treatment_part) if repairs_blackout else ""
	if cast_type == "heal":
		if BODY_HEALTH.is_dead(_body_state()):
			return _spell_failure("dead")
		if repairs_blackout and repair_part.is_empty():
			return _spell_failure("no_blacked_part")
		if not repairs_blackout and BODY_HEALTH.heal_capacity(_body_state(), treatment_part) <= 0.0:
			return _spell_failure("blacked_part" if not treatment_part.is_empty() and float(_body_state().parts[treatment_part]) <= 0.0 else "already_full")
	var stamina_cost := maxf(0.0, float(definition.get("stamina_cost", 0.0))) * get_body_attack_stamina_multiplier()
	if stamina < stamina_cost:
		return _spell_failure("not_enough_stamina")

	var projectile: MagicProjectile
	var health_restored := 0.0
	if cast_type == "projectile":
		projectile = _spawn_magic_projectile(spell_id, definition, aim_direction)
		if projectile == null:
			return _spell_failure("cannot_cast_here")
	elif cast_type == "heal":
		health_restored = restore_body_part(repair_part) if repairs_blackout else restore_health(float(definition.get("heal_amount", 0.0)), treatment_part)
		if health_restored > 0.0 and hud != null and hud.has_method("flash_healing"):
			hud.flash_healing()
	else:
		return _spell_failure("invalid_spell")

	_consume_stamina(stamina_cost)
	spell_cooldown = maxf(0.0, float(definition.get("cooldown", 0.5)))
	_cast_recoil = 0.22
	_camera_shake = maxf(_camera_shake, 0.035)
	spell_cast.emit(spell_id, stamina_cost)
	_refresh_magic_hud()
	return {
		"accepted": true,
		"spell_id": spell_id,
		"cast_type": cast_type,
		"stamina_spent": stamina_cost,
		"projectile": projectile,
		"health_restored": health_restored,
		"repaired_part": repair_part,
	}


func _try_cast_selected_spell() -> void:
	var spell_id := ExpeditionSession.get_selected_spell()
	if spell_id.is_empty():
		if hud:
			hud.show_event("먼저 마법서를 사용해 주문을 익히십시오", 1.0)
		return
	var result := cast_spell(spell_id)
	if bool(result.get("accepted", false)):
		if hud:
			var message := "%s 시전 · 기력 -%d" % [SPELL_CATALOG_SCRIPT.get_spell_name(spell_id), roundi(float(result.get("stamina_spent", 0.0)))]
			if float(result.get("health_restored", 0.0)) > 0.0:
				message += " · 체력 +%d" % roundi(float(result.get("health_restored", 0.0)))
			hud.show_event(message, 0.75)
		return
	if hud:
		var reason := str(result.get("reason", ""))
		match reason:
			"staff_required":
				hud.show_event("마법사 지팡이를 장착해야 합니다", 0.9)
			"not_enough_stamina":
				hud.show_event("마법을 시전할 기력이 부족합니다", 0.9)
			"already_full":
				hud.show_event("체력이 이미 가득합니다", 0.8)
			"cooldown":
				pass
			_:
				hud.show_event("지금은 마법을 사용할 수 없습니다", 0.8)


func _spawn_magic_projectile(spell_id: String, definition: Dictionary, aim_direction: Vector3) -> MagicProjectile:
	if not is_inside_tree() or camera == null:
		return null
	var origin := camera.global_position + (-camera.global_transform.basis.z * 0.85)
	if is_instance_valid(staff_muzzle):
		origin = staff_muzzle.global_position
	var travel_direction := aim_direction.normalized() if aim_direction.length_squared() > 0.0001 else _crosshair_spell_direction(origin)
	var projectile := MAGIC_PROJECTILE_SCRIPT.new() as MagicProjectile
	projectile.configure(spell_id, definition, self, travel_direction)
	projectile.hit_target.connect(_on_spell_projectile_hit)
	var projectile_parent: Node = game if is_instance_valid(game) else get_parent()
	if projectile_parent == null:
		projectile.free()
		return null
	projectile_parent.add_child(projectile)
	projectile.global_position = origin
	return projectile


func _crosshair_spell_direction(origin: Vector3) -> Vector3:
	var camera_direction := -camera.global_transform.basis.z
	var aim_from := camera.global_position
	var aim_to := aim_from + camera_direction * 45.0
	var query := PhysicsRayQueryParameters3D.create(aim_from, aim_to, WORLD_LAYER | ENEMY_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit.get("position", aim_to) as Vector3 if not hit.is_empty() else aim_to
	return origin.direction_to(aim_point)


func _on_spell_projectile_hit(_spell_id: String, _target: Node, spell_damage: float) -> void:
	attack_landed.emit(spell_damage, false)
	if hud:
		hud.show_hit(false)


func _spell_failure(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "stamina_spent": 0.0}


func _is_staff_equipped() -> bool:
	return _equipped_weapon_type() == "staff"


func is_dagger_equipped() -> bool:
	if inventory_model == null:
		return false
	return str(ExpeditionInventory.get_item_definition(str(inventory_model.equipment.get("weapon", ""))).get("weapon_family", "")) == "dagger"


func _has_melee_weapon_equipped() -> bool:
	return _equipped_weapon_type() == "melee"


func _equipped_weapon_type() -> String:
	# Standalone combat tests do not bind an inventory and retain the historical
	# sword default. Runtime scenes always bind their shared expedition inventory.
	if inventory_model == null:
		return "melee"
	var weapon_id := str(inventory_model.equipment.get("weapon", ""))
	if weapon_id.is_empty():
		return "unarmed"
	var definition := ExpeditionInventory.get_item_definition(weapon_id)
	if definition.is_empty():
		return "unarmed"
	return str(definition.get("weapon_type", "unarmed"))


func _on_inventory_changed() -> void:
	if _sword_attack_had_shield and not _has_shield_equipped():
		cancel_sword_attack()
	_sync_equipped_weapon()
	_refresh_archery_hud()


func _on_equipment_condition_changed(slot_name: String) -> void:
	if slot_name != "offhand": return
	_sync_shield_damage_visual()
	# A zero-condition item loaded/set outside a hit is unusable, but does not
	# fabricate an impact burst. Finish the current real block before removal.
	if not _shield_wear_resolving:
		var condition := inventory_model.get_equipment_durability("offhand")
		if not condition.is_empty() and float(condition.current) <= 0.0:
			blocking = false
			block_time = 0.0
		_refresh_carried_visibility()


func _sync_shield_damage_visual() -> void:
	var condition := inventory_model.get_equipment_durability("offhand") if inventory_model != null else {}
	SHIELD_DAMAGE.apply(shield_model, str(condition.get("stage", "high")))


func get_shield_damage_snapshot() -> Dictionary:
	var result := inventory_model.get_equipment_durability("offhand") if inventory_model != null else {}
	result.merge(SHIELD_DAMAGE.snapshot(shield_model))
	return result


func get_shield_shatter_snapshot() -> Dictionary:
	var result: Dictionary = _shield_debris.snapshot() if is_instance_valid(_shield_debris) else {"active": false, "fragment_count": 0, "age": 0.0, "bodies": []}
	result["spawn_count"] = _shield_shatter_count
	return result


func clear_shield_fragments() -> void:
	if is_instance_valid(_shield_debris):
		if _shield_debris.get_parent() != null: _shield_debris.get_parent().remove_child(_shield_debris)
		_shield_debris.queue_free()
	_shield_debris = null
	_shield_shatter_count = 0


func _apply_shield_wear(amount: float) -> bool:
	if inventory_model == null: return false
	var before := inventory_model.get_equipment_durability("offhand")
	_shield_wear_resolving = true
	var after := inventory_model.damage_equipment_durability("offhand", amount * SHIELD_WEAR_PER_BLOCKED_DAMAGE)
	_shield_wear_resolving = false
	return not before.is_empty() and not after.is_empty() and float(before.current) > 0.0 and float(after.current) <= 0.0


func _finish_shield_shatter() -> void:
	# Called only after the breaking hit's block/parry has been resolved.
	if inventory_model == null or str(inventory_model.equipment.get("offhand", "")) != "round_shield": return
	var condition := inventory_model.get_equipment_durability("offhand")
	if condition.is_empty() or float(condition.current) > 0.0: return
	var previous_count := _shield_shatter_count
	clear_shield_fragments()
	_shield_debris = SHIELD_SHATTER.new()
	_shield_debris.name = "ShieldShatterDebris"
	add_child(_shield_debris)
	_shield_debris.launch(shield_model.global_transform, velocity, -global_basis.z)
	_shield_shatter_count = previous_count + 1
	inventory_model.discard_equipment("offhand")
	blocking = false
	block_time = 0.0
	_shield_raise_progress = 0.0
	_shield_impact = 0.0
	_shield_stowed = true
	_suppress_automatic_torch_hand = true
	_shield_stow_elapsed = SHIELD_STOW_DURATION
	_refresh_carried_visibility()
	if hud: hud.show_event("방패가 산산이 부서졌습니다", 1.5)


func _sync_equipped_weapon() -> void:
	_sync_shield_damage_visual()
	var equipped_identity := "" if inventory_model == null else str(inventory_model.equipment.get("weapon", "")) + str(inventory_model.get_equipment_instance("weapon").get("uid", ""))
	var equipped_offhand := "" if inventory_model == null else str(inventory_model.equipment.get("offhand", ""))
	if equipped_identity != _displayed_weapon_identity or equipped_offhand != _displayed_offhand:
		cancel_execution()
		cancel_bandage_motion()
		reset_shield_carry()
	var weapon_type := _equipped_weapon_type()
	if is_instance_valid(sword_visual_root):
		sword_visual_root.visible = weapon_type == "melee" and not is_dagger_equipped()
	if is_instance_valid(dagger_visual_root):
		dagger_visual_root.visible = is_dagger_equipped()
		var held_visual := dagger_visual_root if is_dagger_equipped() else sword_visual_root
		sword_blade = held_visual.find_child("PittedBlade", true, false) as MeshInstance3D
	if is_instance_valid(sword_visual_root) and not is_dagger_equipped():
		_sync_smithing_weapon_visual()
	if is_instance_valid(staff_visual_root):
		staff_visual_root.visible = weapon_type == "staff"
	if is_instance_valid(bow_visual_root):
		bow_visual_root.visible = weapon_type == "bow"
	if is_instance_valid(flail_visual_root):
		flail_visual_root.visible = weapon_type == "flail"
	_refresh_carried_visibility()
	var identity := "" if inventory_model == null else str(inventory_model.equipment.get("weapon", "")) + str(inventory_model.get_equipment_instance("weapon").get("uid", ""))
	var offhand := "" if inventory_model == null else str(inventory_model.equipment.get("offhand", ""))
	var weapon_changed := _displayed_weapon_type != weapon_type or _displayed_weapon_identity != identity
	var shield_added := offhand == "round_shield" and _displayed_offhand != offhand
	_displayed_offhand = offhand
	if not weapon_changed:
		if shield_added and _motion_initialized:
			begin_equipment_draw(false, true)
		return
	_displayed_weapon_type = weapon_type
	_displayed_weapon_identity = identity
	if _motion_initialized:
		_motion_equip_elapsed = 0.0
		reset_reference_movement_motion()
	_motion_initialized = is_instance_valid(weapon_pivot)
	cancel_bow_draw()
	cancel_flail_action()
	cancel_sword_attack()
	_refresh_magic_hud()
	_sword_draw_elapsed = SWORD_DRAW_DURATION
	if _motion_initialized and weapon_type == "melee" and not safe_zone_mode:
		begin_equipment_draw(true, _has_shield_equipped())


func handle_primary_weapon_input(event: InputEvent) -> bool:
	if not InputMap.has_action("primary_weapon") or not event.is_action_pressed("primary_weapon") or event.is_echo() or not _has_melee_weapon_equipped():
		return false
	request_primary_weapon()
	return true


func request_primary_weapon() -> Dictionary:
	if is_paralyzed():
		return {"accepted": false, "reason": "paralyzed"}
	if (is_inside_tree() and get_tree().paused) or safe_zone_mode or camping or chest_equipment_stowed or is_timed_interacting() or current_trap != null or combat_state != CombatState.READY:
		return {"accepted": false, "reason": "busy"}
	if not _has_melee_weapon_equipped() or not _has_shield_equipped():
		return {"accepted": false, "reason": "no_held_shield"}
	if _equipment_draw_active():
		return {"accepted": false, "reason": "drawing"}
	# The item remains equipped in the bag; carried presentation and guard use
	# stop independently, so inventory notifications cannot re-equip the shield.
	_shield_stow_from = shield_pivot.transform
	_shield_stowed = true
	_suppress_automatic_torch_hand = true
	_shield_stow_elapsed = 0.0
	blocking = false
	_shield_raise_progress = 0.0
	_shield_impact = 0.0
	_update_viewmodel(0.0)
	return {"accepted": true, "action": "stow_shield"}


func reset_shield_carry() -> void:
	_shield_stowed = false
	_suppress_automatic_torch_hand = false
	_shield_stow_elapsed = SHIELD_STOW_DURATION


func _shield_stowing() -> bool:
	return _shield_stowed and _shield_stow_elapsed < SHIELD_STOW_DURATION


func _sword_support_requested() -> bool:
	return _shield_stowed and _suppress_automatic_torch_hand and not safe_zone_mode and _equipped_weapon_type() == "melee" and not is_dagger_equipped()


func _sword_support_progress() -> float:
	return clampf((_shield_stow_elapsed - SHIELD_STOW_DURATION) / SWORD_SUPPORT_DURATION, 0.0, 1.0) if _sword_support_requested() else 0.0


func _shield_visible_in_hand() -> bool:
	return _shield_item_usable() and (not _shield_stowed or _shield_stowing())


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


func _draw_reach_flexion(digit: String, time: float) -> Vector3:
	# Open during the reach, then wrap from the little finger toward the index.
	# These are additional bends: the mesh already has flexion in its rest pose.
	var initial: Vector3
	var opened: Vector3
	var grasp: Vector3
	var start: float
	match digit:
		"little":
			initial = Vector3(.10, .60, .32); opened = Vector3(.03, .22, .12)
			grasp = Vector3(.60, .72, .46); start = .105
		"ring":
			initial = Vector3(.08, .65, .30); opened = Vector3(.02, .25, .10)
			grasp = Vector3(.58, .74, .44); start = .12
		"middle":
			initial = Vector3(.09, .70, .28); opened = Vector3(.025, .28, .09)
			grasp = Vector3(.54, .71, .40); start = .135
		"index":
			initial = Vector3(.06, .65, .25); opened = Vector3(.015, .24, .08)
			grasp = Vector3(.48, .66, .36); start = .15
		"thumb":
			initial = Vector3(.05, .08, .09); opened = Vector3(.01, .025, .035)
			grasp = Vector3(.42, .35, .28); start = .185
		_:
			return Vector3.ZERO
	var result := initial.lerp(opened, MOTION.smooth_phase(time / .09))
	for joint in 3:
		# The knuckle leads, followed by the middle and tip joints.
		var closure := MOTION.smooth_phase((time - start - joint * .018) / .145)
		result[joint] = lerpf(result[joint], grasp[joint], closure)
	return result


func _refresh_magic_hud() -> void:
	if hud == null or not hud.has_method("update_magic"):
		return
	var magic := ExpeditionSession.get_magic_snapshot()
	hud.update_magic(
		magic.get("learned", []) as Array[String],
		str(magic.get("selected", "")),
		_is_staff_equipped() and not camping
	)
	_refresh_archery_hud()
	_refresh_flail_hud()


func _body_state() -> Dictionary:
	if _body_health_session_bound:
		ExpeditionSession.ensure_journey()
		return ExpeditionSession.body_health
	return _body_health_state


func get_body_health_snapshot() -> Dictionary:
	return BODY_HEALTH.snapshot(_body_state(), ExpeditionSession.active_conditions)


func get_selected_treatment_part() -> String:
	return str(_body_state().get("selected_part", ""))


func select_treatment_part(part: String) -> bool:
	if not part.is_empty() and not BODY_HEALTH.PART_MAX_HEALTH.has(part):
		return false
	_body_state()["selected_part"] = part
	return true


func reset_body_health() -> void:
	cancel_item_use()
	cancel_bandage_motion()
	BODY_HEALTH.set_total_for_debug(_body_state(), MAX_HEALTH)
	_last_body_health = health
	combat_state = CombatState.READY
	_refresh_body_health_hud()


func restore_body_part(part: String = "") -> float:
	if combat_state == CombatState.DEAD:
		return 0.0
	var restored := BODY_HEALTH.repair(_body_state(), part)
	_last_body_health = health
	_refresh_body_health_hud()
	return restored


func apply_body_damage(part: String, amount: float) -> Dictionary:
	if combat_state == CombatState.DEAD:
		return {"accepted": false, "damage": 0.0, "part": part, "blacked": false, "dead": true}
	var result := BODY_HEALTH.damage(_body_state(), part, amount)
	if bool(result.accepted):
		_interrupt_camp("공격받아 야영이 중단되었습니다 · 사용한 보급품은 반환되지 않습니다")
		cancel_bow_draw()
		cancel_flail_action()
		sync_body_health_from_session()
	return result


func sync_body_health_from_session() -> void:
	var actual_damage := maxf(0.0, _last_body_health - health)
	_last_body_health = health
	if actual_damage > 0.0:
		cancel_execution()
		ExpeditionSession.add_stress(StressProfile.damage_gain(actual_damage))
		_camera_shake = maxf(_camera_shake, 0.16)
		if is_instance_valid(hud):
			hud.flash_damage()
	_refresh_body_health_hud()
	if is_paralyzed():
		blocking = false
		velocity.x = 0.0
		velocity.z = 0.0
		cancel_sword_attack()
		cancel_bow_draw()
		cancel_flail_action()
		cancel_timed_interaction()
	if BODY_HEALTH.is_dead(_body_state()) and combat_state != CombatState.DEAD:
		cancel_timed_interaction()
		cancel_sword_attack()
		cancel_item_use()
		combat_state = CombatState.DEAD
		blocking = false
		if is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()


func _refresh_body_health_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.update_health(health, MAX_HEALTH)
	if hud.has_method("update_body_health"):
		hud.call("update_body_health", get_body_health_snapshot())
	if hud.has_method("update_stress"):
		hud.update_stress(ExpeditionSession.stress, StressProfile.MAX_STRESS, StressProfile.stage_name(ExpeditionSession.stress))


func is_paralyzed() -> bool:
	return float(ExpeditionSession.active_conditions.get("paralysis", 0.0)) > 0.0


func get_body_movement_multiplier() -> float:
	if is_paralyzed():
		return 0.0
	var injuries := BODY_HEALTH.impairment_count(_body_state(), ["left_leg", "right_leg"], ExpeditionSession.active_conditions)
	return pow(0.65, injuries)


func get_body_combat_multiplier() -> float:
	return get_body_attack_multiplier()


func get_body_attack_multiplier() -> float:
	var injuries := BODY_HEALTH.impairment_count(_body_state(), ["left_arm", "right_arm"], ExpeditionSession.active_conditions)
	return pow(0.80, injuries)


func get_body_attack_stamina_multiplier() -> float:
	return 1.0 / maxf(0.1, get_body_attack_multiplier())


func receive_attack(amount: float, attacker_position: Vector3, ailment_id := "", part: String = "thorax") -> Dictionary:
	if combat_state == CombatState.DEAD:
		return {"parried": false, "blocked": false, "damage": 0.0}
	_release_exhausted_shield_guard()
	cancel_timed_interaction("피격으로 상호작용이 중단되었습니다")
	if current_trap != null and current_trap.has_method("cancel_disarm"):
		current_trap.call("cancel_disarm", "피격으로 해제가 중단되었습니다")

	var to_attacker := global_position.direction_to(attacker_position)
	to_attacker.y = 0.0
	to_attacker = to_attacker.normalized()
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var frontal := forward.dot(to_attacker) > cos(deg_to_rad(55.0))

	var shield_guard := _has_shield_equipped()
	if blocking and not is_paralyzed() and not _is_bow_equipped() and not _is_flail_equipped() and frontal and stamina > 0.0:
		var shattered := _apply_shield_wear(amount) if shield_guard else false
		if block_time <= JUST_GUARD_WINDOW:
			stamina = minf(MAX_STAMINA, stamina + 8.0)
			_shield_impact = CHOREOGRAPHY.IMPACT_SECONDS if shield_guard else 0.13
			_camera_shake = maxf(_camera_shake, 0.055)
			if hud:
				hud.update_stamina(stamina, MAX_STAMINA)
				hud.show_event("방패 저스트 가드 · 적 스턴" if shield_guard else "무기 저스트 가드", 0.9)
			if shattered: _finish_shield_shatter()
			return {"parried": true, "blocked": true, "damage": 0.0, "shield_guard": shield_guard}
		var stamina_damage := amount * 1.18
		if shield_guard:
			# The raised shield stops this strike. If it exhausts stamina,
			# lower the guard immediately so subsequent strikes are unguarded.
			_consume_stamina(stamina_damage)
			_shield_impact = CHOREOGRAPHY.IMPACT_SECONDS
			_camera_shake = maxf(_camera_shake, 0.035)
			if hud:
				hud.show_event("피해 차단 · 기력 고갈로 방패를 내립니다" if stamina <= 0.0 else "방패로 피해를 완전히 막았습니다", 0.9 if stamina <= 0.0 else 0.55)
			if shattered: _finish_shield_shatter()
			return {"parried": false, "blocked": true, "damage": 0.0, "condition": "", "shield_guard": true}
		if stamina >= stamina_damage:
			_consume_stamina(stamina_damage)
			var chip_damage := ceilf(amount * 0.18)
			_shield_impact = CHOREOGRAPHY.IMPACT_SECONDS if _has_shield_equipped() else 0.1
			_camera_shake = maxf(_camera_shake, 0.035)
			_apply_health_damage(chip_damage, part)
			var chip_condition := _apply_damage_condition(ailment_id, chip_damage, part)
			if hud:
				hud.show_event("무기로 막았습니다", 0.55)
			return {"parried": false, "blocked": true, "damage": chip_damage, "condition": chip_condition}
		stamina = 0.0
		stamina_regen_delay = 1.1
		_shield_impact = CHOREOGRAPHY.IMPACT_SECONDS if _has_shield_equipped() else 0.22
		_set_combat_state(CombatState.GUARD_BREAK)
		var break_damage := ceilf(amount * 0.55)
		_apply_health_damage(break_damage, part)
		var break_condition := _apply_damage_condition(ailment_id, break_damage, part)
		return {"parried": false, "blocked": true, "damage": break_damage, "condition": break_condition}

	_apply_health_damage(amount, part)
	var applied_condition := _apply_damage_condition(ailment_id, amount, part)
	return {"parried": false, "blocked": false, "damage": amount, "condition": applied_condition}


func receive_environment_damage(amount: float, cause: String, ailment_id := "", part: String = "left_leg") -> void:
	if combat_state == CombatState.DEAD:
		return
	cancel_timed_interaction("피격으로 상호작용이 중단되었습니다")
	if current_trap != null and current_trap.has_method("cancel_disarm"):
		current_trap.call("cancel_disarm", "해제 실패")
	_apply_health_damage(amount, part)
	_apply_damage_condition(ailment_id, amount, part)
	if hud:
		hud.show_event("%s · -%d 체력" % [cause, roundi(amount)], 1.4)


func _apply_health_damage(amount: float, part: String = "thorax") -> void:
	apply_body_damage(part, amount)


func get_max_health() -> float:
	return MAX_HEALTH


func get_healable_health_capacity(part: String = "") -> float:
	return BODY_HEALTH.heal_capacity(_body_state(), part)


func restore_health(amount: float, part: String = "") -> float:
	if combat_state == CombatState.DEAD or amount <= 0.0:
		return 0.0
	var multiplier := 0.5 if float(ExpeditionSession.active_conditions.get("curse", 0.0)) > 0.0 else 1.0
	var restored := BODY_HEALTH.heal(_body_state(), amount * multiplier, part)
	_last_body_health = health
	_refresh_body_health_hud()
	return restored


func use_consumable(item_id: String, inventory: ExpeditionInventory, validate_only := false, play_motion := true, treatment_override := "_current") -> Dictionary:
	if combat_state == CombatState.DEAD or BODY_HEALTH.is_dead(_body_state()):
		return _consumable_failure("dead", "사망한 상태에서는 물품을 사용할 수 없습니다.")
	if camping:
		return _consumable_failure("busy", "야영 중에는 야영 메뉴에서 보급품을 사용하세요.")
	if inventory == null:
		return _consumable_failure("missing_inventory", "가방을 확인할 수 없습니다.")
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty() or str(definition.get("category", "")) != "consumable":
		return _consumable_failure("not_consumable", "이 물품은 바로 사용할 수 없습니다.")
	var effect := str(definition.get("effect", ""))
	if effect == "learn_spell":
		if validate_only:
			var spell_id := str(definition.get("spell_id", ""))
			if not SPELL_CATALOG_SCRIPT.is_valid_spell(spell_id) or ExpeditionSession.is_spell_learned(spell_id):
				return _consumable_failure("already_learned", "배울 수 있는 새 주문이 없습니다.")
			return {"accepted": true} if inventory.count_item(item_id) > 0 else _consumable_failure("not_owned", "소지하지 않은 물품입니다.")
		var learning_result := ExpeditionSession.learn_spell_from_book(item_id, inventory)
		if bool(learning_result.get("accepted", false)):
			_refresh_magic_hud()
		return learning_result
	var amount := maxf(0.0, float(definition.get("amount", 0.0)))
	var treatment_part := get_selected_treatment_part() if treatment_override == "_current" else treatment_override
	var condition_to_clear := "bleeding" if effect == "bandage" else str(definition.get("condition", ""))
	var can_clear_condition := not condition_to_clear.is_empty() and ExpeditionSession.condition_affects_part(condition_to_clear, treatment_part)
	var repair_part := BODY_HEALTH.repair_target(_body_state(), treatment_part) if effect == "surgery" else ""
	match effect:
		"heal", "bandage":
			if BODY_HEALTH.heal_capacity(_body_state(), treatment_part) <= 0.0 and not can_clear_condition:
				if not treatment_part.is_empty() and float(_body_state().parts[treatment_part]) <= 0.0:
					return _consumable_failure("blacked_part", "체력이 0인 부위는 먼저 수술 도구나 고위 복구 마법으로 치료해야 합니다.")
				return _consumable_failure("already_full", "일반 회복으로 치료할 수 있는 상처가 없습니다.")
		"surgery":
			if repair_part.is_empty():
				return _consumable_failure("no_blacked_part", "복구할 수 있는 체력 0 부위가 없습니다.")
		"cure_condition":
			if not can_clear_condition:
				return _consumable_failure("condition_absent", "해당 부위에 치료할 상태이상이 없습니다.")
		"restore_hunger":
			if ExpeditionSession.hunger >= ExpeditionSession.MAX_NEED:
				return _consumable_failure("already_full", "이미 충분히 배부릅니다.")
		"restore_thirst":
			if ExpeditionSession.thirst >= ExpeditionSession.MAX_NEED:
				return _consumable_failure("already_full", "이미 수분이 충분합니다.")
		_:
			return _consumable_failure("unsupported_effect", "이 물품은 현재 가방에서 바로 사용할 수 없습니다.")
	if validate_only:
		return {"accepted": true} if inventory.count_item(item_id) > 0 else _consumable_failure("not_owned", "소지하지 않은 물품입니다.")
	if not inventory.remove_item(item_id, 1):
		return _consumable_failure("not_owned", "가방에서 해당 아이템을 찾을 수 없습니다.")

	var health_restored := 0.0
	var hunger_restored := 0.0
	var thirst_restored := 0.0
	var condition_cleared := ""
	match effect:
		"heal", "bandage":
			health_restored = restore_health(amount, treatment_part)
			if can_clear_condition and _clear_treatment_condition(condition_to_clear, treatment_part):
				condition_cleared = condition_to_clear
		"surgery":
			health_restored = restore_body_part(repair_part)
		"cure_condition":
			if _clear_treatment_condition(condition_to_clear, treatment_part):
				condition_cleared = condition_to_clear
		"restore_hunger":
			var restored_hunger := ExpeditionSession.restore_needs(amount, 0.0)
			hunger_restored = float(restored_hunger.get("hunger", 0.0))
		"restore_thirst":
			var restored_thirst := ExpeditionSession.restore_needs(0.0, amount)
			thirst_restored = float(restored_thirst.get("thirst", 0.0))
	_refresh_survival_hud()
	var item_name := ExpeditionInventory.get_item_name(item_id)
	var result_parts: Array[String] = ["%s 사용" % item_name]
	if health_restored > 0.0:
		result_parts.append("체력 +%d" % roundi(health_restored))
	if hunger_restored > 0.0:
		result_parts.append("포만감 +%d" % roundi(hunger_restored))
	if thirst_restored > 0.0:
		result_parts.append("수분 +%d" % roundi(thirst_restored))
	if not condition_cleared.is_empty():
		result_parts.append("%s 해소" % ExpeditionSession.get_condition_display_name(condition_cleared))
	if play_motion: _play_consumable_motion(item_id, treatment_part)
	return {
		"accepted": true,
		"message": " · ".join(result_parts),
		"health_restored": health_restored,
		"hunger_restored": hunger_restored,
		"thirst_restored": thirst_restored,
		"condition_cleared": condition_cleared,
		"repaired_part": repair_part,
	}


func _clear_treatment_condition(condition_id: String, part: String) -> bool:
	var cleared := ExpeditionSession.clear_condition_from_part(condition_id, part)
	if cleared and not _body_health_session_bound:
		if ExpeditionSession.body_health.condition_parts.has(condition_id):
			_body_state().condition_parts[condition_id] = (ExpeditionSession.body_health.condition_parts[condition_id] as Array).duplicate()
		else:
			_body_state().condition_parts.erase(condition_id)
	return cleared


func apply_condition(condition_id: String, duration := -1.0, part: String = "") -> bool:
	var applied := ExpeditionSession.apply_condition(condition_id, duration, part)
	if applied:
		if not _body_health_session_bound and ExpeditionSession.body_health.condition_parts.has(condition_id):
			_body_state().condition_parts[condition_id] = (ExpeditionSession.body_health.condition_parts[condition_id] as Array).duplicate()
		sync_body_health_from_session()
		_refresh_survival_hud()
	return applied


func _apply_damage_condition(condition_id: String, damage: float, part: String = "") -> String:
	if damage <= 0.0 or condition_id.is_empty() or combat_state == CombatState.DEAD:
		return ""
	return condition_id if apply_condition(condition_id, -1.0, part) else ""


func _refresh_survival_hud() -> void:
	if not is_instance_valid(hud):
		return
	var survival := ExpeditionSession.get_survival_snapshot()
	hud.update_survival(float(survival.get("hunger", ExpeditionSession.MAX_NEED)), float(survival.get("thirst", ExpeditionSession.MAX_NEED)), float(survival.get("maximum", ExpeditionSession.MAX_NEED)))
	hud.update_conditions(survival.get("conditions", {}) as Dictionary, float(survival.get("drain_multiplier", 1.0)))
	if hud.has_method("update_stress"):
		hud.update_stress(ExpeditionSession.stress, StressProfile.MAX_STRESS, StressProfile.stage_name(ExpeditionSession.stress))


func _consumable_failure(reason: String, message: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "message": message}


func _consume_stamina(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	stamina_regen_delay = 0.72
	_release_exhausted_shield_guard()
	if hud:
		hud.update_stamina(stamina, MAX_STAMINA)


func _release_exhausted_shield_guard() -> void:
	if not blocking or stamina > 0.0 or not _has_shield_equipped():
		return
	blocking = false
	block_time = 0.0
	if hud:
		hud.update_weapon_state("기력 부족 · 방패를 들 수 없습니다", Color(0.9, 0.58, 0.3))


func _update_stamina(delta: float) -> void:
	if stamina_regen_delay <= 0.0 and combat_state != CombatState.WINDUP and not bow_drawing and not _is_flail_busy() and not blocking and stamina < MAX_STAMINA:
		stamina = minf(MAX_STAMINA, stamina + 25.0 * delta)
		if hud:
			hud.update_stamina(stamina, MAX_STAMINA)


func _set_combat_state(next_state: CombatState) -> void:
	if next_state != CombatState.READY:
		cancel_bandage_motion()
	combat_state = next_state
	state_time = 0.0
	if is_instance_valid(viewmodel_renderer) and next_state != CombatState.EXECUTION:
		# Let real skin occlude the dagger while it enters and leaves the body.
		# Returning, cancelling or switching equipment restores the carried pass.
		viewmodel_renderer.set_world_contact_enabled(is_dagger_equipped() and next_state in [CombatState.ACTIVE, CombatState.RECOVERY])
	if next_state == CombatState.READY:
		_sword_direct_entry = false
		_sword_entry_arm.clear()
		_sword_clash_recovering = false
		attack_release_requested = false
		attack_hit_ids.clear()
		_sword_attack_uses_cycle = false
		_sword_attack_had_shield = false


func _update_viewmodel(delta: float) -> void:
	if weapon_pivot == null or delta < 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if is_execution_active():
		_update_execution_viewmodel()
		return
	advance_bandage_motion(delta)
	if is_bandage_motion_active():
		_refresh_carried_visibility()
		return
	if chest_equipment_stowed:
		_reference_arm_target.clear()
		_apply_chest_equipment_pose()
		_update_character_arms()
		return
	_shield_stow_elapsed = minf(SHIELD_STOW_DURATION + SWORD_SUPPORT_DURATION, _shield_stow_elapsed + delta)
	# Actions may interrupt presentation immediately; the existing pose handoff
	# blends from the actual drawn position without delaying gameplay contact.
	if combat_state != CombatState.READY or blocking or safe_zone_mode or camping:
		_sword_draw_elapsed = SWORD_DRAW_DURATION
	else:
		_sword_draw_elapsed = minf(SWORD_DRAW_DURATION, _sword_draw_elapsed + delta)
	_motion_clock += delta
	_motion_equip_elapsed = minf(MOTION.EQUIP_DURATION, _motion_equip_elapsed + delta)
	if _motion_flail_phase != flail_state:
		_motion_flail_transition_from = weapon_pivot.transform
		_motion_flail_phase = flail_state
		_motion_flail_elapsed = 0.0
	else:
		_motion_flail_elapsed += delta
	var phase := str(CombatState.keys()[combat_state]).to_lower()
	var weapon := _equipped_weapon_type()
	var bow_impulse := 0.0
	var paired_sword := weapon == "melee" and _has_shield_equipped() and not is_dagger_equipped()
	var coordinated_sword := weapon == "melee" and _uses_coordinated_sword_motion()
	_shield_raise_progress = move_toward(_shield_raise_progress, 1.0 if blocking and _has_shield_equipped() else 0.0, delta / (CHOREOGRAPHY.RAISE_SECONDS if blocking else CHOREOGRAPHY.LOWER_SECONDS))
	var reference_enabled := weapon == "melee" and not is_dagger_equipped() and not safe_zone_mode and REFERENCE_MOTION.is_available()
	var reference_guard_owned := blocking or _shield_raise_progress > 0.0
	_advance_reference_pose_handoff(reference_enabled, phase, reference_guard_owned, delta)
	var target := MOTION.sword(phase, state_time, attack_charge, blocking, paired_sword or (coordinated_sword and not blocking), sword_attack_variant)
	if paired_sword:
		if phase == "ready": target = CHOREOGRAPHY.guard_sword(_shield_raise_progress)
		if phase == "recovery" and _sword_clash_recovering and not reference_enabled:
			target = CHOREOGRAPHY.mix(_sword_clash_weapon_pose,CHOREOGRAPHY.ready(),state_time / lerpf(0.47,0.68,attack_charge))
		var pulse := CHOREOGRAPHY.recoil(_shield_impact) if _shield_impact > 0.0 else 0.0
		target.origin += Vector3(0.012, 0.018, 0.024) * pulse
		target.basis = target.basis * Basis(Vector3.RIGHT, 0.045 * pulse)
	if is_dagger_equipped():
		target = DAGGER_MOTION.pose(phase, state_time, blocking)
	elif weapon == "bow":
		var draw := get_bow_draw_ratio() if bow_drawing else 0.0
		var release_progress := 1.0 - bow_cooldown / BOW_SHOT_COOLDOWN if bow_cooldown > 0.0 and _bow_release_draw > 0.0 else 1.0
		target = MOTION.bow(draw, release_progress, _bow_release_draw)
		bow_impulse = pow(clampf(_bow_recoil / BOW_RECOIL_DURATION, 0.0, 1.0), 2.0) * bow_recoil_strength
		target.origin += Vector3(_bow_recoil_side * 0.025, 0.018, 0.075) * bow_impulse
		ARCHERY_VISUALS.set_bow_draw(bow_visual_root, draw)
		var nocked_arrow := bow_visual_root.get_node_or_null("NockedArrow") as Node3D
		if nocked_arrow != null:
			nocked_arrow.visible = get_arrow_count() > 0 and bow_cooldown <= 0.0
	elif weapon == "flail":
		var elapsed := flail_action_time if flail_state == "melee" else flail_spin_time if flail_state == "spinning" else _motion_flail_elapsed
		target = MOTION.flail(flail_state, elapsed, flail_spin_phase, get_flail_charge())
	elif weapon == "staff":
		target = MOTION.staff(_cast_recoil)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_motion_speed = lerpf(_motion_speed, planar_speed, MOTION.damping(8.0, delta))
	var local_velocity := global_basis.inverse() * velocity if is_inside_tree() else velocity
	var sword_airborne := weapon == "melee" and _movement_ground_known and not _movement_grounded
	var movement := MOTION.locomotion(_motion_clock, 0.0 if sword_airborne else _motion_speed, local_velocity.x, bow_drawing or blocking or phase != "ready")
	var reference_locomotion := reference_enabled and not _equipment_draw_active() and phase == "ready" and not reference_guard_owned and _has_reference_locomotion()
	if reference_locomotion:
		target = _sample_reference_locomotion(target, delta)
		# Authored idle already contains its breathing. Retain ordinary walking
		# stride only, then remove that stride as the authored run/air takes over.
		if REFERENCE_MOTION.has_track("idle"):
			var stride_speed := 0.0 if sword_airborne else _motion_speed
			var breathing: Vector3 = MOTION.locomotion(_motion_clock, 0.0, 0.0, false).position
			movement.position -= breathing * (1.0 - minf(stride_speed / WALK_SPEED, 1.0))
		var authored_amount := 1.0 if _movement_phase != "grounded" or REFERENCE_MOTION.has_track("walk") else clampf((_motion_speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
		movement.position *= 1.0 - authored_amount
		movement.rotation *= 1.0 - authored_amount
	else:
		_reference_locomotion_valid = false
	if reference_enabled and phase == "recovery" and _sword_clash_recovering:
		target = CHOREOGRAPHY.ready()
	_reference_arm_target = _reference_right_arm_target(reference_enabled, reference_locomotion, phase, coordinated_sword, target)
	if _equipment_draw_active():
		movement.position = Vector3.ZERO
		movement.rotation = Vector3.ZERO
		if _draw_sword and not is_dagger_equipped():
			target = REFERENCE_MOTION.sample("equip", _sword_draw_elapsed)
			_reference_arm_target = REFERENCE_MOTION.sample_right_arm("equip", _sword_draw_elapsed)
		elif _draw_sword and is_dagger_equipped():
			var hidden := target
			hidden.origin += Vector3(-.45, -.55, .10)
			target = hidden.interpolate_with(target, MOTION.smooth_phase((_sword_draw_elapsed - .46) / (SWORD_DRAW_DURATION - .46)))
	target.origin += movement.position
	target.basis = target.basis * Basis.from_euler(movement.rotation)
	var look := Vector2(rotation.y, _pitch)
	if delta > 0.0:
		var look_velocity := Vector2(angle_difference(_motion_previous_look.x, look.x), angle_difference(_motion_previous_look.y, look.y)) / maxf(delta, 0.001)
		var wanted_sway := Vector2(clampf(look_velocity.x * -0.012, -0.028, 0.028), clampf(look_velocity.y * -0.010, -0.020, 0.020))
		_motion_look_sway = _motion_look_sway.lerp(wanted_sway, MOTION.damping(12.0, delta))
	_motion_previous_look = look
	target.origin += Vector3(_motion_look_sway.x, _motion_look_sway.y, 0)
	var raising := 1.0 - MOTION.smooth_phase(_motion_equip_elapsed / MOTION.EQUIP_DURATION)
	target.origin += Vector3(0.035, -0.27, 0.12) * raising
	target.basis = target.basis * Basis.from_euler(Vector3(0.32, 0, -0.12) * raising)
	# Continuous phase curves themselves are authoritative: do not chase them
	# with a frame-rate-dependent spring that shifts the visible contact time.
	if weapon == "flail" and flail_state == "returning" and _motion_flail_elapsed < 0.12:
		target = _motion_flail_transition_from.interpolate_with(target, MOTION.smooth_phase(_motion_flail_elapsed / 0.12))
	if weapon == "flail" and _flail_cancel_remaining > 0.0:
		target = _flail_cancel_weapon_pose.interpolate_with(target, MOTION.smooth_phase(1.0 - maxf(0.0, _flail_cancel_remaining - delta) / 0.18))
	if is_instance_valid(shield_pivot):
		var shield_target := CHOREOGRAPHY.shield(_shield_raise_progress, _shield_impact, phase, state_time, attack_charge, sword_attack_variant) if paired_sword else MOTION.shield(blocking, _shield_impact, phase)
		if paired_sword and phase == "recovery" and _sword_clash_recovering and not reference_enabled:
			shield_target = CHOREOGRAPHY.mix(_sword_clash_shield_pose,CHOREOGRAPHY.shield(0,0,"ready",0,0,sword_attack_variant),state_time / lerpf(0.47,0.68,attack_charge))
		if reference_locomotion:
			if not _reference_shield_valid:
				_reference_shield_valid = true
				_reference_shield_from = shield_target
			_reference_shield_pose = shield_target
			var authored_shield := _reference_locomotion_target(shield_target, "shield")
			_reference_shield_pose = _reference_shield_from.interpolate_with(authored_shield, MOTION.smooth_phase(_reference_locomotion_elapsed / 0.10))
			shield_target = _reference_shield_pose
		if reference_enabled and phase == "recovery" and _sword_clash_recovering:
			shield_target = CHOREOGRAPHY.shield(0, 0, "ready", 0, 0, sword_attack_variant)
		# Camera-space carry framing is applied after authored locomotion so it
		# remains at the lower-left edge while walking, running and recovering.
		shield_target.origin += _shield_corner_offset()
		shield_target.origin += movement.position * 0.65
		if paired_sword:
			shield_target.origin += Vector3(0,-0.22,0.08) * raising
		if _equipment_draw_active() and _draw_shield:
			shield_target = REFERENCE_MOTION.sample("equip", _sword_draw_elapsed, "shield")
		if paired_sword and _sword_attack_had_shield and not blocking and phase in ["windup", "active", "recovery"]:
			# Clear the sword path before contact, without delaying its direct entry.
			# Defense remains owned by blocking and stamina, not this visual pose.
			shield_pivot.transform = _sword_attack_shield_pose(phase)
		elif reference_enabled:
			shield_pivot.transform = _apply_reference_pose_handoff(shield_target, "shield")
		elif paired_sword:
			shield_pivot.transform = shield_target
		else:
			shield_pivot.transform = shield_pivot.transform.interpolate_with(shield_target, MOTION.damping(19.0 if blocking else 13.0, delta))
		if _shield_stowed:
			var stow_target := _shield_stow_from
			stow_target.origin += Vector3(-1.45, .05, .22)
			stow_target.basis = Basis(Vector3.UP, deg_to_rad(-45.0)) * stow_target.basis
			shield_pivot.transform = _shield_stow_from.interpolate_with(stow_target, MOTION.smooth_phase(_shield_stow_elapsed / SHIELD_STOW_DURATION))
		_shield_impact = maxf(0.0, _shield_impact - delta)
	if paired_sword:
		target = _match_sword_carry_to_shield(target, phase, reference_enabled)
	if reference_enabled:
		_compose_reference_arm(target)
		if _uses_direct_sword_entry(phase):
			# Both cuts start from the held pose and join their authored sweep.
			# Reuse the reverse cut's direct entry without an extra wrist windup.
			var entry_pose := _sword_entry_pose
			var entry_arm := _sword_entry_arm
			var entry_progress := 0.0 if phase == "windup" else _direct_sword_entry_progress()
			target = entry_pose.interpolate_with(target, entry_progress)
			_reference_arm_target = _mix_reference_arms(entry_arm, _reference_arm_target, entry_progress)
		target = _apply_reference_pose_handoff(target, "sword")
	weapon_pivot.transform = target
	_update_flail_pose(delta)
	_spell_visual_time += delta
	if is_instance_valid(staff_crystal):
		var cast_pulse := sin(clampf((0.22 - _cast_recoil) / 0.22, 0.0, 1.0) * PI) if _cast_recoil > 0 else 0.0
		staff_crystal.scale = Vector3(0.66, 1.18, 0.66) * (1.0 + sin(_spell_visual_time * 4.4) * 0.025 + cast_pulse * 0.10)
	if is_instance_valid(staff_light):
		staff_light.light_energy = 0.45 + sin(_spell_visual_time * 5.2) * 0.04 + _cast_recoil * 1.2
	if is_instance_valid(torch_pivot):
		var held := torch_enabled and _left_hand_role() == "torch"
		# One reversible path: lift from below the view, then settle at the side.
		# Reversing F mid-motion reverses travel from the current pose without a jump.
		var rate := 1.0 if held else TORCH_GRIP.DRAW_DURATION / TORCH_GRIP.STOW_DURATION
		_torch_draw_elapsed = move_toward(_torch_draw_elapsed, TORCH_GRIP.DRAW_DURATION if held else 0.0, maxf(delta, 0.0) * rate)
		var pocket := MOTION.pose(TORCH_GRIP.STOW_POSITION, TORCH_GRIP.STOW_ROTATION)
		var lower_edge := MOTION.pose(TORCH_GRIP.DRAW_POSITION, TORCH_GRIP.DRAW_ROTATION)
		var carry := MOTION.pose(TORCH_GRIP.CARRY_POSITION, TORCH_GRIP.CARRY_ROTATION)
		var torch_target: Transform3D
		if _torch_draw_elapsed < TORCH_GRIP.DRAW_REVEAL_TIME:
			torch_target = MOTION.blend(pocket, lower_edge, _torch_draw_elapsed / TORCH_GRIP.DRAW_REVEAL_TIME)
		else:
			torch_target = MOTION.blend(lower_edge, carry, (_torch_draw_elapsed - TORCH_GRIP.DRAW_REVEAL_TIME) / (TORCH_GRIP.DRAW_DURATION - TORCH_GRIP.DRAW_REVEAL_TIME))
		torch_target.origin += movement.position * 0.35 * MOTION.smooth_phase(_torch_draw_elapsed / TORCH_GRIP.DRAW_DURATION)
		torch_pivot.transform = torch_target
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta)
		camera.position = Vector3(sin(_motion_clock * 71.0), cos(_motion_clock * 83.0), 0) * _camera_shake * 0.11
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, MOTION.damping(22.0, delta))
	camera.rotation = Vector3(deg_to_rad(0.7), deg_to_rad(-0.35 * _bow_recoil_side), 0.0) * bow_impulse
	_refresh_carried_visibility()
	_update_character_arms()


func _sword_attack_shield_pose(phase: String) -> Transform3D:
	var clear_pose := _sword_entry_shield_pose
	clear_pose.origin += Vector3(-0.95, 0.02, 0.04)
	clear_pose.basis = Basis(Vector3.UP, deg_to_rad(-10.0)) * clear_pose.basis
	if phase == "recovery":
		# Keep the opening through the blade's exit, then ease back to carry.
		# A clash can interrupt the opening: recover from its exact visible pose.
		var start := _sword_clash_shield_pose if _sword_clash_recovering else clear_pose
		var rest := _reference_locomotion_target(CHOREOGRAPHY.shield(0, 0, "ready", 0, 0, sword_attack_variant), "shield")
		var duration := lerpf(0.47, 0.68, clampf(attack_charge, 0.0, 1.0))
		return start.interpolate_with(rest, MOTION.smooth_phase((state_time - 0.06) / (duration - 0.06)))
	# One clock across WINDUP/ACTIVE avoids restarting the opening on release.
	var opening := MOTION.smooth_phase((_motion_clock - _sword_entry_shield_clock) / 0.12)
	return _sword_entry_shield_pose.interpolate_with(clear_pose, opening)


func _advance_reference_pose_handoff(enabled: bool, phase: String, guard_owned: bool, delta: float) -> void:
	if not enabled:
		_reference_pose_key = ""
		_reference_pose_handoff_active = false
		return
	var key := ("guard" if guard_owned else "locomotion") if phase == "ready" else phase
	if _equipment_draw_active(): key = "draw"
	if key != _reference_pose_key:
		# Movement and guard can end at any sampled pose. Capture the actual
		# rendered pose before preparing a new target, including at delta=0.
		_reference_pose_handoff_active = not _reference_pose_key.is_empty() and key in ["windup", "guard", "locomotion"]
		if _reference_pose_handoff_active:
			_reference_pose_weapon_from = weapon_pivot.transform
			_reference_pose_shield_from = shield_pivot.transform if is_instance_valid(shield_pivot) else Transform3D.IDENTITY
			_reference_arm_handoff_from = _reference_arm_rendered.duplicate(true)
			_reference_pose_handoff_elapsed = 0.0
		_reference_pose_key = key
	if _reference_pose_handoff_active:
		_reference_pose_handoff_elapsed += delta
		# ACTIVE clears the charge handoff and owns its direct entry, including
		# a forehand released before the other cuts' minimum windup.
		if _reference_pose_handoff_elapsed >= 0.10:
			_reference_pose_handoff_active = false


func _apply_reference_pose_handoff(target: Transform3D, track: String) -> Transform3D:
	if combat_state == CombatState.RECOVERY and _sword_clash_recovering:
		var contact := _sword_clash_weapon_pose if track == "sword" else _sword_clash_shield_pose
		var elapsed := state_time / lerpf(0.47, 0.68, clampf(attack_charge, 0.0, 1.0))
		# All normal motion/equip/impact offsets have already been composed.
		# Blend once from contact to that moving target; t=0 is exactly contact.
		return contact.interpolate_with(target, MOTION.smooth_phase(elapsed))
	if _reference_pose_handoff_active:
		var previous := _reference_pose_weapon_from if track == "sword" else _reference_pose_shield_from
		return previous.interpolate_with(target, MOTION.smooth_phase(_reference_pose_handoff_elapsed / 0.10))
	return target


func _has_reference_locomotion() -> bool:
	if REFERENCE_MOTION.has_track("idle"): return true
	if _movement_ground_known and _movement_phase != "grounded":
		return REFERENCE_MOTION.has_track(_movement_phase)
	return REFERENCE_MOTION.has_track("run")


func _reference_locomotion_target(base: Transform3D, track: String) -> Transform3D:
	if REFERENCE_MOTION.has_track("idle", track):
		base = REFERENCE_MOTION.sample("idle", _motion_clock, track)
	if _movement_ground_known and _movement_phase != "grounded" and REFERENCE_MOTION.has_track(_movement_phase, track):
		var sampled := REFERENCE_MOTION.sample(_movement_phase, _movement_phase_time, track)
		return base.interpolate_with(sampled, _movement_landing_strength) if _movement_phase == "land" else sampled
	if REFERENCE_MOTION.has_track("walk", track):
		base = base.interpolate_with(REFERENCE_MOTION.sample("walk", _movement_run_time, track), MOTION.smooth_phase(clampf(_motion_speed / WALK_SPEED, 0.0, 1.0)))
	if REFERENCE_MOTION.has_track("run", track):
		var running := clampf((_motion_speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
		return base.interpolate_with(REFERENCE_MOTION.sample("run", _movement_run_time, track), MOTION.smooth_phase(running))
	return base


func _sample_reference_locomotion(base: Transform3D, delta: float) -> Transform3D:
	var key := _movement_phase if _movement_ground_known else "grounded"
	if not _reference_locomotion_valid:
		_reference_locomotion_valid = true
		_reference_shield_valid = false
		_reference_locomotion_pose = base
		_reference_locomotion_from = base
		_reference_arm_locomotion_from = _reference_arm_for_pivot(_reference_arm_rendered, base)
		_reference_locomotion_key = key
		_reference_locomotion_elapsed = 0.0
	elif key != _reference_locomotion_key:
		_reference_locomotion_from = _reference_locomotion_pose
		_reference_arm_locomotion_from = _reference_arm_for_pivot(_reference_arm_rendered, _reference_locomotion_from)
		_reference_shield_from = _reference_shield_pose
		_reference_locomotion_key = key
		_reference_locomotion_elapsed = 0.0
	var target := _reference_locomotion_target(base, "sword")
	_reference_locomotion_elapsed += delta
	_reference_locomotion_pose = _reference_locomotion_from.interpolate_with(target, MOTION.smooth_phase(_reference_locomotion_elapsed / 0.10))
	return _reference_locomotion_pose


func _reference_right_arm_target(enabled: bool, locomotion: bool, phase: String, paired: bool, pivot: Transform3D) -> Dictionary:
	if not enabled or not REFERENCE_MOTION.right_arm_available():
		return {}
	if locomotion:
		var result := REFERENCE_MOTION.sample_right_arm("idle", _motion_clock)
		if _movement_ground_known and _movement_phase != "grounded":
			var airborne := REFERENCE_MOTION.sample_right_arm(_movement_phase, _movement_phase_time)
			result = _mix_reference_arms(result, airborne, _movement_landing_strength) if _movement_phase == "land" else airborne
		else:
			if REFERENCE_MOTION.has_right_arm("walk"):
				result = _mix_reference_arms(result, REFERENCE_MOTION.sample_right_arm("walk", _movement_run_time), MOTION.smooth_phase(clampf(_motion_speed / WALK_SPEED, 0.0, 1.0)))
			var running := clampf((_motion_speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
			result = _mix_reference_arms(result, REFERENCE_MOTION.sample_right_arm("run", _movement_run_time), MOTION.smooth_phase(running))
		return _mix_reference_arms(_reference_arm_locomotion_from, result, MOTION.smooth_phase(_reference_locomotion_elapsed / 0.10))
	if phase == "recovery" and _sword_clash_recovering:
		return _reference_arm_for_pivot(REFERENCE_MOTION.sample_right_arm("idle", 0.0), pivot)
	if phase in ["windup", "active", "recovery"] and not blocking and REFERENCE_MOTION.has_right_arm(sword_attack_variant):
		var metadata := REFERENCE_MOTION.clip_metadata(sword_attack_variant)
		var time := REFERENCE_MOTION.authored_attack_time(metadata.timing, phase, state_time, attack_charge, paired)
		return REFERENCE_MOTION.sample_right_arm(sword_attack_variant, time)
	# Guard has its own gameplay pose. Supply a reachable anatomical target so
	# the same transition can blend into it from the last authored arm pose.
	return _reference_arm_for_pivot({}, pivot)


func _uses_direct_sword_entry(phase: String) -> bool:
	return _sword_direct_entry and not blocking and (phase == "windup" or (phase == "active" and state_time < _sword_direct_entry_duration()))


func _sword_direct_entry_duration() -> float:
	# Both cuts use the same held-to-authored entry timing.
	return SWORD_DIRECT_ENTRY_SECONDS


func _direct_sword_entry_progress() -> float:
	# Finish before the actual blade crossing and body contact. Zero endpoint
	# blend velocity joins the existing motion without a second lift or snap.
	return MOTION.smooth_phase(state_time / _sword_direct_entry_duration())


func _mix_reference_arms(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	if a.is_empty(): return b.duplicate(true)
	if b.is_empty(): return a.duplicate(true)
	if weight <= 0.0: return a.duplicate(true)
	if weight >= 1.0: return b.duplicate(true)
	var result := {"exact_sample": false}
	for joint: String in ["shoulder", "elbow", "wrist"]:
		result[joint] = (a[joint] as Vector3).lerp(b[joint], weight)
	result["requested_shoulder"] = (a.get("requested_shoulder", a.shoulder) as Vector3).lerp(b.get("requested_shoulder", b.shoulder), weight)
	result["raw_sword"] = (a.raw_sword as Transform3D).interpolate_with(b.raw_sword, weight)
	return result


func _reference_arm_for_pivot(arm: Dictionary, pivot: Transform3D) -> Dictionary:
	if arm.is_empty():
		var shoulder: Vector3 = SWORD_LONG_GRIP.SOURCE_READY * SWORD_LONG_GRIP.REST_SHOULDER
		var result := REFERENCE_ARM.solve(shoulder, shoulder + Vector3(0.75, -0.72, 0.28), pivot * SWORD_LONG_GRIP.REST_WRIST, _reference_arm_previous_bend)
		result["raw_sword"] = pivot
		result["exact_sample"] = false
		result["requested_shoulder"] = shoulder
		return result
	var result := arm.duplicate(true)
	var source: Transform3D = arm.raw_sword
	var offset := pivot * source.affine_inverse()
	for joint: String in ["shoulder", "elbow", "wrist"]:
		result[joint] = offset * (arm[joint] as Vector3)
	result["requested_shoulder"] = offset * (arm.get("requested_shoulder", arm.shoulder) as Vector3)
	result["raw_sword"] = pivot
	result["exact_sample"] = bool(arm.get("exact_sample", false)) and source.is_equal_approx(pivot)
	return result


func _compose_reference_arm(pivot_before_handoff: Transform3D) -> void:
	if _reference_arm_target.is_empty(): return
	# Walking, look sway, equip and recoil are applied to the same evaluated
	# pose. Only then blend from actual contact/transition joints, as for sword.
	_reference_arm_target = _reference_arm_for_pivot(_reference_arm_target, pivot_before_handoff)
	if combat_state == CombatState.RECOVERY and _sword_clash_recovering:
		var elapsed := state_time / lerpf(0.47, 0.68, clampf(attack_charge, 0.0, 1.0))
		_reference_arm_target = _mix_reference_arms(_reference_arm_clash_from, _reference_arm_target, MOTION.smooth_phase(elapsed))
	elif _reference_pose_handoff_active:
		_reference_arm_target = _mix_reference_arms(_reference_arm_handoff_from, _reference_arm_target, MOTION.smooth_phase(_reference_pose_handoff_elapsed / 0.10))


func toggle_torch() -> bool:
	set_torch_enabled(not torch_enabled)
	return torch_enabled


func set_torch_enabled(enabled: bool) -> void:
	_suppress_automatic_torch_hand = false
	torch_enabled = enabled
	if torch:
		torch.visible = enabled
	if torch_fill:
		torch_fill.visible = enabled
	if torch_flame:
		torch_flame.visible = enabled
	if hud:
		hud.update_torch(enabled)


func _update_torch(delta: float) -> void:
	if is_inside_tree() and get_tree().paused:
		return
	if torch_flame != null and camera != null:
		var lateral := camera.global_basis.x
		lateral.y = 0.0
		lateral = lateral.normalized()
		TORCH_FIRE.update_flow(torch_flame, lateral * velocity.dot(lateral), delta)
	if not torch_enabled or torch == null or torch_fill == null or torch_flame == null:
		return
	_torch_time += delta
	var flicker := sin(_torch_time * 17.0) * 0.24 + sin(_torch_time * 31.0) * 0.12
	torch.light_energy = float(torch.get_meta("base_energy", 4.9)) * (1.0 + flicker / 4.9)
	torch_fill.light_energy = float(torch_fill.get_meta("base_energy", 2.4)) * (1.0 + flicker * 0.55 / 2.4)
	# The flipbook shader animates internally; keep the flames anchored to the cloth.


func _add_character_arm(parent: Node3D, grip: Vector3, side: int) -> Node3D:
	var arm := PLAYER_ARM_VISUAL.new()
	arm.name = "CharacterArm"
	parent.add_child(arm)
	arm.set_meta("torch_source", parent == torch_pivot)
	arm.setup(side)
	arm.set_meta("grip_local", grip)
	arm.set_meta("hand_side", side)
	_position_character_hand(arm, grip, side)
	arm.set_grip(0.92)
	return arm


## An opt-in art review mode, owned by this player instance only. Gameplay
## contacts and the authored sword/shield adapters remain exactly the same.
func set_hands_greybox_enabled(enabled: bool) -> bool:
	return set_hands_visual_profile("greybox" if enabled else ("original" if hands_greybox_enabled else hands_visual_profile))


func set_hands_detailed_enabled(enabled: bool) -> bool:
	return set_hands_visual_profile("detailed" if enabled else ("original" if hands_detailed_enabled else hands_visual_profile))


func set_hands_visual_profile(profile: String) -> bool:
	if profile not in ["original", "greybox", "detailed"]:
		return false
	if finger_joint_review_active and profile != "detailed":
		end_finger_joint_review(false)
	if profile == hands_visual_profile:
		return true
	var generic_arms: Array[Node3D] = [_legacy_weapon_arm, torch_arm, left_support_arm, right_relaxed_arm]
	for arm: Node3D in generic_arms:
		if not is_instance_valid(arm):
			return false
	var changed: Array[Node3D] = []
	for arm: Node3D in generic_arms:
		if not bool(arm.call("set_visual_profile", profile)):
			for previous: Node3D in changed:
				previous.call("set_visual_profile", hands_visual_profile)
			return false
		changed.append(arm)
	if is_instance_valid(chest_hands) and not bool(chest_hands.call("set_visual_profile", profile)):
		for previous: Node3D in changed:
			previous.call("set_visual_profile", hands_visual_profile)
		return false
	hands_visual_profile = profile
	hands_greybox_enabled = profile == "greybox"
	hands_detailed_enabled = profile == "detailed"
	_update_character_arms()
	return true


func get_hands_greybox_snapshot() -> Dictionary:
	return _get_hands_profile_snapshot("greybox")


func get_hands_detailed_snapshot() -> Dictionary:
	return _get_hands_profile_snapshot("detailed")


func _get_hands_profile_snapshot(profile: String) -> Dictionary:
	var generic_count := 0
	var enabled_count := 0
	var chest_count := 0
	for arm: Node3D in [_legacy_weapon_arm, torch_arm, left_support_arm, right_relaxed_arm]:
		if is_instance_valid(arm):
			generic_count += 1
			if str(arm.get("visual_profile")) == profile:
				enabled_count += 1
	if is_instance_valid(chest_hands):
		for arm: Node3D in chest_hands.get("_arms").values():
			if str(arm.get("visual_profile")) == profile:
				chest_count += 1
	var result := {"enabled": hands_visual_profile == profile, "profile": hands_visual_profile, "generic_arm_count": generic_count, "sources_available": ResourceLoader.exists("res://assets/3d/player/hands_%s/left_hand_%s.glb" % [profile, profile]) and ResourceLoader.exists("res://assets/3d/player/hands_%s/right_hand_%s.glb" % [profile, profile])}
	if profile != "greybox":
		result.sources_available = ResourceLoader.exists("res://assets/3d/player/fp_arms/left.scn") and ResourceLoader.exists("res://assets/3d/player/fp_arms/right.scn")
	result[profile + "_arm_count"] = enabled_count
	result["chest_" + profile + "_count"] = chest_count
	return result


## Review the real free-hand rigs. The room owns pausing/input; this player
## owns only a temporary visual pose and restores its previous profile.
func begin_finger_joint_review() -> bool:
	if finger_joint_review_active:
		return true
	if _equipped_weapon_type() != "unarmed" or _left_hand_role() != "free" or chest_equipment_stowed or camping:
		return false
	_finger_joint_review_profile = hands_visual_profile
	if not set_hands_visual_profile("detailed"):
		return false
	for arm: Node3D in [left_support_arm, right_relaxed_arm]:
		if not bool(arm.call("get_joint_snapshot").get("ready", false)):
			set_hands_visual_profile(_finger_joint_review_profile)
			return false
	_finger_joint_review_values.clear()
	_finger_joint_review_view = "dorsal"
	for side in [-1, 1]:
		_finger_joint_review_values[side] = {}
		for digit: String in SWORD_SHIELD_ARM.DIGITS:
			_finger_joint_review_values[side][digit] = Vector3.ZERO
		var arm := left_support_arm if side < 0 else right_relaxed_arm
		arm.call("reset_pose")
	finger_joint_review_active = true
	_update_character_arms()
	return true


func end_finger_joint_review(restore_profile := true) -> void:
	if not finger_joint_review_active:
		return
	for arm: Node3D in [left_support_arm, right_relaxed_arm]:
		if is_instance_valid(arm):
			arm.call("reset_pose")
	finger_joint_review_active = false
	_finger_joint_review_values.clear()
	var previous_profile := _finger_joint_review_profile
	_finger_joint_review_profile = "original"
	_finger_joint_review_view = "dorsal"
	if restore_profile:
		set_hands_visual_profile(previous_profile)
	_update_character_arms()


func set_review_joint_flexion(digit: String, joint: int, amount: float, side := 0) -> bool:
	if not finger_joint_review_active or not SWORD_SHIELD_ARM.DIGITS.has(digit) or joint < 0 or joint > 2 or side not in [-1, 0, 1] or not is_finite(amount):
		return false
	for hand_side in [-1, 1]:
		if side != 0 and hand_side != side:
			continue
		var values: Vector3 = _finger_joint_review_values[hand_side][digit]
		values[joint] = clampf(amount, 0.0, 1.0)
		_finger_joint_review_values[hand_side][digit] = values
		var arm := left_support_arm if hand_side < 0 else right_relaxed_arm
		arm.call("set_joint_flexion", digit, joint, values[joint])
	return true


func set_review_digit_flexion(digit: String, amounts: Vector3, side := 0) -> bool:
	if not finger_joint_review_active or not SWORD_SHIELD_ARM.DIGITS.has(digit) or side not in [-1, 0, 1] or not amounts.is_finite():
		return false
	for joint in 3:
		set_review_joint_flexion(digit, joint, amounts[joint], side)
	return true


func get_finger_joint_review_snapshot() -> Dictionary:
	var hands := {}
	for side in [-1, 1]:
		var arm := left_support_arm if side < 0 else right_relaxed_arm
		if is_instance_valid(arm):
			hands[side] = arm.call("get_joint_snapshot")
	return {"active": finger_joint_review_active, "values": _finger_joint_review_values.duplicate(true), "hands": hands, "previous_profile": _finger_joint_review_profile, "profile": hands_visual_profile, "view": _finger_joint_review_view}


func set_review_hand_view(view: String) -> bool:
	if not finger_joint_review_active or view not in ["dorsal", "palm", "wrist_side"]:
		return false
	_finger_joint_review_view = view
	_update_character_arms()
	return true


func _update_finger_joint_review_pose() -> void:
	for side in [-1, 1]:
		var arm := left_support_arm if side < 0 else right_relaxed_arm
		var position_local := Vector3(-0.27 if side < 0 else 0.025, 0.035, -0.43)
		var local_basis := Basis.from_euler(Vector3(1.35, -side * 0.25, side * 0.10))
		if _finger_joint_review_view == "palm":
			local_basis *= Basis(Vector3.FORWARD, PI)
		elif _finger_joint_review_view == "wrist_side":
			local_basis *= Basis(Vector3.FORWARD, side * PI * 0.5)
		var orientation := camera.global_basis * local_basis
		_place_hand_contact(arm, camera.to_global(position_local), orientation, "review_left" if side < 0 else "review_right")
		var shoulder := camera.to_global(Vector3(side * 0.29, -0.34, 0.10))
		var elbow := MOTION.elbow(shoulder, arm.global_position, camera.global_basis * Vector3(side * 0.65, -0.85, 0.14))
		arm.call("fit_arm", shoulder, elbow)
		for digit: String in SWORD_SHIELD_ARM.DIGITS:
			arm.call("set_digit_flexion", digit, _finger_joint_review_values[side][digit])


func _add_sword_shield_arm(parent: Node3D, side: int) -> Node3D:
	var arm := preload("res://scripts/supplied_fp_arm.gd").new()
	arm.name = "SwordShieldArm"
	parent.add_child(arm)
	arm.setup(side)
	arm.set_meta("hand_side", side)
	return arm


func _prepare_sword_shield_materials(node: Node) -> void:
	if node is MeshInstance3D:
		SWORD_SHIELD_ARM.prepare_materials(node as MeshInstance3D)
		if str(node.name).begins_with("Grip") and (node as MeshInstance3D).get_active_material(0).resource_name != "FP_SwordLeather":
			var grip_leather := (node as MeshInstance3D).get_active_material(0).duplicate() as StandardMaterial3D
			grip_leather.albedo_color = Color(0.28, 0.25, 0.22)
			grip_leather.roughness = 0.85
			(node as MeshInstance3D).material_override = grip_leather
	for child in node.get_children(): _prepare_sword_shield_materials(child)


func _position_character_hand(arm: Node3D, grip: Vector3, side: int) -> void:
	# The same GLB hand is wrist-centred, fingers forward and palm below.
	# Roll its palm toward the shaft, then curl the fingers around that shaft.
	arm.rotation = Vector3(0.0, float(side) * deg_to_rad(135.0) if arm.get_meta("continuous_skin", false) else -float(side) * deg_to_rad(35.0), float(side) * PI * 0.5 if arm.get_meta("continuous_skin", false) else -float(side) * PI * 0.5)
	# Centre the closed palm on the shaft after turning the wrist; its back
	# remains readable instead of presenting an edge-on hand to the camera.
	var palm := SWORD_SHIELD_ARM.GRIP_CENTER if arm.get_meta("continuous_skin", false) else Vector3(0.0, 0.0, -0.086)
	arm.position = grip - arm.basis * palm


func _update_character_arms() -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	_hand_contacts.clear()
	_joint_landmarks.clear()
	var role := _left_hand_role()
	_refresh_hand_visibility()
	_update_draw_reach_material()
	if finger_joint_review_active:
		if _equipped_weapon_type() != "unarmed" or role != "free" or chest_equipment_stowed or camping:
			end_finger_joint_review()
		else:
			_update_finger_joint_review_pose()
		return
	if is_instance_valid(weapon_arm):
		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping and not _equipment_draw_reaching()
		var grip := Vector3(0.0, -0.108, 0.002) if weapon_arm == _sword_weapon_arm else Vector3(0.0, -0.17, 0.015)
		if _is_staff_equipped():
			grip = staff_visual_root.transform * Vector3(0.0, -0.28, 0.0)
		elif _is_flail_equipped():
			var anchors: Dictionary = FLAIL_VISUALS.flail_hand_anchors(flail_visual_root)
			grip = flail_visual_root.transform * (anchors.get("grip", Vector3(0.0, -0.10, 0.0)) as Vector3)
		weapon_arm.set_meta("grip_local", grip)
		if weapon_arm == _sword_weapon_arm:
			_fit_sword_grip(grip)
		else:
			_position_character_hand(weapon_arm, grip, 1)
			weapon_arm.call("set_grip", 0.95 if combat_state in [CombatState.ACTIVE, CombatState.WINDUP] else 0.87)
		if _is_bow_equipped():
			_update_bow_hands()
	if role == "shield" and is_instance_valid(shield_model):
		_fit_shield_grip()
	if role == "sword_support":
		_fit_sword_support()
	if role == "torch" and is_instance_valid(torch_arm):
		if torch_arm.visual_profile == "greybox":
			_position_character_hand(torch_arm, Vector3(0.0, 0.12, 0.0), -1)
		else:
			torch_arm.transform = TORCH_GRIP.ARM_TRANSFORM
		torch_arm.call("set_torch_grip")
		var target := torch_pivot.to_global(Vector3(0.0, 0.12, 0.0))
		var actual := torch_arm.to_global(Vector3(0.0, 0.0, -0.086) if torch_arm.visual_profile == "greybox" else TORCH_GRIP.CONTACT_CENTER)
		_hand_contacts["torch"] = {"target": target, "actual": actual, "error": actual.distance_to(target)}
	if role == "free" and is_instance_valid(left_support_arm):
		var lift := sin(clampf((0.22 - _cast_recoil) / 0.22, 0.0, 1.0) * PI) if _is_staff_equipped() and _cast_recoil > 0.0 else 0.0
		var contact := camera.to_global(Vector3(-0.43 + lift * 0.04, -0.29 + lift * 0.12 + sin(_motion_clock * 1.8) * 0.004, -0.65 - lift * 0.10))
		_place_hand_contact(left_support_arm, contact, camera.global_basis * Basis.from_euler(Vector3(0.75, 0.35, -0.26)), "free_left")
		left_support_arm.call("set_relaxed_pose", 0.72 if lift > 0.0 else 0.0)
	if is_instance_valid(right_relaxed_arm) and right_relaxed_arm.visible:
		_place_hand_contact(right_relaxed_arm, camera.to_global(Vector3(0.43, -0.60, -0.65)), camera.global_basis * Basis.from_euler(Vector3(0.75, -0.28, 0.25)), "free_right")
		right_relaxed_arm.call("set_relaxed_pose", 0.0)
		if _equipment_draw_reaching():
			var t := _sword_draw_elapsed
			# One uninterrupted diagonal reach toward the left hip; no raised hold.
			var reach := Vector3(0.39, -0.06, -0.38).lerp(Vector3(-0.35, -0.70, -0.38), MOTION.smooth_phase(t / 0.46))
			# Back of the hand faces the camera; wrist exits toward lower-right.
			# The supplied rest hand already includes natural PIP flexion.
			var wrist_axis := Vector3(0.94, -0.25, 0.22).normalized()
			var across := Vector3(0, 0.5, 1).cross(wrist_axis).normalized()
			var hand_frame := Basis(across, wrist_axis.cross(across).normalized(), wrist_axis)
			_place_hand_contact(right_relaxed_arm, camera.to_global(reach), camera.global_basis * hand_frame, "draw_reach")
			right_relaxed_arm.call("set_relaxed_pose", 1.0)
			for digit: String in ["index", "middle", "ring", "little", "thumb"]:
				right_relaxed_arm.call("set_digit_flexion", digit, _draw_reach_flexion(digit, t))
	for arm: Node3D in [weapon_arm, shield_arm, torch_arm, left_support_arm, right_relaxed_arm, sword_support_arm]:
		if not is_instance_valid(arm) or not arm.is_visible_in_tree():
			continue
		var side := float(arm.get_meta("hand_side", 1))
		var shoulder := camera.global_transform * Vector3(side * 0.29, -0.34, 0.10)
		var pole := camera.global_basis * Vector3(side * 0.65, -0.85, 0.14)
		if arm == weapon_arm and _is_bow_equipped():
			pole = camera.global_basis * Vector3(0.9, -0.24, 0.20)
		var elbow := MOTION.elbow(shoulder, arm.global_position, pole)
		if arm == _sword_weapon_arm or arm == sword_support_arm or (arm == shield_arm and role == "shield"):
			continue # These two grips already fitted their anatomical wrist chain.
		if arm == right_relaxed_arm and _equipment_draw_reaching():
			elbow = arm.global_position + arm.global_basis.z * 0.26
			shoulder = elbow + (shoulder - elbow).normalized() * 0.34
			_joint_landmarks["draw_reach"] = {"shoulder": shoulder, "elbow": elbow, "wrist": arm.global_position, "upper_length": shoulder.distance_to(elbow), "forearm_length": elbow.distance_to(arm.global_position)}
		arm.call("fit_arm", shoulder, elbow)
		if arm == torch_arm:
			var wrist_axis := arm.global_basis.z.normalized()
			var forearm_axis := (elbow - arm.global_position).normalized()
			_joint_landmarks["torch"] = {"shoulder": shoulder, "elbow": elbow, "wrist": arm.global_position, "wrist_angle_degrees": rad_to_deg(acos(clampf(wrist_axis.dot(forearm_axis), -1.0, 1.0)))}


func _fit_sword_support() -> void:
	var progress := _sword_support_progress()
	var blend := MOTION.smooth_phase(progress)
	var target := weapon_pivot.to_global(SWORD_SUPPORT_GRIP)
	var contact := camera.to_global(Vector3(-0.82, -0.30, -0.50)).lerp(target, blend)
	# Left thumb/index point toward the crossguard; the wrist exits leftward.
	var x := weapon_pivot.global_basis.y.normalized()
	var shoulder := camera.to_global(Vector3(-0.29, -0.34, 0.10))
	var hint := camera.to_global(Vector3(-0.55, -0.58, -0.05))
	var wrist := contact
	var orientation := Basis.IDENTITY
	var fitted := {}
	for iteration in 5:
		fitted = REFERENCE_ARM.solve(shoulder, hint, wrist)
		var z: Vector3 = fitted.elbow - wrist
		z = (z - x * z.dot(x)).normalized()
		if z.length_squared() < .5: z = -weapon_pivot.global_basis.x.normalized()
		orientation = Basis(x, z.cross(x).normalized(), z)
		wrist = contact - orientation * SWORD_SHIELD_ARM.GRIP_CENTER
	_place_hand_contact(sword_support_arm, contact, orientation, "sword_support")
	fitted = REFERENCE_ARM.solve(shoulder, hint, wrist)
	var elbow: Vector3 = fitted.elbow
	shoulder = fitted.shoulder
	sword_support_arm.call("set_sword_grip_surface", weapon_pivot.global_transform.affine_inverse() * Transform3D(orientation, target - orientation * SWORD_SHIELD_ARM.GRIP_CENTER))
	sword_support_arm.call("set_combat_grip", "sword", lerpf(0.12, 0.91, MOTION.smooth_phase((progress - 0.74) / 0.26)))
	sword_support_arm.call("fit_arm", shoulder, elbow)
	_hand_contacts["sword_support"]["grip_error"] = contact.distance_to(target)
	_joint_landmarks["sword_support"] = {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "upper_length": shoulder.distance_to(elbow), "forearm_length": elbow.distance_to(wrist)}


func _fit_sword_grip(grip_local: Vector3) -> void:
	# The normal supplied grip stays authored; the rear thrust alone uses the
	# diagonal palm contact and individual finger pose on the same handle.
	if weapon_arm.get_meta("imported_static_grip", false):
		weapon_arm.transform = Transform3D.IDENTITY
		var rear_grip := REAR_TAKEDOWN_MOTION.grip_blend(execution_elapsed) if is_execution_active() and _execution_profile == "rear_sword" else 0.0
		weapon_arm.call("set_thrust_grip", rear_grip)
		var target := weapon_pivot.to_global(grip_local + SWORD_LONG_GRIP.THRUST_CONTACT_OFFSET * rear_grip)
		var actual: Vector3 = weapon_arm.call("get_palm_anchor_world")
		_hand_contacts["sword"] = {"target": target, "actual": actual, "error": actual.distance_to(target), "scope": "posed palm anchor; skin contact audited separately"}
		# The authored glove stays on the sword. Sleeve segments follow the
		# shoulder, with the leather cuff rotating around the fixed wrist.
		var wrist_local := REAR_TAKEDOWN_MOTION.wrist_local(execution_elapsed) if is_execution_active() and _execution_profile == "rear_sword" else SWORD_LONG_GRIP.REST_WRIST
		var wrist := weapon_arm.to_global(wrist_local)
		if not _reference_arm_target.is_empty():
			var local_wrist := camera.to_local(wrist)
			var fitted := _reference_arm_target.duplicate(true)
			var exact := bool(fitted.get("exact_sample", false)) and (fitted.wrist as Vector3).distance_to(local_wrist) < 0.001
			var retained := bool(fitted.get("fitted_pose", false)) and (fitted.wrist as Vector3).distance_to(local_wrist) < 0.000001
			if not exact and not retained:
				fitted = REFERENCE_ARM.solve(fitted.shoulder, fitted.elbow, local_wrist, _reference_arm_previous_bend)
				_reference_arm_previous_bend = fitted.bend
			else:
				var axis := (local_wrist - (fitted.shoulder as Vector3)).normalized()
				var hint: Vector3 = fitted.elbow - fitted.shoulder
				var bend := hint - axis * hint.dot(axis)
				if bend.length_squared() > 0.00000001: _reference_arm_previous_bend = bend.normalized()
			weapon_arm.call("fit_arm", camera.to_global(fitted.shoulder), camera.to_global(fitted.elbow), true)
			_record_reference_arm(fitted.shoulder, fitted.elbow, local_wrist, exact, _reference_arm_target.get("requested_shoulder", _reference_arm_target.shoulder))
			return
		var shoulder := camera.to_global(SWORD_LONG_GRIP.SOURCE_READY * SWORD_LONG_GRIP.REST_SHOULDER)
		var offset := wrist - shoulder
		var reach := offset.length()
		var axis := offset / maxf(reach, 0.00001)
		var upper := SWORD_LONG_GRIP.REST_ELBOW.distance_to(SWORD_LONG_GRIP.REST_SHOULDER)
		var forearm := SWORD_LONG_GRIP.REST_WRIST.distance_to(SWORD_LONG_GRIP.REST_ELBOW)
		var elbow := shoulder + offset * (upper / (upper + forearm))
		if reach < upper + forearm and reach > absf(upper - forearm):
			var along := (upper * upper - forearm * forearm + reach * reach) / (2.0 * reach)
			var pole := camera.global_basis * Vector3(0.75, -0.72, 0.28)
			var bend := (pole - axis * pole.dot(axis)).normalized()
			elbow = shoulder + axis * along + bend * sqrt(maxf(0.0, upper * upper - along * along))
		weapon_arm.call("fit_arm", shoulder, elbow)
		_record_reference_arm(camera.to_local(shoulder), camera.to_local(elbow), camera.to_local(wrist), false, camera.to_local(shoulder))
		return
	var contact := weapon_pivot.to_global(grip_local)
	var phase := str(CombatState.keys()[combat_state]).to_lower()
	var effort := CHOREOGRAPHY.attack_weight(phase,state_time,attack_charge)
	var shoulder := camera.to_global(Vector3(0.29,-0.34,0.10))
	# Torso/shoulder lead, then elbow and wrist. The pole smoothly crosses the
	# chest for the reverse cut; it is not switched at the active boundary.
	var pole_local := Vector3(0.75,-0.72,0.28)
	if sword_attack_variant == "left_reverse": pole_local = pole_local.lerp(Vector3(0.35,-0.75,0.36),effort)
	if sword_attack_variant == "overhead": pole_local = pole_local.lerp(Vector3(0.85,0.10,0.35),effort)
	if sword_attack_variant == "right_diagonal" and phase == "recovery":
		var recovery_t := clampf(state_time / lerpf(0.47,0.68,attack_charge),0.0,1.0)
		var tuck := sin(PI * recovery_t)
		pole_local.x -= 0.17 * tuck * tuck
	var pole := camera.global_basis * pole_local
	# In anatomical right-hand wrist space the thumb/index lie on -X.
	# Keep that edge at the crossguard, with the little finger toward pommel.
	var x := -weapon_pivot.global_basis.y.normalized()
	var desired_roll := deg_to_rad(lerpf(-40.0,0.0,effort))
	var fitted := _sword_wrist_frame(contact,shoulder,pole,x,desired_roll)
	# Open the finger row toward the camera only as far as the actual fitted
	# forearm permits. Measure the completed wrist chain, not its projection
	# before the palm offset: that approximation overbent charged recoveries.
	if float(fitted.alignment) < 0.55 and absf(desired_roll) > 0.00001:
		var neutral := _sword_wrist_frame(contact,shoulder,pole,x,0.0)
		if float(neutral.alignment) > float(fitted.alignment):
			fitted = neutral
			if float(neutral.alignment) >= 0.55:
				var low := 0.0
				var high := absf(desired_roll)
				for step in 6:
					var amount := (low + high) * 0.5
					var candidate := _sword_wrist_frame(contact,shoulder,pole,x,signf(desired_roll) * amount)
					if float(candidate.alignment) >= 0.55:
						low = amount
						fitted = candidate
					else: high = amount
	_place_hand_contact(weapon_arm,contact,fitted.basis,"sword")
	var wrist := weapon_arm.global_position
	var joint: Vector3 = fitted.elbow
	weapon_arm.call("set_sword_grip_surface",weapon_pivot.global_transform.affine_inverse() * weapon_arm.global_transform)
	weapon_arm.call("set_combat_grip","sword",0.84 + effort * 0.14)
	weapon_arm.call("fit_arm",shoulder,joint)
	_joint_landmarks["sword"] = {"shoulder":shoulder,"elbow":joint,"wrist":wrist,"wrist_axis":weapon_arm.global_basis.z,"upper_length":shoulder.distance_to(joint),"forearm_length":joint.distance_to(wrist)}


func _record_reference_arm(shoulder: Vector3, elbow: Vector3, wrist: Vector3, exact: bool, requested_shoulder: Vector3) -> void:
	# Stowing shifts hidden equipment without advancing the motion clock. Keep
	# the last visible joints beside the carried pivots for cancellation/return.
	if not chest_equipment_stowed:
		var lengths_valid := absf(shoulder.distance_to(elbow) / REFERENCE_ARM.UPPER_LENGTH - 1.0) <= 0.01 and absf(elbow.distance_to(wrist) / REFERENCE_ARM.FOREARM_LENGTH - 1.0) <= 0.01
		_reference_arm_rendered = {"shoulder": shoulder, "elbow": elbow, "wrist": wrist, "raw_sword": weapon_pivot.transform, "exact_sample": exact, "requested_shoulder": requested_shoulder, "fitted_pose": lengths_valid}
	_joint_landmarks["sword"] = {"shoulder": camera.to_global(shoulder), "elbow": camera.to_global(elbow), "wrist": camera.to_global(wrist), "upper_length": shoulder.distance_to(elbow), "forearm_length": elbow.distance_to(wrist), "authored_arm_active": not _reference_arm_target.is_empty(), "exact_authored_sample": exact, "shoulder_adjustment_m": shoulder.distance_to(requested_shoulder)}


func _sword_wrist_frame(contact: Vector3, shoulder: Vector3, pole: Vector3, x: Vector3, roll: float) -> Dictionary:
	var wrist := contact
	var joint := CHOREOGRAPHY.elbow(shoulder,wrist,pole)
	var orientation := Basis.IDENTITY
	for iteration in 4:
		var back := joint - contact
		back -= x * back.dot(x)
		if back.length_squared() < 0.00001: back = weapon_pivot.global_basis.z
		var z := back.normalized().rotated(x,roll)
		orientation = Basis(x,z.cross(x).normalized(),z)
		wrist = contact - orientation * SWORD_SHIELD_ARM.GRIP_CENTER
		joint = CHOREOGRAPHY.elbow(shoulder,wrist,pole)
	return {"basis":orientation,"elbow":joint,"alignment":orientation.z.dot((joint - wrist).normalized())}


func _match_sword_carry_to_shield(target: Transform3D, phase: String, authored: bool) -> Transform3D:
	# Match the real left grip in camera space, reflecting X only. Blade/hand
	# remain one rigid asset, and authored combat takes over via its handoff.
	if authored and (phase != "ready" or REFERENCE_MOTION.has_track("walk")): return target
	var grip := shield_model.find_child("RearGrip", true, false) as Node3D
	if grip == null: return target
	var weight := 1.0 - CHOREOGRAPHY.smooth(_shield_raise_progress)
	if not authored: weight *= 1.0 - CHOREOGRAPHY.attack_weight(phase, state_time, attack_charge)
	var left := camera.to_local(grip.global_position)
	var right := Vector3(-left.x, left.y, left.z)
	var matched_origin := right - target.basis * SWORD_LONG_GRIP.GRIP_CENTER
	target.origin = target.origin.lerp(matched_origin, weight)
	return target


func _shield_corner_offset() -> Vector3:
	# Complete Mac clips already contain their final camera framing.
	if REFERENCE_MOTION.has_track("walk", "shield"): return Vector3.ZERO
	var phase := str(CombatState.keys()[combat_state]).to_lower()
	if REFERENCE_MOTION.is_available() and _equipped_weapon_type() == "melee" and phase != "ready":
		# The authored phase handoff already blends out of the carried pose.
		return Vector3.ZERO
	var attack := CHOREOGRAPHY.attack_weight(phase, state_time, attack_charge)
	return SHIELD_CORNER_OFFSET * (1.0 - CHOREOGRAPHY.smooth(_shield_raise_progress)) * (1.0 - attack)


func _fit_shield_grip() -> void:
	var grip := shield_model.find_child("RearGrip",true,false) as Node3D
	var top := shield_model.find_child("RearGripTop",true,false) as Node3D
	var bottom := shield_model.find_child("RearGripBottom",true,false) as Node3D
	var strap := shield_model.find_child("RearArmStrap",true,false) as Node3D
	if grip == null or top == null or bottom == null or strap == null: return
	# The anatomical left thumb/index are +X, toward the upper strap anchor.
	var x := (top.global_position - bottom.global_position).normalized()
	var under_strap := strap.global_position - shield_pivot.global_basis.z * 0.04
	var back := under_strap - grip.global_position
	back = (back - x * back.dot(x)).normalized()
	var orientation := Basis(x,back.cross(x).normalized(),back)
	_place_hand_contact(shield_arm,grip.global_position,orientation,"shield")
	shield_arm.call("set_shield_grip_surface",shield_model.global_transform.affine_inverse() * shield_arm.global_transform)
	var shoulder := camera.to_global(Vector3(-0.29,-0.34,0.10))
	var wrist := shield_arm.global_position
	# The enarme constrains the forearm in every pose, including lowered carry.
	var joint := wrist + (under_strap - wrist).normalized() * 0.34
	# The clavicle comes slightly forward/down as the arm raises into guard.
	# This preserves the rim/grip pose without overextending the upper sleeve.
	shoulder += camera.global_basis * Vector3(0, -0.025, -0.035) * CHOREOGRAPHY.smooth(_shield_raise_progress)
	shield_arm.call("set_combat_grip","shield",0.86 + _shield_raise_progress * 0.09 + (0.04 if _shield_impact > 0.0 else 0.0))
	shield_arm.call("fit_arm",shoulder,joint)
	_joint_landmarks["shield"] = {"shoulder":shoulder,"elbow":joint,"wrist":wrist,"wrist_axis":shield_arm.global_basis.z,"strap":under_strap,"upper_length":shoulder.distance_to(joint),"forearm_length":joint.distance_to(wrist)}



func _place_hand_contact(arm: Node3D, contact: Vector3, orientation: Basis, label: String) -> void:
	var palm := SWORD_SHIELD_ARM.GRIP_CENTER if arm.get_meta("continuous_skin", false) else Vector3(0.0, 0.0, -0.086)
	arm.global_transform = Transform3D(orientation, contact - orientation * palm)
	_hand_contacts[label] = {"target": contact, "actual": arm.global_transform * palm, "error": (arm.global_transform * palm).distance_to(contact)}


func _bow_string_anchor_for_draw(draw: float) -> Vector3:
	if not is_instance_valid(bow_visual_root):
		return Vector3.ZERO
	ARCHERY_VISUALS.set_bow_draw(bow_visual_root, draw)
	var anchors: Dictionary = ARCHERY_VISUALS.bow_hand_anchors(bow_visual_root)
	return anchors.string


func _update_bow_hands() -> void:
	if not is_instance_valid(bow_visual_root) or not is_instance_valid(left_support_arm):
		return
	var anchors: Dictionary = ARCHERY_VISUALS.bow_hand_anchors(bow_visual_root)
	var left_basis := bow_visual_root.global_basis * Basis.from_euler(Vector3(0.0, 0.35, PI * 0.5))
	_place_hand_contact(left_support_arm, bow_visual_root.to_global(anchors.grip), left_basis, "bow_grip")
	left_support_arm.call("set_grip", 0.91, 0.72)
	var right_anchor: Vector3 = anchors.string
	var release := 0.0
	if not bow_drawing and bow_cooldown > 0.0 and _bow_release_draw > 0.0:
		var elapsed := BOW_SHOT_COOLDOWN - bow_cooldown
		var follow := _bow_release_anchor + Vector3(0.09, 0.005, 0.065) * _bow_release_draw
		right_anchor = _bow_release_anchor.lerp(follow, MOTION.smooth_phase(elapsed / 0.12)) if elapsed < 0.12 else follow.lerp(right_anchor, MOTION.smooth_phase((elapsed - 0.12) / 0.43))
		release = sin(clampf(elapsed / BOW_SHOT_COOLDOWN, 0.0, 1.0) * PI)
	var right_basis := bow_visual_root.global_basis * Basis.from_euler(Vector3(0.12, -0.28, -PI * 0.5))
	_place_hand_contact(weapon_arm, bow_visual_root.to_global(right_anchor), right_basis, "bow_string" if bow_drawing or bow_cooldown <= 0.0 else "bow_release")
	weapon_arm.call("set_string_draw", 0.92 if bow_drawing else 0.75, release)


func _has_shield_equipped() -> bool:
	# Combat uses the held shield; a packed shield stays assigned in inventory.
	return not _shield_stowed and _shield_item_usable()


func _shield_item_usable() -> bool:
	return inventory_model != null and str(inventory_model.equipment.get("offhand", "")) == "round_shield" and float(inventory_model.get_equipment_durability("offhand").get("current", 0.0)) > 0.0


func _left_hand_role() -> String:
	if not safe_zone_mode and _is_bow_equipped():
		return "bow"
	if not safe_zone_mode and _shield_visible_in_hand() and not _is_flail_equipped():
		return "shield"
	if _sword_support_requested():
		return "sword_support"
	if _suppress_automatic_torch_hand:
		return "free"
	var has_torch := inventory_model == null or str(inventory_model.equipment.get("utility", "")) == "field_torch"
	if has_torch and (torch_enabled or _torch_draw_elapsed > 0.0) and (safe_zone_mode or not _is_flail_equipped()):
		return "torch"
	return "free"


func get_first_person_motion_snapshot() -> Dictionary:
	var arms := 0
	for arm: Node3D in [weapon_arm, shield_arm, torch_arm, left_support_arm, right_relaxed_arm, sword_support_arm]:
		if is_instance_valid(arm) and arm.is_visible_in_tree():
			arms += 1
	return {"weapon": _equipped_weapon_type(), "phase": str(CombatState.keys()[combat_state]).to_lower(), "phase_time": state_time, "sword_attack_variant": sword_attack_variant, "sword_attack_mode": sword_attack_mode, "sword_next_attack_variant": get_next_sword_attack_variant(), "motion_time": _motion_clock, "grounded": _movement_grounded, "movement_ground_known": _movement_ground_known, "movement_phase": _movement_phase, "movement_phase_time": _movement_phase_time, "landing_count": _movement_landing_count, "landing_strength": _movement_landing_strength, "reference_motion_available": REFERENCE_MOTION.is_available(), "shield_raise_progress": _shield_raise_progress, "shield_impact_remaining": _shield_impact, "joint_landmarks": _joint_landmarks.duplicate(true), "equip_progress": _motion_equip_elapsed / MOTION.EQUIP_DURATION, "sword_draw_progress": _sword_draw_elapsed / SWORD_DRAW_DURATION, "sword_draw_active": _equipment_draw_active(), "shield_stowed": _shield_stowed, "shield_stow_progress": minf(1.0, _shield_stow_elapsed / SHIELD_STOW_DURATION), "sword_support_progress": _sword_support_progress(), "sword_draw_reaching": _equipment_draw_reaching(), "flail_phase": flail_state, "draw_ratio": get_bow_draw_ratio(), "visible_arm_count": arms, "left_hand_role": _left_hand_role(), "hand_contacts": _hand_contacts.duplicate(true), "weapon_transform": weapon_pivot.transform if is_instance_valid(weapon_pivot) else Transform3D.IDENTITY, "shield_visible": is_instance_valid(shield_pivot) and shield_pivot.is_visible_in_tree(), "torch_enabled": torch_enabled, "torch_draw_progress": _torch_draw_elapsed / TORCH_GRIP.DRAW_DURATION}


func _add_fire_sparks(parent: Node3D) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "EmberSparks"
	sparks.amount = 14
	sparks.lifetime = 0.85
	sparks.preprocess = 0.85
	sparks.randomness = 0.48
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.055
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.gravity = Vector3(0.0, 0.42, 0.0)
	sparks.initial_velocity_min = 0.22
	sparks.initial_velocity_max = 0.65
	sparks.scale_amount_min = 0.18
	sparks.scale_amount_max = 0.58
	sparks.position.y = 0.04

	var ember_quad := QuadMesh.new()
	ember_quad.size = Vector2(0.009, 0.026)
	var ember_material := StandardMaterial3D.new()
	ember_material.albedo_color = Color(1.0, 0.28, 0.025, 0.92)
	ember_material.emission_enabled = true
	ember_material.emission = Color(1.0, 0.09, 0.008)
	ember_material.emission_energy_multiplier = 4.5
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_material.vertex_color_use_as_albedo = true
	ember_quad.material = ember_material
	sparks.mesh = ember_quad
	parent.add_child(sparks)


func _apply_material_to_prefix(root: Node, prefixes: Array, material: Material) -> void:
	if root is MeshInstance3D:
		for prefix in prefixes:
			if String(root.name).begins_with(String(prefix)):
				(root as MeshInstance3D).material_override = material
				break
	for child in root.get_children():
		_apply_material_to_prefix(child, prefixes, material)


func _set_meshes_visible_by_name(root: Node, mesh_names: Array[String], visible_value: bool) -> void:
	if root is GeometryInstance3D and mesh_names.has(String(root.name)):
		(root as GeometryInstance3D).visible = visible_value
	for child in root.get_children():
		_set_meshes_visible_by_name(child, mesh_names, visible_value)


func _box_mesh(size_value: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_value
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	return mesh_instance


func _sphere_mesh(radius_value: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius_value
	sphere.height = radius_value * 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	mesh_instance.mesh = sphere
	mesh_instance.material_override = material
	return mesh_instance


func _shield_disc(radius_value: float, depth: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius_value
	cylinder.bottom_radius = radius_value
	cylinder.height = depth
	cylinder.radial_segments = 10
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = material
	mesh_instance.rotation.x = deg_to_rad(90)
	return mesh_instance


func _cylinder_mesh(top_radius: float, bottom_radius: float, height_value: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height_value
	cylinder.radial_segments = 8
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = material
	return mesh_instance


func _material(color_value: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material


func _textured_material(
	color_value: Color,
	texture_value: Texture2D,
	roughness_value: float,
	metallic_value: float,
	texture_scale: float
) -> StandardMaterial3D:
	var material := _material(color_value, roughness_value, metallic_value)
	material.albedo_texture = texture_value
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 32.0
	material.uv1_scale = Vector3.ONE * texture_scale
	return material


func get_melee_damage(charge: float = 0.0) -> float:
	if inventory_model == null:
		return lerpf(27.0, 53.0, clampf(charge, 0.0, 1.0)) * get_body_attack_multiplier()
	var stats := inventory_model.equipped_smithing_stats()
	return lerpf(float(stats.light_damage), float(stats.heavy_damage), clampf(charge, 0.0, 1.0)) * get_body_attack_multiplier()


func get_melee_stamina_cost(charge: float = 0.0) -> float:
	var scale := 1.0 if inventory_model == null else float(inventory_model.equipped_smithing_stats().stamina_scale)
	return lerpf(18.0, 30.0, clampf(charge, 0.0, 1.0)) * scale * get_body_attack_stamina_multiplier()


func apply_smithing_on_hit() -> void:
	if inventory_model == null:
		return
	var heal := float(inventory_model.equipped_smithing_stats().life_on_hit)
	if heal > 0.0:
		restore_health(heal)


func _sync_smithing_weapon_visual() -> void:
	if not is_instance_valid(sword_visual_root) or inventory_model == null:
		return
	var id := str(inventory_model.equipment.get("weapon", ""))
	var instance := inventory_model.get_equipment_instance("weapon")
	var mods: Dictionary = instance.get("smithing", {})
	var signature := id + JSON.stringify(mods)
	if signature == _smithing_visual_signature:
		return
	_smithing_visual_signature = signature
	var previous := sword_visual_root.get_node_or_null("SmithingDetails")
	if previous != null:
		sword_visual_root.remove_child(previous)
		previous.free()
	var crafted := id in ["forged_longsword", "forged_arming_sword"]
	var grip := str(mods.get("grip", ""))
	var edge := str(mods.get("reinforcement", ""))
	for candidate in sword_visual_root.find_children("*", "MeshInstance3D", true, false):
		var part := candidate as MeshInstance3D
		if not part.has_meta("smithing_base_material"):
			part.set_meta("smithing_base_material", part.material_override)
		part.material_override = part.get_meta("smithing_base_material") as Material
		if str(part.name).begins_with("Grip") and not grip.is_empty():
			part.material_override = _material(Color(0.18, 0.075, 0.035) if grip == "leather_grip" else Color(0.11, 0.22, 0.20), 0.72, 0.04)
		elif part == sword_blade and crafted:
			part.material_override = _material(Color(0.62, 0.68, 0.72), 0.27, 0.82)
		elif str(part.name).begins_with("Fuller") and not edge.is_empty():
			part.material_override = _material(Color(0.91, 0.90, 0.80) if edge == "silver_edge" else Color(0.28, 0.34, 0.40), 0.23, 0.85)
	var details := Node3D.new()
	details.name = "SmithingDetails"
	sword_visual_root.add_child(details)
	details.set_meta("item_id", id)
	details.set_meta("grip", grip)
	details.set_meta("reinforcement", edge)
	var socket_count := int(mods.get("sockets", 0))
	var runes: Array = mods.get("runes", [])
	for index in socket_count:
		var rim := _cylinder_mesh(0.018, 0.018, 0.007, _material(Color(0.46, 0.39, 0.24), 0.35, 0.8))
		rim.name = "RuneSocket%d" % index
		rim.position = Vector3(0, 0.23 + float(index) * 0.15, 0.007)
		rim.rotation.x = PI * 0.5
		rim.layers = sword_blade.layers
		details.add_child(rim)
		var rune_id := str(runes[index]) if index < runes.size() else ""
		var color := Color(0.035, 0.025, 0.02) if rune_id.is_empty() else Color(1.0, 0.25, 0.045) if rune_id == "ember_rune" else Color(0.05, 0.85, 0.69)
		var material := _material(color, 0.25, 0.25)
		material.emission_enabled = not rune_id.is_empty()
		material.emission = color
		material.emission_energy_multiplier = 1.3
		var gem := _sphere_mesh(0.013, material)
		gem.name = "RuneGem%d" % index
		gem.position = Vector3(0, rim.position.y, 0.012)
		gem.scale = Vector3(1.0, 1.0, 0.45)
		gem.layers = sword_blade.layers
		details.add_child(gem)
	if grip == "balanced_grip":
		var counterweight := _sphere_mesh(0.033, _material(Color(0.57, 0.65, 0.65), 0.27, 0.8))
		counterweight.name = "BalancedPommelInlay"
		counterweight.position = Vector3(0, -0.339, 0.014)
		counterweight.scale.z = 0.3
		counterweight.layers = sword_blade.layers
		details.add_child(counterweight)


func _update_draw_reach_material() -> void:
	# The flexible reaching hand wears the same brown full glove as the rigid
	# sword grip. Instance overrides are restored before free-hand/other use.
	if _equipment_draw_reaching() and is_instance_valid(right_relaxed_arm):
		if _draw_reach_material == null:
			_draw_reach_material = StandardMaterial3D.new()
			_draw_reach_material.resource_name = "DrawOnlyBrownGlove"
			_draw_reach_material.albedo_color = Color(0.15, 0.092, 0.065)
			_draw_reach_material.roughness = 0.90
		for part: MeshInstance3D in right_relaxed_arm.hand_meshes:
			if not _draw_reach_overrides.has(part): _draw_reach_overrides[part] = part.material_override
			part.material_override = _draw_reach_material
	else:
		for part: MeshInstance3D in _draw_reach_overrides:
			if is_instance_valid(part): part.material_override = _draw_reach_overrides[part]
		_draw_reach_overrides.clear()


func _refresh_hand_visibility() -> void:
	if is_instance_valid(_sword_weapon_arm) and is_instance_valid(_legacy_weapon_arm):
		weapon_arm = _sword_weapon_arm if _equipped_weapon_type() == "melee" else _legacy_weapon_arm
		_legacy_weapon_arm.visible = false
		_sword_weapon_arm.visible = false
	var role := _left_hand_role()
	if is_instance_valid(left_support_arm):
		var using_free_hand := role == "free" and _is_staff_equipped() and _cast_recoil > 0.0
		left_support_arm.visible = (role == "bow" or using_free_hand) and not chest_equipment_stowed and not camping
	if is_instance_valid(right_relaxed_arm):
		right_relaxed_arm.visible = (safe_zone_mode or _equipped_weapon_type() == "unarmed" or _equipment_draw_reaching()) and not chest_equipment_stowed and not camping
	if is_instance_valid(shield_arm):
		shield_arm.visible = role == "shield" and not chest_equipment_stowed and not camping
	if is_instance_valid(sword_support_arm):
		sword_support_arm.visible = role == "sword_support" and not chest_equipment_stowed and not camping and not _equipment_draw_reaching()
	if is_instance_valid(torch_arm):
		torch_arm.visible = role == "torch" and not chest_equipment_stowed and not camping
	if is_instance_valid(weapon_arm):
		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping and not _equipment_draw_reaching()


func is_bandage_motion_active() -> bool:
	return (is_instance_valid(bandage_hands) and bool(bandage_hands.active)) or (is_instance_valid(splint_hands) and bool(splint_hands.active)) or (is_instance_valid(potion_hands) and bool(potion_hands.active)) or (is_instance_valid(jerky_hands) and bool(jerky_hands.active))


func cancel_bandage_motion() -> void:
	if not is_bandage_motion_active(): return
	bandage_hands.clear()
	splint_hands.clear()
	potion_hands.clear()
	jerky_hands.clear()
	_refresh_carried_visibility()


func advance_bandage_motion(delta: float) -> void:
	if not is_bandage_motion_active(): return
	if combat_state != CombatState.READY or blocking or bow_drawing or _is_flail_busy() or camping or is_timed_interacting() or current_trap != null:
		cancel_bandage_motion()
		return
	if is_inside_tree() and get_tree().paused: return
	_active_treatment_hands().advance(delta)
	if not is_bandage_motion_active():
		_refresh_carried_visibility()


func _active_treatment_hands() -> Node3D:
	if is_instance_valid(jerky_hands) and jerky_hands.active: return jerky_hands
	if is_instance_valid(potion_hands) and potion_hands.active: return potion_hands
	return splint_hands if is_instance_valid(splint_hands) and splint_hands.active else bandage_hands


func _play_consumable_motion(item_id: String, treatment_part: String) -> void:
	if item_id == "beef_jerky" and is_instance_valid(jerky_hands):
		cancel_bandage_motion()
		jerky_hands.begin([weapon_pivot, shield_pivot, torch_pivot, support_arm_root])
		viewmodel_renderer._assign_equipment_layer(jerky_hands)
		_refresh_carried_visibility()
	if item_id == "healing_draught" and is_instance_valid(potion_hands):
		cancel_bandage_motion()
		potion_hands.begin([weapon_pivot, shield_pivot, torch_pivot, support_arm_root])
		viewmodel_renderer._assign_equipment_layer(potion_hands)
		_refresh_carried_visibility()
	if item_id == "linen_bandage" and treatment_part == "left_arm" and is_instance_valid(bandage_hands):
		cancel_bandage_motion()
		bandage_hands.begin([weapon_pivot, shield_pivot, torch_pivot, support_arm_root])
		viewmodel_renderer._assign_equipment_layer(bandage_hands)
		_refresh_carried_visibility()
	if item_id == "splint" and treatment_part == "left_arm" and is_instance_valid(splint_hands):
		cancel_bandage_motion()
		splint_hands.begin([weapon_pivot, shield_pivot, torch_pivot, support_arm_root])
		viewmodel_renderer._assign_equipment_layer(splint_hands)
		_refresh_carried_visibility()


func is_item_use_active() -> bool:
	return not _item_use.is_empty()


func get_item_use_snapshot() -> Dictionary:
	return _item_use.duplicate(true)


func begin_item_use(item_id: String, inventory: ExpeditionInventory, from_inventory := false) -> Dictionary:
	if is_item_use_active() or is_bandage_motion_active() or camping or (is_paralyzed() and not _item_treats_paralysis(item_id)) or combat_state != CombatState.READY or is_timed_interacting() or current_trap != null or blocking or bow_drawing or _is_flail_busy():
		return _consumable_failure("busy", "현재 행동을 마친 뒤 사용하세요.")
	if is_inside_tree() and get_tree().paused and not from_inventory:
		return _consumable_failure("paused", "일시정지 중에는 사용할 수 없습니다.")
	var eligible := use_consumable(item_id, inventory, true)
	if not bool(eligible.get("accepted", false)): return eligible
	var effect := str(ExpeditionInventory.get_item_definition(item_id).get("effect", ""))
	var duration := 3.0
	match effect:
		"bandage": duration = preload("res://scripts/bandage_use_visuals.gd").DURATION
		"surgery": duration = 12.0
		"restore_hunger": duration = 4.0
		"restore_thirst": duration = 3.0
		"learn_spell": duration = 5.0
	if item_id == "beef_jerky": duration = preload("res://scripts/jerky_eat_visuals.gd").EAT_DURATION
	if item_id == "healing_draught": duration = preload("res://scripts/potion_drink_visuals.gd").DRINK_DURATION
	if item_id == "splint": duration = preload("res://scripts/splint_use_visuals.gd").SPLINT_DURATION
	var part := get_selected_treatment_part()
	_play_consumable_motion(item_id, part)
	_item_use_inventory = inventory
	_item_use = {"item_id": item_id, "name": ExpeditionInventory.get_item_name(item_id), "duration": duration, "elapsed": 0.0, "remaining": duration, "part": part}
	_refresh_item_use_hud()
	return {"accepted": true, "started": true, "duration": duration, "message": ExpeditionInventory.get_item_name(item_id) + " 사용 중 · F 취소"}


func advance_item_use(delta: float) -> void:
	if not is_item_use_active(): return
	if combat_state != CombatState.READY or BODY_HEALTH.is_dead(_body_state()) or (is_paralyzed() and not _item_treats_paralysis(str(_item_use.item_id))) or camping or blocking or bow_drawing or _is_flail_busy() or is_timed_interacting() or current_trap != null:
		cancel_item_use()
		return
	if delta <= 0 or (is_inside_tree() and get_tree().paused): return
	_item_use.elapsed = minf(float(_item_use.duration), float(_item_use.elapsed) + delta)
	_item_use.remaining = maxf(0, float(_item_use.duration) - float(_item_use.elapsed))
	_refresh_item_use_hud()
	if float(_item_use.remaining) > 0: return
	var completed := _item_use.duplicate()
	var source := _item_use_inventory
	_item_use.clear()
	_item_use_inventory = null
	cancel_bandage_motion()
	last_item_use_result = use_consumable(str(completed.item_id), source, false, false, str(completed.part))
	_refresh_item_use_hud()
	if is_instance_valid(hud): hud.show_event(str(last_item_use_result.get("message", "사용을 완료할 수 없습니다.")), 1.2)
	item_use_finished.emit(last_item_use_result)


func cancel_item_use() -> bool:
	if not is_item_use_active(): return false
	_item_use.clear()
	_item_use_inventory = null
	cancel_bandage_motion()
	last_item_use_result = {"accepted": false, "cancelled": true, "message": "아이템 사용을 취소했습니다"}
	_refresh_item_use_hud()
	return true


func handle_torch_action() -> bool:
	# One shared F dispatch prevents cancellation and torch toggling in one frame.
	if cancel_item_use():
		if is_instance_valid(hud): hud.show_event("아이템 사용 취소", 0.8)
		return torch_enabled
	return toggle_torch()


func _refresh_item_use_hud() -> void:
	if is_instance_valid(hud): hud.update_item_use(get_item_use_snapshot())


func _item_treats_paralysis(item_id: String) -> bool:
	var definition := ExpeditionInventory.get_item_definition(item_id)
	return definition.get("effect", "") == "cure_condition" and definition.get("condition", "") == "paralysis"
