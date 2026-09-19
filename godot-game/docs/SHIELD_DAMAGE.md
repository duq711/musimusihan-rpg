# 방패 내구도와 실제 파손 / Shield durability and physical damage

2026-09-19 사용자 요청은 방패 상태를 상·중·하 세 단계의 실제 파손 형태로 만들고 1인칭에서도 보이게 하는 것이다. 단계별 외형은 실제 3D 방패 메시로 표현한다. 원본 상 단계 모델, 손잡이·손·팔과 기존 캐릭터 의상은 보존한다. 다음 수치와 마모 규칙은 이번 구현을 위한 조정 가능한 값이며 사용자 확정 수치와 구분한다.

The request is to show high, medium and low shield condition as real 3D damage, including the first-person view. The original high-condition model, grip, hands, arms and costume remain. The numerical thresholds and wear rules below are adjustable implementation choices, separate from the user's requested visual result.

## 내구도와 단계 / Durability and stages

방패는 물품 개체별로 현재 내구도와 최대 내구도를 가지며 기본 최대값은 **100**이다. 기존 방패 설명의 내구도 문구와 달리 실제 개체 상태를 사용한다. 상태는 현재/최대 비율로 계산한다.

| 단계 / Stage | 현재/최대 내구도 비율 / Current-to-maximum ratio | 외형 / Appearance |
|---|---|---|
| 상 / `high` | `ratio > 2/3` | 기존 원본 방패 / Original shield |
| 중 / `medium` | `1/3 < ratio <= 2/3` | 새 중간 파손 GLB / New moderately damaged GLB |
| 하 / `low` | `0 <= ratio <= 1/3` | 새 심한 파손 GLB / New heavily damaged GLB |

경계값은 정확히 2/3이면 중, 정확히 1/3이면 하다. **0도 하 단계에 포함**하며 방패를 자동 삭제·폐기하거나 네 번째 완전 파괴 상태를 추가하지 않는다. 새 모델은 손잡이 위치를 유지한 채 방패 본체의 실제 파손 형상을 바꾼다. 새 게임용 파일은 `assets/3d/player/shield_damage/round_shield_medium.glb`와 `round_shield_low.glb`다. Mac 제작 원본은 `asset-staging/shield_damage_20260919/shield_medium.blend`와 `shield_low.blend`에 보존한다. 최종 실제 화면에서 기본 위치와 가드 양쪽의 파손 차이·파단면·손잡이 연결을 확인했다.

Durability belongs to each shield item instance, with a default maximum of **100**, and uses the current/maximum ratio. Exactly two thirds is medium; exactly one third is low. **Zero remains low**: the shield is not automatically deleted/discarded, and there is no fourth destroyed state. Actual damaged geometry replaces the shield body while retaining grip placement. New game assets are `assets/3d/player/shield_damage/round_shield_medium.glb` and `round_shield_low.glb`. Mac authoring files are preserved at `asset-staging/shield_damage_20260919/shield_medium.blend` and `shield_low.blend`. Final actual renders verified damage differences, fracture surfaces and grip attachment in both idle and guard views.

## 실제 방어와 마모 / Blocking and wear

실제 방패로 막힌 타격에서 **들어온 피해량 × 0.25**만큼 내구도를 줄인다. 저스트 가드도 방패로 막은 타격이므로 같은 마모를 적용한다. 예를 들어 피해 20을 막으면 내구도 5가 줄며, 내구도는 0 아래로 내려가지 않는다. 방패로 막지 못한 타격이나 환경 피해에 마모를 임의로 더하지 않는다.

이번 세 단계는 외형과 개체 내구도 변화이며 **방어 성능의 단계별 약화는 추가하지 않는다**. 기존 정면 방어의 완전 피해 차단, 저스트 가드 스턴, 기력 소모와 기력 0의 방패 올리기 거절을 유지한다. 내구도 0에서도 하 외형을 유지하며 별도의 가드 금지 규칙을 추가하지 않는다. 수리·마모 회복이나 다른 무기 내구도는 이번 범위에 포함하지 않는다.

A production shield-blocked hit consumes **incoming damage × 0.25** durability, including a just guard. For example, blocking 20 damage costs 5 durability. Values clamp at zero; unblocked or environmental hits do not acquire shield wear. This revision changes appearance and item condition, **not stage-based defensive strength**. Existing full frontal damage blocking, just-guard stun, stamina costs and rejection of guard at zero stamina remain. Zero durability keeps the low appearance without adding a new guard restriction. Repairs, condition recovery and durability for other weapons are outside this change.

## 1인칭과 테스트룸 / First person and test room

1인칭의 기본 방패 위치·가드·막힘 충격·수납에서 같은 개체의 파손 상태를 사용한다. 상·중·하 모델의 손잡이 연결을 유지하며 내구도 변화가 검·손·팔 자세를 바꾸지 않도록 한다. 실제 화면 검수는 부드러운 시험 조명과 게임의 1인칭 카메라에서 따로 확인한다.

