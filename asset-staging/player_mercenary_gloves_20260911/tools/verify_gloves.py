"""Independent, read-only delivery checks for full-finger mercenary gloves.

The builder is never imported. Geometry is compared to the approved source,
and actual exported materials, weights, UVs, morphs and pixels are inspected.
"""
import argparse, hashlib, importlib.util, json, sys, traceback
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

HERE=Path(__file__).resolve().parent
STAGING=HERE.parents[1]
ROLES={'Detailed_Glove_Fingers','Detailed_Glove','Detailed_Trim','Detailed_Sleeve'}
DIGITS=('thumb','index','middle','ring','little')
KEYS=[f'Joint_{d}_{j}' for d in DIGITS for j in range(3)]

def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

legacy=module(STAGING/'player_hands_realism_20260911/tools/verify_hands_realistic.py','gloves_legacy_readonly')
generic=module(STAGING/'player_hands_proportions_20260911/tools/verify_proportions.py','gloves_generic_readonly')
detail=module(STAGING/'player_fingers_detail_20260911/tools/verify_finger_detail.py','gloves_pixel_helpers')
core=legacy.core;generic.legacy=legacy;generic.core=core;detail.legacy=legacy

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def parts_for(scene,rig):
    hand=[o for o in core.rigged_meshes(scene,rig)if 'anatomicalhand' in o.name.lower()]
    assert len(hand)==1
    parts={'hand':hand[0]}
    for prefix in ('WristCuff','Forearm','UpperArm'):
        candidates=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(prefix)]
        assert candidates
        parts[prefix]=min(candidates,key=lambda o:abs(o.matrix_world.translation.x-rig.matrix_world.translation.x))
    return parts

legacy.parts_for=parts_for

