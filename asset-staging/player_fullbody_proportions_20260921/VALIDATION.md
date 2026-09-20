# 손 비율 검증 / Hand proportion validation

2026-09-21: 전신 손을 82%로 축소하고 손목 중심을 유지하며 소매 끝을 연결했다. Mac Blender 백그라운드로 별도 제작 원본을 저장했다.

- `player_fullbody_fp_arms`: PASS. 28개 메시·장갑 세로 20–22cm·가로 15cm 미만·손목/어깨 위치·재질·구형 손 제거 검사.
- 기존 24개 몸 메시 서명과 1인칭 원본/스크립트 해시는 이전 제작 결과와 동일.
- 숨김 Vulkan 실제 렌더: PASS, 전신 4방향과 얼굴 5장. 정면·사선·측면·후면을 직접 검토했다.
- 결과: `godot-game/artifacts/visual_qa/player_appearance/fullbody_proportions_20260921/`. 입력·원정 상태 보존. 기존 스크립트 경고는 있으나 오류 없음.
- 공용 모델만 교체하며 기존 F2 외형·인벤토리 연결 코드는 유지한다. 전체 게임 회귀를 재실행한 것은 아니다.

English: Reduced full-body hands to 82%, anchored at the wrists, with a smooth sleeve transition. Saved separate editable production sources using background Blender on Mac. The asset test passed (28 meshes, 20–22cm hand height, under 15cm width, wrist/shoulder placement, materials, retired-hand removal). The other 24 mesh signatures and first-person source/script hashes match the prior production record. Hidden Vulkan rendering passed with five captures; front, quarter, side and back were visually reviewed. Input and expedition state stayed intact. Existing script warnings remain without errors. This replaces only the shared model and retains existing F2/inventory routing; it is not a new full-game regression run.

Rebuild: run `build.py` using Mac Blender. It reuses `../player_fullbody_fp_arms_20260920/pose.json` and the preserved original-body backup from that production archive.
