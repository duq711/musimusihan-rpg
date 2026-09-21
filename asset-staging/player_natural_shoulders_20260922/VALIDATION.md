# 목·어깨를 자연스럽게 연결 / Rebuild the neck and shoulder joins

후드 아래 남아 있던 넓고 평평한 몸통 상단과 안쪽으로 꺾인 소매 캡을 교체했다. 목에서 어깨 끝으로 이어지는 경사, 몸통 앞뒤에 붙는 소매 루트, 실제 목둘레 개구부를 만든다. 몸통과 소매 경계는 같은 정점 위치·법선을 사용해 끊겨 보이지 않게 한다. 두 번 솟던 어깨 끝과 연결부의 띠도 곡면으로 다듬었다.

English: Replace the broad, flat torso cap and inward-folded sleeve caps with sloping shoulders, a true neck opening and sleeve roots joined to the front and back of the chest. Shared seam positions and normals prevent stump-like shading. Fair the double shoulder peaks and the lower connection band into continuous surfaces.

몸통과 새 어깨의 UV를 기존 소매 아틀라스의 직물 영역에 연속적으로 맞춰 옷감이 망토나 턱받이처럼 끊겨 보이는 경계를 제거했다. 원본 비트맵은 수정하지 않았고 전신 옷감의 노멀 강도는 0.25로 맞췄다. 후드를 다시 추가하지 않는다.

English: Map the torso and rebuilt shoulders continuously to the existing woven sleeve atlas, removing cape/bib-like material boundaries. Original bitmap files remain unchanged; full-body cloth normal strength is 0.25. No hood is added.

## 보존과 산출물 / Preservation and outputs

- 제공한 머리·눈, 양손·손목, 하체를 포함한 다른 **20개 메시**의 내보낸 배열을 보존했다. Preserve exported arrays of the other **20 meshes**, including the supplied head/eyes, hands/wrists and lower body.
- 높이 **1.24m 아래 몸통 좌표**, 양쪽 **소매 좌표·UV**를 보존했다. 몸통 UV는 옷감 연결을 위해 새로 배치했다. Preserve torso geometry and sleeve geometry/UVs below **1.24m**; intentionally remap torso UVs.
- 일인칭 원본 팔·손과 게임 동작은 변경하지 않는다. First-person source assets and gameplay behavior remain unchanged.
- 제작 / Builder: `build.py`. 결과 / Outputs: `Gravebound_Natural_Shoulders.blend`, `gravebound_player_natural_shoulders.glb`.
- 게임 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- 뷰어에 **상체 비율 / 형태 확인** 버튼을 추가했다. 무채색 형태 확인은 원래 재질로 되돌릴 수 있다. Add upper-body framing and reversible neutral-clay inspection to the review viewer.

## 검증 / Validation

- Blender 제작·보존 검사 **PASS**. Blender production/preservation checks passed.
- 독립 기하 검사 `geometry_audit.json` **PASS**: 목 내부 9개 위치의 막힘 제거, 양쪽 어깨의 공유 좌표·법선, 바깥으로 다시 솟지 않는 어깨 경사를 확인했다. Independent audit confirms nine unobstructed neck probes, shared shoulder positions/normals and no secondary shoulder peaks.
- 최종 모델의 `player_fullbody_fp_arms`, `player_hood_closure`(목·어깨 구조 포함), `player_face_asset`, `player_appearance` **4/4 PASS**. 실제 모델·초상화·카메라 레이어·F2 왕복·초기화·원정 복원을 확인했다. Four final-model regressions cover the actual model, portrait, camera layers, F2 roundtrips, reset and expedition restoration.
- 실제 렌더 / Actual rendering: 최종 embedded/Vulkan 12개 시점, 색상·무채색과 360° 뷰어 검토. Final twelve embedded/Vulkan captures, textured/clay review and the live 360° viewer.
- 격리 임포트에서 일부 UID 경로 대체 경고가 있지만 텍스처는 정상 로드된다. 기존 유형의 ObjectDB 1개 종료 경고가 남는다. Isolated import emits some UID path-fallback warnings with correct texture loading; one existing-type ObjectDB exit warning remains.
- 근거 / Evidence: `build_report.json`, `geometry_audit.json`, `final_tests.log`, `final_render.log`, `../../godot-game/artifacts/visual_qa/player_appearance/natural_shoulders_final_20260922/`.
- 최종 모델 / Final model SHA256: `5a70869278947f6ec5a332ac16409f9763071e1d0d98b14f511f81721bd409cc`.
