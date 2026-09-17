# 크리프 부위 절단 / Creep dismemberment

사용자 결정: 같은 팔·다리·머리를 집중 공격하면 절단한다. **팔다리 절단 후에도 살아서 전투를 계속한다.** 머리 절단은 즉시 사망이다. 기존 체력 소진으로 사망하는 규칙은 그대로 적용한다.

User decision: concentrated attacks can sever an arm, leg or head. **Limb loss does not automatically kill the creature**; it continues fighting until ordinary health depletion. Decapitation kills immediately.

## 현재 규칙 / Current tuning

- 왼팔·오른팔·왼다리·오른다리·머리를 따로 누적한다. 같은 부위에 양의 피해 **2회 이상 + 누적 35**가 필요하다. 수치는 이번 구현의 조정 가능한 초기값이다.
- 부위 피해는 시간이나 다른 부위 타격으로 초기화되지 않는다. 서로 다른 부위의 피해는 합산하지 않는다. 몸통 타격은 체력만 줄인다.
- 잃은 팔의 펀치는 피해를 주지 않는다. 원본 클립의 첫 접촉은 오른팔, 두 번째는 왼팔이다. 양팔을 잃으면 물기만 선택한다.
- 다리 하나를 잃으면 이동 속도 50%, 둘을 잃으면 18%가 된다. 남은 몸은 기울여 지면에 맞추며 기존 추적·공격 클립을 사용한다. 별도로 제작한 절뚝임·포복 애니메이션은 아니다.
- 절단 자체는 보상을 지급하지 않는다. 실제 사망 때 기존 처치·전리품·귀환문 처리를 한 번만 실행한다.

Each of five regions requires at least two positive hits and 35 accumulated damage. These are initial tunable values. Damage persists independently; torso hits only reduce health. Missing arms cannot deliver their corresponding punches; an armless Creep uses bites. One missing leg halves movement, two reduce it to 18%. Existing clips use a grounded lean; bespoke limping/crawling clips are not included. Only actual death grants the normal single reward.

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

게임을 다시 실행한 뒤 **F2 → 기본 → 크리프 부위 절단**의 다섯 부위 또는 분산 타격 비교를 선택한다. 0.8초 간격 18 피해 두 번을 실제 타격 함수로 적용한 뒤 생존 개체가 전투를 재개한다. F2는 예약 타격·적 AI·떨어진 부위의 물리를 함께 멈춘다. 재선택으로 초기화하고 원정을 나가면 원래 인벤토리·상태를 복원한다.

Restart the game and select one of five region trials or the distributed-hit comparison under F2. Two real 18-damage hits occur 0.8 seconds apart before combat resumes. F2 pauses pending hits, AI and detached physics. Reselection resets the trial; leaving restores the original expedition.

자동 검증 / Automated checks:

```sh
./godot-game/tests/run_headless_tests.sh creep_dismemberment creep_hit_query located_hit_path creep_dismemberment_trial creep_enemy creep_ragdoll
```

검수 기록과 확인 범위는 [검증 결과](../artifacts/validation/creep_dismemberment_20260917/README.md)에 남긴다. / See the linked validation record for executed checks, actual renders and remaining limits.

2026-09-18: [18초 실제 렌더링 영상](../artifacts/validation/creep_dismemberment_video_20260918/creep_dismemberment.mp4)과 [촬영·검증 기록](../artifacts/validation/creep_dismemberment_video_20260918/README.md)을 추가했다. 팔·다리·머리 순서로 절단과 후속 동작을 연속 확인할 수 있다. / Added an 18-second actual-render video and capture record showing arm, leg and head severance with subsequent behavior.
