"""Deterministic Mac Blender authoring; supplied SBSAR textures, closed meshes.
Run: Blender --background --factory-startup --python build_jerky.py
"""
import bpy, bmesh, math, random, json, hashlib, shutil
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.noise import noise_vector

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
EXPORT = PROJECT / 'exports/Beef_Jerky_2026-09-16'
GAME = PROJECT / 'godot-game/assets/3d/items/beef_jerky'
for folder in [EXPORT, EXPORT/'textures', EXPORT/'individual', GAME]:
    folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.threads_mode = 'FIXED'
scene.render.threads = 6
scene.render.resolution_x = 1600
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.world.color = (.14,.14,.14)
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'

textures = {}
for channel in ['basecolor','normal','roughness','metallic','height']:
    dest = EXPORT/'textures'/f'jerky_{channel}.png'
    shutil.copy2(ROOT/'output/textures'/f'BeefJerky_Beef_Jerky_{channel}.png', dest)
    img = bpy.data.images.load(str(dest),check_existing=True)
    if channel!='basecolor': img.colorspace_settings.name='Non-Color'
    textures[channel]=img
height_img=textures['height']
hbuf=np.empty(len(height_img.pixels),dtype=np.float32)
height_img.pixels.foreach_get(hbuf)
hbuf=hbuf.reshape((height_img.size[1],height_img.size[0],4))[:,:,0]

def sample_height(u,v):
    return float(hbuf[int((v%1)*(hbuf.shape[0]-1)),int((u%1)*(hbuf.shape[1]-1))])

mat=bpy.data.materials.new('Beef jerky • supplied SBSAR / OpenGL PBR')
mat.use_nodes=True
n=mat.node_tree.nodes;l=mat.node_tree.links
bs=n.get('Principled BSDF')
for i,channel in enumerate(['basecolor','normal','roughness','metallic']):
    tex=n.new('ShaderNodeTexImage');tex.image=textures[channel];tex.label=channel;tex.location=(-550,350-i*230)
    if channel=='normal':
        norm=n.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.4;norm.location=(-250,80)
        l.new(tex.outputs['Color'],norm.inputs['Color']);l.new(norm.outputs['Normal'],bs.inputs['Normal'])
    else: l.new(tex.outputs['Color'],bs.inputs[{'basecolor':'Base Color','roughness':'Roughness','metallic':'Metallic'}[channel]])
bs.inputs['IOR'].default_value=1.45

# Length / maximum width / thickness, asymmetric width profiles and curl.
specs=[
 dict(name='01_long_torn_strip',length=.174,width=.036,thick=.0034,profile=[.35,.7,.87,.66,1,.88,.67,.7,.23],twist=.25,curl=.007),
 dict(name='02_broad_ragged_slab',length=.132,width=.073,thick=.0047,profile=[.44,.86,.76,1,.94,.66,.85,.41,.25],twist=-.18,curl=.012),
 dict(name='03_forked_end',length=.150,width=.047,thick=.0031,profile=[.60,.54,.92,.95,.78,.94,.70,.42,.64],twist=.48,curl=.011),
 dict(name='04_curled_ribbon',length=.159,width=.030,thick=.0030,profile=[.4,.65,.78,1,.8,.98,.6,.51,.32],twist=1.1,curl=.024),
 dict(name='05_short_torn_chunk',length=.083,width=.052,thick=.0052,profile=[.48,.8,1,.95,.73,.80,.92,.70,.43],twist=.3,curl=.006),
 dict(name='06_wide_split_sheet',length=.141,width=.058,thick=.0037,profile=[.24,.69,.84,1,.8,.75,.80,.52,.40],twist=-.6,curl=.018),
 dict(name='07_thin_taper',length=.130,width=.024,thick=.0028,profile=[.14,.40,.71,1,.81,.60,.79,.41,.10],twist=.6,curl=.013),
 dict(name='08_broken_corner',length=.067,width=.043,thick=.0046,profile=[.7,.75,1,.81,.77,.65,.56,.49,.25],twist=-.3,curl=.008),
]

def noise(p): return noise_vector(Vector(p),noise_basis='PERLIN_ORIGINAL').x
def interp(values,t):
    p=min(len(values)-1.000001,max(0,t)*(len(values)-1));i=int(p);f=p-i
    return values[i]*(1-f)+values[i+1]*f

