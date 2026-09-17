extends SceneTree

const OUTPUT_PATH := "res://artifacts/visual_qa/survival_hud_injured.png"
const IMAGE_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Survival preview requires a rendering display.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.hunger = 72.0
	ExpeditionSession.thirst = 58.0
	ExpeditionSession.apply_condition("bleeding", 180.0)

	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	game.player.set_physics_process(false)
	game._refresh_survival_hud()
	for enemy in get_nodes_in_group("enemy"):
		(enemy as Node).set_physics_process(false)
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save survival preview: %s" % error_string(error))
		quit(1)
		return
	print("SURVIVAL PREVIEW PASS: %s" % output_path)
	quit(0)
