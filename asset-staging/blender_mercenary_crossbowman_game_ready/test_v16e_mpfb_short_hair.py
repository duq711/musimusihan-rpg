"""Test the CC0 MPFB short02 hair fitted to the v15 head."""
from collections import defaultdict
from pathlib import Path
import math
import json
import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING=ROOT/'asset-staging'/'blender_mercenary_crossbowman_game_ready';PREVIEWS=STAGING/'previews'
bpy.ops.wm.open_mainfile(filepath=str(STAGING/'mercenary_crossbowman_game_ready_v15.blend'))
scene=bpy.context.scene;camera=scene.camera;head=bpy.data.objects['Mercenary_Male_HeadNeck_LOD0'];rig=bpy.data.objects['Mercenary_Rigify_Rig_v4'];coll=head.users_collection[0]

# Append the existing CC0 MPFB short02 hair mesh.  Its authored dimensions are
# fitted with the exact v2 normalization and a small measured head-center shift.
with bpy.data.libraries.load(str(STAGING/'mpfb_base_test.blend'),link=False) as (src,dst):
 dst.objects=[n for n in ('Mercenary_Male_Hair',) if n in src.objects]
source=dst.objects[0];coll.objects.link(source)
source_hair_mat=source.data.materials[0]
source_hair_image=next(node.image for node in source_hair_mat.node_tree.nodes if node.type=='TEX_IMAGE' and node.image)
pixels=np.empty(len(source_hair_image.pixels),dtype=np.float32);source_hair_image.pixels.foreach_get(pixels)
rgba=pixels.reshape((-1,4))
# Preserve the source strand contrast while shifting the blond asset to a
# weathered dark brown.  Direct channel scaling retains much more detail than
# replacing RGB with a single luminance value.
rgba[:,:3]=np.clip(rgba[:,:3]*np.array((.58,.50,.42),dtype=np.float32)+np.array((.003,.002,.001),dtype=np.float32),0,1)
dark_image=bpy.data.images.get('short02_darkbrown_2k_v16j.png') or bpy.data.images.new('short02_darkbrown_2k_v16j.png',width=source_hair_image.size[0],height=source_hair_image.size[1],alpha=True)
dark_image.colorspace_settings.name=source_hair_image.colorspace_settings.name;dark_image.pixels.foreach_set(rgba.reshape(-1));dark_image.filepath_raw=str(STAGING/'textures'/'short02_darkbrown_2k_v16j.png');dark_image.file_format='PNG';dark_image.save()
dark_mat=source_hair_mat.copy();dark_mat.name='MAT_CC0_ShortHair_DarkBrown_2K_v16j';dark_mat.diffuse_color=(.08,.045,.025,1);dark_mat.use_backface_culling=False
for node in dark_mat.node_tree.nodes:
 # Keep the original AlphaMapTexture untouched; it carries the strand cutout
 # detail.  Replacing it was what made the earlier dark test look like clay.
 if node.type=='TEX_IMAGE' and node.image and node.name=='DiffuseTexture':node.image=dark_image
mesh=source.data.copy();hair=bpy.data.objects.new('Mercenary_ThinShortHair_LOD0_v16j',mesh);coll.objects.link(hair)
for i,m in enumerate(source.data.materials):
 if i>=len(mesh.materials):mesh.materials.append(m)
hair.matrix_world.identity()
S=.9964966407164464;CX=-8.940696716308594e-08;CY=-.06141343340277672;ZMIN=.000809629331342876;YSHIFT=-.00795
mw=source.matrix_world.copy()
for v in mesh.vertices:
 p=mw@v.co
 q=Vector(((p.x-CX)*S,(p.y-CY)*S+YSHIFT,(p.z-ZMIN)*S))
 q.x*=.965;q.y=.010+(q.y-.010)*.965;q.z=1.640+(q.z-1.640)*.965
 if q.y<-.055:q.y+=.0015
 v.co=q
mesh.update()
mesh.materials.clear();mesh.materials.append(dark_mat)
for c in list(source.users_collection):c.objects.unlink(source)
bpy.data.objects.remove(source,do_unlink=True)
hair['game_asset']=True;hair['part_category']='Hair';hair['intentional_layer']=True;hair['source']='CC0 MPFB short02 dark-brown thin fit over preserved v15 head'
for p in mesh.polygons:p.use_smooth=True
for m in mesh.materials:
 if m:
  m.use_backface_culling=False

def nonmanifold(o):
 counts=defaultdict(int)
 for p in o.data.polygons:
  vs=list(p.vertices)
  for a,b in zip(vs,vs[1:]+vs[:1]):counts[tuple(sorted((a,b)))]+=1
 return sum(c!=2 for c in counts.values())

