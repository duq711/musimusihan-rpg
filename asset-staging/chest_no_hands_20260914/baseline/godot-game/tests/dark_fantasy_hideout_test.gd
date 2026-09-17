extends SceneTree

const HIDEOUT := preload("res://scripts/hideout.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.ensure_journey()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var builder := HIDEOUT.new() as SanctuaryHideout
	builder._build_materials()
	var props := Node3D.new()
	builder._add_crate(props, Vector3.ZERO, Vector3.ONE)
	builder._add_barrel(props, Vector3(2.0, 0.0, 0.0), 0.4, 1.0)
	builder._add_bucket(props, Vector3(4.0, 0.0, 0.0), 0.6)
	builder._add_skull(props, Vector3(5.0, 0.4, 0.0), 0.23)
	builder._build_broken_saint(props)
	builder._add_hanging_cloth(props, Vector3(7.0, 1.8, 0.0), Vector2(0.8, 1.6), Color(0.25, 0.24, 0.20))
	var vice: Node3D = builder._build_rusty_vice(props, Vector3.ZERO)
	_check(vice.has_node("FixedJaw") and vice.has_node("MovingJaw") and vice.has_node("THandle") and vice.has_node("ThreadedSpindle"), "Production vice has actual opposing jaws, spindle and transverse handle")
	var vice_bounds := AABB()
	for part in vice.get_children():
		if part is MeshInstance3D:
			var bounds: AABB = part.transform * part.get_aabb()
			vice_bounds = bounds if vice_bounds.size == Vector3.ZERO else vice_bounds.merge(bounds)
	_check(vice_bounds.size.x <= 0.441 and vice_bounds.size.y <= 0.421 and vice_bounds.size.z <= 0.561, "Vice stays inside its original visual envelope")
	_check((vice.get_node("FixedGrippingFace") as Node3D).position.z - (vice.get_node("MovingGrippingFace") as Node3D).position.z > 0.05, "Real open jaw clearance remains visible")
	_check(props.find_children("CrateVerticalPlank*", "MeshInstance3D", true, false).size() == 12, "Crate has separate front/rear vertical planks")
	_check(props.find_children("CurvedOakStave*", "MeshInstance3D", true, false).size() == 18, "Barrel has eighteen physical curved staves")
	var bucket := props.find_child("RainBucket", true, false) as MeshInstance3D
	_check(bucket != null and not (bucket.mesh as CylinderMesh).cap_top, "Rain bucket has a real open top")
	var skull := props.find_child("WeatheredSkull", true, false) as MeshInstance3D
	_check(skull != null and skull.get_meta("anatomical_source_pieces", 0) >= 20, "Ossuary skull uses shared real cranial bone geometry")
	var robe := props.find_child("SaintRobe", true, false) as MeshInstance3D
	_check(robe != null and robe.mesh is ArrayMesh and robe.mesh.surface_get_array_len(0) > 10000, "Landmark uses continuous sculpted drapery")
	var cloak := props.find_child("CloakCloth", true, false) as MeshInstance3D
	_check(cloak != null and cloak.mesh is ArrayMesh and cloak.get_aabb().size.z > 0.2, "Hanging cloak has folded depth on both sides")
	_check(props.find_children("CollisionShape3D", "CollisionShape3D", true, false).is_empty(), "Decorative standalone builders do not add gameplay colliders")
	builder._build_hearth(props)
	var hearth := props.find_child("OnlyWarmHearth", true, false) as Node3D
	_check(hearth.find_child("HearthStoneFoundation", true, false) != null, "Hearth rests on a continuous low stone foundation")
	var log_count := 0
	for child in hearth.get_children():
		if child is MeshInstance3D and child.material_override == builder.ember_material and child.mesh is ArrayMesh:
			log_count += 1
			_check(child.get_aabb().size.y <= 0.161 and child.get_aabb().size.x <= 0.721, "Round charred logs stay inside their original bar envelope")
	_check(log_count == 3 and builder.ember_material.albedo_texture == builder.HEARTH_VISUAL.COAL, "All three actual hearth logs use generated coal surfaces")
	for vessel_name in ["CookingPot", "SingleCup"]:
		var vessel := props.find_child(vessel_name, true, false) as Node3D
		var shell := vessel.find_child("HollowVesselBody", true, false) as MeshInstance3D
		_check(shell != null and shell.mesh is ArrayMesh and vessel.find_child("RolledVesselRim", true, false) != null, "Hearth vessel has real inner wall, bottom and rolled rim: " + vessel_name)
		var top := shell.get_aabb().end.y
		var near_top_intersection := false
		var floor_intersection := false
		var faces := shell.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			near_top_intersection = near_top_intersection or Geometry3D.segment_intersects_triangle(Vector3(0, top + 0.05, 0), Vector3(0, top - 0.04, 0), faces[index], faces[index + 1], faces[index + 2]) != null
			floor_intersection = floor_intersection or Geometry3D.segment_intersects_triangle(Vector3(0, top + 0.05, 0), Vector3(0, -1, 0), faces[index], faces[index + 1], faces[index + 2]) != null
		_check(not near_top_intersection and floor_intersection, "Actual vessel is open at the rim with a closed interior bottom: " + vessel_name)
		var arrays := shell.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var outer_row := 2 if vessel_name == "CookingPot" else 1
		var inner_row := 7 if vessel_name == "CookingPot" else 4
		for row in [outer_row, inner_row]:
			var index: int = row * 48 * 6
			var radial := Vector3(vertices[index].x, 0, vertices[index].z).normalized()
			var expected_sign := 1.0 if row == outer_row else -1.0
			_check(normals[index].dot(radial) * expected_sign > 0.4, "Vessel exterior normals face outward and cavity normals inward: " + vessel_name)
		var inside_floor_row := 10 if vessel_name == "CookingPot" else 6
		_check(normals[0].y < -0.9 and normals[inside_floor_row * 48 * 6 + 5].y > 0.9, "Vessel underside faces down and cavity floor faces up: " + vessel_name)
	_check(props.find_child("CurvedPotBail", true, false) != null and props.find_child("CurvedCupHandle", true, false) != null, "Pot and cup have attached curved iron handles")
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse_mode, "Production prop builders leave session and input unchanged")
	props.free()
	builder.free()
	for frame in 12:
		await process_frame
	if failures.is_empty():
		print("DARK FANTASY HIDEOUT TEST PASS: real staves, open vessel, anatomical skull, sculpted statue/cloth and session safety")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY HIDEOUT TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
