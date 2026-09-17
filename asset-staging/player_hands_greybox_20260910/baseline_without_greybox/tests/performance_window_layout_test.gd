extends SceneTree

const PREVIEW := preload("res://tests/performance_preview.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_aspect: Variant = ProjectSettings.get_setting("display/window/stretch/aspect")
	var original_mode: Variant = ProjectSettings.get_setting("display/window/stretch/mode")
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "keep")
	var keep := PREVIEW.window_layout_for(Vector2i(2560, 1664))
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")
	var expand := PREVIEW.window_layout_for(Vector2i(2560, 1664))
	var viewport := PREVIEW.create_viewport(Vector2i(2560, 1664), true)
	var matching := viewport.size == Vector2i(2560, 1664) and viewport.get_visible_rect().size == Vector2(1280, 832) and viewport.size_2d_override_stretch
	viewport.free()
	ProjectSettings.set_setting("display/window/stretch/aspect", original_aspect)
	ProjectSettings.set_setting("display/window/stretch/mode", original_mode)
	print("PERFORMANCE WINDOW LAYOUT: keep=%s expand=%s" % [keep, expand])
	if keep.render_size == [2560, 1440] and keep.logical_size == [1280, 720] and expand.render_size == [2560, 1664] and expand.logical_size == [1280, 832] and keep.detached_window_only and expand.detached_window_only and matching:
		print("PERFORMANCE WINDOW LAYOUT PASS: project aspect, actual rendering pixels and logical UI reproduced without creating a window")
		quit(0)
	else:
		push_error("Native benchmark layout must match actual project content scaling and preserve detached-window safety")
		quit(1)
