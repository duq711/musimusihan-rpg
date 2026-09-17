extends Node3D
## A continuous anatomical hand with fifteen deforming finger joints. Wrist
## space is shared by the production equipment contacts: fingers -Z, back +Y.
const LEGACY_FIT := preload("res://scripts/player_arm_visual.gd")
const LEFT := preload("res://assets/3d/player/sword_shield/left_arm.glb")
const RIGHT := preload("res://assets/3d/player/sword_shield/right_arm.glb")
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const GRIP_CENTER := Vector3(0.0, -0.0275, -0.0925)
const DISTAL_LENGTH := {"little": 0.022, "ring": 0.0263, "middle": 0.0275, "index": 0.0253, "thumb": 0.03125}
const SWORD_CURL := {"little": Vector3(-0.86, -1.14, -0.93), "ring": Vector3(-0.92, -1.08, -0.64), "middle": Vector3(-1.02, -1.16, -0.49), "index": Vector3(-0.85, -1.11, -0.78), "thumb": Vector3(0.10, -0.48, -1.35)}
const SHIELD_CURL := {"little": Vector3(-1.50, -1.60, -0.40), "ring": Vector3(-1.47, -1.56, -0.90), "middle": Vector3(-1.43, -1.13, -1.35), "index": Vector3(-1.31, -1.84, -0.62), "thumb": Vector3(0.60, -0.92, -1.40)}
var arm_meshes: Array[MeshInstance3D] = []
var hand_meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var _imported_rotations: Array[Quaternion] = []
var _forearm: Node3D
var _upper_arm: Node3D
var _cuff: Node3D
var _side := 1
var _geometry_side := -1
var grip_amount := 0.0
var _last_thumb_amount := -2.0
var _grip_role := ""
var _grip_cache: Dictionary = {}
var _digit_contacts: Dictionary = {}
var _grip_solve_count := 0
var _pad_influences: Dictionary = {}
var _pad_sample_counts: Dictionary = {}
var _sword_surface_valid := false
var _sword_surface := Transform3D.IDENTITY
var _sword_surface_inverse := Transform3D.IDENTITY
var _sword_surface_input := Transform3D.IDENTITY
var _sword_surface_key := "nominal"
var _last_grip_surface_key := ""
var _shield_surface_valid := false
var _shield_surface := Transform3D.IDENTITY
var _shield_surface_inverse := Transform3D.IDENTITY
var _shield_surface_input := Transform3D.IDENTITY
var _shield_surface_key := "authored_curve"
var _contact_patch_specs: Dictionary = {}
static var _materials: Dictionary = {}


func setup(side: int) -> void:
	_side = -1 if side < 0 else 1
	# With fingers -Z and the dorsal surface +Y, an anatomical right hand
	# has its thumb/index on -X. Equipment role and geometric chirality differ.
	_geometry_side = -_side
	var model := (LEFT if _side < 0 else RIGHT).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	for bone in skeleton.get_bone_count(): _imported_rotations.append(skeleton.get_bone_pose_rotation(bone))
	_forearm = model.find_child("Forearm*", true, false) as Node3D
	_upper_arm = model.find_child("UpperArm*", true, false) as Node3D
	_cuff = model.find_child("WristCuff*", true, false) as Node3D
	_prepare(model)
	_prepare_skin_pads()
	_set_canonical_shield_surface()
	set_meta("source_model", LEFT.resource_path if _side < 0 else RIGHT.resource_path)
	set_meta("anatomical_side", _side)
	set_meta("anatomical_thumb_side", _geometry_side)
	set_meta("continuous_skin", true)
	set_grip(0.9)


func _prepare(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part.skin != null: hand_meshes.append(part)
		else: arm_meshes.append(part)
		prepare_materials(part)
	for child in node.get_children(): _prepare(child)


static func prepare_materials(part: MeshInstance3D) -> void:
	for surface in part.mesh.get_surface_count():
		var source := part.get_active_material(surface) as StandardMaterial3D
		if source == null: continue
		var key := source.get_instance_id()
		if _materials.has(key):
			part.set_surface_override_material(surface, _materials[key])
			continue
		var material := source.duplicate() as StandardMaterial3D
		match source.resource_name:
			"FP_SwordBlade", "FP_SwordEdge", "FP_SwordFurniture", "FP_SwordFuller", "FP_SwordLeather", "FP_ShieldOak", "FP_ShieldIron", "FP_ShieldEdge", "FP_ShieldEnarmes", "FP_ShieldLeatherEdge", "FP_ShieldStitch":
				# Mesh UVs address the original four-bank ImageGen atlas. Vertex
				# color is baked from occlusion of the actual solid construction.
				material.albedo_texture = load("res://assets/ai/sword_shield/weapon_material_atlas_v2.png")
				material.vertex_color_use_as_albedo = true
				material.albedo_color = Color.WHITE
				material.normal_enabled = true
				material.normal_texture = load("res://assets/ai/sword_shield/weapon_material_normal_v2.png")
				material.normal_scale = 0.45
				material.roughness_texture = null
				material.metallic_specular = 0.5
				var is_organic := source.resource_name in ["FP_SwordLeather", "FP_ShieldOak", "FP_ShieldEnarmes", "FP_ShieldLeatherEdge", "FP_ShieldStitch"]
				material.metallic = 0.0 if is_organic else 0.62
				material.roughness = 1.0 if is_organic else 0.48
				if is_organic:
					material.roughness_texture = null
					material.roughness = 0.86 if source.resource_name == "FP_ShieldOak" else 0.67
					material.albedo_color = Color(0.46, 0.43, 0.40) if source.resource_name == "FP_ShieldOak" else Color(0.35, 0.32, 0.29)
				if source.resource_name in ["FP_SwordEdge", "FP_ShieldEdge"]:
					material.albedo_color = Color(1.2, 1.22, 1.23)
					material.roughness = 0.38
				if source.resource_name == "FP_SwordFuller": material.albedo_color = Color(0.55, 0.57, 0.59)
				if source.resource_name.begins_with("FP_Sword"): material.normal_scale = 0.22
				if source.resource_name == "FP_ShieldIron":
					material.metallic = 0.68
					material.roughness = 0.48
					material.normal_scale = 0.28
				if source.resource_name == "FP_ShieldEdge":
					material.albedo_color = Color(0.68, 0.70, 0.71)
					material.roughness = 0.44
					material.normal_scale = 0.20
				if source.resource_name == "FP_ShieldLeatherEdge": material.albedo_color = Color(0.60, 0.45, 0.34)
				if source.resource_name == "FP_ShieldStitch": material.albedo_color = Color(1.3, 1.14, 0.89)
			"FP_Skin":
				material.albedo_color = Color(0.75, 0.75, 0.75)
				material.albedo_texture = load("res://assets/ai/sword_shield/weathered_hand_skin.png")
				material.roughness = 0.72
				material.uv1_scale = Vector3(2, 2, 2)
			"FP_WornLeather", "FP_LayeredVambrace", "FP_EnarmesLeather", "FP_SleeveStrap":
				material.albedo_color = Color(0.43, 0.43, 0.43)
				if source.resource_name == "FP_LayeredVambrace": material.albedo_color = Color(0.60, 0.54, 0.45)
				if source.resource_name == "FP_WornLeather": material.albedo_color = Color(0.62, 0.58, 0.52)
				if source.resource_name == "FP_EnarmesLeather": material.albedo_color = Color(0.36, 0.26, 0.17)
				if source.resource_name == "FP_SleeveStrap": material.albedo_color = Color(0.25,0.21,0.17)
				material.albedo_texture = load("res://assets/ai/sword_shield/worn_charcoal_leather.png")
				material.roughness = 0.68 if source.resource_name == "FP_EnarmesLeather" else 0.82
				if source.resource_name == "FP_WornLeather": material.roughness = 0.66
				if source.resource_name == "FP_LayeredVambrace": material.roughness = 0.74
				material.normal_enabled = true
				material.normal_texture = load("res://assets/3d/player/sword_shield/textures/leather_normal.jpg")
				material.normal_scale = 0.20 if source.resource_name == "FP_WornLeather" else 0.15
				material.uv1_scale = Vector3(0.5,0.5,0.5)
			"FP_SleeveBuckles":
				material.albedo_color = Color(0.20,0.21,0.20)
				material.metallic = 0.55
				material.roughness = 0.72
			"FP_LeatherEdge": material.albedo_color = Color(0.17,0.14,0.11)
			"FP_WaxedThread": material.albedo_color = Color(0.23,0.20,0.17)
			"FP_QuiltedLinen":
				material.albedo_color = Color(0.12, 0.105, 0.085)
				material.roughness = 0.94
				material.albedo_texture = load("res://assets/3d/player/sword_shield/textures/linen_albedo.jpg")
				material.normal_enabled = true
				material.normal_texture = load("res://assets/3d/player/sword_shield/textures/linen_normal.jpg")
				material.normal_scale = 0.38
			"FP_WornOak":
				material.albedo_color = Color(0.34, 0.31, 0.27)
				material.albedo_texture = load("res://assets/3d/abandoned_mine/textures/rough_wood_albedo_2k.jpg")
				material.normal_texture = load("res://assets/3d/abandoned_mine/textures/rough_wood_normal_gl_2k.jpg")
				material.normal_enabled = true
				material.normal_scale = 0.65
				material.roughness = 1.0
				material.metallic_specular = 0.12
				material.roughness_texture = null
			"FP_BrushedSteel", "FP_AgedSteel", "FP_RolledRimSteel":
				material.albedo_texture = load("res://assets/ai/materials/concept_forged_steel.png")
				material.albedo_color = Color(0.90, 0.92, 0.94) if source.resource_name == "FP_BrushedSteel" else Color(0.52, 0.55, 0.58)
				material.roughness = 0.34 if source.resource_name == "FP_BrushedSteel" else 0.42
				material.metallic = 0.25 if source.resource_name == "FP_BrushedSteel" else 0.45
				material.metallic_specular = 0.75
				if source.resource_name == "FP_RolledRimSteel":
					material.albedo_color = Color(0.60, 0.63, 0.65)
					material.metallic = 0.40
					material.roughness = 0.32
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[key] = material
		part.set_surface_override_material(surface, material)


func set_grip(amount: float, thumb_amount: float = -1.0) -> void:
	# Compatibility for the existing equipment callers. These two imported
	# arms are dedicated to sword and shield; other weapons keep their own rig.
	_set_combat_grip("shield" if _side < 0 else "sword", amount, thumb_amount)


func set_combat_grip(role: String, tension: float) -> void:
	if role not in ["sword", "shield"]: return
	_set_combat_grip(role, tension, -1.0)


func set_sword_grip_surface(weapon_from_hand: Transform3D) -> void:
	# The player supplies this only after fitting its final wrist. The actual
	# shaft is oval, so a fixed circular target cannot follow a rolling hand.
	if not weapon_from_hand.is_finite() or absf(weapon_from_hand.basis.determinant()) < 0.00001: return
	if _sword_surface_valid and _sword_surface_input.is_equal_approx(weapon_from_hand): return
	_sword_surface_input = weapon_from_hand
	var angles := weapon_from_hand.basis.get_euler()
	var step := deg_to_rad(0.5)
	angles = Vector3(snappedf(angles.x, step), snappedf(angles.y, step), snappedf(angles.z, step))
	var quantized_origin := weapon_from_hand.origin.snapped(Vector3.ONE * 0.000125)
	var key := "%d,%d,%d:%d,%d,%d" % [roundi(angles.x / step), roundi(angles.y / step), roundi(angles.z / step), roundi(quantized_origin.x / 0.000125), roundi(quantized_origin.y / 0.000125), roundi(quantized_origin.z / 0.000125)]
	if _sword_surface_valid and key == _sword_surface_key: return
	_sword_surface_valid = true
	_sword_surface_key = key
	_sword_surface = Transform3D(Basis.from_euler(angles), quantized_origin)
	_sword_surface_inverse = _sword_surface.affine_inverse()


func _set_canonical_shield_surface() -> void:
	# Same fixed loop and wrist fit used by Player. The mirrored fixture lets
	# independent tests exercise either anatomical hand without a scene.
	var grip := Vector3(-0.18, 0.015, -0.1287358105)
	var x := Vector3(-0.0081963986, 0.1172137745, -0.0009387657).normalized()
	var back := Vector3(0.13, -0.005, -0.0714568114) - grip
	var z := (back - x * back.dot(x)).normalized()
	var basis := Basis(x * _geometry_side, z.cross(x).normalized(), z)
	_shield_surface = Transform3D(basis, grip - basis * GRIP_CENTER)
	_shield_surface_inverse = _shield_surface.affine_inverse()


func set_shield_grip_surface(shield_from_hand: Transform3D) -> void:
	# This transform includes the production shield model's Y=PI orientation.
	# The padded grip follows the actual arched 30 by 22 mm closed section.
	if not shield_from_hand.is_finite() or absf(shield_from_hand.basis.determinant()) < 0.00001: return
	if _shield_surface_valid and _shield_surface_input.is_equal_approx(shield_from_hand): return
	_shield_surface_input = shield_from_hand
	var angles := shield_from_hand.basis.get_euler()
	var step := deg_to_rad(0.5)
	angles = Vector3(snappedf(angles.x, step), snappedf(angles.y, step), snappedf(angles.z, step))
	var origin := shield_from_hand.origin.snapped(Vector3.ONE * 0.000125)
	var key := "%d,%d,%d:%d,%d,%d" % [roundi(angles.x / step), roundi(angles.y / step), roundi(angles.z / step), roundi(origin.x / 0.000125), roundi(origin.y / 0.000125), roundi(origin.z / 0.000125)]
	if _shield_surface_valid and key == _shield_surface_key: return
	_shield_surface_valid = true
	_shield_surface_key = key
	_shield_surface = Transform3D(Basis.from_euler(angles), origin)
	_shield_surface_inverse = _shield_surface.affine_inverse()


static func _authored_shield_loop(u: float, v: float) -> Vector3:
	# Exact surface authored in sword_shield_multiview/shield_geometry.py,
	# exported Blender (X,Y,Z) -> Godot (X,Z,-Y). Solidify adds 2 mm per side.
	var angle := deg_to_rad(-4.0)
	var center_x := -0.18 + v * sin(angle)
	var center_y := 0.015 + v * cos(angle)
	var dish := 0.025 * maxf(0.0, 1.0 - (center_x * center_x + center_y * center_y) / (0.415 * 0.415))
	var rise := 0.145 * pow(maxf(0.0, sin(PI * (v / 0.235 + 0.5))), 0.62)
	var ripple := 0.0005 * cos((u / 0.044 + 0.5) * TAU)
	return Vector3(center_x + u * cos(angle), center_y - u * sin(angle), -(0.004 - dish + rise + ripple))


static func _padded_shield_vertex(row: int, angular: int) -> Vector3:
	# The production GLB retains 64 longitudinal segments and an 18-sided
	# closed section. Sample its authored vertices rather than a smooth oval;
	# the chord is up to 0.2 mm inside that mathematical surface.
	var v := (float(row) / 64.0 - 0.5) * 0.235
	var angle := deg_to_rad(-4.0)
	var axis := Vector3(cos(angle), -sin(angle), 0.0)
	var center := _authored_shield_loop(0.0, v) - Vector3(0.0, 0.0, 0.0005)
	var x := -0.18 + v * sin(angle)
	var y := 0.015 + v * cos(angle)
	var phase := PI * (v / 0.235 + 0.5)
	# Keep the derivative scalar until the final normal: subtracting two
	# float32 Vector3 positions 1 micrometre apart shifts the actual facets.
	var slope := 0.05 * (x * sin(angle) + y * cos(angle)) / (0.415 * 0.415)
	slope += 0.145 * 0.62 * PI / 0.235 * cos(phase) * pow(sin(phase), -0.38)
	var normal := Vector3(-slope * sin(angle), -slope * cos(angle), -1.0).normalized()
	var phi := deg_to_rad(10.0 + 20.0 * posmod(angular, 18))
	return center + axis * (0.015 * cos(phi)) + normal * (0.011 * sin(phi))


static func _padded_shield_surface(v: float, phi: float) -> Dictionary:
	# All hand contacts stay in the padded central rows. Attachment transitions
	# outside |v|=.0525 are geometry only and never replaced by this sampler.
	var row_coordinate := (clampf(v, -0.049, 0.049) / 0.235 + 0.5) * 64.0
	var angular_coordinate := fposmod((rad_to_deg(phi) - 10.0) / 20.0, 18.0)
	var row := floori(row_coordinate)
	var angular := floori(angular_coordinate)
	var r := row_coordinate - row
	var u := angular_coordinate - angular
	var p00 := _padded_shield_vertex(row, angular)
	var p10 := _padded_shield_vertex(row + 1, angular)
	var p01 := _padded_shield_vertex(row, angular + 1)
	var p11 := _padded_shield_vertex(row + 1, angular + 1)
	# Preserve the original exported diagonals, including their switch at the
	# loop crown. This gives the same facet and normal as the rendered mesh.
	var ascending := angular in [0, 1, 2, 3, 8, 9, 10, 11, 12]
	if row >= 32: ascending = not ascending
	var surface: Vector3
	var normal: Vector3
	if ascending:
		if r >= u:
			surface = p00 * (1.0 - r) + p10 * (r - u) + p11 * u
			normal = (p10 - p00).cross(p11 - p00).normalized()
		else:
			surface = p00 * (1.0 - u) + p01 * (u - r) + p11 * r
			normal = (p01 - p00).cross(p11 - p00).normalized()
	elif r + u <= 1.0:
		surface = p00 * (1.0 - r - u) + p10 * r + p01 * u
		normal = (p10 - p00).cross(p01 - p00).normalized()
	else:
		surface = p10 * (1.0 - u) + p01 * (1.0 - r) + p11 * (r + u - 1.0)
		normal = (p01 - p10).cross(p11 - p10).normalized()
	var center := _authored_shield_loop(0.0, v) - Vector3(0.0, 0.0, 0.0005)
	if normal.dot(surface - center) < 0.0: normal = -normal
	return {"surface": surface, "normal": normal}


func _shield_grip_contact(digit: String, along_grip: float, tension: float) -> Dictionary:
	var is_thumb := digit == "thumb"
	var nominal := Vector3(_geometry_side * 0.030 if is_thumb else along_grip, GRIP_CENTER.y, GRIP_CENTER.z)
	var point := _shield_surface * nominal
	var angle := deg_to_rad(-4.0)
	var v := clampf((point.x + 0.18) * sin(angle) + (point.y - 0.015) * cos(angle) + (0.00275 if is_thumb else 0.0), -0.049, 0.049)
	# Each physical phalanx bears on a different part of the padded oval.
	# The long middle finger bears through its proximal glove; PIP and DIP can then
	# close against the palm rather than forming a long unsupported C.
	var phi := deg_to_rad(170.0 if digit == "middle" else 280.0 if is_thumb else 30.0 if digit == "ring" else 15.0)
	var contact := _padded_shield_surface(v, phi)
	var normal: Vector3 = contact.normal
	var surface: Vector3 = contact.surface
	var clearance := lerpf(0.0022, 0.0020, tension)
	if digit == "index": clearance += 0.0005
	elif is_thumb: clearance += 0.00125
	var target := surface + normal * clearance
	return {"target": _shield_surface_inverse * target, "surface": _shield_surface_inverse * surface, "inward": -(_shield_surface_inverse.basis * normal).normalized(), "uv": Vector2(phi, v)}


func _set_combat_grip(role: String, tension: float, thumb_amount: float) -> void:
	if skeleton == null or not is_finite(tension) or not is_finite(thumb_amount): return
	var amount := snappedf(clampf(tension, 0.0, 1.0), 1.0 / 128.0)
	var thumb := -1.0 if thumb_amount < 0.0 else snappedf(clampf(thumb_amount, 0.0, 1.0), 1.0 / 128.0)
	var surface_key := _sword_surface_key if role == "sword" else _shield_surface_key
	if role == _grip_role and is_equal_approx(grip_amount, amount) and is_equal_approx(_last_thumb_amount, thumb) and surface_key == _last_grip_surface_key: return
	grip_amount = amount
	_last_thumb_amount = thumb
	_grip_role = role
	_last_grip_surface_key = surface_key
	var key := "%s:%d:%d:%s" % [role, roundi(amount * 128.0), roundi(thumb * 128.0), surface_key]
	if _grip_cache.has(key):
		var cached: Dictionary = _grip_cache[key]
		for bone in skeleton.get_bone_count():
			if skeleton.get_bone_name(bone) != "wrist": skeleton.set_bone_pose_rotation(bone, cached.rotations[bone])
		_digit_contacts = cached.contacts
		return
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone) != "wrist": skeleton.set_bone_pose_rotation(bone, _imported_rotations[bone])
	_digit_contacts = {}
	var profile: Dictionary = SWORD_CURL if role == "sword" else SHIELD_CURL
	for digit: String in DIGITS:
		var strength := thumb if digit == "thumb" and thumb >= 0.0 else amount
		var root_bone := skeleton.find_bone(digit + "0")
		if root_bone < 0: continue
		if role == "shield" and digit != "thumb":
			_solve_shield_power_digit(digit, profile[digit] * strength, strength)
			continue
		var open_pad := _digit_pad(digit)
		var target := _grip_pad_target(role, digit, skeleton.get_bone_global_pose(root_bone).origin.x, amount)
		target = open_pad.lerp(target, smoothstep(0.0, 0.75, strength))
		_solve_digit_contact(digit, target, profile[digit] * strength, strength)
		if role == "shield":
			var contact := _shield_grip_contact(digit, 0.0, amount)
			_digit_contacts[digit].contact_kind = "strap"
			_digit_contacts[digit].patch = digit
			_digit_contacts[digit].surface = contact.surface
			_digit_contacts[digit].inward = contact.inward
			_digit_contacts[digit].uv = contact.uv
			_digit_contacts[digit].surface_kind = "padded_18gon"
	if role == "shield":
		if amount >= 0.75:
			# Thumb opposition also deforms the index palmar patch through shared
			# weights. Finalize terminal folds after every digit has its pose.
			for digit: String in ["ring", "middle", "index"]:
				var record: Dictionary = _digit_contacts[digit]
				_digit_contacts[digit].angles = _settle_shield_terminal(digit, record.angles, float(record.lateral))
		# The little finger's palmar patch includes neighboring MCP weights;
		# settle it once all three load-bearing fingers have closed.
		_solve_shield_power_digit("little", profile.little * amount, amount)
	var rotations: Array[Quaternion] = []
	for bone in skeleton.get_bone_count(): rotations.append(skeleton.get_bone_pose_rotation(bone))
	# Quantized presentation poses are reusable during animation. Bound this
	# per-arm cache even for callers varying the optional thumb independently.
	if _grip_cache.size() >= 384: _grip_cache.clear()
	_grip_cache[key] = {"rotations": rotations, "contacts": _digit_contacts.duplicate(true)}
	_grip_solve_count += 1


