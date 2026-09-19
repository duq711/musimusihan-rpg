# 포복 크리프 처형 / Crawling Creep execution

2026-09-18 사용자 요청: 다리가 절단되어 기어다니는 크리프를 검으로 찔러 처형하는 동작 한 가지를 우선 제작한다. 기존 서 있는 적의 검·방패 처형과 구분한다.

User request, 2026-09-18: first implement one sword-stab execution for a living Creep crawling after leg loss, separate from the existing standing sword-and-shield execution.

2026-09-19 후속 요청: **찌를 자세 잡기 → 첫 찌르기 → 더 깊게 밀어 넣기 → 검 뽑기**가 구분되는 동작으로 다듬는다. 현재 구현 값과 검증 상태는 아래를 따른다.

Follow-up request, 2026-09-19: distinguish **preparing the stab → first thrust → deeper push → withdrawal**. Current implementation values and validation status are recorded below.

## 조작과 조건 / Input and eligibility

- 검을 든 상태에서 가까운 포복 크리프의 몸통을 바라보고 **LMB를 0.4초 이상 누른 뒤 놓는다**. 짧게 누르면 기존 일반 공격이다.
- 실제 다리 절단 후 랙돌 착지·안정과 포복 회복을 마친 살아 있는 크리프가 대상이다. 포복 크리프는 낮은 체력이나 저스트 가드 경직을 별도로 요구하지 않는다. 떨어지거나 자세를 회복 중일 때, 죽은 상태, 거리·시야·장애물 조건을 벗어나면 시작하지 않는다.
- 검과 방패를 함께 들거나 `1`번으로 방패를 수납한 상태 모두 같은 아래 방향 찌르기를 사용한다. 다른 적과 무기, 기존 일반 공격·서 있는 적 처형 조건은 유지한다.
- 첫 얕은 찌르기에서는 대상을 유지하고, 더 깊이 밀어 넣는 결정타 시점에 한 번만 실제 치명타와 기존 처치 보상을 처리한다. 시체는 기존 랙돌로 이어진다. 동작 중 피해·장비 변경·대상 소멸·새 장애물 등으로 취소되면 예약 치명타가 나중에 발생하지 않는다.

With a sword drawn, aim at a nearby crawling Creep's torso, hold LMB for at least 0.4 seconds and release. Short clicks remain ordinary attacks. A living leg-severed Creep must finish its physical landing and prone recovery; no additional low-health or stagger requirement applies. Falling/recovering, dead, distant or obstructed targets remain invalid. The same downward stab works with a carried or stowed shield. The first shallow stab keeps the target alive; the deeper finishing push uses one production death/reward event and the existing ragdoll. Cancellation cannot leave a delayed lethal hit.

## 접근과 찌르기 / Approach and stab

몸통 기준 수평 거리 **1.10–1.65m**에서 시작한다. 시작 후 첫 0.30초 동안 충돌을 계산하며 몸통에서 약 **1.05m** 떨어진 위치로 접근하고, 시선도 낮은 몸통을 따라간다. 팔만 멀리 뻗어 어깨를 화면 중앙으로 끌어내는 것을 피하기 위한 실제 플레이어 이동이다. 순간 이동하거나 크리프를 플레이어 앞으로 끌어오지 않는다.

총 **2.50초** 동작은 아래 순서로 구성한다. 시간은 LMB를 놓아 처형이 시작된 순간부터 계산한다.

| 단계 / Phase | 현재 구현 / Current implementation |
|---|---|
| 찌를 자세 잡기 / Prepare | 0–0.48초에 몸통을 겨냥하고, 0.75초까지 준비 자세를 유지 / Aim during 0–0.48s, hold until 0.75s |
| 첫 찌르기 / Initial stab | 0.75–1.03초에 약 4.5cm 넣고 1.18초까지 잠시 유지 / Enter approximately 4.5cm during 0.75–1.03s, hold until 1.18s |
| 깊게 밀기 / Deeper push | 1.18–1.52초에 약 22cm까지 밀고, 1.52초에 한 번만 결정타 처리 / Push to approximately 22cm during 1.18–1.52s, commit one lethal hit at 1.52s |
| 검 뽑기 / Withdraw | 1.72–2.12초에 찌른 축을 따라 빼고 2.50초까지 준비 위치로 복귀 / Withdraw along the thrust axis during 1.72–2.12s, return to ready by 2.50s |

시작할 때 현재 자세의 실제 피부가 적용된 몸통 삼각형에서 접촉 지점을 한 번 구하며, 검과 몸통이 같은 월드 깊이를 사용해 들어간 칼끝은 피부에 가려진다. 첫 찌르기·깊은 밀기·회수는 같은 축을 사용한다. 손은 기존 검 파지 위치를 유지하며 실제 팔 길이는 상완 0.34m·전완 0.26m를 보존한다. 위 깊이는 모션의 목표 값이며, 실제 피부 가림·팔 자세와 기록된 침투 깊이는 아래 새 렌더 검수에서 확인했다.

