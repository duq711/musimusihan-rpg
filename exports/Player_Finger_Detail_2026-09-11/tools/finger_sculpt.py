"""Local physical finger refinement; topology, UVs, rig and corrective deltas stay."""
import math
from mathutils import Vector
from mathutils.bvhtree import BVHTree

DIGITS=('thumb','index','middle','ring','little')

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3-2*t)

def weights(obj):
    names={g.index:g.name for g in obj.vertex_groups}
    return [{d:sum(g.weight for g in v.groups if names[g.group].startswith(d)) for d in DIGITS} for v in obj.data.vertices]

def section(points,faces,origin,axis):
    cross=axis.cross(Vector((0,0,1))).normalized();dorsal=cross.cross(axis).normalized();hits=[]
    for f in faces:
        for a,b in zip(f,f[1:]+f[:1]):
            pa,pb=points[a],points[b];da=(pa-origin).dot(axis);db=(pb-origin).dot(axis)
            if (da<0)!=(db<0):hits.append(pa+(pb-pa)*(da/(da-db)))
    assert hits
    u=[(p-origin).dot(cross) for p in hits];v=[(p-origin).dot(dorsal) for p in hits]
    center=origin+cross*(min(u)+max(u))*.5+dorsal*(min(v)+max(v))*.5
    return center,axis,dorsal,cross,(max(u)-min(u))*.5,(max(v)-min(v))*.5

def make_frames(holder,rig,skin):
    matrix=holder.matrix_world.inverted()@skin.matrix_world;points=[matrix@v.co for v in skin.data.vertices]
    own=weights(skin);physical=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<12036]
    native=holder.matrix_world.inverted()@rig.matrix_world;frames={}
    for d in DIGITS:
        subset=[f for f in physical if sum(own[i][d] for i in f)/len(f)>.6]
        frames[d]=[]
        for j in range(3):
            m=native@rig.data.bones[d+str(j)].matrix_local
            frames[d].append(section(points,subset,m.translation,m.to_3x3().col[1].normalized()))
    return frames

def geometric_normals(mesh,points):
    values=[Vector() for p in points]
    for p in mesh.polygons:
        f=list(p.vertices);a=points[f[0]]
        for j in range(1,len(f)-1):
            n=(points[f[j]]-a).cross(points[f[j+1]]-a)
            for i in (f[0],f[j],f[j+1]):values[i]+=n
    return [v.normalized() for v in values]

