extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_inventory_visual_metadata()
	_test_inventory_texture_assets()
	_test_loot_identification_contract()
	_test_bow_and_arrow_inventory()
	_test_chain_flail_inventory()
	_test_camp_kit_inventory()

	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	_check(inventory.count_item("healing_draught") == 2, "default loadout must contain two healing draughts")
	_check(inventory.count_item("holy_oil_flask") == 1, "default loadout must contain one offensive flask")
	_check(str(inventory.equipment.get("weapon", "")) == "rusted_sword", "default sword must occupy weapon slot")
	_check(str(inventory.equipment.get("offhand", "")) == "round_shield", "default shield must occupy offhand slot")
	_check(inventory.total_weight() > 0.0, "equipped and packed items must contribute weight")

	# Stack merging must prefer an existing stack and must never create more than
	# the authored maximum quantity in one slot.
	var slots_before := inventory.slots.size()
	var remainder := inventory.add_item("healing_draught", 3)
	_check(remainder == 0, "available inventory must accept a full legal stack")
	_check(inventory.count_item("healing_draught") == 5, "stacked healing quantity must be exact")
	_check(inventory.slots.size() == slots_before, "items must merge into a non-full matching stack")
	_check(inventory.add_item("healing_draught", 2) == 0, "overflow beyond one stack must create a second stack")
	_check(inventory.count_item("healing_draught") == 7, "overflow stack quantity must not be lost")

	# Equipping is an atomic swap: the new item leaves the bag and the previous
	# equipment returns without changing total item ownership.
	inventory.add_item("rusted_sword", 1)
	var sword_index := -1
	for index in inventory.slots.size():
		if str(inventory.slots[index].get("id", "")) == "rusted_sword":
			sword_index = index
			break
	var equip_result := inventory.equip_from_slot(sword_index)
	_check(bool(equip_result.get("accepted", false)), "equipment item in bag must be equippable")
	_check(inventory.count_item("rusted_sword") == 1, "equipped swap must return the previous sword to bag")
	var unequip_result := inventory.unequip("head")
	_check(bool(unequip_result.get("accepted", false)), "occupied equipment slot must be unequippable")
	_check(str(inventory.equipment.get("head", "x")).is_empty(), "unequipped slot must be empty")
	_check(inventory.count_item("wanderer_hood") == 1, "unequipped item must enter the bag")

	# Container transfer is deterministic and supports rollback when the bag is
	# full. This is the same transaction used by both inventory overlays.
	var chest := LootContainer.new().configure("테스트 상자", [
		{"id": "black_salt", "quantity": 2},
		{"id": "silver_chalice", "quantity": 1}
	])
	chest.identify_all(false)
	var chest_count_before := chest.item_count()
	var stack := chest.take_from_slot(0)
	var transfer_remainder := inventory.add_item(str(stack.get("id", "")), int(stack.get("quantity", 0)))
	if transfer_remainder > 0:
		chest.store_item(str(stack.get("id", "")), transfer_remainder)
	_check(transfer_remainder == 0, "normal chest transfer must fit")
	_check(chest.item_count() == chest_count_before - 2, "source container must lose exactly the moved quantity")
	_check(inventory.raid_loot_value() >= 36, "treasure value must be derived from carried raid loot")

	var full_inventory := ExpeditionInventory.new()
	_check(full_inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS) == 0, "one-slot equipment must fill every bag cell")
	_check(full_inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "bag must enforce its fixed slot capacity")
	var full_chest := LootContainer.new().configure("가득 찬 가방 테스트", [{"id": "reliquary", "quantity": 1}])
	full_chest.identify_all(false)
	var blocked_stack := full_chest.take_from_slot(0)
	var blocked_remainder := full_inventory.add_item(str(blocked_stack.get("id", "")), int(blocked_stack.get("quantity", 0)))
	if blocked_remainder > 0:
		full_chest.store_item(str(blocked_stack.get("id", "")), blocked_remainder)
	_check(blocked_remainder == 1, "full bag must reject a new item")
	_check(full_chest.item_count() == 1, "rejected transfer must restore the chest item")

	_finish()


