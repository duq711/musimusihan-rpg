# 4방향 참조 전신 비율 / Four-view full-body proportions

사용자가 제공한 정면·후면·양측면 사진을 기준으로 전신의 공통 비율을 다시 맞췄습니다. 이번 지시는 이전의 얼굴·손·하체 치수 고정 조건을 대체합니다. 기존 인물과 복장을 유지하면서 머리 폭, 어깨 경사, 흉곽과 허리, 팔의 길이·각도, 골반 높이, 다리 간격, 부츠 크기와 옆모습을 함께 수정했습니다. 원본은 보존합니다.

English: Refit the whole body from the four supplied views, superseding earlier dimension locks. Preserve the character and outfit while adjusting head width, shoulder slope, torso taper, arm lengths and stance, pelvis height, leg spacing, boots and sagittal alignment. Original production sources remain preserved.

## 산출물 / Outputs

- Preserved source: `../player_reference_anatomy_20260922/Gravebound_Reference_Anatomy.blend`.
- Editable final: `Gravebound_Multiview_Proportions.blend`.
- Reproducible scripts: `build.py`, `deformation.py`.
- Export: `gravebound_player_multiview_proportions.glb`; identical runtime `godot-game/assets/3d/player/gravebound_player.glb`.
- SHA-256: `3f4638ee9fe2e7f0925969eb63d4aba669316892ea21373f280f2a4d0b8e2af9`.
- Original reference images: `reference_images/` (four supplied PNGs, unchanged).
- Photo measurements: `reference_front_back.json`, `comparison_report.json`, `side_alignment_review.json`.
- Interactive comparison: `compare.html`, served by `tools/player-model-viewer/server.py` at `/proportions/compare.html`.
- Real-renderer evidence: `godot-game/artifacts/visual_qa/player_appearance/multiview_proportions_20260922/`.

Built on this Mac with Blender 5.2.1 LTS in background, two threads:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b -t 2 --python-exit-code 1 --python asset-staging/player_multiview_proportions_20260922/build.py
```

## 비율 기준과 수정 / Calibration and fitting

정면 사진 1086×1448에서 발바닥 y1401, 머리카락 아래 추정 두개골 정수리 y36을 현재 모델의 1.7122m 높이에 맞췄습니다. 이는 사진 인물의 실제 키를 안다는 뜻이 아닙니다. 벨트 중심은 기존보다 약 9.6cm 낮아졌고, 팔꿈치·손목·가랑이·부츠 높이를 사진 기준점에 맞췄습니다. 손목은 몸 바깥으로 배치하고 전완은 자연스럽게 좁아지도록 정리했습니다. 골반부터 허벅지까지 연속된 변형을 적용해 치마 같은 단차를 없앴습니다. 발은 단일 발목 기준으로 폭·길이를 조정하고, 정강이와 발목의 앞쪽 치우침을 단계적으로 최대 5.2cm 뒤로 옮겼습니다.

English: Calibrate the 1086×1448 front reference between estimated skull crown y36 and sole y1401 to the existing 1.7122m stature; this is not an estimate of the depicted person's real height. Lower the belt by about 9.6cm and fit elbow, wrist, crotch and boot heights. Open the arm stance and taper the forearms continuously. Use a monotone pelvis mapping to avoid a horizontal crotch ledge; fit each foot as a single volume and move the lower shin/ankle backward by up to 5.2cm.

| 기준 / Anchor | 실제 Z / Actual m | 참조 기준 / Guide m |
|---|---:|---:|
| Belt bounds centre | .98816 | .98483 |
| Elbow guide section | 1.15793 | 1.15793 |
| Wrist shared ring | .93048 | .93089 |
| Crotch bridge | .78162 | .78162 |
| Boot top | .43541 | .43541 |

벨트의 차이 3.3mm는 중심점 자체를 변형한 위치와 변형 후 경계 상자의 중심이 다른 데서 옵니다. 기준점 일치는 표면 전체의 완벽한 재현을 뜻하지 않습니다.

English: The belt's 3.3mm difference is the distinction between a transformed centre point and the centre of transformed bounds. Matching landmarks does not establish an exact full-surface reconstruction.

## 검증 / Validation

- Asset checks: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset` — 3 passed on the final asset (`asset_tests.log`). Wrist regression now measures actual coincident sleeve/hand vertices, distinguishing the tilted joining ring from the surrounding cloth.
- Game integration: `player_appearance` passed actual body/portrait sharing, camera layers, rotation, repeated F2/dungeon roundtrips, reset, cleanup and expedition restoration (`game_integration.log`). Initial runs timed out during source-file I/O; a sampled stack stopped in `fread` on `cave_layout.gd`. Reading that source into cache released the delay. The final run added temporary progress prints only; all production assertions were unchanged. The isolated cache reported texture UID fallbacks to valid paths and the existing one-ObjectDB exit warning; no assertion or script error. Temporary instrumentation is not shipped.
- Independent Blender audit: all 20 meshes retain topology/UV/material assignments, 12 packed bitmaps remain identical; no significant new reversed or degenerate triangles. Shoulder maximum separation .000240mm; wrist separation zero. Trouser/boot overlap remains. See `audit_current.md/json` for tolerances and limited scope.
- Actual rendering: 21 Vulkan/embedded captures using the production portrait and current game GLB, including four calibrated textured/clay view pairs. No native game window, external input capture, cursor movement or audio. Capture manifest matches the final SHA.
- Visual review: front/back/both sides, clay and textured, plus oblique views. Reference comparison at sampled front torso heights differs by median 1px, maximum 4px; front shoulder widths by median 6px, maximum 12px; central crotch gap maximum 3px. These are selected contour samples, not a whole-body error score.
- Viewer: final model hash verified through `/model-info.json`; actual browser model loaded, front view and comparison slider/outline controls checked. Comparison's 14 explicit HTTP routes match source bytes. Only the player import cache was refreshed for the local game.

## 남은 차이 / Remaining differences

사진 네 장은 동일한 정사영 스캔이 아니며, 옷·자세·원근이 다릅니다. 후면 어깨 폭은 일부 높이에서 최대 약 30px(이 기준에서 3.8cm) 차이가 있고, 골반 기준 측면 발목 위치는 약 1.4~1.9cm 차이가 남습니다. 기존 얼굴·머리카락 없는 머리·옷·장갑·장비 디자인도 사진과 다릅니다. 따라서 완전한 복제라고 보고하지 않습니다. 구체적인 비교와 해석은 `final_review.md`에 남겼습니다.

English: The four images are not one calibrated orthographic scan. Pose, clothing and perspective differ. Rear shoulder widths differ by up to about 30px at sampled heights, and pelvis-aligned side ankle position by roughly 1.4–1.9cm. Face, bald scalp, outfit, gloves and equipment designs remain distinct. This is a reference-guided proportion fit, not a claim of exact reconstruction; see `final_review.md`.