def make_piece(spec,index):
    rng=random.Random(10916+index*127)
    nx,ny=64,20
    L,W,T=spec['length'],spec['width'],spec['thick']
    seed=rng.random()*100
    u0,v0=rng.random()*.3,rng.random()*.3
    us,vs=.48+L*1.8,.32+W*4.1
    verts=[];uvs=[];faces=[]
    endleft=[rng.uniform(-.025,.03) for i in range(7)]
    endright=[rng.uniform(-.035,.045) for i in range(7)]
    if index in [2,5]:
        for j in range(7):
            endright[j]-=.12*math.exp(-((j/6-.58)/.18)**2)
    def surface(t,s,side):
        j=round((s+1)*ny/2)
        end0=interp(endleft,(s+1)/2)
        end1=interp(endright,(s+1)/2)
        x=L*(t-.5 + end0*(1-t)**5 + end1*t**5)
        p=interp(spec['profile'],t)
        edge=1+.035*noise((t*38,5,seed))+.009*math.sin(t*169+seed)
        # Deep narrow tears on only one side; asymmetry avoids cookie-cutter silhouettes.
        sidefactor=1+.14*math.sin(t*13+seed+(0 if s<0 else 2.1))
        if s>0: sidefactor-=.18*math.exp(-((t-(.32+.04*(index%4)))/.035)**2)
        y=s*W*.5*p*sidefactor*edge + W*.11*math.sin(t*4.3+seed)
        u=u0+t*us+(0.14 if side<0 else 0)
        v=v0+(s+1)*.5*vs+(0.3 if side<0 else 0)
        h=sample_height(u,v)-.5
        # Broad bow/twist, upturned dry edges, and longitudinal muscle ridges.
        angle=spec['twist']*(t-.35)
        arch=spec['curl']*((t-.4)**2*2.4-.12)
        edgecurl=spec['curl']*.28*(s**4)*(.55+.45*math.sin(t*6+seed))
        ridge=.0002*math.sin(s*38+2*math.sin(t*9+seed))+.00015*noise((t*15,s*6,seed))
        thickness=T*(.55+.45*(1-s*s))*(.75+.25*math.sin(t*4+1))
        z=arch+y*math.sin(angle)+edgecurl+ridge+side*(thickness*.5+h*.0015)
        return (x,y*math.cos(angle),z),(u,v)
    for side in [1,-1]:
        for i in range(nx+1):
            for j in range(ny+1):
                p,uv=surface(i/nx,j/ny*2-1,side);verts.append(p);uvs.append(uv)
    count=(nx+1)*(ny+1)
    def idx(i,j):return i*(ny+1)+j
    for i in range(nx):
        for j in range(ny):
            a,b,c,d=idx(i,j),idx(i+1,j),idx(i+1,j+1),idx(i,j+1)
            faces.append((a,b,c,d));faces.append((d+count,c+count,b+count,a+count))
    # Closed, nonzero-thickness torn perimeter with the same supplied texture.
    perimeter=[idx(i,0) for i in range(nx+1)]+[idx(nx,j) for j in range(1,ny+1)]+[idx(i,ny) for i in range(nx-1,-1,-1)]+[idx(0,j) for j in range(ny-1,0,-1)]
    for k,a in enumerate(perimeter):
        b=perimeter[(k+1)%len(perimeter)]
        faces.append((b,a,a+count,b+count))
    mesh=bpy.data.meshes.new(spec['name'])
    mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name='Jerky grain')
    for loop in mesh.loops:uv.data[loop.index].uv=uvs[loop.vertex_index]
    obj=bpy.data.objects.new('Jerky_'+spec['name'],mesh);scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for p in mesh.polygons:p.use_smooth=True
    # Finite volume and authored UVs remain in GLB; source height is baked into mesh.
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    assert all(e.is_manifold for e in bm.edges),spec['name']
    volume=bm.calc_volume(signed=False);assert volume>0,spec['name']
    bm.to_mesh(mesh);bm.free()
    minz=min(v.co.z for v in mesh.vertices)
    for v in mesh.vertices:v.co.z-=minz
    obj['source_material']='beef-jerky.sbsar / pkg://Beef_Jerky'
    obj['variant_seed']=10916+index*127
    obj['closed_volume_m3']=volume
    return obj

pieces=[make_piece(s,i) for i,s in enumerate(specs)]

def export_glb(objects,path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_yup=True)

metrics=[]
for obj,spec in zip(pieces,specs):
    export_glb([obj],EXPORT/'individual'/f"{spec['name']}.glb")
    # Game uses the shared variants GLB; individual files are delivery assets.
    obj.data.calc_loop_triangles()
    metrics.append(dict(name=obj.name,vertices=len(obj.data.vertices),triangles=len(obj.data.loop_triangles),dimensions_m=list(obj.dimensions),volume_m3=obj['closed_volume_m3']))

