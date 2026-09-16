extends SceneTree
const PREVIEW := preload("res://tests/dungeon_combat_hud_preview.gd")
func _init() -> void: call_deferred("_run")
func _run() -> void:
 var original := ExpeditionSession.capture_snapshot()
 var cursor := Input.mouse_mode
 var sandbox := root.get_node("TestRoomSandbox")
 sandbox.begin()
 root.gui_disable_input = true
 var failures: Array = []
 for shot in PREVIEW.shots():
  var viewport := PREVIEW.HELPERS.create_viewport(shot.size)
  root.add_child(viewport)
  var fixture := PREVIEW.create_fixture(viewport,shot)
  await process_frame
  var report := PREVIEW.inspect_fixture(viewport,fixture,shot)
  failures.append_array(report.failures)
  viewport.free()
  await process_frame
 sandbox.finish()
 if ExpeditionSession.capture_snapshot()!=original or Input.mouse_mode!=cursor: failures.append("Original state changed")
 for failure in failures: push_error(failure)
 print("DUNGEON COMBAT HUD PREVIEW TEST %s: production entry, real 3D scene, responsive HUD and treatment fixtures" % ("PASS" if failures.is_empty() else "FAIL"))
 quit(0 if failures.is_empty() else 1)
