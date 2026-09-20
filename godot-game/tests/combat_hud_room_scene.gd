extends "res://scripts/test_room.gd"
## Production room construction without native focus/cursor changes.
func _ready() -> void:
	room_font = FontVariation.new()
	room_font.base_font = ROOM_FONT
	room_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	child_entered_tree.connect(_on_test_actor_added)
	load("res://tests/performance_scene_factory.gd").prepare_game(self)
	player.position = HOME_POSITION
	feature_entries = CATALOG.entries()
	_build_test_panel()
	test_panel.hide()
	room_hint.hide()
	panel_open = false

func _notification(_what: int) -> void:
	pass
