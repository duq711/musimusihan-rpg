extends SceneTree

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_inventory := ExpeditionSession.get_inventory()
	var original_mouse_mode := Input.mouse_mode
	var oak := SURFACES.old_oak()
	var iron := SURFACES.pitted_iron()
	_check(oak.albedo_texture == SURFACES.OAK, "Oak keeps its authored albedo texture")
	_check(iron.albedo_texture == SURFACES.IRON, "Iron keeps its authored albedo texture")
	_check(iron.metallic > 0.6 and iron.roughness > 0.6, "Forged iron remains rough metal")
	for family in SURFACES.FAMILIES:
		var material := SURFACES.create(family, Color(0.3, 0.28, 0.24))
		_check(material.get_meta("dark_fantasy_surface", "") == family, "Material identifies its production surface family")
		_check(material.normal_enabled and material.normal_texture != null, "Missing microsurface normal is supplied for %s" % family)
		_check(material.roughness_texture != null, "Roughness variation exists for %s" % family)
		_check(material.uv1_triplanar and material.texture_repeat, "Generated primitives use seamless triplanar detail")
		var repeated := SURFACES.create(family, Color.WHITE)
		_check(material.normal_texture == repeated.normal_texture, "Instances share their normal map for %s" % family)
		_check(material.roughness_texture == repeated.roughness_texture, "Instances share their roughness map for %s" % family)
	var authored := StandardMaterial3D.new()
	authored.albedo_texture = SURFACES.OAK
	authored.normal_texture = SURFACES.IRON
	authored.roughness_texture = SURFACES.STONE
	authored.uv1_scale = Vector3(0.4, 0.6, 0.8)
	SURFACES.tune(authored, "oak")
	_check(authored.albedo_texture == SURFACES.OAK and authored.normal_texture == SURFACES.IRON and authored.roughness_texture == SURFACES.STONE, "Tuning must preserve every authored texture channel")
	_check(authored.uv1_scale == Vector3(0.4, 0.6, 0.8), "Tuning preserves authored UV scale")
	_check(ExpeditionSession.get_inventory() == original_inventory and Input.mouse_mode == original_mouse_mode, "Material creation leaves session and input untouched")
	# Let the shared noise workers finish before the test releases resources.
	for frame in 12:
		await process_frame
	if failures.is_empty():
		print("DARK FANTASY MATERIALS TEST PASS: shared aged surfaces, authored maps and session safety")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY MATERIALS TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
