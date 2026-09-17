extends Node3D
class_name BlacksmithVisual
## Production workshop shared by the shelter and the smithing close-up viewport.
## The visual consumes real SmithingSystem snapshots; it never owns inventory,
## input, sound, camera capture, timers or crafting outcomes.

const SURFACES := preload("res://scripts/dark_fantasy_materials.gd")
const FLAME := preload("res://scripts/flame_visuals.gd")
const ARM := preload("res://scripts/player_arm_visual.gd")
const FIRE_TEXTURE: Texture2D = preload("res://assets/ai/vfx/torch_flame.png")
const ANVIL := Vector3(-0.20, 0.0, 0.38)
const FIRE := Vector3(-1.02, 0.0, -0.79)
const WATER := Vector3(1.18, 0.0, 0.32)
const BENCH := Vector3(1.03, 0.0, -0.93)

var _built := false
var _state: Dictionary = {}
var _materials: Dictionary = {}
var _iron_material: StandardMaterial3D
var _rune_material: StandardMaterial3D
var _fire_light: OmniLight3D
var _fire_sprite: Sprite3D
var _bellows_top: Node3D
var _bellows_skin: Node3D
var _hammer: Node3D
var _tongs: Node3D
var _drill: Node3D
var _weapon: Node3D
var _blade_root: Node3D
var _grip_root: Node3D
var _socket_root: Node3D
var _spark_root: Node3D
var _steam_root: Node3D
var _ripples: Node3D
var _camera: Camera3D
var _arms: Dictionary = {}
var _weapon_signature := ""
var _action := ""
var _action_time := 0.0
var _clock := 0.0
var _target_heat := 20.0
var _stage := "idle"
var _station := "overview"
var _work_mode := "forge"
var _file_tool: Node3D
var _held_rune: Node3D
var _hammer_rest := Transform3D.IDENTITY
var _tongs_rest := Transform3D.IDENTITY
var _drill_rest := Transform3D.IDENTITY


func _ready() -> void:
	_build()
	update_state(_state)


func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_build()
	if _arms.is_empty() and is_instance_valid(camera):
		for side in [-1, 1]:
			var arm := ARM.new()
			arm.name = "SmithLeftArm" if side == -1 else "SmithRightArm"
			add_child(arm)
			arm.setup(side)
			arm.set_grip(0.94)
			_arms[side] = arm


func camera_pose(station: String = "overview") -> Dictionary:
	match station:
		"fire", "forge", "bellows", "heating":
			return {"position": Vector3(-0.84, 1.77, 0.39), "target": Vector3(-1.15, 0.99, -0.67), "fov": 61.0}
		"anvil", "hammer", "forging":
			return {"position": Vector3(-0.03, 1.98, 1.00), "target": Vector3(-0.24, 0.91, 0.33), "fov": 59.0}
		"water", "quench", "quenched":
			return {"position": Vector3(1.29, 1.73, 1.03), "target": Vector3(1.06, 0.49, 0.27), "fov": 59.0}
		"upgrade", "finished", "drill", "rune", "workbench":
			return {"position": Vector3(1.02, 1.89, -0.18), "target": Vector3(0.85, 0.97, -0.87), "fov": 55.0}
		_:
			return {"position": Vector3(0.16, 1.99, 3.20), "target": Vector3(-0.13, 1.05, -0.51), "fov": 62.0}


func set_station(station: String) -> void:
	_station = station
	_pose_weapon()


func update_state(snapshot: Dictionary) -> void:
	_state = snapshot.duplicate(true)
	if not _built:
		return
	_target_heat = float(snapshot.get("temperature", 20.0))
	_stage = str(snapshot.get("stage", "idle"))
	_work_mode = str(snapshot.get("work_mode", "forge"))
	var selected: Dictionary = snapshot.get("selected_weapon", {})
	var modifiers: Dictionary = selected.get("smithing", {})
	var signature := JSON.stringify([snapshot.get("recipe_id", "iron_longsword"), modifiers, snapshot.get("drill_progress", 0)])
	if signature != _weapon_signature:
		_weapon_signature = signature
		_rebuild_weapon(modifiers)
	var heat := smoothstep(400.0, 1050.0, _target_heat)
	_iron_material.albedo_color = Color(0.36, 0.37, 0.38).lerp(Color(1.0, 0.34, 0.038), heat)
	_iron_material.emission_enabled = heat > 0.0
	_iron_material.emission = Color(1.0, 0.17, 0.008).lerp(Color(1.0, 0.66, 0.14), heat)
	_iron_material.emission_energy_multiplier = heat * 0.78
	_pose_weapon()


func animate_action(action: String) -> void:
	_build()
	_action = action
	_action_time = 0.0
	if action in ["hammer", "strike"]:
		_spark_root.visible = _target_heat > 500.0
	if action in ["quench", "cool"]:
		_steam_root.visible = true
		_ripples.visible = true


func _build() -> void:
	if _built:
		return
	_built = true
	_materials = {
		"stone": SURFACES.stone(Color(0.37, 0.35, 0.31), 1.4),
		"soot": SURFACES.stone(Color(0.15, 0.13, 0.11), 2.0),
		"mortar": SURFACES.stone(Color(0.20, 0.19, 0.17), 2.0),
		"wood": SURFACES.old_oak(Color(0.28, 0.24, 0.19), 1.2),
		"wood_light": SURFACES.old_oak(Color(0.48, 0.40, 0.31), 0.95),
		"iron": SURFACES.pitted_iron(Color(0.22, 0.24, 0.25), 3.2),
		"steel": SURFACES.pitted_iron(Color(0.53, 0.55, 0.56), 2.5),
		"leather": SURFACES.leather(Color(0.22, 0.13, 0.074), 4.2),
		"brass": _plain(Color(0.40, 0.29, 0.13), 0.78, 0.45),
		"coal": SURFACES.stone(Color(0.027, 0.024, 0.024), 4.0),
		"socket": _plain(Color(0.032, 0.04, 0.046), 0.7, 0.56),
	}
	_iron_material = SURFACES.pitted_iron(Color(0.36, 0.37, 0.38), 5.0)
	_rune_material = _plain(Color(0.07, 0.39, 0.47), 0.4, 0.28)
	_rune_material.emission_enabled = true
	_rune_material.emission = Color(0.035, 0.46, 0.72)
	_rune_material.emission_energy_multiplier = 0.42
	_build_architecture()
	_build_forge()
	_build_bellows()
	_build_anvil()
	_build_water()
	_build_workbench()
	_batch_static_geometry()
	_build_tools()
	_build_effects()
	_weapon = _node(self, "Workpiece")
	_blade_root = _node(_weapon, "ForgedBlade")
	_grip_root = _node(_weapon, "HiltAndGrip")
	_socket_root = _node(_weapon, "DrilledSocketsAndRunes")
	_rebuild_weapon({})
	set_meta("blacksmith_real_geometry", true)
	set_meta("smithing_stations", ["fire", "bellows", "anvil", "quench", "upgrade"])


