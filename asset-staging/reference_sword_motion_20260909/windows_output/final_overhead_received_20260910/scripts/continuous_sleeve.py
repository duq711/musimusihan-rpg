"""Continuous sleeve skin, layered over the approved independent motion controls."""
import bpy,math
from mathutils import Matrix,Vector,Quaternion

def build(scene,root,W,E,H,controls,source_samples):
    axis=(H-W).normalized();cross=Vector((axis.z,0,-axis.x)).normalized();up=axis.cross(cross).normalized()
    # Retain the source leather straps and buckles; replace only the disconnected
    # base sleeve surfaces. The glove and every sword mesh stay byte-equivalent.
    fore=bpy.data.objects['RightArm_Forearm_Surface']
    leather=bpy.data.objects['RightArm_UpperArm_Surface'].data.materials[0]
    import bmesh
    bm=bmesh.new();bm.from_mesh(fore.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index==0],context='FACES')
    bm.to_mesh(fore.data);bm.free();fore.data.update()
    upper=bpy.data.objects['RightArm_UpperArm_Surface'];bpy.data.objects.remove(upper,do_unlink=True)
    for name in ['RightArm_Elbow_LeatherGusset','RightArm_Wrist_UnderCuff']:
        bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
    bone_defs=[('SleeveHand',-.02),('SleeveWrist',.012),('SleeveForearm',.07),('SleeveElbow25',.215),('SleeveElbow50',.26),('SleeveElbow75',.305),('SleeveUpper',.35)]
    armdata=bpy.data.armatures.new('SleeveSurfaceRig');arm=bpy.data.objects.new('SleeveSurfaceRig',armdata);scene.collection.objects.link(arm)
    arm.parent=root;arm.matrix_parent_inverse=Matrix.Identity(4);arm.matrix_basis=Matrix.Identity(4)
    bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);bpy.context.view_layer.objects.active=arm;bpy.ops.object.mode_set(mode='EDIT')
    for name,unused in bone_defs:
        b=armdata.edit_bones.new(name);b.head=(0,0,0);b.tail=(0,.1,0)
    bpy.ops.object.mode_set(mode='OBJECT')
    radius_keys=[(-.030,.026,.034),(-.012,.03205,.04483),(.025,.0381,.04895),(.0745,.04514,.05784),(.0915,.04667,.05964),(.197,.0549,.06876),(.217,.0564,.07044),(.271,.0577,.07252),(.35,.063,.077),(.45,.07,.085),(.606,.078,.093)]
    def radii(x):
        for a,b in zip(radius_keys,radius_keys[1:]):
            if a[0]<=x<=b[0]:
                t=(x-a[0])/(b[0]-a[0]);return (a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t)
        return radius_keys[-1][1:]
    # Dense evenly spaced rings ensure smooth deformation at 127.75deg elbow bend.
    count=128;sides=64;points=[];faces=[];weights=[]
    knots=[(-.03,'SleeveHand'),(-.007,'SleeveHand'),(.012,'SleeveWrist'),(.052,'SleeveForearm'),(.17,'SleeveForearm'),(.215,'SleeveElbow25'),(.26,'SleeveElbow50'),(.305,'SleeveElbow75'),(.35,'SleeveUpper'),(.606,'SleeveUpper')]
    for j in range(count+1):
        dist=-.03+.636*j/count;ra,rb=radii(dist)
        a,b=knots[0],knots[-1]
        for a1,b1 in zip(knots,knots[1:]):
            if a1[0]<=dist<=b1[0]:a,b=a1,b1;break
        t=max(0,min(1,(dist-a[0])/(b[0]-a[0])));weight={a[1]:1-t};weight[b[1]]=weight.get(b[1],0)+t
        for k in range(sides):
            angle=2*math.pi*k/sides
            # Fine cloth irregularity instead of an exposed spherical joint.
            wrinkle=1+.005*math.sin(3*angle+dist*49)*math.sin(math.pi*j/count)
            points.append(W+axis*dist+(cross*(ra*math.cos(angle))+up*(rb*math.sin(angle)))*wrinkle);weights.append(weight)
    for j in range(count):
        for k in range(sides):
            a=j*sides+k;b=j*sides+(k+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(reversed(range(sides))));faces.append(tuple(count*sides+k for k in range(sides)))
    mesh=bpy.data.meshes.new('ContinuousLeatherSleeve');mesh.from_pydata(points,[],faces);mesh.materials.append(leather);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    sleeve=bpy.data.objects.new('RightArm_ContinuousSleeve_Surface',mesh);scene.collection.objects.link(sleeve)
    sleeve.parent=arm;sleeve.matrix_parent_inverse=Matrix.Identity(4);sleeve.matrix_basis=Matrix.Identity(4)
    for p in mesh.polygons:p.use_smooth=len(p.vertices)==4
    for name,unused in bone_defs:sleeve.vertex_groups.new(name=name)
    for idx,row in enumerate(weights):
        for name,value in row.items():
            if value>0:sleeve.vertex_groups[name].add([idx],value,'REPLACE')
    modifier=sleeve.modifiers.new('Continuous sleeve deformation','ARMATURE');modifier.object=arm;modifier.use_deform_preserve_volume=False
    # The retained leather straps, buckles and cuff follow the same surface bend,
    # so their edges cannot remain rigid and float above the elbow or wrist.
    for detail in [fore,bpy.data.objects['RightArm_WristCuff_Surface']]:
        detail.parent=arm;detail.matrix_parent_inverse=Matrix.Identity(4);detail.matrix_basis=Matrix.Identity(4)
        detail.vertex_groups.clear()
        for name,unused in bone_defs:detail.vertex_groups.new(name=name)
        for vertex in detail.data.vertices:
            dist=(vertex.co-W).dot(axis);a,b=knots[0],knots[-1]
            for a1,b1 in zip(knots,knots[1:]):
                if a1[0]<=dist<=b1[0]:a,b=a1,b1;break
            t=max(0,min(1,(dist-a[0])/(b[0]-a[0])));weight={a[1]:1-t};weight[b[1]]=weight.get(b[1],0)+t
            for name,value in weight.items():
                if value>0:detail.vertex_groups[name].add([vertex.index],value,'REPLACE')
        modifier=detail.modifiers.new('Match continuous sleeve skin','ARMATURE');modifier.object=arm;modifier.use_deform_preserve_volume=False
    action=controls['SwordGrip'].animation_data.action;strip=action.layers[0].strips[0]
    slot=action.slots.new('OBJECT',arm.name);bag=strip.channelbags.new(slot)
    rows=[];previous={}
    for idx in range(187):
        scene.frame_set(idx);bpy.context.view_layer.update()
        mats={n:controls[n].matrix_basis.copy() for n in ['SwordGrip','Forearm_R','UpperArm_R']}
        e=Vector(source_samples[idx]['right_arm']['elbow']);w=Vector(source_samples[idx]['right_arm']['wrist'])
        values={'SleeveHand':mats['SwordGrip'],'SleeveForearm':mats['Forearm_R'],'SleeveUpper':mats['UpperArm_R']}
        for name,u in [('SleeveElbow25',.25),('SleeveElbow50',.5),('SleeveElbow75',.75)]:
            q=mats['Forearm_R'].to_quaternion().slerp(mats['UpperArm_R'].to_quaternion(),u)
            M=q.to_matrix().to_4x4();M.translation=e-M.to_3x3()@E;values[name]=M
        q=mats['SwordGrip'].to_quaternion().slerp(mats['Forearm_R'].to_quaternion(),.5)
        M=q.to_matrix().to_4x4();M.translation=w-M.to_3x3()@W;values['SleeveWrist']=M
        row={}
        for name,M in values.items():
            loc,q,scale=M.decompose()
            if name in previous and q.dot(previous[name])<0:q.negate()
            previous[name]=q.copy();row[name]={'location':list(loc),'rotation_quaternion':list(q),'scale':list(scale)}
        rows.append(row)
    for name,unused in bone_defs:
        arm.pose.bones[name].rotation_mode='QUATERNION'
        for prop,n in [('location',3),('rotation_quaternion',4),('scale',3)]:
            for axis_idx in range(n):
                fc=bag.fcurves.new(data_path=f'pose.bones["{name}"].{prop}',index=axis_idx);fc.keyframe_points.add(187)
                fc.keyframe_points.foreach_set('co',[value for i,row in enumerate(rows) for value in (i,row[name][prop][axis_idx])])
                for k in fc.keyframe_points:k.interpolation='LINEAR'
    arm.animation_data_create();arm.animation_data.action=action;arm.animation_data.action_slot=slot
    track=arm.animation_data.nla_tracks.new();track.name='overhead';track.mute=True
    nla=track.strips.new('overhead',0,action);nla.action_slot=slot;nla.action_frame_start=0;nla.action_frame_end=186;nla.extrapolation='NOTHING'
    arm['purpose']='surface deformation only; the eight approved motion controls are unchanged'
    return arm,sleeve,{'skin_count':1,'bone_count':7,'sleeve_vertices':len(points),'sleeve_faces':len(faces),'weighting':'linear blend skin with three elbow intermediate rotations; canonical bind basis identity','surface':'continuous closed sleeve with source leather straps, cuff and glove preserved'}
