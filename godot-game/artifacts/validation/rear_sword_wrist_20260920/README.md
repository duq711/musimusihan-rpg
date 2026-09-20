# 후방 검 제압 손목 보정 / Rear sword takedown wrist follow-up

상태: **최종 손목 핵심·F2 검사와 작업본·게시 대상 복사본의 실제 GPU 검수 통과**. 이전 제압의 통과 이력과 이번 근거를 구분한다. GitHub 반영은 아직 완료로 보고하지 않으며 최종 게시 기록을 따른다.

Status: **final wrist core/F2 checks and actual GPU review of both working and publication copies passed**. Evidence for this correction remains separate from prior takedown results. GitHub publication is not yet claimed complete; consult the final publication record.

## 확인한 문제와 수정 방향 / Finding and correction

- 이전 검사는 팔 길이·접촉·도달 범위를 확인했지만, 손목과 실제 뼈대 축 사이의 방향 불일치는 충분히 검사하지 못했다.
- 앞선 캡처의 약 107° 값은 리그 중립 축과의 회전 차이이며 **해부학적 손목 굽힘각이나 임상 측정값이 아니다**. 그 값을 실제 관절 각도로 그대로 해석하지 않는다.
- 실제 리그의 중립 축과 전완 방향을 비교한다. 이 새 지표도 리그 기준 방향 차이이며 임상적 손목 각도는 아니다. 칼이 몸에 박힌 동안에는 검의 방향을 월드 공간에서 고정했다.
- 찌르기 준비 경로를 15cm 낮췄다. 발검 이후 아래 10cm·앞 20cm 방향 전환은 칼끝이 몸에서 빠진 다음 시작한다. 시작·복귀의 어깨는 실제 준비 자세를 읽어 연결한다.
- 동작 진입 전 실제 자세를 검사하고, 연속 표본 사이 관절 이동 12cm·손 회전 45° 제한을 검사한다. 1.49m에서 접근이 막힌 경우 0.1167초에 접촉 없이 취소되는 것도 확인했다.
- 기존 `F2 → 기본 → 검 제압`의 미인지 후방·경계·정면 항목과 공개 제압 동작 경로를 사용한다. 이번 작업은 입력 방식을 바꾸지 않는다.

Previous checks covered lengths, contact and reach but missed actual-rig-axis orientation. The earlier approximately 107° mismatch and the new axis measurements are **rig-relative metrics, not clinical wrist-flexion angles**. The blade now retains a world-fixed basis while embedded. Preparation moves 15cm lower; the subsequent 10cm-down/20cm-forward turn waits until tip clearance. Entry/recovery shoulders blend from the actual ready pose. Checks cover the real pre-entry pose and 12cm joint-step/45° hand-rotation limits between consecutive samples. A blocked 1.49m approach cancels at 0.1167s without contact. Existing F2 controls and the public action remain unchanged.

## 검증 기록 / Validation record

| 범위 / Scope | 확인 결과 / Verified result |
|---|---|
| 최종 핵심 검사 / Final core test | `rear_takedown` PASS, 185개 표본 / 185 samples |
| 핵심 검사의 활성 구간 축 차이 최대 / Core maximum active axis mismatch | 39.356° |
| 핵심 검사의 관절 이동·손 회전 최대 / Core maximum joint step / hand rotation | 0.106724m / 12.91° |
| 실제 GPU / Actual GPU | `wrist_final_20260920`, PASS, 960×540 · 30fps · 9초 / seconds · 270프레임 / frames, 물리 / physics 60Hz |
| GPU 활성 구간 축 차이 최대 / GPU maximum active axis mismatch | 30.516°; 깊은 찌르기 / deep stab 29.247° |
| GPU 관절 이동·손 회전 최대 / GPU maximum joint step / hand rotation | 0.094880m / 13.005° |
| 박힌 칼의 월드 회전 변화 / Embedded-blade world rotation change | 0° |
| GPU 어깨 IK 보정 최대 / GPU maximum shoulder IK correction | 약 / approximately 2.1×10⁻⁷m |
| 실제 피부 기준 관입·발검 / Actual-skin penetration / extraction | 칼날 / blade 55.0%; 피부 밖 / outside skin 4.81cm |
| 실제 이미지 검토 / Rendered inspection | 준비·깊은 찌르기·중간 전환·발검·사망·복귀 직접 확인 / preparation, deep stab, transitions, extraction, death and recovery opened and inspected |
| OS 하드웨어 입력 / OS hardware input | 검증 범위 밖 / Outside validation scope |
| 참고 영상 2:09–2:14 구간 / Reference-video segment | 직접 확인하지 못함 / Frames unavailable |

`rear_takedown`, `rear_takedown_trial`, `creep_execution`, `sword_shield_execution` 4종은 앞선 손목 후보판에서 모두 통과했다. 이후 관련 회귀 동작을 변경하지 않았으며, 최종 작업본의 `rear_takedown` 핵심 검사와 게시 대상 복사본의 핵심·F2 2종을 다시 통과했다. 강화한 12cm·45° 제한도 포함한다. [최종 핵심 로그](core_test.log), [4종 회귀 로그](regression_tests.log), [최종 게시 대상 2종 로그](publication_tests.log)를 구분해 보존한다. 첫 렌더의 실패도 [초기 실패 로그](initial_render_failures.log)에 남겼다.

