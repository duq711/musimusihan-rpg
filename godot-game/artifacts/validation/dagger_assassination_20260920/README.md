# 단검 후방 암살 검수 / Dagger rear assassination validation

2026-09-20 · macOS · Godot 4.7 `5b4e0cb0f`

## 결과 / Result

실제 단검을 장착하고 적 등 뒤에서 LMB 찌르기를 명중시키면 남은 체력과 관계없이 한 번에 처치한다. 정면·측면은 일반 피해다. 기존 검·방패와 포복 크리프 처형은 유지한다. 전용 단검 모델·찌르기·상인 판매·시험 보급·F2 시험을 포함한다.

Equip the actual dagger and land an LMB thrust from behind an enemy to kill it in one hit, regardless of remaining health. Front and side contacts deal ordinary damage. Existing sword/shield behavior and crawling-Creep executions remain available. Includes a dedicated dagger mesh/thrust, merchant stock, trial supplies and F2 fixtures.

- 사용 / Use: `F2 → 기본 → 단검 · 등 뒤 암살`. 정면 비교 항목, 재선택 회복·재생성 및 원정 복원도 구현했다. / Front control, replay/recovery and expedition restoration are also implemented.
- 판정 / Rules: 적 뒤쪽 ±55°, 수평 1.35m 이내, 실제 조준 방향 1.05m 신체 타격과 벽 가림 검사. 몸통뿐 아니라 후방 조건을 만족하는 다른 신체 부위도 적용한다. / Rear ±55°, horizontal distance ≤1.35m, a 1.05m aimed body contact and wall occlusion. Not torso-only.
- 감지 / Detection: 대기 적의 전방 160° 시야와 0.65m 근접 감지. 이미 시작한 추적은 유지한다. 별도 은신 수치·소음 시스템은 이번 범위에 포함하지 않는다. / Idle enemies use a 160° front cone and 0.65m proximity; alerted pursuit remains active. No separate stealth-stat or noise system was added.

## 실제 렌더링 / Actual rendering

[7초 시연 영상 / Seven-second demonstration](dagger_assassination.mp4): 앞 4초 후방 암살, 뒤 3초 정면 비교. Vulkan GPU 960×540, 초당 30장, 실제 물리 60Hz, 총 210장의 게임 렌더 프레임으로 인코딩했다. 생성 이미지나 사망 장면 합성을 사용하지 않았다.

The video contains four seconds of rear assassination followed by three seconds of frontal control: Vulkan GPU, 960×540, 30 fps, real 60 Hz physics, 210 rendered frames. No generated imagery or composited kill result.

| 시험 / Case | 실제 결과 / Actual result |
| --- | --- |
| 후방 / Rear | 체력 118→0, 타격 1회, 사망 1회, 실제 랙돌 낙하. / HP 118→0, one hit, one death, physical ragdoll fall. |
| 정면 / Front | 체력 118→92.44, 머리 부위 일반 피해 25.56, 생존·공격 유지. / HP 118→92.44, ordinary head-region damage 25.56, remains alive and attacking. |

![단검 준비 / Dagger ready](rear_assassination_ready.png)
![등 뒤 접촉 / Rear contact](rear_assassination_contact.png)
![실제 랙돌 / Physical ragdoll](rear_assassination_ragdoll.png)
![정면 생존 / Frontal survival](front_control_survives.png)

촬영은 실제 `DungeonPlayer`·살아 있는 크리프 AI·충돌·사망 코드를 사용하는 격리 시험 장면이다. 후방 접촉 시 칼끝은 접촉면보다 약 21cm 들어가고 조준 축에서 약 3cm 떨어져 있다. 칼이 피부 뒤로 가려지는 실제 깊이 렌더링을 사용한다. 정면 비교는 접근하는 적에게 먼저 찌르며 카메라가 움직이는 가슴을 추적한다. 후방 사망 후에는 카메라를 아래로 내려 시체를 확인한다. 이 촬영용 카메라 입력을 게임의 자동 조준으로 추가하지 않았다. 화면 글씨는 검수 자막이다.

