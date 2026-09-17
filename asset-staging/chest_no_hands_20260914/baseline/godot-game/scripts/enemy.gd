extends CharacterBody3D
class_name DungeonEnemy

signal defeated(enemy: DungeonEnemy)

const PLAYER_LAYER := 1
const WORLD_LAYER := 2
const ENEMY_LAYER := 4

const WARDEN_MODEL := preload("res://assets/3d/dark_fantasy/sanctuary_warden_3d.glb")
const KEEPER_MODEL := preload("res://assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb")
const PITTED_IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const WEATHERED_BONE_TEXTURE := preload("res://assets/3d/dark_fantasy/weathered_bone_albedo.png")
const SWORD_CLASH_GEOMETRY := preload("res://scripts/sword_clash_geometry.gd")

enum AIState { IDLE, CHASE, WINDUP, ACTIVE, RECOVERY, STAGGER, DEAD }

var display_name := "망각의 감시자"
var max_health := 82.0
var health := 82.0
var attack_damage := 21.0
var move_speed := 2.25
var attack_range := 2.18
var detection_range := 10.5
var body_tint := Color(0.16, 0.18, 0.19)
var inflicted_condition := ""

const ATTACK_HIT_TIME := 0.09
const STAGGER_SECONDS := 0.72
const JUST_GUARD_STUN_SECONDS := 1.15

var target: DungeonPlayer
var hud: DungeonHUD
var game: Node
var ai_state := AIState.IDLE
var state_time := 0.0
var stagger_duration := STAGGER_SECONDS
var gravity := 18.0
var home_position := Vector3.ZERO
var attack_has_connected := false
var attack_has_resolved := false
var locked_attack_direction := Vector3.FORWARD
var visual_time := 0.0
var is_reference_skeleton := false

var weapon_pivot: Node3D
var sword_blade: MeshInstance3D
var pelvis_pivot: Node3D
var torso_pivot: Node3D
var head_pivot: Node3D
var shoulder_l_pivot: Node3D
var shoulder_r_pivot: Node3D
var arm_l_pivot: Node3D
var arm_r_pivot: Node3D
var leg_l_pivot: Node3D
var leg_r_pivot: Node3D
var elbow_l_pivot: Node3D
var elbow_r_pivot: Node3D
var wrist_l_pivot: Node3D
var wrist_r_pivot: Node3D
var knee_l_pivot: Node3D
var knee_r_pivot: Node3D
var ankle_l_pivot: Node3D
var ankle_r_pivot: Node3D
var collision_shape: CollisionShape3D
var visual_root: Node3D
var model_root: Node3D
var eye_light: OmniLight3D
var anatomy_fill_light: OmniLight3D
var ground_shadow: MeshInstance3D
var flash_material: StandardMaterial3D
var flash_tween: Tween
var visual_meshes: Array[MeshInstance3D] = []
var base_rotations: Dictionary = {}
var visual_base_position := Vector3.ZERO


func configure(name_value: String, health_value: float, damage_value: float, speed_value: float, tint_value: Color, ailment_id := "") -> void:
	display_name = name_value
	max_health = health_value
	health = health_value
	attack_damage = damage_value
	move_speed = speed_value
	body_tint = tint_value
	inflicted_condition = ailment_id


func setup(target_ref: DungeonPlayer, hud_ref: DungeonHUD, game_ref: Node) -> void:
	target = target_ref
	hud = hud_ref
	game = game_ref


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = ENEMY_LAYER
	collision_mask = PLAYER_LAYER | WORLD_LAYER
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0))
	home_position = global_position
	_build_body()