func _grip_pad_target(role: String, digit: String, along_grip: float, tension: float) -> Vector3:
	if digit == "thumb":
		# The visible palmar pad touches the real object: a 19.7 mm radial
		# contact on the 17.2–18 mm shaft, or 2 mm off the near ribbon face.
		# The previous thumb target sat 31.76 mm off-axis and could never grip.
		if role == "sword": return _project_sword_surface(Vector3(_geometry_side * 0.054, -0.047125835, -0.090783032), tension, 0.0004)
		return _shield_grip_contact(digit, along_grip, tension).target
	if role == "sword":
		# A ~36 mm oval leather shaft runs along wrist-local X. The distal pad
		# meets its underside while the middle phalanx clears the shaft wall.
		var radius := lerpf(0.0180, 0.0172, clampf((along_grip * _geometry_side + 0.054) / 0.092, 0.0, 1.0))
		return _project_sword_surface(Vector3(along_grip, GRIP_CENTER.y - radius - lerpf(0.0014, 0.0005, tension), GRIP_CENTER.z), tension)
	return _shield_grip_contact(digit, along_grip, tension).target


func _project_sword_surface(nominal: Vector3, tension: float, pad_thickness := 0.0) -> Vector3:
	if not _sword_surface_valid: return nominal
	var point := _sword_surface * nominal
	point.y = clampf(point.y, -0.1634, -0.0332)
	# Exact authored GripLeather radii from sword_geometry.py, with the real
	# 0.52–0.80 mm folded wrap represented by its 0.66 mm middle surface.
	# The current one-hand model compresses only grip Y by .60 about y=-.026;
	# evaluate the original radius curve in its uncompressed source space.
	var source_y := -0.026 + (point.y + 0.026) / 0.60
	var ratio := clampf((source_y + 0.267) / 0.241, 0.0, 1.0)
	var radii := Vector2(1.28 * (0.0148 + 0.0020 * ratio + 0.0010 * sin(ratio * PI)), 1.22 * (0.0107 + 0.0013 * ratio + 0.0005 * sin(ratio * PI))) + Vector2.ONE * 0.00066
	var direction := Vector2(point.x, point.z).normalized()
	if direction.length_squared() < 0.5: direction = Vector2.RIGHT
	var radius := 1.0 / sqrt(direction.x * direction.x / (radii.x * radii.x) + direction.y * direction.y / (radii.y * radii.y))
	var surface := direction * radius
	var normal := Vector2(surface.x / (radii.x * radii.x), surface.y / (radii.y * radii.y)).normalized()
	surface += normal * (lerpf(0.0020, 0.0012, tension) + pad_thickness)
	return _sword_surface_inverse * Vector3(surface.x, point.y, surface.y)


