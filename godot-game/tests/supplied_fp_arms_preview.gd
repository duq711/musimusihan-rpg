extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
var failures: Array[String]=[]
func _init() -> void: call_deferred("_run")
func _run() -> void:
	if DisplayServer.get_name()!="embedded":quit(2);return
	var tag:=OS.get_environment("FP_ARMS_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):quit(2);return
	var path:=ProjectSettings.globalize_path("res://artifacts/visual_qa/fp_arms/"+tag)
	if DirAccess.dir_exists_absolute(path):quit(2);return
	DirAccess.make_dir_recursive_absolute(path)
	root.gui_disable_input=true;root.physics_object_picking=false
	AudioServer.set_bus_mute(0,true)
	var before:=ExpeditionSession.capture_snapshot();var cursor:=Input.mouse_mode
	var sandbox:=root.get_node("TestRoomSandbox");sandbox.begin()
	var sources: Dictionary={}
	for file in ["tests/supplied_fp_arms_preview.gd","tests/player_arm_preview.gd","scripts/bandage_use_visuals.gd","scripts/splint_use_visuals.gd","scripts/player.gd","scripts/supplied_fp_arm.gd","scripts/player_arm_visual.gd","scripts/sword_long_grip_visual.gd","assets/3d/player/fp_arms/left.scn","assets/3d/player/fp_arms/right.scn"]: sources[file]=FileAccess.get_sha256("res://"+file)
	var captures: Array=[]
	var poses: Array = ["bandage","splint","bandage_finish","splint_finish"] if OS.get_environment("FP_ARMS_QA_SCOPE")=="treatments" else ["idle","sword_windup","sword_active","shield_guard","torch_safe_zone","bow_draw","two_hand","open_hands"]
	for pose: String in poses:
		var view:=PREVIEW.create_viewport();root.add_child(view)
		var f: Dictionary
		if pose.begins_with("bandage"): f=preload("res://tests/bandage_motion_preview.gd").create_fixture(view)
		elif pose.begins_with("splint"): f=preload("res://tests/splint_motion_preview.gd").create_fixture(view)
		else: f=PREVIEW.populate_viewport(view)
		var p: DungeonPlayer=f.player
		await physics_frame;await physics_frame
		if pose.begins_with("bandage") or pose.begins_with("splint"):
			var result:=p.begin_item_use("linen_bandage" if pose.begins_with("bandage") else "splint",f.inventory)
			if not result.accepted:failures.append("treatment rejected: "+pose)
			var steps:= (240 if pose.begins_with("bandage") else 324) if pose.ends_with("finish") else 150
			for step in steps:
				p._update_viewmodel(1.0/60.0)
				p.advance_item_use(1.0/60.0)
		elif pose in ["two_hand","open_hands"]:
			PREVIEW.configure_pose(f,"idle");p._sword_draw_elapsed=p.SWORD_DRAW_DURATION
			if pose=="two_hand":
				p.request_primary_weapon()
				for i in 72:p._update_viewmodel(1.0/60.0)
				p.begin_sword_attack("overhead");p.attack_release_requested=true
				for i in 14:p.advance_combat_state(1.0/60.0);p._update_viewmodel(1.0/60.0);p._resolve_active_attack()
			else:
				p.inventory_model.unequip("offhand");p.inventory_model.unequip("weapon");p.set_torch_enabled(false);p._torch_draw_elapsed=0
				p._suppress_automatic_torch_hand=true
				if not p.begin_finger_joint_review():failures.append("finger review rejected")
				p._update_viewmodel(.1)
		else:
			if not PREVIEW.configure_pose(f,pose):failures.append("pose rejected: "+pose)
			if not PREVIEW.inspect_pose(f,pose).passed:failures.append("pose state mismatch: "+pose)
		for i in 8:await process_frame
		RenderingServer.force_draw(false)
		var im:=view.get_texture().get_image()
		if im==null or im.is_empty() or im.save_png(path.path_join(pose+".png"))!=OK:failures.append("image failed: "+pose)
		captures.append({"pose":pose,"state":p.get_first_person_motion_snapshot()})
		p.cancel_timed_interaction();view.queue_free();await process_frame
	sandbox.finish()
	var preserved:=ExpeditionSession.capture_snapshot()==before and cursor==Input.mouse_mode
	if not preserved:failures.append("session/cursor changed")
	for file: String in sources:
		if sources[file]!=FileAccess.get_sha256("res://"+file):failures.append("source changed: "+file)
	var out:=FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"display":DisplayServer.get_name(),"session_cursor_preserved":preserved,"sources":sources,"captures":captures,"failures":failures},"\t"))
	for failure in failures:push_error(failure)
	print("SUPPLIED FP ARMS PREVIEW "+("PASS: " if failures.is_empty() else "FAIL: ")+path)
	quit(0 if failures.is_empty() else 1)
