# 목·어깨 체격 보강 / Sturdier neck and shoulders

사용자 요청: 복원본의 목과 어깨를 좀 더 듬직하게 만든다. 팔을 다시 조형해 달라는 요청으로 확대하지 않는다.

English: Strengthen the restored model’s neck and shoulders while retaining the restored arm shape.

## 변경 / Changes

- 기준 / Preserved source: `../player_trousers_only_20260922/Gravebound_Trousers_Only.blend` (`f279eec` model).
- 목의 최대 가로 배율 1.16, 앞뒤 배율 1.12. 1.475m 아래에서 최대로 적용하고 1.51m에서 0으로 완화한다. 옷깃을 함께 맞춘다. Maximum neck scaling is 1.16 across and 1.12 front-to-back, fading between 1.475m and 1.51m; adjust the neckline consistently.
- 양팔·양손은 각각 바깥으로 18mm 강체 이동. 메시/UV/법선을 다시 조형하지 않는다. 어깨 폭은 총 36mm 보강하고, 몸통이 새 소매 위치에 이어지도록 한다. Rigidly translate both sleeves and hands 18mm outward, preserving their geometry/UVs/normals, and blend the upper torso into the widened shoulder frame.
- 승모근 윗윤곽을 최대 9mm 높이고 목 개구부를 보존한다. Lift the trapezius silhouette by up to 9mm while preserving the neck opening.
- 다른 14개 메시, 비트맵, 재질 및 일인칭 원본을 보존한다. Preserve the other 14 meshes, bitmap/material sources and first-person assets.

## 산출물 / Outputs

`build.py`, `build_report.json`, `Gravebound_Sturdy_Neck_Shoulders.blend`, `gravebound_player_sturdy_neck_shoulders.glb`.

게임 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.

SHA256: `f587e61d3ccb94c5856b3af3104ac8ebb667539aa7d46d01a395a53ed805fda9`.

## 검증 / Validation

- 게임 검사 4/4 PASS: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`, `player_appearance`. 머리·팔다리 표시와 실제 인벤토리 모델, F2 복귀·초기화·원정 복원을 포함한다. Four targeted Godot tests pass, including real appearance/inventory integration and test-room restoration. Evidence: `final_tests.log`.
- `audit_geometry.py`는 제작 코드를 불러오지 않고 원본/결과를 독립 비교한다. 다른 14개 메시와 팔·손의 로컬 형상·UV·법선 및 내장 비트맵이 동일하다. 얼굴/두피 5,248개 정점 변위는 0이다. The independent audit confirms exact preservation of 14 other meshes, limb local geometry/UVs/normals and embedded bitmaps, with zero displacement for 5,248 face/scalp vertices.
- 목 1.470m 단면: 폭 11.90→13.80cm, 깊이 11.55→12.94cm. 어깨 접합 간극 최대 1.49e-8m, 법선 일치(dot) 최소 .9999995. 목 내부 17개 지점의 첫 표면은 숨은 바닥 1.430m이다. Neck dimensions increase by 16%/12%; matching shoulder joins and 17 neck-opening probes pass. Details: `geometry_audit.json`.
- 실제 Vulkan 렌더 13장: `../../godot-game/artifacts/visual_qa/player_appearance/sturdy_neck_shoulders_20260922/`. 독립 검토에서 얼굴/목 관통과 새 어깨 틈이 없고 목·어깨 체격 증가가 확인됐다. 팔의 원래 형태는 유지하며, 사용자 수용 여부를 자동 검사 결과로 대신하지 않는다. Thirteen actual renders complete; independent visual review confirms the requested broader build without new facial distortion or neckline/shoulder gaps. These checks do not imply user acceptance.
- 360° 뷰어와 실제 게임 모델의 해시 일치, 게임 임포트 캐시 갱신 확인. Viewer/runtime hashes match and player import caches are refreshed.
- 격리 임포트의 UID 경로 대체 경고와 기존 유형 ObjectDB 종료 경고가 남지만 모델/텍스처는 정상 로드되고 검사 4개는 통과한다. Isolated-import UID fallbacks and an existing-type ObjectDB exit warning remain; the model/textures load and all four checks pass.
