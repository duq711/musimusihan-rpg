extends MainMenu
class_name SanctuaryHideout

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const HIDEOUT_HUD_SCRIPT := preload("res://scripts/hideout_hud.gd")
const INVENTORY_OVERLAY_SCRIPT := preload("res://scripts/inventory_overlay.gd")
const DROPPED_ITEM_SCRIPT := preload("res://scripts/dropped_item.gd")
const BLACKSMITH_OVERLAY := preload("res://scripts/blacksmith_overlay.gd")
const BLACKSMITH_VISUAL := preload("res://scripts/blacksmith_visual.gd")
const ALCHEMY_OVERLAY := preload("res://scripts/alchemy_overlay.gd")
const ALCHEMY_VISUAL := preload("res://scripts/alchemy_visual.gd")
const COOKING_CONTROLLER := preload("res://scripts/hideout_cooking_controller.gd")
const COOKING_VISUAL := preload("res://scripts/hideout_cooking_visual.gd")
const RUIN_VISUAL := preload("res://scripts/hideout_ruin_visual.gd")
const HIDEOUT_RUIN_VIEWS := preload("res://scripts/hideout_ruin_views.gd")

const INTERACTABLE_SCRIPT := preload("res://scripts/hideout_interactable.gd")

const WALL_TEXTURE := preload("res://assets/ai/materials/ossuary_wall.png")
const FLOOR_TEXTURE := preload("res://assets/ai/materials/wet_flagstone.png")
const OAK_TEXTURE := preload("res://assets/ai/materials/ancient_oak.png")
const IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const FLAME_TEXTURE := preload("res://assets/ai/vfx/torch_flame.png")
const RUNE_TEXTURE := preload("res://assets/ai/vfx/rune_trap.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const SKULL_VISUAL := preload("res://scripts/dark_fantasy_skull.gd")
const EQUIPMENT_CONCEPT := preload("res://scripts/equipment_concept_visual.gd")
const SAINT_VISUAL := preload("res://scripts/dark_fantasy_statue.gd")
const HEARTH_VISUAL := preload("res://scripts/dark_fantasy_hearth_visual.gd")

const FLAME_VISUALS := preload("res://scripts/flame_visuals.gd")
const DUNGEON_CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const STONE_BATCHES := preload("res://scripts/static_stone_batches.gd")
const ARCH_SCENE := preload("res://assets/3d/dark_fantasy/dungeon_archway_4m.glb")
const PILLAR_SCENE := preload("res://assets/3d/dark_fantasy/dungeon_pillar_3m.glb")
const STAIRS_SCENE := preload("res://assets/3d/dark_fantasy/dungeon_stairs_4m.glb")
const TORCH_SCENE := preload("res://assets/3d/dark_fantasy/iron_cage_torch.glb")
const CHEST_SCENE := preload("res://assets/3d/dark_fantasy/reliquary_chest.glb")
const SWORD_SCENE := preload("res://assets/3d/dark_fantasy/rusted_longsword.glb")
const SHIELD_SCENE := preload("res://assets/3d/dark_fantasy/weathered_round_shield.glb")

const PLAYER_LAYER := 1
const WORLD_LAYER := 2
const INTERACT_LAYER := 16
const ENTRANCE_CLICK_DISTANCE := 32.0

enum HideoutMode { RUNNING, MAP, INVENTORY, PAUSED, RESTING, TRANSITIONING, BLACKSMITH, ALCHEMY, COOKING }

var hideout_mode := HideoutMode.RUNNING
var world_root: Node3D
var regions_root: Node3D
var region_nodes: Dictionary = {}
var player: DungeonPlayer
var hideout_hud: DungeonHUD
var inventory_overlay: InventoryOverlay
var blacksmith_overlay: CanvasLayer
var blacksmith_world: Node3D
var alchemy_overlay: CanvasLayer
var alchemy_world: Node3D
var cooking_controller: Node
var cooking_world: Node3D
var ruin_visual: Node3D
var _alchemy_world_was_visible := true
var _alchemy_player_was_visible := true
var _smithing_world_was_visible := true
var _smithing_player_was_visible := true
var inventory: ExpeditionInventory

var stone_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var wood_material: StandardMaterial3D
var metal_material: StandardMaterial3D
var water_material: StandardMaterial3D
var dark_material: StandardMaterial3D
var straw_material: StandardMaterial3D
var cloth_material: StandardMaterial3D
var moss_material: StandardMaterial3D
var bone_material: StandardMaterial3D
var ember_material: StandardMaterial3D

var hearth_root: Node3D
var hearth_light: OmniLight3D
var hearth_flame: Node3D
var water_surfaces: Array[MeshInstance3D] = []
var flicker_lights: Array[Dictionary] = []
var swaying_props: Array[Node3D] = []
var elapsed := 0.0
var brazier_lit := true
var _piece_index := 0
var _current_zone_id := ""
var _visited_zones: Dictionary = {}
var _ui_canvas: CanvasLayer


func _enter_tree() -> void:
	super._enter_tree()
	_register_hideout_inputs()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ExpeditionSession.ensure_journey()
	inventory = ExpeditionSession.get_inventory()
	_build_fonts()
	_build_materials()
	_build_world()
	_spawn_hud()
	_spawn_inventory_overlay()
	_spawn_player()
	_build_interface()
	get_tree().paused = false
	hideout_mode = HideoutMode.RUNNING
	_set_play_mouse_mode()
	call_deferred("_announce_arrival")
	call_deferred("_open_blacksmith_trial")
	call_deferred("_open_alchemy_trial")
	call_deferred("_open_cooking_trial")
	call_deferred("_open_ruin_trial")


func _process(delta: float) -> void:
	elapsed += delta
	_animate_water()
	_animate_lights()
	_animate_hanging_props()
	if hideout_mode == HideoutMode.RUNNING and Input.is_action_just_pressed("torch") and is_instance_valid(player):
		var cancelling := player.is_item_use_active()
		var torch_on := player.handle_torch_action()
		if not cancelling and is_instance_valid(hideout_hud):
			hideout_hud.show_event("횃불을 밝혔습니다" if torch_on else "횃불을 껐습니다", 0.8)
	_update_player_region()
	if is_instance_valid(player) and player.global_position.y < -4.0:
		player.global_position = Vector3(0.0, 1.0, 17.2)
		player.velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and hideout_mode == HideoutMode.RUNNING:
			if _try_open_entrance_from_click(mouse_event.position):
				get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		if DisplayServer.get_name() != "headless":
			var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			_apply_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()
		return
	if hideout_mode == HideoutMode.COOKING:
		if event.keycode == KEY_ESCAPE:
			cooking_controller.close_kitchen()
			get_viewport().set_input_as_handled()
		return
	if current_panel != null:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_M:
			_close_modal()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(inventory_overlay) and inventory_overlay.is_open():
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_I:
			_close_inventory()
			get_viewport().set_input_as_handled()
		return
	if hideout_mode == HideoutMode.PAUSED:
		if event.keycode == KEY_ESCAPE:
			_resume_hideout()
			get_viewport().set_input_as_handled()
		return
	if hideout_mode != HideoutMode.RUNNING:
		return
	if event.physical_keycode == KEY_M:
		_open_destination_map()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_I:
		_open_inventory()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_pause_hideout()
		get_viewport().set_input_as_handled()


func _build_materials() -> void:
	stone_material = DUNGEON_CONCEPT.stone_material(2)
	floor_material = _textured_material(Color(0.55, 0.62, 0.61), FLOOR_TEXTURE, 0.33, 0.025, 0.84)
	wood_material = AGED_SURFACES.old_oak(Color(0.49, 0.455, 0.38), 2.8)
	metal_material = AGED_SURFACES.pitted_iron(Color(0.34, 0.35, 0.32), 3.6)
	dark_material = _material(Color(0.017, 0.021, 0.021), 0.96, 0.01)
	straw_material = AGED_SURFACES.linen(Color(0.34, 0.29, 0.20), 5.5)
	cloth_material = AGED_SURFACES.linen(Color(0.23, 0.22, 0.19), 5.0)
	moss_material = _material(Color(0.075, 0.13, 0.09), 0.97, 0.0)
	bone_material = AGED_SURFACES.bone(Color(0.51, 0.475, 0.38))
	ember_material = HEARTH_VISUAL.charred_material()
	water_material = _material(Color(0.025, 0.095, 0.105, 0.58), 0.08, 0.16)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material.albedo_texture = FLOOR_TEXTURE
	water_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	water_material.texture_repeat = true
	water_material.uv1_scale = Vector3(0.20, 0.20, 0.20)


func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	regions_root = Node3D.new()
	regions_root.name = "StreamingRegions"
	world_root.add_child(regions_root)
	_build_environment()
	_create_regions()
	_build_central_hall()
	_build_entry_and_stairs()
	_build_sleeping_cell()
	_build_storage_room()
	_build_workshop()
	_build_flooded_store()
	_build_sealed_ossuary()
	_build_drainage_tunnel()
	_build_streaming_anchors()
	_build_occluders()
	_add_dust_motes(Vector3(0.0, 3.0, 0.0), Vector3(7.2, 2.0, 9.0), 70)
	ruin_visual = RUIN_VISUAL.new()
	ruin_visual.name = "HideoutRuinVisual"
	world_root.add_child(ruin_visual)
	ruin_visual.build(self)
	for region: Node3D in region_nodes.values():
		STONE_BATCHES.build(region)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "HideoutWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.20, 0.21)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.36, 0.36)
	environment.ambient_light_energy = 0.85
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.026, 0.070, 0.075)
	environment.fog_light_energy = 0.44
	environment.fog_density = 0.009
	environment.fog_height = 0.8
	environment.fog_height_density = 0.15
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 2.6
	environment.ssao_intensity = 1.75
	environment.ssil_enabled = true
	environment.ssil_radius = 3.4
	environment.ssil_intensity = 0.52
	environment.ssr_enabled = true
	environment.ssr_max_steps = 48
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_strength = 0.65
	world_environment.environment = environment
	world_root.add_child(world_environment)

	var cold_fill := DirectionalLight3D.new()
	cold_fill.name = "ColdChapelLeak"
	cold_fill.rotation_degrees = Vector3(-67.0, -24.0, 0.0)
	cold_fill.light_color = Color(0.18, 0.34, 0.41)
	cold_fill.light_energy = 0.31
	cold_fill.shadow_enabled = true
	# Two local cascades cover the interior without redrawing it four times
	# for the default 100-metre outdoor shadow range.
	cold_fill.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	cold_fill.directional_shadow_max_distance = 32.0
	cold_fill.directional_shadow_split_1 = 0.25
	cold_fill.directional_shadow_fade_start = 0.9
	world_root.add_child(cold_fill)
	var stair_light := SpotLight3D.new()
	stair_light.name = "EntranceShaftLight"
	stair_light.position = Vector3(0.0, 6.2, 23.2)
	stair_light.rotation_degrees = Vector3(-88.0, 0.0, 0.0)
	stair_light.spot_range = 14.0
	stair_light.spot_angle = 36.0
	stair_light.light_color = Color(0.27, 0.48, 0.56)
	stair_light.light_energy = 2.1
	stair_light.shadow_enabled = true
	world_root.add_child(stair_light)


func _create_regions() -> void:
	_create_region("Region_CentralCistern", "central", AABB(Vector3(-8.0, -1.0, -10.0), Vector3(16.0, 7.0, 20.0)))
	_create_region("Region_ChapelEntrance", "entrance", AABB(Vector3(-4.0, -1.0, 10.0), Vector3(8.0, 8.0, 17.0)))
	_create_region("Region_CaretakerCell", "sleep", AABB(Vector3(-15.5, -1.0, 1.5), Vector3(7.5, 6.0, 8.0)))
	_create_region("Region_EmptyStorage", "storage", AABB(Vector3(8.0, -1.0, 1.5), Vector3(7.5, 6.0, 8.0)))
	_create_region("Region_BrokenWorkshop", "workshop", AABB(Vector3(8.0, -1.0, -8.5), Vector3(8.5, 6.0, 7.0)))
	_create_region("Region_FloodedStore", "flooded_store", AABB(Vector3(-15.5, -1.0, -8.5), Vector3(7.5, 6.0, 7.0)))
	_create_region("Region_SealedOssuary", "ossuary", AABB(Vector3(-6.0, -1.0, -22.0), Vector3(12.0, 7.0, 12.0)))
	_create_region("Region_DrainageLink", "drain", AABB(Vector3(16.0, -1.0, -7.0), Vector3(9.0, 5.0, 4.0)))


func _create_region(node_name: String, region_id: String, bounds: AABB) -> Node3D:
	var region := Node3D.new()
	region.name = node_name
	region.add_to_group("hideout_stream_region")
	region.set_meta("region_id", region_id)
	region.set_meta("streaming_bounds", bounds)
	region.set_meta("keep_neighbor_regions", 1)
	regions_root.add_child(region)
	region_nodes[region_id] = region
	return region


