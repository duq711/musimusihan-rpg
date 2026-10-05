"""Produce the inspected kenchoo Labrador's two standing care clips on Mac Blender.

Source GLB and raw captures are preserved. Only independently audited claw and
tooth weight errors are repaired in the production copy. Original standing
anatomy is retained for the user's mouse-controlled care interaction.
Mouse ear/head/coat reactions belong to the runtime overlay, not these clips.
"""
import argparse
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh
from labrador_pet_retarget import set_world_pose

FPS = 30
MODEL_SCALE = .30
SOURCE_SHA = '0e30a09051903e2327c31371dc3dd973ca9da9c07a1c8aea5ca5f1af5bcda4fc'
MAPPING = {
    'Back_38':'b_Hips', 'Torso_23':'b_Spine1', 'Torso2_22':'b_Spine2', 'Torso3_15':'b_Spine3',
    'Neck1_14':'b__Neck', 'Neck2_13':'b__Neck1', 'Neck3_12':'b__Neck2',
    'Head_1':'b_Head', 'Neck3.001_11':'b_Head',
    'FrontShoulder.L_18':'b_LeftClav', 'FrontUpperLeg.L_17':'b_LeftArm', 'FrontLowerLeg.L_16':'b_LeftForeArm',
    'FrontShoulder.R_21':'b_RightClav', 'FrontUpperLeg.R_20':'b_RightArm', 'FrontLowerLeg.R_19':'b_RightForeArm',
    'BackShoulder.L_27':'b_Hips', 'BackLeg.L_26':'b_LeftLegUpper', 'BackUpperLeg.L_25':'b_LeftLeg', 'BackLowerLeg.L_24':'b_LeftLeg1',
    'BackShoulder.R_31':'b_Hips', 'BackLeg.R_30':'b_RightLegUpper', 'BackUpperLeg.R_29':'b_RightLeg', 'BackLowerLeg.R_28':'b_RightLeg1',
    'Tail1_37':'b_Tail001',
}
LIMBS = {
    'front.L': {'chain':['FrontUpperLeg.L_17','FrontLowerLeg.L_16'], 'ankle':'IKFrontLeg.L_47','paw':'FF.L_46', 'source_ankle':'b_LeftHand','source_paw':'b__LeftFinger'},
    'front.R': {'chain':['FrontUpperLeg.R_20','FrontLowerLeg.R_19'], 'ankle':'IKFrontLeg.R_51','paw':'FF.R_50', 'source_ankle':'b_RightHand','source_paw':'b_RightFinger'},
    'hind.L': {'chain':['BackLeg.L_26','BackUpperLeg.L_25','BackLowerLeg.L_24'], 'ankle':'IKBackLeg.L_45','paw':'FFB.L_44','source_ankle':'b_LeftAnkle','source_paw':'b_LeftToe'},
    'hind.R': {'chain':['BackLeg.R_30','BackUpperLeg.R_29','BackLowerLeg.R_28'], 'ankle':'IKBackLeg.R_49','paw':'FFB.R_48','source_ankle':'b_RightAnkle','source_paw':'b_RightToe'},
}


def update(): bpy.context.view_layer.update()


def set_action(rig, action):
    rig.animation_data_create(); rig.animation_data.action=action
    if action and action.slots:
        slot=next((slot for slot in action.slots if slot.target_id_type=='OBJECT'),action.slots[0])
        rig.animation_data.action_slot=slot


def basis_snapshot(rig): return {b.name:b.matrix_basis.copy() for b in rig.pose.bones}


def restore_basis(rig, pose):
    for b in rig.pose.bones: b.matrix_basis=pose[b.name]
    update()


def channels(action):
    return [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags for curve in bag.fcurves]


def key_pose(rig, action, frame):
    set_action(rig,action)
    for b in rig.pose.bones:
        b.rotation_mode='QUATERNION'
        for property_name in ('location','rotation_quaternion','scale'):
            b.keyframe_insert(property_name,frame=frame,group=b.name)


