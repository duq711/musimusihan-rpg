extends Node3D

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const TRAP_SCRIPT := preload("res://scripts/trap.gd")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const INVENTORY_OVERLAY_SCRIPT := preload("res://scripts/inventory_overlay.gd")
const DROPPED_ITEM_SCRIPT := preload("res://scripts/dropped_item.gd")
const LOOT_CHEST_SCRIPT := preload("res://scripts/loot_chest.gd")
const LOOT_SPAWN_CATALOG := preload("res://scripts/loot_spawn_catalog.gd")
const LOADING_SCREEN_SCRIPT := preload("res://scripts/loading_screen.gd")
const CAMP_CONTROLLER_SCRIPT := preload("res://scripts/camp_controller.gd")
const STRESS_PERCEPTION_SCRIPT := preload("res://scripts/stress_perception.gd")
const GAME_SCENE_PATH := "res://main.tscn"
const MERCHANT_SCENE_PATH := "res://merchant.tscn"

const WALL_TEXTURE := preload("res://assets/ai/materials/ossuary_wall.png")
const FLOOR_TEXTURE := preload("res://assets/ai/materials/wet_flagstone.png")
const PORTAL_TEXTURE := preload("res://assets/ai/vfx/extraction_portal.png")
const TORCH_FLAME_TEXTURE := preload("res://assets/ai/vfx/torch_flame.png")
const PITTED_IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const ANCIENT_OAK_TEXTURE := preload("res://assets/ai/materials/ancient_oak.png")
const FLAME_VISUALS := preload("res://scripts/flame_visuals.gd")
const DUNGEON_CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const STONE_BATCHES := preload("res://scripts/static_stone_batches.gd")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const PORTAL_ARCH_SCENE := preload("res://assets/3d/dark_fantasy/sanctum_portal_arch.glb")
const PILLAR_SCENE := preload("res://assets/3d/dark_fantasy/dungeon_pillar_3m.glb")
const TORCH_SCENE := preload("res://assets/3d/dark_fantasy/iron_cage_torch.glb")
const EQUIPMENT_CONCEPT := preload("res://scripts/equipment_concept_visual.gd")

const PLAYER_LAYER := 1
const WORLD_LAYER := 2

enum GameMode { RUNNING, PAUSED, INVENTORY, DEAD, WON, CAMPING }

var game_mode := GameMode.RUNNING
var hud: DungeonHUD
var player: DungeonPlayer
var inventory: ExpeditionInventory
var inventory_overlay: InventoryOverlay
var camp: Node
var stress_effects: Node
var _stress_warning_stage := 0
var _window_focused := true
var _camp_hud_was_visible := true
var loot_chests: Array[DungeonLootChest] = []
# Scene-local seed injection enables reproducible test runs without changing
# expedition state. The ordinary -1 value produces a fresh roll on entry.
var loot_spawn_seed := -1
var loot_spawn_sites: Array[Dictionary] = []
var loot_spawn_selection: Array[Dictionary] = []
var _loot_spawn_initialized := false
var active_loot_chest: DungeonLootChest
var enemies_alive := 0
var loot_count := 0
var traps_disarmed := 0
var traps_triggered := 0
var portal_material: StandardMaterial3D
var portal_visual: MeshInstance3D
var elapsed := 0.0
var loading_screen: SanctuaryLoadingScreen
var _loading_failure_message := "장면을 불러올 수 없습니다"
var _survival_warning_level := 0

var stone_material: StandardMaterial3D
var floor_material: StandardMaterial3D
var metal_material: StandardMaterial3D


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Actors update movement and rendered weapon poses at the default priority;
	# combat is resolved here afterward so every clash compares the same frame.
	process_physics_priority = 100
	_register_inputs()


func _ready() -> void:
	inventory = ExpeditionSession.get_inventory()
	_build_materials()
	_build_environment()
	_build_dungeon()
	_spawn_hud()
	_spawn_inventory_overlay()
	_spawn_player()
	_spawn_stress_effects()
	_spawn_camp()
	_spawn_encounters()
	_spawn_loot_chests()
	_build_extraction_gate()
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	_refresh_survival_hud()
	_stress_warning_stage = StressProfile.stage_index(ExpeditionSession.stress)
	get_tree().paused = false
	game_mode = GameMode.RUNNING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if game_mode == GameMode.RUNNING and not get_tree().paused and not is_instance_valid(loading_screen):
		elapsed += delta
		_advance_survival(delta)
		if Input.is_action_just_pressed("torch") and is_instance_valid(player):
			var torch_on := player.toggle_torch()
			hud.show_event("횃불을 밝혔습니다" if torch_on else "횃불을 껐습니다", 0.8)
	_update_stress_presentation()
	if portal_visual:
		portal_visual.rotation.z = sin(elapsed * 0.43) * 0.018
		if portal_material:
			var base_energy := 2.65 if enemies_alive == 0 else 1.45
			portal_material.emission_energy_multiplier = base_energy + sin(Time.get_ticks_msec() * 0.002) * 0.38


