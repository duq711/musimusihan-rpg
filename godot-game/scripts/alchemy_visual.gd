extends Node3D
class_name AlchemyVisual
## A physical apothecary bench shared by the shelter and its crafting viewport.
## State belongs to AlchemySystem. These meshes only depict its real snapshot.

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const FLAME := preload("res://scripts/flame_visuals.gd")
const ARM := preload("res://scripts/player_arm_visual.gd")
const FIRE_TEXTURE: Texture2D = preload("res://assets/ai/vfx/torch_flame.png")
const CAULDRON := Vector3(-0.05, 1.03, -0.25)
const MORTAR := Vector3(-0.92, 0.96, 0.47)
const BASE_COLORS := {"water": Color(0.19, 0.38, 0.37), "wine": Color(0.33, 0.065, 0.065), "oil": Color(0.48, 0.37, 0.075), "spirits": Color(0.32, 0.44, 0.40)}

var _built := false
var _state: Dictionary = {}
var _materials: Dictionary = {}
var _tools: Dictionary = {}
var _vessels: Dictionary = {}
var _vessel_rest: Dictionary = {}
var _camera: Camera3D
var _cauldron: Node3D
var _liquid: MeshInstance3D
var _liquid_material: StandardMaterial3D
var _floating_herbs: Node3D
var _pestle: Node3D
var _mortar: Node3D
var _mortar_herbs: Node3D
var _ingredient_drop: Node3D
var _arms: Dictionary = {}
var _bellows_top: Node3D
var _bellows_skin: Node3D
var _spoon: Node3D
var _hourglass: Node3D
var _sand_top: MeshInstance3D
var _sand_bottom: MeshInstance3D
var _sand_stream: MeshInstance3D
var _pour_stream: MeshInstance3D
var _receiver_liquid: MeshInstance3D
var _bottle: Node3D
var _bottle_liquid: MeshInstance3D
var _steam: Node3D
var _bubbles: Node3D
var _drops: Node3D
var _fire: Sprite3D
var _fire_light: OmniLight3D
var _action := ""
var _action_time := 0.0
var _clock := 0.0
var _lowered := true
var _temperature := 20.0
var _heat := 0.0
var _boiling := false
var _has_liquid := false
var _distilling := false
var _hourglass_fraction := 0.0
var _hourglass_running := false
var _hourglass_start_angle := 0.0
var _hourglass_target_angle := 0.0
var _base_id := "water"


func _ready() -> void:
	_build()
	update_state(_state)


func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_build()
	if _arms.is_empty() and is_instance_valid(camera):
		for side in [-1, 1]:
			var arm := ARM.new()
			arm.name = "AlchemistLeftArm" if side == -1 else "AlchemistRightArm"
			add_child(arm)
			arm.setup(side)
			# The same source character retains its articulated hand and glove.
			# Opaque cloth sleeves avoid sharp steel-like highlights in the bench
			# lighting, while bounded limbs prevent long stretched source meshes.
			for part: MeshInstance3D in arm.arm_meshes:
				part.material_override = _materials.arm_cloth if str(part.name).contains("Sleeve") else _materials.leather
				for surface in part.mesh.get_surface_count():
					part.set_surface_override_material(surface, part.material_override)
				var transverse := 0.86 if str(part.name).contains("Sleeve") else 0.73
				var cross_section := Vector3(transverse, 1.0, transverse)
				var center := part.mesh.get_aabb().get_center()
				part.transform *= Transform3D(Basis.from_scale(cross_section), center - center * cross_section)
			for part: MeshInstance3D in arm.hand_meshes:
				part.material_override = _materials.leather if str(part.name).contains("FingerlessGlove") else _materials.hand_skin
				for surface in part.mesh.get_surface_count():
					part.set_surface_override_material(surface, part.material_override)
			arm.set_grip(0.92)
			arm.visible = false
			_arms[side] = arm


func set_room_visible(value: bool) -> void:
	_build()
	get_node("ApothecaryStoneAndTimber").visible = value


func camera_pose(station: String = "overview") -> Dictionary:
	match station:
		"mortar", "grind": return {"position": Vector3(-0.72, 1.91, 1.62), "target": MORTAR + Vector3(0, 0.10, 0), "fov": 50.0}
		"cauldron", "stir", "fire": return {"position": Vector3(0.10, 2.13, 1.52), "target": CAULDRON + Vector3(0, 0.39, 0), "fov": 55.0}
		"distill", "alembic": return {"position": Vector3(1.07, 1.95, 1.68), "target": Vector3(0.94, 1.27, -0.13), "fov": 52.0}
		_: return {"position": Vector3(0, 2.24, 2.62), "target": Vector3(0, 1.23, -0.20), "fov": 50.0}


func get_tool_position(tool_id: String) -> Vector3:
	_build()
	var key := _tool_alias(tool_id)
	if _tools.has(key):
		return (_tools[key] as Node3D).global_position
	return global_position + CAULDRON


func get_interaction_at(camera: Camera3D, position_in_viewport: Vector2) -> String:
	_build()
	if not is_instance_valid(camera): return ""
	var winner := ""
	var nearest := 50.0
	for tool_id: String in _tools:
		var anchor: Node3D = _tools[tool_id]
		if camera.is_position_behind(anchor.global_position): continue
		var distance := camera.unproject_position(anchor.global_position).distance_to(position_in_viewport)
		if distance < nearest:
			nearest = distance
			winner = tool_id
	if winner == "lower_cauldron" and _lowered: return "raise_cauldron"
	return winner


