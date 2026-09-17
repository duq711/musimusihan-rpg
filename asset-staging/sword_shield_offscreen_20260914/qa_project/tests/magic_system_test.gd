extends SceneTree

const FLOAT_TOLERANCE := 0.002
const EXPECTED_SPELL_ORDER: Array[String] = [
	"fire_bolt",
	"water_bolt",
	"ice_shard",
	"stone_shard",
	"healing_light",
	"restorative_light",
]
const PROJECTILE_SPELL_IDS: Array[String] = [
	"fire_bolt",
	"water_bolt",
	"ice_shard",
	"stone_shard",
]
const MAGIC_ITEM_IDS: Array[String] = [
	"weathered_staff",
	"fire_spellbook",
	"water_spellbook",
	"ice_spellbook",
	"stone_spellbook",
	"healing_spellbook",
	"restoration_spellbook",
]
const BOOK_TO_SPELL := {
	"fire_spellbook": "fire_bolt",
	"water_spellbook": "water_bolt",
	"ice_spellbook": "ice_shard",
	"stone_spellbook": "stone_shard",
	"healing_spellbook": "healing_light",
	"restoration_spellbook": "restorative_light",
}

var failures: Array[String] = []


class SpellTarget:
	extends Node3D

	var hit_count := 0
	var total_damage := 0.0
	var last_damage := 0.0
	var last_attacker_position := Vector3.ZERO
	var last_charge := 0.0
	var last_headshot := true


	func receive_hit(amount: float, attacker_position: Vector3, charge: float, headshot: bool) -> void:
		hit_count += 1
		total_damage += amount
		last_damage = amount
		last_attacker_position = attacker_position
		last_charge = charge
		last_headshot = headshot


class PhysicsSpellTarget:
	extends StaticBody3D

	var hit_count := 0
	var total_damage := 0.0
	var collision_radius := 0.1


	func _init(radius_value := 0.1, layer_value := 4) -> void:
		collision_radius = radius_value
		collision_layer = layer_value
		collision_mask = 0
		var collision := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = collision_radius
		collision.shape = sphere
		add_child(collision)


	func receive_hit(amount: float, _attacker_position: Vector3, _charge: float, _headshot: bool) -> void:
		hit_count += 1
		total_damage += amount


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_standalone_player_actions()
	_test_catalog_and_item_contract()
	_test_spellbook_learning_transaction()
	_test_magic_progress_reset_and_retain()
	_test_staff_stamina_and_cooldown_gate()
	_test_weapon_state_transitions()
	_test_elemental_projectiles()
	await _test_swept_sphere_physics()
	_test_healing_spell()
	await _test_merchant_and_dungeon_spawns()
	_finish()


