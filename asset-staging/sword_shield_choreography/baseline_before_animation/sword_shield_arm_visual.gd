extends Node3D
## A continuous anatomical hand with fifteen deforming finger joints. Wrist
## space is shared by the production equipment contacts: fingers -Z, back +Y.
const LEGACY_FIT := preload("res://scripts/player_arm_visual.gd")
const LEFT := preload("res://assets/3d/player/sword_shield/left_arm.glb")
const RIGHT := preload("res://assets/3d/player/sword_shield/right_arm.glb")
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
var arm_meshes: Array[MeshInstance3D] = []
var hand_meshes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var _forearm: Node3D
var _upper_arm: Node3D
var _cuff: Node3D
var _side := 1
var grip_amount := 0.0
var _last_thumb_amount := -2.0
static var _materials: Dictionary = {}


func setup(side: int) -> void:
	_side = -1 if side < 0 else 1
	var model := (LEFT if _side < 0 else RIGHT).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_forearm = model.find_child("Forearm*", true, false) as Node3D
	_upper_arm = model.find_child("UpperArm*", true, false) as Node3D
	_cuff = model.find_child("WristCuff*", true, false) as Node3D
	_prepare(model)
	set_meta("source_model", LEFT.resource_path if _side < 0 else RIGHT.resource_path)
	set_meta("anatomical_side", _side)
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
			"FP_WornLeather", "FP_LayeredVambrace", "FP_EnarmesLeather":
				material.albedo_color = Color(0.43, 0.43, 0.43)
				if source.resource_name == "FP_LayeredVambrace": material.albedo_color = Color(0.50, 0.46, 0.40)
				if source.resource_name == "FP_EnarmesLeather": material.albedo_color = Color(0.36, 0.26, 0.17)
				material.albedo_texture = load("res://assets/ai/sword_shield/worn_charcoal_leather.png")
				material.roughness = 0.68 if source.resource_name == "FP_EnarmesLeather" else 0.54
				material.normal_enabled = true
				material.normal_texture = load("res://assets/3d/player/sword_shield/textures/leather_normal.jpg")
				material.normal_scale = 0.15
				material.uv1_scale = Vector3(0.5,0.5,0.5)
			"FP_LeatherEdge": material.albedo_color = Color(0.17,0.14,0.11)
			"FP_WaxedThread": material.albedo_color = Color(0.23,0.20,0.17)
			"FP_QuiltedLinen":
				material.albedo_color = Color(0.36, 0.34, 0.30)
				material.albedo_texture = load("res://assets/ai/sword_shield/worn_charcoal_leather.png")
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
	if is_equal_approx(grip_amount, clampf(amount, 0, 1)) and is_equal_approx(_last_thumb_amount, thumb_amount): return
	grip_amount = clampf(amount, 0, 1)
	_last_thumb_amount = thumb_amount
	if skeleton == null: return
	for digit in DIGITS:
		var strength := grip_amount if digit != "thumb" or thumb_amount < 0 else clampf(thumb_amount, 0, 1)
		for joint in 3:
			var index := skeleton.find_bone(digit + str(joint))
			if index < 0: continue
			# Blender's finger bones have local +Y along the digit and +Z on
			# the hand back; local -X curls the real skin toward its palm.
			var curl := [-1.17, -1.40, -0.88][joint] as float
			if digit == "thumb": curl = [-0.32, -0.70, -0.65][joint]
			var rotation := Quaternion(Vector3.RIGHT, curl * strength)
			if joint == 0:
				var spread := {"little": 0.27, "ring": 0.06, "middle": 0.0, "index": -0.06, "thumb": -0.50}
				rotation = Quaternion(Vector3.FORWARD, float(spread[digit]) * _side * strength) * rotation
			skeleton.set_bone_pose_rotation(index, rotation)

	_oppose_thumb(grip_amount)


func _oppose_thumb(amount: float) -> void:
	if amount < 0.5: return
	var end_bone := skeleton.find_bone("thumb2")
	var target := Vector3(_side * 0.050, -0.04625, -0.065)
	for iteration in 5:
		for joint in [2, 1, 0]:
			var bone := skeleton.find_bone("thumb" + str(joint))
			var frame := skeleton.get_bone_global_pose(bone)
			var tip := skeleton.get_bone_global_pose(end_bone) * Vector3(0, 0.03125, 0)
			var delta := Quaternion((tip - frame.origin).normalized(), (target - frame.origin).normalized())
			var parent := skeleton.get_bone_parent(bone)
			var parent_frame := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var reference := parent_frame * skeleton.get_bone_rest(bone).basis
			var local := reference.inverse() * Basis(delta) * reference
			skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion() * skeleton.get_bone_pose_rotation(bone))


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
