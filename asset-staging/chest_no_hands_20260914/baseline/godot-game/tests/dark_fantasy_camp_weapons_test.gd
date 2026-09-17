extends SceneTree

const CAMP := preload("res://scripts/camp_visuals.gd")
const BOW := preload("res://scripts/archery_visuals.gd")
const FLAIL := preload("res://scripts/flail_visuals.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.ensure_journey()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var camp := CAMP.create_camp()
	var bed := camp.get_node("Bedroll") as MeshInstance3D
	_check(bed.mesh is ArrayMesh, "Bedroll uses closed folded cloth geometry")
	_check(bed.has_node("BedrollEdgeStitches") and bed.has_node("BedrollLeatherCarryingStrap"), "Production bedroll includes stitched edging and leather carrying strap")
	_check((bed.get_node("BedrollEdgeStitches") as MultiMeshInstance3D).multimesh.instance_count == 60, "Sixty real stitches share one draw")
	var edges: Dictionary = {}
	var vertices: PackedVector3Array = bed.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 3):
		for side in 3:
			var a := vertices[index + side].snapped(Vector3.ONE * 0.000001)
			var b := vertices[index + (side + 1) % 3].snapped(Vector3.ONE * 0.000001)
			var key := str(a) + ":" + str(b) if str(a) < str(b) else str(b) + ":" + str(a)
			edges[key] = int(edges.get(key, 0)) + 1
	for edge_count in edges.values():
		_check(edge_count == 2, "Cloth top, underside and seams form a closed surface")
	for index in 9:
		_check((camp.get_node("FireRingStone%d" % index) as MeshInstance3D).mesh is ArrayMesh, "Every fire-ring stone has irregular physical geometry")
	CAMP.animate(camp, 1.25, 3)
	_check((camp.get_node("Flame") as Node3D).scale.is_finite(), "Campfire animation retains finite live transforms")
	CAMP.set_cooking(camp, "mushroom_soup", 0.6, true)
	_check((camp.get_node("CookingTools/SoupPot") as Node3D).visible, "Production cooking remains connected after art changes")
	var pot := camp.get_node("CookingTools/SoupPot") as Node3D
	_check((pot.get_node("MushroomSlices") as Node3D).visible and not (pot.get_node("StewMorsels") as Node3D).visible, "Mushroom slices follow actual soup recipe")
	for slice in pot.get_node("MushroomSlices").get_children():
		_check(Vector2(slice.position.x, slice.position.z).length() + 0.025 <= 0.207, "Sliced food stays inside the pot rim")
	CAMP.set_cooking(camp, "trail_stew", 0.6, true)
	_check(not (pot.get_node("MushroomSlices") as Node3D).visible and (pot.get_node("StewMorsels") as Node3D).visible, "Stew morsels switch with actual recipe without changing cooking progress")
	var bow := BOW.create_bow()
	BOW.set_bow_draw(bow, 1.0)
	_check(((bow.get_node("NockedArrow") as Node3D).position + BOW.ARROW_NOCK_LOCAL).distance_to(BOW.bow_hand_anchors(bow).string) < 0.00001, "Full draw keeps the real nock at the string and draw-hand contact")
	var tip := bow.get_node("Tip_1") as Node3D
	_check(tip.get_child_count() == 3, "Horn-nock bindings follow each live bow tip")
	var flail := FLAIL.create_flail()
	_check(flail.has_node("ExposedOakHandle") and flail.has_node("LeatherHandle"), "Flail combines exposed oak with existing functional leather grip")
	var destination := Vector3(0.3, 0.5, -1.2)
	FLAIL.set_head_position(flail, destination)
	_check((flail.get_node("Head") as Node3D).position == destination and (flail.get_node("Chain/End") as Node3D).position == destination, "Forged head and real chain still share the live endpoint")
	_check((flail.get_node("Head/IronBall") as MeshInstance3D).material_override.get_meta("dark_fantasy_surface", "") == "iron", "Production flail head shares aged iron response")
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse_mode, "Art factories and animation leave expedition/input untouched")
	camp.free()
	bow.free()
	flail.free()
	for frame in 12:
		await process_frame
	if failures.is_empty():
		print("DARK FANTASY CAMP WEAPONS TEST PASS: closed folded bedroll, irregular stone ring, live bow/flail/cooking and session safety")
		quit(0)
	else:
		for failure in failures:
			push_error("DARK FANTASY CAMP WEAPONS TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
