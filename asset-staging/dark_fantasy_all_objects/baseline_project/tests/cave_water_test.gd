extends SceneTree

const WATER := preload("res://scripts/cave_water.gd")
const GEOMETRY := preload("res://scripts/cave_geometry.gd")
const LAYOUT := preload("res://scripts/cave_layout.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var geometry: Node3D = GEOMETRY.new()
	root.add_child(geometry)
	geometry.set_process(false)
	geometry._read_samples()
	var water: Node3D = WATER.new()
	geometry.add_child(water)
	water.set_physics_process(false)
	water.build(geometry)
	_check(water.pools.size() == 6 and water.surfaces.size() == 6, "all six authored pools must get actual live surfaces")
	var vertex_total := 0
	for index in water.pools.size():
		var pool: Dictionary = water.pools[index]
		var source: Dictionary = LAYOUT.pools()[index]
		_check(pool.id == source.id and pool.surface_y == source.surface_y and pool.polygon == source.polygon, "authored pool locations/heights/source polygons must remain intact")
		_check(pool.shore.size() == source.polygon.size() * 8, "shoreline geometry must actually round the original corners")
		var maximum_turn := 0.0
		for i in pool.shore.size():
			var incoming: Vector2 = pool.shore[i] - pool.shore[posmod(i - 1, pool.shore.size())]
			var outgoing: Vector2 = pool.shore[(i + 1) % pool.shore.size()] - pool.shore[i]
			maximum_turn = maxf(maximum_turn, absf(incoming.angle_to(outgoing)))
		_check(maximum_turn < 0.55, "rounded water must not retain the metre-long sharp traced corners: " + str(pool.id))
		var surface: MeshInstance3D = water.surfaces[index]
		var arrays: Array = surface.mesh.surface_get_arrays(0)
		vertex_total += arrays[Mesh.ARRAY_VERTEX].size()
		_check(arrays[Mesh.ARRAY_VERTEX].size() > 100 and arrays[Mesh.ARRAY_TEX_UV2].size() == arrays[Mesh.ARRAY_VERTEX].size(), "dense live mesh must carry shoreline-distance and terrain-depth data")
		_check(surface.material_override is ShaderMaterial and surface.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "live water must use its physical surface shader without casting a solid slab shadow")
	_check(vertex_total < 25000, "six live pool meshes must stay within the bounded subdivision budget")
	var feet := Vector3(-54.3, geometry.floor_height(Vector2(-54.3, -18.0)), -18.0)
	var sample: Dictionary = water.sample_surface(feet)
	_check(sample.get("id") == "lower_west_water" and float(sample.get("depth", 0)) > 0.08, "walkable test path must touch actual measured pool water")
	_check(water.sample_surface(Vector3(-58.08, 0, -18.4)).is_empty(), "dry western approach must not count as water")
	_check(water.sample_surface(Vector3(11.5, 0, -47.0)).is_empty(), "solid islands must be excluded from water membership")
	water.advance_contact(0.1, feet + Vector3.UP * 2, Vector3.ZERO, false)
	_check(water.total_ripples == 0, "standing above water or flying over it must not cause footsteps")
	water.advance_contact(0.1, feet, Vector3(0, -2, 0), false)
	_check(water.total_ripples == 1 and water.last_event == "enter", "feet physically entering water must produce one entry ripple")
	water.advance_contact(0.1, feet, Vector3.ZERO, true)
	_check(water.total_ripples == 2 and water.last_event == "land", "landing in water must produce a grounded contact ripple")
	var stopped_count: int = water.total_ripples
	for i in 30:
		water.advance_contact(1.0 / 60.0, feet, Vector3.ZERO, true)
	_check(water.total_ripples == stopped_count, "stopping must not create endless new ripples")
	for i in 16:
		feet.z += 0.08
		water.advance_contact(0.02, feet, Vector3(0, 4, 4), true)
	_check(water.total_ripples >= stopped_count + 2 and water.last_event == "walk", "actual horizontal travel with grounded feet must generate spaced walking ripples")
	var walked_count: int = water.total_ripples
	for i in 10:
		feet.z += 0.12
		water.advance_contact(0.02, feet, Vector3(0, 0, 6), true)
	_check(water.total_ripples > walked_count and water.last_event == "run", "running must generate stronger steps through the same contact path")
	water.advance_contact(0.02, feet, Vector3(0, 4, 1), false)
	_check(water.last_event == "jump", "jumping out of water must leave one takeoff ripple")
	var jump_count: int = water.total_ripples
	for i in 10:
		water.advance_contact(0.02, feet + Vector3.UP, Vector3(0, 1, 1), false)
	_check(water.total_ripples == jump_count, "airborne movement must not continue wet footsteps")
	water.advance_contact(0.1, feet, Vector3(0, -4, 0), true)
	_check(water.total_ripples > jump_count, "landing back in the pool must resume water contact")
	for i in 80:
		water.advance_contact(0.01, Vector3(-58.08, 0, -18.4), Vector3.ZERO, true)
		water.advance_contact(0.01, feet, Vector3.ZERO, true)
	_check(water.get_ripple_events().size() == WATER.MAX_RIPPLES and int(water.get_state_snapshot().ripple_count) <= WATER.MAX_RIPPLES, "many contacts must overwrite a fixed-size ripple buffer, not grow scene nodes or shader arrays")
	var events: PackedVector4Array = water.get_ripple_events()
	events[0] = Vector4.ZERO
	_check(water.get_ripple_events()[0] != Vector4.ZERO, "QA snapshots must not mutate production ring-buffer events")
	var shader_material := water.surfaces[0].material_override as ShaderMaterial
	_check(shader_material.get_shader_parameter("ripple_events") == water.get_ripple_events(), "real shader uniforms must contain the actual foot-contact ring buffer")
	var clock_before: float = water.get_state_snapshot().clock
	paused = true
	water.advance_contact(2.0, feet, Vector3.ZERO, true)
	_check(water.get_state_snapshot().clock == clock_before, "pause/test/inventory menus must freeze water and ripple decay")
	paused = false
	water.advance_contact(5.0, Vector3.ZERO, Vector3.ZERO, false, false)
	_check(water.get_state_snapshot().ripple_count == 0, "old ripples must expire while ambient water remains")
	var actor := CharacterBody3D.new()
	geometry.add_child(actor)
	water.bind_player(actor)
	_check(water.player == actor, "the water system must accept the actual CharacterBody player binding")
	var weak_water: WeakRef = weakref(water)
	geometry.queue_free()
	await process_frame
	_check(weak_water.get_ref() == null, "scene exit must remove the contact tracker and all live water surfaces")
	_check(ExpeditionSession.capture_snapshot() == original, "water presentation and contacts must not mutate the original expedition")
	if failures.is_empty():
		print("CAVE WATER TEST PASS: six rounded terrain-aware pools, islands/dry banks, feet entry/walk/run/stop/jump/landing, fixed GPU ring buffer, shader binding, expiry/pause and cleanup; vertices=" + str(vertex_total))
		quit(0)
	else:
		for failure in failures:
			push_error("CAVE WATER TEST FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
