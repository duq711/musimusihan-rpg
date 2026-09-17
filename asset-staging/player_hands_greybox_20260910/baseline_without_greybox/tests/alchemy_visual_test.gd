extends SceneTree

const VISUAL := preload("res://scripts/alchemy_visual.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mouse_before := Input.mouse_mode
	var static_visual := VISUAL.new()
	static_visual.set_room_visible(false)
	_check(not static_visual._steam.visible and not static_visual._bottle_liquid.visible and not static_visual._liquid.visible, "Static shelter factory must initialize a genuinely empty cold workbench before _ready")
	_check(not static_visual._fire.visible and not static_visual._receiver_liquid.visible, "Static shelter factory must not fabricate active fire or finished distillate")
	static_visual.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(706, 412)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var visual := VISUAL.new()
	viewport.add_child(visual)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	visual.set_camera(camera)
	var pose: Dictionary = visual.camera_pose()
	camera.position = pose.position
	camera.look_at(pose.target)
	camera.fov = pose.fov
	visual.update_state({"base_id": "", "temperature": 20.0, "heat": 0, "cauldron_lowered": true})
	_check(not visual._liquid.visible, "Empty cauldron must show its real hollow interior")
	_check(not visual._steam.visible and not visual._bubbles.visible, "Cold empty cauldron must not boil or steam")
	_check(not visual._fire.visible, "A cold hearth with zero heat must not display active flames")
	visual.update_state({"heat": 3.0})
	var low_flame_size: float = visual._fire.scale.y
	visual.update_state({"heat": 60.0})
	_check(visual._fire.scale.y > low_flame_size, "Dying embers must never display a stronger flame than pumped fire")
	_check(visual.get_meta("alchemy_real_geometry"), "Production alchemy bench metadata missing")
	for node_name in ["HollowHammeredCopperBowl", "HollowStoneMortar", "BeatenCopperRetort", "HandblownHourglass", "MovingBellowsHandle", "OpenIlluminatedRecipeBook", "ActualCondensateDrops", "FinishedPotionBottle"]:
		_check(visual.find_child(node_name, true, false) != null, "Missing physical apparatus: " + node_name)
	for base_id in ["water", "wine", "oil", "spirits"]:
		visual.update_state({"base_id": base_id, "temperature": 94.0, "heat": 70.0, "boiling": true, "ingredients": [{"item_id": "herb", "quantity": 2}], "mortar": [{"item_id": "herb"}], "hourglass_running": true, "hourglass_remaining": 5.0, "hourglass_duration": 10.0})
		_check(visual._liquid.visible, "Poured base must appear: " + base_id)
		_check(visual._steam.visible and visual._bubbles.visible, "Hot actual brew must show boiling and steam")
		_check(visual._floating_herbs.visible and visual._mortar_herbs.visible, "Real herbs must appear in their vessels")
		_check(visual._sand_stream.visible, "Running hourglass must display falling sand")
		visual.animate_action("pour_" + base_id)
		visual._process(0.70)
		_check(visual._pour_stream.visible, "Pour animation must visibly connect jug and cauldron")
		_check((visual._vessels[base_id] as Node3D).position.distance_to((visual._vessel_rest[base_id] as Transform3D).origin) > 0.30, "Pouring must physically lift selected base jug")
		var mouth_node: Node3D = (visual._vessels[base_id] as Node3D).get_node("JugLip")
		var stream_start: Vector3 = visual._pour_stream.to_global(Vector3(0, 0.17, 0))
		var stream_end: Vector3 = visual._pour_stream.to_global(Vector3(0, -0.17, 0))
		_check(stream_start.distance_to(mouth_node.global_position) < 0.001, "The stream must originate at the actual moving " + base_id + " jug mouth")
		_check(absf(stream_end.y - visual._liquid.global_position.y - 0.003) < 0.001, "Poured " + base_id + " must reach the actual liquid surface")
		_check(Vector2(stream_end.x - visual._liquid.global_position.x, stream_end.z - visual._liquid.global_position.z).length() < 0.293, "Poured " + base_id + " must land inside the cauldron mouth")
	visual.animate_action("grind")
	visual._process(0.21)
	var pestle_before: Vector3 = visual._pestle.position
	visual._process(0.16)
	_check(visual._pestle.position.distance_to(pestle_before) > 0.035, "Grinding must move pestle through repeated strokes")
	visual.update_state({"base_id": "water", "mortar": [{"id": "dawn_leaf", "form": "ground", "strokes": 3}]})
	_check(visual._mortar_herbs.scale.y < 0.30, "Actual system ground-form arrays must display compact crushed herbs")
	visual.update_state({"base_id": "water", "mortar": [{"id": "dawn_leaf", "form": "bruised", "strokes": 1}]})
	_check(visual._mortar_herbs.scale.y > 0.5 and visual._mortar_herbs.scale.y < 0.9, "Partially pounded herbs must visibly retain a coarser form")
	visual.animate_action("grind")
	visual._process(0.35)
	_check(not (visual._arms[1] as Node3D).visible, "Full-bench overview must not show detached arm fragments")
	var close_pose: Dictionary = visual.camera_pose("mortar")
	camera.position = close_pose.position
	camera.look_at(close_pose.target)
	camera.fov = close_pose.fov
	visual._process(0.01)
	var working_arm: Node3D = visual._arms[1]
	_check(working_arm.visible, "Mortar closeup must show the actual character's working hand")
	_check(float(working_arm.get_meta("forearm_length", 2.0)) <= 0.301, "Pestle grip must keep the real forearm within its natural length")
	var shoulder_screen := camera.unproject_position(working_arm.get_meta("staged_shoulder", Vector3.ZERO))
	_check(not Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(shoulder_screen), "Visible sleeves must enter from outside the closeup frame")
	_check(working_arm.find_child("Finger0Proximal", true, false) != null, "Grinding must retain the source character's real articulated fingers")
	for part: MeshInstance3D in working_arm.hand_meshes:
		_check(part.mesh.get_surface_count() > 0, "Source hand contact must retain its real visible mesh")
	camera.position = pose.position
	camera.look_at(pose.target)
	camera.fov = pose.fov
	visual.animate_action("pump_bellows")
	visual._process(0.5)
	_check(visual._bellows_skin.scale.y < 0.95, "Bellows must physically compress its leather chamber")
	visual.update_state({"base_id": "wine", "temperature": 70, "cauldron_lowered": false, "stage": "distilling", "distill_progress": 0.5})
	visual._process(0.5)
	_check(visual._cauldron.position.y > VISUAL.CAULDRON.y + 0.20, "Raising cauldron must lift it clear of the fire")
	_check(visual._drops.visible and visual._receiver_liquid.visible, "Distillation must show condensate and collected liquid")
	visual.update_state({"base_id": "water", "temperature": 20, "cauldron_lowered": true, "stage": "finished", "mortar": []})
	visual._process(0.5)
	_check(visual._bottle_liquid.visible, "Finished potion must appear in its bottle")
	_check(not visual._mortar_herbs.visible and not visual._floating_herbs.visible, "Empty ingredient collections must clear previous herbs")
	_check(not visual._drops.visible, "Finished distillation must stop droplets")
	visual.update_state({"stage": "finished", "base_id": "wine", "last_result": {"quality": "failed", "quantity": 0}})
	visual.animate_action("bottle")
	visual._process(0.9)
	_check(not visual._bottle_liquid.visible, "Failed brew must never create a fake visible finished potion")
	visual.animate_action("flip_hourglass")
	visual._process(0.8)
	_check(is_equal_approx(visual._hourglass.rotation.z, PI), "The hourglass must physically make one half-turn")
	visual._process(2.0)
	_check(is_equal_approx(visual._hourglass.rotation.z, PI), "Hourglass frame must retain its flipped rest orientation")
	_check(visual._sand_top.global_basis.y.normalized().dot(Vector3.UP) > 0.99, "Hourglass sand must remain aligned with gravity after turning")
	for action in ["stir", "stir_counterclockwise", "flip_hourglass", "bottle", "add_mortar", "raise_cauldron", "distill"]:
		visual.animate_action(action)
		visual._process(0.35)
		_check(visual.get_meta("last_animated_action") == action, "Action route missing " + action)
	# Interaction targets are projected from real apparatus rather than a
	# fixed screen grid, so camera changes and viewport resizing keep working.
	for action in ["pour_water", "pour_wine", "grind", "pump_bellows", "distill", "flip_hourglass", "bottle", "recipe_book"]:
		var position: Vector3 = visual.get_tool_position(action)
		var screen_point := camera.unproject_position(position)
		_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(screen_point), "Overview must frame clickable tool " + action)
		_check(visual.get_interaction_at(camera, screen_point) == action, "Tool hit mapping must match " + action)
	# Exposed outer walls must point outward; inverted lathe winding produces
	# vessels that look sliced open even though their metadata is correct.
	var mesh: ArrayMesh = visual._lathe(PackedVector2Array([Vector2(0.3, 0), Vector2(0.3, 0.4), Vector2(0.27, 0.4), Vector2(0.27, 0.05)]))
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := 0
	for index in vertices.size():
		if is_equal_approx(Vector2(vertices[index].x, vertices[index].z).length(), 0.3) and absf(normals[index].y) < 0.2:
			if Vector3(vertices[index].x, 0, vertices[index].z).dot(normals[index]) > 0.0: outward += 1
	_check(outward > 20, "Lathed vessel outer walls must face outward")
	visual.set_room_visible(false)
	_check(not visual.get_node("ApothecaryStoneAndTimber").visible, "Shelter embedding must be able to hide duplicate architecture")
	_check(Input.mouse_mode == mouse_before, "Visual must not capture or alter the user's cursor")
	viewport.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("ALCHEMY VISUAL %s: physical vessels, apparatus picking, real snapshot effects, action motion, outward walls and cursor preservation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
