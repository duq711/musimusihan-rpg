extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var stage := Node3D.new()
	root.add_child(stage)
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	stage.add_child(player)
	for variant: String in DungeonLootChest.SUPPLIED_MODELS:
		var chest := DungeonLootChest.new().configure("시험 " + variant, [{"id": "linen_bandage", "quantity": 2}]).configure_visual(variant)
		stage.add_child(chest)
		var bounds := chest.visual_bounds()
		_check(absf(bounds.position.y) < 0.015 and bounds.size.y > 0.35, variant + " must stand on its actual floor origin")
		_check(bounds.size.x <= 1.61 and bounds.size.z <= 1.31, variant + " must fit its authored storage footprint")
		_check(chest.supplied_visual != null and chest.lid_pivot != null, variant + " must use the provided GLB with an actual separate lid")
		var shape := chest.get_children().filter(func(node: Node) -> bool: return node is CollisionShape3D)[0] as CollisionShape3D
		_check((shape.shape as BoxShape3D).size.is_equal_approx(bounds.size) and shape.position.is_equal_approx(bounds.get_center()), variant + " collision must match its own model")
		var closed := chest.lid_pivot.transform
		var materials := 0
		for mesh: MeshInstance3D in chest.supplied_visual.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				if material != null and material.albedo_texture != null:
					materials += 1
		_check(materials >= 2, variant + " must retain textured wood/body and real lid surfaces")
		for approach: String in ["front", "back", "left", "right"]:
			var direction: Vector3 = {"front": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT}[approach]
			player.position = direction * (bounds.size.x * 0.5 + 0.55) + Vector3.UP * 0.9
			player.look_at(chest.position + Vector3.UP * bounds.size.y)
			chest.interact(player)
			_check(player.is_timed_interacting() and chest._hand_approach == approach, variant + " must open through the real player interaction from " + approach)
			player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.86)
			_check(not chest.lid_pivot.transform.is_equal_approx(closed), variant + " real lid must move during hand pull")
			var across := chest.get_hand_contact_transform(1, 0.86).origin - chest.get_hand_contact_transform(-1, 0.86).origin
			_check(across.dot(player.global_basis.x) > 0.01, variant + " left and right hands must not cross at " + approach)
			for side in [-1, 1]:
				var contact := chest.get_hand_contact_transform(side, 0.86)
				_check(contact.is_finite() and contact.basis.is_conformal(), variant + " hand contact must remain a finite orthonormal frame")
				var local_point := chest.lid_pivot.to_local(contact.origin)
				var normal := chest.lid_pivot.global_basis.inverse() * contact.basis.y
				_check(_touches_lid(chest, local_point, normal), variant + " hands must follow an actual lid triangle and its slope at " + approach)
				var hand: Node3D = player.chest_hands.left_hand if side == -1 else player.chest_hands.right_hand
				_check(not hand.is_visible_in_tree(), "Chest opening must not display a reaching or gripping hand.")
			player.cancel_timed_interaction()
			_check(chest.lid_pivot.transform.is_equal_approx(closed) and not chest.opened and not player.chest_hands.active, variant + " cancellation must restore the lid and arms")
		chest.interact(player)
		player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION + 0.1)
		_check(chest.opened and chest.container.ever_opened and not player.is_timed_interacting(), variant + " must complete actual looting")
		if chest._supplied_lid_lifts():
			chest._set_lid_pull(1.0)
			var lid_bounds := DungeonLootChest._mesh_bounds(chest.lid_pivot, chest.supplied_visual)
			var body_bounds := DungeonLootChest._mesh_bounds(chest.supplied_visual.find_child("Body", true, false), chest.supplied_visual)
			_check(absf(lid_bounds.position.y - body_bounds.end.y) < 0.02 and chest.lid_pivot.position.z - closed.origin.z < bounds.size.z * 0.5, variant + " loose lid must finish on the rear rim instead of hovering or intersecting it")
		chest.container.begin_search()
		chest.container.advance_search(1.0)
		var taken := chest.container.take_from_slot(0)
		_check(taken.get("quantity", 0) == 2 and chest.container.is_empty(), variant + " must identify and transfer actual contents")
		chest.interact(player)
		_check(chest.container.is_empty(), variant + " reopening must never refill loot")
		chest.free()
	stage.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_mode, "model checks must preserve the expedition and cursor")
	for failure in failures:
		push_error(failure)
	print("LOOT CONTAINER MODELS TEST %s: four supplied models, real lids, contact surfaces, cancellation and loot persistence" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _touches_lid(chest: DungeonLootChest, point: Vector3, normal: Vector3) -> bool:
	for mesh: MeshInstance3D in chest.lid_pivot.find_children("*", "MeshInstance3D", true, false):
		var frame := DungeonLootChest._transform_to_ancestor(mesh, chest.lid_pivot)
		var faces := mesh.mesh.get_faces()
		for triangle in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(point + Vector3.UP * 0.03, Vector3.DOWN, frame * faces[triangle], frame * faces[triangle + 1], frame * faces[triangle + 2])
			if hit is Vector3 and hit.distance_to(point) < 0.002:
				var surface_normal := ((frame * faces[triangle + 1]) - (frame * faces[triangle])).cross((frame * faces[triangle + 2]) - (frame * faces[triangle])).normalized()
				if absf(surface_normal.dot(normal)) > 0.995:
					return true
	return false


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
