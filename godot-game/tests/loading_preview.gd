extends SceneTree

const OUTPUT_PATH := "res://artifacts/visual_qa/loading_screen.png"
const IMAGE_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Loading preview requires a rendering display; run without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var loading := SanctuaryLoadingScreen.new()
	loading.auto_start = false
	loading.configure(
		"res://main_menu.tscn",
		"성소를 밝히는 중",
		"기억과 길, 마지막 원정의 불씨를 불러오고 있습니다",
		"첫 화면을 준비하는 중",
		0.9
	)
	viewport.add_child(loading)
	await process_frame
	loading._process(1.2)
	loading._set_progress(0.47)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)

	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save loading preview: %s" % error_string(error))
		quit(1)
		return
	print("LOADING PREVIEW PASS: %s" % output_path)
	quit(0)
