"""Fit the locally licensed Roger character inside the original Medival outfit.

Mac Blender: --background --disable-autoexec --python <this file>
The downloaded rig/source remains untouched. Output is a static fitted preview,
not a new animation rig or a cloth simulation. Never redistribute its binaries.
"""
from pathlib import Path
import bpy, bmesh, math, json, os, struct
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent
SOURCE = OUT / 'source/Roger Blender.blend'
DEST = ROOT / 'godot-game/assets/licensed/roger/roger_medival.glb'
DEST.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
scene = bpy.context.scene
rig = bpy.data.objects['Roger']
# Preserve the source's frame-one evaluated T pose before removing animation.
scene.frame_set(1)
rig.animation_data_clear()
bpy.context.view_layer.update()

def world_pose(name, rotation, scale=1, offset=(0,0,0)):
    bone = rig.pose.bones['CC_Base_' + name]
    original = rig.matrix_world @ bone.matrix
    pivot = original.translation.copy()
    transform = Matrix.Translation(pivot + Vector(offset)) @ rotation @ Matrix.Scale(scale, 4) @ Matrix.Translation(-pivot)
    bone.matrix = rig.matrix_world.inverted() @ transform @ original
    bpy.context.view_layer.update()

for side, sign in [('L',1), ('R',-1)]:
    rotation = Matrix.Rotation(math.radians(-8 * sign),4,'Z') @ Matrix.Rotation(math.radians(50 * sign),4,'Y')
    world_pose(side+'_Upperarm', rotation, 1.08, (0, -.030, -.016))
    # Spread the legs to meet the source outfit's separated shoe/ankle centers.
    world_pose(side+'_Thigh', Matrix.Rotation(math.radians(-8.5 * sign),4,'Y'))
    world_pose(side+'_Foot', Matrix.Rotation(math.radians(8.5 * sign),4,'Y'))

# External support maps are also supplied in the downloaded ZIPs. Diffuse,
# normal and hair opacity maps are already packed in the original .blend.
files = {}
for path in (OUT/'source').rglob('*'):
    if path.is_file(): files.setdefault(path.name.lower(), []).append(path)
for image in bpy.data.images:
    if image.packed_file: continue
    name = image.filepath.replace('\\','/').rsplit('/',1)[-1].lower()
    if name in files:
        image.filepath = str(files[name][0])
        try: image.reload()
        except RuntimeError: pass

materials = {}
def pbr_material(source):
    if source.name in materials: return materials[source.name]
    maps = {}
    if source.use_nodes:
        for n in source.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.image:
                for role in ('DIFFUSE','NORMAL','ALPHA','ROUGHNESS'):
                    if '('+role+')' in n.name: maps[role] = n.image
    mat = bpy.data.materials.new('Roger_' + source.name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    tree = mat.node_tree
    p = tree.nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value = .58
    p.inputs['IOR'].default_value = 1.45
    for role in ('DIFFUSE','NORMAL','ROUGHNESS','ALPHA'):
        image = maps.get(role)
        if image is None: continue
        n = tree.nodes.new('ShaderNodeTexImage'); n.image = image
        if role=='DIFFUSE':
            image.colorspace_settings.name='sRGB'
            tree.links.new(n.outputs['Color'], p.inputs['Base Color'])
        else:
            image.colorspace_settings.name='Non-Color'
            if role=='NORMAL':
                normal = tree.nodes.new('ShaderNodeNormalMap')
                normal.inputs['Strength'].default_value = .45
                tree.links.new(n.outputs['Color'], normal.inputs['Color'])
                tree.links.new(normal.outputs['Normal'], p.inputs['Normal'])
            elif role=='ROUGHNESS': tree.links.new(n.outputs['Color'],p.inputs['Roughness'])
            elif role=='ALPHA':
                tree.links.new(n.outputs['Color'],p.inputs['Alpha'])
                mat.surface_render_method='DITHERED'
                mat.blend_method='CLIP'
                mat.alpha_threshold=.35
    if 'Eye' in source.name or 'Cornea' in source.name:
        p.inputs['Roughness'].default_value=.25
    if not maps.get('ALPHA'): mat.blend_method='OPAQUE'
    materials[source.name]=mat
    return mat

bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
result = []
conversion = Matrix.Rotation(math.pi,4,'Z')
# CC3 eye occlusion uses a procedural shader rather than a portable surface;
# the real textured eyeballs and eyelids supply the socket boundary instead.
exclude = {'Boxers','CC_Base_EyeOcclusion','CC_Base_TearLine'}
for obj in list(bpy.data.objects):
    if obj.type!='MESH' or obj.parent!=rig or obj.name in exclude: continue
    evaluated = obj.evaluated_get(dg)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=dg)
    mesh.transform(conversion @ evaluated.matrix_world)
    name = 'Roger_' + obj.name.replace('CC_Base_','')
    new = bpy.data.objects.new(name,mesh)
    for slot in range(len(mesh.materials)):
        mesh.materials[slot] = pbr_material(mesh.materials[slot])
    scene.collection.objects.link(new)
    result.append(new)