func _build_architecture() -> void:
	var room := _node(self, "SootAndTimberWorkshop")
	_box(room, "StoneFloor", Vector3(4.25, 0.12, 3.1), Vector3(0, -0.08, -0.22), _materials.mortar)
	for row in range(7):
		for column in range(9):
			var at := Vector3(-1.89 + column * 0.464 + (0.11 if row % 2 else 0.0), -0.005, -1.43 + row * 0.423)
			var paver := _mesh(room, "ChippedFloorPaver", _chipped_block(Vector3(0.445, 0.056, 0.399), at), _materials.stone if (column + row * 3) % 4 else _materials.mortar)
			paver.position = at
			paver.rotation.y = sin(row * 9.1 + column * 2.7) * 0.022
	for side in [-1, 1]:
		for row in range(7):
			for column in range(5):
				var at := Vector3(side * 2.13, 0.18 + row * 0.37, -1.21 + column * 0.48)
				var stone := _mesh(room, "EnclosingSideWallStone", _chipped_block(Vector3(0.22, 0.352, 0.465), at), _materials.soot)
				stone.position = at
	for row in range(7):
		for column in range(10):
			var x := float(column) * 0.445 - 2.05 + (0.12 if row % 2 else 0.0)
			var brick := _box(room, "Limestone_%d_%d" % [row, column], Vector3(0.424, 0.354, 0.23), Vector3(x, 0.18 + row * 0.37, -1.47), _materials.soot if column < 5 else _materials.stone)
			brick.rotation.z = sin(float(row * 13 + column * 7)) * 0.009
	for column in range(3):
		var x := -2.06 + float(column) * 2.06
		_box(room, "OakUpright", Vector3(0.19, 2.88, 0.21), Vector3(x, 1.44, -1.31), _materials.wood)
		for y in [0.30, 1.95]:
			_box(room, "UprightBand", Vector3(0.204, 0.069, 0.224), Vector3(x, y, -1.31), _materials.iron)
	_box(room, "OverheadLintel", Vector3(4.34, 0.23, 0.26), Vector3(0, 2.72, -1.30), _materials.wood)
	for side in [-1, 1]:
		var brace := _box(room, "CornerBrace", Vector3(0.12, 0.90, 0.12), Vector3(float(side) * 1.73, 2.36, -1.17), _materials.wood)
		brace.rotation.z = float(side) * 0.71
	for index in range(14):
		var shard := _sphere(room, "HammerScale", Vector3(0.04, 0.012, 0.05), Vector3(-0.64 + sin(index * 7.3) * 0.62, 0.004, 0.33 + cos(index * 3.1) * 0.45), _materials.coal, 5, 3)
		shard.rotation.y = index * 1.3


func _build_forge() -> void:
	var forge := _node(self, "MasonryCoalForge", FIRE)
	_box(forge, "HearthCore", Vector3(1.37, 0.77, 0.96), Vector3(0, 0.385, -0.13), _materials.mortar)
	for layer in range(3):
		for index in range(4):
			_box(forge, "HearthFaceStone", Vector3(0.33, 0.237, 0.15), Vector3(-0.51 + index * 0.34, 0.125 + layer * 0.25, 0.355), _materials.stone)
	_box(forge, "AshDoor", Vector3(0.36, 0.28, 0.031), Vector3(0, 0.31, 0.442), _materials.iron)
	for index in range(5):
		_box(forge, "AirSlot", Vector3(0.025, 0.16, 0.008), Vector3(-0.115 + 0.058 * index, 0.31, 0.462), _materials.coal)
	_box(forge, "HearthLip", Vector3(1.44, 0.135, 1.02), Vector3(0, 0.81, -0.13), _materials.soot)
	for side in [-1, 1]:
		for layer in range(2):
			_box(forge, "FireplaceJamb", Vector3(0.245, 0.28, 0.64), Vector3(float(side) * 0.56, 1.01 + layer * 0.292, -0.31), _materials.soot)
	for index in range(9):
		var a0 := float(index) * PI / 9.0 + 0.013
		var a1 := float(index + 1) * PI / 9.0 - 0.013
		var polygon := PackedVector2Array([
			Vector2(cos(a0) * 0.44, sin(a0) * 0.44 + 1.36),
			Vector2(cos(a0) * 0.69, sin(a0) * 0.69 + 1.36),
			Vector2(cos(a1) * 0.69, sin(a1) * 0.69 + 1.36),
			Vector2(cos(a1) * 0.44, sin(a1) * 0.44 + 1.36)])
		var wedge := _mesh(forge, "ArchVoussoir_%02d" % index, _extrude(polygon, -0.63, 0.035), _materials.soot)
		wedge.rotation.x = PI / 2.0
	# The voussoir mesh is generated in X/Z then stood upright. Its positive
	# polygon-Y becomes world Y after a -90° rotation.
	for child in forge.get_children():
		if str(child.name).begins_with("ArchVoussoir"):
			child.rotation.x = -PI / 2.0
			child.position.z = -0.65
	_box(forge, "Chimney", Vector3(1.17, 0.73, 0.57), Vector3(0, 2.39, -0.35), _materials.soot)
	for index in range(27):
		var angle := float(index) * 2.39996
		var radius := sqrt(float(index) / 27.0) * 0.40
		var coal := _sphere(forge, "Coal_%02d" % index, Vector3(0.09, 0.065, 0.08), Vector3(cos(angle) * radius, 0.91 + sin(index * 8.0) * 0.028, -0.20 + sin(angle) * radius * 0.60), _materials.coal, 7, 4)
		coal.rotation = Vector3(index * 0.53, index * 0.71, index * 0.33)
		if index % 3 == 0:
			var ember := _plain(Color(0.63, 0.13, 0.006), 0.1, 0.85)
			ember.emission_enabled = true
			ember.emission = Color(1.0, 0.14, 0.004)
			ember.emission_energy_multiplier = 0.9
			coal.material_override = ember
	_fire_sprite = Sprite3D.new()
	_fire_sprite.name = "LivingCoalFire"
	_fire_sprite.texture = FIRE_TEXTURE
	_fire_sprite.pixel_size = 0.00049
	_fire_sprite.position = Vector3(0, 1.065, -0.19)
	forge.add_child(_fire_sprite)
	FLAME.attach(_fire_sprite)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "ForgeFirelight"
	_fire_light.position = Vector3(0, 1.21, 0.02)
	_fire_light.light_color = Color(1.0, 0.43, 0.13)
	_fire_light.light_energy = 1.6
	_fire_light.omni_range = 4.0
	_fire_light.shadow_enabled = true
	forge.add_child(_fire_light)


