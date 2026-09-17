extends "res://scripts/cave_dungeon.gd"
## Loaded after autoload registration, as in the real cave transition.

func _ready() -> void:
	load("res://tests/performance_scene_factory.gd").prepare_game(self)
	_update_chamber_hud()

func _notification(_what: int) -> void:
	pass

func _on_player_died() -> void:
	set_meta("benchmark_player_died", true)
	game_mode = GameMode.DEAD
