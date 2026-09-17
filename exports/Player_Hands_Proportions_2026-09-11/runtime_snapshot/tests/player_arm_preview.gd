extends SceneTree
## Actual DungeonPlayer arm and hand poses, rendered without a desktop window.
## No game input is sampled or injected, and no synthetic arm pose is drawn.
## Production attack, bow draw and timed chest contact drive the real meshes.

const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_arms"
const CONTACT_PREVIEW := preload("res://tests/contact_visual_preview.gd")
const SOURCE_FILES := [
	"res://assets/3d/player/gravebound_player.glb",
	"res://scripts/player_arm_visual.gd",
	"res://scripts/player.gd",
	"res://scripts/chest_hand_visuals.gd",
]
const POSE_IDS := ["idle", "sword_windup", "sword_active", "shield_guard", "torch_safe_zone", "bow_draw", "chest_touch", "chest_lift"]

var failures: Array[String] = []
var captures: Array[Dictionary] = []
var output_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Player arm captures require tests/run_embedded_preview.sh and its audited embedded renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_ARM_QA_ITERATION").strip_edges()
	if iteration.is_empty():
		iteration = "final"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_ARM_QA_ITERATION must be a plain folder name.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	DirAccess.make_dir_recursive_absolute(output_path)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var initial_mouse_mode := Input.mouse_mode
	var initial_snapshot := ExpeditionSession.capture_snapshot()
	var initial_source_hashes := source_hashes()
	for source_path: String in SOURCE_FILES:
		if str(initial_source_hashes.get(source_path, "")).length() != 64:
			failures.append("Could not hash player arm capture source: " + source_path)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	for pose_id: String in POSE_IDS:
		if not configure_pose(fixture, pose_id):
			failures.append("Could not configure actual player pose: " + pose_id)
			continue
		var inspection := inspect_pose(fixture, pose_id)
		if not inspection.passed:
			failures.append("Production pose state did not match capture: " + pose_id)
		await _capture(viewport, pose_id, inspection)
	(fixture.player as DungeonPlayer).cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	await _capture_mine_views()
	sandbox.finish()
	var state_preserved := Input.mouse_mode == initial_mouse_mode and ExpeditionSession.capture_snapshot() == initial_snapshot
	if not state_preserved:
		failures.append("Arm preview changed the original expedition or cursor mode.")
	var sources_preserved := source_hashes() == initial_source_hashes
	if not sources_preserved:
		failures.append("Player arm source files changed while their images were being captured.")
	var manifest := {
		"display_driver": DisplayServer.get_name(),
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"capture_kind": "Actual DungeonPlayer equipment and chest hand meshes driven by production pose functions in an isolated SubViewport",
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"desktop_capture": false,
		"expedition_and_cursor_preserved": state_preserved,
		"source_sha256": initial_source_hashes,
		"sources_unchanged_during_capture": sources_preserved,
		"captures": captures,
		"failures": failures,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not save player arm capture manifest.")
	for failure in failures:
		push_error(failure)
	print("PLAYER ARM PREVIEW %s: %d actual player poses, expedition and cursor preserved; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)


static func source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for source_path: String in SOURCE_FILES:
		hashes[source_path] = FileAccess.get_sha256(source_path)
	return hashes


func _capture_mine_views() -> void:
	# The reviewed contact helpers build actual production cave geometry,
	# environment, carried lights and player, with player input disabled before
	# _ready. Their SceneTree/native-window launch path never executes here.
	var viewport := CONTACT_PREVIEW.create_viewport()
	viewport.name = "PlayerArmMineViewport"
	viewport.audio_listener_enable_3d = false
	root.add_child(viewport)
	var player := CONTACT_PREVIEW.populate_viewport(viewport)
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	player.bind_inventory(inventory)
	await physics_frame
	await physics_frame
	var configured := CONTACT_PREVIEW.configure_shot(player, {
		"name": "player_arm_mine",
		"position": Vector3(0.6, 1.75, 60.1),
		"target": Vector3(3.356, 0.65, 57.54),
		"equipment": true,
	})
	if not configured:
		failures.append("Could not configure the actual mine player-arm view.")
	else:
		for safe_zone in [true, false]:
			var pose_id := "mine_torch" if safe_zone else "mine_equipped"
			player.configure_safe_zone(safe_zone)
			player._update_viewmodel(1.0)
			player._update_torch(0.0)
			player.viewmodel_renderer.sync_view()
			var inspection := {
				"pose": pose_id,
				"world": "production_cave_geometry",
				"environment": "production_cave_environment",
				"safe_zone": player.safe_zone_mode,
				"weapon_visible": player.weapon_pivot.visible,
				"shield_visible": player.shield_pivot.visible,
				"torch_visible": player.torch_pivot.visible,
				"passed": viewport.size == IMAGE_SIZE and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(),
			}
			inspection.passed = inspection.passed and inspection.torch_visible and inspection.weapon_visible == not safe_zone and inspection.shield_visible == not safe_zone
			if not inspection.passed:
				failures.append("Actual mine arm visibility or input isolation failed: " + pose_id)
			await _capture(viewport, pose_id, inspection)
	viewport.queue_free()
	await process_frame


static func create_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "PlayerArmPreviewViewport"
	viewport.size = IMAGE_SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	var stage := Node3D.new()
	stage.name = "PlayerArmPreviewStage"
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#171a1b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.62, 0.70)
	environment.environment.ambient_light_energy = 0.34
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(14.0, 14.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#302d27")
	floor_material.roughness = 0.98
	floor_mesh.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "ArmPreviewFloor"
	floor_node.mesh = floor_mesh
	stage.add_child(floor_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key.light_color = Color(0.75, 0.80, 0.86)
	key.light_energy = 0.6
	stage.add_child(key)
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.bind_inventory(inventory)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var chest := DungeonLootChest.new().configure("팔 접촉 검증 상자", [{"id": "linen_bandage", "quantity": 1}])
	chest.visible = false
	stage.add_child(chest)
	return {"stage": stage, "player": player, "inventory": inventory, "chest": chest}


static func configure_pose(fixture: Dictionary, pose_id: String) -> bool:
	if not POSE_IDS.has(pose_id):
		return false
	var player := fixture.player as DungeonPlayer
	var chest := fixture.chest as DungeonLootChest
	var inventory := fixture.inventory as ExpeditionInventory
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	player.cancel_bow_draw()
	player.configure_safe_zone(false)
	player.set_camping(false)
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	player.blocking = false
	player.stamina = player.MAX_STAMINA
	player.bow_cooldown = 0.0
	player.position = Vector3(0.0, 0.90, 2.4)
	player.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player._pitch = deg_to_rad(-9.0)
	player.head.rotation = Vector3(player._pitch, 0.0, 0.0)
	player.set_torch_enabled(true)
	chest.visible = false
	if not _equip_weapon(inventory, "hunting_bow" if pose_id == "bow_draw" else "rusted_sword"):
		return false
	match pose_id:
		"sword_windup":
			player._try_begin_attack()
		"sword_active":
			player._try_begin_attack()
			player._commit_attack()
		"shield_guard":
			player.blocking = true
		"torch_safe_zone":
			player.configure_safe_zone(true)
		"bow_draw":
			if not bool(player.begin_bow_draw().get("accepted", false)):
				return false
			player._advance_bow_draw(player.BOW_DRAW_DURATION)
		"chest_touch", "chest_lift":
			chest.visible = true
			player.position = Vector3(0.0, 0.90, -1.50)
			player.rotation.y = PI
			var direction := chest.to_global(Vector3(0.0, 0.84, -0.59)) - player.camera.global_position
			player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
			player.head.rotation.x = player._pitch
			if not chest.is_within_hand_reach(player):
				return false
			player._update_viewmodel(1.0)
			chest.interact(player)
			if not player.is_timed_interacting():
				return false
			player.advance_timed_interaction(chest.OPEN_DURATION * (0.55 if pose_id == "chest_touch" else 0.86))
	player._update_viewmodel(1.0)
	player._update_torch(0.0)
	player.viewmodel_renderer.sync_view()
	return true


static func _equip_weapon(inventory: ExpeditionInventory, item_id: String) -> bool:
	if str(inventory.equipment.get("weapon", "")) == item_id:
		return true
	for index in inventory.slots.size():
		if str(inventory.slots[index].get("id", "")) == item_id:
			inventory.equip_from_slot(index)
			return str(inventory.equipment.get("weapon", "")) == item_id
	return false


static func inspect_pose(fixture: Dictionary, pose_id: String) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var chest := fixture.chest as DungeonLootChest
	var result := {
		"pose": pose_id,
		"combat_state": player.combat_state,
		"blocking": player.blocking,
		"bow_draw_ratio": player.get_bow_draw_ratio(),
		"safe_zone": player.safe_zone_mode,
		"weapon_visible": player.weapon_pivot.visible,
		"shield_visible": player.shield_pivot.visible,
		"torch_visible": player.torch_pivot.visible,
		"chest_phase": str(player.chest_hands.get("phase")),
		"passed": POSE_IDS.has(pose_id) and not player.is_physics_processing() and not player.is_processing_unhandled_input(),
	}
	match pose_id:
		"idle":
			result.passed = result.passed and player.combat_state == DungeonPlayer.CombatState.READY and result.weapon_visible
		"sword_windup":
			result.passed = result.passed and player.combat_state == DungeonPlayer.CombatState.WINDUP
		"sword_active":
			result.passed = result.passed and player.combat_state == DungeonPlayer.CombatState.ACTIVE
		"shield_guard":
			result.passed = result.passed and player.blocking and result.shield_visible
		"torch_safe_zone":
			result.passed = result.passed and player.safe_zone_mode and result.torch_visible and not result.weapon_visible and not result.shield_visible
		"bow_draw":
			result.passed = result.passed and player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), 1.0)
		"chest_touch", "chest_lift":
			var contact_errors: Array[float] = []
			for side in [-1, 1]:
				var hand := player.chest_hands.get("left_hand" if side == -1 else "right_hand") as Node3D
				var contact := chest.get_hand_contact_transform(side, player.get_timed_interaction_progress())
				contact_errors.append(hand.global_position.distance_to(contact.origin))
			result["hand_contact_distances"] = contact_errors
			result.passed = result.passed and player.is_timed_interacting() and player.chest_equipment_stowed and contact_errors.max() < 0.025
	return result


func _capture(viewport: SubViewport, pose_id: String, inspection: Dictionary) -> void:
	for _frame in range(20):
		await process_frame
	RenderingServer.force_draw(false)
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		failures.append("Actual renderer returned no image for " + pose_id)
		return
	var file_name := "player_arms_%s.png" % pose_id
	if rendered.save_png(output_path.path_join(file_name)) != OK:
		failures.append("Could not save " + file_name)
		return
	inspection["image"] = file_name
	captures.append(inspection)
	print("PLAYER ARM CAPTURE: " + output_path.path_join(file_name))
