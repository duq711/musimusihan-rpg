# 방패 내구도와 실제 파손 / Shield durability and physical damage

2026-09-19 후속 사용자 요청에 따라 내구도가 다한 방패는 실제 3D 파편으로 부서진다. 이전의 **내구도 0에서도 방어 유지** 규칙은 이 요청으로 대체한다. 내구도가 남아 있는 동안 상·중·하 세 파손 외형을 사용하고, 마지막 타격이 내구도를 소진하면 방어를 먼저 해결한 뒤 방패를 제거하고 파편 물리를 시작한다. 수치와 마모량은 조정 가능한 구현값이다.

The 2026-09-19 follow-up request makes an exhausted shield break into real 3D debris. This supersedes the previous rule that **zero durability still allows blocking**. Positive condition uses high, medium and low damage models; a final wearing hit resolves its block first, then removes the shield and starts fragment physics. Thresholds and wear amounts remain adjustable implementation values.

## 내구도와 단계 / Durability and stages

내구도는 방패 개체의 `instance.durability`에 저장하고 기본 최대값은 **100**이다. 장비 교체·가방 보관·원정 장면 전환에 같은 개체의 값을 이어 쓴다. 일반 원정의 디스크 저장 기능을 새로 추가한 것은 아니다.

| 단계 / Stage | 현재/최대 내구도 비율 / Current-to-maximum ratio | 외형·사용 / Appearance and use |
|---|---|---|
| 상 / `high` | `ratio > 2/3` | 기존 원본 방패 / Original shield |
| 중 / `medium` | `1/3 < ratio <= 2/3` | 중간 파손 GLB / Moderately damaged GLB |
| 하 / `low` | `0 < ratio <= 1/3` | 심한 파손 GLB / Heavily damaged GLB |
| 완전 파괴 / Shatter event | 실제 방패 타격으로 양수 → 0 / Shield-blocked hit exhausts positive condition | 장착 방패 제거·물리 파편 / Equipped shield removed; physical debris |

정확히 2/3이면 중, 정확히 1/3이면 하다. 세 단계 사이에는 방어 성능 차이를 추가하지 않는다. 기존 원본과 손잡이·손·팔 연결을 보존하며 중·하 모델은 `assets/3d/player/shield_damage/round_shield_medium.glb`·`round_shield_low.glb`다. Mac 제작 원본은 프로젝트 루트의 `asset-staging/shield_damage_20260919/shield_medium.blend`·`shield_low.blend`에 보존한다.

Durability is stored per shield in `instance.durability`, with a default maximum of **100**, and follows that item through equipment swaps, bag storage and expedition scene transitions. This does not add disk saving. Exactly two thirds is medium and exactly one third is low; positive-condition stages do not reduce blocking strength. Existing grip, hands and arms remain attached to the same authored model. The listed game GLBs and preserved Mac sources retain the three-stage models.

## 실제 방어와 완전 파괴 / Blocking and complete destruction

실제 방패로 막힌 타격에서 **들어온 피해량 × 0.25**를 소모하며 저스트 가드도 포함한다. 피해 20을 막으면 내구도 5가 줄고, 0 미만으로 내려가지 않는다. 측면·후방·환경 피해, 수납한 방패, 검만으로 한 방어는 방패 마모나 파괴를 발생시키지 않는다.

내구도가 양수에서 0이 되는 **마지막 타격은 완전히 막는다**. 일반 가드의 기력 소모나 저스트 가드의 기력 회복·적 스턴을 먼저 해결한 뒤, 실제 장착 슬롯에서 방패 개체를 제거한다. 파괴된 방패를 가방이나 회수 물품으로 돌려주지 않는다. 방패 가드는 즉시 끝나고 왼손은 기존 검의 보조 파지로 전환한다. 이후에는 남은 검의 기존 방어 규칙을 사용한다.