This isolated fixture uses the actual player, live Creep AI, collisions and death path. At rear contact, the blade tip is about 21cm beyond the contacted surface with about 3cm lateral offset, occluded by real world depth. The front control stabs earlier while its inspection camera tracks the approaching animated chest. The rear camera looks down after death to inspect the corpse. These capture-only camera inputs are not gameplay aim assistance; on-screen labels are validation subtitles.

물리 좌표를 반영하기 전에 적을 생성하면 정면 시험에서 캡슐 충돌 복구로 적이 튀어 오르는 촬영 초기화 결함이 있었다. 플레이어 배치 후 물리 프레임을 반영하고 캡슐이 겹치지 않는 1.05m에서 생성하도록 고쳤다. 실패한 중간 촬영은 이 결과 영상에 포함하지 않았다.

A fixture initialization issue spawned the frontal enemy before the player's relocated physics transform had synchronized, causing capsule recovery to pop it upward. The final fixture flushes physics frames first and starts at a non-overlapping 1.05m separation. Failed intermediate captures are excluded from this result.

## 검사와 범위 / Checks and scope

- 통과 / Passed: `dagger_assassination`, `dagger_assassination_trial`, `test_room`, `test_room_session`, `supplied_fp_arms`, `smithing_system`, `creep_enemy`, `creep_execution`.
- 핵심·F2 최종 사거리 1.05m 검사: 구입·장착, 자세 연속성, 실제 후방 명중·사망·보상 1회, 정면·측면 일반 피해, 장비 변경·취소, 거리·벽·빗나감, 타격 직전 방향 변경, 찌르기 1회당 대상 1명, F2 정지·재시험·원정 복원. / Final 1.05m core/trial checks cover purchase/equip, pose continuity, actual kill/reward once, normal front/side damage, equipment cancellation, range/walls/misses, turning before impact, one target per thrust, F2 pause/replay/session restoration.
- 게시 범위만 옮긴 격리 사본에서도 `dagger_assassination_trial`·`test_room` 2종을 다시 통과했다. / The isolated publication-scope copy also passed both trial and catalog suites: [publication_check.log](publication_check.log).
- **기존 실패 / Existing failures:** `sword_clash`의 4개 검격 접촉 검사와 `sword_shield_choreography`의 기존 손 에셋/타이밍 기대값 실패는 작업 시작 전 코드의 격리 사본에서도 재현했다. 이번 단검 수정으로 고쳤다고 주장하지 않는다. / Four sword-clash contact checks and existing choreography hand-asset/timing expectations also fail in the isolated pre-task baseline. They remain unresolved and are not reported as fixed.
- **미확인 / Not verified:** OS 하드웨어 마우스 입력과 화면 포커스. 공격·놓기 처리는 실제 게임 함수를 호출해 검증했으며 포인터를 캡처하지 않았다. 원정·가방·커서 복원과 렌더 중 소스 불변은 확인했다. / OS hardware input and focus were not exercised. Real gameplay attack/release methods were invoked without pointer capture. Expedition/inventory/cursor preservation and unchanged render sources were verified.
- 시연은 격리된 실제 게임 3D 장면이며 동굴 전체 플레이 녹화가 아니다. 정면 근접 시 팔이 적에 깊게 들어갈 수 있고, 전용 짝맞춤 암살 애니메이션이나 새로운 사운드는 추가하지 않았다. / This is an isolated real-game 3D fixture, not a full dungeon playthrough. At very close frontal range the arm can enter the enemy deeply; no paired assassination animation or new sound was added.

상세 데이터 / Detailed data: [summary.json](summary.json), [capture_manifest.json](capture_manifest.json), [핵심 / Core](core.log), [F2](trial.log), [기존 처형 / Existing execution](execution_regression.log), [검격 기준본 / Baseline clash](baseline_clash.log), [동작 기준본 / Baseline choreography](baseline_choreography.log). 원시 210장은 로컬 `artifacts/visual_qa/dagger_assassination/verified_20260920/frames`에 보존하고 재생 가능한 MP4와 주요 PNG를 공유한다. / Raw frames remain local; the playable MP4 and selected PNGs are published.
