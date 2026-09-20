"""Turn the existing relaxed hands inward, smoothly distributing twist at cuffs."""
import bpy, json, hashlib, math
from pathlib import Path
from mathutils import Vector, Quaternion
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=ROOT/'asset-staging/player_natural_hands_20260921/Gravebound_Natural_Hands.blend'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def signature(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(f.vertices) for f in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'m':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
objects=list(bpy.data.objects)
unchanged={o.name:signature(o) for o in objects if o.type=='MESH' and not o.name.startswith('Gravebound_FP_')}
report={}
for side,sign in [('L',-1),('R',1)]:
 pivot=Vector((sign*.29,.075,.87));elbow=Vector((sign*.268,.004,1.155));axis=(elbow-pivot).normalized()
 angle=math.radians(-sign*90);rotation=Quaternion(axis,angle);offset=Vector((sign*.015,0,0))
 palm_before=Vector((0,-1,0));palm_after=rotation@palm_before;inward=Vector((-sign,0,0))
 assert palm_after.dot(inward)>.95
 parts={}
 for section in ('Arm','Hand'):
  obj=bpy.data.objects[f'Gravebound_FP_{side}_{section}'];mesh=obj.data
  before=[v.co.copy() for v in mesh.vertices]
  uvs=[[list(x.uv) for x in l.data] for l in mesh.uv_layers]
  faces=[tuple(f.vertices) for f in mesh.polygons]
  cuff_errors=[];kept=0
  for v,p in zip(mesh.vertices,before):
   if section=='Hand':weight=1.
   else:
    t=max(0.,min(1.,(p.z-.95)/(1.135-.95)));weight=1-t*t*(3-2*t)
   if weight==0:kept+=1;continue
   v.co=pivot+Quaternion(axis,angle*weight)@(p-pivot)+offset*weight
   if p.z<=.95:cuff_errors.append((v.co-(pivot+rotation@(p-pivot)+offset)).length)
  mesh.update()
  if mesh.has_custom_normals:mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])
  assert faces==[tuple(f.vertices) for f in mesh.polygons]
  assert uvs==[[list(x.uv) for x in l.data] for l in mesh.uv_layers]
  assert not cuff_errors or max(cuff_errors)<1e-7
  parts[section]={'vertices':len(mesh.vertices),'unchanged_upper_vertices':kept,'cuff_transform_error_m':max(cuff_errors,default=0),'bounds_min':[min(v.co[k] for v in mesh.vertices) for k in range(3)],'bounds_max':[max(v.co[k] for v in mesh.vertices) for k in range(3)]}
 report[side]={'rotation_degrees':-sign*90,'pivot':list(pivot),'outward_offset_m':.015,'axis':list(axis),'palm_direction':list(palm_after),'inward_alignment':palm_after.dot(inward),'parts':parts}
assert unchanged=={o.name:signature(o) for o in objects if o.type=='MESH' and not o.name.startswith('Gravebound_FP_')}
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
for im in bpy.data.images:
 if im.source=='FILE' and im.has_data:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Inward_Palms.blend'),compress=True)
out=W/'gravebound_player_inward_palms.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
(W/'build_report.json').write_text(json.dumps({'source_sha256':sha(SOURCE),'output_sha256':sha(out),'non_arm_geometry_unchanged':True,'uvs_materials_unchanged':True,'forearm_blend_height_m':[.95,1.135],'sides':report},indent=2))
print('INWARD PALMS BUILD PASS',json.dumps(report))