func _advance_survival(delta: float) -> void:
	var previous_warning_level := _survival_warning_level
	var context := {
		"health_ratio": player.health / DungeonPlayer.MAX_HEALTH if is_instance_valid(player) else 1.0,
		"torch_lit": player.torch_enabled if is_instance_valid(player) else true,
		"threatened": _has_nearby_stress_threat(),
		"safe_zone": player.safe_zone_mode if is_instance_valid(player) else true,
	}
	var survival := ExpeditionSession.advance_survival(delta, context)
	_refresh_survival_hud(survival)
	var hunger := float(survival.get("hunger", ExpeditionSession.MAX_NEED))
	var thirst := float(survival.get("thirst", ExpeditionSession.MAX_NEED))
	var next_warning_level := _need_warning_level(minf(hunger, thirst))
	if next_warning_level > previous_warning_level and is_instance_valid(hud):
		if next_warning_level >= 3:
			hud.show_event("생존 보급이 바닥났습니다 · 식량과 물이 필요합니다", 2.2)
		elif next_warning_level == 2:
			hud.show_event("몸이 쇠약해지고 있습니다 · 보급품을 확인하십시오", 1.8)
		elif hunger <= 30.0 and thirst <= 30.0:
			hud.show_event("포만감과 수분이 낮아지고 있습니다", 1.6)
		elif hunger <= 30.0:
			hud.show_event("배가 고프기 시작합니다", 1.4)
		else:
			hud.show_event("목이 마르기 시작합니다", 1.4)
	_survival_warning_level = next_warning_level


func _refresh_survival_hud(snapshot := {}) -> void:
	if not is_instance_valid(hud):
		return
	var survival: Dictionary = snapshot if snapshot is Dictionary and not snapshot.is_empty() else ExpeditionSession.get_survival_snapshot()
	hud.update_survival(float(survival.get("hunger", ExpeditionSession.MAX_NEED)), float(survival.get("thirst", ExpeditionSession.MAX_NEED)), float(survival.get("maximum", ExpeditionSession.MAX_NEED)))
	hud.update_conditions(survival.get("conditions", {}) as Dictionary, float(survival.get("drain_multiplier", 1.0)))
	if hud.has_method("update_stress"):
		hud.update_stress(ExpeditionSession.stress, StressProfile.MAX_STRESS, StressProfile.stage_name(ExpeditionSession.stress))
	_survival_warning_level = _need_warning_level(minf(float(survival.get("hunger", ExpeditionSession.MAX_NEED)), float(survival.get("thirst", ExpeditionSession.MAX_NEED))))


func _need_warning_level(lowest_need: float) -> int:
	if lowest_need <= 0.0:
		return 3
	if lowest_need <= 15.0:
		return 2
	if lowest_need <= 30.0:
		return 1
	return 0


func _spawn_stress_effects() -> void:
	stress_effects = STRESS_PERCEPTION_SCRIPT.new()
	stress_effects.name = "StressPerception"
	stress_effects.setup(player)
	add_child(stress_effects)


func _has_nearby_stress_threat() -> bool:
	if not is_instance_valid(player):
		return false
	for actor in get_tree().get_nodes_in_group("enemy"):
		if actor is DungeonEnemy and not actor.is_queued_for_deletion() and actor.health > 0.0 and actor.ai_state != DungeonEnemy.AIState.DEAD:
			if player.global_position.distance_squared_to(actor.global_position) < 64.0:
				return true
	return false


func suspend_stress_effects() -> void:
	if is_instance_valid(stress_effects):
		stress_effects.set_active(false)


func _update_stress_presentation() -> void:
	if not is_instance_valid(stress_effects) or not is_instance_valid(player):
		return
	var enabled := game_mode == GameMode.RUNNING and not get_tree().paused and not is_instance_valid(loading_screen) and _window_focused and not player.safe_zone_mode and not player.camping and player.health > 0.0
	stress_effects.update_stress(ExpeditionSession.stress)
	stress_effects.set_active(enabled)
	var next_stage := StressProfile.stage_index(ExpeditionSession.stress)
	if enabled and next_stage > _stress_warning_stage:
		var warnings := ["", "마음이 불안해집니다 · 야영으로 진정할 수 있습니다", "어디선가 없는 소리가 들려옵니다 · 스트레스 높음", "주변의 형체가 일그러집니다 · 휴식이 필요합니다"]
		hud.show_event(warnings[next_stage], 2.0)
	_stress_warning_stage = next_stage


func _physics_process(_delta: float) -> void:
	if game_mode not in [GameMode.RUNNING, GameMode.CAMPING] or get_tree().paused:
		return
	if not is_instance_valid(player) or not player.is_physics_processing():
		return
	if game_mode == GameMode.RUNNING:
		player._resolve_active_attack()
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		var enemy := enemy_node as DungeonEnemy
		if enemy != null and enemy.is_physics_processing():
			enemy._resolve_active_attack()


func _unhandled_input(event: InputEvent) -> void:
	if game_mode == GameMode.CAMPING:
		if event.is_action_pressed("camp") or event.is_action_pressed("pause"):
			cancel_camp("야영을 정리했습니다")
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("inventory"):
			cancel_camp("가방을 열어 야영을 중단했습니다")
			_open_inventory()
			get_viewport().set_input_as_handled()
		return
	if game_mode == GameMode.INVENTORY:
		if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
			_close_inventory()
			get_viewport().set_input_as_handled()
		return
	if game_mode == GameMode.PAUSED:
		if _is_continue_event(event) or event.is_action_pressed("pause"):
			_resume_game()
			get_viewport().set_input_as_handled()
		return
	if game_mode == GameMode.DEAD or game_mode == GameMode.WON:
		if game_mode == GameMode.WON and event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			_begin_scene_loading(
				MERCHANT_SCENE_PATH,
				"중개인에게 귀환하는 중",
				"회수품과 원정 기록을 정리하고 있습니다",
				"안전한 귀환로를 여는 중",
				"중개인에게 돌아갈 수 없습니다"
			)
			return
		if event.is_action_pressed("restart"):
			get_viewport().set_input_as_handled()
			# Death starts a fresh expedition loadout but keeps spells learned during
			# this playthrough. Starting a new game from the title clears them.
			ExpeditionSession.begin_new_journey(false)
			_begin_scene_loading(
				GAME_SCENE_PATH,
				"원정을 다시 준비하는 중",
				"검은 성물실과 전투 장비를 다시 정돈하고 있습니다",
				"봉인을 되감는 중",
				"원정을 다시 시작할 수 없습니다"
			)
		return
	if game_mode == GameMode.RUNNING:
		if event.is_action_pressed("camp"):
			open_camp()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("inventory"):
			_open_inventory()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("pause"):
			_pause_game()
			get_viewport().set_input_as_handled()


