extends SceneTree
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const ART := preload("res://scripts/equipment_concept_visual.gd")
const MATERIAL_PROPERTIES := ["albedo_color", "albedo_texture", "normal_enabled", "normal_texture", "normal_scale", "roughness", "metallic", "uv1_scale", "vertex_color_use_as_albedo", "texture_filter"]
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := ExpeditionSession.capture_snapshot()
	var inventory_contents := _inventory_contents(state.inventory)
	var mouse := Input.mouse_mode
	var tube := ART._tube(PackedVector3Array([Vector3.ZERO, Vector3.UP]), PackedFloat32Array([0.05, 0.05]), 12)
	var tube_arrays := tube.surface_get_arrays(0)
	_check((tube_arrays[Mesh.ARRAY_NORMAL][0] as Vector3).x > 0.8, "new closed curved shafts face outward in the renderer")
	for id in ["rusted_longsword", "weathered_round_shield", "iron_cage_torch", "weathered_staff", "wall_torch"]:
		var object := CATALOG.build_object(id)
		_check(object != null, id + " uses the live production equipment builder")
		if object == null:
			continue
		match id:
			"rusted_longsword", "weathered_round_shield":
				_check_current_equipment(object, id)
			"iron_cage_torch":
				_check(object.find_children("CageProng*", "MeshInstance3D", true, false).size() == 6, "torch has six production cage prongs")
				_check(object.find_child("PhotorealFlame", true, false) is Sprite3D, "real production flame remains connected")
			"weathered_staff":
				var crystal := object.find_child("CrackedFocusCrystal", true, false) as MeshInstance3D
				_check(crystal != null and crystal.material_override is StandardMaterial3D and (crystal.material_override as StandardMaterial3D).emission_enabled, "staff retains actual emissive spell focus")
				_check(object.find_child("SpellMuzzle", true, false) != null, "spell firing marker remains on actual staff")
				_check(object.find_children("ConceptFocusBranch*", "MeshInstance3D", true, false).size() == 4, "four curved wooden branches cradle the staff crystal")
			"wall_torch":
				var plate := object.find_child("ConceptWallBackplate", true, false) as MeshInstance3D
				_check(plate != null and plate.position.z < -0.2, "live wall torch has a real rear mounting plate")
				_check(object.find_children("ConceptWallCurvedStay*", "MeshInstance3D", true, false).size() == 2, "two forged stays join handle collars to wall plate")
				_check(object.find_child("LowCostTorchLight", true, false) is OmniLight3D, "wall mounting preserves original production light")
				if plate:
					var model := plate.get_parent() as Node3D
					var child_count := model.get_child_count()
					ART.apply_wall_mount(model)
					_check(child_count == model.get_child_count(), "wall mounting is idempotent")
		object.free()
	_check(ExpeditionSession.capture_snapshot() == state and _inventory_contents(state.inventory) == inventory_contents and Input.mouse_mode == mouse, "equipment inspection preserves expedition and cursor")
	if failures.is_empty():
		print("DARK FANTASY EQUIPMENT TEST PASS: current production GLB resources/materials, actual blade/front/rear grip geometry, no duplicates, torches/staff and deep state preservation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check_current_equipment(object: Node3D, id: String) -> void:
	var sword := id == "rusted_longsword"
	var packed: PackedScene = DungeonPlayer.SWORD_SCENE if sword else DungeonPlayer.SHIELD_SCENE
	var entry := CATALOG.get_entry(id)
	_check(entry.get("factory_type") == "sword_shield" and entry.get("asset_path") == packed.resource_path, "catalog must select the currently equipped GLB: " + id)
	_check(object.get_meta("production_scene", "") == packed.resource_path, "inspection must instantiate the exact production packed resource: " + id)
	var expected := packed.instantiate() as Node3D
	_check(expected != null, "production packed scene must instantiate as a 3D equipment root")
	if expected == null: return
	var helper := DungeonPlayer.new()
	helper._prepare_sword_shield_materials(expected)
	if not sword: expected.rotation.y = PI
	_check(object.transform.is_equal_approx(expected.transform), "equipment keeps its actual front/rear orientation: " + id)
	var meshes := object.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty() and meshes.size() == expected.find_children("*", "MeshInstance3D", true, false).size(), "one production model contains all imported meshes and no duplicate art: " + id)
	for mesh: MeshInstance3D in meshes:
		var source := expected.get_node_or_null(object.get_path_to(mesh)) as MeshInstance3D
		_check(source != null and source.mesh != null and mesh.mesh != null, "each displayed mesh must belong to the current packed scene: " + str(mesh.name))
		if source == null or source.mesh == null or mesh.mesh == null: continue
		_check(mesh.mesh == source.mesh and mesh.transform.is_equal_approx(source.transform), "inspection must share the actual imported mesh and local fit: " + str(mesh.name))
		for surface in mesh.mesh.get_surface_count():
			var actual_material := mesh.get_active_material(surface) as StandardMaterial3D
			var expected_material := source.get_active_material(surface) as StandardMaterial3D
			_check(actual_material != null and expected_material != null, "production equipment needs its real material on every surface")
			if actual_material == null or expected_material == null: continue
			for property: String in MATERIAL_PROPERTIES:
				_check(actual_material.get(property) == expected_material.get(property), "catalog material must match the player's material preparation: " + str(mesh.name) + "/" + property)
			_check(actual_material.albedo_texture != null and actual_material.albedo_texture.resource_path == "res://assets/ai/sword_shield/weapon_material_atlas_v2.png", "weapon material must use the current authored albedo atlas")
			_check(actual_material.normal_enabled and actual_material.normal_texture != null and actual_material.normal_texture.resource_path == "res://assets/ai/sword_shield/weapon_material_normal_v2.png", "weapon surface must retain its actual normal atlas")
			_check(actual_material.vertex_color_use_as_albedo, "actual imported vertex occlusion must remain enabled")
	_check(object.find_children("*", "Skeleton3D", true, false).is_empty() and object.find_children("*", "Camera3D", true, false).is_empty(), "equipment factory must not attach arms or gameplay cameras")
	# Material preparation is repeatable; it must not append the old procedural
	# sword/shield layers to a GLB. Rebuilding returns a fresh single instance.
	var descendants := object.find_children("*", "", true, false).size()
	helper._prepare_sword_shield_materials(object)
	_check(object.find_children("*", "", true, false).size() == descendants, "reapplying production materials cannot duplicate geometry")
	var second := CATALOG.build_object(id)
	_check(second != null and second != object, "repeated catalog calls return independent equipment nodes")
	if second != null:
		_check(second.find_children("*", "", true, false).size() == descendants, "repeated construction must not accumulate legacy art")
		var original_transform := object.transform
		second.position += Vector3(1.0, 2.0, 3.0)
		_check(object.transform.is_equal_approx(original_transform), "one equipment instance cannot mutate another instance's pose")
		second.free()
	if sword: _check_sword_geometry(object)
	else: _check_shield_geometry(object)
	helper.free()
	expected.free()


