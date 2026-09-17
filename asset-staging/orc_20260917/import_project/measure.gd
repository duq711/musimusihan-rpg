extends SceneTree
func _init():call_deferred("run")
func run():
 var model=load("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/3d/enemies/orc/orc.scn").instantiate()
 root.add_child(model)
 var sk=model.find_child("Skeleton3D",true,false)
 var ap=model.find_child("AnimationPlayer",true,false)
 for clip in ["atack1","atack2","atack3"]:
  ap.play(clip)
  for frame in 21:
   ap.seek(ap.get_animation(clip).length*frame/20.0,true)
   var points=[]
   for key in ["ork_left_axe_1_2","ork_right_axe_1_2"]:
    var index=sk.find_bone(key)
    points.append(sk.get_bone_global_pose(index).origin if index>=0 else Vector3.ZERO)
   print(clip," ",frame/20.0," ",points)
 quit()
