extends SceneTree
## Actual production distillation and merchant UI in an embedded SubViewport.
## No native window, game scene entry, external input, focus/cursor API or sound.
const OVERLAY := preload("res://scripts/alchemy_overlay.gd")
const SYSTEM := preload("res://scripts/alchemy_system.gd")
const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const SOURCES := [
	"res://scripts/alchemy_overlay.gd", "res://scripts/alchemy_visual.gd",
	"res://scripts/alchemy_catalog.gd", "res://scripts/alchemy_system.gd",
	"res://scripts/alchemy_audio.gd", "res://scripts/inventory_model.gd",
	"res://scripts/expedition_session.gd", "res://scripts/merchant.gd",
	"res://scripts/test_room_sandbox.gd", "res://assets/fonts/NotoSansKR-Variable.ttf",
	"res://assets/ui/inventory_item_atlas.png",
	"res://assets/ui/liquor_hearth_brandy.svg", "res://assets/ui/liquor_moon_absinthe.svg",
	"res://scripts/player_arm_visual.gd", "res://scripts/dark_fantasy_materials.gd",
	"res://assets/3d/player/gravebound_player.glb", "res://tests/distillation_preview.gd",
]

# MerchantScreen's ordinary entry changes cursor mode and focuses a button.
# Override entry only; construction, selection and selling remain production code.
class OffscreenMerchant extends MerchantScreen:
	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		_build_fonts()
		_build_interface()
		dialogue_panel.hide()
		merchant_stage.hide()
		trade_panel.show()
		_refresh_trade()
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)

