"""Author a local, licensed Shepherd pet animation package in Blender 5.2.

Run with Blender --background --disable-autoexec --python this_file -- --base DIR.
The original archive is never changed. This script contains no third-party mesh data.
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from shepherd_ik import capture_contacts, apply_contacts

FPS = 30
TAU = 2 * math.pi
TAIL_BASE = None


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def envelope(t, a, b, c, d):
    return smooth((t-a)/(b-a)) * (1-smooth((t-c)/(d-c)))


def set_action(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action and action.slots:
        rig.animation_data.action_slot = action.slots[0]


def snapshot(rig):
    return {b.name: b.matrix_basis.copy() for b in rig.pose.bones}


def restore(rig, values):
    for b in rig.pose.bones:
        b.matrix_basis = values[b.name]
    bpy.context.view_layer.update()


def source_pose(rig, action, frame):
    set_action(rig, action)
    bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
    bpy.context.view_layer.update()
    return snapshot(rig)


def turn(rig, name, degrees, axis='X'):
    b = rig.pose.bones[name]
    b.rotation_mode = 'QUATERNION'
    axisv = {'X':(1,0,0),'Y':(0,1,0),'Z':(0,0,1)}[axis]
    b.rotation_quaternion = b.rotation_quaternion @ Quaternion(axisv, math.radians(degrees))


def neck(rig, lower=0, yaw=0, tilt=0):
    turn(rig,'DEF-spine.009',lower*.45)
    turn(rig,'DEF-spine.010',lower*.45)
    turn(rig,'DEF-spine.011',lower*.10)
    turn(rig,'DEF-spine.010',yaw*.35,'Z')
    turn(rig,'DEF-spine.011',yaw*.65,'Z')
    turn(rig,'DEF-spine.011',tilt,'Y')


def tail(rig, t, amount=10, speed=1, sag=35):
    # Keep the tail's attitude in armature space while the pelvis pitches in
    # gallop/sitting. A local-only sag would double the pelvis rotation.
    bpy.context.view_layer.update()
    p=rig.pose.bones['DEF-spine.003'];head=p.matrix.translation.copy()
    height=head.z*rig.matrix_world.to_scale().z
    maximum=math.degrees(math.asin(max(0,min(.95,(height-.055)/.38))))
    sag=min(sag,maximum)
    q=TAIL_BASE.to_quaternion() @ Quaternion((1,0,0),math.radians(-sag))
    q=q @ Quaternion((0,0,1),math.radians(amount*math.sin(TAU*t*speed)))
    p.matrix=Matrix.LocRotScale(head,q,TAIL_BASE.to_scale())
    bpy.context.view_layer.update()
    for i,name in enumerate(('DEF-spine.002','DEF-spine.001','DEF-spine'),1):
        turn(rig,name,amount*math.sin(TAU*t*speed-i*.35), 'Z')


def ears(rig, amount, asymmetric=0):
    for side,sign in [('L',1),('R',-1)]:
        turn(rig,'DEF-Border-collie_ear01.'+side,amount+sign*asymmetric,'X')
        turn(rig,'DEF-AustralianShepherd_ear01.'+side,amount*.3,'X')


def body(rig, basis, drop=0, back=0, pitch=0):
    p=rig.pose.bones['DEF-spine.004']
    p.matrix=Matrix.Translation((0,back,drop)) @ basis @ Matrix.Rotation(math.radians(pitch),4,'X')
    bpy.context.view_layer.update()


def import_sources(base):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps=FPS
    bpy.ops.import_scene.fbx(filepath=str(base/'source/Mesh/SK_GermanShepherd_01.fbx'))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    rig.name='ShepherdPet'
    mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    mesh.name='ShepherdPet_Mesh'
    # Remove only this import's packaging empty; preserve exact world transforms.
    for o in list(bpy.context.scene.objects):
        if o.type=='EMPTY':
            for ch in list(o.children):
                w=ch.matrix_world.copy(); ch.parent=None; ch.matrix_world=w
            bpy.data.objects.remove(o,do_unlink=True)
    sources={}
    for path in sorted((base/'source/Animations').glob('*.fbx')):
        if ' test' in path.name: continue
        objects=set(bpy.data.objects); actions=set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
        imported=set(bpy.data.actions)-actions
        for a in imported:
            a.use_fake_user=True
            a.name='Source_'+path.stem
            sources[path.stem]=a
        for o in set(bpy.data.objects)-objects: bpy.data.objects.remove(o,do_unlink=True)
    for b in rig.pose.bones: b.rotation_mode='QUATERNION'
    return rig,mesh,sources


def textures(base, mesh):
    for mat in mesh.data.materials:
        mat.use_nodes=True
        nt=mat.node_tree; nt.nodes.clear()
        out=nt.nodes.new('ShaderNodeOutputMaterial')
        shader=nt.nodes.new('ShaderNodeBsdfPrincipled')
        nt.links.new(shader.outputs['BSDF'],out.inputs['Surface'])
        for suffix,input_name in [('B','Base Color'),('R','Roughness'),('N','Normal')]:
            tex=nt.nodes.new('ShaderNodeTexImage')
            tex.image=bpy.data.images.load(str(base/f'source/Textures/T_GermanShepherd_{suffix}.png'),check_existing=True)
            tex.image.colorspace_settings.name='sRGB' if suffix=='B' else 'Non-Color'
            if suffix=='N':
                normal=nt.nodes.new('ShaderNodeNormalMap')
                nt.links.new(tex.outputs['Color'],normal.inputs['Color'])
                nt.links.new(normal.outputs['Normal'],shader.inputs[input_name])
            else:
                nt.links.new(tex.outputs['Color'],shader.inputs[input_name])
            if suffix=='B' and 'Transparent' in mat.name:
                nt.links.new(tex.outputs['Alpha'],shader.inputs['Alpha'])
                mat.surface_render_method='DITHERED'
        shader.inputs['Metallic'].default_value=0


def close_loop_local(rig, action, end):
    """Match normalized local quaternion and translation endpoint tangents.

    Symmetric unit quaternions have the same normalized-linear endpoint
    derivative. Local symmetry also preserves the parent's contribution to
    every descendant's world velocity.
    """
    samples=[]
    set_action(rig,action)
    for f in (1,2,end-1,end):
        bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
        samples.append({b.name:b.matrix_basis.copy() for b in rig.pose.bones})
    targets=[{}, {}, {}, {}]
    for b in rig.pose.bones:
        decomposed=[pose[b.name].decompose() for pose in samples]
        p0,q0,s0=decomposed[0];pn,qn,sn=decomposed[-1]
        qn.make_compatible(q0)
        pc=(p0+pn)*.5;qc=q0.slerp(qn,.5);sc=(s0+sn)*.5
        vp=(decomposed[1][0]-decomposed[2][0])*.5
        vs=(decomposed[1][2]-decomposed[2][2])*.5
        logs=[]
        for j in (1,2):
            delta=qc.inverted() @ decomposed[j][1]
            if delta.w<0: delta.negate()
            axis,angle=delta.to_axis_angle();logs.append(axis*angle)
        vq=(logs[0]-logs[1])*.5
        for i,sign in enumerate((0,1,-1,0)):
            q=qc.copy()
            if vq.length>1e-10 and sign:
                q=q @ Quaternion(vq.normalized(),vq.length*sign)
            targets[i][b.name]=Matrix.LocRotScale(pc+vp*sign,q,sc+vs*sign)
    for f,matrices in zip((1,2,end-1,end),targets):
        set_action(rig,None);bpy.context.scene.frame_set(f)
        for b in rig.pose.bones:
            b.matrix_basis=matrices[b.name]
        set_action(rig,action)
        for b in rig.pose.bones:
            b.keyframe_insert('location',frame=f,group=b.name)
            b.keyframe_insert('rotation_quaternion',frame=f,group=b.name)
            b.keyframe_insert('scale',frame=f,group=b.name)


def correct_gait_floor(rig, mesh, paw_indices):
    bpy.context.view_layer.update()
    evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data=evaluated.to_mesh()
    lowest=min((evaluated.matrix_world @ data.vertices[i].co).z for i in paw_indices)
    evaluated.to_mesh_clear()
    if lowest<.0002:
        p=rig.pose.bones['DEF-spine.004'];matrix=p.matrix.copy()
        matrix.translation.z+=(.0002-lowest)/rig.matrix_world.to_scale().z
        p.matrix=matrix;bpy.context.view_layer.update()


def clear_loop_floor(rig, mesh, action, end):
    """Raise a short, symmetric seam arc without changing endpoint tangents.

    Retimed gallop seam reconciliation can lower an interpolated paw below the
    plane. The four endpoint samples get the same vertical correction; its
    interior falloff preserves the original airborne/support gait phases.
    """
    set_action(rig,action)
    lowest=0
    for f in (1,2,end-1,end):
        bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
        evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
        lowest=min(lowest,min((evaluated.matrix_world @ v.co).z for v in data.vertices))
        evaluated.to_mesh_clear()
    correction=max(0,.0002-lowest) if lowest<0 else 0
    if correction:
        for f in range(1,end+1):
            distance=min(f-1,end-f)
            weight=1 if distance<=1 else max(0,1-(distance-1)/2)
            if not weight: continue
            bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
            p=rig.pose.bones['DEF-spine.004'];m=p.matrix.copy()
            m.translation.z+=correction*weight/rig.matrix_world.to_scale().z
            p.matrix=m;p.keyframe_insert('location',frame=f,group=p.name)
    return correction


def clip_specs():
    return [
        ('IdleFriendly',90,True,'idle',[]),
        ('Walk',18,True,'walk',[]),('Run',12,True,'run',[]),
        ('CombatBite',36,False,None,[{'time':.60,'name':'BiteContact'}]),
        ('SearchSniff',90,True,None,[]),('SearchWalk',54,True,'walk',[]),
        ('SearchFound',45,False,None,[{'time':.8,'name':'FoundCue'}]),
        ('RetrievePickup',45,False,None,[{'time':.8,'name':'AttachItem'}]),
        ('RetrieveCarryWalk',36,True,'walk',[]),
        ('RetrieveDrop',45,False,None,[{'time':.8,'name':'DetachItem'}]),
        ('EatStart',30,False,None,[]),('EatLoop',60,True,None,[]),('EatEnd',30,False,None,[]),
        ('PetSit',45,False,None,[]),('PetEnjoy',90,True,None,[]),('PetRise',36,False,None,[]),
    ]


def author(base):
    global TAIL_BASE
    rig,mesh,sources=import_sources(base)
    textures(base,mesh)
    bytype={kind:next(a for k,a in sources.items() if key in k) for kind,key in [('idle','Idle Breathing'),('walk','Walk Loop'),('run','Run Loop')]}
    baseline=source_pose(rig,bytype['idle'],1)
    set_action(rig,None); restore(rig,baseline)
    contacts=capture_contacts(rig,use_rest=False)
    base_pelvis=rig.pose.bones['DEF-spine.004'].matrix.copy()
    TAIL_BASE=rig.pose.bones['DEF-spine.003'].matrix.copy()
    paw_indices=[v.index for v in mesh.data.vertices if any(mesh.vertex_groups[g.group].name.startswith(('DEF-f_palm','DEF-r_palm','DEF-front_toe','DEF-toe')) and g.weight>.3 for g in v.groups)]
    authored=[]; contact_max=0; unreachable=[]
    for name,intervals,loop,src,events in clip_specs():
        a=bpy.data.actions.new(name); a.use_fake_user=True
        frame_values=[]
        for f in range(intervals+1):
            t=f/intervals
            values=baseline
            if src:
                source=bytype[src]; start,end=source.frame_range
                values=source_pose(rig,source,start+(end-start)*t)
            set_action(rig,None); restore(rig,values)
            if src in ('walk','run'):
                # The shared pack's source tail curves sink below this breed's
                # ground plane. Author a breed-specific tail over the source gait.
                for tail_name in ('DEF-spine.003','DEF-spine.002','DEF-spine.001','DEF-spine'):
                    rig.pose.bones[tail_name].matrix_basis=baseline[tail_name]
            if name=='IdleFriendly':
                # Preserve the supplied idle breathing and add a relaxed wag.
                tail(rig,t,5,1)
            elif name=='CombatBite':
                brace=envelope(t,0,.22,.72,1)
                attack=envelope(t,.18,.42,.53,.82)
                body(rig,base_pelvis,drop=-1.0*brace,back=-2.0*attack,pitch=2*brace)
                neck(rig,lower=8*brace-18*attack)
                turn(rig,'DEF-jaw',32*envelope(t,.18,.37,.43,.53))
                ears(rig,-8*brace); tail(rig,t,2*math.sin(math.pi*t),1)
            elif name in ('SearchSniff','SearchWalk'):
                if name=='SearchSniff': body(rig,base_pelvis,drop=-.5,pitch=13)
                neck(rig,lower=72 if name=='SearchSniff' else 58,yaw=5*math.sin(TAU*t),tilt=1.5*math.sin(2*TAU*t))
                turn(rig,'DEF-jaw',1.2*(1-math.cos(6*TAU*t)))
                tail(rig,t,5,1); ears(rig,4,2*math.sin(TAU*t))
            elif name=='SearchFound':
                pause=1-smooth(t/.35)
                body(rig,base_pelvis,drop=-.5*pause,pitch=13*pause)
                neck(rig,lower=72*pause,yaw=10*envelope(t,.22,.5,.7,1),tilt=6*envelope(t,.25,.5,.75,1))
                ears(rig,-7*envelope(t,.2,.4,.72,1));tail(rig,t,13*math.sin(math.pi*t),2)
            elif name in ('RetrievePickup','RetrieveDrop'):
                lower=envelope(t,.0,.43,.68,1)
                body(rig,base_pelvis,drop=-.5*lower,pitch=13*lower)
                neck(rig,lower=83*lower)
                opening=envelope(t,.20,.38,.48,.56) if name=='RetrievePickup' else envelope(t,.45,.53,.62,.74)
                grip=smooth(t/.58) if name=='RetrievePickup' else (1-smooth(t/.74))
                turn(rig,'DEF-jaw',22*opening-7*grip)
                tail(rig,t,5*math.sin(math.pi*t),1)
            elif name=='RetrieveCarryWalk':
                neck(rig,lower=4,tilt=1.0*math.sin(TAU*t))
                # The original walk jaw is reset to a closed grip.
                rig.pose.bones['DEF-jaw'].matrix_basis=baseline['DEF-jaw']
                turn(rig,'DEF-jaw',-7)
                tail(rig,t,7,1)
            elif name in ('EatStart','EatLoop','EatEnd'):
                amount=smooth(t) if name=='EatStart' else (1-smooth(t) if name=='EatEnd' else 1)
                body(rig,base_pelvis,drop=-.5*amount,pitch=13*amount)
                neck(rig,lower=83*amount)
                if name=='EatLoop':
                    neck(rig,lower=1.3*(1-math.cos(3*TAU*t)),yaw=1.5*math.sin(TAU*t))
                    turn(rig,'DEF-jaw',7*(1-math.cos(3*TAU*t)))
                tail(rig,t,4*amount,1)
            elif name in ('PetSit','PetEnjoy','PetRise'):
                seated=smooth(t) if name=='PetSit' else (1-smooth(t) if name=='PetRise' else 1)
                body(rig,base_pelvis,drop=-26*seated,back=10*seated,pitch=-30*seated)
                neck(rig,lower=-10*seated,tilt=(7*math.sin(TAU*t) if name=='PetEnjoy' else 0))
                ears(rig,7*seated,2*math.sin(TAU*t)*seated)
                tail(rig,t,16*seated,2)
            elif name in ('Walk','Run'):
                tail(rig,t,4,1)
            bpy.context.view_layer.update()
            if src in ('walk','run'): correct_gait_floor(rig,mesh,paw_indices)
            if src not in ('walk','run'):
                target={key:dict(value) for key,value in contacts.items()}
                if name in ('PetSit','PetEnjoy','PetRise'):
                    for key in ('hind.L','hind.R'):
                        target[key]['offset']=(0,-8*seated,0)
                receipt=apply_contacts(rig,target)
                if isinstance(receipt,dict):
                    for key,v in receipt.items():
                        if isinstance(v,dict):
                            residual=v.get('contact_error_cm',v.get('reach_residual_cm',0))
                            if isinstance(residual,(float,int)):
                                contact_max=max(contact_max,residual)
                                if residual>.5: unreachable.append([name,f,key,residual])
            bpy.context.scene.frame_set(f+1)
            set_action(rig,a)
            # Every deform bone is sampled; no dependency on IK constraints at playback.
            for b in rig.pose.bones:
                b.keyframe_insert('location',frame=f+1,group=b.name)
                b.keyframe_insert('rotation_quaternion',frame=f+1,group=b.name)
                b.keyframe_insert('scale',frame=f+1,group=b.name)
        if loop: close_loop_local(rig,a,intervals+1)
        seam_lift=clear_loop_floor(rig,mesh,a,intervals+1) if src in ('walk','run') else 0
        for layer in a.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for k in curve.keyframe_points: k.interpolation='LINEAR'
        authored.append({'name':name,'frames':[1,intervals+1],'duration':intervals/FPS,'loop':loop,'source':'RetroStyle locomotion + authored overlay' if src else 'New authored pet motion','events':events,'loop_clearance_lift_m':seam_lift})
        print('AUTHORED',name,flush=True)
    # Bone-parented integration marker, outside the deformation skeleton.
    socket=bpy.data.objects.new('MouthSocket',None);bpy.context.collection.objects.link(socket)
    socket.parent=rig;socket.parent_type='BONE';socket.parent_bone='DEF-spine.011'
    socket.matrix_world=rig.matrix_world @ rig.pose.bones['DEF-spine.011'].matrix @ Matrix.Translation((0,-6,13))
    manifest={'fps':FPS,'rig':'Generic','root':'ShepherdPet','root_motion':'In-place; no gameplay displacement','height_m':.698,'clips':authored,'mouth_socket':{'bone':'DEF-spine.011','note':'Use production marker; retune item attachment to item dimensions.'},'contact_authoring_max_cm':contact_max,'unreachable_frames':unreachable,'scope':'Animation assets only; pet AI, damage, inventory and player hand animation are not implemented.'}
    (base/'production').mkdir(exist_ok=True)
    (base/'export/Animations').mkdir(parents=True,exist_ok=True)
    (base/'export/Textures').mkdir(exist_ok=True)
    (base/'export/animation-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    import shutil
    for p in (base/'source/Textures').glob('*.png'): shutil.copy2(p,base/'export/Textures'/p.name)
    for image in bpy.data.images:
        if image.filepath: image.pack()
    set_action(rig,bpy.data.actions['IdleFriendly']);bpy.context.scene.frame_set(1)
    bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=91
    bpy.ops.wm.save_as_mainfile(filepath=str(base/'production/ShepherdPet_Animations.blend'))
    for o in bpy.context.scene.objects: o.select_set(False)
    rig.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=rig
    set_action(rig,None);restore(rig,{b.name:Matrix.Identity(4) for b in rig.pose.bones})
    export_flags=dict(use_selection=True,object_types={'ARMATURE','MESH'},add_leaf_bones=False,axis_forward='-Z',axis_up='Y',apply_scale_options='FBX_SCALE_UNITS',use_armature_deform_only=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,path_mode='RELATIVE')
    bpy.ops.export_scene.fbx(filepath=str(base/'export/ShepherdPet_Model.fbx'),bake_anim=False,**export_flags)
    # Include the identical skin in every take: Unity preserves a different
    # import root for a bare armature, which would break the shared Avatar paths.
    mesh.select_set(True)
    for c in authored:
        set_action(rig,bpy.data.actions[c['name']]);bpy.context.scene.frame_start=1;bpy.context.scene.frame_end=c['frames'][1];bpy.context.scene.frame_set(1)
        bpy.ops.export_scene.fbx(filepath=str(base/'export/Animations'/f"{c['name']}.fbx"),bake_anim=True,bake_anim_force_startend_keying=True,bake_anim_step=1,**export_flags)
    print('EXPORTED',len(authored),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    author(args.base.resolve())