func _build_central_hall() -> void:
	var region := region_nodes["central"] as Node3D
	_add_static_box(region, "CentralFloor", Vector3(0.0, -0.42, 0.0), Vector3(16.0, 0.84, 20.0), floor_material)
	_add_static_box(region, "CentralCeiling", Vector3(0.0, 5.45, 0.0), Vector3(16.0, 0.5, 20.0), stone_material)
	for x in [-8.25, 8.25]:
		_add_static_box(region, "CentralSideWall", Vector3(x, 2.55, -8.25), Vector3(0.5, 5.2, 3.5), stone_material)
		_add_static_box(region, "CentralSideWall", Vector3(x, 2.55, 0.0), Vector3(0.5, 5.2, 7.0), stone_material)
		_add_static_box(region, "CentralSideWall", Vector3(x, 2.55, 8.25), Vector3(0.5, 5.2, 3.5), stone_material)
	for z in [-10.25, 10.25]:
		_add_static_box(region, "CentralEndWall", Vector3(-5.5, 2.55, z), Vector3(5.0, 5.2, 0.5), stone_material)
		_add_static_box(region, "CentralEndWall", Vector3(5.5, 2.55, z), Vector3(5.0, 5.2, 0.5), stone_material)
	for pillar_position in [Vector3(-6.5, 0.0, -7.8), Vector3(6.5, 0.0, -7.8), Vector3(-6.5, 0.0, 7.8), Vector3(6.5, 0.0, 7.8)]:
		_add_pillar(region, pillar_position, Vector3(1.26, 1.55, 1.26))
	for arch_data in [
		[Vector3(0.0, 0.0, 10.02), 0.0], [Vector3(0.0, 0.0, -10.02), 0.0],
		[Vector3(-8.02, 0.0, 5.0), 90.0], [Vector3(8.02, 0.0, 5.0), 90.0],
		[Vector3(-8.02, 0.0, -5.0), 90.0], [Vector3(8.02, 0.0, -5.0), 90.0]
	]:
		_add_arch(region, arch_data[0], float(arch_data[1]), Vector3(1.08, 1.10, 1.08))
		var arch_position: Vector3 = arch_data[0]
		var side_opening := absf(arch_position.x) > 1.0
		var infill_position := Vector3(signf(arch_position.x) * 8.25, 4.335, arch_position.z) if side_opening else Vector3(arch_position.x, 4.335, signf(arch_position.z) * 10.25)
		var infill_size := Vector3(0.5, 1.77, 3.0) if side_opening else Vector3(6.0, 1.77, 0.5)
		_add_upper_wall_infill(region, "ArchUpperMasonryInfill", infill_position, infill_size)
	for x in [-8.25, 8.25]:
		_add_upper_wall_infill(region, "CeilingWallJointClosure", Vector3(x, 5.175, 0), Vector3(0.5, 0.07, 20.0))
	for z in [-10.25, 10.25]:
		_add_upper_wall_infill(region, "CeilingWallJointClosure", Vector3(0, 5.175, z), Vector3(16.0, 0.07, 0.5))
	_add_water_surface(region, Vector3(0.0, 0.035, -0.6), Vector2(11.8, 14.6), 42.0)
	_add_static_box(region, "DryCauseway", Vector3(0.0, 0.015, 3.8), Vector3(2.15, 0.13, 11.8), floor_material)
	_add_static_box(region, "DryCrossing", Vector3(0.0, 0.018, -4.1), Vector3(9.2, 0.14, 1.55), floor_material)
	_add_rubble_cluster(region, Vector3(-6.8, 0.03, 1.2), 0.75)
	_add_rubble_cluster(region, Vector3(6.9, 0.03, -1.7), 0.62)
	_build_broken_saint(region)
	var saint_light := OmniLight3D.new()
	saint_light.name = "BrokenRoofSaintLight"
	saint_light.position = Vector3(0.7, 2.65, -4.15)
	saint_light.omni_range = 5.4
	saint_light.light_color = Color(0.53, 0.63, 0.63)
	saint_light.light_energy = 3.4
	saint_light.light_specular = 0.28
	saint_light.shadow_enabled = false
	region.add_child(saint_light)
	_build_hearth(region)
	_add_wall_torch(region, Vector3(-7.86, 2.62, 7.4), 90.0, Color(1.0, 0.40, 0.17), 1.0)
	_add_wall_torch(region, Vector3(7.86, 2.62, -1.0), -90.0, Color(0.94, 0.34, 0.13), 0.82)


func _add_upper_wall_infill(parent: Node3D, title: String, at: Vector3, size: Vector3) -> Node3D:
	# Fill the missing facade above existing archways and the original 5 cm
	# ceiling seam. The walkable opening, physics and light placement are kept.
	var infill := DUNGEON_CONCEPT.create_architecture(size, "ossuary_wall")
	infill.name = title
	infill.set_meta("structural_infill", title)
	infill.position = at
	parent.add_child(infill)
	return infill


func _build_entry_and_stairs() -> void:
	var region := region_nodes["entrance"] as Node3D
	_add_static_box(region, "VestibuleFloor", Vector3(0.0, -0.42, 15.0), Vector3(8.0, 0.84, 10.0), floor_material)
	_add_static_box(region, "VestibuleCeiling", Vector3(0.0, 4.45, 15.0), Vector3(8.0, 0.5, 10.0), stone_material)
	for x in [-4.25, 4.25]:
		_add_static_box(region, "VestibuleWall", Vector3(x, 2.05, 15.0), Vector3(0.5, 4.2, 10.0), stone_material)
	_add_static_box(region, "StairThresholdL", Vector3(-3.0, 2.05, 20.25), Vector3(2.0, 4.2, 0.5), stone_material)
	_add_static_box(region, "StairThresholdR", Vector3(3.0, 2.05, 20.25), Vector3(2.0, 4.2, 0.5), stone_material)
	_add_arch(region, Vector3(0.0, 0.0, 20.02), 0.0, Vector3(1.05, 1.02, 1.05))
	for x in [-2.28, 2.28]:
		_add_static_box(region, "OpenStairSideWall", Vector3(x, 3.0, 23.35), Vector3(0.55, 6.0, 6.7), stone_material)
	for index in range(7):
		var step_height := 0.22 * float(index + 1)
		var step_z := 20.55 + float(index) * 0.86
		_add_static_box(region, "ChapelStep", Vector3(0.0, step_height * 0.5, step_z), Vector3(4.0, step_height, 0.92), floor_material)
	var stairs_visual := STAIRS_SCENE.instantiate() as Node3D
	if stairs_visual != null:
		stairs_visual.name = "RuinedChapelStairsVisual"
		stairs_visual.position = Vector3(0.0, 0.06, 22.5)
		stairs_visual.rotation_degrees.y = 180.0
		stairs_visual.scale = Vector3(1.04, 0.55, 1.32)
		region.add_child(stairs_visual)
		_disable_imported_collisions(stairs_visual)
		_apply_material_recursive(stairs_visual, floor_material)
		DUNGEON_CONCEPT.apply_stairs(stairs_visual)
		_set_visibility_range_recursive(stairs_visual, 48.0)
	_add_static_box(region, "HiddenHatchWall", Vector3(0.0, 2.6, 26.72), Vector3(4.5, 3.1, 0.62), wood_material)
	_add_visual_box(region, "HatchIronBraceA", Vector3(0.0, 2.12, 26.35), Vector3(4.25, 0.13, 0.18), metal_material, Vector3(0.0, 0.0, 8.0))
	_add_visual_box(region, "HatchIronBraceB", Vector3(0.0, 3.0, 26.34), Vector3(4.25, 0.13, 0.18), metal_material, Vector3(0.0, 0.0, -8.0))
	_add_interactable(
		region,
		"EntranceTravelInteraction",
		"travel",
		"입구를 통해 원정 떠나기",
		Vector3(0.0, 0.0, 19.72),
		Vector3(4.15, 4.25, 0.32),
		Vector3(0.0, 2.12, 0.0),
		0.0
	)
	_add_visual_box(region, "MudMat", Vector3(-1.35, 0.07, 17.5), Vector3(1.55, 0.10, 0.92), straw_material)
	_add_bucket(region, Vector3(2.7, 0.0, 17.5), 0.62)
	_add_hanging_cloth(region, Vector3(-3.78, 2.55, 16.0), Vector2(1.25, 1.8), Color(0.105, 0.12, 0.105))
	_add_wall_torch(region, Vector3(3.88, 2.45, 13.9), -90.0, Color(0.72, 0.38, 0.18), 0.63)
	_add_rubble_cluster(region, Vector3(-1.72, 1.58, 25.7), 0.72)


func _build_sleeping_cell() -> void:
	var region := region_nodes["sleep"] as Node3D
	_add_room_shell(region, Vector3(-11.75, 0.0, 5.5), Vector2(7.0, 7.0), 4.15, {"east": Vector2(5.0, 3.0)})
	_add_static_box(region, "BedFrame", Vector3(-12.6, 0.28, 6.7), Vector3(3.7, 0.42, 1.65), wood_material, false)
	for side in [-1.0, 1.0]:
		_add_visual_box(region, "BedSideRail_%s" % str(side), Vector3(-12.6, 0.32, 6.7 + side * 0.76), Vector3(3.7, 0.18, 0.12), wood_material)
		for end in [-1.0, 1.0]:
			_add_visual_box(region, "BedCornerPost_%s_%s" % [str(side), str(end)], Vector3(-12.6 + end * 1.72, 0.42, 6.7 + side * 0.76), Vector3(0.15, 0.84, 0.15), wood_material)
	for index in 9:
		_add_visual_box(region, "BedUndersideBoard_%d" % index, Vector3(-14.20 + float(index) * 0.40, 0.37, 6.7), Vector3(0.38, 0.11, 1.55), wood_material)
	var mattress := _add_visual_box(region, "StrawMattress", Vector3(-12.6, 0.57, 6.7), Vector3(3.45, 0.28, 1.45), straw_material)
	mattress.mesh = CampVisuals.create_folded_pad(Vector3(3.45, 0.28, 1.45))
	var blanket := _add_visual_box(region, "ThreadbareBlanket", Vector3(-12.9, 0.75, 6.68), Vector3(2.2, 0.08, 1.5), cloth_material, Vector3(0.0, 0.0, -2.0))
	blanket.mesh = CampVisuals.create_folded_pad(Vector3(2.2, 0.14, 1.5))
	var pillow := _add_visual_box(region, "RolledPillow", Vector3(-14.05, 0.77, 6.7), Vector3(0.48, 0.25, 1.08), cloth_material)
	pillow.mesh = CampVisuals.create_folded_pad(Vector3(0.48, 0.25, 1.08))
	_add_straw_fringe(region, Vector3(-12.6, 0.57, 6.7))
	_add_interactable(region, "BedrollInteraction", "rest", "침상에서 쉬기", Vector3(-12.6, 0.0, 6.7), Vector3(3.9, 1.45, 2.0), Vector3(0.0, 0.72, 0.0), 1.2)

	var chest := CHEST_SCENE.instantiate() as Node3D
	if chest != null:
		chest.name = "PersistentStashVisual"
		chest.position = Vector3(-13.55, 0.0, 3.05)
		chest.rotation_degrees.y = 90.0
		chest.scale = Vector3.ONE * 1.12
		region.add_child(chest)
		_disable_imported_collisions(chest)
		DungeonLootChest.apply_concept_surface(chest)
		_set_visibility_range_recursive(chest, 28.0)
	_add_static_box(region, "StashCollision", Vector3(-13.55, 0.55, 3.05), Vector3(1.55, 1.1, 1.05), dark_material, false)
	_add_interactable(region, "StashInteraction", "stash", "개인 보관함 정리", Vector3(-13.55, 0.0, 3.05), Vector3(2.1, 1.8, 1.8), Vector3(0.0, 0.85, 0.0), 0.35)
	_build_small_stool(region, Vector3(-10.0, 0.0, 7.35))
	_add_bucket(region, Vector3(-9.15, 0.0, 2.7), 0.52)
	_add_hanging_herbs(region, Vector3(-14.9, 2.85, 4.7))
	_add_candle_cluster(region, Vector3(-10.15, 0.75, 3.0), 3)
	_add_interactable(region, "WaterBasinInteraction", "wash", "빗물을 받아 둔 대야 사용", Vector3(-9.25, 0.0, 2.85), Vector3(1.5, 1.5, 1.5), Vector3(0.0, 0.7, 0.0), 0.45)


func _build_storage_room() -> void:
	var region := region_nodes["storage"] as Node3D
	_add_room_shell(region, Vector3(11.75, 0.0, 5.5), Vector2(7.0, 7.0), 4.15, {"west": Vector2(5.0, 3.0)})
	_build_shelf(region, Vector3(14.55, 0.0, 5.5), 0.0, 3.8)
	_build_shelf(region, Vector3(11.7, 0.0, 8.55), 90.0, 2.8)
	_add_crate(region, Vector3(9.4, 0.0, 7.9), Vector3(1.25, 0.92, 1.08))
	_add_crate(region, Vector3(10.4, 0.0, 8.25), Vector3(0.86, 0.62, 0.78))
	_add_barrel(region, Vector3(13.55, 0.0, 2.65), 0.52, 1.22)
	_add_barrel(region, Vector3(14.55, 0.0, 2.9), 0.42, 0.92)
	var sack := _add_visual_box(region, "EmptySack", Vector3(9.5, 0.31, 3.05), Vector3(1.1, 0.26, 0.72), straw_material, Vector3(0.0, 18.0, 5.0))
	sack.mesh = _empty_sack_mesh()
	var sack_material := AGED_SURFACES.linen(Color(0.32, 0.28, 0.20), 4.0)
	sack_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sack.material_override = sack_material
	_add_interactable(region, "StorageNotice", "storage", "텅 빈 저장고 살펴보기", Vector3(12.2, 0.0, 5.3), Vector3(5.6, 2.0, 5.0), Vector3(0.0, 1.0, 0.0), 0.0)


