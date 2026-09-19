# 포복 크리프 처형 / Crawling Creep execution

2026-09-18 사용자 요청: 다리가 절단되어 기어다니는 크리프를 검으로 찔러 처형하는 동작 한 가지를 우선 제작한다. 기존 서 있는 적의 검·방패 처형과 구분한다.

User request, 2026-09-18: first implement one sword-stab execution for a living Creep crawling after leg loss, separate from the existing standing sword-and-shield execution.

2026-09-19 후속 요청: **찌를 자세 잡기 → 첫 찌르기 → 더 깊게 밀어 넣기 → 검 뽑기**가 구분되는 동작으로 다듬는다. 이후 요청으로 찌르기 전 멈춤을 없앴다. 후속 요청에 따라 첫 찌르기는 조용히 받아들이고, 깊게 밀어 넣을 때 크게 움찔한 뒤 잠시 기다렸다가 칼을 뽑도록 했다. 그다음 깊이를 늘렸으며, 최신 요청은 실제 칼날의 절반 정도가 몸 안에 묻히도록 하는 것이다. 현재 구현 값과 검증 상태는 아래를 따른다.

Follow-up request, 2026-09-19: distinguish **preparing the stab → first thrust → deeper push → withdrawal**. A subsequent request removed the pause before the thrust. A follow-up kept the first stab quiet, added a pronounced flinch on the deeper push and held briefly before withdrawal. Depth was then increased; the latest request is to bury approximately half of the actual blade inside the body. Current implementation values and validation status are recorded below.

## 조작과 조건 / Input and eligibility

- 검을 든 상태에서 가까운 포복 크리프의 몸통을 바라보고 **LMB를 0.4초 이상 누른 뒤 놓는다**. 짧게 누르면 기존 일반 공격이다.
- 실제 다리 절단 후 랙돌 착지·안정과 포복 회복을 마친 살아 있는 크리프가 대상이다. 포복 크리프는 낮은 체력이나 저스트 가드 경직을 별도로 요구하지 않는다. 떨어지거나 자세를 회복 중일 때, 죽은 상태, 거리·시야·장애물 조건을 벗어나면 시작하지 않는다.
- 검과 방패를 함께 들거나 `1`번으로 방패를 수납한 상태 모두 같은 아래 방향 찌르기를 사용한다. 다른 적과 무기, 기존 일반 공격·서 있는 적 처형 조건은 유지한다.
- 첫 얕은 찌르기에서는 대상을 유지하고, 더 깊이 밀어 넣는 결정타 시점에 한 번만 실제 치명타와 기존 처치 보상을 처리한다. 시체는 기존 랙돌로 이어진다. 동작 중 피해·장비 변경·대상 소멸·새 장애물 등으로 취소되면 예약 치명타가 나중에 발생하지 않는다.

With a sword drawn, aim at a nearby crawling Creep's torso, hold LMB for at least 0.4 seconds and release. Short clicks remain ordinary attacks. A living leg-severed Creep must finish its physical landing and prone recovery; no additional low-health or stagger requirement applies. Falling/recovering, dead, distant or obstructed targets remain invalid. The same downward stab works with a carried or stowed shield. The first shallow stab keeps the target alive; the deeper finishing push uses one production death/reward event and the existing ragdoll. Cancellation cannot leave a delayed lethal hit.

## 접근과 찌르기 / Approach and stab

몸통 기준 수평 거리 **1.10–1.65m**에서 시작한다. 시작 후 첫 0.30초 동안 충돌을 계산하며 몸통에서 약 **0.84m** 떨어진 위치로 접근하고, 시선도 낮은 몸통을 따라간다. 팔만 멀리 뻗어 어깨를 화면 중앙으로 끌어내는 것을 피하기 위한 실제 플레이어 이동이다. 순간 이동하거나 크리프를 플레이어 앞으로 끌어오지 않는다.

총 **2.24초** 동작은 아래 순서로 구성한다. 시간은 LMB를 놓아 처형이 시작된 순간부터 계산한다.

