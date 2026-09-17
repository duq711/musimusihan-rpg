"""Package only the accepted gloves after checking final evidence against files."""
from pathlib import Path
import hashlib,json,shutil,zipfile

ROOT=Path(__file__).resolve().parents[3]
STAGE=ROOT/'asset-staging/player_mercenary_gloves_20260911'
MODEL=STAGE/'mac_output/iteration_02'
GAME=ROOT/'godot-game'
DEST=ROOT/'exports/Player_Mercenary_Gloves_2026-09-11'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def write(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False))
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst);assert sha(src)==sha(dst)

def main():
    native=read(MODEL/'verification_report.json');assert native['status']=='passed'
    for path,value in native['verified_sha256'].items():assert sha(path)==value,path
    built=read(MODEL/'build_report.json');assert built['blend_sha256']==sha(MODEL/'bilateral_mercenary_gloves.blend')
    render=read(MODEL/'review/render_report.json');visual=read(MODEL/'review/visual_review.json')
    assert all(visual['checks'].values()) and visual['source_sha256']==built['blend_sha256']
    assert visual['render_report_sha256']==sha(MODEL/'review/render_report.json')
    headless=STAGE/'headless_tests02.log';log=headless.read_text()
    assert 'Headless validation: 7 passed, 0 failed.' in log and 'ERROR:' not in log
    for path,value in read(STAGE/'game_integration.json').items():assert sha(ROOT/path)==value,path
    imported=read(STAGE/'atlas_import_validation.json')
    assert len(imported)==6 and all(row['used_channels_pixel_identical'] for row in imported.values())
    for side in ('left','right'):
        assert sha(MODEL/(side+'_mercenary_glove.glb'))==sha(GAME/'assets/3d/player/hands_detailed'/(side+'_hand_detailed.glb'))
    gpu={};capture_files=[]
    for kind,count in [('player_finger_joints',12),('player_hands_detailed',6)]:
        folder=GAME/'artifacts/visual_qa'/kind/'mercenary_gloves_02';manifest=read(folder/'capture_manifest.json')
        assert not manifest['failures'] and len(manifest['captures'])==count
        assert manifest['actual_renderer']=='vulkan' and manifest['display_driver']=='embedded'
        assert manifest['sources_unchanged_during_capture'] and manifest['expedition_inventory_and_cursor_preserved']
        for path,value in manifest['source_sha256'].items():assert sha(GAME/path.removeprefix('res://'))==value,path
        for c in manifest['captures']:
            assert c['passed'] and sha(folder/c['image'])==c['image_sha256']
            capture_files.append(folder/c['image'])
            if kind=='player_finger_joints':
                assert c['wrist_gpu_buffers']['passed'] and c['actual_pbr_bindings']['passed']
                for row in c['actual_pbr_bindings']['bound_texture_pixels'].values():
                    assert row['passed'] and row['actual_pixel_sha256']==row['source_pixel_sha256']
        gpu[kind]={'captures':count,'manifest_sha256':sha(folder/'capture_manifest.json'),'actual_renderer':'vulkan','display_driver':'embedded','passed':True}
    game_visual=read(STAGE/'audit/game_visual_review.json')
    assert game_visual['status']=='passed_for_requested_full_glove_scope'
    assert game_visual['actual_game_capture_count']==18
    for row in game_visual['directly_reviewed_files']:
        assert row['directly_visually_reviewed'] and sha(ROOT/row['file'])==row['sha256']
    # The human-visible visual review is a separate artifact from GPU assertions.
    assert len(capture_files)==18
    summary={'status':'passed','candidate':'iteration_02','style':'Full-finger brown mercenary leather gloves',
      'native_verification_sha256':sha(MODEL/'verification_report.json'),
      'blender_visual_review_sha256':sha(MODEL/'review/visual_review.json'),
      'game_visual_review_sha256':sha(STAGE/'audit/game_visual_review.json'),
      'headless':{'passed':7,'failed':0,'log_sha256':sha(headless)},'gpu':gpu,
      'preserved_previous':read(STAGE/'baseline/previous_assets_preserved.json'),
      'game_integration_sha256':sha(STAGE/'game_integration.json'),
      'glb_roughness_green_channel_and_all_used_pixels_verified':True,
      'limitations':['Shallow inherited fingertip contours remain under the glove surface.',
        'The current detailed profile is selected through the existing test-room entries; the default and dedicated sword/shield hand profiles retain their existing selection rules.',
        'This is a simple game glove asset, not a scanned or historically researched reconstruction.']}
    write(STAGE/'validation_summary.json',summary)
    assert not DEST.exists(),'Keep earlier deliveries immutable'
    DEST.mkdir(parents=True)
    for name in ['bilateral_mercenary_gloves.blend','left_mercenary_glove.glb','right_mercenary_glove.glb',
                 'realistic_hands_basecolor.png','realistic_hands_normal.png','realistic_hands_roughness.png']:
        copy(MODEL/name,DEST/name)
    for p in (MODEL/'review').iterdir():
        if p.is_file():copy(p,DEST/'preview'/p.name)
    for name in ['build_report.json','verification_report.json']:
        copy(MODEL/name,DEST/'verification'/name)
    for name in ['validation_summary.json','game_integration.json','atlas_import_validation.json','headless_tests02.log','gpu_joints02.log','gpu_hands02.log']:
        copy(STAGE/name,DEST/'verification'/name)
    copy(STAGE/'audit/game_visual_review.json',DEST/'verification/game_visual_review.json')
    for kind in gpu:
        folder=GAME/'artifacts/visual_qa'/kind/'mercenary_gloves_02'
        for p in folder.iterdir():
            if p.is_file() and p.suffix in ('.png','.json'):copy(p,DEST/'verification'/kind/p.name)
    readme='''# 중세 용병 가죽 장갑

`bilateral_mercenary_gloves.blend`를 Blender에서 열면 양손 장갑과 관절 리그를 편집할 수 있습니다. 텍스처는 원본 안에 포함되어 있습니다. 좌우 GLB에도 실제 가죽 텍스처와 16본·15개 관절 보정을 포함했습니다.

`preview/`에는 실제 모델의 손등·손바닥 렌더가 있습니다. `verification/`에는 독립 모델 검사, 자동 검사 7개 통과 및 실제 게임 캡처 18개의 검토 근거가 있습니다.

프로젝트에는 기존 상세 양손 경로로 반영했습니다. 테스트룸의 기본 → 캐릭터 그래픽 · 용병 가죽 장갑, 손가락 마디별 관절에서 확인할 수 있습니다. 가까운 거리에서 원본 손끝의 얕은 굴곡은 남아 있습니다.
'''
    (DEST/'README.md').write_text(readme)
    manifest={str(p.relative_to(DEST)):sha(p) for p in sorted(DEST.rglob('*')) if p.is_file()}
    write(DEST/'manifest.json',manifest)
    archive=DEST.with_suffix('.zip');assert not archive.exists()
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(DEST.rglob('*')):
            if p.is_file():z.write(p,DEST.name+'/'+str(p.relative_to(DEST)))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name,digest in manifest.items():assert hashlib.sha256(z.read(DEST.name+'/'+name)).hexdigest()==digest
    write(STAGE/'package_verification.json',{'status':'passed','files':len(manifest)+1,'zip':str(archive),'zip_sha256':sha(archive),'bytes':archive.stat().st_size,'all_archive_files_verified':True})
    print('MERCENARY_GLOVES_DELIVERY_COMPLETE',archive)

if __name__=='__main__':main()
