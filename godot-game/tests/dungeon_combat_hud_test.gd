extends SceneTree
const HUD := preload("res://scripts/hud.gd")
const PANEL := preload("res://scripts/dungeon_combat_hud.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _run() -> void:
 var original := ExpeditionSession.capture_snapshot()
 var cursor := Input.mouse_mode
 var sandbox := root.get_node("TestRoomSandbox")
 sandbox.begin()
 var bag := ExpeditionSession.get_inventory()
 bag.seed_default_loadout()
 for id in ["healing_draught", "linen_bandage", "pilgrim_ration", "boiled_rainwater", "purifying_salt"]: bag.add_item(id,3)
 var player := DungeonPlayer.new()
 player.inventory_model = bag
 var hud := HUD.new()
 root.add_child(hud)
 var overlay := InventoryOverlay.new()
 root.add_child(overlay)
 hud.enable_combat_interface(player,bag,overlay._item_texture)
 var panel: Control = hud.combat_panel
 ExpeditionSession.clear_conditions()
 ExpeditionSession.hunger = 100
 ExpeditionSession.thirst = 100
 ExpeditionSession.stress = 0
 player.stamina = player.MAX_STAMINA
 panel.refresh()
 check(panel.warnings.is_empty(), "Healthy state must not show any warnings")
 check(panel.item_ids.size()==10 and panel.textures.values().all(func(t): return t != null), "Ten real textured inventory shortcuts")
 player.apply_body_damage("left_arm", 60)
 player.apply_condition("curse", 120)
 ExpeditionSession.hunger = 15
 ExpeditionSession.thirst = 15
 ExpeditionSession.stress = 65
 player.stamina = 15
 panel.refresh()
 check(panel.warnings == ["hunger","thirst","fatigue","dizziness","curse"], "Only actual threshold/condition warnings")
 check(panel.body_snapshot.parts.left_arm.health == 0 and panel.body_snapshot.parts.right_arm.health == 60, "Independent actual body health")
 player.select_treatment_part("left_arm")
 var medicine := bag.count_item("healing_draught")
 check(not panel.activate_slot(3).accepted and bag.count_item("healing_draught")==medicine, "Zero limb rejects ordinary medicine without consumption")
 player.select_treatment_part("")
 player.apply_body_damage("right_arm", 20)
 var event := InputEventKey.new()
 event.physical_keycode = KEY_4
 event.pressed = true
 check(panel.handle_shortcut(event) and bag.count_item("healing_draught")==medicine, "4 begins use without early consumption")
 player.advance_item_use(20)
 panel.refresh()
 check(bag.count_item("healing_draught")==medicine-1, "4 consumes one real medicine and heals viable limb")
 var food := bag.count_item("pilgrim_ration")
 event.physical_keycode = KEY_6
 panel.handle_shortcut(event)
 player.advance_item_use(20)
 panel.refresh()
 check(bag.count_item("pilgrim_ration")==food-1 and ExpeditionSession.hunger>25 and "hunger" not in panel.warnings, "Food consumption clears hunger warning")
 event.physical_keycode = KEY_7
 panel.handle_shortcut(event)
 player.advance_item_use(20)
 panel.refresh()
 check(ExpeditionSession.thirst>25 and "thirst" not in panel.warnings, "Water clears thirst warning")
 event.physical_keycode = KEY_9
 panel.handle_shortcut(event)
 player.advance_item_use(20)
 panel.refresh()
 check("curse" not in panel.warnings, "Actual purification clears curse icon")
 bag.add_item("hunting_bow")
 var sword_count := bag.count_item("rusted_sword")
 event.physical_keycode = KEY_2
 panel.handle_shortcut(event)
 player.advance_item_use(20)
 panel.refresh()
 check(bag.equipment.weapon=="hunting_bow" and bag.count_item("rusted_sword")==sword_count+1, "2 equips bow and returns sword")
 event.physical_keycode = KEY_1
 panel.handle_shortcut(event)
 player.advance_item_use(20)
 panel.refresh()
 check(bag.equipment.weapon=="rusted_sword", "1 equips sword")
 var snapshot := bag.slots.duplicate(true)
 paused = true
 check(not panel.activate_slot(5).accepted and bag.slots==snapshot, "Paused inventory/F2 cannot consume")
 paused = false
 event.echo = true
 check(not panel.handle_shortcut(event), "Key repeat cannot consume")
 event.echo = false
 event.alt_pressed = true
 check(not panel.handle_shortcut(event), "Alt number reserved for spell selection")
 event.alt_pressed = false
 player.apply_condition("paralysis", 4)
 check(not panel.activate_slot(5).accepted and bag.slots==snapshot, "Paralysis blocks quick transactions")
 hud.set_combat_interface_enabled(false)
 check(not panel.visible and hud.crosshair.text=="·", "Legacy/test-room HUD restored outside trial")
 hud.free()
 overlay.free()
 player.free()
 sandbox.finish()
 check(ExpeditionSession.capture_snapshot()==original and Input.mouse_mode==cursor, "Original expedition and cursor preserved")
 for failure in failures: push_error(failure)
 print("DUNGEON COMBAT HUD TEST %s: real hotkeys, healing, equipment, warnings, paused actions and restoration" % ("PASS" if failures.is_empty() else "FAIL"))
 quit(0 if failures.is_empty() else 1)