def source_normalized(capture, frame):
    raw=capture.world_pose(frame)
    hips=raw['b_Hips'].translation
    forward=raw['b_Spine3'].translation-hips;forward.y=0;forward.normalize()
    up=Vector((0,1,0));right=up.cross(forward).normalized()
    coordinate=Matrix((right,-forward,up)).to_4x4()
    result={}
    origin=Vector((hips.x,0,hips.z))
    for name,m in raw.items():
        value=coordinate @ m
        value.translation=coordinate.to_3x3() @ (m.translation-origin)
        result[name]=value
    return result


def fabrik(points, lengths, goal, iterations=80):
    points=[p.copy() for p in points]; root=points[0].copy(); goal=goal.copy()
    maximum=sum(lengths)
    if (goal-root).length>maximum:
        direction=(goal-root).normalized()
        for i,length in enumerate(lengths): points[i+1]=points[i]+direction*length
        return points,(points[-1]-goal).length
    for _ in range(iterations):
        points[-1]=goal.copy()
        for i in range(len(lengths)-1,-1,-1):
            direction=points[i]-points[i+1]
            if direction.length<1e-8: direction=Vector((0,-1,0))
            points[i]=points[i+1]+direction.normalized()*lengths[i]
        points[0]=root.copy()
        for i,length in enumerate(lengths):
            direction=points[i+1]-points[i]
            if direction.length<1e-8: direction=Vector((0,-1,0))
            points[i+1]=points[i]+direction.normalized()*length
        if (points[-1]-goal).length<1e-5:break
    return points,(points[-1]-goal).length


def aim(reference, old_vector, new_vector, head):
    swing=old_vector.normalized().rotation_difference(new_vector.normalized())
    result=(swing.to_matrix() @ reference.to_3x3()).to_4x4();result.translation=head
    return result


def repair_weights(base, mesh):
    audit=json.loads((base/'qa/anatomy-audit.json').read_text())
    data=next(item for item in audit['meshes'] if item['name']=='mesh_0')
    assert len(mesh.data.vertices)==data['vertices']==26103
    report=[]
    for part in data['welded_components']:
        if not part.get('repair_transfer'):continue
        source=mesh.vertex_groups[part['repair_transfer']['from']]
        target=mesh.vertex_groups[part['repair_transfer']['to']]
        changed=[]
        for index in part['vertex_indices']:
            vertex=mesh.data.vertices[index]
            old=next((g.weight for g in vertex.groups if g.group==source.index),0)
            existing=next((g.weight for g in vertex.groups if g.group==target.index),0)
            if old>1e-8:
                target.add([index],existing+old,'REPLACE');source.remove([index]);changed.append(index)
        report.append({'component':part['id'],'from':source.name,'to':target.name,
                       'component_vertices':len(part['vertex_indices']),'changed_vertices':len(changed),'indices':changed})
    return report


def coat_mask(base, mesh):
    audit=json.loads((base/'qa/head-interaction-audit.json').read_text())
    excluded=set(audit.get('eye_fur_exclusion_vertex_indices',[]))
    # Key deltas provide an independent conservative eye exclusion, even if an
    # audit reader changes the report's nesting in the future.
    basis=mesh.data.shape_keys.key_blocks[0]
    for key in mesh.data.shape_keys.key_blocks:
        if key.name in ('target_1','target_2'):
            excluded.update(i for i,(a,b) in enumerate(zip(basis.data,key.data)) if (a.co-b.co).length>1e-7)
    mask=mesh.data.color_attributes.new(name='PetCoatMask',type='FLOAT_COLOR',domain='POINT')
    mesh.data.color_attributes.active_color=mask
    ear_groups={group.index for group in mesh.vertex_groups if group.name.startswith('Ear')}
    values=[]
    for vertex in mesh.data.vertices:
        p=vertex.co
        ear=min(1,sum(g.weight for g in vertex.groups if g.group in ear_groups))
        crown=max(0,min(1,(p.z-2.50)/.06))*max(0,min(1,(p.y+2.13)/.10))
        value=max(ear,crown)
        for side in (-1,1):
            d=Vector(((p.x-side*.163)/.09,(p.y+2.122)/.085,(p.z-2.446)/.085)).length
            if d<1.2:value*=max(0,min(1,(d-1)/.2))
        if vertex.index in excluded:value=0
        mask.data[vertex.index].color=(value,0,0,1);values.append(value)
    return {'attribute':'PetCoatMask','channel':'COLOR_0.r','vertices_nonzero':sum(v>1e-6 for v in values),
            'eye_morph_vertices_excluded':len(excluded),'scope':'Audited crown and ears only; teeth/tongue/eyes/muzzle excluded. Shader effect is runtime-controlled.'}


