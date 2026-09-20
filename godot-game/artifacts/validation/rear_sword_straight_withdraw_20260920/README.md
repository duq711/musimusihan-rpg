# 후방 검 제압: 찌른 뒤 직선 회수 / Rear sword takedown: stab and axial withdrawal

**자동 검사 5종, 실제 GPU 9초·270프레임 검수와 전체 영상 디코딩을 통과했다. GitHub 브랜치의 커밋과 검수 이미지·영상 47개를 다시 내려받아 일치를 확인했다.** 이전 비틀기·우측 베기 개정의 검수 결과를 이번 직선 회수의 완료 근거로 재사용하지 않는다.

**Five automated suites, actual nine-second/270-frame GPU review and full-video decoding passed. The GitHub branch SHA and all 47 inspection images/video files were verified through fresh remote downloads.** Earlier twist/right-cut evidence does not validate this changed sequence.

## 변경 / Change

깊게 찌른 뒤 **비틀지 않고, 옆으로 베지 않고, 박힌 검 축 그대로 뒤로 뽑는다.** 회수할 때 플레이어도 충돌을 검사하며 물러나 팔이 닿는 범위와 파지를 유지한다. 칼날 약 94% 관입, 첫 피부 접촉 반응과 깊이에 따른 몸 반응, 기존 손잡이 파지는 유지한다.

최대 깊이에서 한 번 사망·보상을 확정하되, 검이 박힌 동안 몸을 유지한다. 칼끝이 몸 밖으로 빠진 뒤 머리가 붙은 몸 전체의 랙돌을 시작한다. 제작 시계는 준비 0.55초 → 첫 접촉 0.61초 → 최대 깊이·사망 0.90초 → 회수 시작 1.10초 → 칼끝 빠짐·랙돌 1.70초 → 복귀 시작 1.76초 → 종료 2.26초다. 기존 E/F2 조건, 일시정지·회복·재선택·취소·원정 복원을 유지한다.

After the deep stab, **remove twisting and sideways cutting; pull back along the embedded blade axis.** The player retreats with collision checks to retain arm reach and grip. Preserve approximately 94% insertion, actual-contact/depth-linked response and the existing handle grip. Commit one death/reward at full depth, hold the body while the blade remains inserted, then release the intact-head ragdoll after tip clearance. The authored clock is preparation 0.55s, contact 0.61s, full-depth/death 0.90s, withdrawal 1.10s, clearance/ragdoll 1.70s, recovery 1.76s and finish 2.26s. Existing E/F2 eligibility and session controls remain.

## 자동 검사 / Automated checks

[핵심·실제 F2 로그 / Core and F2 log](core_tests.log) · [실제 관절·피부 측정 / Geometry report](core_report.json) · [관련 회귀 로그 / Regression log](regression_tests.log)

| 검사 / Suite | 결과 / Result |
|---|---|
| `rear_takedown` | PASS: 실제 피부 관입, 직선 회수·칼끝 빠진 뒤 랙돌, 팔 연속성, 단일 사망·보상, 가까운/먼 시작·차단 취소 |
| `rear_takedown_trial` | PASS: 실제 F2·공개 E API, 미인지/경계/정면, 일시정지·취소·재선택·초기화·원정 복원 |
| `supplied_fp_arms` | PASS: 공급 팔 어댑터 회귀 |
| `creep_execution` | PASS: 기존 포복 크리프 처형 회귀 |
| `sword_shield_execution` | PASS: 기존 검·방패 처형 회귀 |

실제 변형된 몸통 피부에서 관입 약 0.98212m(칼날 약 93.9828%)와 반대편 칼끝 약 0.27961m를 측정했다. 입구·가장 먼 출구는 모두 몸통이다. 회수 후 칼끝은 입구보다 약 6cm 뒤, 플레이어 간격은 약 1.40m다. 전체 152표본에서 원래 찌르기 축과 칼끝의 최대 옆 방향 차이는 약 0.166mm이고 검의 고정 회전 변화는 0°다. 최대 연속 관절 이동 0.088654m, 손 회전 변화 0.8099°를 확인했다. 별도 새 대기 준비 34표본도 검사했다. 이 수치와 실제 렌더 확인을 구분하며 아래에 화면 검수를 기록한다.