안전한 데이터 편집을 위해 `set_equipment_durability(..., 0)`만 호출한 경우에는 물품을 삭제하거나 파편을 만들지 않는다. 다만 내구도 0 방패는 **화면에서 숨기고 사용 불가**로 처리한다. 내부 단계 계산이 0을 `low`로 반환하더라도 하 단계 방패로 계속 방어할 수 있다는 뜻은 아니다. 파편화는 실제로 막은 타격이 양수 내구도를 0으로 만든 경우에만 발생한다. 수리·파편 회수·다른 장비의 내구도는 이번 범위에 포함하지 않는다.

A shield-blocked hit consumes **incoming damage × 0.25**, including just guard. Side/rear or environmental damage, a stowed shield and sword-only guards do not wear or break the shield. **The final hit is fully blocked**: ordinary stamina cost or just-guard refund/stun resolves before the shield instance is removed from its equipment slot. It is not returned to the bag or turned into collectible loot. Shield guard ends immediately and the left hand transitions to the existing sword-support grip; later guards follow the remaining sword's rules.

Calling the data setter with zero alone does not remove the item or create debris, but that zero-condition shield is **hidden and unusable**. The internal stage label can still be `low` at zero without granting protection. Only an actual blocked hit that exhausts previously positive condition triggers shattering. Repairs, fragment collection and durability for other gear are outside this change.

## 파편과 정리 / Debris and cleanup

파편은 실제 `RigidBody3D`이며 한 번의 파괴에서 **최대 32개**로 제한한다. 중력과 월드 충돌을 사용하고 플레이어·적·다른 파편과의 충돌로 전투를 방해하지 않는다. 월드 충돌 마스크는 레이어 2다. 파편은 장착 방패나 손을 따라다니지 않고 월드에 남아 떨어진다. 수명은 **24초**이며 F2 메뉴에서는 물리와 수명 시간이 함께 정지한다. 새 시험 항목·재선택·초기화·이탈은 파편을 즉시 정리한다.

Fragments are real `RigidBody3D` bodies, limited to **32 per break**, with gravity and world-only collision on mask 2. They do not collide with the player, enemies or each other, and fall independently in world space instead of following the equipped hand. Lifetime is **24 seconds**, paused together with physics by F2. Changing/reselecting a trial, reset and exit clear fragments immediately.

## 1인칭과 테스트룸 / First person and test room

`F2 → 기본`의 `방패 파손 · 상 (75)`·`중 (50)`·`하 (20)`은 해당 내구도의 방패와 AI가 정지된 적 한 명을 준비한다. `RMB`로 기본 위치와 가드를 비교한다. `방패 파손 · 실제 타격 마모`는 내구도 75와 실제 검지기 AI를 준비하며 피해 21 타격을 막을 때마다 5.25가 닳는다.

