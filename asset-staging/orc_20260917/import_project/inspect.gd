extends SceneTree
func _init():call_deferred("run")
func run():
 var doc=FBXDocument.new()
 var state=FBXState.new()
 var err=doc.append_from_file("/Users/duq711gmail.com/Downloads/animation fbx/ork@idle1.fbx",state)
 print("FBX_RESULT ",err)
 var scene=doc.generate_scene(state)
 root.add_child(scene)
 dump(scene)
 var gd=GLTFDocument.new();var gs=GLTFState.new()
 print("GLTF append ",gd.append_from_scene(scene,gs))
 print("GLTF write ",gd.write_to_filesystem(gs,"/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/orc_20260917/idle_import.glb"))
 quit()
func dump(n):
 print(n.get_path()," ",n.get_class())
 if n is MeshInstance3D:print(" mesh ",n.mesh.get_aabb()," skin ",n.skin," mat ",n.mesh.surface_get_material(0))
 if n is Skeleton3D:
  for i in n.get_bone_count():print(" bone ",i," ",n.get_bone_name(i)," ",n.get_bone_rest(i).origin)
 if n is AnimationPlayer:
  for a in n.get_animation_list():print(" clip ",a," ",n.get_animation(a).length," tracks ",n.get_animation(a).get_track_count())
 for c in n.get_children():dump(c)
