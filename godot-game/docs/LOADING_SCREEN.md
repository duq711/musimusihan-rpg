# 로딩 화면 / Loading screen

2026-09-20 사용자 요청: 제공한 세 게임 화면처럼 어두운 장면 중심으로 구성하고, 과도한 장식과 반복 안내를 줄인다.

User request, 2026-09-20: Use a dark scene and restrained information, following the three supplied game screenshots.

## 적용 / Implementation

- 기존 `assets/ui/main_menu_background.png`를 전체 화면에 재사용한다. 원본 이미지는 수정하지 않고 `shaders/loading_backdrop.gdshader`로 채도·가장자리·하단 밝기를 조절한다. 새로운 이미지 생성이나 참고 게임의 이미지 복사는 하지 않았다.
- 청록색 카드, 마름모 문양, 진행률 숫자, 경과 시간, 중복 안내를 없앴다. 작은 중립색 회전 표시, 실제 진행률에 연결된 1px 선, 목적지 이름과 게임 팁 한 줄을 남겼다.
- 시작·은신처·던전·상인·테스트룸은 같은 로더를 사용한다. 기존 호출의 긴 설명은 로딩 화면에 나열하지 않는다. 실패 시 오류 설명과 코드를 표시하며 표시를 초기화하면 정상 상태로 돌아온다.
- 비동기 요청, 진행률, 완료·실패 신호, 입력 차단, 일시정지 중 처리, 장면 준비 후 닫기 동작은 유지한다. 로딩 시간을 연출 때문에 추가로 늘리지 않는다.

The existing sanctuary artwork fills the screen. Its original file is preserved; a canvas shader reduces saturation and fades the edges and lower area. No new generated artwork or copied reference-game art was used. The teal card, diamond ornament, percentage, elapsed time and repeated messages were removed. A small neutral activity ring, a one-pixel line tied to actual progress, a destination label and one gameplay tip remain. Threaded loading, input blocking, paused processing, completion/failure handling and readiness dismissal remain unchanged. No extra artificial loading delay was added.

## 테스트룸 / Test room

기존 `F2 → 장면 → 3D 은신처 · 생활 기능` 또는 `검은 성물실 · 전체 원정`으로 이동하면 같은 실제 로딩 화면을 사용한다. 연결 장면에서 F2 복귀 시에도 새 표시를 사용한다. 이번 변경은 기존 화면의 외형 변경으로, 원정 상태나 시험 보급을 수정하지 않는다.

Existing F2 scene entries use this production loader, including the return to the test room. This presentation change does not alter expedition state or test supplies.

## 검증 / Validation

```sh
GODOT_TEST_TIMEOUT_SECONDS=300 ./godot-game/tests/run_headless_tests.sh loading_screen
LOADING_QA_ITERATION=<new_folder> ./godot-game/tests/run_embedded_preview.sh loading_preview.gd
```

자동 검사는 실제 시작→메인 메뉴 비동기 전환, 단조 증가 진행률, 가짜 진행 방지, 일시정지 중 표시, 오류/초기화, 960×540 배치를 확인한다. 숨김 프리뷰는 960×540, 1280×720, 1920×1080과 오류 화면을 실제 렌더러로 저장하고 원정·커서·소스 해시 보존을 검사한다. OS 하드웨어 입력은 조작하지 않는다.

Automated checks cover the real boot-to-menu threaded transition, monotonic and honest progress, paused activity, errors/reset and compact layout. The hidden renderer captures three resolutions plus an error state, checking session, cursor and source preservation. It does not exercise OS hardware input.

최종 결과 / Final results: see `artifacts/visual_qa/loading/quiet_sanctuary_20260920/REVIEW.md` and its manifest.
