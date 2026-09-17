extends RefCounted

const CATALOG := preload("res://scripts/loot_spawn_catalog.gd")


static func seed_with_items(map_id: String, item_ids: Array) -> int:
	# Content regressions use a reproducible visit containing their supplies;
	# ordinary visits are allowed to omit those sites.
	for seed_value in range(4096):
		var found := {}
		for site: Dictionary in CATALOG.roll(map_id, seed_value):
			for stack: Dictionary in site.items:
				found[str(stack.id)] = true
		if item_ids.all(func(item_id: String) -> bool: return found.has(item_id)):
			return seed_value
	return -1


static func chest_with_item(game: Node, item_id: String) -> DungeonLootChest:
	for chest: DungeonLootChest in game.loot_chests:
		for stack: Dictionary in chest.container.items:
			if str(stack.id) == item_id:
				return chest
	return null


static func valid_count(game: Node) -> bool:
	return game.loot_chests.size() == game.loot_spawn_selection.size() and game.loot_chests.size() >= 2 and game.loot_chests.size() <= 4
