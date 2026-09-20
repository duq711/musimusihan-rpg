# 후방 검 제압: 중단 직선 찌르기 / Rear sword takedown: middle-guard straight thrust

2026-09-20 사용자 첨부 도식의 **가운데 왼쪽, 중단에서 곧게 찌르는 그림**을 주 참고로 삼았다. 손·전완·검이 목표로 이어지는 동작을 반영하고, 도식의 방패·의상·다른 찌르기들을 섞지 않는다. 기존 깊은 관통 → 한 번 비틀기 → 플레이어 우측 베기와 머리를 유지한 랙돌은 유지한다.

The primary reference is the user's **middle-left drawing of a straight thrust from middle guard**. It guides the hand/forearm/blade line, without combining the shield, costume or other illustrated attacks. Retain the deep through-stab, one twist, player-right extraction and intact-head ragdoll.

## 현재 검증 상태 / Current validation status

**최종 코드 자동 검사 5종과 실제 GPU 9초·270프레임 검수를 통과했다.** 준비·찌르기 중간·깊은 찌르기·비틀기 후 유지·우측 베기·발검·복귀의 실제 1인칭 및 정면·측면 스틸을 열어 확인했다. 앞선 후보에서 발견한 소매 내부 노출은 준비 손잡이를 낮추고 찌르기 선을 바꾼 최종 렌더에서 제거됨을 확인했다. 전체 영상의 270프레임 디코딩도 통과했다. 별도 검토자도 동작 전 구간의 표본 프레임 22장과 정면·측면·파지 측면 스틸을 독립적으로 확인했으며, 소매의 카메라 관통·큰 팔 교차·역방향 튐을 추가 결함으로 발견하지 않았다. **GitHub 구현 커밋 `c675082`과 영상·이미지 LFS 37개를 원격에서 다시 받아 확인했다.** [게시 검증 기록](publication_verified.json)을 따른다.

**Final code passed five automated suites and nine seconds/270 frames of actual GPU checks.** Actual first-person and front/side stills were opened across preparation, mid-thrust, deep stab, post-twist hold, right cut, withdrawal and recovery. Lowering the preparation hilt and changing the thrust line removed the earlier candidate's sleeve-interior exposure in the final renders. The full 270-frame video decoded successfully. A separate reviewer independently inspected 22 sampled frames spanning the action and front/side/grip stills, finding no remaining blocking sleeve/camera intersection, large arm crossing or reverse snap. **Implementation commit `c675082` and all 37 video/image LFS objects were fetched again and verified against GitHub.** See the [publication verification](publication_verified.json).

[전체 9초 영상 / Full nine-second video](rear_sword_middle_thrust.mp4) · [GPU 실행 로그](gpu_render.log) · [270프레임 디코드 로그](video_decode.log) · [프레임별 원본 측정](capture_manifest.json)

## 원인과 변경 / Cause and change

- 기존 파지는 손·검이 거의 직각인 망치식 관계였으며, 배치 원점과 실제 손목 관절 사이에 약 2.54cm 차이가 있었다. 준비 팔꿈치 방향을 선형 보간하면 가까운 자세에서 방향이 뒤집힐 수 있었다.
- 후방 제압에서만 50° 대각 파지와 약 19mm 손잡이 접촉면 보정, 손가락별 굽힘·벌림을 적용한다. 실제 손목 관절에서 고정된 팔 길이를 풀고, 팔꿈치 방향을 운반한 뒤 회전시킨다. 대기·일반 공격으로 돌아오면 전용 파지를 해제한다.
- 0.55초 준비 동안 충돌을 검사하며 적과 약 1.40m 공간을 확보한 뒤 0.90초까지 0.78m 간격으로 전진 찌른다. 가까운 시작에서는 필요한 만큼 먼저 물러난다. 16cm 좌측 시선 보정으로 어깨·전완을 찌르기 선 쪽으로 향하게 한다. 최종 검 진행선은 적의 전방축에서 좌향 20°·상향 12°이며, 검축 회전 기준값은 180°다. 준비 손잡이를 낮춰 팔과 소매가 카메라를 지나가지 않게 한다.
- 94% 관입과 반대편 칼끝을 유지한다. 1.02–1.34초 검날 축으로 45° 한 번 비틀고, 1.44–2.20초 우측으로 베어 뺀다. 1.70초 실제 몸통 베기에서 사망·보상 한 번, 2.32초 여운 끝, 2.84초 복귀다. 머리 절단은 하지 않는다.
- 원본 모델·텍스처·피부 영향·팔 길이와 E/F2 조건, 별도 시험 원정 복원을 유지한다. 준비 후퇴 또는 찌르기 전진이 막히면 접촉 전에 취소한다.

