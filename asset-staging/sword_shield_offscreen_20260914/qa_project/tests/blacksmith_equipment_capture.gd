extends RefCounted
## Reuses the audited arm preview's production player and offscreen stage.
## The passed inventory must already have the completed/upgraded sword equipped.
## No native window, hardware input, mouse mode, or expedition state is changed.

const ARM_PREVIEW := preload("res://tests/player_arm_preview.gd")


static func create_viewport(bag: ExpeditionInventory) -> SubViewport:
	var viewport := ARM_PREVIEW.create_viewport()
	viewport.name = "BlacksmithEquippedWeaponViewport"
	# _ready on the actual player needs a World3D and active scene tree. Build
	# after the caller attaches this otherwise self-contained viewport.
	viewport.ready.connect(_populate.bind(viewport, bag), CONNECT_ONE_SHOT)
	return viewport


static func _populate(viewport: SubViewport, bag: ExpeditionInventory) -> void:
	var fixture := ARM_PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	# Configure the inherited idle pose against its temporary starter inventory;
	# the helper's rusted-sword selection must not replace the supplied weapon.
	var configured := ARM_PREVIEW.configure_pose(fixture, "idle")
	player.bind_inventory(bag)
	fixture.inventory = bag
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)
	player._update_viewmodel(1.0)
	player._update_torch(0.0)
	player.viewmodel_renderer.sync_view()
	viewport.set_meta("blacksmith_fixture", fixture)
	viewport.set_meta("blacksmith_configured", configured)


static func inspect(viewport: SubViewport) -> Dictionary:
	var fixture: Dictionary = viewport.get_meta("blacksmith_fixture", {})
	if fixture.is_empty():
		return {"passed": false, "reason": "viewport_not_attached"}
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	var mods: Dictionary = bag.get_equipment_instance("weapon").get("smithing", {})
	var details := player.sword_visual_root.get_node_or_null("SmithingDetails")
	var gems: Array[Dictionary] = []
	var correct_layers := true
	if details != null:
		for child in details.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("RuneGem"):
				var mesh := child as MeshInstance3D
				correct_layers = correct_layers and mesh.layers == player.sword_blade.layers
				gems.append({"name": str(mesh.name), "visible": mesh.is_visible_in_tree(), "layer": mesh.layers})
	return {
		"passed": bool(viewport.get_meta("blacksmith_configured", false)) and viewport.gui_disable_input and not viewport.physics_object_picking and not player.is_physics_processing() and not player.is_processing_input() and not player.is_processing_unhandled_input() and player.sword_visual_root.visible and correct_layers and gems.size() == (mods.get("runes", []) as Array).size(),
		"capture_kind": "Actual equipped DungeonPlayer sword, production inventory modifiers and first-person equipment renderer",
		"item_id": str(bag.equipment.get("weapon", "")),
		"smithing": mods.duplicate(true),
		"combat_stats": bag.equipped_smithing_stats(),
		"rune_gems": gems,
		"equipment_layer": player.sword_blade.layers,
		"input_disabled": not player.is_processing_input() and not player.is_processing_unhandled_input(),
	}