# Keep the fitted complete source body in this first inspection. The final
# garment-occluded mask is a derivative, never applied to the source .blend.
for obj in list(bpy.data.objects):
    if obj not in result: bpy.data.objects.remove(obj,do_unlink=True)

clothing = ROOT/'asset-staging/medival_clean_20260924/Medival_Clean.blend'
with bpy.data.libraries.load(str(clothing),link=False) as (src,dst):
    dst.objects=[name for name in src.objects if name.startswith('Medival_')]
for obj in dst.objects:
    if obj and obj.type=='MESH':
        scene.collection.objects.link(obj); result.append(obj)

# Local fit corrections keep exposed neck/calves centered in source openings.
for obj in result:
    if not obj.name.startswith('Roger_'): continue
    for v in obj.data.vertices:
        if v.co.z>1.40:
            v.co.y += .04 * min(1, max(0, (v.co.z-1.40)/.10))
            if obj.name=='Roger_Body' and v.co.z<1.595:
                t=min(1,max(0,(1.595-v.co.z)/.025))
                radius=math.sqrt((v.co.x/.060)**2+((v.co.y+.038)/.050)**2)
                if radius>1:
                    v.co.x=(1-t)*v.co.x+t*v.co.x/radius
                    v.co.y=(1-t)*v.co.y+t*(-.038+(v.co.y+.038)/radius)
        elif v.co.z<.50:
            v.co.y += .035
            if v.co.z<.18:
                sign=1 if v.co.x>0 else -1
                t=min(1,max(0,(.18-v.co.z)/.045))
                v.co.x=(1-t)*v.co.x+t*(sign*.202+(v.co.x-sign*.223)*.68)
                v.co.y=(1-t)*v.co.y+t*(-.042+(v.co.y+.042)*.68)
    obj.data.update()

# Remove only covered body faces after checking the original fitted rig.
# Preserve an overlap underneath collars/cuffs and trouser/shoe openings.
if os.environ.get('ROGER_FULL_BODY','0')!='1':
    obj=bpy.data.objects['Roger_Body']
    bm=bmesh.new(); bm.from_mesh(obj.data)
    remove=[]
    for f in bm.faces:
        c=f.calc_center_median(); x=abs(c.x)
        head_neck=c.z>1.60 or (c.z>1.515 and x<.069) or (c.z>1.425 and x<.048 and c.y>0)
        hand=c.z>.80 and x>.51 and (x-.192)*.643 + (1.490-c.z)*.766 >.535
        ankle=.10<c.z<.43
        if not (head_neck or hand or ankle): remove.append(f)
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bm.to_mesh(obj.data); bm.free(); obj.data.update()

# Fit the hidden calf overlap to the actual trouser surface. A horizontal
# ray from inside each cuff preserves the natural leg wherever cloth is open,
# while preventing the wider upper calf from crossing the original garment.
pants=bpy.data.objects['Medival_Pants']
bm=bmesh.new();bm.from_mesh(pants.data)
bm.transform(pants.matrix_world)
cuff_tree=BVHTree.FromBMesh(bm);bm.free()
body=bpy.data.objects['Roger_Body']
# Smaller hidden triangles follow the cuff's irregular contour without a long
# coarse triangle bridging through folds. UVs interpolate with the new edges.
bm=bmesh.new();bm.from_mesh(body.data)
edges=[e for e in bm.edges if all(.28<v.co.z<.50 for v in e.verts)]
bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True)
bm.to_mesh(body.data);bm.free();body.data.update()
for v in body.data.vertices:
    if not .30<v.co.z<.50: continue
    sign=1 if v.co.x>0 else -1
    center=Vector((sign*.174,-.052,v.co.z))
    delta=v.co-center
    distance=delta.length
    if distance<.0001: continue
    hit,normal,index,ray_distance=cuff_tree.ray_cast(center,delta.normalized(),.15)
    if hit is not None and ray_distance<distance+.008:
        v.co=center+delta.normalized()*max(.01,ray_distance-.008)