The original hand/blade relationship was almost perpendicular, and the placement origin differed from the actual wrist by approximately 2.54cm. Linear elbow-direction blending could flip the preparation pole. The rear-only 50° diagonal grip, approximately 19mm handle-contact adjustment and individual finger curl/spread use the real wrist with fixed limb lengths. Transporting then rotating the elbow direction avoids that interpolation flip; ordinary ready/attack poses restore their original grip. Collision-tested preparation creates 1.40m of space by 0.55s, then advances toward 0.78m by the 0.90s thrust. A 16cm leftward focus offset directs the arm toward the stab line. The final blade line is 20° left and 12° up from enemy forward, with a 180° blade-roll reference. Lowering the preparation hilt routes the arm and sleeve clear of the camera. Retain 94% insertion, one 45° twist at 1.02–1.34s, right extraction at 1.44–2.20s, one fatal torso cut/reward at 1.70s and recovery by 2.84s. Source assets, weights, lengths and E/F2/session behavior remain.

## 자동 검사 / Automated checks

[전체 자동 검사 로그](headless_checks.log), [실제 관절·피부 교차 측정](geometry_checks.json).

| 검사 / Suite | 결과 / Result |
|---|---|
| `rear_takedown` | PASS: 미인지 후방 조건, 가까운/먼 시작, 실제 피부의 깊은 관통, 한 번 비틀기, 우측 발검, 머리 유지·사망·보상 한 번, 취소·복원 |
| `rear_takedown_trial` | PASS: 실제 F2 미인지·경계·정면 시험, 공개 E API, 정지·취소·재선택·초기화·원정 복원 |
| `supplied_fp_arms` | PASS: 공급 팔 어댑터 관련 회귀 |
| `creep_execution` | PASS: 기존 포복 크리프 처형 관련 회귀 |
| `sword_shield_execution` | PASS: 기존 검·방패 처형 관련 회귀 |

새로 초기화한 대기 자세부터 준비 동작을 검사한 34표본의 최대 관절 이동은 0.045250m, 손 회전 변화는 6.4512°다. 전체 동작 193표본에서는 최대 관절 이동 0.078482m, 손 회전 변화 6.7101°, 박힌 구간의 실제 손 중립축·전완축 차이 최대 35.5282°다. 박힌 칼의 의도하지 않은 방향 변화는 0°, 의도한 단일 비틀기는 약 45°다. 팔꿈치·손목의 연속 표본 한계는 기존 검사의 12cm·45°를 유지했다.

실제 검날 약 1.045m 중 0.9823m를 등 피부 기준으로 넣는다. 교차 검사는 충돌 대용 도형이 아니라 현재 변형된 몸통의 피부 삼각형에서 입구·가장 먼 앞쪽 출구를 찾는다. 준비 후퇴 차단은 0.2667초, 전진 차단은 0.5833초에 찌르기 접촉 없이 취소했다. 1.71초의 큰 단일 시간 간격으로 진행해도 뒤쪽 벽에 필요한 후퇴가 막히면 찌르기·보상 없이 취소한다. 후방 제압 이후 일반 공격 80표본에서는 제압 전용 파지가 남지 않음을 확인했다.

Fresh-idle preparation covers 34 samples, with maximum joint step 0.045250m and hand rotation step 6.4512°. The 193-sample complete action records 0.078482m, 6.7101° and maximum embedded actual hand-neutral/forearm-axis difference 35.5282°. Unintended embedded blade drift is 0°, while the intended single twist reaches approximately 45°. Existing 12cm/45° continuity limits were retained. Actual posed torso-skin triangles establish approximately 0.9823m insertion of a 1.045m blade; the farthest forward crossing identifies the exit. Blocked retreat and approach cancel at 0.2667s and 0.5833s before stab contact. A 1.71s single-step regression also cancels without stabbing/reward when the required retreat is blocked. Eighty ordinary-attack samples verify removal of the rear-only grip.

