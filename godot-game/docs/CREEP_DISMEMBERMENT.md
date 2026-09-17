# 크리프 부위 절단 / Creep dismemberment

사용자 결정: 같은 팔·다리·머리를 집중 공격하면 절단한다. **팔다리 절단 후에도 살아서 전투를 계속한다.** 머리 절단은 즉시 사망이다. 기존 체력 소진으로 사망하는 규칙은 그대로 적용한다.

User decision: concentrated attacks can sever an arm, leg or head. **Limb loss does not automatically kill the creature**; it continues fighting until ordinary health depletion. Decapitation kills immediately.

2026-09-18 후속 사용자 결정: **다리를 하나라도 잃으면 살아 있는 상태로 랙돌 물리에 따라 쓰러진다. 몸이 바닥에 닿아 안정된 뒤 포복 자세로 전환하고 플레이어를 추적한다.** 고정 시간만 기다려 공중에서 기어가는 자세를 시작하지 않는다. / Follow-up user decision on 2026-09-18: **losing either leg causes a living physical ragdoll fall. After the body has landed and stabilized, it transitions to a prone crawl and pursues the player.** A fixed timer alone must not begin crawling while airborne.

## 현재 규칙 / Current tuning

- 왼팔·오른팔·왼다리·오른다리·머리를 따로 누적한다. 같은 부위에 양의 피해 **2회 이상 + 누적 35**가 필요하다. 수치는 이번 구현의 조정 가능한 초기값이다.
- 부위 피해는 시간이나 다른 부위 타격으로 초기화되지 않는다. 서로 다른 부위의 피해는 합산하지 않는다. 몸통 타격은 체력만 줄인다.
- 잃은 팔의 펀치는 피해를 주지 않는다. 원본 클립의 첫 접촉은 오른팔, 두 번째는 왼팔이다. 양팔을 잃으면 물기만 선택한다.
- 다리를 하나라도 잃으면 `falling` 상태에서 실제 랙돌로 쓰러진다. 몸통과 머리가 지면 가까이 가라앉고 움직임이 안정된 뒤 `recovering` 상태로 넘어가며, 그때의 자세에서 포복 자세로 이어진다. 전환이 끝날 때까지 추적과 공격을 하지 않는다. 이후 지지하는 손을 번갈아 앞으로 뻗고 몸을 당기며 추적한다. 다리 하나를 잃으면 이동 속도 50%, 둘을 잃으면 18%라는 기존 보정은 유지한다.
- 기어가는 동안 서서 펀치하는 대신 낮은 자세로 물기를 사용한다. 이동용 몸통 캡슐 높이는 0.86m, 공격 사거리는 1.15m로 맞춘다. 이 값과 착지 안정성 기준·자세 전환 시간은 조정 가능한 구현값이다.
- 절단 자체는 보상을 지급하지 않는다. 실제 사망 때 기존 처치·전리품·귀환문 처리를 한 번만 실행한다.

Each of five regions requires at least two positive hits and 35 accumulated damage. These are initial tunable values. Damage persists independently; torso hits only reduce health. Missing arms cannot deliver their corresponding punches; an armless Creep uses bites. Losing either leg enters a living physical `falling` phase. Once the torso and head are near the ground and stable, `recovering` blends the actual fallen pose into the prone pose. Pursuit and attacks stay disabled until recovery completes, then supporting hands alternate forward reaches and pulling the body. One missing leg halves movement; two reduce it to 18%. Crawling uses a low bite instead of upright punches, with a 0.86m navigation capsule and 1.15m attack range. Timing and dimensions are tunable implementation values. Only actual death grants the normal single reward.

## 다리 절단 후 기어가기 / Crawling after leg loss

넘어지는 동안에는 사망 랙돌과 같은 실제 관절·충돌 물리를 사용하되 살아 있는 상태를 유지한다. 착지 후 실제 뼈 자세에서 회복을 시작하므로 쓰러진 상태를 버리고 즉시 기본 포복 자세로 튀지 않도록 한다. 착지·회복 중에도 예약 부위 타격과 F2 일시정지 경로를 유지한다. / Falling uses actual joint and collision physics while the actor remains alive. Recovery starts from the physical bone pose after landing, avoiding an immediate snap to the default crawl pose. Scheduled localized hits and F2 pause remain available throughout the fall and recovery.

