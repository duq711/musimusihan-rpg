extends SceneTree

const ARM := preload("res://scripts/greybox_arm_visual.gd")
const HAND_PREVIEW := preload("res://tests/player_hands_detailed_preview.gd")
const WRIST_AUDIT := preload("res://tests/player_hands_detailed_test.gd").WristGeometryAudit
const PREVIEW := preload("res://tests/player_finger_joints_preview.gd")
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
var failures: Array[String] = []
var _sources: Dictionary = {}
var _wrist_auditor := WRIST_AUDIT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_independent_joints_and_correctives()
	await _test_gameplay_and_review()
	await _test_room_lifecycle()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER FINGER JOINTS %s: thirty independent local joints, actual localized morph and weighted skin, rigid nails, limits/reset, bow/chest linkage, real controls and isolated F2/repeat/switch/reset/exit" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_independent_joints_and_correctives() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var contents := HAND_PREVIEW.inventory_contents(snapshot.get("inventory"))
	var mouse := Input.mouse_mode
	var stage := Node3D.new()
	root.add_child(stage)
	stage.transform = Transform3D(Basis(Vector3.UP, 0.27), Vector3(0.3, 0.8, -1.0))
	for side in [-1, 1]:
		var arm := ARM.new()
		stage.add_child(arm)
		_check(arm.setup(side, "detailed"), "joint fixture needs the actual detailed model for side " + str(side))
		var skeleton := arm.skeleton as Skeleton3D
		if skeleton == null:
			_check(false, "detailed model has no real skeleton")
			continue
		_check(skeleton.get_bone_count() == 16, "correctives must preserve the original sixteen deform bones")
		arm.reset_pose()
		var rest := _bone_poses(skeleton)
		var global_rest := _global_bones(skeleton)
		var wrist := arm.global_transform
		var open_skin := _skin_points(arm)
		var all_sources := arm.get_source_meshes()
		var report: Dictionary = arm.get_joint_snapshot()
		_check(report.ready and report.corrective_available and report.morph_count == 15, "both detailed rigs need all fifteen usable joint correctives")
		for digit: String in DIGITS:
			var corrective_centers: Array[Vector3] = []
			for joint in 3:
				arm.reset_pose()
				var context := "%s/%s%d" % [side, digit, joint]
				var bone := skeleton.find_bone(digit + str(joint))
				var limit_degrees: float = [60.0, 70.0, 80.0][joint] if digit == "thumb" else [90.0, 110.0, 80.0][joint]
				var limit := deg_to_rad(limit_degrees)
				_check(is_equal_approx(float(report.limits_radians[digit][joint]), limit), "joint limits must match their intended anatomical range: " + context)
				var center := _audit_corrective(arm, digit, joint, context)
				for previous: Vector3 in corrective_centers:
					_check(center.distance_to(previous) > 0.002, "different joints must affect distinct skin sections: " + context)
				corrective_centers.append(center)
				var nail_before := _nail_local_points(arm, digit)
				_check(arm.set_joint_flexion(digit, joint, 0.5), "valid half flexion must be accepted: " + context)
				var halfway: Dictionary = arm.get_joint_snapshot()
				_check(is_equal_approx(float(halfway.flexion[digit][joint]), 0.5) and is_equal_approx(absf(float(halfway.angles_radians[digit][joint])), limit * 0.5), "half flexion must produce a real half-angle pose: " + context)
				_check(is_equal_approx(skeleton.get_bone_pose_rotation(bone).angle_to(rest[bone].basis.get_rotation_quaternion()), limit * 0.5), "reported half flexion must match the actual bone rotation: " + context)
				_check(arm.set_joint_flexion(digit, joint, 1.0), "full flexion must be accepted: " + context)
				var actual := _bone_poses(skeleton)
				for other in skeleton.get_bone_count():
					if other == bone:
						_check(is_equal_approx(actual[other].basis.get_rotation_quaternion().angle_to(rest[other].basis.get_rotation_quaternion()), limit), "full flexion must rotate precisely its own local joint: " + context)
					else:
						_check(actual[other].is_equal_approx(rest[other]), "other local joints, including downstream child angles, must remain unchanged: " + context + "/" + skeleton.get_bone_name(other))
				var global_pose := _global_bones(skeleton)
				for other in skeleton.get_bone_count():
					if not skeleton.get_bone_name(other).begins_with(digit):
						_check(global_pose[other].is_equal_approx(global_rest[other]), "independent flexion must preserve the wrist and every other digit in global skeleton space: " + context)
				var full: Dictionary = arm.get_joint_snapshot()
				var shape_name := "Joint_%s_%d" % [digit, joint]
				_check(is_equal_approx(float(full.morph_values.get(shape_name, -1.0)), 1.0), "the actual corrected joint must reach its full morph weight: " + context)
				for other_shape: String in full.morph_values:
					if other_shape != shape_name: _check(is_zero_approx(float(full.morph_values[other_shape])), "independent flexion must not activate unrelated shape keys: " + context)
				var posed := _skin_points(arm)
				_check(open_skin.size() > 100 and _max_displacement(open_skin, posed) > 0.001, "independent flexion must move actual weighted skin: " + context)
				_check(_max_displacement(posed, _skin_points(arm, false)) > 0.000005, "the runtime corrective must contribute actual surface displacement beyond bone-only skinning: " + context)
				_check(_max_displacement(nail_before, _nail_local_points(arm, digit)) < 0.00002, "nail geometry must stay rigidly attached to its distal bone: " + context)
				_check(arm.global_transform.is_equal_approx(wrist), "joint controls must never move the equipment wrist frame: " + context)
				_check(arm.set_joint_flexion(digit, joint, 3.0) and _bone_poses(skeleton) == actual, "finite values above one must clamp at the full joint limit: " + context)
				var protected_state: Dictionary = arm.get_joint_snapshot()
				_check(not arm.set_joint_flexion(digit, joint, NAN) and not arm.set_joint_flexion(digit, joint, INF) and not arm.set_joint_flexion("unknown", joint, 0.5) and not arm.set_joint_flexion(digit, -1, 0.5) and not arm.set_joint_flexion(digit, 3, 0.5), "invalid or nonfinite joint commands must be rejected: " + context)
				_check(arm.get_joint_snapshot() == protected_state and _bone_poses(skeleton) == actual, "rejected joint commands must leave bones and correction weights untouched: " + context)
				_check(arm.set_joint_flexion(digit, joint, -2.0), "finite values below zero must clamp to open: " + context)
				_check(_poses_equal(_bone_poses(skeleton), rest) and _max_displacement(open_skin, _skin_points(arm)) < 0.00001, "opening an individual joint must restore actual source skin: " + context)
		_check(arm.set_digit_flexion("index", Vector3(0.2, 0.4, 0.6)) and (arm.get_joint_snapshot().flexion.index as Vector3).is_equal_approx(Vector3(0.2, 0.4, 0.6)), "a digit command must preserve three independent flexion amounts")
		var before_bad_digit: Dictionary = arm.get_joint_snapshot()
		_check(not arm.set_digit_flexion("index", Vector3(0.3, NAN, 0.7)) and arm.get_joint_snapshot() == before_bad_digit, "a nonfinite digit vector must be rejected atomically without partial joint edits")
		arm.set_grip(1.0)
		arm.reset_pose()
		_check(_bone_poses(skeleton) == rest and _max_displacement(open_skin, _skin_points(arm)) < 0.00001 and arm.get_source_meshes() == all_sources, "reset must clear all thirty controls without replacing or mutating source resources")
		var gray := ARM.new()
		stage.add_child(gray)
		_check(gray.setup(side) and gray.set_joint_flexion("index", 1, 0.5), "preserved greybox must retain the same independent joint API")
		_check(int(gray.get_joint_snapshot().morph_count) == 0 and not bool(gray.get_joint_snapshot().corrective_available), "greybox must not pretend to contain the detailed corrective geometry")
	stage.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot and HAND_PREVIEW.inventory_contents(snapshot.get("inventory")) == contents and Input.mouse_mode == mouse, "isolated joint and geometry checks must preserve expedition, nested inventory and cursor")


