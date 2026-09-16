extends SceneTree

const SanctuaryHideout := preload("res://scripts/hideout.gd")
const SCENE_TRANSITION_TIMEOUT_MSEC := 30000

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene := load("res://main_menu.tscn") as PackedScene
	_check(menu_scene != null, "main menu must load")
	if menu_scene == null:
		_finish()
		return
	var menu := menu_scene.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.transition_duration = 0.0
	_check(menu.door_button == null and menu.destination_panel == null, "the title menu must not expose the hideout door or destination map")
	menu.new_game_button.pressed.emit()
	var hideout_transition := await _wait_for_scene("res://hideout.tscn")
	_check(bool(hideout_transition.get("saw_loading", false)), "title-to-hideout travel must visibly pass through the animated loading screen")

	var hideout := current_scene as SanctuaryHideout
	_check(hideout != null and hideout.scene_file_path == "res://hideout.tscn", "starting the game must enter the sanctuary hideout before showing destinations")
	if hideout == null:
		_finish()
		return
	hideout.transition_duration = 0.0
	_check(hideout.door_button != null and hideout.destination_panel != null, "the sanctuary hideout must own the door and destination map")
	hideout.door_button.pressed.emit()
	_check(hideout.destination_panel.visible, "the sanctuary door must open the destination map")
	hideout.destination_merchant_button.pressed.emit()
	var merchant_transition := await _wait_for_scene("res://merchant.tscn")
	_check(bool(merchant_transition.get("saw_loading", false)), "hideout-to-merchant travel must visibly pass through the animated loading screen")

	var merchant := current_scene as MerchantScreen
	_check(merchant != null and merchant.scene_file_path == "res://merchant.tscn", "the merchant destination must open the merchant scene")
	if merchant == null:
		_finish()
		return
	await process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "merchant scene must release the mouse")
	_check(merchant.inventory == ExpeditionSession.get_inventory(), "merchant must use the shared expedition bag")
	_check(merchant.merchant_artwork_slot != null and merchant.merchant_artwork_slot.name == "MerchantArtworkSlot", "merchant scene must expose a replaceable artwork slot")
	_check(merchant.portrait_slot != null and merchant.portrait_slot.name == "MerchantPortraitSlot", "dialogue must expose a replaceable portrait slot")
	_check(merchant.dialogue_panel.visible and merchant.merchant_stage.visible and not merchant.trade_panel.visible, "merchant must open on the staged dialogue view")
	_check(merchant.merchant_name_label.text.contains("모르칸"), "dialogue must identify the merchant")
	_check(merchant.dialogue_buttons.size() == 5, "dialogue must provide trade, rumor, work, dungeon, and leave choices")
	_check(merchant.trade_option_button.has_focus(), "the trade choice must receive initial keyboard focus")
	_check(_within_viewport(merchant.dialogue_panel) and _within_viewport(merchant.trade_panel), "authored merchant panels must fit the 1280 by 720 viewport")

	merchant.rumor_option_button.pressed.emit()
	_check(merchant.dialogue_line_label.text.contains("종소리"), "rumor choice must update the merchant response")
	merchant.work_option_button.pressed.emit()
	_check(merchant.dialogue_line_label.text.contains("증류기"), "work choice must update the merchant response")

	merchant.trade_option_button.pressed.emit()
	_check(merchant.trade_panel.visible and not merchant.dialogue_panel.visible and not merchant.merchant_stage.visible, "trade choice must open the buy/sell workspace")
	_check(merchant.currency_label.text.contains(str(ExpeditionSession.STARTING_CROWNS)), "trade header must show the live wallet")
	_check(merchant.stock_buttons.has("linen_bandage") and merchant.stock_buttons.has("lamp_oil"), "trade view must render authored stock rows")
	_check(merchant.bag_buttons.has("healing_draught") and merchant.bag_buttons.has("linen_bandage"), "trade view must render the current bag rows")

	var inventory := ExpeditionSession.get_inventory()
	var original_bandages := inventory.count_item("linen_bandage")
	var original_stock := ExpeditionSession.get_stock_quantity("linen_bandage")
	var original_crowns := ExpeditionSession.crowns
	(merchant.stock_buttons["linen_bandage"] as Button).pressed.emit()
	_check(not merchant.buy_button.disabled and merchant.buy_detail_label.text.contains("누런 붕대"), "selecting stock must expose its details and enable buying")
	merchant.buy_button.grab_focus()
	_check((merchant.stock_buttons["linen_bandage"] as Button).button_pressed, "the selected stock row must stay visibly marked after focus moves to buy")
	merchant.buy_button.pressed.emit()
	_check(inventory.count_item("linen_bandage") == original_bandages + 1, "buy button must move one item into the bag")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == original_stock - 1, "buy button must refresh merchant stock")
	_check(ExpeditionSession.crowns == original_crowns - ExpeditionSession.get_buy_price("linen_bandage"), "buy button must refresh the wallet")
	_check(merchant.trade_status_label.text.contains("구매했습니다"), "successful buying must provide visible feedback")

	(merchant.bag_buttons["linen_bandage"] as Button).pressed.emit()
	_check(not merchant.sell_button.disabled and merchant.sell_detail_label.text.contains("판매"), "selecting a bag item must expose its resale details")
	merchant.sell_button.pressed.emit()
	_check(inventory.count_item("linen_bandage") == original_bandages, "sell button must remove one item from the bag")
	_check(merchant.trade_status_label.text.contains("판매했습니다"), "successful selling must provide visible feedback")

	var lamp_before := inventory.count_item("lamp_oil")
	(merchant.stock_buttons["lamp_oil"] as Button).pressed.emit()
	merchant.buy_button.pressed.emit()
	_check(inventory.count_item("lamp_oil") == lamp_before + 1, "a purchased supply must remain in the shared bag")
	var prepared_crowns := ExpeditionSession.crowns
	var prepared_lamp_stock := ExpeditionSession.get_stock_quantity("lamp_oil")

	_send_escape(merchant)
	_check(merchant.dialogue_panel.visible and not merchant.trade_panel.visible, "Escape from trading must return to dialogue")
	merchant.transition_duration = 0.0
	merchant.dungeon_option_button.pressed.emit()
	var dungeon_transition := await _wait_for_scene("res://main.tscn")
	_check(bool(dungeon_transition.get("saw_loading", false)), "merchant-to-dungeon travel must visibly pass through the animated loading screen")
	_check(current_scene != null and current_scene.scene_file_path == "res://main.tscn", "dungeon dialogue choice must enter the realtime dungeon")
	if current_scene != null and current_scene.scene_file_path == "res://main.tscn":
		_check(current_scene.get("inventory") == ExpeditionSession.get_inventory(), "dungeon must retain the exact merchant session inventory")
		_check(ExpeditionSession.get_inventory().count_item("lamp_oil") == lamp_before + 1, "merchant purchases must persist after entering the dungeon")
		_check(ExpeditionSession.crowns == prepared_crowns and ExpeditionSession.get_stock_quantity("lamp_oil") == prepared_lamp_stock, "wallet and merchant stock must persist after entering the dungeon")

	var dungeon := current_scene
	if dungeon != null and dungeon.scene_file_path == "res://main.tscn":
		var raid_inventory := ExpeditionSession.get_inventory()
		var loot_before := raid_inventory.count_item("black_salt")
		raid_inventory.add_item("black_salt", 1)
		dungeon.set("enemies_alive", 0)
		dungeon.call("_on_extraction_body_entered", dungeon.get("player"))
		_check(paused and int(dungeon.get("game_mode")) == 4, "successful extraction must open the won result state")
		_check((dungeon.get("hud") as DungeonHUD).overlay_detail.text.contains("중개인에게 귀환"), "successful extraction must explain how to return to the merchant")
		_send_action(dungeon, "interact")
		var extraction_transition := await _wait_for_scene("res://merchant.tscn")
		_check(bool(extraction_transition.get("saw_loading", false)), "dungeon extraction must visibly pass through the animated loading screen")
		var return_merchant := current_scene as MerchantScreen
		_check(return_merchant != null, "successful extraction must return to the merchant without resetting the session")
		if return_merchant != null:
			_check(ExpeditionSession.get_inventory().count_item("black_salt") == loot_before + 1, "extracted loot must survive the merchant return")
			_check(ExpeditionSession.crowns == prepared_crowns and ExpeditionSession.get_stock_quantity("lamp_oil") == prepared_lamp_stock, "wallet and merchant stock must persist after extracting back to the merchant")
			return_merchant._show_trade()
			_check(return_merchant.bag_buttons.has("black_salt"), "extracted loot must appear in the merchant sale list")
			var crowns_before_loot_sale := ExpeditionSession.crowns
			(return_merchant.bag_buttons["black_salt"] as Button).pressed.emit()
			return_merchant.sell_button.pressed.emit()
			_check(ExpeditionSession.get_inventory().count_item("black_salt") == loot_before, "selling extracted loot must remove it from the bag")
			_check(ExpeditionSession.crowns == crowns_before_loot_sale + ExpeditionSession.get_sell_price("black_salt"), "selling extracted loot must pay into the persistent wallet")
			for stock_id in ExpeditionSession.merchant_stock:
				(ExpeditionSession.merchant_stock[stock_id] as Dictionary)["quantity"] = 0
				(ExpeditionSession.merchant_stock[stock_id] as Dictionary)["unlimited"] = false
			return_merchant._show_dialogue()
			return_merchant._show_trade()
			_check(return_merchant.trade_back_button.has_focus(), "an entirely sold-out catalog must move keyboard focus to the trade back button")

			var preserved_inventory := ExpeditionSession.get_inventory()
			var preserved_crowns := ExpeditionSession.crowns
			var preserved_lamp_count := preserved_inventory.count_item("lamp_oil")
			var preserved_lamp_stock := ExpeditionSession.get_stock_quantity("lamp_oil")
			return_merchant._show_dialogue()
			return_merchant.transition_duration = 0.0
			return_merchant.leave_option_button.pressed.emit()
			var hideout_return_transition := await _wait_for_scene("res://hideout.tscn")
			_check(bool(hideout_return_transition.get("saw_loading", false)), "merchant leave must visibly pass through the animated loading screen")
			var returned_hideout := current_scene as SanctuaryHideout
			_check(returned_hideout != null and returned_hideout.scene_file_path == "res://hideout.tscn", "the merchant leave choice must return to hideout.tscn")
			if returned_hideout != null:
				_check(ExpeditionSession.journey_started, "returning to the hideout must keep the expedition session active")
				_check(ExpeditionSession.get_inventory() == preserved_inventory, "returning to the hideout must retain the exact shared bag")
				_check(ExpeditionSession.crowns == preserved_crowns, "returning to the hideout must preserve the wallet")
				_check(ExpeditionSession.get_inventory().count_item("lamp_oil") == preserved_lamp_count, "returning to the hideout must preserve bag contents")
				_check(ExpeditionSession.get_stock_quantity("lamp_oil") == preserved_lamp_stock, "returning to the hideout must preserve merchant stock")
				returned_hideout.transition_duration = 0.0
				returned_hideout.door_button.pressed.emit()
				_check(returned_hideout.destination_panel.visible, "the returned hideout door must reopen the destination map")
				returned_hideout.destination_merchant_button.pressed.emit()
				var merchant_revisit_transition := await _wait_for_scene("res://merchant.tscn")
				_check(bool(merchant_revisit_transition.get("saw_loading", false)), "merchant revisit must visibly pass through the animated loading screen")
				var revisited_merchant := current_scene as MerchantScreen
				_check(revisited_merchant != null, "the hideout map must allow revisiting the merchant")
				_check(ExpeditionSession.journey_started and ExpeditionSession.get_inventory() == preserved_inventory, "revisiting the merchant must retain the active session and exact shared bag")
				_check(ExpeditionSession.crowns == preserved_crowns, "revisiting a destination from the hideout must preserve the wallet")
				_check(ExpeditionSession.get_inventory().count_item("lamp_oil") == preserved_lamp_count, "revisiting a destination from the hideout must preserve the bag")
				_check(ExpeditionSession.get_stock_quantity("lamp_oil") == preserved_lamp_stock, "revisiting a destination from the hideout must preserve merchant stock")
				if revisited_merchant != null:
					revisited_merchant.transition_duration = 0.0
					_send_escape(revisited_merchant)
					var hideout_escape_transition := await _wait_for_scene("res://hideout.tscn")
					_check(bool(hideout_escape_transition.get("saw_loading", false)), "merchant Escape return must visibly pass through the animated loading screen")
					var escaped_hideout := current_scene as SanctuaryHideout
					_check(escaped_hideout != null and escaped_hideout.scene_file_path == "res://hideout.tscn", "Escape from merchant dialogue must return to hideout.tscn")
					_check(ExpeditionSession.journey_started and ExpeditionSession.get_inventory() == preserved_inventory, "Escape to the hideout must retain the active session and exact shared bag")
					_check(ExpeditionSession.crowns == preserved_crowns, "Escape to the hideout must preserve the wallet")
					_check(ExpeditionSession.get_inventory().count_item("lamp_oil") == preserved_lamp_count, "Escape to the hideout must preserve bag contents")
					_check(ExpeditionSession.get_stock_quantity("lamp_oil") == preserved_lamp_stock, "Escape to the hideout must preserve merchant stock")

	_finish()


