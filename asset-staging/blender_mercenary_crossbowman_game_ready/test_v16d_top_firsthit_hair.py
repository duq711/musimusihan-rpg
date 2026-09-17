"""Retexture only the v15 crown faces visible from +Z; add no geometry."""
from pathlib import Path
import math
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING=ROOT/'asset-staging'/'blender_mercenary_crossbowman_game_ready'
PREVIEWS=STAGING/'previews'
bpy.ops.wm.open_mainfile(filepath=str(STAGING/'mercenary_crossbowman_game_ready_v15.blend'))
scene=bpy.context.scene; camera=scene.camera
head=bpy.data.objects['Mercenary_Male_HeadNeck_LOD0']

img=bpy.data.images.load(str(STAGING/'textures'/'hair_scalp_darkbrown_2k_v11.png'),check_existing=True)
mat=bpy.data.materials.new('MAT_Hair_Crown_SweptDarkBrown_2K_v16d');mat.use_nodes=True
mat.diffuse_color=(.075,.034,.014,1);mat.roughness=.64;mat.use_backface_culling=False
n=mat.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');bs=n.new('ShaderNodeBsdfPrincipled');tex=n.new('ShaderNodeTexImage')
tex.image=img;tex.extension='REPEAT';tex.interpolation='Linear';bs.inputs['Roughness'].default_value=.64
if 'Anisotropic IOR Level' in bs.inputs:bs.inputs['Anisotropic IOR Level'].default_value=.26
mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);mat.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
head.data.materials.append(mat);mi=len(head.data.materials)-1
uv=head.data.uv_layers.active or head.data.uv_layers.new(name='UVMap')
bvh=BVHTree.FromPolygons([v.co for v in head.data.vertices],[tuple(p.vertices) for p in head.data.polygons],all_triangles=False,epsilon=1e-7)
selected=[]
for p in head.data.polygons:
    c=p.center
    if p.material_index not in (0,1,7) or c.z<1.645 or p.normal.z<.12 or abs(c.x)>.112:continue
    _loc,_normal,idx,_dist=bvh.ray_cast(Vector((c.x,c.y,2.4)),Vector((0,0,-1)),2.0)
    if idx!=p.index:continue
    selected.append(p);p.material_index=mi
    # Swept, slightly curved flow from left/back toward right/front.  This
    # avoids the radial starburst and the planar front/back rectangle.
    for li in p.loop_indices:
        co=head.data.vertices[head.data.loops[li].vertex_index].co
        x=co.x;y=co.y-.012
        u=.5+4.7*x+1.15*y+3.2*x*y
        v=.5+4.4*y-.55*x+.7*x*x
        uv.data[li].uv=(u,v)
head.data.update()
for name in ('Mercenary_Rigify_Rig_v4','metarig_mercenary_v4'):
 o=bpy.data.objects.get(name)
 if o:o.hide_render=True
def look_at(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
def render(k,loc,target,ortho=None,lens=72,res=(1200,1000)):
 if ortho is None:camera.data.type='PERSP';camera.data.lens=lens
 else:camera.data.type='ORTHO';camera.data.ortho_scale=ortho
 camera.location=loc;look_at(camera,target);scene.render.resolution_x,scene.render.resolution_y=res;scene.render.resolution_percentage=100
 scene.render.filepath=str(PREVIEWS/f'diagnostic_v16d_{k}.png');bpy.ops.render.render(write_still=True)
render('top_close',(0,0,5),(0,.02,1.49),.95,res=(1200,900))
render('head_three_quarter',(.75,-1.35,1.93),(0,0,1.69),lens=78)
render('front',(0,-5.2,.89),(0,0,.89),2.06,res=(1200,1200))
render('three_quarter',(2.35,-3.15,1.55),(0,0,1),lens=72,res=(1200,1200))
bpy.ops.wm.save_as_mainfile(filepath=str(STAGING/'mercenary_crossbowman_game_ready_v16d_top_hair_test.blend'))
print('SELECTED',len(selected),'BY_OLD_MAT', {i:sum(1 for p in selected if False) for i in ()})
