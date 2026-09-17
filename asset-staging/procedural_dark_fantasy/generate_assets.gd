extends SceneTree

# Standalone, deterministic GLB generator for Godot 4.7.
# Run from this folder with:
#   /path/to/Godot --headless --path . --script generate_assets.gd

const OUTPUT_DIR := "res://out"
const EPSILON_DEPTH := 0.012

var mats: Dictionary = {}
var stone_variants: Array[StandardMaterial3D] = []
var wood_variants: Array[StandardMaterial3D] = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	rng.seed = 0x5A17D4
	_init_materials()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var assets: Array[Dictionary] = [
		{"name": "sanctuary_warden_3d", "root": _build_sanctuary_warden()},
		{"name": "ossuary_keeper_3d", "root": _build_ossuary_keeper()},
		{"name": "rusted_longsword", "root": _build_sword()},
		{"name": "weathered_round_shield", "root": _build_shield()},
		{"name": "iron_cage_torch", "root": _build_torch()},
		{"name": "reliquary_chest", "root": _build_chest()},
		{"name": "blood_rune_trap", "root": _build_rune_trap()},
		{"name": "sanctum_portal_arch", "root": _build_portal_arch()},
		{"name": "dungeon_floor_4m", "root": _build_floor_module()},
		{"name": "dungeon_wall_4m", "root": _build_wall_module()},
		{"name": "dungeon_archway_4m", "root": _build_archway_module()},
		{"name": "dungeon_pillar_3m", "root": _build_pillar_module()},
		{"name": "dungeon_stairs_4m", "root": _build_stairs_module()},
	]

	var failed: Array[String] = []
	for item in assets:
		var asset_name: String = item.name
		var root: Node3D = item.root
		var error := _export_glb(root, "%s/%s.glb" % [OUTPUT_DIR, asset_name])
		if error != OK:
			failed.append("%s (%s)" % [asset_name, error_string(error)])
		root.free()

	if failed.is_empty():
		print("Generated %d dark-fantasy GLB assets in %s" % [assets.size(), ProjectSettings.globalize_path(OUTPUT_DIR)])
		quit(0)
	else:
		push_error("GLB generation failures: %s" % ", ".join(failed))
		quit(1)


func _init_materials() -> void:
	mats.steel = _material(Color("#4c5150"), 0.82, 0.32)
	mats.dark_steel = _material(Color("#171918"), 0.88, 0.54)
	mats.rust = _material(Color("#652815"), 0.48, 0.91)
	mats.rust_bright = _material(Color("#96381b"), 0.36, 0.88)
	mats.leather = _material(Color("#291209"), 0.04, 0.93)
	mats.leather_light = _material(Color("#4a2412"), 0.03, 0.88)
	mats.wood = _material(Color("#32170c"), 0.02, 0.96)
	mats.wood_dark = _material(Color("#170b07"), 0.01, 0.99)
	mats.stone = _material(Color("#343431"), 0.0, 0.97)
	mats.stone_dark = _material(Color("#171918"), 0.0, 0.99)
	mats.mortar = _material(Color("#101211"), 0.0, 1.0)
	mats.ash = _material(Color("#080807"), 0.0, 1.0)
	mats.bone = _material(Color("#8e846b"), 0.0, 0.84)
	mats.rune = _material(Color("#9d0a07"), 0.1, 0.42, Color("#ff1808"), 0.55)
	mats.portal = _material(Color(0.008, 0.055, 0.052, 0.74), 0.18, 0.22, Color("#0ca58f"), 0.65, true)
	mats.portal_hot = _material(Color(0.025, 0.28, 0.23, 0.82), 0.2, 0.25, Color("#25d8bc"), 1.0, true)
	mats.flame_outer = _material(Color(1.0, 0.12, 0.012, 0.86), 0.0, 0.3, Color("#ff2608"), 1.3, true)
	mats.flame_inner = _material(Color(1.0, 0.64, 0.08, 0.92), 0.0, 0.22, Color("#ff8c14"), 1.8, true)
	mats.coal = _material(Color("#170403"), 0.0, 1.0, Color("#b51b05"), 0.7)
	mats.black_iron = _material(Color("#111516"), 0.86, 0.50)
	mats.iron_edge = _material(Color("#343a3a"), 0.91, 0.31)
	mats.black_cloth = _material(Color("#090b0c"), 0.0, 0.98)
	mats.cloth_faded = _material(Color("#242321"), 0.0, 0.99)
	mats.cloth_rotten = _material(Color("#3a3126"), 0.0, 1.0)
	mats.bone_dirty = _material(Color("#766d57"), 0.0, 0.89)
	mats.bone_shadow = _material(Color("#302d27"), 0.0, 0.96)
	mats.sinew = _material(Color("#3b130f"), 0.0, 0.91)
	mats.dried_blood = _material(Color("#350705"), 0.05, 0.80)
	mats.eye_teal = _material(Color("#061b19"), 0.05, 0.32, Color("#18d8c2"), 2.4)
	mats.invisible = _material(Color(0, 0, 0, 0), 0.0, 1.0, Color.BLACK, 0.0, true)

	for color in ["#292a28", "#30312e", "#383733", "#242625", "#3d3933"]:
		stone_variants.append(_material(Color(color), 0.0, 0.94 + rng.randf_range(0.0, 0.05)))
	for color in ["#291208", "#35170a", "#401d0c", "#251008"]:
		wood_variants.append(_material(Color(color), 0.02, 0.92 + rng.randf_range(0.0, 0.06)))


