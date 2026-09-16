extends SceneTree
const BOW := preload("res://scripts/archery_visuals.gd")
const FLAIL := preload("res://scripts/flail_visuals.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var hud := DungeonHUD.new()
	root.add_child(hud)
	hud.update_stress(1.0)
	var stable := hud.stress_bar.get_theme_stylebox("fill")
	for i in 90:
		hud.update_stress(1.0 + float(i) * 0.01)
		_check(hud.stress_bar.get_theme_stylebox("fill") == stable, "live fractional stress must reuse its severity style rather than allocating every tick")
	_check(is_equal_approx(hud.stress_bar.value, 1.89), "style reuse must retain precise live meter values")
	for value in [40.0, 60.0, 80.0, 0.0]:
		hud.update_stress(value)
		var fill := hud.stress_bar.get_theme_stylebox("fill") as StyleBoxFlat
		_check(fill.bg_color.is_equal_approx(DungeonHUD.stress_color(value).darkened(0.15)), "all severity transitions must keep the original palette")
	_check(hud.stress_bar.get_theme_stylebox("fill") == stable and hud._stress_fill_styles.size() == 4, "returning to stable reuses the original style with a four-style lifetime bound")
	hud.update_weapon_state("무기 준비", Color(0.2, 0.3, 0.4))
	hud.update_weapon_state("공격 준비", Color(0.8, 0.5, 0.2))
	_check(hud.state_label.text == "공격 준비" and hud.state_label.get_theme_color("font_color") == Color(0.8, 0.5, 0.2), "changed text and color remain immediately visible")
	hud.update_conditions({"bleeding": 2.0}, 1.3)
	hud.update_conditions({}, 1.0)
	_check(hud.condition_label.text == "상태 · 안정", "clearing conditions must replace a cached warning")
	paused = true
	hud.update_stress(85.0)
	_check(hud.stress_bar.value == 85.0, "manual test-room values must still update while the game is paused")
	paused = false
	var other := DungeonHUD.new()
	root.add_child(other)
	other.update_stress(0.0)
	_check(other.stress_bar.get_theme_stylebox("fill") != stable, "separate scene HUDs must own independent mutable style resources")
	other.free()
	hud.free()
	var world := Node3D.new()
	root.add_child(world)
	var bow := BOW.create_bow()
	world.add_child(bow)
	var relaxed := _bow_arrays(bow)
	BOW.set_bow_draw(bow, 0.5)
	var arrow := bow.get_node("NockedArrow") as Node3D
	var pulled_position := arrow.position
	var pulled_mesh: Mesh = (bow.get_node("SmoothBentOakLimb_1") as MeshInstance3D).mesh
	for i in 30:
		bow.position = Vector3(float(i), 0, 0)
		bow.visible = i % 2 == 0
		BOW.set_bow_draw(bow, 0.5)
	_check(arrow.position == pulled_position and (bow.get_node("SmoothBentOakLimb_1") as MeshInstance3D).mesh == pulled_mesh, "same local draw remains attached through parent motion and visibility changes")
	BOW.set_bow_draw(bow, 1.0)
	_check(arrow.position != pulled_position, "a changed draw must immediately move the real string and nocked arrow")
	BOW.set_bow_draw(bow, 0.0)
	_check(_bow_arrays(bow) == relaxed, "draw cancellation must restore the exact relaxed authored bow geometry")
	var flail := FLAIL.create_flail()
	world.add_child(flail)
	var chain := flail.get_node("Chain") as Node3D
	var links := chain.get_node("Links") as MultiMeshInstance3D
	var idle_count := links.multimesh.visible_instance_count
	for i in 30:
		flail.rotation.y = float(i) * 0.1
		FLAIL.set_head_visible(flail, false)
		FLAIL.set_head_position(flail, Vector3(0.15, -0.16, -0.62))
		FLAIL.set_head_visible(flail, true)
	_check(links.multimesh.visible_instance_count == idle_count and chain.visible, "cached held links survive hidden equipment and restored head visibility")
	FLAIL.update_chain(chain, Vector3.ZERO, Vector3.UP * 14.0, 0.035)
	_check(links.multimesh.visible_instance_count > idle_count and (chain.get_node("End") as Node3D).position == Vector3.UP * 14.0, "outbound chain changes still upload their new length and endpoint")
	FLAIL.update_chain(chain, Vector3.ZERO, Vector3.ZERO)
	_check(links.multimesh.visible_instance_count == 0, "collapsed returning chain remains safe")
	FLAIL.set_head_position(flail, Vector3(0.15, -0.16, -0.62))
	_check(links.multimesh.visible_instance_count == idle_count, "return/reset restores the held chain after an unrelated trajectory")
	world.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse, "visual cache lifecycle cannot change expedition or capture input")
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("RUNTIME VISUAL CACHE PASS: four stable HUD styles, precise live values and immediate transitions, paused updates, independent scenes, local bow draw through motion/hiding/cancel, chain throw/return/reset and state isolation")
	quit(0 if failures.is_empty() else 1)


func _bow_arrays(bow: Node3D) -> PackedVector3Array:
	var limb := bow.get_node("SmoothBentOakLimb_1") as MeshInstance3D
	return limb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _check(value: bool, message: String) -> void:
	if not value and not failures.has(message):
		failures.append(message)
