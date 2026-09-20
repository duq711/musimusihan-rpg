# 팔 전체 재조정 / Whole-arm refit

사용자가 손 축소 후에도 팔 비율 문제를 지적하여 소매 전체를 다시 맞췄다. 전완 폭을 약 18cm에서 12cm로 줄이고 손목을 7cm 아래·2cm 안쪽으로 옮겼다. 팔꿈치 기준 높이는 1.135m다. 손 크기는 앞선 82%를 유지했다. 손목 접합부는 손과 소매에 동일한 이동을 적용해 보존했다.

- Mac Blender 별도 제작: `build.py`, `Gravebound_FP_Arms.blend`, `gravebound_player_fp_arms.glb`. 이전 버전 보존.
- `player_fullbody_fp_arms`: PASS. 전완 폭/깊이, 손목·손끝 높이, 어깨 연결, 28개 메시, 재질, 이전 손 제거 검사.
- 나머지 몸 메시 24개의 서명 및 1인칭 에셋·스크립트 해시는 이전 결과와 동일.
- 기존 F2 외형 기능이 사용하는 공용 게임 모델 교체. UI·전투 코드는 변경하지 않음.

English: Following user feedback, refit the entire sleeve rather than shrinking the hands again. Reduce the forearm from roughly 18cm to 12cm wide, move the wrist 7cm downward and 2cm inward, and place the elbow reference at 1.135m. Retain the 82% hand scale. Preserve the wrist junction by applying the same translation to both meshes near the seam. The asset regression passes, covering arm dimensions, wrist/fingertip height, shoulder connection, materials, 28 meshes and retired-hand removal. Other body geometry and first-person source hashes remain unchanged. The existing F2 appearance entry uses the updated shared model; no UI or combat code changes.

Rebuild using Mac Blender and `build.py`; it reuses the original body archive and `pose.json` in `../player_fullbody_fp_arms_20260920/`.

최종 숨김 Vulkan 렌더 PASS: `godot-game/artifacts/visual_qa/player_appearance/fullbody_anatomy_20260921_final/`의 5장. 첫 반복에서 4방향을 확인했고, 손목 경계 보정 후 최종 사선·측면을 재검토했다. 입력·원정 상태 보존, 기존 스크립트 경고 외 실행 오류 없음.

Final hidden Vulkan render passed with five captures. Reviewed four directions in the initial pass and rechecked the final quarter and side views after the wrist seam correction. Input and expedition state were preserved; existing script warnings remain without execution errors.