def material_textures(base):
    output=base/'export/Textures';output.mkdir(parents=True,exist_ok=True)
    names={'Image_0':'Labrador_BaseColor.png','Image_1':'Labrador_Normal.png','Image_2':'Labrador_MetallicRoughness.png'}
    result={}
    for image in bpy.data.images:
        if image.name not in names:continue
        path=output/names[image.name];image.filepath_raw=str(path);image.file_format='PNG';image.save()
        result[image.name]=str(path.relative_to(base/'export'))
        image.pack()
    for material in bpy.data.materials:
        if not material.use_nodes:continue
        for node in material.node_tree.nodes:
            if node.type=='NORMAL_MAP':node.inputs['Strength'].default_value=.2
    return {'baseColor':result['Image_0'],'normal':result['Image_1'],'metallicRoughness':result['Image_2']}


def pad_indices(mesh, name):
    index=mesh.vertex_groups[name].index
    return [v.index for v in mesh.data.vertices if any(g.group==index and g.weight>.6 for g in v.groups)]


def paw_floor(mesh, rig, indices):
    update();evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
    minimum=min((evaluated.matrix_world @ data.vertices[index].co).z for index in indices)
    evaluated.to_mesh_clear();return minimum


def measured_sit(rig, mesh, capture, raw_frame, neutral_source, target_neutral, pads):
    source=source_normalized(capture,raw_frame)
    root=rig.pose.bones['Body_43'];base=target_neutral[root.name].copy()
    # The acquired rig's hip height matches the medium captured dog's height
    # after the production scale. Keep a single body scale and actual anatomy.
    factor=target_neutral['Back_38'].translation.z/neutral_source['b_Hips'].translation.z
    base.translation.z+=(source['b_Hips'].translation.z-neutral_source['b_Hips'].translation.z)*factor*.80
    set_world_pose(root,base)
    depth=lambda b:len(b.parent_recursive)
    for name in sorted(MAPPING,key=lambda name:depth(rig.pose.bones[name])):
        bone=rig.pose.bones[name];source_name=MAPPING[name]
        delta=source[source_name].to_quaternion() @ neutral_source[source_name].to_quaternion().inverted()
        if name in ('Back_38','Torso_23','Torso2_22','Torso3_15','FrontShoulder.L_18','FrontShoulder.R_21','BackShoulder.L_27','BackShoulder.R_31'):
            # This model's torso is substantially longer relative to its fore
            # limbs than the captured dog. Full captured spinal pitch would
            # lift the shoulders beyond the actual forelimb reach. Retain the
            # measured timing/hip descent but calibrate world body pitch to the
            # acquired skin's proportions, then solve its unchanged limbs.
            delta=Quaternion((1,0,0,0)).slerp(delta,.42)
        if name=='Tail1_37':delta=Quaternion((1,0,0,0))
        matrix=Matrix.LocRotScale(bone.matrix.translation,delta @ target_neutral[name].to_quaternion(),target_neutral[name].to_scale())
        set_world_pose(bone,matrix)
    receipts={}
    for key,limb in LIMBS.items():
        ankle=rig.pose.bones[limb['ankle']];paw=rig.pose.bones[limb['paw']]
        source_ankle=limb['source_ankle'];source_paw=limb['source_paw']
        delta=Quaternion((1,0,0,0))
        foot=target_neutral[ankle.name].copy();foot.translation+=(source[source_ankle].translation-neutral_source[source_ankle].translation)*factor
        foot=Matrix.LocRotScale(foot.translation,delta @ target_neutral[ankle.name].to_quaternion(),foot.to_scale())
        set_world_pose(ankle,foot)
        paw_delta=Quaternion((1,0,0,0))
        paw_m=Matrix.LocRotScale(paw.matrix.translation,paw_delta @ target_neutral[paw.name].to_quaternion(),target_neutral[paw.name].to_scale())
        set_world_pose(paw,paw_m)
        # All four pads support this deliberately selected seated transition.
        # Correct the actual weighted mesh pad, not a guessed bone endpoint.
        minimum=paw_floor(mesh,rig,pads[key])
        foot=ankle.matrix.copy();foot.translation.z+=(.00015-minimum)/MODEL_SCALE;set_world_pose(ankle,foot)
        bones=[rig.pose.bones[name] for name in limb['chain']]
        reference={bone.name:bone.matrix.copy() for bone in bones}
        points=[bone.matrix.translation.copy() for bone in bones]
        rest_end=target_neutral[ankle.name].translation-target_neutral[bones[-1].name].translation
        delta_last=reference[bones[-1].name].to_quaternion() @ target_neutral[bones[-1].name].to_quaternion().inverted()
        points.append(points[-1]+delta_last @ rest_end)
        lengths=[(points[i+1]-points[i]).length for i in range(len(bones))]
        placement=0.0
        if key.startswith('front'):
            # Retargeted pad placement is fitted to the acquired model's shorter
            # forelimbs. Keep the supporting pad on the floor and record this
            # anatomical correction separately from the IK reach residual.
            goal=ankle.matrix.translation.copy();vector=goal-points[0]
            reach=sum(lengths)-1e-4
            horizontal=Vector((vector.x,vector.y,0))
            radius=math.sqrt(max(0,reach*reach-vector.z*vector.z))
            if horizontal.length>radius and abs(vector.z)<reach:
                correction=horizontal.normalized()*(radius-horizontal.length)
                placement=correction.length*MODEL_SCALE
                fitted=ankle.matrix.copy();fitted.translation+=correction;set_world_pose(ankle,fitted)
        solved,error=fabrik(points,lengths,ankle.matrix.translation)
        for i,bone in enumerate(bones):
            set_world_pose(bone,aim(reference[bone.name],points[i+1]-points[i],solved[i+1]-solved[i],solved[i]))
        receipts[key]={'reach_residual_m':error*MODEL_SCALE,'segment_lengths_m':[v*MODEL_SCALE for v in lengths],
                       'target_anatomy_foot_placement_m':placement,
                       'pad_floor_m':paw_floor(mesh,rig,pads[key])}
    return receipts


