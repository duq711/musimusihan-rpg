extends CharacterBody3D
class_name DungeonPlayer

signal died
signal attack_landed(damage: float, headshot: bool)
signal spell_cast(spell_id: String, stamina_spent: float)
signal arrow_fired(draw_ratio: float, stamina_spent: float)
signal flail_thrown(charge: float)
signal timed_interaction_started(owner: Node, duration: float)
signal timed_interaction_finished(owner: Node)
signal timed_interaction_cancelled(owner: Node)

const PLAYER_LAYER := 1
const WORLD_LAYER := 2
const ENEMY_LAYER := 4
const INTERACT_LAYER := 16

const SWORD_SCENE := preload("res://assets/3d/player/sword_shield/longsword.glb")
const SWORD_SHIELD_ARM := preload("res://scripts/sword_shield_arm_visual.gd")
const SHIELD_SCENE := preload("res://assets/3d/player/sword_shield/round_shield.glb")
const TORCH_SCENE := preload("res://assets/3d/dark_fantasy/iron_cage_torch.glb")
const TORCH_FLAME_TEXTURE := preload("res://assets/ai/vfx/torch_flame.png")
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

const SWORD_CLASH_MARGIN := 0.02

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.2
const JUMP_VELOCITY := 5.2
const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0
const ATTACK_HIT_TIME := 0.055
const SWORD_CLASH_GRACE_END := 0.11

enum CombatState { READY, WINDUP, ACTIVE, RECOVERY, GUARD_BREAK, DEAD }

var health := MAX_HEALTH
var stamina := MAX_STAMINA
var combat_state := CombatState.READY
var state_time := 0.0
var attack_charge := 0.0
var attack_release_requested := false
var attack_hit_ids: Dictionary = {}
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
var _motion_clock := 0.0
var _motion_equip_elapsed := MOTION.EQUIP_DURATION
var _motion_initialized := false
var _motion_flail_phase := "ready"
var _motion_flail_elapsed := 0.0
var _motion_flail_transition_from := Transform3D.IDENTITY
var _motion_speed := 0.0
var _motion_look_sway := Vector2.ZERO
var _motion_previous_look := Vector2.ZERO
var _bow_release_anchor := Vector3.ZERO
var _bow_release_draw := 0.0
var _hand_contacts: Dictionary = {}
var weapon_pivot: Node3D
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
	bind_inventory(inventory_ref)


func bind_inventory(model: ExpeditionInventory) -> void:
	if inventory_model != null and inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.disconnect(_on_inventory_changed)
	inventory_model = model
	if inventory_model != null and not inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.connect(_on_inventory_changed)
	_sync_equipped_weapon()


