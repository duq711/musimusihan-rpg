extends SceneTree
const A=preload("res://scripts/sword_long_grip_visual.gd")
func _initialize():call_deferred("run")
func run():
 if DisplayServer.get_name()!="embedded":push_error("Expected embedded display");quit(2);return
 var cursor=Input.mouse_mode
 var viewport=SubViewport.new();viewport.size=Vector2i(900,900);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 var stage=Node3D.new();viewport.add_child(stage)
 var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color(.06,.075,.09);e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color(.9,.92,1.0);e.ambient_light_energy=.8;env.environment=e;stage.add_child(env)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=1.3;stage.add_child(light)
 var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(10,145,0);fill.light_energy=.5;stage.add_child(fill)
 var arm=A.new();stage.add_child(arm);arm.setup();var fp=arm._fp_arm;var rig=fp.skeleton
 var sword=A.create_sword();stage.add_child(sword)
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.34;camera.near=.001;stage.add_child(camera);camera.make_current()
 var output="/private/tmp/thrust-grip-render";DirAccess.make_dir_recursive_absolute(output)
 var poses_before=[]
 for i in rig.get_bone_count():poses_before.append(rig.get_bone_pose(i))
 for amount in [0.0,1.0]:
  arm.set_thrust_grip(amount)
  var wrist=A.wrist_local(amount);var neutral=A.neutral_axis_local(amount);var elbow=wrist+neutral*.26;var shoulder=elbow+neutral*.34
  arm.fit_arm(shoulder,elbow)
  var i=0
  for position in [Vector3(.35,-.13,.30),Vector3(-.35,-.13,-.24),Vector3(-.35,-.13,.26),Vector3(.35,-.13,-.27)]:
   camera.position=position;camera.look_at(Vector3(0,-.135,0),Vector3.UP)
   for warm in 3:await process_frame
   await RenderingServer.frame_post_draw
   viewport.get_texture().get_image().save_png(output+"/grip_%d_view_%d.png"%[int(amount),i]);i+=1
 arm.set_thrust_grip(0)
 var restored=true
 for i in rig.get_bone_count():
  if rig.get_bone_name(i)in ["upper","elbow","forearm"]:continue
  restored=restored and rig.get_bone_pose(i).is_equal_approx(poses_before[i])
 print("THRUST GRIP REAL RENDER PASS images=8 hand_restored=",restored," cursor=",cursor==Input.mouse_mode," display=",DisplayServer.get_name())
 viewport.queue_free();await process_frame;quit(0 if restored else 1)