body.data.update()

# Named visible anatomical regions provide accurate head/hand viewer focus.
body=bpy.data.objects['Roger_Body']
def region(c):
    if c.z>1.4 and abs(c.x)<.15: return 'Head_Neck'
    if c.z>.8: return 'Hand_L' if c.x<0 else 'Hand_R'
    return 'Calf_L' if c.x<0 else 'Calf_R'
for part in ('Head_Neck','Hand_L','Hand_R','Calf_L','Calf_R'):
    mesh=body.data.copy(); bm=bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if region(f.calc_center_median())!=part],context='FACES')
    bm.to_mesh(mesh); bm.free(); mesh.update()
    obj=bpy.data.objects.new('Roger_'+part,mesh)
    scene.collection.objects.link(obj); result.append(obj)
result.remove(body); bpy.data.objects.remove(body,do_unlink=True)
bpy.data.objects['Roger_Short_blowback'].name='Roger_Hair'

bpy.ops.object.select_all(action='DESELECT')
for obj in result: obj.select_set(True)
bpy.context.view_layer.objects.active=result[0]
bpy.context.view_layer.update()
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Roger_Medival.blend'))
if os.environ.get('ROGER_SKIP_EXPORT','0')!='1':
    temporary_glb=DEST.with_name('roger_medival.building.glb')
    bpy.ops.export_scene.gltf(filepath=str(temporary_glb),export_format='GLB',use_selection=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_animations=False)
    # Blender 5.2's retired blend_method does not export CLIP consistently.
    # Use depth-writing alpha masks for hair/scalp instead of sorted blending.
    # Beard/lash cards retain smooth transparency; they do not enclose the scalp.
    raw=temporary_glb.read_bytes()
    length=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+length])
    for material in document.get('materials',[]):
        if material.get('name') in ('Roger_Hair','Roger_Scalp') and material.get('alphaMode')=='BLEND':
            material['alphaMode']='MASK'; material['alphaCutoff']=.30
    payload=json.dumps(document,separators=(',',':')).encode()
    payload+=b' '*((-len(payload))%4)
    remainder=raw[20+length:]
    temporary_glb.write_bytes(struct.pack('<III',0x46546c67,2,20+len(payload)+len(remainder))+struct.pack('<II',len(payload),0x4e4f534a)+payload+remainder)
    os.replace(temporary_glb, DEST)

report={'source':'TurboSquid Roger 1861645, Mr Browen','static_pose':True,'cloth_simulation':False,'meshes':[]}
for obj in result:
    points=[obj.matrix_world@v.co for v in obj.data.vertices]
    report['meshes'].append({'name':obj.name,'vertices':len(points),'faces':len(obj.data.polygons),'bounds':[[round(min(p[i] for p in points),5)for i in range(3)],[round(max(p[i] for p in points),5)for i in range(3)]]})
(OUT/'fit_report.json').write_text(json.dumps(report,indent=2))
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=840;scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.render.use_compositing=False
scene.view_settings.exposure=-.35
world=bpy.data.worlds.new('PreviewWorld');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.065,.075,.072,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.6
scene.view_settings.view_transform='AgX'
bpy.ops.object.camera_add(location=(0,4,.95));cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.08
for loc,power,size in (((-2,3,4),700,4),((2,2,2),350,3),((0,-3,3),600,3)):
    bpy.ops.object.light_add(type='AREA',location=loc)
    light=bpy.context.object;light.data.energy=power;light.data.size=size
    light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
views=[('front',(0,4,.97)),('side',(4,0,.97)),('back',(0,-4,.97)),('three_quarter',(3,4,1.3))]
if os.environ.get('ROGER_QUICK','0')=='1':views=views[:1]
for name,loc in views:
    cam.location=loc;cam.rotation_euler=(Vector((0,0,.95))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/('preview_'+name+'.png'))
    bpy.ops.render.render(write_still=True)
cam.data.ortho_scale=.46
cam.location=(.22,3,1.7)
cam.rotation_euler=(Vector((0,0,1.65))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(OUT/'preview_head.png')
bpy.ops.render.render(write_still=True)
print('ROGER_FIT_READY',DEST)