func _exit_tree() -> void:
	cancel_timed_interaction()
	set_chest_container_open(false)
	cancel_flail_action()
	if inventory_model != null and inventory_model.changed.is_connected(_on_inventory_changed):
		inventory_model.changed.disconnect(_on_inventory_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_timed_interaction("상호작용을 중단했습니다")
		cancel_bow_draw()
		cancel_flail_action()


func get_inventory_status_snapshot() -> Dictionary:
	return {
		"health": health,
		"max_health": MAX_HEALTH,
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
	_refresh_carried_visibility()


func set_camping(enabled: bool) -> void:
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
	_sword_weapon_arm = _add_sword_shield_arm(weapon_pivot, 1)
	weapon_arm = _sword_weapon_arm

	_build_shield(dark_steel, leather)
	_build_equipped_torch(dark_steel)
	support_arm_root = Node3D.new()
	support_arm_root.name = "FreeHandPresentation"
	camera.add_child(support_arm_root)
	left_support_arm = _add_character_arm(support_arm_root, Vector3(-0.36, -0.34, -0.44), -1)
	left_support_arm.name = "LeftSupportArm"
	right_relaxed_arm = _add_character_arm(support_arm_root, Vector3(0.38, -0.38, -0.42), 1)
	right_relaxed_arm.name = "RightRelaxedArm"
	right_relaxed_arm.visible = false
	chest_hands = CHEST_HAND_VISUALS.new()
	chest_hands.name = "ChestHands"
	chest_hands.setup(self)
	add_child(chest_hands)
	viewmodel_renderer = FIRST_PERSON_RENDERER.new()
	viewmodel_renderer.name = "FirstPersonRenderer"
	add_child(viewmodel_renderer)
	viewmodel_renderer.setup(camera, [weapon_pivot, shield_pivot, torch_pivot, support_arm_root])
	configure_safe_zone(safe_zone_mode)


func _build_sword_visual(dark_steel: StandardMaterial3D, blade_steel: StandardMaterial3D, rusted_steel: StandardMaterial3D) -> void:
	sword_visual_root = SWORD_SCENE.instantiate() as Node3D
	sword_visual_root.name = "RustedLongswordVisual"
	weapon_pivot.add_child(sword_visual_root)
	sword_blade = sword_visual_root.find_child("PittedBlade", true, false) as MeshInstance3D
	_prepare_sword_shield_materials(sword_visual_root)


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
	shield_model.name = "WeatheredRoundShieldVisual"
	# The owner sees its actual rear straps; the boss faces the opponent.
	shield_model.rotation.y = PI
	shield_pivot.add_child(shield_model)
	_prepare_sword_shield_materials(shield_model)
	shield_arm = _add_sword_shield_arm(shield_pivot, -1)


func _build_equipped_torch(iron: StandardMaterial3D) -> void:
	# Utility-slot torch: it remains equipped alongside sword and shield until the
	# later shop/loadout pass introduces real equipment slots and fuel condition.
	torch_pivot = Node3D.new()
	torch_pivot.name = "EquippedTorch"
	torch_pivot.position = Vector3(-0.79, -0.58, -1.08)
	torch_pivot.rotation = Vector3(deg_to_rad(-7), deg_to_rad(8), deg_to_rad(-7))
	camera.add_child(torch_pivot)

	var torch_model := TORCH_SCENE.instantiate() as Node3D
	torch_model.name = "IronCageTorchVisual"
	torch_model.scale = Vector3.ONE * 0.74
	torch_pivot.add_child(torch_model)
	var torch_wood := _textured_material(Color(0.48, 0.35, 0.24), ANCIENT_OAK_TEXTURE, 0.93, 0.01, 3.0)
	_apply_material_to_prefix(torch_model, ["CharredHandle"], torch_wood)
	_apply_material_to_prefix(torch_model, ["IronCollar", "FuelCup", "CageProng", "CageTop"], iron)
	var coal_material := _material(Color(0.025, 0.012, 0.009), 0.91, 0.03)
	coal_material.emission_enabled = true
	coal_material.emission = Color(0.28, 0.018, 0.005)
	coal_material.emission_energy_multiplier = 0.35
	_apply_material_to_prefix(torch_model, ["Coal"], coal_material)
	EQUIPMENT_CONCEPT.apply_torch(torch_model)
	_set_meshes_visible_by_name(torch_model, ["OuterFlame", "InnerFlame"], false)

	torch_flame = Node3D.new()
	torch_flame.name = "Flame"
	torch_flame.position.y = 0.86
	torch_pivot.add_child(torch_flame)

	var flame_sprite := Sprite3D.new()
	flame_sprite.name = "PhotorealFlame"
	flame_sprite.texture = TORCH_FLAME_TEXTURE
	flame_sprite.pixel_size = 0.00023
	flame_sprite.position.y = 0.11
	flame_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	flame_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	flame_sprite.double_sided = true
	flame_sprite.shaded = false
	torch_flame.add_child(flame_sprite)
	FLAME_VISUALS.attach(flame_sprite)
	_add_fire_sparks(torch_flame)
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
	if combat_state == CombatState.DEAD or camping:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and current_trap == null:
		rotate_y(-event.relative.x * 0.00215)
		_pitch = clampf(_pitch - event.relative.y * 0.00215, deg_to_rad(-82), deg_to_rad(78))
		head.rotation.x = _pitch
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		cancel_bow_draw()
		cancel_flail_action()
		return
	if safe_zone_mode:
		return
	if is_timed_interacting():
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
	if camping:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and current_trap == null and not is_timed_interacting() and not bow_drawing and not _is_flail_busy() and combat_state == CombatState.READY and stamina >= 12.0:
		velocity.y = JUMP_VELOCITY
		_consume_stamina(12.0)

	var movement := Vector2.ZERO
	if current_trap == null and not is_timed_interacting() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		movement = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var local_direction := Vector3(movement.x, 0, movement.y)
	var direction := (global_transform.basis * local_direction).normalized()

	var speed := WALK_SPEED
	var sprinting := not is_timed_interacting() and not bow_drawing and not _is_flail_busy() and Input.is_action_pressed("sprint") and movement.y < -0.15 and stamina > 0.0
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

	var acceleration := 18.0 if direction != Vector3.ZERO else 24.0
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar_speed > 0.3:
		_bob_time += delta * (10.5 if sprinting else 7.3)
		head.position.y = 0.67 + sin(_bob_time) * minf(planar_speed / WALK_SPEED, 1.0) * 0.025
	else:
		head.position.y = lerpf(head.position.y, 0.67, delta * 8.0)


func _update_combat(delta: float) -> void:
	advance_combat_state(delta, Input.is_action_pressed("block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func advance_combat_state(delta: float, block_requested: bool = false) -> void:
	if camping or combat_state == CombatState.DEAD or delta <= 0.0:
		return
	# The normal dungeon controller processes while paused. Never let held bow
	# stamina (or charge time) advance through that inherited processing mode.
	if is_inside_tree() and get_tree().paused:
		return
	if safe_zone_mode:
		cancel_bow_draw()
		cancel_flail_action()
		blocking = false
		if combat_state != CombatState.READY:
			_set_combat_state(CombatState.READY)
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
					hud.update_weapon_state("방패 가드 · 저스트 가드 %.2f초" % maxf(0.0, 0.2 - block_time), Color(0.52, 0.75, 0.78))
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
			if (attack_release_requested and state_time >= 0.22) or state_time >= 1.24:
				_commit_attack()
		CombatState.ACTIVE:
			pass
		CombatState.RECOVERY:
			if hud:
				hud.update_weapon_state("자세 회복 중", Color(0.58, 0.55, 0.5))
			var recovery := lerpf(0.47, 0.68, attack_charge)
			if state_time >= recovery:
				_set_combat_state(CombatState.READY)
		CombatState.GUARD_BREAK:
			if hud:
				hud.update_weapon_state("가드 붕괴", Color(0.9, 0.24, 0.14))
			if state_time >= 1.05:
				_set_combat_state(CombatState.READY)


func _try_begin_attack() -> void:
	if not _has_melee_weapon_equipped():
		if hud:
			hud.show_event("먼저 근접 무기를 장착하십시오", 0.8)
		return
	if combat_state != CombatState.READY or blocking or current_trap != null or is_timed_interacting() or stamina < get_melee_stamina_cost(0.0):
		if stamina < get_melee_stamina_cost(0.0) and hud:
			hud.show_event("기력이 부족합니다", 0.8)
		return
	attack_charge = 0.0
	attack_release_requested = false
	attack_hit_ids.clear()
	_set_combat_state(CombatState.WINDUP)


func _commit_attack() -> void:
	var cost := get_melee_stamina_cost(attack_charge)
	_consume_stamina(cost)
	_set_combat_state(CombatState.ACTIVE)


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
	var waiting_for_sword_clash := state_time < SWORD_CLASH_GRACE_END and _has_active_sword_opponent_in_melee_path()
	if state_time >= ATTACK_HIT_TIME and attack_hit_ids.is_empty() and not waiting_for_sword_clash:
		_perform_melee_hit()
	if combat_state == CombatState.ACTIVE and state_time >= 0.16:
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
		attack_hit_ids[instance_id] = true
		var aim_point: Vector3 = candidate.call("get_aim_point") if candidate.has_method("get_aim_point") else candidate.global_position
		var aim_direction := camera.global_position.direction_to(aim_point)
		var headshot: bool = (-camera.global_transform.basis.z).dot(aim_direction) > 0.991 and aim_point.y > candidate.global_position.y + 0.35
		var damage := get_melee_damage(attack_charge)
		if headshot:
			damage *= 1.42
		candidate.call("receive_hit", damage, global_position, attack_charge, headshot)
		apply_smithing_on_hit()
		landed = true
		attack_landed.emit(damage, headshot)
		if hud:
			hud.show_hit(headshot)
		_camera_shake = maxf(_camera_shake, 0.055)
	if not landed:
		_check_wall_strike()


func _query_melee_hits() -> Array[Dictionary]:
	var shape := SphereShape3D.new()
	shape.radius = lerpf(0.7, 0.82, attack_charge)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position + (-camera.global_transform.basis.z * lerpf(1.42, 1.58, attack_charge)))
	query.collision_mask = ENEMY_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 12)


func is_sword_attack_active() -> bool:
	return combat_state == CombatState.ACTIVE and sword_blade != null and _has_melee_weapon_equipped()


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
	var to := from + (-camera.global_transform.basis.z * 2.05)
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_camera_shake = maxf(_camera_shake, 0.025)


func _update_interaction(delta: float) -> void:
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
		_begin_chest_hands(owner)
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
		if is_instance_valid(chest_hands):
			chest_hands.set_progress(progress)
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
	_interrupt_camp("가방을 열어 야영을 중단했습니다")
	cancel_bow_draw()
	cancel_flail_action()
	cancel_timed_interaction()
	set_chest_container_open(false)
	blocking = false
	velocity.x = 0.0
	velocity.z = 0.0
	if combat_state != CombatState.READY and combat_state != CombatState.DEAD:
		_set_combat_state(CombatState.READY)


func _on_timed_interaction_owner_exiting() -> void:
	cancel_timed_interaction()


func _begin_chest_hands(chest: DungeonLootChest) -> void:
	_capture_chest_carried_poses()
	chest_equipment_stowed = true
	_chest_stow_amount = 0.0
	if is_instance_valid(chest_hands):
		chest_hands.begin(chest)
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
	for carried: Node3D in [weapon_pivot, shield_pivot, torch_pivot, torch]:
		if is_instance_valid(carried) and _chest_carried_poses.has(carried.get_instance_id()):
			carried.transform = _chest_carried_poses[carried.get_instance_id()]
	_chest_carried_poses.clear()
	_refresh_carried_visibility()


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
	var tucked := chest_equipment_stowed and _chest_stow_amount >= 0.999
	if is_instance_valid(weapon_pivot):
		weapon_pivot.visible = not camping and not safe_zone_mode and not tucked
	if is_instance_valid(shield_pivot):
		shield_pivot.visible = not camping and not safe_zone_mode and not tucked and _has_shield_equipped() and not _is_bow_equipped() and not _is_flail_equipped()
	if is_instance_valid(torch_pivot):
		torch_pivot.visible = not camping and not tucked
	if is_instance_valid(support_arm_root):
		support_arm_root.visible = not camping and not chest_equipment_stowed
	_refresh_hand_visibility()


func begin_trap_disarm(trap: Node, title_text: String, zone_start: float, zone_end: float) -> bool:
	if camping or current_trap != null or combat_state == CombatState.DEAD:
		return false
	current_trap = trap
	cancel_bow_draw()
	cancel_flail_action()
	trap_lockout = 0.22
	blocking = false
	velocity.x = 0.0
	velocity.z = 0.0
	if combat_state != CombatState.READY and combat_state != CombatState.DEAD:
		_set_combat_state(CombatState.READY)
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
	if stamina < FLAIL_PROFILE.MELEE_STAMINA:
		return _flail_failure("not_enough_stamina")
	_flail_cancel_remaining = 0.0
	flail_state = "melee"
	flail_action_time = 0.0
	_flail_melee_hit_done = false
	blocking = false
	_consume_stamina(FLAIL_PROFILE.MELEE_STAMINA)
	_refresh_flail_hud()
	return {"accepted": true, "stamina_spent": FLAIL_PROFILE.MELEE_STAMINA}


func begin_flail_spin() -> Dictionary:
	var reason := _flail_use_failure()
	if not reason.is_empty():
		return _flail_failure(reason)
	if stamina < FLAIL_PROFILE.SPIN_STAMINA:
		return _flail_failure("not_enough_stamina")
	_flail_cancel_remaining = 0.0
	flail_state = "spinning"
	flail_spin_time = 0.0
	flail_spin_phase = 0.0
	_flail_release_pending = false
	_flail_release_aim = Vector3.ZERO
	blocking = false
	_consume_stamina(FLAIL_PROFILE.SPIN_STAMINA)
	_update_flail_pose()
	_refresh_flail_hud()
	return {"accepted": true, "stamina_spent": FLAIL_PROFILE.SPIN_STAMINA}


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
	return {"accepted": true, "queued": false, "projectile": projectile, "charge": charge, "damage": FLAIL_PROFILE.throw_damage(charge), "range": FLAIL_PROFILE.throw_range(charge), "stamina_spent": 0.0}


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
	var sphere := SphereShape3D.new()
	sphere.radius = 0.70
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position - head.global_basis.z * 1.55)
	query.collision_mask = ENEMY_LAYER
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 12):
		var target := result.get("collider") as Node3D
		if not is_instance_valid(target) or not target.has_method("receive_hit") or not _has_clear_melee_path(target):
			continue
		target.call("receive_hit", FLAIL_PROFILE.MELEE_DAMAGE, global_position, 0.5, false)
		attack_landed.emit(FLAIL_PROFILE.MELEE_DAMAGE, false)
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
	return BOW_SHOT_PROFILE.damage_for_draw(get_bow_draw_ratio())


