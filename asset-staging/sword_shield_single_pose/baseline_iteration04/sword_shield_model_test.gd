extends SceneTree
const SHIELD_PREVIEW := preload("res://tests/sword_shield_preview.gd")
const PREVIEW := preload("res://tests/first_person_motion_preview.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var fingerprint := PREVIEW.inventory_fingerprint(original.inventory)
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	await physics_frame
	var player := fixture.player as DungeonPlayer
	if not PREVIEW.configure_pose(fixture, "shield_guard"): failures.append("Cannot equip and guard with actual sword/shield")
	for arm in [player.weapon_arm, player.shield_arm]:
		if not arm.get_meta("continuous_skin", false): failures.append("Production arm must use continuous anatomical skin")
		var rig := arm.get("skeleton") as Skeleton3D
		if rig == null or rig.get_bone_count() != 16: failures.append("Missing real sixteen-bone hand skeleton")
		else:
			var side := int(arm.get_meta("hand_side"))
			if rig.get_bone_global_pose(rig.find_bone("thumb0")).origin.x * side < 0.01: failures.append("Anatomical thumb side must match the actual left/right hand, not a mislabeled mirror")
			for name in ["index0", "middle1", "thumb1"]:
				if rig.get_bone_pose_rotation(rig.find_bone(name)).is_equal_approx(Quaternion.IDENTITY): failures.append("Real joints did not curl: " + name)
		if arm.get("_forearm") == null or arm.get("_upper_arm") == null: failures.append("Both imported sleeve joints must be fitted, including the right-hand source")
		if arm.get("_cuff") == null: failures.append("The flexible anatomical cuff must be fitted with its real forearm")
		for mesh: MeshInstance3D in arm.get("hand_meshes"):
			if mesh.skin == null or mesh.skin.get_bind_count() != 16: failures.append("Visible continuous hand must really deform with its sixteen-bone skin")
	var top := player.shield_model.find_child("RearGripTop", true, false) as Node3D
	var bottom := player.shield_model.find_child("RearGripBottom", true, false) as Node3D
	var grip_axis := (top.global_position - bottom.global_position).normalized()
	if (-player.shield_arm.global_basis.x).dot(grip_axis) < 0.99: failures.append("Actual knuckle row must align with the modeled strap, including its slant")
	if player.shield_arm.global_basis.y.dot(player.shield_arm.global_position.direction_to(player.camera.global_position)) < 0.25: failures.append("Shield guard must expose the anatomical hand back toward the viewer")
	# The new sword grip shows the curled finger edge in three-quarter view.
	# Requiring its dorsal face to point at the camera hid that finger row.
	var sword_hand_facing := player.weapon_arm.global_basis.y.dot(player.weapon_arm.global_position.direction_to(player.camera.global_position))
	if absf(sword_hand_facing) > 0.5: failures.append("Sword guard must retain a readable three-quarter grip rather than a flat palm/back")
	if player.weapon_arm.global_basis.x.dot(player.weapon_pivot.global_basis.y) < 0.99: failures.append("Sword knuckle row must remain aligned with its actual handle")
	var cuff_clearance := (player.shield_arm.global_position-player.shield_pivot.global_position).dot(player.shield_pivot.global_basis.z)
	if cuff_clearance < 0.04: failures.append("The anatomical cuff needs real clearance behind the shield board: " + str(cuff_clearance))
	if player.sword_blade == null or player.sword_blade.mesh.get_aabb().size.x > 0.08: failures.append("Visible modeled blade must have reference-like slender proportions")
	if not bool(player.receive_attack(18, player.global_position + Vector3(0,0,-2)).get("blocked", false)): failures.append("Production shield did not block")
	var poses := {}
	for id in SHIELD_PREVIEW.POSES:
		if not SHIELD_PREVIEW.configure_pose(fixture, id): failures.append("Failed actual reference pose " + id)
		poses[id] = player.weapon_pivot.transform
		if player.get_first_person_motion_snapshot().visible_arm_count != 2: failures.append("Reference pose left an extra arm visible")
		var forearm := player.shield_arm.get("_forearm") as Node3D
		var elbow := forearm.to_global(Vector3(0,0,0.26))
		if player.camera.to_local(elbow).z > -0.05: failures.append("Shield elbow crossed the camera, exaggerating forearm perspective: " + id)
	if poses.guard.is_equal_approx(poses.impact): failures.append("Actual shield impact must raise the supporting sword")
	SHIELD_PREVIEW.configure_pose(fixture, "idle")
	fixture.sequence_time = 0.0
	fixture.sequence_events = {}
	var phases := {}
	for frame in 52:
		if not SHIELD_PREVIEW.advance_sequence(fixture, 0.05): failures.append("Real guard did not absorb the sequence attack")
		phases[player.combat_state] = true
		var forearm := player.shield_arm.get("_forearm") as Node3D
		if player.camera.to_local(forearm.to_global(Vector3(0,0,0.26))).z > -0.05: failures.append("Continuous shield movement brought the elbow through the camera at frame " + str(frame))
	if fixture.sequence_events.size() != 4 or not phases.has(player.CombatState.ACTIVE) or not phases.has(player.CombatState.RECOVERY): failures.append("Continuous production clock must play guard, impact, attack and recovery")
	if not is_equal_approx(player.health, player.MAX_HEALTH - 4.0): failures.append("Normal shield guard must retain its actual four-point chip damage")
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	if ExpeditionSession.capture_snapshot() != original or fingerprint != PREVIEW.inventory_fingerprint(original.inventory) or cursor != Input.mouse_mode: failures.append("Model and sequence checks changed the original expedition or cursor")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD MODEL ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
