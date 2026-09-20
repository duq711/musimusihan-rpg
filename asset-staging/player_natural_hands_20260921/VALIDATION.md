# 손 피부·손바닥 수정 / Natural skin and hand pose

전신 플레이어의 손 피부 밝기·주황빛을 낮추고, 원본 리그의 관절 가중치로 편안하게 굽힌 손가락과 완만한 손바닥 곡면을 만들었다. 별도 알베도 복사본을 양쪽 손과 노출 손목에 적용했다. 가죽과 천 픽셀은 피부 마스크 밖에서 그대로 유지한다. 이 변경은 전신 모델에 적용되며 일인칭 원본과 장비 동작은 보존한다.

English: Reduce full-body hand skin brightness and orange saturation. Use original rig weights for relaxed fingers and a gentle palm cup. Apply a copied graded albedo to both hands and exposed wrists, retaining pixels outside the skin mask. This updates the full-body model while preserving first-person assets and equipment behavior.

## 제작 / Production

- 입력 / Input: ../player_matching_sleeves_20260921/Gravebound_Matching_Sleeves.blend and original fp_arms rig/pose.json.
- 실행 / Run: Mac Blender background with build.py; hand_pose.py uses the original skin weights and joint axes.
- 피부 / Skin: saturation 0.78, RGB brightness factors 0.78/0.79/0.80; soft mask preserves texture details.
- 손바닥 / Palm: mirrored 5° palm cup; individual finger grip values 0.20–0.31.
- 산출물 / Outputs: Gravebound_Natural_Hands.blend, gravebound_player_natural_hands.glb, build_report.json.

## 검증 / Validation

- 원본 손 정점 대응 오차 2.24e-8m 이하. 양쪽 손목 경계 106개 정점씩 정확히 고정. 소매와 몸통의 형상·UV 보존 / Source mapping error <=2.24e-8m; 106 wrist seam vertices per side fixed exactly; sleeve/body geometry and UVs unchanged.
- player_fullbody_fp_arms PASS: 좌우 손·손목 피부 재질, 소매·손목 치수와 기존 구조 검사 / both graded hand/wrist materials, sleeve/wrist dimensions and structure.
- player_appearance PASS: 초상화·인벤토리·F2·원정 복원. 기존 ObjectDB 2개 종료 경고 기록 / portrait, inventory, F2 and expedition restoration; two existing ObjectDB exit warnings remain.
- Godot 실제 GPU: natural_hands_20260921_verified의 전신 및 손등·손바닥·측면·무채색 손바닥. 렌더 표면 검토에서 새 관통·관절 붕괴·봉제선 파손 없음 / actual GPU full-body and dorsal/palm/side/clay-palm captures; no new intersection, joint collapse or torn seam observed.

이 모델은 정지 전신 표시용이며 새 손 애니메이션을 추가하지 않는다. 손바닥 촬영은 실제 메시를 따로 복제해 몸통 가림을 없앤 검수 화면이다.

English: This is the static full-body display model, without new hand animations. Close-ups isolate a duplicate of the actual hand mesh to remove torso occlusion.