func _advance_bow_draw(delta: float) -> void:
	if not bow_drawing or (is_inside_tree() and get_tree().paused):
		return
	# Damage caps at full draw, but maintaining the string remains an exertion.
	# Charge and cost use elapsed simulation time, never render-frame counts.
	var elapsed := maxf(0.0, delta)
	var spent := minf(maxf(0.0, stamina), BOW_DRAW_STAMINA_PER_SECOND * elapsed)
	if spent > 0.0:
		_consume_stamina(spent)
		bow_draw_stamina_spent += spent
		bow_draw_time = minf(BOW_DRAW_DURATION, bow_draw_time + spent / BOW_DRAW_STAMINA_PER_SECOND)
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
		"base_damage": BOW_SHOT_PROFILE.damage_for_draw(draw_ratio),
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
	if cast_type == "heal" and health >= MAX_HEALTH:
		return _spell_failure("already_full")
	var stamina_cost := maxf(0.0, float(definition.get("stamina_cost", 0.0)))
	if stamina < stamina_cost:
		return _spell_failure("not_enough_stamina")

	var projectile: MagicProjectile
	var health_restored := 0.0
	if cast_type == "projectile":
		projectile = _spawn_magic_projectile(spell_id, definition, aim_direction)
		if projectile == null:
			return _spell_failure("cannot_cast_here")
	elif cast_type == "heal":
		health_restored = restore_health(float(definition.get("heal_amount", 0.0)))
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
	_sync_equipped_weapon()
	_refresh_archery_hud()


