"""Build a separate, player-sized version of the supplied Medival outfit.

Run on this Mac with Blender in background mode. The Downloads originals are
read-only inputs; all generated content stays in this staging directory.
"""

import bpy
import bmesh
import json
import math
import os
import subprocess
from mathutils import Vector


OUT = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(OUT))
PLAYER = os.path.join(ROOT, 'godot-game/assets/3d/player/gravebound_player.glb')
SOURCE = os.path.join(OUT, 'source/Medival.blend')
RAR = os.path.join(OUT, 'source/Textures.rar')
TEX = os.path.join(OUT, 'textures')
os.makedirs(TEX, exist_ok=True)

EXPECTED_TEXTURES = (
    '16_DefaultMaterial_BaseColor.png',
    '16_DefaultMaterial_Normal.png',
    '16_DefaultMaterial_Roughness.png',
    '16_DefaultMaterial_Metallic.png',
    '16_DefaultMaterial_Opacity.png',
    '16_DefaultMaterial_Height.png',
)
for name in EXPECTED_TEXTURES:
    with open(os.path.join(TEX, name), 'wb') as output:
        subprocess.run(['bsdtar', '-xOf', RAR, name], check=True, stdout=output)

bpy.ops.wm.open_mainfile(filepath=SOURCE, load_ui=False)
for image in bpy.data.images:
    name = os.path.basename(image.filepath)
    if name in EXPECTED_TEXTURES:
        image.filepath = os.path.join(TEX, name)
        image.reload()


def interp(value, points):
    if value <= points[0][0]:
        a, b = points[:2]
    elif value >= points[-1][0]:
        a, b = points[-2:]
    else:
        a, b = next((points[i], points[i+1]) for i in range(len(points)-1)
                    if points[i][0] <= value <= points[i+1][0])
    t = (value-a[0])/(b[0]-a[0])
    return a[1] + t*(b[1]-a[1])


SHIRT_Z = [(.80,.77), (.815,.79), (1.10,.99), (1.43,1.375), (1.577,1.565)]
PANTS_Z = [(.306,.145), (.50,.435), (.80,.775), (1.05,.965), (1.105,1.012)]


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value-a)/(b-a)))
    return t*t*(3.0-2.0*t)


def torso_point(p):
    return Vector((p.x*1.075, p.y*1.12+0.007, interp(p.z, SHIRT_Z)))


def arm_point(p):
    side = 1 if p.x >= 0 else -1
    s = Vector((side*.205, -.050, 1.425))
    e = Vector((side*.405, -.038, 1.205))
    w = Vector((side*.555, +.012, 1.065))
    ts = Vector((side*.205, +.005, 1.374))
    te = Vector((side*.278, +.014, 1.158))
    tw = Vector((side*.369, +.075, .900))
    candidates = []
    for a,b,ta,tb in ((s,e,ts,te),(e,w,te,tw)):
        delta = b-a
        t = max(0.0,min(1.0,(p-a).dot(delta)/delta.length_squared))
        center = a.lerp(b,t)
        distance = (p-center).length_squared
        rotation = delta.rotation_difference(tb-ta)
        target = ta.lerp(tb,t) + rotation @ (p-center)
        candidates.append((distance,target))
    posed = min(candidates,key=lambda c:c[0])[1]
    # Keep the shoulder shell joined to the main shirt while the outer sleeve
    # follows the lowered arm.  The x threshold excludes the tunic's hem.
    weight = smooth(.185,.305,abs(p.x))
    return torso_point(p).lerp(posed,weight)


original = {name:bpy.data.objects[name] for name in ('shirt','Pants','bend','boots_left','Boots_right')}
names = {'shirt':'Medival_ShirtUpper','Pants':'Medival_Pants','bend':'Medival_Belt',
         'boots_left':'Medival_Shoe_L','Boots_right':'Medival_Shoe_R'}
for old,obj in original.items():
    transform = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        p = transform @ vertex.co
        if old == 'shirt':
            mapped = arm_point(p)
        elif old == 'Pants':
            mapped = Vector((p.x*1.025, p.y*1.05, interp(p.z,PANTS_Z)))
        elif old == 'bend':
            mapped = Vector((p.x*1.08,p.y*1.08,p.z-.108))
        else:
            mapped = p
        vertex.co = mapped
    obj.matrix_world.identity()
    obj.name = names[old]
    obj.data.name = names[old]+'Mesh'


