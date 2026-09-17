extends SceneTree

const SAMPLER := preload("res://scripts/performance_sampler.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dormant := SubViewport.new()
	dormant.name = "ClosedPortrait"
	dormant.size = Vector2i(472, 560)
	dormant.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(dormant)
	var sampler := SAMPLER.new()
	sampler.begin(SAMPLER.collect_viewports(root))
	var sample := sampler.record(17.0)
	var path := str(dormant.get_path())
	var counters: Dictionary = sample.viewports[path]
	check(not counters.rendering, "closed portrait must be explicitly recorded as disabled")
	for key in counters:
		if key not in ["width", "height", "rendering"]:
			check(counters[key] == 0, "disabled portrait must not contribute stale counter " + key)
	check(counters.width == 472 and counters.height == 560, "disabled viewport identity and dimensions remain available")
	var summary := sampler.summary()
	check(summary.wall_ms.over_16_67ms_percent == 100.0, "frame-time budget must count slow measured frames")
	check(not summary.draw_calls.has("over_16_67ms_percent"), "render counts must not be compared to a millisecond budget")
	check(summary.viewports[path].visible_draw_calls.p50 == 0, "summary preserves separate visible, shadow and canvas counters")
	sampler.begin([dormant])
	check(sampler.samples.is_empty() and sampler.viewports.size() == 1, "reopening measurement clears prior samples and replaces the measured viewports")
	sampler.end()
	check(sampler.viewports.is_empty(), "closing measurement releases all timestamp collection targets")
	dormant.free()
	if failures.is_empty():
		print("PERFORMANCE SAMPLER PASS: disabled viewport exclusion, render-pass counter structure and measurement cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