| 단계 / Phase | 현재 구현 / Current implementation |
|---|---|
| 찌를 자세 잡기 / Prepare | 0–0.30초에 접근하며 몸통을 겨냥하고 멈춤 없이 첫 찌르기로 연결 / Approach and aim during 0–0.30s, continuing into the thrust without a hold |
| 첫 찌르기 / Initial stab | 0.30–0.58초에 약 4.5cm 넣고 0.68초까지 유지 / Enter approximately 4.5cm during 0.30–0.58s, hold until 0.68s |
| 깊게 밀기 / Deeper push | 0.68–1.02초에 실측 칼날의 55%(현재 약 57.5cm)까지 밀고, 1.02초에 한 번만 결정타 처리 / Push to 55% of measured blade length (currently about 57.5cm) during 0.68–1.02s; commit one lethal hit at 1.02s |
| 결정타 후 유지 / Hold after finishing contact | 1.02–1.46초에 깊은 찌르기 위치를 0.44초 유지 / Hold the deeper stab position for 0.44s during 1.02–1.46s |
| 검 뽑기 / Withdraw | 1.46–1.86초에 찌른 축을 따라 빼고 2.24초까지 준비 위치로 복귀 / Withdraw along the thrust axis during 1.46–1.86s, return to ready by 2.24s |

시작할 때 현재 자세의 실제 피부가 적용된 몸통 삼각형에서 접촉 지점을 한 번 구하며, 검과 몸통이 같은 월드 깊이를 사용해 들어간 칼끝은 피부에 가려진다. 첫 찌르기·깊은 밀기·회수는 같은 축을 사용한다. 손은 기존 검 파지 위치를 유지하며 실제 팔 길이는 상완 0.34m·전완 0.26m를 보존한다. 위 깊이는 모션의 목표 값이며 실제 피부 가림·팔 자세·침투 깊이는 개정별 검수 기록으로 구분한다.

Start at a horizontal torso distance of **1.10–1.65m**. During the first 0.30 seconds, the player advances through normal collision movement toward approximately **0.84m**, with the view following the low torso. This physical approach avoids pulling the shoulder cap into the center of the view; neither participant teleports. The **2.24-second** action prepares and immediately continues into the shallow stab, pushes deeper, holds briefly and withdraws as listed above. The anchor is sampled once from an actual posed torso-skin triangle. The initial thrust, deeper push and extraction share one axis; shared world depth lets the skin occlude the buried tip. The original sword grip and 0.34m upper arm / 0.26m forearm lengths are retained. Penetration distances are motion targets; verification of occlusion, arm pose and recorded depth is tracked separately for each revision.

깊은 찌르기는 고정 cm값 대신 원본 검의 실제 칼날 길이의 **55%**를 사용한다. 현재 칼날은 약 **1.045m**이므로 목표 관입은 **0.57475m**다. 기존 36cm는 칼날의 약 34.45%였다. 캡슐 충돌을 보존하며 접근하고, 깊게 밀 때 상체를 앞으로 숙여 팔 길이를 억지로 늘이지 않는다. 접근 속도는 기존 2.8m/s를 유지한다.

Deep penetration now uses **55% of actual source blade length** rather than a fixed centimeter value. The current blade measures approximately **1.045m**, giving a **0.57475m** target. The previous 36cm buried only about 34.45%. Approach retains capsule collisions and adds a forward upper-body lean during the deep push to preserve arm length. Approach speed remains 2.8m/s.

## 찔림 반응 / Contact reaction

첫 얕은 찌르기에는 움찔 반응을 주지 않는다. 깊게 밀어 넣는 도중인 0.88초부터 가슴·머리 반응이 시작되어 1.02초 결정타에서 최대가 된다. 제작값은 가슴 14°·머리 20°이며, 이를 적용한 마지막 자세를 사망 랙돌로 넘긴다. 반응은 찌른 접촉점을 중심으로 상체에 적용하며 루트·골반·다리는 유지한다. 검은 결정타 뒤 0.44초 동안 깊은 위치에 머문 다음 찌른 축을 따라 빠진다. 첫 찌르기는 비치명 단계이고 사망·보상은 깊은 결정타에서 한 번만 발생한다. 처형 전 LMB 0.4초 입력 조건과 준비 후 멈추지 않고 찌르는 연결은 유지한다.

The first shallow stab has no flinch. Recoil starts at 0.88s during the deeper push and peaks at the 1.02s finishing contact. Production angles are 14° for the chest and 20° for the head; that final reaction pose transfers into death ragdoll. Upper-body recoil pivots around the stab contact while the root, pelvis and legs remain fixed. The blade holds at the deeper position for 0.44s after finishing contact, then withdraws along the thrust axis. The first stab stays nonlethal, with one death/reward event on the deeper strike. The 0.4-second LMB requirement and continuous preparation-to-thrust transition remain.