before_nm=nonmanifold(hair)
if before_nm:
 bpy.context.view_layer.objects.active=hair;hair.select_set(True)
 solid=hair.modifiers.new('ClosedHairCards','SOLIDIFY');solid.thickness=.00035;solid.offset=0;solid.use_even_offset=True;solid.use_quality_normals=True
 bpy.ops.object.modifier_apply(modifier=solid.name)
 hair.select_set(False)

# The appended MPFB mesh carries anonymous deform-layer data even though the
# copied object has no visible vertex groups.  Clear it before adding the one
# intended rigid head binding; otherwise the sums are roughly 2.0 and the hair
# can double-transform during export.
bm=bmesh.new();bm.from_mesh(hair.data)
deform=bm.verts.layers.deform.verify()
for v in bm.verts:
 dv=v[deform]
 for key in list(dv.keys()):del dv[key]
bm.to_mesh(hair.data);bm.free();hair.data.update()
for old_group in list(hair.vertex_groups):hair.vertex_groups.remove(old_group)

# Build this before parenting while the fitted hair and head share object-space
# coordinates.  It is later used to neutralize only rear scalp polygons that
# are genuinely hidden beneath the new hair shell.
hair_bvh=BVHTree.FromPolygons([v.co for v in hair.data.vertices],[tuple(p.vertices) for p in hair.data.polygons],all_triangles=False,epsilon=1e-7)

g=hair.vertex_groups.new(name='DEF-spine.006');g.add([v.index for v in hair.data.vertices],1,'REPLACE')
arm=hair.modifiers.new('RigifyDeform','ARMATURE');arm.object=rig;arm.use_deform_preserve_volume=True;hair.parent=rig;hair.matrix_parent_inverse=rig.matrix_world.inverted()

# Under the translucent card gaps, make only actual +Z first-hit crown faces
# use the project's hair texture.  Side/front projection and silhouette remain.
raw_scalp=bpy.data.images.load(str(STAGING/'textures'/'hair_scalp_darkbrown_2k_v11.png'),check_existing=True)
scalp_pixels=np.empty(len(raw_scalp.pixels),dtype=np.float32);raw_scalp.pixels.foreach_get(scalp_pixels)
scalp_rgba=scalp_pixels.reshape((-1,4))
# Lift the earlier almost-black scalp texture into the same neutral mid-brown
# range as the MPFB shell while retaining its fine strand contrast.
scalp_rgba[:,:3]=np.clip(np.power(np.maximum(scalp_rgba[:,:3],0),.74)*np.array((1.08,.88,.72),dtype=np.float32)+np.array((.008,.003,.001),dtype=np.float32),0,1)
img=bpy.data.images.get('hair_scalp_neutralbrown_2k_v16j.png') or bpy.data.images.new('hair_scalp_neutralbrown_2k_v16j.png',width=raw_scalp.size[0],height=raw_scalp.size[1],alpha=True)
img.colorspace_settings.name=raw_scalp.colorspace_settings.name;img.pixels.foreach_set(scalp_rgba.reshape(-1));img.filepath_raw=str(STAGING/'textures'/'hair_scalp_neutralbrown_2k_v16j.png');img.file_format='PNG';img.save()
mat=bpy.data.materials.new('MAT_Hair_ScalpNeutralBrown_2K_v16j');mat.use_nodes=True;mat.use_backface_culling=False
n=mat.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');tx=n.new('ShaderNodeTexImage');tx.image=img;tx.extension='REPEAT';bs.inputs['Roughness'].default_value=.64
mat.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color']);mat.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
head.data.materials.append(mat);mi=len(head.data.materials)-1;uv=head.data.uv_layers.active

# The rear patch uses the shell's own diffuse atlas as an opaque scalp texture.
# A tightly bounded crop from the lower island contains dense multidirectional
# strands and avoids the long parallel lines of the generic crown texture.
back_mat=bpy.data.materials.new('MAT_Hair_BackShellMatched_2K_v16j');back_mat.use_nodes=True;back_mat.use_backface_culling=False
bn=back_mat.node_tree.nodes;bn.clear();bout=bn.new('ShaderNodeOutputMaterial');bbs=bn.new('ShaderNodeBsdfPrincipled');btx=bn.new('ShaderNodeTexImage');btx.image=dark_image;btx.extension='EXTEND';bbs.inputs['Roughness'].default_value=.62
back_mat.node_tree.links.new(btx.outputs['Color'],bbs.inputs['Base Color']);back_mat.node_tree.links.new(bbs.outputs['BSDF'],bout.inputs['Surface'])
head.data.materials.append(back_mat);mi_back=len(head.data.materials)-1
bvh=BVHTree.FromPolygons([v.co for v in head.data.vertices],[tuple(p.vertices) for p in head.data.polygons],all_triangles=False,epsilon=1e-7)
selected=0
for p in head.data.polygons:
 c=p.center
 if p.material_index not in (0,1,7) or c.z<1.655 or p.normal.z<.22 or abs(c.x)>.105:continue
 _l,_n,idx,_d=bvh.ray_cast(Vector((c.x,c.y,2.4)),Vector((0,0,-1)),2)
 if idx!=p.index:continue
 selected+=1;p.material_index=mi
 for li in p.loop_indices:
  co=head.data.vertices[head.data.loops[li].vertex_index].co;x=co.x;y=co.y-.012
  uv.data[li].uv=(.5+4.7*x+1.15*y+3.2*x*y,.5+4.4*y-.55*x+.7*x*x)
