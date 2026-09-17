"""Move the flexible wrist start outside rigid skin; no rebake or geometry edit."""
import argparse,copy,hashlib,json,re,shutil,struct,sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from reference_metadata_signatures import snapshot,hashed
from build_reference_hands import collect

OLD=.014;NEW=.028;END=.075

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def patch_blend(source,target):
    old_sha=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source));before=snapshot()
    original_props={o.name:dict(o.items()) for o in bpy.data.objects}
    rows=[]
    for obj in bpy.data.objects:
        if 'wrist_flex_start_z' not in obj:continue
        assert abs(float(obj['wrist_flex_start_z'])-OLD)<1e-8
        assert int(obj['wrist_flex_version'])==1 and abs(float(obj['wrist_flex_end_z'])-END)<1e-8
        obj['wrist_flex_start_z']=NEW
        rows.append({'object':obj.name,'type':obj.type,'before':OLD,'after':NEW})
    assert len(rows)>=4
    # All named objects keep every other custom property too.
    for obj in bpy.data.objects:
        expected=original_props[obj.name].copy()
        if 'wrist_flex_start_z' in expected:expected['wrist_flex_start_z']=NEW
        assert dict(obj.items())==expected
    assert snapshot()==before,'In-memory metadata patch changed payload'
    target.parent.mkdir(parents=True,exist_ok=True);bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(target),check_existing=False,relative_remap=False)
    bpy.ops.wm.open_mainfile(filepath=str(target));after=snapshot();assert after==before,'Saved metadata patch changed payload'
    assert sha(source)==old_sha
    for row in rows:assert abs(float(bpy.data.objects[row['object']]['wrist_flex_start_z'])-NEW)<1e-8
    return {'source':str(source),'source_sha256':old_sha,'output_sha256':sha(target),'changed_properties':rows,
        'all_except_start_property_exact':True,'before_payload_signature':hashed(before),'after_payload_signature':hashed(after),
        'signature_scope':'All mesh attributes/UV/topology/weights/keys, rest/pose matrices, object/material graphs, packed image hashes and filepaths, cameras/render settings/viewports; only named start property excluded.'}

def patch_glb(source,target):
    old=source.read_bytes();size,kind=struct.unpack_from('<II',old,12);assert kind==0x4e4f534a
    raw=old[20:20+size];doc=json.loads(raw);expected=copy.deepcopy(doc);rows=[]
    for index,node in enumerate(expected.get('nodes',[])):
        props=node.get('extras',{})
        if 'wrist_flex_start_z' in props:
            assert props['wrist_flex_start_z']==OLD and props['wrist_flex_end_z']==END and props['wrist_flex_version']==1
            props['wrist_flex_start_z']=NEW;rows.append({'node':index,'name':node.get('name')})
    assert len(rows)==2
    changed,count=re.subn(rb'("wrist_flex_start_z"\s*:\s*)0\.014\b',lambda m:m[1]+b'0.028',raw)
    assert count==2 and len(changed)==len(raw) and json.loads(changed)==expected
    new=old[:20]+changed+old[20+size:]
    assert new[20+size:]==old[20+size:],'Binary chunk changed'
    target.write_bytes(new)
    return {'source_sha256':hashlib.sha256(old).hexdigest(),'output_sha256':sha(target),'changed_nodes':rows,
        'json_diff_only_named_start':True,'whole_binary_chunk_exact':True,'binary_chunk_sha256':hashlib.sha256(old[20+size:]).hexdigest(),
        'file_size_unchanged':len(old)==len(new),'images_accessors_normals_tangents_morphs_weights_bin_exact':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--geometry-source',type=Path,required=True);p.add_argument('--geometry-output',type=Path,required=True)
    p.add_argument('--final-source',type=Path,required=True);p.add_argument('--final-output',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);assert bpy.app.background
    gs,go,fs,fo=[x.resolve() for x in [a.geometry_source,a.geometry_output,a.final_source,a.final_output]]
    assert gs.is_dir() and fs.is_dir() and not go.exists() and not fo.exists(),'Use new output directories'
    all_source_hashes={str(p):sha(p) for root in [gs,fs] for p in root.rglob('*') if p.is_file()}
    go.mkdir();fo.mkdir()
    geometry=patch_blend(gs/'bilateral_hands_reference_geometry.blend',go/'bilateral_hands_reference_geometry.blend')
    report=json.loads((gs/'geometry_report.json').read_text());report['geometry_blend_sha256']=geometry['output_sha256']
    report['wrist_metadata_update']={'start_before':OLD,'start_after':NEW,'end_unchanged':END,'version_unchanged':1,'geometry04_to05':geometry,
        'reason':'Keep the entire rigid anatomical skin overlap z<=.020696754 within the rigid cuff interval; 7.303 mm margin to the new start.'}
    report['status']='metadata_updated_pending_independent_validation_and_game_review'
    (go/'geometry_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
    final=patch_blend(fs/'bilateral_hands_reference.blend',fo/'bilateral_hands_reference.blend')
    glbs={side:patch_glb(fs/f'{side}_hand_reference.glb',fo/f'{side}_hand_reference.glb') for side in ['left','right']}
    copied={}
    for source in fs.iterdir():
        if source.is_file() and (source.suffix=='.png' or source.name=='atlas_padding_report.json' or source.name.endswith('_tangent_repair.json')):
            shutil.copy2(source,fo/source.name);assert sha(source)==sha(fo/source.name);copied[source.name]=sha(source)
    raw=fo/'unfilled_atlas';raw.mkdir()
    for channel in ['basecolor','normal','roughness']:
        name=f'reference_hands_{channel}.png';source=fs/'unfilled_atlas'/name
        shutil.copy2(source,raw/name);assert sha(source)==sha(raw/name)
        copied['unfilled_atlas/'+name]=sha(source)
    material=json.loads((fs/'material_report.json').read_text());material['source']=str(go/'bilateral_hands_reference_geometry.blend');material['source_sha256']=geometry['output_sha256'];material['blend_sha256']=final['output_sha256']
    for side in ['left','right']:
        material['hands'][side]['export']['sha256']=glbs[side]['output_sha256']
    material['status']='metadata_updated_pending_independent_validation_and_game_review'
    material['wrist_metadata_update']={'report':'metadata_update_report.json','start_before':OLD,'start_after':NEW,'end_unchanged':END,
        'render_note':'Neutral Blender renders copied byte-for-byte from final02: geometry/materials/pose/cameras unchanged. Runtime wrist bending requires new Godot capture.'}
    (fo/'material_report.json').write_text(json.dumps(material,indent=2,ensure_ascii=False))
    assert all(sha(Path(p))==expected for p,expected in all_source_hashes.items())
    result={'status':'metadata_only_payload_preservation_passed','start_before':OLD,'start_after':NEW,'end_unchanged':END,'version_unchanged':1,
        'geometry_blend':geometry,'final_blend':final,'glbs':glbs,'copied_payload_sha256':copied,'all_prior_recursive_files_sha_unchanged':True,
        'no_bake_render_or_geometry_operation':True,'independent_runtime_visual_validation':'pending'}
    (fo/'metadata_update_report.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
    print('WRIST_METADATA_PATCH_COMPLETE',json.dumps({'geometry_sha':geometry['output_sha256'],'final_sha':final['output_sha256'],'glbs':glbs}),flush=True)

if __name__=='__main__':main()
