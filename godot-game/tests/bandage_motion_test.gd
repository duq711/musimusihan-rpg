extends SceneTree
const PREVIEW := preload("res://tests/bandage_motion_preview.gd")
const FIXTURE := preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

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
	var before := inventory.count_item("linen_bandage")
	var initial_weapon: Transform3D = player.weapon_pivot.transform
	var initial_pair: Transform3D = player.weapon_pivot.global_transform.affine_inverse() * player.support_arm_root.global_transform
	var result := player.use_consumable("linen_bandage", inventory)
	_check(result.accepted and result.health_restored == 18.0, "actual selected-arm bandage must heal once")
	_check(inventory.count_item("linen_bandage") == before - 1 and player.is_bandage_motion_active(), "successful use must spend one and start presentation")
	_check(player.weapon_pivot.visible and not player.bandage_hands.visible and player.weapon_pivot.transform.is_equal_approx(initial_weapon), "use must begin from the visible held weapon pose without a pop")
	var healed := player.health
	var previous_roll: Vector3 = player.bandage_hands.roll.position
	var previous_basis: Basis = player.bandage_hands.right_arm.basis
	var minimum_arm_clearance := INF
	var left_mesh: MeshInstance3D = player.bandage_hands._forearm_mesh
	var right_mesh: MeshInstance3D = player.bandage_hands.right_arm.arm_meshes[0]
	var maximum_free_strip := 0.0
	var first_working_basis := Basis.IDENTITY
	var receiving_arm_rotation := 0.0
	var tear_origin := Vector3.ZERO
	var max_step := 0.0
	var max_angle := 0.0
	var maximum_wrist_gap := 0.0
	var maximum_upper_length := 0.0
	var minimum_receiving_wrist_y := INF
	paused = true
	player.advance_bandage_motion(1.0)
	_check(player.bandage_hands.elapsed == 0.0, "paused inventory must defer animation until world resumes")
	paused = false
	for i in 320:
		player._update_viewmodel(1.0 / 60.0)
		if i == 11:
			_check(player.weapon_pivot.visible and not player.bandage_hands.visible and player.weapon_pivot.position.y < initial_weapon.origin.y - 0.1, "lower held equipment before exposing the treatment hands")
			_check((player.weapon_pivot.global_transform.affine_inverse() * player.support_arm_root.global_transform).is_equal_approx(initial_pair), "stowing must preserve the relative weapon and supporting-hand grip")
		if i == 32:
			_check(not player.weapon_pivot.visible and not player.support_arm_root.visible and player.bandage_hands.visible and is_zero_approx(player.bandage_hands.winding), "raise empty hands only after equipment is stowed, without unfolding")
			var paused_at: float = player.bandage_hands.elapsed
			var paused_pose: Transform3D = player.bandage_hands.left_arm.transform
			paused = true
			player.advance_bandage_motion(1.0)
			_check(player.bandage_hands.elapsed == paused_at and player.bandage_hands.left_arm.transform.is_equal_approx(paused_pose), "pause must freeze the hand-lift transition")
			paused = false
		if i == 59:
			_check(player.bandage_hands.cloth.visible and player.bandage_hands.winding > 0.0, "lifting must join the existing winding motion without a preparation hold")
		if i == 227:
			tear_origin = player.bandage_hands.roll.position
		if i == 233:
			_check(not player.bandage_hands.torn and player.bandage_hands.roll.position.distance_to(tear_origin) > 0.02, "last wrap must immediately build tension without a finishing hold")
		if i == 242:
			_check(player.bandage_hands.torn and player.bandage_hands.roll.position.distance_to(tear_origin) > 0.1, "roll hand must visibly pull away and tear the strip")
			var vertices: PackedVector3Array = player.bandage_hands.strip.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var tail_start := (vertices[0] + vertices[2]) * 0.5
			var tail_end := (vertices[1] + vertices[5]) * 0.5
			_check(tail_start.distance_to(tail_end) < 0.06 and tail_start.distance_to(player.bandage_hands._point(player.bandage_hands.winding)) > 0.03, "torn strip must remain a short roll-side tail rather than bridge back to the arm")
			_check(player.bandage_hands.cloth.visible, "tearing must leave the deposited dressing on the arm")
		if i == 308:
			_check(player.weapon_pivot.visible and not player.bandage_hands.visible and player.weapon_pivot.position.y < initial_weapon.origin.y, "raise equipment from below after the dressing hands have left")
		for arm: Node3D in [player.bandage_hands.left_arm, player.bandage_hands.right_arm]:
			var adapter: Node3D = arm._active_visual
			var hand_wrist: Vector3 = adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(adapter.skeleton.find_bone("wrist")).origin
			var sleeve_wrist: Vector3 = adapter.get_forearm_frame().origin
			maximum_wrist_gap = maxf(maximum_wrist_gap, hand_wrist.distance_to(sleeve_wrist))
		if i >= 48 and i < 255:
			maximum_upper_length = maxf(maximum_upper_length, player.bandage_hands.right_arm._active_visual.get_upper_length())
		if i >= 48 and i < 228:
			var receiving_adapter: Node3D = player.bandage_hands.left_arm._active_visual
			var receiving_wrist: Vector3 = receiving_adapter.global_position
			minimum_receiving_wrist_y = minf(minimum_receiving_wrist_y, player.camera.unproject_position(receiving_wrist).y / viewport.size.y)
			var closest := Geometry3D.get_closest_points_between_segments(player.bandage_hands.left_arm._active_visual.get_forearm_frame() * Vector3(0, 0, 0.077), player.bandage_hands.left_arm._active_visual.get_forearm_frame() * Vector3(0, 0, 0.271), player.bandage_hands.right_arm._active_visual.get_forearm_frame() * Vector3(0, 0, 0.077), player.bandage_hands.right_arm._active_visual.get_forearm_frame() * Vector3(0, 0, 0.271))
			maximum_free_strip = maxf(maximum_free_strip, player.bandage_hands.roll.position.distance_to(player.bandage_hands._point(player.bandage_hands.winding)))
			if i == 48: first_working_basis = player.bandage_hands.left_arm.basis
			receiving_arm_rotation = maxf(receiving_arm_rotation, first_working_basis.get_rotation_quaternion().angle_to(player.bandage_hands.left_arm.basis.get_rotation_quaternion()))
			minimum_arm_clearance = minf(minimum_arm_clearance, closest[0].distance_to(closest[1]))
		max_step = maxf(max_step, previous_roll.distance_to(player.bandage_hands.roll.position))
		max_angle = maxf(max_angle, previous_basis.get_rotation_quaternion().angle_to(player.bandage_hands.right_arm.basis.get_rotation_quaternion()))
		previous_roll = player.bandage_hands.roll.position
		previous_basis = player.bandage_hands.right_arm.basis
	print("Bandage forearm centreline clearance: ", minimum_arm_clearance)
	print("Bandage wrist gap / upper sleeve length: ", maximum_wrist_gap, " / ", maximum_upper_length)
	_check(maximum_wrist_gap < 0.001, "hand skeleton and forearm must meet at the anatomical wrist throughout the motion")
	_check(minimum_receiving_wrist_y > 0.85, "reference receiving hand must stay at the lower frame edge during winding")
	_check(maximum_upper_length < 0.53, "winding upper sleeve must not stretch into the foreground from an excessively low shoulder")
	_check(maximum_free_strip < 0.11, "reference passes must keep the roll close to the forearm")
	_check(receiving_arm_rotation > 0.15, "receiving arm must pronate and move with the winding hand")
	_check(player.bandage_hands.left_arm._active_visual.grip_amount > 0.75, "receiving hand must close into the reference fist")
	_check(minimum_arm_clearance > 0.10, "winding forearms must remain separated rather than pass through one another")
	_check(max_step < 0.05 and max_angle < 0.20, "continuous wrist/roll path must not snap between winding cycles")
	_check(is_equal_approx(player.bandage_hands.winding, TAU * 3.0), "bandage must wind three low reference passes")
	_check(player.bandage_hands.cloth.visible and player.bandage_hands.cloth.mesh.get_surface_count() == 1, "finished dressing must remain on the receiving arm through the return pose")
	player._update_viewmodel(0.1)
	_check(not player.is_bandage_motion_active() and player.weapon_pivot.visible, "completion must restore equipment")
	_check(player.health == healed and inventory.count_item("linen_bandage") == before - 1, "presentation must never apply a second heal or spend")
	player.apply_body_damage("left_arm", 20.0)
	var before_cancel: Transform3D = player.weapon_pivot.transform
	player.use_consumable("linen_bandage", inventory)
	player._update_viewmodel(0.2)
	player.prepare_for_inventory()
	_check(player.weapon_pivot.transform.is_equal_approx(before_cancel), "interruption must restore the captured equipment transform")
	_check(not player.is_bandage_motion_active(), "inventory/F2 preparation must clear both temporary hands and cloth")
	player.use_consumable("linen_bandage", inventory)
	player._set_combat_state(DungeonPlayer.CombatState.WINDUP)
	_check(not player.is_bandage_motion_active(), "combat must immediately release presentation ownership")
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	player.reset_body_health()
	_check(not player.use_consumable("linen_bandage", inventory).accepted and not player.is_bandage_motion_active(), "rejected full-health use must not animate")
	player.select_treatment_part("right_leg")
	player.apply_body_damage("right_leg", 10.0)
	inventory.add_item("linen_bandage", 1)
	_check(player.use_consumable("linen_bandage", inventory).accepted and not player.is_bandage_motion_active(), "other body targets retain existing treatment without an incorrect forearm motion")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode, "preview fixture must restore original expedition and cursor")
	for failure in failures: push_error(failure)
	print("BANDAGE MOTION TEST %s: stow/lift/tear/redraw, real consumption, 3 low wraps, continuous pose, pause, completion, interruption, isolation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