Start at a horizontal torso distance of **1.10–1.65m**. During the first 0.30 seconds, the player advances through normal collision movement toward approximately **1.05m**, with the view following the low torso. This physical approach avoids pulling the shoulder cap into the center of the view; neither participant teleports. The **2.50-second** action now visibly prepares, enters shallowly, pushes deeper and withdraws as listed above. The anchor is sampled once from an actual posed torso-skin triangle. The initial thrust, deeper push and extraction share one axis; shared world depth lets the skin occlude the buried tip. The original sword grip and 0.34m upper arm / 0.26m forearm lengths are retained. Penetration distances are motion targets; renewed rendering below verified occlusion, arm pose and recorded depth.

## 테스트룸 / Test room

`F2 → 기본 → 크리프 처형 · 포복 찌르기`와 `크리프 처형 · 양다리 포복`은 새 크리프와 검·방패, 회복된 플레이어를 준비한다. 기존 부위 타격 코드로 18 피해를 다리마다 두 번 전달하고 실제로 쓰러져 회복할 때까지 기다린다. 양다리 시험만 네 번의 일반 피해에서 살아남도록 시험 체력 118을 사용한다. 마지막 준비 단계에서 **플레이어만** 몸통을 내려다보는 가까운 시험 위치로 옮기며 크리프의 착지 위치·골격을 순간 이동시키지 않는다.

준비 후 자동으로 처형하지 않는다. 직접 LMB를 길게 누르고 놓아야 한다. `1`번은 방패를 수납하고 같은 조건을 시험한다. `F2`는 준비 타이머, 물리와 실행 중 처형 자세·접촉 시간을 멈추고 재개한다. 항목을 다시 선택하면 온전한 몸에서 다시 시작한다. 다른 항목 선택·초기화·장면 종료는 예약 준비와 진행 중 처형을 취소한다. 원정 상태와 원래 인벤토리는 시험 종료 시 복원한다.

Both F2 entries prepare a fresh actual Creep, sword/shield and healed player. Ordinary localized hits sever the requested leg(s); the fixture waits for real physics and recovery. Only the both-leg fixture uses 118 HP to survive four ordinary hits. Reframing moves only the test player, never the landed enemy or its skeleton. Execution requires the user's charged release. F2 pauses and resumes setup, physics and the paired execution clock; replay/reset cancels stale ownership and restores fixtures. The original expedition and inventory remain isolated and are restored on exit.

## 검증 / Validation

### 현재 2.50초 개정 / Current 2.50-second revision

준비·첫 찌르기·깊은 밀기·회수와 1.52초 결정타를 반영했다. 새 `creep_execution`, `creep_execution_trial`, `sword_shield_execution` 자동 검사 **3종이 통과**했다. 실제 GPU `deep_stab_20260919_02`의 정지 화면에서 준비·첫 찌르기·깊은 밀기·회수를 정면과 측면에서 확인했으며 manifest 실패는 없다. 세 사례 모두 4.5cm의 첫 찌르기와 22cm의 깊은 찌르기를 기록하고, 오른쪽 어깨 이동 보정은 0m이며 기존 팔 길이를 유지했다. 실제 GPU `deep_stab_20260919_final03`의 전체 18초 영상(30fps·540프레임), 단계 이미지 27장(전체 PNG 66장), MP4 인코딩과 전체 디코딩도 통과했다. 세 사례에서 단일 사망과 어깨 보정 0m를 확인했고 manifest 실패는 없다. 초기 검수에서 깊은 찌르기에 필요했던 어깨 보정 7.3cm는 접근 목표를 1.15m에서 1.05m로 바꿔 해결했다. 평평한 시험 바닥의 현재 모델 검수이며 경사·계단·다른 적 크기는 미확인이다. GitHub 반영은 최종 게시 기록을 따른다. 새 산출물 경로는 `artifacts/validation/creep_execution_deep_stab_20260919/creep_execution_deep_stab.mp4`다. 아래 이전 버전 기록과 구분한다.

