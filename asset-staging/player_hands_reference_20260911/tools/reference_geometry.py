"""Reference-led bare-hand shape reconstruction; preserves named rig/pivot semantics."""
import math

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

DIGITS=('thumb','index','middle','ring','little')
PHYSICAL=12036


def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)))
    return t*t*(3.-2.*t)


def gauss(x,y,cx,cy,rx,ry):
    return math.exp(-(((x-cx)/rx)**2+((y-cy)/ry)**2))


def descendants(obj):
    result=[]
    for child in obj.children:
        result.append(child);result.extend(descendants(child))
    return result


def bounds(points):
    return [[min(p[k] for p in points),max(p[k] for p in points)] for k in range(3)]


def frame(rig,holder,name):
    m=holder.matrix_world.inverted()@rig.matrix_world@rig.data.bones[name].matrix_local
    return m.translation,m.to_3x3().col[1].normalized(),m.to_3x3().col[0].normalized(),m.to_3x3().col[2].normalized()


def section_center(points,faces,origin,axis,cross,dorsal):
    hits=[]
    for f in faces:
        for a,b in zip(f,f[1:]+f[:1]):
            pa,pb=points[a],points[b];da=(pa-origin).dot(axis);db=(pb-origin).dot(axis)
            if (da<0)!=(db<0):hits.append(pa+(pb-pa)*(da/(da-db)))
    if not hits:return origin.copy(),None
    xs=sorted((p-origin).dot(cross) for p in hits);zs=sorted((p-origin).dot(dorsal) for p in hits)
    # Boundary extrema describe an actual surface section, not a deep bone axis.
    center=origin+cross*(xs[0]+xs[-1])*.5+dorsal*(zs[0]+zs[-1])*.5
    return center,{'width_mm':(xs[-1]-xs[0])*1000,'thickness_mm':(zs[-1]-zs[0])*1000}


def interpolate(knots,t):
    if t<=knots[0][0]:return knots[0][1]
    for (a,x),(b,y) in zip(knots,knots[1:]):
        if t<=b:
            return x+(y-x)*smooth(a,b,t)
    return knots[-1][1]


def radial_profile(tree,y,count=128):
    radii=[]
    for j in range(count):
        angle=math.tau*j/count;direction=Vector((math.cos(angle),0,math.sin(angle)))
        center=Vector((0,y,0))
        hit=tree.ray_cast(center+direction*.16,-direction,.32)
        assert hit[0] is not None,'Missing wrist radial section'
        radii.append((hit[0]-center).dot(direction))
    return radii


def angular_radius(profile,direction):
    u=(math.atan2(direction.z,direction.x)%math.tau)/math.tau*len(profile)
    i=int(u)%len(profile);t=u%1
    return profile[i]*(1-t)+profile[(i+1)%len(profile)]*t


def soften_transition_arrays(arrays,faces,original_points,mask,iterations=5):
    """Identical localized linear surface operator for Basis and all 15 keys."""
    # UV-split source coordinates can differ by a fraction of a micron. Rounded
    # grid keys split pairs that straddle a cell boundary and opened a 0.7 mm
    # thumb slit under relaxation. Group by actual distance, not grid address.
    tree=KDTree(len(original_points));parents=list(range(len(original_points)))
    for i,p in enumerate(original_points):tree.insert(p,i)
    tree.balance()
    def root(index):
        while parents[index]!=index:
            parents[index]=parents[parents[index]];index=parents[index]
        return index
    for i,p in enumerate(original_points):
        for unused,j,distance in tree.find_range(p,1e-6):
            a,b=root(i),root(j)
            if a!=b:parents[max(a,b)]=min(a,b)
    groups={};canonical=[]
    for i in range(len(original_points)):groups.setdefault(root(i),[]).append(i)
    members=list(groups.values())
    for unused in original_points:canonical.append(0)
    for group,indices in enumerate(members):
        for index in indices:canonical[index]=group
    neighbors=[set() for unused in members]
    for f in faces:
        for a,b in zip(f,f[1:]+f[:1]):
            a,b=canonical[a],canonical[b]
            if a!=b:neighbors[a].add(b);neighbors[b].add(a)
    strengths=[max(mask[i] for i in indices)*.34 for indices in members]
    active=[i for i,s in enumerate(strengths) if s>1e-4 and neighbors[i]]
    active_set=set(active)
    for positions in arrays:
        values=[sum((positions[i] for i in indices),Vector())/len(indices) for indices in members]
        for unused in range(iterations):
            updated=list(values)
            for i in active:
                average=sum((values[j] for j in neighbors[i]),Vector())/len(neighbors[i])
                updated[i]=values[i].lerp(average,strengths[i])
            values=updated
        for i,indices in enumerate(members):
            if i in active_set or len(indices)>1:
                for index in indices:positions[index]=values[i].copy()
    return len(active)


