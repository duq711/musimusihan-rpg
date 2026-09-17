"""Test a geometry-preserving scalp material/UV repair on v15."""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING = ROOT / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
PREVIEWS = STAGING / 'previews'
bpy.ops.wm.open_mainfile(filepath=str(STAGING / 'mercenary_crossbowman_game_ready_v15.blend'))
scene = bpy.context.scene
camera = scene.camera
head = bpy.data.objects['Mercenary_Male_HeadNeck_LOD0']

img = bpy.data.images.load(str(STAGING / 'textures' / 'hair_scalp_darkbrown_2k_v11.png'), check_existing=True)
mat = bpy.data.materials.new('MAT_Hair_DarkBrown_Radial_2K_v16b')
mat.use_nodes = True
mat.diffuse_color = (0.075, 0.032, 0.012, 1)
mat.roughness = .64
mat.use_backface_culling = False
n = mat.node_tree.nodes
n.clear()
out=n.new('ShaderNodeOutputMaterial'); bs=n.new('ShaderNodeBsdfPrincipled'); tex=n.new('ShaderNodeTexImage')
tex.image=img; tex.extension='REPEAT'; bs.inputs['Roughness'].default_value=.64
mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']); mat.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
head.data.materials.append(mat)
mi=len(head.data.materials)-1
uv=head.data.uv_layers.active or head.data.uv_layers.new(name='UVMap')

def hairline(phi):
    s=math.sin(phi)
    return 1.638 + 0.050*max(0,-s) - 0.026*max(0,s) + 0.008*math.sin(3*phi+.4) + .005*math.sin(7*phi-.8)

chosen=[]
for p in head.data.polygons:
    c=p.center
    phi=math.atan2(c.y-.012,c.x)
    # Ears remain skin.  Only the scalp ellipsoid is recoloured.
    if abs(c.x) <= .108 and c.z >= hairline(phi):
        chosen.append(p)
        p.material_index=mi
        raws=[]
        for li in p.loop_indices:
            co=head.data.vertices[head.data.loops[li].vertex_index].co
            ph=math.atan2(co.y-.012,co.x)
            u=(ph+math.pi)/(2*math.pi)
            radial=math.sqrt((co.x/.091)**2+((co.y-.012)/.105)**2)
            vertical=(co.z-1.64)/.14
            theta=math.atan2(radial,vertical)
            raws.append([li,u,theta/math.pi*1.5])
        us=[r[1] for r in raws]
        if max(us)-min(us)>.5:
            for r in raws:
                if r[1]<.5:r[1]+=1
        for li,u,v in raws:uv.data[li].uv=(u,v)
head.data.update()

for name in ('Mercenary_Rigify_Rig_v4','metarig_mercenary_v4'):
    o=bpy.data.objects.get(name)
    if o:o.hide_render=True

def look_at(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
def render(k,loc,target,ortho=None,lens=72,res=(1200,1000)):
    if ortho is None:camera.data.type='PERSP';camera.data.lens=lens
    else:camera.data.type='ORTHO';camera.data.ortho_scale=ortho
    camera.location=loc;look_at(camera,target);scene.render.resolution_x,scene.render.resolution_y=res
    scene.render.resolution_percentage=100;scene.render.filepath=str(PREVIEWS/f'diagnostic_v16b_{k}.png')
    bpy.ops.render.render(write_still=True)
render('top_close',(0,0,5),(0,.02,1.49),.95,res=(1200,900))
render('head_three_quarter',(.75,-1.35,1.93),(0,0,1.69),lens=78)
render('front',(0,-5.2,.89),(0,0,.89),2.06,res=(1200,1200))
render('three_quarter',(2.35,-3.15,1.55),(0,0,1),lens=72,res=(1200,1200))
bpy.ops.wm.save_as_mainfile(filepath=str(STAGING/'mercenary_crossbowman_game_ready_v16b_scalp_test.blend'))
print('SELECTED',len(chosen))
