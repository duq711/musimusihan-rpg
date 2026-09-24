# 게임 제작 기준서

## 2026-09-24 후방 검 제압 — 어깨 옆 밀착 시점 / Rear takedown — close shoulder-side view

**사용자 확정 방향:** 첨부한 파크라이 스크린샷처럼 미인지 몬스터의 뒤에 바짝 접근하고, 몸 반대편으로 나온 칼날이 실제 1인칭 화면에서 보이도록 후방 검 제압을 조정한다. 참고 범위는 사용자가 제공한 한 장의 화면이다. 원본 영상 전체를 시청했다거나 동일 애니메이션을 확보했다는 뜻이 아니다.

현재 구현값은 적 기준 준비 위치 `(-0.10, 0, 1.35)m`, 밀착 위치 `(-0.57, 0, 0.63)m`이며 밀착 수평 거리는 약 `0.8496m`다. 가슴 중심에서 적의 왼쪽으로 `0.18m` 옮긴 축으로 실제 등 피부를 찾아 진입점을 정한다. 이 수치는 사용자 확정 규칙이 아닌 현재 제작 설정이며 아래 팔 길이·파지·가림 검사와 실제 렌더로 검수했다. 시작 시 저장한 적 방향을 이동·시선 기준으로 사용하여 사망 후 대상 참조를 다시 요구하지 않는다. 경로는 작은 충돌 이동으로 나누고 누적 막힘이 `0.04m`를 넘으면 추가 이동을 즉시 멈추고 취소한다. 몸을 투명하게 하거나 칼을 화면에 합성하지 않는다. 기존 약 94% 관입, 실제 첫 접촉 출혈, 고개 들기, 짧은 비틀기, 직선 발검, 칼끝이 빠진 뒤 머리 유지 랙돌과 단일 사망·보상, E/F2·시험 원정 복원을 유지한다.

**검증 상태: 후방 제압 핵심·실제 F2 자동 검사 2종과 실제 GPU 9초·270프레임 검수를 통과했다. 84개 검수 PNG 중 주요 7장과 JPG 13개 표본의 독립 시각 검토를 마쳤다. GitHub 전용 브랜치와 `f1789b4` 반영을 확인했으며 검수 미디어 85개를 새 위치로 다운로드해 SHA-256 일치를 확인했다.** 1인칭에서 실제 반대편 피부 출구부터 칼끝까지 보이는지, 중앙·좌우 후방 접근과 장애물 취소가 정상인지 검증한다. 화면 좌표에 포함된 칼의 밑동이나 측면 카메라의 관통만으로 1인칭 가시성을 판정하지 않는다. 근거는 [밀착 제압 검수 기록](../artifacts/validation/rear_close_takedown_20260924/README.md)에 보존한다. 1인칭의 돌출 날은 좁은 칼끝으로 보이며 참고의 큰 전경 단검과 동일한 크기·구도는 아니다. 아래 기록은 각 이전 버전의 근거로 보존한다.

**User-confirmed direction:** approach tightly behind an unaware monster and make the real blade emerging from the opposite body surface visible in first person, following the supplied Far Cry screenshot. The reference is one user-provided frame; it does not establish that the full video was watched or its animation assets obtained.

Current target-local settings are preparation at `(-0.10, 0, 1.35)m` and close stance at `(-0.57, 0, 0.63)m`, approximately `0.8496m` horizontally. A ray offset `0.18m` to the target’s left from the chest finds the actual back-skin entry. These are implementation settings, not user-fixed rules, reviewed through the arm-length, grip, occlusion and actual-render checks below. Movement and aim use the target orientation cached at the start, without rereading a potentially removed post-death target. Small collision-tested substeps stop immediately and cancel when accumulated obstruction exceeds `0.04m`. Do not make the body transparent or composite a blade onto the screen. Preserve approximately 94% insertion, first-contact blood, raised-head response, brief twist, straight extraction, intact-head ragdoll after clearance, one death/reward and E/F2/session restoration.

**Validation: both rear-takedown core and real F2 suites passed, along with nine seconds/270 frames of actual GPU checks. Independent visual review covered seven key stills from 84 inspection PNGs and thirteen JPG samples. GitHub branch/commit `f1789b4` is confirmed; all 85 media files were downloaded into fresh storage and verified by SHA-256.** Verify visibility of the actual opposite-surface exit-to-tip segment in first person, centred/left/right rear approaches and safe obstacle cancellation. The near-side heel projecting in-frame or a side-view penetration does not prove first-person visibility. See the [close-takedown report](../artifacts/validation/rear_close_takedown_20260924/README.md). The first-person protrusion is a narrow tip, not the large foreground knife or exact composition of the reference. Earlier records remain evidence for their respective revisions.

## 2026-09-21 후방 검 제압 — 피격 시 고개를 드는 반응 / Rear takedown — raised-head impact response

**최신 사용자 확정 변경:** 크리프가 검에 찔릴 때 고개를 위로 들며 비명을 지르는 듯한 반응을 추가한다. 목과 머리 뼈를 함께 뒤로 젖히고 첫 실제 피부 접촉부터 깊은 찌르기까지 부드럽게 강화한다. 검이 박힌 동안 고개를 든 자세를 유지하며 기존 몸 반응과 연결한다. 이번 요청은 자세 표현이며 비명 음향을 새로 추가하는 범위로 확대하지 않는다.

첫 접촉 혈흔 1회, 깊이 약 94%, 20° 한 번 비틀기, 직선 회수와 칼끝이 빠진 뒤 머리 유지 랙돌을 유지한다. 기존 접촉 0.61초·최대 깊이 0.90초·회수 1.30초·칼끝 빠짐 1.90초·종료 2.46초 시계와 E/F2 조건·시험 원정 복원은 변경하지 않는다. 실제 주둥이 축은 접촉 전 아래 42.3177°에서 깊게 찌를 때 위 16.6823°로 약 59° 올라가고 아래턱은 기준 자세에서 24° 열린다. 수치는 해당 리그의 제작·측정값이며 의학적 관절 각도가 아니다.