func _test_catalog_and_item_contract() -> void:
	_check(SpellCatalog.SPELL_ORDER == EXPECTED_SPELL_ORDER, "spell catalog must preserve the four elements and expose ordinary healing followed by advanced restoration")
	var seen_elements: Dictionary = {}
	for spell_id in PROJECTILE_SPELL_IDS:
		var definition := SpellCatalog.get_spell_definition(spell_id)
		var element := str(definition.get("element", ""))
		_check(not definition.is_empty(), "%s must exist in the spell catalog" % spell_id)
		_check(str(definition.get("cast_type", "")) == "projectile", "%s must be an elemental projectile" % spell_id)
		_check(not element.is_empty() and not seen_elements.has(element), "%s must expose a distinct authored element" % spell_id)
		_check(float(definition.get("damage", 0.0)) > 0.0, "%s must deal positive damage" % spell_id)
		_check(float(definition.get("speed", 0.0)) > 0.0, "%s must travel at a positive speed" % spell_id)
		_check(float(definition.get("stamina_cost", 0.0)) > 0.0, "%s must spend positive stamina" % spell_id)
		_check(float(definition.get("cooldown", 0.0)) > 0.0, "%s must define a positive cooldown" % spell_id)
		seen_elements[element] = true
	_check(seen_elements.size() == PROJECTILE_SPELL_IDS.size(), "the four projectile spells must remain mechanically distinguishable by element")

	var healing := SpellCatalog.get_spell_definition("healing_light")
	_check(str(healing.get("cast_type", "")) == "heal", "healing_light must remain a healing spell")
	_check(float(healing.get("heal_amount", 0.0)) > 0.0, "healing_light must restore positive health")
	_check(float(healing.get("stamina_cost", 0.0)) > 0.0, "healing_light must spend positive stamina")
	_check(float(healing.get("cooldown", 0.0)) > 0.0, "healing_light must define a positive cooldown")

	var staff := ExpeditionInventory.get_item_definition("weathered_staff")
	_check(str(staff.get("category", "")) == "equipment", "the weathered staff must be equipment")
	_check(str(staff.get("equip_slot", "")) == "weapon", "the weathered staff must occupy the weapon slot")
	_check(str(staff.get("weapon_type", "")) == "staff", "the weathered staff must identify itself as a casting focus")
	for book_id_value in BOOK_TO_SPELL:
		var book_id := str(book_id_value)
		var definition := ExpeditionInventory.get_item_definition(book_id)
		_check(str(definition.get("category", "")) == "consumable", "%s must be usable from the inventory" % book_id)
		_check(str(definition.get("effect", "")) == "learn_spell", "%s must permanently teach a spell" % book_id)
		_check(str(definition.get("spell_id", "")) == str(BOOK_TO_SPELL[book_id]), "%s must teach its authored spell" % book_id)
		_check(bool(definition.get("unique_learning", false)), "%s must prevent duplicate learning purchases" % book_id)
		_check(int(definition.get("stack_max", 0)) == 1, "%s must remain a unique one-per-stack book" % book_id)


func _test_spellbook_learning_transaction() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(inventory.add_item("fire_spellbook", 2) == 0, "spellbook fixture must add both fire books")
	var player := DungeonPlayer.new()
	var count_before := inventory.count_item("fire_spellbook")
	var learned := player.use_consumable("fire_spellbook", inventory)
	_check(bool(learned.get("accepted", false)), "using an owned unlearned spellbook must succeed")
	_check(str(learned.get("spell_learned", "")) == "fire_bolt", "the fire spellbook result must report fire_bolt")
	_check(ExpeditionSession.is_spell_learned("fire_bolt"), "using a fire spellbook must permanently learn fire_bolt")
	_check(inventory.count_item("fire_spellbook") == count_before - 1, "successful spellbook learning must consume exactly one copy")
	_check(ExpeditionSession.get_selected_spell() == "fire_bolt", "the first learned spell must become selected")

	count_before = inventory.count_item("fire_spellbook")
	var duplicate := player.use_consumable("fire_spellbook", inventory)
	_check(not bool(duplicate.get("accepted", true)) and str(duplicate.get("reason", "")) == "already_learned", "an already learned spellbook must be rejected clearly")
	_check(inventory.count_item("fire_spellbook") == count_before, "a rejected duplicate spellbook must not be consumed")

	var missing_before := inventory.count_item("water_spellbook")
	var missing := ExpeditionSession.learn_spell_from_book("water_spellbook", inventory)
	_check(not bool(missing.get("accepted", true)) and str(missing.get("reason", "")) == "not_owned", "a valid but unowned spellbook must be rejected")
	_check(inventory.count_item("water_spellbook") == missing_before and not ExpeditionSession.is_spell_learned("water_bolt"), "an unowned spellbook request must not mutate items or knowledge")

	var draught_before := inventory.count_item("healing_draught")
	var not_a_book := ExpeditionSession.learn_spell_from_book("healing_draught", inventory)
	_check(not bool(not_a_book.get("accepted", true)) and str(not_a_book.get("reason", "")) == "not_spellbook", "ordinary consumables must not be accepted as spellbooks")
	_check(inventory.count_item("healing_draught") == draught_before, "rejecting a non-spellbook must not consume it")
	player.free()