func _build_bellows() -> void:
	var bellows := _node(self, "WorkingLeatherBellows", Vector3(-1.85, 0.80, -0.27))
	bellows.rotation.y = -0.30
	var outline := PackedVector2Array([Vector2(-0.13, -0.49), Vector2(0.11, -0.49), Vector2(0.28, 0.19), Vector2(0.17, 0.41), Vector2(-0.17, 0.41), Vector2(-0.28, 0.19)])
	_mesh(bellows, "LowerOakLeaf", _extrude(outline, -0.055, 0.0), _materials.wood)
	_bellows_top = _node(bellows, "MovingUpperLeaf", Vector3(0, 0.24, 0))
	_mesh(_bellows_top, "UpperOakLeaf", _extrude(outline, 0.0, 0.055), _materials.wood_light)
	_box(_bellows_top, "PullHandle", Vector3(0.42, 0.06, 0.07), Vector3(0, 0.035, 0.42), _materials.wood_light)
	_bellows_skin = _node(bellows, "FoldingLeather", Vector3(0, 0.0, 0))
	for index in range(5):
		var fold := _mesh(_bellows_skin, "LeatherPleat_%d" % index, _extrude(outline, 0.019, 0.056), _materials.leather)
		fold.position.y = float(index) * 0.048
		fold.scale = Vector3(1.0 + (0.03 if index % 2 == 0 else -0.03), 1.0, 1.0)
	for z in [-0.24, 0.16]:
		_box(_bellows_top, "LeafIronStrap", Vector3(0.36 if z > 0 else 0.25, 0.009, 0.035), Vector3(0, 0.060, z), _materials.iron)
	for side in [-1, 1]:
		for z in [-0.28, 0.21]:
			_sphere(_bellows_top, "ForgedRivet", Vector3.ONE * 0.014, Vector3(float(side) * (0.15 if z > 0 else 0.09), 0.067, z), _materials.iron, 7, 4)
	_cylinder_between(bellows, "IronAirNozzle", Vector3(0, 0.06, -0.40), Vector3(0.42, 0.09, -0.70), 0.046, _materials.iron)
	for z in [-0.31, 0.27]:
		_box(bellows, "BellowsTrestle", Vector3(0.10, 0.76, 0.12), Vector3(0, -0.42, z), _materials.wood)


func _build_anvil() -> void:
	var anvil := _node(self, "HornedForgedAnvil", ANVIL)
	_cylinder(anvil, "OakStump", 0.34, 0.29, 0.55, Vector3(0, 0.275, 0), _materials.wood, 15)
	_cylinder(anvil, "StumpEndgrain", 0.325, 0.325, 0.020, Vector3(0, 0.558, 0), _materials.wood_light, 15)
	for height in [0.10, 0.46]:
		_torus(anvil, "StumpIronHoop", 0.326, 0.012, Vector3(0, height, 0), _materials.iron)
	for index in range(16):
		var a := index * TAU / 16.0
		_cylinder_between(anvil, "BarkCrevice", Vector3(cos(a) * 0.334, 0.02, sin(a) * 0.334), Vector3(cos(a + 0.016) * 0.304, 0.54, sin(a + 0.016) * 0.304), 0.006, _materials.soot)
	# A forged waist, flared feet and shaped heel/horn, not a rectangular prop.
	var profile := [Vector3(0.0, 0.575, 0.0), Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.69, 0.0), Vector3(0.0, 0.78, 0.0), Vector3(0.0, 0.85, 0.0), Vector3(0.0, 0.92, 0.0)]
	_mesh(anvil, "FlaredBody", _loft_rectangles(profile, [Vector2(0.33, 0.22), Vector2(0.31, 0.21), Vector2(0.18, 0.13), Vector2(0.16, 0.12), Vector2(0.29, 0.155), Vector2(0.39, 0.16)]), _materials.iron)
	var top_outline := PackedVector2Array([Vector2(-0.43, -0.15), Vector2(0.37, -0.15), Vector2(0.52, -0.125), Vector2(0.52, 0.125), Vector2(0.37, 0.15), Vector2(-0.43, 0.15)])
	_mesh(anvil, "HardenedStrikingFace", _extrude(top_outline, 0.918, 0.957), _materials.steel)
	var horn := _node(anvil, "TaperedRoundHorn", Vector3(-0.41, 0.90, 0))
	_mesh(horn, "ForgedHorn", _horn_mesh(), _materials.steel)
	_box(anvil, "HardyHole", Vector3(0.047, 0.003, 0.047), Vector3(0.36, 0.960, 0.02), _materials.socket)
	_cylinder(anvil, "PritchelHole", 0.016, 0.016, 0.004, Vector3(0.45, 0.959, -0.015), _materials.socket, 12)
	for index in range(22):
		var x := -0.30 + float(index % 7) * 0.094
		var z := -0.11 + floorf(float(index) / 7.0) * 0.061
		var mark := _box(anvil, "HammerFaceScar", Vector3(0.025, 0.001, 0.0015), Vector3(x, 0.9585, z), _materials.iron)
		mark.rotation.y = float(index) * 0.77
	for side in [-1, 1]:
		_box(anvil, "AnchorStaple", Vector3(0.035, 0.10, 0.042), Vector3(float(side) * 0.29, 0.59, 0.10), _materials.iron)


func _build_water() -> void:
	var tub := _node(self, "QuenchingWaterTrough", WATER)
	_cylinder(tub, "OakTubBottom", 0.39, 0.39, 0.075, Vector3(0, 0.09, 0), _materials.wood, 24)
	for index in range(24):
		var a0 := index * TAU / 24.0 + 0.004
		var a1 := (index + 1) * TAU / 24.0 - 0.004
		var stave_outline := PackedVector2Array([Vector2(cos(a0), sin(a0)) * 0.355, Vector2(cos(a0), sin(a0)) * 0.421, Vector2(cos(a1), sin(a1)) * 0.421, Vector2(cos(a1), sin(a1)) * 0.355])
		_mesh(tub, "IndividualOakStave", _extrude(stave_outline, 0.09, 0.634 + sin(index * 2.71) * 0.011), _materials.wood_light if index % 3 else _materials.wood)
	for height in [0.17, 0.53]:
		var band := CylinderMesh.new()
		band.top_radius = 0.427
		band.bottom_radius = 0.427
		band.height = 0.05
		band.cap_top = false
		band.cap_bottom = false
		band.radial_segments = 32
		var hoop := _mesh(tub, "ForgedIronHoop", band, _materials.iron)
		hoop.position.y = height
		for index in range(8):
			var angle := index * TAU / 8.0
			_sphere(tub, "HoopRivet", Vector3.ONE * 0.01, Vector3(cos(angle) * 0.43, height, sin(angle) * 0.43), _materials.iron, 6, 3)
	var water_shader := Shader.new()
	water_shader.code = """shader_type spatial;
render_mode cull_disabled;
void vertex(){ VERTEX.y += sin(VERTEX.x * 22.0 + TIME * 1.8) * cos(VERTEX.z * 19.0 + TIME * 1.3) * 0.003; }
void fragment(){ float ripple = sin(UV.x * 86.0 + TIME * 1.7) * cos(UV.y * 61.0 + TIME); ALBEDO = vec3(0.055,0.084,0.081) + ripple * 0.009; METALLIC = 0.35; ROUGHNESS = 0.22; NORMAL_MAP = vec3(0.5 + ripple * 0.09, 0.5, 1.0); }
"""
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	_cylinder(tub, "WaterSurface", 0.354, 0.354, 0.008, Vector3(0, 0.516, 0), water_mat, 32)
	_ripples = _node(tub, "QuenchRipples", Vector3(0, 0.526, 0))
	var ripple_mat := _plain(Color(0.16, 0.23, 0.22), 0.2, 0.2)
	for index in range(3):
		_torus(_ripples, "WaterRing", 0.067 + 0.07 * index, 0.0018, Vector3.ZERO, ripple_mat)
	_ripples.visible = false


