extends Node3D
class_name HideoutCookingVisual

const HEARTH := preload("res://scripts/dark_fantasy_hearth_visual.gd")
const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const CAMP := preload("res://scripts/camp_visuals.gd")
const TOOL_SCALE := 1.8
const TOOL_BASE_Y := 0.15
const REST_POSITION := Vector3(1.44, 0.045, -0.26)

var _built := false
var _tools: Node3D
var _pot: Node3D
var _chain: Node3D


func _init() -> void:
	name = "HearthCookingEquipment"
	ensure_built()
	set_cooking("", 0.0, false)


func ensure_built() -> void:
	if _built:
		return
	_built = true
	var iron := SURFACES.pitted_iron(Color(0.25, 0.26, 0.25), 4.0)
	var black_iron := SURFACES.pitted_iron(Color(0.15, 0.16, 0.155), 4.0)
	black_iron.metallic_specular = 0.20
	var wood := SURFACES.old_oak(Color(0.44, 0.37, 0.27), 3.0)
	_build_tripod(iron)
	_build_preparation_bench(wood, iron, black_iron)
	# CampVisuals owns food, stirring, browning and steam, so all kitchens use
	# the same recipe animation and the real activity's progress clock.
	_tools = CAMP._create_cooking_tools(self)
	_tools.scale = Vector3.ONE * TOOL_SCALE
	_tools.position.y = TOOL_BASE_Y
	_pot = _tools.get_node("SoupPot") as Node3D
	for child in _pot.get_children():
		if String(child.name).begins_with("PotStand") or String(child.name).begins_with("PotHandle"):
			(child as Node3D).visible = false
	for old_name in ["CookingPot", "PotRim"]:
		var old := _pot.get_node(old_name)
		_pot.remove_child(old)
		old.free()
	# The vessel is hollow, including an inward-facing wall and closed floor.
	# Its opening surrounds the shared camp soup surface without capping it.
	var vessel := HEARTH.create_vessel(0.28, 0.25, black_iron, true)
	vessel.name = "CookingPot"
	vessel.position.y = 0.41
	_pot.add_child(vessel)
	HEARTH.add_pot_bail(vessel, 0.28, 0.25, iron)
	# The skewer supports are forged iron here, suitable for a permanent hearth.
	var spit := _tools.get_node("RoastingSpit") as Node3D
	for child in spit.get_children():
		if child is MeshInstance3D:
			child.material_override = iron
	set_meta("permanent_cooking_equipment", true)


func set_cooking(recipe_id: String, progress: float, active: bool) -> void:
	ensure_built()
	var recipe := recipe_id.trim_prefix("cook:")
	var cooking := active and recipe in ["roast_meat", "mushroom_soup", "trail_stew"]
	var amount := clampf(progress, 0.0, 1.0) if is_finite(progress) else 0.0
	CAMP.set_cooking(self, recipe, amount, cooking)
	# Unlike a portable camp, the hideout keeps its utensils available between
	# meals. Only ingredients, bubbles, steam and the loaded skewer are transient.
	_tools.visible = true
	_pot.visible = true
	var roasting := cooking and recipe == "roast_meat"
	var soup := cooking and not roasting
	_pot.position = REST_POSITION / TOOL_SCALE if roasting else Vector3.ZERO
	_chain.visible = not roasting
	(_tools.get_node("CookingSteam") as Node3D).visible = cooking
	for child in _pot.get_children():
		var title := String(child.name)
		if title == "SoupSurface" or title == "SoupHerbs" or title.begins_with("SoupBubble") or title.begins_with("SoupIngredient"):
			(child as Node3D).visible = soup
	(_pot.get_node("MushroomSlices") as Node3D).visible = soup and recipe == "mushroom_soup"
	(_pot.get_node("StewMorsels") as Node3D).visible = soup and recipe == "trail_stew"
	if not soup:
		var spoon := _pot.get_node("StirringSpoon") as Node3D
		spoon.position = Vector3(0.11, 0.48, 0.06)
		spoon.rotation = Vector3(0.18, 0.0, -0.40)
	set_meta("recipe_id", recipe if cooking else "")
	set_meta("progress", amount if cooking else 0.0)
	set_meta("cooking_active", cooking)


