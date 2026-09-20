# 후방 검 제압 · 좌측으로 베어 빼기 / Rear sword takedown · leftward extraction

상태: **최종 자동 검사 4종과 실제 GPU 9초·270프레임 검수를 통과했다.** 게시용 사본도 핵심·실제 F2 검사 2종을 통과했으며 관련 제작 코드 7파일은 검수 작업본과 바이트 단위로 같다. GitHub 반영 여부는 최종 게시 확인을 따른다.

Status: **four final automated suites and nine seconds/270 frames of actual GPU review passed.** The scoped publication copy also passed core/actual F2 checks; seven relevant production files are byte-identical to the reviewed working copy. GitHub status follows final remote confirmation.

## 사용자 변경과 구현 / User change and implementation

사용자 지시에 따라 후방에서 목을 베는 두 번째 공격과 머리 절단을 취소했다. **깊게 찌르기 → 짧게 유지 → 플레이어 좌측으로 베어 빼기 → 복귀**의 한 흐름으로 바꿨다. 몸통을 베어 빼는 접촉에서 사망·보상을 한 번 처리하고, 머리가 붙은 몸 전체가 랙돌로 쓰러진다. 일반 집중 공격의 부위 절단과 포복 크리프 처형은 별도로 유지한다.

At the user's request, the separate rear neck strike and decapitation are removed. The sequence is now **deep stab → brief hold → cut the sword out toward the player's left → recover**. Lateral torso contact triggers one death/reward and a full-body ragdoll with the head attached. Ordinary focused-hit dismemberment and crawler execution remain separate.

- 준비 0–0.28초, 찌르기 접촉 0.62초, 유지 종료 1.03초, 좌측 발검 1.03–1.66초, 치명적 몸통 베기 1.27초, 여운 종료 1.80초, 복귀 완료 2.28초다. / Preparation 0–0.28s, stab at 0.62s, hold until 1.03s, lateral extraction 1.03–1.66s, fatal torso cut at 1.27s, follow-through until 1.80s, recovery complete at 2.28s.
- 손잡이가 좌측 28cm·아래 3.5cm·뒤 34cm로 이동하며 검의 방향을 좌측 50°로 이어 준다. / The grip travels 28cm left, 3.5cm down and 34cm back while the blade turns 50° left.
- 칼날 약 55% 관입과 기존 고정 그립을 유지한다. 목 베기용 두 번째 전진을 제거하고 찌르기 거리를 유지한다. / Approximately 55% blade penetration and the fixed grip remain. The second advance formerly used for the neck cut is removed.
- `F2 → 기본 → 검 제압 · 미인지 후방`에서 **E**로 시험한다. 경계·정면 비교, 취소·정지·회복·재생성·원정 복원은 같은 실제 게임 경로를 사용한다. / Use **E** in the existing F2 rear-takedown entry; alerted/front comparisons and cancellation, pause, healing, replay and expedition restoration use the production paths.

## 검사 결과 / Results

| 범위 / Scope | 확인 결과 / Verified result |
|---|---|
| 최종 자동 검사 / Final automated suites | `rear_takedown`, `rear_takedown_trial`, `creep_execution`, `sword_shield_execution`: 4 PASS |
| 게시용 사본 / Publication copy | 핵심·실제 F2 2 PASS / Core and actual F2: 2 PASS |
| 핵심 실제 리그 표본 / Core actual-rig samples | 156 |
| 핵심 활성 축 차이 최대 / Core maximum active-axis mismatch | 39.991° |
| 핵심 관절 이동·손 회전 최대 / Core maximum joint step / hand rotation | 0.098173m / 6.478° |
| 실제 GPU / Actual GPU | `left_exit_verified_20260920`, PASS, 960×540, 30fps, 9초 / seconds, 270프레임 / frames, 물리 / physics 60Hz |
| GPU 활성 축 차이 최대 / GPU maximum active-axis mismatch | 31.412° |
| GPU 관절 이동·손 회전 최대 / GPU maximum joint step / hand rotation | 0.086797m / 11.697° |
| 박힌 칼의 월드 회전 변화 / Embedded-blade world rotation change | 0° |
| 실제 피부 기준 칼날 관입 / Actual-skin blade penetration | 약 / approximately 55% |
| GPU 검날 뿌리의 좌측 이동 / GPU blade-heel leftward shift | 0.341838m |
| GPU 칼끝 후퇴 / GPU tip retreat | 0.724959m |
| GPU 칼끝의 원래 상처 평면 이탈 / GPU tip clearance from original wound plane | 피부 바깥 / outside by 0.150209m |
| 치명적 접촉 / Fatal contact | 직전 생존 틱 111 몸통 접촉, 사망 틱 112 / Torso contact on last living tick 111; death on tick 112 |
| 실제 사망 시각 / Observed death time | 1.2833초: 1.27초 접촉 기준 다음 물리 틱 / 1.2833s: next physics tick after the 1.27s gate |
| 머리·처치·보상 / Head, defeat, reward | 머리 분리 0, 머리 유지 랙돌, 사망·보상 1회 / Zero severed heads, attached-head ragdoll, one death/reward |
| 막힌 초기 접근 / Blocked initial approach | 0.1167초 접촉 전 취소 / Cancelled at 0.1167s before contact |

