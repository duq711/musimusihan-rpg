extends SceneTree

const STONE := preload("res://scripts/dungeon_concept_visual.gd")
const SHADOWS := preload("res://scripts/static_solid_shadows.gd")
const BAKER := preload("res://tests/prop_lod_bake_helpers.gd")
const HIDEOUT := preload("res://scripts/hideout.gd")
const GAME := preload("res://scripts/game.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	for kind in ["ossuary_wall", "wet_flagstone_floor", "crypt_ceiling"]:
		var size := Vector3(4, 3, 0.5) if kind == "ossuary_wall" else Vector3(4, 0.5, 5)
		var visual := STONE.create_architecture(size, kind)
		var shadow := visual.get_node("SolidArchitectureShadow") as MeshInstance3D
		_check(shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "the simplified panel must render only into shadows")
		_check(shadow.mesh.get_faces().size() == 36, "a solid panel uses exactly twelve shadow triangles")
		_check(shadow.mesh.get_aabb() == AABB(-size * 0.5, size), "shadow bounds equal the original individual solid box")
		_check(shadow.transform == Transform3D.IDENTITY, "shadow preserves local panel position and orientation")
		var dense := visual.get_node("BondedMasonryBlocks" if kind == "ossuary_wall" else "FlagstoneSlabs") as MeshInstance3D
		var source := STONE.source_assembly_mesh("masonry" if kind == "ossuary_wall" else "paving", size)
		_check(BAKER.array_hash(dense.mesh) == BAKER.array_hash(source), "the visible production mesh retains every source vertex, normal, UV and index")
		_check(dense.visible and dense.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "full visible stone stays enabled and avoids duplicated shadow submission")
		_check(dense.material_override == STONE.stone_material(2 if kind == "ossuary_wall" else 1), "the original detailed surface material is unchanged")
		for child: MeshInstance3D in visual.find_children("*", "MeshInstance3D", false, false):
			if str(child.name) in SHADOWS.REPLACED_SURFACES:
				_check(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "solid mortar and stone must share the single panel shadow")
			elif str(child.name).begins_with("CeilingRib"):
				_check(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "ornamented ceiling ribs retain their authored shadows")
		_check(SHADOWS.add(visual, size) == shadow, "repeated shadow setup must be idempotent")
		var second := STONE.create_architecture(size, kind)
		_check((second.get_node("SolidArchitectureShadow") as MeshInstance3D).mesh == shadow.mesh, "identical solid shadow meshes share their immutable geometry")
		visual.free()
		second.free()
	var arch := Node3D.new()
	STONE.apply_archway(arch)
	_check(arch.find_child("SolidArchitectureShadow", true, false) == null, "the open arch must never receive a solid bounding-box shadow")
	arch.free()
	var hideout := HIDEOUT.new()
	hideout._build_materials()
	var room := Node3D.new()
	hideout._add_room_shell(room, Vector3.ZERO, Vector2(4, 5), 3.0, {"east": Vector2(0, 1.5)})
	var faces := PackedVector3Array()
	for node: MeshInstance3D in room.find_children("SolidArchitectureShadow", "MeshInstance3D", true, false):
		var relative := _relative_transform(node, room)
		for point: Vector3 in node.mesh.get_faces():
			faces.append(relative * point)
		_validate_collider(node)
	_check(not _intersects(faces, Vector3(0, 1.4, 0), Vector3(4, 1.4, 0)), "the actual east doorway remains open to light at standing eye height")
	_check(not _intersects(faces, Vector3(0, 0.1, 0), Vector3(4, 0.1, 0)), "the actual east doorway remains open to light down to the floor")
	_check(_intersects(faces, Vector3(0, 1.4, 0), Vector3(4, 1.4, 2)), "the adjoining solid wall still blocks light")
	_check(_intersects(faces, Vector3(0, 1.4, 0), Vector3(-4, 1.4, 0)), "the opposite wall still blocks light")
	_check(_intersects(faces, Vector3(0, 1.4, 0), Vector3(0, -1, 0)), "the actual floor still blocks below-room light")
	room.free()
	hideout.free()
	# The test-room autoload must finish registering before its dependent
	# production script is loaded; no scene is entered or readied here.
	for script in [GAME, load("res://scripts/test_room.gd")]:
		var world: Node3D = script.new()
		world.call("_build_materials")
		var wall: StaticBody3D = world.call("_add_static_box", "TestShadowWall", Vector3(7, 2, -6), Vector3(4, 3, 0.5), world.get("stone_material"))
		var shadow := wall.find_child("SolidArchitectureShadow", true, false) as MeshInstance3D
		_check(shadow != null, "dungeon and actual test-room builder must use production solid shadows")
		if shadow != null:
			_validate_collider(shadow)
			_check(_relative_transform(shadow, world).origin == Vector3(7, 2, -6), "production shadow follows the unchanged body placement")
		world.free()
	_check(snapshot == ExpeditionSession.capture_snapshot() and mouse == Input.mouse_mode, "shadow optimization preserves expedition and cursor")
	if failures.is_empty():
		print("PROP SOLID SHADOW PASS: exact visible buffers/materials; 12-triangle collider-sized shadow panels; real room passage/light blocking and floor contact; authored arch/ribs preserved; dungeon/test-room connection and unchanged session")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _validate_collider(shadow: MeshInstance3D) -> void:
	var body := shadow.get_parent().get_parent() as StaticBody3D
	_check(body != null, "the panel shadow stays under its original body")
	if body == null:
		return
	var collision := body.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D
	_check(shadow.mesh.get_aabb() == AABB(-(collision.shape as BoxShape3D).size * 0.5, (collision.shape as BoxShape3D).size), "the shadow covers exactly one original collision solid")
	_check(body.collision_layer == GAME.WORLD_LAYER, "original world collision layer remains unchanged")


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var cursor := node.get_parent()
	while cursor != ancestor:
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


func _intersects(faces: PackedVector3Array, start: Vector3, end: Vector3) -> bool:
	for index in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false


func _check(passed: bool, message: String) -> void:
	if not passed and message not in failures:
		failures.append(message)