func _audit_corrective(arm: Node3D, digit: String, joint: int, context: String) -> Vector3:
	var skeleton := arm.get("skeleton") as Skeleton3D
	var bone := skeleton.find_bone(digit + str(joint))
	var joint_frame := skeleton.get_bone_global_rest(bone)
	var section_min := Vector3(INF, INF, INF)
	var section_max := Vector3(-INF, -INF, -INF)
	var section_samples := 0
	var affected := PackedVector3Array()
	var centroid := Vector3.ZERO
	var changed := 0
	var maximum := 0.0
	var farthest := 0.0
	var axial_extent := 0.0
	var wrong_digit := 0
	var unrelated_maximum := 0.0
	var mixed_vertices_changed := 0
	for mesh in _meshes(arm):
		var index := mesh.find_blend_shape_by_name("Joint_%s_%d" % [digit, joint])
		if index < 0: continue
		var source := _mesh_source(mesh, skeleton)
		var to_skeleton := skeleton.global_transform.affine_inverse() * mesh.global_transform
		var to_joint := joint_frame.affine_inverse() * to_skeleton
		for surface: Dictionary in source.surfaces:
			var vertices: PackedVector3Array = surface.vertices
			var shape: PackedVector3Array = surface.shapes[index]
			_check(shape.size() == vertices.size(), "corrective buffer must cover the actual surface vertices: " + context)
			if shape.size() != vertices.size(): continue
			for vertex in vertices.size():
				var delta := shape[vertex] - vertices[vertex] if source.normalized else shape[vertex]
				var point := to_joint * vertices[vertex]
				var dominant := -1
				var dominant_weight := 0.0
				var has_digit_influence := false
				for influence in int(surface.stride):
					var entry := vertex * int(surface.stride) + influence
					var weight := float(surface.weights[entry])
					var named_bone: int = source.bones[surface.bones[entry]]
					if weight > 0.0 and skeleton.get_bone_name(named_bone).begins_with(digit): has_digit_influence = true
					if weight > dominant_weight:
						dominant_weight = weight
						dominant = named_bone
				var owned := dominant >= 0 and skeleton.get_bone_name(dominant).begins_with(digit)
				if owned and absf(point.y) < 0.004 and not str(surface.material_name).begins_with("Detailed_Trim"):
					section_min = section_min.min(point)
					section_max = section_max.max(point)
					section_samples += 1
				# Skin, glove and stitching can share influences at finger borders.
				# Check actual named weights; an unrelated vertex must stay unchanged.
				if not has_digit_influence:
					unrelated_maximum = maxf(unrelated_maximum, delta.length())
					if delta != Vector3.ZERO: wrong_digit += 1
				elif not owned and delta.length() >= 0.0000001:
					mixed_vertices_changed += 1
				if delta.length() < 0.000001: continue
				changed += 1
				maximum = maxf(maximum, delta.length())
				affected.append(point)
				centroid += joint_frame * point
	# Authored thumb pivots are offset from the actual finger skin. Measure
	# locality around the owned skin cross-section at the joint plane, while
	# retaining a separate axial bound so a remote skin patch cannot pass.
	var section_center := (section_min + section_max) * 0.5
	section_center.y = 0.0
	for point: Vector3 in affected:
		farthest = maxf(farthest, point.distance_to(section_center))
		axial_extent = maxf(axial_extent, absf(point.y))
	# The proportion map preserves all original corrective support vertices.
	# Its weighted skin map and remapped bone axes project middle1/ring1 support
	# to 14.299/14.669 mm; only those two joint planes need a 15 mm bound.
	var axial_limit := 0.015 if joint == 1 and digit in ["middle", "ring"] else 0.0142
	if OS.get_environment("PLAYER_FINGER_JOINTS_QA_DIAGNOSTIC") == "1":
		print("JOINT GEOMETRY DIAGNOSTIC: " + JSON.stringify({"context": context, "changed_vertices": changed, "maximum_delta_m": maximum, "skin_section_samples": section_samples, "skin_section_radius_m": farthest, "axial_extent_m": axial_extent, "axial_limit_m": axial_limit, "unrelated_vertices_changed": wrong_digit, "unrelated_maximum_delta_m": unrelated_maximum, "mixed_vertices_changed": mixed_vertices_changed}))
	_check(changed >= 5 and maximum > 0.00001 and maximum < 0.0015, "each joint must have real, small corrective vertex deltas: " + context + " changed=" + str(changed) + " max=" + str(maximum))
	_check(section_samples >= 8 and farthest < 0.04 and axial_extent < axial_limit and wrong_digit == 0, "corrective geometry must stay near its skin joint and preserve vertices with no target-digit weight: " + context + " radius=" + str(farthest) + " axial=" + str(axial_extent) + " axial_limit=" + str(axial_limit) + " unrelated=" + str(wrong_digit) + " unrelated_max=" + str(unrelated_maximum))
	return centroid / float(maxi(1, changed))


