# 야영 설치와 텐트 요리 / Camp placement and tent cooking

2026-09-20 사용자 요청과 현재 구현 연결 기록입니다. 검증 결과·게시 상태는 해당 작업의 최종 기록을 따릅니다.

## 사용자 확정 / Confirmed request

C로 바로 모닥불을 설치하는 조작을 없애고, 설치할 수 없는 방향은 빨강·가능한 방향은 초록으로 표시합니다. 설치한 텐트에 상호작용하면 모닥불 앞에 앉아 음식을 요리합니다.

Remove direct C-key camp installation. Show invalid placement in red and valid placement in green. Interacting with the installed tent seats the player by the fire for cooking.

## 구현한 조작 / Implemented flow

1. 가방에서 휴대 야영 도구를 선택하고 **설치**를 누릅니다.
2. 바닥을 조준합니다. 초록은 설치 가능, 빨강은 불가입니다.
3. 초록에서 **LMB**로 확정하면 도구 1개를 소비합니다. **F / Esc**로 확정 전에 취소하면 소비하지 않습니다.
4. 텐트를 바라보고 **E**로 상호작용하면 모닥불 앞에 앉습니다.
5. 요리 탭에서 조리법을 고릅니다. 재료·온기는 조리 시작 때 소비하고, 완료하면 즉시 먹어 실제 회복 효과를 적용합니다.
6. **Esc / 일어서기**는 야영지를 남기고 일어섭니다. **야영지 정리**는 설치물을 제거하며 도구를 반환하지 않습니다.

Choose Install on the camp kit, aim, and confirm a green location with LMB. Confirmation spends one kit; F or Esc cancels an unconfirmed preview for free. Use E on the tent to sit. A recipe spends ingredients and warmth at its start and applies food recovery only on completion. Standing up keeps the campsite; dismantling removes it without refunding the kit.

조준 사거리 5m, 전체 설치 공간·바닥·물·장애물·좌석 접근 검사, 한 번에 야영지 한 개, 온기 3은 이번 구현에서 정한 조정 가능한 값과 규칙입니다. 미리보기는 실제 물리 검사 결과를 사용하고 확정 순간 다시 검사합니다. 적 접근·피격 등으로 미완료 활동이 중단되면 회복 효과를 주지 않으며 사용한 재료를 반환하지 않습니다. 시험 메뉴·항목 변경·초기화·장면 이탈은 설치물과 미리보기를 정리합니다.

The tunable implementation uses a five-meter aim range, full footprint/floor/water/obstacle/access checks, one deployed camp, and three warmth. Confirmation repeats the physical validation. Interrupted activities give no completion recovery or ingredient refund. Test-menu transitions, trial changes, resets and scene exits clean up campsite and preview objects.

## 현재 요리 범위 / Current cooking scope

기존 `CampCookingCatalog`의 고기구이·버섯수프·고기버섯 스튜를 연결합니다. 실제 꼬치·냄비의 조리 진행, 재료 수량, 남은 시간, 완료 후 즉시 식사·회복을 사용합니다. 자유로운 조리 도구 조작이나 별도 완성 음식 저장 기능은 현재 범위에 포함하지 않습니다. 은신처의 고정 화롯불은 기존 도구·온기 무료 규칙을 유지합니다.

The existing catalog supplies roast meat, mushroom soup and meat/mushroom stew. Cooking uses the real spit/pot presentation, ingredient quantities, elapsed time and immediate eating/recovery on completion. Freeform utensil manipulation and stored finished meals are outside the current scope. The hideout's fixed cooking fire retains its existing no-kit/no-warmth rule.

## 테스트룸과 파일 / Test room and files

`F2 → 생존 → 야영 · 빨강/초록 설치 판정`은 열린 바닥과 실제 장애물, 야영 도구·조리 재료를 준비합니다. 기존 휴식·응급처치 및 요리 항목도 같은 설치·텐트 흐름을 사용합니다. 시험은 별도 원정과 가방에서 실행되며 종료 시 원래 원정의 객체와 내용을 복원합니다.

The F2 survival placement trial supplies open ground, a physical obstacle, kits and cooking materials. Existing rest/treatment and cooking trials use the same production placement/tent flow. The sandbox restores the original expedition and inventory identity after testing.

| 파일 / File | 역할 / Role |
|---|---|
| `scripts/camp_controller.gd` | 배치·설치·착석·요리 상태와 자원 거래 / Placement, camp activity states and transactions |
| `scripts/camp_placement_probe.gd` | 물리 바닥·공간·좌석 접근 검사 / Physical floor, footprint and access checks |
| `scripts/camp_visuals.gd` | 빨강·초록 미리보기, 모닥불·텐트·조리 외형 / Preview, fire, tent and cooking geometry |
| `scripts/camp_placement_overlay.gd` | 설치 상태·확정·취소 안내 / Placement status and control prompts |
| `scripts/game.gd`, `scripts/inventory_overlay.gd`, `scripts/player.gd` | 가방·입력·착석 연결 / Inventory, input and seated player integration |
| `scripts/test_room.gd`, `scripts/test_room_catalog.gd` | 실행 가능한 F2 비교 항목 / Playable F2 comparison trial |
| `tests/camp_placement_test.gd`, `tests/camp_placement_room_test.gd` | 물리 판정·거래·실제 가방/텐트 경로와 원정 복원 / Physical checks, transactions, real inventory/tent routes and restoration |

헤드리스 검사 후 숨김 렌더러로 확인합니다. 명령은 `godot-game/`에서 실행합니다.

Run the related headless checks before the hidden renderer, from `godot-game/`.

```bash
./tests/run_headless_tests.sh camp_placement camp_placement_room camp_system camp_flow camp_hud cooking_system cooking_hud stress_system test_room test_room_session
CAMP_PLACEMENT_QA_ITERATION=<새 이름> ./tests/run_embedded_preview.sh camp_placement_preview.gd
```

[숨김 실행 규칙](../tests/EMBEDDED_RENDERING.md)을 따릅니다. 실제 UI 콜백·물리 상호작용과 렌더링 검증은 OS 마우스 캡처·하드웨어 입력 검증을 포함하지 않습니다.

Follow the hidden-rendering rules. Real UI callbacks, physical interaction targets and rendered output do not establish native OS pointer-capture or hardware-input coverage.

검증 결과는 [이번 작업 검수 기록](../artifacts/validation/camp_placement_20260920/README.md)에 남깁니다. / See the linked task validation record for executed checks and rendered evidence.
