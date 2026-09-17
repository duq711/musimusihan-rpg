extends SceneTree

const OUTPUT_PATH := "res://artifacts/visual_qa/inventory_status_footer.png"
const IMAGE_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Inventory status preview requires a rendering display.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.hunger = 64.0
	ExpeditionSession.thirst = 53.0

	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.028, 0.02)
	background.size = Vector2(IMAGE_SIZE)
	viewport.add_child(background)
	var inventory := ExpeditionSession.get_inventory()
	var runtime_status := {
		"health": 82.0,
		"max_health": 100.0,
		"stamina": 68.0,
		"max_stamina": 100.0
	}
	var overlay := InventoryOverlay.new()
	viewport.add_child(overlay)
	await process_frame
	overlay.open_inventory(inventory, func() -> Dictionary: return runtime_status)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save inventory status preview: %s" % error_string(error))
		quit(1)
		return
	print("INVENTORY STATUS PREVIEW PASS: %s" % output_path)
	quit(0)