func _test_magic_progress_reset_and_retain() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_learn_from_added_book("fire_spellbook", inventory)
	_learn_from_added_book("water_spellbook", inventory)
	_check(ExpeditionSession.select_spell("water_bolt"), "a learned spell must be selectable")
	var first_inventory := inventory

	ExpeditionSession.begin_new_journey(false)
	_check(ExpeditionSession.get_inventory() != first_inventory, "retaining magic progress must still start a fresh expedition inventory")
	_check(ExpeditionSession.is_spell_learned("fire_bolt") and ExpeditionSession.is_spell_learned("water_bolt"), "begin_new_journey(false) must retain learned spells")
	_check(ExpeditionSession.get_selected_spell() == "water_bolt", "begin_new_journey(false) must retain the selected learned spell")
	ExpeditionSession.ensure_journey()
	_check(ExpeditionSession.is_spell_learned("fire_bolt") and ExpeditionSession.get_selected_spell() == "water_bolt", "scene-style ensure_journey calls must not reset magic progress")

	ExpeditionSession.begin_new_journey()
	_check(not ExpeditionSession.is_spell_learned("fire_bolt") and not ExpeditionSession.is_spell_learned("water_bolt"), "a normal new journey must clear learned spells")
	_check(ExpeditionSession.get_selected_spell().is_empty(), "a normal new journey must clear spell selection")


func _test_staff_stamina_and_cooldown_gate() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_learn_from_added_book("fire_spellbook", inventory)
	_learn_from_added_book("water_spellbook", inventory)
	var fixture := _create_player_fixture(inventory)
	var world := fixture["world"] as Node3D
	var player := fixture["player"] as DungeonPlayer
	var initial_stamina := player.stamina
	var initial_projectiles := _count_projectiles(world)
	var selected_before := ExpeditionSession.get_selected_spell()
	_check(not player.select_spell_by_slot(1), "spell-slot selection must be rejected while a staff is not equipped")
	_check(ExpeditionSession.get_selected_spell() == selected_before, "rejected spell-slot selection must preserve the previous selection")

	var sword_rejection := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(not bool(sword_rejection.get("accepted", true)) and str(sword_rejection.get("reason", "")) == "staff_required", "a learned spell must not cast while a sword is equipped")
	_check_close(player.stamina, initial_stamina, "staff-gate rejection must not spend stamina")
	_check(_count_projectiles(world) == initial_projectiles, "staff-gate rejection must not spawn a projectile")

	_check(inventory.add_item("weathered_staff", 1) == 0, "staff fixture must fit in the expedition bag")
	var bag_only_rejection := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(not bool(bag_only_rejection.get("accepted", true)) and str(bag_only_rejection.get("reason", "")) == "staff_required", "merely carrying a staff must not permit casting")
	_check_close(player.stamina, initial_stamina, "bag-only staff rejection must not spend stamina")
	_check(_count_projectiles(world) == initial_projectiles, "bag-only staff rejection must not spawn a projectile")

	_check(_equip_staff(inventory), "equipping the weathered staff through the inventory model must succeed")
	_check(player.select_spell_by_slot(1), "equipping a staff must allow selecting a learned spell by slot")
	_check(ExpeditionSession.get_selected_spell() == "water_bolt", "staff-enabled slot selection must select the matching learned spell")
	_check(player.select_spell_by_slot(0) and ExpeditionSession.get_selected_spell() == "fire_bolt", "the equipped staff must allow returning to the learned fire slot")
	var fire_definition := SpellCatalog.get_spell_definition("fire_bolt")
	var stamina_cost := float(fire_definition.get("stamina_cost", -1.0))
	var cooldown := float(fire_definition.get("cooldown", -1.0))
	var cast := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(bool(cast.get("accepted", false)), "an equipped staff and learned spell must permit casting")
	_check_close(float(cast.get("stamina_spent", -1.0)), stamina_cost, "successful cast result must report the authored stamina cost")
	_check_close(player.stamina, initial_stamina - stamina_cost, "successful casting must subtract the exact authored stamina cost")
	_check_close(player.spell_cooldown, cooldown, "successful casting must start the authored cooldown")
	_check(cast.get("projectile") is MagicProjectile, "a successful fire cast must return its projectile")

	var stamina_after_cast := player.stamina
	var projectiles_after_cast := _count_projectiles(world)
	var cooldown_rejection := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(not bool(cooldown_rejection.get("accepted", true)) and str(cooldown_rejection.get("reason", "")) == "cooldown", "immediate repeated casting must be rejected by cooldown")
	_check_close(player.stamina, stamina_after_cast, "cooldown rejection must not spend stamina")
	_check(_count_projectiles(world) == projectiles_after_cast, "cooldown rejection must not spawn another projectile")

	player._physics_process(cooldown + 0.01)
	_check_close(player.spell_cooldown, 0.0, "authored cooldown must expire through normal player simulation")
	var post_cooldown_cast := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(bool(post_cooldown_cast.get("accepted", false)), "the spell must cast again after cooldown expires")

	player.spell_cooldown = 0.0
	player.stamina = maxf(0.0, stamina_cost - 0.01)
	var insufficient_before := player.stamina
	var projectile_count_before := _count_projectiles(world)
	var insufficient := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(not bool(insufficient.get("accepted", true)) and str(insufficient.get("reason", "")) == "not_enough_stamina", "casting below the exact stamina cost must be rejected")
	_check_close(player.stamina, insufficient_before, "insufficient-stamina rejection must not change stamina")
	_check(_count_projectiles(world) == projectile_count_before, "insufficient-stamina rejection must not spawn a projectile")
	world.free()


