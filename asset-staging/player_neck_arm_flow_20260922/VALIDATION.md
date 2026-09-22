# 목·어깨 흐름과 원단 연결 / Neck, shoulder and textile flow

## 결과 / Result

직전 듬직한 체격을 유지하며 목의 완만한 입체감, 어깨 접합 골과 소매 캡, 상부 원단 연결을 국소 수정했습니다. 얼굴·손·팔꿈치·전완·하체와 후드/코트 제거 상태는 유지합니다. 이전에 철회된 팔 전체 조형은 재사용하지 않았습니다.

English: Refine the neck, shoulder valley/cap and upper-sleeve textile while keeping the sturdy source build. Preserve the face, hands, elbows, forearms, lower body and hood/coat removal. The rejected broad arm resculpt is not reused.

- 기준 / Source: `../player_sturdy_neck_shoulders_20260922/Gravebound_Sturdy_Neck_Shoulders.blend`
- 기준 GLB SHA256 / Source: `f587e61d3ccb94c5856b3af3104ac8ebb667539aa7d46d01a395a53ed805fda9`
- 최종 GLB SHA256 / Final: `40eda135a75a5a5ce7cdbf841c1b4ce4f0f64529011b727349da58f4e739c272`
- 결과 / Outputs: `Gravebound_Neck_Arm_Flow.blend`, `gravebound_player_neck_arm_flow.glb`, `textures/`
- 게임 에셋 / Game asset: `../../godot-game/assets/3d/player/gravebound_player.glb`

## 변경과 보존 / Changes and preservation

목의 변화는 높이 1.445~1.51m 구간에 한정하며 최대 2.326mm입니다. 피부에 날카로운 홈을 파지 않고 넓은 곡면을 더했습니다. 옷 형상은 높이 1.275m 위에서 최대 7.577mm 조정했으며, 어깨의 단면 골 깊이는 위치에 따라 약 3.0~9.6mm 줄었습니다. 실제 겨드랑이 빈 공간 24개 표본을 유지합니다.

English: Neck changes are limited to 1.445–1.51m, at most 2.326mm. Add broad form without sharp carved grooves. Garment changes are above 1.275m, at most 7.577mm; sampled shoulder valleys are reduced by about 3.0–9.6mm. Preserve all 24 sampled real underarm openings.

다른 16개 메시의 Blender 데이터와 변환은 동일하고, GLB의 위치·노멀·UV·인덱스도 동일합니다. 바지 R 접선 11개의 내보내기 반올림 차이는 최대 0.00010002입니다. 전체 20개 메시의 토폴로지는 유지하며 얼굴 1.51m 이상, 목 밑동 1.445m 이하와 하부 팔 좌표는 그대로입니다.

English: Sixteen other meshes retain exact Blender data/transforms and exported position, normal, UV and index data. Eleven right-trouser tangents have export rounding differences up to 0.00010002. Preserve all 20 mesh topologies and protected face, neck-base and lower-arm geometry.

원래 UV 전체와 원본 비트맵은 보존합니다. 양쪽 상부 소매에만 새 UV와 PBR 재질을 추가하고 색상·노멀을 2K 이미지 4개로 베이크했습니다. 높이 1.18~1.285m에서 표면의 원단을 혼합합니다. 하단 소매/피부의 UV·재질은 동일합니다. 베이크 경계 Z=1.1763m의 일부 정점은 접선 평균이 달라져 실제 화면에서도 확인했습니다. 기존 원단 노멀 강도 0.25를 베이크에 포함하며, 최종 접선과 노멀 UV 방향의 평균 내적은 양팔 모두 0.9999 이상입니다.

English: Retain every original UV and bitmap. Add an upper-sleeve UV/PBR material per arm and bake blended color/normals into four 2K maps over 1.18–1.285m. Lower-sleeve and skin UVs/materials remain unchanged. Some boundary tangents at Z=1.1763m change through averaging and were visually reviewed. The bake includes the original normal strength of 0.25; exported tangents align with the normal UVs above 0.9999 mean dot on both arms.

## 검증 / Validation

- Mac Blender 5.2.1 CLI 제작·독립 감사 통과: `build_report.json`, `geometry_audit.json`. / Mac background build and independent audit passed.
- Godot 관련 검사 4개 통과: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`, `player_appearance`. 최초 전신 검사는 파일 읽기 대기 때문에 180초 시간 초과였고 나머지 3개는 통과했습니다. 동일 전신 코드·모델을 최소 로컬 프로젝트에서 재실행해 통과했습니다. 근거: `final_tests.log`, `final_retry.log`. / Four relevant checks passed; after an I/O timeout, the full-body test passed with identical code/model in an isolated local project. The other three passed in the game QA project.
- 테스트는 새 원단이 상부 소매에만 적용되고, 피부와 하단 소매에 침범하지 않으며, 실제 조명과 노멀맵을 유지하는지 확인합니다. / Tests check upper-sleeve-only assignment and lit PBR/normal detail.
- Vulkan/embedded 실제 렌더 13장, 최종 모델 해시 일치, 원정 상태·커서 보존. / Thirteen actual Vulkan/embedded renders match the final hash; expedition state and cursor are preserved.
- 실제 프리뷰: `../../godot-game/artifacts/visual_qa/player_appearance/neck_arm_flow_20260922/`. 비교 기준: 같은 상위 폴더의 `sturdy_neck_shoulders_20260922/`. / Final and source views use matching camera angles.
- 로컬 360도 뷰어가 같은 최종 GLB 해시를 제공하는 것을 확인했습니다. / The local 360° viewer serves the same final GLB hash.

정면·사선·측면에서 UV 보간으로 생겼던 새 수평 띠가 제거됐고, 팔꿈치/전완이 통짜로 변하는 회귀는 보이지 않았습니다. 기존 옷의 작은 각진 어깨 윗윤곽과 일부 원단 방향 변화는 남습니다. 이 검증은 국소 수정의 보존·렌더 상태를 확인하며 사용자의 미적 승인을 대신하지 않습니다. 격리 게임 검사에는 기존 UID 경로 대체 경고와 종료 시 ObjectDB 1개 경고가 남습니다.

English: Front, oblique and side review shows the new stretched horizontal bands removed, without cylindrical elbow/forearm regression. Some pre-existing angular shoulder-top shape and fabric direction changes remain. Validation establishes preservation/render behavior, not user aesthetic approval. Isolated game logs retain UID path-fallback warnings and one existing ObjectDB exit warning.

## 재현 / Reproduction

프로젝트 루트에서 Mac Blender 백그라운드로 `build.py`, 이어서 `audit_geometry.py`를 실행합니다. Godot 가져오기 후 관련 헤드리스 검사를 실행하고, `PLAYER_QA_ITERATION=neck_arm_flow_20260922 PLAYER_QA_BODY_ONLY=1 PLAYER_QA_SHOULDER_FORM=1`로 `tests/run_embedded_preview.sh player_appearance_preview.gd`를 실행합니다. 네이티브 창·포커스·커서 캡처를 사용하지 않습니다.

English: Run the builder and independent audit with Mac background Blender, import into Godot, run the four headless checks, then use the listed environment values with the embedded preview runner. No native window, focus or cursor capture is used.