def loop_close(rig, action, end):
    set_action(rig,action);samples=[]
    for frame in (1,2,end-1,end):
        bpy.context.scene.frame_set(frame);samples.append(basis_snapshot(rig))
    corrected=[{}, {}, {}, {}]
    for name in samples[0]:
        values=[pose[name].decompose() for pose in samples]
        p0,q0,s0=values[0];pn,qn,sn=values[-1];qn.make_compatible(q0)
        pc=(p0+pn)*.5;qc=q0.slerp(qn,.5);sc=(s0+sn)*.5
        vp=(values[1][0]-values[2][0])*.5;vs=(values[1][2]-values[2][2])*.5
        logs=[]
        for index in (1,2):
            q=qc.inverted() @ values[index][1]
            if q.w<0:q.negate()
            axis,angle=q.to_axis_angle();logs.append(axis*angle)
        vq=(logs[0]-logs[1])*.5
        for index,sign in enumerate((0,1,-1,0)):
            q=qc.copy()
            if vq.length>1e-10 and sign:q=q @ Quaternion(vq.normalized(),sign*vq.length)
            corrected[index][name]=Matrix.LocRotScale(pc+vp*sign,q,sc+vs*sign)
    for frame,pose in zip((1,2,end-1,end),corrected):
        set_action(rig,None);bpy.context.scene.frame_set(frame);restore_basis(rig,pose);key_pose(rig,action,frame)