func _test_gameplay_and_review() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var contents := HAND_PREVIEW.inventory_contents(snapshot.get("inventory"))
	var mouse := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	await physics_frame
	await physics_frame
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "joint preview must use an isolated, silent world without external input")
	for pose: String in PREVIEW.POSE_IDS:
		_check(PREVIEW.configure_pose(fixture, pose), "preview must configure the actual joint/gameplay state: " + pose)
		_check(bool(PREVIEW.inspect_pose(fixture, pose).passed), "preview must inspect the actual joint/gameplay state: " + pose)
		if pose in ["open", "palm", "wrist_side", "fist"]:
			for wrapper: Node3D in [player.left_support_arm, player.right_relaxed_arm]:
				failures.append_array(_wrist_auditor.inspect(wrapper.get("detailed_visual"), "joint review/" + pose + "/" + str(wrapper.name)))
		if pose in ["bow_draw", "chest_touch", "chest_lift"]:
			var arms: Array = [player._legacy_weapon_arm.detailed_visual] if pose == "bow_draw" else [player.chest_hands._arms[-1].detailed_visual, player.chest_hands._arms[1].detailed_visual]
			for arm: Node3D in arms:
				var report: Dictionary = arm.get_joint_snapshot()
				var positive := 0
				for value in report.morph_values.values():
					if float(value) > 0.001: positive += 1
				_check(positive >= 3 and _max_displacement(_skin_points(arm), _skin_points(arm, false)) > 0.000001, "actual bow/chest poses must drive multiple real corrective surfaces: " + pose)
	_check(PREVIEW.configure_pose(fixture, "open"), "full sequence audit must start from the real open review pose")
	var sequence_controls: Control = fixture.controls
	sequence_controls.sequence_button.pressed.emit()
	var previous_frame := 0
	for step in 16:
		var frame := step * 15 + 4 if step < 15 else 225
		sequence_controls.advance_sequence(float(frame - previous_frame) / 15.0)
		_check(bool(PREVIEW.inspect_sequence(fixture, frame).passed), "the production sequence and actual slider states must reach every independent joint in order: step " + str(step))
		previous_frame = frame
	player.end_finger_joint_review()
	_check(HAND_PREVIEW.configure_pose(fixture, "free_hands") and player.set_hands_visual_profile("greybox") and player.begin_finger_joint_review(), "review must enter from the preserved greybox profile without changing inventory")
	_check(player.hands_visual_profile == "detailed" and player.set_review_joint_flexion("ring", 2, 0.4, -1), "review must bind its actual detailed model and selected-side joint override")
	var protected_review: Dictionary = player.get_finger_joint_review_snapshot()
	_check(not player.set_review_joint_flexion("ring", 2, NAN, -1) and not player.set_review_joint_flexion("ring", 2, 0.7, 2) and player.get_finger_joint_review_snapshot() == protected_review, "invalid review input must preserve current values and actual posed hands")
	player.end_finger_joint_review()
	_check(player.hands_visual_profile == "greybox" and not player.get_finger_joint_review_snapshot().active, "ending review must restore the exact previously selected greybox profile")
	_check(player.set_hands_visual_profile("original") and player.begin_finger_joint_review(), "review must also enter from the original presentation")
	player.end_finger_joint_review()
	_check(player.hands_visual_profile == "original" and not player.get_finger_joint_review_snapshot().active, "review must restore the original appearance without retaining overrides")
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot and HAND_PREVIEW.inventory_contents(snapshot.get("inventory")) == contents and Input.mouse_mode == mouse, "preview lifecycle must preserve original inventory, expedition and cursor")


