# 후방 제압: 찌르기·비틀기 반응과 혈흔 / Rear takedown: stab/twist response and blood

**로컬 최종 핵심 검사와 실제 GPU 9초·270프레임 검수, 전체 영상 디코딩을 통과했다.** 실제 F2 및 관련 회귀의 통과 기록은 아래 실행 시점을 구분한다. **실제 이미지 25장·연속 표본의 독립 시각 검수도 완료했다. GitHub 원격 반영은 확인 대기다.** [시각 검수 기록](visual_review.json)

**Local final core checks, actual nine-second/270-frame GPU checks and full-video decoding passed.** Real F2 and related regressions are distinguished by run below. **Independent review of 25 actual images and sequence samples is complete; GitHub publication remains pending.** [Visual review](visual_review.json)

[전체 영상 / Full video](rear_stab_reaction_blood.mp4) · [GPU 측정 / Capture manifest](capture_manifest.json) · [렌더 로그 / GPU log](gpu_preview.log) · [270프레임 디코딩 / Full decode](video_decode.log) · [검증 코드 일치 / Validated-source match](source_validation_match.json)

## 변경 / Change

첫 실제 피부 접촉에서 **3D 월드 혈흔을 한 번** 발생시킨다. 깊게 찌를 때 몸통은 크게 움찔하고, 박힌 검을 짧게 한 번 비틀면 작은 추가 반응을 준다. 검은 이후 같은 축으로 뽑으며 칼끝이 빠진 뒤 머리를 유지한 몸 전체의 랙돌을 시작한다. 옆 베기와 참수는 추가하지 않았다.

제작 시계는 준비 0.55초, 접촉·혈흔 0.61초, 최대 깊이·사망 0.90초, 1.00–1.22초 손·검 20° 한 번 비틀기, 회수 시작 1.30초, 칼끝 빠짐·랙돌 1.90초, 복귀 1.96–2.46초다. 몸통은 깊은 찌르기에서 약 15° 기울고, 비틀기에는 약 -8° 몸통 회전과 작은 3° 추가 기울기 펄스를 사용한다. 이는 원본 리그의 제작 각도이며 의학적 관절 각도가 아니다. 약 94% 관입, 사망·보상 한 번, 후퇴하며 직선 회수하는 파지와 E/F2·원정 복원을 유지한다.

Emit **one 3D world-space blood burst** at actual first skin contact. The deep stab creates a strong body flinch; one brief blade twist adds a smaller response. Then withdraw along the blade axis and release the intact-head ragdoll only after tip clearance. No lateral cut or decapitation. Authored timing is preparation 0.55s, contact/blood 0.61s, deep-stab/death 0.90s, one 20° hand/blade twist at 1.00–1.22s, withdrawal 1.30s, clearance/ragdoll 1.90s and recovery 1.96–2.46s. The chest bends approximately 15° at depth; twist adds approximately -8° torso yaw and a small 3° pitch/tilt pulse. These are asset-production angles, not clinical joint measurements. Retain approximately 94% depth, one death/reward, retreat-assisted straight withdrawal and E/F2/session behavior.

## 검사 근거 / Verification evidence

| 검사 / Check | 기록과 범위 / Evidence and scope |
|---|---|
| 최종 핵심 / Final core | [core04](core_pass.log): 최종 몸통 회전·캐시 보정 뒤 PASS. 실제 접촉·혈흔 1회·반응·짧은 비틀기·직선 회수·칼끝 제거 후 랙돌·충돌 취소·원정 보존 |
| 실제 F2 / Real F2 | [core03의 F2 검사](trial_pass.log): 공개 E·미인지/경계/정면·정지·취소·재생성·혈흔 정리·원정 복원 PASS |
| 관련 회귀 / Related regressions | [tests02](regression_pass.log): `creep_execution`, `supplied_fp_arms`, `sword_shield_execution` 각 PASS. 후속 후방 제압 캐시·회전 조정 전 실행 |
| 최종 실제 GPU / Final actual GPU | 960×540 Vulkan, 60Hz 물리, 30fps·9초·270프레임, 실패 0개·실제 PNG 58장·전체 MP4 디코딩 PASS |