func update_state(snapshot: Dictionary) -> void:
	_state = snapshot.duplicate(true)
	if not _built: return
	_temperature = float(snapshot.get("temperature", 20.0))
	_heat = float(snapshot.get("heat", 0.0))
	_lowered = bool(snapshot.get("cauldron_lowered", false))
	_boiling = bool(snapshot.get("boiling", _temperature >= 90.0))
	_base_id = str(snapshot.get("base_id", ""))
	_has_liquid = not _base_id.is_empty()
	_liquid.visible = _has_liquid
	var liquid_color: Color = BASE_COLORS.get(_base_id, BASE_COLORS.water)
	var ingredient_count := _collection_count(snapshot.get("ingredients", []))
	_liquid_material.albedo_color = liquid_color.lerp(Color(0.18, 0.29, 0.085), clampf(float(ingredient_count) * 0.09, 0, 0.56))
	_floating_herbs.visible = _has_liquid and ingredient_count > 0
	_mortar_herbs.visible = _collection_count(snapshot.get("mortar", [])) > 0
	var mortar_state: Variant = snapshot.get("mortar", {})
	var ground := bool(mortar_state.get("ground", false)) if mortar_state is Dictionary else false
	var grinding_fraction := 1.0 if ground else 0.0
	if mortar_state is Array and not mortar_state.is_empty():
		ground = true
		grinding_fraction = 0.0
		for handful: Dictionary in mortar_state:
			var handful_ground := bool(handful.get("ground", false)) or str(handful.get("form", "whole")) == "ground"
			ground = ground and handful_ground
			grinding_fraction += 1.0 if handful_ground else clampf(float(handful.get("strokes", 0)) / 3.0, 0, 1)
		grinding_fraction /= mortar_state.size()
	_mortar_herbs.scale = Vector3(1.0, lerpf(1.0, 0.26, grinding_fraction), 1.0)
	_hourglass_running = bool(snapshot.get("hourglass_running", false))
	var turn_seconds := maxf(1.0, float(snapshot.get("hourglass_duration", snapshot.get("turn_seconds", 10.0))))
	_hourglass_fraction = clampf(float(snapshot.get("hourglass_remaining", 0.0)) / turn_seconds, 0, 1)
	var stage := str(snapshot.get("stage", "idle"))
	_distilling = stage in ["distilling", "distill"] or bool(snapshot.get("distilling", false))
	var distill_progress := float(snapshot.get("distill_progress", 0.0))
	_receiver_liquid.scale.y = maxf(0.025, clampf(distill_progress, 0, 1))
	_receiver_liquid.position.y = 0.03 + 0.055 * clampf(distill_progress, 0, 1)
	_receiver_liquid.visible = distill_progress > 0.0
	var result: Dictionary = snapshot.get("last_result", {})
	_bottle_liquid.visible = stage in ["finished", "bottled", "complete"] and str(result.get("quality", "")) != "failed"
	_bottle_liquid.scale.y = 1.0
	_bottle_liquid.position.y = 0.083
	set_meta("displayed_base", _base_id)
	set_meta("displayed_temperature", _temperature)
	set_meta("displayed_ingredient_count", ingredient_count)
	set_meta("displayed_mortar_count", _collection_count(snapshot.get("mortar", [])))
	_pose(0.0)


func animate_action(action: String) -> void:
	_build()
	_action = action
	_action_time = 0.0
	if action in ["flip_hourglass", "hourglass", "turn_hourglass"]:
		_hourglass_start_angle = _hourglass_target_angle
		_hourglass_target_angle += PI
	set_meta("last_animated_action", action)


func _build() -> void:
	if _built: return
	_built = true
	_materials = {
		"stone": SURFACES.stone(Color(0.37, 0.36, 0.31), 2.0),
		"soot": SURFACES.stone(Color(0.14, 0.14, 0.12), 2.0),
		"wood": SURFACES.old_oak(Color(0.37, 0.29, 0.19), 1.4),
		"dark_wood": SURFACES.old_oak(Color(0.20, 0.15, 0.10), 1.7),
		"iron": SURFACES.pitted_iron(Color(0.19, 0.21, 0.20), 3.0),
		"copper": SURFACES.create("iron", Color(0.60, 0.39, 0.22), SURFACES.IRON, 3.6),
		"patina": _plain(Color(0.14, 0.24, 0.18), 0.56, 0.72),
		"brass": _plain(Color(0.50, 0.38, 0.16), 0.72, 0.40),
		"ceramic": _plain(Color(0.45, 0.40, 0.28), 0.02, 0.65),
		"dark_ceramic": _plain(Color(0.20, 0.16, 0.11), 0.05, 0.53),
		"leather": SURFACES.leather(Color(0.25, 0.15, 0.085), 3.8),
		"linen": SURFACES.linen(Color(0.56, 0.49, 0.36), 5.0),
		"arm_cloth": SURFACES.linen(Color(0.085, 0.067, 0.041), 4.0),
		"hand_skin": _plain(Color(0.64, 0.435, 0.30), 0.0, 0.86),
		"paper": _plain(Color(0.63, 0.54, 0.36), 0.0, 0.95),
		"ink": _plain(Color(0.13, 0.095, 0.04), 0.0, 1.0),
		"leaf": _plain(Color(0.21, 0.29, 0.065), 0.0, 0.87),
		"dry_leaf": _plain(Color(0.36, 0.30, 0.085), 0.0, 0.91),
		"flower": _plain(Color(0.44, 0.20, 0.39), 0.0, 0.91),
		"sand": _plain(Color(0.66, 0.50, 0.27), 0.0, 0.94),
		"coal": SURFACES.stone(Color(0.018, 0.018, 0.016), 3.0),
	}
	_liquid_material = _plain(BASE_COLORS.water, 0.20, 0.19)
	_build_room()
	_build_bench()
	_build_hearth()
	_build_cauldron()
	_build_bases()
	_build_mortar()
	_build_bellows()
	_build_alembic()
	_build_hourglass()
	_build_book_and_herbs()
	_build_effects()
	set_meta("alchemy_real_geometry", true)
	set_meta("alchemy_stations", ["base_vessels", "cauldron", "bellows", "mortar", "hourglass", "alembic", "bottle", "recipe_book"])
	set_meta("hollow_vessels", ["cauldron", "mortar", "herb_bowls"])
	# The shelter's static preview factory can build then detach this script
	# before _ready runs. Apply the actual empty state during construction, too.
	update_state(_state)
	_cauldron.position.y = CAULDRON.y + (0.0 if _lowered else 0.24)