upper = bpy.data.objects['Medival_ShirtUpper']


def clip(obj, z, keep_lower):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bisect_plane(
        bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        plane_co=(0,0,z), plane_no=(0,0,1), dist=.00005,
        clear_inner=not keep_lower, clear_outer=keep_lower)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# The original tunic has separate front and rear fabric pieces.  Preserve
# their UVs, shape and material, then reduce each to a SoftBody3D-sized panel.
hem_source=upper.copy()
hem_source.data=upper.data.copy()
bpy.context.collection.objects.link(hem_source)
hem_source.name='HemSourceTemporary'
clip(hem_source,1.020,True)

bm=bmesh.new()
bm.from_mesh(hem_source.data)
bm.verts.ensure_lookup_table()
bm.verts.index_update()
unvisited=set(bm.verts)
islands=[]
while unvisited:
    seed=unvisited.pop()
    island={seed}
    queue=[seed]
    while queue:
        v=queue.pop()
        for edge in v.link_edges:
            other=edge.other_vert(v)
            if other in unvisited:
                unvisited.remove(other)
                island.add(other)
                queue.append(other)
    if len(island)>1000:
        islands.append({'indices':{v.index for v in island},
                        'mean_y':sum(v.co.y for v in island)/len(island),
                        'size':len(island)})
bm.free()
islands.sort(key=lambda i:-i['size'])
if len(islands)<2:
    raise RuntimeError('Expected separate front and rear tunic hem pieces')
panels={}
hem_material=upper.data.materials[0].copy()
hem_material.name='Medival_OriginalHemFabric'
hem_material.use_backface_culling=False
for island in islands[:2]:
    label='Front' if island['mean_y']>0 else 'Back'
    mesh=hem_source.data.copy()
    piece=bmesh.new()
    piece.from_mesh(mesh)
    piece.verts.ensure_lookup_table()
    piece.verts.index_update()
    bmesh.ops.delete(piece,geom=[v for v in piece.verts
                                 if v.index not in island['indices']],context='VERTS')
    piece.to_mesh(mesh)
    piece.free()
    mesh.materials.clear()
    mesh.materials.append(hem_material)
    mesh.name='Medival_Hem'+label+'SoftMesh'
    obj=bpy.data.objects.new('Medival_Hem'+label+'Soft',mesh)
    bpy.context.collection.objects.link(obj)
    panels[label]=obj
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    for iteration in range(5):
        triangles=sum(len(poly.vertices)-2 for poly in obj.data.polygons)
        if triangles<=620:
            break
        mod=obj.modifiers.new('SoftClothTriangleBudget','DECIMATE')
        mod.decimate_type='COLLAPSE'
        mod.ratio=max(.025,min(.8,500/triangles))
        bpy.ops.object.modifier_apply(modifier=mod.name)
    triangles=sum(len(poly.vertices)-2 for poly in obj.data.polygons)
    if triangles>650:
        raise RuntimeError(f'{obj.name} exceeds soft cloth budget: {triangles}')

bpy.data.objects.remove(hem_source,do_unlink=True)

# The source alpha texture has a broad transparent patch on the shoulder.
# Keep the original fabric maps, but render the stationary upper garment as
# solid cloth; only the frayed moving hem panels retain source opacity.
upper_material=upper.data.materials[0].copy()
upper_material.name='Medival_SolidUpperFabric'
upper_material.blend_method='OPAQUE'
upper_material.use_backface_culling=False
if upper_material.use_nodes:
    for node in upper_material.node_tree.nodes:
        if node.type=='BSDF_PRINCIPLED':
            alpha=node.inputs.get('Alpha')
            if alpha:
                for link in list(alpha.links):
                    upper_material.node_tree.links.remove(link)
                alpha.default_value=1.0
upper.data.materials[0]=upper_material

bm=bmesh.new()
bm.from_mesh(upper.data)
removed=[f for f in bm.faces if f.calc_center_median().z<1.018 and
         abs(f.calc_center_median().x)<.255]
bmesh.ops.delete(bm,geom=removed,context='FACES')
bm.to_mesh(upper.data)
bm.free()
upper.data.update()