[최종 4종 검사 로그](core_and_regression_tests.log), [게시용 사본 검사 로그](publication_tests.log), [실제 GPU 로그](render.log), [캡처 요약](capture_summary.json), [전체 틱 기록](capture_manifest_full.json.gz)을 보존했다. 실제 준비·찌르기·좌측 베기·발검·머리 유지 사망·복귀 이미지를 열어 검토했다. 9초 영상은 실제 렌더 이미지로 만들었으며 270프레임 전체 디코딩 검사를 통과했다. 게시용 사본에서는 이번 범위 밖의 기존 테스트룸 변경만 제외했으며, 위 제작 파일의 동일성을 확인했다.

The linked final four-suite log, publication checks, actual GPU log, summary and full tick record preserve the evidence. Actual prepare/stab/left-cut/extraction/attached-head death/recovery images were opened and reviewed. The nine-second video uses actual rendered frames and passed a complete 270-frame decoding check. Unrelated pre-existing test-room changes were excluded from the publication copy; relevant production-file identity was verified.

## 영상과 검수 이미지 / Video and inspected stills

- [전체 9초 영상 / Full nine-second video](rear_sword_left_exit.mp4)
- [준비 / Prepare](rear_sword_prepare.png), [깊은 찌르기 / Deep stab](rear_sword_stab.png), [유지 / Hold](rear_sword_hold.png)
- [좌측 베기 / Leftward cut](rear_sword_slash.png), [발검 / Extraction](rear_sword_withdraw.png), [여운 / Follow-through](rear_sword_cut_end.png)
- [머리 유지 사망 / Attached-head death](rear_sword_death.png), [복귀 / Recovery](rear_sword_recovered.png), [최종 시신 / Final corpse](rear_sword_final.png)
- [경계 대상 거절 / Alerted-target denial](alerted_denial_denied.png)

## 측정 범위와 한계 / Measurement scope and limits

접촉 구간의 검 가시성, 칼끝의 피부 이탈과 연속된 좌측 궤적을 확인했다. 좌측 베기의 마지막 여운은 화면 밖으로 나갈 수 있다. 실제 적의 부위 질의는 사망 후 비활성화되므로 몸통 접촉은 치명적 접촉 직전의 생존 틱에서 측정한다. 사망 후에는 원래 상처 평면을 기준으로 발검을 측정하고 머리 유지·랙돌·단일 보상을 별도로 확인한다. 움직이며 쓰러지는 시신의 모든 삼각형과 검이 전혀 겹치지 않는다는 검사는 아니다.

Checks cover visible contact, tip clearance and the continuous leftward trajectory; the finishing sweep may leave the frame. Production hit-region queries disable after death, so torso contact is measured on the last living tick. Extraction after death uses the original wound plane, with attached-head ragdoll and single reward verified separately. This does not establish that the blade never intersects any triangle of the moving, falling corpse.

축 차이는 실제 리그의 중립 전완 축 기준이며 해부학적·임상적 손목 굽힘각이 아니다. 55% 관입은 진입 피부와 실제 칼날 길이 기준으로, 모든 자세에서 반대쪽 피부를 뚫지 않는다는 뜻은 아니다. 영상의 3.5–4.3초 하향 시선은 완료 후 시신을 살피는 검수 전용 카메라 이동이며 게임 모션에 추가하지 않았다. OS 하드웨어 E/마우스 입력과 참고 영상의 프레임 일치는 미확인이다.

Axis mismatch is relative to the authored neutral forearm, not a clinical wrist angle. The 55% insertion is measured from entry skin against blade length, not a guarantee against far-side exit in every pose. The video tilts down at 3.5–4.3s solely to inspect the completed corpse; that camera move was not added to gameplay. OS hardware E/mouse input and exact reference-video frame matching remain unverified.

이전 [손목 보정 검수](../rear_sword_wrist_20260920/README.md)와 [목 베기 제작 기록](../rear_sword_takedown_20260920/README.md)은 과거 근거로 보존한다. 이번 시작 파일은 `/private/tmp/rear-left-exit-baseline-20260920`에 보존했다.

Previous [wrist validation](../rear_sword_wrist_20260920/README.md) and [decapitation records](../rear_sword_takedown_20260920/README.md) remain historical evidence. Task-start files are preserved in `/private/tmp/rear-left-exit-baseline-20260920`.
