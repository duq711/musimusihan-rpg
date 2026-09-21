"""Integrate the user's OBJ/MTL/TGA head and eyes with their original UVs."""
from pathlib import Path
import bpy, json, hashlib, zipfile, struct
from mathutils import Vector

W=Path(__file__).resolve().parent
SOURCE=W.parent/'player_face_repair_20260921/Gravebound_Repaired_Face.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

def signature(o):
    return hashlib.sha256(json.dumps({'vertices':[list(v.co) for v in o.data.vertices],
        'faces':[list(p.vertices) for p in o.data.polygons],
        'uv':[[list(v.uv) for v in l.data] for l in o.data.uv_layers],
        'world':[list(r) for r in o.matrix_world],
        'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()

before={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH'
        and o.name not in ('Gravebound_AnatomicalHead','Gravebound_Eyes')}
vertices=[];uvs=[];normals=[];groups={};group=None
for line in (W/'Untitled.Obj').read_text().splitlines():
    t=line.split()
    if not t:continue
    if t[0]=='v':vertices.append(Vector(tuple(map(float,t[1:4]))))
    elif t[0]=='vt':uvs.append(tuple(map(float,t[1:3])))
    elif t[0]=='vn':normals.append(Vector(tuple(map(float,t[1:4]))))
    elif t[0]=='g':group=t[1];groups[group]=[]
    elif t[0]=='f':groups[group].append([tuple(int(i)-1 for i in part.split('/')) for part in t[1:]])
assert set(groups)=={'Group1','eye'} and len(vertices)==6236
mtl=(W/'Untitled.mtl').read_text()
assert 'map_Kd Untitled_defaultMat_color.tga' in mtl
archive=W/'Untitled_defaultMat_color.tga.zip';tga=W/'Untitled_defaultMat_color.tga'
if not tga.exists():
    with zipfile.ZipFile(archive) as z:tga.write_bytes(z.read('Untitled_defaultMat_color.tga'))
texture=bpy.data.images.load(str(tga),check_existing=False)
texture.name='Gravebound_UserSupplied_OriginalAtlas_2048'
texture.scale(2048,2048);texture.file_format='PNG';texture.pack()

def landmark(px,py):
    """Interpolate the original eye geometry at its photographed iris center."""
    target=Vector((px/1024,1-py/1024))
    best=None
    for face in groups['eye']:
        assert len(face)==3
        a,b,c=[Vector(uvs[q[1]]) for q in face]
        e=b-a;f=c-a;d=target-a;den=e.x*f.y-e.y*f.x
        if abs(den)<1e-12:continue
        wb=(d.x*f.y-d.y*f.x)/den;wc=(e.x*d.y-e.y*d.x)/den;wa=1-wb-wc
        if min(wa,wb,wc)>=-1e-6:
            return sum((vertices[q[0]]*w for q,w in zip(face,(wa,wb,wc))),Vector())
        for q in face:
            distance=(Vector(uvs[q[1]])-target).length_squared
            if best is None or distance<best[0]:best=(distance,vertices[q[0]])
    assert best is not None
    return best[1]

left=landmark(653,892);right=landmark(899,892);center=(left+right)*.5
scale=.0609005/abs(right.x-left.x)
target=Vector((0,.103703,1.616825))
def world(p):
    p=(p-center)*scale
    return target+Vector((-p.x,p.z,p.y))

def material(name,roughness):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=roughness
    bsdf.inputs['Specular IOR Level'].default_value=.30
    image=mat.node_tree.nodes.new('ShaderNodeTexImage');image.image=texture
    mat.node_tree.links.new(image.outputs['Color'],bsdf.inputs['Base Color'])
    return mat

headmat=material('Gravebound_UserSupplied_Head_PBR',.70)
eyemat=material('Gravebound_UserSupplied_Eyes_PBR',.28)
reports={}
for group,name,mat in [('Group1','Gravebound_AnatomicalHead',headmat),('eye','Gravebound_Eyes',eyemat)]:
    obj=bpy.data.objects[name];inv=obj.matrix_world.inverted()
    faces=groups[group];ids=sorted({q[0] for face in faces for q in face});remap={v:i for i,v in enumerate(ids)}
    mesh=bpy.data.meshes.new(name+'_SuppliedOBJ')
    mesh.from_pydata([inv@world(vertices[i]) for i in ids],[],[[remap[q[0]] for q in f] for f in faces]);mesh.update()
    mesh.materials.append(mat);layer=mesh.uv_layers.new(name='UVMap');loopnormals=[]
    for poly,face in zip(mesh.polygons,faces):
        poly.use_smooth=True
        for li,q in zip(poly.loop_indices,face):
            layer.data[li].uv=uvs[q[1]]
            normal=normals[q[2]]
            loopnormals.append(inv.to_3x3()@Vector((-normal.x,normal.z,normal.y)))
    mesh.normals_split_custom_set(loopnormals);obj.data=mesh
    assert all((Vector(layer.data[li].uv)-Vector(uvs[q[1]])).length<1e-7
               for p,face in zip(mesh.polygons,faces) for li,q in zip(p.loop_indices,face))
    obj['source']='User supplied Untitled.Obj, Untitled.mtl, Untitled_defaultMat_color.tga.zip'
    reports[group]={'vertices':len(mesh.vertices),'triangles':len(mesh.polygons),'original_uvs_preserved':True,
        'world_bounds':[[min((obj.matrix_world@v.co)[i] for v in mesh.vertices),max((obj.matrix_world@v.co)[i] for v in mesh.vertices)] for i in range(3)]}

assert before=={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in ('Gravebound_AnatomicalHead','Gravebound_Eyes')}
assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])==27
assert 'Gravebound_PointHood' not in bpy.data.objects
bpy.data.orphans_purge(do_recursive=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Supplied_Face.blend'),compress=True)
tmp=W/'face_export.tmp.glb';out=W/'gravebound_player_supplied_face.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes();assert struct.unpack_from('<I',data,8)[0]==len(data);tmp.replace(out)
report={'input_files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [W/'Untitled.Obj',W/'Untitled.mtl',archive]},
    'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(data).hexdigest(),
    'source_atlas_size':[4096,4096],'runtime_atlas_size':list(texture.size),'uniform_scale':scale,'source_iris_centers':[list(left),list(right)],
    'target_iris_midpoint':list(target),'source_coordinate_mapping':'OBJ Y-up +Z-forward to character +Z-up +Y-forward',
    'groups':reports,'other_25_meshes_unchanged':True,'mesh_count':27,
    'missing_optional_normal_map':'Untitled_defaultMat_nmap.tga was not supplied; use original geometry normals without this texture.',
    'pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2));print('SUPPLIED OBJ FACE BUILD PASS',report['output_sha256'])