func _build_workbench() -> void:
	var bench := _node(self, "RuneAndGripWorkbench", BENCH)
	for x in [-0.63, 0.63]:
		for z in [-0.26, 0.26]:
			_box(bench, "TrestleLeg", Vector3(0.11, 0.86, 0.11), Vector3(x, 0.44, z), _materials.wood)
	_box(bench, "LowBrace", Vector3(1.40, 0.09, 0.085), Vector3(0, 0.25, 0.21), _materials.wood)
	for row in range(4):
		_box(bench, "ScarredOakPlank", Vector3(1.51, 0.09, 0.179), Vector3(0, 0.90, -0.274 + row * 0.182), _materials.wood_light)
	for index in range(24):
		var nick := _box(bench, "WorktopKnifeScar", Vector3(0.04 + (index % 4) * 0.016, 0.0012, 0.0018), Vector3(sin(index * 4.23) * 0.64, 0.946, cos(index * 3.14 + 0.8) * 0.24), _materials.soot)
		nick.rotation.y = index * 0.31
	_box(bench, "LeatherWorkMat", Vector3(0.81, 0.018, 0.52), Vector3(-0.09, 0.955, 0.04), _materials.leather)
	var vice := _node(bench, "DrillingVice", Vector3(-0.57, 0.98, 0.09))
	_box(vice, "ViceBody", Vector3(0.16, 0.12, 0.19), Vector3(0, 0.03, 0), _materials.iron)
	for z in [-0.085, 0.085]:
		_box(vice, "ViceJaw", Vector3(0.22, 0.06, 0.035), Vector3(0, 0.12, z), _materials.steel)
	_cylinder_between(vice, "ThreadedViceScrew", Vector3(0, 0.04, -0.10), Vector3(0, 0.04, 0.26), 0.019, _materials.steel)
	_cylinder_between(vice, "ViceScrewBar", Vector3(-0.12, 0.04, 0.26), Vector3(0.12, 0.04, 0.26), 0.011, _materials.iron)
	for index in range(3):
		var tray := _node(bench, "RuneTray_%d" % index, Vector3(0.54, 0.969, -0.20 + index * 0.19))
		_box(tray, "TrayBottom", Vector3(0.24, 0.025, 0.14), Vector3.ZERO, _materials.wood)
		for side in [-1, 1]:
			_box(tray, "TrayEdge", Vector3(0.24, 0.027, 0.018), Vector3(0, 0.02, side * 0.07), _materials.wood)
			_box(tray, "TrayEdge", Vector3(0.018, 0.027, 0.14), Vector3(side * 0.12, 0.02, 0), _materials.wood)
		for gem in range(3):
			_sphere(tray, "UncutRuneStone", Vector3(0.025, 0.030, 0.020), Vector3(-0.066 + gem * 0.065, 0.038, sin(gem * 2.7) * 0.024), _rune_material if index == 0 else _materials.steel, 5, 3)
	for index in range(3):
		var grip := _cylinder(bench, "SpareWrappedGrip", 0.021, 0.026, 0.20, Vector3(-0.33 + index * 0.11, 0.988, -0.23), _materials.leather, 12)
		grip.rotation.x = PI / 2.0
	var rack := _node(self, "WallToolRack", Vector3(0.94, 1.69, -1.285))
	_box(rack, "HangingRail", Vector3(1.78, 0.095, 0.045), Vector3.ZERO, _materials.wood_light)
	for index in range(6):
		var x := -0.72 + index * 0.278
		_cylinder_between(rack, "IronToolPeg", Vector3(x, 0.014, 0.02), Vector3(x, 0.014, 0.09), 0.013, _materials.iron)
		var tool := _node(rack, "HangingTool_%d" % index, Vector3(x, -0.035, 0.094))
		tool.rotation.z = sin(index * 5.1) * 0.09
		if index % 3 == 0:
			_cylinder_between(tool, "WoodHandle", Vector3(0, 0, 0), Vector3(0, -0.36, 0), 0.019, _materials.wood_light)
			_box(tool, "HammerHead", Vector3(0.16, 0.068, 0.065), Vector3(0, -0.33, 0), _materials.iron)
		elif index % 3 == 1:
			for side in [-1, 1]:
				_cylinder_between(tool, "TongsHandle", Vector3(side * 0.035, 0, 0), Vector3(side * 0.020, -0.40, 0), 0.011, _materials.iron)
				_cylinder_between(tool, "TongsJaw", Vector3(side * 0.02, -0.4, 0), Vector3(side * 0.041, -0.48, 0), 0.013, _materials.iron)
		else:
			_cylinder_between(tool, "FileHandle", Vector3(0, 0, 0), Vector3(0, -0.15, 0), 0.022, _materials.wood_light)
			_box(tool, "LongFileBlade", Vector3(0.033, 0.28, 0.016), Vector3(0, -0.29, 0), _materials.steel)
	# Spare billets and a small coal basket make the stations read as a place
	# where materials are handled, rather than disconnected interaction props.
	for index in range(5):
		var billet := _box(self, "StackedIronBillet", Vector3(0.095, 0.075, 0.43), Vector3(0.49 + (index % 2) * 0.11, 0.06 + floorf(float(index) / 2.0) * 0.074, -0.93), _materials.iron)
		billet.rotation.y = 0.12