**후방 제압 핵심·실제 F2 자동 검사 2종과 실제 GPU 9초·270프레임 검수·전체 영상 디코딩을 통과했다. 실제 이미지·표본 프레임의 독립 시각 검토도 완료했다. GitHub 구현 커밋 [`a8fddf8`](https://github.com/duq711/musimusihan-rpg/commit/a8fddf87cee30ce5b64607603c095acd3bbf8c45)의 원격 일치와 PNG·영상 LFS 85개를 새 저장소로 다시 받아 확인했다.** [고개 반응 검수 기록](../artifacts/validation/rear_stab_head_lift_20260921/README.md)에 결과를 보존한다. 아래 혈흔 버전의 결과는 이전 버전의 근거로 보존하며 새 자세의 완료 근거로 재사용하지 않는다.

**Latest user-confirmed change:** make Creep lift its head as if screaming when stabbed. Extend the neck and head together, blend the response from actual first skin contact through full depth, and hold the raised-head pose while the blade remains embedded, alongside the existing body reaction. This requests a physical pose, not new scream audio.

Keep one contact-blood burst, approximately 94% depth, one 20° twist, axial extraction and intact-head ragdoll after blade clearance. Existing contact at 0.61s, full depth at 0.90s, extraction from 1.30s, clearance at 1.90s, completion at 2.46s and E/F2/session rules remain unchanged. The actual snout axis rises about 59°, from 42.3177° below horizontal before contact to 16.6823° above it at deep stab, with a 24° lower-jaw opening relative to its baseline. These are asset-specific settings/measurements, not medical joint angles.

**Both rear-takedown core and real F2 suites passed, along with nine seconds/270 frames of actual GPU checks, full-video decoding and independent still/sample-frame review. GitHub implementation commit [`a8fddf8`](https://github.com/duq711/musimusihan-rpg/commit/a8fddf87cee30ce5b64607603c095acd3bbf8c45) matches the remote; all 85 PNG/video LFS references were fetched into fresh storage and verified.** See the [head-response report](../artifacts/validation/rear_stab_head_lift_20260921/README.md). The blood revision below remains historical evidence and does not validate the new pose.

실제 주둥이 방향은 접촉 전 아래 42.3177°에서 깊은 찌르기 때 위 16.6823°로 약 59° 올라가며 아래턱을 열어 반응을 표현한다. 정면·측면에서는 들린 고개와 열린 입이 보이고, 뒤에서 보는 1인칭에서는 들린 머리 윤곽이 주로 보인다. 입은 자연스럽게 가려지므로 1인칭에서 입 모양까지 선명하게 보인다고 주장하지 않는다. 검수 표본에서 목의 열린 틈이나 큰 치아 관통은 보이지 않았지만 정밀 입 메시 충돌 검증은 아니다.

The measured snout direction rises about 59°, from 42.3177° below horizontal before contact to 16.6823° above it at deep stab, with the lower jaw opened. Front/side views show the raised head and open mouth; rear first-person views mainly show the raised-head silhouette, with the mouth naturally occluded. Reviewed samples show no open neck gap or gross tooth penetration; this is not exact mouth-mesh collision validation.

## 2026-09-21 후방 검 제압 — 찌르기·비틀기 반응과 혈흔 / Rear takedown — stab/twist response and blood

**이전 제작·검수 기록. 최신 요청은 이 순서를 유지하며 피격 시 목·머리를 들어 올리는 반응을 추가한다. / Historical production and validation. The latest request retains this sequence and adds a raised-neck/head impact response.**

**최신 사용자 확정 변경:** 찌르기와 짧은 비틀기에 몬스터 몸 반응을 주고, 최초 실제 피부 접촉에서 3D 월드 혈흔을 한 번 발생시킨다. 깊은 찌르기에 강한 반응, 짧은 비틀기에 그보다 작은 반응을 구분한다. 직선 회수는 유지하지만 비틀기 없음 조건은 짧은 20° 한 번 비틀기로 대체한다. 옆 베기·목 베기·머리 절단은 되살리지 않는다.

혈흔은 화면 오버레이가 아니라 실제 접촉 월드 지점의 효과이며, 접촉 전에는 나오지 않고 깊이·비틀기·회수에서 중복 생성하지 않는다. 제작 시계는 준비 0.55초, 접촉·혈흔 0.61초, 최대 깊이·사망 확정 0.90초, 1.00–1.22초 20° 비틀기, 유지 종료·회수 시작 1.30초, 칼끝 빠짐·랙돌 1.90초, 복귀 시작 1.96초, 종료 2.46초다. 깊이 약 94%와 사망·보상 한 번, 박힌 동안 몸 유지·빠진 뒤 머리 유지 랙돌, 후퇴하며 같은 축으로 빼는 파지, E/F2 조건·시험 원정 복원은 유지한다.

**로컬 최종 핵심 검사와 실제 GPU 9초·270프레임 검수·전체 영상 디코딩을 통과했다. 실제 F2와 관련 회귀 3종의 통과는 실행 시점을 구분해 검수 기록에 남겼다. GitHub 원격 커밋 `6efb02a`와 새 저장소로 다시 받은 영상·이미지 59개 파일의 해시 일치를 확인했다.** [새 검수 기록](../artifacts/validation/rear_stab_reaction_blood_20260921/README.md)에 최종 근거를 보존한다. 수치들은 제작 설정이며 이전 개정의 통과를 이번 검증으로 대신하지 않는다. 기존 외형·정밀 충돌·하드웨어 입력 검증 한계는 유지한다.

**Latest user-confirmed change:** add a strong monster response to the deep stab, a smaller response to one brief twist and one 3D world-space blood emission at actual first skin contact. Retain straight withdrawal, replacing the no-twist rule with a short 20° twist. Do not restore lateral cutting, neck strikes or decapitation.

Blood originates at the real contact point rather than a screen overlay, with no pre-contact emission or duplication at depth, twist or extraction. The authored clock is preparation 0.55s, contact/blood 0.61s, full-depth/death 0.90s, one 20° twist during 1.00–1.22s, hold end/withdrawal 1.30s, clearance/ragdoll 1.90s, recovery 1.96s and completion 2.46s. Retain approximately 94% depth, one death/reward, held-body then intact-head ragdoll, retreat-assisted axial extraction and existing E/F2/session rules.

**Local final core checks, actual nine-second/270-frame GPU review and full-video decoding passed. Real F2 and three related regression passes are recorded at their actual run points. GitHub commit `6efb02a` and fresh remote-download hashes for all 59 image/video files were verified.** The [new report](../artifacts/validation/rear_stab_reaction_blood_20260921/README.md) records evidence; authored settings and earlier revision passes are not substitutes for current validation. Existing appearance, exhaustive-collision and hardware-input limitations remain.

혈흔은 작은 짙은 붉은 3D 물방울·얼룩이며 연속 유체막은 아니다. 비틀기 반응은 측면에서 더 잘 읽힌다. 검수 화면은 실제 시험 스튜디오이며 동굴 수동 플레이나 OS 하드웨어 입력 검증으로 보고하지 않는다.

Blood uses small dark-red 3D droplets/stains rather than a continuous fluid film. Twist response reads more clearly from the side. Evidence comes from the actual test studio, not a manually played cave scene or OS hardware input validation.

## 2026-09-20 후방 검 제압 — 찌른 뒤 직선 회수 / Rear takedown — stab and axial withdrawal

**이전 제작·검수 기록. 최신 요청은 직선 회수를 유지하며 짧은 비틀기·몸 반응·접촉 혈흔을 추가한다. / Historical production and validation. The latest request retains axial withdrawal while adding a short twist, body response and contact blood.**

**최신 사용자 확정 변경:** 검을 깊게 찌른 뒤 박힌 검 방향 그대로 뒤로 뽑는다. 앞선 검 비틀기와 플레이어 우측 옆 베기만 취소하며 대각 파지·팔 전진·첫 접촉부터 깊이에 따라 커지는 반응·깊은 관통·머리 유지 요구는 이어간다.

검 회수는 같은 축에서 진행하고 플레이어도 충돌을 검사하며 물러나 팔이 닿는 범위와 고정 파지를 유지한다. 최대 깊이에서 사망·보상을 한 번 확정하되 검이 박힌 동안 몸을 유지하고 칼끝이 몸에서 빠진 뒤 랙돌로 넘긴다. 머리 절단은 없다. 현재 제작 시계는 준비 0.55초, 접촉 0.61초, 최대 깊이·사망 0.90초, 회수 시작 1.10초, 칼끝 빠짐·랙돌 1.70초, 복귀 시작 1.76초, 종료 2.26초이며 칼날 약 94% 관입은 유지한다. 이 수치는 조정 가능한 제작값이며 실제 GPU의 랙돌 해제는 1.70초, 칼끝이 입구보다 약 6cm 빠진 뒤다.

**현재 상태: 자동 검사 5종과 실제 GPU 9초·270프레임 검수·전체 영상 디코딩 통과. 실제 1인칭·측면에서 직선 회수와 칼끝이 빠진 뒤 랙돌을 확인했다. GitHub 브랜치의 커밋과 검수 이미지·영상 47개를 다시 내려받아 일치를 확인했다.** 최종 산출물은 [검수 기록](../artifacts/validation/rear_sword_straight_withdraw_20260920/README.md)과 [전체 영상](../artifacts/validation/rear_sword_straight_withdraw_20260920/rear_sword_straight_withdraw.mp4)에 보존한다. 아래 이전 동작의 검사·게시 통과는 해당 버전의 기록이며 이번 변경의 완료 근거로 재사용하지 않는다. 기존 원본 소매·검지 간격·손 전체 정밀 충돌 검사의 한계를 해소했다고 주장하지 않는다.

**Latest user-confirmed change:** after the deep stab, pull back along the embedded blade's axis. Cancel only the previous twist and player-right lateral cut; retain diagonal grip, forward arm drive, contact/depth-linked reaction, deep penetration and an attached head.

The player retreats with collision checks during axial extraction to maintain fixed grip and arm reach. Commit one death/reward at maximum depth, hold the body while the blade remains inserted and release the intact-head ragdoll after tip clearance. Verified sequence timings are preparation 0.55s, contact 0.61s, maximum-depth/death 0.90s, withdrawal 1.10s, clearance/ragdoll 1.70s, recovery 1.76s and completion 2.26s, retaining approximately 94% insertion. These are adjustable production settings; actual GPU release occurs at 1.70s with the tip approximately 6cm behind the entry.

**Status: five automated suites, actual nine-second/270-frame GPU review and full-video decoding passed. Actual first-person/side views confirm axial withdrawal and blade-clear ragdoll. The GitHub branch SHA and all 47 inspection images/video files were verified through fresh remote downloads.** The [report](../artifacts/validation/rear_sword_straight_withdraw_20260920/README.md) and [full video](../artifacts/validation/rear_sword_straight_withdraw_20260920/rear_sword_straight_withdraw.mp4) are intended evidence locations. Earlier passes/publication records validate only earlier sequences. Existing source-sleeve, index-spacing and exhaustive hand-collision limitations are not claimed fixed.

## 2026-09-20 후방 검 제압 — 전진 찌르기와 접촉 반응 / Rear takedown — forward thrust and contact response

**이전 제작·검수 기록. 위 직선 회수 요청이 비틀기·우측 발검을 대체한다. 파지·전진·첫 접촉 반응은 이어간다. / Historical production and validation. Axial withdrawal above supersedes twist/right extraction while retaining grip, forward drive and first-contact response.**

**최신 후속 제작:** 파지와 팔 전진, 실제 첫 접촉에서 시작하는 적의 반응, 1인칭 화면 구도를 함께 수정한다. 손목 회전 하나만 바꾸는 방식으로 마치지 않는다. 엄지·손가락이 손잡이에 맞게 연결되고 팔의 전진이 읽히며, 찌르기 전에는 반응하지 않고 실제 피부 접촉부터 반응해야 한다.

제압 전용 파지는 62° 제작값과 손가락별 접촉 조정으로 구현한다. 카메라 전진을 2.5cm로 줄이고 최종 적과의 간격을 약 0.985m로 두어 손·검·전완의 흐름을 볼 수 있게 한다. 찌르기·유지 중 팔꿈치를 우측 아래로 연결하고, 회수 시 안정된 굽힘 방향을 현재 팔 축으로 이어 받아 갑작스러운 뒤집힘을 억제한다. 첫 실제 피부 접촉에서 작은 움찔을 시작하고 관입 깊이에 따라 반응을 키운다. 구현상 첫 접촉 0.61초·최대 깊이 0.90초로 구분한다. 기존 깊은 관통과 반대편 칼끝, 한 번 비틀기·플레이어 우측 발검, 머리 유지와 단일 사망·보상을 유지한다. 후퇴·전진의 충돌 취소, 일반 파지 복원, E/F2·시험 원정 복원도 유지한다. 이 값은 원본 리그에 맞춘 제작 판단이며 의학적 관절 각도를 뜻하지 않는다. 최종 실제 렌더와 독립 표본 프레임 검토로 이전 소매 가림과 큰 팔꿈치 튐·손/검 분리가 보이지 않음을 확인했다. 원본 넓은 소매와 검지 간격은 외형 한계로 남는다.

**최종 자동 검사 5종과 실제 GPU 9초·270프레임 검수·전체 영상 디코딩을 통과했다. 파지·측면 화면과 동작 표본의 독립 검토도 완료했다. GitHub 브랜치의 커밋 일치와 검수 이미지·영상 45개의 재다운로드 일치를 확인했다.** [이번 전진 찌르기 검수 기록](../artifacts/validation/rear_sword_force_thrust_20260920/README.md)과 [전체 영상](../artifacts/validation/rear_sword_force_thrust_20260920/rear_sword_force_thrust.mp4)에 최종 근거를 보존한다. 아래 중단 찌르기와 이전 검수 결과는 해당 과거 버전의 기록이며 이번 수정의 완료 근거로 재사용하지 않는다. 역사적 무술 동작을 정확히 복제했다거나 의학적 인체공학을 검증했다고 주장하지 않는다.

**Latest follow-up:** refine grip, readable forward arm extension, the enemy's response at actual first contact and first-person framing together, rather than changing wrist rotation alone. Thumb/fingers should meet the handle naturally; the arm drive must remain readable and the enemy must not react before actual skin contact.

A rear-only 62° diagonal grip and individual finger contacts are implemented. Reduce camera advance to 2.5cm and use approximately 0.985m final target spacing to expose hand/blade/forearm motion. Guide the embedded elbow down/right and transport the stable held bend onto the current arm axis during withdrawal to suppress sudden flips. Begin a small flinch at actual skin contact and build the response with insertion depth. Authored first contact is 0.61s and maximum depth 0.90s. Preserve deep through-penetration and the opposite tip, one twist, player-right extraction, an attached head and one death/reward. Collision cancellation, ordinary-grip restoration and E/F2/expedition restoration remain. These are asset-specific production settings, not medical joint angles; actual renders and independent sampled-frame review confirm removal of the earlier sleeve obstruction without a large elbow snap or hand/weapon detachment. The original wide sleeve and index spacing remain visual limitations.

**Final validation passed five automated suites, actual nine-second/270-frame GPU review and full-video decoding, with independent side/grip and sampled-frame inspection. GitHub branch SHA and all 45 image/video files were verified by fresh remote download.** The [current report](../artifacts/validation/rear_sword_force_thrust_20260920/README.md) and [full video](../artifacts/validation/rear_sword_force_thrust_20260920/rear_sword_force_thrust.mp4) are the final evidence locations. Historical middle-guard and earlier reports do not establish this revision's completion. Exact historical technique reproduction and medical ergonomics are not claimed.

선정한 다섯 손가락 쌍의 표면 교차는 0개지만 손 전체의 완전한 충돌 검사는 아니다. 손바닥 정점 한 개가 손잡이 타원 근사 안쪽 약 3.19mm에 남으며 정확한 손잡이 메시 관통량을 뜻하지는 않는다. 검지 간격이 남는 점을 포함해 접촉이 완벽하다고 보고하지 않는다.

Five selected digit pairs have zero measured surface crossings, but this is not an exhaustive hand collision proof. One palm vertex remains approximately 3.19mm inside the elliptical handle proxy, which is not an exact penetration depth into the true handle mesh. Index spacing remains; flawless contact is not claimed.

## 2026-09-20 후방 검 제압 — 중단 직선 찌르기 / Rear takedown — middle-guard straight thrust

**이전 제작·검수 기록. 현재 파지·전진·첫 접촉 반응·구도 수정은 위 섹션을 따른다. / Historical production and validation; the grip/extension/first-contact/framing revision above is current.**

**최신 사용자 확정 변경:** 첨부 무술 도식의 가운데 왼쪽 중단 직선 찌르기를 참고하여, 손목을 비튼 망치식 파지 대신 손·전완·검이 목표 쪽으로 이어지게 한다. 방패·의상·도식의 모든 동작을 복제하는 요구로 확대하지 않는다. 깊은 관통·한 번 비틀기·플레이어 우측 베기·머리 유지 랙돌의 앞선 순서는 유지한다.

확인한 제작 원인은 기존 검/손의 거의 90° 망치식 관계와 배치 원점/실제 손목 사이 약 2.54cm 차이다. 조정값은 후방 제압용 50° 대각 파지, 손잡이 접촉면 19mm 보정, 손가락별 굽힘·벌림, 실제 손목 기반 고정 길이 팔 풀이와 연속적인 준비 팔꿈치 방향이다. 준비 0.55초 동안 충돌을 확인하며 1.40m 공간을 확보하고 0.90초까지 0.78m로 전진 찌른다. 16cm 좌측 시선 보정으로 어깨·전완을 찌르기 선에 맞춘다. 최종 진행선은 적 전방축에서 좌향 20°·상향 12°, 검축 회전 기준 180°이며 준비 손잡이를 낮춰 소매가 카메라를 지나가지 않게 한다. 실제 등 피부 기준 칼날 94% 관입, 1.02–1.34초 45° 한 번 비틀기, 1.44–2.20초 우측 발검, 1.70초 단일 사망·보상, 2.32초 여운 끝·2.84초 복귀를 사용한다. 수치는 원본 리그에 맞춘 조정 가능한 제작 판단이다. 원본 에셋·피부 영향·팔다리 길이, E/F2 조건과 별도 원정 복원을 유지한다.

**검증 상태: 최종 코드 자동 검사 5종(후방 제압·실제 F2·공급 팔·포복 처형·검/방패 처형)과 실제 GPU 9초·270프레임 검수를 통과했다. 준비·찌르기 중간·관통·비틀기 후·베기·발검의 실제 1인칭 및 정면·측면 스틸을 열어 확인했고, 최종 경로에서 후보판의 소매 내부 노출이 제거됨을 확인했다. 전체 영상 270프레임 디코딩도 통과했다. 원격 게시 상태는 최종 게시 기록을 따른다.** [중단 찌르기 검수 기록](../artifacts/validation/rear_sword_middle_thrust_20260920/README.md)에 근거를 보존한다. 아래 이전 개정의 통과 기록을 새 동작의 근거로 재사용하지 않는다. 도식의 역사적 기술이나 의학적 인체공학을 정확히 재현·검증했다는 주장은 하지 않는다. 최종 실제 GPU의 활성 손·전완 축 차이는 최대 26.6389°, 연속 관절 이동 0.083612m, 몸통 반대편 칼끝 돌출 약 0.30164m다. 자세별 실제 스틸·연속 프레임 독립 검토와 전체 9초 영상을 검수 기록에 보존한다.

**Latest user-confirmed change:** use the middle-left drawing's straight thrust from middle guard, aligning the hand, forearm and blade toward the target instead of a twisted hammer grip. Do not expand this into copying the shield, clothing or every illustrated action. Preserve the earlier deep through-stab, one twist, player-right cut and intact-head ragdoll.

The identified production issues are the previous nearly 90° hand/blade relationship and approximately 2.54cm placement-origin/actual-wrist discrepancy. Tunable changes are a rear-only 50° diagonal grip, 19mm handle-contact correction, individual finger curl/spread, a real-wrist fixed-length arm solve and continuous preparation elbow direction. Collision-tested preparation creates 1.40m of room by 0.55s before thrusting toward 0.78m by 0.90s; a 16cm leftward focus adjustment aligns shoulder and forearm with the thrust line. The final blade line is 20° left/12° up from enemy forward, with 180° roll reference and a lowered preparation hilt to clear the camera. Retain 94% actual-skin insertion, one 45° twist during 1.02–1.34s, right extraction during 1.44–2.20s, one death/reward at 1.70s, follow-through to 2.32s and recovery by 2.84s. Original assets, skin weights, limb lengths, E/F2 eligibility and isolated-session restoration remain.

**Validation status: final code passed five automated suites and nine seconds/270 frames of actual GPU checks. Actual first-person and front/side stills were reviewed across preparation, mid-thrust, penetration, hold and extraction; the final path removes the earlier sleeve-interior exposure. Full 270-frame decoding passed. Remote publication follows the final record.** See the [middle-guard report](../artifacts/validation/rear_sword_middle_thrust_20260920/README.md). Historical passes below do not validate the new motion. Exact historical martial-technique reproduction or medical ergonomics are not claimed. Final actual GPU metrics are maximum active hand/forearm-axis mismatch 26.6389°, joint step 0.083612m and approximately 0.30164m of tip protrusion beyond the torso. The report preserves pose stills, independent sequence-frame review and the full nine-second video.

## 2026-09-20 후방 검 제압 — 깊은 관통·비틀기·우측 베기 / Rear takedown — through-stab, twist and right cut

**이전 제작·검수 기록. 최신 중단 찌르기 수정은 위 섹션을 따른다. / Historical production and validation; the middle-guard revision above is the current change.**

**최신 사용자 확정 변경:** 검을 거의 끝까지 밀어 넣어 칼끝이 반대편에서 보이게 한 뒤, 검을 한 번 비틀고 **플레이어 기준 우측으로 베어 빼기**로 변경한다. 이 요구가 아래의 좌측 발검을 대체한다. 목 베기·머리 절단 취소는 유지하며 우측 몸통 베기에서 한 번 사망·보상, 머리가 붙은 몸 전체의 랙돌로 연결한다. 일반 집중 공격 절단, 단검 암살, 포복 처형과 원본 에셋은 변경하지 않는다.

현재 제작값은 0.68초 찌르기, 0.80–1.12초 검날 축 45° 비틀기, 1.22–1.98초 우측 발검(1.48초 치명적 몸통 베기), 2.10초까지 여운, 2.62초 복귀다. 실제 등 피부 기준 칼날 94% 관입을 적용한다. 핵심 검사에서 약 1.045m 검날 중 0.9823m 관입과 변형된 몸통 피부 밖 0.37184–0.40671m 칼끝 돌출을 확인했다. 준비 중 1.15m까지 접근하고 찌르며 0.78m까지 전진한다. 이 수치는 조정 가능한 구현 판단이며 충돌·팔 도달·고정 그립 조건을 유지한다. 반대편 피부 밖 칼끝은 실제 메시로 측정했고 동일한 자세의 정면·측면 실제 렌더에서도 몸통 반대편 칼끝을 확인했다. 지원 검·미인지/뒤쪽 조건·E 입력·F2 세 항목은 유지한다. **최종 코드의 핵심·실제 F2 검사 2종과 실제 GPU 9초·270프레임 검수를 통과했다. 준비 자세를 새로 생성한 상태에서도 연속성을 검사했고, 정면·측면 렌더로 반대편 칼끝을 확인했다. 핵심·F2·포복 처형·검/방패 처형 4종 회귀는 앞선 후보판에서 통과한 기록으로 구분한다.** [새 검수 기록](../artifacts/validation/rear_sword_through_twist_20260920/README.md)에 최종 결과와 전체 영상을 보존하며 아래 이전 검증과 구분한다. 파크라이 동작의 정확한 프레임 일치와 OS 하드웨어 입력은 미확인이다.

**Latest user-confirmed change:** drive nearly the whole blade through until its tip is visible on the opposite side, twist once, then **cut out toward the player's right**. This supersedes leftward extraction below. The neck strike and decapitation remain cancelled; the right torso cut commits one death/reward and intact-head full-body ragdoll. Other dismemberment, dagger assassination, crawler execution and source assets remain unchanged.

Current tunable timing is 0.68s stab, one 45° blade-axis twist during 0.80–1.12s, right extraction during 1.22–1.98s (fatal torso cut at 1.48s), follow-through to 2.10s and finish at 2.62s. Core checks measure 94% past actual back skin: 0.9823m of the approximately 1.045m blade and 0.37184–0.40671m of tip protrusion beyond the posed torso skin. Preparation approaches 1.15m and the thrust closes toward 0.78m with collision/reach checks and fixed grip. Opposite-side tip protrusion is measured from the actual mesh; actual front/side renders of the same pose also confirm the torso exit tip. Supported swords, unaware/rear eligibility and E/F2 controls remain. **Final code passed core/actual F2 checks and nine seconds/270 frames of actual GPU review, including fresh-idle preparation continuity and front/side confirmation of the exit tip. The four-suite core/F2/crawler/sword-shield regression pass belongs to an earlier candidate and is recorded separately.** The [new report](../artifacts/validation/rear_sword_through_twist_20260920/README.md) records this revision separately from historical passes. Exact Far Cry frame matching and OS hardware input remain unverified.

## 2026-09-20 후방 검 제압 — 좌측으로 베어 빼기 / Rear sword takedown — lateral extraction

**이전 제작·검수 기록. 위 관통·비틀기·우측 발검이 현재 요구다. / Historical production and validation; through-stab, twist and right extraction above are the current request.**

**사용자 확정 변경:** 후방에서 머리를 자르는 동작은 취소한다. 검으로 깊게 찌른 뒤 **플레이어 기준 좌측으로 베면서 검을 빼고** 복귀한다. 별도의 목 베기 준비·두 번째 공격·머리 분리는 하지 않으며, 몸통을 베어 빼는 한 동작에서 한 번 사망하고 머리가 붙은 몸 전체가 랙돌로 쓰러진다. 일반 집중 공격에 따른 기존 부위 절단과 포복 처형은 변경하지 않는다. 이 요구가 아래의 이전 목 베기 순서보다 우선한다.

현재 제작값은 0.62초 찌르기, 1.03–1.66초 좌측 발검(1.27초 몸통 베기 사망), 1.80초까지 여운, 2.28초 복귀다. 지원 검·미인지/뒤쪽 조건·E 입력·기존 F2 세 항목은 유지한다. 시작이 멀면 첫 0.28초 준비 중 충돌을 확인하며 1.15m까지 접근하지만 목 베기용 두 번째 전진은 없앤다. 실제 피부 기준 검날 약 55% 관입, 고정 그립과 자연스러운 손목 연결은 유지한다. 이 수치는 조정 가능한 구현 판단이다. **이번 변경의 핵심·실제 F2·포복 처형·검/방패 처형 자동 검사 4종과 실제 GPU 9초·270프레임 검수를 통과했다. 게시용 사본의 핵심·실제 F2 검사 2종도 통과했다.** [현재 검수 기록](../artifacts/validation/rear_sword_left_exit_20260920/README.md)에 전체 영상·최종 수치·측정 한계를 보존한다. 이전 손목 및 목 베기 검수는 새 동작의 통과 근거가 아니다. GitHub 반영 상태는 최종 게시 기록을 따른다.

**User-confirmed change:** cancel the rear neck-cut sequence. Stab deeply, **cut the sword out toward the player's left**, then recover. Remove the separate neck windup, second strike and head separation; the lateral torso cut commits one death and a full-body ragdoll with the head attached. Existing focused-hit dismemberment and crawler execution are unchanged. This request supersedes the historical decapitation sequence below.

Current tunable timing is 0.62s stab, 1.03–1.66s lateral extraction (fatal torso cut at 1.27s), follow-through until 1.80s and finish at 2.28s. Supported swords, unaware/rear eligibility, E and the three F2 fixtures remain. Distant starts approach toward 1.15m during the first 0.28s with collision checks; the second advance used by the neck strike is removed. Approximately 55% actual-skin blade penetration, fixed grip and natural wrist alignment remain. **Four final automated suites passed: core, actual F2, crawler execution and sword/shield execution, plus nine seconds/270 frames of actual GPU review. The scoped publication copy also passed core/actual F2 checks.** The [current report](../artifacts/validation/rear_sword_left_exit_20260920/README.md) preserves the full video, final measurements and limitations. Previous wrist/decapitation passes do not establish this revision's validation. GitHub status follows the final publication record.

## 2026-09-20 후방 검 제압 손목 보정 — 후속 제작 / Rear takedown wrist correction — follow-up

**이전 제작·검수 기록. 위 관통·비틀기·우측 발검이 현재 동작 순서다. / Historical production and validation; through-stab, twist and right extraction above are the current sequence.**

기존 검 제압의 팔 길이·도달 검사는 손목 방향이 자연스럽다는 근거로 충분하지 않았다. 실제 리그 축에 대한 손·전완 검사와 박힌 검의 월드 방향 고정을 추가했다. 준비 경로를 15cm 낮추고 아래 10cm·앞 20cm 방향 전환은 칼끝이 빠진 다음 시작하며, 시작·복귀 어깨는 실제 준비 자세와 연결한다. 이전 약 107°와 새 축 차이 값은 리그 기준이며 해부학적·임상적 손목 굽힘각을 뜻하지 않는다. 기존 F2 항목과 공개 E 경로를 유지한다. **최종 핵심·F2 검사 및 실제 GPU `wrist_final_20260920`의 9초·270프레임 검수를 통과했다.** GPU의 최대 활성 축 차이 30.516°(깊은 찌르기 29.247°), 최대 관절 이동 0.094880m·손 회전 13.005°, 박힌 칼의 월드 회전 변화 0°를 확인했다. 실제 진입 자세와 연속 표본의 12cm·45° 제한, 접근 차단 시 접촉 전 취소도 검사했다. 이전 검수와 이번 최신·이전 후보판 회귀 근거는 [현재 검수 기록](../artifacts/validation/rear_sword_wrist_20260920/README.md)에 구분한다. 참고 영상 2:09–2:14·OS 하드웨어 입력은 미확인이며 GitHub 상태는 최종 게시 기록을 따른다.

Prior length/reach checks were insufficient to establish natural wrist orientation. The correction adds actual-rig-axis checks and a fixed embedded-world basis, lowers preparation 15cm and delays the 10cm-down/20cm-forward turn until tip clearance. Entry/recovery blend from the actual ready pose. Old approximately 107° and new axis measurements are rig-relative, not anatomical or clinical wrist angles. Existing F2/E controls remain. **Final core/F2 checks and nine seconds/270 frames of actual GPU `wrist_final_20260920` passed**, with maximum active axis mismatch 30.516° (deep stab 29.247°), joint step 0.094880m, hand rotation 13.005° and embedded world rotation change 0°. Actual pre-entry pose, consecutive-sample 12cm/45° limits and blocked-approach cancellation before contact were checked. The linked report separates earlier history, candidate regressions and latest evidence. Reference-video 2:09–2:14 and OS input remain unverified; GitHub status follows the final publication record.

## 2026-09-20 검으로 미인지 몬스터 후방 제압 — 사용자 요청 / Unaware rear sword takedown — requested feature

**이전 요청·검수 기록. 목 베기·머리 절단은 같은 날 후속 사용자 요청으로 취소했다. / Historical request and validation; a later same-day user instruction cancels the neck strike and decapitation.**

사용자는 미인지 몬스터 뒤에서 검으로 찌르고, 검을 뽑은 뒤 크게 휘둘러 목을 베는 제압을 요청했다. 찌르기와 발검 중에는 대상을 살아 있게 유지하고 마지막 베기에만 실제 머리 분리·사망·보상 1회를 연결한다. E 상호작용으로 시작하며 정면·경계 상태에서는 거절한다. 이 미인지 요구는 기존 단검 암살에도 우선 적용되어 이미 추적·공격 중인 적을 뒤에서 즉사시키던 범위를 제한한다.

현재 제작 범위는 `rusted_sword`, `forged_longsword`, `forged_arming_sword`와 머리·다리가 온전한 서 있는 크리프다. 조정 가능한 조건은 뒤쪽 ±55°, 수평 0.85–1.50m, 높이 차 0.8m 이하, 벽 가림 확인이다. 공유 동작은 0.62초 찌르기 → 1.03–1.42초 발검 → 1.98초 목 베기 → 2.70초 복귀다. 1.15m보다 먼 시작 거리에서는 첫 0.28초 준비 중에도 충돌을 확인하며 접근한다. 발검부터 베기 준비 사이에는 적과 약 0.82m 간격까지 짧게 전진하고, 칼날 끝에서 10% 뒤 지점으로 목을 벤다. 실제 팔이 도달하지 못하면 취소한다. F2에 실제 미인지 후방/경계/정면 비교와 일시정지·취소·재생성·원정 복원을 연결했다. [사용자 참고 영상](https://youtu.be/EsBYKoMkSOo)의 2:09–2:14 프레임은 직접 확인하지 못했으므로 프레임 일치 검증으로 보고하지 않는다. **최종 핵심·F2·테스트룸 및 관련 회귀 고유 자동 검사 7종과 실제 GPU `reach_fixed_20260920`을 통과했다.** 실제 검수는 60Hz 물리·960×540·30fps·9초·270프레임이며 최대 어깨 보정 0.018026m, 목 베기 팔 도달 약 0.5157m를 확인했다. 핵심 검사는 1.15m/1.49m 시작, 실제 피부 기준 칼날 55% 관입, 장애물 취소와 단일 절단·사망·보상을 확인했다. 기존 F2·테스트룸 종료 ObjectDB 경고는 [검수 기록](../artifacts/validation/rear_sword_takedown_20260920/README.md)에 남긴다. OS 하드웨어 입력은 미검증이며 GitHub 상태는 최종 게시 기록을 따른다.

The user requested stabbing an unaware monster from behind with a sword, withdrawing, then swinging broadly to decapitate. Stab and withdrawal keep it alive; the final cut alone commits actual head separation, death and one reward. E starts the action, while front/alerted targets are rejected. This newer unawareness requirement also restricts existing dagger assassination against alerted chasing/attacking enemies.

Current scope includes `rusted_sword`, `forged_longsword`, `forged_arming_sword` and a standing Creep with intact head/legs. Tunable conditions are ±55° rear, 0.85–1.50m horizontal distance, at most 0.8m height difference and clear line of sight. The shared sequence stabs at 0.62s, withdraws during 1.03–1.42s, cuts at 1.98s and finishes at 2.70s. Starts beyond 1.15m first approach during the initial 0.28s preparation with collision checks. Extraction/cut preparation then closes toward a 0.82m gap, with the neck contact 10% of blade length behind the tip. Unreachable arm paths cancel the action. F2 covers unaware rear/alerted/front comparisons, pause, cancellation, replay and original-expedition restoration. Reference-video 2:09–2:14 frames were unavailable; exact frame matching is not claimed. **Seven distinct final core, F2, test-room and related regression suites passed, plus actual GPU `reach_fixed_20260920`.** Review used 60Hz physics, 960×540, 30fps, nine seconds and 270 frames, with maximum shoulder correction 0.018026m and cutting reach about 0.5157m. Core checks confirmed 1.15m/1.49m starts, actual-skin 55% penetration, obstacle cancellation and one decapitation/death/reward. Existing ObjectDB exit warnings remain in the linked report. OS hardware input is unverified; GitHub status follows the final publication record.

## 2026-09-20 단검 후방 암살 — 사용자 요청 / Dagger rear assassination — requested feature

단검을 장착하고 가까운 적의 등 뒤를 실제로 찔러 즉사시키는 기능을 추가한다. 같은 날 후속 사용자 지시로 대기·미인지 상태도 필수 조건으로 추가했으며, 이미 추적·공격 중인 적의 등 뒤는 일반 피해로 처리한다. 검·방패 처형과 포복 크리프 처형은 별도 동작으로 유지한다. 뒤에서 일반 공격 입력 LMB를 사용하며, 사망·보상은 기존 경로로 한 번만 처리한다. 정면·측면에는 일반 단검 피해를 적용한다.

조정 가능한 구현값은 `iron_dagger` 기본 피해 18/최대 차지 28, 뒤쪽 ±55°·수평 1.35m 이내의 암살 조건, 조준 방향 1.05m의 신체 타격과 벽 가림 검사다. 크리프는 현재 자세의 부위별 판정을 사용하고, 뒤쪽 조건을 만족한 머리·팔다리 명중도 암살로 처리하며 몸통으로 제한하지 않는다. 대기 적은 전방 160° 시야 또는 0.65m 근접으로 감지하고, 이미 추적 중이면 기존 추적을 이어간다. 이는 후방 접근을 가능하게 하는 범위이며 별도 은신 수치·경보 전파 시스템을 추가하지 않는다. F2에 실제 단검·건강한 크리프의 등 뒤/정면 비교와 회복·재생성·원정 격리를 연결한다. **직전 단검 버전은 1.05m 사거리로 핵심·실제 F2 자동 검사 2종을 통과했으며, 실제 GPU에서 후방 118→0의 1회 사망·랙돌과 정면 피격 후 생존을 확인했다.** [검수 기록·영상](../artifacts/validation/dagger_assassination_20260920/README.md)에 범위를 보존한다. 검증은 실제 공격 처리 함수를 사용하며 OS 마우스 입력·포인터 캡처 검증은 포함하지 않는다. 기존 검격·공격 동작 검사 실패는 작업 시작 전 기준본에서도 재현하여 별도 기록한다. GitHub 반영은 최종 게시 기록을 따른다.

Add a lethal dagger stab from close behind using ordinary LMB input and the existing single death/reward path. A subsequent same-day user instruction additionally requires an idle, unaware enemy; alerted chasing/attacking enemies take ordinary rear-hit damage. Front/side hits retain ordinary dagger damage; sword/shield and crawler executions remain separate. Tunable values are 18–28 damage, ±55° rear/1.35m horizontal eligibility and a 1.05m aimed body-hit query with wall checks. Creep uses hit regions in its current pose; rear-qualified head/limb hits also count, without a torso-only restriction. Idle detection uses a 160° front cone or 0.65m proximity; established pursuit continues. This enables rear approach without adding stealth stats or propagated alarms. F2 connects real healthy rear/front Creep trials, healing, respawning and isolated expedition restoration. **The previous dagger revision passed the core and real F2 suites at 1.05m reach; actual GPU review confirmed one rear defeat from 118 HP to zero with ragdoll and survival after a front hit.** See the linked validation report and video. Checks use production attack methods, without OS mouse routing or pointer capture. Existing sword-clash/choreography failures were reproduced on the task-start baseline and remain documented separately. GitHub status follows the final publication record.

기준일: 2026-09-10. 출처: 사용자가 PD 역할을 지정하면서 설명한 게임 컨셉.

이 문서의 **확정**은 사용자에게서 받은 제작 방향이라는 뜻이며, 구현 완료를 뜻하지 않는다. **제안**은 PD 검토안, **미정**은 추가 결정이 필요한 항목이다. 이후 사용자 지시가 우선하며, 변경할 때 관련 항목과 결정 기록을 함께 갱신한다.

## 1. 게임의 중심 경험 — 확정

다크 판타지 세계에서 던전을 탐험하고 전리품을 가지고 살아 돌아오는 싱글플레이 게임을 만든다. 최우선 경험은 **값비싼 물건을 얻은 순간, 그것을 잃지 않고 탈출하고 싶어지는 긴장감**이다.

- 플레이와 원정 진입, 아이템·퀘스트 진행의 참고 방향은 사용자가 설명한 이스케이프 프롬 타르코프 방식이다.
- 전투와 분위기는 다크 앤 다커를 참고하며, 방향 공격과 콤보는 사용자가 설명한 킹덤컴 딜리버런스·시벌리의 느낌을 목표로 한다.
- 보스전은 잠깐의 실수가 죽음으로 이어질 수 있고, 함정을 잘못 밟으면 치명적인 부상을 입을 수 있다.
- 중무장한 상태로 반복해서 죽어도 다시 도전할 경제적 수단이 있어야 한다.
- 초기 제작 대상은 싱글플레이다. 반응에 따라 PvE 협동을 추가할 의향이 있으며, 현재 확정 제작 범위에는 포함하지 않는다.

레퍼런스 이름만으로 해당 게임의 모든 규칙을 도입하지 않는다. 이 문서에 적힌 사용자 요구를 우선하며, 외부 게임의 구체적인 사양 비교가 필요할 때 별도로 조사한다.

## 2. 월드와 원정 — 확정 및 미정

확정된 공간 구조:

`은신처 ↔ 자유롭게 이동하는 마을 광장·상인 → 맵 선택 → 던전 원정 → 탈출·귀환 → 거래·임무·은신처 성장`

- 은신처에서 상인들이 있는 마을 광장까지는 오픈월드 형식으로 연결한다.
- 던전은 맵을 선택하여 입장하는 세미 오픈월드 구조다.
- 은신처는 던전이 아니며 무작위 루팅 상자 생성 대상에서 제외한다. 입장마다 상자의 유무가 달라지는 규칙은 던전에만 적용한다.
- 맵은 최종적으로 최소 10개를 기획한다. 구체적인 맵 이름·순서·해금 조건은 미정이다.
- 한 맵에 머무르는 시간은 평균 30~60분을 목표로 한다. 이 표현이 강제 제한시간인지 목표 플레이 시간인지는 확인이 필요하다.
- 탈출 지점 수·개방 조건·조기 탈출 가능 여부·시간 초과 결과·중도 종료와 저장 규칙은 미정이다.
- 은신처와 광장 사이의 이동 경험은 확정이지만, 광장의 안전 여부와 기술적인 장면 연결 방식은 미정이다.

PD 제안: 고가품을 얻고 탐험을 중단할 수 있는 일반 탈출 경로를 둔다. 보스 처치로만 가능한 탈출은 특별한 경로나 보상으로 검토한다. 현재 구현의 전원 처치 조건을 최종 규칙으로 고정하지 않는다.

## 3. 플레이어의 세 목표와 엔딩 — 확정

플레이어는 세 가지 목표 중 하나를 선택한다. 선택 시점·변경 가능 여부·전투 능력 차이는 미정이며, 서사 목표를 곧바로 전투 직업 제한으로 해석하지 않는다.

| 목표 | 던전에 오는 이유 | 정해진 엔딩 |
|---|---|---|
| 학자 | 미지의 지식을 습득해 인류를 진보시키려는 야망 | 너무 많은 미지의 지식을 습득한 끝에 미쳐 버린다. |
| 성직자 | 종교적 이유로 던전을 없애려 한다. | 던전이 자신이 없앨 수 있는 존재가 아님을 깨닫고 체념한다. |
| 탐험가 | 목돈을 모아 이곳을 탈출하려 한다. | 도망친 곳에서도 던전이 발견되어 영원히 벗어날 수 없음을 깨닫는다. |

세 결말은 인간의 이해와 통제를 넘어서는 공포를 공유한다. 상인으로 등장하는 성직자와 플레이어의 성직자 목표는 별개의 역할이다.

PD 제안: 각 경로에서 실제로 달성하는 중간 성과, 알게 되는 정보, 임무 선택을 다르게 만든다. 비극적인 결말을 유지하면서도 그곳에 이르는 여정과 성취가 의미 있도록 한다. 지식 획득과 현재 스트레스 시스템을 직접 연결할지는 별도로 결정한다.

## 4. 손실과 재기 — 확정 및 미정

확정된 요구:

- 반복 사망과 장비 손실 때문에 파산하더라도 다시 던전에 도전할 수단을 제공한다.
- 던전 입장 직후 가까운 곳에 시체가 있고, 그곳에서 매우 저렴한 무기와 방어구를 얻을 수 있게 한다.
- 사용자는 주운 무기를 상점에서 취급하지 않아 판매할 수 없도록 요구했다. **입구 시체의 무료 무기만인지, 모든 습득 무기인지 범위는 확인 중이다.**
- 이 수단은 자산을 걸지 않고 다시 수익을 노릴 수 있게 하는 장치다. 별도 스캐브 캐릭터나 별도 모드 제작까지 확정된 것은 아니다.

미정 사항:

- 사망할 때 반입 장비·원정 중 습득품·지갑·임무 진행·부상 중 무엇을 잃거나 유지하는가.
- 무료 시체 장비의 회수·보관 가능 여부와 방어구의 판매 규칙.
- 무료 장비를 분해·제작·교환에 사용했을 때 가치가 생기는가.
- 부상·저주가 귀환 또는 사망 후에도 남는다면, 치료 상인 미해금 및 잔고 0 상태에서 어떻게 재도전하는가.
- 보험·보호 보관함·무료 장비 지급 횟수나 대기시간은 결정되지 않았다.

PD 제안: 시작 장비를 얻는 데 다시 고급 장비가 필요하지 않도록 접근성을 보장한다. 무료 출발 이후에는 탐험과 탈출에 실패할 위험을 유지한다. 무료품의 반복 판매나 가공만으로 원정 보상보다 큰 수익이 생기지 않는지 경제 담당이 확인한다.

## 5. 상인·우호도·임무 — 확정

모든 상인에게 우호도 수치가 있다. 일정 우호도 또는 임무 진행으로 추가 임무와 다른 상인의 소개가 열리는 구조를 사용한다. 각 상인의 정확한 수치와 조건 조합은 미정이다.

| 상인 | 역할 |
|---|---|
| 잡상인 | 게임 시작부터 해금. 기초 튜토리얼 임무와 다른 상인 소개의 출발점. |
| 무기 상인 | 무기 취급. 구체적인 매입·판매 품목과 서비스는 후속 설계. |
| 방어구 상인 | 방어구 취급. 구체적인 매입·판매 품목과 서비스는 후속 설계. |
| 연금술사 | 출혈·골절·식중독 등 물리적 부상·질환 치료와 의약품 판매. |
| 성직자 | 저주 해제와 신성한 가호. 던전 안에서도 이를 사용할 수 있게 하는 물건 판매. |
| 음식 상인 | 식재료 판매. |

잡상인 튜토리얼의 확정된 내용은 던전 입장, 몬스터 처치, 던전에서 물건 회수, 은신처 업그레이드 또는 꾸미기다. 일정량의 임무를 끝내면 다른 상인을 소개한다. 정확한 임무 개수·처치 수·회수품·소개 순서는 아직 정하지 않았다.

PD 제안: 튜토리얼 임무는 실제 해당 기능을 수행했을 때 진행한다. 수락·추적·달성·보고·보상·소개 해금이 하나의 흐름으로 연결되어야 한다. 사망 전 처치 기록과 회수품 전달의 인정 방식은 각각 명시한다. 필수 치료를 받기 위한 임무가 그 치료 없이는 수행 불가능한 구조가 되지 않게 한다.

## 6. 전투·마법·원거리 — 확정 및 미정

### 근접 무기

- 기본 마우스 공격은 세 번의 휘두르기가 반복되는 간단한 조작이다.
- Alt를 사용하면 상·하·좌·우·중앙 중 원하는 공격 방향을 선택할 수 있다.
- 특정 커맨드 순서에 맞게 공격하면 무기 콤보가 발동한다.
- 철퇴·도끼·롱소드 등 모든 냉병기에 이 공통 방향을 적용한다.
- Alt를 누르고 있는 방식인지 전환 방식인지, 방향을 마우스로 고르는지, 중앙이 찌르기인지, 입력 허용 시간과 취소 규칙은 미정이다.

PD 제안: 공통 입력 규칙을 공유하되 무기별 사거리·공격 궤적·속도·회복 시간·유효 콤보는 다르게 설계한다. 기본 공격에도 쓰임을 두고, 방향 공격과 콤보는 적의 방어를 공략하는 선택으로 검증한다. 기존 차지 공격·방패·검격 방어·사슬철퇴 특수 공격과의 관계를 먼저 정리한다.

### 방패 — 사용자 확정 (2026-09-12)

- 방패로 가드를 유지하는 동안 적의 공격 피해를 완전히 막는다. 피해를 전부 막기 위해 정확한 타이밍을 맞출 필요는 없다.
- 공격이 닿는 순간에 맞춰 방패를 올리는 저스트 가드는 피해 차단에 더해 공격한 적을 스턴시킨다. 타이밍을 맞춘 보상은 적의 빈틈이다.
- **사용자 후속 확정 — 기력이 0이면 방패를 아예 들 수 없다.** 가드는 기력이 남아 있을 때만 시작·유지한다. 앞서 채택한 기력 0의 가드 허용은 이 지시로 대체됐다.

현재 구현 판단·조정 가능한 값: 기존 정면 좌우 55도 판정과 적 공격 대상 범위를 유지하며 측면·후방 공격 및 환경 피해는 제외한다. 저스트 가드 판정은 방어 시작 후 0.20초, 스턴은 1.15초로 둔다. 일반 방어는 피격량×1.18의 기력을 0까지 소모한다. 막은 결과 기력이 0이 되면 해당 타격은 완전 방어하고 즉시 방패를 내리며, 다음 타격부터 정상적으로 피해를 받는다. 기력이 회복된 뒤 다시 방어를 요청하면 방패를 들 수 있다. 저스트 가드의 기력 8 회복은 유지하지만 기력 0에서는 가드가 성립하지 않으므로 저스트 가드·스턴·회복 보상이 발생하지 않는다. 이 수치와 고갈 시 타격 처리 방식·방어 범위는 전투 담당의 구현 판단이며 사용자 확정 수치가 아니다. 검날끼리 충돌하는 기존 검격 방어의 0.72초 경직과는 구분한다.

구현·검증 상태: **기력 고갈 후속 변경 검증 완료**. 실제 플레이어·적 판정과 기존 방패 시험에 연결했고, 기력 0 거절·막은 직후 고갈에 따른 해제·실제 방패 하강·회복 후 재가드·원정 복원을 포함한 헤드리스 검사 5개가 통과했다. 창 없는 실제 HUD 상태 5개를 촬영하고 기력 부족 안내와 내려간 방패를 확인했다. [이번 검증 기록](../artifacts/validation/shield_stamina_required_20260912/README.md)을 따른다. 이전 완전 방어·스턴 변경에서 확인한 헤드리스 검사 10개와 HUD 촬영은 [당시 검증 기록](../artifacts/validation/shield_guard_20260912/README.md)으로 보존하며, 현재 기력 고갈 규칙의 통과 근거로 대신하지 않는다. 기존 정밀 모션의 파지·소매·복귀 실패는 수정 전 기준본에서도 같은 항목·프레임으로 재현된 별도 이력이다.

### 마법

- 현재 방향은 마법 지팡이가 있어야 마법을 사용할 수 있는 방식이다.
- 주문 습득·시전 자원·시전 시간·중단·지팡이 종류별 차이는 후속 설계 대상이다.

### 활과 플린트락 머스킷

- 활은 사용자가 설명한 킹덤컴식 사용감을 목표로 한다. 조준선·흔들림·숙련·당김 등의 구체적인 기준은 별도로 정한다.
- 플린트락 머스킷은 장전과 연사가 느리고 한 발이 강력하다.
- 탄약·화약·장전 단계·중단 시 처리·불발 등 세부 규칙은 미정이다. 사용자 언급 없이 자동 추가하지 않는다.

## 7. PD가 제안하는 공통 판단 기준

아래는 사용자 목표를 달성하기 위한 제안이며, 개별 수치가 확정된 것은 아니다.

1. 위험을 감수할수록 더 좋은 전리품에 접근하되, 이미 얻은 물건을 지키기 위해 돌아서는 판단이 유효해야 한다.
2. 치명적인 보스·함정은 소리·동작·환경 흔적 등을 통해 배우고 대응할 단서를 제공한다. 반복 사망이 다음 판단을 개선하는지 확인한다.
3. 공포를 위한 어둠과 실제 조작에 필요한 적의 예고 동작·부상·탈출 정보의 식별성을 함께 검토한다.
4. 높은 장비 비용은 부담을 만들지만, 최저 자산 상태에서도 다시 출발할 길을 남긴다.
5. 안전 지역의 거래·제작 수익과 던전 회수 보상을 함께 비교한다. 기존 생활 기능은 보존하면서 긴장감을 약화시키는 경제 구조가 있는지 검토한다.
6. 세 서사 경로가 공유하는 세계 규칙은 일관되게 유지한다. 서로 다른 신념과 정보로 같은 공포를 드러낼 수 있다.

## 8. 현재 프로젝트와의 차이 — 코드 조사 기준

2026-09-10 읽기 전용 조사 결과다. 이번 기획 정리에서 게임을 실행하거나 기능 테스트를 새로 통과시킨 것은 아니다. 구현 상태는 후속 작업 때 다시 확인한다.

| 분야 | 확인한 기반 | 새 방향을 위해 필요한 일 | 근거 |
|---|---|---|---|
| 거점·월드 | 자유 이동 은신처와 지도에서의 장면 선택 | 걸어서 연결되는 상인 광장, 실제 별도 창고·업그레이드 | `scripts/hideout.gd`, `scripts/main_menu.gd` |
| 원정 | 두 던전 기반과 경과 시간 기록 | 원정 시간 규칙, 단계적인 10개 이상 맵 확장 | `scripts/game.gd`, `scripts/cave_dungeon.gd` |
| 탈출 | 적을 모두 처치한 뒤 귀환문으로 생환 | 전리품 회수 후 조기 탈출 선택의 설계 | `scripts/game.gd`의 `enemies_alive` 조건 |
| 사망·재산 | 사망 결과 화면과 재시작 | 지속 재산과 원정 손실 분리, 파산 후 재기 | `scripts/expedition_session.gd`의 `begin_new_journey()`는 기본 장비·돈·상인 재고도 초기화 |
| 거래·임무 | 중개인 실제 구매·판매와 대화 | 상인별 우호도, 실제 임무 상태, 소개 해금, 무료품 매입 정책 | `scripts/merchant.gd`, `scripts/expedition_session.gd` |
| 근접 | 방패 장착 검의 세 공격 패턴 순환 | Alt 방향 선택, 커맨드 콤보, 다른 냉병기 적용 | `scripts/player.gd` |
| 원거리·마법 | 당김·기력·물리 화살, 지팡이 장착 조건의 실제 시전 | 목표 활 사용감 정의, 머스킷 제작 | `scripts/player.gd` |
| 부상·서사 | 출혈·골절·저주와 함정 연결 | 식중독·상인 치료, 세 목표와 엔딩 진행 | `scripts/expedition_session.gd`, `scripts/cave_dungeon.gd` |

## 9. 제작 순서 — PD 제안

완성 목표인 최소 10개 맵을 유지하며, 먼저 하나의 맵에서 게임 전체 순환을 검증한다. 아래 단계는 구현 완료 선언이나 확정 일정이 아니다.

1. **원정 규칙 결정:** 매입 금지 범위·사망 손실/복구·시간의 의미를 결정하고, 기존 탈출·초기화 방식과 맞춘다.
2. **한 맵에서 핵심 순환 완성:** 준비 → 무료 장비 회수 또는 장비 반입 → 탐험 → 값비싼 전리품 획득 → 계속 진행/탈출 판단 → 귀환·거래 또는 사망·재기를 연결한다. 독립 창고와 지속 재산, 실제 튜토리얼과 첫 상인 소개까지 함께 설계한다.
3. **전투·부상 검증:** 대표 근접 무기 하나로 기본 공격·방향 공격·콤보를 완성하고 보스·함정·치료·활·지팡이의 위험과 비용을 조율한다. 준비 단계의 무기 실험은 2단계와 병행할 수 있다.
4. **거점·콘텐츠 확장:** 은신처↔광장 이동, 여섯 상인 역할, 은신처 성장, 추가 무기·머스킷과 세 서사 경로를 확장한다.
5. **맵 확장과 완주 검증:** 지도별 탐험 방식·환경 위험·전리품·임무·탈출 특징을 구분하여 최소 10개로 늘리고, 세 경로를 처음부터 엔딩까지 검증한다.

첫 맵의 평가 항목은 고가품 획득 전후 탈출 판단의 변화, 사망 원인의 이해 가능성, 연속 실패 후 재출발 가능성, 목표 플레이 시간, 튜토리얼과 거래의 연결이다. 수치 목표는 실제 시험 결과를 보고 정한다.

PvE 협동을 위해 소유권·원정 상태·보상 지급 책임을 명확히 나누는 설계를 검토한다. 실제 네트워크 기능과 협동 규칙은 별도 제작 결정이 필요하다.

## 10. 현재 확인할 질문

| ID | 질문 | 상태 |
|---|---|---|
| Q01 | 매입 금지는 입구 시체의 무료 무기에만 적용하는가, 던전에서 주운 모든 무기에 적용하는가? | 사용자 답변 대기 |
| Q02 | 사망 시 장비·습득품을 어떻게 잃고 부상은 어떻게 복구하는가? 잔고 0에서도 정상적으로 재출발 가능한가? | 사용자 답변 대기 |
| Q03 | 30~60분은 맵별 제한시간인가, 목표 플레이 시간인가? | 사용자 답변 대기 |

다음 설계에서 다룰 질문: 일반 탈출의 조건, 임무 진행 보존, 원정 중 저장/종료, Alt 조작, 세 목표의 선택 시점, 상인 소개 순서. 답하지 않은 규칙을 PD 제안만으로 사용자 확정사항으로 바꾸지 않는다.

## 결정 기록

- 2026-09-12 후속 변경: **사용자 확정 — 기력 0이면 방패를 아예 들 수 없다.** 이전의 기력 0 가드 허용 구현 결정을 대체한다. 방어 중 고갈시키는 타격 자체는 완전히 막은 뒤 즉시 방패를 내리고, 이후 공격은 정상 피해를 주며 회복 후 새 방어 요청으로 다시 올리는 방식은 이번 구현 판단이다. 방패 유지 중 완전 방어와 저스트 가드 시 적 스턴은 유지한다. 실제 판정·같은 테스트룸 항목을 연결하고, 관련 자동 검증 5개와 숨김 HUD 촬영·고갈 화면 검토를 완료했다.

- 2026-09-12 초기 변경: 사용자가 전투 기획 담당 작업명 ‘강형욱’을 지정했다. **사용자 확정 — 방패 유지 중에는 적 공격 피해를 완전히 막고, 완벽한 타이밍의 가드는 공격한 적에게 스턴을 준다.** 당시 기력 0에서도 가드를 허용한 구현 결정은 같은 날 후속 지시로 **대체됨(superseded)**. 정면 판정·0.20초 타이밍·1.15초 스턴 등 수치는 조정 가능한 구현값이다. 당시 실제 방패 기능·테스트룸·관련 자동 검증과 HUD 확인 결과는 역사 기록으로 보존한다. 기존 정밀 모션의 실패도 변경 전 비교 결과와 함께 별도 기록한다.

- 2026-09-12: 사용자가 참고 이미지처럼 아이템 상세 설명을 요청했다. 상세창의 기능은 이름표·버리기와 장착 가능한 물건의 장착하기로 한정한다. 원본 카탈로그의 이미지·설명·속성을 표시한다. 24자 별칭, 수량 선택 후 바닥에 놓고 같은 장소에서 회수하는 방식은 이번 구현 판단이며, 시험 세션에서 이름표·개별 강화 정보·물품 수량을 함께 보존한다.

- 2026-09-12 후속 정정: **사용자 확정 — 은신처는 던전이 아니므로 무작위 루팅 상자를 생성하지 않는다.** 앞선 맵 루팅 요청의 범위는 던전으로 한정한다. 실제 `hideout.tscn`은 기존부터 무작위 생성에 연결되지 않았으며 개인 보관함과 생활 소품을 사용한다. `main.tscn`의 검은 성물실은 은신처와 별도의 던전이므로 폐광과 함께 기존 루팅 적용을 유지한다.
- 2026-09-12: **사용자 확정 — 맵의 루팅 상자는 장소의 용도에 맞는 자연스러운 위치에 놓여야 하며, 같은 자리라도 맵 입장에 따라 있거나 없어야 한다.** 고정 후보 위치를 사용하는 방식은 허용됐다. 제공된 나무 상자 2종·나무 통·보물상자를 사용한다. 현재 두 던전에 후보별 점유 추첨을 적용하며 한 번 들어간 맵에서는 결과와 수색 상태를 유지한다. 후보 수, 개별 확률과 맵당 최소·최대 상자 수는 맵 담당의 조정 가능한 구현값이며 사용자 확정 수치가 아니다. 새 맵을 추가할 때도 보관 이유·바닥 접촉·여는 공간·통행 여유를 검증한 후보를 등록한다. 저장 후 재접속의 원정 지속 규칙은 기존 미정 사항으로 유지한다.
- 2026-09-12: 사용자가 UI·UX 담당 작업명 ‘유아인’을 지정하고 첨부 은신처 화면의 UI 제거와 조준선 확대를 요청했다. 해당 화면의 위치·생존·생활 안내 카드, 하단 조작 안내 및 지도 버튼을 숨기며 중앙 점 조준선을 유지한다. 확대 배율 2배는 이번 구현 판단이다. 가방·지도·일시정지와 상호작용 시 표시되는 기능 화면은 유지한다.
- 2026-09-10: 사용자 컨셉을 최초 기준으로 등록. 원정의 긴장감, 최소 10개 맵, 싱글 우선, 세 목표와 비극적 엔딩, 여섯 상인 역할, 무료 시체 장비, 공통 근접 조작, 지팡이·활·머스킷 방향을 기록했다. Q01~Q03은 미정으로 보존한다.

담당자 책임과 작업 인수 기준은 [TEAM_ROLES.md](TEAM_ROLES.md), 실제 개발·검증 규칙은 [AGENTS.md](../AGENTS.md)를 따른다.

## 무장 구성·주무장 입력 — 사용자 후속 확정 (2026-09-12)

- 무장 구성은 주무장 1개, 부무장 2개로 간다. 주무장 기본키는 1이다.
- 의도한 흐름: 비무장 상태에서 검·방패를 주무장으로 갖추고 1을 누르면 둘을 꺼낸다. 검·방패를 들고 다시 1을 누르면 방패를 수납하고 검만 유지한다.
- 이번 우선 구현 범위는 사용자의 “일단 1번을 누르면 방패를 집어넣게” 지시다. 검·방패를 든 상태의 1 입력과 왼쪽으로 빠지는 방패 수납, 수납 후 검 유지 및 방패 방어 해제를 구현한다. 물품 자체를 장착 해제하거나 버리지 않는다.
- 전체 주/부무장 슬롯 개편과 비무장 → 주무장 꺼내기 입력 연결은 아직 미구현이다. 검만 든 뒤 추가 1 입력의 동작은 미정이며 이번에는 변화가 없다. 장비를 다시 장착하거나 테스트룸 시험을 재선택하면 방패 준비 상태로 복원한다.
- 1키는 검을 든 상태에서 주무장 입력이 우선한다. 지팡이의 기존 숫자 주문 선택은 유지하며 전체 입력 개편은 후속 범위다.

- 2026-09-13 사용자 후속 확정: 방패 수납 후 왼손이 검을 잡아 양손 파지로 전환한다. 왼손 복귀·손가락 파지·검 추종을 이번에 확장하며, 공격력 등 전투 수치는 변경하지 않는다.

- 2026-09-13 사용자 후속 확정: 검 양손 파지의 휘두르기 모션은 검·방패와 통일한다. 동일한 세 방향 베기와 재생 시간 및 동작에 맞는 타격 시점을 사용하며, 방패 소지 판정과는 분리한다.
- 2026-09-13 사용자 수정 지시: 우→좌 기본 베기는 날로 베는 궤적과 관성에 맞는 마무리·복귀로 다듬는다. 좌→우 역베기의 검 위치·모양은 보존하고, 오른손 엄지의 과도한 침투와 왼손의 느슨한 파지만 수정한다. 검 원본과 전투 수치는 유지하며 구현·실제 렌더 검증 상태는 테스트룸 문서에 기록한다.
- 2026-09-13 이전 사용자 확정: 기본 우→좌 베기는 현재 파지 위치에서 손목을 돌려 검을 눕힌 후 날부터 벤다. 공격 전에 검을 한 번 더 치켜드는 동작은 없앤다. 이전 직접 공격의 ‘준비 중 검·팔 자세 전체 유지’ 구현 기준은 기본 베기의 손목 회전을 허용하는 이 지시로 대체한다. 방패 착용/수납은 같은 공격 연결과 속도를 사용하며 기존 차지·피해·기력·방패 방어 규칙을 유지한다.
- 당시 구현 판단: `right_diagonal` 준비 0.14초 동안 파지 중심(`GRIP_CENTER`) 위치를 유지하며 손목을 회전하고, 활성 첫 0.10초는 같은 시각의 제작 모션으로 연결한다. Mac 제작 기본 베기는 얕은 우상향 검 길이축과 고정된 날면을 유지한 채 손이 좌하향으로 이어지는 당겨 베기로 조정하며, 끝부분의 180도 반전을 제거한다. 역방향·내려베기 데이터와 원본 손 모델은 보존한다. 최소 준비 0.22초·차지 판정 기준 0.24초, 활성 구간 기준 타격 0.145초·활성 길이 0.30초는 기존 튜닝값을 유지한다.
- 당시 구현·검증 상태: 위 날 정렬 변경의 관련 자동 검사 10종과 실제 Vulkan/embedded 촬영을 완료했다. 기존 자연 검격 교차 시험 1건은 변경 전과 같은 항목에서 실패한다. 원본 손 모델의 엄지·왼손 모양을 추가로 교정했다는 뜻은 아니다.  변경 전 소스는 `../../asset-staging/sword_edge_alignment_20260913/baseline/`에 보존한다. 테스트룸의 기존 `주무장 1번 · 방패 수납`에서 검·방패와 양손 상태를 비교하며 세부 절차·결과는 [TEST_ROOM.md](../TEST_ROOM.md)에 기록한다.

- 2026-09-13 이전 복원 지시: 마지막 좌우 대칭 역베기 결과가 거절되어 해당 변경을 취소한다. 승인된 `right_diagonal`은 유지하고, `left_reverse`와 해당 런타임 연결은 `../../asset-staging/sword_reverse_match_20260913/baseline/`의 변경 직전 상태로 복원한다. 새로운 모션 방향은 추가로 확정하지 않는다.
- 복원 상태: 직전 baseline으로 복원하고 관련 자동 검사 4종을 통과했다. 다시 촬영한 양손 기본·역베기 총 182 PNG가 변경 전 촬영과 모두 일치하며 원정·가방·커서를 보존했다. 복원 근거는 `../../asset-staging/sword_reverse_restore_20260913/validation_summary.json`에 기록한다. 거절된 변경의 검사·촬영과 복원 전 문서는 과거 이력으로 보존하며 새 모션의 사용자 승인을 뜻하지 않는다.

- 2026-09-13 이전 사용자 지시: 복원된 `left_reverse`를 보존하고, `right_diagonal`을 그 역베기와 유사하되 방향만 반대로 바꾼다. 앞선 정베기 승인본 고정과 얕은 우상향·고정 날면 기준은 이 후속 요청으로 대체했다.
- 당시 후보 03 구현 판단: 정베기 제작 시각 0~0.80초는 원본 역베기의 `1.42 - 새 시각`에 해당하는 동일한 `sword`·`right_arm` 포즈를 사용했다. 회수에서는 원본 0.341666667~0.62초의 준비 정지를 생략하고 새 0.803333333~1.42초에 원본 0.341666667→0초의 기존 포즈로 대기 복귀를 이었다. 공간 반전·새 팔 생성 없이 기존 포즈를 재사용했다. 별도 0.14초 손목 준비를 제거하여 WINDUP의 시작 자세·높이를 유지하고, 정베기는 활성 0.145초 타격 시점까지 직접 연결했다. 역베기·내려베기의 연결은 기존 0.10초를 유지했다. 정베기 방패 곡선은 새 시각 격자에서 원래 같은 시각 포즈를 재표본화했으며 바이트 동일성을 뜻하지 않는다. 기존 최소 입력 0.22초·차지 판정 0.24초, 타격 0.145초·활성 0.30초, 피해·기력·방패 규칙은 유지했다.
- 당시 검증 이력: 후보 03을 적용하고 관련 자동 검사 5종과 실제 Vulkan/embedded 촬영을 완료했다. 방패·양손에서 기존 역베기의 총 182 PNG가 변경 전과 같았으며, 수정 정베기의 우→좌 진행·대기 복귀를 직접 확인했다. 정베기 진입의 한 프레임 화면 밖 이동은 남아 있었다. 이 결과는 아래 파지 방향 변경 전 기록이며 검격 교차 시험과 이전 후보 이력을 구분한다. 근거·제한·변경 전 자료는 `../../asset-staging/sword_forehand_from_reverse_20260913/validation_summary.json`, `visual_review.json`, `baseline/`에 보존한다.

- 2026-09-13 이전 사용자 지시: 정베기의 우→좌 이동은 승인했으며, 이동을 유지한 채 검 모델 방향을 반대로 바꾼다.
- 당시 구현·검증 이력: 최종 실제 파지점 중심의 로컬 Z축 회전으로 검과 오른쪽 장갑을 함께 돌려 활성 0.145초 타격까지 점진적으로 180도에 도달하게 했다. 왼손 추종과 소매 IK, manifest·원본 GLB·역베기와 기존 공격 시간·차지·피해·기력·방패 규칙은 보존했다. 관련 검사 8종과 실제 양손·방패 촬영을 완료했으며 기존 역베기 182 PNG와 원본 모션·모델을 보존했다. 회수 중 화면 밖 구간과 기존 자연 검격 교차 시험의 동일한 5개 실패는 당시에도 남아 있었다. 이 결과는 아래 즉시 베기 변경 전 기록이며 영상·변경 전 자료·검사 근거는 [검증 기록](../../asset-staging/sword_forehand_grip_direction_20260913/validation_summary.json)에 보존한다.

- 2026-09-13 이전 지시·구현: 공격 모션을 기존 역베기와 유사하게 만든다. `left_reverse`의 같은 시각 움직임을 기준으로 `right_diagonal`을 좌우 반대 방향으로 제작하며 칼끝 높이·앞뒤 거리·날면과 베기 리듬을 유지한다. 기존 역베기와 나머지 클립, 원본 오른손·검 GLB는 보존한다. 짧은 정베기 입력을 놓으면 바로 공격을 시작하는 규칙과 누르기 차지·피해·기력·방패 규칙은 유지한다.
- 이번 구현 판단: Mac에서 manifest의 `right_diagonal`만 변경한다. 기존 역베기의 같은 시각 검·팔 자세를 화면 좌우 반대로 대응시키고, 모델 형상을 보존한 채 실제 오른쪽 손목에 팔을 맞춘다. 시작과 끝은 원래 오른쪽 대기 자세로 부드럽게 연결한다. 정베기의 별도 180도 회전과 독립적인 타격 자세 진입을 제거하고, 두 베기 모두 활성 첫 0.10초 동안 시작 자세에서 해당 시각의 제작 모션으로 연결한다. 기존 타격 0.145초·활성 0.30초와 전투 수치를 유지한다.
- 현재 구현·검증 상태: 관련 자동 검사 9종을 통과하고 실제 embedded Vulkan에서 양손·방패의 두 베기를 364개 시퀀스 PNG로 촬영했다. 기존 역베기 182개 PNG가 변경 전과 바이트 단위로 같았으며, 정베기를 제외한 9클립과 원본 모델을 보존했다. 보이는 베기의 칼끝 높이·깊이·날 기울기의 좌우 대응과 새 손·소매 분리 없는 대기 복귀를 확인했다. 활성 약 0.183초에는 두 검이 동일하게 화면 밖으로 나가며, 팔 모델의 완전한 좌우 대칭·해부학 전체 검증과 사용자 최종 미감 승인은 이 결과에 포함하지 않는다.
- 검증 기록: 기존 `sword_clash`의 동일한 4개 항목 실패는 이번 9종 통과에서 제외한다. [검증 요약](../../asset-staging/sword_forehand_mirror_reverse_20260913/validation_summary.json), [화면 검토](../../asset-staging/sword_forehand_mirror_reverse_20260913/visual_review.json), [전투 검사 로그](../../asset-staging/sword_forehand_mirror_reverse_20260913/combat_tests.log)에 근거를 기록한다. 기존 `주무장 1번 · 방패 수납`의 실제 표적에서 역베기 기준 양방향 비교를 반복하며 영상·절차는 [TEST_ROOM.md](../TEST_ROOM.md)를 따른다. 직전 `immediate_cut`은 사용자 거절 이력이며 [당시 검사·촬영 기록](../../asset-staging/sword_forehand_immediate_cut_20260913/validation_summary.json)과 원본 자료를 보존한다.

- 2026-09-13 이전 구현 — 정베기를 화면 밖까지 끝까지 휘두르기: 타격 직후 검을 급하게 뒤집던 구간을 수평 베기 연장으로 교체했다. 검·칼끝은 왼쪽으로 계속 진행해 화면 밖으로 빠지며, 화면 아래에서 방향을 정리한 뒤 이미 대기 각도를 갖춘 채 복귀한다. 타격까지의 제작 키, 역베기와 나머지 9클립, 원본 모델·파지, 타격 시간·피해·기력·방패 규칙을 보존했다.
- 이번 검증·사용 위치는 [TEST_ROOM.md](../TEST_ROOM.md)의 최신 항목과 [제작·검증 기록](../../asset-staging/sword_followthrough_20260913/validation_summary.json)을 따른다. 이전 전체 활성 구간의 좌우 반사 기준은 이번 지시로 타격까지의 유지와 화면 밖 후속 베기로 변경되었다.

- 2026-09-14 이전 구현 — 공격 중 방패 유지·역베기 마무리: 검·방패의 정베기·역베기·내려베기 모두 공격 시작 시 들고 있던 방패 위치·각도를 차지부터 회수 끝까지 유지한다. 공격이 끝나면 기존 대기·이동 자세로 연결하며 방어 판정은 기존 RMB·기력 조건을 따른다. 역베기는 타격 이후 칼날의 기울기를 유지하며 오른쪽 화면 밖까지 이어지고, 화면 아래에서 방향을 정리한 뒤 대기 자세로 돌아온다. 정베기·내려베기의 검 궤적과 역베기의 타격까지 제작 키, 원본 모델·파지와 전투 수치는 보존한다.
- 이번 결과와 반복 시험은 [TEST_ROOM.md](../TEST_ROOM.md)와 [검증 기록](../../asset-staging/sword_shield_hold_reverse_finish_20260914/validation_summary.json)을 따른다. 역베기 후속 베기 구간의 변경은 이번 지시가 이전 역베기 전체 보존 조건을 대체한 것이다.

- 2026-09-14 최신 사용자 확정: 공격 중 방패를 고정하던 방식을 대체하고 검을 휘두르기 전에 방패를 왼쪽으로 자연스럽게 빼놓는다. 기존 검 궤적과 화면 밖 마무리는 유지한다.
- 구현 판단: 세 공격 모두 실제 방패 시작 자세에서 0.12초 동안 왼쪽 26cm·위 2cm·뒤 4cm, 옆 회전 10도로 공간을 만든다. 준비→공격 전환의 연속 시계를 사용해 공격 지연 없이 타격 전에 이동을 마친다. 회수 시작 0.06초 뒤부터 대기·이동 자세로 복귀하며 충돌·취소 연결과 기존 방어·기력 규칙을 유지한다. 반복 시험은 [TEST_ROOM.md](../TEST_ROOM.md)의 최신 항목을 따른다.


2026-09-14 최신 사용자 지시 — 방패를 왼쪽 화면 밖으로 완전히 빼기: 앞선 26cm 이동을 95cm 이동으로 늘려 방패 전체가 왼쪽 화면 밖으로 나가도록 한다. 세 공격의 0.12초 선행 이동·회수 복귀 연결과 검 궤적·전투 수치는 유지한다. `F2 → 기본 → 주무장 1번 · 방패 수납`의 **방패 왼쪽 화면 밖으로**와 기존 내려베기 시험에서 짧은/차지 입력을 반복한다. 자동 검사에서는 방패의 모든 메시 경계가 카메라의 왼쪽 시야 밖인지 실제 투영으로 확인한다.


## 2026-09-14 부위별 체력과 상태이상 개편

사용자 확정: 하나의 전체 체력 대신 부위별 체력을 사용한다. 체력이 0인 부위는 일반 회복 수단과 보통의 치유 마법으로 회복하지 못한다. 특수 수술로 0에서 1로 복구한 뒤 다시 치료해야 하며, 높은 단계의 마법도 손상 부위를 복구할 수 있다. 골절·출혈·저주·마비·독을 실제 상태이상으로 추가한다. 첨부 화면은 7부위 상태와 전체 합계를 보여주는 UI 참고다.

이번 구현 판단: 머리35·흉부85·복부70·양팔 각60·양다리 각65, 합440을 사용한다. 머리·흉부가0이면 사망하고 나머지 부위의0은 생존 가능한 손상으로 남긴다. 수술 도구와 3단계 고위 재생은 손상 부위 하나를 정확히1로 복구하며 상태이상은 따로 치료한다. 일반 피해의 잔여량은 살아있는 다른 부위로 분배한다. 현재 적 근접 판정은 기존 사거리·방향 판정을 유지하므로 접근 방향에 따라 전면흉부·측면팔·후면복부·위쪽머리를 선택하며, 바닥 함정은 다리를 다친다. 이는 정밀한 메시 부위 충돌을 구현했다는 뜻이 아니다.

치료 대상은 건강 탭에서 지정하거나 자동 선택한다. 휴식·요리·침상·흡혈은 체력이 남은 부위만 회복한다. 부위 상태는 원정 세션에 보존하고 테스트룸의 전체 회복·총체력 수치 조절은 시험 초기화를 위한 명시적 우회로 구분한다. 골절·출혈은 다친 위치를 표시하며 독·저주·마비는 전신 상태로 표시한다. 새 치료품·마법·상태이상은 원본 카탈로그에서 시험 항목을 자동 등록한다. 수치·피해부위 선택·사망 조건·효과 강도는 조정 가능한 구현 규칙이며 별도의 사용자 확정 수치로 간주하지 않는다.

구현·검증 상태: 실제 플레이·은신처·동굴·테스트룸에 통합하고 부위별 치료, 상태이상, 무기 불이익, 사망·재시험·원정 복원과 기존 관련 회귀를 검증했다. 1280·960의 실제 UI 좌표 입력과 embedded Vulkan 6장을 확인했다. 동굴 사망 후 F2 복귀의 첫 물리 틱 이전 회복 누락도 수정·재검증했다. 결과·검증 범위·실제 화면은 [검증 기록](../artifacts/validation/body_health_20260914/README.md)과 [테스트룸 안내](../TEST_ROOM.md)에 기록한다.

### 2026-09-14 건강 화면 참고 디자인 적용

최신 사용자 지시: 제공한 갑옷 전신 건강 UI와 매우 유사하게 화면을 제작한다. 참고의 어두운 성소·깃발·촛불·갑옷 인물, 황동 장식, 명조체, 붉은 체력 막대, 부위 위치와 상하단 구성을 따르며 가로 게임 화면에 맞춘다. 기본 화면에서는 인물을 중심으로 일곱 체력을 표시하고 부위 선택 시 실제 치료창을 연다. 기존 수술·마법·상태이상·선택 부위·실제 440 체력 규칙은 유지한다. 이번 UI 요청을 새로운 피로·체온 시스템이나 머리 최대 55의 확정으로 취급하지 않는다. 별도 답변이 없는 하단 지표는 기존 포만감·수분·기력·스트레스 데이터에 연결한다. 제작·검증 상태는 [화면 개편 기록](../artifacts/validation/health_reference_20260914/README.md)에 기록한다.


### 2026-09-14 장비·건강 상태 통합

최신 사용자 확정: 별도 장비 탭과 건강 탭을 통합하고, 새 가로 참고처럼 왼쪽 인물·부위 체력·생존 상태와 오른쪽 장비·주머니·허리 파우치·배낭·빠른 사용을 한 화면에 표시한다. 이 지시가 앞선 장비/건강 화면 분리를 대체한다.

구현 판단: 실제 장비 5슬롯과 가방 30칸을 그대로 사용하며, 수납 목록을 8/6/16칸의 표시 구역으로 나눈다. 빠른 사용은 가방에 남은 소비품을 순서대로 최대10개 자동 표시하고 버튼/1~0으로 실제 사용한다. 부위 치료·상태이상·수술·고위 재생·아이템 상세·이름표·장착·폐기는 같은 기존 모델을 사용한다. 참고 그림의 온도·방사능 숫자나 없는 장비 부위를 새 게임 규칙으로 추가하지 않는다. 배경의 기사는 상태 화면용 삽화이며 실시간 장비 모델 미리보기로 간주하지 않는다. 구현과 실제 검증은 [통합 기록](../artifacts/validation/unified_inventory_20260914/README.md)에 남긴다.


2026-09-14 사용자 지시: 상자에 손을 뻗어 잠금을 만지고 뚜껑을 드는 모션을 제거했다. 손 원본 에셋은 보존하며 실제 상자 열기에서는 손 리그를 활성화하거나 진행시키지 않는다. 1.2초 열기·뚜껑 애니메이션·수색·아이템 이동과 장비 숨김/복귀, 취소·F2·재선택·원정 복원은 유지한다. 테스트룸의 `상자 조사 · 열기 · 수색`과 `상자 모션 · 손 동작 없이 열기`에서 반복할 수 있다.


### 2026-09-14 허리 파우치·배낭 장비 교체

사용자 확정: 장착 장비 칸에서 허리 파우치와 배낭을 교체할 수 있어야 한다. 두 장비 슬롯을 추가하여 기존 5슬롯을 7슬롯으로 확장한다. 구현 판단: 기본품과 가벼운 교체품을 각 한 종류씩 두고 기존 상세·장착·해제·이름표·버리기 경로를 사용한다. 소지품은 공용 가방에 유지하고 전체 수납은 기존 30칸이다. 교체 전 장비와 개별 이름표를 보존하며, 기존 5키 장비 데이터도 새 슬롯을 수용한다. 가방 종류별 용량이나 중첩 가방 수납 규칙은 이번 요청에 포함하지 않는다. 테스트룸의 실제 교체 시험과 1280·960 입력/화면 검증을 함께 제공한다.


### 2026-09-15 사용자 지시 — 던전 전투 화면

던전 입장 시 참고 이미지처럼 상단 소지품 단축키, 초록 인체 체력 표시와 인접한 조건부 디버프 아이콘을 노출한다. 앞선 은신처 상시 UI 제거와 적용 장소가 다르다. 물품 사용은 실제 장비·치료·소비로 이어진다.

UI 구현 기준: 1~0의 고정 자동 기본 배치, 실제 일곱 부위 체력과 총 체력/기력, 활성 상태만 보이는 경고. 배고픔·갈증 25 이하, 기력 25% 이하, 스트레스 60 이상을 경고 임계값으로 사용한다. 스트레스의 어지러움 표시와 기력의 피곤함 표시는 기존 수치의 경고이며 독립적인 추가 질환은 아니다. 저주 등 실제 상태이상은 활성 여부를 따른다. 주문 선택은 던전에서 Alt+숫자로 분리하고 기존 시험 항목 조작은 유지한다. 사용자 지정 배치 편집과 별도 피로 질환은 이번 범위에 포함하지 않는다.


### 2026-09-15 사용자 지시 — 아이템 사용 중 남은 시간과 F 취소

중앙 원형 사용 진행 표시와 남은 초, F 취소를 실제 아이템 사용에 연결한다. UI에서 시작하는 소모품 사용은 시간이 끝나야 아이템 한 개 소비와 효과가 적용된다. 취소·중단은 미완료 소비/효과를 남기지 않는다. 붕대·부목은 기존 제작 모션 시간과 맞추고, 일반 약/물 3초·식량 4초·마법서 5초·수술 12초를 이번 구현의 조정 가능한 기본 시간으로 둔다. 참고 영상은 직접 불러오지 못했으므로 첨부 스크린샷의 원형 타이머·소수 초·F 취소를 시각 기준으로 사용한다. 타이머는 원정 저장 필드가 아닌 현재 플레이어의 일시적 행동 상태이며 장면 전환과 시험 복원 때 취소한다.

### 2026-09-17 사용자 지시 — 제작한 육포를 꺼내 먹기 / Eating the authored jerky

[참고 영상 1:45–1:53](https://www.youtube.com/watch?v=kaJqMSBgi00&t=105s)의 오른손으로 꺼내기·입에 가져가 베어 물기·잠깐 내리기·두 번째 한입 흐름을 제작한 불규칙 육포에 적용한다. 해당 구간을 실제 브라우저 화면에서 확인했다. 영상의 소시지를 기존 육포 모델로 바꾸고 엄지·검지로 얇은 끝을 집으며, 손목과 팔은 연결한 채 입을 시점 아래에 둔다. 두 번 베어 문 모양은 원본 재질과 손에 잡힌 부분을 유지하고 노출된 끝만 바꾼다.

구현 시간은 영상 구간에 맞춘 8초이며 조정 가능하다. 음식 효과는 기존 식량의 포만감 32를 재사용한 구현값이다. 완료 시 1개 소비, 중도 취소 시 미소비, F 취소·F2 재시험·원정 격리를 유지한다. 새로운 회복 효과나 식량 밸런스 확정은 아니다.

The referenced 1:45–1:53 sequence was inspected in the browser. Its right-hand draw, bite, brief lowering and second bite are adapted to the existing irregular jerky, using a calibrated thumb/index pinch and connected wrist. The food reaches the lips below the eye camera. Bitten meshes preserve the held end and original material. The adjustable duration is eight seconds; the implementation reuses the existing ration's 32-point hunger effect, commits one item only on completion, and retains cancellation and isolated test-room replay.

### 2026-09-15 사용자 후속 지시 — 나무 막대와 붕대로 부목 제작

사용자는 버클·가죽 스트랩 방식의 부목이 어색하다고 지적하고 [Gray Zone Warfare 영상 31초부터](https://www.youtube.com/watch?v=sjPpfdlupx4&t=31s)처럼 손목 아래에 나무 막대를 받치고 붕대를 감는 방식으로 교체하도록 지시했다. 이전 버클형은 현재 확정 외형이 아니며 제작 이력으로 보존한다. 해당 영상 31~37초의 지지대 배치·팔 회전·붕대 감기·끝 눌러 고정을 실제 브라우저 화면으로 확인했다. 기존 왼팔 치료에 맞춰 좌우 반전하고 현대식 지지대 재질은 단순 나무로 바꾼다. 공통 사용 완료·F 취소 규칙은 유지하며 모션 시간은 7.2초로 조정한다. 제작·실제 검증 상태는 `asset-staging/splint_wrap_20260915/` 기록을 따른다.


### 2026-09-15 사용자 확정 — 제공한 FP arms로 팔·손 교체

제공 파일 `fp_arms.glb`를 1인칭 팔·손 기본 외형으로 사용한다. 검은 소매·갈색 반장갑을 원본대로 유지하고 좌우 실제 뼈대를 기존 무기 동작에 연결했다. 검·방패와 양손 베기의 기존 궤적·장비 위치·전투 규칙은 유지한다. 원본은 `asset-staging/fp_arms_20260915/`에 보존하며 제작·검증은 Mac에서 수행했다. 이번 작업은 1인칭 팔 교체이며 전신 캐릭터 외형 교체를 의미하지 않는다.


### 2026-09-17 사용자 확정 — 제공 모델로 오크 적 추가 / Supplied orc enemy

사용자가 오크의 원본 메시·애니메이션 FBX·텍스처를 제공하고 적 NPC 추가를 요청했다. 기존 캐릭터 그래픽 담당이 원본 도끼·장비·스킨·애니메이션을 통합한다. 구현 판단으로 기존 근접 적 AI와 방패/피격/보상 규칙을 재사용하고 테스트룸 전용 대련 및 폐광 동쪽 창고 적에 적용한다. 던전의 적 수와 기존 창고 적 수치를 유지하며 신규 보스·종족 서사·별도 전투 규칙은 확정하지 않는다.

The user requested an enemy NPC using the supplied orc assets. The implementation reuses existing melee AI, blocking, damage and rewards, with a dedicated test-room duel and the eastern mine store encounter. Existing counts/stats remain unchanged; no new boss, lore or separate combat rules are established.


### 2026-09-17 사용자 후속 확정 — 오크 그래픽 삭제 / Orc graphics removed

사용자가 추가된 몬스터 그래픽을 거부하고 삭제를 요청했다. 위 오크 추가 결정을 철회하여 게임용 오크 모델·행동 코드·테스트룸 대련을 제거하고 동쪽 창고의 기존 검지기를 복원한다. 제작 원본은 보존하며 이 에셋을 재적용하지 않는다. 다른 적과 전투·보상 규칙은 유지한다.

The user rejected the added monster graphics and requested removal, superseding the orc addition above. Remove the runtime asset, controller and trial, restore the original store warden, and preserve the source files without reapplying them. Other enemies and combat/reward rules remain unchanged.

### 2026-09-17 사용자 후속 확정 — CGTrader 크리프 적용 / CGTrader Creep integration

사용자는 오크 삭제 후 지정한 [Creep Creature](https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature)의 모델과 애니메이션을 받아 적용하도록 요청했다. 새 모델의 적용은 확정이며, 이전 오크를 다시 쓰는 결정은 아니다. 제작자는 andriichykrii다. 라이선스에 따른 원본·변환 에셋의 로컬 보관과 공개 저장소 설치 방법은 [크리프 안내](../docs/CREEP_ASSET.md)에 기록한다.

After removing the orc, the user requested the specified Creep Creature model and animations by andriichykrii. This confirms use of the new asset without reinstating the rejected orc. The linked guide documents local asset storage and installation for public-repository users.

구현 판단: 에셋 설치 시 폐광 동쪽 창고 적 한 명과 테스트룸 전용 대련에 연결한다. 기존 적 여섯 명·창고 적 수치·근접 전투·방패·피격·보상·귀환 규칙을 재사용한다. 원본 17개 클립은 보존하고, 게임에서는 대기·추적·물기·양손 연타·피격·사망 6개를 사용한다. 반복이 포함된 공격 클립은 첫 완결 동작 구간만 게임의 한 공격으로 사용한다. 미설치 환경은 기존 검지기를 유지한다. 신규 보스·종족 서사·추가 공격 규칙은 확정하지 않는다.

Implementation choice: integrate one eastern-store encounter and a dedicated test-room duel when installed. Reuse existing encounter count, stats, combat, shield, damage, reward, and extraction rules. Preserve all seventeen clips, connecting six to current behavior and using the first complete cycle of repeating attack clips. Missing-asset environments retain the original warden. No new boss, species lore, or additional combat system is established.

실제 게임 연결과 설치·미설치 자동 검사, GPU 화면 10장 검토를 완료했다. [검증 기록](../artifacts/validation/creep_20260917/README.md)을 따른다. / Integration, installed/missing-asset checks and ten actual GPU renders are verified; see the validation record.

### 2026-09-17 크리프 사망 래그돌 / Creep death ragdoll

사용자 후속 요청에 따라 크리프의 사망을 실제 관절 물리로 연결한다. 구현 범위는 기존 Creep 뼈대의 사망 반응·래그돌 전환·바닥과 벽 접촉이며, 원본 모델과 17개 동작 클립을 보존한다. 살아 있는 적의 공격·방패·피격·처치 보상과 폐광 조우 수는 기존 규칙을 유지한다.

The follow-up request connects Creep death to physical joints. The implementation covers a death reaction, ragdoll transition, and floor/wall contact on the existing skeleton while preserving the source model and all seventeen animation clips. Living attacks, shield interactions, damage, defeat rewards, and mine encounter counts retain their existing rules.

테스트룸에 정면·측면·북쪽 벽 사망 시험을 연결한다. 회복·재생성 후 1초 뒤 실제 피격 함수로 치명타를 주고, F2 일시정지·재선택·초기화·원정 격리를 포함한다. 물리·테스트룸·관련 전투 검사와 실제 GPU 영상 검증을 완료했다. [검증 범위](../artifacts/validation/creep_ragdoll_20260917/README.md)를 따른다.

The test room adds front, side, and north-wall death scenarios. Each heals and respawns, then sends a fatal hit through the real damage function after one second, including F2 pause, replay, reset, and expedition isolation. Physics, test-room, related combat checks and real GPU-video validation passed; see the linked scope and limitations.

## 2026-09-18 크리프 부위 절단 — 사용자 확정 / Creep dismemberment — confirmed

같은 팔·다리·머리를 집중 공격하면 해당 부위를 절단한다. 사용자는 팔다리 절단 후에도 크리프가 살아서 전투를 계속하도록 선택했다. 머리 절단은 즉시 사망이며, 일반 체력 소진에 따른 사망·기존 처치 보상은 유지한다. 초기 구현값(부위당 2회 이상·누적 35, 다리 손실 시 이동 속도 50%/18%)은 조정 가능한 제작 판단이다. 실제 부위 메시·피격 위치·분리 물리·생존 공격·F2 시험을 연결했다. [동작·설치 안내](../docs/CREEP_DISMEMBERMENT.md)와 [검증 근거](../artifacts/validation/creep_dismemberment_20260917/README.md)를 따른다.

Focused hits sever the selected arm, leg or head. The user chose continued combat after limb loss; decapitation kills immediately. Normal health depletion and single death rewards remain. The initial two-hit/35-damage threshold and 50%/18% leg-loss speeds are tunable implementation values. See the linked implementation and validation records.

### 2026-09-18 후속 사용자 확정 — 다리 절단 후 기어가기 / Confirmed follow-up: crawling after leg loss

사용자는 다리가 절단된 크리프가 기어다니도록 요청했다. 한쪽 다리만 잃어도 몸을 지면으로 낮추고 손을 번갈아 뻗어 당기며 이동한다. 기존의 서 있는 추적 자세를 기울여 보이는 방식은 대체한다. 낮은 자세에서는 서서 펀치하지 않고 물기로 공격한다. 팔다리 절단 후 생존, 머리 절단 즉시 사망, 체력 소진과 보상 규칙은 유지한다.

The user requested crawling after leg severance. Losing either leg lowers the body to the ground and alternates reaching and pulling with the supporting hands, replacing the earlier tilted upright pursuit. Attacks use a low bite instead of standing punches. Continued survival after limb loss, immediate death after decapitation, ordinary health depletion and reward rules remain.

구현 판단: 원본 `sleep_loop`의 누운 골격 자세에 코드로 손 IK·몸통 이동을 더하며, 별도 FBX 포복 클립 제작으로 간주하지 않는다. 약 0.48초 자세 전환, 이동 속도 50%/18%, 이동용 캡슐 높이 0.86m, 공격 사거리 1.15m를 조정 가능한 초기값으로 사용한다. `F2 → 기본 → 크리프 절단`의 왼다리·오른다리에 새 동작을 연결하고 양다리 시험을 추가한다. 양다리 시험에만 체력 118을 주고 실제 18 피해 네 번으로 체력 46을 남긴다. 원본 모델·17개 클립과 일반 적 체력은 보존한다.

Implementation choice: use the source prone `sleep_loop` skeletal pose with procedural hand IK and body movement, rather than claiming a separately authored crawl FBX clip. Tunable starting values are a 0.48-second pose transition, 50%/18% movement factors, a 0.86m navigation capsule and 1.15m attack range. Existing left/right-leg F2 trials use the new motion, and a both-legs trial starts at 118 test-only HP before four actual 18-damage hits leave 46 HP. The source model, seventeen clips and normal enemy health are preserved.

관련 자동 검사 7개, 최종 집중 검사와 실제 GPU 영상 36초 검증을 완료했다. 실제 검사·영상과 남은 제약은 [기어가기 검수 기록](../artifacts/validation/creep_crawl_20260918/README.md)에 남기며, 이전 절단 영상의 검증 완료를 새 동작의 완료로 간주하지 않는다. / Seven related suites, a focused final rerun and a 36-second actual GPU video passed. Executed checks, actual video and remaining limits belong in the linked crawl validation record; completion of the earlier dismemberment video does not establish completion of this motion.

### 2026-09-18 후속 사용자 확정 — 랙돌 착지 후 포복 회복 / Confirmed follow-up: prone recovery after a physical fall

다리가 절단되면 바로 포복 자세를 취하지 않고 실제 랙돌로 쓰러진다. 신체가 바닥에 닿고 안정된 뒤 포복 자세를 갖추고 플레이어를 쫓아간다. 이는 앞선 약 0.48초 즉시 포복 전환을 대체한다. 생존 상태의 낙하(`falling`)와 착지 후 자세 전환(`recovering`) 동안 추적과 공격을 중지하며, 실제 쓰러진 뼈 자세에서 포복으로 이어지도록 한다. 사지 절단 후 생존·머리 절단 사망·보상·이동 속도 규칙은 유지한다.

After leg severance, the creature falls with actual ragdoll physics rather than immediately adopting its crawl pose. It begins prone recovery only after its body has landed and stabilized, then pursues the player. This replaces the earlier immediate ~0.48-second crawl transition. Living `falling` and grounded `recovering` phases suspend pursuit and attacks, and recovery starts from the actual physical bone pose. Survival after limb loss, death after decapitation, rewards and movement factors remain unchanged.

착지 판단은 몸통·머리의 지면 접근과 물리 움직임의 안정성을 함께 확인하며 고정 시간만으로 판정하지 않는다. 이 기준과 회복 시간은 구현에서 조정할 수 있는 값이다. 기존 F2 왼다리·오른다리·양다리 항목에 실제 절단 → 랙돌 낙하 → 착지 → 포복 → 전투 재개를 연결하고 각 단계의 일시정지와 중도 취소를 검증했다. 새 `creep_knockdown`을 포함한 **자동 검사 8개와 실제 GPU 영상 60초 검증을 통과**했다. 결과·기록·남은 제약은 [랙돌 착지·회복 검수 기록](../artifacts/validation/creep_living_fall_20260918/README.md), 실제 동작은 [새 시연 영상](../artifacts/validation/creep_living_fall_20260918/creep_living_fall.mp4)에 남긴다. 이전 포복 영상 통과를 이번 물리 전환의 완료 근거로 사용하지 않는다.

Landing uses both torso/head ground proximity and stable physical movement, not a timer alone; thresholds and recovery duration are tunable implementation choices. Existing F2 left-leg, right-leg and both-leg trials exercise real severance, physical fall, landing, prone recovery and resumed combat, with phase pause and cancellation checks. **Eight automated suites and a 60-second actual GPU video review passed**, including the new knockdown suite. Results, evidence and limitations belong in the linked fall/recovery validation record and new demonstration video. The earlier crawl video does not validate this physical transition.

### 2026-09-18 후속 제작 — 포복 중 하체 동작 / Lower-body motion during crawling

포복 중 상체뿐 아니라 골반과 남은 다리도 움직이도록 보완한다. 남은 다리 관절을 원본의 누운 자세에 고정하지 않고 움직이며, 골반은 팔로 몸을 당기는 흐름에 맞춰 무게를 옮긴다. 양다리가 없으면 팔·골반의 움직임으로 진행하고 없어진 다리는 되살리지 않는다. 기존 랙돌 낙하 → 착지·안정 → 포복 회복 → 추적과 낮은 물기 공격, 피해·속도·보상 규칙은 유지한다.

The crawl follow-up moves the pelvis and surviving leg alongside the upper body. Remaining leg joints articulate instead of staying fixed in the source sleeping pose, and pelvic weight shifts follow the arm-pulling rhythm. When both legs are missing, motion uses the arms and pelvis without restoring detached limbs. Existing physical fall, stable landing, prone recovery, pursuit, low bites, damage, speed and reward rules remain intact.

기존 F2 왼다리·오른다리·양다리 시험의 설명과 정지 검사를 확장하고 실제 크리프 추적 경로를 유지한다. 골반·남은 다리 관절을 포함해 F2 정지 시 자세가 고정되는지 확인했다. 관련 자동 검사 **6개와 마지막 조정 후 집중 검사, 실제 GPU 영상 60초 검증을 통과**했다. 새 [검수 기록](../artifacts/validation/creep_lower_body_20260918/README.md)과 [시연 영상](../artifacts/validation/creep_lower_body_20260918/creep_lower_body.mp4)은 이전 랙돌·포복 영상의 검증 완료와 구분한다. 평평한 바닥에서 확인했으며 경사·계단 접지는 미확인이다.

Existing F2 left-leg, right-leg and both-leg descriptions and pause checks are expanded while retaining production Creep pursuit. Pose freezing includes the pelvis and surviving leg joints. **Six related suites, the focused check after the final adjustment, and a 60-second actual GPU video review passed**. The linked new validation record and video are separate from the earlier ragdoll/crawl video results. Validation used a flat floor; slopes and stairs remain unverified.


## 2026-09-18 포복 크리프 검 처형 — 사용자 확정 / Crawling Creep sword execution — confirmed

사용자는 다리가 절단되어 기어다니는 크리프를 처형하는 기능과, 검으로 찔러 넣는 동작 한 가지를 먼저 요청했다. 실제 다리 절단·랙돌 착지·포복 회복을 마친 살아 있는 크리프가 대상이며, 접촉 시 실제 사망·보상·시체 랙돌로 이어진다. 원본 모델과 기존 포복·절단·일반 공격은 보존한다.

The user requested execution of a leg-severed crawling Creep, starting with one sword-stab motion. Eligible living crawlers first complete real severance, physical landing and prone recovery. Contact enters production death, reward and corpse ragdoll. Source models and existing crawl, severance and ordinary attacks are preserved.

초기 제작 판단: 가까운 몸통 조준·LMB 0.4초 이상 누른 뒤 놓기, 검·방패 및 방패 수납 상태 모두 같은 찌르기, 포복 대상에는 추가 저체력·경직 조건 없음. 이는 조정 가능한 조작·밸런스 값이며 다른 적·모든 무기·추가 처형 모션을 확정한 것은 아니다. 같은 변경에서 `F2 → 기본 → 크리프 처형`의 한쪽·양쪽 다리 시험, 실제 플레이 경로와 정지·재시도·원정 복원을 연결한다. 구현·검증 상태는 [처형 안내](../docs/CREEP_EXECUTION.md)를 따른다.

Initial implementation choices: aim at the nearby torso, hold LMB for at least 0.4 seconds and release; one stab with a carried or stowed shield; no extra low-health/stagger gate for crawlers. These are adjustable controls/balance values, not approval of all enemies, weapons or additional execution motions. The same change connects single/both-leg F2 fixtures to actual play, pause/replay and session restoration. The linked guide tracks implementation and verification separately.


이전 1.55초 버전 검증 이력(0.82초 타격·10cm 찌르기): 서로 다른 자동 검사 7종과 실제 GPU `final_04`의 18초 시퀀스(540프레임)·정지 화면 39장을 확인했다. 한쪽 다리 1인칭·같은 절단 상태의 별도 측면 반복·양다리 1인칭 세 사례에서 피부 접촉과 단일 사망을 확인했다. 접근을 실제 충돌 이동으로 바꾼 뒤 오른쪽 어깨 이동 보정은 0m이고 기존 팔 길이는 유지한다. 영상 산출물은 `artifacts/validation/creep_execution_20260918/creep_execution.mp4`에 보존한다. 평평한 시험 바닥에서 검증했으며 경사·계단·다른 적 크기는 미확인이다. 파일 인코딩 검증과 GitHub 게시 상태는 최종 검수 기록을 따른다.

Previous 1.55-second version validation (0.82-second hit, 10cm penetration): seven distinct automated suites and actual GPU `final_04` output—an 18-second, 540-frame sequence and 39 stills. Single-leg first person, a separate side-view repeat and both-leg first person each confirmed skin contact and one defeat. Collision-aware approach removed right-shoulder correction while preserving arm lengths. The video artifact belongs at `artifacts/validation/creep_execution_20260918/creep_execution.mp4`. Validation used a flat inspection floor; slopes, stairs and differently sized enemies remain unverified. The final verification record separately tracks encoded-file checks and GitHub publication.


## 2026-09-19 포복 처형 단계 구분 — 사용자 확정 / Staged crawling execution — confirmed

사용자는 칼을 찌를 자세를 먼저 취하고, 찌른 뒤 더 깊게 넣은 다음 뽑도록 요청했다. 기존 포복 처형의 조작·대상·거리 조건과 F2 시험 흐름은 유지한다. 이전 개정의 제작 값은 전체 2.50초, 첫 찌르기 1.03초·4.5cm, 깊은 결정타 1.52초·22cm, 회수 1.72–2.12초다. 준비·얕은 접촉·깊은 밀기·회수를 분리하고 최초 접촉이 아닌 깊은 결정타에 한 번만 사망·보상을 적용한다. 시작 거리 1.10–1.65m는 유지하고 실제 접근 목표를 1.05m로 조정했다. 새 자동 검사 3종과 GPU `deep_stab_20260919_02` 정면·측면 정지 화면 검증을 통과했고 세 사례의 오른쪽 어깨 이동 보정은 0m다. 최종 `deep_stab_20260919_final03`의 실제 18초 영상(540프레임)과 단계 이미지 27장·MP4 전체 디코딩도 통과했다. 이전 버전 검증과 구분하며 GitHub 상태는 최종 게시 기록을 따른다. [현재 구현·검수 상태](../docs/CREEP_EXECUTION.md).

The user requested preparing to stab, making the first thrust, driving the blade deeper, then pulling it out. Existing controls, target/distance rules and F2 flow remain. Previous revision values were 2.50s total, the initial 4.5cm stab at 1.03s, the deeper 22cm lethal push at 1.52s and withdrawal during 1.72–2.12s. Death/reward occur once on the deeper finishing push, not the first contact. Starting range remains 1.10–1.65m; physical approach now targets 1.05m. Three updated suites and front/side GPU stills from `deep_stab_20260919_02` passed, with zero right-shoulder correction in all three cases. The final `deep_stab_20260919_final03` runtime sequence passed: 18 seconds, 540 frames, 27 stage images and full MP4 decoding. Previous-version results remain separate; GitHub status follows the final publication record. See the current implementation and validation guide.


## 2026-09-19 찌르기 전 멈춤 제거·찔림 반응 — 이전 개정 / Remove pre-stab hold and add recoil — previous revision

사용자는 찌르기 전 대기를 없애고 몬스터가 찔릴 때 움찔하도록 요청했다. 준비 자세에서 멈추던 구간을 없애 0.30초 준비 후 곧바로 찌르며, 첫 얕은 찌르기 0.58초·4.5cm, 깊은 결정타 1.02초·22cm, 회수 1.18–1.58초, 전체 1.96초로 조정한다. 첫 실제 피부 접촉과 깊은 결정타에 가슴·머리 반응을 적용하고 루트·하체와 찌른 지점은 유지한다. 기존 입력·대상 조건, 첫 찌르기 생존, 깊은 결정타의 단일 사망·보상, F2 정지·재시험은 유지한다. 새 자동 검사 4종과 실제 GPU `recoil_20260919_final02`의 18초 무음 영상 540프레임·단계 PNG 33장 및 MP4 전체 디코딩을 확인했다. 세 사례에서 가슴·머리의 실제 골격 반응, 루트 유지와 단일 사망을 검증했고 원본 14개 파일 해시는 보존했다. 경사·계단은 미확인이다. 위 2.50초 버전 결과와 구분하며 GitHub 상태는 최종 게시 기록을 따른다. [현재 검수 상태](../docs/CREEP_EXECUTION.md#검증--validation).

The user requested removing the delay before stabbing and making the monster recoil when struck. Preparation now flows directly into the thrust at 0.30s, reaching a 4.5cm initial stab at 0.58s and a 22cm lethal push at 1.02s; withdrawal spans 1.18–1.58s and the full action lasts 1.96s. Chest/head recoil responds to first actual skin contact and the deeper finishing contact while preserving the root, lower body and stab anchor. Existing input and eligibility, survival through the first stab, single death/reward on the deeper hit and F2 pause/replay remain. Four updated suites passed, as did the actual GPU `recoil_20260919_final02` sequence: an 18-second silent video, 540 frames, 33 stage PNGs and full MP4 decoding. All three cases verified real chest/head skeletal recoil, a fixed root and one defeat; fourteen source-file hashes are preserved. Slopes and stairs remain unverified. These results are separate from the 2.50-second revision above, and GitHub status follows the final publication record. See the current validation record.


## 2026-09-19 깊게 찌를 때 크게 움찔·회수 전 대기 — 이전 22cm 개정 / Stronger deep-stab reaction and hold before withdrawal — previous 22cm revision

사용자는 첫 찌르기는 조용히 받고, 더 깊게 찌를 때 크게 움찔한 뒤 잠시 기다렸다가 칼을 뽑도록 요청했다. 첫 찌르기의 반응은 0으로 하고 깊은 밀기 중 0.88초부터 반응을 시작해 1.02초에 가슴 14°·머리 20°로 최대가 되게 한다. 준비 후 멈춤 없는 연결, 첫 찌르기 0.58초·4.5cm와 깊은 결정타 1.02초·22cm는 유지한다. 결정타 뒤 0.44초 유지하고 1.46–1.86초 회수, 전체 2.24초로 조정한다. 루트·하체와 기존 사망·보상·F2 시험 규칙은 유지한다. 새 자동 검사 2종과 실제 GPU `deep_recoil_20260919_01`의 18초 무음 영상 540프레임·단계 PNG 39장 및 MP4 전체 디코딩을 확인했다. 세 사례 모두 첫 반응 0, 깊은 반응 강도 1, 0.44초 유지·회수와 단일 사망을 확인했다. 원본 14개 파일 해시를 보존했고 이전 1.96초의 4종 검사와 구분한다. GitHub 상태는 최종 게시 기록을 따르며 경사·계단은 미확인이다. [현재 검수 상태](../docs/CREEP_EXECUTION.md#검증--validation).

The user requested a quiet first stab, a pronounced flinch on the deeper push and a brief pause before extraction. Initial recoil is zero; deep recoil begins at 0.88s and peaks at 1.02s with 14° chest and 20° head production rotations. The continuous preparation-to-thrust transition, 4.5cm initial stab at 0.58s and 22cm finishing contact at 1.02s remain. The blade holds for 0.44s after impact, withdraws during 1.46–1.86s and returns by 2.24s. Root/lower-body pose and existing death, reward and F2 trial rules remain. Two updated suites passed, as did actual GPU `deep_recoil_20260919_01`: an 18-second silent video, 540 frames, 39 stage PNGs and full MP4 decoding. All three cases confirmed zero initial recoil, deep recoil weight 1, a 0.44-second hold, withdrawal and one defeat. Fourteen source-file hashes are preserved. These results remain separate from the previous 1.96-second revision's four suites. GitHub status follows the final publication record; slopes and stairs remain unverified. See the current validation record.


## 2026-09-19 더 깊은 찌르기 — 이전 36cm 개정 / Deeper penetration — previous 36cm revision

사용자는 같은 처형에서 칼을 더 깊이 넣도록 요청했다. 깊이를 22cm에서 **36cm**로 14cm 늘리고, 팔 길이를 유지하도록 실제 접근 목표는 1.05m에서 **0.88m**로 17cm 가까이 옮겼다. 첫 찌르기 4.5cm, 가슴 14°·머리 20°의 큰 반응, 결정타 뒤 0.44초 유지와 전체 2.24초를 유지한다. 자동 검사 2종과 실제 GPU `deeper_20260919_01`의 18초 무음 영상 540프레임·단계 PNG 39장, MP4 전체 디코딩을 확인했다. 세 사례 모두 어깨 이동 보정 0m와 원래 팔 길이를 유지하며, 결정타 피부 기하 검사에서는 칼끝이 반대쪽 피부보다 31.6–33.3cm 앞에 남았다. 이 수치는 결정타 자세에 한정한다. 원본 14개 파일 해시를 보존했고 직전 22cm 결과와 구분한다. GitHub 상태는 최종 게시 기록을 따르며 경사·계단은 미확인이다. [현재 검수 상태](../docs/CREEP_EXECUTION.md#검증--validation).

The user requested a deeper insertion in the same execution. Depth increases 14cm from 22cm to **36cm**, with actual approach moving 17cm closer from 1.05m to **0.88m** to preserve arm reach. The 4.5cm first stab, 14° chest/20° head recoil, 0.44-second hold and 2.24-second duration remain. Two suites and actual GPU `deeper_20260919_01` passed: an 18-second silent video, 540 frames, 39 stage PNGs and full MP4 decoding. All three cases retain zero shoulder translation correction and original arm lengths; finishing-contact skin geometry places the tip 31.6–33.3cm before the far exit. That geometric result is limited to the finishing-contact pose. Fourteen source-file hashes are preserved, and previous 22cm validation remains separate. GitHub status follows the final publication record; slopes and stairs remain unverified. See the current validation record.


## 2026-09-19 칼날 절반 정도가 묻히는 처형 — 이전 개정 / Bury approximately half the blade — previous revision

사용자는 칼이 실제로 절반 정도 몸에 묻히도록 요청했다. 원본 칼날 약 1.045m의 55%인 **0.57475m**를 동적으로 계산하며, 접근 목표는 **0.84m**, 접근 속도는 기존 2.8m/s다. 깊게 미는 상체 숙임을 추가해 팔 길이를 유지하고, 첫 찌르기·반응·0.44초 유지·전체 2.24초는 보존한다. 최종 포복·시험룸 검사 2종과 같은 작업의 기존 검·방패 처형 회귀 검사를 통과했다. 실제 GPU `half_blade_20260919_03` 18초·540프레임·39단계 PNG에서 세 결정타 모두 어깨 보정 0m를 확인했다. 결정타의 실제 피부 기하 검사에서 칼날 55.46–55.56%가 몸 안에 있고 반대쪽 피부까지 10.1–11.8cm 남았으며, 이 수치는 그 자세에 한정한다. 원본 16개 파일 해시를 보존했다. MP4 인코딩·전체 540프레임 디코딩도 통과했으며 GitHub 상태는 최종 게시 기록을 따른다. 이전 36cm 결과와 구분하고 경사·계단은 미확인이다. [현재 검수 상태](../docs/CREEP_EXECUTION.md#검증--validation).

The user requested burying approximately half of the actual blade. Depth dynamically uses **0.57475m**, or 55% of the approximately 1.045m source blade, with a **0.84m** approach target and original 2.8m/s speed. Added upper-body lean preserves arm lengths; initial-stab, recoil, 0.44-second hold and 2.24-second duration remain. Both final crawler/trial suites and the existing sword/shield execution regression passed during this task. Actual GPU `half_blade_20260919_03` records 18 seconds, 540 frames and 39 stage PNGs with zero shoulder correction at all three finishing contacts. Actual-skin contact-pose geometry places 55.46–55.56% inside and leaves 10.1–11.8cm to the far-side skin; those values cover that pose only. Sixteen source-file hashes are preserved. MP4 encoding and full 540-frame decoding also passed; GitHub status follows the final publication record. Previous 36cm results remain separate; slopes and stairs remain unverified. See the current verification record.


## 2026-09-19 검이 몸에서 빠질 때 랙돌 — 사용자 확정 / Start ragdoll when the blade clears — confirmed request

사용자는 칼이 몸에서 뽑혀 나오는 시점에 랙돌을 시작하도록 요청했다. 깊은 결정타 1.02초의 사망·보상 1회는 유지하고, 그 후에는 `execution_hold`로 죽은 몸의 움찔한 골격 자세를 고정하며 아직 물리 몸체를 만들지 않는다. 1.46초 발검 시작 후 실제 칼끝이 원래 피부 진입점에서 1cm 밖으로 나오면(현재 약 1.70초) 추가 반응 대기 없이 바로 중력 랙돌로 넘긴다. 검 깊이 55%, 깊은 위치 0.44초 유지와 전체 2.24초를 보존한다. 취소·장비 교체·플레이어 사망/제거는 고정을 즉시 풀고, F2 정지는 대기·발검·해제 판정을 함께 멈춘다. 자동 검사 4종과 실제 GPU `withdraw_ragdoll_20260919_01`의 18초·540프레임·PNG 48장 검수를 통과했다. 세 사례 모두 1.70초 칼끝 이탈 시 추가 반응 지연 없이 물리를 시작했고 1인칭·측면에서 유지→이탈→낙하를 확인했다. MP4 전체 540프레임 디코딩과 원본 파일 16개의 해시 보존도 확인했으며 GitHub 상태는 최종 게시 기록을 따른다. 직전 칼날 절반 결과와 구분하며 경사·계단은 미확인이다. [현재 검수 상태](../docs/CREEP_EXECUTION.md#검증--validation).

The user requested starting ragdoll when the blade is pulled clear of the body. The 1.02s finishing contact still commits one defeat/reward, then `execution_hold` freezes the defeated recoil pose without creating physical bodies. Extraction begins at 1.46s; when the actual tip is 1cm outside the original skin-entry anchor (currently about 1.70s), gravity ragdoll starts immediately without an extra reaction wait. The 55% penetration, 0.44s deep hold and 2.24s total remain. Cancellation, equipment changes or player death/removal release the held corpse immediately; F2 freezes the wait, extraction and release evaluation. Four automated suites and actual GPU `withdraw_ragdoll_20260919_01` passed: 18 seconds, 540 frames and 48 PNGs. All three cases begin physics at 1.70s tip clearance without added reaction delay; hold→clearance→fall was inspected from first-person and side views. Full 540-frame MP4 decoding and preservation of sixteen source-file hashes also passed; GitHub status follows the final publication record. Previous half-blade validation remains separate; slopes and stairs remain unverified. See the current verification record.


## 2026-09-19 방패 내구도별 실제 파손 — 사용자 확정 / Physical shield damage by durability — confirmed request

사용자는 방패의 상·중·하 실제 파손 외형과 1인칭 표시를 요청했고, **2026-09-19 후속으로 내구도 0에서 실제 파편으로 부서지는 동작을 요청했다.** 이 결정은 이전의 0에서도 하 단계 방패로 계속 방어한다는 구현을 대체한다. 내구도가 양수인 세 단계에서는 방어 성능을 약화하지 않는다. 실제 방패로 막힌 타격이 내구도를 소진하면 마지막 가드의 피해 차단·기력·저스트 가드 스턴을 먼저 해결하고 방패 개체를 장착 슬롯에서 제거한다. 왼손은 기존 검의 보조 파지로 전환하며 이후에는 검의 방어 규칙만 사용한다.

조정 가능한 구현값: 개체별 최대 내구도 100, 양수 비율 2/3 초과 상·1/3 초과 중·나머지 하, 실제 막은 피해×0.25 마모(저스트 가드 포함). 파편은 최대 32개의 실제 물리 몸체로 월드에만 충돌하고 중력으로 떨어지며 24초 후 정리한다. F2는 물리와 수명을 정지하고 재선택·초기화·이탈은 즉시 정리한다. 데이터 setter가 0을 지정하는 것만으로는 물품 삭제나 파편이 생기지 않지만 해당 방패는 숨김·사용 불가다. 수리·파편 회수·다른 장비 내구도는 추가하지 않는다.

F2에 세 단계 비교·실제 마모와 내구도 5의 완전 파괴 시험을 연결했다. **완전 파괴는 관련 고유 자동 검사 7종과 Mac GPU 8초·240프레임·PNG 6장 검수를 통과했다.** 마지막 물리 검사는 32/32 접지·안정화와 24초 정리를 확인했고 GPU 8초 시점에는 32개 접지·31개 안정화, 충돌체 최저점 -0.01655m를 확인했다. 과대 철테 충돌체를 실제 파편 분리·관성·접지 회전 저항으로 수정했으며 위치 강제 보정은 쓰지 않는다. 소스 95개·원정·커서를 보존했다. MP4 인코딩·240프레임 전체 디코딩도 통과했다. GitHub 확인은 대기이며 경사·계단·OS 직접 입력은 미확인이다. 이전 3단계·재질 검증은 별도 과거 기록으로 보존한다. 기존 검격·옛 손 모델 검사 실패 역시 해결했다고 주장하지 않는다. [현재 구현·과거 검수 상태](../docs/SHIELD_DAMAGE.md).

The user requested high/medium/low physical shield damage visible in first person, then **on 2026-09-19 requested shattering at zero condition**. This supersedes the former zero-condition blocking implementation. Positive-condition stages retain defensive strength. A shield-blocked hit that exhausts condition resolves full protection, stamina and timed-guard stun first, then removes the item from its equipment slot. The left hand transitions to sword support; later defense uses the remaining sword's rules.

Tunable implementation values are 100 maximum condition, positive high above two thirds, medium above one third, low otherwise, and 25% wear from actual blocked damage including just guard. Up to 32 real physics fragments use world-only collision and gravity, then expire after 24 seconds. F2 pauses physics/lifetime; replay, reset and exit clear them. A data-only zero setter hides/disables the shield without deleting the item or spawning debris. Repairs, fragment collection and other-equipment durability are not added.

F2 connects the three appearance comparisons, live wear and a five-condition destruction fixture. **Destruction passed seven distinct related suites and actual Mac GPU review**, with eight seconds, 240 frames and six PNGs. Final physics verifies 32/32 contacts and settling plus 24-second cleanup; the GPU endpoint has 32 contacts, 31 settled pieces and minimum collision height -0.01655m. Actual piece separation, hull inertia and contact rolling resistance corrected the oversized rim collider without forced position correction. Ninety-five source hashes, expedition and cursor state were preserved. MP4 encoding and full 240-frame decoding also passed. GitHub confirmation remains pending; slopes, stairs and manual OS input are unverified. Earlier stage/material validation is preserved separately. Existing blade-clash/old-hand-model failures are not claimed fixed. See the linked implementation and validation record.