The preparation, shallow stab, deeper push, extraction and 1.52-second lethal contact are implemented. Three updated suites passed: `creep_execution`, `creep_execution_trial` and `sword_shield_execution`. Actual GPU `deep_stab_20260919_02` stills verified the stages from front and side with no manifest failures. All three cases recorded 4.5cm shallow and 22cm deep penetration, zero right-shoulder correction and preserved arm lengths. The full actual GPU `deep_stab_20260919_final03` sequence passed: 18 seconds, 540 frames at 30fps, 27 stage images (66 PNGs total), MP4 encoding and full decoding. All three cases recorded one defeat and zero shoulder correction, with no manifest failures. The initial 7.3cm shoulder correction during deep penetration was removed by changing approach distance from 1.15m to 1.05m. Checks cover current models on a flat floor; slopes, stairs and different enemy sizes remain unverified. GitHub status follows the final publication record. Its artifact path is `artifacts/validation/creep_execution_deep_stab_20260919/creep_execution_deep_stab.mp4`. These results are separate from the previous-version record below.

이번 개정 자동 검사: `./godot-game/tests/run_headless_tests.sh creep_execution creep_execution_trial sword_shield_execution`.

새 `creep_execution_trial_test.gd`는 등록, 실제 한쪽/양쪽 다리 절단과 착지·회복 대기, 높은 체력에서도 포복 대상 선택, 검·방패/방패 수납, 접촉 전 생존과 한 번의 사망·보상, F2 실행 중 정지·재개, 준비 취소·초기화, 원정 완전 복원을 검사한다. 핵심 플레이어·크리프 처형 검사는 담당 구현의 집중 검사와 함께 실행한다. 실제 렌더링은 별도로 확인해야 하며, 자동 검사 통과만으로 화면 검증을 완료했다고 간주하지 않는다.

The integration test covers registration, real single/both-leg cuts and grounded recovery, high-health crawler selection, carried/stowed shield, contact-timed single death/reward, F2 pause/resume, setup cancellation/reset and exact session restoration. Core execution checks run alongside it. Actual rendering remains a separate check.

### 이전 1.55초 버전 검수 이력 / Previous 1.55-second version validation

아래는 2026-09-18의 **0.82초 타격·10cm 찌르기·전체 1.55초** 동작에 대한 기록이다.

The following records cover the 2026-09-18 motion: **0.82-second impact, 10cm penetration, 1.55-second total duration**.

이전 실행 결과: `creep_execution`, `creep_execution_trial`, `creep_dismemberment_trial`, `enemy_execution`, `sword_shield_execution`, `first_person_renderer`, `test_room`의 **서로 다른 자동 검사 7종이 통과**했다. 실제 GPU `approach_03` 정지 화면에서 접근·접촉·회수와 1인칭 어깨 끝 노출 개선을 확인했다. 1.50m에서 약 0.35m 실제 접근한 접촉 자세에서 오른쪽 어깨 이동 보정은 기존 0.281m에서 0m로 줄고 상완·전완 길이는 유지됐다. 일반 테스트룸의 기존 ObjectDB 2개 종료 경고는 남아 있다. 최종 실제 GPU `final_04`의 **18초 시퀀스(30fps, JPG 540장)와 PNG 39장 검증도 완료**했다. 세 사례 모두 실제 피부 접촉을 기록하고 오른쪽 어깨 이동 보정이 0m이며 처치가 한 번씩 발생했다. 검수 manifest의 실패 목록은 비어 있다.

Previous results: **seven distinct suites passed**: `creep_execution`, `creep_execution_trial`, `creep_dismemberment_trial`, `enemy_execution`, `sword_shield_execution`, `first_person_renderer` and `test_room`. Actual GPU `approach_03` stills verified approach, contact, withdrawal and removal of the exposed first-person shoulder caps. At contact after approximately 0.35m of physical approach from 1.50m, right-shoulder correction fell from 0.281m to zero while upper/forearm lengths were retained. The general test room's existing two-ObjectDB shutdown warning remains. Final actual GPU `final_04` validation also passed: an **18-second sequence (540 JPG frames at 30fps) and 39 PNG stills**. All three cases recorded actual skin contact, zero right-shoulder correction and exactly one defeat. The validation manifest contains no failures.

이전 검수 범위는 평평한 시험 바닥과 당시 크리프·플레이어 팔·검 모델이다. 경사면·계단 및 크기가 다른 적에 대한 접근·접촉은 **미확인**이다. 검수 영상 산출물 경로는 `artifacts/validation/creep_execution_20260918/creep_execution.mp4`다. GPU 시퀀스 검증과 MP4 인코딩·파일 재생 검증은 구분하며, 파일 검증과 GitHub 반영 여부는 최종 검수 기록의 확인 결과를 따른다.

Previous verification covers the flat inspection floor and the then-current Creep, player arms and sword. Slopes, stairs and differently sized enemies remain **unverified**. The video artifact path is `artifacts/validation/creep_execution_20260918/creep_execution.mp4`. GPU sequence validation is separate from MP4 encoding and file playback validation; consult the final verification record for file checks and GitHub publication status.
