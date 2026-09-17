extends "res://tests/creep_ragdoll_preview.gd"
## Same installed Creep, real hits and physics; no generated frames or desktop UI.
const CUT_CASES := [
 {"region": "right_arm", "title": "오른팔 절단 → 남은 팔·물기 공격 / ARM LOSS → CONTINUED COMBAT"},
 {"region": "left_leg", "title": "왼다리 절단 → 느린 추적 / LEG LOSS → SLOW PURSUIT"},
 {"region": "head", "title": "머리 절단 → 사망·래그돌 / HEAD LOSS → RAGDOLL"},
]
class TargetDummy extends DungeonPlayer:
 var contacts := 0
 func _ready() -> void:
  set_physics_process(false)
  set_process(false)
  set_process_input(false)
  set_process_unhandled_input(false)
 func receive_attack(_amount: float, _attacker: Vector3, _ailment := "", _part := "thorax") -> Dictionary:
  contacts += 1
  return {"blocked": false, "parried": false}

func _run() -> void:
 if DisplayServer.get_name() != "embedded":
  push_error("Only audited embedded rendering is permitted."); quit(2); return
 var tag := OS.get_environment("CREEP_DISMEMBERMENT_QA_ITERATION")
 if not tag.is_valid_filename() or tag.begins_with("."):
  push_error("Choose a new CREEP_DISMEMBERMENT_QA_ITERATION directory."); quit(2); return
 var record_video := OS.get_environment("CREEP_DISMEMBERMENT_VIDEO") == "1"
 var directory := "/private/tmp/creep-dismemberment-" + tag
 if DirAccess.dir_exists_absolute(directory):
  push_error("Cannot overwrite existing renders."); quit(2); return
 DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
 root.gui_disable_input = true
 root.physics_object_picking = false
 AudioServer.set_bus_mute(0, true)
 var cursor := Input.mouse_mode
 var session := ExpeditionSession.capture_snapshot()
 var sandbox := root.get_node("TestRoomSandbox")
 _check(not sandbox.active, "isolated preview session")
 sandbox.begin()
 var hashes := _source_hashes()
 for path in [CREEP.DISMEMBERMENT.MODEL_PATH, "res://scripts/creep_dismemberment.gd", "res://scripts/creep_severed_part.gd", "res://tests/creep_dismemberment_preview.gd"]:
  hashes[path] = FileAccess.get_sha256(path)
 var frame_number := 0
 var frames: Array = []
 var outcomes: Array = []
 for case: Dictionary in CUT_CASES:
  var viewport := _create_viewport()
  viewport.size = Vector2i(960, 540)
  viewport.size_2d_override = Vector2i(1280, 720)
  viewport.size_2d_override_stretch = true
  viewport.msaa_3d = Viewport.MSAA_DISABLED
  viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
  root.add_child(viewport)
  var fixture := _create_fixture(viewport, {"wall_position": Vector3(0, 2, 8), "wall_size": Vector3(.1, .1, .1), "title": case.title})
  for child in viewport.get_children():
   if child is CanvasLayer:
    for label in child.get_children():
     if label is Label and label.text.begins_with("CREEP  |"):
      label.text = "CREEP | 부위 절단 · 실제 3D / ANATOMICAL SEVERANCE"
  var actor = fixture.actor
  actor.health = 82; actor.max_health = 82
  var target := TargetDummy.new()
  fixture.world.add_child(target)
  target.position = Vector3(0, .9, -1.4)
  actor.target = target
  # Match production game's attack-resolution pass after actor physics.
  fixture.world.get_parent().name = "IsolatedRuntime_" + case.region
  fixture.camera.position = Vector3(-2.7, 2.0, -4.3) if case.region != "left_leg" else Vector3(3.6, 2.2, -5.2)
  fixture.camera.look_at(Vector3(0, .9, -.9) if case.region == "left_leg" else Vector3(0, .9, -.2))
  actor.set_physics_process(false)
  for warm in 8:
   await process_frame
  _check(actor.dismemberment.enabled, "split geometry installed")
  var previous_tick := -1
  for frame in 90:
   await process_frame
   var tick := int(Engine.get_physics_frames())
   if previous_tick >= 0: _check(tick - previous_tick == 4, "continuous 60 Hz physics at 15 fps")
   previous_tick = tick
   if frame in [9, 21]:
    var point: Vector3 = actor.dismemberment.hit_point_for_region(case.region)
    actor.receive_located_hit(18, Vector3(0, .9, -3), .5, case.region == "head", point)
   if frame == 22:
    actor.set_physics_process(true)
    if case.region.ends_with("leg"): target.position.z = -3.0
    actor.attack_index = 0
   actor._resolve_active_attack()
   fixture.status.text = "%0.2f초 | 누적 %d / 35 | 절단 %s | HP %d | %s" % [float(frame)/15, actor.dismemberment.damage[case.region], str(actor.dismemberment.severed), actor.health, actor.animation_clip]
   if record_video or frame in [8, 21, 28, 60, 89]:
    # Render exactly once per recorded physics state. Continuous UPDATE_ALWAYS
    # also rendered while disk readback was pending in the previous attempt.
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var rendered := viewport.get_texture().get_image()
    if record_video:
     _check(rendered.save_jpg(directory.path_join("frames/%05d.jpg" % frame_number), .94) == OK, "continuous GPU frame saved")
    if frame in [8, 21, 28, 60, 89]:
     _check(rendered.save_png(directory.path_join("%s_%03d.png" % [case.region, frame])) == OK, "GPU still saved")
   frames.append({"frame": frame_number, "case": case.region, "case_frame": frame, "state": actor.ai_state, "clip": actor.animation_clip, "snapshot": actor.dismemberment.snapshot(), "ragdoll": actor.ragdoll.phase, "contacts": target.contacts})
   frame_number += 1
  _check(actor.dismemberment.severed == [case.region], "only selected region severed")
  _check((actor.ai_state == DungeonEnemy.AIState.DEAD) == (case.region == "head"), "correct survival behavior")
  if case.region == "right_arm": _check(target.contacts > 0, "surviving Creep still attacks target")
  outcomes.append({"region": case.region, "contacts": target.contacts, "snapshot": actor.dismemberment.snapshot(), "position": actor.position})
  viewport.queue_free()
  await process_frame
  print("CREEP DISMEMBERMENT CASE: ", case.region)
 sandbox.finish()
 _check(session == ExpeditionSession.capture_snapshot(), "original expedition restored")
 _check(cursor == Input.mouse_mode, "cursor unchanged")
 for path: String in hashes: _check(hashes[path] == FileAccess.get_sha256(path), "source unchanged: " + path)
 var output := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
 output.store_string(JSON.stringify(_json_safe({"capture_mode": "Continuous real GPU frames" if record_video else "Selected real GPU frames; no video", "frames": frames, "outcomes": outcomes, "hashes": hashes, "failures": failures, "fps": 15, "physics_hz": 60, "renderer": "embedded Vulkan Forward+"}), "\t"))
 print("CREEP DISMEMBERMENT PREVIEW %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
 quit(0 if failures.is_empty() else 1)
