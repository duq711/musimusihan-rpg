extends SceneTree
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const ART := preload("res://scripts/equipment_concept_visual.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := ExpeditionSession.capture_snapshot()
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
			"rusted_longsword":
				var blade := object.find_child("PittedBlade", true, false) as MeshInstance3D
				_check(blade != null and blade.mesh is ArrayMesh, "real sword uses forged blade geometry")
				if blade:
					var bounds := blade.mesh.get_aabb()
					_check(bounds.position.is_equal_approx(Vector3(-0.068, 0.04, -0.017)), "blade collision proxy minimum remains authored")
					_check(bounds.end.is_equal_approx(Vector3(0.068, 1.085, 0.017)), "blade collision proxy tip/width remain authored")
				var visual := object.find_child("RustedLongswordVisual", true, false) as Node3D
				var count := visual.get_child_count()
				ART.apply_sword(visual)
				_check(count == visual.get_child_count(), "reapplying sword art creates no duplicate geometry")
			"weathered_round_shield":
				_check(object.find_children("ConceptOakPlank*", "MeshInstance3D", true, false).size() == 8, "shield has eight separate physical boards")
				_check(object.find_children("ConceptRimRivet*", "MeshInstance3D", true, false).size() == 32, "shield rim rivets encircle front")
				_check(object.find_child("RearGrip", true, false) != null and object.find_child("RearArmStrap", true, false) != null, "back remains furnished with original grip and strap")
				_check(object.find_child("RearGrip", true, false).mesh.get_aabb().size.z > 0.09, "leather grip arches away from the shield back for fingers")
				var boss := object.find_child("Boss", true, false) as MeshInstance3D
				_check(boss.position.z + boss.mesh.get_aabb().position.z * boss.scale.z < 0.0375, "shield boss intersects the board instead of floating in side views")
				var rim := object.find_child("IronRim", true, false) as MeshInstance3D
				_check(rim.mesh is ArrayMesh and is_equal_approx(rim.mesh.get_aabb().size.z, 0.094), "forged flat rim encloses both plank cut edges")
				for rivet in object.find_children("Rivet*", "MeshInstance3D", true, false):
					_check(rivet.position.z < 0.053, "boss rivets sit on the mounting plate")
				for plank in object.find_children("ConceptOakPlank*", "MeshInstance3D", true, false):
					_check(is_equal_approx(plank.mesh.get_aabb().size.z, 0.075), "shield boards retain front and back thickness")
			"iron_cage_torch":
				_check(object.find_children("CageProng*", "MeshInstance3D", true, false).size() == 6, "torch has six production cage prongs")
				_check(object.find_child("PhotorealFlame", true, false) is Sprite3D, "real production flame remains connected")
			"weathered_staff":
				var crystal := object.find_child("CrackedFocusCrystal", true, false) as MeshInstance3D
				_check(crystal != null and crystal.material_override.emission_enabled, "staff retains actual emissive spell focus")
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
	_check(ExpeditionSession.capture_snapshot() == state and Input.mouse_mode == mouse, "equipment inspection preserves expedition and cursor")
	if failures.is_empty():
		print("DARK FANTASY EQUIPMENT TEST PASS: production materials, physical sides, unchanged blade extents and state")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
