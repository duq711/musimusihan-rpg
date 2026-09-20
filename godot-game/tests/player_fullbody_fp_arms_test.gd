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
		var forearm := AABB()
		var forearm_first := true
		var wrist_section := AABB()
		var wrist_first := true
		var uses_outfit_material := false
		for surface in part.mesh.get_surface_count():
			for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := body.to_local(part.to_global(vertex))
				if part_name.ends_with("_Hand") and point.y > .841 and point.y < .859:
					if wrist_first: wrist_section = AABB(point, Vector3.ZERO); wrist_first = false
					else: wrist_section = wrist_section.expand(point)
				if part_name.ends_with("_Arm") and point.y > 1.02 and point.y < 1.12:
					if forearm_first: forearm = AABB(point, Vector3.ZERO); forearm_first = false
					else: forearm = forearm.expand(point)
				if first: bounds = AABB(point,Vector3.ZERO); first = false
				else: bounds = bounds.expand(point)
			var material := part.get_active_material(surface) as BaseMaterial3D
			uses_outfit_material = uses_outfit_material or material.resource_name == "Gravebound_Matched_Sleeve_Cloth"
			check(material != null and material.albedo_texture != null and (material.resource_name == "Gravebound_Matched_Sleeve_Cloth" or material.normal_texture != null), "matched outfit cloth or preserved FP skin/hand maps")
		check(bounds.size.x < (.33 if part_name.ends_with("_Arm") else .15) and bounds.size.z < .24, "FP parts fitted to body; sloping upper sleeves include their shoulder inset: "+part_name+" "+str(bounds))
		if part_name.ends_with("_Arm"):
			check(uses_outfit_material, "sleeve cloth uses the matched outfit material")
			check(not forearm_first and forearm.size.x < .14 and forearm.size.z < .13, "forearm no longer inflated by first-person proportions")
			check(bounds.end.y > 1.42 and bounds.end.y < 1.46, "sleeve opening reaches under shoulder mantle")
			check(bounds.position.y > .86 and bounds.position.y < .89, "pre-wrist-edit sleeve cuff restored")
		else:
			check(not wrist_first and wrist_section.size.x > .08 and wrist_section.size.x < .10 and wrist_section.size.z < .08, "pre-wrist-edit glove width restored")
			check(bounds.position.y > .67 and bounds.position.y < .70, "relaxed fingertips reach the upper thigh")
			check(bounds.size.y > .20 and bounds.size.y < .22, "pre-wrist-edit glove length restored")
	for side in ["L", "R"]:
		for section in ["Arm", "Hand"]:
			check(names.count("Gravebound_FP_"+side+"_"+section) == 1, "one actual arm/hand per side")
	body.free()
	for failure in failures: push_error(failure)
	print("PLAYER FULLBODY FP ARMS "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
