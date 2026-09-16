# 오크 제거 검증 / Orc removal validation — 2026-09-17

사용자 요청으로 신규 오크의 모델·텍스처·컨트롤러·테스트룸 항목을 삭제했다. 폐광 동쪽 창고의 기존 검지기와 적 6명·수치·보상·탈출 조건을 복구/유지했다. 제작 원본은 asset-staging/orc_20260917에 보존한다.

Removed the rejected orc runtime assets, controller and test-room entry. Restored the original eastern-store warden and preserved all six encounters, stats, rewards and extraction rules. Source files remain archived outside the game.

- cave_dungeon: PASS. 실제 창고 검지기 및 기존 함정·상자·6명 처치 탈출 검사. Real restored warden and cave gameplay regression.
- test_room: PASS. 원정 격리/복원·기존 시험·오크 항목 제거 확인. Session isolation/restoration, existing trials, removed orc entry.
- 첫 test_room 실행은 오래된 허용 action 목록의 기존 7개 동작 누락으로 실패했다. 실제 run_feature()에 이미 구현된 이름으로 목록을 맞춘 뒤 재실행하여 통과했다. 생산 동작은 변경하지 않았다. Initial catalog validation had seven stale omissions; synchronized the test allowlist with already implemented actions, then passed. No production action changes.
- 기존 test_room 종료 경고: ObjectDB 2개 누수. 검사 오류는 없었다. Existing shutdown warning: two leaked ObjectDB instances, no test failures.
- cave_store_enemy_preview: 실제 Forward+/Vulkan 렌더 PASS. 저장된 PNG를 열어 원래 검지기 복구를 확인했다. 원정/커서 보존 확인, 창·OS 입력·소리 없음. Actual GPU capture visually reviewed; original warden restored, session/cursor preserved, no native window/input/audio.

![복구된 창고 적 / Restored store enemy](restored_store_warden.png)
