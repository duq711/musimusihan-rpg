"""Read-only ray, topology and triangle checks at the observed side-view thumb slit."""
import hashlib
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri

stage=Path(__file__).resolve().parents[1]
source=stage/'mac_output/geometry_02/bilateral_hands_reference_geometry.blend'
original=hashlib.sha256(source.read_bytes()).hexdigest()
def read(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    scene=bpy.data.scenes['Bilateral_Reference_Review'];bpy.context.window.scene=scene
    holder=scene.objects['LEFT_PreviewTranslationOnly']
    skin=next(o for o in scene.objects if o.type=='MESH' and 'Anatomical' in o.name and o.parent and any(g.name=='thumb0' for g in o.vertex_groups))
    # Choose left by ancestry rather than data-name suffixes.
    for obj in scene.objects:
        if obj.type!='MESH' or 'Anatomical' not in obj.name:continue
        ancestor=obj
        while ancestor and ancestor!=holder:ancestor=ancestor.parent
        if ancestor==holder:skin=obj;break
    transform=holder.matrix_world.inverted()@skin.matrix_world
    return [transform@v.co for v in skin.data.vertices],[tuple(p.vertices) for p in skin.data.polygons],skin
old_points,old_faces,unused=read(stage/'mac_output/geometry_01/bilateral_hands_reference_geometry.blend')
points,faces,skin=read(source)
tree=BVHTree.FromPolygons(points,faces)
direction=Vector((1,.05,.18)).normalized();center=Vector((0,.064,0))
rotation=(-direction).to_track_quat('-Z','Y')
right=rotation@Vector((1,0,0));up=rotation@Vector((0,1,0))
hits=[]
for x in range(573,628,3):
    for y in range(604,634,3):
        origin=center+direction*1.2+right*((x+.5)/1400-.5)*.35+up*(.5-(y+.5)/1100)*(.35*1100/1400)
        hit=tree.ray_cast(origin,-direction,2.)
        if hit[0] is not None:hits.append({'pixel':[x,y],'point':list(hit[0]),'face':hit[2],'facing':hit[1].dot(direction)})
center_hit=min(hits,key=lambda h:(h['pixel'][0]-600)**2+(h['pixel'][1]-620)**2)
target=Vector(center_hit['point'])
local=[i for i,f in enumerate(faces) if min((points[v]-target).length for v in f)<.013]
canonical={};ids=[]
for p in points:
    key=tuple(round(float(c),6) for c in p)
    if key not in canonical:canonical[key]=len(canonical)
    ids.append(canonical[key])
edges={}
for i,f in enumerate(faces):
    for a,b in zip(f,f[1:]+f[:1]):
        key=tuple(sorted((ids[a],ids[b])));edges.setdefault(key,[]).append(i)
boundaries=[{'edge':list(edge),'faces':adj} for edge,adj in edges.items() if len(adj)!=2 and any(i in local for i in adj)]
stats=[]
for i in local:
    f=faces[i];a,b,c=[points[v] for v in f[:3]]
    normal=(b-a).cross(c-a);area=normal.length*.5
    oa,ob,oc=[old_points[v] for v in f[:3]];old_normal=(ob-oa).cross(oc-oa)
    stats.append({'face':i,'vertices':list(f),'area_mm2':area*1e6,
                  'normal_dot_previous':normal.normalized().dot(old_normal.normalized()),
                  'view_facing':normal.normalized().dot(direction),
                  'centroid':list((a+b+c)/3),
                  'coordinates':[list(points[v]) for v in f],
                  'previous_coordinates':[list(old_points[v]) for v in f]})
intersections=[]
for pos,i in enumerate(local):
    f=faces[i];fi={ids[v] for v in f};a,b,c=[points[v] for v in f[:3]]
    for j in local[pos+1:]:
        g=faces[j]
        if fi.intersection(ids[v] for v in g):continue
        pa,pb,pc=[points[v] for v in g[:3]]
        if any(max(p[k] for p in (a,b,c))<min(p[k] for p in (pa,pb,pc))-1e-8 or max(p[k] for p in (pa,pb,pc))<min(p[k] for p in (a,b,c))-1e-8 for k in range(3)):continue
        collision=False
        for source_tri,target_tri in [((a,b,c),(pa,pb,pc)),((pa,pb,pc),(a,b,c))]:
            for start,end in zip(source_tri,source_tri[1:]+source_tri[:1]):
                ray=end-start;length=ray.length
                if length<1e-9:continue
                hit=intersect_ray_tri(*target_tri,ray.normalized(),start,True)
                if hit is not None:
                    distance=(hit-start).dot(ray.normalized())
                    if 1e-7<distance<length-1e-7:collision=True;break
            if collision:break
        if collision:intersections.append([i,j])
report={'status':'read_only_diagnosis','source_sha256':original,'source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==original,
        'target_pixel':[600,620],'center_hit':center_hit,'local_face_count':len(local),'pixel_rays':hits,
        'welded_boundary_or_nonmanifold_edges':boundaries,'triangle_stats':stats,
        'local_nonadjacent_triangle_intersections':intersections,
        'minimum_area_mm2':min(s['area_mm2'] for s in stats),
        'flipped_from_previous_faces':[s for s in stats if s['normal_dot_previous']<0],
        'backfacing_visible_rays':[h for h in hits if h['facing']<0]}
output=stage/'diagnostics/thumb_slit_02.json';output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(report,indent=2))
print('THUMB_SLIT_DIAGNOSIS',json.dumps({k:len(report[k]) if isinstance(report[k],list) else report[k] for k in ['local_face_count','minimum_area_mm2','welded_boundary_or_nonmanifold_edges','local_nonadjacent_triangle_intersections','flipped_from_previous_faces','backfacing_visible_rays']}),flush=True)
