extends SceneTree
const ART := preload("res://scripts/mine_prop_concept_visual.gd")
const SOURCE := preload("res://assets/3d/abandoned_mine/abandoned_mine.glb")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var mine := SOURCE.instantiate() as Node3D
	var originals: Dictionary = {}
	for visual: MeshInstance3D in mine.find_children("*", "MeshInstance3D", true, false):
		originals[visual] = {"mesh":visual.mesh,"transform":visual.transform}
	ART.apply(mine)
	var changed := 0
	for visual: MeshInstance3D in originals:
		_check(visual.mesh == originals[visual].mesh and visual.transform == originals[visual].transform,"Imported assembly geometry remains exact")
		if not visual.has_meta("mine_prop_concept"): continue
		changed += 1
		for surface in visual.mesh.get_surface_count():
			var source := visual.mesh.surface_get_material(surface) as StandardMaterial3D
			var material := visual.get_surface_override_material(surface) as ShaderMaterial
			if material == null: continue
			_check(material.get_shader_parameter("albedo_map") == source.albedo_texture,"Authored albedo is preserved")
			if source.normal_texture:
				_check(material.get_shader_parameter("normal_map") == source.normal_texture,"Authored normal is preserved")
			if source.roughness_texture:
				_check(material.get_shader_parameter("roughness_map") == source.roughness_texture,"Authored roughness is preserved")
	_check(changed > 100,"Named mine prop assemblies receive material refinement")
	var count := mine.find_children("*", "MeshInstance3D", true, false).size()
	ART.apply(mine)
	_check(mine.find_children("*", "MeshInstance3D", true, false).size() == count,"Repeated application cannot duplicate props")
	var manifest := JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_direction/object_inventory.json")) as Dictionary
	var covered := 0
	var covered_assemblies: Dictionary = {}
	for entry: Dictionary in manifest.entries:
		if entry.category != "mine_prop": continue
		for assembly_name in entry.variant_coverage:
			_check(not covered_assemblies.has(str(assembly_name)), "Different prop archetypes must not accidentally select the same imported assembly: " + str(assembly_name))
			covered_assemblies[str(assembly_name)] = str(entry.id)
		var assembly := mine.find_child(str(entry.node_name),true,false)
		_check(assembly != null,"Mine prop archetype source exists: " + str(entry.id))
		var has_surface := assembly is MeshInstance3D and assembly.has_meta("mine_prop_concept")
		for part in assembly.find_children("*","MeshInstance3D",true,false):
			if part.has_meta("mine_prop_concept"): has_surface = true
		_check(has_surface,"Every mine prop archetype receives real production surfaces: " + str(entry.id))
		covered += 1
	_check(covered == 36,"All 36 inventoried mine prop archetypes covered")
	mine.free()
	_check(Input.mouse_mode == mouse and ExpeditionSession.capture_snapshot() == snapshot,"Art pass never changes input or expedition")
	if failures.is_empty():
		print("MINE PROP CONCEPT PASS: 36 archetypes, ",changed," mesh surfaces, exact geometry/UV/authored maps, idempotent/state safe")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