func _test_weapon_state_transitions() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var fixture := _create_player_fixture(inventory)
	var world := fixture["world"] as Node3D
	var player := fixture["player"] as DungeonPlayer
	_check(player._equipped_weapon_type() == "melee", "the default connected inventory must expose its sword as a melee weapon")
	_check(player.sword_visual_root != null and player.sword_visual_root.visible, "the equipped default sword must start visible")

	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	player.prepare_for_inventory()
	_check(player.combat_state == DungeonPlayer.CombatState.READY, "opening inventory preparation during an active swing must cancel it to READY")

	player._set_combat_state(DungeonPlayer.CombatState.ACTIVE)
	var unequip_result := inventory.unequip("weapon")
	_check(bool(unequip_result.get("accepted", false)), "the connected inventory must unequip its default sword")
	_check(player.combat_state == DungeonPlayer.CombatState.READY, "changing equipment during an active swing must cancel it to READY")
	_check(player._equipped_weapon_type() == "unarmed", "an empty connected weapon slot must report the player as unarmed")
	_check(player.sword_visual_root != null and not player.sword_visual_root.visible, "unequipping the weapon must hide the sword visual")
	_check(not player.is_sword_attack_active(), "an unarmed player must never retain an active sword hit window")

	player.stamina = DungeonPlayer.MAX_STAMINA
	player._try_begin_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.READY, "an unarmed player must be unable to begin a melee attack")
	world.free()