def make_skin(skin,points,faces,weights,keys):
    old=skin.data
    group_names=[group.name for group in skin.vertex_groups]
    material=bpy.data.materials.get('Detailed_Skin')
    assert material is not None
    mesh=bpy.data.meshes.new(old.name+'_BareReference')
    mesh.from_pydata(points,[],faces);mesh.materials.append(material);mesh.update()
    skin.data=mesh
    # Blender 5.2 binds deform-group definitions to the mesh data. Assigning a
    # new mesh can clear the object's group list, so reconstruct its exact order.
    for group in list(skin.vertex_groups):skin.vertex_groups.remove(group)
    for name in group_names:skin.vertex_groups.new(name=name)
    for polygon in mesh.polygons:polygon.use_smooth=True
    for index,groups in enumerate(weights):
        for group,weight in groups:
            skin.vertex_groups[group].add([index],weight,'REPLACE')
    for name,positions in keys:
        key=skin.shape_key_add(name=name,from_mix=False)
        for v,p in zip(key.data,positions):v.co=p
        key.value=0.
    mesh.update()
    # The imported anatomical mesh includes UV-split coincident vertices. Keep
    # their surface shading continuous after the large silhouette deformation.
    shared={}
    for vertex in mesh.vertices:
        position=tuple(round(float(c),6) for c in vertex.co)
        shared.setdefault(position,Vector())
        shared[position]+=vertex.normal
    normals=[shared[tuple(round(float(c),6) for c in vertex.co)].normalized() for vertex in mesh.vertices]
    mesh.normals_split_custom_set_from_vertices(normals)
    skin['reference_bare_skin']=True
    skin['reference_physical_vertex_count']=PHYSICAL
    return mesh