func _build_room() -> void:
	var room := _node(self, "ApothecaryStoneAndTimber")
	_box(room, "Floor", Vector3(4.3, 0.15, 3.2), Vector3(0, -0.08, -0.1), _materials.stone)
	_box(room, "MortarBacking", Vector3(4.2, 2.7, 0.20), Vector3(0, 1.35, -1.32), _materials.soot)
	for row in range(7):
		for col in range(10):
			var block := _box(room, "WeatheredWallBlock", Vector3(0.408, 0.33, 0.21), Vector3(-2.06 + col * 0.43 + (0.10 if row % 2 else 0), 0.18 + row * 0.355, -1.29), _materials.stone)
			block.rotation.z = sin(float(col * 9 + row * 7)) * 0.006
	for side in [-1, 1]:
		_box(room, "OakPillar", Vector3(0.18, 2.64, 0.21), Vector3(side * 1.93, 1.32, -1.08), _materials.dark_wood)
	_box(room, "Lintel", Vector3(4.10, 0.18, 0.24), Vector3(0, 2.60, -1.09), _materials.dark_wood)
	_box(room, "ApothecaryShelf", Vector3(3.28, 0.075, 0.30), Vector3(0, 1.98, -0.98), _materials.wood)
	for side in [-1, 1]:
		_between(room, "ShelfBracket", Vector3(side * 1.28, 1.76, -1.10), Vector3(side * 1.28, 1.95, -0.86), 0.022, _materials.iron)
	for index in range(8):
		var jar := _node(room, "SealedApothecaryJar", Vector3(-1.35 + index * 0.37, 2.02, -0.99))
		var height := 0.18 + float(index % 3) * 0.035
		_cylinder(jar, "EarthenwareBody", 0.073, 0.068, height, Vector3(0, height * 0.5, 0), _materials.dark_ceramic if index % 2 else _materials.ceramic)
		_cylinder(jar, "WaxSeal", 0.073, 0.070, 0.022, Vector3(0, height, 0), _materials.leather)
		_box(jar, "ParchmentLabel", Vector3(0.073, 0.066, 0.005), Vector3(0, height * 0.51, 0.071), _materials.paper)
		for stroke in range(3):
			_box(jar, "LabelMark", Vector3(0.035 + float((index + stroke) % 3) * 0.006, 0.004, 0.001), Vector3(0, height * 0.51 - 0.018 + stroke * 0.015, 0.075), _materials.ink)
	for index in range(5):
		var bunch := _node(room, "HangingDriedHerbs", Vector3(-1.55 + index * 0.74, 1.88, -1.10))
		for stem in range(4):
			var angle := float(stem) * TAU / 4.0
			_between(bunch, "TiedStalk", Vector3.ZERO, Vector3(cos(angle) * 0.045, -0.23, sin(angle) * 0.025), 0.006, _materials.dry_leaf)
			for leaf in range(3):
				var bit := _sphere(bunch, "DryLeaf", Vector3(0.025, 0.047, 0.009), Vector3(cos(angle) * 0.047, -0.12 - leaf * 0.048, sin(angle) * 0.032), _materials.dry_leaf)
				bit.rotation.z = sin(float(stem * 7 + leaf)) * 0.60


func _build_bench() -> void:
	var bench := _node(self, "ScarredOakAlchemyBench")
	for plank in range(5):
		_box(bench, "ThickOakPlank", Vector3(3.54, 0.115, 0.294), Vector3(0, 0.88, -0.55 + plank * 0.300), _materials.wood)
	for x in [-1.48, 1.48]:
		for z in [-0.52, 0.55]:
			_box(bench, "BenchLeg", Vector3(0.16, 0.86, 0.16), Vector3(x, 0.43, z), _materials.dark_wood)
			_cylinder(bench, "IronPlankNail", 0.012, 0.012, 0.006, Vector3(x, 0.94, z), _materials.iron)
	_box(bench, "Apron", Vector3(3.21, 0.26, 0.10), Vector3(0, 0.69, 0.67), _materials.dark_wood)
	_box(bench, "LowerStretcher", Vector3(3.04, 0.12, 0.12), Vector3(0, 0.20, 0.39), _materials.wood)
	for index in range(12):
		var scratch := _box(bench, "KnifeCut", Vector3(0.08 + float(index % 4) * 0.04, 0.001, 0.003), Vector3(-1.5 + float(index) * 0.27, 0.939, 0.53 + sin(index * 7.0) * 0.11), _materials.dark_wood)
		scratch.rotation.y = sin(float(index) * 3.4) * 0.8


func _build_hearth() -> void:
	var hearth := _node(self, "CauldronHearth", Vector3(CAULDRON.x, 0.945, CAULDRON.z))
	_cylinder(hearth, "AshBed", 0.42, 0.42, 0.09, Vector3(0, 0.015, 0), _materials.soot, 32)
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var stone := _box(hearth, "HearthRingStone", Vector3(0.21, 0.15, 0.13), Vector3(sin(angle) * 0.38, 0.06, cos(angle) * 0.38), _materials.soot)
		stone.rotation.y = angle
	for index in range(18):
		var angle := float(index) * 2.39996
		var radius := sqrt(float(index) / 18.0) * 0.28
		var coal := _sphere(hearth, "GlowingCharcoal", Vector3(0.06, 0.04, 0.047), Vector3(cos(angle) * radius, 0.073, sin(angle) * radius), _materials.coal)
		if index % 3 == 0:
			var ember := _plain(Color(0.36, 0.065, 0.006), 0.0, 1.0)
			ember.emission_enabled = true
			ember.emission = Color(0.8, 0.07, 0.002)
			ember.emission_energy_multiplier = 0.62
			coal.material_override = ember
	for side in [-1, 1]:
		_between(hearth, "CauldronRackUpright", Vector3(side * 0.49, 0.03, -0.12), Vector3(side * 0.49, 0.87, -0.12), 0.022, _materials.iron)
		_cylinder(hearth, "RackFoot", 0.07, 0.052, 0.035, Vector3(side * 0.49, 0.01, -0.12), _materials.iron)
	_between(hearth, "HangingBar", Vector3(-0.49, 0.87, -0.12), Vector3(0.49, 0.87, -0.12), 0.025, _materials.iron)
	for side in [-1, 1]:
		for link in range(7):
			var chain := _torus(hearth, "SuspensionChain", 0.019, 0.005, Vector3(side * 0.32, 0.81 - link * 0.050, -0.12), _materials.iron)
			chain.rotation.x = PI / 2.0
			chain.rotation.y = PI / 2.0 if link % 2 else 0.0
	_tool("lower_cauldron", hearth, Vector3(0.47, 0.69, -0.12))
	_fire = Sprite3D.new()
	_fire.name = "LivingAlchemyFire"
	_fire.texture = FIRE_TEXTURE
	_fire.pixel_size = 0.00029
	_fire.position = Vector3(0, 0.16, 0)
	_fire.no_depth_test = false
	hearth.add_child(_fire)
	FLAME.attach(_fire)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "WarmHearthGlow"
	_fire_light.position = Vector3(0, 0.20, 0.03)
	_fire_light.light_color = Color(1.0, 0.39, 0.10)
	_fire_light.omni_range = 1.75
	_fire_light.light_energy = 0.7
	hearth.add_child(_fire_light)


