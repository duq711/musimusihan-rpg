extends SceneTree

const OUTPUT_PATH := "res://artifacts/visual_qa/apprentice_magic_fire.png"
const IMAGE_SIZE := Vector2i(1280, 720)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Magic preview requires a rendering display.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	inventory.add_item("weathered_staff", 1)
	for index in range(inventory.slots.size()):
		if str(inventory.slots[index].get("id", "")) == "weathered_staff":
			inventory.equip_from_slot(index)
			break
	for spell_id in SpellCatalog.SPELL_ORDER:
		ExpeditionSession.learn_spell(spell_id)
	ExpeditionSession.select_spell("fire_bolt")

	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	game.player.stamina = 78.0
	game.hud.update_stamina(78.0, game.player.MAX_STAMINA)
	var cast_result: Dictionary = game.player.cast_spell("fire_bolt")
	if not bool(cast_result.get("accepted", false)):
		push_error("Could not cast fire preview: %s" % str(cast_result.get("reason", "unknown")))
		quit(1)
		return
	await process_frame
	var projectile := cast_result.get("projectile") as MagicProjectile
	if is_instance_valid(projectile):
		projectile.set_physics_process(false)
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		(enemy as Node).set_physics_process(false)
	game.player._update_combat(0.0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save magic preview: %s" % error_string(error))
		quit(1)
		return
	print("MAGIC PREVIEW PASS: %s" % output_path)
	quit(0)