func _material(
	color: Color,
	metallic: float,
	roughness: float,
	emission := Color.BLACK,
	emission_energy := 0.0,
	transparent := false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _new_root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	return root


func _add_mesh(
	root: Node3D,
	node_name: String,
	mesh: Mesh,
	material: Material,
	position := Vector3.ZERO,
	rotation_degrees := Vector3.ZERO,
	scale := Vector3.ONE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.scale = scale
	root.add_child(instance)
	instance.owner = root
	return instance


func _add_marker(root: Node3D, marker_name: String, position: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = marker_name
	marker.position = position
	root.add_child(marker)
	marker.owner = root
	return marker


func _add_owned_pivot(parent: Node3D, scene_root: Node3D, pivot_name: String, position := Vector3.ZERO, rotation_degrees := Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = position
	pivot.rotation_degrees = rotation_degrees
	parent.add_child(pivot)
	pivot.owner = scene_root
	return pivot


func _add_owned_mesh(
	parent: Node3D,
	scene_root: Node3D,
	node_name: String,
	mesh: Mesh,
	material: Material,
	position := Vector3.ZERO,
	rotation_degrees := Vector3.ZERO,
	scale := Vector3.ONE
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.scale = scale
	parent.add_child(instance)
	instance.owner = scene_root
	return instance


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(radius_top: float, radius_bottom: float, height: float, segments := 12) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_top
	mesh.bottom_radius = radius_bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


func _sphere(radius := 0.5, height := 1.0, segments := 16, rings := 8) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _torus(inner_radius: float, outer_radius: float, segments := 32, rings := 8) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = segments
	mesh.ring_segments = rings
	return mesh


func _extruded_polygon_xy(points: PackedVector2Array, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_depth := depth * 0.5
	var count := points.size()

	for index in range(1, count - 1):
		_add_triangle(surface,
			Vector3(points[0].x, points[0].y, half_depth),
			Vector3(points[index].x, points[index].y, half_depth),
			Vector3(points[index + 1].x, points[index + 1].y, half_depth))
		_add_triangle(surface,
			Vector3(points[0].x, points[0].y, -half_depth),
			Vector3(points[index + 1].x, points[index + 1].y, -half_depth),
			Vector3(points[index].x, points[index].y, -half_depth))

	for index in range(count):
		var next := (index + 1) % count
		var a := Vector3(points[index].x, points[index].y, -half_depth)
		var b := Vector3(points[next].x, points[next].y, -half_depth)
		var c := Vector3(points[next].x, points[next].y, half_depth)
		var d := Vector3(points[index].x, points[index].y, half_depth)
		_add_triangle(surface, a, b, c)
		_add_triangle(surface, a, c, d)

	surface.generate_normals()
	return surface.commit()


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_uv(Vector2(0, 0))
	surface.add_vertex(a)
	surface.set_uv(Vector2(1, 0))
	surface.add_vertex(b)
	surface.set_uv(Vector2(0.5, 1))
	surface.add_vertex(c)


func _add_stroke_xz(
	root: Node3D,
	stroke_name: String,
	center: Vector2,
	length: float,
	angle: float,
	width: float,
	material: Material,
	height: float
) -> void:
	_add_mesh(
		root,
		stroke_name,
		_box(Vector3(length, EPSILON_DEPTH, width)),
		material,
		Vector3(center.x, height, center.y),
		Vector3(0, -rad_to_deg(angle), 0)
	)


func _add_collision_box(root: Node3D, node_name: String, size: Vector3, position: Vector3) -> void:
	_add_mesh(root, "%s-colonly" % node_name, _box(size), mats.invisible, position)


func _export_glb(root: Node3D, resource_path: String) -> Error:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(root, state)
	if append_error != OK:
		return append_error
	return document.write_to_filesystem(state, ProjectSettings.globalize_path(resource_path))


func _build_sanctuary_warden() -> Node3D:
	var root := _new_root("SanctuaryWarden3D")
	var visual := _add_owned_pivot(root, root, "VisualRoot")
	var torso := _add_owned_pivot(visual, root, "TorsoPivot", Vector3(0, 1.32, 0))
	var head := _add_owned_pivot(torso, root, "HeadPivot", Vector3(0, 0.49, -0.025), Vector3(-4, 0, 0))
	var arm_l := _add_owned_pivot(torso, root, "ArmLPivot", Vector3(-0.40, 0.30, 0), Vector3(1, 0, 7))
	var arm_r := _add_owned_pivot(torso, root, "ArmRPivot", Vector3(0.40, 0.30, 0), Vector3(-2, 0, -6))
	var leg_l := _add_owned_pivot(visual, root, "LegLPivot", Vector3(-0.175, 0.95, 0), Vector3(0, 0, 2))
	var leg_r := _add_owned_pivot(visual, root, "LegRPivot", Vector3(0.175, 0.95, 0), Vector3(0, 0, -2))

	# Layered torso: an under-tunic remains visible between articulated iron plates.
	_add_owned_mesh(torso, root, "ClothTorsoUndercoat", _cylinder(0.27, 0.32, 0.72, 12), mats.black_cloth, Vector3(0, -0.06, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.73))
	_add_owned_mesh(torso, root, "ArmorBreastplate", _sphere(0.5, 1.0, 20, 10), mats.black_iron, Vector3(0, 0.065, -0.035), Vector3.ZERO, Vector3(0.64, 0.70, 0.43))
	_add_owned_mesh(torso, root, "ArmorBackplate", _sphere(0.5, 1.0, 18, 8), mats.dark_steel, Vector3(0, 0.055, 0.15), Vector3.ZERO, Vector3(0.57, 0.65, 0.30))
	_add_owned_mesh(torso, root, "ArmorBreastRidge", _box(Vector3(0.058, 0.50, 0.055)), mats.iron_edge, Vector3(0, 0.08, -0.245))
	for side in [-1, 1]:
		_add_owned_mesh(torso, root, "ArmorChestFlange%d" % side, _box(Vector3(0.17, 0.045, 0.055)), mats.iron_edge, Vector3(float(side) * 0.17, 0.17, -0.25), Vector3(0, 0, float(side) * 19))
		_add_owned_mesh(torso, root, "ArmorLowerRib%d" % side, _box(Vector3(0.18, 0.038, 0.045)), mats.rust, Vector3(float(side) * 0.14, -0.08, -0.24), Vector3(0, 0, float(side) * 9))

	_add_owned_mesh(torso, root, "ArmorGorget", _torus(0.175, 0.235, 24, 7), mats.black_iron, Vector3(0, 0.385, 0), Vector3.ZERO, Vector3(1.0, 0.75, 0.86))
	_add_owned_mesh(torso, root, "ArmorWaistPlate", _cylinder(0.275, 0.235, 0.18, 12), mats.dark_steel, Vector3(0, -0.36, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.78))
	_add_owned_mesh(torso, root, "ClothLeatherBelt", _torus(0.225, 0.275, 20, 6), mats.leather, Vector3(0, -0.405, 0), Vector3.ZERO, Vector3(1.0, 0.82, 0.78))
	_add_owned_mesh(torso, root, "ArmorBeltBuckle", _box(Vector3(0.12, 0.12, 0.038)), mats.rust_bright, Vector3(0, -0.405, -0.245), Vector3(0, 0, 45))

	# Segmented faulds overlap like real plate armor while leaving the leg pivots free.
	for row in range(3):
		var y := -0.48 - row * 0.11
		var radius := 0.31 - row * 0.025
		_add_owned_mesh(torso, root, "ArmorFauldFront%02d" % row, _box(Vector3(radius * 1.55, 0.12, 0.075)), mats.black_iron, Vector3(0, y, -0.16), Vector3(-4 - row * 3, 0, 0))
		_add_owned_mesh(torso, root, "ArmorFauldBack%02d" % row, _box(Vector3(radius * 1.55, 0.12, 0.065)), mats.dark_steel, Vector3(0, y, 0.15), Vector3(4 + row * 2, 0, 0))
	for side in [-1, 1]:
		_add_owned_mesh(torso, root, "ArmorTasset%d" % side, _box(Vector3(0.18, 0.34, 0.075)), mats.black_iron, Vector3(float(side) * 0.225, -0.62, -0.07), Vector3(-4, 0, float(side) * 5))

	var cloak_points := PackedVector2Array([
		Vector2(-0.30, 0.34), Vector2(0.30, 0.34), Vector2(0.28, -0.38),
		Vector2(0.16, -0.68), Vector2(0.04, -0.57), Vector2(-0.08, -0.73),
		Vector2(-0.20, -0.60), Vector2(-0.30, -0.34)
	])
	_add_owned_mesh(torso, root, "ClothTornCloak", _extruded_polygon_xy(cloak_points, 0.035), mats.black_cloth, Vector3(0, -0.03, 0.265), Vector3(2, 0, 0))
	_add_owned_mesh(torso, root, "ClothCloakClaspL", _sphere(0.5, 1.0, 10, 5), mats.rust, Vector3(-0.22, 0.32, 0.19), Vector3.ZERO, Vector3(0.065, 0.065, 0.035))
	_add_owned_mesh(torso, root, "ClothCloakClaspR", _sphere(0.5, 1.0, 10, 5), mats.rust, Vector3(0.22, 0.32, 0.19), Vector3.ZERO, Vector3(0.065, 0.065, 0.035))

	_build_warden_head(head, root)
	_build_warden_arm(arm_l, root, -1)
	_build_warden_arm(arm_r, root, 1)
	_build_warden_leg(leg_l, root, -1)
	_build_warden_leg(leg_r, root, 1)

	var weapon := _add_owned_pivot(arm_r, root, "WeaponPivot", Vector3(0.01, -0.70, -0.015), Vector3(2, 0, -8))
	_build_warden_sword(weapon, root)
	return root


func _build_warden_head(head: Node3D, root: Node3D) -> void:
	# The hood is a complete three-dimensional shell; the skull sits slightly proud of it.
	_add_owned_mesh(head, root, "ClothHoodShell", _sphere(0.5, 1.0, 18, 9), mats.black_cloth, Vector3(0, 0.02, 0.025), Vector3.ZERO, Vector3(0.47, 0.55, 0.43))
	_add_owned_mesh(head, root, "ClothHoodCowl", _torus(0.18, 0.29, 24, 7), mats.cloth_faded, Vector3(0, -0.18, 0.02), Vector3.ZERO, Vector3(1.1, 0.76, 0.90))
	_add_owned_mesh(head, root, "BoneSkull", _sphere(0.5, 1.0, 18, 9), mats.bone_dirty, Vector3(0, 0.01, -0.205), Vector3.ZERO, Vector3(0.28, 0.35, 0.20))
	_add_owned_mesh(head, root, "BoneBrow", _box(Vector3(0.23, 0.055, 0.045)), mats.bone_shadow, Vector3(0, 0.075, -0.315), Vector3(5, 0, 0))
	for side in [-1, 1]:
		_add_owned_mesh(head, root, "BoneCheek%d" % side, _box(Vector3(0.065, 0.12, 0.055)), mats.bone_dirty, Vector3(float(side) * 0.085, -0.055, -0.305), Vector3(0, float(side) * 11, float(side) * -12))
		_add_owned_mesh(head, root, "EyeSocket%d" % side, _sphere(0.5, 1.0, 12, 6), mats.bone_shadow, Vector3(float(side) * 0.058, 0.043, -0.316), Vector3.ZERO, Vector3(0.070, 0.060, 0.032))
		_add_owned_mesh(head, root, "EyeGlow%d" % side, _sphere(0.5, 1.0, 10, 5), mats.eye_teal, Vector3(float(side) * 0.058, 0.042, -0.342), Vector3.ZERO, Vector3(0.025, 0.023, 0.014))
	_add_owned_mesh(head, root, "BoneNasalCavity", _box(Vector3(0.045, 0.085, 0.035)), mats.bone_shadow, Vector3(0, -0.025, -0.326), Vector3(0, 0, 45))
	_add_owned_mesh(head, root, "BoneJaw", _box(Vector3(0.20, 0.095, 0.10)), mats.bone_dirty, Vector3(0, -0.155, -0.265), Vector3(-7, 0, 0))
	for tooth in range(5):
		_add_owned_mesh(head, root, "BoneTooth%02d" % tooth, _box(Vector3(0.026, 0.045, 0.024)), mats.bone, Vector3(-0.052 + tooth * 0.026, -0.123, -0.325), Vector3(float(tooth % 2) * 5, 0, 0))
	_add_owned_mesh(head, root, "ArmorHoodCrest", _box(Vector3(0.035, 0.28, 0.035)), mats.rust, Vector3(0, 0.09, 0.235), Vector3(12, 0, 0))


func _build_warden_arm(arm: Node3D, root: Node3D, side: int) -> void:
	var side_f := float(side)
	_add_owned_mesh(arm, root, "ArmorPauldron%d" % side, _sphere(0.5, 1.0, 14, 7), mats.black_iron, Vector3(side_f * 0.035, -0.045, 0), Vector3(0, 0, side_f * -8), Vector3(0.42, 0.30, 0.40))
	_add_owned_mesh(arm, root, "ArmorPauldronRim%d" % side, _torus(0.12, 0.18, 18, 6), mats.rust, Vector3(side_f * 0.025, -0.09, 0), Vector3(0, 0, 90), Vector3(1.0, 0.78, 1.0))
	_add_owned_mesh(arm, root, "ClothUpperArm%d" % side, _cylinder(0.105, 0.125, 0.34, 10), mats.black_cloth, Vector3(0, -0.23, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.95))
	_add_owned_mesh(arm, root, "ArmorElbowCop%d" % side, _sphere(0.5, 1.0, 12, 6), mats.dark_steel, Vector3(0, -0.405, -0.015), Vector3.ZERO, Vector3(0.22, 0.19, 0.20))
	_add_owned_mesh(arm, root, "ArmorVambrace%d" % side, _cylinder(0.085, 0.115, 0.31, 10), mats.black_iron, Vector3(0, -0.545, -0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.86))
	_add_owned_mesh(arm, root, "ArmorGauntlet%d" % side, _sphere(0.5, 1.0, 12, 6), mats.iron_edge, Vector3(0, -0.70, -0.015), Vector3.ZERO, Vector3(0.18, 0.20, 0.15))
	for finger in range(3):
		_add_owned_mesh(arm, root, "ArmorFinger%d_%02d" % [side, finger], _box(Vector3(0.032, 0.105, 0.035)), mats.dark_steel, Vector3(-0.036 + finger * 0.036, -0.78, -0.025), Vector3(-4, 0, 0))


func _build_warden_leg(leg: Node3D, root: Node3D, side: int) -> void:
	_add_owned_mesh(leg, root, "ClothLegUnderlay%d" % side, _cylinder(0.125, 0.15, 0.76, 10), mats.black_cloth, Vector3(0, -0.38, 0))
	_add_owned_mesh(leg, root, "ArmorCuisse%d" % side, _cylinder(0.13, 0.17, 0.38, 10), mats.black_iron, Vector3(0, -0.20, -0.005), Vector3.ZERO, Vector3(1.0, 1.0, 0.87))
	_add_owned_mesh(leg, root, "ArmorPoleyn%d" % side, _sphere(0.5, 1.0, 12, 6), mats.iron_edge, Vector3(0, -0.43, -0.055), Vector3.ZERO, Vector3(0.23, 0.20, 0.16))
	_add_owned_mesh(leg, root, "ArmorGreave%d" % side, _cylinder(0.09, 0.125, 0.37, 10), mats.black_iron, Vector3(0, -0.63, -0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.82))
	_add_owned_mesh(leg, root, "ArmorSabaton%d" % side, _box(Vector3(0.22, 0.14, 0.36)), mats.dark_steel, Vector3(0, -0.855, -0.095), Vector3(-7, 0, 0))
	for plate in range(3):
		_add_owned_mesh(leg, root, "ArmorSabatonPlate%d_%02d" % [side, plate], _box(Vector3(0.19 - plate * 0.018, 0.035, 0.11)), mats.iron_edge, Vector3(0, -0.79 - plate * 0.015, -0.16 - plate * 0.075), Vector3(-8, 0, 0))


func _build_warden_sword(weapon: Node3D, root: Node3D) -> void:
	var blade_points := PackedVector2Array([
		Vector2(-0.052, -0.04), Vector2(-0.060, -0.65), Vector2(-0.042, -0.80),
		Vector2(0, -0.90), Vector2(0.042, -0.80), Vector2(0.060, -0.65), Vector2(0.052, -0.04)
	])
	_add_owned_mesh(weapon, root, "WeaponLongswordBlade", _extruded_polygon_xy(blade_points, 0.035), mats.steel)
	_add_owned_mesh(weapon, root, "WeaponLongswordFuller", _box(Vector3(0.018, 0.57, 0.007)), mats.dark_steel, Vector3(0, -0.36, -0.021))
	_add_owned_mesh(weapon, root, "WeaponLongswordGuard", _box(Vector3(0.37, 0.048, 0.075)), mats.black_iron, Vector3(0, 0.005, 0))
	_add_owned_mesh(weapon, root, "WeaponLongswordGrip", _cylinder(0.040, 0.045, 0.27, 10), mats.leather, Vector3(0, 0.16, 0))
	for wrap in range(6):
		_add_owned_mesh(weapon, root, "WeaponGripWrap%02d" % wrap, _torus(0.037, 0.049, 12, 5), mats.leather_light, Vector3(0, 0.055 + wrap * 0.041, 0))
	_add_owned_mesh(weapon, root, "WeaponLongswordPommel", _sphere(0.5, 1.0, 10, 5), mats.rust, Vector3(0, 0.33, 0), Vector3.ZERO, Vector3(0.10, 0.11, 0.075))
	_add_owned_mesh(weapon, root, "WeaponBloodStain", _box(Vector3(0.038, 0.22, 0.006)), mats.dried_blood, Vector3(-0.035, -0.59, -0.022), Vector3(0, 0, -2))


func _build_ossuary_keeper() -> Node3D:
	var root := _new_root("OssuaryKeeper3D")
	var visual := _add_owned_pivot(root, root, "VisualRoot")
	var torso := _add_owned_pivot(visual, root, "TorsoPivot", Vector3(0, 1.19, 0.015), Vector3(-14, 0, 0))
	var head := _add_owned_pivot(torso, root, "HeadPivot", Vector3(0, 0.46, -0.10), Vector3(9, 0, 0))
	var arm_l := _add_owned_pivot(torso, root, "ArmLPivot", Vector3(-0.30, 0.28, -0.01), Vector3(8, -5, 12))
	var arm_r := _add_owned_pivot(torso, root, "ArmRPivot", Vector3(0.30, 0.28, -0.01), Vector3(-8, 4, -10))
	var leg_l := _add_owned_pivot(visual, root, "LegLPivot", Vector3(-0.13, 0.88, 0.03), Vector3(-6, 2, 5))
	var leg_r := _add_owned_pivot(visual, root, "LegRPivot", Vector3(0.13, 0.88, 0.03), Vector3(5, -2, -7))

	# Exposed spine and layered ribs remain readable from front, profile, and rear views.
	for vertebra in range(7):
		_add_owned_mesh(torso, root, "BoneSpine%02d" % vertebra, _sphere(0.5, 1.0, 8, 4), mats.bone_dirty, Vector3(0, -0.27 + vertebra * 0.095, 0.095), Vector3.ZERO, Vector3(0.075, 0.065, 0.065))
	_add_owned_mesh(torso, root, "BoneSternum", _box(Vector3(0.055, 0.43, 0.065)), mats.bone_dirty, Vector3(0, 0.06, -0.17), Vector3(-4, 0, 0))
	for rib in range(5):
		var rib_y := 0.23 - rib * 0.105
		var rib_scale := 1.0 - absf(float(rib) - 2.0) * 0.08
		_add_owned_mesh(torso, root, "BoneRibCage%02d" % rib, _torus(0.205, 0.245, 22, 6), mats.bone_dirty, Vector3(0, rib_y, -0.005), Vector3(90, 0, 0), Vector3(rib_scale, 0.66, 0.70 + rib * 0.035))
		# Dark cartilage break keeps the procedural loops from reading as perfect jewelry.
		_add_owned_mesh(torso, root, "BoneRibShadow%02d" % rib, _box(Vector3(0.055, 0.042, 0.06)), mats.bone_shadow, Vector3((0.025 if rib % 2 == 0 else -0.025), rib_y, -0.245))
	_add_owned_mesh(torso, root, "BonePelvis", _torus(0.17, 0.255, 20, 7), mats.bone_dirty, Vector3(0, -0.39, 0.015), Vector3(90, 0, 0), Vector3(1.08, 0.80, 0.73))
	_add_owned_mesh(torso, root, "ClothWaistCord", _torus(0.21, 0.245, 18, 5), mats.leather, Vector3(0, -0.36, 0), Vector3.ZERO, Vector3(1.0, 0.76, 0.80))

	var front_rag := PackedVector2Array([
		Vector2(-0.26, 0.28), Vector2(0.25, 0.28), Vector2(0.23, -0.24),
		Vector2(0.11, -0.52), Vector2(0.01, -0.38), Vector2(-0.10, -0.58),
		Vector2(-0.19, -0.41), Vector2(-0.27, -0.18)
	])
	_add_owned_mesh(torso, root, "ClothRaggedSurcoatFront", _extruded_polygon_xy(front_rag, 0.032), mats.cloth_rotten, Vector3(0, -0.04, -0.205), Vector3(-4, 0, 0))
	var back_rag := PackedVector2Array([
		Vector2(-0.24, 0.25), Vector2(0.25, 0.25), Vector2(0.23, -0.35),
		Vector2(0.10, -0.60), Vector2(-0.02, -0.45), Vector2(-0.16, -0.63), Vector2(-0.25, -0.30)
	])
	_add_owned_mesh(torso, root, "ClothRaggedSurcoatBack", _extruded_polygon_xy(back_rag, 0.030), mats.cloth_faded, Vector3(0, -0.03, 0.19), Vector3(4, 0, 0))
	for patch in range(4):
		_add_owned_mesh(torso, root, "ClothSurcoatPatch%02d" % patch, _box(Vector3(0.08 + patch * 0.012, 0.055, 0.012)), mats.leather, Vector3(-0.13 + patch * 0.09, 0.13 - patch * 0.13, -0.228), Vector3(0, 0, -19 + patch * 11))

	_build_keeper_head(head, root)
	_build_keeper_arm(arm_l, root, -1)
	_build_keeper_arm(arm_r, root, 1)
	_build_keeper_leg(leg_l, root, -1)
	_build_keeper_leg(leg_r, root, 1)

	var weapon := _add_owned_pivot(arm_r, root, "WeaponPivot", Vector3(0.01, -0.65, -0.025), Vector3(-6, 0, -13))
	_build_keeper_cleaver(weapon, root)
	return root


func _build_keeper_head(head: Node3D, root: Node3D) -> void:
	_add_owned_mesh(head, root, "ClothKeeperHood", _sphere(0.5, 1.0, 16, 8), mats.cloth_rotten, Vector3(0, 0.035, 0.045), Vector3.ZERO, Vector3(0.43, 0.50, 0.40))
	_add_owned_mesh(head, root, "ClothKeeperCowl", _torus(0.15, 0.255, 22, 6), mats.cloth_faded, Vector3(0, -0.17, 0.025), Vector3.ZERO, Vector3(1.0, 0.73, 0.88))
	_add_owned_mesh(head, root, "BoneKeeperSkull", _sphere(0.5, 1.0, 18, 9), mats.bone_dirty, Vector3(0, 0.015, -0.19), Vector3.ZERO, Vector3(0.25, 0.31, 0.18))
	for side in [-1, 1]:
		_add_owned_mesh(head, root, "BoneKeeperTemple%d" % side, _sphere(0.5, 1.0, 10, 5), mats.bone_shadow, Vector3(float(side) * 0.095, 0.035, -0.22), Vector3.ZERO, Vector3(0.060, 0.11, 0.055))
		_add_owned_mesh(head, root, "EyeKeeperSocket%d" % side, _sphere(0.5, 1.0, 10, 5), mats.bone_shadow, Vector3(float(side) * 0.053, 0.035, -0.282), Vector3.ZERO, Vector3(0.065, 0.060, 0.035))
		_add_owned_mesh(head, root, "EyeKeeperGlow%d" % side, _sphere(0.5, 1.0, 10, 5), mats.eye_teal, Vector3(float(side) * 0.053, 0.033, -0.311), Vector3.ZERO, Vector3(0.026, 0.023, 0.014))
	_add_owned_mesh(head, root, "BoneKeeperNose", _box(Vector3(0.040, 0.080, 0.030)), mats.bone_shadow, Vector3(0, -0.022, -0.292), Vector3(0, 0, 45))
	_add_owned_mesh(head, root, "BoneKeeperJaw", _box(Vector3(0.17, 0.085, 0.09)), mats.bone_dirty, Vector3(0.018, -0.145, -0.245), Vector3(-12, 0, 7))
	for tooth in range(4):
		_add_owned_mesh(head, root, "BoneKeeperTooth%02d" % tooth, _box(Vector3(0.025, 0.042, 0.023)), mats.bone, Vector3(-0.039 + tooth * 0.027, -0.112, -0.296), Vector3(float(tooth % 2) * 7, 0, 0))


func _build_keeper_arm(arm: Node3D, root: Node3D, side: int) -> void:
	var side_f := float(side)
	_add_owned_mesh(arm, root, "BoneShoulder%d" % side, _sphere(0.5, 1.0, 10, 5), mats.bone_dirty, Vector3(side_f * 0.02, -0.02, 0), Vector3.ZERO, Vector3(0.18, 0.16, 0.16))
	_add_owned_mesh(arm, root, "BoneHumerus%d" % side, _cylinder(0.042, 0.052, 0.32, 8), mats.bone_dirty, Vector3(0, -0.19, 0), Vector3.ZERO)
	_add_owned_mesh(arm, root, "BoneElbow%d" % side, _sphere(0.5, 1.0, 8, 4), mats.bone, Vector3(0, -0.37, -0.005), Vector3.ZERO, Vector3(0.12, 0.11, 0.11))
	_add_owned_mesh(arm, root, "BoneRadius%d" % side, _cylinder(0.034, 0.041, 0.29, 8), mats.bone_dirty, Vector3(-0.035, -0.515, -0.005), Vector3(0, 0, side_f * 5))
	_add_owned_mesh(arm, root, "BoneUlna%d" % side, _cylinder(0.030, 0.039, 0.29, 8), mats.bone_shadow, Vector3(0.035, -0.515, 0.018), Vector3(0, 0, side_f * -5))
	_add_owned_mesh(arm, root, "ClothWristBinding%d" % side, _cylinder(0.065, 0.065, 0.12, 9), mats.cloth_faded, Vector3(0, -0.65, 0))
	_add_owned_mesh(arm, root, "BoneHand%d" % side, _sphere(0.5, 1.0, 10, 5), mats.bone_dirty, Vector3(0, -0.705, -0.01), Vector3.ZERO, Vector3(0.14, 0.16, 0.11))
	for finger in range(3):
		_add_owned_mesh(arm, root, "BoneFinger%d_%02d" % [side, finger], _box(Vector3(0.026, 0.10, 0.025)), mats.bone_dirty, Vector3(-0.03 + finger * 0.03, -0.785, -0.02), Vector3(-5, 0, 0))


func _build_keeper_leg(leg: Node3D, root: Node3D, side: int) -> void:
	var side_f := float(side)
	_add_owned_mesh(leg, root, "BoneHip%d" % side, _sphere(0.5, 1.0, 10, 5), mats.bone_dirty, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(0.18, 0.16, 0.16))
	_add_owned_mesh(leg, root, "BoneFemur%d" % side, _cylinder(0.050, 0.060, 0.35, 8), mats.bone_dirty, Vector3(0, -0.21, 0), Vector3(0, 0, side_f * 3))
	_add_owned_mesh(leg, root, "BoneKnee%d" % side, _sphere(0.5, 1.0, 9, 5), mats.bone, Vector3(0, -0.41, -0.015), Vector3.ZERO, Vector3(0.14, 0.13, 0.12))
	_add_owned_mesh(leg, root, "BoneShin%d" % side, _cylinder(0.040, 0.050, 0.34, 8), mats.bone_dirty, Vector3(0, -0.60, -0.005), Vector3(0, 0, side_f * -3))
	_add_owned_mesh(leg, root, "ClothAnkleWrap%d" % side, _cylinder(0.070, 0.072, 0.13, 9), mats.cloth_rotten, Vector3(0, -0.76, 0))
	_add_owned_mesh(leg, root, "BoneFoot%d" % side, _box(Vector3(0.16, 0.10, 0.31)), mats.bone_dirty, Vector3(0, -0.79, -0.095), Vector3(-8, 0, 0))
	for toe in range(3):
		_add_owned_mesh(leg, root, "BoneToe%d_%02d" % [side, toe], _box(Vector3(0.032, 0.045, 0.13)), mats.bone, Vector3(-0.035 + toe * 0.035, -0.805, -0.245), Vector3(-6, 0, 0))


func _build_keeper_cleaver(weapon: Node3D, root: Node3D) -> void:
	_add_owned_mesh(weapon, root, "WeaponCleaverGrip", _cylinder(0.040, 0.046, 0.30, 9), mats.leather, Vector3(0, 0.13, 0))
	for wrap in range(5):
		_add_owned_mesh(weapon, root, "WeaponCleaverWrap%02d" % wrap, _torus(0.037, 0.050, 10, 5), mats.leather_light, Vector3(0, 0.025 + wrap * 0.052, 0))
	_add_owned_mesh(weapon, root, "WeaponCleaverPommel", _sphere(0.5, 1.0, 8, 4), mats.rust, Vector3(0, 0.31, 0), Vector3.ZERO, Vector3(0.085, 0.09, 0.07))
	_add_owned_mesh(weapon, root, "WeaponCleaverTang", _box(Vector3(0.075, 0.15, 0.045)), mats.dark_steel, Vector3(0, -0.06, 0))
	var cleaver_points := PackedVector2Array([
		Vector2(-0.07, -0.10), Vector2(-0.18, -0.58), Vector2(-0.15, -0.82),
		Vector2(0.20, -0.84), Vector2(0.26, -0.35), Vector2(0.15, -0.14)
	])
	_add_owned_mesh(weapon, root, "WeaponCleaverBlade", _extruded_polygon_xy(cleaver_points, 0.055), mats.steel)
	_add_owned_mesh(weapon, root, "WeaponCleaverSpine", _box(Vector3(0.055, 0.60, 0.065)), mats.dark_steel, Vector3(0.20, -0.48, 0), Vector3(0, 0, -6))
	_add_owned_mesh(weapon, root, "WeaponCleaverBlood", _box(Vector3(0.28, 0.12, 0.008)), mats.dried_blood, Vector3(0.02, -0.72, -0.032), Vector3(0, 0, -4))
	_add_owned_mesh(weapon, root, "WeaponCleaverNotch", _box(Vector3(0.065, 0.065, 0.062)), mats.bone_shadow, Vector3(-0.14, -0.61, 0), Vector3(0, 0, 35))


func _build_sword() -> Node3D:
	var root := _new_root("RustedLongsword")
	var blade_points := PackedVector2Array([
		Vector2(-0.058, 0.04), Vector2(-0.068, 0.73), Vector2(-0.05, 0.96),
		Vector2(0.0, 1.085), Vector2(0.05, 0.96), Vector2(0.068, 0.73), Vector2(0.058, 0.04)
	])
	_add_mesh(root, "PittedBlade", _extruded_polygon_xy(blade_points, 0.034), mats.steel)
	_add_mesh(root, "FullerFront", _box(Vector3(0.019, 0.66, 0.006)), mats.dark_steel, Vector3(0, 0.49, 0.02))
	_add_mesh(root, "FullerBack", _box(Vector3(0.019, 0.66, 0.006)), mats.dark_steel, Vector3(0, 0.49, -0.02))

	_add_mesh(root, "Crossguard", _box(Vector3(0.39, 0.045, 0.072)), mats.dark_steel, Vector3(0, 0.015, 0))
	_add_mesh(root, "GuardLeftQuillon", _cylinder(0.026, 0.033, 0.13, 8), mats.dark_steel, Vector3(-0.24, 0.045, 0), Vector3(0, 0, 74))
	_add_mesh(root, "GuardRightQuillon", _cylinder(0.026, 0.033, 0.13, 8), mats.dark_steel, Vector3(0.24, 0.045, 0), Vector3(0, 0, -74))
	_add_mesh(root, "Grip", _cylinder(0.043, 0.048, 0.30, 10), mats.leather, Vector3(0, -0.16, 0))
	for index in range(7):
		_add_mesh(root, "GripWrap%02d" % index, _torus(0.041, 0.052, 12, 5), mats.leather_light, Vector3(0, -0.275 + index * 0.039, 0))
	_add_mesh(root, "PommelNeck", _cylinder(0.055, 0.055, 0.055, 10), mats.dark_steel, Vector3(0, -0.335, 0))
	_add_mesh(root, "Pommel", _sphere(0.5, 1.0, 12, 6), mats.dark_steel, Vector3(0, -0.405, 0), Vector3.ZERO, Vector3(0.092, 0.105, 0.07))

	# Deliberate rust blooms break up the otherwise uniform procedural metal.
	_add_mesh(root, "RustBloom01", _box(Vector3(0.018, 0.19, 0.005)), mats.rust, Vector3(-0.052, 0.24, 0.021), Vector3(0, 0, -2))
	_add_mesh(root, "RustBloom02", _box(Vector3(0.014, 0.13, 0.005)), mats.rust_bright, Vector3(0.055, 0.64, 0.021), Vector3(0, 0, 3))
	_add_mesh(root, "RustBloom03", _box(Vector3(0.025, 0.055, 0.005)), mats.rust, Vector3(-0.02, 0.88, 0.021), Vector3(0, 0, -12))
	_add_marker(root, "GripAnchor", Vector3(0, -0.16, 0))
	_add_marker(root, "BladeTip", Vector3(0, 1.085, 0))
	return root


func _build_shield() -> Node3D:
	var root := _new_root("WeatheredRoundShield")
	_add_mesh(root, "WoodenCore", _cylinder(0.455, 0.455, 0.075, 32), mats.wood, Vector3.ZERO, Vector3(90, 0, 0))
	_add_mesh(root, "IronRim", _torus(0.425, 0.50, 40, 8), mats.dark_steel, Vector3(0, 0, 0.015), Vector3(90, 0, 0))

	# Thin seams imply separate rough-hewn planks without polygon-heavy booleans.
	for index in range(-3, 4):
		var x := index * 0.112
		var half_height := sqrt(maxf(0.0, 0.425 * 0.425 - x * x))
		_add_mesh(root, "PlankSeam%02d" % (index + 3), _box(Vector3(0.008, half_height * 2.0, 0.006)), mats.wood_dark, Vector3(x, 0, 0.043))

	_add_mesh(root, "VerticalBrace", _box(Vector3(0.075, 0.78, 0.035)), mats.dark_steel, Vector3(0, 0, 0.072))
	_add_mesh(root, "HorizontalBrace", _box(Vector3(0.78, 0.075, 0.035)), mats.dark_steel, Vector3(0, 0, 0.073))
	_add_mesh(root, "Boss", _sphere(0.5, 1.0, 20, 10), mats.dark_steel, Vector3(0, 0, 0.105), Vector3.ZERO, Vector3(0.175, 0.175, 0.10))
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		_add_mesh(root, "Rivet%02d" % index, _sphere(0.5, 1.0, 8, 4), mats.rust_bright, Vector3(cos(angle) * 0.36, sin(angle) * 0.36, 0.09), Vector3.ZERO, Vector3(0.025, 0.025, 0.016))

	# Rear grip and arm strap are included for third-person/item-inspection views.
	_add_mesh(root, "RearGrip", _box(Vector3(0.08, 0.42, 0.06)), mats.leather, Vector3(0.12, 0, -0.075), Vector3(0, 0, -8))
	_add_mesh(root, "RearArmStrap", _box(Vector3(0.32, 0.07, 0.055)), mats.leather_light, Vector3(-0.06, -0.14, -0.075), Vector3(0, 0, 15))
	_add_marker(root, "HandAnchor", Vector3(0.12, 0, -0.11))
	return root


func _build_torch() -> Node3D:
	var root := _new_root("IronCageTorch")
	_add_mesh(root, "CharredHandle", _cylinder(0.038, 0.052, 0.88, 10), mats.wood_dark, Vector3(0, 0.33, 0))
	for index in range(6):
		_add_mesh(root, "LeatherWrap%02d" % index, _torus(0.037, 0.049, 12, 5), mats.leather_light, Vector3(0, 0.05 + index * 0.046, 0))
	_add_mesh(root, "IronCollar", _cylinder(0.09, 0.07, 0.13, 10), mats.dark_steel, Vector3(0, 0.80, 0))
	_add_mesh(root, "FuelCup", _cylinder(0.14, 0.09, 0.13, 12), mats.dark_steel, Vector3(0, 0.91, 0))
	for index in range(4):
		var angle := TAU * float(index) / 4.0
		_add_mesh(root, "CageProng%02d" % index, _box(Vector3(0.025, 0.34, 0.025)), mats.dark_steel, Vector3(cos(angle) * 0.115, 1.07, sin(angle) * 0.115), Vector3(rad_to_deg(sin(angle) * 7.0), 0, rad_to_deg(cos(angle) * -7.0)))
	_add_mesh(root, "CageTop", _torus(0.095, 0.135, 20, 6), mats.dark_steel, Vector3(0, 1.23, 0))
	for index in range(7):
		var angle := TAU * float(index) / 7.0
		_add_mesh(root, "Coal%02d" % index, _sphere(0.5, 1.0, 8, 4), mats.coal, Vector3(cos(angle) * 0.065, 0.99 + (index % 2) * 0.025, sin(angle) * 0.065), Vector3.ZERO, Vector3(0.055, 0.04, 0.055))

	var outer_flame := PackedVector2Array([
		Vector2(-0.115, 0.0), Vector2(-0.09, 0.20), Vector2(-0.03, 0.38),
		Vector2(0.01, 0.52), Vector2(0.07, 0.29), Vector2(0.12, 0.12), Vector2(0.105, 0.0)
	])
	var inner_flame := PackedVector2Array([
		Vector2(-0.06, 0.0), Vector2(-0.035, 0.15), Vector2(0.005, 0.31),
		Vector2(0.05, 0.13), Vector2(0.065, 0.0)
	])
	_add_mesh(root, "OuterFlame", _extruded_polygon_xy(outer_flame, 0.11), mats.flame_outer, Vector3(0, 0.99, 0))
	_add_mesh(root, "InnerFlame", _extruded_polygon_xy(inner_flame, 0.12), mats.flame_inner, Vector3(0, 1.00, -0.002))
	_add_marker(root, "GripAnchor", Vector3(0, 0.18, 0))
	_add_marker(root, "FlameAnchor", Vector3(0, 1.16, 0))
	return root


func _build_chest() -> Node3D:
	var root := _new_root("ReliquaryChest")
	_add_mesh(root, "ChestBody", _box(Vector3(1.2, 0.62, 0.72)), mats.wood, Vector3(0, 0.37, 0))
	for row in range(3):
		_add_mesh(root, "FrontPlank%02d" % row, _box(Vector3(1.16, 0.17, 0.035)), wood_variants[row % wood_variants.size()], Vector3(0, 0.17 + row * 0.19, -0.375))
		_add_mesh(root, "BackPlank%02d" % row, _box(Vector3(1.16, 0.17, 0.035)), wood_variants[(row + 1) % wood_variants.size()], Vector3(0, 0.17 + row * 0.19, 0.375))

	# Seven slats approximate an old barrel-vault lid and read well at gameplay distance.
	for index in range(-3, 4):
		var z := index * 0.112
		var normalized := clampf(z / 0.37, -1.0, 1.0)
		var y := 0.69 + sqrt(maxf(0.0, 1.0 - normalized * normalized)) * 0.17
		var slope := -rad_to_deg(asin(normalized)) * 0.42
		_add_mesh(root, "LidSlat%02d" % (index + 3), _box(Vector3(1.24, 0.12, 0.14)), wood_variants[(index + 4) % wood_variants.size()], Vector3(0, y, z), Vector3(slope, 0, 0))
		for band_index in range(2):
			var band_x := -0.42 if band_index == 0 else 0.42
			_add_mesh(root, "LidBand%d_%02d" % [band_index, index + 3], _box(Vector3(0.072, 0.135, 0.145)), mats.dark_steel, Vector3(band_x, y + 0.012, z), Vector3(slope, 0, 0))

	for x in [-0.53, 0.53]:
		_add_mesh(root, "FrontCornerBand", _box(Vector3(0.075, 0.62, 0.055)), mats.dark_steel, Vector3(x, 0.37, -0.39))
		_add_mesh(root, "SideCornerBand", _box(Vector3(0.055, 0.62, 0.72)), mats.dark_steel, Vector3(x, 0.37, 0))
	_add_mesh(root, "BottomBand", _box(Vector3(1.28, 0.08, 0.80)), mats.dark_steel, Vector3(0, 0.08, 0))
	_add_mesh(root, "LockPlate", _box(Vector3(0.20, 0.24, 0.055)), mats.dark_steel, Vector3(0, 0.62, -0.405))
	_add_mesh(root, "LockRune", _torus(0.032, 0.065, 14, 5), mats.rune, Vector3(0, 0.64, -0.438), Vector3(90, 0, 0))
	for x in [-0.42, 0.42]:
		_add_mesh(root, "RearHinge", _box(Vector3(0.16, 0.06, 0.09)), mats.rust, Vector3(x, 0.70, 0.40), Vector3(12, 0, 0))
	_add_collision_box(root, "ChestCollision", Vector3(1.28, 0.95, 0.82), Vector3(0, 0.475, 0))
	_add_marker(root, "InteractionAnchor", Vector3(0, 0.58, -0.52))
	_add_marker(root, "LidPivot", Vector3(0, 0.72, 0.38))
	return root


func _build_rune_trap() -> Node3D:
	var root := _new_root("BloodRuneTrap")
	_add_mesh(root, "SunkenStone", _cylinder(0.86, 0.90, 0.10, 40), mats.stone_dark, Vector3(0, 0.02, 0))
	_add_mesh(root, "CarvedPlate", _cylinder(0.78, 0.82, 0.075, 40), mats.stone, Vector3(0, 0.075, 0))
	_add_mesh(root, "OuterBloodRing", _torus(0.63, 0.69, 44, 7), mats.rune, Vector3(0, 0.125, 0))
	_add_mesh(root, "InnerBloodRing", _torus(0.30, 0.335, 36, 6), mats.rune, Vector3(0, 0.13, 0))

	# Twelve individually readable sigils around the circumference.
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var radius := 0.49
		var center := Vector2(cos(angle) * radius, sin(angle) * radius)
		_add_stroke_xz(root, "Rune%02dA" % index, center, 0.15, angle, 0.026, mats.rune, 0.142)
		var tick_center := center + Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5)) * 0.045
		_add_stroke_xz(root, "Rune%02dB" % index, tick_center, 0.085, angle + PI * 0.66, 0.022, mats.rune, 0.144)

	# Central broken triskelion.
	for index in range(3):
		var angle := TAU * float(index) / 3.0 - PI * 0.5
		var center := Vector2(cos(angle) * 0.14, sin(angle) * 0.14)
		_add_stroke_xz(root, "CenterSigil%02d" % index, center, 0.31, angle, 0.032, mats.rune, 0.145)
		var hook_center := center + Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5)) * 0.10
		_add_stroke_xz(root, "CenterHook%02d" % index, hook_center, 0.15, angle + PI * 0.5, 0.026, mats.rune, 0.147)

	# Dark grooves and repaired iron staples make the plate feel excavated rather than pristine.
	for index in range(7):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(0.16, 0.72)
		var center := Vector2(cos(angle) * radius, sin(angle) * radius)
		_add_stroke_xz(root, "Crack%02d" % index, center, rng.randf_range(0.12, 0.32), angle + rng.randf_range(-0.8, 0.8), 0.012, mats.ash, 0.132)
	_add_collision_box(root, "TrapCollision", Vector3(1.78, 0.12, 1.78), Vector3(0, 0.04, 0))
	_add_marker(root, "DamageOrigin", Vector3(0, 0.15, 0))
	return root


func _build_portal_arch() -> Node3D:
	var root := _new_root("SanctumPortalArch")
	# Foundation and two block-built piers.
	_add_mesh(root, "Threshold", _box(Vector3(3.05, 0.26, 0.82)), stone_variants[3], Vector3(0, 0.13, 0))
	for side in [-1, 1]:
		for row in range(6):
			var x: float = float(side) * (1.07 + (row % 2) * 0.025)
			var y := 0.42 + row * 0.37
			var block_scale := Vector3(0.52 + rng.randf_range(-0.035, 0.035), 0.35, 0.62 + rng.randf_range(-0.03, 0.03))
			_add_mesh(root, "Pier%d_%02d" % [side, row], _box(block_scale), stone_variants[(row + (2 if side > 0 else 0)) % stone_variants.size()], Vector3(x, y, rng.randf_range(-0.025, 0.025)), Vector3(0, rng.randf_range(-1.5, 1.5), rng.randf_range(-1.1, 1.1)))

	# Radial blocks form the arch without requiring destructive mesh booleans.
	var arch_center := Vector2(0, 2.23)
	for index in range(13):
		var angle := PI * float(index) / 12.0
		var center := arch_center + Vector2(cos(angle), sin(angle)) * 1.07
		_add_mesh(root, "Voussoir%02d" % index, _box(Vector3(0.43, 0.49, 0.64)), stone_variants[index % stone_variants.size()], Vector3(center.x, center.y, 0), Vector3(0, rng.randf_range(-1.2, 1.2), rad_to_deg(angle - PI * 0.5)))

	# The translucent portal membrane is an elliptical, very shallow cylinder.
	_add_mesh(root, "PortalMembrane", _cylinder(1.0, 1.0, 0.05, 48), mats.portal, Vector3(0, 2.12, 0.04), Vector3(90, 0, 0), Vector3(0.86, 0.045, 1.23))
	for ring_index in range(3):
		var scale_value := 0.70 - ring_index * 0.13
		_add_mesh(root, "PortalCurrent%02d" % ring_index, _torus(scale_value - 0.028, scale_value + 0.028, 40, 6), mats.portal_hot, Vector3(0, 2.12, -0.015 - ring_index * 0.008), Vector3(90, 0, ring_index * 17), Vector3(1.0, 1.0, 1.36))
	for index in range(9):
		var angle := PI * float(index) / 8.0
		var center := arch_center + Vector2(cos(angle), sin(angle)) * 1.37
		_add_mesh(root, "ArchRune%02d" % index, _box(Vector3(0.08, 0.18, 0.018)), mats.portal_hot, Vector3(center.x, center.y, -0.335), Vector3(0, 0, rad_to_deg(angle - PI * 0.5)))

	_add_collision_box(root, "LeftPierCollision", Vector3(0.62, 2.35, 0.72), Vector3(-1.07, 1.28, 0))
	_add_collision_box(root, "RightPierCollision", Vector3(0.62, 2.35, 0.72), Vector3(1.07, 1.28, 0))
	_add_collision_box(root, "ArchCollision", Vector3(2.55, 0.55, 0.72), Vector3(0, 3.18, 0))
	_add_marker(root, "PortalTarget", Vector3(0, 1.35, 0))
	_add_marker(root, "InteractionAnchor", Vector3(0, 1.15, -0.65))
	return root


func _build_floor_module() -> Node3D:
	var root := _new_root("DungeonFloor4m")
	_add_mesh(root, "MortarBed", _box(Vector3(4.0, 0.16, 4.0)), mats.mortar, Vector3(0, -0.10, 0))
	for x_index in range(4):
		for z_index in range(4):
			var x := -1.5 + x_index
			var z := -1.5 + z_index
			var position := Vector3(x + rng.randf_range(-0.035, 0.035), rng.randf_range(-0.015, 0.015), z + rng.randf_range(-0.035, 0.035))
			var size := Vector3(0.93 + rng.randf_range(-0.035, 0.025), 0.19 + rng.randf_range(-0.025, 0.02), 0.93 + rng.randf_range(-0.035, 0.025))
			_add_mesh(root, "FloorStone%d_%d" % [x_index, z_index], _box(size), stone_variants[(x_index * 3 + z_index) % stone_variants.size()], position, Vector3(0, rng.randf_range(-1.2, 1.2), 0))
	_add_collision_box(root, "FloorCollision", Vector3(4.0, 0.20, 4.0), Vector3(0, -0.06, 0))
	return root


func _build_wall_module() -> Node3D:
	var root := _new_root("DungeonWall4m")
	_add_mesh(root, "MortarBacking", _box(Vector3(4.0, 3.0, 0.22)), mats.mortar, Vector3(0, 1.5, 0.08))
	for row in range(6):
		var columns := 8
		var offset := 0.24 if row % 2 == 1 else 0.0
		for column in range(columns):
			var x := -1.75 + column * 0.50 + offset
			if x > 1.92:
				continue
			var y := 0.25 + row * 0.50
			var size := Vector3(0.46 + rng.randf_range(-0.025, 0.025), 0.44 + rng.randf_range(-0.025, 0.025), 0.24 + rng.randf_range(-0.02, 0.025))
			_add_mesh(root, "WallStone%d_%d" % [row, column], _box(size), stone_variants[(row + column * 2) % stone_variants.size()], Vector3(x + rng.randf_range(-0.012, 0.012), y + rng.randf_range(-0.012, 0.012), -0.07 + rng.randf_range(-0.018, 0.025)), Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.1, 1.1), rng.randf_range(-0.8, 0.8)))
			_add_mesh(root, "WallStoneBack%d_%d" % [row, column], _box(size), stone_variants[(row + column * 2 + 1) % stone_variants.size()], Vector3(x + rng.randf_range(-0.012, 0.012), y + rng.randf_range(-0.012, 0.012), 0.31 + rng.randf_range(-0.018, 0.025)), Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.1, 1.1), rng.randf_range(-0.8, 0.8)))
	_add_collision_box(root, "WallCollision", Vector3(4.0, 3.0, 0.35), Vector3(0, 1.5, 0))
	return root


