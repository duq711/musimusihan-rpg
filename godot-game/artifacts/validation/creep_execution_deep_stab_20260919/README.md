# 단계별 포복 처형 / Staged crawling execution

2026-09-19: 사용자가 요청한 **준비 자세 → 첫 찌르기 → 더 깊게 밀기 → 검 뽑기**로 기존 포복 크리프 처형을 수정했습니다. 단일 찌르기였던 이전 1.55초 동작과 검수 자료는 보존했습니다.

The existing crawling-Creep execution now follows the requested **prepare → stab → push deeper → withdraw** sequence. The previous 1.55-second single-thrust version and its evidence remain preserved.

[실제 실행 영상 · 18초 / Actual runtime video · 18 seconds](creep_execution_deep_stab.mp4)

| 동작 / Motion | 처형 시작 후 시각 / Time after execution starts |
| --- | --- |
| 준비 자세를 잡고 유지 / Prepare and hold aim | 0–0.75s |
| 첫 찌르기 · 약 4.5cm / Initial stab, approximately 4.5cm | 0.75–1.03s |
| 잠깐 저항을 받는 구간 / Brief resistance | 1.03–1.18s |
| 약 22cm까지 밀기 · 결정타 / Push to approximately 22cm, lethal contact | 1.18–1.52s |
| 깊게 꽂은 자세 유지 / Hold at full depth | 1.52–1.72s |
| 같은 방향으로 검 뽑기 / Withdraw on the insertion axis | 1.72–2.12s |
| 기본 자세로 복귀 / Return to ready | 2.12–2.50s |

처음 찔렀을 때는 살아 있으며, 깊게 미는 마지막 순간에 한 번만 사망·보상과 기존 랙돌을 처리합니다. 시작할 때 기존 충돌 이동으로 몸통에서 약 1.05m까지 다가갑니다. 팔을 늘이지 않고 22cm 깊이를 확보하기 위한 접근 거리 조정입니다. 검·방패 처형의 기존 시간은 바꾸지 않았습니다.

The crawler stays alive during the first stab; full-depth contact commits one death/reward and the existing ragdoll. Normal collision movement approaches approximately 1.05m from the torso so the deeper push fits the original arm lengths. Standing sword-and-shield execution timing is unchanged.

## 확인한 내용 / Verified

- 자동 검사 `creep_execution`, `creep_execution_trial`, `sword_shield_execution`: 3종 통과. 실제 왼다리·오른다리·양다리 절단과 회복, 준비·얕은 관입·깊은 관입·회수, 결정타 시점, 단일 보상, 중단, F2 정지·재개·복원, 기존 서 있는 적 처형을 확인했습니다.
- 실제 GPU `deep_stab_20260919_final03`: 한쪽 다리 1인칭, 같은 기능의 별도 측면 반복, 양다리 1인칭을 각 6초씩 촬영했습니다. 세 사례 모두 조기 사망 없음, 단일 처치, 실제 피부 접촉을 확인했습니다.
- 첫 렌더에서 깊은 관입 시 어깨가 약 7.3cm 앞으로 보정되는 문제를 발견했습니다. 접근 거리를 1.15m에서 1.05m로 바꾼 뒤, 실제 GPU 재검증에서 세 사례 모두 어깨 보정 0m와 상완 0.34m·전완 0.26m를 유지했습니다. 자동 검사 이후 바뀐 값은 이 접근 거리이며, 변경 후 실제 이동과 접촉은 GPU 실행에서 다시 확인했습니다.
- 960×540, 30fps, 540프레임, 18.00초, 무음 MP4. 전체 540프레임 디코딩 통과. 단계별 PNG 27장을 [stills](stills/)에 보존했습니다.

Three suites passed, covering real limb loss/recovery, both thrust stages, extraction, contact-timed single reward, cancellation, F2 restoration and standing-execution regression. Actual GPU capture contains three six-second cases: single-leg first person, a separate side-view repeat and both-leg first person. All retain one defeat with no premature death. The first render exposed 7.3cm of shoulder correction; reducing the approach distance from 1.15m to 1.05m eliminated it in all three GPU cases while preserving 0.34m/0.26m arm lengths. This distance was the only production parameter changed after the automated suites; actual movement/contact were then rechecked in GPU runs. The silent H.264 video has 540 frames at 30fps and passes complete decoding; 27 named phase stills are included.

## 범위 / Scope

수정한 게임의 실제 모션·전투·물리 코드를 격리된 시험 바닥에서 실행한 영상입니다. 60Hz로 생산 코드의 차지·놓기 함수를 호출하며, 적은 실제 부위 피해·물리 착지·회복을 거칩니다. 촬영 중 적의 이동 AI는 멈춰 접촉을 관찰합니다. 측면은 별도 반복이며 1인칭 팔 장비를 외부에서 확인하는 구도입니다. 던전 수동 플레이, 경사·계단과 다른 크기의 적은 미확인입니다. 생성 이미지·합성 화면은 사용하지 않았습니다.

This uses production motion, combat and physics on an isolated inspection floor. Charge/release runs at 60Hz after real localized damage, physical landing and recovery. Enemy travel is paused during capture to inspect contact. The side view is a separate repeat of the first-person equipment rig. Manual dungeon play, slopes, stairs and differently sized enemies are unverified. No generated or composited imagery replaces runtime rendering.

- [동작 안내 / Feature guide](../../../docs/CREEP_EXECUTION.md)
- [검증 요약·영상 해시 / Summary and video hash](validation_summary.json)
- [실제 GPU 프레임·단계 기록 / GPU frame and phase records](render_manifest.json)
- [물리·접촉 검사 기록 / Physics and contact checks](physics_report.json)
- [실행 로그 / Logs](logs/): 최초 렌더의 어깨 검사 실패도 보존하며, `render02`와 `render-final03`은 통과했습니다. / Initial shoulder-check failures are retained; `render02` and `render-final03` passed.
