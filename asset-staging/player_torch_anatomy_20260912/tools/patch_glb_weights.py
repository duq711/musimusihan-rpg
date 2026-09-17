import sys,json,struct,numpy as np
from pathlib import Path
s=Path(__file__).resolve().parents[1];sys.path.insert(0,str(s/'tools/python_deps'));from scipy.spatial import cKDTree
root=s.parents[1];src=root/'godot-game/assets/3d/player/hands_detailed/left_hand_detailed.glb';raw=bytearray(src.read_bytes());jlen=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+jlen]);start=20+jlen+8
x=np.load(s/'audit/fit_input_reweighted.npz');d={k:x[k] for k in x.files};W=x['weights'];ranks=np.argsort(-W,axis=1);mask=np.zeros_like(W,dtype=bool);np.put_along_axis(mask,ranks[:,:4],True,axis=1);W=np.where(mask,W,0);W/=W.sum(1)[:,None];d['weights']=W;np.savez(s/'audit/fit_input_reweighted.npz',**d)
tree=cKDTree(x['vertices']);names=list(x['names'])
def acc(i):
 a=g['accessors'][i];b=g['bufferViews'][a['bufferView']];dt={5126:'<f4',5123:'<u2',5121:'u1'}[a['componentType']];n={'VEC3':3,'VEC4':4}[a['type']];stride=b.get('byteStride',np.dtype(dt).itemsize*n);offset=start+b.get('byteOffset',0)+a.get('byteOffset',0);return np.ndarray((a['count'],n),dtype=dt,buffer=raw,offset=offset,strides=(stride,np.dtype(dt).itemsize))
count=0
for node in g['nodes']:
 if 'mesh' not in node or not node.get('name','').startswith('Supplied_AnatomicalHand'):continue
 joints=g['skins'][node['skin']]['joints'];mapping=[names.index(g['nodes'][n]['name']) for n in joints];inverse={n:i for i,n in enumerate(mapping)}
 for prim in g['meshes'][node['mesh']]['primitives']:
  p=acc(prim['attributes']['POSITION']);native=np.column_stack([p[:,0],-p[:,2],p[:,1]]);error,ids=tree.query(native);assert error.max()<2e-6
  slots=ranks[ids,:4];weights=np.take_along_axis(W[ids],slots,axis=1);jb=acc(prim['attributes']['JOINTS_0']);wb=acc(prim['attributes']['WEIGHTS_0']);jb[:]=np.vectorize(inverse.get)(slots);wb[:]=weights;count+=len(p)
out=s/'mac_output/left_hand_torch.glb';out.write_bytes(raw)
(s/'audit/weight_export.json').write_text(json.dumps({'matched_imported_vertices':count,'source':str(src),'geometry_uv_materials_unmodified':True,'method':'Original GLB unchanged except four-influence joint/weight buffers; Blender authoring file retained'},indent=2))
print('WEIGHT_ONLY_GLB',count)