func _test_bow_and_arrow_inventory() -> void:
	var bow := ExpeditionInventory.get_item_definition("hunting_bow")
	var arrow := ExpeditionInventory.get_item_definition("wooden_arrow")
	_check(str(bow.get("equip_slot", "")) == "weapon" and str(bow.get("weapon_type", "")) == "bow", "the hunting bow must be a real bow in the weapon slot")
	_check(str(bow.get("ammo_type", "")) == "wooden_arrow", "the bow must reference its catalog ammunition ID")
	_check(str(arrow.get("category", "")) == "ammunition" and int(arrow.get("stack_max", 0)) == 30, "wooden arrows must be ammunition with a thirty-unit stack cap")
	_check(not arrow.has("equip_slot") and not arrow.has("effect"), "arrows must not require equipment or consumable use")
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	_check(inventory.count_item("hunting_bow") == 1 and inventory.count_item("wooden_arrow") == 12, "new journeys must provide a packed bow and twelve arrows")
	_check(str(inventory.equipment.get("weapon", "")) == "rusted_sword", "archery supplies must not replace the starting sword")
	var ammo_before := inventory.count_item("wooden_arrow")
	var weight_before := inventory.total_weight()
	var equip_result := inventory.equip_from_slot(_find_slot(inventory, "hunting_bow"))
	_check(bool(equip_result.get("accepted", false)) and str(inventory.equipment.get("weapon", "")) == "hunting_bow", "the packed bow must equip through the normal equipment transaction")
	_check(inventory.count_item("hunting_bow") == 0 and inventory.count_item("rusted_sword") == 1, "equipping a bow must exchange ownership with the equipped sword")
	_check(inventory.count_item("wooden_arrow") == ammo_before and is_equal_approx(inventory.total_weight(), weight_before), "equipping a bow must preserve arrows and total carried weight")
	var arrow_equip := inventory.equip_from_slot(_find_slot(inventory, "wooden_arrow"))
	_check(not bool(arrow_equip.get("accepted", false)) and str(arrow_equip.get("reason", "")) == "not_equipment", "ammunition must reject equipment-slot use")
	_check(inventory.count_item("wooden_arrow") == ammo_before, "rejected arrow equip must preserve the stack")
	var unequip_result := inventory.unequip("weapon")
	_check(bool(unequip_result.get("accepted", false)) and inventory.count_item("hunting_bow") == 1, "unequipping the bow must return it to the bag")
	_check(inventory.count_item("wooden_arrow") == ammo_before and is_equal_approx(inventory.total_weight(), weight_before), "unequipping the bow must preserve ammunition and weight")

	var arrows := ExpeditionInventory.new()
	_check(arrows.add_item("wooden_arrow", 65) == 0, "arrow stacks must accept quantities spanning several slots")
	_check(arrows.slots.size() == 3 and int(arrows.slots[0].get("quantity", 0)) == 30 and int(arrows.slots[2].get("quantity", 0)) == 5, "sixty-five arrows must split into stacks of thirty, thirty, and five")
	_check(is_equal_approx(arrows.total_weight(), 65.0 * float(arrow.get("weight", 0.0))), "each carried arrow must contribute its catalog weight")
	_check(arrows.remove_item("wooden_arrow", 36), "arrow removal must work across stack boundaries")
	_check(arrows.count_item("wooden_arrow") == 29 and arrows.slots.size() == 1, "cross-stack removal must prune exhausted arrow stacks exactly")
	var remaining_slots := arrows.slots.duplicate(true)
	_check(not arrows.remove_item("wooden_arrow", 30) and arrows.slots == remaining_slots, "insufficient arrow removal must be atomic")
	_check(arrows.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS - 1) == 0, "arrow capacity fixture must fill all remaining bag slots")
	_check(arrows.can_add("wooden_arrow", 1) and not arrows.can_add("wooden_arrow", 2), "a full bag must expose only the spare room in its existing arrow stack")
	_check(arrows.add_item("wooden_arrow", 3) == 2 and arrows.count_item("wooden_arrow") == 30, "capacity-limited arrow additions must report the exact rejected remainder")

	var chest := LootContainer.new().configure("화살 보급 상자", [{"id": "wooden_arrow", "quantity": 35}])
	chest.identify_all(false)
	var transfer_inventory := ExpeditionInventory.new()
	var source_units := chest.item_count()
	var taken := chest.take_from_slot(0, 12)
	_check(transfer_inventory.add_item(str(taken.get("id", "")), int(taken.get("quantity", 0))) == 0, "identified arrows must use normal loot transfer")
	_check(transfer_inventory.count_item("wooden_arrow") == 12 and chest.item_count() + transfer_inventory.count_item("wooden_arrow") == source_units, "partial arrow transfer must preserve all source and bag units")
	var deposited := transfer_inventory.remove_from_slot(0, 7)
	_check(chest.store_item(str(deposited.get("id", "")), int(deposited.get("quantity", 0)), true, true) == 0, "owned arrows must be returnable to a container")
	_check(transfer_inventory.count_item("wooden_arrow") == 5 and chest.item_count() + transfer_inventory.count_item("wooden_arrow") == source_units, "depositing arrows must preserve total ammunition")