## 실제 GPU·영상 검수 / Actual GPU and video review

최종 `middle_thrust_20260920_final`은 실제 Vulkan 렌더러의 숨김 embedded 실행으로 촬영했다. 960×540, 실제 60Hz 물리, 30fps·9초·270프레임이다. 미인지 후방은 실제 제작 동작으로 한 번 처치했고, 경계 상태 비교는 제압 거절·처치 0회를 확인했다. 강제 피해·사망·자세 교체·이미지 합성 없이 같은 게임 코드·리그·무기를 촬영했다. 정면·측면·파지 측면은 동일 월드·동일 물리 표본의 카메라만 바꾼 실제 렌더이며 좌우 반전하지 않았다.

| 단계 / Stage | 1인칭 / First person | 측면 / Side | 정면 / Front | 파지 측면 / Grip side |
|---|---|---|---|---|
| 준비 / Preparation | [보기](rear_sword_prepare.png) | [보기](rear_sword_prepare_side.png) | [보기](rear_sword_prepare_front.png) | [보기](rear_sword_prepare_grip_side.png) |
| 찌르기 중간 / Mid-thrust | [보기](rear_sword_thrust_mid.png) | [보기](rear_sword_thrust_mid_side.png) | [보기](rear_sword_thrust_mid_front.png) | [보기](rear_sword_thrust_mid_grip_side.png) |
| 깊은 찌르기 / Deep stab | [보기](rear_sword_stab.png) | [보기](rear_sword_stab_side.png) | [보기](rear_sword_stab_front.png) | [보기](rear_sword_stab_grip_side.png) |
| 비틀기 후 / Post-twist hold | [보기](rear_sword_hold.png) | [보기](rear_sword_hold_side.png) | [보기](rear_sword_hold_front.png) | [보기](rear_sword_hold_grip_side.png) |

[우측 베기](rear_sword_slash.png), [사망](rear_sword_death.png), [검 빼기](rear_sword_withdraw.png), [발검 완료](rear_sword_cut_end.png), [복귀](rear_sword_recovered.png), [최종 머리 유지 랙돌](rear_sword_final.png), [경계 상태 거절](alerted_denial_denied.png).

| 최종 실제 GPU 측정 / Final actual GPU metric | 결과 / Result |
|---|---|
| 실제 피부 기준 관입 / Actual-skin insertion | 0.9823m, 검날의 약 94% / approximately 94% of blade |
| 찌르기 지점 몸통 두께·반대편 칼끝 / Torso thickness and opposite tip | 약 0.68066m / 0.30164m, 입구·출구 모두 몸통 / both crossings torso |
| 활성 손 중립축·전완축 차이 / Active neutral-hand/forearm mismatch | 최대 26.6389° / maximum |
| 연속 관절 이동·손 회전 / Joint and hand-rotation step | 최대 0.083612m / 6.4508° |
| 의도하지 않은 검 방향 변화 / Unintended embedded blade drift | 0°, 의도한 단일 비틀기 약 45° / intended single twist approximately 45° |
| 카메라–전완 중심선 최소 거리 / Minimum camera–forearm-centerline distance | 활성 0.280397m, 준비 0.541105m / active, preparation |
| 세션·인벤토리·커서·원본 보존 / Session, inventory, cursor and sources preserved | 모두 true / all true |

카메라–전완 값은 실제 팔꿈치·손목으로 계산한 **중심선 대용 지표**이며 소매 피부의 정확한 충돌 증명이 아니다. 그래서 찌르기 중간 실제 스틸을 따로 열어 소매 내부 노출이 사라졌는지 확인했다. 3.5–4.3초에는 처치가 완료된 뒤 쓰러진 몸을 보여 주기 위한 촬영용 아래 시선 이동만 추가했다. 이 시선 이동은 본편 제압 모션 수정이 아니다. 소리·OS 입력·사용자 포커스·마우스 캡처를 사용하지 않았다.