# Physically settle each rotated piece onto the pieces already below it.
# Ray samples under every lower surface vertex avoid an unsupported floating pile.
from mathutils.bvhtree import BVHTree
pile=[]
placements=[(-.025,-.020,18),( .018,.006,-41),(-.012,.017,35),(.001,-.008,-20),(.047,-.001,13),(-.012,.0,75),(-.025,-.017,-12),(.007,-.030,21)]
for i,(source,(px,py,rz)) in enumerate(zip(pieces,placements)):
    obj=source.copy();obj.data=source.data.copy();obj.name=f'Pile_{i+1:02d}';scene.collection.objects.link(obj)
    obj.location=(px,py,0);obj.rotation_euler=(math.radians((i%3-1)*6),math.radians((i%2*2-1)*8),math.radians(rz))
    bpy.context.view_layer.update()
    world=[obj.matrix_world@v.co for v in obj.data.vertices]
    needed=max(-v.z for v in world)
    for prev in pile:
        pv=[prev.matrix_world@v.co for v in prev.data.vertices]
        pf=[list(p.vertices) for p in prev.data.polygons]
        tree=BVHTree.FromPolygons(pv,pf)
        for v in world:
            hit,n,face,dist=tree.ray_cast(Vector((v.x,v.y,.5)),Vector((0,0,-1)),1.0)
            if hit is not None:needed=max(needed,hit.z-v.z+.0002)
    obj.location.z=needed
    bpy.context.view_layer.update();pile.append(obj)
export_glb(pile,EXPORT/'beef_jerky_pile.glb')
shutil.copy2(EXPORT/'beef_jerky_pile.glb',GAME/'beef_jerky_pile.glb')

# Exploded set with real scale and visibly distinct outlines.
for i,obj in enumerate(pieces):
    obj.location=((i%4-1.5)*.184,(i//4-.5)*.106,0)
    obj.rotation_euler=(0,0,math.radians([8,-10,6,-5,-14,8,-6,17][i]))
export_glb(pieces,EXPORT/'beef_jerky_variants.glb')
shutil.copy2(EXPORT/'beef_jerky_variants.glb',GAME/'beef_jerky_variants.glb')

source_hash=hashlib.sha256(Path('/Users/duq711gmail.com/Downloads/beef-jerky.sbsar').read_bytes()).hexdigest()
manifest=dict(source_sbsar='/Users/duq711gmail.com/Downloads/beef-jerky.sbsar',source_sha256=source_hash,texture_resolution=2048,normal_format='OpenGL',units='meters',variants=metrics,pile_triangles=sum(m['triangles'] for m in metrics),blender_version=bpy.app.version_string)
(EXPORT/'asset_manifest.json').write_text(json.dumps(manifest,indent=2))

def aim(obj,point):obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()
def area(name,location,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=location;aim(obj,(0,0,0));return obj
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.0006));floor=bpy.context.object;floor.name='Studio slate (preview only)'
floor_mat=bpy.data.materials.new('Slate backdrop');floor_mat.diffuse_color=(.035,.039,.042,1);floor_mat.use_nodes=True
floor_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.035,.039,.042,1)
floor_mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.92
floor.data.materials.append(floor_mat)
area('Softbox',(-.23,-.23,.46),1.6,.34,(1,.91,.79))
area('Fill',(.3,-.08,.24),.45,.3,(.79,.86,1))
area('Rim',(.08,.32,.3),1.0,.26,(1,.92,.81))
bpy.ops.object.camera_add(location=(.30,-.40,.43));cam=bpy.context.object;cam.name='Asset preview camera';cam.data.type='ORTHO';cam.data.lens=65
scene.camera=cam
for o in pieces:o.hide_render=True
cam.data.ortho_scale=.33;aim(cam,(0,0,.035))
scene.render.filepath=str(EXPORT/'jerky_pile.png')
bpy.ops.render.render(write_still=True)
for o in pile:o.hide_render=True
for o in pieces:o.hide_render=False
cam.location=(0,-.22,.65);cam.data.ortho_scale=.78;aim(cam,(0,0,0))
scene.render.resolution_x=1800;scene.render.resolution_y=1000
scene.render.filepath=str(EXPORT/'jerky_variants.png')
bpy.ops.render.render(write_still=True)
# Authoring file opens to the eight editable variants; pile retained as a collection.
pile_collection=bpy.data.collections.new('Pile arrangement');scene.collection.children.link(pile_collection)
for obj in pile:
    for c in list(obj.users_collection):c.objects.unlink(obj)
    pile_collection.objects.link(obj)
    obj.hide_set(True)
for img in textures.values():img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(EXPORT/'beef_jerky.blend'))
print('JERKY BUILD PASS',json.dumps(manifest),flush=True)