위 기록은 다섯 고유 검사 항목의 통과를 각각 보존한다. 과거 묶음 실행에 포함됐던 후방 제압 실패를 전체 통과로 바꾸어 보고하지 않는다. 후속 회전·캐시 수정은 최종 core04와 최종 GPU에서 검증했다.

These records preserve five distinct passing checks at their actual run points, not a claim that every historical batch passed. Subsequent rear-takedown cache/yaw changes were verified by final core04 and final GPU capture; the three related regression passes precede those narrow adjustments.

최종 GPU에서 최초 혈흔 표본은 동작 0.616667초(접촉 기준 0.61초), 사망은 0.90초, 랙돌 해제는 1.90초다. 혈흔은 24개의 실제 물방울과 최대 8개 얼룩으로 구성되며 약 6초 수명이다. 핵심 검사에서 6.01초 모의 진행 뒤 제거를 확인했고 실제 F2의 일시정지·초기화 정리도 검사했다. 미인지 후방은 처치 한 번, 경계 비교는 제압 거절·처치 0회다. 원본·세션·인벤토리·커서는 보존했다.

GPU의 최대 활성 손·전완 축 차이는 38.5686°, 관절 이동 0.09277m, 손 회전 변화 2.2680°, 칼끝의 축 옆 방향 차이는 약 0.166mm다. 이것은 자세·연속성 지표이며 손 전체의 정확한 표면 충돌을 입증하지 않는다.

Final GPU first records blood at action time 0.616667s after the 0.61s contact threshold; death is at 0.90s and ragdoll release at 1.90s. The effect uses 24 real droplets and at most eight stains with an approximately six-second lifetime. Core simulation confirms cleanup after 6.01s; real F2 pause/reset cleanup was also checked. The rear case kills once; the alerted control rejects with zero kills. Sources, session, inventory and cursor are preserved. GPU maxima are 38.5686° active hand/forearm-axis difference, 0.09277m joint step and 2.2680° hand rotation, with about 0.166mm lateral blade-tip deviation. These diagnose pose continuity, not exhaustive surface collision.

## 실제 화면 / Actual views

| 순간 / Stage | 1인칭 / First person | 측면 / Side | 정면 / Front |
|---|---|---|---|
| 접촉 혈흔 / Contact blood | [보기](rear_sword_impact.png) | [보기](rear_sword_impact_side.png) | [보기](rear_sword_impact_front.png) |
| 깊은 찌르기 / Deep stab | [보기](rear_sword_stab.png) | [보기](rear_sword_stab_side.png) | [보기](rear_sword_stab_front.png) |
| 비틀기 중간 / Mid-twist | [보기](rear_sword_twist_mid.png) | [보기](rear_sword_twist_mid_side.png) | [보기](rear_sword_twist_mid_front.png) |
| 비틀기 끝 / Twist end | [보기](rear_sword_twist_end.png) | [보기](rear_sword_twist_end_side.png) | [보기](rear_sword_twist_end_front.png) |

영상의 약 1.20–1.47초에 작은 짙은 붉은 방울이 보인다. 비틀기 반응은 1인칭보다 측면에서 더 분명하다. 같은 월드·자세를 카메라만 옮겨 촬영하며 화면 합성이나 생성 이미지로 대체하지 않는다.

Small dark-red droplets are visible at approximately video time 1.20–1.47s. Twist response reads more clearly from the side than first person. Inspection views move only the camera around the same world/pose; no generated-image replacement or compositing is used.

## 한계 / Limits

혈흔은 짧은 3D 물방울·얼룩 효과이며 연속적인 유체막 시뮬레이션이 아니다. 실제 시험 스튜디오 렌더를 검증했으며 동굴 실게임 수동 촬영이나 하드웨어 E/마우스 조작 검증은 하지 않았다. 기존 넓은 소매·검지 간격·손 전체 정밀 충돌 검사의 한계는 유지한다. 독립 검토·원격 게시 상태는 위 상태 항목을 따른다.

Blood is a brief 3D droplet/stain effect, not continuous fluid-film simulation. Verification uses the actual test studio, not a manually controlled cave capture or OS hardware E/mouse test. Existing wide-sleeve/index-spacing and exhaustive hand-collision limits remain. Independent-review/publication status follows the status above.
