extends SceneTree
const BASE = preload("res://tests/player_arm_preview.gd")
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures.append(message)
func key(p: Vector3) -> String:
	return str(roundi(p.x*100000))+","+str(roundi(p.y*100000))+","+str(roundi(p.z*100000))
func run():
	var saved=ExpeditionSession.capture_snapshot(); var mouse=Input.mouse_mode
	var sandbox=root.get_node("TestRoomSandbox"); sandbox.begin()
	var viewport=BASE.create_viewport();root.add_child(viewport)
	var f=BASE.populate_viewport(viewport);var p=f.player
	await physics_frame;await physics_frame
	check(BASE.configure_pose(f,"torch_safe_zone"),"real torch fixture")
	check(p.torch_arm.visible and not p.left_support_arm.visible and not p.shield_arm.visible,"one visible left hand owns torch")
	check(p.torch_arm.detailed_visual.get_meta("source_model","")=="res://assets/3d/player/hands_detailed/left_hand_torch.glb","torch owns separate corrected left skin")
	check(p.right_relaxed_arm.detailed_visual.get_meta("source_model","")=="res://assets/3d/player/hands_detailed/right_hand_detailed.glb","right hand keeps original source")
	check(p.torch_pivot.get_node_or_null("WoodenTorchVisual") != null,"supplied wooden torch installed")
	check(p.torch_flame.get_node_or_null("ClothFlame_0") != null,"Unity flipbook flame installed")
	check(is_equal_approx(p.torch_flame.position.y, p.TORCH_FIRE.CLOTH_BASE),"oil flame starts at bottom of cloth")
	check(p.torch_flame.find_children("*","MeshInstance3D",false,false).size()==11,"eight cloth emitters plus three upper flame planes")
	for card in p.torch_flame.get_children():
		if not card is MeshInstance3D:continue
		check(card.material_override.get_shader_parameter("flame_atlas")==p.TORCH_FIRE.ATLAS,"Unity atlas drives every flame")
		if str(card.name).begins_with("ClothFlame_"):
			check(is_equal_approx(card.position.y-card.mesh.size.y*.5,0.0),"cloth flame anchored at wrapping base")
			check(card.mesh.size.y>p.TORCH_FIRE.CLOTH_TOP-p.TORCH_FIRE.CLOTH_BASE,"cloth flame spans entire wrapping")
	audit_flame_flow(p)
	var torch_transform: Transform3D=p.torch_pivot.transform
	var expected: Transform3D=p.torch_arm.transform
	for profile in ["greybox","detailed","original"]:
		check(p.set_hands_visual_profile(profile),"profile available")
		p._update_character_arms()
		check(p.torch_pivot.transform==torch_transform,"hand profile cannot move shaft")
		if profile!="greybox":check(p.torch_arm.transform.is_equal_approx(expected),"authored torch frame restored")
	p.torch_arm.reset_pose();p._update_character_arms()
	check(is_equal_approx(p.torch_arm.get_joint_snapshot().angles_radians.thumb.x, p.TORCH_GRIP.JOINT_ANGLES.thumb.x),"torch restores authored thumb root after reset")
	for speed in [0.,p.WALK_SPEED,p.SPRINT_SPEED]:
		p.velocity=Vector3(0,0,-speed)
		for i in 18:p._update_viewmodel(1./60.)
		check(p.torch_arm.transform.is_equal_approx(expected),"shaft-relative grip locked during locomotion")
		check(p.torch_arm.transform.is_equal_approx(p.TORCH_GRIP.ARM_TRANSFORM),"manual Blender arm placement preserved")
		var angle: float=p.get_first_person_motion_snapshot().joint_landmarks.torch.wrist_angle_degrees
		print("TORCH WRIST angle_degrees=",angle)
		check(angle<25.0,"forearm and hand longitudinal axes stay within 25 degrees during locomotion")
	p.set_torch_enabled(false);p._update_character_arms()
	check(not p.torch_arm.visible and p.left_support_arm.visible,"extinguish restores free left hand")
	check(not p.torch_flame.visible,"extinguish hides flipbook flame")
	p.set_torch_enabled(true);p._update_character_arms()
	check(p.torch_arm.visible and not p.left_support_arm.visible,"relight restores one torch hand")
	check(p.torch_flame.visible,"relight restores flipbook flame")
	var utility=p.inventory_model.equipment.get("utility", "")
	p.inventory_model.equipment["utility"]="";p._refresh_hand_visibility();p._update_viewmodel(.2)
	check(not p.torch_arm.visible,"unequipping utility releases torch hand")
	p.inventory_model.equipment["utility"]=utility;p._refresh_hand_visibility()
	for i in 30:p._update_viewmodel(1./60.)
	check(p.torch_arm.visible and p.torch_arm.transform.is_equal_approx(expected),"equipping utility restores authored grip through transition")
	check(p.camera.to_local(p.get_first_person_motion_snapshot().hand_contacts.free_right.target).y < -0.55,"relaxed right hand lowered below view")
	audit_manual_pose(p)
	viewport.queue_free();await process_frame;sandbox.finish()
	check(saved==ExpeditionSession.capture_snapshot() and mouse==Input.mouse_mode,"fixture restores actual expedition and cursor")
	await audit_testroom()
	if failures.is_empty():print("MANUAL TORCH POSE PASS: exact bone rotations, arm placement, motion, reset, equip and testroom restoration")
	else:
		for e in failures:push_error(e)
	quit(0 if failures.is_empty() else 1)