func _test_chain_flail_inventory() -> void:
	var definition := ExpeditionInventory.get_item_definition("chain_flail")
	_check(str(definition.get("name", "")) == "사슬철퇴" and str(definition.get("weapon_type", "")) == "flail", "chain flail must have its own weapon type and authored name")
	_check(str(definition.get("equip_slot", "")) == "weapon" and int(definition.get("stack_max", 0)) == 1, "chain flail must use the standard non-stacking weapon slot")
	_check(is_equal_approx(float(definition.get("weight", 0.0)), 4.8) and int(definition.get("value", 0)) == 64, "chain flail must use its authored weight and resale basis")
	_check(definition.get("ui_span") == Vector2i(2, 3) and str(definition.get("icon_path", "")) == "res://assets/ui/chain_flail.svg", "chain flail must use its independent two-by-three inventory icon")
	_check(not definition.has("ammo_type") and not definition.has("effect"), "chain flail is persistent equipment, not ammunition or a consumable")
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	_check(inventory.count_item("chain_flail") == 1 and str(inventory.equipment.weapon) == "rusted_sword", "starter bag must add one flail without replacing the equipped sword")
	var weight := inventory.total_weight()
	var arrows := inventory.count_item("wooden_arrow")
	var bows := inventory.count_item("hunting_bow")
	_check(bool(inventory.equip_from_slot(_find_slot(inventory, "chain_flail")).get("accepted", false)), "chain flail must equip through the existing equipment transaction")
	_check(str(inventory.equipment.weapon) == "chain_flail" and inventory.count_item("chain_flail") == 0 and inventory.count_item("rusted_sword") == 1, "equipping must exchange the packed flail and equipped sword")
	_check(is_equal_approx(inventory.total_weight(), weight) and inventory.count_item("wooden_arrow") == arrows and inventory.count_item("hunting_bow") == bows, "flail equip must preserve carried weight and archery supplies")
	_check(str(inventory.equipment.offhand) == "round_shield", "two-handed gameplay must not destroy or silently unequip the owned shield")
	_check(bool(inventory.unequip("weapon").get("accepted", false)) and inventory.count_item("chain_flail") == 1, "unequipping must return the same reusable flail to the bag")
	_check(is_equal_approx(inventory.total_weight(), weight), "flail unequip must preserve total item ownership")
	inventory.seed_default_loadout()
	_check(inventory.count_item("chain_flail") == 1, "reset must restore exactly one starter flail, not accumulate copies")
	var chest := LootContainer.new().configure("철퇴 보급", [{"id": "chain_flail", "quantity": 1}])
	_check(chest.take_from_slot(0).is_empty(), "unidentified flail loot must obey the normal identification requirement")
	chest.identify_all(false)
	var taken := chest.take_from_slot(0)
	_check(str(taken.get("id", "")) == "chain_flail" and inventory.add_item("chain_flail", int(taken.get("quantity", 0))) == 0, "identified flail loot must transfer through the normal catalog-backed container path")
	_check(chest.item_count() == 0 and inventory.count_item("chain_flail") == 2, "flail transfer must preserve exactly one source item")


