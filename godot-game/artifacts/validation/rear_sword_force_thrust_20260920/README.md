# 후방 검 제압: 파지·전진·접촉 반응 / Rear sword takedown: grip, forward drive and contact response

검을 쥔 손과 팔이 실제로 앞으로 미는 흐름, 피부에 닿은 직후 시작하는 적의 반응, 손잡이를 가리지 않는 구도를 함께 수정했다. 기존 **깊은 관통 → 한 번 비틀기 → 플레이어 우측으로 베어 빼기 → 머리를 유지한 랙돌**은 유지한다.

This revision combines a firmer handle grip and readable forward arm drive with an enemy reaction that begins at skin contact and framing that exposes the handle. Preserve **deep through-stab → one twist → player-right extraction → intact-head ragdoll**.

## 검증 상태 / Validation status

**최종 자동 검사 5종, 실제 GPU 9초·270프레임 검수, 전체 영상 디코딩을 통과했다.** 파지 네 방향과 준비·접촉·관통·비틀기·우측 발검·복귀의 실제 스틸을 확인했다. 별도 검토자도 동작 중 프레임 43–105 구간의 표본과 측면·파지 화면을 독립적으로 열어 검토했으며, 이전 소매 가림이 제거되고 큰 팔꿈치 튐이나 손·검 분리가 보이지 않음을 확인했다. 넓은 원본 소매와 검지 간격은 남아 있는 외형 한계로 명시한다. **GitHub 원격 반영은 아직 미확인**이며 최종 게시 기록을 따른다.

**Final validation passed five automated suites, actual nine-second/270-frame GPU review and full-video decoding.** Four grip views and actual preparation/contact/penetration/twist/right-extraction/recovery stills were inspected. An independent reviewer opened samples from frames 43–105 plus side/grip views, confirming removal of the prior sleeve obstruction without a large elbow snap or hand/weapon detachment. The original wide sleeve and index spacing remain visual limitations. **GitHub publication remains unconfirmed** until the final remote record.

[전체 9초 영상 / Full nine-second video](rear_sword_force_thrust.mp4) · [핵심 검사 로그 / Core log](core_tests.log) · [관련 회귀 로그 / Regression log](regression_tests.log) · [핵심 측정 / Core measurements](core_report.json) · [실제 렌더 로그 / Render log](render.log) · [프레임별 실제 측정 / Capture manifest](capture_manifest.json) · [전체 디코딩 / Full decoding](video_decode.log)

| 최종 자동 검사 / Final automated suite | 결과 / Result |
|---|---|
| `rear_takedown` | PASS: 실제 피부 접촉·깊이별 반응, 관통·비틀기·우측 발검, 팔 연속성, 머리 유지·사망/보상 한 번, 충돌 취소와 일반 파지 복원 |
| `rear_takedown_trial` | PASS: 실제 F2·공개 E API, 미인지/경계/정면 조건, 일시정지·취소·재선택·초기화·원정 복원 |
| `supplied_fp_arms` | PASS: 공급 팔 어댑터 관련 회귀 |
| `creep_execution` | PASS: 기존 포복 크리프 처형 회귀 |
| `sword_shield_execution` | PASS: 기존 검·방패 처형 회귀 |

## 수정 내용 / Changes

- **파지:** 후방 제압에서만 62° 대각 파지를 사용하고 엄지를 검지 뿌리 바깥쪽으로 맞췄다. 네 손가락을 각각 조정해 손잡이를 감싸도록 한다. 원본 메시·텍스처·피부 영향과 손목/기준 축을 보존한다. 일반 대기·공격으로 돌아오면 전용 파지를 해제한다.
- **팔 전진과 구도:** 준비 공간 약 1.40m에서 앞으로 밀고 최종 간격은 약 0.985m로 둔다. 카메라 전진은 2.5cm로 줄여 적에게 붙는 카메라 이동이 팔 전진을 덮지 않게 한다. 준비 손잡이는 낮게, 박힌 동안 팔꿈치는 우측 아래로 연결한다.
- **회수 안정화:** 검을 뺄 때 비틀기 후 유지 자세의 안정된 팔꿈치 굽힘 방향을 현재 팔 축으로 운반한다. 마지막 자세에도 안정된 굽힘을 잡은 뒤 복귀하며, 팔 풀이의 방향이 바뀌는 지점에서 역방향으로 튀지 않게 한다. 실제 손목 기준과 고정된 팔 길이는 유지한다.
- **접촉 반응:** 첫 피부 접촉은 0.61초, 최대 깊이는 0.90초다. 접촉 전에는 반응하지 않고 접촉 후 작은 움찔을 빠르게 시작하며, 깊어지는 정도에 따라 몸 반응이 커진다. 최대 깊이에 도달할 때까지 반응을 기다리지 않는다.
- **유지한 기능:** 칼날 약 94% 관입과 몸통 반대편 칼끝, 검축으로 한 번 45° 비틀기, 플레이어 우측 발검, 실제 몸통 베기에서 한 번 사망·보상과 머리 유지 랙돌을 유지한다. E/F2·후방/미인지 조건·충돌 취소·원정 복원도 유지한다.

