extends SceneTree
const A=preload("res://scripts/sword_long_grip_visual.gd")
const IK=preload("res://scripts/reference_sword_arm.gd")
func _initialize():call_deferred("run")
func run():
 var arm=A.new();root.add_child(arm);arm.setup()
 var fp=arm._fp_arm;var rig=fp.skeleton
 var out={"skin":[],"candidates":[]}
 for amount in [0.0,1.0]:
  arm.set_thrust_grip(amount)
  var points={}
  for digit in ["little","ring","middle","index","thumb","palm"]:points[digit]=[]
  for part in fp.hand_meshes:
   for surf in part.mesh.get_surface_count():
    var a=part.mesh.surface_get_arrays(surf);var vs=a[Mesh.ARRAY_VERTEX];var bi=a[Mesh.ARRAY_BONES];var ws=a[Mesh.ARRAY_WEIGHTS]
    for i in vs.size():
     var p=Vector3.ZERO;var main="";var maxw=-1.0
     for j in 4:
      var k=i*4+j;var bind=bi[k];var b=part.skin.get_bind_bone(bind)
      if b<0:b=rig.find_bone(part.skin.get_bind_name(bind))
      p+=(rig.get_bone_global_pose(b)*part.skin.get_bind_pose(bind)*vs[i])*ws[k]
      if ws[k]>maxw:maxw=ws[k];main=rig.get_bone_name(b)
     p=rig.to_global(p)
     for digit in points:
      if main.begins_with(digit):points[digit].append([p.x,p.y,p.z])
  out.skin.append({"amount":amount,"points":points,"wrist":str(rig.to_global(rig.get_bone_global_pose(rig.find_bone("wrist")).origin)),"reported_wrist":str(A.wrist_local(amount))})
 var direction=Vector3(-.068232,-.207912,-.975765).normalized()
 var shoulder=Vector3(.248203,1.374,.781)
 var origin=Vector3(.0035,1.447,.2705)
 for roll in range(0,360,2):
  var worst=0.0;var rows=[];var penalty=0.0
  for twist in [0.0,-45.0]:
   var z=(Vector3.UP-direction*direction.dot(Vector3.UP)).normalized().rotated(direction,deg_to_rad(roll+twist))
   var basis=Basis(direction.cross(z).normalized(),direction,z)
   var wrist=origin+basis*A.wrist_local(1.0)
   var neutral=(basis*A.neutral_axis_local(1.0)).normalized()
   var fit=IK.solve(shoulder,wrist+neutral*.26,wrist)
   var fore=(fit.elbow-wrist).normalized()
   var mismatch=rad_to_deg(fore.angle_to(neutral))
   var bladeangle=rad_to_deg((-fore).angle_to(direction))
   worst=maxf(worst,mismatch)
   penalty+=pow(maxf(0,shoulder.x-fit.elbow.x)*100,2)+pow(maxf(0,fit.elbow.y-shoulder.y)*100,2)
   rows.append({"twist":twist,"mismatch":mismatch,"bladeangle":bladeangle,"elbow":str(fit.elbow),"wrist":str(wrist),"shoulder_adjust":fit.shoulder_adjustment_m})
  out.candidates.append({"roll":roll,"cost":worst+penalty,"rows":rows})
 out.candidates.sort_custom(func(a,b):return a.cost<b.cost)
 print("TOP ROLLS ",JSON.stringify(out.candidates.slice(0,10)))
 FileAccess.open("/private/tmp/thrust-candidates.json",FileAccess.WRITE).store_string(JSON.stringify(out))
 print("THRUST CANDIDATE PROBE DONE")
 quit()
