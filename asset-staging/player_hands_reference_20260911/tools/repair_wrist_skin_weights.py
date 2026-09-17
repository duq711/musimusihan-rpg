"""Repair demonstrated skinned wrist-rim separation without rebaking the asset."""
import argparse,copy,hashlib,json,math,re,shutil,struct,sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from reference_weight_signatures import snapshot,hashed
from build_reference_hands import collect

START=.010;END=.018;FLEX_OLD=.028;FLEX_NEW=.026

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]
def blend(z):
    t=max(0.,min(1.,(z-START)/(END-START)));return t*t*(3.-2.*t)
def corrected(weights,z):
    s=blend(z)
    other={name:f32(weight*(1.-s)) for name,weight in weights.items() if name!='wrist'}
    other={name:weight for name,weight in other.items() if weight>0.}
    other['wrist']=f32(1.-sum(other.values()))
    return other

def evaluated(obj):
    deps=bpy.context.evaluated_depsgraph_get();obj_e=obj.evaluated_get(deps);mesh=obj_e.to_mesh()
    matrix=obj_e.matrix_world;norm=matrix.to_3x3().inverted().transposed()
    result=([matrix@v.co for v in mesh.vertices],[(norm@v.normal).normalized() for v in mesh.vertices])
    obj_e.to_mesh_clear();return result

def all_weights():
    return {m.name:hashed([[(g.group,g.weight) for g in v.groups] for v in m.vertices]) for m in bpy.data.meshes}

def patch_blend(source,target):
    before_sha=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Reference_Review'];bpy.context.window.scene=scene
    hands=collect(scene);before=snapshot();weights_before=all_weights();rows={};changed_meshes=set();eval_before={side:evaluated(row[3]) for side,row in hands.items()}
    for side,(holder,objects,rig,skin,nails) in hands.items():
        assert skin.data not in changed_meshes;changed_meshes.add(skin.data)
        matrix=holder.matrix_world.inverted()@skin.matrix_world
        names={g.index:g.name for g in skin.vertex_groups};groups={g.name:g for g in skin.vertex_groups};assert 'wrist' in groups
        changes=[];morph_max={k.name:0. for k in skin.data.shape_keys.key_blocks[1:]}
        basis=skin.data.shape_keys.key_blocks[0]
        for vertex in skin.data.vertices:
            z=-(matrix@vertex.co).y
            if z<=START:continue
            old={names[g.group]:g.weight for g in vertex.groups};new=corrected(old,z)
            if old==new:continue
            for name in old.keys()-new.keys():groups[name].remove([vertex.index])
            for name,weight in new.items():groups[name].add([vertex.index],weight,'REPLACE')
            changes.append({'vertex':vertex.index,'native_godot_z':z,'ramp':blend(z),'before':old,'after':new})
            if z>=END:
                for key in skin.data.shape_keys.key_blocks[1:]:
                    delta=matrix.to_3x3()@(key.data[vertex.index].co-basis.data[vertex.index].co)
                    morph_max[key.name]=max(morph_max[key.name],delta.length)
        skin.data.update()
        rows[side]={'mesh':skin.data.name,'instances':[o.name for o in bpy.data.objects if o.type=='MESH' and o.data==skin.data],
            'changed_vertices':len(changes),'vertices':changes,'boundary_morph_delta_max_m':morph_max,'morphs_modified':False}
    metadata=[]
    for obj in bpy.data.objects:
        if 'wrist_flex_start_z' not in obj:continue
        assert abs(float(obj['wrist_flex_start_z'])-FLEX_OLD)<1e-8
        assert float(obj['wrist_flex_end_z'])==.075 and int(obj['wrist_flex_version'])==1
        obj['wrist_flex_start_z']=FLEX_NEW;metadata.append(obj.name)
    bpy.context.view_layer.update();eval_after={side:evaluated(row[3]) for side,row in hands.items()}
    neutral={}
    for side in hands:
        a,b=eval_before[side],eval_after[side]
        neutral[side]={'max_position_error_m':max((x-y).length for x,y in zip(a[0],b[0])),
                       'max_unit_normal_error':max((x-y).length for x,y in zip(a[1],b[1]))}
        assert neutral[side]['max_position_error_m']<2e-7 and neutral[side]['max_unit_normal_error']<2e-5
    assert before==snapshot(),'Unexpected geometry/key/UV/rest/pose/material/image/camera/world/light change'
    weights_after=all_weights();allowed={m.name for m in changed_meshes}
    assert all(weights_after[name]==value for name,value in weights_before.items() if name not in allowed)
    expected_weights=weights_after.copy();target.parent.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(target),check_existing=False,relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(target));assert snapshot()==before and all_weights()==expected_weights
    assert sha(source)==before_sha
    return {'source':str(source),'source_sha256':before_sha,'output_sha256':sha(target),'hands':rows,
            'geometry_keys_uv_materials_images_rest_pose_cameras_world_lights_exact':True,
            'before_frozen_signature':hashed(before),'after_reopen_frozen_signature':hashed(snapshot()),
            'unrelated_mesh_weights_exact':True,'neutral_evaluated':neutral,'metadata_objects':metadata,
            'source_unchanged':True,'weight_formula':'For z>.010, s=smoothstep(.010,.018,z); nonWrist=float32(old*(1-s)); wrist=float32(1-sum(rounded nonWrist)); zero nonWrist influences removed. z<=.010 untouched.'}

