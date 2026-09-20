# 후드 제거 / Remove the hood

사용자의 최종 요청에 따라 `Gravebound_PointHood`를 전신 모델에서 제거한다. 앞서 만든 어깨 연결 천과 목 카울, 망토, 손·팔은 유지한다. 후드 아래 머리에는 의상 그림이 투영돼 있었으므로, 기존 머리 형상을 유지하면서 원본 머리의 얼굴·귀·목·두피 UV와 사용 재질을 복원한다. 두피만 복원한 중간본은 최종 결과로 사용하지 않는다.

English: Follow the user's final request by removing `Gravebound_PointHood` from the full-body model. Retain the shoulder closure, neck cowl, mantle, arms and hands. The formerly hidden head carried projected clothing artwork, so restore the original facial, ear, neck and scalp UVs/materials while preserving its geometry. The scalp-only intermediate model is not the final result.

- 원본 / Input: `../player_hood_shoulder_closure_20260921/Gravebound_Closed_Shoulder_Hood.blend`.
- 머리 재질 원본 / Head material source: `../blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend`, object `Mercenary_Male_HeadNeck_LOD0`.
- 제작 / Production: `build.py`, `restore_scalp.py`, `Gravebound_No_Hood.blend`, `gravebound_player_no_hood.glb`.
- 게임 결과 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- 최종 GLB SHA256: `6217c0ab6c9d79de8f77395011e6d22cbb5678fba593627259ad62d9ecdeb529`.

## 보존과 복원 / Preservation and restoration

후드 제거 후 메시 수는 27개다. 머리 외 다른 26개 메시의 정점·면·UV·변환은 보존 검사 대상으로 유지하며, 머리 역시 정점·면을 바꾸지 않는다. 현재 머리의 35,366개 삼각형과 원본을 좌표로 일치시킨 뒤 면별 UV를 복원하여 이음새에서 다른 면의 UV를 섞지 않는다. 머리의 실제 사용 재질 7개와 관련 텍스처 11장을 복원한다. 원본 파일은 수정하지 않으며, 패킹할 복사본 텍스처의 최대 해상도를 2048로 제한한다. 원본 앞·뒤 얼굴 투영 재질은 조명에 반응하지 않는 방식이었으므로, 같은 UV·알베도를 Principled BSDF의 Base Color에 연결하고 거칠기 0.88의 PBR 재질로 바꿔 게임 조명에 맞췄다.

English: Removing the hood leaves 27 meshes. Preserve vertices, faces, UVs and transforms of the other 26 meshes; also preserve the head's vertices and faces. Match all 35,366 head triangles to the source by position and transfer UVs per face corner, retaining the original seams. Restore seven used materials and eleven associated textures. Preserve source files and limit only the packed texture copies to a maximum dimension of 2048. Replace the original unlit front/back face projection shaders with Principled BSDF materials using the same UVs/albedo and roughness 0.88 so they respond to game lighting.

## 검증 상태 / Verification status

최종 제작·자동 검사·Godot 실제 렌더·360° 뷰어 검증을 완료했다. GitHub 원격 게시는 아래 절차로 진행한다.

Final production, automated checks, actual Godot rendering and the 360° viewer check are complete. GitHub publication follows the process below.

- 제작 / Production: `build_report.json` 및 `restoration_report.json` PASS. 35,366개 머리 면의 원본 매칭 오차 0, 누락·중복 0. 전체 머리 UV/사용 재질 복원과 머리 형상 보존, 다른 26개 메시 보존 및 총 27개 메시를 확인했다. Both final reports confirm exact head matching, restored UVs/materials, unchanged head geometry, preservation of the other 26 meshes and 27 meshes in total.
- 자동 검사 / Automated checks: `asset_test.log`의 2개 검사 및 `integration_test.log`의 통합 검사 1개 PASS. 앞·뒤 투영 재질의 PBR 전환 이후 최종 GLB로 다시 통과했다. Both asset checks and the integration check pass on the final GLB after converting the projection materials to PBR.
- 360° 뷰어 / 360° viewer: 최종 GLB의 정면·후면·전신을 직접 확인했다. 후드가 없고 기존 망토·손·팔은 유지된다. Inspected the final GLB from the front, rear and full-body views; the hood is absent and the mantle, hands and arms remain.
- 실제 렌더 / Actual rendering: Godot embedded/Vulkan에서 `no_hood_20260921` 12개 시점 생성 PASS. 전신 정면·정수리·후두부·어깨를 시각 확인했고 모델 해시가 최종 GLB와 일치한다. Twelve embedded/Vulkan views passed; front, crown, rear head and shoulder renders were inspected, with the final model hash confirmed.
- 공유 / Publication: 프로젝트 지시에 따라 관련 변경만 커밋·LFS 업로드·푸시 후 원격 SHA를 확인한다. Commit only this task, upload LFS assets, push, and verify the remote SHA per project instructions.

머리의 기존 줄무늬와 각진 UV 경계는 남아 있다. 이번 검증은 후드 제거·원본 머리 복원·의상 보존에 해당하며 머리 모델 전체의 품질 개선을 의미하지 않는다. 통합 검사 종료 시 기존 ObjectDB 누수 경고 2개와 UID 경로 fallback 경고가 남지만 검사는 통과했다.

English: Existing striped hair and angular UV boundaries remain. This verification covers hood removal, original head restoration and outfit preservation, not a full head-quality redesign. The integration test passes with existing warnings for two ObjectDB instances at exit and UID path fallbacks.
