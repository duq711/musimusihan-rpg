# 방패 나무 단면 보강 / Shield fracture wood detail

사용자 지적: 깨진 단면이 단색이라 나무처럼 읽히지 않음. `FP_ShieldFractureOak`에만 나이테·목섬유·기공·미세 요철을 추가했다. 판재의 세로축에 맞춘 3차원 결이 방패와 함께 움직인다. 형상·정상 겉면·철테·손잡이·팔·내구도 규칙은 바꾸지 않았다.

The previously flat fracture faces now use growth rings, fibres, pores and fine surface relief. The wood pattern is anchored to the shield's local volume and its vertical plank direction. Geometry, normal outer materials, iron rim, grips, arms and wear rules are unchanged. Fine relief is shading, not extra loose-fragment geometry.

실제 Godot GPU 화면 / Actual Godot GPU captures:

- [1인칭 가드 수정 전 / Guard before](before_low_guard.png) → [수정 후 / After](low_guard.png)
- [1인칭 대기 수정 전 / Idle before](before_medium_idle.png) → [수정 후 / After](medium_idle.png)
- [중 단계 단면 근접 / Medium fracture close-up](medium_inspector_fracture_top_closeup.png)
- [하 단계 단면 근접 / Low fracture close-up](low_inspector_fracture_top_closeup.png)
- [실제 피격 마모 영상 / Actual blocked-hit wear video](shield_grain.mp4)

근접 이미지는 본편에서 선택된 동일 메시·동일 재질의 별도 검사 카메라다. 1인칭 화면은 본편 카메라·배치·조명으로 촬영했다. 수정 전 사진은 직전 방패 파손 검증의 같은 구도 자료다. 생성 이미지나 합성 결과가 아니다.

Close-ups use an inspection camera around the exact runtime-selected mesh and materials. First-person images use production camera, placement and lighting. Before images come from the preceding shield-damage validation with matching framing. These are actual renders, not generated or composited illustrations.

검증 / Validation:

- `shield_damage`, `first_person_renderer`: **2 PASS**. 기존 종료 ObjectDB 경고는 남아 있다. / Two relevant suites passed; existing shutdown ObjectDB warning remains.
- Mac 숨김 Vulkan/embedded: **18 PNG**, 1280×720, 30fps, 240프레임/8초. 실제 가드 타격 5회와 상태·손 접촉 보존. / Eighteen PNGs and an eight-second sequence of five production guard hits with state and grip checks.
- 소스 해시·원정·커서 보존, manifest 실패 없음. / Source hashes, expedition and cursor preserved; no manifest failures.
- 첫 렌더의 너무 규칙적인 줄무늬를 다듬은 뒤 최종 중·하 단면 근접 및 실제 1인칭 가드·대기 이미지를 직접 열어 확인. / Uniform initial bands were refined and final close-ups and first-person images were directly inspected.
- 영상 인코딩과 전체 디코딩 결과·파일 해시는 `validation_summary.json`과 로그를 따른다. / Video encoding, full decoding and hashes are recorded in the summary and logs.

기존 각진 파손 윤곽은 유지한다. 이번 검증에 전체 던전 수동 플레이·OS 입력은 포함하지 않았다. 원격 반영은 로컬 `asset-staging/shield_grain_20260919/publication.json` 기록을 따른다.

The existing angular fracture silhouette remains. This pass does not claim a full manual dungeon playthrough or OS-input verification. Publication is recorded separately in the local publication JSON.
