"""Read-only direct OBJ parsing: components, UVs, boundaries and polygroup facts."""
import hashlib,json,time
from collections import Counter
from pathlib import Path
import numpy as np

SOURCE=Path('/Users/duq711gmail.com/Downloads/hand1.OBJ')
OUT=Path(__file__).resolve().parents[1]/'audit'
raw=SOURCE.read_bytes();digest=hashlib.sha256(raw).hexdigest()
vertices=[];faces=[];groups=Counter();face_groups=Counter();declarations=Counter();current='(none)';colors=Counter();comment=[]
for line in raw.decode('ascii').rstrip('\x00').splitlines():
    words=line.split()
    if not words:continue
    kind=words[0];declarations[kind]+=1
    if kind=='#':
        if len(comment)<10:comment.append(line)
    elif kind=='v':vertices.append([float(x)for x in words[1:4]]);colors[len(words)-1]+=1
    elif kind=='g':current=' '.join(words[1:]);groups[current]+=1
    elif kind=='f':
        indices=[int(x.split('/')[0])for x in words[1:]]
        indices=[x-1 if x>0 else len(vertices)+x for x in indices]
        faces.append(indices);face_groups[current]+=1
points=np.asarray(vertices,dtype=np.float64);nv=len(points);lengths=np.asarray([len(f)for f in faces],dtype=np.int32)
assert np.isfinite(points).all()
starts=np.concatenate(([0],np.cumsum(lengths)[:-1]));flat=np.asarray([i for f in faces for i in f],dtype=np.int32)
assert flat.min()>=0 and flat.max()<nv
ends=np.cumsum(lengths)-1;nexts=np.roll(flat,-1);nexts[ends]=flat[starts]
low=np.minimum(flat,nexts).astype(np.int64);high=np.maximum(flat,nexts).astype(np.int64)
keys=low*nv+high;unique,counts=np.unique(keys,return_counts=True)
edge0=unique//nv;edge1=unique%nv
parent=list(range(nv));sizes=[1]*nv
def find(a):
    while parent[a]!=a:parent[a]=parent[parent[a]];a=parent[a]
    return a
for a,b in zip(edge0.tolist(),edge1.tolist()):
    a,b=find(a),find(b)
    if a!=b:
        if sizes[a]<sizes[b]:a,b=b,a
        parent[b]=a;sizes[a]+=sizes[b]
roots=np.asarray([find(i)for i in range(nv)],dtype=np.int32)
root_ids,labels=np.unique(roots,return_inverse=True);labels=labels.astype(np.int32)
face_component=labels[flat[starts]]
boundary_indices=np.flatnonzero(counts==1)
nonmanifold=np.flatnonzero(counts>2)
components=[]
for label in range(len(root_ids)):
    mask=labels==label;part=points[mask];edge_mask=labels[edge0]==label;face_mask=face_component==label
    boundary=boundary_indices[labels[edge0[boundary_indices]]==label]
    pca_center=part.mean(axis=0);cov=(part-pca_center).T@(part-pca_center)/len(part);values,vectors=np.linalg.eigh(cov);order=np.argsort(values)[::-1]
    row={'component':label,'vertices':int(mask.sum()),'edges':int(edge_mask.sum()),'faces':int(face_mask.sum()),
        'triangles_after_fan_triangulation':int((lengths[face_mask]-2).sum()),'boundary_edges':len(boundary),
        'nonmanifold_edges':int(np.count_nonzero(edge_mask&(counts>2))),
        'euler_characteristic':int(mask.sum()-edge_mask.sum()+face_mask.sum()),
        'bounds':np.stack((part.min(axis=0),part.max(axis=0))).tolist(),'centroid':pca_center.tolist(),
        'pca_axes_columns':vectors[:,order].tolist(),'pca_variances':values[order].tolist(),
        'face_sizes':{str(k):int(v)for k,v in zip(*np.unique(lengths[face_mask],return_counts=True))}}
    if len(boundary):
        boundary_vertices=np.unique(np.concatenate((edge0[boundary],edge1[boundary])))
        row['boundary_bounds']=np.stack((points[boundary_vertices].min(axis=0),points[boundary_vertices].max(axis=0))).tolist()
        row['boundary_vertices']=boundary_vertices.tolist()
    components.append(row)
components.sort(key=lambda r:r['vertices'],reverse=True)
OUT.mkdir(exist_ok=True)
np.save(OUT/'obj_component_labels.npy',labels)
report={'source':str(SOURCE),'source_sha256':digest,'source_bytes':len(raw),'comments':comment,
    'null_bytes':raw.count(b'\0'),'vertices':nv,'faces':len(faces),'triangles_after_fan_triangulation':int((lengths-2).sum()),
    'uv_coordinates':declarations['vt'],'normals':declarations['vn'],'materials':declarations['usemtl'],'material_libraries':declarations['mtllib'],
    'vertex_field_count':dict(colors),'groups':dict(groups),'face_groups':dict(face_groups),
    'bounds':np.stack((points.min(axis=0),points.max(axis=0))).tolist(),'unique_edges':len(unique),
    'boundary_edges':len(boundary_indices),'nonmanifold_edges':len(nonmanifold),'connected_components':components,
    'component_labels_file':'obj_component_labels.npy','component_labels_sha256':hashlib.sha256((OUT/'obj_component_labels.npy').read_bytes()).hexdigest(),
    'interpretation':['OBJ has no skeletal rig or animation data. A single named polygroup cannot by itself identify anatomical digits.',
        'Connected components and actual geometry may identify nail islands; their anatomical names need the separate direct visual audit.',
        'Topological closure here means indexed edge multiplicity, not a proof of absence of surface self-intersection.']}
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==digest
(OUT/'obj_topology.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k]for k in ('vertices','faces','triangles_after_fan_triangulation','uv_coordinates','groups','boundary_edges','nonmanifold_edges')}))
print(json.dumps(components,indent=2))
