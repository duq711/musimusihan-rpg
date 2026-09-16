extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const FP := preload("res://scripts/supplied_fp_arm.gd")
var failures: Array[String]=[]
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	var session := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var view := PREVIEW.create_viewport();root.add_child(view)
	var f := PREVIEW.populate_viewport(view)
	var player: DungeonPlayer=f.player
	await process_frame
	for arm: Node3D in [player._legacy_weapon_arm,player.weapon_arm,player.shield_arm,player.sword_support_arm,player.torch_arm,player.left_support_arm,player.right_relaxed_arm]:
		check("fp_arms" in str(arm.get_meta("source_model","")),"every production arm must use supplied FP arms")
		check(not arm.get("hand_meshes").is_empty() and not arm.get("arm_meshes").is_empty(),"real supplied hand and arm meshes must be present")
	for side in [-1,1]:
		var arm := FP.new();root.add_child(arm);check(arm.setup(side),"rig loads")
		check(arm.skeleton.get_bone_count()==20,"all twenty original deform joints retained per side")
		var bone := arm.skeleton.find_bone("index1")
		arm.set_grip(0);var before := arm.skeleton.get_bone_pose_rotation(bone)
		arm.set_grip(1);check(before.angle_to(arm.skeleton.get_bone_pose_rotation(bone))>.5,"finger bones actually deform between open and gripping")
		arm.fit_arm(Vector3(side*.1,-.1,.55),Vector3(0,0,.26))
		for part: MeshInstance3D in arm.arm_meshes+arm.hand_meshes:
			check(part.skin!=null and part.mesh.get_aabb().size.length()<1.0,"original skin and human-scale geometry retained")
		arm.queue_free()
	for pose: String in PREVIEW.POSE_IDS:
		check(PREVIEW.configure_pose(f,pose),"production pose config "+pose)
		check(PREVIEW.inspect_pose(f,pose).passed,"production pose behavior "+pose)
	player.cancel_timed_interaction()
	view.queue_free();await process_frame
	sandbox.finish()
	check(ExpeditionSession.capture_snapshot()==session and Input.mouse_mode==cursor,"original session and cursor preserved")
	for message in failures:push_error(message)
	print("SUPPLIED FP ARMS "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