def sculpt_hand(hand,strength=1.0):
    holder,rig,skin=hand['holder'],hand['rig'],hand['skin'];mesh=skin.data
    transform=holder.matrix_world.inverted()@skin.matrix_world;inverse=transform.inverted()
    points=[transform@v.co for v in mesh.vertices];own=weights(skin);frames=make_frames(holder,rig,skin)
    old_custom=[n.vector.copy() for n in mesh.corner_normals]
    normal_matrix=transform.to_3x3().inverted().transposed()
    normals=[(normal_matrix@v.normal).normalized() for v in mesh.vertices]
    eligible=set();protected=set()
    for polygon in mesh.polygons:
        role=mesh.materials[polygon.material_index].name
        (eligible if role=='Detailed_Skin' else protected).update(polygon.vertices)
    eligible-=protected
    nails=[o for o in hand['objects'] if o.type=='MESH' and 'Nail_' in o.name]
    np,nf=[],[]
    for nail in nails:
        offset=len(np);matrix=holder.matrix_world.inverted()@nail.matrix_world
        np.extend(matrix@v.co for v in nail.data.vertices);nf.extend([offset+i for i in p.vertices] for p in nail.data.polygons)
    nailtree=BVHTree.FromPolygons(np,nf)
    boundary=list(protected.intersection(range(12036)));boundarytree=None
    from mathutils.kdtree import KDTree
    boundarytree=KDTree(len(boundary))
    for i,k in enumerate(boundary):boundarytree.insert(points[k],i)
    boundarytree.balance()
    new=[p.copy() for p in points];changed={d:[] for d in DIGITS};maximum=0.
    tip_extents={d:max((p-frames[d][2][0]).dot(frames[d][2][1]) for p,w in zip(points[:12036],own[:12036]) if w[d]>.95) for d in DIGITS}
    for i in sorted(eligible):
        if i>=12036:continue
        d=max(DIGITS,key=lambda d:own[i][d]);dominance=own[i][d]
        if dominance<.8:continue
        p=points[i];n=normals[i];amount=0.
        for j in ((2,) if d=='thumb' else (1,2)):
            center,axis,dorsal,cross,rx,rz=frames[d][j];offset=p-center;v=offset.dot(axis);u=offset.dot(cross)
            outer=max(0,n.dot(dorsal))**2;inner=max(0,-n.dot(dorsal))**2;side=max(0,1-abs(n.dot(dorsal)))**2
            region=math.exp(-((offset-axis*v).length/(max(rx,rz)*1.35))**6)
            scale=1. if j==1 else .65
            # Soft condyles and a shallow collar, not a rigid ring around the finger.
            bulge=math.exp(-(v/.0044)**2)*(.00074*outer+.00038*side)
            crease=math.exp(-((v+.0008+.0012*(u/max(rx,.001))**2)/.0011)**2)
            amount+=region*scale*(bulge-.00027*crease*inner)
        if d!='thumb':
            a=frames[d][1][0];b=frames[d][2][0];axis=(b-a).normalized();offset=p-(a+b)*.5
            radial=(offset-axis*offset.dot(axis));r=radial.length
            if r>1e-6:
                side=abs(n.dot(frames[d][1][3]))**2
                amount-=.00025*side*math.exp(-(offset.dot(axis)/.0065)**2)
        center,axis,dorsal,cross,rx,rz=frames[d][2];offset=p-center;v=offset.dot(axis)
        tip=tip_extents[d]
        pad=math.exp(-((v-tip*.62)/max(tip*.31,.003))**2)*max(0,-n.dot(dorsal))**2
        amount+=.00052*pad
        nail_distance=nailtree.find_nearest(p)[3]
        edge_distance=boundarytree.find(p)[2]
        guard=smooth(.0012,.0042,nail_distance)*smooth(.0009,.0034,edge_distance)*smooth(.8,.99,dominance)
        amount*=guard*strength;amount=max(-.00085,min(.00085,amount))
        if abs(amount)>1e-8:
            new[i]=p+n*amount;changed[d].append(i);maximum=max(maximum,abs(amount))
    # Authored skin has a few geometrically coincident, topologically split seams.
    # Use one displacement for each sub-micron group, retaining its original gap,
    # UV split and indices. Different vertex normals must not pull a seam apart.
    seam_tree=KDTree(12036)
    for i,p in enumerate(points[:12036]):seam_tree.insert(p,i)
    seam_tree.balance();seam_groups=[];seen=set()
    for i,p in enumerate(points[:12036]):
        if i in seen:continue
        group={j for _,j,_ in seam_tree.find_range(p,.000001)}
        if len(group)<2:continue
        frontier=list(group)
        while frontier:
            j=frontier.pop()
            for _,k,_ in seam_tree.find_range(points[j],.000001):
                if k not in group:group.add(k);frontier.append(k)
        seen.update(group)
        delta=sum((new[j]-points[j] for j in group),Vector())/len(group)
        if any(j not in eligible or (new[j]-points[j]).length<1e-8 for j in group):delta=Vector()
        for j in group:new[j]=points[j]+delta
        seam_groups.append(sorted(group))
    changed={d:[] for d in DIGITS};maximum=0.
    for i,(old,current) in enumerate(zip(points,new)):
        distance=(current-old).length
        if distance>1e-8:
            changed[max(DIGITS,key=lambda d:own[i][d])].append(i);maximum=max(maximum,distance)
    old_local=[v.co.copy() for v in mesh.vertices];new_local=[inverse@p for p in new]
    moved={i for indices in changed.values() for i in indices}
    old_geo=geometric_normals(mesh,old_local);new_geo=geometric_normals(mesh,new_local)
    for i in moved:
        delta=new_local[i]-old_local[i]
        for key in mesh.shape_keys.key_blocks:key.data[i].co+=delta
        mesh.vertices[i].co=mesh.shape_keys.key_blocks[0].data[i].co
    mesh.update();custom=[]
    for loop,n in zip(mesh.loops,old_custom):
        i=loop.vertex_index
        if i in moved and old_geo[i].length>.5 and new_geo[i].length>.5:n=old_geo[i].rotation_difference(new_geo[i])@n
        custom.append(n.normalized())
    mesh.normals_split_custom_set(custom)
    return {'changed_by_digit':{d:len(v) for d,v in changed.items()},'changed_vertex_indices':sorted(moved),
        'maximum_displacement_m':maximum,'maximum_allowed_m':.00085,'strength':strength,
        'submicron_seam_groups_shared_displacement':seam_groups,
        'scope':'Only original exposed skin vertices. Original glove, trim, nails, wrist, rig, topology and UV retained.',
        'corrective_method':'Same local Basis offset added to all fifteen relative keys; original correction vectors preserved.',
        'landmarks':{d:[{'center':list(f[0]),'axis':list(f[1]),'dorsal':list(f[2]),'cross':list(f[3]),'radius_x':f[4],'radius_z':f[5]} for f in fs] for d,fs in frames.items()}}

