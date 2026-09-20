# 얼굴·눈·머리 재질 수정 / Repair the exposed face, eyes and hair

후드 제거로 드러난 얼굴에서 눈이 검게 비고, 콧등에 검은 조각이 나타나며, 옆머리와 앞머리 무늬가 부자연스럽게 보였다. 눈에는 의상 아틀라스가 남아 있었고, 코의 72개 면은 머리카락 재질로 잘못 분류돼 있었다. 두피의 긴 선 무늬도 머리 표면에서 늘어나 보였다. 앞선 후드 제거 검수는 후드 부재와 의상 보존을 확인했지만 이러한 얼굴 재질 오류를 충분히 판별하지 못했다.

English: Removing the hood exposed black-looking eyes, dark fragments on the nose and distorted side/front hair patterns. The eyes still used the garment atlas, 72 nose faces were incorrectly assigned a hair material, and long scalp strands appeared stretched. The preceding review confirmed hood removal and outfit preservation but did not adequately identify these facial material defects.

## 수정 범위 / Change scope

- 얼굴 / Face: 코의 72개 면을 주변 얼굴에서 구한 아핀 UV 매핑으로 복원했다. 얼굴 사진에 남아 이중 눈처럼 보이던 1,120개 픽셀은 주변 피부의 2D 샘플로 정리했다. 원본 텍스처와 머리 형상은 보존했다. Restored 72 nose faces using the surrounding facial UV fit and cleaned 1,120 projected eye pixels with nearby 2D skin samples. Preserved the original texture and head geometry.
- 눈 / Eyes: 기존 `Gravebound_Eyes` 안에서 중복 안구를 정리하고 갈색 홍채·동공과 음영이 있는 흰자를 적용했다. 반지름 5.6mm의 곡면 홍채는 눈꺼풀 개구 중심에 맞춰 2.5mm 아래에 배치했다. 256px 흰자 텍스처는 위 눈꺼풀 근처를 어둡게 하고 아래쪽 음영과 눈 안쪽의 약한 붉은 기운을 더한다. Removed redundant eye shells and added curved brown irises, pupils and shaded sclera. The 5.6mm iris moves 2.5mm down to align with the opening. A 256px sclera texture adds soft upper/lower lid shading and slight nasal warmth.
- 머리카락 / Hair: 길게 늘어진 선 무늬를 짧은 머리 질감으로 바꾸고 앞머리 경계를 1K 텍스처에 베이크했다. 경계 아래 피부는 원래 얼굴의 연속 2D UV로 샘플링한다. Replaced stretched strands with short hair and baked the fringe boundary into a 1K texture, sampling the original continuous facial UVs beneath it.
- 관자놀이·볼 옆 / Temples and outer cheeks: 앞얼굴·측면 피부·귀 위 머리의 9,085개 면을 같은 1K 재질로 연결했다. 원래 앞얼굴 사진과 측면 피부 UV를 공간 기준으로 부드럽게 섞어 큰 톱니 색 경계를 줄였다. 중앙 얼굴과 형상은 유지했다. Connected 9,085 front-face, side-skin and lower-temple hair faces through one 1K material. Spatially blended the original front photograph and side-skin UVs to soften the jagged color boundary, preserving the central face and geometry.

변경 대상은 `Gravebound_AnatomicalHead`의 UV·재질과 `Gravebound_Eyes`다. 그 외 25개 메시의 정점·면·UV·변환·재질을 보존하고 전체 27개 메시 구성을 유지했다. 제거된 후드는 다시 추가하지 않았으며 원본 제작·일인칭 에셋도 보존했다.

English: Changes are limited to the head's UVs/materials and `Gravebound_Eyes`. Preserved vertices, faces, UVs, transforms and materials of the other 25 meshes and retained 27 mesh nodes. The hood remains removed; source and first-person assets are preserved.

- 원본 / Input: `../player_no_hood_20260921/Gravebound_No_Hood.blend`.
- 제작 / Production: `build.py`, `repair_face.py`, `repair_hair.py`, `repair_temples.py`, `repair_eyes.py`.
- 결과 / Outputs: `Gravebound_Repaired_Face.blend`, `gravebound_player_repaired_face.glb`.
- 게임 대상 / Runtime target: `../../godot-game/assets/3d/player/gravebound_player.glb`.

## 검증 상태 / Verification status

- 제작·내보내기 / Production and export: **PASS**. 코·눈·머리·관자놀이 수정 검사, 다른 25개 메시 보존과 전체 27개 메시 구성을 확인했다. 최종 GLB SHA256: `63e38da6e529c2923f6afdba89ae959da24aad1bd80a43863fc5d7597372a818`. Repair checks and preservation of the other 25 meshes and 27-node model passed; final GLB exported with this SHA256.
- 에셋 검사 / Asset checks: 최종 GLB의 관련 Godot 검사 **3/3 PASS**. All three relevant Godot asset checks passed on the final GLB.
- 통합 검사 / Integration check: `player_appearance` **PASS**. 실제 모델·인벤토리 초상화·카메라 레이어·F2 왕복·초기화·원정 복원을 확인했다. Actual model, inventory portrait, camera layers, F2 roundtrips, reset and expedition restoration passed. 기존 종료 시 ObjectDB 2개 경고는 남는다. The existing two-ObjectDB exit warning remains.
- 실제 화면 / Visual checks: **PASS**. embedded/Vulkan 10개 시점과 같은 SHA의 360° 뷰어에서 겹눈·코의 검은 조각·귀 앞의 깨진 경계 제거를 확인했다. Ten embedded/Vulkan views and the same-SHA 360° viewer confirm removal of doubled eyes, black nose fragments and the broken ear-front boundary. 검증용 Godot·Blender 프로세스 종료도 확인했다. Validation Godot/Blender processes exited.
- 게시 대상 / Publication target: `duq711/musimusihan-rpg`, `codex/player-fullbody-fp-arms`. 이 작업의 코드·제작 원본·런타임 에셋·검수 이미지를 함께 공유한다. Publish the scoped code, production source, runtime assets and review images together.

확대 검수 / Close-up review: `PLAYER_QA_FACE_DETAIL=1 PLAYER_QA_BODY_ONLY=1 PLAYER_QA_ITERATION=face_repair_20260921 tests/run_embedded_preview.sh player_appearance_preview.gd`는 기본 5개에 정면·양쪽 사선·후면·정수리 확대 5개를 추가한다. 기본 실행 결과는 유지한다.

English: `PLAYER_QA_FACE_DETAIL=1` adds five close views (front, both oblique views, rear and crown) to the five default captures; default behavior remains unchanged.

검수 범위 / Review limits: 이번 수정은 잘못 연결된 재질과 깨진 경계를 바로잡는다. 원본 얼굴의 낮은 세부 해상도·구운 음영·측면 텍스처 늘어짐과 단순한 흰자 표현은 남는다. This repair fixes incorrect materials and broken boundaries; original facial detail resolution, baked shading, side-texture stretching and simple sclera rendering remain.

검수 산출물 / Evidence: `../../godot-game/artifacts/visual_qa/player_appearance/face_repair_20260921/`, `build_report.json`, `asset_test.log`, `integration_test.log`, `render.log`.