var failures: Array[String] = []
var captures: Array[Dictionary] = []
var local_gui_checks: Dictionary = {}
var canvas: SubViewport
var ui: CanvasLayer
var output_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited run_embedded_preview.sh distillation_preview.gd runner.")
		quit(2)
		return
	var iteration := OS.get_environment("HIDEOUT_DISTILLING_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Specify a new HIDEOUT_DISTILLING_QA_ITERATION directory name.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path("res://artifacts/visual_qa/distillation/" + iteration)
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Capture folders must be new: " + output_path)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Cannot create capture folder.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := _inventory_fingerprint(original_bag)
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := _sandbox_snapshot(sandbox)
	var hashes := {}
	for source in SOURCES:
		hashes[source] = FileAccess.get_sha256(source)
		if str(hashes[source]).is_empty(): failures.append("Missing source hash: " + source)
	AudioServer.set_bus_mute(0, true)
	root.gui_disable_input = true
	root.physics_object_picking = false
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	for id: String in SYSTEM.trial_supplies():
		if bag.add_item(id, int(SYSTEM.trial_supplies()[id])) != 0:
			failures.append("Could not prepare isolated trial supply: " + id)
	canvas = SubViewport.new()
	canvas.name = "IsolatedDistillationAndMerchantUI"
	canvas.size = Vector2i(1280, 720)
	canvas.own_world_3d = true
	canvas.physics_object_picking = false
	canvas.audio_listener_enable_2d = false
	canvas.audio_listener_enable_3d = false
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	ui = OVERLAY.new()
	canvas.add_child(ui)
	ui.set_process_input(false)
	ui.set_process_unhandled_input(false)
	ui.set_process_unhandled_key_input(false)
	ui.scene_viewport.physics_object_picking = false
	ui.scene_viewport.audio_listener_enable_2d = false
	ui.scene_viewport.audio_listener_enable_3d = false
	ui.open_for_inventory(bag)
	ui.set_process(false)
	await _click(ui.product_buttons.liquor)
	_check_gui("actual_liquor_tab", str(CATALOG.recipe(str(ui.system.snapshot().recipe_id)).get("product_type", "medicine")) == "liquor" and ui.recipe_picker.item_count == CATALOG.liquor_recipe_ids().size())
	_act("select_recipe", "hearth_brandy")
	await _capture("01_liquor_recipe_and_profit")
	# Native Godot button dispatch stays inside this isolated viewport.
	await _click(ui.base_buttons.wine)
	_check_gui("actual_wine_button", str(ui.system.snapshot().base_id) == "wine")
	await _capture("02_wine_pouring", "pour_wine", 0.45)
	_prepare_herbs("hearth_brandy")
	ui.set_view("cauldron")
	await _capture("03_prepared_herbs", "add_mortar", 0.60)
	var recipe: Dictionary = CATALOG.recipe("hearth_brandy")
	for stir in int(recipe.get("stirs", 0)): _act("stir")
	_act("turn_hourglass")
	_heat_until(float(recipe.get("boil_target", 1.0)))
	_act("raise_cauldron")
	_act("start_distillation")
	_distill_until(0.52)
	ui.set_view("distill")
	await _capture("04_active_distillation")
	_distill_until(1.0)
	ui._refresh()
	await _click(ui.action_buttons.bottle)
	var result: Dictionary = ui.system.snapshot().last_result
	var product_id := str(result.get("item_id", ""))
	_check_gui("actual_bottle_button", str(ui.system.snapshot().stage) == "finished" and str(result.get("quality", "")) == "strong" and bag.count_item(product_id) == 2)
	await _capture("05_finished_saleable_bottles", "bottle", 0.55)
	await _capture_merchant_sale(bag, product_id)
	ui.open_for_inventory(bag)
	ui.set_process(false)
	_act("select_recipe", "moon_absinthe")
	ui.set_view("overview")
	canvas.size = Vector2i(960, 540)
	ui._layout()
	await _capture("07_small_moon_absinthe_recipe")
	ui.cancel_work()
	canvas.queue_free()
	await process_frame
	ExpeditionSession.restore_snapshot(original)
	var preserved := ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_before
	var final_bag_hash := _inventory_fingerprint(original_bag)
	var sandbox_preserved := _sandbox_snapshot(sandbox) == sandbox_before
	if not preserved or final_bag_hash != original_bag_hash or not sandbox_preserved:
		failures.append("Original expedition, inventory, sandbox or cursor changed.")
	for source in SOURCES:
		if FileAccess.get_sha256(source) != hashes[source]: failures.append("Source changed during capture: " + source)
	var manifest := {
		"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(),
		"actual_production_ui": true, "actual_merchant_sale": bool(local_gui_checks.get("actual_merchant_liquor_sale", false)), "local_gui_checks": local_gui_checks,
		"desktop_capture": false, "hardware_input": false, "external_input_disabled": true,
		"expedition_and_cursor_preserved": preserved, "sandbox_preserved": sandbox_preserved,
		"original_inventory_sha256_before": original_bag_hash, "original_inventory_sha256_after": final_bag_hash,
		"source_sha256": hashes, "captures": captures, "failures": failures,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Could not write capture manifest.")
	else:
		file.store_string(JSON.stringify(manifest, "\t"))
	for failure in failures: push_error(failure)
	print("DISTILLATION PREVIEW %s: %d production captures; real local brewing and sale buttons; expedition and cursor preserved; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)


func _act(action: String, payload: Variant = null) -> void:
	var result: Dictionary = ui.perform_action(action, payload)
	if not bool(result.get("accepted", false)):
		failures.append(action + ": " + str(result.get("message", "")))


func _prepare_herbs(recipe_id: String) -> void:
	for milestone: Dictionary in CATALOG.recipe(recipe_id).get("milestones", []):
		_heat_until(float(milestone.get("boil_before", 0.0)))
		_act("raise_cauldron")
		if milestone.has("max_temp"):
			for attempt in 1000:
				if float(ui.system.snapshot().temperature) <= float(milestone.max_temp): break
				ui.system.tick(0.05)
			if float(ui.system.snapshot().temperature) > float(milestone.max_temp): failures.append("Could not cool for herb milestone.")
		if str(milestone.get("form", "whole")) == "ground":
			_act("add_to_mortar", str(milestone.herb))
			for stroke in SYSTEM.GRIND_STROKES: _act("grind")
			_act("pour_mortar")
		else:
			_act("add_whole", str(milestone.herb))


func _heat_step() -> void:
	var state: Dictionary = ui.system.snapshot()
	var point := float(state.boiling_point)
	ui.system.set_cauldron_lowered(float(state.temperature) <= point + 9.0)
	if float(state.heat) < (point - 20.0) / 1.4: ui.system.pump_bellows()
	ui.system.tick(0.05)


func _heat_until(turns: float) -> void:
	for attempt in 5000:
		if float(ui.system.snapshot().boil_turns) + 0.00001 >= turns: return
		_heat_step()
	failures.append("Bounded physical simulation never reached %.1f boiling turns." % turns)


func _distill_until(progress: float) -> void:
	for attempt in 5000:
		if float(ui.system.snapshot().distill_progress) >= progress: return
		_heat_step()
	failures.append("Bounded physical simulation never reached %.2f distillation." % progress)


func _click(button: Button) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		failures.append("Local click target is missing, hidden or disabled.")
		return
	for frame in 3: await process_frame
	var point := button.get_global_rect().get_center()
	if not Rect2(Vector2.ZERO, Vector2(canvas.size)).has_point(point):
		failures.append("Local click target is outside viewport: " + str(button.name))
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame


func _check_gui(id: String, passed: bool) -> void:
	local_gui_checks[id] = passed
	if not passed: failures.append("Production local GUI action failed: " + id)


func _capture(id: String, animation := "", time := 0.0) -> void:
	ui._refresh()
	for frame in 8: await process_frame
	ui.visual.set_process(false)
	if not animation.is_empty():
		ui.visual.animate_action(animation)
		ui.visual._process(time)
	for frame in 3: await process_frame
	var state: Dictionary = ui.system.snapshot()
	var detail := {
		"recipe_id": state.recipe_id, "stage": state.stage, "base_id": state.base_id,
		"ingredients": state.ingredients, "temperature": state.temperature,
		"boil_turns": state.boil_turns, "distill_progress": state.distill_progress,
		"result": state.last_result, "recipe_text": ui.recipe_text.text,
	}
	_save_pixels(id, detail)
	ui.visual.set_process(true)


func _capture_merchant_sale(bag: ExpeditionInventory, product_id: String) -> void:
	ui.close()
	var merchant := OffscreenMerchant.new()
	merchant.name = "IsolatedProductionMerchant"
	merchant.inventory = bag
	merchant.size = Vector2(1280, 720)
	canvas.add_child(merchant)
	for frame in 4: await process_frame
	if not merchant.bag_buttons.has(product_id):
		failures.append("Actual brewed liquor is absent from merchant bag list.")
	else:
		var row: Button = merchant.bag_buttons[product_id]
		var scroll := merchant.bag_rows.get_parent() as ScrollContainer
		scroll.ensure_control_visible(row)
		await _click(row)
		_check_gui("actual_merchant_liquor_selection", merchant.selected_sell_id == product_id and not merchant.sell_button.disabled)
		var before_crowns := ExpeditionSession.crowns
		var before_count := bag.count_item(product_id)
		var price := ExpeditionSession.get_sell_price(product_id)
		await _click(merchant.sell_button)
		_check_gui("actual_merchant_liquor_sale", ExpeditionSession.crowns == before_crowns + price and bag.count_item(product_id) == before_count - 1)
		for frame in 5: await process_frame
		if merchant.bag_buttons.has(product_id):
			scroll.ensure_control_visible(merchant.bag_buttons[product_id])
		for frame in 5: await process_frame
		_save_pixels("06_merchant_liquor_sold", {
			"product_id": product_id, "price": price,
			"crowns_before": before_crowns, "crowns_after": ExpeditionSession.crowns,
			"bottles_before": before_count, "bottles_after": bag.count_item(product_id),
			"trade_status": merchant.trade_status_label.text, "sell_detail": merchant.sell_detail_label.text,
		})
	merchant.queue_free()
	await process_frame


func _save_pixels(id: String, detail: Dictionary) -> void:
	RenderingServer.force_draw(false)
	var pixels := canvas.get_texture().get_image()
	var target := output_path.path_join(id + ".png")
	if pixels == null or pixels.is_empty() or pixels.save_png(target) != OK:
		failures.append("Missing actual renderer pixels: " + id)
	detail.merge({"id": id, "image": id + ".png", "size": str(canvas.size), "sha256": FileAccess.get_sha256(target)})
	captures.append(detail)


func _inventory_fingerprint(bag: ExpeditionInventory) -> String:
	if bag == null: return "no_inventory"
	return JSON.stringify({"slots": bag.slots, "equipment": bag.equipment, "equipment_data": bag.equipment_data}).sha256_text()


func _sandbox_snapshot(sandbox: Node) -> Dictionary:
	return {
		"active": sandbox.active, "saved_session": sandbox.saved_session.duplicate(true),
		"pending_cave_entry_room": sandbox.pending_cave_entry_room,
		"pending_blacksmith_trial": sandbox.pending_blacksmith_trial,
		"pending_alchemy_trial": sandbox.pending_alchemy_trial,
		"pending_cooking_trial": sandbox.pending_cooking_trial,
	}