원본의 누운 `sleep_loop` 자세(Godot 가져오기 이름 `sleep`)를 기어가기의 골격 기준으로 사용하고, 머리를 진행 방향으로 돌린 뒤 손 목표점에 맞춰 팔 관절을 계산하는 IK와 몸통 이동을 코드로 더한다. 손이 앞으로 나가는 구간과 지면을 지지하며 몸을 당기는 구간을 교대로 연결한다. 원본 FBX·GLB의 17개 클립은 보존하며, 새 포복 동작을 별도 FBX 애니메이션으로 제작했다고 표현하지 않는다.

The source prone `sleep_loop` pose (imported in Godot as `sleep`) provides the skeletal basis. Code turns the head forward and adds procedural hand-target IK and body motion, alternating forward reaches with planted pulling phases. All seventeen source FBX/GLB clips remain intact. This is a procedural crawl based on a source pose, not a separately authored crawl FBX clip.

## 실제 3D 및 타격 / Geometry and contacts

`tools/build_creep_dismemberment.py`는 로컬 원본 `creep.glb`에서 여섯 개 스킨 메시와 열 개 절단면을 만든다. 원본은 변경하지 않는다. 원본의 55개 뼈, 17개 클립, 피부 재질·텍스처를 유지한다. 절단면은 평소 숨기고 해당 부위가 잘릴 때 표시한다. 잘리는 순간의 피부 변형을 한 번 계산해 독립된 `RigidBody3D`로 옮긴다. 분리 부위는 지면·벽과 충돌하며, 본체가 움직이거나 나중에 사망해도 다시 연결되지 않는다.

The converter preserves the original file and produces six skinned parts and ten caps. Each severed part is baked at the contact pose and released as an independent rigid body with floor/wall collision. It cannot stretch back to the living skin or reappear in the later death ragdoll.

검·철퇴 근접과 화살·투척 철퇴·마법은 현재 뼈 위치를 따라 움직이는 부위 캡슐에 접촉한다. 이는 삼각형 하나하나를 검사하는 픽셀 단위 판정이 아니라, 신체 두께에 맞춘 간단한 충돌 형상이다. 이동용 몸통 캡슐로 없어진 팔을 다시 맞히지 않는다. 벽과 신체의 충돌 순서를 비교하며, 꽂힌 화살도 부위의 뼈와 절단 조각을 따라간다.

Melee and projectiles use posed anatomical capsules, not per-triangle pixel-exact collisions. The broad navigation capsule cannot absorb hits through a missing limb. World contacts are ordered by collision time; embedded arrows follow both live bones and detached parts.

## 설치와 시험 / Installation and trials

원본 설치는 [CREEP_ASSET.md](CREEP_ASSET.md)를 따른다. 프로젝트 루트에서 다음을 실행한 뒤 Godot 에셋을 다시 가져온다.

After installing the original asset, run from the repository root and reimport the derived GLB in Godot:

```sh
python3 tools/build_creep_dismemberment.py
python3 tools/verify_creep_dismemberment.py
```

파생 파일은 `godot-game/assets/licensed/creep/creep_dismembered.glb`다. 원본과 마찬가지로 공개 GitHub에 에셋 자체를 재배포하지 않는다. 코드·변환기·설치 안내는 공개한다. 파생 파일이 없으면 기존 크리프 모델을 유지하고 F2 절단 시험은 설치 안내를 표시한다.

The derived GLB stays local under `assets/licensed/creep/`; public GitHub contains code, converters and installation instructions. Without the derivative, the original Creep remains available and the dismemberment trial reports the missing installation.