func _wait_for_scene(scene_path: String, timeout_msec := SCENE_TRANSITION_TIMEOUT_MSEC) -> Dictionary:
	var saw_loading := _loading_screen_is_present()
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		saw_loading = saw_loading or _loading_screen_is_present()
		var scene := current_scene
		if scene != null and scene.scene_file_path == scene_path and not _loading_screen_is_present():
			return {"reached": true, "saw_loading": saw_loading}
		await process_frame
	_check(false, "scene transition to %s must finish and dismiss its loading overlay before the timeout" % scene_path)
	return {"reached": false, "saw_loading": saw_loading}


func _loading_screen_is_present() -> bool:
	if current_scene is SanctuaryLoadingScreen:
		return true
	for node in root.find_children("*", "", true, false):
		if node is SanctuaryLoadingScreen:
			return true
	return false


func _within_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1280.0 and rect.end.y <= 720.0


func _send_escape(merchant: MerchantScreen) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	merchant._unhandled_input(event)


func _send_action(target: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	target.call("_unhandled_input", event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("MERCHANT FLOW TEST PASS: title-to-hideout start, destination, dialogue, buy/sell UI, dungeon persistence, merchant return routes, and hideout revisit")
		quit(0)
		return
	for failure in failures:
		push_error("MERCHANT FLOW TEST FAIL: %s" % failure)
	quit(1)
