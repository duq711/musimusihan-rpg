extends SceneTree
const PREVIEW := preload("res://tests/sword_shield_choreography_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var original := snapshot.get("inventory") as ExpeditionInventory
	var fingerprint := PREVIEW.PREVIEW.inventory_fingerprint(original)
	var cursor := Input.mouse_mode
	var hashes := PREVIEW.source_hashes()
	for source: String in hashes:
		_check(str(hashes[source]).length() == 64, "every actual choreography capture dependency must have a content hash: " + source)
	_check(hashes.has("res://scripts/sword_shield_choreography.gd") and hashes.has("res://tests/sword_shield_choreography_preview.gd"), "source preservation must include the new production curves and capture harness")
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "capture fixture test must not replace an existing sandbox")
	if sandbox.active:
		quit(1)
		return
	sandbox.begin()
	var ids := {}
	var attack_samples := {}
	for action_id: String in PREVIEW.ACTIONS:
		_check(not ids.has(action_id), "the six production capture actions must be uniquely named")
		ids[action_id] = true
		var viewport := PREVIEW.create_viewport()
		root.add_child(viewport)
		var fixture := PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		_check(PREVIEW.begin_action(fixture, action_id), "capture must initialize its actual sword/shield action: " + action_id)
		var player := fixture.player as DungeonPlayer
		var source_parent := player.camera.get_parent()
		var source_id := player.camera.get_instance_id()
		var arm_ids := [player.weapon_arm.get_instance_id(), player.shield_arm.get_instance_id()]
		var source_meshes := _source_meshes(player)
		var samples: Array[Transform3D] = []
		var key_count := 0
		for frame in range(PREVIEW.FRAME_COUNT):
			if frame > 0:
				_check(PREVIEW.advance_action(fixture, 1.0 / PREVIEW.FPS), "capture must advance only accepted production actions: " + action_id)
			var inspection := PREVIEW.inspect_action(fixture)
			_check(bool(inspection.passed), "POV must retain two actual arms, disabled input and the source equipment pass: " + action_id)
			_check(viewport.size == PREVIEW.POV_SIZE and viewport.get_camera_3d() == player.camera and player.viewmodel_renderer.overlay.visible, "POV must retain its original camera and 1280x720 production overlay")
			_check(is_equal_approx(float(fixture.action_time), float(frame) / PREVIEW.FPS), "capture frame times must come from the shared 120Hz simulation clock")
			if PREVIEW.ATTACKS.has(action_id): samples.append(player.weapon_pivot.transform)
			if PREVIEW.keyframes(action_id).has(frame):
				key_count += 1
				var pose_before := player.get_first_person_motion_snapshot().duplicate(true)
				var landmarks_before := PREVIEW.arm_landmarks(player)
				var camera_before := player.camera.global_transform
				for view: String in PREVIEW.EXTERNAL_VIEWS:
					_check(PREVIEW.select_view(fixture, view), "each external direction must be executable: " + view)
					var external_inspection := PREVIEW.inspect_action(fixture)
					_check(bool(external_inspection.passed) and viewport.size == PREVIEW.EXTERNAL_SIZE and not player.viewmodel_renderer.overlay.visible, "external capture must render layer 20 directly with no overlaid POV copy")
					_check(not player.player_body.visible and not bool(external_inspection.studio_floor_visible), "external diagnostics must omit the unsynchronized static body and occluding floor")
					_check(player.camera.get_parent() == source_parent and player.camera.get_instance_id() == source_id and player.camera.global_transform == camera_before, "external inspection must never reparent, replace or move the production camera")
					_check(player.weapon_arm.get_instance_id() == arm_ids[0] and player.shield_arm.get_instance_id() == arm_ids[1] and _source_meshes(player) == source_meshes, "external views must reuse the exact same live arms and meshes, never gallery substitutes")
					_check(player.get_first_person_motion_snapshot() == pose_before and PREVIEW.arm_landmarks(player) == landmarks_before, "changing diagnostic cameras must not advance or fake any hand, wrist, elbow or combat state")
					_check_external_framing(fixture, view)
				_check(PREVIEW.select_view(fixture, "pov"), "capture must restore POV after each four-direction inspection")
				_check(player.player_body.visible == bool(fixture.body_visible) and (fixture.stage as Node3D).get_node("ArmPreviewFloor").visible == bool(fixture.floor_visible), "POV restoration must recover the original scene visibility")
		_check(key_count == 4, "every action must provide four actual keyframes with four external directions")
		_check(bool(PREVIEW.action_summary(fixture).passed), "recorded real phase/resource history must match the action: " + action_id)
		_check(not PREVIEW.advance_action(fixture, -1.0) and not PREVIEW.select_view(fixture, "invented"), "invalid progression and diagnostic directions must fail closed")
		if PREVIEW.ATTACKS.has(action_id): attack_samples[action_id] = samples
		player.cancel_sword_attack()
		var viewport_ref: WeakRef = weakref(viewport)
		viewport.queue_free()
		fixture.clear()
		await process_frame
		_check(viewport_ref.get_ref() == null, "capture action cleanup must release its full player/renderer fixture")
	_check(ids.size() == 6 and PREVIEW.EXTERNAL_VIEWS.size() == 4, "capture must include ready, three cuts, shield raise and block impact with four external directions")
	for first in range(PREVIEW.ATTACKS.size()):
		for second in range(first + 1, PREVIEW.ATTACKS.size()):
			var a: Array = attack_samples.get(PREVIEW.ATTACKS[first], [])
			var b: Array = attack_samples.get(PREVIEW.ATTACKS[second], [])
			var differences := 0
			for frame in range(mini(a.size(), b.size())):
				if not (a[frame] as Transform3D).is_equal_approx(b[frame] as Transform3D): differences += 1
			_check(differences >= 6, "the three captured attacks must sample different actual weapon trajectories, not relabel the same sequence")
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == snapshot and PREVIEW.PREVIEW.inventory_fingerprint(original) == fingerprint and Input.mouse_mode == cursor and not sandbox.active, "capture setup, real actions, external cameras and cleanup must preserve original expedition identity, nested inventory contents and cursor")
	_check(PREVIEW.source_hashes() == hashes, "headless fixture verification must not mutate any production, model or reference source")
	var encoded: Variant = PREVIEW.json_value({"position": Vector3(1, 2, 3), "pose": Transform3D.IDENTITY})
	_check(encoded.position == [1.0, 2.0, 3.0] and encoded.pose.origin == [0.0, 0.0, 0.0], "manifest landmarks must remain numeric coordinates rather than opaque transform strings")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD CHOREOGRAPHY PREVIEW TEST %s: six real action sequences, four same-arm diagnostic cameras, numeric landmarks, isolated inputs and deep session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check_external_framing(fixture: Dictionary, view: String) -> void:
	var player := fixture.player as DungeonPlayer
	var external := fixture.external_camera as Camera3D
	var viewport := fixture.viewport as SubViewport
	_check(external.cull_mask == (1 << 20) - 1 and external.projection == Camera3D.PROJECTION_ORTHOGONAL, "diagnostic camera must include actual carried layer 20 in an independent orthographic view")
	var axis := player.camera.global_basis * (Vector3.UP if view == "top" else Vector3.DOWN if view == "bottom" else Vector3.LEFT if view == "left" else Vector3.RIGHT)
	_check(external.global_basis.z.normalized().dot(axis.normalized()) > 0.999, "diagnostic direction must match the documented source-camera side: " + view)
	var framed := true
	var points := PREVIEW.geometry_points(player)
	for point in points:
		var pixel := external.unproject_position(point)
		if external.is_position_behind(point) or pixel.x < 0.0 or pixel.y < 0.0 or pixel.x > viewport.size.x or pixel.y > viewport.size.y: framed = false
	_check(not points.is_empty() and framed, "external frame must include actual sword/shield geometry and both shoulder/elbow/wrist chains: " + view)
	var arms := PREVIEW.arm_landmarks(player)
	_check(arms.has("left") and arms.left.has("shoulder") and arms.left.has("elbow") and arms.left.has("wrist") and arms.left.bones.size() == 16, "external record must retain the actual left arm and sixteen posed shield bones")
	_check(arms.has("right") and bool(arms.right.get("imported_static_grip", false)) and not bool(arms.right.get("continuous_skin", true)) and arms.right.bones.is_empty() and arms.right.source_forearm_bounds_world.size() == 8, "static right-hand inspection must report real imported forearm bounds without invented skeletal joints")
	if arms.has("right") and arms.right.has("source_forearm_bounds_world"):
		var forearm := player.weapon_arm.get("_forearm") as MeshInstance3D
		for index in range(8):
			_check((arms.right.source_forearm_bounds_world[index] as Vector3).distance_to(forearm.to_global(forearm.get_aabb().get_endpoint(index))) < 0.00001, "imported forearm inspection must measure each actual rendered mesh corner")


func _source_meshes(player: DungeonPlayer) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	for carried: Node3D in [player.weapon_arm, player.shield_arm, player.sword_visual_root, player.shield_model]:
		for instance: MeshInstance3D in carried.find_children("*", "MeshInstance3D", true, false):
			if instance.mesh != null: meshes.append(instance.mesh)
	return meshes


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
