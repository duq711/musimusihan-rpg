# 어깨·겨드랑이 재조형 / Resculpt shoulder and underarm transitions

요청: 어깨가 과도하게 둥글고 팔이 몸통에 따로 붙어 보이는 형태를 개선한다. 이전에는 접합부의 구멍·법선과 윗윤곽을 검사했지만, 가슴·등 외측의 골과 별도로 부푼 소매 캡이 남아 있었다.

English: Address the oversized rounded shoulders and detached-looking arms. Previous seam and roof checks did not catch the deep chest/back valley followed by a separate sleeve-cap bulge.

## 변경 / Changes

- 몸통과 두 소매를 한 표면으로 조형해 앞뒤 접합 골을 채우고 어깨 바깥 볼륨을 줄인다. Sculpt the joined torso/sleeves together, fill the front/back valley and reduce the lateral cap.
- 고정 수직 경계를 해제하고 가슴 전체·겨드랑이·어깨 꼭대기를 넓게 다듬는다. 목 개구부 내부와 목둘레는 별도로 보존한다. Release the artificial straight seam and fair the chest, underarms and upper shoulders while protecting the neck opening.
- 측면을 1mm 간격으로 측정하고 높이 방향으로 곡선을 평활화한 뒤, 위팔과 어깨 상단을 연속 곡면으로 연결한다. Sample the lateral surface at uniform 1mm height intervals, smooth its profile vertically and blend the upper arm into the shoulder roof continuously.
- 기존 직물 UV를 연속적으로 배치해 어깨 밑 띠 경계를 제거한다. 비트맵·재질 설정·손목 피부는 변경하지 않는다. Use coherent cloth UVs to remove the band below the shoulder, preserving bitmap sources, material settings and cuff skin.
- 얼굴·손·바지·벨트·주머니·부츠 등 나머지 17개 메시와 높이 1.18m 이하 기하를 유지한다. 일인칭 원본은 수정하지 않는다. Preserve the other 17 meshes and geometry below 1.18m; do not modify first-person source assets.

## 산출물 / Outputs

- 이전 원본 / Preserved source: `../player_trousers_only_20260922/Gravebound_Trousers_Only.blend`.
- 제작 / Build: `build.py`; 독립 기하 감사 / independent geometry audit: `audit_geometry.py`.
- 결과 / Results: `Gravebound_Shoulder_Form.blend`, `gravebound_player_shoulder_form.glb`.
- 게임 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- SHA256: `d5fb5f81c684a2afd5b4b4d5dfd833c33b7f601b541a2f83c1538c11036e0ef6`.

## 검증 / Validation

- 최종 Godot 검사 **4/4 PASS**: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`, `player_appearance`. Actual game/portrait body, camera layers, F2 roundtrips, reset and expedition restoration are covered. Evidence: `final_tests.log`.
- `geometry_audit.json`: 다른 17개 메시의 형상·노멀·UV·인덱스·변환·재질 참조 보존, 비트맵 동일, 1.18m 아래 기하 보존. 앞뒤 단면의 최대 34.8mm 재돌출이 검사 지점에서 0mm로 감소. 측면 중심 능선 잔차는 최대 0.85mm, 목 내부 9개 표본 모두 숨은 바닥 1.430m 유지. Preserve all 17 other meshes and embedded bitmaps; sampled secondary shoulder lobes drop from 34.8mm to 0mm, the maximum sampled lateral ridge residual is 0.85mm, and all nine neck probes retain the hidden floor at 1.430m.
- 최종 13장 렌더 및 별도 검토 완료: 정면·사선·측면·후면의 재질/무채색 8장에서 분리된 소매 캡, 깊은 접합 골, 측면 단차가 해소되었음을 확인했다. 360° 뷰어와 게임 GLB의 해시가 동일하다. All 13 final captures completed; independent review of eight textured/clay views accepted the continuous chest/shoulder/arm form without the separate cap, deep junction valley or lateral ledge. Viewer and game GLB hashes match.
- 실제 비교 / Actual comparison: `../../godot-game/artifacts/visual_qa/player_appearance/shoulder_form_before_20260922/` and `../../godot-game/artifacts/visual_qa/player_appearance/shoulder_form_final_20260922/`.
- `PLAYER_QA_SHOULDER_FORM=1`: 같은 카메라·조명에서 정면·사선·측면·후면 재질/무채색 8장을 추가 촬영한다. 원래 카메라·뷰포트·재질 복원, 외부 입력과 오디오 비활성. Eight extra matching textured/clay angles use the production model with camera, viewport and materials restored and external input/audio disabled.
- 격리 임포트의 UID 경로 대체 경고에서 텍스처는 정상 로드된다. 기존 유형의 ObjectDB 종료 경고 1개가 남는다. Isolated-import UID fallback warnings still load the correct textures; one existing-type ObjectDB exit warning remains.