func _build_archway_module() -> Node3D:
	var root := _new_root("DungeonArchway4m")
	# Side piers leave a 1.7 m opening and share the same 4 m grid footprint as the wall.
	for side in [-1, 1]:
		for row in range(6):
			for column in range(2):
				var x: float = float(side) * (1.10 + column * 0.48)
				var y := 0.25 + row * 0.50
				_add_mesh(root, "ArchPier%d_%d_%d" % [side, row, column], _box(Vector3(0.44, 0.45, 0.34)), stone_variants[(row + column) % stone_variants.size()], Vector3(x, y, rng.randf_range(-0.015, 0.015)), Vector3(0, rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6)))
	var center := Vector2(0, 2.05)
	for index in range(11):
		var angle := PI * float(index) / 10.0
		var location := center + Vector2(cos(angle), sin(angle)) * 0.92
		_add_mesh(root, "ArchStone%02d" % index, _box(Vector3(0.40, 0.46, 0.40)), stone_variants[(index + 2) % stone_variants.size()], Vector3(location.x, location.y, 0), Vector3(0, rng.randf_range(-0.8, 0.8), rad_to_deg(angle - PI * 0.5)))
	for column in range(8):
		_add_mesh(root, "TopStone%02d" % column, _box(Vector3(0.46, 0.42, 0.34)), stone_variants[column % stone_variants.size()], Vector3(-1.75 + column * 0.5, 2.79, 0))
	_add_collision_box(root, "ArchLeftCollision", Vector3(1.12, 3.0, 0.42), Vector3(-1.44, 1.5, 0))
	_add_collision_box(root, "ArchRightCollision", Vector3(1.12, 3.0, 0.42), Vector3(1.44, 1.5, 0))
	_add_collision_box(root, "ArchTopCollision", Vector3(1.78, 0.62, 0.42), Vector3(0, 2.72, 0))
	_add_marker(root, "DoorwayCenter", Vector3(0, 1.0, 0))
	return root