func _begin_scene_loading(scene_path: String, title_text: String, detail_text: String, status_text: String, failure_text: String) -> void:
	if is_instance_valid(loading_screen):
		return
	suspend_stress_effects()
	cancel_camp("", false)
	if is_instance_valid(player):
		player.cancel_timed_interaction()
		player.set_chest_container_open(false)
		player.cancel_flail_action()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_loading_failure_message = failure_text
	loading_screen = LOADING_SCREEN_SCRIPT.new() as SanctuaryLoadingScreen
	loading_screen.name = "SceneLoadingOverlay"
	loading_screen.configure(scene_path, title_text, detail_text, status_text, 0.7)
	loading_screen.load_failed.connect(_on_scene_loading_failed.bind(loading_screen))
	loading_screen.attach_as_overlay(get_tree())


func _on_scene_loading_failed(_error_code: int, failed_screen: SanctuaryLoadingScreen) -> void:
	if failed_screen != loading_screen:
		return
	failed_screen.dismiss()
	loading_screen = null
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(hud):
		hud.show_event(_loading_failure_message, 1.2)


func _is_continue_event(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("interact")


func _spawn_camp() -> void:
	camp = CAMP_CONTROLLER_SCRIPT.new()
	camp.name = "DungeonCamp"
	camp.setup(self, player, inventory)
	camp.opened.connect(_on_camp_opened)
	camp.rest_started.connect(_on_camp_rest_started)
	camp.rest_finished.connect(_on_camp_rest_finished)
	camp.closed.connect(_on_camp_closed)
	add_child(camp)


func open_camp() -> Dictionary:
	if not is_instance_valid(camp):
		return {"accepted": false, "reason": "unavailable", "message": "이곳에서는 야영할 수 없습니다"}
	var result: Dictionary = camp.open_camp()
	if not bool(result.get("accepted", false)) and is_instance_valid(hud):
		hud.show_event(str(result.get("message", "지금은 야영할 수 없습니다")), 1.8)
	return result


func _camp_open_failure() -> String:
	if not is_inside_tree() or not is_instance_valid(player):
		return "unavailable"
	if game_mode != GameMode.RUNNING or is_instance_valid(loading_screen):
		return "busy"
	if get_tree().paused:
		return "paused"
	if player.safe_zone_mode:
		return "safe_zone"
	if player.combat_state == DungeonPlayer.CombatState.DEAD:
		return "dead"
	if player.current_trap != null or player.is_timed_interacting() or player.trap_lockout > 0.0:
		return "busy"
	if player.combat_state != DungeonPlayer.CombatState.READY or player.bow_drawing or player._is_flail_busy() or player.blocking:
		return "busy"
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.2:
		return "moving"
	return ""


func cancel_camp(reason := "", restore_controls := true) -> void:
	if is_instance_valid(camp):
		camp.cancel_camp(reason, restore_controls)


func _on_camp_opened() -> void:
	suspend_stress_effects()
	game_mode = GameMode.CAMPING
	player.set_camping(true)
	var hud_root := hud.get_node("HUDRoot") as Control
	_camp_hud_was_visible = hud_root.visible
	hud_root.hide()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_prompt("")


func _on_camp_rest_started() -> void:
	if game_mode != GameMode.CAMPING:
		return
	# The UI stays usable, but nearby enemies and projectiles remain live.
	# Survival time is advanced only by the camp action's authored time scale.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_camp_rest_finished(_result: Dictionary) -> void:
	if game_mode != GameMode.CAMPING or player.combat_state == DungeonPlayer.CombatState.DEAD:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_survival_hud()


func _on_camp_closed(reason: String, restore_controls: bool) -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		player.set_camping(false)
	if game_mode == GameMode.CAMPING:
		game_mode = GameMode.RUNNING
		if restore_controls and is_inside_tree():
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(hud) and hud.is_inside_tree():
		(hud.get_node("HUDRoot") as Control).visible = _camp_hud_was_visible
		_refresh_survival_hud()
		if not reason.is_empty():
			hud.show_event(reason, 1.8)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		suspend_stress_effects()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(camp) and camp.state == "resting":
		# Losing the window cannot leave a defenseless player resting unattended.
		_pause_game()


func _pause_game() -> void:
	suspend_stress_effects()
	cancel_camp("야영을 중단하고 일시정지했습니다", false)
	if is_instance_valid(player):
		player.cancel_timed_interaction("일시정지하여 상호작용을 중단했습니다")
		player.set_chest_container_open(false)
		player.cancel_bow_draw()
		player.cancel_flail_action()
	game_mode = GameMode.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay("원정 일시정지", "클릭 또는 ESC · 계속")


func _resume_game() -> void:
	game_mode = GameMode.RUNNING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.hide_overlay()


func _open_inventory() -> void:
	if game_mode == GameMode.CAMPING:
		cancel_camp("가방을 열어 야영을 중단했습니다")
	if game_mode != GameMode.RUNNING or inventory_overlay == null:
		return
	if is_instance_valid(player) and player.current_trap != null:
		hud.show_event("함정 해제를 마친 뒤 가방을 확인하십시오", 1.0)
		return
	suspend_stress_effects()
	game_mode = GameMode.INVENTORY
	active_loot_chest = null
	if is_instance_valid(player):
		player.prepare_for_inventory()
	if hud:
		hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status_provider := Callable(player, "get_inventory_status_snapshot") if is_instance_valid(player) else Callable()
	inventory_overlay.open_inventory(inventory, status_provider)
	get_tree().paused = true


func _open_container(chest: DungeonLootChest) -> void:
	if game_mode != GameMode.RUNNING or inventory_overlay == null or not is_instance_valid(chest):
		return
	suspend_stress_effects()
	game_mode = GameMode.INVENTORY
	active_loot_chest = chest
	if is_instance_valid(player):
		player.prepare_for_inventory()
		player.set_chest_container_open(true)
	if hud:
		hud.set_prompt("")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var status_provider := Callable(player, "get_inventory_status_snapshot") if is_instance_valid(player) else Callable()
	inventory_overlay.open_container(inventory, chest.container, status_provider)
	get_tree().paused = true


func _close_inventory() -> void:
	if game_mode != GameMode.INVENTORY:
		return
	if inventory_overlay and inventory_overlay.is_open():
		inventory_overlay.close()
		# A nested quantity picker owns the first close request. Keep the world
		# paused until the inventory overlay itself has actually closed.
		if inventory_overlay.is_open():
			return
	if game_mode != GameMode.INVENTORY:
		return
	game_mode = GameMode.RUNNING
	active_loot_chest = null
	if is_instance_valid(player):
		player.set_chest_container_open(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_inventory_closed() -> void:
	if game_mode != GameMode.INVENTORY:
		return
	game_mode = GameMode.RUNNING
	active_loot_chest = null
	if is_instance_valid(player):
		player.set_chest_container_open(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_consumable_requested(item_id: String) -> void:
	if game_mode != GameMode.INVENTORY or not is_instance_valid(player):
		return
	var result := player.use_consumable(item_id, inventory)
	var message := str(result.get("message", "물품을 사용할 수 없습니다."))
	inventory_overlay.set_status(message)
	hud.show_event(message, 1.1)
	if bool(result.get("accepted", false)):
		inventory_overlay.refresh_status_readout()
		_refresh_survival_hud()


func _on_loot_chest_requested(chest: DungeonLootChest) -> void:
	_open_container(chest)


func _spawn_hud() -> void:
	hud = HUD_SCRIPT.new() as DungeonHUD
	hud.name = "DungeonHUD"
	add_child(hud)


func _spawn_inventory_overlay() -> void:
	inventory_overlay = INVENTORY_OVERLAY_SCRIPT.new() as InventoryOverlay
	inventory_overlay.name = "InventoryOverlay"
	inventory_overlay.closed.connect(_on_inventory_closed)
	inventory_overlay.consumable_requested.connect(_on_consumable_requested)
	inventory_overlay.item_discarded.connect(_on_item_discarded)
	add_child(inventory_overlay)


func _on_item_discarded(stack: Dictionary) -> void:
	var dropped := DROPPED_ITEM_SCRIPT.spawn_discarded(self, player, stack)
	inventory_overlay.set_status("%s을(를) 바닥에 놓았습니다. 가방을 닫고 E로 주울 수 있습니다." % ExpeditionInventory.get_item_name(str(stack.get("id", ""))) if is_instance_valid(dropped) else "안전하게 놓을 바닥이 없어 물품을 되돌렸습니다.")


func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new() as DungeonPlayer
	player.position = Vector3(0, 1.0, 14.2)
	player.setup(self, hud, inventory)
	player.died.connect(_on_player_died)
	add_child(player)


func _spawn_encounters() -> void:
	_spawn_enemy("망각의 검지기", Vector3(0, 1.0, 1.9), 82.0, 21.0, 2.2, Color(0.145, 0.18, 0.19), "bleeding")
	_spawn_enemy("굶주린 성소지기", Vector3(1.7, 1.0, -10.7), 68.0, 18.0, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	_spawn_trap("속박의 룬 압력판", Vector3(0, 0.0, 6.7), 32.0, 0.86, 0.62, "curse")
	_spawn_trap("피를 부르는 철침진", Vector3(-1.8, 0.0, -6.15), 38.0, 1.12, 0.37, "bleeding")


func _spawn_loot_chests() -> void:
	_spawn_loot_sites("reliquary")


func _spawn_loot_sites(map_id: String) -> void:
	# This guard also covers accidental repeated setup calls. Opening a menu,
	# looting an item or closing a container never changes the sampled sites.
	if _loot_spawn_initialized:
		return
	_loot_spawn_initialized = true
	loot_spawn_sites = LOOT_SPAWN_CATALOG.candidates(map_id)
	loot_spawn_selection = LOOT_SPAWN_CATALOG.roll(map_id, loot_spawn_seed)
	for site: Dictionary in loot_spawn_selection:
		var chest := _spawn_loot_chest(str(site.title), site.position, site.items, str(site.subtitle), str(site.model_variant), float(site.yaw), str(site.id))
		chest.set_meta("loot_site_context", site.context)
		chest.set_meta("loot_approach_position", site.approach_position)


func _spawn_loot_chest(title_text: String, spawn_position: Vector3, item_stacks: Array, subtitle_text: String, model_variant: String = "", yaw: float = PI, site_id: String = "") -> DungeonLootChest:
	var chest := LOOT_CHEST_SCRIPT.new() as DungeonLootChest
	chest.configure(title_text, item_stacks, subtitle_text)
	chest.configure_visual(model_variant)
	chest.position = spawn_position
	chest.rotation.y = yaw
	if not site_id.is_empty():
		chest.set_meta("loot_site_id", site_id)
	chest.open_requested.connect(_on_loot_chest_requested)
	add_child(chest)
	loot_chests.append(chest)
	return chest

func _spawn_enemy(enemy_name: String, spawn_position: Vector3, hp: float, damage: float, speed: float, tint: Color, ailment_id := "") -> void:
	var enemy := ENEMY_SCRIPT.new() as DungeonEnemy
	enemy.configure(enemy_name, hp, damage, speed, tint, ailment_id)
	enemy.setup(player, hud, self)
	enemy.position = spawn_position
	enemy.defeated.connect(_on_enemy_defeated)
	add_child(enemy)
	enemies_alive += 1


func _spawn_trap(trap_name: String, spawn_position: Vector3, damage: float, speed: float, zone_center: float, ailment_id := "") -> void:
	var trap := TRAP_SCRIPT.new() as RuneTrap
	trap.configure(trap_name, damage, speed, zone_center, ailment_id)
	trap.setup(hud, self)
	trap.position = spawn_position
	trap.resolved.connect(_on_trap_resolved)
	add_child(trap)


func _on_enemy_defeated(enemy: DungeonEnemy) -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	loot_count += 1
	var reward_added := _grant_inventory_reward("rune_fragment")
	hud.show_event(
		"%s 처치 · 청록 룬 파편 회수" % enemy.display_name
		if reward_added
		else "%s 처치 · 가방이 가득 차 룬 파편을 놓쳤습니다" % enemy.display_name,
		1.5
	)
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	if enemies_alive == 0:
		portal_material.albedo_color = Color(0.12, 0.58, 0.5, 0.72)
		portal_material.emission = Color(0.08, 0.95, 0.72)
		hud.show_event("귀환문의 봉인이 풀렸습니다", 2.1)


func _on_trap_resolved(_trap: RuneTrap, success: bool) -> void:
	if success:
		traps_disarmed += 1
		loot_count += 1
		if not _grant_inventory_reward("rune_fragment"):
			hud.show_event("가방이 가득 차 룬 파편을 회수하지 못했습니다", 1.2)
	else:
		traps_triggered += 1
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)


func _grant_inventory_reward(item_id: String, quantity := 1) -> bool:
	if inventory == null or inventory.add_item(item_id, quantity) > 0:
		return false
	return true


func _on_player_died() -> void:
	suspend_stress_effects()
	cancel_camp("", false)
	if is_instance_valid(player):
		player.cancel_timed_interaction()
		player.set_chest_container_open(false)
	game_mode = GameMode.DEAD
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(0.25).timeout
	get_tree().paused = true
	hud.show_overlay(
		"원정 실패",
		"성소가 회수품을 삼켰습니다.\n처치 %d · 해제 %d · 작동시킨 함정 %d\n\nR · 다시 원정" % [loot_count - traps_disarmed, traps_disarmed, traps_triggered]
	)


func _on_extraction_body_entered(body: Node3D) -> void:
	if body != player or game_mode != GameMode.RUNNING:
		return
	if enemies_alive > 0:
		hud.show_event("귀환문이 봉인되어 있습니다 · 감시자 %d명 남음" % enemies_alive, 1.4)
		return
	game_mode = GameMode.WON
	suspend_stress_effects()
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	player.cancel_flail_action()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	var carried_loot_value := inventory.raid_loot_value() if inventory != null else 0
	var secured_value := carried_loot_value + traps_disarmed * 16
	hud.show_overlay(
		"생환 · 회수품 확보",
		"검은 성물실에서 무사히 빠져나왔습니다.\n처치 %d · 함정 해제 %d · 가방 전리품 %d 크라운\n확보 가치 %d 크라운\n\n상호작용 키 · 중개인에게 귀환\nR · 장비를 초기화하고 새 원정" % [loot_count - traps_disarmed, traps_disarmed, carried_loot_value, secured_value]
	)


func _build_materials() -> void:
	stone_material = _material(Color(0.72, 0.76, 0.76), 0.86, 0.035)
	stone_material.albedo_texture = WALL_TEXTURE
	_configure_triplanar(stone_material, Vector3(0.62, 0.62, 0.62))

	floor_material = _material(Color(0.63, 0.69, 0.69), 0.31, 0.025)
	floor_material.albedo_texture = FLOOR_TEXTURE
	_configure_triplanar(floor_material, Vector3(0.78, 0.78, 0.78))

	metal_material = _material(Color(0.105, 0.115, 0.115), 0.46, 0.82)
	metal_material.albedo_texture = PITTED_IRON_TEXTURE
	_configure_triplanar(metal_material, Vector3(3.8, 3.8, 3.8))


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.006, 0.009, 0.013)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.115, 0.17, 0.19)
	environment.ambient_light_energy = 0.34
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.045, 0.092, 0.10)
	environment.fog_light_energy = 0.46
	environment.fog_density = 0.016
	environment.fog_height = 0.0
	environment.fog_height_density = 0.18
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 2.1
	environment.ssao_intensity = 1.65
	environment.ssil_enabled = true
	environment.ssil_radius = 3.0
	environment.ssil_intensity = 0.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.82
	environment.glow_strength = 0.72
	environment.glow_bloom = 0.09
	world_environment.environment = environment
	add_child(world_environment)

	var moon := DirectionalLight3D.new()
	moon.name = "ColdMoonlight"
	moon.rotation_degrees = Vector3(-62, -28, 0)
	moon.light_color = Color(0.23, 0.40, 0.48)
	moon.light_energy = 0.38
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 32.0
	moon.directional_shadow_split_1 = 0.25
	moon.directional_shadow_fade_start = 0.9
	add_child(moon)