func _build_tools() -> void:
	_hammer = _node(self, "AnimatedSmithHammer", ANVIL + Vector3(0.38, 1.15, 0.40))
	_cylinder_between(_hammer, "AshwoodHandle", Vector3(0, 0.025, 0), Vector3(0, 0.29, 0), 0.019, _materials.wood_light)
	var head_outline := PackedVector2Array([Vector2(-0.122, -0.047), Vector2(0.076, -0.047), Vector2(0.135, -0.021), Vector2(0.135, 0.021), Vector2(0.076, 0.047), Vector2(-0.122, 0.047)])
	_mesh(_hammer, "CrossPeenHammerHead", _extrude(head_outline, 0.25, 0.34), _materials.iron)
	_box(_hammer, "PolishedHammerFace", Vector3(0.015, 0.087, 0.089), Vector3(-0.119, 0.29, 0), _materials.steel)
	_hammer.rotation = Vector3(-0.48, 0.0, -0.42)
	_hammer_rest = _hammer.transform
	_tongs = _node(self, "AnimatedForgingTongs", ANVIL + Vector3(-0.36, 0.99, 0.34))
	for side in [-1, 1]:
		_cylinder_between(_tongs, "LongRein", Vector3(side * 0.045, 0, 0.41), Vector3(-side * 0.010, 0, -0.04), 0.010, _materials.iron)
		_cylinder_between(_tongs, "CurvedJaw", Vector3(-side * 0.01, 0, -0.04), Vector3(side * 0.018, 0, -0.16), 0.012, _materials.steel)
		_cylinder_between(_tongs, "Bit", Vector3(side * 0.018, 0, -0.16), Vector3(side * 0.012, 0, -0.22), 0.012, _materials.steel)
	_cylinder(_tongs, "PivotRivet", 0.020, 0.020, 0.037, Vector3(0, 0.008, -0.005), _materials.steel, 12)
	_tongs.rotation.y = -0.32
	_tongs_rest = _tongs.transform
	_drill = _node(self, "AnimatedBraceDrill", BENCH + Vector3(0, 1.21, 0.01))
	_cylinder_between(_drill, "DrillBit", Vector3(0, -0.23, 0), Vector3(0, 0, 0), 0.008, _materials.steel)
	_cylinder_between(_drill, "LowerBrace", Vector3(0, 0, 0), Vector3(0.13, 0.075, 0), 0.012, _materials.iron)
	_cylinder_between(_drill, "CrankArm", Vector3(0.13, 0.075, 0), Vector3(0.13, 0.26, 0), 0.012, _materials.iron)
	_cylinder_between(_drill, "UpperBrace", Vector3(0.13, 0.26, 0), Vector3(0, 0.31, 0), 0.012, _materials.iron)
	_cylinder(_drill, "CrankWoodGrip", 0.027, 0.027, 0.125, Vector3(0.13, 0.17, 0), _materials.wood_light, 12)
	_sphere(_drill, "PalmPressurePad", Vector3(0.067, 0.025, 0.067), Vector3(0, 0.335, 0), _materials.wood_light, 14, 7)
	_drill_rest = _drill.transform
	_file_tool = _node(self, "WorkingBladeFile", BENCH + Vector3(0, 1.09, 0.13))
	_box(_file_tool, "CrossCutFile", Vector3(0.25, 0.02, 0.04), Vector3(-0.04, 0, 0), _materials.steel)
	_cylinder_between(_file_tool, "FileGrip", Vector3(0.09, 0, 0), Vector3(0.23, 0, 0), 0.024, _materials.wood_light)
	_held_rune = _node(self, "HandHeldRuneFragment")
	_sphere(_held_rune, "FacetedRuneFragment", Vector3(0.015, 0.019, 0.015), Vector3.ZERO, _rune_material, 6, 3)


func _build_effects() -> void:
	_spark_root = _node(self, "HammerImpactSparks", ANVIL + Vector3(0, 0.99, 0))
	var spark_mat := _plain(Color(1.0, 0.52, 0.08), 0.0, 1.0)
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.30, 0.01)
	spark_mat.emission_energy_multiplier = 2.0
	for index in range(16):
		var spark := _box(_spark_root, "HotScale", Vector3(0.005, 0.024, 0.005), Vector3.ZERO, spark_mat)
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark_root.visible = false
	_steam_root = _node(self, "QuenchingSteam", WATER + Vector3(0, 0.55, 0))
	for index in range(8):
		var steam := Sprite3D.new()
		steam.name = "RisingSteam_%d" % index
		steam.texture = FLAME.steam_texture()
		steam.pixel_size = 0.003
		steam.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		steam.no_depth_test = false
		steam.shaded = false
		steam.modulate = Color(0.78, 0.83, 0.85, 0.48)
		_steam_root.add_child(steam)
	_steam_root.visible = false


func _batch_static_geometry() -> void:
	# Architectural blocks, nails, rails, spare tools and coal share existing
	# textures. Merge their transformed mesh surfaces once by material so the
	# detailed workshop has tens of draw calls instead of hundreds. Moving
	# bellows/fire/ripples and the hero anvil silhouette remain independent.
	var groups: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	_collect_static(self, Transform3D.IDENTITY, groups, originals)
	var expected_triangles := 0
	for original in originals:
		expected_triangles += _triangle_count(original.mesh)
	var merged_triangles := 0
	var merged := _node(self, "BatchedWorkshopSurfaces")
	for key: int in groups:
		var group: Dictionary = groups[key]
		var surface: SurfaceTool = group.surface
		var joined := surface.commit()
		merged_triangles += _triangle_count(joined)
		_mesh(merged, "WorkshopSurface_%d" % key, joined, group.material)
	for original in originals:
		original.get_parent().remove_child(original)
		original.queue_free()
	set_meta("static_meshes_batched", originals.size())
	set_meta("static_draw_surfaces", groups.size())
	set_meta("static_expected_triangles", expected_triangles)
	set_meta("static_merged_triangles", merged_triangles)


func _triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += floori(float(indices.size() if not indices.is_empty() else vertices.size()) / 3.0)
	return count


func _collect_static(parent: Node3D, relative: Transform3D, groups: Dictionary, originals: Array[MeshInstance3D]) -> void:
	for child in parent.get_children():
		if not child is Node3D or child in [_bellows_top, _bellows_skin, _ripples, _fire_sprite]:
			continue
		var child_node := child as Node3D
		var transform_to_root := relative * child_node.transform
		if child is MeshInstance3D and child.name != "ForgedHorn":
			var instance := child as MeshInstance3D
			var material := instance.material_override
			if material != null and instance.mesh != null:
				var key := material.get_instance_id()
				if not groups.has(key):
					var new_builder := SurfaceTool.new()
					new_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = {"surface": new_builder, "material": material}
				var builder: SurfaceTool = groups[key].surface
				for surface_index in range(instance.mesh.get_surface_count()):
					builder.append_from(instance.mesh, surface_index, transform_to_root)
				originals.append(instance)
		_collect_static(child_node, transform_to_root, groups, originals)


func _rebuild_weapon(modifiers: Dictionary) -> void:
	for target in [_blade_root, _grip_root, _socket_root]:
		for child in target.get_children():
			target.remove_child(child)
			child.queue_free()
	var socket_count := int(modifiers.get("socket_count", modifiers.get("sockets", 0))) if not modifiers.get("sockets", 0) is Array else (modifiers.get("sockets") as Array).size()
	var runes: Array = modifiers.get("runes", [])
	socket_count = clampi(maxi(socket_count, runes.size()), 0, 2)
	var length_scale := 0.83 if str(_state.get("recipe_id", "iron_longsword")) == "iron_arming_sword" else 1.0
	# Each bored section is a true ring-to-square mesh with an open centre and
	# dark cylindrical walls. No black decal is used to imitate a socket.
	var blade_bottom := 0.004
	var blade_top := 0.023
	var starts := [-0.13, -0.38, -0.63]
	for index in range(3):
		var center := float(starts[index])
		if index < socket_count:
			_mesh(_blade_root, "BoredBladeSection_%d" % index, _socket_plate(0.035, center, 0.125, 0.016, blade_bottom, blade_top), _iron_material)
			_mesh(_socket_root, "SocketInterior_%d" % index, _socket_wall(0.016, center, blade_bottom, blade_top), _materials.socket)
			_torus(_socket_root, "EngravedSocketRim_%d" % index, 0.018, 0.002, Vector3(0, blade_top + 0.002, center), _materials.steel)
			if index < runes.size() and not str(runes[index]).is_empty():
				var gem := _sphere(_socket_root, "SeatedRune_%d" % index, Vector3(0.015, 0.013, 0.015), Vector3(0, blade_top + 0.003, center), _rune_material, 6, 3)
				gem.rotation.y = PI / 6.0
				for bar in range(3):
					var glyph := _box(_socket_root, "RuneGlyph", Vector3(0.0015, 0.001, 0.013), Vector3(-0.004 + bar * 0.004, blade_top + 0.016, center), _materials.steel)
					glyph.rotation.y = -0.4 + bar * 0.4
		else:
			_box(_blade_root, "BladeWeb_%d" % index, Vector3(0.07, blade_top - blade_bottom, 0.25), Vector3(0, (blade_top + blade_bottom) * 0.5, center), _iron_material)
	var tip := PackedVector2Array([Vector2(-0.035, -0.755), Vector2(0, -0.925), Vector2(0.035, -0.755)])
	_mesh(_blade_root, "GroundPoint", _extrude(tip, blade_bottom, blade_top), _iron_material)
	var edge_id := str(modifiers.get("blade", modifiers.get("reinforcement", modifiers.get("edge", ""))))
	var edge_mat: Material = _materials.steel
	if edge_id == "silver_edge":
		edge_mat = _plain(Color(0.75, 0.79, 0.82), 0.92, 0.26)
	for side in [-1, 1]:
		var edge_outline := PackedVector2Array([Vector2(side * 0.035, -0.005), Vector2(side * 0.043, -0.02), Vector2(side * 0.043, -0.72), Vector2(0, -0.925), Vector2(side * 0.035, -0.755)])
		_mesh(_blade_root, "HonedEdge", _extrude(edge_outline, 0.010, 0.016), edge_mat if not edge_id.is_empty() else _iron_material)
	_cylinder_between(_grip_root, "BladeTang", Vector3(0, 0.012, 0.0), Vector3(0, 0.012, 0.24), 0.012, _materials.iron)
	var guard_outline := PackedVector2Array([Vector2(-0.175, -0.009), Vector2(-0.162, 0.026), Vector2(-0.06, 0.018), Vector2(0.06, 0.018), Vector2(0.162, 0.026), Vector2(0.175, -0.009), Vector2(0.06, -0.026), Vector2(-0.06, -0.026)])
	_mesh(_grip_root, "SweptCrossguard", _extrude(guard_outline, -0.006, 0.043), _materials.iron)
	var grip_id := str(modifiers.get("grip", "leather_grip"))
	_cylinder_between(_grip_root, "WrappedLeatherGrip", Vector3(0, 0.015, 0.033), Vector3(0, 0.015, 0.216), 0.026 if grip_id != "balanced_grip" else 0.023, _materials.leather)
	for index in range(12):
		var ring := _torus(_grip_root, "GripWrapSeam", 0.026, 0.0024, Vector3(0, 0.015, 0.035 + index * 0.015), _materials.wood if grip_id == "balanced_grip" else _materials.iron)
		ring.rotation.x = PI / 2.0
	var pommel := _cylinder(_grip_root, "WheelPommel", 0.043, 0.043, 0.029, Vector3(0, 0.018, 0.252), _materials.brass if grip_id == "balanced_grip" else _materials.steel, 12)
	pommel.rotation.x = PI / 2.0
	_weapon.scale = Vector3(1, 1, length_scale)
	_weapon.set_meta("visible_socket_count", socket_count)
	_weapon.set_meta("visible_rune_count", runes.size())


func _pose_weapon() -> void:
	if not is_instance_valid(_weapon):
		return
	var upgrade := _station in ["upgrade", "drill", "rune", "workbench"] or _stage == "finished"
	_grip_root.visible = _stage in ["idle", "finished"] or upgrade
	_drill.visible = upgrade and _work_mode == "rune" and _action != "insert_rune"
	_file_tool.visible = upgrade and _work_mode == "blade"
	_held_rune.visible = upgrade and _work_mode == "rune" and _action == "insert_rune" and _action_time < 0.65
	_hammer.visible = not upgrade and _stage != "fire"
	_tongs.visible = not upgrade and _stage not in ["idle", "finished"]
	if upgrade:
		_weapon.position = BENCH + Vector3(0.22, 0.973, 0.23)
		_weapon.rotation = Vector3(0, 1.04, 0)
	elif _stage == "fire":
		_weapon.position = FIRE + Vector3(-0.10, 0.95, 0.39)
		_weapon.rotation = Vector3(0, -0.20, 0)
		_tongs.position = _weapon.position + Vector3(-0.11, 0, 0.05)
		_tongs.rotation.y = -0.20
	elif _stage == "quenched" or _station == "quench":
		_weapon.position = WATER + Vector3(0, 0.61, 0.13)
		_weapon.rotation = Vector3(-0.28, 0.1, 0)
		_tongs.position = _weapon.position + Vector3(0, 0.02, 0.16)
		_tongs.rotation.y = 0.1
	else:
		var section := clampi(int(_state.get("selected_section", 1)), 0, 2)
		var longitudinal := 0.13 + section * 0.25
		_weapon.rotation = Vector3(0, -0.97, 0)
		_weapon.position = ANVIL + Vector3(0, 0.965, 0) + _weapon.basis.z * longitudinal
		if int(_state.get("side", 0)) == 1:
			_weapon.rotation.z = PI
			_weapon.position.y += 0.028
		_tongs.position = _weapon.position + _weapon.basis.z * 0.22
		_tongs.rotation = Vector3(0, -0.97, 0)


