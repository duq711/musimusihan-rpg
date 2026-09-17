# 크리프 절단면 개선 / Creep wound surfaces

2026-09-18 사용자 요청: 단색 분홍색 절단판으로 긴장감이 깨지는 표현을 개선한다. 절단 판정·생존·보상 규칙은 유지한다.

User request: replace the uniform pink cut surface with a convincing injury. Existing hit, survival and reward rules remain unchanged.

## 구현 / Implementation

- 머리 분리군에서 `Neck`을 제외해 목과 등은 몸체에 남긴다. 런타임 부위 판정·래그돌도 같은 구분을 사용한다.
- 원래 피부 경계 정점·가중치를 유지하고, 몸체·떨어진 부위에 각각 안쪽으로 최대 3.5cm 들어간 단면을 만든다. 불규칙한 테두리·짙은 내부·근육층·작은 뼈와 골수 중심은 실제 메시와 정점색이다.
- 단면 UV 기반 셰이더는 얼룩·섬유 명암·젖은 반사를 추가한다. 양쪽 단면과 CPU 스키닝 결과에 같은 재질·UV·정점색을 유지하며 피격 발광 덮개를 제거한다.
- 절단 순간 단면의 실제 변형 위치에서 작은 방울 24개를 한 번 방출한다. 월드 표면에 부딪힌 방울만 혈흔을 남기며, 한 번에 최대 12개·18초 수명이다. 지면 없는 곳에는 떠 있는 혈흔을 만들지 않는다.
- 효과는 F2와 함께 멈추며 재선택·장면 정리 시 제거된다. 효과 자체는 피해·보상을 발생시키지 않는다.

The neck stays with the torso. Both sides retain the original animated skin boundary and gain recessed tissue geometry, varied vertex colors and a UV-based wet surface material. A single bounded burst emits 24 droplets from the posed cut; world contacts produce at most 12 stains, all cleaned up after 18 seconds or when their owner is removed. Pause applies to particles, stains and their lifetime. Effects do not affect damage or rewards.

## 재생성과 확인 / Rebuild and inspect

원본·파생 GLB는 기존 라이선스 정책에 따라 로컬에 보존한다. 공개 저장소에는 생성기·런타임·검증 코드와 렌더 결과만 공유한다.

Original and derived GLBs remain local under the existing asset policy. The public repository shares the builder, runtime, checks and rendered evidence.

```sh
python3 tools/build_creep_dismemberment.py
python3 tools/verify_creep_dismemberment.py
# Reimport the derived GLB in Godot before testing.
./godot-game/tests/run_headless_tests.sh creep_wound creep_dismemberment creep_dismemberment_trial creep_knockdown creep_crawl creep_ragdoll creep_hit_query test_room_session
CREEP_WOUND_QA_ITERATION=review_01 GODOT_PREVIEW_TIMEOUT_SECONDS=360 ./godot-game/tests/run_embedded_preview.sh creep_wound_preview.gd
```

게임을 다시 실행하고 **F2 → 기본 → 크리프 절단면 · 깊이·혈흔**을 선택한다. 실제 머리 타격 두 번으로 절단하며 기존 팔·다리 시험에도 같은 단면·효과가 적용된다. F2 정지, 같은 항목 재선택으로 체력·온전한 몸을 복구한다.

Restart the game and choose **F2 → Basic → Creep wound surfaces**. Two real head hits trigger the cut; existing arm and leg trials use the same surfaces and effects. F2 pauses; reselecting restores the intact actor and health.

촬영은 창·포커스·소리를 만들지 않는 기존 embedded GPU 경로로 수행한다. 스튜디오 검수 장면이며 사용자 데스크톱 또는 실제 하드웨어 조작 검증은 아니다. 현재 남은 한계는 고정된 관절 부위 절단(임의 평면 절단 아님), 경량 입자·혈흔(유체 시뮬레이션 아님)이다.

Capture uses the audited embedded GPU path without windows, focus or sound. It is a studio inspection fixture, not desktop or hardware-input validation. Cuts remain at fixed anatomical regions; droplets and stains are lightweight effects rather than fluid simulation.

검증 결과와 실제 화면: [이번 검수 기록](../artifacts/validation/creep_wounds_20260918/README.md).

Executed checks and actual screenshots: [validation record](../artifacts/validation/creep_wounds_20260918/README.md).
