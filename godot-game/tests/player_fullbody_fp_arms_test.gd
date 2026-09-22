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
	check(parts.size() == 20, "16 body meshes and four FP parts; hood, neck cowl and long coat tails removed")
	for retired: String in ["Gravebound_PointHood", "Gravebound_InnerNeckCowl", "Gravebound_Mantle_L", "Gravebound_Mantle_R", "Gravebound_MantleBack", "Gravebound_CoatBackAndSides", "Gravebound_CoatSkirt_L", "Gravebound_CoatSkirt_R"]:
		check(body.find_child(retired, true, false) == null, "retired hood, neck cloth or long coat tail physically removed from the imported model: " + retired)
	check(body.find_child("Gravebound_AnatomicalHead", true, false) != null, "head retained")
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
		var uses_blended_sleeve := false
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as BaseMaterial3D
			if material == null:
				check(false, "FP surfaces require a material")
				continue
			var is_blended_sleeve := material.resource_name in ["Gravebound_Sleeve_Flow_L", "Gravebound_Sleeve_Flow_R"]
			var is_cloth := material.resource_name == "Gravebound_Matched_Sleeve_Cloth" or is_blended_sleeve
			uses_blended_sleeve = uses_blended_sleeve or is_blended_sleeve
			if is_blended_sleeve:
				check(part_name.ends_with("_Arm"), "blended cloth must not replace hand or wrist skin")
				check(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and material.roughness > .8, "baked cloth retains lit rough PBR shading")
				check(material.normal_enabled and material.normal_texture != null, "baked textile retains its tangent-space surface detail")
			for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := body.to_local(part.to_global(vertex))
				if is_blended_sleeve:
					check(point.y > 1.17, "textile blend is confined above the lower sleeve")
				if part_name.ends_with("_Hand"):
					# Measure the same cuff section in its original frame after palm rotation.
					var side_sign := -1.0 if "_L_" in part_name else 1.0
					var pivot := Vector3(side_sign * .29, .87, -.075)
					var elbow := Vector3(side_sign * .268, 1.155, -.004)
					# Undo the rigid 18mm shoulder-width offset before the palm rotation.
					var wrist_point := pivot + Basis((elbow-pivot).normalized(), deg_to_rad(side_sign*90.0)) * (point - Vector3(side_sign*(.015 + .018), 0, 0) - pivot)
					if wrist_point.y > .841 and wrist_point.y < .859:
						if wrist_first: wrist_section = AABB(wrist_point, Vector3.ZERO); wrist_first = false
						else: wrist_section = wrist_section.expand(wrist_point)
				if part_name.ends_with("_Arm") and point.y > 1.02 and point.y < 1.12:
					if forearm_first: forearm = AABB(point, Vector3.ZERO); forearm_first = false
					else: forearm = forearm.expand(point)
				if first: bounds = AABB(point,Vector3.ZERO); first = false
				else: bounds = bounds.expand(point)
			uses_outfit_material = uses_outfit_material or is_cloth
			if not is_cloth:
				check(material.resource_name.begins_with("Gravebound_Natural_Hands_"), "both hands and wrist skin use the graded skin texture")
			check(material.albedo_texture != null and (is_cloth or material.normal_texture != null), "matched outfit cloth or preserved FP skin/hand maps")
		check(bounds.size.x < (.33 if part_name.ends_with("_Arm") else .15) and bounds.size.z < .24, "FP parts fitted to body; sloping upper sleeves include their shoulder inset: "+part_name+" "+str(bounds))
		if part_name.ends_with("_Arm"):
			check(uses_outfit_material, "sleeve cloth uses the matched outfit material")
			check(uses_blended_sleeve, "upper sleeve uses the baked textile transition")
			check(not forearm_first and forearm.size.x < .14 and forearm.size.z < .13, "forearm no longer inflated by first-person proportions")
			check(bounds.end.y > 1.42 and bounds.end.y < 1.46, "sleeve upper end retains its fitted shoulder height")
			check(bounds.position.y > .86 and bounds.position.y < .89, "pre-wrist-edit sleeve cuff restored")
		else:
			check(bounds.size.z > bounds.size.x * 1.15, "relaxed hands face the thighs instead of the rear")
			check(not wrist_first and wrist_section.size.x > .08 and wrist_section.size.x < .10 and wrist_section.size.z < .08, "glove cuff dimensions preserved in the original frame")
			check(bounds.position.y > .67 and bounds.position.y < .70, "relaxed fingertips reach the upper thigh")
			check(bounds.size.y > .20 and bounds.size.y < .22, "pre-wrist-edit glove length restored")
	for side in ["L", "R"]:
		for section in ["Arm", "Hand"]:
			check(names.count("Gravebound_FP_"+side+"_"+section) == 1, "one actual arm/hand per side")
		var trouser_name: String = "Gravebound_Trousers_" + side
		check(names.count(trouser_name) == 1, "one actual trouser half per side")
		var trousers := body.find_child(trouser_name, true, false) as MeshInstance3D
		if trousers == null or trousers.mesh == null:
			check(false, "complete trousers must remain after the coat tails are removed: " + trouser_name)
			continue
		var highest := -INF
		for surface in trousers.mesh.get_surface_count():
			for vertex: Vector3 in trousers.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				highest = maxf(highest, body.to_local(trousers.to_global(vertex)).y)
		check(highest >= 1.08, "trousers must extend through the exposed pelvis to the waist: " + trouser_name)
	body.free()
	for failure in failures: push_error(failure)
	print("PLAYER FULLBODY FP ARMS "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
