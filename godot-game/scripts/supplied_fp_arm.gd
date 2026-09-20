extends Node3D
## User supplied FP arms. Original geometry, UVs and joint weights; gameplay
## wrist/equipment transforms are owned by the caller, never by this adapter.
const SOURCE_DIR := "res://assets/3d/player/fp_arms/"
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const GRIP_CENTER := Vector3(0, -.019, -.0825)
## Radial build only: keep limb lengths and the fixed hand/equipment anchors.
const FOREARM_BUILD := 2.0
const UPPER_ARM_BUILD := 1.70
const HAND_BUILD := 1.30
var skeleton: Skeleton3D
var arm_meshes: Array[MeshInstance3D] = []
var hand_meshes: Array[MeshInstance3D] = []
var long_grip_surface := false
var grip_amount := 0.0
var _side := 1
var _data: Dictionary
var _rest: Array[Transform3D] = []
var _angles: Dictionary = {}
var _axes: Dictionary = {}
var _role := "relaxed"
var _source := ""
var _forearm_fit := Transform3D.IDENTITY

func setup(side: int, _profile := "original", _torch_source := false) -> bool:
	_side = -1 if side < 0 else 1
	_source = SOURCE_DIR + ("left.scn" if _side < 0 else "right.scn")
	var packed := load(_source) as PackedScene
	if packed == null: return false
	var model := packed.instantiate()
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null: return false
	_data = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_DIR + "rig.json")).sides["L" if _side < 0 else "R"]
	for i in skeleton.get_bone_count(): _rest.append(skeleton.get_bone_global_rest(i))
	for key: String in _data.hinges:
		var i := skeleton.find_bone(key)
		_axes[key] = (_rest[i].basis.inverse() * _vec(_data.hinges[key])).normalized()
	_collect(model)
	set_meta("source_model", _source)
	set_meta("anatomical_side", _side)
	set_meta("continuous_skin", true)
	set_meta("supplied_fp_arms", true)
	_apply_hand_build()
	set_relaxed_pose()
	return true

