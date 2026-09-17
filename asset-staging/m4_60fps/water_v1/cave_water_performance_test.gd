extends SceneTree

const WATER := preload("res://scripts/cave_water.gd")
const GEOMETRY := preload("res://scripts/cave_geometry.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var geometry: Node3D = GEOMETRY.new()
	root.add_child(geometry)
	geometry.set_process(false)
	geometry._read_samples()
	var water: Node3D = WATER.new()
	geometry.add_child(water)
	water.set_physics_process(false)
	water.build(geometry)
	var second: Node3D = WATER.new()
	geometry.add_child(second)
	second.set_physics_process(false)
	second.build(geometry)
	var material := water.surfaces[0].material_override as ShaderMaterial
	_check(water.surfaces.size() == 6, "the optimization retains all six actual water surfaces")
	for surface: MeshInstance3D in water.surfaces:
		_check(surface.material_override == material, "identical world-space pool uniforms share one system-owned material")
	_check(second.surfaces[0].material_override != material, "independent water systems must never share mutable clocks or events")
	_check(int(material.get_shader_parameter("active_ripple_count")) == 0, "dry stationary scenes submit no ripple loop iterations")
	_check(material.shader.code.contains("i < active_ripple_count"), "the actual production shader must use the bounded active loop")
	_check(water.get_ripple_events().size() == 24, "the gameplay event ring remains at its original 24-event capacity")

	var dry := Vector3(-58.08, 0.0, -18.4)
	var feet := Vector3(-54.3, geometry.floor_height(Vector2(-54.3, -18.0)), -18.0)
	water.advance_contact(0.1, dry, Vector3.ZERO, true)
	water.advance_contact(0.1, feet, Vector3.ZERO, true)
	_check(water.total_ripples == 1 and water.last_event == "enter", "a real wet contact still creates the original entry event")
	_check_render_submission(water)
	_check(int(material.get_shader_parameter("active_ripple_count")) == 1, "a single contact renders only its one active event")
	_check(int(second.surfaces[0].material_override.get_shader_parameter("active_ripple_count")) == 0, "wet contact does not leak into another water system")
	var resting_events: PackedVector4Array = water.get_ripple_events()
	var resting_uniform: PackedVector4Array = material.get_shader_parameter("ripple_events")
	water.advance_contact(0.2, feet, Vector3.ZERO, true)
	_check(water.get_ripple_events() == resting_events and material.get_shader_parameter("ripple_events") == resting_uniform, "resting advances the shared clock without changing contact events")
	for index in range(40):
		water.advance_contact(0.01, dry, Vector3.ZERO, true)
		water.advance_contact(0.01, feet, Vector3.ZERO, true)
	_check(water.total_ripples == 41 and water.get_ripple_events().size() == 24, "repeated physical contacts wrap the original bounded ring")
	_check_render_submission(water)
	_check(int(material.get_shader_parameter("active_ripple_count")) == 24, "all live events remain visible when the complete ring is active")
	var full_ring: PackedVector4Array = water.get_ripple_events()
	var before_pause: Dictionary = water.get_state_snapshot()
	paused = true
	water.advance_contact(2.0, feet, Vector3.ZERO, true)
	_check(water.get_state_snapshot() == before_pause, "paused tests freeze both event lifetime and the water clock")
	paused = false
	water.advance_contact(5.0, Vector3.ZERO, Vector3.ZERO, false, false)
	_check(water.get_ripple_events() == full_ring, "expiry removes only rendering work and preserves the public contact history")
	_check(int(material.get_shader_parameter("active_ripple_count")) == 0, "expired contacts return the real shader to a zero-iteration ripple loop")
	_check(water.get_state_snapshot().ripple_count == 0, "render expiry follows the existing gameplay lifetime")
	_check_render_submission(water)
	geometry.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse, "water optimization preserves expedition and cursor state")
	if failures.is_empty():
		print("CAVE WATER PERFORMANCE PASS: one material per six pools, zero idle/expired ripple iterations, all live ring events and ring order preserved, 24-event wrap, independent worlds, pause and state isolation")
		quit(0)
	else:
		for message: String in failures:
			push_error(message)
		quit(1)

func _check_render_submission(water: Node3D) -> void:
	var material := water.surfaces[0].material_override as ShaderMaterial
	var count := int(material.get_shader_parameter("active_ripple_count"))
	var upload: PackedVector4Array = material.get_shader_parameter("ripple_events")
	var events: PackedVector4Array = water.get_ripple_events()
	var shader_clock := float(PackedFloat32Array([water.get_state_snapshot().clock])[0])
	_check(count >= 0 and count <= 24 and upload.size() == 24, "the shader submission has bounded capacity and count")
	var last_source_index := -1
	for index in range(count):
		var source_index := events.find(upload[index], last_source_index + 1)
		_check(source_index > last_source_index, "rendered contacts remain exact original-ring events in their original summation order")
		last_source_index = source_index
	for event: Vector4 in events:
		var age := shader_clock - event.z
		if event.w > 0.0 and age >= 0.0 and age < 4.2:
			_check(upload.slice(0, count).has(event), "every visible original contact wave must survive active submission")
	for surface: MeshInstance3D in water.surfaces:
		_check(surface.material_override.get_shader_parameter("water_clock") == material.get_shader_parameter("water_clock"), "all six pools remain on the same production clock")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