def reposition_thumb_nail(hand):
    """Fit the thumb nail's footprint to the actual distal tip, per user correction."""
    holder,rig,skin=hand['holder'],hand['rig'],hand['skin'];own=weights(skin)
    matrix=holder.matrix_world.inverted()@skin.matrix_world;points=[matrix@v.co for v in skin.data.vertices]
    rm=holder.matrix_world.inverted()@rig.matrix_world
    axis=(rm.to_3x3()@rig.data.bones['thumb2'].matrix_local.to_3x3().col[1]).normalized()
    cross=axis.cross(Vector((0,0,1))).normalized()
    nail=next(o for o in hand['objects'] if o.type=='MESH' and o.name.startswith('Nail_thumb'))
    nm=holder.matrix_world.inverted()@nail.matrix_world;inverse=nm.inverted();old=[nm@v.co for v in nail.data.vertices]
    lo=min(p.dot(axis) for p in old);hi=max(p.dot(axis) for p in old)
    tip=max(p.dot(axis) for p,w in zip(points[:12036],own[:12036]) if w['thumb']>.95)
    scale=.74
    faces=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<12036 and sum(own[i]['thumb'] for i in p.vertices)/len(p.vertices)>.6]
    old_cross=(min(p.dot(cross) for p in old)+max(p.dot(cross) for p in old))*.5
    dorsal=(Vector((0,0,1))-axis*axis.z).normalized();tree=BVHTree.FromPolygons(points,faces)
    new=[]
    for attempt in range(14):
        margin=.0019+attempt*.0004;target_max=tip-margin;target_mid=target_max-(hi-lo)*scale*.5
        center,*unused=section(points,faces,axis*target_mid,axis)
        cross_shift=center.dot(cross)-old_cross
        assert abs(cross_shift)<.004
        new=[p+axis*(target_max-(hi-p.dot(axis))*scale-p.dot(axis))+cross*cross_shift for p in old]
        if all(tree.ray_cast(p+dorsal*.035,-dorsal,.075)[0] is not None for p in new[:161]):break
    else:raise AssertionError('Thumb footprint does not fit actual skin silhouette')
    old_custom=[n.vector.copy() for n in nail.data.corner_normals]
    old_geo=geometric_normals(nail.data,[v.co.copy() for v in nail.data.vertices]);new_local=[inverse@p for p in new]
    new_geo=geometric_normals(nail.data,new_local)
    for v,p in zip(nail.data.vertices,new_local):v.co=p
    nail.data.update()
    nail.data.normals_split_custom_set([(old_geo[l.vertex_index].rotation_difference(new_geo[l.vertex_index])@n).normalized() for l,n in zip(nail.data.loops,old_custom)])
    return {'reason':'User identified low, elongated thumb nail placement.','axial_length_scale':scale,'source_length_m':hi-lo,'target_length_m':(hi-lo)*scale,'source_tip_margin_m':tip-hi,'target_tip_margin_m':margin,'lateral_center_shift_m':cross_shift,'method':'Shorten footprint from proximal side, place as close to tip as the actual skin ray footprint permits, and center across actual skin section; seat on skin in following step.'}