func _build_body() -> void:
	collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.43
	capsule.height = 1.78
	collision_shape.shape = capsule
	add_child(collision_shape)

	visual_root = Node3D.new()
	visual_root.name = "DarkFantasyVisual"
	visual_root.position.y = -0.90
	add_child(visual_root)
	visual_base_position = visual_root.position

	var is_keeper := display_name.contains("굶주린")
	is_reference_skeleton = is_keeper
	var enemy_scene: PackedScene = KEEPER_MODEL if is_keeper else WARDEN_MODEL
	model_root = enemy_scene.instantiate() as Node3D
	model_root.name = "AnatomicalSkeleton3D" if is_keeper else "SanctuaryWarden3D"
	visual_root.add_child(model_root)
	if is_reference_skeleton:
		_build_reference_skeleton_rig()

	pelvis_pivot = _find_model_pivot(["PelvisPivot"])
	torso_pivot = _find_model_pivot(["TorsoPivot"])
	head_pivot = _find_model_pivot(["HeadPivot"])
	shoulder_l_pivot = _find_model_pivot(["ShoulderLPivot"])
	shoulder_r_pivot = _find_model_pivot(["ShoulderRPivot"])
	arm_l_pivot = _find_model_pivot(["ArmLPivot", "LeftArmPivot"])
	arm_r_pivot = _find_model_pivot(["ArmRPivot", "RightArmPivot"])
	leg_l_pivot = _find_model_pivot(["LegLPivot", "LeftLegPivot"])
	leg_r_pivot = _find_model_pivot(["LegRPivot", "RightLegPivot"])
	elbow_l_pivot = _find_model_pivot(["ElbowLPivot"])
	elbow_r_pivot = _find_model_pivot(["ElbowRPivot"])
	wrist_l_pivot = _find_model_pivot(["WristLPivot"])
	wrist_r_pivot = _find_model_pivot(["WristRPivot"])
	knee_l_pivot = _find_model_pivot(["KneeLPivot"])
	knee_r_pivot = _find_model_pivot(["KneeRPivot"])
	ankle_l_pivot = _find_model_pivot(["AnkleLPivot"])
	ankle_r_pivot = _find_model_pivot(["AnkleRPivot"])
	weapon_pivot = _find_model_pivot(["WeaponPivot"])
	sword_blade = model_root.find_child("WeaponLongswordBlade", true, false) as MeshInstance3D
	_cache_bind_pose()
	if not is_reference_skeleton:
		preload("res://scripts/warden_concept_visual.gd").apply(model_root)
	_collect_visual_meshes(model_root)
	_apply_aged_surface_detail()
	if is_reference_skeleton:
		_apply_reference_bone_material()
	_prepare_flash_overlay()

	var shadow_alpha := 0.32 if is_reference_skeleton else 0.56
	var shadow_material := _material(Color(0.005, 0.008, 0.009, shadow_alpha), 1.0, 0.0)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_shadow = MeshInstance3D.new()
	ground_shadow.name = "EnemyGroundShadow"
	var shadow_disc := CylinderMesh.new()
	shadow_disc.top_radius = 0.46 if is_reference_skeleton else 0.52
	shadow_disc.bottom_radius = 0.56 if is_reference_skeleton else 0.64
	shadow_disc.height = 0.018
	shadow_disc.radial_segments = 32
	ground_shadow.mesh = shadow_disc
	ground_shadow.material_override = shadow_material
	ground_shadow.position.y = -0.885
	add_child(ground_shadow)

	eye_light = OmniLight3D.new()
	eye_light.name = "SpectralEyeGlow"
	eye_light.position = Vector3(0.0, 1.55 if not is_keeper else 1.43, -0.18)
	eye_light.light_color = Color(0.08, 0.82, 0.72)
	eye_light.light_energy = 0.08
	eye_light.omni_range = 2.6
	eye_light.shadow_enabled = false
	eye_light.visible = not is_keeper
	visual_root.add_child(eye_light)
	if is_keeper:
		anatomy_fill_light = OmniLight3D.new()
		anatomy_fill_light.name = "SkeletonReadabilityFill"
		anatomy_fill_light.position = Vector3(0.0, 1.12, -0.52)
		anatomy_fill_light.light_color = Color(0.66, 0.72, 0.68)
		anatomy_fill_light.light_energy = 0.68
		anatomy_fill_light.omni_range = 2.4
		anatomy_fill_light.shadow_enabled = false
		visual_root.add_child(anatomy_fill_light)


