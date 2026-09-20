"""Compare former shoulder gaps against final cloth using vertical top rays.

Blender --background --python audit_coverage.py -- /absolute/final.blend
Recognizes bridges before joining and after joining Gravebound_MantleBack.
"""
import bpy,json,hashlib,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent
BASE=W.parent/'player_hood_redesign_20260921/Gravebound_Rebuilt_Hood.blend'
final=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else W/'Gravebound_Closed_Shoulder_Hood.blend'
cloth_names={'Gravebound_PointHood','Gravebound_InnerNeckCowl','Gravebound_Mantle_L','Gravebound_Mantle_R','Gravebound_MantleBack','Gravebound_ShoulderBridge_L','Gravebound_ShoulderBridge_R'}
def load_cloth(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));vs=[];ts=[]
 for o in bpy.data.objects:
  if o.name not in cloth_names or o.type!='MESH':continue
  m=o.data;m.calc_loop_triangles();off=len(vs);vs.extend(o.matrix_world@v.co for v in m.vertices);ts.extend(tuple(off+v for v in t.vertices) for t in m.loop_triangles)
 return BVHTree.FromPolygons(vs,ts,all_triangles=True)
def top(tree,x,y):
 p,n,idx,d=tree.ray_cast(Vector((x,y,2.)),Vector((0,0,-1)),1.)
 return p.z if p is not None else None
extraction=json.loads((W/'geometry_extraction_report.json').read_text());baseline=load_cloth(BASE);new=load_cloth(final)
rows=[]
for side in extraction['sides']:
 for r in side['rows'][1:-1]:
  b,f=r['back_edge'],r['front_edge']
  if f[1]-b[1]<.012:continue
  for k in range(1,20):
   t=k/20;x=b[0]*(1-t)+f[0]*t;y=b[1]*(1-t)+f[1]*t;expected=b[2]*(1-t)+f[2]*t-.012
   before=top(baseline,x,y);after=top(new,x,y)
   rows.append({'side':side['object'],'x':x,'y':y,'minimum_cloth_height':expected,'before':before,'after':after,'was_gap':before is None or before<expected,'is_gap':after is None or after<expected})
failures=[r for r in rows if r['is_gap']];before_gaps=[r for r in rows if r['was_gap']]
report={'baseline_blend_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'final_blend_sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'audit_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'sample_count':len(rows),'former_gap_rays':len(before_gaps),'remaining_gap_rays':len(failures),'failures':failures[:40],'pass':not failures and bool(before_gaps)}
# For smoke assets, keep final evidence separate from production validation.
name='coverage_report.json' if final.name=='Gravebound_Closed_Shoulder_Hood.blend' else 'coverage_smoke_report.json'
(W/name).write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert report['pass']
