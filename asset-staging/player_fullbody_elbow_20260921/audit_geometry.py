"""Check restored wrists and localized elbow edits against the pre-wrist model."""
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
  assert signature(p for p in points if p[1]<=.98)==signature(p for p in old[name] if p[1]<=.98),name
  assert signature(points)!=signature(old[name]),name
  elbow=[p for p in points if 1.08<p[1]<1.12]
  width=max(p[0] for p in elbow)-min(p[0] for p in elbow)
  depth=max(p[2] for p in elbow)-min(p[2] for p in elbow)
  assert .06<width<.115 and .06<depth<.115,(name,width,depth)
  print(name,'elbow width/depth',round(width,4),round(depth,4))
r=json.loads((WORK/'build_report.json').read_text())
baseline=json.loads((ROOT/'asset-staging/player_fullbody_anatomy_20260921/build_report.json').read_text())
assert r['retained_signatures']==baseline['retained_signatures']
assert r['fp_sources']==baseline['fp_sources']
print('PASS: both complete hands and lower sleeves restored, elbows changed, 24 body meshes and FP sources preserved.')
