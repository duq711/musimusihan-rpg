"""Read-only source-relative seam and per-hand UV diagnostics, no acceptance override."""
import importlib.util,json
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('glove_seam_diagnostics',here/'verify_gloves.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
source=here.parents[1]/'player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
inputs=[source,*[here.parent/'mac_output'/name/'bilateral_mercenary_gloves.blend'for name in ('iteration_01','iteration_02')]]
hashes={str(p):v.sha(p)for p in inputs}
bpy.ops.wm.open_mainfile(filepath=str(source));scene,rigs=v.native_rigs()
old={s:v.capture(scene,r)for s,r in rigs.items()};old_colors={s:v.finger_basecolor_samples(scene,r)for s,r in rigs.items()}
report={'read_only_hashes':hashes,'candidates':{}}
for name,path in zip(('iteration_01','iteration_02'),inputs[1:]):
    bpy.ops.wm.open_mainfile(filepath=str(path));scene,rigs=v.native_rigs();rows=report['candidates'][name]={}
    for side,rig in rigs.items():
        before=old[side]['parts']['hand'];after=v.capture(scene,rig)['parts']['hand'];row=rows[side]={'seams':{}}
        try:row['actual_uv_coverage']=v.compare_finger_basecolor_samples(old_colors[side],v.finger_basecolor_samples(scene,rig))
        except Exception as e:row['actual_uv_coverage']={'error':str(e)}
        tree=KDTree(12036)
        for i,p in enumerate(before['points'][:12036]):tree.insert(Vector(p),i)
        tree.balance();pairs=set()
        for i,p in enumerate(before['points'][:12036]):
            pairs.update((i,j)for _,j,_ in tree.find_range(Vector(p),1e-6)if j>i)
        pairs=np.asarray(sorted(pairs),dtype=np.int64)
        for key in ['Basis',*v.KEYS]:
            a=before['points']if key=='Basis'else before['points']+before['deltas'][key]
            b=after['points']if key=='Basis'else after['points']+after['deltas'][key]
            da=np.linalg.norm(a[pairs[:,0]]-a[pairs[:,1]],axis=1);db=np.linalg.norm(b[pairs[:,0]]-b[pairs[:,1]],axis=1)
            idx=int(np.argmax(db));growth=int(np.argmax(db-da))
            row['seams'][key]={'pairs':len(pairs),'source_maximum_m':float(da.max()),'candidate_maximum_m':float(db.max()),
                'maximum_growth_m':float((db-da).max()),'maximum_gap_vertices':pairs[idx].tolist(),
                'maximum_growth_vertices':pairs[growth].tolist(),'source_pairs_above_2um':int(np.count_nonzero(da>2e-6)),
                'candidate_pairs_above_2um':int(np.count_nonzero(db>2e-6))}
assert all(v.sha(p)==h for p,h in hashes.items())
out=here.parent/'audit';out.mkdir(exist_ok=True);(out/'seam_and_uv_iteration01_02.json').write_text(json.dumps(report,indent=2)+'\n')
print('GLOVE_SEAM_AUDIT_COMPLETE')
