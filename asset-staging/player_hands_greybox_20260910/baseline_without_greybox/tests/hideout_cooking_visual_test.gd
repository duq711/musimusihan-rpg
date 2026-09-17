extends SceneTree

const EQUIPMENT := preload("res://scripts/hideout_cooking_visual.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var equipment := EQUIPMENT.new()
	var tools := equipment.get_node("CookingTools") as Node3D
	var pot := tools.get_node("SoupPot") as Node3D
	var steam := tools.get_node("CookingSteam") as Node3D
	_check(equipment.find_child("ForgedCookingTripod", true, false) != null and equipment.find_child("CookingKnife", true, false) != null, "Permanent tripod and preparation tools must be built even outside the scene tree")
	_check(equipment.find_child("CookingPot", true, false).has_node("HollowVesselBody") and equipment.find_child("SingleCup", true, false).has_node("HollowVesselBody"), "Cooking vessels must retain actual open shell geometry")
	_check(tools.visible and pot.visible and not steam.visible and not pot.get_node("SoupSurface").visible, "Idle equipment must remain available without fabricated food or steam")
	var child_count := equipment.get_child_count()
	equipment.ensure_built()
	_check(child_count == equipment.get_child_count(), "Repeated initialization must not duplicate equipment")
	equipment.set_cooking("cook:mushroom_soup", 0.4, true)
	_check(pot.get_node("MushroomSlices").visible and not pot.get_node("StewMorsels").visible and steam.visible, "Soup animation must display the actual selected recipe")
	var spoon := pot.get_node("StirringSpoon") as Node3D
	var spoon_at := spoon.transform
	var steam_at := (steam.get_node("SteamPuff0") as Node3D).transform
	equipment.set_cooking("mushroom_soup", 0.4, true)
	_check(spoon_at == spoon.transform and steam_at == (steam.get_node("SteamPuff0") as Node3D).transform, "Identical progress must preserve animation while paused")
	equipment.set_cooking("trail_stew", 0.7, true)
	_check(pot.get_node("StewMorsels").visible and not pot.get_node("MushroomSlices").visible, "Changing recipe must replace stale soup ingredients")
	equipment.set_cooking("roast_meat", 0.15, true)
	var spit := tools.get_node("RoastingSpit") as Node3D
	var skewer := spit.get_node("SpitSkewer") as Node3D
	var meat := skewer.get_node("MeatChunk0") as MeshInstance3D
	var early_rotation := skewer.rotation
	var early_color := (meat.material_override as StandardMaterial3D).albedo_color
	_check(spit.visible and pot.visible and pot.position.x > 0.7 and not pot.get_node("SoupSurface").visible, "Roasting must use the real spit and safely park the empty cauldron on its rest")
	equipment.set_cooking("roast_meat", 0.85, true)
	_check(early_rotation != skewer.rotation and early_color != (meat.material_override as StandardMaterial3D).albedo_color, "Real cooking progress must rotate the spit and brown its food")
	equipment.set_cooking("", 0.0, false)
	_check(pot.visible and pot.position == Vector3.ZERO and not spit.visible and not steam.visible and not pot.get_node("StewMorsels").visible, "Completion or interruption must restore the empty suspended pot and clear all food effects")
	equipment.set_cooking("invalid_recipe", NAN, true)
	_check(not equipment.get_meta("cooking_active") and equipment.get_meta("progress") == 0.0 and not steam.visible, "Unknown recipes and invalid progress must leave stable idle equipment")
	_check(ExpeditionSession.capture_snapshot() == session and Input.mouse_mode == mouse_mode, "Visual construction and animations must not mutate the session or capture input")
	equipment.free()
	for frame in 8:
		await process_frame
	if failures.is_empty():
		print("HIDEOUT COOKING VISUAL TEST PASS: permanent equipment, hollow vessels, shared recipe visuals, deterministic progress and cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT COOKING VISUAL TEST FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