func _sync_equipped_weapon() -> void:
	var weapon_type := _equipped_weapon_type()
	if is_instance_valid(sword_visual_root):
		sword_visual_root.visible = weapon_type == "melee"
		_sync_smithing_weapon_visual()
	if is_instance_valid(staff_visual_root):
		staff_visual_root.visible = weapon_type == "staff"
	if is_instance_valid(bow_visual_root):
		bow_visual_root.visible = weapon_type == "bow"
	if is_instance_valid(flail_visual_root):
		flail_visual_root.visible = weapon_type == "flail"
	_refresh_carried_visibility()
	var identity := "" if inventory_model == null else str(inventory_model.equipment.get("weapon", "")) + str(inventory_model.get_equipment_instance("weapon").get("uid", ""))
	if _displayed_weapon_type == weapon_type and _displayed_weapon_identity == identity:
		return
	_displayed_weapon_type = weapon_type
	_displayed_weapon_identity = identity
	if _motion_initialized:
		_motion_equip_elapsed = 0.0
	_motion_initialized = is_instance_valid(weapon_pivot)
	cancel_bow_draw()
	cancel_flail_action()
	blocking = false
	if combat_state != CombatState.READY and combat_state != CombatState.DEAD:
		_set_combat_state(CombatState.READY)
	_refresh_magic_hud()


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