func _build_reference_skeleton_rig() -> void:
	# BodyParts3D keeps every anatomical element as a separate high-detail mesh.
	# The source coordinates are baked to metre/Y-up space. Reparenting while
	# preserving global transform keeps every source vertex intact and makes the
	# rigid bones game-poseable.
	var pelvis := _make_reference_pivot("PelvisPivot", model_root, Vector3(0.0, 0.840, 0.070))
	var torso := _make_reference_pivot("TorsoPivot", pelvis, Vector3(0.0, 0.100, -0.005))
	var head := _make_reference_pivot("HeadPivot", torso, Vector3(0.0, 0.520, -0.001))
	var shoulder_l := _make_reference_pivot("ShoulderLPivot", torso, Vector3(0.070, 0.420, 0.015))
	var arm_l := _make_reference_pivot("ArmLPivot", shoulder_l, Vector3(0.110, -0.045, -0.004))
	var elbow_l := _make_reference_pivot("ElbowLPivot", arm_l, Vector3(0.040, -0.275, 0.009))
	var wrist_l := _make_reference_pivot("WristLPivot", elbow_l, Vector3(0.020, -0.230, 0.007))
	var hand_l := _make_reference_pivot("HandLPivot", wrist_l, Vector3.ZERO)
	var shoulder_r := _make_reference_pivot("ShoulderRPivot", torso, Vector3(-0.070, 0.420, 0.015))
	var arm_r := _make_reference_pivot("ArmRPivot", shoulder_r, Vector3(-0.110, -0.045, -0.004))
	var elbow_r := _make_reference_pivot("ElbowRPivot", arm_r, Vector3(-0.040, -0.275, 0.009))
	var wrist_r := _make_reference_pivot("WristRPivot", elbow_r, Vector3(-0.020, -0.230, 0.007))
	var weapon := _make_reference_pivot("WeaponPivot", wrist_r, Vector3.ZERO)
	var hand_r := _make_reference_pivot("HandRPivot", weapon, Vector3.ZERO)
	var leg_l := _make_reference_pivot("LegLPivot", pelvis, Vector3(0.075, -0.020, 0.010))
	var knee_l := _make_reference_pivot("KneeLPivot", leg_l, Vector3(-0.005, -0.450, 0.002))
	var ankle_l := _make_reference_pivot("AnkleLPivot", knee_l, Vector3(0.005, -0.375, 0.003))
	var leg_r := _make_reference_pivot("LegRPivot", pelvis, Vector3(-0.075, -0.020, 0.010))
	var knee_r := _make_reference_pivot("KneeRPivot", leg_r, Vector3(0.005, -0.450, 0.002))
	var ankle_r := _make_reference_pivot("AnkleRPivot", knee_r, Vector3(-0.005, -0.375, 0.003))
	var rig_targets := {
		"pelvis": pelvis,
		"torso": torso,
		"head": head,
		"shoulder_l": shoulder_l,
		"shoulder_r": shoulder_r,
		"upper_l": arm_l,
		"lower_l": elbow_l,
		"hand_l": hand_l,
		"upper_r": arm_r,
		"lower_r": elbow_r,
		"hand_r": hand_r,
		"upper_leg_l": leg_l,
		"lower_leg_l": knee_l,
		"foot_l": ankle_l,
		"upper_leg_r": leg_r,
		"lower_leg_r": knee_r,
		"foot_r": ankle_r,
	}
	var source_meshes: Array[MeshInstance3D] = []
	_gather_reference_meshes(model_root, source_meshes)
	for mesh_instance in source_meshes:
		var target_key := _reference_rig_region(mesh_instance)
		var target := rig_targets[target_key] as Node3D
		var model_transform := _transform_to_ancestor(mesh_instance, model_root)
		var target_transform := _transform_to_ancestor(target, model_root)
		mesh_instance.owner = null
		mesh_instance.reparent(target, false)
		mesh_instance.transform = target_transform.affine_inverse() * model_transform

	# The supplied stock pose uses a slightly perspective-enlarged skull. A small
	# joint-local scale correction matches that silhouette without changing the
	# official source geometry stored in the GLB.
	head.scale = Vector3.ONE * 1.16

	# The atlas faces +Z and is 1.70675 m tall. The game contract faces -Z and
	# uses an approximately 1.91 m enemy while keeping its lowest vertex at y=0.
	model_root.rotation.y = PI
	model_root.scale = Vector3.ONE * 1.12
	model_root.position.y = 0.079


func _make_reference_pivot(pivot_name: String, parent: Node3D, local_position: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = local_position
	parent.add_child(pivot)
	return pivot


func _gather_reference_meshes(parent: Node, output: Array[MeshInstance3D]) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			output.append(child as MeshInstance3D)
		_gather_reference_meshes(child, output)


func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	# Relative geometry is independent of tree membership and world placement.
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _reference_rig_region(mesh_instance: MeshInstance3D) -> String:
	var part_name := String(mesh_instance.name)
	var mesh_center := _transform_to_ancestor(mesh_instance, model_root) * mesh_instance.get_aabb().get_center()
	var side := "l" if mesh_center.x >= 0.0 else "r"
	match part_name:
		"FJ3152", "FJ3288", "FJ3393":
			return "pelvis"
		"FJ3237", "FJ3279":
			return "shoulder_l"
		"FJ3362", "FJ3384":
			return "shoulder_r"
		"FJ3262":
			return "upper_l"
		"FJ3368":
			return "upper_r"
		"FJ3277", "FJ3286":
			return "lower_l"
		"FJ3349", "FJ3391":
			return "lower_r"
		"FJ3259":
			return "upper_leg_l"
		"FJ3365":
			return "upper_leg_r"
		"FJ3260", "FJ3275", "FJ3282":
			return "lower_leg_l"
		"FJ3366", "FJ3381", "FJ3387":
			return "lower_leg_r"
		"FJ2772", "FJ3199", "FJ3200", "FJ3201", "FJ3263", "FJ3265", \
		"FJ3269", "FJ3272", "FJ3273", "FJ3274", "FJ3281", "FJ3287", \
		"FJ3289", "FJ3309", "FJ3369", "FJ3371", "FJ3375", "FJ3378", \
		"FJ3379", "FJ3380", "FJ3386", "FJ3392", "FJ3394", "FJ3395":
			return "head"
	# Distal groups are spatially unambiguous in the official neutral pose and
	# cover all 27 hand and 26 foot elements on each side.
	if mesh_center.y < 0.120:
		return "foot_%s" % side
	if mesh_center.y < 0.850 and absf(mesh_center.x) > 0.180:
		return "hand_%s" % side
	return "torso"


func _find_model_pivot(candidate_names: Array[String]) -> Node3D:
	for candidate_name in candidate_names:
		var candidate := model_root.find_child(candidate_name, true, false)
		if candidate is Node3D:
			return candidate as Node3D
	return null


func _cache_bind_pose() -> void:
	base_rotations.clear()
	var pivots := [
		pelvis_pivot,
		torso_pivot,
		head_pivot,
		shoulder_l_pivot,
		shoulder_r_pivot,
		arm_l_pivot,
		arm_r_pivot,
		leg_l_pivot,
		leg_r_pivot,
		elbow_l_pivot,
		elbow_r_pivot,
		wrist_l_pivot,
		wrist_r_pivot,
		knee_l_pivot,
		knee_r_pivot,
		ankle_l_pivot,
		ankle_r_pivot,
		weapon_pivot
	]
	for pivot_value in pivots:
		if pivot_value is Node3D:
			base_rotations[pivot_value] = (pivot_value as Node3D).rotation


func _collect_visual_meshes(parent: Node) -> void:
	if parent is MeshInstance3D:
		var mesh_instance := parent as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		visual_meshes.append(mesh_instance)
	for child in parent.get_children():
		_collect_visual_meshes(child)


func _prepare_flash_overlay() -> void:
	flash_material = StandardMaterial3D.new()
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.08, 0.025, 0.0)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.025, 0.008)
	flash_material.emission_energy_multiplier = 0.0
	for mesh_instance in visual_meshes:
		mesh_instance.material_overlay = flash_material