func _test_camp_kit_inventory() -> void:
	var definition := ExpeditionInventory.get_item_definition("camp_kit")
	_check(str(definition.get("name", "")) == "휴대 야영 도구" and str(definition.get("category", "")) == "supply", "camp kit must be a catalog-backed supply item")
	_check(int(definition.get("stack_max", 0)) == 3 and is_equal_approx(float(definition.get("weight", 0.0)), 0.5) and int(definition.get("value", 0)) == 18, "camp kit must have the authored stack cap, weight and value")
	_check(definition.get("ui_span") == Vector2i(1, 2) and not definition.has("equip_slot") and not definition.has("effect"), "camp kit must be a one-by-two supply, not directly usable equipment or medicine")
	_check(str(definition.get("description", "")).contains("첫 휴식 때 1개") and str(definition.get("description", "")).contains("온기 3"), "camp kit description must explain first-rest consumption and warmth")
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	_check(inventory.count_item("camp_kit") == 1 and str(inventory.equipment.weapon) == "rusted_sword", "starter bag must contain one kit without changing equipment")
	_check(inventory.count_item("chain_flail") == 1 and inventory.count_item("hunting_bow") == 1 and inventory.count_item("wooden_arrow") == 12, "camp supply must preserve all existing starting weapons and ammunition")
	var weight_before := inventory.total_weight()
	_check(inventory.add_item("camp_kit", 3) == 0 and inventory.count_item("camp_kit") == 4, "camp kits must support several stacks")
	var stacks: Array[int] = []
	for slot in inventory.slots:
		if str(slot.id) == "camp_kit":
			stacks.append(int(slot.quantity))
	_check(stacks == [3, 1] and is_equal_approx(inventory.total_weight(), weight_before + 1.5), "kit stacking must preserve exact three-unit cap and carried weight")
	var before := inventory.slots.duplicate(true)
	_check(not bool(inventory.equip_from_slot(_find_slot(inventory, "camp_kit")).get("accepted", false)) and inventory.slots == before, "camp kit must reject ordinary equipment use without consumption")
	inventory.seed_default_loadout()
	_check(inventory.count_item("camp_kit") == 1, "loadout reset must restore exactly one kit")


func _find_slot(inventory: ExpeditionInventory, item_id: String) -> int:
	for index in inventory.slots.size():
		if str(inventory.slots[index].get("id", "")) == item_id:
			return index
	return -1