func _test_elemental_projectiles() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(inventory.add_item("weathered_staff", 1) == 0 and _equip_staff(inventory), "elemental fixture must equip the weathered staff")
	for book_id in ["fire_spellbook", "water_spellbook", "ice_spellbook", "stone_spellbook"]:
		_learn_from_added_book(book_id, inventory)
	var fixture := _create_player_fixture(inventory)
	var world := fixture["world"] as Node3D
	var player := fixture["player"] as DungeonPlayer
	var target := SpellTarget.new()
	world.add_child(target)
	var seen_elements: Dictionary = {}

	for spell_id in PROJECTILE_SPELL_IDS:
		player.spell_cooldown = 0.0
		player.stamina = DungeonPlayer.MAX_STAMINA
		var definition := SpellCatalog.get_spell_definition(spell_id)
		var expected_cost := float(definition.get("stamina_cost", -1.0))
		var expected_damage := float(definition.get("damage", -1.0))
		var expected_element := str(definition.get("element", ""))
		var hits_before := target.hit_count
		var damage_before := target.total_damage
		var cast := player.cast_spell(spell_id, Vector3.FORWARD)
		var projectile := cast.get("projectile") as MagicProjectile
		_check(bool(cast.get("accepted", false)), "%s must cast successfully with its book learned and staff equipped" % spell_id)
		_check(projectile != null and is_instance_valid(projectile), "%s must create a live MagicProjectile" % spell_id)
		_check_close(player.stamina, DungeonPlayer.MAX_STAMINA - expected_cost, "%s must subtract its exact stamina cost" % spell_id)
		if projectile == null or not is_instance_valid(projectile):
			continue
		_check(projectile.get_parent() == world, "%s projectile must spawn into the active gameplay world" % spell_id)
		_check(projectile.spell_id == spell_id, "%s projectile must preserve its spell ID" % spell_id)
		_check(projectile.element == expected_element, "%s projectile must preserve its authored element" % spell_id)
		_check_close(projectile.damage, expected_damage, "%s projectile must preserve its authored damage" % spell_id)
		_check_close(projectile.speed, float(definition.get("speed", -1.0)), "%s projectile must preserve its authored speed" % spell_id)
		seen_elements[projectile.element] = true

		_check(projectile.resolve_hit(target), "%s projectile must resolve its first valid target hit" % spell_id)
		_check(target.hit_count == hits_before + 1, "%s projectile must damage its target exactly once" % spell_id)
		_check_close(target.total_damage, damage_before + expected_damage, "%s projectile must deliver its authored damage" % spell_id)
		_check_close(target.last_damage, expected_damage, "%s hit callback must receive the authored damage" % spell_id)
		_check(not target.last_headshot, "%s projectile damage must not masquerade as a headshot" % spell_id)
		_check(not projectile.resolve_hit(target), "%s projectile must reject a second resolution" % spell_id)
		_check(target.hit_count == hits_before + 1, "%s projectile must not deal duplicate collision damage" % spell_id)

	_check(seen_elements.size() == PROJECTILE_SPELL_IDS.size(), "fire, water, ice, and stone casts must create four distinct projectile elements")
	world.free()


func _test_swept_sphere_physics() -> void:
	var definition := SpellCatalog.get_spell_definition("fire_bolt")
	var projectile_radius := float(definition.get("radius", 0.15))
	var target_radius := projectile_radius * 0.20
	var lateral_offset := projectile_radius * 0.75

	# A zero-width centre ray deliberately misses this small enemy, while the
	# projectile's authored sphere still overlaps it during the same sweep.
	var edge_world := Node3D.new()
	edge_world.name = "SweptSphereEdgeWorld"
	root.add_child(edge_world)
	var edge_target := PhysicsSpellTarget.new(target_radius, MagicProjectile.ENEMY_LAYER)
	edge_target.position = Vector3(lateral_offset, 0.0, -2.0)
	edge_world.add_child(edge_target)
	await physics_frame
	var centre_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3(0.0, 0.0, -3.0), MagicProjectile.ENEMY_LAYER)
	centre_ray.collide_with_areas = false
	centre_ray.collide_with_bodies = true
	var centre_hit := edge_world.get_world_3d().direct_space_state.intersect_ray(centre_ray)
	_check(centre_hit.is_empty(), "the off-centre enemy fixture must genuinely miss the projectile centre ray")
	_check(lateral_offset < projectile_radius + target_radius, "the off-centre enemy fixture must remain inside the projectile sphere radius")
	var edge_projectile := _spawn_physics_projectile(edge_world, null, definition, Vector3.ZERO)
	await _wait_for_physics_resolution(edge_target, edge_projectile)
	_check(edge_target.hit_count == 1, "a centre-ray miss inside the projectile radius must be hit by the swept sphere")
	_check_close(edge_target.total_damage, float(definition.get("damage", -1.0)), "the swept-sphere edge hit must apply the authored damage exactly once")
	edge_world.queue_free()
	await process_frame

	# A WORLD_LAYER body closer than the enemy must resolve the projectile as a
	# blocker even when the same sweep could otherwise reach the target behind it.
	var wall_world := Node3D.new()
	wall_world.name = "SweptSphereWallWorld"
	root.add_child(wall_world)
	var wall := _create_world_wall(Vector3(0.0, 0.0, -1.0), Vector3(2.0, 2.0, 0.08))
	wall_world.add_child(wall)
	var blocked_target := PhysicsSpellTarget.new(0.2, MagicProjectile.ENEMY_LAYER)
	blocked_target.position = Vector3(0.0, 0.0, -2.0)
	wall_world.add_child(blocked_target)
	await physics_frame
	var blocked_projectile := _spawn_physics_projectile(wall_world, null, definition, Vector3.ZERO)
	await _wait_for_physics_resolution(blocked_target, blocked_projectile)
	_check(blocked_target.hit_count == 0, "a WORLD_LAYER wall in front of an enemy must block all projectile damage")
	_check(not is_instance_valid(blocked_projectile), "a projectile blocked by a world wall must resolve and leave the physics world")
	wall_world.queue_free()
	await process_frame

	# Put a collider using the enemy mask directly around the launch point. It
	# would consume the first sweep without the explicit caster exception.
	var caster_world := Node3D.new()
	caster_world.name = "SweptSphereCasterWorld"
	root.add_child(caster_world)
	var caster := PhysicsSpellTarget.new(0.36, MagicProjectile.ENEMY_LAYER)
	caster.position = Vector3.ZERO
	caster_world.add_child(caster)
	var downstream_target := PhysicsSpellTarget.new(0.2, MagicProjectile.ENEMY_LAYER)
	downstream_target.position = Vector3(0.0, 0.0, -2.2)
	caster_world.add_child(downstream_target)
	await physics_frame
	var caster_projectile := _spawn_physics_projectile(caster_world, caster, definition, Vector3.ZERO)
	await _wait_for_physics_resolution(downstream_target, caster_projectile)
	_check(caster.hit_count == 0, "the projectile sweep must exclude its caster even when launched inside the caster collider")
	_check(downstream_target.hit_count == 1, "caster exclusion must let the projectile continue to a downstream enemy")
	caster_world.queue_free()
	await process_frame


