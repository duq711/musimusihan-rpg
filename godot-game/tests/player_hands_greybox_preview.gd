extends SceneTree
## Actual opt-in player hands, driven by normal bow/chest functions in a private
## SubViewport. This launch path requires the audited windowless renderer.

const BASE := preload("res://tests/player_arm_preview.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_hands_greybox"
const POSE_IDS := ["free_hands", "bow_draw", "bow_release", "chest_touch", "chest_lift"]
const SOURCE_FILES := [
	"res://assets/3d/player/hands_greybox/left_hand_greybox.glb",
	"res://assets/3d/player/hands_greybox/right_hand_greybox.glb",
	"res://scripts/greybox_arm_visual.gd",
	"res://scripts/player_arm_visual.gd",
	"res://scripts/player.gd",
	"res://scripts/chest_hand_visuals.gd",
	"res://tests/player_arm_preview.gd",
	"res://tests/player_hands_greybox_preview.gd",
]
var failures: Array[String] = []
var captures: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Greybox captures require the audited tests/run_embedded_preview.sh renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_HANDS_GREYBOX_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_HANDS_GREYBOX_QA_ITERATION must name a new plain output folder.")
		quit(2)
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Greybox capture folder already exists; choose a new iteration.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create greybox capture folder.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var original := ExpeditionSession.capture_snapshot()
	var original_contents := inventory_contents(original.get("inventory") as ExpeditionInventory)
	var cursor := Input.mouse_mode
	var hashes := source_hashes()
	for path: String in SOURCE_FILES:
		if str(hashes[path]).length() != 64: failures.append("Missing capture source: " + path)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	for pose_id: String in POSE_IDS:
		if not configure_pose(fixture, pose_id):
			failures.append("Could not configure production greybox pose: " + pose_id)
			continue
		var inspection := inspect_pose(fixture, pose_id)
		if not inspection.passed: failures.append("Production greybox state failed: " + pose_id)
		for _frame in 12: await process_frame
		RenderingServer.force_draw(false)
		var rendered := viewport.get_texture().get_image()
		if rendered == null or rendered.is_empty():
			failures.append("Actual renderer returned no pixels: " + pose_id)
			continue
		var file_name := pose_id + ".png"
		if rendered.save_png(output_path.path_join(file_name)) != OK:
			failures.append("Could not save greybox capture: " + pose_id)
			continue
		inspection["image"] = file_name
		inspection["image_sha256"] = FileAccess.get_sha256(output_path.path_join(file_name))
		captures.append(inspection)
		print("PLAYER HANDS GREYBOX CAPTURE: " + output_path.path_join(file_name))
	(fixture.player as DungeonPlayer).cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == original and inventory_contents(original.get("inventory") as ExpeditionInventory) == original_contents and Input.mouse_mode == cursor
	if not preserved: failures.append("Greybox preview changed original inventory, expedition or cursor.")
	var sources_preserved := source_hashes() == hashes
	if not sources_preserved: failures.append("Greybox sources changed during capture.")
	var manifest := {
		"display_driver": DisplayServer.get_name(),
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"capture_kind": "Actual DungeonPlayer opt-in greybox arms and timed DungeonLootChest contact in an isolated SubViewport",
		"desktop_capture": false,
		"external_input": false,
		"expedition_inventory_and_cursor_preserved": preserved,
		"source_sha256": hashes,
		"sources_unchanged_during_capture": sources_preserved,
		"captures": captures,
		"failures": failures,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: failures.append("Could not save greybox capture manifest.")
	for failure in failures: push_error(failure)
	print("PLAYER HANDS GREYBOX PREVIEW %s: %d actual poses; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)


static func create_viewport() -> SubViewport:
	var viewport := BASE.create_viewport()
	viewport.name = "PlayerHandsGreyboxPreviewViewport"
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	return BASE.populate_viewport(viewport)


static func configure_pose(fixture: Dictionary, pose_id: String) -> bool:
	if not POSE_IDS.has(pose_id): return false
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	var base_pose := "idle" if pose_id == "free_hands" else "bow_draw" if pose_id == "bow_release" else pose_id
	if not BASE.configure_pose(fixture, base_pose): return false
	if not player.set_hands_greybox_enabled(true): return false
	player.set_torch_enabled(false)
	fixture["arrows_before_release"] = bag.count_item("wooden_arrow")
	fixture["action_result"] = {}
	if pose_id == "free_hands":
		for slot: String in ["weapon", "offhand"]:
			if not str(bag.equipment.get(slot, "")).is_empty() and not bool(bag.unequip(slot).get("accepted", false)): return false
	elif pose_id == "bow_release":
		fixture.action_result = player.release_bow_shot()
		if not bool(fixture.action_result.get("accepted", false)): return false
		# A capture records the real release frame without advancing projectiles
		# through a fixture that is deliberately not simulating gameplay input.
		for projectile in player.get_tree().get_nodes_in_group("arrow_projectile"):
			projectile.set_physics_process(false)
		# Progress the same cooldown/recoil clock as gameplay so this image shows
		# the actual finger release, not the still-hooked first instant of a shot.
		player.advance_action_timers(0.12)
	player._update_viewmodel(0.12 if pose_id == "bow_release" else 1.0)
	player._update_torch(0.0)
	player.viewmodel_renderer.sync_view()
	return true


static func inspect_pose(fixture: Dictionary, pose_id: String) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	var result := {
		"pose": pose_id,
		"greybox": player.get_hands_greybox_snapshot(),
		"weapon": str(bag.equipment.get("weapon", "")),
		"offhand": str(bag.equipment.get("offhand", "")),
		"bow_drawing": player.bow_drawing,
		"bow_draw_ratio": player.get_bow_draw_ratio(),
		"arrow_count": bag.count_item("wooden_arrow"),
		"chest_phase": player.chest_hands.phase,
		"passed": POSE_IDS.has(pose_id) and player.hands_greybox_enabled and not player.is_physics_processing() and not player.is_processing_unhandled_input(),
	}
	if pose_id == "free_hands":
		result.passed = result.passed and result.weapon.is_empty() and result.offhand.is_empty() and player.left_support_arm.is_visible_in_tree() and player.right_relaxed_arm.is_visible_in_tree()
	elif pose_id == "bow_draw":
		result.passed = result.passed and player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), 1.0)
	elif pose_id == "bow_release":
		var hand_report: Dictionary = player._legacy_weapon_arm.get("greybox_visual").get_snapshot()
		result["string_hook_amount"] = hand_report.string_hook_amount
		result.passed = result.passed and not player.bow_drawing and result.arrow_count == int(fixture.arrows_before_release) - 1 and float(hand_report.string_hook_amount) < 0.95
	elif pose_id.begins_with("chest_"):
		var contact_errors: Array[float] = []
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side == -1 else player.chest_hands.right_hand
			var contact: Transform3D = fixture.chest.get_hand_contact_transform(side, player.get_timed_interaction_progress())
			contact_errors.append(hand.global_position.distance_to(contact.origin))
		result["hand_contact_distances"] = contact_errors
		result.passed = result.passed and player.is_timed_interacting() and player.chest_equipment_stowed and not player.chest_hands.active and not player.chest_hands.is_visible_in_tree()
	return result


static func inventory_contents(inventory: ExpeditionInventory) -> Dictionary:
	if inventory == null: return {}
	return {"slots": inventory.slots.duplicate(true), "equipment": inventory.equipment.duplicate(true), "equipment_data": inventory.equipment_data.duplicate(true)}


static func source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_FILES: result[path] = FileAccess.get_sha256(path)
	return result