func _test_room_lifecycle() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	var sword := original.get_equipment_instance("weapon")
	sword["uid"] = "finger_joint_original"
	sword["smithing"] = {"quality": 73.0, "runes": ["ember_rune"], "drill_progress": 0.4}
	ExpeditionSession.crowns = 727
	ExpeditionSession.hunger = 46.5
	ExpeditionSession.thirst = 36.25
	ExpeditionSession.stress = 29.0
	var saved := ExpeditionSession.capture_snapshot()
	var contents := HAND_PREVIEW.inventory_contents(original)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_finger_joints")
	_check(entries.size() == 1 and entries[0].action == "player_finger_joints" and entries[0].category == "기본", "independent finger joints need one executable testroom feature")
	for iteration in 2:
		room.run_feature("player_finger_joints")
		var player := room.player as DungeonPlayer
		player.set_physics_process(false)
		await process_frame
		var controls: Control = room.finger_joint_controls
		_check(is_instance_valid(controls) and controls.visible and paused and not room.panel_open and player.get_finger_joint_review_snapshot().active, "joint feature must show real controls over a paused gameplay scene")
		if not is_instance_valid(controls): continue
		_check(controls.sliders.size() == 15, "joint controls must expose every digit and all three joints")
		_check(controls.view_selector.item_count == 3 and controls.view_selector.selected == 0 and player.get_finger_joint_review_snapshot().view == "dorsal", "each trial must expose dorsal, palm and wrist-side views and begin in the original dorsal view")
		var hunger := ExpeditionSession.hunger
		var bag_contents := HAND_PREVIEW.inventory_contents(room.inventory)
		controls.side_selector.select(1)
		controls.side_selector.item_selected.emit(1)
		controls.preset_open_button.pressed.emit()
		(controls.sliders["index:1"] as Range).value = 0.65
		var report: Dictionary = player.get_finger_joint_review_snapshot()
		_check(is_equal_approx(float(report.values[-1].index.y), 0.65) and is_zero_approx(float(report.values[1].index.y)), "the actual selected-side slider signal must affect only the chosen middle joint")
		var skeleton: Skeleton3D = player.left_support_arm.detailed_visual.skeleton
		var actual := skeleton.get_bone_pose_rotation(skeleton.find_bone("index1"))
		player._update_character_arms()
		_check(actual.is_equal_approx(skeleton.get_bone_pose_rotation(skeleton.find_bone("index1"))), "gameplay updates must preserve the live independent-joint review override")
		var before_view: Dictionary = player.get_finger_joint_review_snapshot()
		controls.view_selector.select(1)
		controls.view_selector.item_selected.emit(1)
		_check(player.get_finger_joint_review_snapshot().view == "palm" and player.get_finger_joint_review_snapshot().values == before_view.values, "the actual palm-view selector must rotate presentation while preserving all joint values")
		var palm_transforms := [player.left_support_arm.global_transform, player.right_relaxed_arm.global_transform]
		var camera_before := player.camera.global_transform
		var finger_poses := _bone_poses(skeleton)
		controls.view_selector.select(2)
		controls.view_selector.item_selected.emit(2)
		_check(player.get_finger_joint_review_snapshot().view == "wrist_side" and player.get_finger_joint_review_snapshot().values == before_view.values and _poses_equal(_bone_poses(skeleton), finger_poses), "the actual wrist-side selector must preserve every flexion value and actual local finger pose")
		_check(not player.left_support_arm.global_transform.is_equal_approx(palm_transforms[0]) and not player.right_relaxed_arm.global_transform.is_equal_approx(palm_transforms[1]) and player.camera.global_transform.is_equal_approx(camera_before), "wrist-side inspection must change both real arm presentations without moving the gameplay camera")
		controls.side_selector.select(0)
		controls.side_selector.item_selected.emit(0)
		controls.preset_fist_button.pressed.emit()
		report = player.get_finger_joint_review_snapshot()
		for side in [-1, 1]:
			for digit: String in DIGITS: _check((report.values[side][digit] as Vector3).is_equal_approx(Vector3.ONE), "the actual fist preset must close all fifteen joints on both hands")
		controls.preset_open_button.pressed.emit()
		controls.sequence_button.pressed.emit()
		controls.advance_sequence(0.4)
		var sequence_a: Dictionary = player.get_finger_joint_review_snapshot()
		controls.advance_sequence(0.75)
		var sequence_b: Dictionary = player.get_finger_joint_review_snapshot()
		_check(sequence_a.values != sequence_b.values and sequence_a.active and sequence_b.active, "the actual sequence button and clock must animate independent joint values")
		for side in [-1, 1]:
			_check(_active_joint_count(sequence_a.values[side]) == 1 and _active_joint_count(sequence_b.values[side]) == 1, "sequential review must flex one joint at a time per hand")
		await create_timer(0.03, true).timeout
		_check(is_equal_approx(ExpeditionSession.hunger, hunger) and HAND_PREVIEW.inventory_contents(room.inventory) == bag_contents, "joint UI manipulation and its sequence must leave paused survival and inventory untouched")
		var view_rect := root.get_visible_rect()
		_check(view_rect.encloses(controls.close_button.get_global_rect()) and view_rect.encloses(controls.preset_fist_button.get_global_rect()), "the real close and preset controls must fit inside the viewport")
		_check_joint_control_visibility(controls, view_rect)
		await _press_f2()
		_check(paused and room.panel_open and not player.get_finger_joint_review_snapshot().active and not is_instance_valid(room.finger_joint_controls), "F2 must close joint controls and release overrides into the paused test menu")
		_check(player.get_finger_joint_review_snapshot().view == "dorsal", "F2 must also clear the temporary wrist-side inspection view")
		_check(sandbox.saved_session == saved and HAND_PREVIEW.inventory_contents(original) == contents, "repeated joint trials must preserve original nested inventory and expedition")
	room.run_feature("player_finger_joints")
	room.finger_joint_controls.close_button.pressed.emit()
	await process_frame
	_check(room.panel_open and not room.player.get_finger_joint_review_snapshot().active, "the actual close button must release joint overrides and return to the menu")
	room.run_feature("player_finger_joints")
	room.run_feature("player_hands_greybox")
	_check(not room.player.get_finger_joint_review_snapshot().active and room.player.hands_visual_profile == "greybox" and not is_instance_valid(room.finger_joint_controls), "another feature must clear controls and allow the original greybox comparison")
	await _press_f2()
	room.run_feature("player_finger_joints")
	room.finger_joint_controls.view_selector.select(2)
	room.finger_joint_controls.view_selector.item_selected.emit(2)
	var previous_inventory: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != previous_inventory and room.player.hands_visual_profile == "original" and not room.player.get_finger_joint_review_snapshot().active and paused and room.panel_open and not is_instance_valid(room.finger_joint_controls), "reset must clear joint overrides/UI and replace only the isolated loadout")
	room.run_feature("player_finger_joints")
	_check(room.player.get_finger_joint_review_snapshot().active and room.player.get_finger_joint_review_snapshot().view == "dorsal" and room.finger_joint_controls.view_selector.selected == 0, "independent joint feature must remain executable in its default view after reset")
	room.finger_joint_controls.view_selector.select(2)
	room.finger_joint_controls.view_selector.item_selected.emit(2)
	room.leave_room()
	await _wait_for_menu()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved and HAND_PREVIEW.inventory_contents(original) == contents, "exiting joint review must restore original inventory identity, equipment metadata and every session field")