## 테스트룸 / Test room

`F2 → 기본 → 크리프 처형 · 포복 찌르기`와 `크리프 처형 · 양다리 포복`은 새 크리프와 검·방패, 회복된 플레이어를 준비한다. 기존 부위 타격 코드로 18 피해를 다리마다 두 번 전달하고 실제로 쓰러져 회복할 때까지 기다린다. 양다리 시험만 네 번의 일반 피해에서 살아남도록 시험 체력 118을 사용한다. 마지막 준비 단계에서 **플레이어만** 몸통을 내려다보는 가까운 시험 위치로 옮기며 크리프의 착지 위치·골격을 순간 이동시키지 않는다.

준비 후 자동으로 처형하지 않는다. 직접 LMB를 길게 누르고 놓아야 한다. `1`번은 방패를 수납하고 같은 조건을 시험한다. `F2`는 준비 타이머, 물리와 실행 중 처형 자세·접촉 시간을 멈추고 재개한다. 항목을 다시 선택하면 온전한 몸에서 다시 시작한다. 다른 항목 선택·초기화·장면 종료는 예약 준비와 진행 중 처형을 취소한다. 원정 상태와 원래 인벤토리는 시험 종료 시 복원한다.

Both F2 entries prepare a fresh actual Creep, sword/shield and healed player. Ordinary localized hits sever the requested leg(s); the fixture waits for real physics and recovery. Only the both-leg fixture uses 118 HP to survive four ordinary hits. Reframing moves only the test player, never the landed enemy or its skeleton. Execution requires the user's charged release. F2 pauses and resumes setup, physics and the paired execution clock; replay/reset cancels stale ownership and restores fixtures. The original expedition and inventory remain isolated and are restored on exit.

## 검증 / Validation

### 현재 칼날 55% 깊이 개정 / Current 55%-of-blade penetration

최종 구현은 칼날 약 1.045m의 55%인 **0.57475m**, 접근 목표 **0.84m**, 기존 접근 속도 2.8m/s다. 깊게 밀 때 상체를 숙이며 기존 팔 길이를 유지한다. 첫 찌르기 4.5cm, 가슴 14°·머리 20° 반응, 결정타 뒤 0.44초 유지와 전체 2.24초는 보존한다. 최종 코드의 `creep_execution`, `creep_execution_trial` **2종을 통과**했고, 같은 작업에서 기존 `sword_shield_execution` 회귀 검사도 통과했다.

최종 실제 GPU `half_blade_20260919_03`은 **18초·30fps·540프레임·단계 PNG 39장**으로 기록했고 manifest 실패가 없다. 세 사례의 깊은 결정타 모두 칼날 55% 관입을 확인했고, 첫 찌르기·최대 깊이·유지 후반·회수 끝 표본 모두 어깨 이동 보정은 0m다. 한쪽·양쪽 다리 1인칭과 측면 결정타·유지 후반을 직접 검토했다. 실제 변형된 피부 기준의 결정타 기하 검사는 약 **55.46–55.56%가 몸 안에 있으며**, 칼끝에서 반대편 피부까지 **10.1–11.8cm**가 남는 것을 확인했다. 이 피부 수치는 결정타 자세의 세 헤드리스 사례에 한정한다. 원본 파일 16개의 해시 보존을 확인했다.

첫 두 렌더 후보에서는 더 가까운 접근을 시도해도 실제 캡슐 충돌이 전진을 막아 어깨 보정 약 9.65cm가 발생했다. 최종본은 접근 목표를 도달 가능한 0.84m로 조정하고 깊은 밀기의 상체 숙임을 늘렸으며, 접근 속도를 원래 값으로 유지했다. 이 실패 후보는 최종 통과 자료와 구분한다. 영상은 `artifacts/validation/creep_execution_half_blade_20260919/creep_execution_half_blade.mp4`에 보존한다. MP4 인코딩·전체 540프레임 디코딩을 통과했으며 960×540·30fps·18초의 무음 영상임을 확인했다. GitHub 반영은 최종 게시 기록을 따른다. 경사·계단·다른 적 크기는 미확인이다.