func _build_dungeon() -> void:
	_add_static_box("Floor", Vector3(0, -0.5, 0), Vector3(21, 1, 34), floor_material)
	_add_static_box("Ceiling", Vector3(0, 5.25, 0), Vector3(21, 0.5, 34), stone_material)
	_add_static_box("WestWall", Vector3(-10.5, 2.35, 0), Vector3(0.8, 5.2, 34), stone_material)
	_add_static_box("EastWall", Vector3(10.5, 2.35, 0), Vector3(0.8, 5.2, 34), stone_material)
	_add_static_box("NorthWall", Vector3(0, 2.35, -17), Vector3(21, 5.2, 0.8), stone_material)
	_add_static_box("SouthWall", Vector3(0, 2.35, 17), Vector3(21, 5.2, 0.8), stone_material)

	# Broken dividing walls keep a readable combat corridor without requiring navmesh baking.
	_add_static_box("GateWallL", Vector3(-7.0, 2.2, 8.4), Vector3(7.0, 4.4, 0.72), stone_material)
	_add_static_box("GateWallR", Vector3(7.0, 2.2, 8.4), Vector3(7.0, 4.4, 0.72), stone_material)
	_add_static_box("InnerWallL", Vector3(-7.2, 2.2, -3.7), Vector3(6.6, 4.4, 0.72), stone_material)
	_add_static_box("InnerWallR", Vector3(7.2, 2.2, -3.7), Vector3(6.6, 4.4, 0.72), stone_material)

	for x in [-7.7, 7.7]:
		for z in [12.0, 3.5, -8.6]:
			_add_static_box("Pillar", Vector3(x, 2.05, z), Vector3(1.05, 4.1, 1.05), stone_material, false)
			_add_pillar_visual(Vector3(x, 0.0, z))

	# Waist-high cover makes spacing and strafing matter during melee encounters.
	_add_static_box("BrokenAltar", Vector3(-3.8, 0.62, 1.1), Vector3(2.7, 1.24, 1.3), stone_material)

	# Layered arches, hanging chains, rubble, and wet patches break the old box-room silhouette.
	_add_gothic_arch(Vector3(0.0, 2.30, 8.38), 3.55, 1.42)
	_add_gothic_arch(Vector3(0.0, 2.30, -3.68), 3.95, 1.55)
	_add_hanging_chain(Vector3(-4.7, 4.86, 7.9), 2.15)
	_add_hanging_chain(Vector3(5.0, 4.86, -4.3), 1.72)
	_add_hanging_chain(Vector3(-2.8, 4.86, -12.7), 1.35)
	_add_rubble_cluster(Vector3(-8.65, 0.02, 5.2), 0.8)
	_add_rubble_cluster(Vector3(8.45, 0.02, -1.1), 1.05)
	_add_rubble_cluster(Vector3(-5.15, 0.02, -12.8), 0.72)
	_add_wet_patch(Vector3(2.8, 0.012, 10.0), Vector2(2.5, 1.45), -17.0)
	_add_wet_patch(Vector3(-3.1, 0.013, -7.4), Vector2(2.1, 1.15), 23.0)

	_add_torch(Vector3(-9.75, 2.65, 12.2), Color(1.0, 0.4, 0.16))
	_add_torch(Vector3(9.75, 2.65, 6.0), Color(1.0, 0.45, 0.18))
	_add_torch(Vector3(-9.75, 2.65, -1.5), Color(0.8, 0.23, 0.1))
	_add_torch(Vector3(9.75, 2.65, -8.5), Color(0.25, 0.65, 0.58))
	_add_torch(Vector3(-6.2, 2.4, -14.8), Color(0.18, 0.72, 0.63))
	STONE_BATCHES.build(self)


