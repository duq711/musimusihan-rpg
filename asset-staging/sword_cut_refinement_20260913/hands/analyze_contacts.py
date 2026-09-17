"""Independently compare actual Godot skin samples to rendered hilt triangles."""
import json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

root=Path(__file__).resolve().parent
source=root/'runtime_contacts.json'
data=json.loads(source.read_text())
vertices=[]; triangles=[]
for part in data['hilt']:
    offset=len(vertices)
    vertices.extend(Vector(p) for p in part['vertices'])
    indices=part['triangles']
    triangles.extend(tuple(offset+i for i in indices[start:start+3]) for start in range(0,len(indices),3))
tree=BVHTree.FromPolygons(vertices,triangles,all_triangles=True)
patches={};samples=[]
for sample in data['samples']:
    gaps={}
    for patch,p in sample['patches'].items():
        point=Vector(p)
        near,normal,_,distance=tree.find_nearest(point)
        # Godot's clockwise front-face winding is opposite to Blender BVH.
        # The convex leather shaft's outward side is independently radial.
        if near.x*normal.x+near.z*normal.z<0: normal=-normal
        gap=distance if (point-near).dot(normal)>=0 else -distance
        gaps[patch]=gap
        patches.setdefault(patch,[]).append(gap)
    samples.append({'variant':sample['variant'],'frame':sample['frame'],'gaps':gaps})
summary={patch:{'minimum_gap_m':min(values),'maximum_gap_m':max(values),'mean_gap_m':sum(values)/len(values)} for patch,values in patches.items()}
thumb_gaps=[]
for point in map(Vector,data.get('right_thumb_points',[])):
    near,normal,_,distance=tree.find_nearest(point)
    if near.x*normal.x+near.z*normal.z<0: normal=-normal
    thumb_gaps.append(distance if (point-near).dot(normal)>=0 else -distance)
thumb={'sample_count':len(thumb_gaps),'minimum_gap_m':min(thumb_gaps),'penetrating_more_than_1mm':sum(v<-.001 for v in thumb_gaps),'contact_vertices_within_2mm':sum(-.0005<=v<=.002 for v in thumb_gaps)}
assert thumb['minimum_gap_m']>=-.0005 and thumb['contact_vertices_within_2mm']>=5,thumb
maximum_godot_gap_difference=0.0
for patch,values in summary.items():
    for field in ['minimum_gap_m','maximum_gap_m']:
        maximum_godot_gap_difference=max(maximum_godot_gap_difference,abs(values[field]-data['summary'][patch][field]))
assert maximum_godot_gap_difference<.000001,maximum_godot_gap_difference
result={'source':str(source),'samples':samples,'summary':summary,'right_thumb_actual':thumb,'independent_godot_gap_maximum_difference_m':maximum_godot_gap_difference}
print('RIGHT THUMB ACTUAL',json.dumps(thumb))
(root/'left_contact_validation.json').write_text(json.dumps(result,indent=2))
print('LEFT CONTACTS',json.dumps(summary))
