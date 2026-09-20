# 후방 검 제압 · 깊은 관통·비틀기·우측 베기 / Through-stab, twist and right cut

상태: 최종 코드의 핵심/F2 검사와 실제 GPU 9초·270프레임 검수 통과. 핵심·F2·포복·검/방패 처형 4종 회귀는 준비 팔 경로를 최종 보정하기 전 후보판의 통과 기록이다. 이전 좌측 발검의 통과 기록을 이번 결과로 사용하지 않는다.

Status: final-code core/F2 checks and nine seconds/270 frames of actual GPU review passed. The four-suite core/F2/crawler/sword-shield regression pass belongs to a candidate before the final preparation-arm correction. Earlier leftward-extraction passes do not validate this revision.

## 변경 범위 / Scope

사용자 최신 요구는 칼날을 거의 끝까지 관통시키고 한 번 비틀어 플레이어 우측으로 베어 빼는 것이다. 목 베기·머리 절단 취소와 머리가 붙은 몸 전체의 랙돌, 단일 사망·보상을 유지한다. 일반 집중 공격 절단·단검 암살·포복 처형과 팔/검 원본 에셋은 범위 밖이다.

The latest request is a nearly full-depth through-stab, one twist and a player-right cut-out. Keep decapitation cancelled, the attached-head full-body ragdoll and one death/reward. Ordinary dismemberment, dagger assassination, crawler execution and source arm/sword assets are outside this change.

## 제작값 / Tunable motion values

- 깊은 찌르기 0.68초. 실제 등 피부 기준 칼날 94% 관입. / Deep stab at 0.68s, inserting 94% of blade length past actual back skin.
- 0.80–1.12초 검날 축 45° 한 번 비틀기. / One 45° blade-axis twist during 0.80–1.12s.
- 1.22–1.98초 플레이어 우측으로 베어 빼기, 1.48초 치명적 몸통 베기. / Player-right cut-out during 1.22–1.98s, fatal torso cut at 1.48s.
- 2.10초까지 여운, 2.62초 복귀. 준비 중 1.15m·찌르기 중 0.78m 접근. / Follow-through to 2.10s, recovery by 2.62s; approach 1.15m in preparation and 0.78m during thrust.

## 직접 시험 / Manual trial

`F2 → 기본 → 검 제압 · 미인지 후방`에서 `E`로 시작한다. 경계 상태·정면 비교 항목은 같은 입력을 거절한다. F2 정지, 회복·재선택, 전체 초기화·원정 복원은 유지한다. 공개 E 동작 API 검사와 OS 하드웨어 입력 검증을 구분한다.

Use E in the unaware-rear F2 trial. Alerted-rear/front comparisons reject it. F2 pause, recovery/replay, reset and expedition restoration remain. Production E API checks and OS hardware input checks are distinct.

## 자동 검증 / Automated validation

[후보판 핵심·회귀 로그](core_regression_tests.log)의 `rear_takedown`, `rear_takedown_trial`, `creep_execution`, `sword_shield_execution` 4종이 모두 통과했다. 이후 실제 렌더에서 드러난 준비 팔 경로를 수정한 **최종 코드**는 [게시용 사본 로그](publication_tests.log)의 핵심·실제 F2 2종과 아래 실제 GPU 검수로 확인했다. 최종 검사는 새로 생성한 대기 자세에서 시작하는 준비 18표본도 포함한다. 테스트룸 등록과 실제 E 처리, 미인지/후방 허용·경계/정면 거절, 공유 시계 정지, 취소·재선택·초기화·원정 복원을 검사했다. 1.15m와 1.49m 시작, 긴 프레임 간격, 막힌 초기 접근의 찌르기 전 취소도 포함한다.

The candidate log passes four suites: `rear_takedown`, `rear_takedown_trial`, `creep_execution` and `sword_shield_execution`. After correcting the preparation arm path exposed by actual rendering, **final code** passed the linked publication-copy core/actual F2 checks and GPU review below. Final checks include 18 preparation samples starting from a freshly initialized idle pose. Coverage includes registration and production E handling, unaware/rear acceptance and alerted/front refusal, shared-clock pause, cancellation/replay/reset and expedition restoration, 1.15m/1.49m starts, long ticks and blocked-approach cancellation before stabbing.