func _build_extraction_gate() -> void:
	var arch_model := PORTAL_ARCH_SCENE.instantiate() as Node3D
	arch_model.name = "SanctumPortalArchVisual"
	arch_model.position = Vector3(0.0, 0.0, -15.47)
	arch_model.scale = Vector3(1.48, 1.48, 1.18)
	add_child(arch_model)
	_disable_imported_collisions(arch_model)
	_set_meshes_visible_by_prefix(arch_model, ["PortalMembrane", "PortalCurrent", "ArchRune"], false)
	_apply_material_to_prefix(arch_model, ["Threshold", "Pier", "Voussoir"], stone_material)
	DUNGEON_CONCEPT.apply_portal(arch_model)

	# Existing collision dimensions remain authoritative; the imported arch is visual only.
	_add_static_box("PortalLeft", Vector3(-2.25, 2.0, -15.45), Vector3(0.65, 4.0, 0.8), stone_material, false)
	_add_static_box("PortalRight", Vector3(2.25, 2.0, -15.45), Vector3(0.65, 4.0, 0.8), stone_material, false)
	_add_static_box("PortalTop", Vector3(0, 4.0, -15.45), Vector3(5.1, 0.65, 0.8), stone_material, false)

	portal_material = _material(Color(0.72, 0.18, 0.12, 0.72), 0.24, 0.03)
	portal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_material.emission_enabled = true
	portal_material.emission = Color(0.82, 0.045, 0.018)
	portal_material.emission_energy_multiplier = 1.45
	portal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	portal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	portal_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	portal_material.albedo_texture = PORTAL_TEXTURE
	portal_material.emission_texture = PORTAL_TEXTURE
	var portal_quad := QuadMesh.new()
	portal_quad.size = Vector2(3.55, 4.72)
	portal_visual = MeshInstance3D.new()
	portal_visual.name = "AIExtractionPortal"
	portal_visual.mesh = portal_quad
	portal_visual.material_override = portal_material
	portal_visual.position = Vector3(0, 2.42, -15.35)
	add_child(portal_visual)
	_add_portal_motes(Vector3(0, 2.28, -15.18))

	var extraction_area := Area3D.new()
	extraction_area.name = "ExtractionArea"
	extraction_area.collision_layer = 0
	extraction_area.collision_mask = PLAYER_LAYER
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 3.5, 1.1)
	shape_node.shape = box
	extraction_area.add_child(shape_node)
	extraction_area.position = Vector3(0, 1.8, -15.0)
	extraction_area.body_entered.connect(_on_extraction_body_entered)
	add_child(extraction_area)