func _build_workshop() -> void:
	var region := region_nodes["workshop"] as Node3D
	_add_room_shell(region, Vector3(12.0, 0.0, -5.0), Vector2(8.0, 6.0), 4.15, {"west": Vector2(-5.0, 3.0), "east": Vector2(-5.0, 3.0)})
	blacksmith_world = BLACKSMITH_VISUAL.new()
	blacksmith_world.name = "WorkingBlacksmith"
	blacksmith_world.position = Vector3(11.8, 0.0, -6.05)
	region.add_child(blacksmith_world)
	# The workstations occupy the north side, preserving the east/west passage.
	_add_static_box(region, "ForgeCollision", Vector3(10.78, 0.65, -6.9), Vector3(1.45, 1.3, 1.0), metal_material, false)
	_add_static_box(region, "AnvilCollision", Vector3(11.6, 0.5, -5.67), Vector3(1.0, 1.0, 0.65), metal_material, false)
	var quench_body := StaticBody3D.new()
	quench_body.name = "QuenchCollision"
	quench_body.position = Vector3(12.98, 0.325, -5.73)
	var quench_collision := CollisionShape3D.new()
	var quench_shape := CylinderShape3D.new()
	quench_shape.radius = 0.43
	quench_shape.height = 0.65
	quench_collision.shape = quench_shape
	quench_body.add_child(quench_collision)
	region.add_child(quench_body)
	_add_static_box(region, "SmithBenchCollision", Vector3(12.83, 0.48, -6.98), Vector3(1.8, 0.96, 0.7), wood_material, false)
	_add_interactable(region, "WorkbenchInteraction", "workbench", "대장간 · 무기 제작 / 개조", Vector3(11.8, 0.0, -5.9), Vector3(4.2, 2.1, 2.0), Vector3(0.0, 1.0, 0.0), 0.3)
	# The apothecary occupies the opposite wall. Its interaction and collision
	# remain south of the through passage and do not overlap the blacksmith.
	alchemy_world = ALCHEMY_VISUAL.new()
	alchemy_world.name = "WorkingAlchemyBench"
	alchemy_world.position = Vector3(11.1, 0.0, -2.8)
	alchemy_world.rotation.y = PI
	region.add_child(alchemy_world)
	alchemy_world.set_room_visible(false)
	_add_static_box(region, "AlchemyBenchCollision", Vector3(11.1, 0.47, -2.85), Vector3(3.58, 0.94, 1.5), wood_material, false)
	_add_interactable(region, "AlchemyBenchInteraction", "alchemy", "연금술 · 물약 조제와 술 증류", Vector3(11.1, 0.0, -2.85), Vector3(3.65, 1.85, 1.65), Vector3(0.0, 1.05, 0.0), 0.3)
	_build_weapon_rack(region, Vector3(14.9, 0.0, -2.8))


func _build_rusty_vice(parent: Node3D, at: Vector3) -> Node3D:
	var vice := Node3D.new()
	vice.name = "RustyVice"
	vice.position = at
	parent.add_child(vice)
	var iron := AGED_SURFACES.pitted_iron(Color(0.28, 0.27, 0.245), 5.0)
	var jaw_iron := AGED_SURFACES.pitted_iron(Color(0.40, 0.405, 0.39), 5.0)
	var base := _add_visual_box(vice, "CastIronBase", Vector3(0, -0.17, 0.015), Vector3(0.40, 0.08, 0.43), iron)
	base.mesh = DUNGEON_CONCEPT.chipped_block(Vector3(0.40, 0.08, 0.43), 5)
	_add_visual_box(vice, "FixedJawBody", Vector3(0, -0.035, 0.125), Vector3(0.24, 0.22, 0.16), iron)
	_add_visual_box(vice, "FixedJaw", Vector3(0, 0.145, 0.076), Vector3(0.34, 0.13, 0.10), iron)
	_add_visual_box(vice, "FixedGrippingFace", Vector3(0, 0.164, 0.019), Vector3(0.34, 0.085, 0.018), jaw_iron)
	_add_visual_box(vice, "MovingJawBody", Vector3(0, -0.009, -0.123), Vector3(0.23, 0.25, 0.10), iron)
	_add_visual_box(vice, "MovingJaw", Vector3(0, 0.145, -0.117), Vector3(0.34, 0.13, 0.10), iron)
	_add_visual_box(vice, "MovingGrippingFace", Vector3(0, 0.164, -0.060), Vector3(0.34, 0.085, 0.018), jaw_iron)
	_add_visual_box(vice, "SlidingRail", Vector3(0, -0.068, -0.003), Vector3(0.115, 0.084, 0.35), iron)
	var spindle := _add_cylinder_visual(vice, "ThreadedSpindle", Vector3(0, -0.022, -0.027), 0.020, 0.020, 0.46, jaw_iron)
	spindle.rotation.x = PI * 0.5
	for index in 18:
		var thread := MeshInstance3D.new()
		thread.name = "SpindleThread_%d" % index
		var ring := TorusMesh.new()
		ring.inner_radius = 0.017
		ring.outer_radius = 0.025
		ring.rings = 12
		ring.ring_segments = 4
		thread.mesh = ring
		thread.material_override = jaw_iron
		thread.rotation.x = PI * 0.5
		thread.position = Vector3(0, -0.022, -0.235 + float(index) * 0.024)
		vice.add_child(thread)
	var hub := _add_cylinder_visual(vice, "HandleHub", Vector3(0, -0.022, -0.25), 0.042, 0.042, 0.055, iron)
	hub.rotation.x = PI * 0.5
	var handle := _add_cylinder_visual(vice, "THandle", Vector3(0, -0.022, -0.257), 0.011, 0.011, 0.40, jaw_iron)
	handle.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		var end := _add_cylinder_visual(vice, "HandleStop", Vector3(side * 0.2, -0.022, -0.257), 0.022, 0.022, 0.023, iron)
		end.rotation.z = PI * 0.5
		for z in [-0.135, 0.165]:
			_add_cylinder_visual(vice, "BaseBolt", Vector3(side * 0.145, -0.122, z), 0.023, 0.023, 0.020, jaw_iron, 6)
	return vice


func _build_flooded_store() -> void:
	var region := region_nodes["flooded_store"] as Node3D
	_add_room_shell(region, Vector3(-11.75, 0.0, -5.0), Vector2(7.0, 6.0), 4.15, {"east": Vector2(-5.0, 3.0)})
	_add_water_surface(region, Vector3(-11.8, 0.055, -5.0), Vector2(6.4, 5.3), 22.0)
	_build_shelf(region, Vector3(-14.6, 0.0, -5.2), 0.0, 3.2)
	_add_barrel(region, Vector3(-10.0, 0.0, -7.15), 0.48, 1.1)
	_add_barrel(region, Vector3(-9.15, 0.0, -6.65), 0.38, 0.82)
	_add_rubble_cluster(region, Vector3(-13.3, 0.04, -2.55), 0.52)
	_add_interactable(region, "FloodedStoreNotice", "flooded_store", "침수된 저장고 조사", Vector3(-11.6, 0.0, -5.2), Vector3(5.5, 2.2, 4.6), Vector3(0.0, 1.0, 0.0), 0.0)


func _build_sealed_ossuary() -> void:
	var region := region_nodes["ossuary"] as Node3D
	_add_static_box(region, "OssuaryFloor", Vector3(0.0, -0.42, -16.0), Vector3(12.0, 0.84, 12.0), floor_material)
	_add_static_box(region, "OssuaryCeiling", Vector3(0.0, 4.75, -16.0), Vector3(12.0, 0.5, 12.0), stone_material)
	for x in [-6.25, 6.25]:
		_add_static_box(region, "OssuaryWall", Vector3(x, 2.25, -16.0), Vector3(0.5, 4.6, 12.0), stone_material)
	_add_static_box(region, "OssuaryBackWall", Vector3(0.0, 2.25, -22.25), Vector3(12.0, 4.6, 0.5), stone_material)
	_add_static_box(region, "OssuaryShoulderL", Vector3(-4.5, 2.25, -10.25), Vector3(3.0, 4.6, 0.5), stone_material)
	_add_static_box(region, "OssuaryShoulderR", Vector3(4.5, 2.25, -10.25), Vector3(3.0, 4.6, 0.5), stone_material)
	_add_arch(region, Vector3(0.0, 0.0, -10.05), 0.0, Vector3(1.42, 1.18, 1.18))
	_add_iron_gate(region, Vector3(0.0, 0.0, -10.32), 5.7, 3.65, false)
	_add_static_box(region, "OssuaryGateCollision", Vector3(0.0, 1.75, -10.32), Vector3(5.8, 3.5, 0.35), dark_material, false)
	_add_interactable(region, "OssuaryGateInteraction", "ossuary_gate", "봉인된 납골실 문 조사", Vector3(0.0, 0.0, -9.72), Vector3(5.8, 3.5, 1.0), Vector3(0.0, 1.7, 0.0), 0.45)
	_add_niche_wall(region, Vector3(0.0, 0.0, -21.88), 5, 3)
	_add_niche_wall(region, Vector3(-5.88, 0.0, -16.2), 4, 3, 90.0)
	_add_niche_wall(region, Vector3(5.88, 0.0, -16.2), 4, 3, 90.0)
	_add_water_surface(region, Vector3(0.0, 0.045, -16.3), Vector2(9.8, 9.3), 25.0)
	_add_cold_rune(region, Vector3(0.0, 0.08, -17.4), Vector2(2.4, 2.4))
	var ossuary_light := OmniLight3D.new()
	ossuary_light.name = "SealedOssuaryGlow"
	ossuary_light.position = Vector3(0.0, 2.4, -17.4)
	ossuary_light.light_color = Color(0.18, 0.34, 0.31)
	ossuary_light.light_energy = 0.40
	ossuary_light.light_specular = 0.035
	ossuary_light.omni_range = 5.2
	ossuary_light.shadow_enabled = false
	region.add_child(ossuary_light)


func _build_drainage_tunnel() -> void:
	var region := region_nodes["drain"] as Node3D
	_add_static_box(region, "DrainFloor", Vector3(20.3, -0.42, -5.0), Vector3(8.6, 0.84, 3.4), floor_material)
	_add_static_box(region, "DrainCeiling", Vector3(20.3, 3.55, -5.0), Vector3(8.6, 0.45, 3.4), stone_material)
	for z in [-6.95, -3.05]:
		_add_static_box(region, "DrainWall", Vector3(20.3, 1.65, z), Vector3(8.6, 3.5, 0.5), stone_material)
	_add_static_box(region, "CollapsedDrain", Vector3(24.6, 1.55, -5.0), Vector3(0.8, 3.3, 3.4), stone_material)
	_add_iron_gate(region, Vector3(16.12, 0.0, -5.0), 3.2, 3.3, true)
	_add_static_box(region, "DrainGateCollision", Vector3(16.12, 1.55, -5.0), Vector3(0.34, 3.2, 3.3), dark_material, false)
	_add_interactable(region, "DrainGateInteraction", "drain_gate", "쇠사슬로 묶인 배수문 조사", Vector3(15.52, 0.0, -5.0), Vector3(1.1, 3.2, 3.3), Vector3(0.0, 1.55, 0.0), 0.45)
	_add_water_surface(region, Vector3(20.1, 0.05, -5.0), Vector2(8.0, 2.6), 18.0)
	_add_rubble_cluster(region, Vector3(23.75, 0.02, -5.0), 1.0)
	var drain_light := OmniLight3D.new()
	drain_light.name = "DrainageDaylightLeak"
	drain_light.position = Vector3(21.7, 2.8, -5.0)
	drain_light.light_color = Color(0.32, 0.40, 0.40)
	drain_light.light_energy = 0.60
	drain_light.light_specular = 0.035
	drain_light.omni_range = 4.8
	drain_light.shadow_enabled = false
	region.add_child(drain_light)


func _build_streaming_anchors() -> void:
	var anchors := Node3D.new()
	anchors.name = "OpenWorldAnchors"
	world_root.add_child(anchors)
	_add_anchor(anchors, "Spawn_NewGame", Vector3(0.0, 1.0, 17.2), "hideout_interior")
	_add_anchor(anchors, "Spawn_FromMerchant", Vector3(-1.2, 1.0, 17.0), "hideout_interior")
	_add_anchor(anchors, "Spawn_FromDungeon", Vector3(1.2, 1.0, 17.0), "hideout_interior")
	_add_anchor(anchors, "WorldExit_ChapelRuins", Vector3(0.0, 2.0, 27.4), "chapel_ruins")
	_add_anchor(anchors, "WorldExit_Drainage", Vector3(24.8, 1.0, -5.0), "marsh_drainage")
	anchors.set_meta("streaming_contract", "target_world_id + target_spawn_id")
	anchors.set_meta("interior_scene_id", "flooded_ossuary_hideout")


