"""Read-only detailed witnesses for a rejected geometry candidate."""
import argparse, importlib.util, json, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('photoref_diagnostic_verifier',here/'verify_photoref_fingers.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v);v.load_helpers()
parser=argparse.ArgumentParser();parser.add_argument('--candidate',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);out=args.candidate.resolve()
src=here.parents[1]/'player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
target=out/'bilateral_hands_finger_detail.blend'
hashes={str(p):v.detail.sha(p) for p in (src,target)}
bpy.ops.wm.open_mainfile(filepath=str(src));scene,rigs=v.detail.activate()
old={s:v.detail.capture(scene,r)for s,r in rigs.items()}
bpy.ops.wm.open_mainfile(filepath=str(target));scene,rigs=v.detail.activate()
new={s:v.detail.capture(scene,r)for s,r in rigs.items()};report={'hashes':hashes,'hands':{}}
for side,rig in rigs.items():
    a,b=old[side]['parts']['hand'],new[side]['parts']['hand'];tri=np.asarray([t for t in a['triangles']if max(t)<12036])
    p,q=a['points'][tri],b['points'][tri];na=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);nb=np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0])
    area0,area1=np.linalg.norm(na,axis=1),np.linalg.norm(nb,axis=1)
    align=np.sum(na*nb,axis=1)/(area0*area1)
    row=report['hands'][side]={'flipped_triangles':[],'nail_mesh_checks':{},'seating':{}}
    for idx in np.flatnonzero(align<=0):
        row['flipped_triangles'].append({'physical_triangle_index':int(idx),'vertices':tri[idx].tolist(),
            'source_normal_alignment':float(align[idx]),'source_double_area_m2':float(area0[idx]),'new_double_area_m2':float(area1[idx]),
            'source_native':p[idx].tolist(),'new_native':q[idx].tolist(),
            'weights':[a['weights'][i]for i in tri[idx]],'displacement_m':np.linalg.norm(q[idx]-p[idx],axis=1).tolist()})
    changed=np.linalg.norm(b['points']-a['points'],axis=1)>0;touched=np.any(changed[tri],axis=1)
    faces=[tuple(t) for t in tri];tree=BVHTree.FromPolygons([Vector(p)for p in b['points']],faces,all_triangles=True)
    newhits=[];tested=0
    for ia,ib in sorted({(min(i,j),max(i,j))for i,j in tree.overlap(tree)if i!=j and(touched[i]or touched[j])}):
        if set(faces[ia])&set(faces[ib])or any(np.linalg.norm(x-y)<1e-7 for x in p[ia]for y in p[ib]):continue
        tested+=1
        if v.detail.triangle_hit(q[ia],q[ib])and not v.detail.triangle_hit(p[ia],p[ib]):newhits.append([ia,ib])
    row['new_true_intersection_pairs']=newhits;row['actual_triangle_pairs_tested']=tested
    for d in v.DIGITS:
        try:row['nail_mesh_checks'][d]=v.inspect_nail_mesh(old[side]['parts']['nail_'+d],new[side]['parts']['nail_'+d],old[side],d)
        except Exception as e:row['nail_mesh_checks'][d]={'error':str(e)}
    for pose,digits in v.rotation.nail_measurements(scene,rig).items():
        row['seating'][pose]={}
        for d,m in digits.items():
            misses=int(np.count_nonzero(~np.isfinite(m['ray_top'])))
            maximum=float(m['distances'].max());signed=float(m['signed_top'].min());ray=float(np.nanmin(m['ray_top']))
            row['seating'][pose][d]={'maximum_gap_m':maximum,'minimum_signed_top_m':signed,'ray_misses':misses,
                'minimum_geometric_ray_clearance_m':ray,
                'passed':misses==0 and maximum<.0008 and signed>=-.00002 and ray>=(0. if pose=='neutral'else-.00002)}
assert all(v.detail.sha(p)==s for p,s in hashes.items())
(out/'geometry_diagnostic.json').write_text(json.dumps(report,indent=2)+'\n')
print('PHOTOREF_GEOMETRY_DIAGNOSTIC_COMPLETE',json.dumps({s:{'flipped':len(r['flipped_triangles']),'new_intersections':len(r['new_true_intersection_pairs']),
    'failed_seating':[p+'/'+d for p,ds in r['seating'].items()for d,m in ds.items()if not m['passed']]}for s,r in report['hands'].items()}))