func _test_healing_spell() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(inventory.add_item("weathered_staff", 1) == 0 and _equip_staff(inventory), "healing fixture must equip the weathered staff")
	_learn_from_added_book("healing_spellbook", inventory)
	var fixture := _create_player_fixture(inventory)
	var world := fixture["world"] as Node3D
	var player := fixture["player"] as DungeonPlayer
	var definition := SpellCatalog.get_spell_definition("healing_light")
	var heal_amount := float(definition.get("heal_amount", -1.0))
	var stamina_cost := float(definition.get("stamina_cost", -1.0))
	player.health = 50.0
	player.stamina = DungeonPlayer.MAX_STAMINA

	var cast := player.cast_spell("healing_light", Vector3.FORWARD)
	_check(bool(cast.get("accepted", false)), "healing_light must cast when health is missing")
	_check_close(float(cast.get("health_restored", -1.0)), heal_amount, "healing_light result must report the exact authored healing")
	_check_close(player.health, 50.0 + heal_amount, "healing_light must restore the exact authored health")
	_check_close(player.stamina, DungeonPlayer.MAX_STAMINA - stamina_cost, "healing_light must spend its exact authored stamina cost")
	_check(cast.get("projectile") == null, "healing_light must apply directly without spawning a projectile")

	player.spell_cooldown = 0.0
	player.health = DungeonPlayer.MAX_HEALTH
	var full_stamina := player.stamina
	var projectile_count := _count_projectiles(world)
	var full_rejection := player.cast_spell("healing_light", Vector3.FORWARD)
	_check(not bool(full_rejection.get("accepted", true)) and str(full_rejection.get("reason", "")) == "already_full", "healing_light must be rejected at full health")
	_check_close(player.stamina, full_stamina, "full-health healing rejection must not spend stamina")
	_check(_count_projectiles(world) == projectile_count, "full-health healing rejection must not create a projectile")
	world.free()