func _build_pillar_module() -> Node3D:
	var root := _new_root("DungeonPillar3m")
	_add_mesh(root, "Footing", _box(Vector3(0.92, 0.22, 0.92)), stone_variants[3], Vector3(0, 0.11, 0))
	_add_mesh(root, "LowerPlinth", _box(Vector3(0.74, 0.24, 0.74)), stone_variants[1], Vector3(0, 0.34, 0), Vector3(0, 4, 0))
	_add_mesh(root, "Column", _cylinder(0.31, 0.37, 2.20, 10), stone_variants[0], Vector3(0, 1.53, 0), Vector3(0, 7, 0))
	_add_mesh(root, "LowerCollar", _cylinder(0.40, 0.40, 0.17, 10), stone_variants[4], Vector3(0, 0.53, 0))
	_add_mesh(root, "UpperCollar", _cylinder(0.40, 0.40, 0.17, 10), stone_variants[4], Vector3(0, 2.54, 0))
	_add_mesh(root, "Capital", _box(Vector3(0.76, 0.27, 0.76)), stone_variants[2], Vector3(0, 2.76, 0), Vector3(0, -3, 0))
	_add_mesh(root, "Abacus", _box(Vector3(0.94, 0.22, 0.94)), stone_variants[3], Vector3(0, 3.0, 0))
	_add_mesh(root, "BloodMark", _box(Vector3(0.035, 0.72, 0.018)), mats.rune, Vector3(0, 1.72, -0.323), Vector3(0, 0, 7))
	_add_collision_box(root, "PillarCollision", Vector3(0.82, 3.10, 0.82), Vector3(0, 1.55, 0))
	return root


