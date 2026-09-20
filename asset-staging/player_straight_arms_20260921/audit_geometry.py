"""Check restored wrists and localized elbow edits against the pre-wrist model and anatomical sleeve profiles."""
import json, struct
from pathlib import Path
WORK=Path(__file__).resolve().parent
ROOT=WORK.parents[1]
def meshes(path):
 data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n]);result={}
 for mesh in doc['meshes']:
  if not mesh['name'].startswith('FP_'):continue
  acc=doc['accessors'][mesh['primitives'][0]['attributes']['POSITION']]
  view=doc['bufferViews'][acc['bufferView']]
  assert acc['componentType']==5126 and acc['type']=='VEC3'
  offset=28+n+view.get('byteOffset',0)+acc.get('byteOffset',0)
  result[mesh['name']]=[struct.unpack_from('<3f',data,offset+i*view.get('byteStride',12)) for i in range(acc['count'])]
 return result
def signature(points):return set(tuple(round(c,6) for c in p) for p in points)
old=meshes(ROOT/'asset-staging/player_fullbody_anatomy_20260921/gravebound_player_fp_arms.glb')
new=meshes(ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
for name,points in new.items():
 if 'Hand' in name:assert signature(points)==signature(old[name]),name
 else:
  assert signature(p for p in points if p[1]<=.925)==signature(p for p in old[name] if p[1]<=.925),name
  assert signature(points)!=signature(old[name]),name
  sections=[]
  for ri in (10,25,40,55,65):
   height=.935+(1.443-.935)*ri/80
   q=[p for p in points if abs(p[1]-height)<1e-5]
   assert q,(name,ri)
   bounds=[(min(p[k] for p in q),max(p[k] for p in q)) for k in (0,2)]
   sections.append((height,[(a+b)/2 for a,b in bounds],[b-a for a,b in bounds]))
  first,last=sections[0],sections[-1]
  for h,center,width in sections:
   t=(h-first[0])/(last[0]-first[0])
   for k in (0,1):
    assert abs(center[k]-(first[1][k]*(1-t)+last[1][k]*t))<1e-5,(name,'bent axis')
    assert abs(width[k]-(first[2][k]*(1-t)+last[2][k]*t))<1e-5,(name,'wavy outline')
  print(name,'straight axis and linear taper PASS')
r=json.loads((WORK/'build_report.json').read_text())
baseline=json.loads((ROOT/'asset-staging/player_fullbody_anatomy_20260921/build_report.json').read_text())
assert r['retained_signatures']==baseline['retained_signatures']
assert r['fp_sources']==baseline['fp_sources']
print('PASS: both complete hands and lower sleeves restored, straight sleeve profile verified, 24 body meshes and FP sources preserved.')
