# 로딩 화면 검수 / Loading screen review

2026-09-20. 기존 성소 배경을 보존하고 로딩 UI만 수정했다. 청록색 카드·마름모·숫자 진행률·경과 시간·중복 안내를 제거했다. 소형 중립색 표시와 실제 진행률 선, 짧은 목적지/팁으로 정리했다.

The existing sanctuary artwork is preserved. The teal card, diamond, numeric percentage, timer and repeated copy were removed. A small neutral indicator, honest progress line and concise destination/tip remain.

- PASS: loading_screen — 실제 boot→main_menu 비동기 전환, 진행률, 일시정지 중 표시, 오류 및 재설정, 960×540 배치. / Real boot-to-menu threaded transition, progress, paused activity, errors/reset and compact layout.
- PASS: loading_preview — embedded/Vulkan 실제 4장. 01_boot, 02_hideout_small, 03_dungeon_wide, 04_failure. / Four actual embedded/Vulkan captures.
- 직접 검토: 카드 없이 장면이 전체 화면을 채우고, 하단 문구가 배경과 분리되어 읽힌다. 작은 화면에서도 잘림·겹침 없음. 오류 상태에서는 진행 표시가 멈추고 오류 코드와 안내가 보인다. / Visual review: full-screen scene, readable lower copy, no clipping or overlaps at compact size, stopped indicator and readable failure information.
- 원정·커서 보존 true, 촬영 중 소스 해시 불변, failures 없음. / Session and cursor preserved; stable source hashes and no failures.
- OS 입력·포커스는 조작하지 않았다. 이전 플레이어 스크립트의 비관련 경고는 render.log에 보존하며 이번 변경의 오류로 보고하지 않는다. / No OS input or focus manipulation. Existing unrelated player-script warnings remain in the local render log.

본편의 비동기 전환 API와 테스트룸 장면 이동은 같은 로더를 사용한다. 이 작업에서 새 게임 규칙·보급·원정 상태를 추가하지 않았다.

Production and existing test-room scene transitions share this loader. No gameplay rules, supplies or expedition state were added.
