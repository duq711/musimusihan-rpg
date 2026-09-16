extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	var original_inventory := ExpeditionSession.get_inventory()
	var original := ExpeditionSession.capture_snapshot()
	var original_slots := original_inventory.slots.duplicate(true)
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var inventory := ExpeditionSession.get_inventory()
	inventory.seed_default_loadout()
	inventory.add_item("beef_jerky", 3)
	var player := DungeonPlayer.new()
	player.inventory_model = inventory
	var definition := ExpeditionInventory.get_item_definition("beef_jerky")
	_check(definition.effect == "restore_hunger" and definition.amount == ExpeditionInventory.get_item_definition("pilgrim_ration").amount, "Jerky reuses the existing ration hunger effect")
	_check(ResourceLoader.exists(str(definition.icon_path)), "Jerky has a loadable inventory icon")
	ExpeditionSession.hunger = 35.0
	var initial_count := inventory.count_item("beef_jerky")
	var health := player.health
	var thirst := ExpeditionSession.thirst
	var result := player.begin_item_use("beef_jerky", inventory)
	_check(result.get("started", false) and is_equal_approx(float(result.duration), 8.0), "Jerky starts its authored eight-second timer")
	_check(inventory.count_item("beef_jerky") == initial_count and ExpeditionSession.hunger == 35.0, "Starting does not consume or feed early")
	player.advance_item_use(7.99)
	_check(inventory.count_item("beef_jerky") == initial_count and ExpeditionSession.hunger == 35.0, "Eating remains atomic until the exact completion boundary")
	_check(not player.begin_item_use("beef_jerky", inventory).accepted, "A second use cannot overlap the first")
	var torch_before := player.torch_enabled
	player.handle_torch_action()
	_check(not player.is_item_use_active() and inventory.count_item("beef_jerky") == initial_count and ExpeditionSession.hunger == 35.0, "F cancels without consuming or feeding")
	_check(player.torch_enabled == torch_before, "F cancellation does not also toggle the torch")
	player.begin_item_use("beef_jerky", inventory)
	player.advance_item_use(8.0)
	_check(inventory.count_item("beef_jerky") == initial_count - 1 and ExpeditionSession.hunger == 67.0, "Completion consumes exactly one and restores 32 hunger")
	_check(player.health == health and ExpeditionSession.thirst == thirst, "Food does not introduce unrelated healing or thirst effects")
	player.advance_item_use(20.0)
	_check(inventory.count_item("beef_jerky") == initial_count - 1 and ExpeditionSession.hunger == 67.0, "A completed timer cannot consume twice")
	ExpeditionSession.hunger = 95.0
	player.begin_item_use("beef_jerky", inventory)
	player.advance_item_use(8.0)
	_check(ExpeditionSession.hunger == ExpeditionSession.MAX_NEED and inventory.count_item("beef_jerky") == initial_count - 2, "Food is clamped at the existing hunger maximum")
	_check(not player.begin_item_use("beef_jerky", inventory).accepted, "A full player cannot waste jerky")
	ExpeditionSession.hunger = 10.0
	player.begin_item_use("beef_jerky", inventory)
	player.advance_item_use(2.0)
	player.prepare_for_inventory()
	_check(not player.is_item_use_active() and ExpeditionSession.hunger == 10.0 and inventory.count_item("beef_jerky") == 1, "Opening inventory cancels the pending meal")
	player.begin_item_use("beef_jerky", inventory)
	inventory.remove_item("beef_jerky", 1)
	player.advance_item_use(8.0)
	_check(not player.last_item_use_result.accepted and ExpeditionSession.hunger == 10.0, "Completion revalidates item ownership")
	player.free()
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and ExpeditionSession.get_inventory() == original_inventory and original_inventory.slots == original_slots and Input.mouse_mode == cursor, "Original expedition, bag identity, contents and cursor restore exactly")
	for failure in failures: push_error(failure)
	print("육포 사용 검사 / JERKY ITEM USE %s: eight-second timer, atomic food effect, F/inventory cancellation, ownership and exact restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
