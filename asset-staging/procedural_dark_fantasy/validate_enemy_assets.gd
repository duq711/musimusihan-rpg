extends SceneTree

# Contract validation for the two runtime-articulated enemy visuals. This script
# intentionally loads the exported GLBs through Godot's normal importer rather
# than inspecting the generator's in-memory scene.

const REQUIRED_PATHS := [
	"VisualRoot",
	"VisualRoot/TorsoPivot",
	"VisualRoot/TorsoPivot/HeadPivot",
	"VisualRoot/TorsoPivot/ArmLPivot",
	"VisualRoot/TorsoPivot/ArmRPivot",
	"VisualRoot/TorsoPivot/ArmRPivot/WeaponPivot",
	"VisualRoot/LegLPivot",
	"VisualRoot/LegRPivot",
]
const ALLOWED_MESH_PREFIXES := ["Armor", "Cloth", "Bone", "Weapon", "Eye"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions := [
		{
			"file": "sanctuary_warden_3d.glb",
			"weapon": "WeaponLongswordBlade",
			"eye_prefix": "EyeGlow",
			"minimum_meshes": 80,
		},
		{
			"file": "ossuary_keeper_3d.glb",
			"weapon": "WeaponCleaverBlade",
			"eye_prefix": "EyeKeeperGlow",
			"minimum_meshes": 85,
		},
	]
	var failures: Array[String] = []
	for definition in definitions:
		_validate_one(definition, failures)

	if failures.is_empty():
		print("Enemy GLB contract validation passed.")
		quit(0)
	else:
		push_error("Enemy GLB contract failures:\n - %s" % "\n - ".join(failures))
		quit(1)


func _validate_one(definition: Dictionary, failures: Array[String]) -> void:
	var file_name: String = definition.file
	var packed := load("res://out/%s" % file_name) as PackedScene
	if packed == null:
		failures.append("%s is not an imported PackedScene" % file_name)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		failures.append("%s did not instantiate as Node3D" % file_name)
		return
	get_root().add_child(instance)

	for required_path in REQUIRED_PATHS:
		if instance.get_node_or_null(required_path) == null:
			failures.append("%s missing %s" % [file_name, required_path])

	var mesh_count := 0
	var eye_count := 0
	var weapon_found := false
	var forbidden_body_count := 0
	var found_bounds := false
	var combined := AABB()
	for node in _all_descendants(instance):
		if node is CollisionObject3D or node is CollisionShape3D:
			forbidden_body_count += 1
		if node is MeshInstance3D:
			mesh_count += 1
			var mesh_name := String(node.name)
			var allowed := false
			for prefix in ALLOWED_MESH_PREFIXES:
				if mesh_name.begins_with(prefix):
					allowed = true
					break
			if not allowed:
				failures.append("%s mesh %s lacks a selection prefix" % [file_name, mesh_name])
			if mesh_name.begins_with(definition.eye_prefix):
				eye_count += 1
			if mesh_name == definition.weapon:
				weapon_found = true
			var mesh_node := node as MeshInstance3D
			var world_aabb := mesh_node.global_transform * mesh_node.get_aabb()
			combined = world_aabb if not found_bounds else combined.merge(world_aabb)
			found_bounds = true

	if mesh_count < int(definition.minimum_meshes):
		failures.append("%s has only %d meshes" % [file_name, mesh_count])
	if eye_count != 2:
		failures.append("%s expected 2 glow eyes, found %d" % [file_name, eye_count])
	if not weapon_found:
		failures.append("%s missing weapon mesh %s" % [file_name, definition.weapon])
	if forbidden_body_count != 0:
		failures.append("%s unexpectedly contains %d collision nodes" % [file_name, forbidden_body_count])
	if not found_bounds:
		failures.append("%s has no mesh bounds" % file_name)
	else:
		var min_y := combined.position.y
		var height := combined.size.y
		if min_y < -0.075 or min_y > 0.075:
			failures.append("%s feet are not at y=0 (min y %.3f)" % [file_name, min_y])
		if height < 1.85 or height > 2.18:
			failures.append("%s height %.3f is outside 1.85..2.18m" % [file_name, height])
		print("%-26s meshes=%d eyes=%d collisions=%d bounds=(%.2f, %.2f, %.2f) min_y=%.3f" % [
			file_name, mesh_count, eye_count, forbidden_body_count,
			combined.size.x, combined.size.y, combined.size.z, min_y,
		])
	instance.free()


func _all_descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result