func _check_sword_geometry(object: Node3D) -> void:
	var blade := object.find_child("PittedBlade", true, false) as MeshInstance3D
	var tip := object.find_child("BladeTip", true, false) as Node3D
	var grip := object.find_child("HandGrip", true, false) as Node3D
	var leather := object.find_child("GripLeather", true, false) as MeshInstance3D
	_check(blade != null and blade.mesh is ArrayMesh and tip != null and grip != null and leather != null, "current sword needs the visible forged blade and both physical contact markers")
	if blade == null or blade.mesh == null or tip == null or grip == null or leather == null or leather.mesh == null: return
	var bounds := _display_transform(object, blade) * blade.mesh.get_aabb()
	_check(bounds.position.distance_to(Vector3(-0.031, -0.01, -0.0045)) < 0.00001 and bounds.end.distance_to(Vector3(0.031, 1.035, 0.0045)) < 0.00001, "current blade keeps its authored edge thickness, narrow section and gameplay reach")
	var tip_position := _display_transform(object, tip).origin
	_check(absf(tip_position.y - bounds.end.y) < 0.00001 and absf(tip_position.x) < 0.00001, "real blade-tip marker must terminate on the visible steel")
	var grip_bounds := _display_transform(object, leather) * leather.mesh.get_aabb()
	_check(grip_bounds.grow(0.001).has_point(_display_transform(object, grip).origin), "the actual one-hand contact must remain inside its shortened leather grip")
	_check(grip_bounds.size.y > 0.14 and grip_bounds.size.y < 0.15, "the current one-hand grip must retain its actual 145mm length")
	var steel := _material_geometry(object, "FP_SwordBlade")
	_check(steel.points.size() > 100 and steel.forward > 0 and steel.backward > 0, "the real blade must have visible steel faces on both sides")


