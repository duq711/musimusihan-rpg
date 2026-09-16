extends SceneTree
const PREVIEW := preload("res://tests/potion_motion_preview.gd")
const FIXTURE := preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := FIXTURE.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.create_fixture(viewport)
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	var count := inventory.count_item("healing_draught")
	var health := player.health
	_check(player.begin_item_use("healing_draught", inventory).accepted, "eligible potion starts")
	_check(player.potion_hands.active, "production potion motion active")
	_check(inventory.count_item("healing_draught") == count and player.health == health, "no early consumption or healing")
	paused = true
	player.advance_bandage_motion(1.0)
	_check(player.potion_hands.elapsed == 0, "pause freezes motion")
	paused = false
	var previous_fill := 1.0
	var up_before := Vector3.ZERO
	var surface_moves := false
	var cap_poses := {}
	var previous_cap_yaw := 0.0
	for i in ceili((player.potion_hands.DRINK_DURATION - 0.05) * 60.0):
		player._update_viewmodel(1.0 / 60.0)
		player.advance_item_use(1.0 / 60.0)
		var motion: Node3D = player.potion_hands
		_check(motion.fill <= previous_fill + 0.00001, "liquid must drain monotonically")
		previous_fill = motion.fill
		_check((motion.bottle.position + motion.bottle.basis.orthonormalized() * motion.BOTTLE_GRIP_OFFSET).distance_to(motion._grip(motion.right_arm)) < 0.001, "bottle follows finger cradle")
		if motion.elapsed >= 0.98 and motion.elapsed <= 2.14:
			_check(motion.cork.rotation.y >= previous_cap_yaw - 0.00001, "stopper keeps opening progress while wrist resets")
			previous_cap_yaw = motion.cork.rotation.y
			_check(motion.cork.position.y < 4.795 + 0.004 / (motion.MODEL_SCALE * motion.BOTTLE_SIZE.y), "stopper remains seated until both turns finish")
		if (motion.elapsed > 1.10 and motion.elapsed < 1.36) or (motion.elapsed > 1.78 and motion.elapsed < 2.12):
			for vertex_index in [308, 16]:
				var distance := _cap_surface_distance(motion, _left_skin_point(motion, vertex_index))
				_check(distance > -0.0015 and distance < 0.004, "thumb/index pads stay on the stopper during each turn")
		if i in [83, 92, 100]:
			var rig: Skeleton3D = motion.left_arm._active_visual.skeleton
			cap_poses[i] = {"hand": motion.left_arm.basis.get_rotation_quaternion(), "cap": motion.cork.rotation.y, "index": rig.get_bone_pose_rotation(rig.find_bone("index1"))}
		if motion.elapsed > motion.DRINK_START + 0.2 and motion.elapsed < motion.DRINK_END - 0.15:
			var mouth: Vector3 = motion.bottle.transform * Vector3(0, 5.143, 0)
			var bottom: Vector3 = motion.bottle.transform * Vector3(0, -2.0316, 0)
			_check(mouth.distance_to(motion.DRINK_MOUTH) < 0.001, "bottle lip must stay at the mouth during gulps")
			_check((mouth - bottom).normalized().dot(Vector3.BACK) > 0.65, "bottle neck points back toward the face")
			_check(bottom.y > mouth.y + 0.08, "bottle base rises above the lips during drinking")
			var camera_lip: Vector3 = player.camera.to_local(motion.to_global(mouth))
			_check(camera_lip.y < -0.10 and camera_lip.z > -0.055, "lip contact stays below the eyes and nose, close to the lower face")
			_check(camera_lip.y < camera_lip.z * tan(deg_to_rad(player.camera.fov) * 0.5), "bottle opening remains below the bottom of the camera view")
			if up_before != Vector3.ZERO and up_before.distance_to(motion.liquid_up) > 0.002: surface_moves = true
			up_before = motion.liquid_up
		if motion.elapsed > motion.DRINK_END + 0.05: _check(not motion.liquid.visible, "empty bottle has no remaining liquid")
	_check(surface_moves, "liquid surface sloshes while drinking")
	_check(cap_poses[83].hand.angle_to(cap_poses[100].hand) > 0.65, "wrist visibly returns for a second turn")
	_check(absf(cap_poses[83].cap - cap_poses[100].cap) < 0.001, "regripping does not tighten the stopper again")
	_check(cap_poses[83].index.angle_to(cap_poses[92].index) > 0.15, "index finger relaxes between turns")
	_check(cap_poses[83].index.angle_to(cap_poses[100].index) < 0.04, "index finger closes again before the second turn")
	player._update_viewmodel(0.2)
	player.advance_item_use(0.2)
	_check(not player.is_item_use_active() and not player.potion_hands.active, "drink returns equipment")
	_check(inventory.count_item("healing_draught") == count - 1 and player.health > health, "completion consumes one and heals")
	player.apply_body_damage("left_arm", 20)
	_check(player.begin_item_use("healing_draught", inventory).accepted, "repeat starts")
	player._update_viewmodel(2.8)
	player.advance_item_use(2.8)
	player.handle_torch_action()
	_check(inventory.count_item("healing_draught") == count - 1 and not player.potion_hands.active, "F cancels without consumption")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "session and cursor restore")
	for failure in failures: push_error(failure)
	print("POTION MOTION TEST %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

# Two fingertip surface vertices from the supplied left SCN, evaluated through
# the real skin matrices (not the animation's hand-position anchor).
func _left_skin_point(motion: Node3D, vertex_index: int) -> Vector3:
	var arm: Node3D = motion.left_arm._active_visual
	var rig: Skeleton3D = arm.skeleton
	var part: MeshInstance3D = arm.hand_meshes[0]
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var point := Vector3.ZERO
	for j in 4:
		var k := vertex_index * 4 + j
		var bind := bones[k]
		var bone := part.skin.get_bind_bone(bind)
		if bone < 0: bone = rig.find_bone(part.skin.get_bind_name(bind))
		point += (rig.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind) * vertices[vertex_index]) * weights[k]
	return rig.to_global(point)

func _cap_surface_distance(motion: Node3D, world_point: Vector3) -> float:
	var bounds: AABB = motion.cork.mesh.get_aabb()
	var local: Vector3 = motion.cork.to_local(world_point) - bounds.get_center()
	var size: Vector3 = motion.cork.global_basis.get_scale()
	local *= size
	var radius := maxf(bounds.size.x * size.x, bounds.size.z * size.z) * 0.5
	var d := Vector2(Vector2(local.x, local.z).length() - radius, absf(local.y) - bounds.size.y * size.y * 0.5)
	return Vector2(maxf(d.x, 0), maxf(d.y, 0)).length() + minf(maxf(d.x, d.y), 0)