func _add_static_box(
	node_name: String,
	box_position: Vector3,
	box_size: Vector3,
	material: StandardMaterial3D,
	show_visual := true
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = box_position
	body.collision_layer = WORLD_LAYER
	body.collision_mask = PLAYER_LAYER | 4
	if show_visual:
		var kind := _architecture_kind(node_name, material, box_size)
		if not kind.is_empty():
			body.add_child(DUNGEON_CONCEPT.create_architecture(box_size, kind))
		else:
			body.add_child(_visual_box(box_size, material))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


func _add_visual_box(box_position: Vector3, box_size: Vector3, material: StandardMaterial3D) -> void:
	var visual := _visual_box(box_size, material)
	visual.position = box_position
	add_child(visual)


func _visual_box(box_size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh_value := BoxMesh.new()
	mesh_value.size = box_size
	instance.mesh = mesh_value
	instance.material_override = material
	return instance


func _add_torch(torch_position: Vector3, color_value: Color) -> void:
	var torch_model := TORCH_SCENE.instantiate() as Node3D
	torch_model.name = "WallIronCageTorch"
	torch_model.position = torch_position + Vector3(0.0, -0.23, 0.0)
	torch_model.scale = Vector3.ONE * 0.48
	add_child(torch_model)
	_disable_imported_collisions(torch_model)
	_set_meshes_visible_by_prefix(torch_model, ["OuterFlame", "InnerFlame"], false)
	var torch_wood := _material(Color(0.45, 0.34, 0.24), 0.92, 0.01)
	torch_wood.albedo_texture = ANCIENT_OAK_TEXTURE
	torch_wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	torch_wood.uv1_triplanar = true
	torch_wood.uv1_scale = Vector3.ONE * 3.0
	_apply_material_to_prefix(torch_model, ["CharredHandle"], torch_wood)
	_apply_material_to_prefix(torch_model, ["IronCollar", "FuelCup", "CageProng", "CageTop"], metal_material)
	var coal_material := _material(Color(0.025, 0.012, 0.009), 0.92, 0.02)
	coal_material.emission_enabled = true
	coal_material.emission = Color(0.25, 0.015, 0.004)
	coal_material.emission_energy_multiplier = 0.30
	_apply_material_to_prefix(torch_model, ["Coal"], coal_material)
	EQUIPMENT_CONCEPT.apply_torch(torch_model)
	EQUIPMENT_CONCEPT.apply_wall_mount(torch_model, 0.50)
	torch_model.rotation.y = 0.0 if torch_position.z < -14.0 else (PI * 0.5 if torch_position.x < 0.0 else -PI * 0.5)

	var flame := Sprite3D.new()
	flame.name = "PhotorealWallFlame"
	flame.texture = TORCH_FLAME_TEXTURE
	flame.pixel_size = 0.00034
	flame.position = torch_position + Vector3(0, 0.35, 0)
	flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	flame.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	flame.double_sided = true
	flame.shaded = false
	flame.modulate = color_value.lightened(0.24)
	add_child(flame)
	FLAME_VISUALS.attach(flame)
	_add_fire_sparks_at(torch_position + Vector3(0, 0.33, 0), color_value)

	var light := OmniLight3D.new()
	light.position = torch_position + Vector3(0, 0.32, 0)
	light.light_color = color_value
	light.light_energy = 1.45
	light.omni_range = 6.4
	light.shadow_enabled = false
	add_child(light)


func _configure_triplanar(material: StandardMaterial3D, scale_value: Vector3) -> void:
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.texture_repeat = true
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 48.0
	material.uv1_scale = scale_value


func _add_pillar_visual(pillar_position: Vector3) -> void:
	var pillar := PILLAR_SCENE.instantiate() as Node3D
	pillar.name = "OssuaryPillarVisual"
	pillar.position = pillar_position
	pillar.scale = Vector3(1.55, 1.32, 1.55)
	add_child(pillar)
	_disable_imported_collisions(pillar)
	_apply_material_recursive(pillar, stone_material)
	DUNGEON_CONCEPT.apply_pillar(pillar)


func _add_gothic_arch(center: Vector3, half_width: float, rise: float) -> void:
	for index in 25:
		var block := MeshInstance3D.new()
		block.name = "GothicVoussoir"
		block.mesh = DUNGEON_CONCEPT.arch_wedge(half_width, rise, index, 25)
		block.material_override = DUNGEON_CONCEPT.stone_material(index)
		block.position = center
		add_child(block)


func _add_hanging_chain(chain_position: Vector3, length: float) -> void:
	var link_count := maxi(3, floori(length / 0.13))
	for index in range(link_count):
		var link := MeshInstance3D.new()
		link.name = "RustedChainLink"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.035
		torus.outer_radius = 0.062
		torus.rings = 20
		torus.ring_segments = 8
		link.mesh = torus
		link.material_override = AGED_SURFACES.pitted_iron(Color(0.39, 0.365, 0.31), 4.0)
		link.position = chain_position + Vector3(0.0, -float(index) * 0.125, 0.0)
		link.rotation_degrees = Vector3(90.0, 90.0 if index % 2 else 0.0, 0.0)
		link.scale.z = 1.52
		add_child(link)


func _add_rubble_cluster(cluster_position: Vector3, scale_value: float) -> void:
	var offsets := [
		Vector3(-0.46, 0.08, 0.10), Vector3(-0.18, 0.12, -0.24),
		Vector3(0.16, 0.09, 0.18), Vector3(0.43, 0.15, -0.08),
		Vector3(-0.02, 0.18, 0.02), Vector3(0.28, 0.07, 0.34),
		Vector3(-0.35, 0.06, -0.39)
	]
	for index in range(offsets.size()):
		var rubble_size := Vector3(0.34 + float(index % 3) * 0.09, 0.16 + float(index % 2) * 0.10, 0.28 + float((index + 1) % 3) * 0.07) * scale_value
		var rubble := _visual_box(rubble_size, DUNGEON_CONCEPT.stone_material(index))
		rubble.mesh = DUNGEON_CONCEPT.chipped_block(rubble_size, index)
		rubble.name = "BrokenOssuaryStone"
		rubble.position = cluster_position + offsets[index] * scale_value
		rubble.rotation_degrees = Vector3(float(index * 11 % 19), float(index * 37 % 85), float(index * 7 % 16))
		add_child(rubble)


func _add_wet_patch(patch_position: Vector3, patch_size: Vector2, yaw_degrees: float) -> void:
	var patch_material := AGED_SURFACES.stone(Color(0.12, 0.18, 0.18, 0.64), 2.0)
	patch_material.roughness = 0.15
	patch_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	patch_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var patch_quad := QuadMesh.new()
	patch_quad.size = patch_size
	var patch := MeshInstance3D.new()
	patch.name = "WetFloorReflection"
	patch.mesh = DUNGEON_CONCEPT.irregular_patch(patch_size)
	patch.material_override = patch_material
	patch.position = patch_position
	patch.rotation_degrees = Vector3(-90.0, yaw_degrees, 0.0)
	add_child(patch)


func _add_fire_sparks_at(spark_position: Vector3, color_value: Color) -> void:
	var sparks := CPUParticles3D.new()
	sparks.name = "WallTorchSparks"
	sparks.position = spark_position
	sparks.amount = 12
	sparks.lifetime = 1.0
	sparks.preprocess = 1.0
	sparks.randomness = 0.52
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.07
	sparks.direction = Vector3.UP
	sparks.spread = 24.0
	sparks.gravity = Vector3(0.0, 0.34, 0.0)
	sparks.initial_velocity_min = 0.16
	sparks.initial_velocity_max = 0.56
	sparks.scale_amount_min = 0.18
	sparks.scale_amount_max = 0.58
	var ember_quad := QuadMesh.new()
	ember_quad.size = Vector2(0.009, 0.025)
	var ember_material := _material(Color(color_value, 0.88), 0.2, 0.0)
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_material.vertex_color_use_as_albedo = true
	ember_material.emission_enabled = true
	ember_material.emission = color_value
	ember_material.emission_energy_multiplier = 4.0
	ember_quad.material = ember_material
	sparks.mesh = ember_quad
	add_child(sparks)


func _add_portal_motes(mote_position: Vector3) -> void:
	var motes := CPUParticles3D.new()
	motes.name = "PortalSpectralMotes"
	motes.position = mote_position
	motes.amount = 36
	motes.lifetime = 1.75
	motes.preprocess = 1.75
	motes.randomness = 0.62
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 1.18
	motes.direction = Vector3.UP
	motes.spread = 36.0
	motes.gravity = Vector3(0.0, 0.22, 0.0)
	motes.initial_velocity_min = 0.08
	motes.initial_velocity_max = 0.42
	motes.scale_amount_min = 0.20
	motes.scale_amount_max = 0.64
	var mote_quad := QuadMesh.new()
	mote_quad.size = Vector2(0.012, 0.048)
	var mote_material := _material(Color(0.06, 0.78, 0.69, 0.72), 0.2, 0.0)
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_material.vertex_color_use_as_albedo = true
	mote_material.emission_enabled = true
	mote_material.emission = Color(0.02, 0.84, 0.72)
	mote_material.emission_energy_multiplier = 3.5
	mote_quad.material = mote_material
	motes.mesh = mote_quad
	add_child(motes)


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


func _register_inputs() -> void:
	_register_key("move_forward", KEY_W)
	_register_key("move_back", KEY_S)
	_register_key("move_left", KEY_A)
	_register_key("move_right", KEY_D)
	_register_key("sprint", KEY_SHIFT)
	_register_key("jump", KEY_SPACE)
	_register_key("interact", KEY_E)
	_register_key("torch", KEY_F)
	_register_key("inventory", KEY_I)
	_register_key("camp", KEY_C)
	_register_key("restart", KEY_R)
	_register_key("pause", KEY_ESCAPE)
	_register_key("primary_weapon", KEY_1)
	_register_key("spell_1", KEY_1)
	_register_key("spell_2", KEY_2)
	_register_key("spell_3", KEY_3)
	_register_key("spell_4", KEY_4)
	_register_key("spell_5", KEY_5)
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


func _architecture_kind(title: String, material: StandardMaterial3D, size: Vector3) -> String:
	if title == "BrokenAltar":
		return "broken_altar"
	if material == floor_material:
		return "wet_flagstone_floor"
	if material == stone_material and title.contains("Ceiling"):
		return "crypt_ceiling"
	if material == stone_material and title.contains("Wall"):
		return "ossuary_wall"
	return ""


func _add_architecture_visual(at: Vector3, size: Vector3, kind: String) -> Node3D:
	var visual := DUNGEON_CONCEPT.create_architecture(size, kind)
	visual.position = at
	add_child(visual)
	return visual