func _check_shield_geometry(object: Node3D) -> void:
	var wood := _material_geometry(object, "FP_ShieldOak")
	var iron := _material_geometry(object, "FP_ShieldIron")
	var leather := _material_geometry(object, "FP_ShieldEnarmes")
	var leather_edge := _material_geometry(object, "FP_ShieldLeatherEdge")
	var loop_points: Array[Vector3] = leather.points.duplicate()
	loop_points.append_array(leather_edge.points)
	_check(not wood.points.is_empty() and not iron.points.is_empty() and not leather.points.is_empty(), "batched shield must contain actual oak, iron and leather triangles")
	if wood.points.is_empty() or iron.points.is_empty() or leather.points.is_empty(): return
	var wood_bounds: AABB = wood.bounds
	_check(wood_bounds.size.x > 0.82 and wood_bounds.size.x < 0.84 and wood_bounds.size.y > 0.82 and wood_bounds.size.z > 0.035, "real shield boards must form a full-size thick disk")
	_check(wood.forward > 0 and wood.backward > 0, "actual oak must expose both its front and its furnished rear")
	var boss_front := INF
	var rim_min := INF
	var rim_max := -INF
	var rim_radius := 0.0
	for point: Vector3 in iron.points:
		var radius := Vector2(point.x, point.y).length()
		if radius < 0.09: boss_front = minf(boss_front, point.z)
		if radius > 0.39:
			rim_min = minf(rim_min, point.z)
			rim_max = maxf(rim_max, point.z)
			rim_radius = maxf(rim_radius, radius)
	_check(is_finite(boss_front) and boss_front < -0.075 and boss_front < wood_bounds.position.z, "the actual boss must project from the -Z front of the boards")
	_check(rim_radius > 0.422 and rim_radius < 0.430 and rim_min < -0.023 and rim_max > 0.009, "physical rolled iron must wrap the board circumference and both cut-edge sides")
	var markers: Dictionary = {}
	for name: String in ["RearGrip", "RearGripTop", "RearGripBottom", "RearArmStrap"]:
		var marker := object.find_child(name, true, false) as Node3D
		_check(marker != null, "current shield must retain its actual contact marker: " + name)
		if marker == null: continue
		var point := _display_transform(object, marker).origin
		markers[name] = point
		var nearest := INF
		for vertex: Vector3 in loop_points: nearest = minf(nearest, point.distance_to(vertex))
		_check(point.z > 0.09, "rear contact marker must remain behind the actual shield boards: " + name)
		if name == "RearArmStrap":
			_check(nearest < 0.006, "the independent forearm strap marker must remain on its unchanged leather geometry")
		elif name == "RearGrip":
			_check(nearest > 0.0105 and nearest < 0.0115, "the hand marker must be enclosed by the real 22mm-deep padded section")
			var theta := deg_to_rad(-4.0)
			var width_axis := object.transform.basis * Vector3(cos(theta), -sin(theta), 0.0)
			var v := 0.0
			var source_center := _authored_loop_center(v)
			# Subtracting Vector3 centers only 2 micrometres apart quantizes the
			# small depth derivative: those vectors use float32. Differentiate
			# the authored scalar curve before constructing its actual normal.
			var thickness_axis := object.transform.basis * _authored_loop_normal(v)
			var center := object.transform * source_center
			for angular in 18:
				var phi := deg_to_rad(10.0 + 20.0 * angular)
				var expected := center + width_axis * (0.015 * cos(phi)) + thickness_axis * (0.011 * sin(phi))
				var vertex_gap := INF
				for vertex: Vector3 in loop_points: vertex_gap = minf(vertex_gap, expected.distance_to(vertex))
				_check(vertex_gap < 0.000025, "all 18 actual central vertices must enclose the contact with the authored 30 by 22mm section")
		else:
			# These named contacts are quarter-span centers at v=+/-.05875,
			# inside the padded transition. They are not the loop attachments.
			_check(nearest > 0.0092 and nearest < 0.0103, "quarter-span contact must remain inside its real padded-to-flat transition: " + name)
	# Real attachments are at the span ends; these keep their original flat
	# geometry and the existing strict 6mm contact bound.
	for v: float in [-0.1175, 0.1175]:
		var attachment := object.transform * _authored_loop_center(v)
		var nearest := INF
		for vertex: Vector3 in loop_points: nearest = minf(nearest, attachment.distance_to(vertex))
		_check(nearest < 0.006, "both original end attachments must remain on the unchanged leather surface")

	if markers.size() == 4:
		_check((markers.RearGripTop as Vector3).distance_to(markers.RearGripBottom) > 0.11, "real hand contact spans the slanted grip loop")
		_check((markers.RearGrip as Vector3).z > maxf((markers.RearGripTop as Vector3).z, (markers.RearGripBottom as Vector3).z) + 0.02, "grip crown must visibly arch behind both lower loop points")
		_check((markers.RearGrip as Vector3).distance_to(markers.RearArmStrap) > 0.28, "the separate enarme must support the forearm away from the hand grip")