The final implementation uses **0.57475m**, or 55% of the approximately 1.045m blade, with a **0.84m** approach target and the original 2.8m/s approach speed. Added forward upper-body lean preserves arm length during the deep push. The 4.5cm first stab, 14° chest/20° head reaction, 0.44-second hold and 2.24-second duration remain. **Two suites passed on the final code:** `creep_execution` and `creep_execution_trial`; the existing `sword_shield_execution` regression suite also passed during this task.

Final actual GPU `half_blade_20260919_03` records **18 seconds, 540 frames at 30fps and 39 stage PNGs**, with no manifest failures. All three finishing-contact cases confirm 55% penetration; initial-stab, maximum-depth, late-hold and withdrawal-end samples all show zero shoulder translation correction. Single/both-leg first-person and side impact/late-hold views were directly inspected. Finishing-contact geometry against actual deformed skin shows approximately **55.46–55.56% inside the body**, leaving **10.1–11.8cm** between the tip and far-side skin. Those skin measurements cover the three headless cases at finishing contact only. Sixteen source-file hashes are preserved.

The first two render candidates produced approximately 9.65cm of shoulder correction: actual capsule contact stopped the closer approach even when its speed increased. The final revision uses a reachable 0.84m target, more upper-body lean on the deeper push and the original speed. Those failed candidates remain separate from final passing evidence. The video is retained at `artifacts/validation/creep_execution_half_blade_20260919/creep_execution_half_blade.mp4`. MP4 encoding and full 540-frame decoding passed, confirming a silent 960×540, 30fps, 18-second file. GitHub status follows the final publication record. Slopes, stairs and differently sized enemies remain unverified.

### 이전 36cm 깊은 찌르기 검수 / Previous 36cm deeper penetration validation

깊은 찌르기를 **22cm에서 36cm로 14cm 늘렸다**. 팔 길이를 유지하도록 실제 접근 목표를 1.05m에서 **0.88m**로 17cm 가까이 옮겼다. 첫 찌르기 4.5cm, 큰 반응의 가슴 14°·머리 20°, 결정타 뒤 0.44초 유지와 전체 2.24초는 그대로다. `creep_execution`, `creep_execution_trial` 자동 검사 **2종을 통과**했다. 실제 변형된 몸통 피부의 교차 검사에서 세 절단 사례 모두 깊은 결정타 시점의 칼끝이 반대편 피부보다 31.6–33.3cm 앞에 남았다. 이 수치는 결정타 자세의 기하 검사이며 이후 랙돌 전체 구간에 대한 수치는 아니다.

실제 GPU `deeper_20260919_01`은 manifest 실패 없이 **960×540·30fps·18초·540프레임의 무음 영상과 단계 PNG 39장**을 기록했다. 세 사례 모두 깊이 36cm, 어깨 이동 보정 0m, 기존 상완 0.34m·전완 0.26m를 유지했다. 한쪽·양쪽 다리 1인칭 결정타와 측면 결정타·유지 후반 화면에서 노출된 칼날이 줄었고 반대편으로 칼끝이 드러나지 않는 것을 직접 확인했다. MP4 인코딩·전체 540프레임 디코딩을 통과했고 원본 파일 14개의 해시도 보존했다. 영상은 `artifacts/validation/creep_execution_deeper_20260919/creep_execution_deeper.mp4`에 있다. 아래 이전 22cm 결과와 구분하며 GitHub 반영은 최종 게시 기록을 따른다. 경사·계단·다른 적 크기는 미확인이다.

Deep penetration increased **14cm, from 22cm to 36cm**. Actual approach moves 17cm closer, from 1.05m to **0.88m**, preserving arm lengths. The 4.5cm initial stab, 14° chest/20° head reaction, 0.44-second post-impact hold and 2.24-second total remain. **Two suites passed:** `creep_execution` and `creep_execution_trial`. Ray intersections against the actual deformed torso skin show the tip remains 31.6–33.3cm before the far skin exit in all three severance cases at finishing contact. This geometric result covers that contact pose, not the entire subsequent ragdoll sequence.

