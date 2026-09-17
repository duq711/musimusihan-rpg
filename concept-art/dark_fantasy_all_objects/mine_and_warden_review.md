폐광 및 성소 감시자 시각 검토 — 2026-09-06

활성 오브젝트는 126종이며 사용자가 완료했다고 지정한 플레이어 몸체와 손/팔 2종은 제외했다. 폐광 소품 36종의 이미지 생성 컨셉은 실제 원본 여섯 방향 촬영을 먼저 확인하고 각각 생성했다. 입력 이미지, 프롬프트, 생성 원본 경로는 mine_generation_audit.json 및 prompts/*.provenance.json에 보존했다.

성소 감시자는 원래 전투 피벗, 무기 칼날과 타격용 형상, 충돌체, 공격 수치 및 애니메이션을 유지하면서 실제 두개골, 안쪽으로 들어간 후드, 여러 겹의 갑옷, 접히고 찢어진 망토, 발등 갑옷과 닫힌 신발 밑창을 만들었다. 실제 촬영 props_iteration_02 → props_iteration_03 → effects_iteration_01을 비교하여 어깨를 줄이고 빈 윗면을 닫고, 갈색 천을 먹색으로 바꾸고, 얼굴과 눈의 밝기를 낮췄다. 마지막 촬영은 실제 생성 직후 정착하는 idle 손목 자세를 사용하며, 원본 비교에도 같은 자세를 적용했다. 원본과 같은 무기와 모든 전투 수치를 검증했다. 그림의 미세한 자수와 장식 수준까지 동일하다고 평가하지 않는다.

폐광 소품은 원본 모델의 형태, 배치, UV, 기존 알베도·노멀·거칠기 지도를 보존하고 재질만 수정했다. 36종의 목재, 쇠, 뼈, 밧줄, 천, 석재, 그을린 유리를 분류하여 실제 게임과 검사실이 같은 재질을 사용한다. mine_iteration_01에서는 모든 58종(소품 36, 파쇄 암석 12, 널빤지 3, 기타 폐광 7)을 여섯 방향으로 촬영하고 전부 육안 검토했다. 첫 결과에서 목재가 너무 밝고 유리가 황금색으로 반짝여 mine_iteration_02에서 목재 명도와 채도, 뼈의 황색, 유리 반사를 낮췄다. 두 번째 실제 촬영에서는 목재가 어두운 회갈색으로 정착하고 쇠와 유리가 소품의 분위기에 맞게 보인다. 형태와 모든 여섯 카메라 방향을 보존했다. 높은 해상도의 컨셉 그림보다 미세한 홈과 표면 대비는 덜 세밀하다.

촬영 연결 오류 두 가지를 수정했다. mine_ore_cart는 전복된 광차를 중복 선택하고 있었으므로 실제 직립형 Mine_north_workings_ore_cart_01로 바꿨다. aged_board_00..02는 배치 전 단위 메시를 촬영하고 있었으므로 실제 폐광의 첫 MultiMesh 배치에서 추출한 변환과 색을 사용하도록 했다. 현재와 원본 검사실에 같은 수정을 적용했다. baseline_catalog_corrected_01에서 네 오브젝트를 다시 촬영하고 이미지 생성 컨셉 네 장을 교체했다. 이전 이미지와 프롬프트는 superseded_catalog_reference_01에 보존했다. 실제 널빤지 배치와 보존 자료의 값이 일치하는지 별도 자동 검증을 추가했다.

검증 통과: 전체 126종 원본 검사실, 폐광 58종 현재 검사실, 36종의 실제 원본 메시 및 표면 지도 보존, 성소 감시자 전투/충돌/형상 보존, 실제 세 가지 널빤지 배치 값, 12종 재촬영 검사실. 모든 촬영은 Godot Vulkan 실제 렌더러의 숨김 방식으로 수행했고 원정 상태와 커서를 보존했다. 일부 기존 자원에 대해 종료 시 ObjectDB 경고 2개가 있으나 기능 오류 또는 촬영 실패는 발생하지 않았다.

최종 판자 재질은 실제 인스턴스 색상에 중복 곱해진 어두운 색을 보정한 뒤 다시 명도를 낮추고 차가운 색 균형을 적용했다. mine_iteration_03에서 나뭇결이 다시 드러나는 것을 확인하고 최종 색 조정 후 판자 3종 자동 검사실 검증을 통과했다. 같은 촬영에서 수면의 위·아래가 모두 보이고 석순 바닥의 늘어진 무늬가 사라진 것을 확인했다. 판자 컨셉 두 장에 이미지 생성이 임의로 붙인 금속 마감과 못은 추가 편집으로 제거했다.

Final complete capture final_iteration_01: every mine archetype (36 mine props + 23 environment objects = 59) was visually reviewed in all six directions. The manifest confirms 126 complete objects, unchanged source hashes during capture, and preserved expedition/cursor state. Per-ID actual sheet/view paths, SHA256 and explicit findings are saved in mine_final_review.json. Water underside and calcite/formation cap projection are fixed; final board tint preserves exact production instance colors and wood grain. Remaining simpler board damage, rope fibers and large rock facets are documented.

One additional final review correction: keeper bone tint in enemy.gd now balances the already-warm authored texture with (0.66, 0.74, 0.90), roughness 0.93 and specular 0.25. The source texture, anatomy and animation pivots are unchanged. visual_asset and warden_concept tests passed. Shared skull neutralization also preserves exact geometry. A subsequent capture will verify the appearance.

The two enemy six-view sheets in final_corrections_01 were visually reviewed after neutral bone correction: the keeper is now worn grey-ivory instead of mustard yellow; the warden skull is neutral and recessed while hood/armor/boots/idle sword pose remain intact. The correction capture manifest confirms Vulkan, 8 captured archetypes, unchanged sources during capture, and preserved expedition/cursor. A fresh warden_concept test after shared skull tint also passed. Enemy sources are frozen.

Final complete capture final_iteration_02 is verified: 126 objects / 756 views, 84 unchanged source hashes during capture, preserved expedition/cursor. For all 59 mine objects the declared source hashes and bounds are unchanged from the fully visually reviewed final01. 58 complete sheets are byte-identical; canvas rack differs only at two pixels by one RGB quantization level and was visually rechecked with no perceptible change. mine_final_review.json now points to final02 with exact per-view hashes; the original final01 review is archived, and detailed comparison is in mine_final_pixel_comparison.json.


Final iteration 03 evidence update: the full actual Vulkan manifest passed 126 objects / 756 views, with all 85 source hashes unchanged during capture and expedition/cursor preserved. The 59 owned mine objects were compared against final02: all source-entry hashes and bounds match, 58 six-view sheets and 353 individual views are byte- and pixel-identical. mine_timber_support_02 differs at one pixel by one channel level; both six-view sheets were directly inspected and are visually equivalent. All 59 current review entries and 354 view paths/hashes now reference final_iteration_03. Final02 review and comparison files are retained separately. No production source was changed during this evidence update.