The rear-only 62° diagonal grip places the thumb outside the index root and adjusts each finger around the handle while retaining source assets, skin weights and wrist/neutral anchors. Ordinary ready/attack poses restore their original grip. Preparation creates approximately 1.40m of room and the thrust finishes around 0.985m away; reducing camera advance to 2.5cm exposes the arm drive. The embedded elbow bends down/right. Withdrawal transports the stable held elbow bend onto the current arm axis, with a stable end bend released into recovery rather than switching branches. First skin contact is authored at 0.61s and maximum depth at 0.90s: no pre-contact reaction, then a rapid small flinch increasing with insertion. Preserve approximately 94% penetration, one 45° twist, right extraction, one death/reward, intact-head ragdoll and existing E/F2/collision/session behavior.

## 실제 접촉과 반응 / Actual contact and reaction

핵심 검사는 변형된 실제 몸통 피부 삼각형과 표시되는 검날을 교차시켰다. 0.609초에는 칼끝이 피부 밖 약 2.58mm이며 몸 반응은 0이다. 0.61초 접촉 경계에서는 반응을 0에서 연속적으로 시작하고, 다음 60Hz 표본인 약 0.6267초에서 실제 흉부 회전 약 0.488°가 생긴다. 0.69초에는 약 3.508°, 0.90초 최대 깊이에는 약 9°다. 접촉 순간의 불연속적인 큰 점프나 사전 움찔 대신 깊이에 연결되는 반응이다.

The core check intersects actual posed torso triangles with the displayed blade. At 0.609s the tip is about 2.58mm outside skin and reaction is zero. Response starts continuously from zero at the 0.61s contact boundary; the next 60Hz sample, approximately 0.6267s, has about 0.488° actual chest rotation, rising to 3.508° at 0.69s and approximately 9° at maximum depth. This ties response to contact/depth rather than a large discontinuity or anticipatory flinch.

| 단계 / Stage | 1인칭 / First person | 측면 / Side | 정면 / Front | 파지 측면 / Grip side |
|---|---|---|---|---|
| 접촉 전 / Before contact | [보기](rear_sword_before_contact.png) | [보기](rear_sword_before_contact_side.png) | [보기](rear_sword_before_contact_front.png) | [보기](rear_sword_before_contact_grip_side.png) |
| 첫 접촉 직후 / First contact | [보기](rear_sword_first_contact.png) | [보기](rear_sword_first_contact_side.png) | [보기](rear_sword_first_contact_front.png) | [보기](rear_sword_first_contact_grip_side.png) |
| 깊어지는 반응 / Building recoil | [보기](rear_sword_recoil.png) | [보기](rear_sword_recoil_side.png) | [보기](rear_sword_recoil_front.png) | [보기](rear_sword_recoil_grip_side.png) |
| 최대 깊이 / Maximum depth | [보기](rear_sword_stab.png) | [보기](rear_sword_stab_side.png) | [보기](rear_sword_stab_front.png) | [보기](rear_sword_stab_grip_side.png) |
| 비틀기 후 유지 / Post-twist hold | [보기](rear_sword_hold.png) | [보기](rear_sword_hold_side.png) | [보기](rear_sword_hold_front.png) | [보기](rear_sword_hold_grip_side.png) |

[준비](rear_sword_prepare.png) · [찌르기 중간](rear_sword_thrust_mid.png) · [우측 베기](rear_sword_slash.png) · [사망](rear_sword_death.png) · [검 빼기](rear_sword_withdraw.png) · [발검 완료](rear_sword_cut_end.png) · [복귀](rear_sword_recovered.png) · [최종 랙돌](rear_sword_final.png) · [경계 상태 거절](alerted_denial_denied.png)

## 검증 수치와 범위 / Measurements and scope

| 항목 / Metric | 최종 핵심 검사 / Final core | 실제 GPU / Actual GPU |
|---|---|---|
| 관입 깊이 / Skin insertion | 약 0.98212m / ~93.9828% | 약 0.98224m / ~93.9940% |
| 몸통 반대편 칼끝 / Opposite torso tip | 약 0.27961m | 약 0.27515m |
| 활성 손 중립축·전완 차이 최대 / Maximum active neutral-hand/forearm mismatch | 34.7426° | 41.0141° |
| 연속 관절 이동 최대 / Maximum consecutive joint step | 0.088653m | 0.092928m |
| 손 회전 변화 최대 / Maximum hand-rotation step | 5.1446° | 5.5743° |
| 의도하지 않은 박힌 검 회전 / Unintended embedded blade drift | 0° | 0° |
| 의도한 단일 비틀기 / Intended single twist | 약 45° | 약 45° |
| 카메라–전완 중심선 최소 / Minimum camera–forearm-centerline distance | 활성 0.384415m / 준비 0.623671m | 활성 0.396474m / 준비 0.604890m |

