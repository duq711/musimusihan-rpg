extends SceneTree
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const ART := preload("res://scripts/cave_art_direction.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	for id in ["mine_rock_formation", "mine_calcite", "mine_mineral_cluster", "mine_surface_rock", "mine_detail_rock"]:
		var object := CATALOG.build_object(id)
		for node: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
			for index in node.mesh.get_surface_count():
				var material := node.get_active_material(index)
				if not material is ShaderMaterial or material.shader != ART.GEOLOGY:
					failures.append("%s/%s active material bypasses actual world-projected geology: %s override=%s surface_override=%s" % [id, node.name, material, node.material_override, node.get_surface_override_material(index)])
		object.free()
	CATALOG.release_cached_templates()
	if ExpeditionSession.capture_snapshot() != state or Input.mouse_mode != mouse:
		failures.append("Geology factories changed expedition or cursor")
	if failures.is_empty():
		print("DARK FANTASY GEOLOGY TEST PASS: actual rock, calcite, mineral and scan materials use continuous production projection; session preserved")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