def author(base):
    source_path=base/'source/LabradorDog_kenchoo_2k.glb'
    if hashlib.sha256(source_path.read_bytes()).hexdigest()!=SOURCE_SHA:raise RuntimeError('Unexpected Labrador source')
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source_path))
    scene=bpy.context.scene;scene.render.fps=FPS
    rig=next(o for o in scene.objects if o.type=='ARMATURE');mesh=bpy.data.objects['mesh_0'];hair=bpy.data.objects['Object_18']
    original_action=rig.animation_data.action;original_action.name='Source_KenchooIdle';original_action.use_fake_user=True
    scene.frame_set(1);update()
    rig_world=rig.matrix_world.copy();rig.parent=None;rig.matrix_world=rig_world
    rig.name='LabradorPet';mesh.name='LabradorPet_Mesh';hair.name='LabradorPet_MouthFur'
    for bone in rig.pose.bones:bone.rotation_mode='QUATERNION';bone.custom_shape=None
    helper=bpy.data.objects.get('Icosphere')
    if helper:bpy.data.objects.remove(helper,do_unlink=True)
    repairs=repair_weights(base,mesh);mask=coat_mask(base,mesh)
    textures=material_textures(base)
    rig.scale=(MODEL_SCALE,)*3;rig.location.z=.00495;update()
    # Mouse interaction owns squint/blink; prevent an unrelated source timeline
    # from being silently baked into the care loop's eyelid channels.
    if mesh.data.shape_keys:
        mesh.data.shape_keys.animation_data_clear()
        for key in mesh.data.shape_keys.key_blocks:key.value=0
    original_baseline=basis_snapshot(rig);target_neutral={b.name:b.matrix.copy() for b in rig.pose.bones}
    pads={key:pad_indices(mesh,limb['paw']) for key,limb in LIMBS.items()}
    clip_specs=[('IdleFriendly',313,True),('PetEnjoy',120,True)]
    authored=[];sit_poses=[];reach_max=0;clearance_min=1;receipts=[]
    for name,intervals,loop in clip_specs:
        action=bpy.data.actions.new(name);action.use_fake_user=True
        for f in range(intervals+1):
            t=f/intervals
            if name=='IdleFriendly':
                set_action(rig,original_action);scene.frame_set(f+1);update();pose=basis_snapshot(rig)
                set_action(rig,None);restore_basis(rig,pose)
            else:
                set_action(rig,None);restore_basis(rig,original_baseline)
                # Calm standing base: the acquired animal's anatomy stays stable;
                # subtle breathing and distal wag leave ears/head for the mouse.
                chest=rig.pose.bones['Torso2_22'];chest.rotation_quaternion=chest.rotation_quaternion @ Quaternion((1,0,0),math.radians(.2*math.sin(2*math.pi*t)))
                for i,name_tail in enumerate(('Tail2_36','Tail3_35','Tail4_34','Tail5_33','Tail6_32')):
                    bone=rig.pose.bones[name_tail]
                    bone.rotation_quaternion=bone.rotation_quaternion @ Quaternion((0,0,1),math.radians(2.3*math.sin(4*math.pi*t-i*.25)))
                update()
            scene.frame_set(f+1);key_pose(rig,action,f+1)
        if loop:loop_close(rig,action,intervals+1)
        for curve in channels(action):
            for key in curve.keyframe_points:key.interpolation='LINEAR'
        authored.append({'name':name,'frames':[1,intervals+1],'duration':intervals/FPS,'loop':loop,
                         'source':'Original kenchoo idle' if name=='IdleFriendly' else 'Original standing anatomy; authored subtle .2-degree breathing and 2.3-degree distal wag',
                         'source_capture':None,'source_raw_frames':None,'reverse':False})
        print('LABRADOR_AUTHORED',name,flush=True)
    (base/'sit-authoring-contact.json').write_text(json.dumps({'frames':receipts},indent=2)+'\n')
    if reach_max>.008:
        (base/'validation').mkdir(exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(base/'validation/contact-debug.blend'))
        raise RuntimeError(f'Measured sit has unreachable limbs: {reach_max}m')
    set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1);update()
    # Bone-parented, named attachment marker keeps FBX and gameplay paths exact.
    socket=bpy.data.objects.new('MouthSocket',None);bpy.context.collection.objects.link(socket)
    socket.parent=rig;socket.parent_type='BONE';socket.parent_bone='Head_1';update()
    socket.matrix_world=rig.matrix_world @ Matrix.Translation((0,-2.48,2.13));socket.scale=(1/MODEL_SCALE,)*3
    output=base/'export';(output/'Animations').mkdir(parents=True,exist_ok=True);(base/'production').mkdir(exist_ok=True)
    manifest={'fps':FPS,'model':'LabradorPet_Model.fbx','rigRoot':'LabradorPet','rig':'Legacy-compatible same skeleton',
              'headBone':'Head_1','headUpperHelper':'Neck3.001_11','jawBone':'Neck3.002_10','neckBones':['Neck1_14','Neck2_13','Neck3_12'],
              'earBones':{'left':['Ear1.L_5','Ear2.L_4','Ear3.L_3','Ear4.L_2'],'right':['Ear1.R_9','Ear2.R_8','Ear3.R_7','Ear4.R_6']},
              'mouthSocketParent':'Head_1','mouthSocket':'MouthSocket','mouthSocketPosition':list(socket.matrix_basis.translation),
              'mouthSocketPositionSpace':'Blender bone-parent matrix_basis; use exported MouthSocket transform in Unity.',
              'mouthSocketLocalScale':1/MODEL_SCALE,'mouthSocketWorldScale':1,
              'modelScale':MODEL_SCALE,'forward':'Blender -Y; FBX exported -Z forward/Y up for Unity +Z forward/Y up.',
              'textures':textures,'normalScale':.2,'metallicFactor':.0909091,'clips':authored,'weight_repairs':repairs,'coat_mask':mask,
              'source_sha256':SOURCE_SHA,'authoring_contact':{'policy':'Standing rest-support paw controls retained. Full evaluated skin clearance is checked separately.'},
              'scope':'Two standing care clips; no hands. Runtime adds mouse-driven ears/head/coat and happy eyelid response. Raw seated retarget exploration is preserved separately and excluded from the final bundle.'}
    (output/'animation-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (base/'motion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (base/'sit-authoring-contact.json').write_text(json.dumps({'frames':receipts},indent=2)+'\n')
    scene.frame_start=1;scene.frame_end=314
    for image in bpy.data.images:
        if image.filepath:image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(base/'production/LabradorPet_Animations.blend'))
    selected=[rig,mesh,hair,socket]+[o for o in rig.children_recursive if o.type=='EMPTY']
    for o in scene.objects:o.select_set(False)
    for o in selected:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    flags=dict(use_selection=True,object_types={'ARMATURE','MESH','EMPTY'},add_leaf_bones=False,axis_forward='-Z',axis_up='Y',
               apply_scale_options='FBX_SCALE_UNITS',use_armature_deform_only=False,bake_anim_use_all_actions=False,
               bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,path_mode='RELATIVE',colors_type='LINEAR')
    set_action(rig,None);restore_basis(rig,original_baseline)
    bpy.ops.export_scene.fbx(filepath=str(output/'LabradorPet_Model.fbx'),bake_anim=False,**flags)
    for clip in authored:
        set_action(rig,bpy.data.actions[clip['name']]);scene.frame_start=1;scene.frame_end=clip['frames'][1];scene.frame_set(1)
        bpy.ops.export_scene.fbx(filepath=str(output/'Animations'/f"{clip['name']}.fbx"),bake_anim=True,bake_anim_force_startend_keying=True,bake_anim_step=1,**flags)
    if hashlib.sha256(source_path.read_bytes()).hexdigest()!=SOURCE_SHA:raise RuntimeError('Original source changed')
    print('LABRADOR_EXPORTED',len(authored),str(output),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);author(args.base.resolve())