Actual GPU `deeper_20260919_01` has no manifest failures and records a **silent 960×540, 30fps, 18-second, 540-frame video and 39 stage PNGs**. All three cases retain 36cm penetration, zero shoulder translation correction and the original 0.34m upper arm / 0.26m forearm. Direct inspection of single/both-leg first-person impact and side impact/late-hold views shows less exposed blade and no visible tip protruding through the far side. MP4 encoding and full 540-frame decoding passed; fourteen source-file hashes are preserved. The video is at `artifacts/validation/creep_execution_deeper_20260919/creep_execution_deeper.mp4`. These results remain separate from the previous 22cm validation below; GitHub status follows the final publication record. Slopes, stairs and differently sized enemies remain unverified.

### 이전 22cm 깊은 찌르기 반응·회수 대기 검수 / Previous 22cm deeper-push recoil and delayed withdrawal validation

이번 2.24초 개정의 자동 검사 `creep_execution`, `creep_execution_trial` **2종이 통과**했다. 실제 GPU `deep_recoil_20260919_01`에서 **960×540·30fps·18초·540프레임의 무음 영상과 단계 PNG 39장**을 촬영했으며 manifest 실패는 없다. 1인칭·별도 측면 반복에서 조용한 첫 찌르기, 깊게 밀 때 큰 반응, 0.44초 유지와 회수를 직접 검토했다. 세 사례 모두 첫 찌르기 반응 강도는 0이고 해당 골격 자세는 같으며, 깊은 반응 강도는 1이고 개별 뼈 로컬 회전은 가슴 14°·머리 20°다. 이 값은 머리의 누적 세계 회전과 구분한다. 사망은 각각 한 번이고 원래 접촉점 기준 유지 깊이는 22cm다.

유지 후반에는 사망 랙돌로 몸이 조금 내려가지만 측면에서 검과 몸의 접촉이 읽히는 것을 확인해 기존 랙돌 코드는 유지했다. MP4 인코딩·전체 540프레임 디코딩과 원본 파일 14개의 해시 보존을 확인했다. 영상 경로는 `artifacts/validation/creep_execution_deep_recoil_20260919/creep_execution_deep_recoil.mp4`다. 이전 1.96초의 4종 검사·첫 접촉 반응 검수와 구분한다. GitHub 반영은 최종 게시 기록을 따르며, 경사·계단·다른 적 크기는 미확인이다.

**Two suites passed** for this 2.24-second revision: `creep_execution` and `creep_execution_trial`. Actual GPU `deep_recoil_20260919_01` produced a **silent 960×540, 30fps, 18-second, 540-frame video and 39 stage PNGs** with no manifest failures. First-person and separate side-view inspection confirmed a quiet first stab, pronounced deep-push recoil, the 0.44-second hold and extraction. All three cases have zero initial recoil and unchanged initial skeletal pose, followed by deep recoil weight 1 with individual local-bone rotations of 14° chest and 20° head. These are not cumulative head world-rotation values. Each case records one defeat and 22cm hold depth relative to the original contact anchor.

The corpse settles slightly under ragdoll during the later hold, but blade/body contact remains readable from the side, so existing ragdoll code is retained. MP4 encoding, full 540-frame decoding and preservation of fourteen source-file hashes passed. The video is at `artifacts/validation/creep_execution_deep_recoil_20260919/creep_execution_deep_recoil.mp4`. These results remain separate from the previous 1.96-second revision's four suites and initial-contact recoil checks. GitHub status follows the final publication record; slopes, stairs and differently sized enemies remain unverified.

### 이전 1.96초 멈춤 제거·찔림 반응 검수 이력 / Previous 1.96-second no-hold and contact-recoil validation

자동 검사 **4종**(`creep_execution`, `creep_execution_trial`, `sword_shield_execution`, `enemy_execution`)을 통과했다. 테스트룸 검사는 설명의 `랙돌` 표기를 복구한 뒤 재실행해 통과했다. 핵심 검사는 첫 피부 접촉의 비치명 반응·깊은 결정타의 단일 사망, 골반·다리 9개 뼈 고정, 중도 취소 후 포복 복귀, 사망 랙돌의 최종 반응 자세 상속을 확인했다.