def capture(scene,rig):
    result=generic.capture(scene,rig)
    result['objects']={o.name:{'parent':o.parent.name if o.parent else None,
        'matrix_basis':[list(r) for r in o.matrix_basis], 'matrix_parent_inverse':[list(r)for r in o.matrix_parent_inverse]}
        for o in [rig,rig.parent,*parts_for(scene,rig).values()] if o is not None}
    for label,obj in parts_for(scene,rig).items():
        result['parts'][label]['key_names']=[k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else []
    return result

def native_rigs():
    scene=bpy.data.scenes['Bilateral_Realistic_Review'];core.activate(scene)
    rigs=sorted((o for o in scene.objects if o.type=='ARMATURE'),key=lambda r:core.wrist_world(r).x)
    assert len(rigs)==2
    return scene,dict(zip(('left','right'),rigs))

def inspect_coincident_seams(old,new):
    """Check actual positions of source split vertices, including each key."""
    tree=KDTree(12036)
    for i,p in enumerate(old['points'][:12036]):tree.insert(Vector(p),i)
    tree.balance();pairs=set()
    for i,p in enumerate(old['points'][:12036]):
        for unused,j,unused_distance in tree.find_range(Vector(p),1e-6):
            if j>i:pairs.add((i,j))
    assert pairs,'No real physical seam witnesses were collected'
    pairs=np.asarray(sorted(pairs),dtype=np.int64);rows={}
    for key in ['Basis',*KEYS]:
        p=new['points'] if key=='Basis' else new['points']+new['deltas'][key]
        source=old['points'] if key=='Basis' else old['points']+old['deltas'][key]
        distance=np.linalg.norm(p[pairs[:,0]]-p[pairs[:,1]],axis=1)
        before=np.linalg.norm(source[pairs[:,0]]-source[pairs[:,1]],axis=1)
        worst=int(np.argmax(distance));maximum=float(distance[worst])
        # Some approved corrective vectors already differ across duplicate
        # vertices by a few micrometres. They remain exactly preserved in this
        # task; require no meaningful regression instead of rewriting the rig.
        limits=np.full(len(pairs),2e-6)if key=='Basis'else np.maximum(2e-6,before+.2e-6)
        violations=np.flatnonzero(distance>limits)
        if len(violations):
            i=int(violations[np.argmax(distance[violations]-limits[violations])])
            raise AssertionError('Physical split seam opens in '+key+': '+json.dumps({'vertices':pairs[i].tolist(),'source_gap_m':float(before[i]),'candidate_gap_m':float(distance[i]),'allowed_gap_m':float(limits[i])}))
        rows[key]={'maximum_actual_seam_gap_m':maximum,'source_maximum_gap_m':float(before.max()),
            'maximum_added_gap_m':float((distance-before).max()),'source_pairs_exceeding_2um':int(np.count_nonzero(before>2e-6)),
            'candidate_pairs_exceeding_2um':int(np.count_nonzero(distance>2e-6))}
    return {'source_coincident_vertex_pairs':len(pairs),'per_shape_key':rows,
        'basis_at_most_2um_and_correctives_within_inherited_limits':True,
        'limit_description':'Basis <= 2 micrometres. Each corrective pair <= max(2 micrometres, corresponding source gap + 0.2 micrometres), because original corrective vectors are preserved.'}

def finger_basecolor_samples(scene,rig):
    """Read each hand's actual face UVs; a shared atlas hash is insufficient."""
    hand=parts_for(scene,rig)['hand'];mesh=hand.data
    material=next(m for m in mesh.materials if m.name in ('Detailed_Skin','Detailed_Glove_Fingers'))
    image=material.node_tree.nodes['Baked_basecolor'].image
    assert tuple(image.size)==(4096,4096)
    p=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(p)
    p=p.reshape(4096,4096,image.channels)
    groups={g.index:g.name for g in hand.vertex_groups}
    ownership=np.asarray([[sum(g.weight for g in v.groups if groups[g.group].startswith(d))for d in DIGITS]for v in mesh.vertices])
    result={d:[]for d in DIGITS}
    for face in mesh.polygons:
        if mesh.materials[face.material_index]!=material:continue
        uv=np.mean([mesh.uv_layers.active.data[i].uv[:]for i in face.loop_indices],axis=0)
        x,y=np.clip((np.mod(uv,1)*4096).astype(np.int64),0,4095)
        digit=DIGITS[int(np.argmax(np.mean(ownership[list(face.vertices)],axis=0)))]
        result[digit].append(p[y,x,:3].copy())
    return {d:np.asarray(values)for d,values in result.items()}

def compare_finger_basecolor_samples(original,current):
    report={}
    for d,old in original.items():
        new=current[d];assert new.shape==old.shape and len(new)>=20 and np.isfinite(new).all()
        difference=np.max(np.abs(new-old),axis=1);changed=float(np.mean(difference>.03))
        row={'actual_face_uv_samples':len(new),'fraction_changed_more_than_003':changed,
            'source_median_rgb':np.median(old,axis=0).tolist(),'new_median_rgb':np.median(new,axis=0).tolist(),
            'mean_absolute_rgb_difference':float(np.abs(new-old).mean())}
        report[d]=row
        assert changed>=.95,'Exposed source skin persists on actual '+d+' UV surfaces: '+json.dumps(row)
    return report

def validate_preservation(source,current):
    assert source['rest']==current['rest'] and len(current['rest'])==16,'Sixteen bone rest transforms changed'
    assert source['objects']==current['objects'],'Retained object or parent transforms changed'
    rows={}
    for label,old in source['parts'].items():
        new=current['parts'][label]
        for field in ('faces','weights','uv_layers','face_materials','key_names','flex'):
            assert old[field]==new[field],f'Protected {field} changed on {label}'
        assert [n.replace('Detailed_Skin','Detailed_Glove_Fingers')for n in old['materials']]==new['materials']
        assert old['points'].shape==new['points'].shape and np.isfinite(new['points']).all()
        assert list(old['deltas'])==list(new['deltas'])
        delta=new['points']-old['points'];distance=np.linalg.norm(delta,axis=1)
        for name,values in new['deltas'].items():
            assert np.isfinite(values).all()
            assert float(np.linalg.norm(values-old['deltas'][name],axis=1).max())<4e-8,'Joint corrective vector changed: '+name
        if label!='hand':
            assert np.array_equal(old['points'],new['points']),'Unrelated arm/cuff geometry moved'
            rows[label]={'positions_topology_uv_weights_exact':True};continue
        assert len(new['points'])==14988 and list(new['deltas'])==KEYS
        allowed=np.zeros(14988,dtype=bool);protected=allowed.copy()
        for face,mi in zip(old['faces'],old['face_materials']):
            (allowed if old['materials'][mi]=='Detailed_Skin' else protected)[list(face)]=True
        allowed&=~protected;allowed[12036:]=False
        assert np.array_equal(old['points'][~allowed],new['points'][~allowed]),'Original glove/shared boundary geometry moved'
        assert float(distance.max())<.004,'Glove shell changed the approved hand proportions excessively'
        counts={d:sum(distance[i]>1e-6 for i,w in enumerate(old['weights'])if sum(v for k,v in w.items()if k.startswith(d))>.8)for d in DIGITS}
        assert all(n>5 for n in counts.values()),'A finger has no measurable glove shell'
        # Same indexed faces preserve the source tip closures and all connected
        # surface components. Check every authored triangle for finite area.
        triangles=np.asarray([(f[0],f[j],f[j+1])for f in new['faces']for j in range(1,len(f)-1)])
        pts=new['points'][triangles];areas=np.linalg.norm(np.cross(pts[:,1]-pts[:,0],pts[:,2]-pts[:,0]),axis=1)
        oldpts=old['points'][triangles];oldareas=np.linalg.norm(np.cross(oldpts[:,1]-oldpts[:,0],oldpts[:,2]-oldpts[:,0]),axis=1)
        assert np.isfinite(areas).all() and np.all(areas[oldareas>1e-14]>1e-14),'A formerly valid finger surface collapsed'
        rows[label]={'vertices':14988,'triangles':len(triangles),'topology_and_tip_closures_preserved':True,
            'uv_and_weights_exact':True,'all_15_corrective_vectors_preserved':True,
            'maximum_shell_displacement_m':float(distance.max()),'changed_vertices_by_digit':{d:int(v)for d,v in counts.items()},
            'actual_split_seam_closure':inspect_coincident_seams(old,new)}
    return rows

def inspect_native_materials(scene,out):
    meshes=[o for o in scene.objects if o.type=='MESH']
    assert not any('nail' in o.name.lower()for o in meshes),'Native nail mesh remains'
    materials={m for o in meshes for m in o.data.materials}
    assert {m.name for m in materials}==ROLES,'Production includes an exposed-skin/nail material or a missing glove role'
    arrays={};evidence={}
    for semantic in ('basecolor','normal','roughness'):
        bound=[]
        for m in materials:
            n=m.node_tree.nodes.get('Baked_'+semantic);assert n and n.image
            bound.append(n.image)
            assert n.outputs['Color'].is_linked,'Actual material does not consume its baked map'
        assert len(set(bound))==1
        im=bound[0];assert tuple(im.size)==(4096,4096)and im.packed_file
        path=out/f'realistic_hands_{semantic}.png'
        packed=hashlib.sha256(im.packed_file.data).hexdigest();assert packed==sha(path),'Stale packed map bytes'
        p=np.empty(len(im.pixels),dtype=np.float32);im.pixels.foreach_get(p);assert np.isfinite(p).all()
        arrays[semantic]=p.reshape(4096,4096,im.channels)[:,:,:3].copy()
        evidence[semantic]={'file_sha256':sha(path),'packed_sha256':packed,'packed_bytes_equal_file':True,'dimensions':[4096,4096]}
    return arrays,{'roles':sorted(ROLES),'no_nail_meshes':True,'no_exposed_skin_role':True,'maps':evidence}

def glb_container(path):
    doc,binary=legacy.glb_chunks(path)
    assert len(doc['skins'])==1 and len(doc['skins'][0]['joints'])==16
    roles={m['name']for m in doc['materials']};assert roles==ROLES
    assert not any('nail' in n.get('name','').lower()for n in doc.get('nodes',[]))
    assert not any('nail' in m.get('name','').lower()for m in doc.get('meshes',[]))
    targets=[]
    for m in doc['meshes']:
        names=m.get('extras',{}).get('targetNames',[])
        if names:
            assert names==KEYS
            for p in m['primitives']:
                assert len(p.get('targets',[]))==15
                assert all('POSITION'in t and 'NORMAL'in t for t in p['targets'])
            targets.append(m['name'])
    assert len(targets)==1
    return {'roles':sorted(roles),'no_nail_nodes_or_meshes':True,'no_exposed_skin_material':True,'joints':16,'fifteen_position_and_normal_morphs':targets}

def main():
    p=argparse.ArgumentParser();p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--source-dir',type=Path,default=STAGING/'player_fingers_detail_20260911/mac_output/iteration_10')
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert bpy.app.background
    source,out=a.source_dir.resolve(),a.output_dir.resolve();src=source/'bilateral_hands_finger_detail.blend';dst=out/'bilateral_mercenary_gloves.blend'
    glbs={s:out/f'{s}_mercenary_glove.glb'for s in ('left','right')}
    inputs=[src,dst,Path(__file__),Path(legacy.__file__),Path(generic.__file__),Path(detail.__file__),Path(core.__file__),*glbs.values()]
    inputs+=[source/f'{s}_hand_finger_detail.glb'for s in glbs]
    inputs+=[out/f'realistic_hands_{m}.png'for m in ('basecolor','normal','roughness')]
    hashes={str(f):sha(f)for f in inputs};report={'status':'running','verified_sha256':hashes,'checks':{},'errors':[],
        'limitations':['This bounded asset audit preserves the source indexed closures and checks finite, noncollapsed geometry; visual glove quality and actual game deformation are reviewed separately.']}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(src));scene,rigs=native_rigs();old={s:capture(scene,r)for s,r in rigs.items()}
        old_colors={s:finger_basecolor_samples(scene,r)for s,r in rigs.items()}
        for s in glbs:
            bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source/f'{s}_hand_finger_detail.glb'),bone_heuristic='TEMPERANCE')
            rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');legacy.attach_prior_export_weights(old[s],legacy.snapshot(bpy.context.scene,rig))
        bpy.ops.wm.open_mainfile(filepath=str(dst));scene,rigs=native_rigs();new={s:capture(scene,r)for s,r in rigs.items()}
        atlases,report['checks']['native_materials']=inspect_native_materials(scene,out)
        report['checks']['both_hands_actual_finger_uv_basecolor']={s:compare_finger_basecolor_samples(old_colors[s],finger_basecolor_samples(scene,r))for s,r in rigs.items()}
        for s in glbs:
            report['checks']['editable_'+s]=validate_preservation(old[s],new[s])
            for label,part in new[s]['parts'].items():part['prior_export_weights']=old[s]['parts'][label]['prior_export_weights']
        for s,path in glbs.items():
            row=report['checks'][s+'_glb']={'container':glb_container(path)}
            row['embedded_actual_pixels']=detail.embedded_pixels(path,source/f'{s}_hand_finger_detail.glb',atlases)
            bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path),bone_heuristic='TEMPERANCE')
            rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
            row['actual_geometry_uv_weight_morph_roundtrip']=generic.roundtrip(capture(bpy.context.scene,rig),new[s])
    except Exception as e:report['errors'].append({'error':str(e),'traceback':traceback.format_exc()})
    assert all(sha(f)==h for f,h in hashes.items()),'A read-only input changed during verification'
    report['status']='failed'if report['errors']else'passed';(out/'verification_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('MERCENARY_GLOVE_VERIFICATION',report['status'],json.dumps(report['errors']),flush=True)
    if report['errors']:raise SystemExit(1)

if __name__=='__main__':main()
