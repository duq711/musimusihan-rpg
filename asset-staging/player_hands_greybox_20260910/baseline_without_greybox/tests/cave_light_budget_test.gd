extends SceneTree
const GEOMETRY := preload("res://scripts/cave_geometry.gd")
const BUDGET := preload("res://scripts/cave_light_budget.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var world: Node3D = GEOMETRY.new()
	root.add_child(world)
	world.set_process(false)
	world._add_lantern_light({"position": [1.0, 2.0, 3.0], "energy": 2.5, "range": 7.4})
	var light: OmniLight3D = world.torch_lights[0]
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.global_position = light.global_position + Vector3(0, 0, 9.99)
	_check(light.shadow_enabled and light.distance_fade_shadow == 10.0, "nearby authored lamps retain full shadows to ten metres")
	_check(light.light_color == Color(1.0, 0.73, 0.40) and is_equal_approx(light.omni_range, 7.4) and is_equal_approx(light.light_energy, 2.5 * 1.35), "the actual production lamp retains authored range, color and base radiance")
	_check(light.distance_fade_begin == 24.0 and light.distance_fade_length == 10.0 and is_equal_approx(light.light_size, 0.08) and is_equal_approx(light.omni_attenuation, 1.6), "only distant shadows change; light geometry and light fade remain original")
	world._process(0.125)
	_check(is_equal_approx(light.light_energy, _original_energy(2.5 * 1.35, 0.125, 0)), "near flicker preserves the exact original phase formula")
	camera.global_position = light.global_position + Vector3(0, 0, 33.9)
	_check(BUDGET.needs_flicker_update(light, camera), "fading light continues updating through its complete visible range")
	camera.global_position = light.global_position + Vector3(0, 0, 34.1)
	var last_energy := light.light_energy
	for i in range(20):
		world._process(0.2)
	_check(light.light_energy == last_energy and is_equal_approx(world._clock, 4.125), "invisible lamps stop uniform updates while their shared phase clock advances")
	camera.global_position = light.global_position + Vector3(0, 0, 5.0)
	world._process(0.25)
	_check(is_equal_approx(light.light_energy, _original_energy(2.5 * 1.35, 4.375, 0)), "returning to a lamp resumes the phase it would have reached without skipped updates")
	world.set_process(true)
	paused = true
	var clock_before: float = world._clock
	await create_timer(0.03, true).timeout
	_check(world._clock == clock_before, "pausing the real scene freezes flicker phase as before")
	world.set_process(false)
	paused = false
	_check(BUDGET.needs_flicker_update(light, null), "worlds without a camera retain the original unconditional updates")
	var survey := OmniLight3D.new()
	survey.distance_fade_enabled = true
	survey.distance_fade_begin = 24
	survey.distance_fade_length = 8
	BUDGET.configure(survey)
	_check(survey.distance_fade_shadow == 10.0 and survey.distance_fade_length == 8.0, "working-face lamps share near-shadow distance while keeping their own fade length")
	survey.free()
	world.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse, "lamp budgeting preserves expedition and input state")
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("CAVE LIGHT BUDGET PASS: actual authored lamp retains range, radiance, ten-metre near shadows, original flicker, far update retirement, seamless phase return, pause and expedition isolation")
	quit(0 if failures.is_empty() else 1)


func _original_energy(base: float, clock: float, index: int) -> float:
	return base * (0.98 + sin(clock * 6.1 + index * 1.7) * 0.018 + sin(clock * 9.3 + index) * 0.01)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