head.data.update()

# Replace the whole back-facing upper projection patch with the shell-matched
# neutral hair material.  A shallow U-shaped, slightly irregular lower hairline
# removes the old rectangular edge while keeping the nape and ears untouched.
back_selected=0
for p in head.data.polygons:
 c=p.center
 side=min(1,abs(c.x)/.112)
 hairline=1.586+.035*side**1.65+.0035*math.sin(19*c.x+1.1)
 if p.material_index not in (0,1,7,mi,mi_back) or c.y<.015 or c.z<hairline or abs(c.x)>.112:continue
 origin=Vector((c.x,.7,c.z));direction=Vector((0,-1,0))
 _l,_n,idx,head_d=bvh.ray_cast(origin,direction,1.5)
 if idx!=p.index:continue
 back_selected+=1;p.material_index=mi_back
 for li in p.loop_indices:
  co=head.data.vertices[head.data.loops[li].vertex_index].co
  # Stay inside the dense central portion of the lower atlas island so the
  # patch never samples its flat dark background at the nape or right side.
  uv.data[li].uv=(.41+.62*co.x+.045*(co.z-1.68),.18+1.05*(co.z-1.586)+.06*co.x)
head.data.update()

for name in ('Mercenary_Rigify_Rig_v4','metarig_mercenary_v4'):
 o=bpy.data.objects.get(name)
 if o:o.hide_render=True
def look_at(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
def render(k,loc,target,ortho=None,lens=72,res=(1200,1000)):
 if ortho is None:camera.data.type='PERSP';camera.data.lens=lens
 else:camera.data.type='ORTHO';camera.data.ortho_scale=ortho
 camera.location=loc;look_at(camera,target);scene.render.resolution_x,scene.render.resolution_y=res;scene.render.resolution_percentage=100;scene.render.filepath=str(PREVIEWS/f'diagnostic_v16j_{k}.png');bpy.ops.render.render(write_still=True)
render('top_close',(0,0,5),(0,.02,1.49),.95,res=(1200,900));render('head_three_quarter',(.75,-1.35,1.93),(0,0,1.69),lens=78);render('front',(0,-5.2,.89),(0,0,.89),2.06,res=(1200,1200));render('three_quarter',(2.35,-3.15,1.55),(0,0,1),lens=72,res=(1200,1200));render('back_head',(0,1.55,1.83),(0,.015,1.67),lens=82,res=(1100,1000))
bpy.ops.wm.save_as_mainfile(filepath=str(STAGING/'mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'))
hair_tris=sum(max(1,len(p.vertices)-2) for p in hair.data.polygons)
character_meshes=[o for o in scene.objects if o.type=='MESH' and o.get('part_category') is not None]
total_tris=sum(sum(max(1,len(p.vertices)-2) for p in o.data.polygons) for o in character_meshes)
weight_sums=[sum(g.weight for g in v.groups) for v in hair.data.vertices]
report={'candidate':str(STAGING/'mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'),'source':str(STAGING/'mercenary_crossbowman_game_ready_v15.blend'),'hair_object':hair.name,'hair_triangles':hair_tris,'character_triangles':total_tris,'character_meshes':len(character_meshes),'hair_nonmanifold_before_solidify':before_nm,'hair_nonmanifold_after_solidify':nonmanifold(hair),'hair_weight_sum_range':[min(weight_sums),max(weight_sums)],'rigify_modifier':any(m.type=='ARMATURE' and m.object==rig for m in hair.modifiers),'deform_bones':sum(1 for b in rig.data.bones if b.use_deform),'original_face_object_preserved':bpy.data.objects.get('Mercenary_Male_HeadNeck_LOD0') is head,'top_first_hit_faces_retextured':selected,'back_first_hit_faces_retextured':back_selected,'pose':'T-pose unchanged','texture':str(STAGING/'textures'/'short02_darkbrown_2k_v16j.png'),'scalp_texture':str(STAGING/'textures'/'hair_scalp_neutralbrown_2k_v16j.png')}
(STAGING/'v16j_hair_candidate_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
