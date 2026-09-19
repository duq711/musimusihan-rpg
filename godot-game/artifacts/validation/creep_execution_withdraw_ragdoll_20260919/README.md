# 검을 뽑을 때 랙돌 / Ragdoll on sword withdrawal

한국어: 포복 중인 크리프를 깊게 찌른 뒤에는 마지막 움찔 자세를 유지하고, 실제 검끝이 몸에서 빠져나오는 순간부터 중력 랙돌로 쓰러지도록 수정했습니다. 칼날 55% 삽입, 깊게 찌를 때 한 번 크게 움찔하기, 사망·보상 1회 처리는 유지합니다.

English: A crawling Creep holds its final deep-stab contraction until the actual sword tip clears the body, then falls using gravity-driven ragdoll. The 55% blade insertion, one strong deep flinch, and single death/reward are preserved.

## 실제 영상 / Actual capture

[18초 검수 영상 / 18-second validation video](creep_execution_withdraw_ragdoll.mp4)

- 0–6초: 왼다리 절단 · 1인칭 / Left leg missing, first person.
- 6–12초: 같은 조건을 별도로 재실행한 측면 / Separate side-camera repeat under the same conditions.
- 12–18초: 양다리 절단 · 1인칭 / Both legs missing, first person.

실제 게임 클래스와 모델을 사용한 숨김 GPU 시험 장면입니다. 생성 영상이나 합성이 아닙니다. 측면에는 1인칭용 팔 모델만 표시되며 별도의 전신 플레이어 모델은 없습니다. 960×540, 30fps, 540프레임, 무음이며 전체 파일 디코딩을 통과했습니다.

This is an embedded GPU test scene using production gameplay classes and models, not generated or composited imagery. The side view shows the first-person arms, not a full-body player model. The silent 960×540, 30fps video contains 540 frames and passed full-file decoding.

## 확인 결과 / Verification

- `creep_execution`, `creep_execution_trial`, `creep_ragdoll`, `sword_shield_execution`: 모두 PASS / All PASS.
- 왼다리·오른다리·양다리 절단 자동 검사에서 찌르는 동안 자세 유지, 검끝 이탈 시 즉시 물리 전환, 사망·보상 1회를 확인했습니다. / Automated checks cover left, right, and both missing legs; pose holding, immediate release on blade clearance, and one death/reward.
- 깊은 타격은 1.02초, 뽑기 시작은 1.46초입니다. GPU 세 사례 모두 1.70초에 검끝이 원래 피부 진입점에서 1.80cm 빠져나와 랙돌로 전환했습니다. 추가 사망 반응 지연과 인위적인 밀침은 없습니다. / Deep impact remains at 1.02s and extraction begins at 1.46s. All three GPU cases release at 1.70s with the tip 1.80cm outside the original entry point, without an extra death reaction or added impulse.
- 이탈 후 약 0.15초 동안 주요 물리 몸체의 최대 이동은 약 22.14cm입니다. `buried_hold_end`, `blade_exit_before`, `blade_exit`, `ragdoll_motion`의 실제 1인칭·측면 PNG를 열어 자세 유지와 이후 낙하를 확인했습니다. / Core physical bodies move up to about 22.14cm within roughly 0.15s after release. Actual first-person and side images at the named stages were opened and inspected for holding and subsequent falling.
- 취소, 장비 변경, 플레이어 사망·제거, 긴 프레임, F2 일시정지·재개, 시험 변경·초기화를 검사했습니다. 분리된 대상은 물리 세계로 돌아온 뒤 해제하고, 삭제 예정 대상에는 물리 몸체를 만들지 않습니다. / Checks cover cancellation, equipment changes, player death/removal, long ticks, F2 pause/resume, trial changes and resets. Detached targets release on re-entry; queued deletions create no physical bodies.

첫 시험에서 대상 초기화 중 물리 생성 오류를 발견하여 수정했습니다. 최종 기능·시험룸 재검사 로그는 `headless_final.log`이며 엔진 오류 없이 통과했습니다. 일반 사망·검방패 회귀 검사는 `headless_regression.log`에 있습니다.

The first trial exposed an off-tree physics creation error during reset. It was fixed; the final feature/trial rerun in `headless_final.log` passed without engine errors. Ordinary death and sword/shield regression results are in `headless_regression.log`.

`validation_summary.json`, `physics_report.json`, `render_manifest.json`에 시점·실제 칼날 깊이·물리 상태와 소스 16개의 SHA-256을 기록했습니다. 단계별 실제 PNG 48장을 함께 보존합니다.

The summary, physics report, and render manifest record timing, measured blade depth, physics state, and 16 source SHA-256 hashes. All 48 actual stage PNGs are preserved.

미확인: 경사·계단, 다른 체격의 적, OS 키보드·마우스로 전체 던전을 진행한 결과. 검수 범위는 현재 크리프 모델과 평평한 시험 바닥입니다.

Unverified: slopes/stairs, differently sized enemies, and a full dungeon playthrough using OS keyboard/mouse input. Validation covers the current Creep model on a flat test floor.
