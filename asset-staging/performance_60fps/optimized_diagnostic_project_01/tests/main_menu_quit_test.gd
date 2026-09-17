extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://main_menu.tscn") as PackedScene
	if packed == null:
		push_error("MAIN MENU QUIT TEST FAIL: main menu scene must load")
		quit(1)
		return
	var menu := packed.instantiate() as MainMenu
	root.add_child(menu)
	await process_frame
	menu.quit_button.pressed.emit()
	if not menu.quit_panel.visible:
		push_error("MAIN MENU QUIT TEST FAIL: quit confirmation must open")
		quit(1)
		return
	print("MAIN MENU QUIT TEST PASS: confirmed exit requests SceneTree shutdown")
	menu.quit_confirm_button.pressed.emit()
	await create_timer(0.75).timeout
	push_error("MAIN MENU QUIT TEST FAIL: confirmed exit did not stop the process")
	quit(1)
