extends Node3D
class_name HideoutInteractable

signal activated(action_id: String, player: Node)

const INTERACT_LAYER := 16

@export var action_id := "inspect"
@export var prompt_text := "조사"
@export var interaction_duration := 0.0
@export var interaction_size := Vector3(1.6, 1.8, 1.4)
@export var interaction_offset := Vector3(0.0, 0.9, 0.0)
@export var one_shot := false

var disabled := false
var _active_player: Node
var _interaction_area: Area3D


func configure(
	action_value: String,
	prompt_value: String,
	size_value := Vector3(1.6, 1.8, 1.4),
	offset_value := Vector3(0.0, 0.9, 0.0),
	duration_value := 0.0
) -> HideoutInteractable:
	action_id = action_value
	prompt_text = prompt_value
	interaction_size = size_value
	interaction_offset = offset_value
	interaction_duration = maxf(0.0, duration_value)
	return self


func _ready() -> void:
	_build_interaction_area()


func _build_interaction_area() -> void:
	if is_instance_valid(_interaction_area):
		return
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = INTERACT_LAYER
	_interaction_area.collision_mask = 0
	_interaction_area.monitorable = true
	_interaction_area.set_meta("interaction_owner", self)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = interaction_size
	collision.shape = box
	collision.position = interaction_offset
	_interaction_area.add_child(collision)
	add_child(_interaction_area)


func get_interaction_prompt() -> String:
	if disabled:
		return ""
	if is_instance_valid(_active_player):
		return "%s 중..." % prompt_text
	if interaction_duration > 0.0:
		return "[E] %s · %.1f초" % [prompt_text, interaction_duration]
	return "[E] %s" % prompt_text


func interact(player: Node) -> void:
	if disabled or not is_instance_valid(player) or is_instance_valid(_active_player):
		return
	if interaction_duration > 0.0 and player.has_method("begin_timed_interaction"):
		_active_player = player
		if not bool(player.call("begin_timed_interaction", self, interaction_duration, prompt_text)):
			_active_player = null
		return
	_activate(player)


func complete_timed_interaction(player: Node) -> void:
	if player != _active_player:
		return
	_active_player = null
	_activate(player)


func cancel_timed_interaction(player: Node) -> void:
	if player == _active_player:
		_active_player = null


func get_interaction_duration() -> float:
	return interaction_duration


func _activate(player: Node) -> void:
	if one_shot:
		disabled = true
		if is_instance_valid(_interaction_area):
			_interaction_area.collision_layer = 0
	activated.emit(action_id, player)
