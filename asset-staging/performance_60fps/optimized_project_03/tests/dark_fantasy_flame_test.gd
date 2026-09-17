extends SceneTree

const FLAME := preload("res://scripts/flame_visuals.gd")
const CAMP := preload("res://scripts/camp_visuals.gd")
const HIDEOUT := preload("res://scripts/hideout.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.ensure_journey()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mode := Input.mouse_mode
	var camp: Node3D = CAMP.create_camp()
	var sprite := camp.get_node("Flame") as Sprite3D
	_check(sprite.has_meta("dimensional_flame"), "Live camp builds shared dimensional flame")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, "Flame keeps world vertical from top and bottom viewpoints")
	var tongue := sprite.find_child("FlowingFireTongue_0", true, false) as MeshInstance3D
	_check(tongue != null and tongue.get_aabb().size.z > 0.03, "A true flame volume remains visible when image is edge-on")
	for warmth in [0, 1, 3]:
		for elapsed in [0.0, 0.6, 1.25]:
			CAMP.animate(camp, elapsed, warmth)
			var flame_foot: float = sprite.position.y + (tongue.position.y + tongue.get_aabb().position.y) * sprite.scale.y
			_check(is_equal_approx(flame_foot, 0.10), "Camp flame stays rooted on logs through warmth and flicker changes")
	_check((sprite.material_override as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "Authored black matte does not obscure scene behind flame")
	FLAME.attach(sprite)
	_check(sprite.get_child_count() == 1, "Repeated surface hook leaves only one flame assembly")
	var hideout := HIDEOUT.new()
	hideout._build_materials()
	var root_node := Node3D.new()
	hideout._add_water_drips(Vector3(0, 3, 0), Vector3(1, 0.1, 1), 18, root_node)
	var drops := root_node.get_child(0) as CPUParticles3D
	_check(drops.mesh is ArrayMesh and drops.amount == 18, "Live water drips preserve particle count and use actual tear volume")
	_check(drops.mesh.get_aabb().size.z > 0.01, "Water has a circular top-view footprint")
	_check(FLAME.steam_texture() == FLAME.steam_texture(), "Cooking wisps share a single texture")
	_check(snapshot == ExpeditionSession.capture_snapshot() and mode == Input.mouse_mode, "Decorative effects leave session and input unchanged")
	root_node.free()
	hideout.free()
	camp.free()
	for frame in 12:
		await process_frame
	if failures.is_empty():
		print("DARK FANTASY FLAME TEST PASS: actual flame volume, additive source detail, water beads and session preservation")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY FLAME TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
