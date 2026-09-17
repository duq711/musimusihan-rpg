import json,struct,math
from pathlib import Path
S=Path(__file__).resolve().parents[1];p=S/'mac_output/iteration_03/left_hand_realistic.glb';blob=p.read_bytes();n=struct.unpack_from('<I',blob,12)[0];d=json.loads(blob[20:20+n]);base=20+n+8

def acc(i):
 x=d['accessors'][i];v=d['bufferViews'][x['bufferView']];k={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[x['type']];fmt={5126:'f',5123:'H',5125:'I'}[x['componentType']];stride=v.get('byteStride',struct.calcsize(fmt)*k);off=base+v.get('byteOffset',0)+x.get('byteOffset',0);return[struct.unpack_from('<'+fmt*k,blob,off+j*stride)for j in range(x['count'])]
rows=[]
for mesh in d['meshes']:
 for pi,primitive in enumerate(mesh['primitives']):
  a=primitive['attributes'];ts=acc(a['TANGENT']);bad=[i for i,t in enumerate(ts)if sum(c*c for c in t[:3])<.99]
  if not bad:continue
  ps,uvs,ns=acc(a['POSITION']),acc(a['TEXCOORD_0']),acc(a['NORMAL']);flat=[x[0]for x in acc(primitive['indices'])];tris=[flat[i:i+3]for i in range(0,len(flat),3)]
  for vi in bad:
   triangle_rows=[]
   for tri in tris:
    if vi not in tri:continue
    uv=[uvs[i]for i in tri];det=(uv[1][0]-uv[0][0])*(uv[2][1]-uv[0][1])-(uv[1][1]-uv[0][1])*(uv[2][0]-uv[0][0]);triangle_rows.append({'indices':tri,'position':[ps[i]for i in tri],'uv':uv,'uv_determinant':det,'neighbor_tangents':[ts[i]for i in tri]})
   rows.append({'mesh':mesh['name'],'primitive':pi,'vertex':vi,'tangent':ts[vi],'normal':ns[vi],'adjacent_triangles':triangle_rows})
(S/'diagnostics/tangent_zero_provenance.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows,indent=2))