func receive_attack(amount: float, attacker_position: Vector3, ailment_id := "") -> Dictionary:
	if combat_state == CombatState.DEAD:
		return {"parried": false, "blocked": false, "damage": 0.0}
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

	if blocking and not _is_bow_equipped() and not _is_flail_equipped() and frontal and stamina > 0.0:
		if block_time <= 0.20:
			stamina = minf(MAX_STAMINA, stamina + 8.0)
			_shield_impact = 0.13
			_camera_shake = maxf(_camera_shake, 0.055)
			if hud:
				hud.update_stamina(stamina, MAX_STAMINA)
				hud.show_event("방패 저스트 가드", 0.9)
			return {"parried": true, "blocked": true, "damage": 0.0}
		var stamina_damage := amount * 1.18
		if stamina >= stamina_damage:
			_consume_stamina(stamina_damage)
			var chip_damage := ceilf(amount * 0.18)
			_shield_impact = 0.1
			_camera_shake = maxf(_camera_shake, 0.035)
			_apply_health_damage(chip_damage)
			var chip_condition := _apply_damage_condition(ailment_id, chip_damage)
			if hud:
				hud.show_event("방패로 막았습니다", 0.55)
			return {"parried": false, "blocked": true, "damage": chip_damage, "condition": chip_condition}
		stamina = 0.0
		stamina_regen_delay = 1.1
		_shield_impact = 0.22
		_set_combat_state(CombatState.GUARD_BREAK)
		var break_damage := ceilf(amount * 0.55)
		_apply_health_damage(break_damage)
		var break_condition := _apply_damage_condition(ailment_id, break_damage)
		return {"parried": false, "blocked": true, "damage": break_damage, "condition": break_condition}

	_apply_health_damage(amount)
	var applied_condition := _apply_damage_condition(ailment_id, amount)
	return {"parried": false, "blocked": false, "damage": amount, "condition": applied_condition}


func receive_environment_damage(amount: float, cause: String, ailment_id := "") -> void:
	if combat_state == CombatState.DEAD:
		return
	cancel_timed_interaction("피격으로 상호작용이 중단되었습니다")
	if current_trap != null and current_trap.has_method("cancel_disarm"):
		current_trap.call("cancel_disarm", "해제 실패")
	_apply_health_damage(amount)
	_apply_damage_condition(ailment_id, amount)
	if hud:
		hud.show_event("%s · -%d 체력" % [cause, roundi(amount)], 1.4)


func _apply_health_damage(amount: float) -> void:
	var actual_damage := minf(health, maxf(0.0, amount))
	if amount > 0.0:
		_interrupt_camp("공격받아 야영이 중단되었습니다 · 사용한 보급품은 반환되지 않습니다")
		cancel_bow_draw()
		cancel_flail_action()
	health = maxf(0.0, health - amount)
	ExpeditionSession.add_stress(StressProfile.damage_gain(actual_damage))
	_camera_shake = maxf(_camera_shake, 0.16)
	if hud:
		hud.update_health(health, MAX_HEALTH)
		hud.flash_damage()
		if hud.has_method("update_stress"):
			hud.update_stress(ExpeditionSession.stress, StressProfile.MAX_STRESS, StressProfile.stage_name(ExpeditionSession.stress))
	if health <= 0.0:
		cancel_timed_interaction()
		combat_state = CombatState.DEAD
		blocking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()


func get_max_health() -> float:
	return MAX_HEALTH


func restore_health(amount: float) -> float:
	if combat_state == CombatState.DEAD or amount <= 0.0:
		return 0.0
	var previous := health
	health = minf(MAX_HEALTH, health + amount)
	if hud:
		hud.update_health(health, MAX_HEALTH)
	return health - previous


