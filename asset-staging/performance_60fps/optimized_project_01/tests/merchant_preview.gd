extends SceneTree

const OUTPUT_DIR := "res://artifacts/visual_qa"
const IMAGE_SIZE := Vector2i(1280, 720)

var viewport: SubViewport


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Merchant previews require a rendering display; run this script without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	viewport = SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var menu := (load("res://main_menu.tscn") as PackedScene).instantiate() as MainMenu
	viewport.add_child(menu)
	await process_frame
	await _capture("main_menu_title.png")
	viewport.remove_child(menu)
	menu.free()

	ExpeditionSession.begin_new_journey()
	var hideout := (load("res://hideout.tscn") as PackedScene).instantiate() as SanctuaryHideout
	viewport.add_child(hideout)
	await process_frame
	await _capture("sanctuary_hideout_door.png")
	hideout.door_button.pressed.emit()
	await _capture("merchant_destination_prompt.png")
	viewport.remove_child(hideout)
	hideout.free()

	var merchant := (load("res://merchant.tscn") as PackedScene).instantiate() as MerchantScreen
	viewport.add_child(merchant)
	await process_frame
	await _capture("merchant_dialogue_placeholder.png")
	merchant._show_trade()
	await _capture("merchant_trade_workspace.png")

	print("MERCHANT PREVIEW PASS: %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name])
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save merchant preview %s: %s" % [output_path, error_string(error)])
		quit(1)