func _build_cauldron() -> void:
	_cauldron = _node(self, "LiftableCopperCauldron", CAULDRON)
	var profile := PackedVector2Array([Vector2(0.06, 0.03), Vector2(0.23, 0.045), Vector2(0.32, 0.14), Vector2(0.34, 0.30), Vector2(0.33, 0.39), Vector2(0.308, 0.39), Vector2(0.316, 0.30), Vector2(0.296, 0.15), Vector2(0.21, 0.075), Vector2(0.01, 0.07)])
	_mesh(_cauldron, "HollowHammeredCopperBowl", _lathe(profile, 48), _materials.copper)
	_torus(_cauldron, "RolledCopperRim", 0.323, 0.018, Vector3(0, 0.388, 0), _materials.brass)
	_torus(_cauldron, "DarkPatinaFoot", 0.215, 0.011, Vector3(0, 0.075, 0), _materials.patina)
	for side in [-1, 1]:
		var handle := _torus(_cauldron, "IronCauldronHandle", 0.075, 0.013, Vector3(side * 0.331, 0.28, 0), _materials.iron)
		handle.rotation.z = PI / 2.0
		_sphere(_cauldron, "RivetedHandleMount", Vector3(0.016, 0.026, 0.027), Vector3(side * 0.331, 0.29, 0), _materials.brass)
	for rivet in range(20):
		var angle := float(rivet) * TAU / 20.0
		_sphere(_cauldron, "RimRivet", Vector3(0.008, 0.008, 0.008), Vector3(cos(angle) * 0.332, 0.348, sin(angle) * 0.332), _materials.brass)
	_liquid = _cylinder(_cauldron, "ActualBrewSurface", 0.293, 0.293, 0.006, Vector3(0, 0.306, 0), _liquid_material, 48)
	_floating_herbs = _node(_cauldron, "FloatingAddedIngredients", Vector3(0, 0.313, 0))
	for index in range(12):
		var angle := float(index) * 2.39996
		var leaf := _sphere(_floating_herbs, "FloatingLeaf", Vector3(0.026, 0.003, 0.010), Vector3(cos(angle) * 0.21, 0, sin(angle) * 0.21), _materials.leaf if index % 3 else _materials.dry_leaf)
		leaf.rotation.y = angle
	_spoon = _node(self, "WoodenStirringSpoon", Vector3(0.47, 1.02, 0.37))
	_between(_spoon, "LongSpoonHandle", Vector3(0, 0, 0), Vector3(0.06, 0.49, 0), 0.018, _materials.wood)
	_sphere(_spoon, "SpoonBowl", Vector3(0.041, 0.066, 0.017), Vector3(0, 0.018, 0), _materials.dark_wood)
	_spoon.rotation.z = -0.63
	_tool("stir", _cauldron, Vector3(0, 0.34, 0.13))


func _build_bases() -> void:
	var index := 0
	for base_id: String in ["water", "wine", "oil", "spirits"]:
		var at := Vector3(-1.53 + (index % 2) * 0.35, 0.946, -0.47 + (index / 2) * 0.38)
		var vessel := _node(self, "BaseVessel_" + base_id, at)
		var height := 0.40 if index < 2 else 0.30
		var body_material: Material = _materials.ceramic if base_id == "water" else _materials.dark_ceramic
		if base_id == "wine": body_material = _plain(Color(0.26, 0.12, 0.065), 0.0, 0.55)
		if base_id == "oil": body_material = _plain(Color(0.36, 0.32, 0.12), 0.15, 0.42)
		if base_id == "spirits": body_material = _plain(Color(0.14, 0.26, 0.21), 0.12, 0.35)
		var profile := PackedVector2Array([Vector2(0.07, 0), Vector2(0.118, height * 0.12), Vector2(0.13, height * 0.49), Vector2(0.115, height * 0.71), Vector2(0.058, height * 0.84), Vector2(0.052, height), Vector2(0.035, height), Vector2(0.036, height * 0.89)])
		_mesh(vessel, "GlazedBaseJug", _lathe(profile), body_material)
		_torus(vessel, "JugLip", 0.045, 0.011, Vector3(0, height, 0), _materials.ceramic)
		var handle := _torus(vessel, "JugHandle", 0.070, 0.016, Vector3(0.119, height * 0.58, 0), body_material)
		handle.rotation.x = PI / 2.0
		_box(vessel, "VesselParchmentTag", Vector3(0.088, 0.085, 0.004), Vector3(0, height * 0.48, 0.124), _materials.paper)
		var label := Label3D.new()
		label.name = "BaseName"
		label.text = ["물", "포도주", "기름", "증류주"][index]
		label.font_size = 32
		label.pixel_size = 0.00185
		label.modulate = Color(0.18, 0.11, 0.055)
		label.outline_size = 0
		label.no_depth_test = false
		label.position = Vector3(0, height * 0.48, 0.129)
		vessel.add_child(label)
		_tool("pour_" + base_id, vessel, Vector3(0, height * 0.55, 0))
		_vessels[base_id] = vessel
		_vessel_rest[base_id] = vessel.transform
		index += 1


func _build_mortar() -> void:
	var mortar := _node(self, "StoneMortarAndPestle", MORTAR)
	_mortar = mortar
	var profile := PackedVector2Array([Vector2(0.09, 0), Vector2(0.14, 0.035), Vector2(0.19, 0.18), Vector2(0.185, 0.205), Vector2(0.15, 0.205), Vector2(0.135, 0.15), Vector2(0.08, 0.06), Vector2(0, 0.052)])
	_mesh(mortar, "HollowStoneMortar", _lathe(profile), _materials.stone)
	_torus(mortar, "WornMortarRim", 0.17, 0.017, Vector3(0, 0.201, 0), _materials.stone)
	_mortar_herbs = _node(mortar, "IngredientsInsideMortar", Vector3(0, 0.073, 0))
	for index in range(9):
		var angle := float(index) * 2.39
		var leaf := _sphere(_mortar_herbs, "FreshMortarLeaf", Vector3(0.043, 0.019, 0.013), Vector3(cos(angle) * 0.075, float(index % 3) * 0.020, sin(angle) * 0.075), _materials.leaf)
		leaf.rotation = Vector3(angle, angle * 0.6, angle * 0.3)
	_pestle = _node(self, "MovingStonePestle", MORTAR + Vector3(0.05, 0.20, 0))
	_sphere(_pestle, "RoundedPestleFoot", Vector3(0.043, 0.07, 0.042), Vector3.ZERO, _materials.stone)
	_cylinder(_pestle, "PestleHandle", 0.029, 0.035, 0.27, Vector3(0, 0.17, 0), _materials.stone)
	_sphere(_pestle, "PestlePommel", Vector3(0.037, 0.04, 0.037), Vector3(0, 0.305, 0), _materials.stone)
	_pestle.rotation.z = -0.40
	_tool("grind", mortar, Vector3(0, 0.20, 0))
	_tool("add_mortar", mortar, Vector3(0.22, 0.07, 0.08))