func _build_tripod(iron: StandardMaterial3D) -> void:
	var tripod := Node3D.new()
	tripod.name = "ForgedCookingTripod"
	add_child(tripod)
	for index in 3:
		var angle := -PI * 0.5 + TAU * float(index) / 3.0
		var foot := Vector3(cos(angle) * 1.06, 0.07, sin(angle) * 1.06)
		var shoulder := Vector3(cos(angle) * 0.13, 1.78, sin(angle) * 0.13)
		var tip := Vector3(cos(angle) * 0.07, 2.01, sin(angle) * 0.07)
		HEARTH.add_curved_handle(tripod, "ForgedTripodLeg%d" % index, PackedVector3Array([foot, shoulder, tip]), 0.025, iron)
		_box(tripod, "FlattenedTripodFoot%d" % index, foot - Vector3(0.0, 0.05, 0.0), Vector3(0.13, 0.035, 0.11), iron)
	_ring(tripod, "TripodBindingCollar", Vector3(0.0, 1.91, 0.0), 0.095, 0.124, iron)
	_chain = Node3D.new()
	_chain.name = "CauldronSuspensionChain"
	tripod.add_child(_chain)
	for index in 6:
		var link := _ring(_chain, "ForgedChainLink%d" % index, Vector3(0.0, 1.49 + float(index) * 0.076, 0.0), 0.038, 0.049, iron)
		link.rotation.x = PI * 0.5
		link.rotation.y = PI * 0.5 if index % 2 else 0.0
		link.scale.z = 1.2
	HEARTH.add_curved_handle(_chain, "CauldronHangingHook", PackedVector3Array([Vector3(0.0, 1.50, 0.0), Vector3(0.0, 1.445, 0.0), Vector3(0.0, 1.435, 0.035), Vector3(0.0, 1.472, 0.05)]), 0.009, iron)


func _build_preparation_bench(wood: StandardMaterial3D, iron: StandardMaterial3D, black_iron: StandardMaterial3D) -> void:
	var bench := Node3D.new()
	bench.name = "HearthPreparationBench"
	bench.position = Vector3(1.44, 0.0, -0.02)
	add_child(bench)
	for side in [-1.0, 1.0]:
		_box(bench, "SeasonedOakTop", Vector3(side * 0.156, 0.63, 0.0), Vector3(0.30, 0.09, 1.15), wood)
		_box(bench, "OakTrestle", Vector3(0.0, 0.315, side * 0.40), Vector3(0.47, 0.59, 0.10), wood)
		_box(bench, "IronTableStrap", Vector3(0.0, 0.678, side * 0.43), Vector3(0.62, 0.009, 0.04), iron)
	_box(bench, "TrestleCrossBrace", Vector3(0.0, 0.23, 0.0), Vector3(0.07, 0.09, 0.89), wood)
	_box(bench, "CuttingBoard", Vector3(0.02, 0.698, 0.32), Vector3(0.39, 0.032, 0.32), wood)
	var knife := Node3D.new()
	knife.name = "CookingKnife"
	knife.position = Vector3(0.065, 0.725, 0.33)
	knife.rotation.y = -0.36
	bench.add_child(knife)
	_box(knife, "ForgedKnifeBlade", Vector3(0.0, 0.0, -0.062), Vector3(0.048, 0.009, 0.15), iron)
	_box(knife, "WoodenKnifeHandle", Vector3(0.0, 0.0, 0.061), Vector3(0.032, 0.022, 0.098), wood)
	var cup := HEARTH.create_vessel(0.078, 0.15, black_iron, false)
	cup.name = "SingleCup"
	cup.position = Vector3(-0.17, 0.75, 0.41)
	HEARTH.add_cup_handle(cup, 0.078, 0.15, iron)
	bench.add_child(cup)
	# A trivet supports the pot on the bench while the spit occupies the fire.
	_ring(bench, "CauldronRestTrivet", Vector3(0.0, 0.690, -0.24), 0.22, 0.238, black_iron)
	for side in [-1.0, 1.0]:
		_box(bench, "TrivetCrossbar", Vector3(side * 0.12, 0.687, -0.24), Vector3(0.021, 0.014, 0.40), black_iron)
	var rack := Node3D.new()
	rack.name = "HangingUtensils"
	rack.position = Vector3(0.27, 0.52, 0.16)
	bench.add_child(rack)
	HEARTH.add_curved_handle(rack, "ServingLadleStem", PackedVector3Array([Vector3.ZERO, Vector3(0.045, -0.32, 0.0)]), 0.012, wood)
	var ladle := HEARTH.create_vessel(0.061, 0.043, iron, true)
	ladle.name = "ServingLadleBowl"
	ladle.position = Vector3(0.045, -0.34, 0.0)
	ladle.rotation.z = PI * 0.40
	rack.add_child(ladle)
	_ring(rack, "LadleHangingLoop", Vector3.ZERO, 0.026, 0.035, iron).rotation.x = PI * 0.5


func _box(parent: Node3D, title: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _ring(parent: Node3D, title: String, at: Vector3, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 24
	mesh.ring_segments = 8
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance
