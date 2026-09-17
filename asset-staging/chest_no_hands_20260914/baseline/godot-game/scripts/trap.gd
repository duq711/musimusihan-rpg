extends Node3D
class_name RuneTrap

signal resolved(trap: RuneTrap, success: bool)

const PLAYER_LAYER := 1
const INTERACT_LAYER := 16
const INSPECT_DURATION := 0.9

const TRAP_SCENE := preload("res://assets/3d/dark_fantasy/blood_rune_trap.glb")
const RUNE_TEXTURE := preload("res://assets/ai/vfx/rune_trap.png")
const PITTED_IRON_TEXTURE := preload("res://assets/ai/materials/pitted_black_iron.png")
const AGED_SURFACES := preload("res://scripts/dark_fantasy_materials.gd")

enum TrapState { ARMED, INSPECTING, DISARMING, DISARMED, TRIGGERED }

var display_name := "속박의 룬 압력판"
var damage := 34.0
var needle_speed := 0.92
var success_width := 0.22
var success_start := 0.55
var success_end := 0.77
var needle_phase := 0.0
var needle_value := 0.0
var state := TrapState.ARMED
var inflicted_condition := ""

var player: DungeonPlayer
var inspecting_player: DungeonPlayer
var hud: DungeonHUD
var game: Node
var trigger_area: Area3D
var interaction_area: Area3D
var plate_material: StandardMaterial3D
var rune_material: StandardMaterial3D
var spike_root: Node3D
var rune_light: OmniLight3D


func configure(name_value: String, damage_value: float, speed_value: float, zone_center: float, ailment_id := "") -> void:
	display_name = name_value
	damage = damage_value
	needle_speed = speed_value
	success_start = clampf(zone_center - success_width * 0.5, 0.08, 0.72)
	success_end = success_start + success_width
	inflicted_condition = ailment_id


func setup(hud_ref: DungeonHUD, game_ref: Node) -> void:
	hud = hud_ref
	game = game_ref


func _ready() -> void:
	add_to_group("trap")
	_build_visuals()
	_build_areas()


func _process(delta: float) -> void:
	if state != TrapState.DISARMING:
		return
	needle_phase += delta * needle_speed
	needle_value = pingpong(needle_phase, 1.0)
	if hud:
		hud.update_trap_meter(needle_value, success_start, success_end)


func _build_visuals() -> void:
	plate_material = AGED_SURFACES.stone(Color(0.22, 0.25, 0.245), 2.8)
	rune_material = _material(Color(0.16, 0.37, 0.33, 0.94), 0.86, 0.10)
	rune_material.emission_enabled = true
	rune_material.emission = Color(0.045, 0.25, 0.20)
	rune_material.emission_energy_multiplier = 0.65
	rune_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rune_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	rune_material.albedo_texture = RUNE_TEXTURE
	rune_material.emission_texture = RUNE_TEXTURE

	var trap_model := TRAP_SCENE.instantiate() as Node3D
	trap_model.name = "BloodRuneTrapVisual"
	trap_model.scale = Vector3.ONE * 0.80
	add_child(trap_model)
	_disable_imported_collisions(trap_model)
	_apply_material_to_prefix(trap_model, ["SunkenStone", "CarvedPlate"], plate_material)
	_set_meshes_visible_by_prefix(
		trap_model,
		["OuterBloodRing", "InnerBloodRing", "Rune", "CenterSigil", "CenterHook"],
		false
	)

	var rune_quad := QuadMesh.new()
	rune_quad.size = Vector2(1.34, 1.34)
	var rune_decal := MeshInstance3D.new()
	rune_decal.name = "AITrapRune"
	rune_decal.mesh = rune_quad
	rune_decal.material_override = rune_material
	rune_decal.position.y = 0.155
	rune_decal.rotation.x = deg_to_rad(-90.0)
	add_child(rune_decal)

	rune_light = OmniLight3D.new()
	rune_light.name = "RuneGlow"
	rune_light.position.y = 0.22
	rune_light.light_color = Color(0.06, 0.82, 0.68)
	rune_light.light_energy = 0.22
	rune_light.omni_range = 2.25
	rune_light.shadow_enabled = false
	add_child(rune_light)

	spike_root = Node3D.new()
	spike_root.name = "Spikes"
	spike_root.position.y = -0.5
	add_child(spike_root)
	var iron := AGED_SURFACES.pitted_iron(Color(0.45, 0.46, 0.425), 4.0)
	for x in [-0.43, 0.0, 0.43]:
		for z in [-0.43, 0.0, 0.43]:
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.008
			cone.bottom_radius = 0.085
			cone.height = 0.78
			cone.radial_segments = 16
			spike.mesh = cone
			spike.material_override = iron
			spike.position = Vector3(x, 0.39, z)
			spike_root.add_child(spike)
			var socket := MeshInstance3D.new()
			var socket_mesh := TorusMesh.new()
			socket_mesh.inner_radius = 0.065
			socket_mesh.outer_radius = 0.105
			socket_mesh.rings = 14
			socket_mesh.ring_segments = 6
			socket.mesh = socket_mesh
			socket.material_override = iron
			socket.position = Vector3(x, 0.02, z)
			spike_root.add_child(socket)


func _build_areas() -> void:
	trigger_area = Area3D.new()
	trigger_area.name = "TriggerArea"
	trigger_area.collision_layer = 0
	trigger_area.collision_mask = PLAYER_LAYER
	trigger_area.monitoring = true
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(1.34, 0.22, 1.34)
	trigger_shape.shape = trigger_box
	trigger_shape.position.y = 0.15
	trigger_area.add_child(trigger_shape)
	trigger_area.body_entered.connect(_on_body_entered)
	add_child(trigger_area)

	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = INTERACT_LAYER
	interaction_area.collision_mask = 0
	interaction_area.monitorable = true
	interaction_area.set_meta("interaction_owner", self)
	var focus_shape := CollisionShape3D.new()
	var focus_box := BoxShape3D.new()
	focus_box.size = Vector3(1.5, 1.15, 1.5)
	focus_shape.shape = focus_box
	focus_shape.position.y = 0.54
	interaction_area.add_child(focus_shape)
	add_child(interaction_area)


func get_interaction_prompt() -> String:
	match state:
		TrapState.ARMED:
			return "[E] %s 조사 · %.1f초" % [display_name, INSPECT_DURATION]
		TrapState.INSPECTING:
			return "%s 조사 중..." % display_name
		TrapState.DISARMING:
			return "해제 중"
		TrapState.DISARMED:
			return "해제된 함정"
		_:
			return "작동한 함정"


func interact(player_ref: DungeonPlayer) -> void:
	if state != TrapState.ARMED or not is_instance_valid(player_ref):
		return
	state = TrapState.INSPECTING
	inspecting_player = player_ref
	if not player_ref.begin_timed_interaction(self, INSPECT_DURATION, "%s 조사 중" % display_name):
		state = TrapState.ARMED
		inspecting_player = null


func complete_timed_interaction(player_ref: DungeonPlayer) -> void:
	if state != TrapState.INSPECTING or player_ref != inspecting_player:
		return
	inspecting_player = null
	state = TrapState.ARMED
	begin_disarm(player_ref)


func cancel_timed_interaction(player_ref: DungeonPlayer) -> void:
	if state != TrapState.INSPECTING or player_ref != inspecting_player:
		return
	inspecting_player = null
	state = TrapState.ARMED


func get_interaction_duration() -> float:
	return INSPECT_DURATION if state == TrapState.ARMED else 0.0


func begin_disarm(player_ref: DungeonPlayer) -> void:
	if state != TrapState.ARMED or not is_instance_valid(player_ref):
		return
	if player_ref.begin_trap_disarm(self, display_name, success_start, success_end):
		player = player_ref
		state = TrapState.DISARMING
		needle_phase = 0.0
		needle_value = 0.0


func confirm_disarm() -> void:
	if state != TrapState.DISARMING:
		return
	if is_value_in_success_zone(needle_value):
		state = TrapState.DISARMED
		if is_instance_valid(player):
			player.finish_trap_disarm()
		_disable_areas()
		plate_material.albedo_color = Color(0.07, 0.14, 0.105)
		rune_material.emission = Color(0.035, 0.24, 0.14)
		if rune_light:
			rune_light.light_color = Color(0.05, 0.34, 0.18)
			rune_light.light_energy = 0.10
		if hud:
			hud.show_event("함정 해제 성공 · 룬 파편 회수", 1.6)
		resolved.emit(self, true)
	else:
		_trigger(player, "해제 실패")


func cancel_disarm(reason: String) -> void:
	if state != TrapState.DISARMING:
		return
	state = TrapState.ARMED
	if is_instance_valid(player):
		player.finish_trap_disarm()
	player = null
	if hud:
		hud.show_event(reason, 1.1)


func is_value_in_success_zone(value: float) -> bool:
	return value >= success_start and value <= success_end


func _on_body_entered(body: Node3D) -> void:
	if (state == TrapState.ARMED or state == TrapState.INSPECTING) and body is DungeonPlayer:
		_trigger(body, "철침 함정")


func _trigger(victim: DungeonPlayer, cause: String) -> void:
	if state == TrapState.DISARMED or state == TrapState.TRIGGERED:
		return
	if state == TrapState.INSPECTING and is_instance_valid(victim):
		victim.cancel_timed_interaction()
	inspecting_player = null
	state = TrapState.TRIGGERED
	if is_instance_valid(victim) and victim.current_trap == self:
		victim.finish_trap_disarm()
	_disable_areas()
	plate_material.albedo_color = Color(0.21, 0.055, 0.035)
	rune_material.emission = Color(0.85, 0.04, 0.015)
	if rune_light:
		rune_light.light_color = Color(1.0, 0.055, 0.018)
		rune_light.light_energy = 0.72
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(spike_root, "position:y", 0.0, 0.16)
	if is_instance_valid(victim):
		var contact_side := victim.to_local(global_position).x
		victim.receive_environment_damage(damage, cause, inflicted_condition, "right_leg" if contact_side > 0.0 else "left_leg")
	resolved.emit(self, false)


func _disable_areas() -> void:
	if trigger_area:
		trigger_area.set_deferred("monitoring", false)
	if interaction_area:
		interaction_area.set_deferred("collision_layer", 0)


func _disable_imported_collisions(root: Node) -> void:
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_disable_imported_collisions(child)


func _set_meshes_visible_by_prefix(root: Node, prefixes: Array, visible_value: bool) -> void:
	if root is GeometryInstance3D and _name_starts_with_any(String(root.name), prefixes):
		(root as GeometryInstance3D).visible = visible_value
	for child in root.get_children():
		_set_meshes_visible_by_prefix(child, prefixes, visible_value)


func _apply_material_to_prefix(root: Node, prefixes: Array, material: Material) -> void:
	if root is MeshInstance3D and _name_starts_with_any(String(root.name), prefixes):
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_material_to_prefix(child, prefixes, material)


func _name_starts_with_any(node_name: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if node_name.begins_with(String(prefix)):
			return true
	return false


func _box(size_value: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh_value := BoxMesh.new()
	mesh_value.size = size_value
	instance.mesh = mesh_value
	instance.material_override = material
	return instance


func _material(color_value: Color, roughness_value: float, metallic_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = roughness_value
	material.metallic = metallic_value
	return material