func _build_bellows() -> void:
	var bellows := _node(self, "LeatherHandBellows", Vector3(-0.36, 0.957, 0.55))
	bellows.rotation.y = -0.28
	_sphere(bellows, "LowerBellowsBoard", Vector3(0.16, 0.023, 0.23), Vector3.ZERO, _materials.dark_wood)
	_bellows_skin = _node(bellows, "AccordionLeather")
	for fold in range(5):
		_sphere(_bellows_skin, "FoldedLeatherPleat", Vector3(0.145 + (0.01 if fold % 2 else 0), 0.014, 0.215), Vector3(0, 0.026 + fold * 0.018, 0), _materials.leather)
	_bellows_top = _node(bellows, "MovingBellowsHandle", Vector3(0, 0.12, 0))
	_sphere(_bellows_top, "UpperBellowsBoard", Vector3(0.16, 0.023, 0.23), Vector3.ZERO, _materials.wood)
	_box(_bellows_top, "HandGrip", Vector3(0.057, 0.038, 0.21), Vector3(0, 0.01, 0.24), _materials.wood)
	_between(bellows, "BrassAirNozzle", Vector3(0, 0.06, -0.18), Vector3(0, 0.055, -0.43), 0.026, _materials.brass)
	for side in [-1, 1]:
		for stud in range(6):
			_sphere(_bellows_top, "LeatherRivet", Vector3.ONE * 0.008, Vector3(side * 0.125, 0.025, -0.12 + stud * 0.05), _materials.brass)
	_tool("pump_bellows", bellows, Vector3(0, 0.18, 0.12))


func _build_alembic() -> void:
	var alembic := _node(self, "CopperAlembicAndCondenser", Vector3(0.93, 0.952, -0.40))
	_cylinder(alembic, "DistillerStand", 0.27, 0.27, 0.08, Vector3(0, 0.04, 0), _materials.iron, 24)
	var profile := PackedVector2Array([Vector2(0.12, 0.075), Vector2(0.23, 0.16), Vector2(0.25, 0.32), Vector2(0.23, 0.44), Vector2(0.17, 0.49), Vector2(0.18, 0.53), Vector2(0.24, 0.57), Vector2(0.19, 0.65), Vector2(0.09, 0.76), Vector2(0.025, 0.79)])
	_mesh(alembic, "BeatenCopperRetort", _lathe(profile, 40), _materials.copper)
	_torus(alembic, "RetortSeam", 0.234, 0.012, Vector3(0, 0.425, 0), _materials.brass)
	_torus(alembic, "LutedLidSeal", 0.178, 0.015, Vector3(0, 0.521, 0), _materials.linen)
	var pipe_points := [Vector3(0.12, 0.69, 0), Vector3(0.37, 0.71, 0.01), Vector3(0.47, 0.54, 0.02), Vector3(0.47, 0.34, 0.10), Vector3(0.49, 0.24, 0.17)]
	for index in range(pipe_points.size() - 1):
		_between(alembic, "CondensingSwanNeck", pipe_points[index], pipe_points[index + 1], 0.028, _materials.copper)
		_sphere(alembic, "SolderedTubeJoint", Vector3.ONE * 0.030, pipe_points[index + 1], _materials.copper)
	for coil in range(5):
		_torus(alembic, "CoolingCopperCoil", 0.065, 0.014, Vector3(0.46, 0.41 + coil * 0.035, 0.02), _materials.patina)
	_cylinder(alembic, "ReceiverFoot", 0.082, 0.082, 0.026, Vector3(0.49, 0.014, 0.19), _materials.brass)
	var glass := _glass(Color(0.53, 0.69, 0.58, 0.30))
	_mesh(alembic, "GlassReceivingVial", _lathe(PackedVector2Array([Vector2(0.05, 0.03), Vector2(0.072, 0.06), Vector2(0.073, 0.16), Vector2(0.045, 0.19), Vector2(0.035, 0.23), Vector2(0.027, 0.23), Vector2(0.026, 0.20)])), glass).position = Vector3(0.49, 0, 0.19)
	_receiver_liquid = _cylinder(alembic, "CollectedDistillate", 0.064, 0.064, 0.11, Vector3(0.49, 0.085, 0.19), _plain(Color(0.32, 0.50, 0.35), 0.08, 0.23), 24)
	_drops = _node(alembic, "ActualCondensateDrops", Vector3(0.49, 0.225, 0.17))
	for index in range(4):
		_sphere(_drops, "CondensateDrop", Vector3(0.006, 0.015, 0.006), Vector3(0, -index * 0.017, 0), _plain(Color(0.52, 0.70, 0.60), 0.1, 0.15))
	_tool("distill", alembic, Vector3(0, 0.46, 0.10))
	_bottle = _node(self, "FinishedPotionBottle", Vector3(0.63, 0.95, 0.56))
	_mesh(_bottle, "GreenGlassPotionBottle", _lathe(PackedVector2Array([Vector2(0.045, 0), Vector2(0.066, 0.035), Vector2(0.066, 0.16), Vector2(0.030, 0.20), Vector2(0.030, 0.27), Vector2(0.020, 0.27), Vector2(0.020, 0.22)])), _glass(Color(0.28, 0.46, 0.29, 0.42)))
	_torus(_bottle, "BottleLip", 0.026, 0.007, Vector3(0, 0.268, 0), _materials.copper)
	_bottle_liquid = _cylinder(_bottle, "BottledPotionLiquid", 0.058, 0.058, 0.13, Vector3(0, 0.083, 0), _plain(Color(0.33, 0.49, 0.10), 0.1, 0.20), 24)
	_cylinder(self, "WaitingCork", 0.022, 0.026, 0.040, Vector3(0.75, 0.964, 0.59), _materials.wood)
	_tool("bottle", _bottle, Vector3(0, 0.12, 0))


func _build_hourglass() -> void:
	_hourglass = _node(self, "TurningBrassHourglass", Vector3(0.37, 1.19, 0.10))
	for side in [-1, 1]:
		_cylinder(_hourglass, "HourglassEndPlate", 0.097, 0.097, 0.027, Vector3(0, side * 0.22, 0), _materials.wood)
		_torus(_hourglass, "BrassEndBand", 0.086, 0.008, Vector3(0, side * 0.206, 0), _materials.brass)
	for post in range(4):
		var angle := float(post) * TAU / 4 + PI / 4
		_between(_hourglass, "BrassSupportColumn", Vector3(cos(angle) * 0.075, -0.21, sin(angle) * 0.075), Vector3(cos(angle) * 0.075, 0.21, sin(angle) * 0.075), 0.007, _materials.brass)
	var profile := PackedVector2Array([Vector2(0.054, -0.196), Vector2(0.063, -0.15), Vector2(0.050, -0.08), Vector2(0.010, 0), Vector2(0.050, 0.08), Vector2(0.063, 0.15), Vector2(0.054, 0.196)])
	_mesh(_hourglass, "HandblownHourglass", _lathe(profile), _glass(Color(0.72, 0.74, 0.64, 0.20)))
	_sand_top = _cylinder(_hourglass, "RemainingUpperSand", 0.007, 0.051, 0.145, Vector3(0, 0.106, 0), _materials.sand, 24)
	_sand_bottom = _cylinder(_hourglass, "ElapsedLowerSand", 0.053, 0.001, 0.13, Vector3(0, -0.125, 0), _materials.sand, 24)
	_sand_stream = _cylinder(_hourglass, "FallingSandThread", 0.002, 0.002, 0.18, Vector3(0, -0.061, 0), _materials.sand, 8)
	_tool("flip_hourglass", _hourglass, Vector3(0, 0, 0))