func _process(delta: float) -> void:
	if not _built:
		return
	_clock += delta
	_action_time += delta
	var beat := sin(_clock * 9.2) * 0.05 + sin(_clock * 17.3) * 0.035
	var heat := smoothstep(20.0, 1000.0, _target_heat)
	_fire_light.light_energy = 1.5 + heat * 1.1 + beat
	_fire_sprite.scale = Vector3.ONE * (1.0 + heat * 0.35 + beat * 0.45)
	var pulse := sin(clampf(_action_time / 0.65, 0.0, 1.0) * PI)
	var pumping := _action in ["bellows", "pump_bellows", "pump"] and _action_time < 0.65
	_bellows_top.position.y = 0.24 - (pulse * 0.15 if pumping else 0.0)
	_bellows_skin.scale.y = 1.0 - (pulse * 0.60 if pumping else 0.0)
	_hammer.transform = _hammer_rest
	var charge := float(_state.get("hammer_charge", 0.0))
	var impact := 0.0
	if _action in ["hammer", "strike"] and _action_time < 0.58:
		impact = sin(clampf(_action_time / 0.36, 0.0, 1.0) * PI)
	var wrist_rest := ANVIL + Vector3(0.33, 1.20 + charge * 0.18, 0.37)
	var wrist_contact := ANVIL + Vector3(0.26, 1.00, 0.27)
	_hammer.position = wrist_rest.lerp(wrist_contact, impact)
	var head_target := ANVIL + Vector3(0.02, 0.988, 0.0)
	var head_rest := ANVIL + Vector3(0.28, 1.42 + charge * 0.22, 0.23)
	var head := head_rest.lerp(head_target, impact)
	_hammer.quaternion = Quaternion(Vector3.UP, (head - _hammer.position).normalized())
	if _action in ["flip", "flip_blade"] and _action_time < 0.5:
		_pose_weapon()
		_weapon.position.y += pulse * 0.075
		_weapon.rotation.z += sin(_action_time / 0.5 * PI) * 0.50
	_drill.transform = _drill_rest
	# A compact brace leaves the pressure hand below the upper HUD. Scale the
	# matching root height as well, keeping the cutting tip on the same bore.
	_drill.scale.y = 0.76
	var bore_at := _weapon.position + _weapon.basis * Vector3(0, 0.023, -0.13)
	if _weapon.get_meta("visible_socket_count", 0) >= 2:
		bore_at = _weapon.position + _weapon.basis * Vector3(0, 0.023, -0.38)
	_drill.position = bore_at + Vector3(0, 0.231 * 0.76, 0)
	if _action in ["drill", "drill_socket"] and _action_time < 1.2:
		_drill.rotation.y = _action_time * TAU * 2.5
		_drill.position.y -= minf(_action_time, 0.5) * 0.027 * 0.76
	_file_tool.position = _weapon.position + _weapon.basis * Vector3(0.02, 0.06, -0.33)
	_file_tool.rotation.y = -0.40
	if _action == "reinforce_blade" and _action_time < 1.0:
		_file_tool.position.x += sin(_action_time * TAU * 3.0) * 0.065
	_held_rune.position = bore_at + Vector3(0.03, 0.13 * (1.0 - clampf(_action_time / 0.65, 0, 1)), 0.02)
	_animate_effects()
	_pose_arms()


func _animate_effects() -> void:
	if _spark_root.visible:
		var t := _action_time - 0.19
		_spark_root.visible = t < 0.50 and _action in ["hammer", "strike"]
		for index in range(_spark_root.get_child_count()):
			var spark := _spark_root.get_child(index) as Node3D
			spark.visible = t >= 0.0
			var angle := float(index) * 2.39996
			var speed := 0.43 + float(index % 5) * 0.19
			spark.position = Vector3(cos(angle) * t * speed, t * (0.65 + (index % 3) * 0.38) - t * t * 2.3, sin(angle) * t * speed)
			spark.rotation = Vector3(angle, t * 8.0, angle)
	if _steam_root.visible:
		var t := _action_time
		_steam_root.visible = t < 3.0 and _action in ["quench", "cool"]
		_ripples.visible = _steam_root.visible
		_ripples.scale = Vector3.ONE * (0.5 + fmod(t * 0.8, 0.8))
		for index in range(_steam_root.get_child_count()):
			var steam := _steam_root.get_child(index) as Sprite3D
			var rise := fmod(t * 0.62 + index * 0.12, 0.85)
			steam.position = Vector3(sin(index * 2.3 + t) * rise * 0.15, rise, cos(index * 4.1) * 0.12)
			steam.scale = Vector3.ONE * (0.45 + rise * 2.2)
			steam.modulate.a = 0.18 * (1.0 - rise) * (1.0 - smoothstep(1.6, 3.0, t))


func _pose_arms() -> void:
	if not is_instance_valid(_camera) or not is_inside_tree() or not _camera.is_inside_tree():
		return
	var active := _stage in ["fire", "anvil", "quenched"] or _station in ["upgrade", "drill", "rune", "workbench"]
	for side in [-1, 1]:
		var arm: Node3D = _arms.get(side)
		if not is_instance_valid(arm):
			continue
		arm.visible = active
		if not active:
			continue
		var target := _hammer.position + _hammer.basis * Vector3(0, 0.115, 0) if side == 1 else _tongs.position + _tongs.basis * Vector3(0, 0, 0.30)
		var hand_yaw := float(side) * 0.25
		if _stage == "fire":
			target = _tongs.position + Vector3(0, 0, 0.32) if side == 1 else Vector3(-1.83, _bellows_top.global_position.y + 0.055, 0.15)
		elif _station in ["upgrade", "drill", "rune", "workbench"] or _stage == "finished":
			if _work_mode == "grip" or _work_mode == "forge":
				target = _weapon.position + _weapon.basis * Vector3(float(side) * 0.025, 0.10, 0.12 if side == 1 else -0.055)
				hand_yaw = -0.9 if side == -1 else 0.7
				if _action == "replace_grip" and side == 1 and _action_time < 0.8:
					target += _weapon.basis.z * sin(_action_time / 0.8 * PI) * 0.07
			elif _work_mode == "blade":
				target = _file_tool.position + _file_tool.basis * Vector3(0.18, 0.05, 0.015) if side == 1 else _weapon.position + _weapon.basis * Vector3(-0.04, 0.07, 0.09)
				hand_yaw = -0.8 if side == 1 else 0.5
			elif _action == "insert_rune":
				target = _held_rune.position + Vector3(0.04, 0.05, 0.05) if side == 1 else _weapon.position + _weapon.basis * Vector3(-0.04, 0.07, 0.08)
			else:
				target = _drill.position + _drill.basis * Vector3(0.17, 0.17, 0.015) if side == 1 else _drill.position + _drill.basis * Vector3(-0.035, 0.36, 0.075)
				hand_yaw = -0.7 if side == -1 else 0.2
		if _stage == "quenched" and side == 1:
			arm.visible = false
			continue
		arm.position = target + Vector3(0, 0.006, 0.06)
		arm.rotation = Vector3(-0.75, hand_yaw, float(side) * -0.17)
		var shoulder := _camera.global_transform * Vector3(side * 0.34, -0.71, 0.24)
		var wanted_elbow := shoulder.lerp(arm.global_position, 0.50) + _camera.global_basis * Vector3(side * 0.13, -0.15, 0.0)
		var elbow := arm.global_position + (wanted_elbow - arm.global_position).limit_length(0.30)
		var upper_start := elbow + (shoulder - elbow).limit_length(0.65)
		if side == -1 and _work_mode == "rune" and _drill.visible:
			# Raised elbow enters from the side at the cap's own depth. The
			# sleeve no longer crosses the lens and conceals the bit and blank.
			elbow = arm.global_position + _camera.global_basis * Vector3(-0.285, 0.025, -0.045)
			upper_start = elbow + _camera.global_basis * Vector3(-0.50, 0.035, -0.065)
		arm.call("fit_arm", upper_start, elbow)


