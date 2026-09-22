"""Refit the clothed upper-body masses to the supplied reference proportion study."""
from pathlib import Path
import bpy,sys,json,hashlib,struct,shutil
from mathutils import Matrix,Vector
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
from deformation import garment,neck
SOURCE=HERE.parent/'player_neck_arm_flow_20260922/Gravebound_Neck_Arm_Flow.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
TARGETS=['Gravebound_AnatomicalHead','Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
def sig(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'uv':[[list(d.uv) for d in l.data] for l in o.data.uv_layers],'normals':[list(n.vector) for n in o.data.corner_normals],'world':[list(row) for row in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
preserved={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in TARGETS}
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'parts':{},'preserved_meshes':preserved}
for name in TARGETS:
 o=bpy.data.objects[name];me=o.data;world=o.matrix_world.copy();inv=world.inverted()
 nw=world.to_3x3().inverted().transposed();nl=world.to_3x3().transposed()
 points=[world@v.co for v in me.vertices];old_normals=[n.vector.copy() for n in me.corner_normals]
 fn=neck if name==TARGETS[0] else garment
 changes={};jacobians={};minimum=1.
 for i,p in enumerate(points):
  q=fn(p)
  if (q-p).length<1e-8:continue
  columns=[]
  for axis in range(3):
   d=Vector();d[axis]=.00001;columns.append((fn(p+d)-fn(p-d))/.00002)
  j=Matrix(columns).transposed();det=j.determinant();minimum=min(minimum,det)
  assert det>.25,(name,tuple(p),det)
  changes[i]=q;jacobians[i]=j.inverted().transposed()
 normals=[]
 for loop,n in zip(me.loops,old_normals):
  j=jacobians.get(loop.vertex_index);normals.append(n if j is None else (nl@j@nw@n).normalized())
 for i,q in changes.items():me.vertices[i].co=inv@q
 me.update();me.normals_split_custom_set(normals)
 report['parts'][name]={'changed_vertices':len(changes),'max_displacement_m':max(((q-points[i]).length for i,q in changes.items()),default=0),'minimum_jacobian':minimum}
 o['anatomy_revision']='Reference-guided rib cage, pectoral, trapezius, deltoid and upper-arm mass distribution'
assert preserved=={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in TARGETS}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'Gravebound_Reference_Anatomy.blend'),compress=True)
out=HERE/'gravebound_player_reference_anatomy.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=out.read_bytes();assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data)
shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report.update(output_sha256=hashlib.sha256(data).hexdigest(),preserved_mesh_count=len(preserved),pass_build=True)
(HERE/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('REFERENCE ANATOMY BUILD PASS',report['output_sha256'],flush=True)