def ranges(offsets):
    ordered=sorted(offsets);result=[]
    for value in ordered:
        if result and result[-1][1]==value:result[-1][1]=value+1
        else:result.append([value,value+1])
    return result

def patch_glb(source,target):
    old=source.read_bytes();size,kind=struct.unpack_from('<II',old,12);assert kind==0x4e4f534a
    raw=old[20:20+size];doc=json.loads(raw);base=20+size+8;data=bytearray(old);allowed=set();changes=[];joint_changes=[]
    def layout(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];n={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];fmt={5126:'f',5121:'B',5123:'H',5125:'I'}[a['componentType']];step=struct.calcsize(fmt)*n
        return a,fmt,n,base+v.get('byteOffset',0)+a.get('byteOffset',0),v.get('byteStride',step)
    def read(index,i):
        a,fmt,n,start,stride=layout(index);return list(struct.unpack_from('<'+fmt*n,old,start+i*stride))
    def write(index,i,slot,value):
        a,fmt,n,start,stride=layout(index);offset=start+i*stride+slot*struct.calcsize(fmt);packed=struct.pack('<'+fmt,value);data[offset:offset+len(packed)]=packed;allowed.update(range(offset,offset+len(packed)))
    for node in doc['nodes']:
        if 'Anatomical' not in node.get('name','') or 'mesh' not in node:continue
        skin=doc['skins'][node['skin']];bone_names=[doc['nodes'][j]['name'] for j in skin['joints']];wrist=bone_names.index('wrist')
        for primitive_index,p in enumerate(doc['meshes'][node['mesh']]['primitives']):
            attrs=p['attributes'];sets=[k for k in [0,1] if 'WEIGHTS_'+str(k) in attrs]
            for i in range(doc['accessors'][attrs['POSITION']]['count']):
                z=read(attrs['POSITION'],i)[2]
                if z<=START:continue
                slots=[]
                for group in sets:
                    ji,wi=attrs['JOINTS_'+str(group)],attrs['WEIGHTS_'+str(group)]
                    assert doc['accessors'][wi]['componentType']==5126
                    slots.extend({'joint':j,'weight':w,'joint_accessor':ji,'weight_accessor':wi,'slot':slot} for slot,(j,w) in enumerate(zip(read(ji,i),read(wi,i))))
                named={bone_names[s['joint']]:s['weight'] for s in slots if s['weight']>0.};desired=corrected(named,z)
                wrist_slot=next((s for s in slots if s['joint']==wrist and s['weight']>0.),None)
                if wrist_slot is None:
                    wrist_slot=next(s for s in slots if s['weight']==0.)
                    if wrist_slot['joint']!=wrist:
                        write(wrist_slot['joint_accessor'],i,wrist_slot['slot'],wrist);joint_changes.append({'vertex':i,'old_joint':wrist_slot['joint'],'new_joint':wrist})
                    wrist_slot['joint']=wrist
                for slot in slots:
                    value=desired['wrist'] if slot is wrist_slot else (desired.get(bone_names[slot['joint']],0.) if slot['weight']>0 and slot['joint']!=wrist else 0.)
                    write(slot['weight_accessor'],i,slot['slot'],value)
                changes.append({'mesh':node['name'],'primitive':primitive_index,'vertex':i,'native_godot_z':z,'ramp':blend(z),'before':named,'after':desired})
    expected=copy.deepcopy(doc);metadata=[]
    for i,node in enumerate(expected['nodes']):
        props=node.get('extras',{})
        if 'wrist_flex_start_z'in props:
            assert props['wrist_flex_start_z']==FLEX_OLD;props['wrist_flex_start_z']=FLEX_NEW;metadata.append(i)
    changed_json,count=re.subn(rb'("wrist_flex_start_z"\s*:\s*)0\.028\b',lambda m:m[1]+b'0.026',raw)
    assert count==2 and len(changed_json)==len(raw) and json.loads(changed_json)==expected
    data[20:20+size]=changed_json
    actual={i for i,(a,b) in enumerate(zip(old[base:],data[base:]),base) if a!=b}
    assert actual<=allowed and len(data)==len(old)
    masked_before=bytearray(old[base:]);masked_after=bytearray(data[base:])
    for i in allowed:masked_before[i-base]=0;masked_after[i-base]=0
    assert masked_before==masked_after
    target.write_bytes(data)
    return {'source_sha256':hashlib.sha256(old).hexdigest(),'output_sha256':sha(target),
            'changed_vertices':len(changes),'vertices':changes,'joint_changes':joint_changes,'metadata_nodes':metadata,
            'allowed_binary_ranges_file_offsets':ranges(allowed),'actual_changed_binary_ranges_file_offsets':ranges(actual),
            'all_other_binary_bytes_exact':True,'masked_binary_sha256':hashlib.sha256(masked_before).hexdigest(),
            'json_change_only_start_028_to026':True,'file_size_unchanged':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--geometry-source',type=Path,required=True);p.add_argument('--geometry-output',type=Path,required=True)
    p.add_argument('--final-source',type=Path,required=True);p.add_argument('--final-output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert bpy.app.background
    gs,go,fs,fo=[v.resolve() for v in [a.geometry_source,a.geometry_output,a.final_source,a.final_output]]
    assert not go.exists() and not fo.exists();originals={str(p):sha(p) for root in [gs,fs] for p in root.rglob('*') if p.is_file()};go.mkdir();fo.mkdir()
    geometry=patch_blend(gs/'bilateral_hands_reference_geometry.blend',go/'bilateral_hands_reference_geometry.blend')
    report=json.loads((gs/'geometry_report.json').read_text());report['geometry_blend_sha256']=geometry['output_sha256'];report['wrist_weight_update']={'report':'weight_update_report.json','details':geometry,'flex_start_before':FLEX_OLD,'flex_start_after':FLEX_NEW};report['status']='weights_corrected_pending_independent_and_game_validation'
    (go/'geometry_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
    final=patch_blend(fs/'bilateral_hands_reference.blend',fo/'bilateral_hands_reference.blend');glbs={s:patch_glb(fs/f'{s}_hand_reference.glb',fo/f'{s}_hand_reference.glb') for s in ['left','right']}
    copied={}
    for source in fs.iterdir():
        if source.is_file() and (source.suffix=='.png' or source.name in ['atlas_padding_report.json','metadata_update_report.json'] or source.name.endswith('_tangent_repair.json')):
            shutil.copy2(source,fo/source.name);assert sha(source)==sha(fo/source.name);copied[source.name]=sha(source)
    raw=fo/'unfilled_atlas';raw.mkdir()
    for channel in ['basecolor','normal','roughness']:
        source=fs/'unfilled_atlas'/f'reference_hands_{channel}.png';shutil.copy2(source,raw/source.name);copied['unfilled_atlas/'+source.name]=sha(source);assert sha(raw/source.name)==sha(source)
    material=json.loads((fs/'material_report.json').read_text());material['source']=str(go/'bilateral_hands_reference_geometry.blend');material['source_sha256']=geometry['output_sha256'];material['blend_sha256']=final['output_sha256']
    for s in ['left','right']:material['hands'][s]['export']['sha256']=glbs[s]['output_sha256']
    material['wrist_weight_update']={'report':'weight_update_report.json','flex_start_before':FLEX_OLD,'flex_start_after':FLEX_NEW,'neutral_render_provenance':'Copied exact final02/03 neutral renders; geometry/material/world/lights/cameras exact, actual neutral evaluated position and normal tolerances measured despite changed skin weights.'};material['status']='weights_corrected_pending_independent_and_game_validation'
    (fo/'material_report.json').write_text(json.dumps(material,indent=2,ensure_ascii=False))
    assert all(sha(Path(p))==value for p,value in originals.items())
    result={'status':'weight_and_metadata_patch_preservation_passed','source_final03_immutable':True,'geometry':geometry,'final':final,'glbs':glbs,'copied_payload_sha256':copied,
            'flex_start_before':FLEX_OLD,'flex_start_after':FLEX_NEW,'flex_end_unchanged':.075,'flex_version_unchanged':1,
            'preservation_scope':'Only approved skin weights and named start metadata change. Mesh geometry, normals, UV, morph deltas, rest, material/images, lights/world/cameras unchanged; neutral evaluated appearance measured.',
            'no_rebake_no_render_no_geometry_edit':True,'new_game_validation':'pending'}
    (fo/'weight_update_report.json').write_text(json.dumps(result,indent=2,ensure_ascii=False));(go/'weight_update_report.json').write_text(json.dumps({'status':result['status'],'geometry':geometry,'flex_start_before':FLEX_OLD,'flex_start_after':FLEX_NEW},indent=2,ensure_ascii=False))
    print('WRIST_WEIGHTS_PATCH_COMPLETE',json.dumps({'geometry_sha':geometry['output_sha256'],'final_sha':final['output_sha256'],'glbs':{s:r['output_sha256'] for s,r in glbs.items()},'neutral':final['neutral_evaluated']}),flush=True)

if __name__=='__main__':main()
