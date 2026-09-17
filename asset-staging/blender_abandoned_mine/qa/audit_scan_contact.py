import bpy, sys, json
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
import rock_detail
bvh=rock_detail._terrain_surface()
result=[]
for obj in bpy.data.objects:
    if obj.type!='MESH' or not obj.name.startswith('RockScan_'):continue
    coords=np.array([obj.matrix_world@v.co for v in obj.data.vertices])
    local=np.array([v.co for v in obj.data.vertices])
    step=max(1,len(coords)//160)
    distances=[]
    for p in coords[::step]:
        hit,n,face,dist=bvh.find_nearest(Vector(p))
        distances.append(float(dist))
    result.append({'name':obj.name,'loc':list(obj.location),'rot':list(obj.rotation_euler),'scale':list(obj.scale),'bbox':[coords.min(axis=0).tolist(),coords.max(axis=0).tolist()],
                   'local_bbox':[local.min(axis=0).tolist(),local.max(axis=0).tolist()],
                   'distance_percentiles':np.percentile(distances,[0,25,50,75,100]).tolist()})
(ROOT/'qa/scan_contact_before.json').write_text(json.dumps(result,indent=2))
print(json.dumps([r for r in result if r['bbox'][0][1]<-48 or 'entrance' in r['name']],indent=2),flush=True)
