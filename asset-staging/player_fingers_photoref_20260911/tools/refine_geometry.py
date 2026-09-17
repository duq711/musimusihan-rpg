"""Smooth the physical finger surface and sculpt a thin continuous nail bed."""
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
from finger_sculpt import weights,geometric_normals,smooth

DIGITS=('thumb','index','middle','ring','little')
def nail_frame(hand,nail):
    rm=hand['holder'].matrix_world.inverted()@hand['rig'].matrix_world
    digit=next(d for d in DIGITS if nail.name.startswith('Nail_'+d))
    axis=(rm.to_3x3()@hand['rig'].data.bones[digit+'2'].matrix_local.to_3x3().col[1]).normalized()
    matrix=hand['holder'].matrix_world.inverted()@nail.matrix_world
    points=[matrix@v.co for v in nail.data.vertices];nail.data.calc_loop_triangles()
    faces=[list(t.vertices) for t in nail.data.loop_triangles if max(t.vertices)<161]
    normal=sum(((points[f[1]]-points[f[0]]).cross(points[f[2]]-points[f[0]]) for f in faces),Vector()).normalized()
    dorsal=(normal-axis*normal.dot(axis)).normalized();cross=axis.cross(dorsal).normalized()
    return digit,matrix,points,faces,axis,dorsal,cross

