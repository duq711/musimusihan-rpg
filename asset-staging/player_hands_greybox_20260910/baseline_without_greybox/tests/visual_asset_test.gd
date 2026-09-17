extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var texture_paths := [
		"res://assets/ai/materials/ossuary_wall.png",
		"res://assets/ai/materials/wet_flagstone.png",
		"res://assets/ai/materials/ancient_oak.png",
		"res://assets/ai/materials/pitted_black_iron.png",
		"res://assets/ai/vfx/extraction_portal.png",
		"res://assets/ai/vfx/rune_trap.png",
		"res://assets/ai/vfx/torch_flame.png"
	]
	for path in texture_paths:
		_check(load(path) is Texture2D, "AI texture must load: %s" % path)

	var model_paths := [
		"res://assets/3d/dark_fantasy/rusted_longsword.glb",
		"res://assets/3d/dark_fantasy/weathered_round_shield.glb",
		"res://assets/3d/dark_fantasy/iron_cage_torch.glb",
		"res://assets/3d/dark_fantasy/reliquary_chest.glb",
		"res://assets/3d/dark_fantasy/blood_rune_trap.glb",
		"res://assets/3d/dark_fantasy/sanctum_portal_arch.glb",
		"res://assets/3d/dark_fantasy/sanctuary_warden_3d.glb",
		"res://assets/3d/dark_fantasy/anatomical_skeleton_cc_by_4.glb"
	]
	for path in model_paths:
		var packed := load(path) as PackedScene
		_check(packed != null, "dark-fantasy GLB must import: %s" % path)
		if packed:
			var instance := packed.instantiate()
			_check(instance is Node3D, "dark-fantasy GLB must instantiate as Node3D: %s" % path)
			instance.free()

	var packed_game := load("res://main.tscn") as PackedScene
	_check(packed_game != null, "main scene must load for visual validation")
	if packed_game == null:
		_finish()
		return
	var game := packed_game.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame

	_check(game.stone_material.albedo_texture != null, "wall material must use the AI ossuary texture")
	_check(game.floor_material.albedo_texture != null, "floor material must use the AI wet-flagstone texture")
	_check(game.find_child("OssuaryPillarVisual", true, false) != null, "modular Gothic pillars must spawn")
	_check(game.find_child("GothicVoussoir", true, false) != null, "Gothic arch detail must spawn")
	_check(game.find_child("PortalSpectralMotes", true, false) is CPUParticles3D, "portal motes must spawn")
	_check(game.portal_visual != null and game.portal_material.albedo_texture != null, "AI extraction portal must be applied")

	var player := get_first_node_in_group("player") as DungeonPlayer
	_check(player != null, "player must spawn for visual validation")
	if player:
		_check(player.weapon_pivot.find_child("RustedLongswordVisual", true, false) != null, "longsword GLB must be mounted to WeaponPivot")
		_check(player.sword_blade is MeshInstance3D and player.sword_blade.name == "PittedBlade", "player sword-clash proxy must follow the rendered blade mesh")
		_check(player.shield_pivot.find_child("WeatheredRoundShieldVisual", true, false) != null, "shield GLB must be mounted to ShieldPivot")
		_check(player.torch_pivot.find_child("IronCageTorchVisual", true, false) != null, "torch GLB must be mounted to EquippedTorch")
		_check(player.torch_flame.find_child("PhotorealFlame", true, false) is Sprite3D, "AI torch flame must be mounted")

	var enemies := get_nodes_in_group("enemy")
	_check(enemies.size() == 2, "two fully 3D enemies must spawn")
	var enemy_model_names: Array[StringName] = []
	var enemy_instances: Array[DungeonEnemy] = []
	for enemy_node in enemies:
		var enemy := enemy_node as DungeonEnemy
		enemy.set_physics_process(false)
		enemy_instances.append(enemy)
		_check(enemy.model_root is Node3D, "each enemy must mount an actual 3D model")
		_check(enemy.find_children("*", "Sprite3D", true, false).is_empty(), "enemy hierarchy must contain no 2D billboard sprites")
		_check(enemy.visual_meshes.size() >= 24, "each enemy must contain a detailed multi-part 3D mesh")
		_check(enemy.torso_pivot != null and enemy.head_pivot != null, "enemy torso and head pivots must exist")
		_check(enemy.arm_l_pivot != null and enemy.arm_r_pivot != null, "enemy arm pivots must exist")
		_check(enemy.leg_l_pivot != null and enemy.leg_r_pivot != null, "enemy leg pivots must exist")
		_check(enemy.weapon_pivot != null and enemy.model_root.is_ancestor_of(enemy.weapon_pivot), "weapon pivot must belong to the imported 3D model")
		_check(enemy.find_children("*", "CollisionShape3D", true, false).size() == 1, "enemy must keep exactly one gameplay collision capsule")
		var capsule := enemy.collision_shape.shape as CapsuleShape3D
		_check(capsule != null and is_equal_approx(capsule.radius, 0.43) and is_equal_approx(capsule.height, 1.78), "3D visual swap must preserve enemy collision dimensions")
		var is_reference_skeleton := enemy.display_name.contains("굶주린")
		if is_reference_skeleton:
			_check(enemy.sword_blade == null, "unarmed reference skeleton must not expose a sword-clash blade")
			var hand_l := enemy.model_root.find_child("HandLPivot", true, false) as Node3D
			var hand_r := enemy.model_root.find_child("HandRPivot", true, false) as Node3D
			var skull_count := 0
			var hand_l_count := 0
			var hand_r_count := 0
			var foot_l_count := 0
			var foot_r_count := 0
			for bone_mesh in enemy.visual_meshes:
				if enemy.head_pivot.is_ancestor_of(bone_mesh):
					skull_count += 1
				if hand_l != null and hand_l.is_ancestor_of(bone_mesh):
					hand_l_count += 1
				if hand_r != null and hand_r.is_ancestor_of(bone_mesh):
					hand_r_count += 1
				if enemy.ankle_l_pivot.is_ancestor_of(bone_mesh):
					foot_l_count += 1
				if enemy.ankle_r_pivot.is_ancestor_of(bone_mesh):
					foot_r_count += 1
			_check(enemy.visual_meshes.size() == 202, "BodyParts3D skeleton must retain all 202 selected anatomical structures")
			_check(enemy.model_root.find_child("FJ3200", true, false) is MeshInstance3D, "reference skeleton must retain the official frontal-bone mesh")
			_check(enemy.model_root.find_child("FJ3289", true, false) is MeshInstance3D, "reference skeleton must retain the separate anatomical mandible")
			var rib_l_ids := ["FJ3225", "FJ3226", "FJ3227", "FJ3228", "FJ3229", "FJ3230", "FJ3231", "FJ3232", "FJ3233", "FJ3234", "FJ3235", "FJ3236"]
			var rib_r_ids := ["FJ3330", "FJ3331", "FJ3332", "FJ3334", "FJ3336", "FJ3338", "FJ3340", "FJ3342", "FJ3344", "FJ3346", "FJ3347", "FJ3348"]
			for rib_id in rib_l_ids + rib_r_ids:
				var rib := enemy.model_root.find_child(rib_id, true, false)
				_check(rib is MeshInstance3D and enemy.torso_pivot.is_ancestor_of(rib), "official rib %s must remain attached to the torso" % rib_id)
			var spine_count := 0
			for spine_index in range(3154, 3178):
				if enemy.model_root.find_child("FJ%d" % spine_index, true, false) is MeshInstance3D:
					spine_count += 1
			_check(spine_count == 24, "reference skeleton must have all 24 presacral vertebrae")
			_check(skull_count == 24, "reference skeleton must retain all 24 selected skull structures")
			_check(hand_l_count == 27 and hand_r_count == 27, "reference skeleton must rig all 27 bones of each hand independently by side")
			_check(foot_l_count == 26 and foot_r_count == 26, "reference skeleton must rig all 26 bones of each foot independently by side")
			_check(enemy.pelvis_pivot != null, "reference skeleton must have a pelvis root joint")
			_check(enemy.shoulder_l_pivot != null and enemy.shoulder_r_pivot != null, "reference skeleton must have independent shoulder-girdle joints")
			_check(enemy.elbow_l_pivot != null and enemy.elbow_r_pivot != null, "reference skeleton must have independent elbow joints")
			_check(enemy.wrist_l_pivot != null and enemy.wrist_r_pivot != null, "reference skeleton must have independent wrist joints")
			_check(enemy.knee_l_pivot != null and enemy.knee_r_pivot != null, "reference skeleton must have independent knee joints")
			_check(enemy.ankle_l_pivot != null and enemy.ankle_r_pivot != null, "reference skeleton must have independent ankle joints")
			var hip_l := enemy.model_root.find_child("FJ3288", true, false)
			var hip_r := enemy.model_root.find_child("FJ3152", true, false)
			_check(hip_l != null and hip_r != null and enemy.pelvis_pivot.is_ancestor_of(hip_l) and enemy.pelvis_pivot.is_ancestor_of(hip_r), "both hip bones must remain attached to PelvisPivot")
			_check(enemy.pelvis_pivot.is_ancestor_of(enemy.leg_l_pivot) and enemy.pelvis_pivot.is_ancestor_of(enemy.leg_r_pivot), "both leg rigs must share PelvisPivot with the hip bones")
			_check(enemy.model_root.find_child("FJ3262", true, false).get_parent() == enemy.arm_l_pivot, "left humerus must be mounted directly to its shoulder joint")
			_check(enemy.model_root.find_child("FJ3368", true, false).get_parent() == enemy.arm_r_pivot, "right humerus must be mounted directly to its shoulder joint")
			_check(enemy.model_root.find_child("FJ3282", true, false).get_parent() == enemy.knee_l_pivot, "left tibia must be mounted directly to its knee joint")
			_check(enemy.model_root.find_child("FJ3387", true, false).get_parent() == enemy.knee_r_pivot, "right tibia must be mounted directly to its knee joint")
			_check(enemy.model_root.find_children("Cloth*", "MeshInstance3D", true, false).is_empty(), "reference skeleton must have no hood or clothing")
			_check(enemy.model_root.find_children("Armor*", "MeshInstance3D", true, false).is_empty(), "reference skeleton must have no armor")
			_check(enemy.model_root.find_children("Weapon*", "MeshInstance3D", true, false).is_empty(), "reference skeleton must be unarmed like the supplied image")
			_check(enemy.model_root.find_children("Eye*Glow*", "MeshInstance3D", true, false).is_empty() and not enemy.eye_light.visible, "reference skeleton must use empty eye sockets without glow")
			_check(is_equal_approx(absf(enemy.model_root.rotation.y), PI), "reference skeleton must face Godot's -Z gameplay-forward direction")
		else:
			_check(enemy.model_root.find_child("WeaponLongswordBlade", true, false) is MeshInstance3D, "warden must retain its modeled longsword")
			_check(enemy.sword_blade == enemy.model_root.find_child("WeaponLongswordBlade", true, false), "armed enemy sword-clash proxy must follow the rendered blade mesh")
			_check(enemy.model_root.find_child("Eye*Glow*", true, false) is MeshInstance3D, "warden must retain modeled emissive eyes")
		var pose_probe := enemy.model_root.find_child("FJ3193", true, false) as Node3D if is_reference_skeleton else enemy.model_root.find_child("WeaponLongswordBlade", true, false) as Node3D
		var bind_probe_position := pose_probe.global_position if pose_probe != null else Vector3.ZERO
		var bind_weapon_rotation := enemy.weapon_pivot.rotation
		enemy._set_state(DungeonEnemy.AIState.WINDUP)
		enemy._update_weapon_pose(1.0)
		enemy._update_visual_pose(1.0)
		var windup_probe_position := pose_probe.global_position if pose_probe != null else Vector3.ZERO
		var windup_rotation := enemy.weapon_pivot.rotation
		enemy._set_state(DungeonEnemy.AIState.ACTIVE)
		enemy._update_weapon_pose(1.0)
		enemy._update_visual_pose(1.0)
		_check(not windup_rotation.is_equal_approx(bind_weapon_rotation) and not enemy.weapon_pivot.rotation.is_equal_approx(windup_rotation), "3D weapon or wrist joint must animate through windup and attack poses")
		_check(pose_probe != null and bind_probe_position.distance_to(windup_probe_position) > 0.025 and windup_probe_position.distance_to(pose_probe.global_position) > 0.025, "a visible hand or weapon mesh must move through windup and attack poses")
		if is_reference_skeleton:
			var knee_r_bind: Vector3 = enemy.base_rotations[enemy.knee_r_pivot]
			_check(absf(enemy.knee_r_pivot.rotation.x - knee_r_bind.x) > deg_to_rad(35.0), "reference attack must flex the right knee on its anatomical hinge axis")
			_check(absf(enemy.knee_r_pivot.rotation.z - knee_r_bind.z) < deg_to_rad(10.0), "reference attack must not laterally dislocate the right knee")
		enemy_model_names.append(enemy.model_root.name)
	_check(enemy_model_names.size() == 2 and enemy_model_names[0] != enemy_model_names[1], "enemy variants must use distinct 3D models")
	if enemy_instances.size() == 2:
		_check(enemy_instances[0].flash_material != enemy_instances[1].flash_material, "hit overlays must be unique per enemy instance")
		enemy_instances[0]._flash_body()
		_check(enemy_instances[0].flash_material.albedo_color.a > 0.5 and is_zero_approx(enemy_instances[1].flash_material.albedo_color.a), "one enemy hit flash must not alter the other enemy")

	var traps := get_nodes_in_group("trap")
	_check(traps.size() == 2, "two upgraded traps must spawn")
	for trap_node in traps:
		var trap := trap_node as RuneTrap
		_check(trap.find_child("BloodRuneTrapVisual", true, false) != null, "trap GLB visual must spawn")
		_check(trap.find_child("AITrapRune", true, false) is MeshInstance3D, "AI rune decal must be applied to trap")
		_check(trap.spike_root != null and trap.spike_root.get_child_count() >= 18, "trap must preserve animated detailed spikes")

	var chests := get_nodes_in_group("loot_chest")
	_check(chests.size() == 2, "two upgraded reliquary chests must spawn")
	if not chests.is_empty():
		var chest := chests[0] as DungeonLootChest
		_check(chest.find_child("ReliquaryChestVisual", true, false) != null, "reliquary chest GLB visual must spawn")
		_check(chest.find_child("AISealRune", true, false) is MeshInstance3D, "AI seal rune must be applied to chest")
		_check(chest.lid_pivot != null and chest.lid_pivot.get_child_count() > 0, "chest lid geometry must remain attached to its animation pivot")
		chest._animate_open()
		await create_timer(0.5).timeout
		_check(chest.lid_pivot.rotation.x > deg_to_rad(45.0), "upgraded chest lid must animate upward around its rear hinge")

	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("VISUAL ASSET TEST PASS: reference-matched skeleton, full 3D enemies, GLBs, pivots, VFX, and animated props")
		quit(0)
		return
	for failure in failures:
		push_error("VISUAL ASSET TEST FAIL: %s" % failure)
	quit(1)