func use_consumable(item_id: String, inventory: ExpeditionInventory) -> Dictionary:
	if camping:
		return _consumable_failure("busy", "야영 중에는 야영 메뉴에서 보급품을 사용하세요.")
	if inventory == null:
		return _consumable_failure("missing_inventory", "가방을 확인할 수 없습니다.")
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty() or str(definition.get("category", "")) != "consumable":
		return _consumable_failure("not_consumable", "이 물품은 바로 사용할 수 없습니다.")
	var effect := str(definition.get("effect", ""))
	if effect == "learn_spell":
		var learning_result := ExpeditionSession.learn_spell_from_book(item_id, inventory)
		if bool(learning_result.get("accepted", false)):
			_refresh_magic_hud()
		return learning_result
	var amount := maxf(0.0, float(definition.get("amount", 0.0)))
	var condition_to_clear := "bleeding" if effect == "bandage" else ""
	match effect:
		"heal", "bandage":
			if health >= MAX_HEALTH and (condition_to_clear.is_empty() or not ExpeditionSession.has_condition(condition_to_clear)):
				return _consumable_failure("already_full", "체력이 이미 가득합니다.")
		"restore_hunger":
			if ExpeditionSession.hunger >= ExpeditionSession.MAX_NEED:
				return _consumable_failure("already_full", "이미 충분히 배부릅니다.")
		"restore_thirst":
			if ExpeditionSession.thirst >= ExpeditionSession.MAX_NEED:
				return _consumable_failure("already_full", "이미 수분이 충분합니다.")
		_:
			return _consumable_failure("unsupported_effect", "이 물품은 현재 가방에서 바로 사용할 수 없습니다.")
	if not inventory.remove_item(item_id, 1):
		return _consumable_failure("not_owned", "가방에서 해당 아이템을 찾을 수 없습니다.")

	var health_restored := 0.0
	var hunger_restored := 0.0
	var thirst_restored := 0.0
	var condition_cleared := ""
	match effect:
		"heal", "bandage":
			health_restored = restore_health(amount)
			if not condition_to_clear.is_empty() and ExpeditionSession.clear_condition(condition_to_clear):
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
	return {
		"accepted": true,
		"message": " · ".join(result_parts),
		"health_restored": health_restored,
		"hunger_restored": hunger_restored,
		"thirst_restored": thirst_restored,
		"condition_cleared": condition_cleared,
	}


func apply_condition(condition_id: String, duration := -1.0) -> bool:
	var applied := ExpeditionSession.apply_condition(condition_id, duration)
	if applied:
		_refresh_survival_hud()
	return applied


func _apply_damage_condition(condition_id: String, damage: float) -> String:
	if damage <= 0.0 or condition_id.is_empty() or combat_state == CombatState.DEAD:
		return ""
	return condition_id if apply_condition(condition_id) else ""


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
	if hud:
		hud.update_stamina(stamina, MAX_STAMINA)


func _update_stamina(delta: float) -> void:
	if stamina_regen_delay <= 0.0 and combat_state != CombatState.WINDUP and not bow_drawing and not _is_flail_busy() and not blocking and stamina < MAX_STAMINA:
		stamina = minf(MAX_STAMINA, stamina + 25.0 * delta)
		if hud:
			hud.update_stamina(stamina, MAX_STAMINA)


func _set_combat_state(next_state: CombatState) -> void:
	combat_state = next_state
	state_time = 0.0
	if next_state == CombatState.READY:
		attack_release_requested = false
		attack_hit_ids.clear()


func _update_viewmodel(delta: float) -> void:
	if weapon_pivot == null or delta < 0.0 or (is_inside_tree() and get_tree().paused):
		return
	if chest_equipment_stowed:
		_apply_chest_equipment_pose()
		_update_character_arms()
		return
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
	var target := MOTION.sword(phase, state_time, attack_charge, blocking, _has_shield_equipped())
	if weapon == "melee" and blocking and _has_shield_equipped() and _shield_impact > 0.0:
		var pulse := sin(clampf(_shield_impact / 0.22, 0.0, 1.0) * PI)
		target.origin += Vector3(-0.06, 0.18, 0.03) * pulse
		target.basis = target.basis * Basis(Vector3.RIGHT, 0.17 * pulse)
	if weapon == "bow":
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
	var movement := MOTION.locomotion(_motion_clock, _motion_speed, local_velocity.x, bow_drawing or blocking or phase != "ready")
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
	weapon_pivot.transform = target
	_update_flail_pose(delta)
	_spell_visual_time += delta
	if is_instance_valid(staff_crystal):
		var cast_pulse := sin(clampf((0.22 - _cast_recoil) / 0.22, 0.0, 1.0) * PI) if _cast_recoil > 0 else 0.0
		staff_crystal.scale = Vector3(0.66, 1.18, 0.66) * (1.0 + sin(_spell_visual_time * 4.4) * 0.025 + cast_pulse * 0.10)
	if is_instance_valid(staff_light):
		staff_light.light_energy = 0.45 + sin(_spell_visual_time * 5.2) * 0.04 + _cast_recoil * 1.2
	if is_instance_valid(shield_pivot):
		var shield_target := MOTION.shield(blocking, _shield_impact, phase)
		shield_target.origin += movement.position * 0.65
		shield_pivot.transform = shield_pivot.transform.interpolate_with(shield_target, MOTION.damping(50.0 if _shield_impact > 0.0 else (19.0 if blocking else 13.0), delta))
		_shield_impact = maxf(0.0, _shield_impact - delta)
	if is_instance_valid(torch_pivot):
		var held := _left_hand_role() == "torch"
		var torch_target := MOTION.pose(Vector3(-0.40, -0.46, -0.62), Vector3(-25, 8, 13)) if held else MOTION.pose(Vector3(-0.78, -1.55, -0.38), Vector3(-8, 10, -4))
		torch_target.origin += movement.position * 0.65 if held else Vector3.ZERO
		torch_pivot.transform = torch_pivot.transform.interpolate_with(torch_target, MOTION.damping(15.0, delta))
	if _camera_shake > 0.0:
		_camera_shake = maxf(0.0, _camera_shake - delta)
		camera.position = Vector3(sin(_motion_clock * 71.0), cos(_motion_clock * 83.0), 0) * _camera_shake * 0.11
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, MOTION.damping(22.0, delta))
	camera.rotation = Vector3(deg_to_rad(0.7), deg_to_rad(-0.35 * _bow_recoil_side), 0.0) * bow_impulse
	_refresh_carried_visibility()
	_update_character_arms()