Four suites—`rear_takedown`, `rear_takedown_trial`, `creep_execution` and `sword_shield_execution`—passed on an earlier wrist candidate. Their related regression behavior was unchanged afterward. The final working core and publication-copy core/F2 tests passed again, including the strengthened 12cm/45° limits. Latest results, earlier regression logs and initial render failures remain separate.

중간 핵심 검사 05는 시간 초과했다. 재시도 06의 프로세스 표본과 열린 파일 검사에서는 기존 `health_gothic_card.gd`를 읽는 `fread` 대기를 관찰했고, 이후 읽기가 재개되어 검사 06은 통과했다. 이미 종료된 05의 호출 스택은 확인하지 못했으며 시간 초과를 코드 실패나 확정된 iCloud 문제로 분류하지 않는다. [파일 읽기 시간 초과 기록](file_read_timeout.log).

Intermediate core run 05 timed out. Sampling/open-file inspection during retry 06 observed `fread` waiting for the existing `health_gothic_card.gd`; reading later resumed and run 06 passed. Run 05 had already exited, so its stack was not established. The timeout is not classified as a code failure or a confirmed iCloud cause. See the linked record.

## 게시 대상 검증 / Publication-copy verification

게시 대상 복사본에서도 최종 핵심·F2 2종과 실제 GPU 270프레임을 통과했다. 손목 지표는 작업본과 동일하며 찌르기·사망·복귀 이미지를 직접 열어 확인했다. 최종 작업본의 플레이어·모션 소스는 게시 대상과 바이트 단위로 동일하다. [게시 대상 요약](publication_capture_summary.json), [전체 기록](publication_capture_manifest_full.json.gz), [렌더 로그](publication_render.log)를 보존한다. 이는 로컬 게시 대상의 검증이며 GitHub 푸시·원격 확인 완료를 뜻하지 않는다.

The scoped publication copy passed final core/F2 tests and 270 actual GPU frames. Wrist metrics match the working copy, with stab/death/recovery stills opened and inspected. Final player/motion sources are byte-identical between those copies. See the publication summary, full record and render log. This verifies the local publication copy, not a completed GitHub push or remote confirmation.

영상은 현재 작업본의 기존 상처 효과를 포함한다. 그 효과는 이번 게시 범위에 추가하지 않았으며, 게시 대상의 자세는 별도 렌더에서 동일함을 확인했다.

The video includes pre-existing wound effects from the working copy. Those effects are outside this publication scope; matching posture was independently verified in the publication render.

## 산출물과 범위 / Artifacts and scope

- [최종 9초 영상 / Final nine-second video](rear_sword_wrist.mp4)
- [수정 전 찌르기 / Previous stab](before_stab.png), [수정 후 찌르기 / Corrected stab](rear_sword_stab.png)
- [준비 / Preparation](rear_sword_prepare.png), [유지 / Hold](rear_sword_hold.png), [발검 / Withdrawal](rear_sword_withdraw.png), [목 베기 / Cut](rear_sword_slash.png), [사망 / Death](rear_sword_death.png), [복귀 / Recovery](rear_sword_recovered.png)
- [캡처 요약 / Capture summary](capture_summary.json), [전체 기록 / Full manifest](capture_manifest_full.json.gz), [렌더 로그 / Render log](render.log)

실제 제압 뒤의 시신·분리 머리를 살피기 위해 영상은 3.5–4.3초에 검수 카메라를 아래로 기울인다. 이 관찰용 회전은 게임 제압 동작에 추가한 카메라 움직임이 아니다. 55% 관입 수치는 진입 피부와 실제 칼날 길이를 기준으로 하며, 모든 자세에서 반대쪽 피부를 관통하지 않는다는 보장은 아니다. 이번 직접 검토 범위에서 남은 시각적 결함은 확인되지 않았으나 모든 환경·각도에 대한 무결함을 뜻하지 않는다.

After the takedown, the capture tilts its inspection camera downward at 3.5–4.3s to examine the corpse and detached head; this is not added gameplay camera motion. The 55% depth is measured from entry skin against actual blade length, not a guarantee against far-side exit in every pose. No remaining visual defect was identified in this review scope; this does not establish defect-free behavior in every environment or angle.

이전 제작·검수는 [후방 검 제압 기록](../rear_sword_takedown_20260920/README.md)에 그대로 보존한다. 작업 시작본은 `/private/tmp/rear-wrist-baseline-20260920`에 있다. GitHub 상태는 별도의 최종 게시 확인을 따른다.

The [previous takedown report](../rear_sword_takedown_20260920/README.md) remains preserved as history, with task-start copies in `/private/tmp/rear-wrist-baseline-20260920`. GitHub status requires the separate final publication confirmation.