func _build_book_and_herbs() -> void:
	var book := _node(self, "OpenIlluminatedRecipeBook", Vector3(1.17, 0.959, 0.48))
	book.rotation.x = -0.17
	book.rotation.y = -0.17
	for side in [-1, 1]:
		var page := _node(book, "RecipePage", Vector3(side * 0.155, 0.028, 0))
		page.rotation.z = side * -0.10
		_box(page, "LeatherCover", Vector3(0.31, 0.024, 0.41), Vector3(0, -0.015, 0), _materials.leather)
		_box(page, "AgedPageBlock", Vector3(0.285, 0.028, 0.381), Vector3(0, 0.008, 0), _materials.paper)
		for line in range(11):
			var width := 0.16 + float((line * 3 + side) % 4) * 0.014
			_box(page, "RecipeInkLine", Vector3(width, 0.0015, 0.003), Vector3(0, 0.0235, -0.146 + line * 0.027), _materials.ink)
			if line % 3 == 0:
				_box(page, "RubricatedInitial", Vector3(0.014, 0.0015, 0.014), Vector3(-0.104, 0.024, -0.143 + line * 0.027), _materials.copper)
	_box(book, "RedBookmark", Vector3(0.021, 0.001, 0.49), Vector3(0.04, 0.054, 0.045), _plain(Color(0.27, 0.035, 0.025), 0, 1))
	_tool("recipe_book", book, Vector3(0, 0.05, 0))
	for index in range(3):
		var bowl := _node(self, "FreshHerbBowl", Vector3(-0.83 + index * 0.36, 0.949, -0.74))
		_mesh(bowl, "OpenHerbDish", _lathe(PackedVector2Array([Vector2(0.05, 0), Vector2(0.11, 0.025), Vector2(0.145, 0.10), Vector2(0.13, 0.10), Vector2(0.095, 0.035), Vector2(0, 0.016)])), _materials.dark_ceramic)
		for herb in range(7):
			var angle := float(herb) * 2.39996
			var leaf := _sphere(bowl, "GatheredMedicinalHerb", Vector3(0.052, 0.015, 0.021), Vector3(cos(angle) * 0.065, 0.06 + float(herb % 3) * 0.021, sin(angle) * 0.065), _materials.leaf if index != 2 else _materials.flower)
			leaf.rotation = Vector3(angle, angle * 0.7, 0)


func _build_effects() -> void:
	_ingredient_drop = _node(self, "HandfulOfFallingHerbs")
	for index in range(7):
		var leaf := _sphere(_ingredient_drop, "FallingHerb", Vector3(0.027, 0.007, 0.014), Vector3(sin(index * 4.0) * 0.045, index * 0.018, cos(index * 3.0) * 0.045), _materials.leaf)
		leaf.rotation = Vector3(index * 0.7, index * 1.3, 0)
	_ingredient_drop.visible = false
	_steam = _node(_cauldron, "TemperatureDrivenSteam", Vector3(0, 0.35, 0))
	for index in range(8):
		var wisp := Sprite3D.new()
		wisp.name = "RisingSteamWisp"
		wisp.texture = FLAME.steam_texture()
		wisp.pixel_size = 0.0023
		wisp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		wisp.shaded = true
		wisp.modulate = Color(0.75, 0.73, 0.64, 0.20)
		_steam.add_child(wisp)
	_bubbles = _node(_cauldron, "BoilingSurfaceBubbles", Vector3(0, 0.313, 0))
	for index in range(14):
		var angle := float(index) * 2.39996
		_torus(_bubbles, "BurstingBrewBubble", 0.014, 0.003, Vector3(cos(angle) * 0.22, 0, sin(angle) * 0.22), _plain(Color(0.52, 0.55, 0.30), 0.20, 0.24))
	_pour_stream = _cylinder(self, "PouringBaseStream", 0.008, 0.011, 0.34, Vector3(0, 1.60, -0.25), _plain(Color(0.42, 0.53, 0.43), 0.12, 0.15), 10)
	_pour_stream.visible = false


func _process(delta: float) -> void:
	if not _built: return
	_clock += delta
	_action_time += delta
	_pose(delta)


