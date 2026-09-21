# 직전 팔 모델 복원 / Restore the previous arm model

사용자 요청: 마지막 어깨·팔 수정 결과가 이상해졌으므로 이전 버전으로 복귀한다.

English: The user rejected the latest shoulder/arm changes and requested the previous version.

- 철회 / Rejected: `9081104ab3c10841417e355f002f7936fc49beb0`.
- 복원 기준 / Immediate predecessor: `f279eecf95efa4f012164a05877bd9762c369e92`.
- 원본 / Source: `../player_trousers_only_20260922/gravebound_player_trousers_only.glb`.
- 활성 에셋 / Runtime: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- SHA256: `f7ad57eddd4ac751daee53fcdb05bf627a749007f0989d9f344f735dfb2e2a77`.

직전 Git LFS 해시와 보존된 원본, 복원한 게임 파일의 바이트가 일치한다. 얼굴·손·바지·벨트·부츠와 후드/코트 제거 상태를 유지했다. 기존 접합면 검사의 고정 좌표도 직전 모델에 맞춰 복원했다. 마지막 조형 산출물과 검토 도구는 이력으로 보존한다.

English: The prior Git LFS hash, preserved source and restored runtime bytes match exactly. Preserve the face, hands, trousers, belt, boots and hood/coat removal. Restore the seam test’s previous coordinate condition. Retain the rejected production artifacts and inspection tooling as history.

## 검증 / Validation

복원 바이트 확인 / Byte equality: `restore_report.json`.

- Godot 검사 4/4 통과: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`, `player_appearance`. Four targeted Godot checks pass; see `final_tests.log`.
- 숨김 실제 렌더 5장과 360° 뷰어에서 복원본 표시 확인. Five actual-renderer captures and the 360° viewer show the restored model. Captures: `../../godot-game/artifacts/visual_qa/player_appearance/shoulder_rollback_20260922/`.
- 격리 임포트의 UID 경로 대체와 기존 유형 ObjectDB 종료 경고는 남지만 모델은 정상 로드되며 모든 검사는 통과한다. Isolated-import UID fallbacks and an existing-type ObjectDB exit warning remain; the model loads and all checks pass.
