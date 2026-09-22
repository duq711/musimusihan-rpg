# 겨드랑이 연결부 수정 / Axilla refinement

## 결과 / Result

사용자가 승인한 전신 비율을 기준으로 가슴·등에서 위팔로 이어지는 깊은 수직 홈을 완화했습니다. 어깨 폭, 팔 길이, 겨드랑이 아래의 빈 공간은 유지했습니다. 목·얼굴·손·하체를 포함한 나머지 17개 메시는 원본과 같습니다. 짧은 옷 이음선과 기존 천 무늬 방향 차이는 남습니다.

The deep vertical chest/back-to-arm groove is softened without changing the approved body width, limb lengths, or open underarm silhouette. The other 17 meshes, including head, hands and lower body, are unchanged. Short garment seams and existing differences in textile direction remain.

## 산출물 / Artifacts

- Source: `../player_multiview_proportions_20260922/Gravebound_Multiview_Proportions.blend` (preserved).
- Result: `Gravebound_Axilla_Refinement.blend`, `gravebound_player_axilla_refinement.glb`.
- Game: `../../godot-game/assets/3d/player/gravebound_player.glb`.
- SHA-256: `e54f38efcba95a849eccbe958a6ab059a647de171101ab15cf851ee2ae61532c`.
- Viewer: <http://127.0.0.1:8768/?view=axilla>.
- Before/after: <http://127.0.0.1:8768/axilla/compare.html>.

## 제작·검증 / Construction and validation

Mac Blender CLI로 기존 표면의 국소 곡면을 보간했습니다. 원본의 깊이 20%를 남겨 변형이 접히지 않도록 하고, 같은 변형으로 표면 노멀을 옮겼습니다. 연결부의 앞뒤 깊이만 최대 9.21mm 달라졌으며, 정면 실루엣을 결정하는 X/Z 좌표는 보존했습니다.

Built with background Blender on this Mac. A compact quadratic surface fit retains 20% of the source depth; normals follow the inverse-transpose deformation Jacobian. Maximum depth displacement is 9.21mm. World X/Z coordinates are preserved.

- `audit_local.py`: PASS. Topology, UVs, material graphs and all 12 packed images unchanged; no new significant degenerate triangles, opposed normals or projected winding reversals. Shoulder boundaries coincide within 0.000251mm. This bounded audit does not certify global self-intersection absence.
- `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset`: 3 PASS in the isolated asset runtime.
- `player_appearance`: PASS in the isolated full-game runtime, covering the actual imported body, inventory portrait, paused rotation, repeated F2/dungeon roundtrips, reset/cleanup and expedition restoration. Existing isolated-cache texture UID path fallbacks and one ObjectDB exit warning remain; no test assertion failed.
- Actual Godot embedded renderer: 19 final images and 19 baseline images with matched cameras. Reviewed front/oblique/rear textured and clay closeups, shoulder views and full-body views. Source manifests record actual renderer and GLB hash.
- Local viewer: current game GLB hash and all 12 before/after image routes verified; zoom and comparison UI checked in browser.

최종 렌더는 `../../godot-game/artifacts/visual_qa/player_appearance/axilla_refinement_final_20260922/`, 원본 비교는 `axilla_baseline_20260922/`에 있습니다. 중간 후보는 배포하지 않았습니다.

Final renders are stored in the folders above. Intermediate candidates are excluded from publication.