soft_hem_report=[]
for label,obj in panels.items():
    verts=obj.data.vertices
    max_z=max(v.co.z for v in verts)
    pin_vertices=[v.index for v in verts if max_z-v.co.z<.003]
    if len(pin_vertices)<4:
        raise RuntimeError(f'{obj.name} has too few waist anchors')
    soft_hem_report.append({
        'name':obj.name,'anchor_blender_z':max_z,'anchor_godot_y':max_z,
        'anchor_select_epsilon':.003,
        'pin_vertex_count_blender':len(pin_vertices),
        'pin_vertex_indices_blender':pin_vertices,
        'triangles':sum(len(poly.vertices)-2 for poly in obj.data.polygons),
        'note':'Find imported glTF surface points at local Y within epsilon of anchor_godot_y; glTF UV splits can renumber vertices.'
    })

output_objects=[upper,panels['Front'],panels['Back'],bpy.data.objects['Medival_Pants'],
                bpy.data.objects['Medival_Belt']]
bpy.data.objects['Medival_Shoe_L'].hide_render=True
bpy.data.objects['Medival_Shoe_R'].hide_render=True

for obj in bpy.data.objects:
    obj.select_set(False)
for obj in output_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active=upper

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'Medival_Retargeted.blend'))
bpy.ops.export_scene.gltf(
    filepath=os.path.join(OUT,'Medival_Retargeted.glb'),
    export_format='GLB', use_selection=True, export_yup=True,
    export_texcoords=True, export_normals=True, export_materials='EXPORT')


def bounds(obj):
    pts=[obj.matrix_world@Vector(c) for c in obj.bound_box]
    return [[round(min(v[i] for v in pts),5) for i in range(3)],
            [round(max(v[i] for v in pts),5) for i in range(3)]]


report={
    'source':os.path.basename(SOURCE),
    'objects':[{'name':o.name,'vertices':len(o.data.vertices),
                'faces':len(o.data.polygons),'bounds_blender_xyz':bounds(o)}
               for o in output_objects],
    'soft_hems':soft_hem_report,
    'included_textures':list(EXPECTED_TEXTURES),
    'retained_player_parts':['head','eyes','hands','tall boots','boot cuffs'],
    'supplied_low_shoes':'Preserved in source .blend; omitted from runtime outfit to keep the existing tall boots and avoid exposed shins.',
}
with open(os.path.join(OUT,'structure_report.json'),'w') as f:
    json.dump(report,f,indent=2)

# The reference player is preview-only.  Its old outfit is hidden so that the
# preview reflects which game meshes must be replaced at integration time.
before=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=PLAYER)
new_objects=[o for o in bpy.data.objects if o not in before]
keep_player=('Gravebound_AnatomicalHead','Gravebound_Eyes','FP_L_Hand','FP_R_Hand','Gravebound_Boot')
for obj in new_objects:
    if obj.type == 'MESH' and not any(key in obj.name for key in keep_player):
        obj.hide_render=True

scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=960
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.world.color=(.23,.23,.23)
scene.view_settings.view_transform='AgX'

bpy.ops.object.camera_add(location=(0,4,1))
cam=bpy.context.object
scene.camera=cam
cam.data.type='ORTHO'
cam.data.ortho_scale=1.92
for pos,power in [((-2,3,4),900),((2,-2,3),600)]:
    bpy.ops.object.light_add(type='AREA',location=pos)
    light=bpy.context.object
    light.data.energy=power
    light.data.shape='DISK'
    light.data.size=3.5
    light.rotation_euler=(Vector((0,0,.9))-light.location).to_track_quat('-Z','Y').to_euler()

for label,position in [('front',(0,4,1)),('side',(4,0,1)),
                       ('oblique',(3,3,1)),('back',(0,-4,1)),
                       ('rear_oblique',(3,-3,1))]:
    cam.location=position
    cam.rotation_euler=(Vector((0,0,.85))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=os.path.join(OUT,'preview_'+label+'.png')
    bpy.ops.render.render(write_still=True)
    print('RENDERED',scene.render.filepath)

print('STAGED_REPORT',json.dumps({k:v for k,v in report.items() if k!='soft_hems'}))
print('SOFT_HEMS',json.dumps([{k:v for k,v in item.items() if k!='pin_vertex_indices_blender'} for item in soft_hem_report]))