func _test_loot_identification_contract() -> void:
	# Authored loot must begin concealed and remain untakeable until its exact
	# stack has been identified.
	var concealed := LootContainer.new().configure("미식별 전리품", [
		{"id": "black_salt", "quantity": 2},
		{"id": "silver_chalice", "quantity": 1},
		{"id": "reliquary", "quantity": 1}
	])
	_check(concealed.items.size() == 3, "configure must preserve three distinct authored loot stacks")
	_check(concealed.identified_stack_count() == 0, "every authored stack must be unidentified immediately after configure")
	_check(concealed.unidentified_stack_count() == 3, "configure must report every authored stack as unidentified")
	_check(concealed.has_unidentified_items(), "a freshly configured container must report concealed contents")
	var concealed_total := concealed.item_count()
	_check(concealed.take_from_slot(0).is_empty(), "taking an unidentified stack must be rejected")
	_check(concealed.item_count() == concealed_total, "a rejected unidentified take must not change total quantity")

	# Beginning a search alone reveals nothing. Crossing each interval reveals
	# exactly one stack, in stable slot order.
	concealed.identify_interval = 0.5
	_check(concealed.begin_search(), "the first begin_search call must start the container search")
	_check(concealed.advance_search(0.499).is_empty(), "search must reveal zero stacks just before the identify interval")
	_check(concealed.identified_stack_count() == 0, "elapsed time below one interval must keep every stack concealed")
	var first_reveal := concealed.advance_search(0.001)
	_check(not first_reveal.is_empty(), "crossing the first identify interval must return one revealed stack")
	_check(concealed.identified_stack_count() == 1, "the first elapsed interval must identify exactly one stack")
	_check(int(first_reveal.get("index", -1)) == 0, "the first reveal must identify the first concealed slot")
	var second_reveal := concealed.advance_search(0.5)
	_check(not second_reveal.is_empty(), "the second elapsed interval must return another revealed stack")
	_check(concealed.identified_stack_count() == 2, "the second elapsed interval must identify exactly one additional stack")
	var third_reveal := concealed.advance_search(0.5)
	_check(not third_reveal.is_empty(), "the third elapsed interval must return the final revealed stack")
	_check(concealed.identified_stack_count() == 3, "each completed interval must reveal exactly one stack")
	_check(not concealed.has_unidentified_items(), "all stacks must be known after one interval per stack")

	# Even a very large frame delta may expose at most one stack per call; saved
	# excess elapsed time can drive the following calls one stack at a time.
	var long_frame := LootContainer.new().configure("긴 프레임", [
		{"id": "black_salt", "quantity": 1},
		{"id": "silver_chalice", "quantity": 1},
		{"id": "rune_fragment", "quantity": 1}
	])
	long_frame.identify_interval = 0.5
	long_frame.begin_search()
	var long_frame_first := long_frame.advance_search(8.0)
	_check(not long_frame_first.is_empty(), "a long search update must still reveal a stack")
	_check(long_frame.identified_stack_count() == 1, "one advance_search call must never identify more than one stack")
	var long_frame_second := long_frame.advance_search(0.001)
	_check(not long_frame_second.is_empty(), "carried elapsed search time must be usable by the next update")
	_check(long_frame.identified_stack_count() == 2, "a second update may identify only one additional stack")

	# Reopening calls begin_search again. That must not restart the search or
	# discard a partially completed interval.
	var reopened := LootContainer.new().configure("재개방", [
		{"id": "grave_key", "quantity": 1},
		{"id": "rune_fragment", "quantity": 1}
	])
	reopened.identify_interval = 0.8
	_check(reopened.begin_search(), "partial-search fixture must start once")
	_check(reopened.advance_search(0.3).is_empty(), "partial search time must not reveal an item early")
	var partial_elapsed := reopened.search_elapsed
	_check(not reopened.begin_search(), "begin_search on a reopened container must not restart an active search")
	_check(is_equal_approx(reopened.search_elapsed, partial_elapsed), "reopening must preserve partial search elapsed time")
	_check(reopened.advance_search(0.49).is_empty(), "preserved partial time below the interval must still reveal nothing")
	_check(reopened.identified_stack_count() == 0, "reopened partial search must keep all stacks concealed before the threshold")
	_check(not reopened.advance_search(0.011).is_empty(), "reopened search must reveal one stack when preserved time crosses the interval")
	_check(reopened.identified_stack_count() == 1, "reopened search must continue rather than reveal or reset multiple stacks")

	# Known and unknown stacks of the same item ID are separate identities and
	# must never merge, even when both have remaining stack capacity.
	var mixed_identity := LootContainer.new().configure("알려진 전리품", [
		{"id": "black_salt", "quantity": 2}
	])
	_check(mixed_identity.store_item("black_salt", 3, false, true) == 0, "an identified stack must fit beside concealed loot")
	_check(mixed_identity.items.size() == 2, "known and unknown stacks with the same item ID must not merge")
	_check(not mixed_identity.is_stack_identified(0), "the authored same-ID stack must remain unknown")
	_check(mixed_identity.is_stack_identified(1), "the deposited same-ID stack must remain known")
	_check(int(mixed_identity.items[0].get("quantity", 0)) == 2, "separating known loot must preserve unknown quantity")
	_check(int(mixed_identity.items[1].get("quantity", 0)) == 3, "separating unknown loot must preserve known quantity")

	# A successful take must explicitly carry its identified state, and the
	# returned units plus the remaining units must conserve total ownership.
	var take_source := LootContainer.new().configure("식별 전송", [
		{"id": "black_salt", "quantity": 4}
	])
	take_source.identify_all(false)
	var take_total_before := take_source.item_count()
	var identified_take := take_source.take_from_slot(0, 2, false)
	_check(bool(identified_take.get("identified", false)), "an identified take result must include identified=true")
	_check(str(identified_take.get("id", "")) == "black_salt", "an identified take result must preserve its item ID")
	_check(int(identified_take.get("quantity", 0)) == 2, "an identified partial take must return the requested quantity")
	_check(take_source.item_count() + int(identified_take.get("quantity", 0)) == take_total_before, "identified take must conserve returned plus remaining total quantity")


