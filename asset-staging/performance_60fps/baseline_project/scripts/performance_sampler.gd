extends RefCounted
## Read cached engine/renderer counters without images, force_draw or disk I/O.

const FRAME_BUDGET_MS := 1000.0 / 60.0
var viewports: Array[Viewport] = []
var samples: Array[Dictionary] = []


static func collect_viewports(node: Node) -> Array[Viewport]:
	var result: Array[Viewport] = []
	if node is Viewport:
		result.append(node)
	for child in node.get_children():
		result.append_array(collect_viewports(child))
	return result


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
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		result.render_cpu_ms += cpu
		result.render_gpu_ms += gpu
		result.viewports[str(viewport.get_path())] = {"cpu_ms": cpu, "gpu_ms": gpu, "width": viewport.get_visible_rect().size.x, "height": viewport.get_visible_rect().size.y}
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
	result["viewports"] = {}
	for path in samples[0].viewports:
		var viewport_summary := {}
		for key in ["cpu_ms", "gpu_ms"]:
			var values: Array[float] = []
			for frame in samples:
				if frame.viewports.has(path):
					values.append(float(frame.viewports[path][key]))
			viewport_summary[key] = summarize_values(values)
		viewport_summary["width"] = samples[0].viewports[path].width
		viewport_summary["height"] = samples[0].viewports[path].height
		result.viewports[path] = viewport_summary
	return result
