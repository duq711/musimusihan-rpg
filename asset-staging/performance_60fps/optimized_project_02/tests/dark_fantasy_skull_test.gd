extends SceneTree

const SKULL := preload("res://scripts/dark_fantasy_skull.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var skull := SKULL.create(0.4)
	var small := SKULL.create(0.2)
	var ok := skull.mesh != null and skull.mesh == small.mesh
	if ok:
		ok = is_equal_approx(skull.get_aabb().size.y * skull.scale.y, 0.4)
		ok = ok and skull.get_meta("anatomical_source_pieces", 0) >= 20
		ok = ok and skull.mesh.surface_get_array_len(0) > 1000
		ok = ok and skull.get_aabb().get_center().length() < 0.0001
	skull.free()
	small.free()
	for frame in 12:
		await process_frame
	if ok:
		print("DARK FANTASY SKULL TEST PASS: actual cranial bones, shared geometry, centered bounds and exact size")
		quit(0)
	else:
		push_error("DARK FANTASY SKULL TEST FAIL: mesh assembly or normalized bounds")
		quit(1)