핵심의 전체 동작은 196표본이며, 별도 새 대기 진입부터 준비 34표본은 최대 관절 이동 0.046235m·손 회전 0.8166°다. 실제 피부 교차는 입구·가장 먼 출구가 모두 몸통임을 확인하며, 충돌 대용 상자나 절단면을 출구로 대신하지 않는다. 표시된 GPU 검날은 약 1.045m다. 미인지 후방 시나리오는 처치 한 번, 경계 상태 시나리오는 제압 거절·처치 0회다. 머리 분리는 없다. 기존 12cm 관절 연속성·45° 손축 제한을 유지한다.

실제 렌더는 숨김 embedded Vulkan, 960×540, 물리 60Hz, 30fps·9초·270프레임이다. 같은 월드·물리 표본에서 카메라만 이동해 정면·측면·파지 측면을 촬영한다. 1인칭과 동일하게 별도 3인칭 몸 레이어를 제외한다. 사망·피해·포즈를 강제로 덮어씌우거나 이미지를 생성·합성·반전하지 않는다. 처치 완료 뒤 3.5–4.3초에는 바닥의 몸을 보여 주는 촬영용 아래 시선 이동만 있다. 원본 파일·세션·인벤토리·커서 보존은 모두 true다.

The full core trajectory has 196 samples; a separate 34-sample fresh-idle preparation records maximum joint step 0.046235m and hand rotation 0.8166°. Actual skin intersections identify both entry and farthest exit on torso skin, not proxy boxes or caps. The rendered blade is approximately 1.045m. The rear case has one kill, while the alerted control rejects with zero kills; no head separation occurs. Existing 12cm continuity and 45° hand-axis limits remain. Actual capture uses hidden embedded Vulkan at 960×540, 60Hz physics and 30fps for nine seconds/270 frames. Cameras share the same world/physics pose and exclude the separate third-person body layer like the main first-person view. No forced pose/death/damage, generated-image replacement, compositing or mirroring is used. Only the completed-kill inspection tilts downward during 3.5–4.3s. Sources, session, inventory and cursor are preserved.

## 파지 검수와 남은 한계 / Grip review and remaining limits

[파지 검수 기록](grip_review.json) · [측정값](grip_metrics.json) · [검사 코드](grip_validator.py) · [후보값](grip_candidate.json) · [실제 리그 추출](grip_rig_export.json)

같은 손·검 자세의 실제 네 방향 렌더: [각도 0](grip_1_view_0.png), [각도 1](grip_1_view_1.png), [각도 2](grip_1_view_2.png), [각도 3](grip_1_view_3.png).

선정한 다섯 손가락 쌍(검지–중지, 중지–약지, 약지–새끼, 엄지–검지, 엄지–중지)의 주 영향 피부 삼각형에서는 교차 0개를 확인했다. 이는 선택한 쌍·분류의 검사이며 모든 손 표면·완전한 닫힌 메시 사이의 무관통 증명이 아니다. 손잡이 단면 타원 근사에서 손바닥 정점 한 개는 약 3.19mm 안쪽에 남아 있다. **정확한 손잡이 메시와의 3.19mm 관통을 뜻하지는 않지만 접촉이 완벽하다고 보고하지 않는다.** 검지는 가드 쪽을 더 높게 잡으므로 중지와의 간격이 남는 대각 파지다. 검지 간격과 손 전체의 정밀 충돌은 남은 시각·검증 한계다.

손·전완 축 차이는 원본 리그 중립 기준이며 의학적 손목 굽힘각이 아니다. 카메라–전완 중심선 거리도 정확한 소매 표면 충돌 검사를 대신하지 않는다. 3인칭 전신 모션, 일반 대기 파지의 기존 접촉 문제, 역사적 무술의 정확한 복제, 하드웨어 E/마우스 입력은 이번 완료 범위에 넣지 않는다. OS 포커스·커서·마우스 캡처·오디오 재생을 방해하지 않는 방식으로 실행했다.

Selected dominant-skin triangles for five digit pairs—index/middle, middle/ring, ring/little, thumb/index and thumb/middle—have zero measured crossings. This is not an exhaustive closed-mesh or all-surface nonintersection proof. One palm vertex remains approximately 3.19mm inside the elliptical handle-section proxy. **That is not an exact 3.19mm intersection with the true handle mesh, but contact is not claimed flawless.** The index remains higher toward the guard, leaving spacing from the middle finger in this diagonal grip. Index spacing and exhaustive hand collision remain limitations. Hand/forearm-axis differences are rig-neutral diagnostics, not clinical wrist angles, and camera/forearm-centerline distances do not replace exact sleeve collision checks. Third-person full-body animation, ordinary-ready grip contact issues, exact historical technique and OS hardware input are outside completion scope. Execution does not disrupt OS focus, cursor, mouse capture or audible playback.
