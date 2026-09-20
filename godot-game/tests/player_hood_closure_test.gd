extends SceneTree
## Inspect the imported game mesh where the front/rear mantle previously had gaps.
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := APPEARANCE.create_body()
	root.add_child(body)
	var mantle := body.find_child("Gravebound_MantleBack", true, false) as MeshInstance3D
	if mantle == null or mantle.mesh == null:
		failures.append("Imported shoulder mantle missing")
	else:
		for side: float in [-1.0, 1.0]:
			for sample: Vector2 in [Vector2(.15, -.06), Vector2(.20, -.065), Vector2(.225, -.055)]:
				var origin := Vector3(side * sample.x, 1.7, sample.y)
				var end := Vector3(origin.x, 1.39, origin.z)
				if not _cloth_covers(body, mantle, origin, end):
					failures.append("Open shoulder at " + str(origin))
	body.free()
	for failure in failures:
		push_error(failure)
	print("PLAYER HOOD CLOSURE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _cloth_covers(body: Node3D, part: MeshInstance3D, origin: Vector3, end: Vector3) -> bool:
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0, count, 3):
			var triangle: Array[Vector3] = []
			for corner in 3:
				var vertex_index := indices[index + corner] if not indices.is_empty() else index + corner
				triangle.append(body.to_local(part.to_global(vertices[vertex_index])))
			# Scale-aware vertical intersection for the finely tessellated cloth.
			var a := triangle[0]
			var e := triangle[1] - a
			var f := triangle[2] - a
			var determinant := e.x * f.z - e.z * f.x
			if abs(determinant) < 1e-12:
				continue
			var u := ((origin.x - a.x) * f.z - (origin.z - a.z) * f.x) / determinant
			var v := (e.x * (origin.z - a.z) - e.z * (origin.x - a.x)) / determinant
			if u >= 0.0 and v >= 0.0 and u + v <= 1.0:
				var height := a.y + u * e.y + v * f.y
				if height >= end.y and height <= origin.y:
					return true
	return false
