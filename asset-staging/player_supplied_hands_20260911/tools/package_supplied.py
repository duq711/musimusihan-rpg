"""Package verified current supplied hands, preserving all previous deliveries."""
import hashlib,json,shutil,zipfile
from pathlib import Path
stage=Path(__file__).resolve().parents[1];project=stage.parents[1];out=stage/'mac_output/iteration_05'
dest=project/'exports/Player_Supplied_Hands_2026-09-11'
summary=json.loads((stage/'validation_summary.json').read_text());assert summary['status']=='complete'
assert summary['headless']['passed']==8 and summary['headless']['failed']==0
for log in summary['headless']['accepted_logs']:
    assert (stage/log).exists()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
pairs={'left_hand_supplied.glb':project/'godot-game/assets/3d/player/hands_detailed/left_hand_detailed.glb',
       'right_hand_supplied.glb':project/'godot-game/assets/3d/player/hands_detailed/right_hand_detailed.glb',
       'gravebound_player_supplied_hands.glb':project/'godot-game/assets/3d/player/gravebound_player.glb'}
for name,target in pairs.items():assert sha(out/name)==sha(target),'Current game/source mismatch: '+name
assert not dest.exists();dest.mkdir(parents=True)
def cp(source,relative):
    target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target);assert sha(source)==sha(target)
cp(out/'bilateral_supplied_hands.blend',Path('Blender/bilateral_supplied_hands.blend'))
for n in pairs:cp(out/n,Path('GLB')/n)
for p in out.glob('*.png'):cp(p,Path('Textures')/p.name)
for n in ('hand1.OBJ','left_hand.ZTL','source_manifest.json'):cp(stage/'input'/n,Path('Originals')/n)
for p in (stage/'review/final_05').glob('*.png'):cp(p,Path('Preview/Hands')/p.name)
for p in (stage/'review/final_02').glob('character_*.png'):cp(p,Path('Preview/Character')/p.name)
for category in ('player_appearance','player_finger_joints','player_hands_detailed'):
    capture_iteration='supplied_hands_03' if category=='player_appearance' else 'supplied_hands_05'
    folder=project/'godot-game/artifacts/visual_qa'/category/capture_iteration
    assert (folder/'capture_manifest.json').exists()
    for p in folder.iterdir():
        if p.is_file() and p.suffix in ('.png','.json'):cp(p,Path('Preview/Game')/category/p.name)
for n in ('validation_summary.json','README.md'):cp(stage/n,Path(n))
delivery_intro='''# 납품 파일 열기

- `Blender/bilateral_supplied_hands.blend`: 편집 가능한 양손·캐릭터 장면. 사용 텍스처 7개가 파일 안에 포함되어 있다.
- `GLB/`: 게임용 양손과 전신 캐릭터. GLB 안에도 텍스처가 포함되어 있다.
- `Textures/`: 양손·의상용 4K 색상·노멀·거칠기 원본 PNG.
- `Originals/`: 변경하지 않은 사용자 OBJ·ZTL 원본.
- `Preview/`: Blender 및 실제 게임 검토 이미지.
- `Verification/`, `validation_summary.json`, `SHA256.json`: 검증 결과와 무결성 기록.

아래 제작 기록의 `mac_output/`, `audit/`, `review/` 경로는 원래 게임 프로젝트의 제작 폴더를 기준으로 한다. 이 납품에서는 위 폴더를 사용한다.

---

'''
(dest/'README.md').write_text(delivery_intro+(dest/'README.md').read_text())
for p in (stage/'audit').glob('*'):
    if p.is_file() and p.suffix in ('.json','.log') and ('05' in p.name or p.name in ('body_gpu_03.log','uid_warning_diagnosis.json','mcp_connection_diagnosis.json')):cp(p,Path('Verification')/p.name)
for p in out.glob('*.json'):cp(p,Path('Verification')/p.name)
for n in ('canonical_landmarks.json','canonical_landmarks_right.json','preparation_report.json','supplied_left_rigged.rig_report.json','supplied_right_rigged.rig_report.json'):cp(stage/'geometry'/n,Path('Verification')/n)
for n in ('mesh_preflight.json','native_visual_review.json','source_unchanged.json','hands_render_report.json','render_suite_report.json'):
    p=stage/'review/final_05'/n
    if p.exists():cp(p,Path('Verification')/n)
manifest={str(p.relative_to(dest)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in dest.rglob('*') if p.is_file()}
(dest/'SHA256.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
archive=dest.with_suffix('.zip');assert not archive.exists()
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(dest.rglob('*')):
        if p.is_file():z.write(p,arcname=str(p.relative_to(dest.parent)))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
result={'directory':str(dest),'archive':str(archive),'archive_sha256':sha(archive),'archive_bytes':archive.stat().st_size,'files':len(manifest)+1}
(stage/'delivery_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False))