func _add_anchor(parent: Node3D, node_name: String, anchor_position: Vector3, target_world_id: String) -> void:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = anchor_position
	marker.set_meta("target_world_id", target_world_id)
	marker.set_meta("target_spawn_id", node_name)
	parent.add_child(marker)


func _build_occluders() -> void:
	var root_node := Node3D.new()
	root_node.name = "RoomOccluders"
	world_root.add_child(root_node)
	for data in [
		[Vector3(-8.25, 2.55, 0.0), Vector3(0.35, 5.0, 6.8)],
		[Vector3(8.25, 2.55, 0.0), Vector3(0.35, 5.0, 6.8)],
		[Vector3(-8.25, 2.55, 8.25), Vector3(0.35, 5.0, 3.3)],
		[Vector3(8.25, 2.55, 8.25), Vector3(0.35, 5.0, 3.3)],
		[Vector3(-5.5, 2.55, -10.25), Vector3(4.8, 5.0, 0.35)],
		[Vector3(5.5, 2.55, -10.25), Vector3(4.8, 5.0, 0.35)]
	]:
		var instance := OccluderInstance3D.new()
		instance.name = "RoomWallOccluder"
		instance.position = data[0]
		var box := BoxOccluder3D.new()
		box.size = data[1]
		instance.occluder = box
		root_node.add_child(instance)


func _build_broken_saint(parent: Node3D) -> void:
	var statue := Node3D.new()
	statue.name = "HeadlessSaintLandmark"
	statue.position = Vector3(0.0, 0.0, -6.45)
	parent.add_child(statue)
	_add_visual_box(statue, "StatuePlinth", Vector3(0.0, 0.38, 0.0), Vector3(2.25, 0.76, 1.7), stone_material)
	_add_visual_box(statue, "StatueBase", Vector3(0.0, 0.92, 0.0), Vector3(1.25, 0.36, 1.0), stone_material)
	statue.add_child(SAINT_VISUAL.create())
	_add_visual_box(statue, "CarvedPlinthTopMoulding", Vector3(0.0, 0.80, 0.0), Vector3(2.32, 0.12, 1.78), stone_material)
	_add_visual_box(statue, "CarvedPlinthFootMoulding", Vector3(0.0, 0.09, 0.0), Vector3(2.34, 0.18, 1.80), stone_material)
	_add_visual_box(statue, "WeatheredCrossVertical", Vector3(0.0, 0.44, -0.87), Vector3(0.07, 0.30, 0.045), stone_material)
	_add_visual_box(statue, "WeatheredCrossArms", Vector3(0.0, 0.51, -0.87), Vector3(0.23, 0.06, 0.045), stone_material)
	_add_rubble_cluster(parent, Vector3(1.15, 0.03, -6.0), 0.46)


func _build_hearth(parent: Node3D) -> void:
	hearth_root = Node3D.new()
	hearth_root.name = "OnlyWarmHearth"
	hearth_root.position = Vector3(0.0, 0.0, 2.2)
	parent.add_child(hearth_root)
	_add_cylinder_visual(hearth_root, "HearthStoneFoundation", Vector3(0, 0.10, 0), 1.02, 1.0, 0.12, stone_material, 48)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var stone := _visual_box(Vector3(0.45, 0.28, 0.34), stone_material)
		stone.name = "HearthStone"
		stone.position = Vector3(cos(angle) * 0.82, 0.18, sin(angle) * 0.82)
		stone.rotation.y = PI * 0.5 - angle
		hearth_root.add_child(stone)
	_add_cylinder_visual(hearth_root, "AshBed", Vector3(0.0, 0.12, 0.0), 0.70, 0.70, 0.12, ember_material)
	for offset in [Vector3(-0.28, 0.28, 0.0), Vector3(0.28, 0.28, 0.0), Vector3(0.0, 0.31, -0.26)]:
		var log := _add_visual_box(hearth_root, "EmberLog", offset, Vector3(0.72, 0.16, 0.18), ember_material, Vector3(0.0, 35.0 * offset.x, 0.0))
		log.mesh = HEARTH_VISUAL.charred_log(0.72, 0.08)
	hearth_flame = _add_flame(hearth_root, Vector3(0.0, 0.46, 0.0), 1.1, Color(1.0, 0.39, 0.12))
	hearth_light = OmniLight3D.new()
	hearth_light.name = "HearthLight"
	# Keep the light inside the flame, below the suspended cauldron floor.
	# A light inside the iron vessel would shadow the entire central hall.
	hearth_light.position = Vector3(0.0, 0.48, 0.0)
	hearth_light.light_color = Color(1.0, 0.37, 0.14)
	hearth_light.light_energy = 2.25
	hearth_light.omni_range = 8.8
	hearth_light.shadow_enabled = true
	hearth_root.add_child(hearth_light)
	flicker_lights.append({"light": hearth_light, "base": 2.25, "phase": 0.6})
	_add_interactable(hearth_root, "HearthInteraction", "hearth", "화롯불 지피기 / 덮기", Vector3.ZERO, Vector3(2.1, 0.55, 2.1), Vector3(0.0, 0.3, 0.0), 0.35)
	cooking_world = COOKING_VISUAL.new()
	cooking_world.name = "HearthCookingEquipment"
	hearth_root.add_child(cooking_world)
	_add_interactable(hearth_root, "CookingPotInteraction", "meal", "화롯불 요리 · 조리하고 먹기", Vector3.ZERO, Vector3(1.15, 1.3, 1.15), Vector3(0.0, 1.25, 0.0), 0.3)


func _build_small_stool(parent: Node3D, stool_position: Vector3) -> void:
	_add_cylinder_visual(parent, "StoolSeat", stool_position + Vector3(0.0, 0.54, 0.0), 0.52, 0.52, 0.16, wood_material, 32)
	for offset in [Vector3(-0.28, 0.25, -0.22), Vector3(0.28, 0.25, -0.22), Vector3(0.0, 0.25, 0.30)]:
		var leg := _add_cylinder_visual(parent, "StoolLeg", stool_position + offset, 0.068, 0.082, 0.52, wood_material, 12)
		leg.basis = Basis(Quaternion(Vector3.UP, Vector3(-offset.x * 0.5, 1.0, -offset.z * 0.5).normalized()))


func _add_straw_fringe(parent: Node3D, at: Vector3) -> void:
	var straw := MultiMeshInstance3D.new()
	straw.name = "BedStrawFringe"
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.002
	stalk.bottom_radius = 0.003
	stalk.height = 0.16
	stalk.radial_segments = 4
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = stalk
	instances.instance_count = 180
	for index in 180:
		var side := -1.0 if index < 90 else 1.0
		var x := -1.64 + float(index % 90) / 89.0 * 3.28
		var position_value := Vector3(x, sin(float(index) * 2.4) * 0.065, side * 0.735)
		var direction := Vector3(sin(float(index) * 2.39), 0.2 * cos(float(index)), side * 0.6).normalized()
		instances.set_instance_transform(index, Transform3D(Basis(Quaternion(Vector3.UP, direction)), position_value))
	straw.multimesh = instances
	straw.material_override = straw_material
	straw.position = at
	parent.add_child(straw)


func _build_shelf(parent: Node3D, shelf_position: Vector3, yaw_degrees: float, width: float) -> void:
	var shelf := Node3D.new()
	shelf.name = "BareStorageShelf"
	shelf.position = shelf_position
	shelf.rotation_degrees.y = yaw_degrees
	parent.add_child(shelf)
	for x in [-width * 0.43, width * 0.43]:
		_add_visual_box(shelf, "ShelfPost", Vector3(x, 1.25, 0.0), Vector3(0.29, 2.5, 0.42), wood_material)
	for y in [0.35, 1.25, 2.15]:
		for index in 4:
			_add_visual_box(shelf, "ShelfBoard", Vector3(0.0, y, -0.29 + float(index) * 0.195), Vector3(width, 0.13, 0.183), wood_material, Vector3(0.0, 0.0, 1.5 if y > 1.0 else -1.0))
		for side in [-1.0, 1.0]:
			_add_visual_box(shelf, "ShelfMortiseSupport", Vector3(side * width * 0.40, y - 0.10, 0.0), Vector3(0.14, 0.12, 0.82), wood_material)
			DungeonLootChest._add_rivet(shelf, Vector3(side * width * 0.44, y, -0.23), Vector3.FORWARD, metal_material)


func _build_weapon_rack(parent: Node3D, rack_position: Vector3) -> void:
	var rack := Node3D.new()
	rack.name = "AbandonedWeaponRack"
	rack.position = rack_position
	rack.rotation_degrees.y = -90.0
	parent.add_child(rack)
	_add_visual_box(rack, "RackBeam", Vector3(0.0, 1.25, 0.0), Vector3(2.4, 0.18, 0.24), wood_material)
	_add_visual_box(rack, "RackPostL", Vector3(-1.0, 0.75, 0.0), Vector3(0.20, 1.5, 0.24), wood_material)
	_add_visual_box(rack, "RackPostR", Vector3(1.0, 0.75, 0.0), Vector3(0.20, 1.5, 0.24), wood_material)
	var sword := SWORD_SCENE.instantiate() as Node3D
	if sword != null:
		sword.name = "StoredRustedSword"
		sword.position = Vector3(-0.42, 1.18, -0.1)
		sword.rotation_degrees = Vector3(0.0, 0.0, -14.0)
		sword.scale = Vector3.ONE * 0.82
		rack.add_child(sword)
		_disable_imported_collisions(sword)
		EQUIPMENT_CONCEPT.apply_sword(sword)
		_set_visibility_range_recursive(sword, 24.0)
	var shield := SHIELD_SCENE.instantiate() as Node3D
	if shield != null:
		shield.name = "StoredRoundShield"
		shield.position = Vector3(0.58, 1.12, -0.12)
		shield.scale = Vector3.ONE * 0.78
		rack.add_child(shield)
		_disable_imported_collisions(shield)
		EQUIPMENT_CONCEPT.apply_shield(shield)
		_set_visibility_range_recursive(shield, 24.0)


func _add_room_shell(parent: Node3D, center: Vector3, size_xz: Vector2, height: float, openings: Dictionary) -> void:
	_add_static_box(parent, "RoomFloor", center + Vector3(0.0, -0.42, 0.0), Vector3(size_xz.x, 0.84, size_xz.y), floor_material)
	_add_static_box(parent, "RoomCeiling", center + Vector3(0.0, height + 0.23, 0.0), Vector3(size_xz.x, 0.46, size_xz.y), stone_material)
	var half_x := size_xz.x * 0.5
	var half_z := size_xz.y * 0.5
	_add_static_box(parent, "RoomNorthWall", center + Vector3(0.0, height * 0.5, -half_z - 0.25), Vector3(size_xz.x, height, 0.5), stone_material)
	_add_static_box(parent, "RoomSouthWall", center + Vector3(0.0, height * 0.5, half_z + 0.25), Vector3(size_xz.x, height, 0.5), stone_material)
	for side in ["west", "east"]:
		var x := -half_x - 0.25 if side == "west" else half_x + 0.25
		if openings.has(side):
			var opening: Vector2 = openings[side]
			var local_z := opening.x - center.z
			var half_open := opening.y * 0.5
			var first_length := local_z - half_open + half_z
			var second_length := half_z - (local_z + half_open)
			if first_length > 0.05:
				_add_static_box(parent, "RoomSideWall", center + Vector3(x, height * 0.5, -half_z + first_length * 0.5), Vector3(0.5, height, first_length), stone_material)
			if second_length > 0.05:
				_add_static_box(parent, "RoomSideWall", center + Vector3(x, height * 0.5, local_z + half_open + second_length * 0.5), Vector3(0.5, height, second_length), stone_material)
		else:
			_add_static_box(parent, "RoomSideWall", center + Vector3(x, height * 0.5, 0.0), Vector3(0.5, height, size_xz.y), stone_material)


func _add_static_box(
	parent: Node3D,
	node_name: String,
	box_position: Vector3,
	box_size: Vector3,
	material: StandardMaterial3D,
	show_visual := true
) -> StaticBody3D:
	_piece_index += 1
	var body := StaticBody3D.new()
	body.name = "%s_%03d" % [node_name, _piece_index]
	body.position = box_position
	body.collision_layer = WORLD_LAYER
	body.collision_mask = PLAYER_LAYER
	if show_visual:
		var kind := ""
		if material == floor_material:
			kind = "wet_flagstone_floor"
		elif material == stone_material and node_name.contains("Ceiling"):
			kind = "crypt_ceiling"
		elif material == stone_material and node_name.contains("Wall"):
			kind = "ossuary_wall"
		if kind.is_empty():
			body.add_child(_visual_box(box_size, material))
		else:
			body.add_child(DUNGEON_CONCEPT.create_architecture(box_size, kind))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