func _build_stairs_module() -> Node3D:
	var root := _new_root("DungeonStairs4m")
	var step_count := 10
	var rise := 0.20
	var run := 0.38
	for index in range(step_count):
		var height := (index + 1) * rise
		var z := 1.71 - index * run
		_add_mesh(root, "Step%02d" % index, _box(Vector3(2.0, height, run + 0.035)), stone_variants[index % stone_variants.size()], Vector3(rng.randf_range(-0.012, 0.012), height * 0.5, z), Vector3(0, rng.randf_range(-0.5, 0.5), 0))
		_add_mesh(root, "StepLip%02d" % index, _box(Vector3(2.06, 0.055, 0.08)), stone_variants[(index + 2) % stone_variants.size()], Vector3(0, height - 0.02, z - run * 0.48))
	# Two side buttresses visually support the staircase; gameplay can keep its own ramp collider.
	_add_mesh(root, "LeftButtress", _box(Vector3(0.24, 1.95, 3.90)), mats.stone_dark, Vector3(-1.08, 0.975, 0.0))
	_add_mesh(root, "RightButtress", _box(Vector3(0.24, 1.95, 3.90)), mats.stone_dark, Vector3(1.08, 0.975, 0.0))
	var ramp_profile := PackedVector2Array([
		Vector2(-1.92, 0.0), Vector2(1.92, 0.0), Vector2(1.92, 0.20), Vector2(-1.92, 2.02)
	])
	_add_mesh(root, "StairRampCollision-colonly", _extruded_polygon_xy(ramp_profile, 2.0), mats.invisible, Vector3.ZERO, Vector3(0, 90, 0))
	_add_marker(root, "StairBottom", Vector3(0, 0, 1.9))
	_add_marker(root, "StairTop", Vector3(0, 2.0, -1.9))
	return root