func _plain(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = roughness
	return result


func _node(parent: Node3D, node_name: String, at := Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = node_name
	result.position = at
	parent.add_child(result)
	return result


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = mesh
	result.material_override = material
	parent.add_child(result)
	return result


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var stone_piece := node_name.begins_with("Limestone") or node_name in ["HearthFaceStone", "FireplaceJamb", "Chimney", "HearthLip"]
	var render_mesh: Mesh = shape
	if stone_piece:
		render_mesh = _chipped_block(size, at)
	var result := _mesh(parent, node_name, render_mesh, material)
	result.position = at
	return result


func _sphere(parent: Node3D, node_name: String, radii: Vector3, at: Vector3, material: Material, segments := 12, rings := 6) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = segments
	shape.rings = rings
	var result := _mesh(parent, node_name, shape, material)
	result.scale = radii
	result.position = at
	return result


func _cylinder(parent: Node3D, node_name: String, bottom: float, top: float, height: float, at: Vector3, material: Material, segments := 16) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = segments
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	return result


func _cylinder_between(parent: Node3D, node_name: String, start: Vector3, finish: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var direction := finish - start
	var result := _cylinder(parent, node_name, radius, radius * 0.94, direction.length(), (start + finish) * 0.5, material, 12)
	result.quaternion = Quaternion(Vector3.UP, direction.normalized())
	return result


func _torus(parent: Node3D, node_name: String, radius: float, tube: float, at: Vector3, material: Material) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - tube
	shape.outer_radius = radius + tube
	shape.rings = 24
	shape.ring_segments = 6
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	return result


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for point in [a, b, c]:
		surface.set_uv(Vector2(point.x, point.z))
		surface.add_vertex(point)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(surface, a, b, c)
	_triangle(surface, a, c, d)


func _extrude(outline: PackedVector2Array, bottom: float, top: float) -> ArrayMesh:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index in range(0, triangles.size(), 3):
		var a := outline[triangles[index]]
		var b := outline[triangles[index + 1]]
		var c := outline[triangles[index + 2]]
		_triangle(result, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y))
		_triangle(result, Vector3(c.x, bottom, c.y), Vector3(b.x, bottom, b.y), Vector3(a.x, bottom, a.y))
	for index in range(outline.size()):
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_quad(result, Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y))
	result.generate_normals()
	result.index()
	return result.commit()


func _loft_rectangles(centres: Array, dimensions: Array) -> ArrayMesh:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(centres.size() - 1):
		for corner in range(4):
			var signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			var sa: Vector2 = signs[corner]
			var sb: Vector2 = signs[(corner + 1) % 4]
			var da: Vector2 = dimensions[index]
			var db: Vector2 = dimensions[index + 1]
			var ca: Vector3 = centres[index]
			var cb: Vector3 = centres[index + 1]
			_quad(result, ca + Vector3(sa.x * da.x, 0, sa.y * da.y), ca + Vector3(sb.x * da.x, 0, sb.y * da.y), cb + Vector3(sb.x * db.x, 0, sb.y * db.y), cb + Vector3(sa.x * db.x, 0, sa.y * db.y))
	result.generate_normals()
	result.index()
	return result.commit()


func _chipped_block(size: Vector3, at: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bevel := minf(0.023, minf(size.x, size.z) * 0.095)
	var half := Vector2(size.x, size.z) * 0.5
	var outline := PackedVector2Array([Vector2(-half.x + bevel, -half.y), Vector2(half.x - bevel, -half.y), Vector2(half.x, -half.y + bevel), Vector2(half.x, half.y - bevel), Vector2(half.x - bevel, half.y), Vector2(-half.x + bevel, half.y), Vector2(-half.x, half.y - bevel), Vector2(-half.x, -half.y + bevel)])
	var rings: Array[PackedVector3Array] = []
	for level in range(4):
		var ring := PackedVector3Array()
		var y := [-size.y * 0.5, -size.y * 0.5 + bevel, size.y * 0.5 - bevel, size.y * 0.5][level] as float
		var shrink := 0.974 if level in [0, 3] else 1.0
		for index in range(outline.size()):
			var p := outline[index] * shrink
			var phase := at.x * 12.7 + at.y * 23.1 + index * 4.7
			ring.append(Vector3(p.x + sin(phase) * bevel * 0.26, y + cos(phase * 1.7) * bevel * 0.23, p.y + sin(phase * 0.8) * bevel * 0.26))
		rings.append(ring)
	for level in range(3):
		for index in range(8):
			var next := (index + 1) % 8
			_quad(surface, rings[level][index], rings[level][next], rings[level + 1][next], rings[level + 1][index])
	for index in range(1, 7):
		_triangle(surface, rings[3][0], rings[3][index], rings[3][index + 1])
		_triangle(surface, rings[0][index + 1], rings[0][index], rings[0][0])
	surface.generate_normals()
	surface.index()
	return surface.commit()


func _horn_mesh() -> ArrayMesh:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(6):
		var t0 := float(segment) / 6.0
		var t1 := float(segment + 1) / 6.0
		for radial in range(18):
			var a0 := radial * TAU / 18.0
			var a1 := (radial + 1) * TAU / 18.0
			var r0 := pow(1.0 - t0, 0.72) * 0.135 + 0.002
			var r1 := pow(1.0 - t1, 0.72) * 0.135 + 0.002
			var c0 := Vector3(-t0 * 0.45, t0 * 0.035, 0)
			var c1 := Vector3(-t1 * 0.45, t1 * 0.035, 0)
			_quad(result, c0 + Vector3(0, cos(a1) * r0 * 0.43, sin(a1) * r0), c1 + Vector3(0, cos(a1) * r1 * 0.43, sin(a1) * r1), c1 + Vector3(0, cos(a0) * r1 * 0.43, sin(a0) * r1), c0 + Vector3(0, cos(a0) * r0 * 0.43, sin(a0) * r0))
	result.generate_normals()
	result.index()
	return result.commit()


func _socket_plate(half_width: float, center: float, half_length: float, radius: float, bottom: float, top: float) -> ArrayMesh:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(32):
		var a0 := index * TAU / 32.0
		var a1 := (index + 1) * TAU / 32.0
		var u := Vector2(cos(a0), sin(a0))
		var v := Vector2(cos(a1), sin(a1))
		var outer0 := u * minf(half_width / maxf(absf(u.x), 0.00001), half_length / maxf(absf(u.y), 0.00001))
		var outer1 := v * minf(half_width / maxf(absf(v.x), 0.00001), half_length / maxf(absf(v.y), 0.00001))
		var inner0 := u * radius
		var inner1 := v * radius
		_quad(result, Vector3(outer0.x, top, center + outer0.y), Vector3(outer1.x, top, center + outer1.y), Vector3(inner1.x, top, center + inner1.y), Vector3(inner0.x, top, center + inner0.y))
		_quad(result, Vector3(inner0.x, bottom, center + inner0.y), Vector3(inner1.x, bottom, center + inner1.y), Vector3(outer1.x, bottom, center + outer1.y), Vector3(outer0.x, bottom, center + outer0.y))
	result.generate_normals()
	result.index()
	return result.commit()


func _socket_wall(radius: float, center: float, bottom: float, top: float) -> ArrayMesh:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(24):
		var a := Vector2(cos(index * TAU / 24.0), sin(index * TAU / 24.0)) * radius
		var b := Vector2(cos((index + 1) * TAU / 24.0), sin((index + 1) * TAU / 24.0)) * radius
		_quad(result, Vector3(b.x, top, center + b.y), Vector3(b.x, bottom, center + b.y), Vector3(a.x, bottom, center + a.y), Vector3(a.x, top, center + a.y))
	result.generate_normals()
	result.index()
	return result.commit()
