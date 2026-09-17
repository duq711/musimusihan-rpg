"""Read-only source nail topology, frames, UVs, and finite shell audit."""
import json, sys, hashlib, importlib.util
from pathlib import Path
import bpy
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
detail=module(ROOT/'player_fingers_detail_20260911/tools/verify_finger_detail.py','probe_detail')
rotation=module(ROOT/'player_fingers_detail_20260911/tools/verify_thumb_rotation.py','probe_rotation')
legacy=module(ROOT/'player_hands_realism_20260911/tools/verify_hands_realistic.py','probe_legacy')
generic=module(ROOT/'player_hands_proportions_20260911/tools/verify_proportions.py','probe_generic')
generic.legacy=legacy;generic.core=legacy.core
detail.legacy=legacy;detail.generic=generic;detail.core=legacy.core
source=ROOT/'player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
old=detail.sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source))
scene,rigs=detail.activate();result={'source':str(source),'source_sha256':old,'hands':{}}
for side,rig in rigs.items():
    snap=detail.capture(scene,rig);rows={}
    for digit in detail.DIGITS:
        p=snap['parts']['nail_'+digit];points=p['points'];normal=rotation.nail_normal(p)
        axis=rotation.unit(np.asarray(snap['bone_points'][digit+'2']['tail'])-snap['bone_points'][digit+'2']['head'])
        dorsal=rotation.unit(normal-axis*np.dot(normal,axis));cross=rotation.unit(np.cross(axis,dorsal))
        basis=np.column_stack((cross,axis,dorsal));local=(points-points[0])@basis
        top=np.array([t for t in p['triangles'] if max(t)<161]);a,b,c=points[top[:,0]],points[top[:,1]],points[top[:,2]]
        n=np.cross(b-a,c-a);n/=np.linalg.norm(n,axis=1)[:,None]
        rows[digit]={'vertices':len(points),'faces':len(p['faces']),'triangles':len(p['triangles']),'top_triangles':len(top),
            'top_center_index':0,'top_rings':[[1+i*32,32+i*32] for i in range(5)],'paired_bottom_offset':161,
            'native_top_normal':normal.tolist(),'native_axis':axis.tolist(),'frame_cross_axis_dorsal':basis.tolist(),
            'top_bottom_distance_mm':(np.linalg.norm(points[:161]-points[161:],axis=1)*1000).tolist(),
            'top_local_mm':(local[:161]*1000).tolist(),'top_uv_sets':p['uv_sets'][:161],
            'top_triangle_normal_dot_average':[float(v) for v in n@normal]}
    result['hands'][side]=rows
assert detail.sha(source)==old
(HERE.parent/'audit/source_nail_structure.json').write_text(json.dumps(result,indent=2)+'\n')
print('NAIL_STRUCTURE_PROBE_COMPLETE')
