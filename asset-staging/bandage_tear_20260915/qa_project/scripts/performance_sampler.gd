extends RefCounted
## Read cached engine/renderer counters without images, force_draw or disk I/O.

const FRAME_BUDGET_MS := 1000.0 / 60.0
const PASS_NAMES := ["visible", "shadow", "canvas"]
const COUNTER_NAMES := ["objects", "primitives", "draw_calls"]
const DIMENSION_NAMES := ["width", "height", "logical_width", "logical_height", "render_3d_width", "render_3d_height"]
var viewports: Array[Viewport] = []
var samples: Array[Dictionary] = []


static func collect_viewports(node: Node) -> Array[Viewport]:
	var result: Array[Viewport] = []
	if node is Viewport:
		result.append(node)
	for child in node.get_children():
		result.append_array(collect_viewports(child))
	return result


static func physical_render_size(viewport: Viewport) -> Vector2i:
	# Measurement must also work in preserved baseline projects that do not
	# contain the production resolution-budget helper.
	if viewport is SubViewport:
		return (viewport as SubViewport).size
	return Vector2i((viewport.get_visible_rect().size * viewport.get_stretch_transform().get_scale()).round())


func begin(targets: Array[Viewport]) -> void:
	end()
	viewports = targets.duplicate()
	samples.clear()
	for viewport in viewports:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)


func end() -> void:
	for viewport in viewports:
		if is_instance_valid(viewport):
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)
	viewports.clear()


func record(wall_ms: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := {"wall_ms": wall_ms, "render_cpu_ms": RenderingServer.get_frame_setup_time_cpu(), "render_gpu_ms": 0.0, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), "buffer_memory_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED), "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "viewports": {}}
	for viewport in viewports:
		if not is_instance_valid(viewport):
			continue
		var rid := viewport.get_viewport_rid()
		# Disabled viewports retain their most recent timestamp. It belongs to
		# an old frame (for example a closed inventory portrait), not this one.
		var rendering: bool = not viewport is SubViewport or viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid) if rendering else 0.0
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid) if rendering else 0.0
		result.render_cpu_ms += cpu
		result.render_gpu_ms += gpu
		var size := physical_render_size(viewport)
		var counters: Dictionary = {"cpu_ms": cpu, "gpu_ms": gpu, "rendering": rendering, "width": size.x, "height": size.y, "logical_width": viewport.get_visible_rect().size.x, "logical_height": viewport.get_visible_rect().size.y, "render_3d_width": roundi(size.x * viewport.scaling_3d_scale), "render_3d_height": roundi(size.y * viewport.scaling_3d_scale), "draw_calls": 0, "primitives": 0, "objects": 0}
		# Godot separates visible geometry, shadow redraws and 2D canvas work.
		# Keep each pass as well as its sum so expensive shadow duplication is
		# distinguishable from the player's actual equipment geometry.
		for pass_index in PASS_NAMES.size():
			for counter_index in COUNTER_NAMES.size():
				var count: int = RenderingServer.viewport_get_render_info(rid, pass_index, counter_index) if rendering else 0
				var counter_name: String = COUNTER_NAMES[counter_index]
				counters[PASS_NAMES[pass_index] + "_" + counter_name] = count
				counters[counter_name] += count
		result.viewports[str(viewport.get_path())] = counters
	result["sampling_overhead_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	samples.append(result)
	return result


static func summarize_values(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	var missed := 0
	for value in ordered:
		total += value
		if value > FRAME_BUDGET_MS:
			missed += 1
	return {"count": ordered.size(), "mean": total / ordered.size(), "min": ordered[0], "p50": ordered[int(ceil(ordered.size() * 0.50)) - 1], "p95": ordered[int(ceil(ordered.size() * 0.95)) - 1], "p99": ordered[int(ceil(ordered.size() * 0.99)) - 1], "max": ordered[-1], "over_16_67ms_percent": float(missed) / ordered.size() * 100.0}


func summary() -> Dictionary:
	var result := {}
	if samples.is_empty():
		return result
	for key in samples[0]:
		if key == "viewports":
			continue
		var values: Array[float] = []
		for frame in samples:
			values.append(float(frame[key]))
		result[key] = summarize_values(values)
		if not str(key).ends_with("_ms"):
			result[key].erase("over_16_67ms_percent")
	result["viewports"] = {}
	for path in samples[0].viewports:
		var viewport_summary := {}
		for key in samples[0].viewports[path]:
			if key in DIMENSION_NAMES or key == "rendering":
				continue
			var values: Array[float] = []
			for frame in samples:
				if frame.viewports.has(path):
					values.append(float(frame.viewports[path][key]))
			viewport_summary[key] = summarize_values(values)
			if not str(key).ends_with("_ms"):
				viewport_summary[key].erase("over_16_67ms_percent")
		for key in DIMENSION_NAMES:
			viewport_summary[key] = samples[0].viewports[path][key]
		result.viewports[path] = viewport_summary
	return result