| 핵심 검사 실측 / Core measurement | 결과 / Result |
|---|---|
| 실제 검날 길이 / Actual blade length | 약 / approximately 1.045m |
| 등 피부 이후 관입 / Insertion past back skin | 0.9823m, 94% |
| 반대편 몸통 피부 밖 칼끝 / Tip beyond opposite torso skin | 0.37184–0.40671m |
| 검날 축으로 한 번 비틀기 / One blade-axis twist | 약 / approximately 45° |
| 고정 구간 검날 방향 변화 / Blade drift outside twist | 0° |
| 박힌 검/발검 주요 구간의 실제 손·전완 축 차이 최대 / Maximum embedded/extraction actual hand–forearm axis mismatch | 41.215° |
| 연속 표본 관절 이동 최대 / Maximum joint step | 0.111641m |
| 연속 표본 손 회전 최대 / Maximum hand rotation step | 6.969° |
| 반복 제압 연속 자세 표본 / Reused-fixture continuity samples | 182 |
| 새 대기 자세 준비 표본 / Fresh-idle preparation samples | 18 |
| 새 대기 자세 준비 최대 관절 이동 / Fresh-idle maximum joint step | 0.106447m |
| 새 대기 자세 준비 최대 어깨 보정 / Fresh-idle maximum shoulder correction | 2.699 × 10⁻⁷m |
| 치명적 접촉 / Fatal contact | 몸통 / torso |
| 사망·보상·분리 머리 / Deaths, rewards, separated heads | 1 / 1 / 0 |

관통 검사는 현재 자세의 보이는 실제 피부 삼각형만 사용하며 충돌 대체물·절단 마개는 사용하지 않는다. 검의 직선과 만나는 몸통 뒤쪽 진입점부터 가장 먼 앞쪽 피부 교차점까지를 측정해 `torso → torso` 관통을 확인했다. 이 수치는 칼끝이 화면에 실제로 보였다는 증거와 구분한다. 손·전완 축 차이는 제공 리그의 중립 축을 기준으로 하며 해부학적·임상적 손목 굽힘각이 아니다.

Penetration uses visible posed skin triangles, excluding collision proxies and severance caps. It measures from back-torso entry to the farthest forward skin crossing, confirming `torso → torso` penetration. This geometry result is distinct from rendered pixel visibility. The hand–forearm angle is relative to the supplied rig's neutral axis, not an anatomical or clinical wrist-flexion measurement.

초기 후보에서 칼이 머리 쪽을 향하던 방향을 수정했다. 이후 첫 실제 GPU 검사에서는 칼끝 중심의 준비 보간 때문에 팔과 어깨가 과도하게 움직여 실패했다. 최종본은 손잡이 원점 기준의 짧은 경로, 아래 30cm·뒤 10cm의 완만한 호와 바깥쪽 30cm 팔꿈치 방향으로 바꾸고, 실제 대기 어깨에서 시작해 새 대기 자세 회귀와 GPU 검사를 통과했다. 최종 관통축은 아래로 12°, 기본 롤은 130°이며 몸통을 우측으로 베어 나온다. 고정 그립을 유지하며 검날 길이축을 중심으로 한 번만 비튼다. 머리는 붙은 상태에서 전체 몸이 랙돌로 전환되고 사망·보상은 한 번만 발생한다.

An early candidate aimed toward the head. The first actual GPU check then failed because tip-anchored preparation interpolation overextended the arm and shoulder. The final version uses a compact grip-origin path, a 30cm-down/10cm-back arc and a 30cm outward elbow hint, starting from the actual idle shoulder; it passes both fresh-idle regression and GPU review. Final insertion uses a 12° downward axis and 130° base roll, followed by the rightward torso cut. It keeps the rigid grip and performs one blade-axis twist. Death transitions the whole body into ragdoll with the head attached and awards the result once.

## 실제 화면 검수 / Actual rendering review

최종 `through_twist_release_20260920`은 게시 범위의 실제 본편 코드만 반영한 격리 복사본에서 embedded Vulkan으로 촬영했다. 960×540, 30fps, 9초·270프레임이며 물리는 60Hz다. [검사 로그](render_checks.log)와 [전체 촬영 매니페스트](capture_manifest.json.gz)에 성공 상태·원본 해시·실제 배우 상태·매 프레임 측정을 보존한다. 핵심 검사 수치는 [geometry_checks.json](geometry_checks.json)에 별도로 보존한다. 핵심의 반대편 돌출 0.37184–0.40671m와 실제 GPU의 0.375425–0.410937m는 각각의 실제 자세에서 측정한 결과다. [소스 대조 기록](scoped_source_verification.json)은 작업 범위·게시본·렌더에 사용된 본편 바이트 일치를 확인한다. [영상 검사](video_validation.json)와 [디코드 로그](video_decode.log)에서 MP4 전체 270프레임이 정상 디코드됨을 확인했다.

Final `through_twist_release_20260920` rendered an isolated copy of the scoped production code through embedded Vulkan: 960×540, 30fps, nine seconds/270 frames with 60Hz physics. The linked log and compressed full manifest preserve pass status, source hashes, actual actor state and frame measurements; the geometry JSON separately preserves core checks. Core exit protrusion of 0.37184–0.40671m and GPU protrusion of 0.375425–0.410937m belong to their respective actual poses. The linked source-verification record confirms matching scoped production bytes across the task, publication copy and render. Video validation and decode logs confirm all 270 MP4 frames decode successfully.