func _digit_pad(digit: String) -> Vector3:
	if _pad_influences.has(digit):
		var point := Vector3.ZERO
		for influence: Dictionary in _pad_influences[digit]:
			var frame := skeleton.get_bone_global_pose(influence.bone)
			point += frame.basis * (influence.local as Vector3) + frame.origin * float(influence.weight)
		return point
	var bone := skeleton.find_bone(digit + "2")
	return skeleton.get_bone_global_pose(bone) * Vector3(0.0, float(DISTAL_LENGTH[digit]) * 0.82, -0.006)


func _digit_pad_normal(patch: String) -> Vector3:
	var normal := Vector3.ZERO
	for influence: Dictionary in _pad_influences.get(patch, []):
		normal += skeleton.get_bone_global_pose(influence.bone).basis * (influence.normal as Vector3)
	return normal.normalized() if normal.length_squared() > 0.000001 else Vector3.DOWN


func _prepare_skin_pads() -> void:
	# Select actual skin vertices around each distal pad once. Compress their
	# exact linear-blend skinning into one weighted point per influencing bone
	# so CCD follows the visible skin, including shared PIP/DIP weights.
	var part: MeshInstance3D
	for candidate in hand_meshes:
		if str(candidate.name).begins_with("ContinuousAnatomicalHand"):
			part = candidate
			break
	if part == null or part.skin == null: return
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := joints.size() / vertices.size()
	var bind_bones: Array[int] = []
	for bind in part.skin.get_bind_count():
		var bone := part.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(str(part.skin.get_bind_name(bind)))
		bind_bones.append(bone)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var patches: Array[Dictionary] = []
	for digit: String in DIGITS:
		var distal := skeleton.find_bone(digit + "2")
		patches.append({"key": digit, "bone": distal, "reference": skeleton.get_bone_global_rest(distal) * Vector3(0.0, float(DISTAL_LENGTH[digit]) * 0.82, -0.006), "palmar": false, "bone_name": digit + "2", "fraction": 0.82, "depth": -0.006})
		if digit == "thumb": continue
		var middle := skeleton.find_bone(digit + "1")
		var middle_length := skeleton.get_bone_rest(distal).origin.length()
		patches.append({"key": digit + "_middle", "bone": middle, "reference": skeleton.get_bone_global_rest(middle) * Vector3(0.0, middle_length * 0.55, -0.007), "palmar": false, "bone_name": digit + "1", "fraction": 0.55, "depth": -0.007})
		if digit == "middle":
			var proximal := skeleton.find_bone("middle0")
			var proximal_length := skeleton.get_bone_rest(middle).origin.length()
			patches.append({"key": "middle_proximal", "bone": proximal, "reference": skeleton.get_bone_global_rest(proximal) * Vector3(0.0, proximal_length * 0.85, -0.007), "palmar": false, "bone_name": "middle0", "fraction": 0.85, "depth": -0.007})
		var root := skeleton.get_bone_global_rest(skeleton.find_bone(digit + "0")).origin
		patches.append({"key": digit + "_palm", "bone": skeleton.find_bone("wrist"), "reference": Vector3(root.x, -0.016, root.z + 0.018), "palmar": true, "bone_name": "wrist", "fraction": 0.0, "depth": 0.0})
	for patch: Dictionary in patches:
		var candidates: Array[Dictionary] = []
		for vertex in vertices.size():
			if patch.palmar and normals[vertex].y > -0.3: continue
			var dominant_weight := 0.0
			for slot in stride:
				if bind_bones[joints[vertex * stride + slot]] == int(patch.bone): dominant_weight += weights[vertex * stride + slot]
			if dominant_weight > 0.55: candidates.append({"vertex": vertex, "distance": vertices[vertex].distance_squared_to(patch.reference)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
		var count := mini(20, candidates.size())
		if count == 0: continue
		var by_bone: Dictionary = {}
		for sample in count:
			var vertex := int(candidates[sample].vertex)
			for slot in stride:
				var weight := weights[vertex * stride + slot] / count
				if weight <= 0.0: continue
				var bind := joints[vertex * stride + slot]
				var bone := bind_bones[bind]
				if bone < 0: continue
				if not by_bone.has(bone): by_bone[bone] = {"bone": bone, "local": Vector3.ZERO, "normal": Vector3.ZERO, "weight": 0.0}
				by_bone[bone].local += (part.skin.get_bind_pose(bind) * vertices[vertex]) * weight
				by_bone[bone].normal += (part.skin.get_bind_pose(bind).basis * normals[vertex]) * weight
				by_bone[bone].weight += weight
		_pad_influences[patch.key] = by_bone.values()
		_pad_sample_counts[patch.key] = count
		_contact_patch_specs[patch.key] = {"bone": patch.bone_name, "reference": patch.reference, "fraction": patch.fraction, "depth": patch.depth, "palmar_normal_filter": patch.palmar}

	_prepare_glove_contact()


func _prepare_glove_contact() -> void:
	# Leather, not the skin under it, is the outer load-bearing surface of
	# the middle proximal phalanx. Select the actual weighted shell near its
	# open end, identically to the independent physical contact test.
	var proximal := skeleton.find_bone("middle0")
	var next_joint := skeleton.find_bone("middle1")
	var length := skeleton.get_bone_rest(next_joint).origin.length()
	var rest := skeleton.get_bone_global_rest(proximal)
	var inverse_rest := rest.affine_inverse()
	var reference := rest * Vector3(0.0, length * 0.80, -0.007)
	var samples: Array[Dictionary] = []
	for part: MeshInstance3D in hand_meshes:
		if not str(part.name).begins_with("ProximalFingerlessLeatherExtensions") or part.skin == null: continue
		var bound_bones: Array[int] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(str(part.skin.get_bind_name(bind)))
			bound_bones.append(bone)
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = joints.size() / vertices.size()
			for vertex in vertices.size():
				var local := inverse_rest * vertices[vertex]
				var fraction := local.y / length
				if fraction < 0.70 or fraction > 0.84 or (rest.basis.transposed() * normals[vertex]).z > -0.15: continue
				var dominant_weight := 0.0
				for slot in stride:
					if bound_bones[joints[vertex * stride + slot]] == proximal: dominant_weight += weights[vertex * stride + slot]
				if dominant_weight <= 0.55: continue
				var influences: Array[Dictionary] = []
				for slot in stride:
					var weight := weights[vertex * stride + slot]
					if weight <= 0.0: continue
					var bind := joints[vertex * stride + slot]
					influences.append({"bone": bound_bones[bind], "local": part.skin.get_bind_pose(bind) * vertices[vertex], "normal": part.skin.get_bind_pose(bind).basis * normals[vertex], "weight": weight})
				samples.append({"distance": vertices[vertex].distance_squared_to(reference), "influences": influences})
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var count := mini(20, samples.size())
	if count == 0: return
	var by_bone: Dictionary = {}
	for sample in count:
		for influence: Dictionary in samples[sample].influences:
			var bone: int = influence.bone
			var weight := float(influence.weight) / count
			if not by_bone.has(bone): by_bone[bone] = {"bone": bone, "local": Vector3.ZERO, "normal": Vector3.ZERO, "weight": 0.0}
			by_bone[bone].local += (influence.local as Vector3) * weight
			by_bone[bone].normal += (influence.normal as Vector3) * weight
			by_bone[bone].weight += weight
	_pad_influences["middle_glove"] = by_bone.values()
	_pad_sample_counts["middle_glove"] = count
	_contact_patch_specs["middle_glove"] = {"bone": "middle0", "reference": reference, "fraction": 0.80, "fraction_bounds": Vector2(0.70, 0.84), "depth": -0.007, "palmar_normal_filter": true, "source_mesh": "ProximalFingerlessLeatherExtensions"}


func _apply_digit_angles(digit: String, angles: Vector3, lateral: float, opposition := 0.0) -> void:
	for joint in 3:
		var rotation := Quaternion(Vector3.RIGHT, angles[joint])
		if joint == 0:
			# Thumb metacarpal pronation presents the soft pad to the grip. A
			# position-only finger hinge instead seats the side of the thumb.
			rotation = Quaternion(Vector3.BACK, lateral) * Quaternion(Vector3.UP, opposition) * rotation
		var bone := skeleton.find_bone(digit + str(joint))
		# Godot bone pose rotations are absolute parent-local transforms. They
		# are not rest-relative deltas: retain the imported MCP/IP orientation.
		# Skeleton3D.reset_bone_pose likewise copies rest.basis into pose.
		skeleton.set_bone_pose_rotation(bone, (_imported_rotations[bone] * rotation).normalized())


func _solve_shield_power_digit(digit: String, seed: Vector3, strength: float) -> void:
	var lower := Vector3(-1.65, -1.95, -1.35)
	var angles := seed
	var lateral := 0.0
	var contact := _shield_grip_contact(digit, skeleton.get_bone_global_pose(skeleton.find_bone(digit + "0")).origin.x, grip_amount)
	var closure := smoothstep(0.0, 0.75, strength)
	var is_little := digit == "little"
	var is_proximal := digit == "middle"
	var patch := digit if is_little else "middle_glove" if is_proximal else digit + "_middle"
	var palm_patch := digit + "_palm"
	var open_pad := _digit_pad(patch)
	var target: Vector3 = _digit_pad(palm_patch) + _digit_pad_normal(palm_patch) * 0.002 if is_little else contact.target
	target = _digit_pad(patch).lerp(target, closure)
	_apply_digit_angles(digit, angles, lateral)
	if strength > 0.0:
		for iteration in 35:
			for joint in ([2, 1, 0] if is_little else [0] if is_proximal else [1, 0]):
				if is_little: target = open_pad.lerp(_digit_pad(palm_patch) + _digit_pad_normal(palm_patch) * 0.002, closure)
				var frame := skeleton.get_bone_global_pose(skeleton.find_bone(digit + str(joint)))
				var delta := _hinge_correction(frame.origin, frame.basis.x.normalized(), _digit_pad(patch), target)
				angles[joint] = clampf(angles[joint] + clampf(delta, -0.22, 0.22), lower[joint], 0.0)
				_apply_digit_angles(digit, angles, lateral)
			var root_bone := skeleton.find_bone(digit + "0")
			var reference := skeleton.get_bone_global_pose(skeleton.get_bone_parent(root_bone)) * skeleton.get_bone_rest(root_bone)
			var delta := _hinge_correction(reference.origin, reference.basis.z.normalized(), _digit_pad(patch), target)
			lateral = clampf(lateral + clampf(delta, -0.10, 0.10), -0.22, 0.22)
			_apply_digit_angles(digit, angles, lateral)
			if not is_little:
				# A proximal contact leaves both distal hinges free; a middle
				# contact leaves only the terminal hinge free to close the fist.
				for joint in ([2, 1] if is_proximal else [2]):
					var frame := skeleton.get_bone_global_pose(skeleton.find_bone(digit + str(joint)))
					var palm := _digit_pad(palm_patch) + _digit_pad_normal(palm_patch) * 0.002
					delta = _hinge_correction(frame.origin, frame.basis.x.normalized(), _digit_pad(digit), palm)
					angles[joint] = clampf(angles[joint] + clampf(delta, -0.22, 0.22) * closure, lower[joint], 0.0)
					_apply_digit_angles(digit, angles, lateral)

	if strength >= 0.75 and not is_little:
		angles = _settle_shield_terminal(digit, angles, lateral)
	_digit_contacts[digit] = {"target": target, "angles": angles, "lateral": lateral, "opposition": 0.0, "lower_limits": lower, "upper_limits": Vector3.ZERO, "lateral_limit": 0.22, "patch": patch, "contact_kind": "palm_tuck" if is_little else "glove_strap" if is_proximal else "strap", "surface_kind": "padded_18gon", "surface": _digit_pad(digit + "_palm") if is_little else contact.surface, "inward": Vector3.UP if is_little else contact.inward, "uv": contact.uv}


func _settle_shield_terminal(digit: String, angles: Vector3, lateral: float) -> Vector3:
	var palm_patch := digit + "_palm"
	# Choose the nearest reachable terminal pose that stays on the outside
	# of the real deformed palmar skin. A global -Y offset is incorrect when
	# shared MCP weights fold the palm's contact normal during a power grip.
	var best_score := INF
	var best_angle := angles.z
	for sample in 55:
		var candidate := lerpf(-1.35, 0.0 if digit == "middle" else -0.40, float(sample) / 54.0)
		_apply_digit_angles(digit, Vector3(angles.x, angles.y, candidate), lateral)
		var offset := _digit_pad(digit) - _digit_pad(palm_patch)
		var signed_gap := offset.dot(_digit_pad_normal(palm_patch))
		var score := offset.length_squared() + pow(maxf(0.0, 0.0015 - signed_gap), 2.0) * 100.0
		if score < best_score:
			best_score = score
			best_angle = candidate
	angles.z = best_angle
	_apply_digit_angles(digit, angles, lateral)
	return angles


func _solve_digit_contact(digit: String, target: Vector3, seed: Vector3, strength: float) -> void:
	var is_thumb := digit == "thumb"
	var lower := Vector3(-0.85, -1.45, -1.45) if is_thumb else Vector3(-1.65, -1.95, -1.35)
	var upper := Vector3(0.65, 0.35, 0.10) if is_thumb else Vector3.ZERO
	var lateral_limit := 1.05 if is_thumb else 0.22
	var opposition := 0.0
	if is_thumb:
		opposition = float(_geometry_side) * (-0.75 if _grip_role == "sword" else 0.75) * smoothstep(0.0, 0.75, strength)
	var angles := seed
	var lateral := 0.0
	_apply_digit_angles(digit, angles, lateral, opposition)
	if strength > 0.0:
		for iteration in 20:
			for joint in [2, 1, 0]:
				var bone := skeleton.find_bone(digit + str(joint))
				var frame := skeleton.get_bone_global_pose(bone)
				var delta := _hinge_correction(frame.origin, frame.basis.x.normalized(), _digit_pad(digit), target)
				angles[joint] = clampf(angles[joint] + clampf(delta, -0.22, 0.22), lower[joint], upper[joint])
				_apply_digit_angles(digit, angles, lateral, opposition)
			# Small MCP adduction is solved from each contact's lateral error.
			# No arbitrary finger fan is introduced by the grip strength.
			var root_bone := skeleton.find_bone(digit + "0")
			var parent := skeleton.get_bone_parent(root_bone)
			var reference := skeleton.get_bone_global_pose(parent) * skeleton.get_bone_rest(root_bone)
			var delta := _hinge_correction(reference.origin, reference.basis.z.normalized(), _digit_pad(digit), target)
			lateral = clampf(lateral + clampf(delta, -0.10, 0.10), -lateral_limit, lateral_limit)
			_apply_digit_angles(digit, angles, lateral, opposition)
	_digit_contacts[digit] = {"target": target, "angles": angles, "lateral": lateral, "opposition": opposition, "lower_limits": lower, "upper_limits": upper, "lateral_limit": lateral_limit}


func _hinge_correction(origin: Vector3, axis: Vector3, point: Vector3, target: Vector3) -> float:
	var from := point - origin
	var to := target - origin
	from -= axis * from.dot(axis)
	to -= axis * to.dot(axis)
	if from.length_squared() < 0.00000001 or to.length_squared() < 0.00000001: return 0.0
	return atan2(axis.dot(from.cross(to)), from.dot(to))


func get_combat_grip_snapshot() -> Dictionary:
	var contacts := _digit_contacts.duplicate(true)
	for digit: String in contacts:
		contacts[digit].actual = _digit_pad(str(contacts[digit].get("patch", digit)))
		contacts[digit].distal_actual = _digit_pad(digit)
		if digit != "thumb": contacts[digit].palm_actual = _digit_pad(digit + "_palm")
		if digit == "middle": contacts[digit].proximal_actual = _digit_pad("middle_proximal")
		contacts[digit].error = (contacts[digit].actual as Vector3).distance_to(contacts[digit].target)
	return {"role": _grip_role, "tension": grip_amount, "center": GRIP_CENTER, "contacts": contacts, "skin_sample_counts": _pad_sample_counts.duplicate(), "solve_count": _grip_solve_count, "bone_count": skeleton.get_bone_count() if skeleton != null else 0, "geometry_side": _geometry_side, "surface_key": _last_grip_surface_key, "sword_surface_valid": _sword_surface_valid, "weapon_from_hand": _sword_surface, "shield_surface_valid": _shield_surface_valid, "shield_from_hand": _shield_surface, "contact_patch_specs": _contact_patch_specs.duplicate(true), "cache_size": _grip_cache.size()}


func fit_arm(shoulder_world: Vector3, elbow_world: Vector3) -> void:
	if _forearm == null or _upper_arm == null: return
	var inverse := LEGACY_FIT._accumulated_transform(self).affine_inverse()
	var shoulder := inverse * shoulder_world
	var elbow := inverse * elbow_world
	_forearm.transform = LEGACY_FIT._fit_segment(Vector3(0, 0, 0.26), Vector3.ZERO, elbow, Vector3.ZERO)
	_upper_arm.transform = LEGACY_FIT._fit_segment(Vector3(0, 0, 0.60), Vector3(0, 0, 0.26), shoulder, elbow)
	# The soft open cuff follows the sleeve at the wrist, rather than sticking
	# out along the fist's forward axis when the sword rolls in a countercut.
	if _cuff != null: _cuff.transform = Transform3D(_forearm.transform.basis.orthonormalized(), Vector3.ZERO)


func set_arm_visible(enabled: bool) -> void:
	for mesh in arm_meshes: mesh.visible = enabled


func get_source_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for part in arm_meshes + hand_meshes: result.append(part.mesh)
	return result
