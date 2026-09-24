extends SceneTree
## Asset-level regression for the four-view calibrated full-body proportions.
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []
const JOIN_TOLERANCE := .00001
func _point_cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / JOIN_TOLERANCE), floori(point.y / JOIN_TOLERANCE), floori(point.z / JOIN_TOLERANCE))
func _bounds(points: Array[Vector3]) -> AABB:
	var result := AABB(points[0], Vector3.ZERO)
	for point in points: result = result.expand(point)
	return result
func _shared_points(first: Array[Vector3], second: Array[Vector3]) -> Array[Vector3]:
	# Compare actual imported positions, independent of historical palm rotations.
	var cells: Dictionary = {}
	for point in first:
		var key := _point_cell(point)
		if not cells.has(key): cells[key] = []
		cells[key].append(point)
	var found: Dictionary = {}
	for point in second:
		var key := _point_cell(point)
		var matched := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					for candidate: Vector3 in cells.get(key + Vector3i(dx, dy, dz), []):
						if point.distance_to(candidate) <= JOIN_TOLERANCE:
							matched = true
		if matched: found[key] = point
	var result: Array[Vector3] = []
	for point: Vector3 in found.values(): result.append(point)
	return result
func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	# Calibrated source geometry is preserved as the public fallback; the
	# optional local Roger character has its own fitted body proportions.
	var body := APPEARANCE.create_body(false)
	root.add_child(body)
	var parts := body.find_children("*", "MeshInstance3D", true, false)
	check(parts.size() == 25, "the calibrated 20 base meshes remain alongside five supplied garment meshes")
	for retired_outfit_name in APPEARANCE.RETIRED_OUTFIT_PARTS:
		var retired_outfit := body.find_child(retired_outfit_name, true, false) as MeshInstance3D
		check(retired_outfit != null and not retired_outfit.visible, "original fitted geometry stays available but hidden beneath the supplied outfit: " + retired_outfit_name)
	for retired: String in ["Gravebound_PointHood", "Gravebound_InnerNeckCowl", "Gravebound_Mantle_L", "Gravebound_Mantle_R", "Gravebound_MantleBack", "Gravebound_CoatBackAndSides", "Gravebound_CoatSkirt_L", "Gravebound_CoatSkirt_R"]:
		check(body.find_child(retired, true, false) == null, "retired hood, neck cloth or long coat tail physically removed from the imported model: " + retired)
	check(body.find_child("Gravebound_AnatomicalHead", true, false) != null, "head retained")
	var names: Array[String] = []
	var part_points: Dictionary = {}
	var full_points: Array[Vector3] = []
	for part: MeshInstance3D in parts:
		var part_name := str(part.name)
		names.append(part_name)
		check(part.layers == APPEARANCE.BODY_LAYER, "dedicated body layer")
		for retired: String in ["SuppliedHand", "SuppliedNail", "FingerlessGlove", "Gravebound_Sleeve", "Gravebound_Bracer"]:
			check(not retired in part_name, "retired hand/sleeve geometry physically removed")
		var points: Array[Vector3] = []
		for surface in part.mesh.get_surface_count():
			for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				points.append(body.to_local(part.to_global(vertex)))
		part_points[part_name] = points
		full_points.append_array(points)
		if not part_name.begins_with("Gravebound_FP_"): continue
		var bounds := AABB()
		var first := true
		# Thin cross-sections measure thickness without counting the depth
		# traveled by the sloping forearm after the elbow-height adjustment.
		var forearm_heights: Array[float] = [1.00, 1.07, 1.13]
		var forearm_sections: Array[AABB] = [AABB(), AABB(), AABB()]
		var forearm_samples: Array[int] = [0, 0, 0]
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
					# The baked upper-sleeve patch follows the fitted geometry;
					# it must remain above the lower forearm and cuff.
					check(point.y > 1.14, "textile blend is confined above the lower sleeve")
				if part_name.ends_with("_Arm"):
					for section in forearm_heights.size():
						if absf(point.y - forearm_heights[section]) < .004:
							if forearm_samples[section] == 0: forearm_sections[section] = AABB(point, Vector3.ZERO)
							else: forearm_sections[section] = forearm_sections[section].expand(point)
							forearm_samples[section] += 1
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
			for section in forearm_heights.size():
				check(forearm_samples[section] > 20 and forearm_sections[section].size.x < .14 and forearm_sections[section].size.z < .13, "forearm thickness stays fitted to body at height " + str(forearm_heights[section]))
			check(bounds.end.y > 1.42 and bounds.end.y < 1.46, "sleeve upper end retains its fitted shoulder height")
			check(bounds.position.y > .905 and bounds.position.y < .925, "sleeve cuff reaches the calibrated wrist height")
		else:
			check(bounds.size.z > bounds.size.x * 1.15, "relaxed hands face the thighs instead of the rear")
			check(bounds.position.y > .73 and bounds.position.y < .76, "fingertips follow the reference arm length near the upper thigh")
			check(bounds.size.y > .19 and bounds.size.y < .215, "hand and glove retain a human-scale length after the full-body fit")
	var full_bounds := _bounds(full_points)
	check(full_bounds.size.y > 1.70 and full_bounds.size.y < 1.725 and full_bounds.end.y > 1.71 and full_bounds.end.y < 1.73, "reference fit retains the 1.712 m calibrated stature")
	var belt_bounds := _bounds(part_points["Gravebound_LeatherBelt"])
	var belt_height := belt_bounds.get_center().y
	# These are independent calibrated guide ranges, not the old mesh dimensions.
	# A nonlinear fit maps the old centre differently from its transformed AABB.
	check(belt_height > .975 and belt_height < 1.005, "belt follows the reference waist height near .985 m")
	var crotch_height := INF
	for side in ["L", "R"]:
		var arm_points: Array[Vector3] = part_points["Gravebound_FP_" + side + "_Arm"]
		var hand_points: Array[Vector3] = part_points["Gravebound_FP_" + side + "_Hand"]
		var wrist_points := _shared_points(arm_points, hand_points)
		check(wrist_points.size() >= 20, "sleeve and glove share the actual wrist boundary within 10 micrometres: " + side)
		if not wrist_points.is_empty():
			var wrist_bounds := _bounds(wrist_points)
			check(wrist_bounds.get_center().y > .925 and wrist_bounds.get_center().y < .937, "shared cuff centre matches reference wrist height .931 m: " + side)
			check(absf(wrist_bounds.get_center().x) > .365 and absf(wrist_bounds.get_center().x) < .395, "wrist lateral position matches the reference relaxed stance: " + side)
			# The reference sleeve projects to about 6 cm at the wrist. Its
			# tilted skin/glove joining ring is narrower than the visible cloth.
			check(wrist_bounds.size.x > .045 and wrist_bounds.size.x < .07 and wrist_bounds.size.z > .060 and wrist_bounds.size.z < .095 and wrist_bounds.size.y < .045, "shared cuff has a fitted cross-section without a stretched connector: " + side)
		var shoulder_points := _shared_points(part_points["Gravebound_QuiltedTorso"], arm_points)
		check(shoulder_points.size() >= 200, "body and sleeve retain their continuous shoulder boundary: " + side)
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
		check(highest > .985 and highest < 1.005, "trousers reach the calibrated waist beneath the belt: " + trouser_name)
		for point: Vector3 in part_points[trouser_name]:
			if absf(point.x) < .006: crotch_height = minf(crotch_height, point.y)
		var boot_bounds := _bounds(part_points["Gravebound_Boot_" + side])
		check(boot_bounds.end.y > .425 and boot_bounds.end.y < .445, "boot shaft ends near the reference .435 m height: " + side)
		check(boot_bounds.position.y > .002 and boot_bounds.position.y < .015, "boot soles stay grounded: " + side)
		check(boot_bounds.size.z > .28 and boot_bounds.size.z < .345, "oversized boots are shortened to the reference side-view scale: " + side)
		var trouser_bounds := _bounds(part_points[trouser_name])
		check(trouser_bounds.position.y < boot_bounds.end.y - .04, "trouser hems remain tucked into the fitted boots: " + side)
	check(crotch_height > .77 and crotch_height < .795, "central trouser bridge matches the reference .782 m crotch height")
	check(belt_height - crotch_height > .19 and belt_height - crotch_height < .23, "waist-to-crotch proportion follows the calibrated full-body reference")
	body.free()
	for failure in failures: push_error(failure)
	print("PLAYER FULLBODY FP ARMS "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