func _check_joint_control_visibility(controls: Control, view_rect: Rect2) -> void:
	_check(view_rect.size.is_equal_approx(Vector2(1280, 720)), "joint control visibility must be checked at the normal 1280 by 720 viewport")
	var controls_layer := controls.get_parent() as CanvasLayer
	_check(controls_layer != null and controls_layer.layer == 70, "production joint controls must use the same layer 70 as the preview above the viewmodel overlay")
	_check(view_rect.encloses(controls.side_selector.get_global_rect()) and view_rect.encloses(controls.view_selector.get_global_rect()), "the actual hand-side and wrist-view selectors must remain inside the viewport")
	var numbers: Dictionary = controls.get("_numbers")
	_check(numbers.size() == 15, "every joint slider needs its actual percentage label")
	for digit: String in DIGITS:
		for joint in 3:
			var key := "%s:%d" % [digit, joint]
			var slider := controls.sliders.get(key) as HSlider
			var number := numbers.get(key) as Label
			_check(is_instance_valid(slider) and is_instance_valid(number), "the real joint controls must contain both slider and percentage: " + key)
			if not is_instance_valid(slider) or not is_instance_valid(number): continue
			var ancestor := slider.get_parent()
			while ancestor != null and not ancestor is ScrollContainer: ancestor = ancestor.get_parent()
			var scroll := ancestor as ScrollContainer
			_check(scroll != null and scroll.is_ancestor_of(number), "the slider and percentage must belong to the same actual scroll viewport: " + key)
			if scroll == null: continue
			var clip_rect := scroll.get_global_rect()
			_check(scroll.scroll_vertical == 0 and view_rect.encloses(clip_rect), "all joint rows must be available at the initial scroll position: " + key)
			_check(slider.is_visible_in_tree() and clip_rect.encloses(slider.get_global_rect()), "the complete joint slider must remain inside its actual scroll viewport: " + key)
			_check(number.is_visible_in_tree() and clip_rect.encloses(number.get_global_rect()), "the complete joint percentage must remain inside its actual scroll viewport: " + key + " label=" + str(number.get_global_rect()) + " clip=" + str(clip_rect))


