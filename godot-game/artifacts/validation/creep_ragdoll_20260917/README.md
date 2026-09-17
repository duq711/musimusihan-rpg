# 크리프 래그돌 검증 / Creep ragdoll validation

2026-09-17. 실제 게임의 크리프는 치명타 직후 0.18초 피격 반응을 거쳐 20개 물리체·19개 제한 관절로 쓰러진다. 원본 스킨과 모든 클립은 보존하며, 독립된 손·발 IK 뼈를 명시적으로 연결한다. 보상·귀환문은 사망 순간 한 번만 처리한다.

The production Creep now transitions from a 0.18-second hit reaction into a 20-body, 19-joint ragdoll. Explicit mappings preserve its unusual hand/foot IK roots, original skin, and source clips. Defeat rewards and extraction progress remain immediate and single-fire.

[실제 렌더 영상 / Actual render video](creep_ragdoll.mp4): 14초, 1280×720, 30fps, 420프레임. 측면 충격·벽 접촉 다음 정면 충격·열린 바닥 낙하. 게임의 실제 치명타·연속 물리를 스튜디오에서 촬영했으며 수동 플레이 영상이 아니다. / 14 seconds; side impact against a wall, then frontal impact onto open floor. Production fatal-hit handling and continuous physics in a neutral studio, not a manual gameplay recording.

![벽 접촉 후 / After wall contact](side_impact_settled.png)
![바닥 낙하 후 / After floor collapse](front_impact_settled.png)

## 실행한 검사 / Checks executed

- `creep_ragdoll`: 실제 60Hz 물리 4조건(정면·측면·반대쪽·정면 벽), 유한 좌표, 바닥/벽 경계, 몸통 낙하, 관절 연결, 정착·고정, 중복 사망 방지, 원본·커서 보존 통과. 열린 바닥/측면벽은 약 2.35–2.83초, 정면벽은 약 6.02초에 정착. / Four actual physics cases passed; settling took ~2.35–2.83 s normally and ~6.02 s against the frontal wall.
- `creep_ragdoll_trial`: 3개 F2 실행 경로, 실제 1초 타이머 치명타, 반응→물리, F2 정지·재개, 한 번의 룬 보상, 재선택·예약 취소·초기화, 원정·인벤토리 정확 복원 통과. / Three real trial paths, pausable fatal-hit timers, transitions, single rewards, replay/reset/cancellation and exact session restoration passed.
- `creep_enemy`, `creep_motion_reel`, `test_room` 관련 회귀 통과. / Related combat, retained source-clip reel, and test-room regressions passed.
- Vulkan Forward+ 실제 렌더: 두 시나리오 각각 210프레임, 프레임마다 60Hz 물리 2틱, 4단계(living/reaction/simulating/settled), 원정·커서·소스 해시 보존 통과. 초기·낙하·최종 이미지를 직접 열어 검토. / GPU capture verified exactly two physics ticks per video frame, all four phases and preserved state/hashes; stills were opened and reviewed.

## 보완 과정과 범위 / Iteration and limits

초기에는 지면에 닿은 뒤 관절 계산의 미세한 떨림으로 정착이 늦어졌다. 지지 여부·이동 에너지와 시간 조건을 함께 사용하고 잔진동 감쇠를 늘렸다. 첫 5초 렌더에서 벽 앞 정착을 모두 담지 못한 실패도 보존했다. 최종 영상은 7초씩 촬영한다. / Initial solver jitter delayed settling; support, motion energy, damping and time conditions were tuned. A first five-second capture failed to include settled state against the wall. Final cases are recorded for seven seconds each.

물리 충돌은 20개의 단순 캡슐로 근사한다. 손가락별 충돌·시체 차기·경사면/계단 전면 시험·대규모 시체 더미 성능은 이번 검증에 포함하지 않는다. 4조건에서 순간 관절 앵커 오차 최대 약 0.119m를 기록했으며 영구 분리는 관찰되지 않았다. 작은 손끝/표면 접촉 여유는 남을 수 있다. / Collision uses simplified capsules. Per-finger collision, corpse kicking, exhaustive slopes/stairs and large corpse piles are not covered. Peak transient joint-anchor error was ~0.119 m across tested impacts; no permanent separation was observed. Small surface/contact padding remains possible.

기존 텍스처 UID 3개는 파일 경로로 정상 대체되며, 기존 테스트룸 종료 시 ObjectDB 2개 경고가 남는다. 이번 실행은 설치된 에셋 기준이며 미설치 분기는 별도로 재실행하지 않았다. / Existing texture UID fallbacks and the test-room's two-instance exit warning remain. Tests used the installed asset; missing-asset branches were not separately rerun this time.

`manifest.json`은 전체 로컬 캡처 기록에서 프레임 시각·상태·검사 결과와 최종 자세를 추린 공유본이다. 원본 메시/텍스처는 공개하지 않는다. / The shared manifest retains timing, phases, validation results and final poses from the full local capture. Licensed model/texture files are not published.
