"""Rig the supplied anatomy itself; never transplant old mesh-index correctives.

Public API: rig_hand(body, nails_by_digit, landmarks, side='left') -> (rig, report).
Landmarks use canonical world metres and expose digits[digit] with root, pip,
dip, tip (or a four-point list). An optional nail_normal overrides PCA orientation.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

DIGITS=('thumb','index','middle','ring','little')
BONES=['wrist']+[d+str(j)for d in DIGITS for j in range(3)]
KEYS=[f'Joint_{d}_{j}'for d in DIGITS for j in range(3)]

def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0.,1.);return t*t*(3.-2.*t)

def coordinates(obj):
    p=np.empty(len(obj.data.vertices)*3,dtype=np.float32);obj.data.vertices.foreach_get('co',p)
    p=p.reshape(-1,3).astype(np.float64);m=np.asarray(obj.matrix_world)
    return p@m[:3,:3].T+m[:3,3]

def evaluated_coordinates(obj):
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh()
    try:
        p=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',p)
        p=p.reshape(-1,3).astype(np.float64);m=np.asarray(ev.matrix_world)
        return p@m[:3,:3].T+m[:3,3]
    finally:ev.to_mesh_clear()

def unit(v):
    v=np.asarray(v,dtype=float);length=np.linalg.norm(v);assert length>1e-10;return v/length

def landmark_frames(landmarks,nails,side):
    records=landmarks.get('digits',landmarks.get('fingers',landmarks))
    frames={}
    for d in DIGITS:
        r=records[d]
        if isinstance(r,(list,tuple)):points=np.asarray(r,dtype=float);normal=None
        else:
            points=np.asarray(r['points']if 'points'in r else[r[k] for k in ('root','pip','dip','tip')],dtype=float)
            normal=r.get('nail_outward_normal',r.get('nail_normal',r.get('dorsal_normal')))
        assert points.shape==(4,3)and np.isfinite(points).all()
        lengths=np.linalg.norm(np.diff(points,axis=0),axis=1)
        assert np.all((lengths>.004)&(lengths<.09)),f'Invalid source joint spacing: {d}/{lengths}'
        npnts=coordinates(nails[d]);center=npnts.mean(axis=0)
        if normal is None:
            values,vectors=np.linalg.eigh(np.cov((npnts-center).T));normal=vectors[:,np.argmin(values)]
            reference=np.array((1. if side=='left'else-1.,0.,0.))if d=='thumb'else np.array((0.,0.,1.))
            if np.dot(normal,reference)<0:normal=-normal
        normal=unit(normal);cross=unit(np.cross(unit(points[-1]-points[-2]),normal))
        nail_width=float(np.ptp(npnts@cross));radius=max(.0045,nail_width*.78)
        frames[d]={'points':points,'lengths':lengths,'nail_normal':normal,'radius':radius}
    return frames

def make_rig(frames,landmarks,side):
    data=bpy.data.armatures.new('Supplied_HandSkeleton_'+side)
    rig=bpy.data.objects.new('Supplied_HandRig_'+side,data);bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    wrist=data.edit_bones.new('wrist')
    wrist.head=Vector(landmarks.get('wrist_head',landmarks.get('wrist_cap_center',landmarks.get('wrist_cap_canonical',(0.,-.05625,0.)))))
    wrist.tail=Vector(landmarks.get('wrist_tail',landmarks.get('wrist',(0.,.016830526,0.))))
    wrist.align_roll(Vector((0,0,1)))
    for d in DIGITS:
        points=frames[d]['points'];parent=wrist
        for j in range(3):
            b=data.edit_bones.new(d+str(j));b.head=Vector(points[j]);b.tail=Vector(points[j+1]);b.parent=parent
            b.use_connect=j>0
            dorsal=frames[d]['nail_normal']if d=='thumb'else np.array((0.,0.,1.))
            axis=unit(points[j+1]-points[j]);dorsal=unit(dorsal-axis*np.dot(axis,dorsal))
            b.align_roll(Vector(dorsal));parent=b
    bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
    assert len(rig.data.bones)==16 and set(rig.data.bones.keys())==set(BONES)
    return rig

def bind_object(obj,rig):
    matrix=obj.matrix_world.copy();obj.parent=rig;obj.matrix_parent_inverse=rig.matrix_world.inverted();obj.matrix_world=matrix
    modifiers=[m for m in obj.modifiers if m.type=='ARMATURE']
    modifier=modifiers[0]if modifiers else obj.modifiers.new('Supplied source anatomy skinning','ARMATURE')
    modifier.object=rig;modifier.use_deform_preserve_volume=False
    modifier.use_vertex_groups=True

def matrix_weights(body):
    matrix=np.zeros((len(body.data.vertices),16),dtype=float);names={g.index:g.name for g in body.vertex_groups}
    for v in body.data.vertices:
        for g in v.groups:
            if names[g.group]in BONES:matrix[v.index,BONES.index(names[g.group])]=g.weight
    return matrix

def source_digit_coordinates(points,frames):
    distances=[];axials=[]
    for d in DIGITS:
        record=frames[d];joints=record['points'];lengths=record['lengths'];ds=[];ss=[];offset=0.
        for j in range(3):
            axis=(joints[j+1]-joints[j])/lengths[j]
            t=np.clip((points-joints[j])@axis,0.,lengths[j])
            closest=joints[j]+t[:,None]*axis
            ds.append(np.linalg.norm(points-closest,axis=1));ss.append(offset+t);offset+=lengths[j]
        ds=np.column_stack(ds);ss=np.column_stack(ss);indices=np.argmin(ds,axis=1);rows=np.arange(len(points))
        distance=ds[rows,indices];s=ss[rows,indices]
        proximal=(points-joints[0])@unit(joints[1]-joints[0]);s=np.where(proximal<0,proximal,s)
        distances.append(distance);axials.append(s)
    distances=np.column_stack(distances);axials=np.column_stack(axials)
    owner=np.argmin(distances,axis=1)
    return owner,distances,axials

def fallback_weights(points,frames):
    owner,distances,axials=source_digit_coordinates(points,frames)
    result=np.zeros((len(points),16),dtype=float)
    for di,d in enumerate(DIGITS):
        chosen=owner==di;s=axials[chosen,di];lengths=frames[d]['lengths'];radius=frames[d]['radius']
        radial=1.-smooth(radius*1.6,radius*3.0,distances[chosen,di])
        gate=smooth(-min(.015,lengths[0]*.45),min(.012,lengths[0]*.35),s)*radial
        width0=min(lengths[0],lengths[1])*.27;width1=min(lengths[1],lengths[2])*.27
        w0=1.-smooth(lengths[0]-width0,lengths[0]+width0,s)
        w2=smooth(lengths[0]+lengths[1]-width1,lengths[0]+lengths[1]+width1,s)
        w1=np.maximum(0.,1.-w0-w2);weights=np.column_stack((w0,w1,w2));weights/=weights.sum(axis=1)[:,None]
        result[chosen,0]=1.-gate;result[np.ix_(chosen,[BONES.index(d+str(j))for j in range(3)])]=weights*gate[:,None]
    return result

def assign_weights(body,weights):
    weights=np.maximum(0.,weights);weights/=weights.sum(axis=1)[:,None]
    # Keep at most four influences per vertex for the existing game skinning path.
    order=np.argsort(weights,axis=1);rows=np.arange(len(weights))[:,None];weights[rows,order[:,:-4]]=0
    weights/=weights.sum(axis=1)[:,None]
    body.vertex_groups.clear();groups=[body.vertex_groups.new(name=n)for n in BONES]
    for i,row in enumerate(weights):
        for j in np.flatnonzero(row>1e-8):groups[j].add([i],float(row[j]),'REPLACE')
    return weights

def nail_surface_trees(nails):
    return {d:BVHTree.FromPolygons([Vector(p)for p in coordinates(n)], [tuple(f.vertices)for f in n.data.polygons])for d,n in nails.items()}

def bind_body(body,rig,frames,nails):
    points=coordinates(body);before=points.copy();heat_error=None
    try:
        bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
        bpy.ops.object.parent_set(type='ARMATURE_AUTO',keep_transform=True)
        weights=matrix_weights(body);sums=weights.sum(axis=1)
        assert np.isfinite(weights).all()and np.all(sums>1e-5),'Bone heat left unweighted source vertices'
        weights/=sums[:,None]
        owner,distances,axials=source_digit_coordinates(points,frames)
        violations=[]
        for di,d in enumerate(DIGITS):
            distal=(owner==di)&(axials[:,di]>sum(frames[d]['lengths'][:2])+.003)&(distances[:,di]<frames[d]['radius']*1.6)
            own=weights[:,[BONES.index(d+str(j))for j in range(3)]].sum(axis=1)
            if np.count_nonzero(distal)and np.min(own[distal])<.80:violations.append(d)
        assert not violations,'Bone heat leaked distal finger ownership: '+','.join(violations)
        method='Blender bone heat, with source nail-bed attachment protection'
    except Exception as error:
        heat_error=str(error);weights=fallback_weights(points,frames);method='Source centerline restricted distance weights'
    bind_object(body,rig)
    trees=nail_surface_trees(nails);bed_counts={};nail_distance=np.full(len(points),np.inf)
    # Protect each real source nail contact region as a distal-phalanx surface.
    for d,tree in trees.items():
        distances=np.asarray([tree.find_nearest(Vector(p))[3]for p in points]);nail_distance=np.minimum(nail_distance,distances)
        blend=1.-smooth(.00125,.0035,distances);active=blend>0
        weights[active]*=(1.-blend[active,None]);weights[active,BONES.index(d+'2')]+=blend[active]
        bed_counts[d]=int(np.count_nonzero(blend>.999))
    weights=assign_weights(body,weights)
    assert float(np.max(np.abs(coordinates(body)-before)))<1e-7,'Binding moved the supplied neutral geometry'
    for d,n in nails.items():
        bind_object(n,rig);n.vertex_groups.clear();group=n.vertex_groups.new(name=d+'2');group.add(list(range(len(n.data.vertices))),1.,'REPLACE')
    return weights,nail_distance,{'method':method,'bone_heat_error':heat_error,'nail_bed_rigid_vertex_counts':bed_counts}

def create_correctives(body,rig,frames,weights,nail_distance):
    assert body.data.shape_keys is None,'Prepared source unexpectedly contains old shape keys'
    body.shape_key_add(name='Basis',from_mix=False);body.data.shape_keys.use_relative=True
    points=coordinates(body);inverse=np.asarray(body.matrix_world.inverted())[:3,:3];report={}
    for di,d in enumerate(DIGITS):
        influence=weights[:,[BONES.index(d+str(j))for j in range(3)]].sum(axis=1)
        for j in range(3):
            bone=rig.data.bones[d+str(j)];head=np.asarray(rig.matrix_world@bone.head_local)
            axis=unit(np.asarray((rig.matrix_world.to_3x3()@bone.matrix_local.to_3x3().col[1])))
            q=points-head;along=q@axis;radial=q-along[:,None]*axis;radius=np.linalg.norm(radial,axis=1)
            unit_radial=radial/np.maximum(radius,1e-10)[:,None]
            span=min(.014,max(.007,frames[d]['lengths'][j]*.42))
            axial=np.exp(-((along/(span*.60))**2))*(1.-smooth(span*.75,span,np.abs(along)))
            radial_gate=1.-smooth(frames[d]['radius']*1.4,frames[d]['radius']*2.3,radius)
            guard=smooth(.0018,.0045,nail_distance)
            amplitude=(.00024 if j!=1 else .00034)*axial*radial_gate*influence*guard
            delta=unit_radial*amplitude[:,None]
            name=f'Joint_{d}_{j}';key=body.shape_key_add(name=name,from_mix=False);key.slider_min=0.;key.slider_max=1.;key.value=0.
            local=delta@inverse.T
            for i in np.flatnonzero(amplitude>1e-9):key.data[int(i)].co+=Vector(local[i])
            active=int(np.count_nonzero(amplitude>1e-6));maximum=float(amplitude.max())
            assert active>=5 and maximum>1e-5,f'No meaningful actual joint corrective: {name}/{active}/{maximum}'
            report[name]={'active_vertices_over_1um':active,'maximum_displacement_m':maximum,'axial_support_m':span,
                'source_joint_head_world':head.tolist(),'method':'Small radial volume correction, localized in the actual source joint frame and weighted digit region; nail bed protected.'}
    assert [k.name for k in body.data.shape_keys.key_blocks[1:]]==KEYS
    return report

def inspect_binding(body,nails,rig):
    weights=matrix_weights(body);sums=weights.sum(axis=1)
    assert np.isfinite(weights).all()and np.all(sums>.999999)&np.all(sums<1.000001)
    report={'vertices':len(weights),'maximum_weight_sum_error':float(np.abs(sums-1.).max()),
        'unweighted_vertices':int(np.count_nonzero(sums<1e-6)),'maximum_influences':int(np.count_nonzero(weights>0,axis=1).max()),
        'bone_vertex_counts':{n:int(np.count_nonzero(weights[:,i]>1e-6))for i,n in enumerate(BONES)},'rigid_nails':{}}
    assert report['maximum_influences']<=4
    assert all(report['bone_vertex_counts'][n]>0 for n in BONES),'An actual anatomical bone has no affected vertices'
    for d,n in nails.items():
        assert [g.name for g in n.vertex_groups]==[d+'2']
        assert all(len(v.groups)==1 and abs(v.groups[0].weight-1.)<1e-8 for v in n.data.vertices)
        report['rigid_nails'][d]={'vertices':len(n.data.vertices),'group':d+'2','weight':1.}
    return report

def inspect_quarter_flex(body,nails,rig):
    baseline=evaluated_coordinates(body);saved={b.name:b.matrix_basis.copy()for b in rig.pose.bones};rows={}
    initial_nails={d:evaluated_coordinates(n)for d,n in nails.items()}
    try:
        for d in DIGITS:
            for j in range(3):
                name=d+str(j);bone=rig.pose.bones[name];angle=.25*((60,70,80)if d=='thumb'else(90,110,80))[j]
                bone.matrix_basis=saved[name]@Matrix.Rotation(-math.radians(angle),4,'X')
                key=body.data.shape_keys.key_blocks[f'Joint_{d}_{j}'];key.value=.25;bpy.context.view_layer.update()
                posed=evaluated_coordinates(body);movement=np.linalg.norm(posed-baseline,axis=1)
                assert np.isfinite(posed).all()and float(movement.max())>.00025,'Actual joint does not deform supplied geometry: '+name
                current_nail=evaluated_coordinates(nails[d]);local=(rig.matrix_world@rig.pose.bones[d+'2'].matrix).inverted()
                rest_inverse=(rig.matrix_world@rig.data.bones[d+'2'].matrix_local).inverted()
                expected=np.asarray([rest_inverse@Vector(p)for p in initial_nails[d]])
                actual=np.asarray([local@Vector(p)for p in current_nail]);nail_error=float(np.linalg.norm(actual-expected,axis=1).max())
                assert nail_error<2e-6,'A nail does not remain rigidly attached to its actual distal bone'
                rows[name]={'tested_degrees':angle,'actual_maximum_skin_movement_m':float(movement.max()),'rigid_nail_local_error_m':nail_error}
                bone.matrix_basis=saved[name];key.value=0.;bpy.context.view_layer.update()
    finally:
        for b in rig.pose.bones:b.matrix_basis=saved[b.name]
        for k in body.data.shape_keys.key_blocks[1:]:k.value=0.
        bpy.context.view_layer.update()
    reset=float(np.linalg.norm(evaluated_coordinates(body)-baseline,axis=1).max());assert reset<1e-7
    return {'actual_25_percent_joint_flex':rows,'neutral_reset_error_m':reset,'all_15_joint_handles_tested':True}

def rig_hand(body,nails,landmarks,side='left'):
    assert side in ('left','right')and body.type=='MESH'and set(nails)==set(DIGITS)
    assert not any(m.type=='ARMATURE'for m in body.modifiers),'Source body already has an armature modifier'
    source_points=coordinates(body);frames=landmark_frames(landmarks,nails,side)
    rig=make_rig(frames,landmarks,side);weights,nail_distance,binding=bind_body(body,rig,frames,nails)
    correctives=create_correctives(body,rig,frames,weights,nail_distance)
    report={'side':side,'rig':rig.name,'bones':{b.name:{'parent':b.parent.name if b.parent else None,
        'head_world':list(rig.matrix_world@b.head_local),'tail_world':list(rig.matrix_world@b.tail_local),
        'local_x_world':list(rig.matrix_world.to_3x3()@b.matrix_local.to_3x3().col[0]),
        'local_z_world':list(rig.matrix_world.to_3x3()@b.matrix_local.to_3x3().col[2])}for b in rig.data.bones},
        'binding':binding,'weight_audit':inspect_binding(body,nails,rig),'new_source_correctives':correctives,
        'native_deformation':inspect_quarter_flex(body,nails,rig)}
    assert np.max(np.abs(coordinates(body)-source_points))<1e-7
    report['supplied_neutral_geometry_preserved']=True;return rig,report

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--landmarks',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert bpy.app.background
    assert not a.output.exists(),'Never overwrite a prepared/rigged source'
    source_sha=hashlib.sha256(a.source.read_bytes()).hexdigest();bpy.ops.wm.open_mainfile(filepath=str(a.source.resolve()))
    body=bpy.data.objects['Supplied_AnatomicalHand'];nails={d:bpy.data.objects['Nail_'+d]for d in DIGITS}
    rig,report=rig_hand(body,nails,json.loads(a.landmarks.read_text()))
    a.output.parent.mkdir(exist_ok=True,parents=True);bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(a.output.resolve()),check_existing=False)
    assert hashlib.sha256(a.source.read_bytes()).hexdigest()==source_sha
    report['source_blend_sha256']=source_sha;report['rigged_blend_sha256']=hashlib.sha256(a.output.read_bytes()).hexdigest()
    report['script_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    a.output.with_suffix('.rig_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SUPPLIED_HAND_RIG_COMPLETE',str(a.output),flush=True)

if __name__=='__main__':main()
