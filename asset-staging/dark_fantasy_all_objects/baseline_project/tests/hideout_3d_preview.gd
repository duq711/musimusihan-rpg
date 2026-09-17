extends SceneTree

const OUTPUT_DIR := "res://artifacts/visual_qa"
const IMAGE_SIZE := Vector2i(1280, 720)

var viewport: SubViewport
var hideout: SanctuaryHideout


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Hideout previews require a rendering display.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	viewport = SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	ExpeditionSession.begin_new_journey()
	hideout = (load("res://hideout.tscn") as PackedScene).instantiate() as SanctuaryHideout
	viewport.add_child(hideout)
	await process_frame
	await process_frame
	hideout.player.set_physics_process(false)
	hideout.player.set_process_unhandled_input(false)
	hideout.hideout_hud.visible = false
	hideout.door_button.visible = false

	await _set_view_and_capture(Vector3(0.0, 1.0, 17.2), Vector3(0.0, 1.5, 23.5), "hideout_entrance.png", 66.0)
	await _set_view_and_capture(Vector3(0.0, 1.0, 8.4), Vector3(0.0, 1.4, -5.7), "hideout_central_hall.png", 66.0)
	await _set_view_and_capture(Vector3(-7.0, 1.0, 5.0), Vector3(-12.5, 1.0, 5.2), "hideout_sleeping_cell.png", 68.0)
	await _set_view_and_capture(Vector3(7.0, 1.0, -5.0), Vector3(12.2, 1.1, -5.2), "hideout_workshop.png", 68.0)
	await _set_view_and_capture(Vector3(0.0, 1.0, -7.8), Vector3(0.0, 1.4, -17.0), "hideout_sealed_ossuary.png", 64.0)
	print("HIDEOUT 3D PREVIEW PASS: %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)


func _set_view_and_capture(position_value: Vector3, target: Vector3, file_name: String, fov: float) -> void:
	hideout.player.global_position = position_value
	hideout.player.look_at(Vector3(target.x, position_value.y, target.z), Vector3.UP)
	hideout.player.head.rotation.x = 0.0
	hideout.player.camera.fov = fov
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name])
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save hideout preview %s: %s" % [path, error_string(error)])
		quit(1)