새 **`방패 파손 · 완전 파괴와 파편`** (`shield_damage:shatter`)은 내구도 **5**에서 시작한다. `RMB`로 실제 적의 피해 21 공격을 한 번 막으면 0이 되어 마지막 공격 차단→장착 방패 제거→파편 낙하→검 양손 파지를 시험할 수 있다. `F2`로 물리를 정지·재개하고 같은 항목을 다시 선택하면 이전 파편을 지우고 내구도 5 방패를 다시 준비한다. 전체 초기화는 별도 시험 가방의 최대 내구도 100으로 돌아간다. 나가면 원래 원정의 물품 개체와 내구도를 복원한다. [상세 실행 절차](../TEST_ROOM.md#방패-내구도3단계-파손--shield-durability-and-three-damage-stages).

Under F2 → 기본, high (75), medium (50) and low (20) entries prepare static comparisons, while actual wear starts at 75 with a live warden and costs 5.25 per blocked 21-damage hit. The new **complete destruction and debris** entry (`shield_damage:shatter`) starts at **5**. One real blocked strike demonstrates the final block, equipment removal, falling debris and two-handed sword support. F2 pauses/resumes physics; reselecting clears debris and restores a five-condition trial shield. Full reset creates a fresh isolated inventory at 100; exit restores the original expedition's item instances and condition.

## 검증 상태 / Validation status

**완전 파괴 후속 변경의 자동 검사와 실제 화면 검증을 완료했다.** 서로 다른 관련 검사 7종(`shield_shatter`, `shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session`, `test_room`)이 통과했다. 마지막 `shield_shatter` 실행은 **32/32 바닥 접촉·32/32 안정화**, 강화한 **바닥 관통 허용 2.5cm**, 24초 수명 만료 경계, 마지막 일반/저스트 가드·중복 파괴 방지·F2 정지/재선택/초기화·원정 복원을 확인했다.

최종 Mac 숨김 GPU 4차 촬영은 **1280×720·30fps·8초·240프레임·PNG 6장**으로 통과했다. 32개 모두 바닥에 접촉했고 촬영 8초 시점에는 31개가 안정화됐다. 충돌체 최저점은 **-0.01655m**로 2.5cm 허용 범위 안이다. 대기·파괴·38프레임·착지 화면을 직접 열어 검토했고 소스 95개의 해시, 원정과 커서를 보존했다. 촬영 카메라가 0.9–1.7초에 아래를 보는 것은 검수 연출이며 실제 게임 카메라를 강제로 움직이지 않는다.

중간 검수에서 큰 철테가 중앙 금속 파편 `metal029`와 잘못 묶여 0.85×0.638m짜리 볼록 충돌체가 된 문제를 찾았다. 실제 정점 반경으로 철테를 분리하고 뒷면 부속을 가까운 나무 조각에 연결해 중앙 돌출 금속을 **0.174×0.174×0.0386m**로 바로잡았다. 파편 32개가 모두 닫힌 형상이며 원본과의 최대 오차는 **0.0499mm**다. 적절한 볼록체 관성과 실제 접지 시 회전 저항을 사용하며 월드 좌표를 강제로 올려 바닥 문제를 감추지 않는다.

[새 검수 기록](../artifacts/validation/shield_shatter_20260919/README.md)에 결과를 보존한다. 무음 [검수 영상](../artifacts/validation/shield_shatter_20260919/shield_shatter.mp4)은 **939KiB·1280×720·30fps·8초·240프레임**이며 MP4 인코딩과 전체 디코딩을 통과했다. 현재 소스 95개의 해시 일치도 다시 확인했고 [검수 요약](../artifacts/validation/shield_shatter_20260919/summary.json)에 기록했다. GitHub 원격 반영 여부는 최종 게시 기록을 따른다. 경사·계단과 OS 직접 입력 검수는 미확인이다. 아래 기존 3단계·목섬유 검수는 과거 기록으로 구분한다.

**Automated and actual-render validation of complete destruction is complete.** Seven distinct related suites passed: `shield_shatter`, `shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session` and `test_room`. The final focused run verifies **32/32 floor contacts and 32/32 settled fragments**, a stricter **2.5cm penetration limit**, the 24-second lifetime boundary, final ordinary/timed guard, single destruction, F2 pause/replay/reset and expedition restoration.

Final hidden Mac GPU capture 4 passed with **1280×720, 30fps, eight seconds, 240 frames and six PNGs**. All 32 fragments contact the floor; 31 are settled at eight seconds. Minimum collision height is **-0.01655m**, within the 2.5cm allowance. Ready, break, frame 38 and settled images were opened for review; 95 source hashes, expedition and cursor state were preserved. Looking down from 0.9–1.7 seconds belongs only to the capture camera, not forced gameplay movement.

An intermediate inspection found the large rim incorrectly grouped into central fragment `metal029`, producing an oversized 0.85×0.638m convex collider. Radial classification of actual vertices and attachment of rear hardware to nearby wood reduced the central boss to **0.174×0.174×0.0386m**. All 32 pieces are closed, with **0.0499mm** maximum deviation from the source. Correct hull inertia and real-contact rolling resistance solve the fall without forced world-position correction.

The linked new validation record preserves this evidence. The silent review MP4 is **939KiB, 1280×720, 30fps, eight seconds and 240 frames**; encoding and full decoding passed. The current 95 source hashes were verified again and recorded in the linked validation summary. GitHub publication confirmation follows the final publication record. Slopes, stairs and manual OS input remain unverified. Earlier three-stage and grain checks below remain historical.

검사 명령 / Test command: `./tests/run_headless_tests.sh shield_shatter shield_damage shield_guard primary_shield_stow first_person_renderer test_room_session test_room`.

### 이전 3단계 구현의 검증 기록 / Earlier three-stage validation

`shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session`, `test_room`의 **서로 다른 자동 검사 6종이 통과**했다. 집중 검사는 임계값 경계·저스트 가드 포함 실제 마모·비방어 피해 예외·0 하한·단계 메시 교체·개체 보존·F2 정지/반복/복원과 1인칭 손잡이 연결을 확인한다. 1차 실제 이미지에서 발견한 중 단계 철테의 회색 절삭 형상 잔류는 제거했고, 마지막 모델 수정 후 정점 반경 회귀 검사를 포함한 `shield_damage`를 다시 통과했다.

최종 Mac 숨김 GPU `artifacts/visual_qa/shield_damage/shield_damage_20260919_02`의 manifest 실패는 없다. **비교 PNG 12장·마모 전환 PNG 4장과 1280×720·30fps·8초·240프레임**을 기록했다. 촬영에서는 실제 피해 40을 다섯 번 막아 **75→65(중)→55→45→35→25(하)**로 변했으며 건강·가드·손잡이 접촉을 유지했다. 이는 F2의 피해 21 대련과 구분되는 촬영용 실제 타격 값이다. 기본 위치·가드에서 파손이 보이며 밝힌 앞·뒤 검수에서도 파단과 손잡이를 직접 확인했다. 촬영 전후 소스 파일 88개의 해시가 같고 원정·커서가 보존됐다. 무음 검수 영상은 [shield_damage.mp4](../artifacts/validation/shield_damage_20260919/shield_damage.mp4)에 저장했고 MP4 인코딩과 240프레임 전체 디코딩이 모두 종료 코드 0으로 통과했다. 같은 검증 폴더에 안내·요약·검사 로그를 보존했다. GitHub 반영은 최종 게시 기록을 따른다.

기존 검사 `sword_clash`와 `first_person_motion_test_room`은 실패했으나 수정 전 기준본과 오류 목록·순서가 완전히 같았다(로그 ERROR 줄 각각 4개·64개). 기존 검격·이전 손 모델의 실패는 이번 6종 통과와 구분하며 해결했다고 주장하지 않는다. OS 하드웨어 입력 검수는 하지 않았고, 실제 플레이 코드에 연결된 숨김 실행으로 검증했다.

**Six distinct automated suites passed:** `shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session` and `test_room`. Focused coverage includes threshold boundaries, actual wear including just guard, non-blocked-hit exceptions, the zero floor, model switching, instance preservation, F2 pause/replay/restore and first-person grip attachment. Gray cutting geometry found on the medium rim in the first actual images was removed. After the final model correction, `shield_damage` passed again with a vertex-radius regression check.

Final hidden Mac GPU output at `artifacts/visual_qa/shield_damage/shield_damage_20260919_02` has no manifest failures. It records **12 comparison PNGs, 4 wear-transition PNGs and 1280×720, 30fps, 8 seconds, 240 frames**. Five actual blocked 40-damage hits produce **75→65 (medium)→55→45→35→25 (low)** while preserving health, guard and grip contact. The capture's 40-damage hits are separate from the 21-damage live F2 duel. Direct inspection confirms visible damage in idle/guard and fracture/grip geometry in brighter front/rear views. Eighty-eight source-file hashes match before/after capture, and expedition/cursor state is preserved. The silent review video is saved at [shield_damage.mp4](../artifacts/validation/shield_damage_20260919/shield_damage.mp4). MP4 encoding and full decoding of all 240 frames passed with exit code 0; the same validation folder retains the guide, summary and test logs. GitHub status follows the final publication record.

Existing `sword_clash` and `first_person_motion_test_room` checks still fail, with error lists and ordering identical to the unchanged baseline (4 and 64 ERROR log lines respectively). Those blade-clash/old-hand-model failures are separate from the six passing suites and are not claimed fixed. Validation uses hidden execution of production game code, not OS hardware input testing.

## 2026-09-19 이전 재질 보완 기록 / Earlier fracture growth-ring and fibre revision

단색으로 밋밋했던 절단면을 보완하기 위해 중·하 방패의 노출 목재 재질 `FP_ShieldFractureOak`에만 나이테·기공·길게 이어지는 목섬유와 미세한 표면 요철 표현을 추가했다. [절단면 셰이더](../shaders/shield_fracture_wood.gdshader)는 판재의 로컬 Y축을 섬유 방향으로 삼고 3D 모델 내부 좌표로 나이테를 계산하므로 비스듬한 파단면에서도 결이 이어지며 방패와 함께 움직인다. [재질 연결](../scripts/shield_damage_visual.gd)은 해당 단면만 교체한다. 상 모델·기존 겉면·파손 형상·손잡이와 내구도·마모 규칙은 그대로다.

The medium/low shield's exposed `FP_ShieldFractureOak` material gains growth rings, pores, longitudinal fibres and subtle surface relief. The linked fracture shader uses local Y as the plank/fibre axis and solid object-space coordinates, keeping grain continuous across angled breaks and attached to the shield. Material binding targets only the fracture surface. The high model, existing exterior, damage geometry, grip and durability/wear rules remain unchanged.

이전 재질 보완은 `shield_damage`·`first_person_renderer` 자동 검사 2종과 최종 Mac 숨김 GPU `artifacts/visual_qa/shield_damage/shield_grain_20260919_02`를 통과했다. 첫 촬영에서 균일하게 보이던 줄무늬를 불규칙한 폭·색과 목섬유로 다듬어 다시 촬영했다. **1인칭 6장·앞뒤 6장·단면 근접 2장·피격 전환 4장, 총 PNG 18장**을 기록하고 중·하 근접, 실제 하 단계 가드와 중 단계 기본 화면을 열어 확인했다. 촬영 전후 소스 89개의 해시와 원정·커서를 보존했고 상 단계 기본·가드 이미지는 이전 결과와 바이트 단위로 같았다. [무음 검수 영상](../artifacts/validation/shield_grain_20260919/shield_grain.mp4)은 1280×720·30fps·8초·240프레임이며 인코딩과 전체 디코딩이 종료 코드 0으로 통과했다. [검수 요약](../artifacts/validation/shield_grain_20260919/validation_summary.json)에 근거를 보존했다. GitHub 상태는 최종 게시 기록을 따른다.

This material follow-up passed the `shield_damage` and `first_person_renderer` suites and final hidden Mac GPU capture `artifacts/visual_qa/shield_damage/shield_grain_20260919_02`. Uniform bands seen in the first capture were refined into irregular widths, colours and fibres before recapturing. **Eighteen PNGs cover six first-person views, six front/rear views, two fracture closeups and four wear transitions.** Both medium/low closeups and actual low-guard/medium-idle views were opened for inspection. Eighty-nine source hashes and expedition/cursor state were preserved across capture; high-stage idle/guard images remain byte-identical to the prior result. The linked silent review video contains 1280×720, 30fps, eight seconds and 240 frames; encoding and full decoding passed with exit code 0. Evidence is saved in the linked validation summary. GitHub status follows the final publication record.

기존 파손 실루엣은 유지한다. 미세 요철은 빛에 반응하는 표면 표현이며 새로 떨어져 나오는 목섬유·파편 형상을 추가한 것은 아니다. 이전 재질 검수는 위의 기존 3단계 구현 및 새 완전 파괴 검수와 구분하며 새 OS 직접 입력·전체 던전 플레이 검수는 하지 않았다.

The existing fracture silhouette remains. Fine relief is a shading effect, not newly modelled loose fibres or fragments. This material validation is separate from the earlier three-stage implementation checks; no new manual OS-input or full-dungeon-play validation was performed.
