"""Package the actual original-style proportion edit after independent review."""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--visually-reviewed',action='store_true');args=parser.parse_args()
    assert args.visually_reviewed
    stage=Path(__file__).resolve().parents[1];project=stage.parents[1];game=project/'godot-game';model=stage/'mac_output/iteration_01'
    independent=read(model/'verification_report.json');assert independent['status']=='passed' and not independent['errors']
    for path,value in independent['verified_sha256'].items():assert sha(Path(path))==value,path
    models={p.name:sha(p) for p in [model/'bilateral_hands_proportions.blend',*sorted(model.glob('*.glb'))]}
    for side in ('left','right'):assert models[f'{side}_hand_proportions.glb']==sha(game/f'assets/3d/player/hands_detailed/{side}_hand_detailed.glb')
    headless=stage/'godot_proportions_final01.log';log=headless.read_text()
    assert 'Headless validation: 7 passed, 0 failed.' in log and 'ERROR:' not in log
    prior=read(stage/'baseline/preserved_artifacts.json');assert all(sha(project/p)==value for p,value in prior.items())
    previews={};source_paths=set()
    expected_images={
        'player_finger_joints':{'open.png','palm.png','wrist_side.png','roots.png','middles.png','tips.png','fist.png','bow_draw.png','chest_touch.png','controls.png','skin_dorsal_neutral.png','skin_palm_neutral.png'},
        'player_hands_detailed':{'free_hands.png','free_hands_greybox.png','bow_draw.png','bow_release.png','chest_touch.png','chest_lift.png'}}
    for kind,count in [('player_finger_joints',12),('player_hands_detailed',6)]:
        folder=game/'artifacts/visual_qa'/kind/'proportions_final_01';manifest=read(folder/'capture_manifest.json')
        assert len(manifest['captures'])==count and not manifest['failures']
        assert {c['image'] for c in manifest['captures']}==expected_images[kind]
        assert manifest['display_driver']=='embedded' and manifest['actual_renderer']=='vulkan'
        assert manifest['sources_unchanged_during_capture'] and manifest['expedition_inventory_and_cursor_preserved']
        for p,value in manifest['source_sha256'].items():
            relative=p.removeprefix('res://');assert sha(game/relative)==value;source_paths.add(relative)
        for capture in manifest['captures']:
            assert capture['passed'] and sha(folder/capture['image'])==capture['image_sha256']
            if kind=='player_finger_joints':assert capture['wrist_gpu_buffers']['passed'] and capture['actual_pbr_bindings']['passed']
        previews[kind]={'count':count,'all_directly_visually_reviewed':True,'manifest_sha256':sha(folder/'capture_manifest.json')}
    native=['preview_finger_dorsum.png','hand_dorsum.png','hand_palm.png','hand_palm_upright.png']
    build=read(model/'build_report.json')
    for render in build['renders'].values():
        assert render['actual_blender_render'] and render['same_original_lights_and_materials']
        assert sha(model/render['file'])==render['sha256']
    palm=read(model/'palm_review.json')
    assert palm['actual_blender_render'] and palm['model_hashes_unchanged'] and palm['upright_world_y_camera']
    assert palm['file']=='hand_palm_upright.png' and sha(model/palm['file'])==palm['sha256']
    assert build['blend_sha256']==models['bilateral_hands_proportions.blend']
    textures=build['textures_unchanged_sha256']
    for name,value in textures.items():assert sha(model/name)==value
    summary={'status':'passed','scope':'Original gloved realism04 model; proportions only, retaining authored material and detail content.',
        'model_sha256':models,'independent_report_sha256':sha(model/'verification_report.json'),'headless':{'passed':7,'failed':0,'log_sha256':sha(headless)},
        'previews':previews,'native_render_sha256':{name:sha(model/name) for name in native},'native_renders_directly_reviewed':True,
        'preferred_palm_render':'hand_palm_upright.png','texture_sha256':textures,'reference_match':read(stage/'reference_match.json'),
        'preserved_prior_files':len(prior),'all_prior_hashes_unchanged':True,
        'limitations':['Ratios are artistic estimates from a single perspective reference, not calibrated anatomical measurements.','Original source detail is retained; no new skin or nail sculpting was requested.','The unrelated full project suite was not run.'],
        'tool_source_sha256':{p.name:sha(p) for p in sorted((stage/'tools').glob('*.py'))}}
    (stage/'validation_summary.json').write_text(json.dumps(summary,indent=2))
    dest=project/'exports/Player_Hands_Proportions_2026-09-11';archive=dest.with_suffix('.zip');assert not dest.exists() and not archive.exists();dest.mkdir()
    def copy(a,b):b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
    for p in model.iterdir():
        if p.is_file() and p.suffix in ('.blend','.glb','.png','.json'):copy(p,dest/p.name)
    for p in (stage/'tools').glob('*.py'):copy(p,dest/'tools'/p.name)
    for name in ('verify_hands_realistic.py','joint_verification_core.py'):copy(stage.parent/'player_hands_realism_20260911/tools'/name,dest/'tools/support'/name)
    copy(stage/'README.md',dest/'README.md');copy(stage/'validation_summary.json',dest/'validation_summary.json');copy(stage/'reference_match.json',dest/'reference_match.json')
    copy(stage/'baseline/preserved_artifacts.json',dest/'validation/preserved_artifacts.json')
    for p in (stage/'reference').glob('*.png'):copy(p,dest/'reference'/p.name)
    for name in ('godot_proportions_final01.log','verify_proportions_iteration01_02.log','build01.log','godot_import01.log','palm_review01.log','godot_joint_gpu01.log','godot_detailed_gpu01.log'):
        copy(stage/name,dest/'validation'/name)
    for kind in previews:shutil.copytree(game/'artifacts/visual_qa'/kind/'proportions_final_01',dest/'godot_preview'/kind)
    source_paths.update(['tests/player_finger_joints_test.gd','tests/player_hands_detailed_test.gd','scripts/test_room_catalog.gd','assets/3d/player/hands_detailed/README.md'])
    # Models/textures are already delivered at top level; include relevant code.
    for path in source_paths:
        if Path(path).suffix in ('.gd','.md'):copy(game/path,dest/'runtime_snapshot'/path)
    files={str(p.relative_to(dest)):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'FILE_MANIFEST.json').write_text(json.dumps(files,indent=2))
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(dest.rglob('*')):
            if p.is_file():z.write(p,str(p.relative_to(dest.parent)))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for p in dest.rglob('*'):
            if p.is_file():assert z.read(str(p.relative_to(dest.parent)))==p.read_bytes()
    assert all(sha(project/p)==value for p,value in prior.items())
    result={'status':'passed','package':str(dest),'files':len(files)+1,'zip_sha256':sha(archive),'zip_bytes':archive.stat().st_size,'zip_crc_and_exact_content':True,'prior_files_unchanged':len(prior)}
    (stage/'package_verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

if __name__=='__main__':main()
