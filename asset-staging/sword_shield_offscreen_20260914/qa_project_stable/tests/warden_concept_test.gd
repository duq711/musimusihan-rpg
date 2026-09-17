extends SceneTree
const VISUALS := preload("res://scripts/warden_concept_visual.gd")
const MODEL := preload("res://assets/3d/dark_fantasy/sanctuary_warden_3d.glb")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mouse := Input.mouse_mode
	var snapshot := ExpeditionSession.capture_snapshot()
	var model := MODEL.instantiate() as Node3D
	var pivots: Dictionary = {}
	for node in model.find_children("*Pivot", "Node3D", true, false):
		pivots[str(node.name)] = node.transform
	var blade := model.find_child("WeaponLongswordBlade", true, false) as MeshInstance3D
	var original_mesh := blade.mesh
	var original_blade_transform := blade.transform
	VISUALS.apply(model)
	_check(model.get_meta("warden_concept_version", 0) == 1, "Concept reconstruction is applied")
	_check(blade.mesh == original_mesh and blade.transform == original_blade_transform and blade.visible, "Exact weapon blade proxy remains authoritative")
	for label in pivots:
		_check((model.find_child(str(label), true, false) as Node3D).transform == pivots[label], "Animation pivot preserved: " + str(label))
	var plate := model.find_child("ConceptForgedCuirass", true, false) as MeshInstance3D
	var arrays: Array = plate.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := 0.0
	for index in range(vertices.size()):
		outward += normals[index].dot(Vector3(vertices[index].x, 0.0, vertices[index].z))
	_check(outward > 0.0, "Forged armor normals face outwards")
	var cloth := model.find_child("ConceptLongTornCloak", true, false) as MeshInstance3D
	_check(cloth != null and cloth.mesh.get_surface_count() > 0, "Long torn folded cloak uses real geometry")
	if cloth:
		_check(cloth.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 3000, "Cloak has authored folds and ragged topology")
	var skull := model.find_child("ConceptAnatomicalSkull", true, false) as MeshInstance3D
	_check(skull != null and skull.mesh.get_aabb().size.y > 0.28, "Warden skull reuses real anatomical cranial geometry")
	_check(model.find_children("ConceptLayeredSabaton*", "MeshInstance3D", true, false).size() == 8, "Both boots carry four articulated toe plates")
	_check(model.find_children("ConceptSoleTread*", "MeshInstance3D", true, false).size() == 16, "Boot undersides are modeled for bottom view")
	_check(model.find_children("ConceptClosedSoleUnderside", "MeshInstance3D", true, false).size() == 2, "Both boots have physically closed bottoms")
	var count := model.find_children("*", "MeshInstance3D", true, false).size()
	VISUALS.apply(model)
	_check(model.find_children("*", "MeshInstance3D", true, false).size() == count, "Visual application is idempotent")
	model.free()
	var enemy := DungeonEnemy.new()
	enemy._build_body()
	_check(enemy.model_root.get_meta("warden_concept_version", 0) == 1, "Production enemy factory applies concept visual")
	_check(enemy.collision_shape.shape is CapsuleShape3D and is_equal_approx((enemy.collision_shape.shape as CapsuleShape3D).radius, 0.43), "Enemy collision unchanged")
	_check(enemy.max_health == 82.0 and enemy.attack_damage == 21.0 and enemy.move_speed == 2.25, "Gameplay values unchanged")
	enemy.free()
	_check(Input.mouse_mode == mouse, "Visual factories never capture input")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "Visual factories do not mutate expedition state")
	if failures.is_empty():
		print("WARDEN CONCEPT PASS: anatomical skull, folded hood/cloak, fitted armor, layered boot soles, exact pivots/blade/collision and session safety")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
