# 간단 제작 교체 / Simple crafting replacement

2026-10-04, 한국 시간 / Korea time.

사용자 확정: 기존 갑옷·물약·무기 제작을 첨부 사진의 간단한 구성으로 교체합니다. **분류·아이템 목록 → 설명·필요/보유 재료 → 수량 → 제작 → 대기열**이 현재 제작 방식입니다. 새 작업대 등급·잠금·제작 숙련도는 추가하지 않았습니다.

Approved request: replace the previous crafting with the supplied reference's simple categories, item grid, description/materials, quantity and queue flow. Workbench tiers, locks and crafting skill progression are not part of this change.

## 현재 동작 / Current behavior

- 무기·방어구·물약·도구/소모품의 고정 제조법 18개. 표준 아이템을 자동 제작하며 수동 가열·망치질·천공·룬 개조·약초 손질·젓기·병입 화면과 기존 제작 F2 항목을 제거했습니다. / Eighteen fixed recipes produce standard items automatically. Manual forging, drilling, rune upgrading and alchemy screens and their old F2 entries are removed from active gameplay.
- 은신처의 기존 제작대와 물약 작업대에서 E로 같은 화면을 엽니다. 분류 선택은 시작 목록만 바꾸며 어느 작업대에서도 모든 제조법을 선택할 수 있습니다. / Existing sanctuary stations open the shared screen with E; either station permits every category.
- 수량 1~99, 최대 버튼, 1회·선택 수량의 필요 재료와 실제 가방 보유량, 제작 시간·완성 수량을 표시합니다. 재료가 부족하면 제작 버튼을 비활성화합니다. / Quantity 1–99, Max, per-craft/total costs, owned materials, duration and output quantity are shown; insufficient materials disable crafting.
- 최대 8개 작업을 먼저 넣은 순서대로 처리합니다. 선택 수량 전체가 한 작업이며 시간은 1회 시간 × 수량입니다. 화면을 닫아도 대기열은 유지되고 실제 플레이 중 진행됩니다. 정지·가방·설정·지도·F2 메뉴 동안 제작 시간이 멈춥니다. / Up to eight FIFO batches; batch time is per-craft time × quantity. Closing the screen retains the queue, and normal play advances it. Paused/modal/F2 menus freeze its clock.
- 대기열 등록 시 재료를 정확히 확보합니다. ×로 취소하면 원래 재료와 이름표를 반환합니다. 가방이 차면 완성품 또는 반환 재료가 대기하며 공간이 충분할 때 전체를 지급합니다. / Enqueue reserves exact ingredients. Cancel refunds their original instance data. A full bag retains complete output/refunds until enough room exists for an atomic delivery.
- 기존 아이템·개별 검의 개조 정보·에셋 원본을 보존합니다. 이전 검의 개조 효과는 유지하지만 새 제작품에는 품질 판정이나 룬 조작이 없습니다. / Existing items, weapon upgrades and production sources are preserved. Historical upgrades remain effective; new crafting has no quality minigame or rune operation.
- F2의 `간단 제작 · 재료·수량·대기열`에서 동일한 UI와 규칙을 시험합니다. 원래 가방 객체·구독·원정·제작 서비스·진행 중 대기열·화면 선택을 보존하고 시험 종료 시 복원합니다. / The simple-crafting F2 entry exercises the production UI while preserving and restoring the original inventory identity, session, crafting service, pending queue and screen selection.

## 구현 위치 / Implementation

- `Assets/RPG/Runtime/SimpleCraftingSystem.cs`: 제조법·재료 예약·FIFO·취소·가방 공간 처리 / recipes and transactional queue.
- `Assets/RPG/Gameplay/NativeCrafting.cs`, `NativeCraftingFlow.cs`: 공유 화면·기존 작업대 연결 / shared UI and station entry.
- `WorkshopController.cs`, `WorkshopSimpleCrafting.cs`, `WorkshopTrialWorld.cs`, `NativeTrialMenu.cs`: 현재 설명·제작 시계·격리된 F2 연결 / current descriptions, clock and F2 isolation.
- 기존 제작 원본 카탈로그·모델·과거 인수 검사는 보존 자료입니다. 현재 게임은 해당 수동 UI를 생성하거나 입력을 처리하지 않습니다. / Legacy catalogs, models and old acceptance fixtures remain as historical compatibility material; live gameplay neither instantiates nor processes the manual UI.

## 검증 / Validation

**Unity EditMode 9개·PlayMode 4개와 최종 Mac Metal 실행본 87개 UI·연결 검사가 모두 통과**했습니다. 빌드는 오류 0개이며 기존 경고 176개를 기록했습니다. 실제 Unity EditMode, PlayMode, Mac 실행본 검사와 Metal 화면 결과는 `simple-crafting-validation-20261004.json`에 기록합니다. 실행은 숨김 백그라운드 방식이며 오디오 재생·마우스 캡처를 차단했습니다. 하드웨어 키보드/마우스, 최종 스피커 출력, 전체 게임 완성률을 인증하는 검사는 아닙니다.

**All 9 EditMode tests, 4 PlayMode tests and 87 final Mac Metal player checks passed.** The build has zero errors and 176 recorded warnings. Actual Unity domain, controller, packaged-player and Metal screen evidence is in `simple-crafting-validation-20261004.json`. Validation is hidden and silent, with no desktop pointer capture. Hardware input, speaker output and whole-game completion are outside these scoped checks.

![실제 Unity 제작 화면 / Actual Unity crafting screen](simple-crafting-ui-20261004.png)

빌드 중 저장 공간 부족으로 직렬화 데이터 일부가 0으로 기록된 실패를 확인했습니다. 원본과 기존 임포트 자료가 정상임을 확인하고, 여유 공간이 확보된 상태에서 이번 앱·플레이어 데이터 캐시를 재생성했습니다. [Unity의 CleanBuildCache 절차](https://docs.unity3d.com/6000.0/Manual/build-clean-build.html)를 사용했으며 `RPG_CLEAN_BUILD_CACHE=1`로 재현할 수 있습니다. 복구본에서 Mesh 4,163개·TextAsset 112개의 데이터와 원본 은신처 JSON 전체 바이트를 확인한 뒤 최종 실행본 검사를 다시 통과했습니다.

A disk-full build produced empty serialized payloads. Source/imported assets remained intact. Regenerating this task's player cache and app with enough free space and CleanBuildCache recovered the output. The recovered app's 4,163 meshes, 112 text assets and complete hideout JSON were checked before the final player acceptance passed.

## 공유 / Publication

구현 커밋은 `3483e44d`입니다. 로컬 GitHub 인증 만료로 전체 Unity 브랜치와 LFS 푸시는 차단됐습니다. 연결된 GitHub를 통해 [이번 작업의 복원 패키지](https://github.com/duq711/musimusihan-rpg/tree/codex/unity-simple-crafting-20261004-evidence/task-archives/simple-crafting-20261004)에 정확한 코드 패치·실제 화면 바이트·검증 기록을 게시하고 원격 내용을 비교합니다. 작업 패키지 공유는 전체 Unity 브랜치 동기화와 구분합니다.

Implementation commit: `3483e44d`. Expired local GitHub authentication blocks the full Unity branch and LFS push. The connected GitHub app publishes the exact task patch, actual screenshot bytes and validation records in the linked restorable package, with remote content verification. This task archive is separate from full Unity branch synchronization.