`F2 → 기본`의 `방패 파손 · 상 (75)`·`중 (50)`·`하 (20)`은 해당 내구도의 방패와 AI가 정지된 적 한 명을 준비한다. `RMB`로 기본 위치와 가드를 비교한다. `방패 파손 · 실제 타격 마모`는 내구도 75와 실제 검지기 AI를 준비한다. 피해 21 타격을 막으면 1회에 5.25가 닳는다. F2로 기력을 회복하며 계속 시험하고 같은 항목 재선택은 75에서 다시 시작한다. 전체 초기화는 새 시험 가방의 최대 내구도 100으로 복구한다. 시험 중에는 별도 원정을 사용하고, F2 메뉴가 열리면 전투·마모가 정지하며 종료할 때 원래 원정·물품 개체와 내구도를 복원한다. [상세 실행 절차](../TEST_ROOM.md#방패-내구도3단계-파손--shield-durability-and-three-damage-stages).

Idle carry, guard, block impact and stow must show the same shield instance's condition in first person. Damaged models keep grip attachment and do not change sword, hand or arm pose. Rendering checks separately inspect the geometry under neutral lighting and the production first-person camera. Under F2 → 기본, high (75), medium (50) and low (20) entries prepare the respective condition and one paused enemy; use RMB to compare idle and guard. The actual-wear entry starts at 75 with a live warden: each blocked 21-damage hit consumes 5.25 durability. Recover stamina through F2 to continue; reselecting restarts at 75, and full reset creates a new trial inventory at maximum 100. An open menu pauses combat/wear; exit restores original expedition, item instances and condition. The linked test-room guide records exact labels and instructions.

## 검증 상태 / Validation status

`shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session`, `test_room`의 **서로 다른 자동 검사 6종이 통과**했다. 집중 검사는 임계값 경계·저스트 가드 포함 실제 마모·비방어 피해 예외·0 하한·단계 메시 교체·개체 보존·F2 정지/반복/복원과 1인칭 손잡이 연결을 확인한다. 1차 실제 이미지에서 발견한 중 단계 철테의 회색 절삭 형상 잔류는 제거했고, 마지막 모델 수정 후 정점 반경 회귀 검사를 포함한 `shield_damage`를 다시 통과했다.

최종 Mac 숨김 GPU `artifacts/visual_qa/shield_damage/shield_damage_20260919_02`의 manifest 실패는 없다. **비교 PNG 12장·마모 전환 PNG 4장과 1280×720·30fps·8초·240프레임**을 기록했다. 촬영에서는 실제 피해 40을 다섯 번 막아 **75→65(중)→55→45→35→25(하)**로 변했으며 건강·가드·손잡이 접촉을 유지했다. 이는 F2의 피해 21 대련과 구분되는 촬영용 실제 타격 값이다. 기본 위치·가드에서 파손이 보이며 밝힌 앞·뒤 검수에서도 파단과 손잡이를 직접 확인했다. 촬영 전후 소스 파일 88개의 해시가 같고 원정·커서가 보존됐다. 무음 검수 영상은 [shield_damage.mp4](../artifacts/validation/shield_damage_20260919/shield_damage.mp4)에 저장했고 MP4 인코딩과 240프레임 전체 디코딩이 모두 종료 코드 0으로 통과했다. 같은 검증 폴더에 안내·요약·검사 로그를 보존했다. GitHub 반영은 최종 게시 기록을 따른다.

기존 검사 `sword_clash`와 `first_person_motion_test_room`은 실패했으나 수정 전 기준본과 오류 목록·순서가 완전히 같았다(로그 ERROR 줄 각각 4개·64개). 기존 검격·이전 손 모델의 실패는 이번 6종 통과와 구분하며 해결했다고 주장하지 않는다. OS 하드웨어 입력 검수는 하지 않았고, 실제 플레이 코드에 연결된 숨김 실행으로 검증했다.

**Six distinct automated suites passed:** `shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room_session` and `test_room`. Focused coverage includes threshold boundaries, actual wear including just guard, non-blocked-hit exceptions, the zero floor, model switching, instance preservation, F2 pause/replay/restore and first-person grip attachment. Gray cutting geometry found on the medium rim in the first actual images was removed. After the final model correction, `shield_damage` passed again with a vertex-radius regression check.

Final hidden Mac GPU output at `artifacts/visual_qa/shield_damage/shield_damage_20260919_02` has no manifest failures. It records **12 comparison PNGs, 4 wear-transition PNGs and 1280×720, 30fps, 8 seconds, 240 frames**. Five actual blocked 40-damage hits produce **75→65 (medium)→55→45→35→25 (low)** while preserving health, guard and grip contact. The capture's 40-damage hits are separate from the 21-damage live F2 duel. Direct inspection confirms visible damage in idle/guard and fracture/grip geometry in brighter front/rear views. Eighty-eight source-file hashes match before/after capture, and expedition/cursor state is preserved. The silent review video is saved at [shield_damage.mp4](../artifacts/validation/shield_damage_20260919/shield_damage.mp4). MP4 encoding and full decoding of all 240 frames passed with exit code 0; the same validation folder retains the guide, summary and test logs. GitHub status follows the final publication record.

Existing `sword_clash` and `first_person_motion_test_room` checks still fail, with error lists and ordering identical to the unchanged baseline (4 and 64 ERROR log lines respectively). Those blade-clash/old-hand-model failures are separate from the six passing suites and are not claimed fixed. Validation uses hidden execution of production game code, not OS hardware input testing.