Actual posed torso-skin measurements show about 0.98212m insertion (93.9828% of blade) and 0.27961m opposite-side protrusion, with both entry and farthest exit on torso. Withdrawal places the tip approximately 6cm behind the entry and returns the player to about 1.40m spacing. Across 152 samples, maximum lateral deviation from the original thrust axis is about 0.166mm and fixed-blade rotation change is 0°. Maximum consecutive joint step is 0.088654m and hand rotation 0.8099°; separate fresh-idle preparation covers 34 samples. These automated measurements are distinct from the actual visual review recorded below.

## 실제 화면 자료 / Actual visual evidence

[전체 9초 영상 / Full video](rear_sword_straight_withdraw.mp4) · [촬영 측정 / Capture manifest](capture_manifest.json) · [렌더 로그 / Render log](render.log) · [270프레임 디코딩 / Full decoding](video_decode.log)

실제 GPU 검수는 270프레임·9초, 실패 0개다. 깊은 찌르기·회수 중간·칼끝 빠짐·복귀와 해당 측면을 열어, 검이 같은 축으로 빠지고 손·팔이 연결되며 칼끝이 빠진 뒤 몸이 떨어지는 것을 확인했다. 실제 랙돌 해제는 동작 1.70초, 이때 칼끝은 입구 기준 -0.060000028m다. 고정 검 회전 변화 0°, 최대 옆 방향 편차 약 0.166mm이며 머리 유지·처치 한 번이다. 전체 MP4 270프레임 디코딩도 통과했다. 별도 검토자도 원본 20프레임과 측면에서 큰 팔꿈치 반전·소매 가림 없이 직선 회수 후 쓰러짐을 확인했다. [독립 검수 기록](visual_review.json).

| 단계 / Stage | 1인칭 / First person | 측면 / Side |
|---|---|---|
| 깊은 찌르기 / Deep stab | [보기](rear_sword_stab.png) | [보기](rear_sword_stab_side.png) |
| 직선 회수 / Axial withdrawal | [보기](rear_sword_withdraw_mid.png) | [보기](rear_sword_withdraw_mid_side.png) |
| 칼끝 빠짐 / Tip clearance | [보기](rear_sword_clear.png) | [보기](rear_sword_clear_side.png) |
| 복귀 / Recovery | [보기](rear_sword_recover.png) | [보기](rear_sword_recover_side.png) |

Actual GPU review records nine seconds/270 frames with zero failures. Opened deep-stab, mid-withdrawal, tip-clearance and recovery views, including side views, show fixed-axis extraction, a connected hand/arm and falling only after tip clearance. Ragdoll releases at action time 1.70s with tip depth -0.060000028m relative to the entry. Fixed blade rotation is 0° and maximum lateral deviation approximately 0.166mm; the head stays attached with one kill. Full 270-frame MP4 decoding passed. An independent review of 20 original frames and side views also confirms axial extraction followed by collapse, without a gross elbow flip or sleeve obstruction. See the [review record](visual_review.json).

## 한계 / Limitations

손·전완 축 수치는 리그 기준이며 의학적 손목 각도가 아니다. 기존 원본 소매의 넓은 외형과 검지 간격, 손 전체와 손잡이의 정밀 충돌 검사는 이번 순서 변경만으로 해소됐다고 주장하지 않는다. 공개 E API·F2 검사는 OS 하드웨어 E/마우스 입력 검증이 아니며 하드웨어 입력은 미확인이다. GitHub 확인 결과는 [원격 검증 기록](publication_verified.json)에 보존했다.

Hand/forearm axes are rig-relative, not clinical joint angles. This sequence change does not claim to fix the original wide sleeve, index spacing or exhaustive hand/handle collision. Public E API/F2 checks do not validate OS hardware input. Remote publication remains unverified until checked.
