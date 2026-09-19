# 크리프 공격 후 이동 연결 / Creep attack-to-walk continuity

2026-09-19. 물기와 양손 연타 뒤 걷기 첫 프레임으로 즉시 이동하던 자세 전환을 수정했다. 수동 `AnimationPlayer.seek()` 경로에 실제 뼈 자세 보간을 넣고, 현재 발 위치에 가까운 보행 시점을 선택한다. 공격→추격은 0.28초, 이동→공격 준비는 0.12초 동안 연결한다. 보행 시계는 실제 수평 속도에 맞춘다. 공격 접촉·피해·회복 시간과 원본 17개 클립은 바꾸지 않았다.

Replaced the immediate jump from bite/two-punch recovery into walk frame zero. The manual AnimationPlayer path now blends actual skeletal poses, selects a nearby foot phase, and advances walking according to horizontal velocity. Attack-to-chase blends for 0.28 seconds; moving-to-windup blends for 0.12 seconds. Authored contact, damage and recovery timings, and all seventeen source clips, remain unchanged.

## 실제 영상 / Actual rendered videos

- [수정 결과 8초 / After, 8 seconds](after.mp4)
- [동일 카메라 전후 비교 / Same-camera comparison](before_after.mp4)
- [수정 전 / Before](before.mp4)

0–4초는 물기 후 추격, 4–8초는 양손 공격 후 추격이다. 두 경우는 각각 새로 만든 개체다. 60Hz 실제 생산 AI·물리를 실행하며 회복 중 타깃만 뒤로 옮겼다. 촬영 도중 본·애니메이션 시각·몬스터 이동을 강제 지정하지 않았다. 같은 고정 카메라, 조명, 바닥에서 Vulkan 1280×720, 30fps로 각 버전 240장을 촬영했다. 비교 영상만 두 실제 영상을 나란히 축소하고 BEFORE/AFTER 글자를 넣었다. 단독 영상은 원래 GPU 화면이다. MP4 세 파일 모두 240프레임 전체 디코딩을 확인했다.

The first four seconds show bite-to-chase; the next four show punch-to-chase on a separately initialized actor. Actual production AI and 60Hz physics run continuously; only the target retreats during recovery. No bones, animation time or monster positions are forced while recording. Both versions use the same fixed camera, lighting and floor: Vulkan, 1280×720, 30fps, 240 frames. Only the comparison video scales the two genuine recordings side by side and labels them. All three MP4 files were fully decoded to verify all 240 frames.

## 관찰 결과 / Observed results

| 실제 60Hz 전환 경계 / Actual 60Hz boundary | 수정 전 / Before | 수정 후 / After |
|---|---:|---:|
| 물기 후 오른발 위치 변화 / Right foot after bite | 0.84419m | 0.00295m |
| 연타 후 오른발 위치 변화 / Right foot after punch | 0.84939m | 0.00307m |
| 물기 후 왼손 위치 변화 / Left hand after bite | 0.44407m | 0.00442m |
| 연타 후 왼손 위치 변화 / Left hand after punch | 0.44582m | 0.00447m |

즉시 같은 자세를 유지하는 단위 검사와 별도로, 위 수치는 실제 AI가 다음 1/60초까지 진행한 결과다. 회복 종료와 추격 시작 틱(물기99, 연타76), 실제 접촉 횟수(1회, 2회)는 전후 동일하다. 전환 주변 0.4초 내 추적한 관절의 프레임당 최대 상대 이동은 수정 후 약 5.5cm다. 원본 보행 자체의 과장된 보폭은 유지하며, 이번 작업은 애니메이션 사이의 연결을 수정했다.

These runtime measurements include one real 1/60-second update, separately from the exact entry-pose unit check. Chase start ticks (99 for bite, 76 for punch) and actual contact counts (one and two) match before and after. Tracked-joint maximum relative movement per frame in the surrounding 0.4-second window is approximately 5.5cm after the fix. The source gait's exaggerated stride remains; this revision addresses transitions between animations.

## 검증 / Validation

최종 고유 자동 검사 7종 통과: `creep_locomotion_transition`, `creep_enemy`, `creep_motion_reel`, `creep_crawl`, `creep_ragdoll`, `creep_execution`, `test_room_session`.

Seven distinct final suites passed: exact per-bone entry continuity, converging to independently sampled source walking, actual-speed clock, attack entry, hit/execution/death ownership, contacts/guard/rewards, crawling, physical collapse, executions, F2 reselect/reset and expedition restoration.

```sh
./godot-game/tests/run_headless_tests.sh creep_locomotion_transition creep_enemy creep_motion_reel creep_crawl creep_ragdoll creep_execution test_room_session
CREEP_TRANSITION_QA_ITERATION=<new-name> GODOT_PREVIEW_TIMEOUT_SECONDS=240 ./godot-game/tests/run_embedded_preview.sh creep_transition_preview.gd
```

F2 → 기본 → 크리프 · 괴물 근접 전투. 공격이 끝날 때 S로 거리를 벌리면 실제 추격 재개를 확인할 수 있다. F2 재선택은 회복·재생성한다. 기존 메뉴 연결·원정 복원을 자동 검증했으며 OS 키보드 입력/사용자 데스크톱 포커스 시험은 하지 않았다.

Use F2 → Basic → Creep melee trial; back away as an attack finishes to inspect resumed pursuit. Reselecting heals and respawns. The real menu wiring and session restoration were checked automatically; hardware keyboard input and desktop focus were not tested.

초기 검사에서 발견한 사항:

- 신규 검사에서 스켈레톤 내부 좌표를 미터로 오인했다. 모델 배율0.3513을 반영한 실제 월드 좌표로 고쳤고 16cm 기준은 유지했다. 전체 56본 중 실제 최대는 손끝 약10.67cm/프레임이다.
- 기존 `creep_crawl`의 처형 검사는 0.7초 타격 전 자세를 1.02초의 의도된 반동과 비교했다. 수정 전 크리프 코드로도 같은 실패를 재현했다. 실제 접촉 시점의 자세를 기준으로 고쳤으며 게임 처형 코드는 바꾸지 않았다.
- 촬영 도구 최초 실행의 비어 있는 인벤토리 처리와 기록 시작 전 물리 시계 진행을 수정했다. 최종 `before_03`, `after_01`은 각240프레임·프레임당2물리틱·원정/커서/소스 보존 검사를 모두 통과했다.

Initial validation corrections: a new test confused skeleton coordinates with world meters (the unchanged 16cm threshold now uses the actual 0.3513 rig scale); an existing crawling execution test compared pre-impact and intentional deep-hit recoil poses, which also failed with the original Creep script, so its reference time was corrected without changing execution gameplay. The capture harness was corrected for an initially absent inventory and a clock that began before recording. Final before_03 and after_01 captures passed their 240-frame, two-ticks-per-frame and state/source-preservation checks.

`before_metrics.json.gz`, `after_metrics.json.gz`, `summary.json`에 원본 해시·카메라·전체60Hz 관절 기록·검증 결과를 보존했다. 라이선스 원본 모델은 프로젝트의 기존 비공개 로컬 경로에 보존하며 이 증거 패키지에 재배포하지 않는다. 캡처는 실제 게임 코드의 격리 시험이며 폐광 전체 장면·다수 개체 성능 측정은 이번에 하지 않았다.

The metrics and summary retain source hashes, camera settings, every 60Hz joint sample and check results. Licensed source models remain in their original private local location and are not redistributed in this evidence package. Captures exercise the actual game code in an isolated fixture; this revision did not benchmark the full mine scene or multiple enemies.