func _apply_aged_surface_detail() -> void:
	for mesh_instance in visual_meshes:
		var part_name := String(mesh_instance.name)
		var is_armor := part_name.begins_with("Armor")
		var is_weapon_metal := part_name.begins_with("Weapon") and not (
			part_name.contains("Grip")
			or part_name.contains("Wrap")
			or part_name.contains("Blood")
		)
		if not is_armor and not is_weapon_metal:
			continue
		var source_material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if source_material == null:
			continue
		var detailed_material := source_material.duplicate(true) as StandardMaterial3D
		var source_color := source_material.albedo_color
		var is_rusted := source_color.r > source_color.g * 1.35 and source_color.r > source_color.b * 1.5
		if is_rusted:
			detailed_material.albedo_color = Color(0.74, 0.42, 0.28, source_color.a)
		elif part_name.contains("Blade"):
			detailed_material.albedo_color = Color(0.80, 0.83, 0.84, source_color.a)
		else:
			detailed_material.albedo_color = Color(0.64, 0.68, 0.70, source_color.a)
		detailed_material.albedo_texture = PITTED_IRON_TEXTURE
		detailed_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		detailed_material.texture_repeat = true
		detailed_material.uv1_triplanar = true
		detailed_material.uv1_triplanar_sharpness = 32.0
		detailed_material.uv1_scale = Vector3.ONE * 3.4
		detailed_material.roughness = maxf(0.56, detailed_material.roughness)
		detailed_material.metallic = maxf(0.58, detailed_material.metallic)
		mesh_instance.material_override = detailed_material


func _apply_reference_bone_material() -> void:
	var bone_material := StandardMaterial3D.new()
	# Balance the warm authored bone texture toward worn neutral ivory.
	bone_material.albedo_color = Color(0.66, 0.74, 0.90)
	bone_material.albedo_texture = WEATHERED_BONE_TEXTURE
	bone_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	bone_material.texture_repeat = true
	bone_material.uv1_triplanar = true
	bone_material.uv1_triplanar_sharpness = 18.0
	bone_material.uv1_scale = Vector3.ONE * 4.2
	bone_material.roughness = 0.93
	bone_material.metallic = 0.0
	bone_material.metallic_specular = 0.25
	for mesh_instance in visual_meshes:
		mesh_instance.material_override = bone_material


func _physics_process(delta: float) -> void:
	if ai_state == AIState.DEAD:
		return
	state_time += delta
	if not is_on_floor():
		velocity.y -= gravity * delta

	var flat_to_target := Vector3.ZERO
	var distance := INF
	if is_instance_valid(target):
		flat_to_target = target.global_position - global_position
		flat_to_target.y = 0.0
		distance = flat_to_target.length()

	match ai_state:
		AIState.IDLE:
			_slow_down(delta)
			if distance <= detection_range and _has_line_of_sight():
				_set_state(AIState.CHASE)
				if hud:
					hud.show_event("%s가 당신을 발견했습니다" % display_name, 1.4)
		AIState.CHASE:
			if distance > detection_range * 1.55:
				_set_state(AIState.IDLE)
			elif distance <= attack_range and _has_line_of_sight():
				locked_attack_direction = flat_to_target.normalized()
				_set_state(AIState.WINDUP)
			else:
				_move_toward_target(flat_to_target, delta)
		AIState.WINDUP:
			_slow_down(delta)
			_face_direction(flat_to_target.normalized(), delta * 6.0)
			if state_time >= 0.7:
				locked_attack_direction = flat_to_target.normalized()
				_set_state(AIState.ACTIVE)
		AIState.ACTIVE:
			_slow_down(delta)
		AIState.RECOVERY:
			_slow_down(delta)
			if state_time >= 0.92:
				_set_state(AIState.CHASE)
		AIState.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)
			if state_time >= stagger_duration:
				_set_state(AIState.CHASE)

	move_and_slide()
	_update_weapon_pose(delta)
	_update_visual_pose(delta)


