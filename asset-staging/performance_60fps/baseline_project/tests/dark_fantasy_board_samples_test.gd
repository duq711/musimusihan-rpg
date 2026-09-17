extends SceneTree
## Capture catalog boards from the actual deterministic dressing submissions.
const READY := preload("res://tests/art_direction_preview.gd")
const SAMPLE_PATH := "res://assets/art_direction/mine_board_samples.json"

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var saved := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	root.add_child(viewport)
	var geometry: Node3D = load("res://scripts/cave_geometry.gd").new()
	viewport.add_child(geometry)
	geometry.call("build")
	geometry.set_process(false)
	if not await READY.await_geometry_ready(geometry):
		push_error("Actual board placement did not become ready")
		quit(1)
		return
	var details: Node = geometry.get("art_details")
	var recorded := JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH)) as Dictionary
	var batches: Dictionary = details.get("_batches")
	var matches := recorded.size() == 3
	for variant in [12,13,14]:
		var sample: Dictionary = recorded.get(str(variant),{})
		if sample.is_empty() or not batches.has(str(sample.get("batch",""))):
			matches = false
			continue
		var batch: Dictionary = batches[str(sample.batch)]
		var actual: Transform3D = batch.transforms[0]
		var expected := Transform3D(Basis(_point(sample.basis[0]),_point(sample.basis[1]),_point(sample.basis[2])),_point(sample.origin))
		if not actual.is_equal_approx(expected): matches = false
		var color_value: Color = batch.colors[0]
		if not color_value.is_equal_approx(Color(sample.color[0],sample.color[1],sample.color[2],sample.color[3])): matches = false
	viewport.free()
	await process_frame
	if matches and saved == ExpeditionSession.capture_snapshot() and mouse == Input.mouse_mode:
		print("DARK FANTASY BOARD SAMPLES PASS: all three actual placed board transforms/colors, state preserved")
		quit(0)
	else:
		push_error("Catalog board evidence must match actual current production submission and preserve state")
		quit(1)

func _point(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])