def nail_plate(nail,skin,rig,holder,digit,points,faces,digit_weight):
    base,axis,cross,dorsal=frame(rig,holder,digit+'2')
    subset=[f for f in faces if all(digit_weight[i]>.25 for i in f)]
    tree=BVHTree.FromPolygons(points,subset,all_triangles=False)
    owned=[p for i,p in enumerate(points) if digit_weight[i]>.6]
    distal=max((p-base).dot(axis) for p in owned)
    center=base+axis*distal*.62
    center,dimensions=section_center(points,subset,center,axis,cross,dorsal)
    assert dimensions is not None,'Missing distal section for '+digit
    length=distal*(.445 if digit=='thumb' else (.42 if digit=='little' else .50))
    width=dimensions['width_mm']*.001*(.78 if digit=='thumb' else .75)
    segments=64;radial_rings=12
    # A sparse three-ring quad cap pierced the skin between its projected
    # vertices. Keep the footprint but resolve curvature with explicit triangles.
    for attempt in range(7):
        top=[];missing=0
        samples=[(0.,0.,0.)]
        for ring in range(1,radial_rings+1):
            radial=ring/radial_rings
            for j in range(segments):
                angle=2*math.pi*j/segments
                u=math.copysign(abs(math.cos(angle))**(2/2.65),math.cos(angle))*width*.5*radial
                v=math.copysign(abs(math.sin(angle))**(2/2.65),math.sin(angle))*length*.5*radial
                samples.append((u,v,radial))
        for u,v,radial in samples:
            target=center+cross*u+axis*v
            hit=tree.ray_cast(target+dorsal*.08,-dorsal,.16)
            if hit[0] is None:missing+=1;top.append(target)
            else:top.append(hit[0]+dorsal*(.00010+.00015*(1-radial**2)))
        if not missing:break
        width*=.91;length*=.96
    assert not missing,'Nail projection misses '+digit
    top_polygons=[]
    for j in range(segments):top_polygons.append((0,1+j,1+(j+1)%segments))
    for ring in range(radial_rings-1):
        a=1+ring*segments;b=a+segments
        for j in range(segments):
            n=(j+1)%segments
            top_polygons.extend(((a+j,b+j,b+n),(a+j,b+n,a+n)))
    # Test vertices, triangle centroids, edge midpoints, and interior witnesses.
    # Only local outward lifts are allowed; no skin or bind weights are edited.
    barycentrics=((1/3,1/3,1/3),(.5,.5,0.),(.5,0.,.5),(0.,.5,.5),
                  (.6,.2,.2),(.2,.6,.2),(.2,.2,.6))
    original_top=[p.copy() for p in top]
    def clearance(point):
        hit=tree.ray_cast(point+dorsal*.04,-dorsal,.08)
        assert hit[0] is not None,'Nail witness lacks supporting skin '+digit
        return (point-hit[0]).dot(dorsal)
    for fit_iteration in range(8):
        lifts=[0.]*len(top)
        for ids in top_polygons:
            for bary in barycentrics:
                point=sum((top[i]*w for i,w in zip(ids,bary)),Vector())
                amount=.000055-clearance(point)
                if amount>0:
                    for i in ids:lifts[i]=max(lifts[i],amount)
        if max(lifts)<1e-7:break
        for i,lift in enumerate(lifts):top[i]+=dorsal*lift
    signed=[clearance(p) for p in top]
    signed.extend(clearance(sum((top[i]*w for i,w in zip(ids,bary)),Vector()))
                  for ids in top_polygons for bary in barycentrics)
    assert min(signed)>=-.000001 and max(signed)<.0008,'Nail surface fit out of range '+digit
    count=len(top);bottom=[p-dorsal*.00013 for p in top]
    polygons=list(top_polygons)
    polygons.extend(tuple(i+count for i in reversed(f)) for f in top_polygons)
    edge=1+(radial_rings-1)*segments
    for j in range(segments):
        a=edge+j;b=edge+(j+1)%segments
        polygons.append((a,a+count,b+count,b))
    native_to_local=nail.matrix_world.inverted()@holder.matrix_world
    mesh=bpy.data.meshes.new('Reference_Nail_'+digit)
    mesh.from_pydata([native_to_local@p for p in top+bottom],[],polygons)
    material=bpy.data.materials.get('Detailed_Nail');assert material
    mesh.materials.append(material);mesh.update()
    nail.data=mesh
    for group in list(nail.vertex_groups):nail.vertex_groups.remove(group)
    nail.vertex_groups.new(name=digit+'2').add(list(range(len(mesh.vertices))),1.,'REPLACE')
    for polygon in mesh.polygons:polygon.use_smooth=True
    nail['detail_role']='Thin reference-shaped nail conforming to bare skin; distal rigid binding'
    return {'object':nail.name,'length_mm':length*1000,'width_mm':width*1000,
            'plate_thickness_mm':.13,'skin_lift_mm_range':[.10,.25],
            'vertices':len(mesh.vertices),'bone':digit+'2','projection_misses':missing,
            'projection_attempts':attempt+1,'radial_rings':radial_rings,'radial_segments':segments,
            'triangle_witness_samples':len(signed),'minimum_top_clearance_m':min(signed),
            'maximum_top_clearance_m':max(signed),'fit_iterations':fit_iteration+1,
            'maximum_local_surface_lift_m':max((a-b).length for a,b in zip(top,original_top))}