def refine(hand,cap_strength=1.):
    holder,skin,rig=hand['holder'],hand['skin'],hand['rig'];mesh=skin.data
    sm=holder.matrix_world.inverted()@skin.matrix_world;inv=sm.inverted();points=[sm@v.co for v in mesh.vertices]
    oldlocal=[v.co.copy() for v in mesh.vertices];custom=[n.vector.copy() for n in mesh.corner_normals];own=weights(skin)
    eligible=set();protected=set()
    for p in mesh.polygons:(eligible if mesh.materials[p.material_index].name=='Detailed_Skin' else protected).update(p.vertices)
    eligible={i for i in eligible-protected if i<12036 and max(own[i].values())>.95}
    nails=[o for o in hand['objects'] if o.type=='MESH' and o.name.startswith('Nail_')]
    nailpoints=[];nailfaces=[]
    for nail in nails:
        _,_,p,faces,*_=nail_frame(hand,nail);offset=len(nailpoints)
        nailpoints.extend(p);nailfaces.extend([[offset+i for i in f] for f in faces])
    allnails=BVHTree.FromPolygons(nailpoints,nailfaces,all_triangles=True)
    smoothing=[smooth(.002,.005,allnails.find_nearest(p)[3]) for p in points[:12036]]
    kd=KDTree(12036)
    for i,p in enumerate(points[:12036]):kd.insert(p,i)
    kd.balance();groups=[];seen=set();which={}
    for i,p in enumerate(points[:12036]):
        if i in seen:continue
        group={j for _,j,_ in kd.find_range(p,.000001)};todo=list(group)
        while todo:
            j=todo.pop()
            for _,k,_ in kd.find_range(points[j],.000001):
                if k not in group:group.add(k);todo.append(k)
        seen.update(group);groups.append(sorted(group))
        for j in group:which[j]=len(groups)-1
    neighbor=[set() for g in groups]
    for edge in mesh.edges:
        a,b=edge.vertices
        if max(a,b)>=12036:continue
        a,b=which[a],which[b]
        if a!=b:neighbor[a].add(b);neighbor[b].add(a)
    centers=[sum((points[j] for j in g),Vector())/len(g) for g in groups]
    current=[p.copy() for p in centers]
    for step in range(8):
        factor=.34 if step%2==0 else -.35;updated=[p.copy() for p in current]
        for i,g in enumerate(groups):
            if not neighbor[i] or any(j not in eligible for j in g):continue
            average=sum((current[j] for j in neighbor[i]),Vector())/len(neighbor[i])
            delta=(average-current[i])*factor*min(smoothing[j] for j in g)
            candidate=current[i]+delta;total=candidate-centers[i]
            if total.length>.00048:candidate=centers[i]+total.normalized()*.00048
            updated[i]=candidate
        current=updated
    new=[p.copy() for p in points]
    for c,old,g in zip(current,centers,groups):
        for i in g:new[i]=points[i]+c-old
    # Smooth all exposed skin normals across the authored UV seams. Their UVs
    # remain separate, but coincident surface vertices share the same shading.
    report={'nails':{}};rm=holder.matrix_world.inverted()@rig.matrix_world
    for nail in nails:
        digit,nm,np0,faces,axis,dorsal,cross=nail_frame(hand,nail)
        center=sum(np0[:161],Vector())/161
        # Make a single smooth cap rather than following every dent in the bed.
        u=np.asarray([(p-center).dot(cross) for p in np0[:161]]);v=np.asarray([(p-center).dot(axis) for p in np0[:161]]);z=np.asarray([(p-center).dot(dorsal) for p in np0[:161]])
        rx=float(abs(u).max());ry=float(abs(v).max());un,vn=u/rx,v/ry
        order=3 if digit=='thumb' else 2;powers=[(i,j) for i in range(order+1) for j in range(order+1-i)]
        design=np.asarray([un**i*vn**j for i,j in powers]).T;coef=np.linalg.lstsq(design,z,rcond=None)[0]
        fitted=design@coef;delta=(fitted-z)*cap_strength
        assert float(abs(delta).max())<.0018,(digit,'Cap smoothing displacement',float(abs(delta).max()))
        ntop=[p+dorsal*float(d) for p,d in zip(np0[:161],delta)]
        oldtree=BVHTree.FromPolygons(np0,faces,all_triangles=True)
        newtree=BVHTree.FromPolygons(ntop,faces,all_triangles=True)
        nailbed=[]
        for i in sorted(eligible):
            if own[i][digit]<.95:continue
            p=new[i];nearest=oldtree.find_nearest(p);dist=nearest[3]
            if dist>.0032:continue
            # Delta at the closest old cap surface interpolates the cap motion
            # continuously beyond its border and prevents detached plate edges.
            point=nearest[0];oldhit=oldtree.ray_cast(point+dorsal*.03,-dorsal,.06)[0];newhit=newtree.ray_cast(point+dorsal*.03,-dorsal,.06)[0]
            if oldhit is None or newhit is None:continue
            lift=(newhit-oldhit).dot(dorsal)
            if (p-point).dot(dorsal)<-.003:continue
            fade=1.-smooth(.0012,.0032,dist)
            amount=lift*fade
            new[i]+=dorsal*amount
            if abs(amount)>1e-8:nailbed.append(i)
        # Preserve each original thin shell vector; top and bottom receive the
        # same smooth displacement, keeping the free edge a thin curved plate.
        nnew=[p.copy() for p in np0]
        for i in range(161):nnew[i]=ntop[i];nnew[i+161]=np0[i+161]+dorsal*float(delta[i])
        report['nails'][digit]={'cap_order':order,'cap_fit_maximum_m':float(abs(delta).max()),'cap_fit_rms_m':float(np.sqrt(np.mean(delta**2))),'bed_vertices':len(nailbed),'dorsal_native':list(dorsal),'axis_native':list(axis),'footprint_and_shell_vectors_preserved':True}
        nail['_photoref_frame_dorsal']=list(dorsal)
        for vertex,p in zip(nail.data.vertices,nnew):vertex.co=nm.inverted()@p
        nail.data.update();geo=geometric_normals(nail.data,[v.co.copy() for v in nail.data.vertices]);nail.data.normals_split_custom_set([geo[l.vertex_index] for l in nail.data.loops])
    # Unify displacement across original submicron seams without welding indices.
    for group in groups:
        if len(group)<2:continue
        delta=sum((new[i]-points[i] for i in group),Vector())/len(group)
        if any(i not in eligible for i in group):delta=Vector()
        for i in group:new[i]=points[i]+delta
    for i in eligible:
        delta=inv@new[i]-oldlocal[i]
        if delta.length<1e-10:continue
        for key in mesh.shape_keys.key_blocks:key.data[i].co+=delta
        mesh.vertices[i].co=mesh.shape_keys.key_blocks[0].data[i].co
    mesh.update()
    # Re-seat each smooth cap with a small uniform lift. This keeps the cap
    # smooth instead of stamping the skin's triangulation back onto its plate.
    skinpoints=[sm@v.co for v in mesh.vertices]
    for nail in nails:
        digit,nm,np0,top,axis,dorsal,cross=nail_frame(hand,nail);dorsal=Vector(nail['_photoref_frame_dorsal'])
        faces=[list(p.vertices) for p in mesh.polygons if max(p.vertices)<12036 and sum(own[i][digit] for i in p.vertices)/len(p.vertices)>.45]
        tree=BVHTree.FromPolygons(skinpoints,faces);gaps=[]
        actual_normal=sum(((np0[f[1]]-np0[f[0]]).cross(np0[f[2]]-np0[f[0]]) for f in top),Vector()).normalized()
        bary=((1/3,1/3,1/3),(.6,.2,.2),(.2,.6,.2),(.2,.2,.6))
        for f in top:
            for w in bary:
                p=sum((np0[i]*a for i,a in zip(f,w)),Vector());hit=tree.ray_cast(p+actual_normal*.03,-actual_normal,.06)[0]
                assert hit is not None,(digit,'Missing new nail bed')
                gaps.append((p-hit).dot(actual_normal))
        lift=max(0.,.00009-min(gaps))/actual_normal.dot(dorsal);assert lift<.0007,(digit,'Nail requires excess global lift',lift)
        for vertex in nail.data.vertices:vertex.co+=nm.inverted().to_3x3()@dorsal*lift
        nail.data.update();report['nails'][digit]['uniform_seating_lift_m']=lift;report['nails'][digit]['minimum_sample_clearance_m']=min(gaps)+lift
        del nail['_photoref_frame_dorsal']
    geo=geometric_normals(mesh,[v.co.copy() for v in mesh.vertices]);normals=geo[:]
    for group in groups:
        if any(i in eligible for i in group):
            normal=sum((geo[i] for i in group),Vector()).normalized()
            for i in group:normals[i]=normal
    mesh.normals_split_custom_set([normals[l.vertex_index] if l.vertex_index in eligible else old for l,old in zip(mesh.loops,custom)])
    distances=[(sm@v.co-p).length for v,p in zip(mesh.vertices,points)]
    report.update({'maximum_skin_displacement_m':max(distances),'moved_skin_vertices':sum(x>1e-8 for x in distances),'new_normals':'Area weighted geometric normals shared at original UV seams on exposed fingers only.','correctives':'Same Basis displacement applied to all original relative keys.'})
    return report
