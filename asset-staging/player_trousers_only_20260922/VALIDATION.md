# 코트 자락 제거 / Remove coat tails

사용자 요청대로 긴 코트 자락 3개를 제거하고 바지만 남긴다. 기존 바지에는 코트에 가려져 있던 허리·골반·가랑이 천이 없었으므로 두 바지 메시를 자연스럽게 이어 완성했다. 벨트·주머니·부츠 및 수정된 얼굴·상체·손은 유지한다.

English: Remove all three long coat-tail meshes and retain trousers. Complete the missing waist, hips and crotch previously concealed by the coat. Retain the belt, pouches, boots and updated face, upper body and hands.

## 산출물 / Outputs

- 이전 원본 / Preserved source: `../player_natural_shoulders_20260922/Gravebound_Natural_Shoulders.blend`.
- 제작 / Reproducible build: `build.py`.
- 결과 / Results: `Gravebound_Trousers_Only.blend`, `gravebound_player_trousers_only.glb`.
- 게임 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- 다른 18개 메시의 좌표·UV·재질 참조·변환 유지, 최종 20개 메시. Preserve geometry, UVs, material references and transforms of 18 other meshes; 20 meshes remain.
- 바지 0.50–0.62m의 원래 무릎 기하 유지, 골반과 허벅지 상부 재구성. 드러난 밑단은 실제 양쪽 부츠 중심에 맞춰 안으로 넣었다. 원본 이미지 변경 없이 기존 직물 UV 사용. Preserve knee geometry between 0.50–0.62m, complete hips/upper thighs and tuck the exposed hems into each retained boot cuff. Use existing cloth without editing bitmap sources.

## 검증 / Validation

- `build_report.json`: 원본 보존과 제작 검사 PASS. Source preservation/build checks pass.
- Godot `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`, `player_appearance` PASS. 최종 모델에서 4개 검사 모두 통과. Four checks pass on the final asset. Evidence: `final_tests.log`.
- 격리 임포트의 UID 경로 대체 경고에서 텍스처는 정상 로드됨. 기존 유형의 ObjectDB 종료 경고 1개. Isolated-import UID fallbacks load the proper textures; one existing-type ObjectDB exit warning remains.
- 실제 화면 / Actual images: `../../godot-game/artifacts/visual_qa/player_appearance/trousers_only_final_20260922/`.
- 모델 SHA256: `f7ad57eddd4ac751daee53fcdb05bf627a749007f0989d9f344f735dfb2e2a77`.

- 독립 기하 검사 / Independent geometry audit: 코트 3개 삭제, 바지 한 벌의 닫힌 연결 표면, 골반 15개 표본, 중앙 이음 368개, 양쪽 부츠 내측 밑단을 확인했다. Verify three deleted coat meshes, one closed connected trouser surface, 15 hip coverage probes, 368 shared center-seam points and both hems within the boot cuffs. `geometry_audit.json`.

- 최종 Godot 렌더 8장과 독립 시각 검토 PASS. 기존 사각형 밑단 돌출이 사라진 것을 정면·아래쪽에서 확인하고 360° 뷰어에 전신을 표시했다. Eight final Godot renders and independent visual review pass; front/low views confirm tucked hems, and the updated full body is displayed in the 360° viewer. Evidence: `final_render.log`.