실제 GPU `recoil_20260919_01` 정지 화면과 `recoil_20260919_final02` 전체 시퀀스 모두 manifest 실패가 없다. 한쪽 다리 1인칭·동일 절단 조건의 별도 측면 반복·양다리 1인칭 세 사례에서 사망은 각각 한 번이며 실제 가슴·머리 뼈의 세계 회전 변화가 2°를 넘고 루트 위치는 유지된다. 첫 반응 강도는 약 0.9864, 깊은 결정타 반응은 1.0이고 얕은/깊은 목표 침투 깊이는 4.5/22cm다. **960×540·30fps·18초·540프레임의 무음 영상과 단계 PNG 33장**, MP4 인코딩·전체 540프레임 디코딩을 확인했다. 원본 파일 14개의 해시는 변경 전과 같다. 영상은 `artifacts/validation/creep_execution_recoil_20260919/creep_execution_recoil.mp4`에 보존한다. 경사·계단·다른 적 크기는 미확인이고, GitHub 원격 확인은 최종 게시 기록을 따른다.

**Four automated suites passed:** `creep_execution`, `creep_execution_trial`, `sword_shield_execution` and `enemy_execution`. The trial suite passed after restoring the required ragdoll wording in its menu descriptions. Core checks cover nonlethal recoil on first skin contact, one lethal deeper strike, nine fixed pelvis/leg bones, crawl restoration after cancellation and transfer of the final reaction pose into death ragdoll.

Actual GPU stills from `recoil_20260919_01` and the full `recoil_20260919_final02` sequence have no manifest failures. Single-leg first person, a separate side-view repeat with the same severance condition and both-leg first person each record one defeat, more than 2° of actual Chest/Head world-bone rotation and an unchanged actor root. Initial recoil weight is approximately 0.9864 and lethal recoil weight is 1.0; shallow/deep target penetration remains 4.5/22cm. The **silent 960×540, 30fps, 18-second, 540-frame video and 33 stage PNGs**, MP4 encoding and full 540-frame decoding passed. Fourteen source-file hashes match the baseline. The video is retained at `artifacts/validation/creep_execution_recoil_20260919/creep_execution_recoil.mp4`. Slopes, stairs and differently sized enemies remain unverified; remote GitHub confirmation follows the final publication record.

### 이전 2.50초 개정 검수 이력 / Previous 2.50-second revision validation

준비·첫 찌르기·깊은 밀기·회수와 1.52초 결정타를 반영했다. 새 `creep_execution`, `creep_execution_trial`, `sword_shield_execution` 자동 검사 **3종이 통과**했다. 실제 GPU `deep_stab_20260919_02`의 정지 화면에서 준비·첫 찌르기·깊은 밀기·회수를 정면과 측면에서 확인했으며 manifest 실패는 없다. 세 사례 모두 4.5cm의 첫 찌르기와 22cm의 깊은 찌르기를 기록하고, 오른쪽 어깨 이동 보정은 0m이며 기존 팔 길이를 유지했다. 실제 GPU `deep_stab_20260919_final03`의 전체 18초 영상(30fps·540프레임), 단계 이미지 27장(전체 PNG 66장), MP4 인코딩과 전체 디코딩도 통과했다. 세 사례에서 단일 사망과 어깨 보정 0m를 확인했고 manifest 실패는 없다. 초기 검수에서 깊은 찌르기에 필요했던 어깨 보정 7.3cm는 접근 목표를 1.15m에서 1.05m로 바꿔 해결했다. 평평한 시험 바닥의 현재 모델 검수이며 경사·계단·다른 적 크기는 미확인이다. GitHub 반영은 최종 게시 기록을 따른다. 새 산출물 경로는 `artifacts/validation/creep_execution_deep_stab_20260919/creep_execution_deep_stab.mp4`다. 아래 이전 버전 기록과 구분한다.

The preparation, shallow stab, deeper push, extraction and 1.52-second lethal contact are implemented. Three updated suites passed: `creep_execution`, `creep_execution_trial` and `sword_shield_execution`. Actual GPU `deep_stab_20260919_02` stills verified the stages from front and side with no manifest failures. All three cases recorded 4.5cm shallow and 22cm deep penetration, zero right-shoulder correction and preserved arm lengths. The full actual GPU `deep_stab_20260919_final03` sequence passed: 18 seconds, 540 frames at 30fps, 27 stage images (66 PNGs total), MP4 encoding and full decoding. All three cases recorded one defeat and zero shoulder correction, with no manifest failures. The initial 7.3cm shoulder correction during deep penetration was removed by changing approach distance from 1.15m to 1.05m. Checks cover current models on a flat floor; slopes, stairs and different enemy sizes remain unverified. GitHub status follows the final publication record. Its artifact path is `artifacts/validation/creep_execution_deep_stab_20260919/creep_execution_deep_stab.mp4`. These results are separate from the previous-version record below.