func _pose(delta: float) -> void:
	var raised_y := CAULDRON.y + (0.0 if _lowered else 0.24)
	_cauldron.position.y = lerpf(_cauldron.position.y, raised_y, minf(1.0, delta * 5.0))
	var activity := clampf(_heat / 100.0, 0, 1)
	_fire.visible = _heat > 0.2
	_fire.scale = Vector3.ONE * (0.46 + activity * 0.85) * (0.98 + sin(_clock * 9.0) * 0.04)
	_fire.modulate.a = 0.40 + activity * 0.58
	_fire_light.light_energy = (0.28 + activity * 0.75) * (0.97 + sin(_clock * 11.0) * 0.05)
	_steam.visible = _has_liquid and _temperature > 45.0
	var steam_strength := smoothstep(45.0, 100.0, _temperature)
	for index in _steam.get_child_count():
		var wisp: Sprite3D = _steam.get_child(index)
		var phase := fposmod(_clock * (0.24 + steam_strength * 0.20) + index * 0.123, 1.0)
		wisp.position = Vector3(sin(index * 4.0 + phase * 2.0) * 0.14, phase * 0.51, cos(index * 3.0) * 0.10)
		wisp.scale = Vector3.ONE * (0.40 + phase * 1.25)
		wisp.modulate.a = sin(phase * PI) * steam_strength * 0.26
	_bubbles.visible = _has_liquid and _boiling
	for index in _bubbles.get_child_count():
		var bubble: Node3D = _bubbles.get_child(index)
		var phase := fposmod(_clock * 1.45 + index * 0.31, 1.0)
		bubble.scale = Vector3.ONE * (0.12 + phase * 1.25)
		bubble.visible = phase < 0.85
	_floating_herbs.rotation.y = _clock * (0.17 if _boiling else 0.015)
	_sand_top.scale.y = maxf(0.015, _hourglass_fraction)
	_sand_top.position.y = 0.034 + 0.072 * _hourglass_fraction
	_sand_bottom.scale.y = maxf(0.015, 1.0 - _hourglass_fraction)
	_sand_bottom.position.y = -0.19 + 0.065 * (1.0 - _hourglass_fraction)
	_sand_stream.visible = _hourglass_running
	_drops.visible = _distilling
	for index in _drops.get_child_count():
		(_drops.get_child(index) as Node3D).position.y = -fposmod(_clock * 0.17 + index * 0.02, 0.07)
	_pestle.position = MORTAR + Vector3(0.05, 0.20, 0)
	_pestle.rotation = Vector3(0, 0, -0.40)
	_mortar.position = MORTAR
	_mortar.rotation = Vector3.ZERO
	_mortar_herbs.visible = _collection_count(_state.get("mortar", [])) > 0
	_ingredient_drop.visible = false
	_bellows_top.position.y = 0.12
	_bellows_skin.scale.y = 1.0
	_hourglass.rotation.z = _hourglass_target_angle
	_pose_hourglass_sand()
	_spoon.position = Vector3(0.47, 1.02, 0.37)
	_spoon.rotation = Vector3(0, 0, -0.63)
	_bottle.position = Vector3(0.63, 0.95, 0.56)
	for base_id: String in _vessels:
		(_vessels[base_id] as Node3D).transform = _vessel_rest[base_id]
	_pour_stream.visible = false
	for side: int in _arms:
		(_arms[side] as Node3D).visible = false
	if _action_time > 2.1: return
	var envelope := sin(minf(_action_time / 1.8, 1.0) * PI)
	if _action.begins_with("pour_") or _action.begins_with("add_base") or _action == "pour_base":
		var chosen := _action.trim_prefix("pour_")
		if not _vessels.has(chosen): chosen = _base_id if _vessels.has(_base_id) else "water"
		var vessel: Node3D = _vessels[chosen]
		var resting: Transform3D = _vessel_rest[chosen]
		var reach := smoothstep(0.0, 0.40, _action_time) * (1.0 - smoothstep(1.30, 1.85, _action_time))
		vessel.position = resting.origin.lerp(Vector3(-0.27, _cauldron.position.y + 0.63, -0.20), reach)
		vessel.rotation.z = -reach * 1.48
		# Follow the actual moving mouth, including each jug's different neck
		# height. Gravity lands the stream directly below it on the real brew.
		var mouth := to_local((vessel.get_node("JugLip") as Node3D).global_position)
		var liquid_top := to_local(_liquid.global_position) + Vector3(0, 0.003, 0)
		var landing := Vector3(mouth.x, liquid_top.y, mouth.z)
		_pour_stream.position = (mouth + landing) * 0.5
		_pour_stream.scale.y = mouth.distance_to(landing) / 0.34
		_pour_stream.quaternion = Quaternion(Vector3.UP, (mouth - landing).normalized())
		_pour_stream.visible = _action_time > 0.42 and _action_time < 1.31
		(_pour_stream.material_override as StandardMaterial3D).albedo_color = BASE_COLORS.get(chosen, BASE_COLORS.water)
	elif _action in ["grind", "grind_mortar"]:
		_pestle.position = MORTAR + Vector3(cos(_action_time * 14) * 0.035, 0.135 + absf(sin(_action_time * 11.5)) * 0.13, sin(_action_time * 14) * 0.025)
		_pestle.rotation = Vector3(sin(_action_time * 14) * 0.10, 0, cos(_action_time * 14) * 0.13)
	elif _action in ["add_mortar", "pour_mortar"]:
		var lift := smoothstep(0.0, 0.40, _action_time) * (1.0 - smoothstep(1.22, 1.90, _action_time))
		_mortar.position = MORTAR.lerp(_cauldron.position + Vector3(-0.25, 0.56, 0.05), lift)
		_mortar.rotation.z = -lift * 1.65
		_pestle.position = MORTAR + Vector3(-0.24, 0.07, 0.02)
		_pestle.rotation.z = -1.30
		_mortar_herbs.visible = _action_time < 0.78
		_ingredient_drop.visible = _action_time > 0.48 and _action_time < 1.1
		_ingredient_drop.position = _cauldron.position + Vector3(-0.03, lerpf(0.62, 0.31, clampf((_action_time - 0.48) / 0.62, 0, 1)), 0.02)
	elif _action in ["add_whole", "add_to_mortar", "add_herb"]:
		var destination := MORTAR + Vector3(0, 0.09, 0) if _action == "add_to_mortar" else _cauldron.position + Vector3(0, 0.31, 0)
		_ingredient_drop.visible = _action_time < 1.10
		_ingredient_drop.position = destination + Vector3(0, lerpf(0.35, 0, smoothstep(0.38, 1.10, _action_time)), 0)
	elif _action in ["pump_bellows", "bellows", "fan"]:
		var press := absf(sin(_action_time * 7.0)) * envelope
		_bellows_top.position.y = 0.12 - press * 0.075
		_bellows_skin.scale.y = 1.0 - press * 0.65
	elif _action in ["stir", "stir_clockwise", "stir_counterclockwise"]:
		var direction := -1.0 if _action == "stir_counterclockwise" else 1.0
		var angle := _action_time * 7.0 * direction
		_spoon.position = _cauldron.position + Vector3(cos(angle) * 0.14, 0.27, sin(angle) * 0.14)
		_spoon.rotation = Vector3(sin(angle) * 0.16, angle, cos(angle) * -0.18)
		_floating_herbs.rotation.y = angle * 0.5
	elif _action in ["flip_hourglass", "hourglass", "turn_hourglass"]:
		_hourglass.rotation.z = lerpf(_hourglass_start_angle, _hourglass_target_angle, smoothstep(0, 0.75, _action_time))
		_pose_hourglass_sand()
	elif _action in ["bottle", "bottle_potion", "finish"]:
		_bottle.position += Vector3(-0.31, 0.29, -0.27) * envelope
		var result: Dictionary = _state.get("last_result", {})
		_bottle_liquid.visible = _action_time > 0.7 and str(result.get("quality", "")) != "failed"
		var fill := smoothstep(0.7, 1.3, _action_time)
		_bottle_liquid.scale.y = maxf(0.02, fill)
		_bottle_liquid.position.y = 0.018 + 0.065 * fill
	_pose_arms()