func toggle_torch() -> bool:
	set_torch_enabled(not torch_enabled)
	return torch_enabled


func set_torch_enabled(enabled: bool) -> void:
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
	if not torch_enabled or torch == null or torch_fill == null or torch_flame == null:
		return
	_torch_time += delta
	var flicker := sin(_torch_time * 17.0) * 0.24 + sin(_torch_time * 31.0) * 0.12
	torch.light_energy = float(torch.get_meta("base_energy", 4.9)) * (1.0 + flicker / 4.9)
	torch_fill.light_energy = float(torch_fill.get_meta("base_energy", 2.4)) * (1.0 + flicker * 0.55 / 2.4)
	var flame_scale := 1.0 + sin(_torch_time * 23.0) * 0.055
	torch_flame.scale = Vector3(1.0 / flame_scale, flame_scale, 1.0 / flame_scale)


func _add_character_arm(parent: Node3D, grip: Vector3, side: int) -> Node3D:
	var arm := PLAYER_ARM_VISUAL.new()
	arm.name = "CharacterArm"
	parent.add_child(arm)
	arm.setup(side)
	arm.set_meta("grip_local", grip)
	arm.set_meta("hand_side", side)
	_position_character_hand(arm, grip, side)
	arm.set_grip(0.92)
	return arm


func _add_sword_shield_arm(parent: Node3D, side: int) -> Node3D:
	var arm := SWORD_SHIELD_ARM.new()
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
	var palm := Vector3(0.0, -0.0275, -0.0925) if arm.get_meta("continuous_skin", false) else Vector3(0.0, 0.0, -0.086)
	arm.position = grip - arm.basis * palm


func _update_character_arms() -> void:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	_hand_contacts.clear()
	var role := _left_hand_role()
	_refresh_hand_visibility()
	if is_instance_valid(weapon_arm):
		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping
		var grip := Vector3(0.0, -0.108, 0.002) if weapon_arm == _sword_weapon_arm else Vector3(0.0, -0.17, 0.015)
		if _is_staff_equipped():
			grip = staff_visual_root.transform * Vector3(0.0, -0.28, 0.0)
		elif _is_flail_equipped():
			var anchors: Dictionary = FLAIL_VISUALS.flail_hand_anchors(flail_visual_root)
			grip = flail_visual_root.transform * (anchors.get("grip", Vector3(0.0, -0.10, 0.0)) as Vector3)
		_position_character_hand(weapon_arm, grip, 1)
		weapon_arm.set_meta("grip_local", grip)
		weapon_arm.call("set_grip", 0.95 if combat_state in [CombatState.ACTIVE, CombatState.WINDUP] else 0.87)
		if _is_bow_equipped():
			_update_bow_hands()
	if role == "shield" and is_instance_valid(shield_model):
		var rear_grip := shield_model.find_child("RearGrip", true, false) as Node3D
		if rear_grip != null:
			var grip_top := shield_model.find_child("RearGripTop", true, false) as Node3D
			var grip_bottom := shield_model.find_child("RearGripBottom", true, false) as Node3D
			var axis := (grip_top.global_position - grip_bottom.global_position).normalized()
			var normal := shield_pivot.global_basis.z.normalized()
			var wrist_back := (axis.cross(-normal) * 0.207912 - normal * 0.978148).normalized()
			var orientation := Basis(-axis, wrist_back.cross(-axis).normalized(), wrist_back)
			_place_hand_contact(shield_arm, rear_grip.global_position, orientation, "shield")
			shield_arm.call("set_grip", 0.97 if blocking else 0.90)
	if role == "free" and is_instance_valid(left_support_arm):
		var lift := sin(clampf((0.22 - _cast_recoil) / 0.22, 0.0, 1.0) * PI) if _is_staff_equipped() and _cast_recoil > 0.0 else 0.0
		var contact := camera.to_global(Vector3(-0.43 + lift * 0.04, -0.29 + lift * 0.12 + sin(_motion_clock * 1.8) * 0.004, -0.65 - lift * 0.10))
		_place_hand_contact(left_support_arm, contact, camera.global_basis * Basis.from_euler(Vector3(0.75, 0.35, -0.26)), "free_left")
		left_support_arm.call("set_relaxed_pose", 0.72 if lift > 0.0 else 0.0)
	if is_instance_valid(right_relaxed_arm) and right_relaxed_arm.visible:
		_place_hand_contact(right_relaxed_arm, camera.to_global(Vector3(0.43, -0.29, -0.65)), camera.global_basis * Basis.from_euler(Vector3(0.75, -0.28, 0.25)), "free_right")
		right_relaxed_arm.call("set_relaxed_pose", 0.0)
	for arm: Node3D in [weapon_arm, shield_arm, torch_arm, left_support_arm, right_relaxed_arm]:
		if not is_instance_valid(arm) or not arm.is_visible_in_tree():
			continue
		var side := float(arm.get_meta("hand_side", 1))
		var shoulder := camera.global_transform * Vector3(side * 0.29, -0.34, 0.10)
		var pole := camera.global_basis * Vector3(side * 0.65, -0.85, 0.14)
		if arm == weapon_arm and _is_bow_equipped():
			pole = camera.global_basis * Vector3(0.9, -0.24, 0.20)
		var elbow := MOTION.elbow(shoulder, arm.global_position, pole)
		if arm == _sword_weapon_arm: elbow = arm.global_position + (elbow - arm.global_position) * 1.30
		if arm == shield_arm and role == "shield":
			var strap := shield_model.find_child("RearArmStrap", true, false) as Node3D
			if strap != null:
				var under_strap := strap.global_position - shield_pivot.global_basis.z * 0.045
				var braced_elbow := arm.global_position + (under_strap - arm.global_position).normalized() * 0.38
				# The relaxed elbow drops below the camera; the raised guard
				# settles into the enarmes. Sample the moving shield itself so
				# changing combat state never snaps the arm to another pose.
				var guard_distance := shield_pivot.position.distance_to(Vector3(-0.231, -0.109, -0.696))
				elbow = elbow.lerp(braced_elbow, 1.0 - smoothstep(0.04, 0.30, guard_distance))
		arm.call("fit_arm", shoulder, elbow)