func _move_toward_target(flat_direction: Vector3, delta: float) -> void:
	if flat_direction.length_squared() < 0.001:
		return
	var direction := flat_direction.normalized()
	_face_direction(direction, delta * 4.3)
	velocity.x = move_toward(velocity.x, direction.x * move_speed, delta * 7.5)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, delta * 7.5)


func _slow_down(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, delta * 8.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 8.0)


func _face_direction(direction: Vector3, weight: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


func _attempt_attack() -> bool:
	if not is_instance_valid(target):
		return false
	var flat_to_target := target.global_position - global_position
	flat_to_target.y = 0.0
	var distance := flat_to_target.length()
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if distance <= attack_range + 0.35 and forward.normalized().dot(flat_to_target.normalized()) > 0.52 and _has_line_of_sight():
		var result := target.receive_attack(attack_damage, global_position, inflicted_condition, _target_body_part())
		if bool(result.get("parried", false)):
			_set_state(AIState.STAGGER, JUST_GUARD_STUN_SECONDS if bool(result.get("shield_guard", false)) else STAGGER_SECONDS)
			velocity = global_position.direction_to(target.global_position) * -2.7
		return true
	return false


func _target_body_part() -> String:
	# Current melee hits use range and facing, so choose a body region from
	# approach direction; this is not a mesh-level anatomical hitbox claim.
	if not is_instance_valid(target):
		return "thorax"
	var approach := target.to_local(global_position)
	if approach.y > 0.7:
		return "head"
	if absf(approach.x) > absf(approach.z) * 0.85:
		return "right_arm" if approach.x > 0.0 else "left_arm"
	return "stomach" if approach.z > 0.0 else "thorax"


func _resolve_active_attack() -> void:
	if ai_state != AIState.ACTIVE:
		return
	if not attack_has_connected and is_instance_valid(target):
		target.try_sword_clash(self)
	if ai_state != AIState.ACTIVE:
		return
	if not attack_has_resolved and state_time >= ATTACK_HIT_TIME:
		attack_has_resolved = true
		var connected := _attempt_attack()
		if ai_state == AIState.ACTIVE:
			attack_has_connected = connected
	if ai_state == AIState.ACTIVE and state_time >= 0.24:
		_set_state(AIState.RECOVERY)


func is_sword_attack_active() -> bool:
	return ai_state == AIState.ACTIVE and sword_blade != null and not attack_has_connected


func get_sword_clash_proxy() -> Dictionary:
	return SWORD_CLASH_GEOMETRY.blade_proxy(sword_blade)


func receive_sword_clash(defender_position: Vector3) -> bool:
	if not is_sword_attack_active():
		return false
	_set_state(AIState.STAGGER)
	var knockback_direction := defender_position.direction_to(global_position)
	knockback_direction.y = 0.0
	if knockback_direction.length_squared() > 0.001:
		velocity = knockback_direction.normalized() * 2.7
	return true


func _has_line_of_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var from := global_position + Vector3(0, 0.55, 0)
	var to := target.global_position + Vector3(0, 0.55, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func receive_hit(amount: float, attacker_position: Vector3, charge: float, headshot: bool) -> void:
	if ai_state == AIState.DEAD:
		return
	health = maxf(0.0, health - amount)
	var knockback := attacker_position.direction_to(global_position)
	knockback.y = 0.0
	velocity += knockback.normalized() * lerpf(1.2, 3.2, charge)
	_flash_body()
	if health <= 0.0:
		_die()
	else:
		_set_state(AIState.STAGGER)
		if hud:
			hud.show_event("%s  -%d%s" % [display_name, roundi(amount), " · 치명타" if headshot else ""], 0.75)


func get_aim_point() -> Vector3:
	return global_position + Vector3(0, 0.7, 0)


func _die() -> void:
	_set_state(AIState.DEAD)
	collision_layer = 0
	collision_mask = 0
	if flash_tween:
		flash_tween.kill()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_parallel(true)
	if visual_root:
		tween.tween_property(visual_root, "rotation:z", deg_to_rad(82), 0.48).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(visual_root, "position:y", visual_base_position.y - 0.05, 0.48)
	if flash_material:
		flash_material.albedo_color = Color(0.015, 0.04, 0.035, 0.0)
		flash_material.emission_energy_multiplier = 0.0
		tween.tween_property(flash_material, "albedo_color", Color(0.015, 0.04, 0.035, 0.48), 0.7)
	if eye_light:
		tween.tween_property(eye_light, "light_energy", 0.0, 0.32)
	if anatomy_fill_light:
		tween.tween_property(anatomy_fill_light, "light_energy", 0.0, 0.32)
	defeated.emit(self)


func _set_state(next_state: AIState, stagger_seconds: float = STAGGER_SECONDS) -> void:
	# A counterattack can extend hit stun, but must not shorten a just guard.
	var remaining_stagger := maxf(0.0, stagger_duration - state_time) if ai_state == AIState.STAGGER else 0.0
	stagger_duration = maxf(stagger_seconds, remaining_stagger) if next_state == AIState.STAGGER else STAGGER_SECONDS
	ai_state = next_state
	state_time = 0.0
	attack_has_connected = false
	attack_has_resolved = false


func _update_weapon_pose(delta: float) -> void:
	var target_offset := Vector3(deg_to_rad(-18), 0, deg_to_rad(22))
	var speed := 8.0
	if ai_state == AIState.WINDUP:
		target_offset = Vector3(deg_to_rad(-55), deg_to_rad(-22), deg_to_rad(-75))
		speed = 5.5
	elif ai_state == AIState.ACTIVE:
		target_offset = Vector3(deg_to_rad(45), deg_to_rad(20), deg_to_rad(88))
		speed = 23.0
	elif ai_state == AIState.RECOVERY:
		target_offset = Vector3(deg_to_rad(18), deg_to_rad(10), deg_to_rad(46))
	elif ai_state == AIState.STAGGER:
		target_offset = Vector3(deg_to_rad(35), deg_to_rad(25), deg_to_rad(45))
	if is_reference_skeleton:
		match ai_state:
			AIState.WINDUP:
				target_offset = _degrees(Vector3(10.0, -8.0, -10.0))
				speed = 7.0
			AIState.ACTIVE:
				target_offset = _degrees(Vector3(-12.0, 10.0, -8.0))
				speed = 24.0
			AIState.RECOVERY:
				target_offset = _degrees(Vector3(-8.0, 5.0, -5.0))
			AIState.STAGGER:
				target_offset = _degrees(Vector3(18.0, 14.0, 18.0))
			_:
				target_offset = _degrees(Vector3(-4.0, 0.0, 0.0))
	_blend_pivot_rotation(weapon_pivot, target_offset, minf(1.0, delta * speed))
	if eye_light:
		eye_light.light_energy = 0.32 if ai_state == AIState.WINDUP else 0.08


func _update_visual_pose(delta: float) -> void:
	if model_root == null or ai_state == AIState.DEAD:
		return
	visual_time += delta
	var time_value := visual_time + float(get_instance_id() % 17) * 0.17
	var target_position := visual_base_position + Vector3(0.0, sin(time_value * 1.9) * 0.008, 0.0)
	var pelvis_offset := Vector3.ZERO
	var torso_offset := Vector3(0.0, 0.0, sin(time_value * 1.9) * deg_to_rad(1.0))
	var head_offset := Vector3(deg_to_rad(-2.0), 0.0, -torso_offset.z * 0.7)
	var shoulder_l_offset := Vector3.ZERO
	var shoulder_r_offset := Vector3.ZERO
	var arm_l_offset := Vector3.ZERO
	var arm_r_offset := Vector3.ZERO
	var leg_l_offset := Vector3.ZERO
	var leg_r_offset := Vector3.ZERO
	var elbow_l_offset := Vector3.ZERO
	var elbow_r_offset := Vector3.ZERO
	var wrist_l_offset := Vector3.ZERO
	var wrist_r_offset := Vector3.ZERO
	var knee_l_offset := Vector3.ZERO
	var knee_r_offset := Vector3.ZERO
	var ankle_l_offset := Vector3.ZERO
	var ankle_r_offset := Vector3.ZERO
	var pose_speed := 7.0
	match ai_state:
		AIState.CHASE:
			var walk := sin(time_value * 7.5)
			target_position.y += absf(walk) * 0.035
			torso_offset = Vector3(deg_to_rad(4.0), 0.0, sin(time_value * 3.75) * deg_to_rad(2.5))
			head_offset = Vector3(deg_to_rad(-1.0), 0.0, -torso_offset.z * 0.55)
			leg_l_offset.x = walk * deg_to_rad(24.0)
			leg_r_offset.x = -walk * deg_to_rad(24.0)
			arm_l_offset.x = -walk * deg_to_rad(18.0)
			arm_r_offset.x = walk * deg_to_rad(18.0)
			pose_speed = 12.0
		AIState.WINDUP:
			target_position += Vector3(0.0, 0.02, 0.08)
			torso_offset = _degrees(Vector3(-10.0, 18.0, -6.0))
			head_offset = _degrees(Vector3(4.0, -12.0, 4.0))
			arm_l_offset = _degrees(Vector3(18.0, -10.0, -18.0))
			arm_r_offset = _degrees(Vector3(-46.0, -18.0, -55.0))
			pose_speed = 5.5
		AIState.ACTIVE:
			target_position += Vector3(0.0, -0.025, -0.14)
			torso_offset = _degrees(Vector3(18.0, -24.0, 10.0))
			head_offset = _degrees(Vector3(-5.0, 15.0, -5.0))
			arm_l_offset = _degrees(Vector3(-12.0, 10.0, -25.0))
			arm_r_offset = _degrees(Vector3(52.0, 18.0, 60.0))
			pose_speed = 22.0
		AIState.RECOVERY:
			target_position += Vector3(0.0, -0.012, -0.05)
			torso_offset = _degrees(Vector3(9.0, -12.0, 5.0))
			head_offset = _degrees(Vector3(-2.0, 7.0, -2.0))
			arm_l_offset = _degrees(Vector3(-6.0, 4.0, -12.0))
			arm_r_offset = _degrees(Vector3(22.0, 10.0, 30.0))
			pose_speed = 8.0
		AIState.STAGGER:
			target_position += Vector3(0.08, -0.035, 0.10)
			torso_offset = _degrees(Vector3(-16.0, 12.0, -12.0))
			head_offset = _degrees(Vector3(10.0, -8.0, 10.0))
			arm_l_offset = _degrees(Vector3(30.0, -25.0, -35.0))
			arm_r_offset = _degrees(Vector3(30.0, 25.0, 35.0))
			pose_speed = 16.0
	if is_reference_skeleton:
		match ai_state:
			AIState.IDLE:
				torso_offset = _degrees(Vector3(-4.0, -4.0, sin(time_value * 1.7) * 2.2))
				head_offset = _degrees(Vector3(3.0, sin(time_value * 0.9) * 4.0, -sin(time_value * 1.7) * 1.4))
				arm_l_offset = _degrees(Vector3(-8.0, -5.0, 16.0))
				arm_r_offset = _degrees(Vector3(-8.0, 5.0, -16.0))
				shoulder_l_offset = _degrees(Vector3(0.0, -1.0, 2.0))
				shoulder_r_offset = _degrees(Vector3(0.0, 1.0, -2.0))
				elbow_l_offset = _degrees(Vector3(8.0, 0.0, 8.0))
				elbow_r_offset = _degrees(Vector3(8.0, 0.0, -8.0))
				wrist_l_offset = _degrees(Vector3(0.0, -4.0, 7.0))
				wrist_r_offset = _degrees(Vector3(0.0, 4.0, -7.0))
				knee_l_offset.x = deg_to_rad(6.0)
				knee_r_offset.x = deg_to_rad(6.0)
				pose_speed = 5.0
			AIState.CHASE:
				var skeleton_walk := sin(time_value * 7.5)
				elbow_l_offset.x = deg_to_rad(14.0 + maxf(0.0, skeleton_walk) * 18.0)
				elbow_r_offset.x = deg_to_rad(14.0 + maxf(0.0, -skeleton_walk) * 18.0)
				knee_l_offset.x = deg_to_rad(7.0 + maxf(0.0, -skeleton_walk) * 42.0)
				knee_r_offset.x = deg_to_rad(7.0 + maxf(0.0, skeleton_walk) * 42.0)
				ankle_l_offset.x = -knee_l_offset.x * 0.45
				ankle_r_offset.x = -knee_r_offset.x * 0.45
			AIState.WINDUP:
				target_position = visual_base_position + Vector3(0.0, -0.045, 0.10)
				torso_offset = _degrees(Vector3(-13.0, 14.0, -7.0))
				head_offset = _degrees(Vector3(8.0, -12.0, 7.0))
				arm_l_offset = _degrees(Vector3(-28.0, -10.0, 58.0))
				arm_r_offset = _degrees(Vector3(-42.0, 14.0, -58.0))
				shoulder_l_offset = _degrees(Vector3(-2.0, -3.0, 7.0))
				shoulder_r_offset = _degrees(Vector3(-4.0, 4.0, -9.0))
				elbow_l_offset = _degrees(Vector3(25.0, 0.0, 22.0))
				elbow_r_offset = _degrees(Vector3(48.0, 0.0, -22.0))
				wrist_l_offset = _degrees(Vector3(8.0, -8.0, 14.0))
				wrist_r_offset = _degrees(Vector3(10.0, 8.0, -14.0))
				knee_l_offset.x = deg_to_rad(28.0)
				knee_r_offset.x = deg_to_rad(28.0)
				pose_speed = 7.0
			AIState.ACTIVE:
				target_position = visual_base_position + Vector3(0.0, 0.110, -0.16)
				pelvis_offset = _degrees(Vector3(0.0, 0.0, 8.0))
				torso_offset = _degrees(Vector3(-7.0, -12.0, 14.0))
				head_offset = _degrees(Vector3(2.0, 6.0, -21.0))
				arm_l_offset = _degrees(Vector3(-10.0, -8.0, 98.0))
				arm_r_offset = _degrees(Vector3(5.0, 7.0, -90.0))
				shoulder_l_offset = _degrees(Vector3(-3.0, -5.0, 10.0))
				shoulder_r_offset = _degrees(Vector3(2.0, 5.0, -9.0))
				elbow_l_offset = _degrees(Vector3(-8.0, -10.0, 8.0))
				elbow_r_offset = _degrees(Vector3(-12.0, 8.0, -48.0))
				wrist_l_offset = _degrees(Vector3(8.0, -8.0, 18.0))
				wrist_r_offset = _degrees(Vector3(-6.0, 8.0, -15.0))
				leg_l_offset = _degrees(Vector3(-8.0, 42.0, -25.0))
				leg_r_offset = _degrees(Vector3(-60.0, -15.0, -30.0))
				knee_l_offset = _degrees(Vector3(-70.0, 2.0, 2.0))
				knee_r_offset = _degrees(Vector3(100.0, -3.0, -2.0))
				ankle_l_offset = _degrees(Vector3(65.0, 0.0, -7.0))
				ankle_r_offset = _degrees(Vector3(-30.0, 30.0, -30.0))
				pose_speed = 24.0
			AIState.RECOVERY:
				elbow_l_offset = _degrees(Vector3(12.0, 0.0, -18.0))
				elbow_r_offset = _degrees(Vector3(18.0, 0.0, 16.0))
				knee_l_offset.x = deg_to_rad(14.0)
				knee_r_offset.x = deg_to_rad(14.0)
			AIState.STAGGER:
				elbow_l_offset = _degrees(Vector3(18.0, 0.0, 35.0))
				elbow_r_offset = _degrees(Vector3(18.0, 0.0, -35.0))
				shoulder_l_offset = _degrees(Vector3(3.0, -4.0, 8.0))
				shoulder_r_offset = _degrees(Vector3(3.0, 4.0, -8.0))
				wrist_l_offset.z = deg_to_rad(22.0)
				wrist_r_offset.z = deg_to_rad(-22.0)
	var blend := minf(1.0, delta * pose_speed)
	visual_root.position = visual_root.position.lerp(target_position, blend)
	_blend_pivot_rotation(pelvis_pivot, pelvis_offset, blend)
	_blend_pivot_rotation(torso_pivot, torso_offset, blend)
	_blend_pivot_rotation(head_pivot, head_offset, blend)
	_blend_pivot_rotation(shoulder_l_pivot, shoulder_l_offset, blend)
	_blend_pivot_rotation(shoulder_r_pivot, shoulder_r_offset, blend)
	_blend_pivot_rotation(arm_l_pivot, arm_l_offset, blend)
	_blend_pivot_rotation(arm_r_pivot, arm_r_offset, blend)
	_blend_pivot_rotation(leg_l_pivot, leg_l_offset, blend)
	_blend_pivot_rotation(leg_r_pivot, leg_r_offset, blend)
	_blend_pivot_rotation(elbow_l_pivot, elbow_l_offset, blend)
	_blend_pivot_rotation(elbow_r_pivot, elbow_r_offset, blend)
	_blend_pivot_rotation(wrist_l_pivot, wrist_l_offset, blend)
	_blend_pivot_rotation(wrist_r_pivot, wrist_r_offset, blend)
	_blend_pivot_rotation(knee_l_pivot, knee_l_offset, blend)
	_blend_pivot_rotation(knee_r_pivot, knee_r_offset, blend)
	_blend_pivot_rotation(ankle_l_pivot, ankle_l_offset, blend)
	_blend_pivot_rotation(ankle_r_pivot, ankle_r_offset, blend)


func _blend_pivot_rotation(pivot_value: Node3D, offset: Vector3, blend: float) -> void:
	if pivot_value == null or not base_rotations.has(pivot_value):
		return
	var bind_rotation: Vector3 = base_rotations[pivot_value]
	var target_rotation := bind_rotation + offset
	pivot_value.rotation.x = lerp_angle(pivot_value.rotation.x, target_rotation.x, blend)
	pivot_value.rotation.y = lerp_angle(pivot_value.rotation.y, target_rotation.y, blend)
	pivot_value.rotation.z = lerp_angle(pivot_value.rotation.z, target_rotation.z, blend)


func _degrees(value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))


func _flash_body() -> void:
	if flash_material == null:
		return
	if flash_tween:
		flash_tween.kill()
	flash_material.albedo_color = Color(1.0, 0.08, 0.025, 0.62)
	flash_material.emission_energy_multiplier = 2.8
	flash_tween = create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash_material, "albedo_color", Color(1.0, 0.08, 0.025, 0.0), 0.18)
	flash_tween.tween_property(flash_material, "emission_energy_multiplier", 0.0, 0.18)


func _box(size_value: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh_value := BoxMesh.new()
	mesh_value.size = size_value
	instance.mesh = mesh_value
	instance.material_override = material
	return instance


func _material(color_value: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material