이전 2.50초 개정 자동 검사: `./godot-game/tests/run_headless_tests.sh creep_execution creep_execution_trial sword_shield_execution`.

새 `creep_execution_trial_test.gd`는 등록, 실제 한쪽/양쪽 다리 절단과 착지·회복 대기, 높은 체력에서도 포복 대상 선택, 검·방패/방패 수납, 접촉 전 생존과 한 번의 사망·보상, F2 실행 중 정지·재개, 준비 취소·초기화, 원정 완전 복원을 검사한다. 핵심 플레이어·크리프 처형 검사는 담당 구현의 집중 검사와 함께 실행한다. 실제 렌더링은 별도로 확인해야 하며, 자동 검사 통과만으로 화면 검증을 완료했다고 간주하지 않는다.

The integration test covers registration, real single/both-leg cuts and grounded recovery, high-health crawler selection, carried/stowed shield, contact-timed single death/reward, F2 pause/resume, setup cancellation/reset and exact session restoration. Core execution checks run alongside it. Actual rendering remains a separate check.

### 이전 1.55초 버전 검수 이력 / Previous 1.55-second version validation

아래는 2026-09-18의 **0.82초 타격·10cm 찌르기·전체 1.55초** 동작에 대한 기록이다.

The following records cover the 2026-09-18 motion: **0.82-second impact, 10cm penetration, 1.55-second total duration**.

이전 실행 결과: `creep_execution`, `creep_execution_trial`, `creep_dismemberment_trial`, `enemy_execution`, `sword_shield_execution`, `first_person_renderer`, `test_room`의 **서로 다른 자동 검사 7종이 통과**했다. 실제 GPU `approach_03` 정지 화면에서 접근·접촉·회수와 1인칭 어깨 끝 노출 개선을 확인했다. 1.50m에서 약 0.35m 실제 접근한 접촉 자세에서 오른쪽 어깨 이동 보정은 기존 0.281m에서 0m로 줄고 상완·전완 길이는 유지됐다. 일반 테스트룸의 기존 ObjectDB 2개 종료 경고는 남아 있다. 최종 실제 GPU `final_04`의 **18초 시퀀스(30fps, JPG 540장)와 PNG 39장 검증도 완료**했다. 세 사례 모두 실제 피부 접촉을 기록하고 오른쪽 어깨 이동 보정이 0m이며 처치가 한 번씩 발생했다. 검수 manifest의 실패 목록은 비어 있다.

Previous results: **seven distinct suites passed**: `creep_execution`, `creep_execution_trial`, `creep_dismemberment_trial`, `enemy_execution`, `sword_shield_execution`, `first_person_renderer` and `test_room`. Actual GPU `approach_03` stills verified approach, contact, withdrawal and removal of the exposed first-person shoulder caps. At contact after approximately 0.35m of physical approach from 1.50m, right-shoulder correction fell from 0.281m to zero while upper/forearm lengths were retained. The general test room's existing two-ObjectDB shutdown warning remains. Final actual GPU `final_04` validation also passed: an **18-second sequence (540 JPG frames at 30fps) and 39 PNG stills**. All three cases recorded actual skin contact, zero right-shoulder correction and exactly one defeat. The validation manifest contains no failures.

이전 검수 범위는 평평한 시험 바닥과 당시 크리프·플레이어 팔·검 모델이다. 경사면·계단 및 크기가 다른 적에 대한 접근·접촉은 **미확인**이다. 검수 영상 산출물 경로는 `artifacts/validation/creep_execution_20260918/creep_execution.mp4`다. GPU 시퀀스 검증과 MP4 인코딩·파일 재생 검증은 구분하며, 파일 검증과 GitHub 반영 여부는 최종 검수 기록의 확인 결과를 따른다.

Previous verification covers the flat inspection floor and the then-current Creep, player arms and sword. Slopes, stairs and differently sized enemies remain **unverified**. The video artifact path is `artifacts/validation/creep_execution_20260918/creep_execution.mp4`. GPU sequence validation is separate from MP4 encoding and file playback validation; consult the final verification record for file checks and GitHub publication status.