func _place_hand_contact(arm: Node3D, contact: Vector3, orientation: Basis, label: String) -> void:
	var palm := Vector3(0.0, -0.0275, -0.0925) if arm.get_meta("continuous_skin", false) else Vector3(0.0, 0.0, -0.086)
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
	return inventory_model != null and str(inventory_model.equipment.get("offhand", "")) == "round_shield"


func _left_hand_role() -> String:
	if not safe_zone_mode and _is_bow_equipped():
		return "bow"
	if not safe_zone_mode and _has_shield_equipped() and not _is_flail_equipped():
		return "shield"
	var has_torch := inventory_model == null or str(inventory_model.equipment.get("utility", "")) == "field_torch"
	if has_torch and torch_enabled and (safe_zone_mode or not _is_flail_equipped()):
		return "torch"
	return "free"


func get_first_person_motion_snapshot() -> Dictionary:
	var arms := 0
	for arm: Node3D in [weapon_arm, shield_arm, torch_arm, left_support_arm, right_relaxed_arm]:
		if is_instance_valid(arm) and arm.is_visible_in_tree():
			arms += 1
	return {"weapon": _equipped_weapon_type(), "phase": str(CombatState.keys()[combat_state]).to_lower(), "phase_time": state_time, "motion_time": _motion_clock, "equip_progress": _motion_equip_elapsed / MOTION.EQUIP_DURATION, "flail_phase": flail_state, "draw_ratio": get_bow_draw_ratio(), "visible_arm_count": arms, "left_hand_role": _left_hand_role(), "hand_contacts": _hand_contacts.duplicate(true), "weapon_transform": weapon_pivot.transform if is_instance_valid(weapon_pivot) else Transform3D.IDENTITY, "shield_visible": is_instance_valid(shield_pivot) and shield_pivot.is_visible_in_tree(), "torch_enabled": torch_enabled}


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
		return lerpf(27.0, 53.0, clampf(charge, 0.0, 1.0))
	var stats := inventory_model.equipped_smithing_stats()
	return lerpf(float(stats.light_damage), float(stats.heavy_damage), clampf(charge, 0.0, 1.0))


func get_melee_stamina_cost(charge: float = 0.0) -> float:
	var scale := 1.0 if inventory_model == null else float(inventory_model.equipped_smithing_stats().stamina_scale)
	return lerpf(18.0, 30.0, clampf(charge, 0.0, 1.0)) * scale


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
		counterweight.position = Vector3(0, -0.318, 0.014)
		counterweight.scale.z = 0.3
		counterweight.layers = sword_blade.layers
		details.add_child(counterweight)


func _refresh_hand_visibility() -> void:
	if is_instance_valid(_sword_weapon_arm) and is_instance_valid(_legacy_weapon_arm):
		weapon_arm = _sword_weapon_arm if _equipped_weapon_type() == "melee" else _legacy_weapon_arm
		_legacy_weapon_arm.visible = false
		_sword_weapon_arm.visible = false
	var role := _left_hand_role()
	if is_instance_valid(left_support_arm):
		left_support_arm.visible = role in ["bow", "free"] and not chest_equipment_stowed and not camping
	if is_instance_valid(right_relaxed_arm):
		right_relaxed_arm.visible = (safe_zone_mode or _equipped_weapon_type() == "unarmed") and not chest_equipment_stowed and not camping
	if is_instance_valid(shield_arm):
		shield_arm.visible = role == "shield" and not chest_equipment_stowed and not camping
	if is_instance_valid(torch_arm):
		torch_arm.visible = role == "torch" and not chest_equipment_stowed and not camping
	if is_instance_valid(weapon_arm):
		weapon_arm.visible = not safe_zone_mode and _equipped_weapon_type() != "unarmed" and not chest_equipment_stowed and not camping
