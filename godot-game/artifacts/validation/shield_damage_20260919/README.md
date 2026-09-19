# 3단계 방패 파손 / Three-stage shield damage

개별 방패의 내구도에 따라 같은 실제 1인칭 방패의 메시를 바꿉니다. 상 단계는 원본, 중 단계는 갈라진 판재와 끊어진 철테, 하 단계는 더 넓게 뜯긴 상단과 옆면입니다. 기존 대기·가드 카메라를 유지하고, 손잡이 4개 마커와 팔·손·방패 노드는 그대로 사용합니다.

The same actual first-person shield selects a mesh from its item's durability. High uses the original; medium has split boards and torn rim sections; low expands the missing upper and side areas. Existing idle/guard cameras, four contact markers and arm/hand/shield nodes are retained.

[실제 피격 전환 영상 / Actual blocked-hit transition video](shield_damage.mp4)

이 영상은 실제 Godot GPU 렌더 240프레임(1280×720, 30fps, 8초, 무음)입니다. 시험 중 기력만 각 타격 직전에 회복시켰으며 실제 `receive_attack(40)`을 5회 호출합니다. 내구도는 75→65→55→45→35→25로 변하고 첫 타격에 중, 마지막 타격에 하 모델이 선택됩니다. 영상 인코딩 및 전체 디코딩을 통과했습니다.

This is an actual 240-frame Godot GPU capture (1280×720, 30fps, eight seconds, silent). Only fixture stamina is refilled before each hit. Five production `receive_attack(40)` calls reduce condition 75→65→55→45→35→25: medium on the first hit and low on the last. Encoding and full decoding passed.

## 비교 화면 / Comparison views

| 단계 / Stage | 실제 대기 / Actual idle | 실제 가드 / Actual guard | 앞면 / Front | 뒷면 / Rear |
|---|---|---|---|---|
| 상 / High | [대기](high_idle.png) | [가드](high_guard.png) | [앞면](high_inspector_front.png) | [뒷면](high_inspector_rear.png) |
| 중 / Medium | [대기](medium_idle.png) | [가드](medium_guard.png) | [앞면](medium_inspector_front.png) | [뒷면](medium_inspector_rear.png) |
| 하 / Low | [대기](low_idle.png) | [가드](low_guard.png) | [앞면](low_inspector_front.png) | [뒷면](low_inspector_rear.png) |

앞·뒤 검사 화면은 실제 플레이어가 선택한 메시와 재질을 공유하는 별도 검사 복제본이며, 중립 흰색 보조 조명을 동일하게 사용합니다. 1인칭 6장과 영상은 기존 플레이어 렌더러를 사용합니다. 단계별 비교에서 카메라·검·방패 변환이 같은지 검사했으며, 실제 이미지를 열어 상단의 단계 차이를 확인했습니다. 생성 이미지나 화면 합성으로 대체하지 않았습니다.

Front/rear views are inspector copies sharing the mesh and materials selected by the actual player, under identical neutral fill lights. The six first-person stills and video use the existing player renderer. Matching camera, sword and shield transforms were checked between stages; the actual images were opened to inspect silhouette differences. No generated imagery or compositing replaces the renders.

## 검증 / Validation

- PASS 6종 / Six passed suites: `shield_damage`, `shield_guard`, `primary_shield_stow`, `first_person_renderer`, `test_room`, `test_room_session`.
- 실제 타격·저스트 가드·비방어 피해 제외·0 하한·경계값·내구도 개체별 보존·동일 ID 장비 교환·F2 정지/초기화/원정 복원·손잡이 고정·정점 반경을 확인했습니다. / Covers actual hits, just guard, exclusions, zero floor, thresholds, per-item preservation, same-ID swaps, F2 pause/reset/expedition restore, grip markers and mesh vertex radius.
- 기존 실패 2종 / Two pre-existing failed suites: `sword_clash`의 4개 ERROR 로그 줄과 `first_person_motion_test_room`의 64개 ERROR 로그 줄은 수정 전 비교 프로젝트에서도 동일한 순서·내용입니다. 이전 검격과 교체 전 손 구조를 가정한 검사 문제이며 이번 변경으로 해결했다고 보고하지 않습니다. / Their four and 64 ERROR lines respectively match the pre-change comparison exactly; legacy clash and old-hand assumptions remain unresolved.
- 시험룸의 새 action 등록 목록 누락과 신규 저스트 가드 검사의 잘못된 플래그 가정은 수정 후 재검사를 통과했습니다. / The new trial action allowlist and incorrect just-guard test assumption were corrected and passed reruns.
- 첫 시각 검수에서 중간 모델에 남은 절단용 면을 발견·제거했습니다. 최종 모델은 원래 원형 범위 검사를 통과했고 직접 렌더에서도 그 보조 형상이 없습니다. / A cutter face found during initial visual review was removed; final vertex-bound checks and direct render inspection pass.
- 실제 GPU 검수 실패 0, 소스 88개 해시 유지, 원정·인벤토리·커서 보존 확인. / GPU checks have zero failures; 88 source hashes and original expedition/inventory/cursor state were preserved.

기존 종료 시 ObjectDB 2개 경고는 남아 있습니다. 전체 던전을 OS 입력으로 수동 플레이한 결과는 미확인입니다. 이번 범위는 세 단계 외형이며, 파편 물리·수리·방어성능 저하·0 내구도에서 장비 삭제는 추가하지 않았습니다. 구현 세부 사항은 [기능 안내](../../../docs/SHIELD_DAMAGE.md)를 참조하세요.

The existing two-ObjectDB shutdown warning remains. A full manual dungeon playthrough using OS input is unverified. Scope is three appearance stages; fragment physics, repairs, weaker guarding and automatic removal at zero are not added. See the linked feature guide for implementation details.