[전체 9초 영상](rear_sword_through_twist.mp4)은 실제 플레이어와 살아 있는 크리프 AI로 실행한 관통·비틀기·우측 발검·머리 유지 랙돌, 이후 경계 대상의 제압 거절을 담는다. 강제 피해·사망이나 생성 이미지를 대체 사용하지 않았다. 준비·찌르기·비틀기·발검·사망·복귀 화면과 동일한 물리 자세의 정면·측면을 직접 열어 검토했고, 칼끝이 목이나 머리가 아닌 몸통 반대편으로 나오는 것을 확인했다.

The full nine-second video uses the actual player and live Creep AI for the through-stab, twist, right cut-out and attached-head ragdoll, followed by alerted-target refusal. It does not substitute forced damage/death or generated imagery. Preparation, stab, twist, extraction, death and recovery frames, plus front/side views of the same physics pose, were opened and inspected. The blade emerges from the opposite torso, rather than the neck or head.

| 최종 GPU 측정 / Final GPU measurement | 결과 / Result |
|---|---|
| 깊은 찌르기 관입률·깊이 / Deep-stab insertion fraction/depth | 94.000003% / 0.982300m |
| 비틀기 후 유지 관입률·깊이 / Post-twist hold insertion fraction/depth | 93.995126% / 0.982249m |
| 반대편 몸통 칼끝 돌출 / Opposite-torso tip protrusion | 0.375425–0.410937m |
| 박힌 검/발검 주요 구간 실제 축 차이 최대 / Maximum embedded/extraction axis mismatch | 41.9204° |
| 전체 동작 관절 이동 최대 / Maximum whole-motion joint step | 0.116258m |
| 손 회전 단계 최대 / Maximum hand rotation step | 15.113° |
| 활성 동작 어깨 보정 최대 / Maximum active shoulder correction | 2.984 × 10⁻⁷m |
| 한 번 비틀기 / One twist | 44.99999° |
| 비틀기 전 박힌 검 회전 변화 / Embedded blade drift before twist | 0° |
| 원본·원정/가방·커서 보존 / Sources, session/inventory, cursor preserved | 모두 참 / all true |

검수 이미지 / Inspection images:

- [준비 / Preparation](rear_sword_prepare.png) · [깊은 찌르기 / Deep stab](rear_sword_stab.png) · [비틀기 시작 / Twist start](rear_sword_twist_start.png) · [비틀기 끝 / Twist end](rear_sword_twist_end.png)
- [우측 베기 / Right cut](rear_sword_slash.png) · [발검 완료 / Extraction](rear_sword_withdraw.png) · [머리 유지 랙돌 / Attached-head ragdoll](rear_sword_death.png) · [복귀 / Recovery](rear_sword_recovered.png)
- [찌르기 정면 / Stab front](rear_sword_stab_front.png) · [찌르기 측면 / Stab side](rear_sword_stab_side.png) · [비튼 뒤 정면 / Hold front](rear_sword_hold_front.png) · [비튼 뒤 측면 / Hold side](rear_sword_hold_side.png)

## 검증 범위와 남은 한계 / Scope and remaining limitations

촬영에는 해당 작업의 게시 범위만 포함한 격리된 본편 코드를 사용했다. 원본 작업 공간의 무관한 동시 변경은 보존하고 이 검증 결과에 포함하지 않았다. 외부 정면·측면 카메라는 **같은 1인칭 검·팔과 몬스터의 관통 상태**를 확인하기 위한 것이다. 그 배경에 보이는 별도 전신 아바타의 대기 팔과 이 1인칭 제압을 통합하는 3인칭 모션은 이번 범위에 포함하지 않는다.

Rendering uses isolated production code scoped to this publication; unrelated concurrent workspace changes are preserved and excluded from these claims. External front/side cameras inspect **the same first-person sword/arm and monster penetration**. Third-person integration with the separate full-body avatar's idle arms visible in the background is outside this revision.

완료 후 시체를 확인하려고 3.5–4.3초에 카메라를 아래로 기울이는 부분만 촬영용 동작이며 새로운 본편 모션이 아니다. 자동 측정의 화면 투영은 가림 여부 자체를 증명하지 않으므로 실제 정면·측면 이미지 검토와 구분한다. 파크라이의 특정 동작·영상 프레임과 정확히 일치하는 모션을 복사하거나 검증한 것은 아니다. OS 하드웨어 E/마우스 입력은 미확인이다. 작업이 시작한 촬영 프로세스는 종료했고 기존 사용자 편집기는 유지했다. GitHub 반영은 최종 게시 기록을 따른다.

The post-action downward camera tilt at 3.5–4.3 seconds is inspection-only, not new gameplay motion. Frustum projection alone does not prove lack of occlusion, so it is distinct from actual front/side image review. No exact Far Cry motion/frame match is claimed. OS hardware E/mouse input remains unverified. Owned capture processes ended while the user editor was preserved. GitHub status follows the final publication record.
