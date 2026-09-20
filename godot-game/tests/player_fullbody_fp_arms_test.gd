extends SceneTree
## Asset-level regression for FP sleeves fitted to the standing body.
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	var body := APPEARANCE.create_body()
	root.add_child(body)
	var parts := body.find_children("*", "MeshInstance3D", true, false)
	check(parts.size() == 28, "24 retained body meshes and four FP parts")
	var names: Array[String] = []
	for part: MeshInstance3D in parts:
		var part_name := str(part.name)
		names.append(part_name)
		check(part.layers == APPEARANCE.BODY_LAYER, "dedicated body layer")
		for retired: String in ["SuppliedHand", "SuppliedNail", "FingerlessGlove", "Gravebound_Sleeve", "Gravebound_Bracer"]:
			check(not retired in part_name, "retired hand/sleeve geometry physically removed")
		if not part_name.begins_with("Gravebound_FP_"): continue
		var bounds := AABB()
		var first := true
		for surface in part.mesh.get_surface_count():
			for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := body.to_local(part.to_global(vertex))
				if first: bounds = AABB(point,Vector3.ZERO); first = false
				else: bounds = bounds.expand(point)
			var material := part.get_active_material(surface) as BaseMaterial3D
			check(material != null and material.albedo_texture != null and material.normal_texture != null, "FP material maps retained")
		check(bounds.size.x < (.33 if part_name.ends_with("_Arm") else .24) and bounds.size.z < .24, "FP parts fitted to body; sloping upper sleeves include their shoulder inset: "+part_name+" "+str(bounds))
		if part_name.ends_with("_Arm"):
			check(bounds.end.y > 1.42 and bounds.end.y < 1.46, "sleeve opening reaches under shoulder mantle")
			check(bounds.position.y > .92 and bounds.position.y < .97, "wrist seam remains at original body fit")
		else:
			check(bounds.size.y > .16 and bounds.size.y < .27, "relaxed glove and fingers retain anatomical length")
	for side in ["L", "R"]:
		for section in ["Arm", "Hand"]:
			check(names.count("Gravebound_FP_"+side+"_"+section) == 1, "one actual arm/hand per side")
	body.free()
	for failure in failures: push_error(failure)
	print("PLAYER FULLBODY FP ARMS "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
