extends SceneTree

const LAYOUT := preload("res://scripts/cave_layout.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := LAYOUT.source_data()
	_check(int(source.schema_version) == 2 and source.source_image.contains("f7c0e1e6"), "the runtime must read the latest reference-traced Blender plan")
	var authored := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../asset-staging/blender_abandoned_mine/layout.json"))
	_check(authored == FileAccess.get_file_as_string(LAYOUT.DATA_PATH), "Blender and Godot must use byte-identical authoritative geometry and gameplay data")
	_check(LAYOUT.rooms().size() == 18 and LAYOUT.corridors().size() == 31, "the reference plan must contain eighteen irregular chambers and thirty-one winding routes")
	_check(LAYOUT.pools().size() == 6 and LAYOUT.islands().size() == 7, "the plan must preserve the paired west pools, north lake, hoist reservoir, long lake and seven rock islands")
	var ids: Dictionary = {}
	var geologies: Dictionary = {}
	for room: Dictionary in LAYOUT.rooms():
		_check(not ids.has(room.id), "authored chamber ids must be unique")
		ids[room.id] = true
		geologies[room.geology] = true
		_check(room.polygon is PackedVector2Array and room.polygon.size() >= 16, "rooms must use traced irregular polygons, never nine circular placeholders")
		_check(Geometry2D.is_point_in_polygon(room.center, room.polygon), "the inspection entry must lie inside " + str(room.id))
		for point: Vector2 in room.polygon:
			_check(LAYOUT.bounds().has_point(point), "traced chamber points must stay within 131 by 139 metres")
	_check(geologies.size() == 4, "fractured limestone, flowstone, lava and mined faces must remain distinct geology zones")
	var reachable := {"entrance": true}
	for _pass in range(ids.size()):
		for link: Dictionary in LAYOUT.corridors():
			_check(ids.has(link.from) and ids.has(link.to), "each winding route must connect real chambers")
			if reachable.has(link.from) or reachable.has(link.to):
				reachable[link.from] = true
				reachable[link.to] = true
	_check(reachable.size() == ids.size(), "all eighteen rooms must remain reachable from the southern entry")
	var islands := LAYOUT.islands()
	for link: Dictionary in LAYOUT.corridors():
		var points := LAYOUT.corridor_points(link)
		_check(points.size() >= 3 and link.width >= 3.2 and link.width <= 6.0, "reference corridors must preserve multiple bends and measured walkable widths")
		for index in range(points.size() - 1):
			var steps := maxi(1, ceili(points[index].distance_to(points[index + 1])))
			for step in range(steps + 1):
				var point := points[index].lerp(points[index + 1], float(step) / steps)
				for island: Dictionary in islands:
					_check(not Geometry2D.is_point_in_polygon(point, island.polygon) and _edge_distance(point, island.polygon) >= 1.29, "routes must pass around the solid rock islands: " + str(link.id))
	for kind: String in ["enemies", "traps", "chests"]:
		var expected: int = {"enemies": 6, "traps": 4, "chests": 5}[kind]
		_check(LAYOUT.gameplay(kind).size() == expected, "the rebuilt mine must retain real encounter and loot counts")
		for placement: Dictionary in LAYOUT.gameplay(kind):
			var point := Vector2(placement.position.x, placement.position.z)
			_check(LAYOUT.room_id_at(point) == placement.room_id, "each authored gameplay placement must lie inside its named chamber: " + str(placement.id))
	var spawn := LAYOUT.spawn_position()
	var extraction := LAYOUT.extraction_position()
	_check(LAYOUT.room_id_at(Vector2(spawn.x, spawn.z)) == "entrance" and spawn.z > 60, "ordinary play must start at the southern mine entry")
	_check(LAYOUT.room_id_at(Vector2(extraction.x, extraction.z)) == "pillar_shrine" and extraction.x > 40 and extraction.z < -55, "extraction must move to the northeastern pillared shrine")
	source.rooms[0].title = "mutated test copy"
	_check(LAYOUT.rooms()[0].title != "mutated test copy", "caller changes must not mutate the shared authored plan")
	if failures.is_empty():
		print("CAVE LAYOUT TEST PASS: byte-identical Blender/Godot plan, eighteen polygons, thirty-one connected bent routes, six water surfaces, seven islands and authored real gameplay placements")
		quit(0)
	else:
		for failure in failures:
			push_error("CAVE LAYOUT TEST FAIL: " + failure)
		quit(1)

func _edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var distance := INF
	for index in range(polygon.size()):
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])))
	return distance

func _check(ok: bool, detail: String) -> void:
	if not ok and not failures.has(detail):
		failures.append(detail)
