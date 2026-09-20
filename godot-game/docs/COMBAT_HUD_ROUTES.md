# 전투 체력 UI 적용 경로 수정 / Combat HUD route fix

2026-09-20

폐광의 별도 플레이어 생성 함수에 전투 HUD 연결이 빠져 있었습니다. 테스트룸도 기본 입장에서는 연결하지 않았고, 전용 UI 시험 이외의 항목을 선택할 때 전투 HUD를 껐습니다. 성물실에서 보이던 새 UI를 실제 폐광·테스트룸에서도 일관되게 표시하도록 수정했습니다.

The mine's separate player-spawn method omitted the combat HUD binding. The test room also skipped it on default entry and disabled it when changing to other trials. The same HUD now appears during play in the sanctuary, mine and test room.

- `scripts/game.gd`: 공통 생성 경로에서 실제 플레이어·가방·아이콘 제공자를 연결합니다. / Bind the real player, inventory and icon provider on the shared spawn path.
- `scripts/cave_dungeon.gd`: 폐광 전용 생성 경로에도 같은 연결을 추가합니다. / Bind the HUD on the mine-specific spawn path.
- `scripts/test_room.gd`: 다른 시험 선택 후에도 새 HUD를 유지하고 지팡이 안내를 `Alt+숫자`로 맞춥니다. / Keep it across trials and correct the staff shortcut guidance.
- F2·인벤토리·일시정지에서는 기존 메뉴 동작에 따라 숨기고, 플레이 재개 시 복원합니다. 숫자는 퀵 소지품, `Alt+숫자`는 주문 선택입니다. / Menus hide the HUD and resuming restores it. Numbers use quick slots; `Alt+number` selects spells.

인체 도형·체력 계산·부위 치료 규칙은 이번 수정의 대상이 아닙니다. 은신처는 기존 요청대로 최소 UI를 유지합니다. 이미 실행 중인 게임은 종료 후 다시 실행해야 변경한 스크립트의 생성 경로가 적용됩니다.

This fixes attachment routes without changing body artwork, health calculations or treatment rules. The hideout retains its minimal HUD. Restart an already running game to use the updated spawn paths.

## 검증 / Validation

```sh
GODOT_TEST_TIMEOUT_SECONDS=600 ./tests/run_headless_tests.sh combat_hud_routes cave_dungeon dungeon_combat_hud
GODOT_TEST_TIMEOUT_SECONDS=600 COMBAT_HUD_QA_SCOPE=routes ./tests/run_headless_tests.sh dungeon_combat_hud_preview
COMBAT_HUD_QA_SCOPE=routes COMBAT_HUD_QA_ITERATION=routes_fixed_20260920 GODOT_PREVIEW_TIMEOUT_SECONDS=600 ./tests/run_embedded_preview.sh dungeon_combat_hud_preview.gd
```

관련 헤드리스 검사 4종 통과. 기본 테스트룸 재개, 시험 변경, F2·인벤토리 왕복, 실제 폐광 입장, 플레이어·가방 연결과 원래 원정·가방 참조 복원을 확인했습니다. 전투 HUD 검사는 실제 치료·장착·경고·메뉴 중 사용 방지도 확인합니다. 주문 시험 준비와 주문 선택·퀵슬롯 함수도 검증합니다. 헤드리스 드라이버는 마우스 캡처를 지원하지 않으므로 플레이어의 캡처 게이트 이후 키 이벤트 전달은 검증 범위에 포함하지 않습니다.

Four relevant headless checks passed, covering default test-room entry, trial changes, F2/inventory cycles, actual mine entry, live player/inventory bindings and restoration of the original session/inventory. Combat HUD checks also cover treatment, equipment, warnings and blocked use while paused, along with spell-trial setup and spell/quick-slot functions. The headless driver cannot capture the mouse, so event delivery past the player mouse-capture gate is outside this validation.

숨김 embedded/Vulkan 렌더로 [폐광 1280×720](../artifacts/visual_qa/dungeon_combat_hud/routes_fixed_20260920/07_mine_warnings.png), [기본 테스트룸 960×540](../artifacts/visual_qa/dungeon_combat_hud/routes_fixed_20260920/08_test_room_default.png)을 직접 검토했습니다. 인체와 팔의 간격·총체력 막대·퀵슬롯이 표시되고 기존 상태 패널은 겹치지 않습니다. 폐광 화면의 경고는 검증용으로 준비한 실제 부상·생존 상태입니다.

Reviewed the actual mine and default test-room GPU renders: separated arms, total health bar and quick slots are visible without overlapping legacy panels. Mine warning icons come from real test damage and survival values.

[촬영 기록](../artifacts/visual_qa/dungeon_combat_hud/routes_fixed_20260920/capture_manifest.json)은 `embedded`, `vulkan`, `preserved: true`, 빈 실패 목록을 기록합니다. 사용자 창·커서·외부 입력·소리 없이 검증했으며 실제 하드웨어 조작 검증은 아닙니다. 촬영 후 추가된 변경은 지팡이 안내문과 입력 회귀검사뿐입니다. 소스 해시는 촬영 시점의 로컬 상태를 보존합니다.

The manifest records embedded/Vulkan rendering, preserved state and no failures. No native window, cursor, external input or audio was used; this does not claim hardware-input validation. Only staff help text and an input regression check were added after capture; source hashes describe the captured local state.
