"""Read-only full-cycle forelimb/thorax surface-intersection and shape QA.

Keeps both diagnosed masks unchanged. Exact nonadjacent segment/triangle
crossings complement (rather than replace) joint-direction and floor QA.
"""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri
sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import set_action,LIMBS
from labrador_pet_validate import coordinates,pose
from labrador_pet_locomotion_validate import rotation_vector
from labrador_sprint_surface_review import bind_data,fixed_masks

def exact_crossings(vectors,tri,fa,fb,tree_a):
    if not len(fa) or not len(fb):return 0
    tree_b=BVHTree.FromPolygons(vectors,[list(tri[i]) for i in fb],all_triangles=True)
    count=0
    for ia,ib in tree_a.overlap(tree_b):
        a,b=tri[fa[ia]],tri[fb[ib]]
        if set(a)&set(b):continue
        hits=[]
        for first,second in ((a,b),(b,a)):
            for j in range(3):
                origin=vectors[first[j]];direction=vectors[first[(j+1)%3]]-origin
                if direction.length<1e-8:continue
                point=intersect_ray_tri(vectors[second[0]],vectors[second[1]],vectors[second[2]],direction,origin,True)
                if point is not None:
                    t=(point-origin).dot(direction)/direction.length_squared
                    if .000001<t<.999999:hits.append(point)
        if len(hits)>=2 and max((a-b).length for a in hits for b in hits)>1e-5:count+=1
    return count

def area(world,tri):
    v=world[tri];return np.linalg.norm(np.cross(v[:,1]-v[:,0],v[:,2]-v[:,0]),axis=1)/2