def refine_hand(skin,rig,holder,nails):
    """Restore one bare skin surface, reshape anatomy, reproject thin nails, taper cuff."""
    inv=holder.matrix_world.inverted();local=skin.matrix_world.inverted()@holder.matrix_world
    all_points=[inv@skin.matrix_world@v.co for v in skin.data.vertices]
    assert len(all_points)==14988,'Expected independently inspected source04 anatomy+trim mesh.'
    points=all_points[:PHYSICAL]
    physical=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<PHYSICAL]
    assert not any(min(p.vertices)<PHYSICAL<=max(p.vertices) for p in skin.data.polygons)
    weights=[[(g.group,g.weight) for g in v.groups] for v in skin.data.vertices[:PHYSICAL]]
    group_names={g.index:g.name for g in skin.vertex_groups}
    digit_weights={d:[sum(w for g,w in groups if group_names[g].startswith(d)) for groups in weights] for d in DIGITS}
    owners=[max(DIGITS,key=lambda d:digit_weights[d][i]) for i in range(PHYSICAL)]
    keys=[(k.name,[inv@skin.matrix_world@v.co for v in k.data[:PHYSICAL]]) for k in skin.data.shape_keys.key_blocks]
    assert len(keys)==16 and keys[0][0]=='Basis'
    handed=1. if frame(rig,holder,'thumb0')[0].x>frame(rig,holder,'middle0')[0].x else -1.
    geometry={};landmarks={};before_sections={}
    for digit in DIGITS:
        frames=[frame(rig,holder,digit+str(j)) for j in range(3)]
        subset=[f for f in physical if sum(digit_weights[digit][i] for i in f)/len(f)>.60]
        centers=[];sections=[]
        for item in frames:
            center,section=section_center(points,subset,*item)
            centers.append(center);sections.append(section)
        # Thumb0 is its metacarpal. Start the finger taper beyond the web, at thumb1.
        start=1 if digit=='thumb' else 0
        base,axis,cross,dorsal=frames[start]
        levels=[(c-base).dot(axis) for c in centers[start:]]
        owned=[p for i,p in enumerate(points) if digit_weights[digit][i]>.6]
        tip=max((p-base).dot(axis) for p in owned)
        near=[p for p in owned if (p-base).dot(axis)>tip-.003]
        tip_center=sum(near,Vector())/len(near)
        center_knots=list(zip(levels,centers[start:]))+[(tip,tip_center)]
        geometry[digit]=(base,axis,cross,dorsal,center_knots,tip,start)
        before_sections[digit]=sections

    def wrist_scales(y):
        amount=1-smooth(.014,.075,-y)
        return 1-.36*amount,1-.50*amount

    def palm(point):
        x,y,z=point
        if y<0:
            sx,sz=wrist_scales(y)
            return Vector((x*sx,y,z*sz))
        sx=.64+.36*smooth(.004,.095,y)
        sz=.50-.14*smooth(.008,.035,y)+.64*smooth(.080,.140,y)
        q=Vector((x*sx,y,z*sz))
        xx=x*handed
        gate=(1-smooth(.073,.112,y))*smooth(.005,.025,y)
        palmar=smooth(.002,.023,-z)
        dorsal=smooth(.002,.024,z)
        thenar=gauss(xx,y,.040,.032,.024,.032)
        hypothenar=gauss(xx,y,-.035,.038,.018,.040)
        hollow=gauss(xx,y,-.001,.057,.025,.027)
        q.z+=gate*palmar*(-.0045*thenar-.0030*hypothenar+.0030*hollow)
        # Low asymmetric metacarpal ridges merge into MCP heads, not round beads.
        for digit in ('index','middle','ring','little'):
            end=geometry[digit][4][0][1]
            start=Vector((end.x*.42,.017,0))
            segment=Vector((end.x-start.x,end.y-start.y,0))
            delta=Vector((x-start.x,y-start.y,0))
            t=max(0.,min(1.,delta.dot(segment)/segment.length_squared))
            distance=(delta-segment*t).length
            q.z+=dorsal*.0009*math.exp(-(distance/.0043)**2)*math.sin(math.pi*t)*gate
        return q

    def warp(point,index):
        body=palm(point)
        digit=owners[index];weight=digit_weights[digit][index]
        base,axis,cross,dorsal,knots,tip,start=geometry[digit]
        t=(point-base).dot(axis)
        c=interpolate(knots,t)
        # Retain tangent coordinate when a point extends outside the sampled centerline.
        c=c+axis*((point-c).dot(axis))
        u=(point-c).dot(cross);v=(point-c).dot(dorsal)
        normalized=max(0.,min(1.,t/max(tip,1e-6)))
        if digit=='thumb':
            sx=interpolate([(0.,.76),(.28,.68),(.54,.72),(.72,.64),(1.,.61)],normalized)
            sz=interpolate([(0.,.72),(.30,.64),(.56,.68),(1.,.60)],normalized)
            gate=smooth(.001,.019,t)
        else:
            joint=(knots[1][0]/tip if len(knots)>2 else .46)
            dip=(knots[2][0]/tip if len(knots)>3 else .73)
            sx=interpolate([(0.,.72),(.20,.56),(joint,.62),((joint+dip)*.5,.55),(dip,.63),(.90,.58),(1.,.67)],normalized)
            sz=interpolate([(0.,.67),(.22,.55),(joint,.59),((joint+dip)*.5,.55),(dip,.63),(1.,.61)],normalized)
            gate=smooth(-.014,.012,t)
        # Elliptic, slightly asymmetric sections: a fuller finger pad and flatter dorsum.
        skew=1+.035*math.tanh(u/.009)*handed
        radial=cross*(u*sx*skew)+dorsal*(v*sz)
        pad=smooth(.40,.62,normalized)*(1-smooth(.91,1.,normalized))
        radial-=dorsal*(.0007*pad*smooth(.002,.010,-v))
        finger=palm(c)+radial
        blend=gate*smooth(.12,.70,weight)
        return body.lerp(finger,blend)

    mapped=[warp(p,i) for i,p in enumerate(points)]
    wrist_profile=radial_profile(BVHTree.FromPolygons(mapped,physical),0.)
    root_centers=sorted([geometry[d][4][0][1] for d in ('index','middle','ring','little')],key=lambda p:p.x)
    webs=[]
    for first,second in zip(root_centers,root_centers[1:]):
        x=(first.x+second.x)*.5
        low=min(first.y,second.y)-.018;high=max(first.y,second.y)+.04
        near=[p for p in mapped if abs(p.x-x)<.003 and low<p.y<high]
        assert near,'Missing interdigital web sample'
        y=max(p.y for p in near)
        webs.append((x,y,abs(second.x-first.x)))
    thumb_web=palm((frame(rig,holder,'index0')[0]+frame(rig,holder,'thumb1')[0])*.5)

    def transition(point):
        q=point.copy()
        # One common skin section continues through the former clothing join.
        # A near-cylindrical 0..24 mm wrist replaces the pinched cloth-lip neck.
        radius=Vector((q.x,0,q.z)).length
        if radius>1e-8 and q.y<.022:
            desired=angular_radius(wrist_profile,q)+.08*(-q.y)
            amount=1-smooth(.004,.022,q.y)
            scale=(radius+(desired-radius)*amount)/radius
            q.x*=scale;q.z*=scale
        for x,y,width in webs:
            q.y-=.0050*gauss(point.x,point.y,x,y,width*.44,.013)
        return q

    native_keys=[(name,[transition(warp(p,i)) for i,p in enumerate(positions)]) for name,positions in keys]
    masks=[]
    for p in native_keys[0][1]:
        mask=max([gauss(p.x,p.y,x,y-.002,width*.55,.019) for x,y,width in webs])
        thumb_mask=gauss(p.x,p.y,thumb_web.x,thumb_web.y,.020,.026)
        masks.append(max(mask,thumb_mask))
    smoothed=soften_transition_arrays([positions for name,positions in native_keys],physical,points,masks)
    mapped=native_keys[0][1]
    mapped_keys=[(name,[local@p for p in positions]) for name,positions in native_keys]
    make_skin(skin,[local@p for p in mapped],physical,weights,mapped_keys)
    maximum=max((a-b).length for a,b in zip(points,mapped))
    after_sections={}
    for digit in DIGITS:
        subset=[f for f in physical if sum(digit_weights[digit][i] for i in f)/len(f)>.60]
        after_sections[digit]=[]
        for j in range(3):
            center,size=section_center(mapped,subset,*frame(rig,holder,digit+str(j)))
            landmarks[digit+'_'+str(j)]=list(center)
            after_sections[digit].append(size)
    nail_report=[]
    for digit in DIGITS:
        nail=next(o for o in nails if o.name.startswith('Nail_'+digit))
        nail_report.append(nail_plate(nail,skin,rig,holder,digit,mapped,physical,digit_weights[digit]))
    cuff_report=[]
    for obj in descendants(holder):
        if obj.type!='MESH' or 'WristCuff' not in obj.name:continue
        to_native=inv@obj.matrix_world;to_local=obj.matrix_world.inverted()@holder.matrix_world
        original_cuff=[to_native@v.co for v in obj.data.vertices]
        original_faces=[list(p.vertices) for p in obj.data.polygons]
        original_tree=BVHTree.FromPolygons(original_cuff,original_faces)
        proximal_profile=radial_profile(original_tree,-.075)
        proximal_next=radial_profile(original_tree,-.076)
        changed=0;max_move=0.;prox_error=0.
        modified=[]
        for index,p in enumerate(original_cuff):
            sx,sz=wrist_scales(p.y);q=Vector((p.x*sx,p.y,p.z*sz));z=-p.y
            if z<.075:
                direction=Vector((q.x,0,q.z)).normalized()
                start=angular_radius(wrist_profile,direction)
                end=angular_radius(proximal_profile,direction)
                end_slope=(angular_radius(proximal_next,direction)-end)/.001
                if z<=.024:outer=start+.08*z
                else:
                    length=.075-.024;t=(z-.024)/length
                    a=start+.08*.024
                    outer=(2*t**3-3*t*t+1)*a+(t**3-2*t*t+t)*length*.08+(-2*t**3+3*t*t)*end+(t**3-t*t)*length*end_slope
                # Preserve the original inner wall offset, but discard its distal
                # rolled closure below. The outside sits 40 microns under skin.
                layer=index//64
                inset=0. if layer<33 else -.00075
                if layer in (33,34,35,36):inset=0.  # only occurs beyond fixed .075
                radius=outer+inset-(.00004*(1-smooth(.024,.040,z)))
                q=Vector((direction.x*radius,p.y,direction.z*radius))
            delta=(p-q).length
            if p.y<=-.075:prox_error=max(prox_error,delta)
            if delta>1e-9:changed+=1;max_move=max(max_move,delta)
            modified.append(q)
        # Source cuff has 33 outer rings, 4 proximal roll rings, 32 inner
        # rings, then 3 distal clothing-roll rings (64 radial samples each).
        assert len(original_cuff)==72*64,'Unexpected source cuff topology'
        kept=69*64
        kept_faces=[f for f in original_faces if max(f)<kept]
        material=obj.data.materials[0]
        mesh=bpy.data.meshes.new('Reference_Bare_Wrist_Transition')
        mesh.from_pydata([to_local@p for p in modified[:kept]],[],kept_faces)
        mesh.materials.append(material)
        for p in mesh.polygons:p.use_smooth=True
        mesh.update();obj.data=mesh
        assert prox_error<1e-8
        cuff_report.append({'object':obj.name,'changed_vertices':changed,'maximum_move_mm':max_move*1000,
                            'proximal_y_le_minus075_max_error_m':prox_error,'axial_coordinates_unchanged':True,
                            'removed_distal_roll_vertices':len(original_cuff)-kept,
                            'removed_distal_roll_triangles':sum(len(f)-2 for f in original_faces)-sum(len(f)-2 for f in kept_faces),
                            'contact_profile':'Same polar skin profile at y=0, 0.08 radial slope to z=.024, Hermite blend to unchanged proximal z=.075; outer overlap 40 microns.',
                            'normals':'Recomputed smooth normals without distal roll cap.'})
    palm_sizes={}
    for y in (0.,.02,.04,.06,.08):
        unused,size=section_center(mapped,physical,Vector((0,y,0)),Vector((0,1,0)),Vector((1,0,0)),Vector((0,0,1)))
        palm_sizes[str(y)]=size
    landmarks.update({'thenar_center':[handed*.034,.034,-.016],
                      'hypothenar_center':[-handed*.030,.038,-.013],
                      'palm_hollow_center':[0,.055,-.008],
                      'wrist_center':[0,0,0]})
    return {'skin_object':skin.name,'physical_vertices':PHYSICAL,'triangles':sum(len(f)-2 for f in physical),
            'removed_trim_vertices':len(all_points)-PHYSICAL,'removed_trim_triangles':5528,
            'single_continuous_bare_skin':True,'skin_material':'Detailed_Skin',
            'maximum_geometry_move_mm':maximum*1000,'before_bounds':bounds(points),'after_bounds':bounds(mapped),
            'before_joint_sections':before_sections,'after_joint_sections':after_sections,
            'after_palm_sections':palm_sizes,'landmarks_native':landmarks,'handedness_x':handed,
            'web_transitions':{'centers_native':webs,'thumb_web_center':list(thumb_web),
                               'maximum_web_lowering_mm':5.,'smoothed_welded_vertices':smoothed,
                               'method':'Rounded U warp plus five mild masked surface relaxation steps, identically applied to Basis and every corrective; actual-distance 1 micron source UV seam weld prevents grid-boundary cracks.'},
            'nails':nail_report,'cuff':cuff_report,'rig_rest_names_axes_and_wrist_pivot_unchanged':True,
            'shape_keys_remapped':['Basis']+[name for name,p in mapped_keys if name!='Basis'],
            'shape_remap_method':'Each source Basis and corrective position passes through the identical smooth anatomy transformation; neutral values remain zero.',
            'weights_method':'Existing anatomical weights retained by original 0..12035 vertex index; each replacement nail remains rigid distal2.',
            'uv_action':'New physical mesh and nails require fresh UV unwrap/bake in pipeline; no old glove colors retained.'}