게임을 다시 실행한 뒤 **F2 → 기본 → 크리프 절단**의 다섯 부위·양다리 기어가기·분산 타격 비교를 선택한다. 0.8초 간격 18 피해 두 번을 실제 타격 함수로 적용한다. 생존 개체는 예약 타격이 끝나면 전투 처리를 재개하되, 다리가 절단된 개체는 랙돌 착지와 포복 자세 전환까지 기다린다. 양다리 시험은 시험 전용 체력 118에서 왼다리 두 번, 오른다리 두 번으로 총 네 번 타격하고 체력 46을 남겨 기어가는 상태를 관찰한다. 일반 크리프 체력은 바꾸지 않는다. F2는 예약 타격·적 AI·쓰러지는 랙돌·포복 자세 전환·기어가기·떨어진 부위의 물리를 함께 멈춘다. 재선택으로 초기화하고 원정을 나가면 원래 인벤토리·상태를 복원한다.

Restart the game and select one of five region trials, both-legs crawling, or the distributed-hit comparison under F2. Two real 18-damage hits occur 0.8 seconds apart. Combat processing resumes after the scheduled hits, but a legless actor still waits for physical landing and prone recovery before pursuing or attacking. The both-legs fixture starts at 118 test-only HP and applies two hits to each leg, retaining 46 HP for observing the live crawler. Normal Creep health is unchanged. F2 pauses pending hits, AI, the falling ragdoll, prone recovery, crawling and detached physics. Reselection resets the trial; leaving restores the original expedition.

자동 검증 / Automated checks:

```sh
./godot-game/tests/run_headless_tests.sh creep_knockdown creep_crawl creep_dismemberment creep_ragdoll creep_enemy creep_hit_query creep_dismemberment_trial test_room
```

검수 기록과 확인 범위는 [검증 결과](../artifacts/validation/creep_dismemberment_20260917/README.md)에 남긴다. / See the linked validation record for executed checks, actual renders and remaining limits.

2026-09-18: [18초 실제 렌더링 영상](../artifacts/validation/creep_dismemberment_video_20260918/creep_dismemberment.mp4)과 [촬영·검증 기록](../artifacts/validation/creep_dismemberment_video_20260918/README.md)을 추가했다. 팔·다리·머리 순서로 절단과 후속 동작을 연속 확인할 수 있다. / Added an 18-second actual-render video and capture record showing arm, leg and head severance with subsequent behavior.

위 영상은 기어가기 변경 전의 기록이다. 새 기어가기의 자동 검사·실제 영상과 남은 제약은 [기어가기 검수 기록](../artifacts/validation/creep_crawl_20260918/README.md)에 기록한다. 관련 자동 검사 7개와 최종 집중 검사, 실제 GPU 영상 36초 검증을 완료했다. / The video above records behavior before the crawl change. New automated checks, actual video and remaining limits belong in the linked crawl validation record. Seven related suites, a final focused rerun and a 36-second actual GPU video passed.

후속 랙돌 착지·포복 회복 변경은 위 자동 검사 **8개와 실제 GPU 영상 60초 검증을 통과**했다. 실제 물리 착지·자세 인계 연속성·바닥 없는 상태의 회복 금지·일시정지·사망 전환과 F2 시험·관련 회귀를 확인했다. 일반 테스트룸의 기존 종료 시 ObjectDB 2개 경고는 남아 있다. [새 시연 영상](../artifacts/validation/creep_living_fall_20260918/creep_living_fall.mp4)은 왼다리·오른다리·양다리의 낙하·착지·회복·추적을 실제 900프레임으로 보여준다. 결과와 남은 제약은 [랙돌 착지·회복 검수 기록](../artifacts/validation/creep_living_fall_20260918/README.md)에 남긴다. 위 기어가기 영상은 이 물리 전환이 추가되기 전의 기록이다.

The physical fall and prone recovery change **passed eight automated suites and a 60-second actual GPU video review**, covering actual landing, pose-handoff continuity, no recovery without a floor, pause, fatal transition, F2 trials and related regressions. The general test-room check retains its existing two-ObjectDB exit warning. The new video contains 900 actual frames showing the left-leg, right-leg and both-leg falls, landing, recovery and pursuit. Results and limitations belong in the linked fall/recovery validation record. The earlier crawl video predates this physical transition.