func _authored_loop_center(v: float) -> Vector3:
	var theta := deg_to_rad(-4.0)
	var x := -0.18 + v * sin(theta)
	var y := 0.015 + v * cos(theta)
	var dish := 0.025 * maxf(0.0, 1.0 - (x * x + y * y) / (0.415 * 0.415))
	var depth := 0.004 - dish + 0.145 * pow(maxf(0.0, sin(PI * (v / 0.235 + 0.5))), 0.62)
	return Vector3(x, y, -depth)


func _authored_loop_normal(v: float) -> Vector3:
	var theta := deg_to_rad(-4.0)
	var x := -0.18 + v * sin(theta)
	var y := 0.015 + v * cos(theta)
	var derivative := 0.05 * (x * sin(theta) + y * cos(theta)) / (0.415 * 0.415)
	if x * x + y * y >= 0.415 * 0.415: derivative = 0.0
	var phase := PI * (v / 0.235 + 0.5)
	derivative += 0.145 * 0.62 * PI / 0.235 * cos(phase) * pow(sin(phase), -0.38)
	return Vector3(-derivative * sin(theta), -derivative * cos(theta), -1.0).normalized()


func _material_geometry(object: Node3D, name: String) -> Dictionary:
	var points: Array[Vector3] = []
	var forward := 0
	var backward := 0
	for part: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var transform := _display_transform(object, part)
		var normal_basis := transform.basis.inverse().transposed()
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.resource_name != name: continue
			var arrays := part.mesh.surface_get_arrays(surface)
			if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			_check(vertices.size() == normals.size() and vertices.size() > 0, "real equipment surface must have complete vertex normals: " + name)
			if vertices.size() != normals.size(): continue
			var indexed := arrays[Mesh.ARRAY_INDEX] is PackedInt32Array
			_check(indexed, "rendered equipment surface must expose real triangle indices: " + name)
			if not indexed: continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			_check(not indices.is_empty() and indices.size() % 3 == 0, "equipment geometry must render complete triangles: " + name)
			var referenced: Dictionary = {}
			var valid := true
			for index in indices:
				if index < 0 or index >= vertices.size(): valid = false
				else: referenced[index] = true
			_check(valid, "equipment triangles must reference actual imported vertices: " + name)
			if not valid: continue
			for index: int in referenced:
				var point: Vector3 = transform * vertices[index]
				var normal: Vector3 = (normal_basis * normals[index]).normalized()
				_check(point.is_finite() and normal.is_finite(), "actual equipment geometry must remain finite: " + name)
				points.append(point)
				if normal.z < -0.5: forward += 1
				if normal.z > 0.5: backward += 1
	var bounds := AABB()
	if not points.is_empty():
		bounds = AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points: bounds = bounds.expand(point)
	return {"points": points, "bounds": bounds, "forward": forward, "backward": backward}


func _display_transform(object: Node3D, descendant: Node3D) -> Transform3D:
	# Factories intentionally remain outside SceneTree; global transforms would
	# be invalid here. Accumulate into the displayed catalog axes explicitly.
	var result := descendant.transform
	var parent := descendant.get_parent()
	while parent != null and parent != object:
		if parent is Node3D: result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return object.transform * result


func _inventory_contents(inventory: ExpeditionInventory) -> Dictionary:
	if inventory == null: return {}
	return {"slots": inventory.slots.duplicate(true), "equipment": inventory.equipment.duplicate(true), "equipment_data": inventory.equipment_data.duplicate(true)}

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