func _test_merchant_and_dungeon_spawns() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_learn_from_added_book("fire_spellbook", inventory)
	_check(ExpeditionSession.select_spell("fire_bolt"), "scene-persistence fixture must select its learned spell")
	for item_id in MAGIC_ITEM_IDS:
		_check(ExpeditionSession.DEFAULT_MERCHANT_STOCK.has(item_id), "%s must be authored in the merchant catalog" % item_id)
		_check(ExpeditionSession.get_stock_quantity(item_id) > 0, "%s must spawn in current merchant stock" % item_id)

	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "the realtime dungeon must load for magic loot integration")
	if packed == null:
		return
	var game := packed.instantiate()
	game.loot_spawn_seed = preload("res://tests/loot_test_helpers.gd").seed_with_items("reliquary", MAGIC_ITEM_IDS)
	root.add_child(game)
	await process_frame
	await physics_frame
	_check(ExpeditionSession.is_spell_learned("fire_bolt") and ExpeditionSession.get_selected_spell() == "fire_bolt", "entering the dungeon scene must preserve learned and selected magic")
	_check(preload("res://tests/loot_test_helpers.gd").valid_count(game), "the dungeon must spawn its visit's selected loot sites")
	_check(game.loot_spawn_seed >= 0, "magic supplies must all remain obtainable together in at least one authored visit")
	var all_spawn_ids: Array[String] = []
	for chest: DungeonLootChest in game.loot_chests:
		all_spawn_ids.append_array(_container_item_ids(chest.container))
	for item_id in MAGIC_ITEM_IDS:
		_check(all_spawn_ids.has(item_id), "%s must be obtainable from occupied authored dungeon sites" % item_id)
	game.queue_free()
	await process_frame


func _learn_from_added_book(book_id: String, inventory: ExpeditionInventory) -> bool:
	if inventory.add_item(book_id, 1) > 0:
		_check(false, "%s fixture must fit in the expedition bag" % book_id)
		return false
	var result := ExpeditionSession.learn_spell_from_book(book_id, inventory)
	_check(bool(result.get("accepted", false)), "%s fixture must teach its spell" % book_id)
	return bool(result.get("accepted", false))


func _equip_staff(inventory: ExpeditionInventory) -> bool:
	for index in range(inventory.slots.size()):
		if str(inventory.slots[index].get("id", "")) != "weathered_staff":
			continue
		var result := inventory.equip_from_slot(index)
		return bool(result.get("accepted", false)) and str(inventory.equipment.get("weapon", "")) == "weathered_staff"
	return false


func _create_player_fixture(inventory: ExpeditionInventory) -> Dictionary:
	var world := Node3D.new()
	world.name = "MagicTestWorld"
	root.add_child(world)
	var player := DungeonPlayer.new()
	player.setup(world, null, inventory)
	world.add_child(player)
	return {"world": world, "player": player}


func _spawn_physics_projectile(world: Node3D, caster: Node, definition: Dictionary, spawn_position: Vector3) -> MagicProjectile:
	var projectile := MagicProjectile.new()
	projectile.configure("fire_bolt", definition, caster, Vector3.FORWARD)
	world.add_child(projectile)
	projectile.global_position = spawn_position
	return projectile


func _create_world_wall(wall_position: Vector3, wall_size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = MagicProjectile.WORLD_LAYER
	wall.collision_mask = 0
	wall.position = wall_position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = wall_size
	collision.shape = box
	wall.add_child(collision)
	return wall


func _wait_for_physics_resolution(target: PhysicsSpellTarget, projectile: MagicProjectile, maximum_frames := 40) -> void:
	for _frame_index in range(maximum_frames):
		await physics_frame
		if target.hit_count > 0 or not is_instance_valid(projectile):
			return


func _ensure_standalone_player_actions() -> void:
	# Runtime dungeon setup normally registers these before the player simulates.
	# This isolated fixture needs only empty actions so direct cooldown advancement
	# follows the regular player physics path without InputMap error noise.
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _count_projectiles(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is MagicProjectile:
			count += 1
	return count


func _container_item_ids(container: LootContainer) -> Array[String]:
	var result: Array[String] = []
	for stack in container.items:
		result.append(str(stack.get("id", "")))
	return result


func _check_close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= FLOAT_TOLERANCE, "%s (expected %.4f, got %.4f)" % [message, expected, actual])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MAGIC SYSTEM TEST PASS: books, persistence, staff gate, unarmed state, attack cancellation, stamina, cooldown, swept-sphere physics, five spells, merchant, and dungeon loot")
		quit(0)
		return
	for failure in failures:
		push_error("MAGIC SYSTEM TEST FAIL: %s" % failure)
	quit(1)
