"""Localized neck/shoulder flow on the sturdy model; preserve lower arm anatomy."""
from pathlib import Path
import sys, bpy, math, json, hashlib, struct, shutil
from mathutils import Vector, Matrix
HERE=Path(__file__).resolve().parent; ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
from neck_shape import deform_neck
from blend_sleeve_material import bake_sleeve_material
SOURCE=HERE.parent/'player_sturdy_neck_shoulders_20260922/Gravebound_Sturdy_Neck_Shoulders.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
HEAD='Gravebound_AnatomicalHead'
GARMENT=['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
TARGETS=[HEAD]+GARMENT
def smooth(t):
    t=max(0.,min(1.,t));return t*t*(3.-2.*t)
def signature(o):
    return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(f.vertices) for f in o.data.polygons],'uv':[[list(u.uv) for u in l.data] for l in o.data.uv_layers],'normals':[list(n.vector) for n in o.data.corner_normals],'world':[list(r) for r in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
preserved={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in TARGETS}

def deform_garment(p):
    x,y,z=abs(p.x),p.y-.002,p.z
    if z<=1.275 or x<=.125:return p.copy()
    height=smooth((z-1.275)/.026)*(1.-smooth((z-1.405)/.040))
    # Retain the real armpit opening. Only soften the valley ABOVE it,
    # and reduce the outer cap by a few millimetres instead of filling it solid.
    root=.008*math.exp(-((x-.197)/.032)**2)
    cap=.004*math.exp(-((x-.259)/.042)**2)
    dy=(root-cap)*height*smooth(abs(y)/.038)
    # Relieve the short ridge at the shoulder's top without moving its pole.
    ridge=.004*math.exp(-((x-.231)/.040)**2-((z-1.416)/.024)**2-(y/.030)**2)
    ridge*=smooth((z-1.30)/.05)*smooth((x-.15)/.035)
    return Vector((p.x-math.copysign(ridge,p.x),p.y+dy*(1. if y>=0. else -1.),z))

report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'preserved_meshes':preserved,'modified_meshes':TARGETS,'parts':{}}
for name in TARGETS:
    obj=bpy.data.objects[name];mesh=obj.data;world=obj.matrix_world.copy();inv=world.inverted()
    original=[world@v.co for v in mesh.vertices]
    old_normals=[n.vector.copy() for n in mesh.corner_normals]
    deform=deform_neck if name==HEAD else deform_garment
    normal_world=world.to_3x3().inverted().transposed();normal_local=world.to_3x3().transposed()
    changed={};jacobians={};min_det=1.
    for i,p in enumerate(original):
        q=deform(p)
        if (q-p).length<1e-9:continue
        columns=[]
        for axis in range(3):
            d=Vector();d[axis]=.00001
            columns.append((deform(p+d)-deform(p-d))/.00002)
        J=Matrix(columns).transposed();min_det=min(min_det,J.determinant())
        assert J.determinant()>.5,(name,tuple(p),J.determinant())
        jacobians[i]=J.inverted().transposed();changed[i]=q
    normals=[]
    for loop,n in zip(mesh.loops,old_normals):
        J=jacobians.get(loop.vertex_index)
        normals.append(n if J is None else (normal_local@J@normal_world@n).normalized())
    for i,q in changed.items():mesh.vertices[i].co=inv@q
    mesh.update();mesh.normals_split_custom_set(normals)
    textile=None
    if name.endswith('_Arm'):
        textile=bake_sleeve_material(obj,original,HERE/'textures')
        for key in ('baked_image','baked_normal_image'):
            textile[key]=str(Path(textile[key]).relative_to(ROOT))
    obj['neck_arm_flow_revision']='Localized neck muscle flow, softened shoulder valley/cap and continuous upper-sleeve weave'
    report['parts'][name]={'changed_vertices':len(changed),'max_displacement_m':max(((q-original[i]).length for i,q in changed.items()),default=0),'minimum_jacobian_determinant':min_det,'textile_bake':textile}
assert preserved=={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in TARGETS}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'Gravebound_Neck_Arm_Flow.blend'),compress=True)
out=HERE/'gravebound_player_neck_arm_flow.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=out.read_bytes();assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data)
shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report.update(output_sha256=hashlib.sha256(data).hexdigest(),preserved_mesh_count=len(preserved),pass_build=True)
(HERE/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('NECK ARM FLOW BUILD PASS',report['output_sha256'],flush=True)