static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _collect(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if "_Arm" in str(node.name): arm_meshes.append(node)
		else: hand_meshes.append(node)
		# Disable skinned mesh rest-bound culling while the fixed gameplay rig moves.
		node.custom_aabb = AABB(Vector3(-2,-2,-2),Vector3(4,4,4))
	for child in node.get_children(): _collect(child)

func _apply(digit: String, angles: Vector3) -> void:
	_angles[digit] = angles
	for joint in 3:
		var key := digit + str(joint)
		var i := skeleton.find_bone(key)
		var rest_rotation := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(i, (rest_rotation * Quaternion(_axes[key], angles[joint])).normalized())

func set_grip(amount: float, thumb_amount: float = -1.0) -> void:
	if not is_finite(amount): return
	grip_amount = clampf(amount, 0, 1)
	for digit: String in DIGITS.slice(0,4):
		var weight := 1.0 if digit != "index" else .92
		_apply(digit, Vector3(-.48,-.82,-.48).lerp(Vector3(.48,.42,.32), grip_amount * weight))
	var thumb := grip_amount if thumb_amount < 0 else clampf(thumb_amount,0,1)
	_apply("thumb",Vector3(-.12,-.25,-.22).lerp(Vector3(.30,.35,.48),thumb))

func set_combat_grip(role: String, tension: float) -> void:
	_role = role
	set_grip(tension)

func set_sword_grip_surface(_weapon_from_hand: Transform3D) -> void: pass
func set_shield_grip_surface(_shield_from_hand: Transform3D) -> void: pass

func set_torch_grip() -> void:
	_role = "torch"
	set_grip(.85)

func set_string_draw(grip_ratio: float, release_ratio := 0.0) -> void:
	set_grip(.0)
	for digit: String in ["index","middle","ring"]:
		_apply(digit, Vector3(-.20,.40,.25).lerp(Vector3(-.48,-.82,-.48), clampf(release_ratio,0,1)))
	set_meta("string_hook_amount", grip_ratio * (1.0-release_ratio))

func set_relaxed_pose(openness := 0.0) -> void:
	_role = "relaxed"
	set_grip(lerpf(.16,0.0,clampf(openness,0,1)))

func reset_pose() -> void:
	skeleton.reset_bone_poses()
	_apply_hand_build()
	set_relaxed_pose(1.0)

func _hand_build_transform() -> Transform3D:
	# Enlarge the complete finger hierarchy around the existing palm contact.
	# The wrist shifts towards the elbow; the sleeve follows that same endpoint.
	return Transform3D(Basis.from_scale(Vector3.ONE * HAND_BUILD), GRIP_CENTER * (1.0 - HAND_BUILD))

func _apply_hand_build() -> void:
	var wrist := skeleton.find_bone("wrist")
	skeleton.set_bone_pose(wrist, _hand_build_transform() * _rest[wrist])
func set_finger_curl(index: int, proximal: float, distal: float) -> void:
	if index < 0 or index > 4: return
	_apply(DIGITS[index], Vector3(-.48-proximal,-.82-distal*.58,-.48-distal*.42))

func set_joint_flexion(digit: String, joint: int, amount: float) -> bool:
	if not DIGITS.has(digit) or joint < 0 or joint > 2 or not is_finite(amount): return false
	var angles: Vector3 = _angles.get(digit,Vector3.ZERO)
	var lo := Vector3(-.12,-.25,-.22) if digit == "thumb" else Vector3(-.48,-.82,-.48)
	var hi := Vector3(.30,.35,.48) if digit == "thumb" else Vector3(.48,.42,.32)
	angles[joint] = lerpf(lo[joint],hi[joint],clampf(amount,0,1))
	_apply(digit,angles)
	return true

func set_digit_flexion(digit: String, amounts: Vector3) -> bool:
	if not DIGITS.has(digit) or not amounts.is_finite(): return false
	for joint in 3: set_joint_flexion(digit,joint,amounts[joint])
	return true

func set_digit_contact_pose(digit: String, angles: Vector3, lateral_axis: Vector3, lateral_angle: float) -> bool:
	# A diagonal handle needs individual MCP spread as well as flexion. Keep
	# the original bone lengths, bind transforms and all skin weights intact.
	if not DIGITS.has(digit) or not angles.is_finite() or not lateral_axis.is_finite() or not is_finite(lateral_angle): return false
	_apply(digit, angles)
	if lateral_axis.length_squared() > .000001:
		var key := digit + "0"
		var i := skeleton.find_bone(key)
		var rest_rotation := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(i, (rest_rotation * Quaternion(lateral_axis.normalized(), lateral_angle) * Quaternion(_axes[key], angles.x)).normalized())
	return true

func fit_arm(shoulder_world: Vector3, elbow_world: Vector3) -> void:
	if skeleton == null: return
	var shoulder := to_local(shoulder_world)
	var elbow := to_local(elbow_world)
	var wrist := _hand_build_transform() * _vec(_data.points.wrist)
	var fore := _fit_segment(_vec(_data.points.elbow),Vector3.ZERO,elbow,wrist,FOREARM_BUILD)
	_forearm_fit=fore
	var upper := _fit_segment(_vec(_data.points.shoulder),_vec(_data.points.elbow),shoulder,elbow,UPPER_ARM_BUILD)
	for key: String in ["upper","elbow","forearm"]:
		var i := skeleton.find_bone(key)
		# These three independent deform roots retain original weight blending
		# across the elbow and wrist while the hand remains on its grip anchor.
		skeleton.set_bone_pose(i, (upper if key == "upper" else fore) * _rest[i])

static func _fit_segment(a: Vector3, b: Vector3, c: Vector3, d: Vector3, radial_build := 1.0) -> Transform3D:
	var old := b-a; var new := d-c
	if old.length() < .00001 or new.length() < .00001: return Transform3D.IDENTITY
	var axis := old.normalized()
	var ratio := new.length()/old.length()-radial_build
	var stretch := Basis(Vector3.RIGHT*radial_build+axis*axis.x*ratio,Vector3.UP*radial_build+axis*axis.y*ratio,Vector3.BACK*radial_build+axis*axis.z*ratio)
	var basis := Basis(Quaternion(axis,new.normalized())) * stretch
	return Transform3D(basis,c-basis*a)

func set_arm_visible(value: bool) -> void:
	for mesh in arm_meshes: mesh.visible=value
func set_render_layers(value: int) -> void:
	for mesh in arm_meshes+hand_meshes: mesh.layers=value
func get_source_meshes() -> Array[Mesh]:
	var meshes: Array[Mesh]=[]
	for part in arm_meshes+hand_meshes: meshes.append(part.mesh)
	return meshes
func get_joint_snapshot() -> Dictionary:
	return {"ready":is_instance_valid(skeleton),"corrective_available":false,"independent_joint_controls":true,"angles_radians":_angles.duplicate(true),"morph_count":0,"source_model":_source}
func get_wrist_snapshot() -> Dictionary:
	return {"enabled":true,"continuous_skin":true,"source_model":_source}
func get_combat_grip_snapshot() -> Dictionary:
	return {"role":_role,"tension":grip_amount,"bone_count":skeleton.get_bone_count(),"source_model":_source}
func get_snapshot() -> Dictionary:
	return {"source_model":_source,"skeleton_bone_count":skeleton.get_bone_count(),"hand_mesh_count":hand_meshes.size(),"arm_mesh_count":arm_meshes.size(),"continuous_skin":true,"anatomical_side":_side}

func get_forearm_frame() -> Transform3D:
	return global_transform * _forearm_fit
func get_upper_length() -> float:
	var a:=skeleton.get_bone_global_pose(skeleton.find_bone("upper")).origin
	var b:=skeleton.get_bone_global_pose(skeleton.find_bone("elbow")).origin
	return skeleton.to_global(a).distance_to(skeleton.to_global(b))
