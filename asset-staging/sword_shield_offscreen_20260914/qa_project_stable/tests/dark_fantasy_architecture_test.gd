extends SceneTree

const CONCEPT := preload("res://scripts/dungeon_concept_visual.gd")
const GAME := preload("res://scripts/game.gd")
const HIDEOUT := preload("res://scripts/hideout.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.ensure_journey()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var game := GAME.new()
	game._build_materials()
	var size := Vector3(3.0, 3.5, 0.5)
	var wall: StaticBody3D = game._add_static_box("OssuaryWall", Vector3(2, 3, 4), size, game.stone_material)
	_check(wall.position == Vector3(2, 3, 4), "Stone facade preserves authoritative position")
	var collision := wall.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	_check((collision.shape as BoxShape3D).size == size, "Visual stone joints leave world collision unchanged")
	_check(wall.find_child("BondedMasonryBlocks", true, false) != null, "Gameplay wall uses the same real masonry builder as gallery")
	game._add_gothic_arch(Vector3.ZERO, 3.55, 1.42)
	var wedges := game.find_children("*", "MeshInstance3D", true, false)
	var curved := 0
	for node in wedges:
		if str(node.name).begins_with("GothicVoussoir") or (node.get_parent() == game and node.mesh is ArrayMesh):
			curved += 1
	_check(curved == 25, "Gothic passage retains 25 true curved wedge stones")
	var mesh := CONCEPT.chipped_block(Vector3(1, 0.5, 0.7), 1)
	_check(mesh == CONCEPT.chipped_block(Vector3(1, 0.5, 0.7), 1), "Repeated stone geometry shares cached immutable mesh")
	for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		_check(point.is_finite() and absf(point.x) <= 0.5001 and absf(point.y) <= 0.2501 and absf(point.z) <= 0.3501, "Chipped stone stays inside original visual footprint")
	var hideout := HIDEOUT.new()
	hideout._build_materials()
	var props := Node3D.new()
	hideout._add_arch(props, Vector3.ZERO, 0, Vector3.ONE)
	hideout._add_pillar(props, Vector3(4, 0, 0), Vector3.ONE)
	hideout._add_iron_gate(props, Vector3(7, 0, 0), 3.2, 3.3, true)
	_check(props.find_child("PointedArchMasonry", true, false) != null, "Production arch has pointed masonry assembly")
	_check(props.find_child("ClusteredColumnMasonry", true, false) != null, "Production pillar has jointed clustered columns")
	_check(props.find_child("HandForgedRivets", true, false) != null, "Gate has physical brace rivets")
	_check_room_visual_seams(hideout)
	_check(snapshot == ExpeditionSession.capture_snapshot() and mouse_mode == Input.mouse_mode, "Architecture factories preserve session and input")
	props.free()
	hideout.free()
	game.free()
	for frame in 12:
		await process_frame
	if failures.is_empty():
		print("DARK FANTASY ARCHITECTURE TEST PASS: authored silhouettes, masonry, collision and session preservation")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY ARCHITECTURE TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)


func _check_room_visual_seams(hideout: Node) -> void:
	var room := Node3D.new()
	hideout._add_room_shell(room, Vector3.ZERO, Vector2(4, 5), 3.0, {})
	var faces := _room_mortar_faces(room)
	var eye := Vector3(0, 1.4, 0)
	for x in [-2.0, 2.0]:
		for z in [-2.5, 2.5]:
			for y in [0.01, 1.4, 2.99]:
				var target := Vector3(x, y, z)
				_check(_intersects_mortar(faces, eye, eye + (target - eye) * 2.0), "Actual opaque mesh closes vertical room corners, including floor and ceiling endpoints")
	for y in [0.0, 3.0]:
		for target: Vector3 in [Vector3(-2, y, 0), Vector3(2, y, 0), Vector3(0, y, -2.5), Vector3(0, y, 2.5)]:
			_check(_intersects_mortar(faces, eye, eye + (target - eye) * 2.0), "Actual opaque mesh closes wall-to-floor and wall-to-ceiling joins")
	for body: StaticBody3D in room.get_children():
		var collision: CollisionShape3D
		for child in body.get_children():
			if child is CollisionShape3D:
				collision = child
		var bounds := AABB(-(collision.shape as BoxShape3D).size * 0.5, (collision.shape as BoxShape3D).size).grow(0.00001)
		_check_core_below_stone(body, (collision.shape as BoxShape3D).size)
		for node: MeshInstance3D in body.find_children("MortarBoundarySeal", "MeshInstance3D", true, false):
			for point: Vector3 in node.mesh.get_faces():
				_check(bounds.has_point(point), "Opaque seam closure stays inside the original production collider")
	room.free()
	var opened_room := Node3D.new()
	hideout._add_room_shell(opened_room, Vector3.ZERO, Vector2(4, 5), 3.0, {"east": Vector2(0, 1.5)})
	_check(not _intersects_mortar(_room_mortar_faces(opened_room), eye, Vector3(4, 1.4, 0)), "Opaque seam closure leaves the original doorway open")
	opened_room.free()
	var upper := Node3D.new()
	hideout._add_upper_wall_infill(upper, "ArchUpperMasonryInfill", Vector3(0, 4.335, 10.25), Vector3(6, 1.77, 0.5))
	hideout._add_upper_wall_infill(upper, "CeilingWallJointClosure", Vector3(0, 5.175, 10.25), Vector3(16, 0.07, 0.5))
	var upper_faces := _room_mortar_faces(upper)
	_check(_intersects_mortar(upper_faces, eye, Vector3(0, 4.8, 10.25) * 2.0 - eye), "Production arch upper infill is opaque across the previously missing facade")
	_check(_intersects_mortar(upper_faces, eye, Vector3(5, 5.175, 10.25) * 2.0 - eye), "Production ceiling closure blocks the original 5 cm wall-height gap")
	_check(not _intersects_mortar(upper_faces, eye, Vector3(0, 1.4, 12)), "Upper infill leaves the original arch passage visibly open")
	_check(upper.find_children("*", "CollisionShape3D", true, false).is_empty(), "Upper visual closure adds no collider to the original passage")
	upper.free()


func _check_core_below_stone(body: Node3D, size: Vector3) -> void:
	var core := body.find_child("RecessedMortarCore", true, false) as MeshInstance3D
	var cladding := body.find_child("BondedMasonryBlocks", true, false) as MeshInstance3D
	var normal_axis := 2 if size.x >= size.z else 0
	if cladding == null:
		cladding = body.find_child("FlagstoneSlabs", true, false) as MeshInstance3D
		normal_axis = 1
	var core_half := (core.mesh as BoxMesh).size[normal_axis] * 0.5
	var faces := cladding.mesh.get_faces()
	for index in range(0, faces.size(), 3):
		var normal := (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).normalized()
		if absf(normal[normal_axis]) < 0.94:
			continue
		for corner in 3:
			_check(absf(faces[index + corner][normal_axis]) > core_half + 0.001, "Recessed core cannot intersect the actual weathered stone facade")


func _room_mortar_faces(room: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for node: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		if node.name != "RecessedMortarCore" and node.name != "MortarBoundarySeal":
			continue
		var transform := node.transform
		var parent := node.get_parent() as Node3D
		while parent != room:
			transform = parent.transform * transform
			parent = parent.get_parent() as Node3D
		for point: Vector3 in node.mesh.get_faces():
			faces.append(transform * point)
	return faces


func _intersects_mortar(faces: PackedVector3Array, start: Vector3, end: Vector3) -> bool:
	for index in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false