The final hidden embedded Vulkan capture runs actual 60Hz physics at 960×540 and records 270 frames at 30fps for nine seconds. Production rear takedown commits one kill; the alerted control rejects with zero kills. No damage/death/pose forcing, compositing or mirroring is used. Inspection cameras observe the same world and exact physics pose. Actual-skin insertion is 0.9823m, approximately 94%; torso thickness is about 0.68066m with 0.30164m tip protrusion, both crossings on torso skin. Maximum active neutral-hand/forearm mismatch is 26.6389°, joint step 0.083612m and hand-rotation step 6.4508°. Embedded drift is zero with one approximately 45° twist. Minimum camera–actual-forearm-centerline distance is 0.280397m active and 0.541105m during preparation. These are centerline proxies, not exact sleeve collision tests; actual mid-thrust images were separately inspected. A capture-only downward camera tilt during 3.5–4.3s inspects the already defeated corpse. No audible playback, OS input, focus changes or mouse capture was used.

## 파지 근접 검수 / Grip closeups

[측정 JSON](thrust-grip-surface-validation.json), [측정 코드](thrust_candidate_probe.gd), [렌더 코드](thrust_grip_closeup.gd), [렌더 로그](thrust-grip-closeup-console.log).

| 자세 / Pose | 실제 렌더 / Actual renders |
|---|---|
| 기존 대기 파지 / Existing ready grip | [각도 0](grip_0_view_0.png), [각도 1](grip_0_view_1.png), [각도 2](grip_0_view_2.png), [각도 3](grip_0_view_3.png) |
| 새 중단 파지 / New middle-guard grip | [각도 0](grip_1_view_0.png), [각도 1](grip_1_view_1.png), [각도 2](grip_1_view_2.png), [각도 3](grip_1_view_3.png) |

실제 변형된 손 피부 정점을 손잡이 단면의 타원 근사(반경 22.5mm·15.4mm)와 비교했다. 새 파지에서는 모든 손가락·손바닥에서 정규화 반경 0.8보다 안쪽인 정점이 0개다. 이는 깊은 겹침을 찾는 보조 지표이며 **실제 닫힌 손·손잡이 메시 사이의 정확한 접촉/관통 검사나 모든 표면의 무결함 증명은 아니다.** 새 파지의 손목 API 위치와 실제 리그 위치를 별도로 검사했고, 파지량 0으로 복귀하면 실제 손·손가락 뼈 자세가 원래대로 돌아온다. 기존 일반 대기 파지에서 보이는 접촉 문제는 이번 후방 제압 변경의 수정 완료 대상으로 확대하지 않는다.

Actual deformed hand vertices are compared against an elliptical approximation of the handle cross-section, radii 22.5mm/15.4mm. The new grip has zero finger/palm vertices below normalized radius 0.8. This is an auxiliary deep-overlap measure, **not exact closed-mesh contact/collision proof or evidence of flawless surfaces**. Wrist API/actual-rig positions are checked separately, and amount zero restores hand/finger bone poses. Existing ordinary-ready grip contact issues are not claimed as fixed by this rear-takedown change.

## 확인 범위와 한계 / Scope and limitations

손·전완 축 차이는 리그 중립 기준 지표이며 임상적 손목 굽힘각이 아니다. 그림의 역사적 기술을 정확히 복제했다거나 의학적 인체공학을 검증했다는 주장은 하지 않는다. 측면 검수 카메라는 본 1인칭 카메라와 동일하게 별도 3인칭 몸 레이어를 제외하며 실제 동일한 1인칭 팔·검 자세를 본다. 별도 3인칭 캐릭터의 전신 모션 개선은 이번 범위가 아니다. 공개 E API/F2 자동 실행은 OS 하드웨어 E/마우스 입력 검증과 구분하며, 하드웨어 입력은 미확인이다. 원격 게시 상태는 위 상태 항목을 따른다. 일반 대기 파지의 기존 접촉 문제와 별도 3인칭 전신 모션은 이번 결과의 완료 범위가 아니다.

Axis differences are rig-neutral diagnostics, not clinical wrist-flexion measurements. Exact historical martial-technique reproduction and medical ergonomics are not claimed. Side inspection cameras exclude the separate third-person body layer just like the main first-person view, observing the same actual first-person arm/sword pose. Full third-person character animation is outside scope. Public E API/F2 checks do not verify OS hardware keyboard/mouse routing; hardware input remains unverified. Remote publication follows the status above. Existing ordinary-ready grip contact issues and full third-person body animation are outside this completion scope.