func _add_visual_box(
	parent: Node3D,
	node_name: String,
	box_position: Vector3,
	box_size: Vector3,
	material: StandardMaterial3D,
	rotation_degrees_value := Vector3.ZERO
) -> MeshInstance3D:
	var visual := _visual_box(box_size, material)
	visual.name = node_name
	visual.position = box_position
	visual.rotation_degrees = rotation_degrees_value
	visual.visibility_range_end = 42.0
	visual.visibility_range_end_margin = 4.0
	parent.add_child(visual)
	return visual


func _visual_box(box_size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh_value := BoxMesh.new()
	mesh_value.size = box_size
	instance.mesh = DUNGEON_CONCEPT.chipped_block(box_size, _piece_index) if material == wood_material or material == stone_material else mesh_value
	instance.material_override = material
	return instance


func _add_cylinder_visual(
	parent: Node3D,
	node_name: String,
	position_value: Vector3,
	top_radius: float,
	bottom_radius: float,
	height: float,
	material: StandardMaterial3D,
	radial_segments := 16
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height
	cylinder.radial_segments = radial_segments
	instance.mesh = cylinder
	instance.material_override = material
	instance.position = position_value
	instance.visibility_range_end = 32.0
	instance.visibility_range_end_margin = 4.0
	parent.add_child(instance)
	return instance


func _add_arch(parent: Node3D, arch_position: Vector3, yaw_degrees: float, scale_value: Vector3) -> void:
	var arch := ARCH_SCENE.instantiate() as Node3D
	if arch == null:
		return
	arch.name = "OssuaryArchway"
	arch.position = arch_position
	arch.rotation_degrees.y = yaw_degrees
	arch.scale = scale_value
	parent.add_child(arch)
	_disable_imported_collisions(arch)
	_apply_material_recursive(arch, stone_material)
	DUNGEON_CONCEPT.apply_archway(arch)
	_set_visibility_range_recursive(arch, 52.0)


func _add_pillar(parent: Node3D, pillar_position: Vector3, scale_value: Vector3) -> void:
	var pillar := PILLAR_SCENE.instantiate() as Node3D
	if pillar == null:
		return
	pillar.name = "CisternPillar"
	pillar.position = pillar_position
	pillar.scale = scale_value
	parent.add_child(pillar)
	_disable_imported_collisions(pillar)
	_apply_material_recursive(pillar, stone_material)
	DUNGEON_CONCEPT.apply_pillar(pillar)
	_set_visibility_range_recursive(pillar, 52.0)


func _add_wall_torch(parent: Node3D, torch_position: Vector3, yaw_degrees: float, color_value: Color, energy: float) -> void:
	var root_node := Node3D.new()
	root_node.name = "SparseWallTorch"
	root_node.position = torch_position
	root_node.rotation_degrees.y = yaw_degrees
	parent.add_child(root_node)
	var torch_model := TORCH_SCENE.instantiate() as Node3D
	if torch_model != null:
		torch_model.name = "IronCageTorchVisual"
		torch_model.scale = Vector3.ONE * 0.52
		root_node.add_child(torch_model)
		_disable_imported_collisions(torch_model)
		_apply_material_to_prefix(torch_model, ["Iron", "FuelCup", "Cage"], metal_material)
		_apply_material_to_prefix(torch_model, ["CharredHandle"], wood_material)
		EQUIPMENT_CONCEPT.apply_torch(torch_model)
		EQUIPMENT_CONCEPT.apply_wall_mount(torch_model)
		_set_meshes_visible_by_prefix(torch_model, ["OuterFlame", "InnerFlame"], false)
		_set_visibility_range_recursive(torch_model, 32.0)
	_add_flame(root_node, Vector3(0.0, 0.58, 0.0), 0.58, color_value)
	var light := OmniLight3D.new()
	light.name = "LowCostTorchLight"
	light.position = Vector3(0.0, 0.62, 0.0)
	light.light_color = color_value
	light.light_energy = energy
	light.omni_range = 5.4
	light.shadow_enabled = false
	root_node.add_child(light)
	flicker_lights.append({"light": light, "base": energy, "phase": float(flicker_lights.size()) * 1.73})


func _add_flame(parent: Node3D, flame_position: Vector3, flame_scale: float, color_value: Color) -> Node3D:
	var flame_root := Node3D.new()
	flame_root.name = "LivingFlame"
	flame_root.position = flame_position
	parent.add_child(flame_root)
	var sprite := Sprite3D.new()
	sprite.name = "FlameSprite"
	sprite.texture = FLAME_TEXTURE
	sprite.pixel_size = 0.00038 * flame_scale
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	sprite.double_sided = true
	sprite.shaded = false
	sprite.modulate = color_value.lightened(0.18)
	flame_root.add_child(sprite)
	FLAME_VISUALS.attach(sprite)
	_add_fire_sparks(flame_root, color_value, flame_scale)
	return flame_root


func _add_fire_sparks(parent: Node3D, color_value: Color, scale_value: float) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "FireSparks"
	sparks.amount = 10
	sparks.lifetime = 1.15
	sparks.preprocess = 1.1
	sparks.randomness = 0.58
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.09 * scale_value
	sparks.direction = Vector3.UP
	sparks.spread = 28.0
	sparks.gravity = Vector3(0.0, 0.22, 0.0)
	sparks.initial_velocity_min = 0.12
	sparks.initial_velocity_max = 0.62
	sparks.scale_amount_min = 0.18
	sparks.scale_amount_max = 0.55
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.035) * scale_value
	var material := _material(Color(color_value, 0.9), 0.2, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = color_value
	material.emission_energy_multiplier = 3.4
	quad.material = material
	sparks.mesh = quad
	parent.add_child(sparks)


func _add_water_surface(parent: Node3D, surface_position: Vector3, size_value: Vector2, visibility_end: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size_value
	mesh.subdivide_width = 3
	mesh.subdivide_depth = 3
	var water := MeshInstance3D.new()
	water.name = "SharedShallowWater"
	water.mesh = mesh
	water.material_override = water_material
	water.position = surface_position
	water.set_meta("rest_height", surface_position.y)
	water.visibility_range_end = visibility_end
	water.visibility_range_end_margin = 4.0
	parent.add_child(water)
	water_surfaces.append(water)


func _add_water_drips(origin: Vector3, extents: Vector3, amount: int, parent_override: Node3D = null) -> void:
	var parent := parent_override if parent_override != null else world_root
	var drips := CPUParticles3D.new()
	drips.name = "CeilingWaterDrips"
	drips.position = origin
	drips.amount = amount
	drips.lifetime = 3.2
	drips.preprocess = 3.2
	drips.randomness = 0.82
	drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drips.emission_box_extents = extents
	drips.direction = Vector3.DOWN
	drips.spread = 3.0
	drips.gravity = Vector3(0.0, -1.8, 0.0)
	drips.initial_velocity_min = 0.32
	drips.initial_velocity_max = 0.9
	drips.scale_amount_min = 0.45
	drips.scale_amount_max = 0.85
	var droplet := FLAME_VISUALS.droplet_mesh()
	var material := _material(Color(0.72, 0.80, 0.81, 0.90), 0.09, 0.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic_specular = 0.95
	material.emission_enabled = true
	material.emission = Color(0.22, 0.27, 0.28)
	droplet.surface_set_material(0, material)
	drips.mesh = droplet
	parent.add_child(drips)


func _add_dust_motes(origin: Vector3, extents: Vector3, amount: int) -> void:
	var motes := CPUParticles3D.new()
	motes.name = "ColdDustMotes"
	motes.position = origin
	motes.amount = amount
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.randomness = 0.88
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = extents
	motes.direction = Vector3(0.12, 0.36, 0.08)
	motes.spread = 52.0
	motes.gravity = Vector3(0.0, 0.012, 0.0)
	motes.initial_velocity_min = 0.018
	motes.initial_velocity_max = 0.085
	motes.scale_amount_min = 0.20
	motes.scale_amount_max = 0.65
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.018)
	var material := _material(Color(0.40, 0.56, 0.56, 0.33), 0.4, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	motes.mesh = quad
	world_root.add_child(motes)


func _add_rubble_cluster(parent: Node3D, center: Vector3, scale_value: float) -> void:
	var offsets := [
		Vector3(-0.48, 0.08, 0.12), Vector3(-0.18, 0.11, -0.27),
		Vector3(0.17, 0.09, 0.20), Vector3(0.46, 0.14, -0.10),
		Vector3(-0.02, 0.17, 0.02), Vector3(0.28, 0.07, 0.35)
	]
	for index in range(offsets.size()):
		var size_value := Vector3(0.34 + float(index % 3) * 0.08, 0.15 + float(index % 2) * 0.09, 0.30 + float((index + 1) % 3) * 0.06) * scale_value
		var rubble := _add_visual_box(parent, "BrokenStone", center + offsets[index] * scale_value, size_value, DUNGEON_CONCEPT.stone_material(index), Vector3(float(index * 9 % 17), float(index * 31 % 83), float(index * 7 % 14)))
		rubble.mesh = DUNGEON_CONCEPT.chipped_block(size_value, index)


func _add_crate(parent: Node3D, position_value: Vector3, size_value: Vector3) -> void:
	var crate := Node3D.new()
	crate.name = "EmptyCrate"
	crate.position = position_value
	crate.rotation_degrees.y = float(_piece_index * 17 % 21) - 10.0
	parent.add_child(crate)
	for side in [-1.0, 1.0]:
		for index in 6:
			var x := (-0.5 + (float(index) + 0.5) / 6.0) * size_value.x
			var z := (-0.5 + (float(index) + 0.5) / 6.0) * size_value.z
			_add_visual_box(crate, "CrateVerticalPlank_%s_%d" % [str(side), index], Vector3(x, size_value.y * 0.5, side * size_value.z * 0.47), Vector3(size_value.x / 6.0 - 0.007, size_value.y * 0.97, 0.05), wood_material)
			_add_visual_box(crate, "CrateSidePlank_%s_%d" % [str(side), index], Vector3(side * size_value.x * 0.47, size_value.y * 0.5, z), Vector3(0.05, size_value.y * 0.97, size_value.z / 6.0 - 0.007), wood_material)
		for height in [0.20, 0.80]:
			_add_visual_box(crate, "CrateBand", Vector3(0.0, size_value.y * height, side * size_value.z * 0.515), Vector3(size_value.x * 1.035, 0.07, 0.035), metal_material)
			_add_visual_box(crate, "CrateSideBand", Vector3(side * size_value.x * 0.515, size_value.y * height, 0.0), Vector3(0.035, 0.07, size_value.z * 1.035), metal_material)
			for across in [-0.42, 0.0, 0.42]:
				DungeonLootChest._add_rivet(crate, Vector3(size_value.x * across, size_value.y * height, side * (size_value.z * 0.515 + 0.02)), Vector3.BACK * side, metal_material)
				DungeonLootChest._add_rivet(crate, Vector3(side * (size_value.x * 0.515 + 0.02), size_value.y * height, size_value.z * across), Vector3.RIGHT * side, metal_material)
	for index in 6:
		var z := (-0.5 + (float(index) + 0.5) / 6.0) * size_value.z * 0.92
		_add_visual_box(crate, "CrateFloorBoard", Vector3(0.0, 0.052, z), Vector3(size_value.x * 0.92, 0.06, size_value.z * 0.92 / 6.0 - 0.005), wood_material)
	for side in [-1.0, 1.0]:
		_add_visual_box(crate, "CrateUndersideBrace", Vector3(side * size_value.x * 0.28, 0.026, 0.0), Vector3(0.065, 0.05, size_value.z * 0.91), wood_material)


func _add_barrel(parent: Node3D, position_value: Vector3, radius: float, height: float) -> void:
	var barrel := Node3D.new()
	barrel.name = "EmptyBarrel"
	barrel.position = position_value
	parent.add_child(barrel)
	var stave_mesh := _barrel_stave_mesh(radius, height)
	for index in 18:
		var stave := MeshInstance3D.new()
		stave.name = "CurvedOakStave%d" % index
		stave.mesh = stave_mesh
		stave.material_override = wood_material
		stave.rotation.y = float(index) * TAU / 18.0
		stave.visibility_range_end = 28.0
		barrel.add_child(stave)
	_add_cylinder_visual(barrel, "BarrelInsetEnds", Vector3(0.0, height * 0.5, 0.0), radius * 0.835, radius * 0.835, height * 0.96, wood_material, 36)
	for y in [height * 0.16, height * 0.84]:
		var ring := MeshInstance3D.new()
		ring.name = "BarrelIronBand"
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.926
		torus.outer_radius = radius * 0.967
		torus.rings = 36
		torus.ring_segments = 4
		ring.mesh = torus
		ring.material_override = metal_material
		ring.position = Vector3(0.0, y, 0.0)
		ring.scale.y = 5.0
		ring.visibility_range_end = 28.0
		barrel.add_child(ring)
		for index in 12:
			var angle := float(index) * TAU / 12.0
			var normal := Vector3(cos(angle), 0.0, sin(angle))
			DungeonLootChest._add_rivet(barrel, normal * radius * 0.967 + Vector3.UP * y, normal, metal_material)


func _barrel_stave_mesh(radius: float, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angle := TAU / 36.0 * 0.974
	for index in 8:
		var t0 := float(index) / 8.0
		var t1 := float(index + 1) / 8.0
		var r0 := radius * (0.88 + sin(t0 * PI) * 0.12)
		var r1 := radius * (0.88 + sin(t1 * PI) * 0.12)
		var a := Vector3(sin(-angle) * r0, t0 * height, cos(angle) * r0)
		var b := Vector3(sin(angle) * r0, t0 * height, cos(angle) * r0)
		var c := Vector3(sin(angle) * r1, t1 * height, cos(angle) * r1)
		var d := Vector3(sin(-angle) * r1, t1 * height, cos(angle) * r1)
		var inset := Vector3(0.0, 0.0, radius * 0.075)
		_prop_quad(surface, a, b, c, d)
		_prop_quad(surface, b - inset, a - inset, d - inset, c - inset)
		_prop_quad(surface, a - inset, a, d, d - inset)
		_prop_quad(surface, b, b - inset, c - inset, c)
		if index == 0:
			_prop_quad(surface, a - inset, b - inset, b, a)
		if index == 7:
			_prop_quad(surface, d, c, c - inset, d - inset)
	surface.generate_normals()
	return surface.commit()


func _prop_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for vertex in [a, b, c, a, c, d]:
		surface.set_uv(Vector2(vertex.x, vertex.y))
		surface.add_vertex(vertex)


func _add_bucket(parent: Node3D, position_value: Vector3, scale_value: float) -> void:
	var bucket := _add_cylinder_visual(parent, "RainBucket", position_value + Vector3(0.0, scale_value * 0.45, 0.0), scale_value * 0.44, scale_value * 0.34, scale_value * 0.9, metal_material, 32)
	(bucket.mesh as CylinderMesh).cap_top = false
	var inside_material := metal_material.duplicate() as StandardMaterial3D
	inside_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	bucket.material_override = inside_material
	for fraction in [0.06, 0.88]:
		var ring := MeshInstance3D.new()
		ring.name = "BucketRolledRim"
		var rim := TorusMesh.new()
		var radius: float = scale_value * (0.34 + float(fraction) / 0.9 * 0.10)
		rim.inner_radius = radius - scale_value * 0.008
		rim.outer_radius = radius + scale_value * 0.012
		rim.rings = 32
		rim.ring_segments = 6
		ring.mesh = rim
		ring.material_override = metal_material
		ring.position = position_value + Vector3.UP * scale_value * fraction
		parent.add_child(ring)
	for index in 16:
		var a0 := float(index) / 16.0 * PI
		var a1 := float(index + 1) / 16.0 * PI
		var from := position_value + Vector3(cos(a0) * scale_value * 0.45, scale_value * (0.77 - sin(a0) * 0.45), -sin(a0) * scale_value * 0.45)
		var to := position_value + Vector3(cos(a1) * scale_value * 0.45, scale_value * (0.77 - sin(a1) * 0.45), -sin(a1) * scale_value * 0.45)
		var handle := _add_cylinder_visual(parent, "BucketBailHandle", (from + to) * 0.5, scale_value * 0.012, scale_value * 0.012, from.distance_to(to), metal_material, 8)
		handle.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = scale_value * 0.422
	water_mesh.bottom_radius = water_mesh.top_radius
	water_mesh.height = 0.002
	water_mesh.radial_segments = 48
	var water := MeshInstance3D.new()
	water.name = "CaughtRainWater"
	water.mesh = water_mesh
	water.material_override = water_material
	water.position = position_value + Vector3(0.0, scale_value * 0.83, 0.0)
	water.visibility_range_end = 22.0
	parent.add_child(water)


func _add_hanging_cloth(parent: Node3D, position_value: Vector3, size_value: Vector2, color_value: Color) -> void:
	var cloth_root := Node3D.new()
	cloth_root.name = "DampHangingCloak"
	cloth_root.position = position_value
	parent.add_child(cloth_root)
	var cloth_mat := AGED_SURFACES.linen(color_value, 3.5)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cloth := MeshInstance3D.new()
	cloth.name = "CloakCloth"
	cloth.mesh = _hanging_cloth_mesh(size_value)
	cloth.material_override = cloth_mat
	cloth_root.add_child(cloth)
	_add_visual_box(cloth_root, "CloakPeg", Vector3(0.0, 0.08, 0.0), Vector3(size_value.x * 1.14, 0.10, 0.12), wood_material)
	swaying_props.append(cloth_root)


func _hanging_cloth_mesh(size_value: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 28:
		for column in 40:
			if row >= 25 and (column * 7) % 19 < 2:
				continue
			var points: Array[Vector3] = []
			for pair in [Vector2(row, column), Vector2(row, column + 1), Vector2(row + 1, column + 1), Vector2(row + 1, column)]:
				var t: float = pair.x / 28.0
				var angle: float = -2.65 + pair.y / 40.0 * 5.30
				var width := size_value.x * (0.10 + smoothstep(0.0, 0.35, t) * 0.39)
				var fold := sin(angle * 9.0 + t * 0.7) * size_value.x * (0.025 + t * 0.025)
				var y := -t * size_value.y + pow(t, 12.0) * sin(angle * 13.0) * size_value.y * 0.05
				points.append(Vector3(sin(angle) * (width + fold), y, cos(angle) * (size_value.x * 0.13 + fold)))
			_prop_quad(surface, points[0], points[1], points[2], points[3])
	surface.generate_normals()
	return surface.commit()


func _add_hanging_herbs(parent: Node3D, position_value: Vector3) -> void:
	var herb_root := Node3D.new()
	herb_root.name = "DryingHerbs"
	herb_root.position = position_value
	parent.add_child(herb_root)
	_add_visual_box(herb_root, "HerbCord", Vector3.ZERO, Vector3(1.7, 0.04, 0.04), straw_material)
	for index in range(5):
		var x := -0.68 + float(index) * 0.34
		_add_visual_box(herb_root, "HerbStem", Vector3(x, -0.38, 0.0), Vector3(0.035, 0.78, 0.035), moss_material, Vector3(0.0, 0.0, -8.0 + float(index) * 3.0))
		var leaves := MeshInstance3D.new()
		leaves.name = "DriedHerbBundle"
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for leaf_index in 36:
			var angle := float(leaf_index) * 2.399
			var y := -0.43 - float(leaf_index) / 36.0 * 0.48
			var stem := Vector3(x, y, 0)
			var reach := Vector3(cos(angle) * 0.15, -0.10, sin(angle) * 0.15)
			var width_axis := Vector3(-sin(angle), 0, cos(angle)) * 0.045
			_prop_quad(surface, stem, stem + reach * 0.52 + width_axis, stem + reach, stem + reach * 0.52 - width_axis)
		surface.generate_normals()
		leaves.mesh = surface.commit()
		var herb_material := AGED_SURFACES.linen(Color(0.22, 0.22, 0.105), 5.0)
		herb_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaves.material_override = herb_material
		herb_root.add_child(leaves)
	swaying_props.append(herb_root)


func _add_candle_cluster(parent: Node3D, base_position: Vector3, count: int) -> void:
	for index in range(count):
		var offset := Vector3(float(index % 2) * 0.19, 0.0, float(index / 2) * 0.16)
		var height := 0.24 + float(index % 3) * 0.08
		_add_cylinder_visual(parent, "UsedCandle", base_position + offset + Vector3(0.0, height * 0.5, 0.0), 0.035, 0.045, height, bone_material, 20)
		for drip_index in 8:
			var angle := float(drip_index) * TAU / 8.0
			var drip_height := height * (0.15 + 0.42 * absf(sin(float(drip_index) * 1.71 + float(index))))
			var drip := _add_cylinder_visual(parent, "CandleWaxDrip", base_position + offset + Vector3(cos(angle) * 0.036, height - drip_height * 0.5, sin(angle) * 0.036), 0.006, 0.005, drip_height, bone_material, 8)
			drip.rotation.z = sin(angle * 2.0) * 0.06
		_add_cylinder_visual(parent, "CharredCandleWick", base_position + offset + Vector3.UP * (height + 0.014), 0.0025, 0.003, 0.030, dark_material, 6)
		var flame := _add_flame(parent, base_position + offset + Vector3(0.0, height + 0.035, 0.0), 0.16, Color(1.0, 0.46, 0.18))
		flame.scale = Vector3.ONE * 0.65


func _empty_sack_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 20:
		for radial in 40:
			var points: Array[Vector3] = []
			for pair in [Vector2(row, radial), Vector2(row, radial + 1), Vector2(row + 1, radial + 1), Vector2(row + 1, radial)]:
				var t: float = pair.x / 20.0
				var angle: float = pair.y / 40.0 * TAU
				var radius := 0.40 + sin(t * PI) * 0.11 - t * 0.14 + sin(angle * 11.0 + t * 2.0) * 0.02
				var y := -0.29 + t * 0.59 + sin(angle * 4.0) * 0.024 * t
				points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius * 0.70))
			_prop_quad(surface, points[0], points[3], points[2], points[1])
	for radial in 40:
		var a0 := float(radial) / 40.0 * TAU
		var a1 := float(radial + 1) / 40.0 * TAU
		_prop_quad(surface, Vector3.ZERO + Vector3.DOWN * 0.28, Vector3(cos(a0) * 0.40, -0.28, sin(a0) * 0.28), Vector3(cos(a1) * 0.40, -0.28, sin(a1) * 0.28), Vector3.ZERO + Vector3.DOWN * 0.28)
	surface.generate_normals()
	return surface.commit()


func _add_moss_patch(parent: Node3D, position_value: Vector3, size_value: Vector2, yaw_degrees: float) -> void:
	var quad := QuadMesh.new()
	quad.size = size_value
	var patch := MeshInstance3D.new()
	patch.name = "DampMossPatch"
	patch.mesh = DUNGEON_CONCEPT.irregular_patch(size_value, 0.014)
	var moss := AGED_SURFACES.stone(Color(0.17, 0.225, 0.095), 3.0)
	moss.cull_mode = BaseMaterial3D.CULL_DISABLED
	patch.material_override = moss
	patch.position = position_value
	patch.rotation_degrees.y = yaw_degrees
	patch.visibility_range_end = 25.0
	parent.add_child(patch)


func _add_iron_gate(parent: Node3D, gate_position: Vector3, width: float, height: float, along_x: bool) -> void:
	var gate := Node3D.new()
	gate.name = "SealedIronGate"
	gate.position = gate_position
	parent.add_child(gate)
	var bar_count := maxi(4, roundi(width / 0.48))
	for index in range(bar_count):
		var across := -width * 0.5 + width * float(index) / float(bar_count - 1)
		var position_value := Vector3(0.0, height * 0.5, across) if along_x else Vector3(across, height * 0.5, 0.0)
		_add_visual_box(gate, "GateBar", position_value, Vector3(0.09, height, 0.09), metal_material)
		if not along_x:
			var spike := _add_cylinder_visual(gate, "GateSpearPoint", position_value + Vector3.UP * (height * 0.5 + 0.12), 0.0, 0.060, 0.24, metal_material, 4)
			spike.rotation.y = PI * 0.25
		for y in [0.45, height - 0.45]:
			for face in [-1.0, 1.0]:
				var rivet_at := Vector3(face * 0.09, y, across) if along_x else Vector3(across, y, face * 0.09)
				DungeonLootChest._add_rivet(gate, rivet_at, Vector3.RIGHT * face if along_x else Vector3.BACK * face, metal_material)
	for y in [0.45, height - 0.45]:
		var size_value := Vector3(0.15, 0.16, width) if along_x else Vector3(width, 0.16, 0.15)
		_add_visual_box(gate, "GateCrossBrace", Vector3(0.0, y, 0.0), size_value, metal_material)


func _add_niche_wall(parent: Node3D, origin: Vector3, columns: int, rows: int, yaw_degrees := 0.0) -> void:
	var root_node := Node3D.new()
	root_node.name = "OssuaryNicheCluster"
	root_node.position = origin
	root_node.rotation_degrees.y = yaw_degrees
	parent.add_child(root_node)
	for row in range(rows):
		for column in range(columns):
			var x := (float(column) - float(columns - 1) * 0.5) * 1.08
			var y := 0.78 + float(row) * 1.08
			_add_visual_box(root_node, "NicheVoid", Vector3(x, y, 0.19), Vector3(0.78, 0.78, 0.06), dark_material)
			for side in [-1.0, 1.0]:
				_add_visual_box(root_node, "NicheFrame", Vector3(x + side * 0.46, y, 0.01), Vector3(0.16, 0.95, 0.42), stone_material)
			_add_visual_box(root_node, "NicheLintel", Vector3(x, y + 0.46, 0.01), Vector3(1.02, 0.15, 0.42), DUNGEON_CONCEPT.stone_material(row + column))
			_add_visual_box(root_node, "NicheSill", Vector3(x, y - 0.46, 0.01), Vector3(1.02, 0.15, 0.42), DUNGEON_CONCEPT.stone_material(row + column))
			_add_visual_box(root_node, "NicheBackStone", Vector3(x, y, 0.25), Vector3(0.91, 0.95, 0.06), DUNGEON_CONCEPT.stone_material(row))
			if (row + column) % 3 != 1:
				_add_skull(root_node, Vector3(x, y - 0.08, -0.02), 0.23)


func _add_skull(parent: Node3D, position_value: Vector3, scale_value: float) -> void:
	var skull := SKULL_VISUAL.create(scale_value * 2.2)
	skull.name = "WeatheredSkull"
	skull.position = position_value
	skull.visibility_range_end = 20.0
	parent.add_child(skull)


func _add_cold_rune(parent: Node3D, position_value: Vector3, size_value: Vector2) -> void:
	var material := _material(Color(0.06, 0.52, 0.48, 0.52), 0.22, 0.05)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.02, 0.58, 0.52)
	material.emission_energy_multiplier = 1.8
	material.albedo_texture = RUNE_TEXTURE
	material.emission_texture = RUNE_TEXTURE
	var plane := PlaneMesh.new()
	plane.size = size_value
	var rune := MeshInstance3D.new()
	rune.name = "DormantExpansionRune"
	rune.mesh = plane
	rune.material_override = material
	rune.position = position_value
	parent.add_child(rune)


func _add_interactable(
	parent: Node3D,
	node_name: String,
	action_id: String,
	prompt_text: String,
	position_value: Vector3,
	size_value: Vector3,
	offset_value: Vector3,
	duration_value: float
) -> HideoutInteractable:
	var interactable := INTERACTABLE_SCRIPT.new() as HideoutInteractable
	interactable.name = node_name
	interactable.configure(action_id, prompt_text, size_value, offset_value, duration_value)
	interactable.position = position_value
	interactable.activated.connect(_on_hideout_interaction)
	parent.add_child(interactable)
	return interactable


func _spawn_hud() -> void:
	hideout_hud = HIDEOUT_HUD_SCRIPT.new() as DungeonHUD
	hideout_hud.name = "HideoutHUD"
	add_child(hideout_hud)


func _spawn_inventory_overlay() -> void:
	inventory_overlay = INVENTORY_OVERLAY_SCRIPT.new() as InventoryOverlay
	inventory_overlay.name = "HideoutInventoryOverlay"
	inventory_overlay.closed.connect(_on_inventory_closed)
	inventory_overlay.consumable_requested.connect(_on_consumable_requested)
	inventory_overlay.treatment_part_selected.connect(_on_treatment_part_selected)
	inventory_overlay.item_discarded.connect(_on_item_discarded)
	add_child(inventory_overlay)


func _on_item_discarded(stack: Dictionary) -> void:
	var dropped := DROPPED_ITEM_SCRIPT.spawn_discarded(world_root, player, stack)
	inventory_overlay.set_status("%s을(를) 바닥에 놓았습니다. 가방을 닫고 E로 주울 수 있습니다." % ExpeditionInventory.get_item_name(str(stack.get("id", ""))) if is_instance_valid(dropped) else "안전하게 놓을 바닥이 없어 물품을 되돌렸습니다.")


func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new() as DungeonPlayer
	player.name = "HideoutPlayer"
	player.position = Vector3(0.0, 1.0, 17.2)
	player.rotation.y = 0.0
	player.configure_safe_zone(true)
	player.setup(self, hideout_hud, inventory)
	add_child(player)
	RUIN_VISUAL.apply_exploration_light(player)


func _build_interface() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.name = "DestinationInterface"
	_ui_canvas.layer = 20
	add_child(_ui_canvas)
	door_button = Button.new()
	door_button.name = "SanctuaryDoorButton"
	door_button.visible = false
	door_button.text = "입구 클릭  ·  원정 지도"
	door_button.tooltip_text = "계단 위 입구를 클릭하면 원정 지도가 열립니다. M 단축키도 사용할 수 있습니다."
	door_button.position = Vector2(1082, 654)
	door_button.size = Vector2(174, 42)
	door_button.focus_mode = Control.FOCUS_NONE
	door_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	door_button.add_theme_font_override("font", ui_medium_font)
	door_button.add_theme_font_size_override("font_size", 12)
	door_button.add_theme_color_override("font_color", Color(0.66, 0.72, 0.69, 0.66))
	door_button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	door_button.add_theme_color_override("font_focus_color", COLOR_IVORY)
	door_button.add_theme_stylebox_override("normal", _panel_style(Color(0.005, 0.012, 0.013, 0.48), Color(0.24, 0.34, 0.33, 0.62), 1, 2))
	door_button.add_theme_stylebox_override("hover", _panel_style(Color(0.035, 0.08, 0.075, 0.90), Color(0.54, 0.68, 0.63, 0.94), 1, 2))
	door_button.add_theme_stylebox_override("focus", _panel_style(Color(0.035, 0.08, 0.075, 0.90), Color(0.54, 0.68, 0.63, 0.94), 1, 2))
	door_button.pressed.connect(_open_destination_map)
	_ui_canvas.add_child(door_button)
	footer_status_label = _label("", 10, COLOR_MUTED)
	footer_status_label.name = "HideoutFooterStatus"
	footer_status_label.visible = false
	_ui_canvas.add_child(footer_status_label)

	modal_scrim = ColorRect.new()
	modal_scrim.name = "DestinationModalScrim"
	modal_scrim.color = Color(0.002, 0.004, 0.005, 0.86)
	modal_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_scrim.visible = false
	_ui_canvas.add_child(modal_scrim)
	destination_panel = _build_destination_panel()
	modal_scrim.add_child(destination_panel)
	fade_layer = ColorRect.new()
	fade_layer.name = "HideoutSceneFade"
	fade_layer.color = Color(0, 0, 0, 0)
	fade_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.z_index = 100
	_ui_canvas.add_child(fade_layer)


func _open_destination_map() -> void:
	if hideout_mode != HideoutMode.RUNNING or transitioning:
		return
	hideout_mode = HideoutMode.MAP
	if is_instance_valid(player):
		player.prepare_for_inventory()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_panel(destination_panel, destination_merchant_button)


func _try_open_entrance_from_click(screen_position: Vector2) -> bool:
	if hideout_mode != HideoutMode.RUNNING or transitioning or not is_instance_valid(player) or not is_instance_valid(player.camera):
		return false
	var click_position := screen_position
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		click_position = get_viewport().get_visible_rect().size * 0.5
	var ray_origin := player.camera.project_ray_origin(click_position)
	var ray_end := ray_origin + player.camera.project_ray_normal(click_position) * ENTRANCE_CLICK_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, WORLD_LAYER | INTERACT_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = true
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider := result.get("collider") as CollisionObject3D
	if collider == null or not collider.has_meta("interaction_owner"):
		return false
	var owner := collider.get_meta("interaction_owner") as Node
	if not owner is HideoutInteractable:
		return false
	var entrance := owner as HideoutInteractable
	if entrance.name != "EntranceTravelInteraction" or entrance.action_id != "travel":
		return false
	entrance.interact(player)
	return true


func _close_modal() -> void:
	var was_open := current_panel != null
	super._close_modal()
	if was_open and not transitioning:
		if is_instance_valid(door_button):
			door_button.focus_mode = Control.FOCUS_NONE
		get_viewport().gui_release_focus()
		get_tree().paused = false
		hideout_mode = HideoutMode.RUNNING
		_set_play_mouse_mode()


func _travel_to_destination(scene_path: String) -> void:
	if is_instance_valid(player): player.cancel_item_use()
	if transitioning:
		return
	cancel_alchemy()
	cancel_cooking()
	hideout_mode = HideoutMode.TRANSITIONING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await super._travel_to_destination(scene_path)


func _open_inventory() -> void:
	if hideout_mode != HideoutMode.RUNNING or inventory_overlay == null:
		return
	hideout_mode = HideoutMode.INVENTORY
	if is_instance_valid(player):
		player.prepare_for_inventory()
	if is_instance_valid(hideout_hud):
		hideout_hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status_provider := Callable(player, "get_inventory_status_snapshot") if is_instance_valid(player) else Callable()
	inventory_overlay.open_inventory(inventory, status_provider)
	get_tree().paused = true


func _close_inventory() -> void:
	if hideout_mode != HideoutMode.INVENTORY:
		return
	if inventory_overlay.is_open():
		inventory_overlay.close()
		if inventory_overlay.is_open():
			return
	_on_inventory_closed()


func _on_inventory_closed() -> void:
	if hideout_mode != HideoutMode.INVENTORY:
		return
	hideout_mode = HideoutMode.RUNNING
	get_tree().paused = false
	get_viewport().gui_release_focus()
	_set_play_mouse_mode()


func _on_consumable_requested(item_id: String) -> void:
	if hideout_mode != HideoutMode.INVENTORY or not is_instance_valid(player):
		return
	var result := player.begin_item_use(item_id, inventory, true)
	var message := str(result.get("message", "물품을 사용할 수 없습니다."))
	inventory_overlay.set_status(message)
	if bool(result.get("accepted", false)):
		_close_inventory()
		inventory_overlay.refresh_status_readout()
		if is_instance_valid(hideout_hud):
			hideout_hud.show_event(message, 1.2)


func _on_treatment_part_selected(part_id: String) -> void:
	if hideout_mode != HideoutMode.INVENTORY or not is_instance_valid(player):
		return
	if player.select_treatment_part(part_id):
		inventory_overlay.refresh_status_readout()


func _pause_hideout() -> void:
	if is_instance_valid(player): player.cancel_item_use()
	hideout_mode = HideoutMode.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(hideout_hud):
		hideout_hud.show_overlay("은신처에서 잠시 멈춤", "ESC · 돌아가기\nM · 원정 지도    I · 가방")


func _resume_hideout() -> void:
	get_tree().paused = false
	hideout_mode = HideoutMode.RUNNING
	if is_instance_valid(hideout_hud):
		hideout_hud.hide_overlay()
	get_viewport().gui_release_focus()
	_set_play_mouse_mode()


func _on_hideout_interaction(action_id: String, _player_node: Node) -> void:
	match action_id:
		"travel":
			_open_destination_map()
		"stash":
			_open_inventory()
		"rest":
			_rest_at_bed()
		"hearth":
			_toggle_hearth()
		"meal":
			_open_cooking()
		"wash":
			hideout_hud.show_event("차가운 빗물로 피와 먼지를 씻었습니다", 1.8)
		"workbench":
			_open_blacksmith()
		"alchemy":
			_open_alchemy()
		"storage":
			hideout_hud.show_event("선반 대부분이 비어 있습니다 · 보급품이 쌓이면 이 방도 살아날 것입니다", 2.4)
		"flooded_store":
			hideout_hud.show_event("배수 장치가 고장 나 있습니다 · 물을 빼면 재배실로 쓸 수 있습니다", 2.4)
		"ossuary_gate":
			hideout_hud.show_event("납골당의 봉인이 안쪽에서 맥박칩니다 · 은신처 2단계에서 개방", 2.5)
		"drain_gate":
			hideout_hud.show_event("이 수로는 늪지대로 이어집니다 · 배수문 복구 후 보조 출구로 사용 가능", 2.5)


func _rest_at_bed() -> void:
	if hideout_mode != HideoutMode.RUNNING:
		return
	hideout_mode = HideoutMode.RESTING
	if is_instance_valid(player):
		player.set_physics_process(false)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_layer, "color", Color(0.005, 0.009, 0.012, 1.0), 0.34)
	await tween.finished
	await get_tree().create_timer(0.28).timeout
	if is_instance_valid(player):
		player.restore_health(player.get_max_health())
		player.stamina = 100.0
	var wake_tween := create_tween()
	wake_tween.tween_property(fade_layer, "color", Color(0, 0, 0, 0), 0.48)
	await wake_tween.finished
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(player):
		player.set_physics_process(true)
	hideout_mode = HideoutMode.RUNNING
	hideout_hud.show_event("축축한 침상에서도 잠은 들었습니다 · 몸과 원정 장비를 추슬렀습니다", 2.4)


func _toggle_hearth() -> void:
	brazier_lit = not brazier_lit
	if is_instance_valid(hearth_flame):
		hearth_flame.visible = brazier_lit
	if is_instance_valid(hearth_light):
		hearth_light.visible = brazier_lit
	for child in hearth_root.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("EmberLog"):
			(child as MeshInstance3D).visible = brazier_lit
	hideout_hud.show_event("젖은 장작에 다시 불씨를 살렸습니다" if brazier_lit else "화로의 불씨를 재 속에 묻었습니다", 1.8)


func _announce_arrival() -> void:
	if is_instance_valid(hideout_hud):
		hideout_hud.show_event("침수된 순례자 납골당 · 아무도 원하지 않아 당신에게 남은 은신처", 3.2)


func _update_player_region() -> void:
	if not is_instance_valid(player) or hideout_mode != HideoutMode.RUNNING:
		return
	var zone_id := _zone_for_position(player.global_position)
	if zone_id == _current_zone_id:
		return
	_current_zone_id = zone_id
	if zone_id.is_empty() or _visited_zones.has(zone_id):
		return
	_visited_zones[zone_id] = true
	var names := {
		"entrance": "무너진 예배당 계단",
		"central": "중앙 저수 홀",
		"sleep": "관리인의 골방",
		"storage": "텅 빈 저장고",
		"workshop": "성소의 대장간",
		"flooded_store": "침수된 보관실",
		"ossuary": "봉인된 납골실",
		"drain": "봉인된 배수 수로"
	}
	if zone_id != "entrance" and names.has(zone_id):
		hideout_hud.show_event(str(names[zone_id]), 1.25)


func _zone_for_position(position_value: Vector3) -> String:
	if position_value.z > 10.0:
		return "entrance"
	if position_value.x < -8.0 and position_value.z > 1.5:
		return "sleep"
	if position_value.x < -8.0 and position_value.z < -1.5:
		return "flooded_store"
	if position_value.x > 16.0:
		return "drain"
	if position_value.x > 8.0 and position_value.z > 1.5:
		return "storage"
	if position_value.x > 8.0 and position_value.z < -1.5:
		return "workshop"
	if position_value.z < -10.0:
		return "ossuary"
	return "central"


func _animate_water() -> void:
	if water_material != null:
		water_material.uv1_offset = Vector3(elapsed * 0.008, elapsed * 0.005, 0.0)
	for index in range(water_surfaces.size()):
		var water := water_surfaces[index]
		if is_instance_valid(water):
			water.position.y = float(water.get_meta("rest_height", 0.04)) + sin(elapsed * 0.72 + float(index) * 1.9) * 0.004


func _animate_lights() -> void:
	for entry in flicker_lights:
		var light := entry.get("light") as OmniLight3D
		if not is_instance_valid(light) or not light.visible:
			continue
		var base_energy := float(entry.get("base", 1.0))
		var phase := float(entry.get("phase", 0.0))
		light.light_energy = base_energy * (0.91 + sin(elapsed * 8.7 + phase) * 0.055 + sin(elapsed * 19.1 + phase * 0.7) * 0.025)


func _animate_hanging_props() -> void:
	for index in range(swaying_props.size()):
		var prop := swaying_props[index]
		if is_instance_valid(prop):
			prop.rotation.z = sin(elapsed * 0.48 + float(index) * 1.7) * 0.012


func _set_play_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.get_name() == "headless" else Input.MOUSE_MODE_CAPTURED


func _focus_default() -> void:
	if is_instance_valid(door_button):
		door_button.focus_mode = Control.FOCUS_NONE
	get_viewport().gui_release_focus()


func _register_hideout_inputs() -> void:
	_register_key("move_forward", KEY_W)
	_register_key("move_back", KEY_S)
	_register_key("move_left", KEY_A)
	_register_key("move_right", KEY_D)
	_register_key("sprint", KEY_SHIFT)
	_register_key("jump", KEY_SPACE)
	_register_key("interact", KEY_E)
	_register_key("torch", KEY_F)
	_register_key("inventory", KEY_I)
	_register_key("map", KEY_M)
	_register_key("pause", KEY_ESCAPE)
	_register_mouse("attack", MOUSE_BUTTON_LEFT)
	_register_mouse("block", MOUSE_BUTTON_RIGHT)


func _register_key(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _register_mouse(action: StringName, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _disable_imported_collisions(root: Node) -> void:
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_disable_imported_collisions(child)


func _set_meshes_visible_by_prefix(root: Node, prefixes: Array, visible_value: bool) -> void:
	if root is GeometryInstance3D and _name_starts_with_any(String(root.name), prefixes):
		(root as GeometryInstance3D).visible = visible_value
	for child in root.get_children():
		_set_meshes_visible_by_prefix(child, prefixes, visible_value)


func _apply_material_to_prefix(root: Node, prefixes: Array, material: Material) -> void:
	if root is MeshInstance3D and _name_starts_with_any(String(root.name), prefixes):
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_material_to_prefix(child, prefixes, material)


func _apply_material_recursive(root: Node, material: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_material_recursive(child, material)


func _set_visibility_range_recursive(root: Node, end_distance: float) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).visibility_range_end = end_distance
		(root as GeometryInstance3D).visibility_range_end_margin = 4.0
	for child in root.get_children():
		_set_visibility_range_recursive(child, end_distance)


func _name_starts_with_any(node_name: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if node_name.begins_with(String(prefix)):
			return true
	return false


func _material(color_value: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material


func _textured_material(
	color_value: Color,
	texture_value: Texture2D,
	roughness_value: float,
	metallic_value: float,
	texture_scale: float
) -> StandardMaterial3D:
	var material := _material(color_value, roughness_value, metallic_value)
	material.albedo_texture = texture_value
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 42.0
	material.uv1_scale = Vector3.ONE * texture_scale
	return material


func _open_blacksmith() -> void:
	if hideout_mode != HideoutMode.RUNNING or transitioning:
		return
	if not is_instance_valid(blacksmith_overlay):
		blacksmith_overlay = BLACKSMITH_OVERLAY.new()
		blacksmith_overlay.name = "BlacksmithOverlay"
		blacksmith_overlay.closed.connect(_on_blacksmith_closed)
		add_child(blacksmith_overlay)
	hideout_mode = HideoutMode.BLACKSMITH
	_smithing_world_was_visible = world_root.visible
	_smithing_player_was_visible = player.visible
	world_root.hide()
	player.hide()
	player.viewmodel_renderer.sync_view()
	player.prepare_for_inventory()
	hideout_hud.set_prompt("")
	hideout_hud.hide()
	door_button.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	blacksmith_overlay.open_for_inventory(inventory)
	get_tree().paused = true


func _on_blacksmith_closed() -> void:
	if hideout_mode != HideoutMode.BLACKSMITH:
		return
	world_root.visible = _smithing_world_was_visible
	player.visible = _smithing_player_was_visible
	player.viewmodel_renderer.sync_view()
	hideout_mode = HideoutMode.RUNNING
	get_tree().paused = false
	hideout_hud.show()
	get_viewport().gui_release_focus()
	_set_play_mouse_mode()


func cancel_blacksmith() -> void:
	# Sandbox exit must never recapture the pointer or alter restored inventory.
	if is_instance_valid(blacksmith_overlay):
		blacksmith_overlay.cancel_work()
	if hideout_mode == HideoutMode.BLACKSMITH:
		hideout_mode = HideoutMode.TRANSITIONING
		get_tree().paused = false


func _open_blacksmith_trial() -> void:
	var sandbox := get_node_or_null("/root/TestRoomSandbox")
	if sandbox == null or not sandbox.active:
		return
	var requested: String = sandbox.consume_blacksmith_trial()
	if requested.is_empty():
		return
	player.global_position = Vector3(11.8, 1.0, -4.0)
	player.rotation.y = 0.0
	_open_blacksmith()
	blacksmith_overlay.show_station(requested)


func _open_alchemy() -> void:
	if hideout_mode != HideoutMode.RUNNING or transitioning:
		return
	if not is_instance_valid(alchemy_overlay):
		alchemy_overlay = ALCHEMY_OVERLAY.new()
		alchemy_overlay.name = "AlchemyOverlay"
		alchemy_overlay.closed.connect(_on_alchemy_closed)
		add_child(alchemy_overlay)
	hideout_mode = HideoutMode.ALCHEMY
	_alchemy_world_was_visible = world_root.visible
	_alchemy_player_was_visible = player.visible
	world_root.hide()
	player.hide()
	player.viewmodel_renderer.sync_view()
	player.prepare_for_inventory()
	hideout_hud.set_prompt("")
	hideout_hud.hide()
	door_button.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Reopening this same bench resumes its unfinished batch. Only leaving the
	# hideout or explicitly discarding it cancels already consumed ingredients.
	alchemy_overlay.open_for_inventory(inventory)
	get_tree().paused = true


func _on_alchemy_closed() -> void:
	if hideout_mode != HideoutMode.ALCHEMY:
		return
	world_root.visible = _alchemy_world_was_visible
	player.visible = _alchemy_player_was_visible
	player.viewmodel_renderer.sync_view()
	hideout_mode = HideoutMode.RUNNING
	get_tree().paused = false
	hideout_hud.show()
	get_viewport().gui_release_focus()
	_set_play_mouse_mode()


func cancel_alchemy() -> void:
	# Transition cleanup must never recapture the pointer or touch a restored
	# original inventory. Batch state belongs exclusively to this local bench.
	if hideout_mode == HideoutMode.ALCHEMY:
		hideout_mode = HideoutMode.TRANSITIONING
		get_tree().paused = false
	if is_instance_valid(alchemy_overlay):
		alchemy_overlay.cancel_work()


func _open_alchemy_trial() -> void:
	var sandbox := get_node_or_null("/root/TestRoomSandbox")
	if sandbox == null or not sandbox.active:
		return
	var requested: String = sandbox.consume_alchemy_trial()
	if requested.is_empty():
		return
	player.global_position = Vector3(11.1, 1.0, -4.35)
	player.rotation.y = PI
	_open_alchemy()
	alchemy_overlay.select_recipe(requested)


func _open_cooking() -> void:
	if hideout_mode != HideoutMode.RUNNING or transitioning:
		return
	if not is_instance_valid(cooking_controller):
		cooking_controller = COOKING_CONTROLLER.new()
		cooking_controller.name = "HearthCookingController"
		cooking_controller.opened.connect(_on_cooking_opened)
		cooking_controller.closed.connect(_on_cooking_closed)
		add_child(cooking_controller)
		cooking_controller.setup(self, player, inventory, cooking_world)
	var result: Dictionary = cooking_controller.open_kitchen()
	if not bool(result.get("accepted", false)):
		hideout_hud.show_event(str(result.get("message", "지금은 조리 기구를 사용할 수 없습니다.")), 2.0)


func _on_cooking_opened() -> void:
	hideout_mode = HideoutMode.COOKING
	player.prepare_for_inventory()
	hideout_hud.set_prompt("")
	hideout_hud.hide()
	door_button.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _on_cooking_closed(_reason: String, restore_controls: bool) -> void:
	if hideout_mode != HideoutMode.COOKING or not restore_controls:
		return
	hideout_mode = HideoutMode.RUNNING
	get_tree().paused = false
	hideout_hud.show()
	get_viewport().gui_release_focus()
	_set_play_mouse_mode()


func cancel_cooking() -> void:
	# Stop completion before sandbox restoration or scene loading can replace
	# the session; transition cleanup must not capture the user's pointer.
	if hideout_mode == HideoutMode.COOKING:
		hideout_mode = HideoutMode.TRANSITIONING
		get_tree().paused = false
	if is_instance_valid(cooking_controller):
		cooking_controller.close_kitchen("조리를 중단했습니다. 사용한 재료는 반환되지 않습니다.", false)


func _open_cooking_trial() -> void:
	var sandbox := get_node_or_null("/root/TestRoomSandbox")
	if sandbox == null or not sandbox.active or not sandbox.consume_cooking_trial():
		return
	player.global_position = Vector3(0.0, 1.0, 4.7)
	player.rotation.y = 0.0
	player._pitch = -0.2
	player.head.rotation.x = player._pitch
	player.health = 35.0
	player.stamina = 20.0
	ExpeditionSession.clear_conditions()
	ExpeditionSession.hunger = 15.0
	ExpeditionSession.thirst = 20.0
	ExpeditionSession.set_stress(55.0)
	_open_cooking()


func _open_ruin_trial() -> void:
	var sandbox := get_node_or_null("/root/TestRoomSandbox")
	if sandbox == null or not sandbox.active:
		return
	var room_id: String = sandbox.consume_hideout_view()
	var shot := HIDEOUT_RUIN_VIEWS.get_shot(room_id)
	if shot.is_empty() or not is_instance_valid(player) or not is_instance_valid(player.camera):
		return
	# Camera positions are shared with the room renderer. Move the real actor
	# by its actual camera offset so the trial remains ordinary playable space.
	var eye: Vector3 = shot.position
	var direction := ((shot.target as Vector3) - eye).normalized()
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-direction.x, -direction.z)
	player._pitch = asin(clampf(direction.y, -1.0, 1.0))
	player.head.rotation.x = player._pitch
	player.camera.position = Vector3.ZERO
	player.camera.fov = float(shot.fov)
	player.global_position += eye - player.camera.global_position
	player.reset_physics_interpolation()
	if is_instance_valid(player.viewmodel_renderer):
		player.viewmodel_renderer.sync_view()
	# Keep the applied live camera transform for inspection at this exact
	# routing boundary. Normal gravity resumes during the loading fade and
	# can settle the standing capsule before the next scene observer runs.
	set_meta("ruin_trial_camera", {"room_id": room_id, "transform": player.camera.global_transform, "fov": player.camera.fov, "player_position": player.global_position, "physics_processing": player.is_physics_processing()})
	_update_player_region()
	hideout_hud.show_event("%s · WASD 탐색 / E 생활 기능 / F 횃불 / F2 복귀" % str(shot.title), 4.0)