def fit_nail_surfaces(hand):
    """Resolve inherited skin-through-nail patches without widening nail outlines."""
    holder,rig,skin=hand['holder'],hand['rig'],hand['skin'];own=weights(skin)
    sm=holder.matrix_world.inverted()@skin.matrix_world
    points=[sm@v.co for v in skin.data.vertices];rm=holder.matrix_world.inverted()@rig.matrix_world
    rows={}
    for digit in DIGITS:
        nail=next(o for o in hand['objects'] if o.type=='MESH' and o.name.startswith('Nail_'+digit))
        mesh=nail.data;assert len(mesh.vertices)==322
        matrix=holder.matrix_world.inverted()@nail.matrix_world;inverse=matrix.inverted()
        old=[matrix@v.co for v in mesh.vertices];current=[p.copy() for p in old]
        axis=(rm.to_3x3()@rig.data.bones[digit+'2'].matrix_local.to_3x3().col[1]).normalized()
        dorsal=(Vector((0,0,1))-axis*axis.z).normalized()
        faces=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<12036 and sum(own[i][digit] for i in p.vertices)/len(p.vertices)>.45]
        tree=BVHTree.FromPolygons(points,faces)
        mesh.calc_loop_triangles();top=[list(t.vertices) for t in mesh.loop_triangles if max(t.vertices)<161]
        old_custom=[n.vector.copy() for n in mesh.corner_normals];shifts=[0.]*161
        def clearance(point):
            hit=tree.ray_cast(point+dorsal*.035,-dorsal,.075)
            assert hit[0] is not None,(digit,'Nail misses original fingertip')
            return (point-hit[0]).dot(dorsal)
        minimum_before=min(clearance(sum((old[i] for i in f),Vector())/3) for f in top)
        # Top ring layout: center0, five 32-vertex rings1..160; bottom index+161.
        # Preserve the in-plane position of every point; only raise along dorsal.
        for i in range(161):
            gap=.00014-clearance(old[i])
            shifts[i]=gap if digit=='thumb' else max(0.,gap)
        thumb_profile=None
        if digit=='thumb':
            # A low-order curved plate follows the fingertip envelope without
            # copying local dents from individual underlying skin vertices.
            import numpy as np
            cross=axis.cross(dorsal).normalized();center=sum(old[:161],Vector())/161
            uv=[((p-center).dot(cross),(p-center).dot(axis)) for p in old[:161]]
            design=np.asarray([[1.,u,v,u*u,u*v,v*v] for u,v in uv])
            needed=np.asarray(shifts);coef=np.linalg.lstsq(design,needed,rcond=None)[0]
            fitted=design@coef;extra=max(0.,float(np.max(needed-fitted)))
            # A globally lifted fit floated above the curved sidewall. Bound
            # smoothing to 0.22mm above the actual bed at each plate vertex.
            shifts=np.maximum(needed,np.minimum(fitted+extra,needed+.00022)).tolist()
            thumb_profile={'method':'Quadratic smoothing constrained to the actual nail bed plus at most 0.22mm; no global floating envelope.','coefficients':coef.tolist(),'maximum_vertex_gap_m':float(np.max(np.asarray(shifts)-needed+.00014))}
        bary=((1/3,1/3,1/3),(.6,.2,.2),(.2,.6,.2),(.2,.2,.6))
        for iteration in range(12):
            needed=[0.]*161;worst=1.
            for f in top:
                for w in bary:
                    point=sum(((old[i]+dorsal*shifts[i])*a for i,a in zip(f,w)),Vector())
                    gap=clearance(point);worst=min(worst,gap)
                    if gap<.00010:
                        for i in f:needed[i]=max(needed[i],(.00012-gap)*1.03)
            if worst>=.00010:break
            for i in range(161):shifts[i]+=needed[i]
        allowed=.009 if digit=='thumb' else .00060
        assert max(abs(x) for x in shifts)<=allowed,(digit,'Nail seating offset too large',max(shifts))
        for i,shift in enumerate(shifts):
            current[i]=old[i]+dorsal*shift;current[i+161]=old[i+161]+dorsal*shift
        old_local=[v.co.copy() for v in mesh.vertices];new_local=[inverse@p for p in current]
        old_geo=geometric_normals(mesh,old_local);new_geo=geometric_normals(mesh,new_local)
        for v,p in zip(mesh.vertices,new_local):v.co=p
        mesh.update();custom=[]
        for loop,n in zip(mesh.loops,old_custom):
            i=loop.vertex_index
            if digit=='thumb':n=new_geo[i]
            elif old_geo[i].length>.5 and new_geo[i].length>.5:n=old_geo[i].rotation_difference(new_geo[i])@n
            custom.append(n.normalized())
        mesh.normals_split_custom_set(custom)
        rows[digit]={'object':nail.name,'top_count':161,'paired_bottom_offset':161,
            'outward_direction_native':list(dorsal),'distal_axis_native':list(axis),
            'method':'Native +Z projected perpendicular to distal bone axis; paired top/bottom equal outward-only shift; axial and cross-plane coordinates retained.',
            'maximum_lift_m':max(shifts),'minimum_lift_m':min(shifts),'allowed_maximum_m':allowed,'changed_top_vertices':sum(abs(x)>1e-8 for x in shifts),
            'minimum_centroid_clearance_before_m':minimum_before,'minimum_sample_clearance_after_m':min(clearance(sum((current[i]*w for i,w in zip(f,weights)),Vector())) for f in top for weights in bary),
            'topology_uv_rigid_weights_unchanged':True}
        if thumb_profile:rows[digit]['smooth_cap_profile']=thumb_profile
    return rows