func audit_testroom():
	var snapshot=ExpeditionSession.capture_snapshot();var mouse=Input.mouse_mode
	var room=(load("res://test_room.tscn") as PackedScene).instantiate();root.add_child(room);current_scene=room
	await process_frame
	for i in 2:
		room.run_feature("motion_torch");room.player.set_physics_process(false)
		await physics_frame;await physics_frame
		room.player._update_character_arms()
		check(room.player.torch_arm.visible and room.player.get_first_person_motion_snapshot().left_hand_role=="torch","testroom entry runs actual torch grip")
		audit_flame_flow(room.player)
		check(room.inventory!=snapshot.get("inventory"),"testroom inventory isolated")
		room._show_test_panel()
	room.queue_free();await process_frame
	root.get_node("TestRoomSandbox").finish();paused=false
	check(ExpeditionSession.capture_snapshot()==snapshot and Input.mouse_mode==mouse,"testroom restores original state")

func audit_manual_pose(p):
	var adapter=p.torch_arm.detailed_visual
	for name in p.TORCH_GRIP.MANUAL_ROTATIONS:
		var index=adapter.skeleton.find_bone(name)
		check(index>=0,"manual bone exists: "+name)
		if index<0:continue
		var expected:Quaternion=(adapter._rests[index]*p.TORCH_GRIP.MANUAL_ROTATIONS[name]).normalized()
		check(absf(expected.dot(adapter.skeleton.get_bone_pose_rotation(index)))>0.999999,"Blender rotation matches: "+name)

func audit_flame_flow(p):
	check(p.torch_flame.get_node("TipFlame_0").mesh.subdivide_depth >= 20, "flame has vertical segments for billowing")
	var old_velocity: Vector3 = p.velocity
	var old_rotation: Vector3 = p.rotation
	var old_enabled: bool = p.torch_enabled
	var old_frame: Transform3D = p.torch_pivot.transform
	check(is_equal_approx(p.torch_flame.get_node("TipFlame_0").mesh.size.y, 0.90), "enlarged upper flame")
	for yaw in [0.0, 1.4]:
		p.rotation.y = yaw
		var right: Vector3 = p.camera.global_basis.x
		right.y = 0.0
		right = right.normalized()
		for direction in [-1.0, 1.0]:
			p.velocity = right * p.WALK_SPEED * direction
			for i in 60: p._update_torch(1.0/60.0)
			var lean: Vector3 = p.torch_flame.get_meta("movement_lean")
			check(lean.dot(right) * direction > 0.2, "flame follows lateral movement even after turning")
			check(lean.length() <= 0.48001, "flame lean bounded")
			for card in p.torch_flame.get_children():
				if not card is MeshInstance3D: continue
				var local_lean: Vector3 = card.material_override.get_shader_parameter("movement_lean")
				check((card.global_basis * local_lean).is_equal_approx(lean), "crossed flame cards share world direction")
		var before: Vector3 = p.torch_flame.get_meta("movement_lean")
		paused = true
		p.velocity = -p.velocity
		p._update_torch(0.5)
		check(p.torch_flame.get_meta("movement_lean") == before, "pause freezes movement response")
		paused = false
		p.velocity = Vector3.ZERO
		p._update_torch(1.0/60.0)
		check(p.torch_flame.get_meta("movement_lean").length() > 0.01, "stop blends rather than snaps")
		p.set_torch_enabled(false)
		for i in 120: p._update_torch(1.0/60.0)
		p.set_torch_enabled(true)
		check(p.torch_flame.get_meta("movement_lean").length() < 0.0001, "stop and relight clear old lean")
	p.rotation = old_rotation
	p.velocity = old_velocity
	p.set_torch_enabled(old_enabled)
	check(p.torch_pivot.transform == old_frame, "flame flow cannot rotate hand or shaft")
