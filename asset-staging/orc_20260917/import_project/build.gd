extends SceneTree
const ROOT="/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/"
const OUT=ROOT+"godot-game/assets/3d/enemies/orc/"
var records={}
func _init():call_deferred("run")
func run():
 var base=import_fbx("idle1")
 base.name="OrcModel"
 root.add_child(base)
 var player=base.find_child("AnimationPlayer",true,false) as AnimationPlayer
 for lib in player.get_animation_library_list():player.remove_animation_library(lib)
 var library=AnimationLibrary.new()
 var wanted=["idle1","idle2","walk","run","atack1","atack2","atack3","gethit","death","roar","jump","wound"]
 for clip in wanted:
  var other=import_fbx(clip)
  var ap=other.find_child("AnimationPlayer",true,false) as AnimationPlayer
  var animation=ap.get_animation(ap.get_animation_list()[0]).duplicate(true) as Animation
  animation.resource_name=clip
  animation.loop_mode=Animation.LOOP_LINEAR if clip in ["idle1","idle2","walk","run","wound"] else Animation.LOOP_NONE
  # Remove only horizontal root travel: CharacterBody3D owns world movement.
  # Preserve the vertical bounce and every original joint rotation.
  for track in animation.get_track_count():
   var path=str(animation.track_get_path(track))
   if animation.track_get_type(track)==Animation.TYPE_POSITION_3D and path.ends_with(":ork_Hips"):
    var first=animation.track_get_key_value(track,0)
    for key in animation.track_get_key_count(track):
     var v=animation.track_get_key_value(track,key);v.x=first.x;v.z=first.z
     animation.track_set_key_value(track,key,v)
  assert(library.add_animation(clip,animation)==OK)
  records[clip]={"seconds":animation.length,"tracks":animation.get_track_count()}
  other.free()
 player.add_animation_library("",library)
 var body=make_material("ork");var axe=make_material("axe")
 prepare(base,base,body,axe)
 player.play("idle1");player.seek(0,true);player.pause()
 var packed=PackedScene.new();assert(packed.pack(base)==OK)
 assert(ResourceSaver.save(packed,OUT+"orc.scn")==OK)
 var file=FileAccess.open(OUT+"animations.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
 print("ORC BUILD PASS ",records)
 quit()
func import_fbx(clip):
 var doc=FBXDocument.new();var state=FBXState.new()
 assert(doc.append_from_file("/Users/duq711gmail.com/Downloads/animation fbx/ork@"+clip+".fbx",state)==OK)
 return doc.generate_scene(state)
func texture(path,normal=false):
 var im=Image.load_from_file(OUT+path+".png");assert(im!=null)
 im.generate_mipmaps(normal)
 return ImageTexture.create_from_image(im)
func make_material(kind):
 var m=StandardMaterial3D.new();m.resource_name="Orc_"+kind
 m.albedo_texture=texture(kind+"_albedo")
 m.normal_enabled=true;m.normal_texture=texture(kind+"_normal",true)
 m.roughness_texture=texture(kind+"_roughness");m.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
 m.metallic_texture=texture(kind+"_metallic");m.metallic=1.0
 m.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
 m.ao_enabled=true;m.ao_texture=texture(kind+"_occlusion")
 m.ao_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
 m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
 return m
func prepare(n,owner_root,body,axe):
 if n!=owner_root:n.owner=owner_root
 if n is MeshInstance3D:
  for surface in n.mesh.get_surface_count():
   var mat=n.mesh.surface_get_material(surface)
   n.mesh.surface_set_material(surface,axe if mat.resource_name=="lambert2" else body)
  n.custom_aabb=AABB(Vector3(-3,-2,-3),Vector3(6,6,6))
 for c in n.get_children():prepare(c,owner_root,body,axe)
