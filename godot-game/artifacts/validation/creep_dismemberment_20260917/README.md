# 크리프 절단 검증 / Creep dismemberment validation

작업 시작 2026-09-17, 최종 검증 2026-09-18 · MacBook · Godot 4.7.

다섯 부위의 누적 피해와 실제 메시 분리, 사지 절단 후 전투 지속, 머리 절단 후 래그돌을 구현했다. F2의 다섯 집중 타격 및 분산 타격 비교는 실제 플레이 함수를 사용한다. 원본 모델과 기존 원정 데이터를 보존했다. / Implemented five independent damage regions, real detached geometry, continued combat after limb loss, and decapitation ragdoll. Six F2 trials exercise production code. Original assets and expedition state were preserved.

## 실제 화면 / Actual renders

후속 완료: [2026-09-18 연속 영상과 검증](../creep_dismemberment_video_20260918/README.md). 실제 GPU 270프레임으로 18초 MP4를 완성했다. 아래의 영상 실패 기록은 이전 시도에 해당한다. / Follow-up complete: an 18-second MP4 containing 270 actual GPU frames is now available. The failed-video notes below describe the earlier attempts.

[절단 전](right_arm_008.png) · [오른팔 낙하](right_arm_028.png) · [남은 팔로 공격](right_arm_089.png) · [다리 절단 후 추적](left_leg_060.png) · [머리 분리](head_028.png) · [사망 후 상태](head_089.png)

15개 PNG는 게임의 동일한 Creep 코드·설치 모델·재질을 격리된 흰 조명 시험장에 배치해 **embedded Vulkan Forward+**로 촬영했다. 실제 60Hz 물리를 연속 진행하고 15Hz 표본 중 각 경우의 지정된 5개 시점만 그렸다. 생성 이미지·합성·데스크톱 캡처가 아니다. 원래 게임의 카메라나 배경을 촬영한 화면은 아니며, 카메라는 시험장 검수용이다.

These 15 PNGs are actual embedded Vulkan renders of the installed production creature in an isolated lit fixture, with continuous 60Hz physics and five selected renders per scenario. They are not generated images, composites or desktop screenshots. This is a studio inspection camera, not the live dungeon camera.

- 오른팔: 누적 36, 체력 46, 오른팔 독립 낙하 후 남은 공격 두 번이 시험 대상에 실제로 접촉.
- 왼다리: 누적 36, 체력 46, 속도 절반, 느린 추적 후 공격 두 번 접촉. 마지막 프레임에서는 추적해 가까워지며 머리 일부가 구도 밖으로 나가므로 전신 접지 평가는 앞선 4초 프레임을 사용했다.
- 머리: 누적 36, 체력 0, 머리 분리 후 본체 래그돌. 이 6초 캡처에서 본체는 `simulating` 상태로 끝나므로 완전 정착을 확인했다고 하지 않는다.

Arm/leg cases retain 46 HP and register two subsequent contacts; the leg case moves at half speed. The advancing leg case partly leaves the final camera framing, so the earlier four-second image is used for full-body inspection. The head case ends dead in the ragdoll `simulating` phase; this capture does not claim that its body has fully settled.

`render_manifest.json`에 270개 실제 상태 표본, 원본 해시, 생존 공격 접촉, 커서·원정 보존 검사와 실패 없음이 기록되어 있다. 1280×720/30fps와 960×540/15fps의 연속 영상 시도는 각각 시간 제한으로 중단됐다(`video_attempt_*.log`). **완성된 연속 영상은 제출하지 않는다.** 최종 선택 프레임 촬영은 성공했다(`render.log`). / The manifest records 270 simulation samples and unchanged source hashes. Two continuous-video attempts timed out; no completed video is claimed. The final selected-frame capture passed.

## 실행한 검사 / Executed checks

- `creep_dismemberment`: 5부위 실제 분리·분산 피해·최소 타격수·다중 절단·사망 보상 1회·부위 물리·F2 정지·사망 후 부위 재생성 금지·잘린 몸체의 래그돌 정착·살아 있는 뼈와 분리한 메시·접지·화살 부착 이전·무효 위치·남은 팔의 공격 접촉. `core.log`, `physics_report.json`.
- `creep_enemy`, `creep_ragdoll`: 원본 클립·방패·저스트 가드·전투 보상 및 기존 정면/측면/벽 사망 물리 회귀. `regression.log`.
- `creep_dismemberment_trial`, `test_room`: 6개 실행 항목·예약 타격·F2 정지/재개·재선택·중도 취소·초기화·원정 복원. `test_room.log`. 일반 테스트룸의 기존 ObjectDB 종료 경고 2개는 남았다.
- 타격 경로 담당 검사: `located_hit_path`, `creep_hit_query`, `arrow_projectile`, `flail_projectile`, `magic_system`, `bow_accuracy` 통과. 4,680회 자세별 선분/구체 검사 중 1,692개 접촉의 판정 부위와 실제 누적 부위가 일치했다. 기존 이동 캡슐 밖의 팔 타격, 없어진 부위 빗나감, 벽 우선 충돌, 절단 조각의 화살 부착을 포함했다.
- 모델 독립 검증: 6개 스킨 부위·10개 캡, 새 절단 경계 닫힘, 원본 면적 상대 오차 `5.66e-10`, 원본 17개 클립×5자세의 경계 간격 0m. `geometry_validation.json`.

All listed suites passed. Checks cover region accumulation and separation, surviving attacks, single rewards, projectile ordering, embedded arrows, pause/reset/session restoration, original combat/ragdoll regressions, and closed animated cut seams. The two existing general test-room shutdown leak warnings remain.

## 남은 한계 / Limits

- 다리 손실은 기존 추적·공격 클립에 느린 이동과 지지점 보정을 적용한다. 별도 포복/절뚝임 애니메이션은 제작하지 않았다.
- 실제 부위 판정은 뼈를 따라 움직이는 캡슐이며, 메시 삼각형 단위의 정확한 판정은 아니다.
- 분리 조각은 절단 당시 자세의 단일 강체다. 떨어지는 손가락·팔꿈치의 추가 관절 운동은 없다.
- 목 단면은 단색의 거친 재질이다. 원본 입·치아의 열린 모서리는 그대로 보존했다. 경계의 8개 웨이트 제한으로 일부 새 정점의 최대 1.55% 작은 영향치가 제거·재정규화됐으며 양쪽 경계/캡에 동일하게 적용됐다.
- 경사면·계단·많은 시체 더미의 스트레스 검사는 미확인. 단일 절단의 메시 굽기는 최종 렌더 기록에서 27–32ms였다.

No bespoke limp/crawl clips, per-triangle hitboxes, articulated detached-limb animation or detailed cut-surface textures are included. Slopes, stairs and large corpse piles remain unverified. One-time geometry baking measured 27–32ms in the final capture.

## 공유 범위 / Publication

코드·변환기·문서·검수 렌더는 GitHub 공유 대상이다. 라이선스 원본과 파생 GLB는 로컬 `assets/licensed/creep/`에 유지한다. 원본 작업 폴더의 iCloud Git 인덱스를 건드리지 않고 별도 게시 복사본에서 이번 변경만 적용했으며, 함께 진행 중인 처형 기능 변경은 포함하지 않았다. / Code, converters, documentation and rendered evidence are published. Licensed source/derived models remain local. An isolated publication copy preserves the original iCloud Git index and excludes unrelated execution-feature work.
