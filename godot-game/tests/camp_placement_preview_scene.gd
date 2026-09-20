extends "res://scripts/game.gd"
## Keep the production world, player and camp signal handlers. Replace only
## entry/focus hooks that would otherwise touch the native cursor/window.

func _ready() -> void:
	loot_spawn_seed = 4729
	load("res://tests/performance_scene_factory.gd").prepare_game(self)


func _notification(_what: int) -> void:
	pass


func _set_camp_mouse_mode(_mode: int) -> void:
	pass