func _mesh_source(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var key := str(mesh.mesh.get_instance_id()) + ":" + str(mesh.skin.get_instance_id())
	if _sources.has(key): return _sources[key]
	var result := {"bones": [], "binds": [], "surfaces": [], "normalized": (mesh.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED}
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
		result.bones.append(bone)
		result.binds.append(mesh.skin.get_bind_pose(bind))
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var shapes: Array[PackedVector3Array] = []
		for shape_arrays: Array in mesh.mesh.surface_get_blend_shape_arrays(surface): shapes.append(shape_arrays[Mesh.ARRAY_VERTEX])
		var included := {}
		for index in range(0, vertices.size(), maxi(1, vertices.size() / 512)): included[index] = true
		# Keep every corrective vertex in the stable sample set. A sparse uniform
		# sample can otherwise miss a small knuckle crease entirely.
		for shape: PackedVector3Array in shapes:
			for index in mini(vertices.size(), shape.size()):
				var delta := shape[index] - vertices[index] if result.normalized else shape[index]
				if delta.length_squared() > 0.00000000000001: included[index] = true
		var indices: Array = included.keys()
		indices.sort()
		var material := mesh.mesh.surface_get_material(surface)
		result.surfaces.append({"vertices": vertices, "bones": bones, "weights": arrays[Mesh.ARRAY_WEIGHTS], "stride": bones.size() / maxi(1, vertices.size()), "shapes": shapes, "indices": indices, "material_name": material.resource_name if material != null else ""})
	_sources[key] = result
	return result


func _skin_points(arm: Node3D, include_correctives := true, mesh_filter := "") -> PackedVector3Array:
	var result := PackedVector3Array()
	var skeleton := arm.get("skeleton") as Skeleton3D
	for mesh in _meshes(arm):
		if mesh.skin == null or (not mesh_filter.is_empty() and str(mesh.name) != mesh_filter): continue
		var source := _mesh_source(mesh, skeleton)
		var matrices: Array[Transform3D] = []
		for bind in source.bones.size(): matrices.append(skeleton.get_bone_global_pose(source.bones[bind]) * (source.binds[bind] as Transform3D))
		var active: Array[int] = []
		if include_correctives:
			for shape in mesh.get_blend_shape_count():
				if absf(mesh.get_blend_shape_value(shape)) > 0.000001: active.append(shape)
		for surface: Dictionary in source.surfaces:
			var vertices: PackedVector3Array = surface.vertices
			for index: int in surface.indices:
				var vertex := vertices[index]
				for shape in active:
					var target: Vector3 = surface.shapes[shape][index]
					# Godot normalized targets store positions; relative targets store
					# deltas. Morphs are mixed before the weighted skeleton transform.
					vertex += (target - vertices[index] if source.normalized else target) * mesh.get_blend_shape_value(shape)
				var posed := Vector3.ZERO
				for influence in int(surface.stride):
					var entry := index * int(surface.stride) + influence
					if float(surface.weights[entry]) > 0.0: posed += matrices[surface.bones[entry]] * vertex * float(surface.weights[entry])
				result.append(mesh.to_global(posed))
	return result


func _nail_local_points(arm: Node3D, digit: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	var skeleton := arm.get("skeleton") as Skeleton3D
	var nail := arm.find_child("Nail_" + digit + "*", true, false) as MeshInstance3D
	_check(nail != null and nail.get_blend_shape_count() == 0, "nails must remain separate rigid geometry without skin correctives")
	if nail == null: return result
	var frame := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(digit + "2"))
	for point in _skin_points(arm, true, str(nail.name)): result.append(frame.affine_inverse() * point)
	return result


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result


func _bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result


func _global_bones(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_global_pose(bone))
	return result


func _poses_equal(a: Array[Transform3D], b: Array[Transform3D]) -> bool:
	if a.size() != b.size(): return false
	for index in a.size():
		if not a[index].is_equal_approx(b[index]): return false
	return true


func _max_displacement(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty(): return INF
	var maximum := 0.0
	for index in a.size(): maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum


func _active_joint_count(values: Dictionary) -> int:
	var count := 0
	for digit: String in DIGITS:
		for joint in 3:
			if float(values[digit][joint]) > 0.000001: count += 1
	return count


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_for_menu() -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://main_menu.tscn" and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "joint review timed out returning to main menu")


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
