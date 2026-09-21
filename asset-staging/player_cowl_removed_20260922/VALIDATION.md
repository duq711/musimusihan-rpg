# 목·어깨 후드 제거 / Remove the draped neck hood

사용자의 요청에 따라 목을 감싸던 천과 양쪽 어깨·뒤쪽 망토를 실제 메시에서 제거했다. 삭제 대상은 `Gravebound_InnerNeckCowl`, `Gravebound_Mantle_L`, `Gravebound_Mantle_R`, `Gravebound_MantleBack`이다. 이전 원본은 보존하고 별도 `.blend`와 `.glb`를 저장했다.

English: Physically remove the neck wrap and front/rear shoulder mantle meshes named above. Preserve the previous source and save separate Blender and GLB outputs.

- 제공한 얼굴·눈, 몸통, 양팔·손을 포함한 나머지 **23개 메시의 정점·면·UV·변환·재질을 보존**했다. 원래 상의에 구워진 옷깃 무늬는 남는다. Preserve the other **23 meshes' vertices, faces, UVs, transforms and materials**, including the supplied head/eyes and both arms/hands. The original jacket's baked collar pattern remains.
- 몸통과 소매는 원래 닫힌 메시다. 목은 몸통 상단에 겹쳐 연결되며 새 후드나 천을 추가하지 않는다. The existing torso and sleeves are closed meshes; the neck overlaps the torso top without adding replacement cloth.
- 제작 / Build: `build.py`, `Gravebound_No_Cowl.blend`, `gravebound_player_no_cowl.glb`, `build_report.json`.
- 게임 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.

## 검증 / Validation

- Mac Blender 백그라운드 제작과 23개 메시 보존 검사 **PASS**. Background Mac Blender build and retained-mesh comparison passed.
- `player_fullbody_fp_arms`, `player_hood_closure`(후드 제거 검사로 갱신 / updated to cowl removal), `player_face_asset`, `player_appearance`: **4/4 PASS**. 실제 모델·초상화·카메라 레이어·F2 왕복·초기화·원정 복원을 포함한다. Covers the actual model, portrait, camera layers, F2 roundtrips, reset and expedition restoration.
- 실제 Godot embedded/Vulkan **12개 시점**을 촬영했고, 네이티브 창·입력·커서·원정을 변경하지 않았다. Twelve real Godot embedded/Vulkan captures preserve native windows, input, cursor and expedition state.
- 360° 뷰어에서 목과 높은 뒤쪽 어깨 시점을 검토했다. Reviewed the neck and high rear shoulder view in the 360° viewer.
- 격리 임포트의 텍스처 UID는 기존 게임 UID와 달라 일부 경로 대체 경고가 발생했지만 텍스처는 정상 로드됐다. 게임 연동 검사 종료 시 기존 유형의 ObjectDB 1개 경고가 남는다. Isolated-import texture UIDs differ from the game cache, producing path-fallback warnings with successful texture loading; one existing-type ObjectDB exit warning remains.
- 근거 / Evidence: `tests.log`, `render.log`, `build_report.json`, `../../godot-game/artifacts/visual_qa/player_appearance/cowl_removed_20260922/`.
- 최종 모델 / Final model SHA256: `c90f433596d8f7c60f0d22d93277e1077324a4b7e299626156d3d2ea82e622e1`.
