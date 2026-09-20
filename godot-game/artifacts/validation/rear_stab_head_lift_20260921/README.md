# 후방 검 제압 · 고개 들기 반응 / Rear takedown · raised-head response

2026-09-21. **로컬 핵심·실제 F2 검사 2종, 실제 GPU 9초·270프레임, 전체 영상 디코딩·독립 시각 검토를 통과했다. GitHub 구현 커밋 [`a8fddf8`](https://github.com/duq711/musimusihan-rpg/commit/a8fddf87cee30ce5b64607603c095acd3bbf8c45)의 원격 일치와 PNG·영상 LFS 85개를 새 저장소로 다시 받아 확인했다.**

September 21, 2026. **Local core/real F2 suites, nine seconds/270 frames of actual GPU checks, full-video decoding and independent visual review passed. GitHub implementation commit [`a8fddf8`](https://github.com/duq711/musimusihan-rpg/commit/a8fddf87cee30ce5b64607603c095acd3bbf8c45) matches the remote; all 85 PNG/video LFS references were fetched into fresh storage and verified.**

## 변경 / Change

첫 실제 피부 접촉 뒤부터 크리프의 목·머리를 함께 들어 올리고 아래턱을 열어 비명을 지르는 듯한 자세를 만든다. 깊이 찌를수록 강화하고 검이 박힌 동안 유지한 뒤, 칼끝이 빠지면 기존 랙돌로 넘긴다. 새 비명 음향은 추가하지 않았다.

기존 순서와 조작을 유지한다: 접촉·혈흔 0.61초 → 최대 깊이·단일 사망 0.90초 → 1.00–1.22초 20° 비틀기 → 1.30초 직선 회수 → 1.90초 칼끝 빠짐·머리 유지 랙돌 → 2.46초 종료. 약 94% 깊이, 접촉 혈흔 1회, 후퇴하며 검을 빼는 파지와 공개 E/F2 경로는 유지한다.

After actual first skin contact, raise Creep's neck and head together and open its lower jaw into a scream-like pose. Build the reaction through full depth, hold it while the blade remains embedded and hand over to existing ragdoll at tip clearance. No scream audio was added.

Retain contact/blood at 0.61s, full depth/one death at 0.90s, one 20° twist during 1.00–1.22s, axial extraction from 1.30s, blade-clear intact-head ragdoll at 1.90s and completion at 2.46s. Approximately 94% depth, one blood burst, retreat-assisted grip and public E/F2 controls are unchanged.

## 검수 자료 / Evidence

- [전체 9초 영상 / Full nine-second video](rear_stab_head_lift.mp4)
- [접촉 전 머리 측면 / Head side before contact](rear_sword_before_contact_head_side.png)
- [깊은 찌르기의 머리 측면 / Head side at deep stab](rear_sword_stab_head_side.png)
- [깊은 찌르기의 머리 정면 / Head front at deep stab](rear_sword_stab_head_front.png)
- [실제 1인칭 / Actual first-person view](rear_sword_stab.png)
- [비틀기 중 머리 측면 / Head side during twist](rear_sword_twist_mid_head_side.png)
- [실제 캡처·수치 / Capture manifest and measurements](capture_manifest.json)
- [핵심·실제 F2 검사 / Core and real F2 tests](core_pass.log)
- [실제 GPU 실행 / Actual GPU run](gpu_preview.log)
- [원본 머리·턱 뼈 점검 / Source head/jaw rig audit](rig_audit.json)
- [독립 시각 검토 / Independent visual review](visual_review.json)
- [전체 영상 디코딩 / Full-video decoding](video_decode.log)

`rear_takedown`과 `rear_takedown_trial`이 통과했다. 실제 Vulkan 렌더는 30fps·270프레임·9초, 물리 60Hz이며 실패 항목은 0개다. 동일한 실제 자세를 여러 카메라에서 촬영한 PNG 84개를 보존했고 영상 인코딩·전체 270프레임 디코딩도 통과했다. 원본 파일·원정 인벤토리·커서 보존도 확인했다. 별도 독립 검토는 기록에 나열된 스틸 12장과 시간순 표본 프레임 6장을 확인했다.

실제 머리→턱 기준 주둥이 방향은 접촉 전 -42.3177°에서 최대 깊이 +16.6823°로 약 59° 상승한다. 아래턱의 기준 자세 대비 회전은 24°, 목 길이 오차는 약 4.47×10⁻⁷m다. 이는 해당 리그·측정 축의 수치이며 의학적 관절 각도나 피부 충돌의 완전한 증명은 아니다.

Both `rear_takedown` and `rear_takedown_trial` passed. Actual Vulkan capture ran for nine seconds/270 frames at 30fps with 60Hz physics and zero reported failures. The artifact preserves 84 PNGs of the same live poses from multiple cameras; encoding and decoding all 270 video frames also passed. Sources, expedition inventory and cursor were preserved. Independent review inspected the listed 12 stills and six chronological sample frames.

The measured head-to-jaw snout axis rises about 59°, from -42.3177° before contact to +16.6823° at full depth. Lower-jaw rotation relative to baseline is 24°; measured neck-length error is approximately 4.47×10⁻⁷m. These are asset/axis measurements, not medical joint angles or exhaustive skin-collision proof.

## 보이는 결과와 한계 / Appearance and limits

정면·측면에서 들린 고개와 열린 입이 확인된다. 뒤에서 보는 1인칭에서는 주로 머리 윤곽이 올라오며 입은 자연스럽게 가려진다. 검수 표본에서 열린 목 틈·큰 치아 관통·분리된 혀는 보이지 않았으나 목 피부 일부의 접힘·늘어짐은 남는다. 최초 고개 반응이 추가 비틀기 반응보다 강하게 보인다.

실제 시험 스튜디오 캡처이며 동굴 수동 플레이나 OS 하드웨어 입력 검증이 아니다. 독립 검토는 명시한 표본 범위이고 모든 프레임의 실시간 재생 검증을 뜻하지 않는다. 원본 소매·손가락 외형 한계와 정확한 입 메시 충돌 검증은 이번에 해결하지 않았다. 이전 혈흔 판의 회귀·게시 통과를 이번 버전의 실행 결과로 계산하지 않는다.

Front/side views show the raised head and open mouth. Rear first-person views primarily show the rising head silhouette; the mouth is naturally hidden. Reviewed samples show no open neck gap, gross tooth penetration or detached tongue, but some neck-skin folding/stretching remains. The initial head response reads more strongly than the additional twist response.

This is actual test-studio capture, not manual cave play or OS hardware-input validation. Independent review covers the listed samples, not full real-time playback of every frame. Existing sleeve/finger appearance limits and exact mouth-mesh collision analysis remain outside this change. Prior blood-revision regression/publication passes are not counted as runs of this revision.