def validate(base,key_only=False):
    path=base/'production/LabradorPet_SprintRepair.blend';bpy.ops.wm.open_mainfile(filepath=str(path))
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh'];mesh.data.calc_loop_triangles()
    tri=np.asarray([list(t.vertices) for t in mesh.data.loop_triangles],dtype=int)
    w=np.zeros((len(mesh.data.vertices),len(mesh.vertex_groups)))
    for v in mesh.data.vertices:
        for g in v.groups:w[v.index,g.group]=g.weight
    def region(prefixes):return w[:,[g.index for g in mesh.vertex_groups if g.name.startswith(prefixes)]].sum(axis=1)
    body_a=region(('Torso','Back_'));body_b=region(('Torso','Neck'))
    names=['FrontShoulder.L_18','FrontUpperLeg.L_17','FrontLowerLeg.L_16','FrontShoulder.R_21','FrontUpperLeg.R_20','FrontLowerLeg.R_19']
    regions={n:w[:,mesh.vertex_groups[n].index] for n in names}
    fa=np.flatnonzero(body_a[tri].mean(axis=1)>.55);fb=np.flatnonzero(body_b[tri].mean(axis=1)>.55)
    legs={n:np.flatnonzero(weights[tri].mean(axis=1)>.55) for n,weights in regions.items()}
    fore=region(('FrontUpperLeg','FrontLowerLeg'));combined=np.flatnonzero(fore[tri].mean(axis=1)>.55)
    proximal=region(('FrontUpperLeg','FrontShoulder'))
    mixed=np.flatnonzero((proximal[tri].mean(axis=1)>.12)&(body_a[tri].mean(axis=1)>.12))
    _,fixed_weights,group_names,_=bind_data(mesh);broad_masks,_=fixed_masks(tri,fixed_weights,group_names)
    set_action(rig,bpy.data.actions['IdleFriendly']);reference=pose(rig,1);neutral=coordinates(mesh);neutral_area=area(neutral,tri)
    set_action(rig,bpy.data.actions['Run']);rows=[];matrices=[]
    phases=np.arange(0,1+1e-6,1/(42 if key_only else 84))
    for phase in phases:
        p=pose(rig,1+phase*42);world=coordinates(mesh);vectors=[Vector(v) for v in world]
        tree_a=BVHTree.FromPolygons(vectors,[list(tri[i]) for i in fa],all_triangles=True)
        tree_b=BVHTree.FromPolygons(vectors,[list(tri[i]) for i in fb],all_triangles=True)
        hits={n:exact_crossings(vectors,tri,fa,faces,tree_a) for n,faces in legs.items()}
        hits_b=exact_crossings(vectors,tri,fb,combined,tree_b)
        broad_body=broad_masks['broader_body_head'];broad_tree=BVHTree.FromPolygons(vectors,[list(tri[i]) for i in broad_body],all_triangles=True)
        broad_hits={k:exact_crossings(vectors,tri,broad_body,broad_masks[k],broad_tree) for k in ('all_front.L','all_front.R','all_hind.L','all_hind.R')}
        ratio=area(world,tri)/np.maximum(neutral_area,1e-12)
        shape={n:{'minimum_area_ratio':float(ratio[faces].min()),'triangles_below_20pct_neutral_area':int((ratio[faces]<.2).sum())} for n,faces in legs.items() if len(faces)}
        tiny=mixed[ratio[mixed]<.2]
        mixed_shape={'minimum_area_ratio':float(ratio[mixed].min()),'triangles_below_20pct_neutral_area':int(len(tiny)),'compressed_triangle_ids':list(map(int,tiny)),'compressed_neutral_area_m2':float(neutral_area[tiny].sum()),'compressed_current_area_m2':float(area(world,tri)[tiny].sum())}
        joints={}
        for k in ('front.L','front.R'):
            l=LIMBS[k];a,b,c=[p[n].translation for n in l['chain']+[l['ankle']]]
            d=(c-a).length;l1=(reference[l['chain'][1]].translation-reference[l['chain'][0]].translation).length;l2=(reference[l['ankle']].translation-reference[l['chain'][1]].translation).length
            joints[k]={'elbow_above_shoulder_m':b.z-a.z,'humerus_rotation_from_neutral_deg':math.degrees(float(np.linalg.norm(rotation_vector(reference[l['chain'][0]],p[l['chain'][0]])))),'shoulder_to_wrist_m':d,'neutral_inner_limit_m':abs(l2-l1),'elbow_internal_angle_deg':math.degrees((a-b).angle(c-b))}
        rows.append({'phase':float(phase),'frame':float(1+phase*42),'mask_a_exact_crossings':hits,'mask_b_exact_crossings':hits_b,'broader_body_head_exact_crossings':broad_hits,'skin_shape':shape,'mixed_proximal_shape':mixed_shape,'joints':joints})
    maximum_a=max(sum(r['mask_a_exact_crossings'].values()) for r in rows);maximum_b=max(r['mask_b_exact_crossings'] for r in rows)
    maximum_broad={k:max(r['broader_body_head_exact_crossings'][k] for r in rows) for k in rows[0]['broader_body_head_exact_crossings']}
    report={'passed':maximum_a==0 and maximum_b==0 and max(maximum_broad.values())==0,'maximum_broader_body_head_exact_crossings':maximum_broad,'broader_masks':{k:{'triangles':len(broad_masks[k]),'original_id_sha256':hashlib.sha256(np.ascontiguousarray(broad_masks[k].astype(np.int32)).tobytes()).hexdigest()} for k in ['broader_body_head',*maximum_broad]},'production_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'samples':len(rows),'sampling_hz':60 if key_only else 120,'mask_a':{'body_triangles':len(fa),'leg_triangles':{n:len(v) for n,v in legs.items()},'unchanged':'Torso+Back vs each foreShoulder/Upper/Lower average weight>.55, excluding shared vertices.'},'mask_b':{'body_triangles':len(fb),'leg_triangles':len(combined),'unchanged':'Torso+Neck vs combined foreUpper/Lower average weight>.55, excluding shared vertices.'},'mixed_proximal_triangles':len(mixed),'maximum_exact_crossing_pairs_mask_a':maximum_a,'maximum_exact_crossing_pairs_mask_b':maximum_b,'maximum_elbow_above_shoulder_m':max(j['elbow_above_shoulder_m'] for r in rows for j in r['joints'].values()),'maximum_humerus_rotation_deg':max(j['humerus_rotation_from_neutral_deg'] for r in rows for j in r['joints'].values()),'maximum_mixed_triangles_below20pct':max(r['mixed_proximal_shape']['triangles_below_20pct_neutral_area'] for r in rows),'maximum_mixed_compressed_neutral_area_m2':max(r['mixed_proximal_shape']['compressed_neutral_area_m2'] for r in rows),'maximum_mixed_compressed_current_area_m2':max(r['mixed_proximal_shape']['compressed_current_area_m2'] for r in rows),'frames':rows,'limits':['Selected surface crossings are not all-mesh collisions or penetration volume.','Per-joint direction and region area metrics do not substitute for both-side rendered anatomy review.','A triangle area ratio below20% is a compression diagnostic; final judgement also uses its absolute area and visible shape, without changing this mask or threshold.']}
    (base/'sprint-repair-skin-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('SPRINT_REPAIR_SKIN',report['passed'],len(rows),maximum_a,maximum_b,report['maximum_elbow_above_shoulder_m'],report['maximum_humerus_rotation_deg'],flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',type=Path,required=True);p.add_argument('--key-only',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);validate(a.base.resolve(),a.key_only)