func _test_inventory_visual_metadata() -> void:
	var alchemy_catalog := preload("res://scripts/alchemy_catalog.gd")
	var alchemy_count := alchemy_catalog.BASES.size() + alchemy_catalog.HERBS.size() + 1 + alchemy_catalog.RECIPES.size() * 3
	_check(ExpeditionInventory.ITEM_DEFINITIONS.size() >= 36 + alchemy_count + 4, "Extensible catalog must retain the established items, alchemy variants and four storage equipment definitions.")
	# These existing medical definitions deliberately reuse the bandage/potion
	# artwork. Validate those exact aliases without allowing unrelated collisions.
	var shared_medical_art := {"surgery_kit": "linen_bandage", "splint": "linen_bandage", "antidote": "healing_draught", "purifying_salt": "linen_bandage", "nerve_tonic": "healing_draught"}
	var used_atlas_cells: Dictionary = {}
	for item_id_value in ExpeditionInventory.ITEM_DEFINITIONS:
		var item_id := str(item_id_value)
		var definition := ExpeditionInventory.get_item_definition(item_id)
		var atlas_value: Variant = definition.get("atlas_cell")
		var icon_path := str(definition.get("icon_path", ""))
		var span_value: Variant = definition.get("ui_span")
		var uses_atlas := typeof(atlas_value) == TYPE_VECTOR2I
		var uses_external_icon := not icon_path.is_empty()
		_check(uses_atlas or uses_external_icon, "%s must define either an atlas cell or an external icon path" % item_id)
		_check(typeof(span_value) == TYPE_VECTOR2I, "%s must define a Vector2i ui_span" % item_id)
		if uses_atlas:
			var atlas_cell: Vector2i = atlas_value
			_check(atlas_cell.x >= 0 and atlas_cell.x < 4 and atlas_cell.y >= 0 and atlas_cell.y < 4, "%s atlas_cell must stay inside the 4 by 4 atlas" % item_id)
			if shared_medical_art.has(item_id):
				_check(atlas_cell == ExpeditionInventory.get_item_definition(shared_medical_art[item_id]).get("atlas_cell"), item_id + " must retain its explicit shared medical artwork.")
			else:
				_check(not used_atlas_cells.has(atlas_cell), "%s atlas_cell must not overlap another authored item" % item_id)
				used_atlas_cells[atlas_cell] = item_id
		elif uses_external_icon:
			_check(ResourceLoader.exists(icon_path, "Texture2D"), "%s external icon must exist as a Texture2D" % item_id)
			var icon := load(icon_path) as Texture2D
			_check(icon != null and icon.get_width() > 0 and icon.get_height() > 0, "%s external icon must contain image data" % item_id)
		if typeof(span_value) == TYPE_VECTOR2I:
			var ui_span: Vector2i = span_value
			_check(ui_span.x > 0 and ui_span.y > 0, "%s ui_span dimensions must be positive" % item_id)
	for survival_item_id in ["pilgrim_ration", "boiled_rainwater"]:
		var survival_definition := ExpeditionInventory.get_item_definition(survival_item_id)
		_check(not survival_definition.is_empty(), "%s must exist in the item catalog" % survival_item_id)
		_check(str(survival_definition.get("category", "")) == "consumable", "%s must be usable as a consumable" % survival_item_id)
		_check(not str(survival_definition.get("icon_path", "")).is_empty(), "%s must use its authored external icon" % survival_item_id)


func _test_inventory_texture_assets() -> void:
	var texture_paths: Array[String] = [
		"res://assets/ui/inventory_item_atlas.png",
		"res://assets/ui/inventory_survivor.png",
		"res://assets/ui/inventory_container_atlas.png"
	]
	for texture_path in texture_paths:
		_check(ResourceLoader.exists(texture_path, "Texture2D"), "%s must exist as a Texture2D resource" % texture_path)
		var texture := load(texture_path) as Texture2D
		_check(texture != null, "%s must load as a Texture2D" % texture_path)
		if texture == null:
			continue
		_check(texture.get_width() > 0 and texture.get_height() > 0, "%s must have positive pixel dimensions" % texture_path)
		var image := texture.get_image()
		_check(image != null and not image.is_empty(), "%s must expose non-empty image data" % texture_path)
		if image != null and not image.is_empty():
			_check(image.detect_alpha() != Image.ALPHA_NONE, "%s must contain valid alpha data" % texture_path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("INVENTORY MODEL TEST PASS: visual metadata, texture assets, stacking, equipment, archery, chain flail, capacity, transfer, and value")
		quit(0)
		return
	for failure in failures:
		push_error("INVENTORY MODEL TEST FAIL: %s" % failure)
	quit(1)