func _pose_arms() -> void:
	if _arms.is_empty() or not is_instance_valid(_camera) or _action_time > 1.85: return
	var side := 1
	var target := Vector3.ZERO
	var hand_basis := Basis.from_euler(Vector3(-0.72, -0.10, 0))
	if _action.begins_with("pour_") and _action != "pour_mortar":
		side = -1
		var chosen := _action.trim_prefix("pour_")
		if not _vessels.has(chosen): chosen = _base_id if _vessels.has(_base_id) else "water"
		var vessel: Node3D = _vessels[chosen]
		target = vessel.position + vessel.basis * Vector3(0.15, 0.22, 0.15)
		hand_basis = vessel.basis * Basis.from_euler(Vector3(-0.20, -0.10, 0))
	elif _action in ["grind", "grind_mortar"]:
		target = _pestle.position + _pestle.basis * Vector3(0.045, 0.255, 0.15)
		hand_basis = _pestle.basis * Basis.from_euler(Vector3(-0.15, -0.28, -0.15))
	elif _action in ["add_mortar", "pour_mortar"]:
		side = -1
		target = _mortar.position + _mortar.basis * Vector3(-0.13, 0.14, 0.15)
		hand_basis = _mortar.basis * Basis.from_euler(Vector3(-0.20, 0, 0))
	elif _action in ["add_whole", "add_to_mortar", "add_herb"]:
		target = _ingredient_drop.position + Vector3(0, 0.13, 0.08)
	elif _action in ["pump_bellows", "bellows", "fan"]:
		side = -1
		target = to_local(_bellows_top.global_position) + Vector3(0, 0.04, 0.21)
		hand_basis = Basis.from_euler(Vector3(0, 0, -0.10))
	elif _action in ["stir", "stir_clockwise", "stir_counterclockwise"]:
		target = _spoon.position + _spoon.basis * Vector3(0.075, 0.38, 0.065)
	elif _action in ["flip_hourglass", "hourglass", "turn_hourglass"]:
		target = _hourglass.position + _hourglass.basis * Vector3(0.085, 0.04, 0.03)
		hand_basis = _hourglass.basis * hand_basis
	elif _action in ["bottle", "bottle_potion", "finish"]:
		target = _bottle.position + Vector3(0.048, 0.17, 0.06)
	else: return
	# The overview is a full workshop inspection. Hands appear at the actual
	# apparatus closeups, where their contact and articulation are readable.
	if _camera.global_position.distance_to(to_global(target)) > 2.05: return
	var arm: Node3D = _arms[side]
	arm.visible = true
	arm.position = target
	arm.basis = hand_basis
	arm.call("set_grip", 0.72 if _action in ["pump_bellows", "add_whole", "add_to_mortar"] else 0.94)
	var viewport_size := _camera.get_viewport().get_visible_rect().size
	var entry := Vector2(viewport_size.x * (-0.06 if side < 0 else 1.06), viewport_size.y * 1.14)
	var depth := -(_camera.global_transform.affine_inverse() * arm.global_position).z
	var wanted_shoulder := _camera.project_position(entry, maxf(0.45, depth * 0.74))
	var wanted_elbow := arm.global_position.lerp(wanted_shoulder, 0.48) + _camera.global_basis.x * side * 0.055
	var elbow := arm.global_position + (wanted_elbow - arm.global_position).limit_length(0.30)
	arm.call("fit_arm", wanted_shoulder, elbow)
	arm.set_meta("staged_shoulder", wanted_shoulder)
	arm.set_meta("forearm_length", arm.global_position.distance_to(elbow))


func _pose_hourglass_sand() -> void:
	# The frame makes a physical half turn. Sand remains aligned to gravity,
	# while its quantity continues to come from the live eight-second timer.
	var inverse_angle := -_hourglass.rotation.z
	_sand_top.position = Vector3(0, 0.034 + 0.072 * _hourglass_fraction, 0).rotated(Vector3.BACK, inverse_angle)
	_sand_bottom.position = Vector3(0, -0.19 + 0.065 * (1.0 - _hourglass_fraction), 0).rotated(Vector3.BACK, inverse_angle)
	_sand_stream.position = Vector3(0, -0.061, 0).rotated(Vector3.BACK, inverse_angle)
	for part: Node3D in [_sand_top, _sand_bottom, _sand_stream]:
		part.rotation.z = inverse_angle


func _tool_alias(action: String) -> String:
	match action:
		"cauldron", "raise_cauldron": return "lower_cauldron"
		"mortar", "grind_mortar": return "grind"
		"bellows": return "pump_bellows"
		"hourglass": return "flip_hourglass"
		"alembic": return "distill"
		_: return action


func _collection_count(value: Variant) -> int:
	if value is Array: return value.size()
	if value is Dictionary:
		if value.has("ingredients"): return _collection_count(value.ingredients)
		if value.has("item_id") or value.has("id"): return int(value.get("quantity", value.get("count", 1)))
		return value.size()
	return 0


func _tool(tool_id: String, parent: Node3D, at: Vector3) -> void:
	var anchor := _node(parent, "ToolAnchor_" + tool_id, at)
	anchor.set_meta("alchemy_tool", tool_id)
	_tools[tool_id] = anchor


func _plain(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _glass(color: Color) -> StandardMaterial3D:
	var material := _plain(color, 0.05, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _node(parent: Node3D, node_name: String, at := Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = node_name
	result.position = at
	parent.add_child(result)
	return result


func _mesh(parent: Node3D, node_name: String, shape: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = shape
	result.material_override = material
	parent.add_child(result)
	return result


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	return result


func _sphere(parent: Node3D, node_name: String, radii: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 12
	shape.rings = 6
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	result.scale = radii
	return result


func _cylinder(parent: Node3D, node_name: String, bottom: float, top: float, height: float, at: Vector3, material: Material, segments := 24) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = segments
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	return result


func _between(parent: Node3D, node_name: String, start: Vector3, finish: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var result := _cylinder(parent, node_name, radius, radius, start.distance_to(finish), (start + finish) * 0.5, material, 12)
	result.quaternion = Quaternion(Vector3.UP, (finish - start).normalized())
	return result


func _torus(parent: Node3D, node_name: String, radius: float, tube: float, at: Vector3, material: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - tube
	shape.outer_radius = radius + tube
	shape.rings = 32
	shape.ring_segments = 8
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	return result


func _lathe(profile: PackedVector2Array, segments := 32) -> ArrayMesh:
	# Continuous outer wall, turned rim and inner wall: no invisible cap across
	# the mouth. Godot's clockwise winding gives outward-facing bowl surfaces.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size() - 1):
		var a := profile[row]
		var b := profile[row + 1]
		for segment in range(segments):
			var t0 := float(segment) * TAU / segments
			var t1 := float(segment + 1) * TAU / segments
			var p0 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p1 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p2 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			var p3 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			for point in [p0, p1, p2, p0, p2, p3]:
				surface.set_uv(Vector2(atan2(point.z, point.x) / TAU, point.y))
				surface.add_vertex(point)
	surface.generate_normals()
	surface.index()
	return surface.commit()
