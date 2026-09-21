# 제공한 머리·눈 모델로 교체 / Replace the head and eyes with the supplied model

사용자가 제공한 `Untitled.Obj`의 실제 머리와 눈 메시를 플레이어에 적용한다. 기존 머리·머리카락·눈은 제거하고 제공 모델의 형상과 원래 UV를 사용한다. 의상·망토·손·팔 등 다른 25개 메시는 보존하며, 전체는 머리와 눈을 포함한 27개 메시 구성이다.

English: Replace the old head, hair and eyes with the actual head and eye meshes from the supplied `Untitled.Obj`, using their original geometry and UVs. Preserve the other 25 outfit, mantle, hand and arm meshes, retaining 27 mesh nodes in total.

## 제작 범위 / Production scope

- 원본 / Originals: `Untitled.Obj`, `Untitled.mtl`, `Untitled_defaultMat_color.tga.zip` 세 파일을 그대로 보존한다. Keep all three supplied files unchanged.
- 메시 / Geometry: 제공 모델은 머리 `Group1`의 5,474개 정점·10,790개 삼각형과 `eye`의 762개 정점·1,444개 삼각형, 합계 **6,236개 정점·12,234개 삼각형**이다. The supplied head and eyes contain **6,236 vertices and 12,234 triangles** combined.
- 배치 / Placement: 원래 비율과 UV를 유지한 채 약 `0.00222755`의 균일 배율과 좌표축 변환·이동으로 기존 몸에 맞춘다. Fit the supplied model with a uniform scale of approximately `0.00222755`, axis conversion and translation, preserving proportions and UVs.
- 색상 / Color: 제공된 4096×4096 TGA의 원본 아틀라스를 사용하며, 게임에는 로딩 부담을 줄인 2048×2048 복사본을 패킹한다. Use the supplied 4K color atlas with its native UVs and pack a 2K runtime copy to reduce loading cost.
- 표면 / Surface: MTL이 참조하는 선택적 `Untitled_defaultMat_nmap.tga`는 제공되지 않았다. 해당 텍스처를 생략하고 메시의 올바른 표면 노멀로 렌더한다. The optional normal map referenced by the MTL was not supplied; omit it and render with the mesh's proper surface normals.

제작 스크립트 / Builder: `build.py`.

결과 / Outputs: `Gravebound_Supplied_Face.blend`, `gravebound_player_supplied_face.glb`.

게임 대상 / Runtime target: `../../godot-game/assets/3d/player/gravebound_player.glb`.

## 검증 상태 / Verification status

- 제작 / Production: **PASS**. 원본 UV와 다른 25개 메시의 정점·면·UV·변환·재질을 보존했다. Native UVs and the other 25 meshes' vertices, faces, UVs, transforms and materials are preserved.
- Godot 에셋 / Asset checks: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset` **3/3 PASS**.
- 통합 / Integration: `player_appearance` **PASS**. 실제 모델·인벤토리 초상화·F2 왕복·초기화·원정 상태 복원을 확인했다. Actual model, inventory portrait, F2 roundtrips, reset and expedition restoration passed. 기존 ObjectDB 2개 종료 경고는 남는다. The existing two-ObjectDB exit warning remains.
- 실제 화면 / Visual: embedded/Vulkan **10개 시점**과 360° 뷰어에서 원본 얼굴·눈·입·귀 정렬과 목 연결을 확인했다. Reviewed ten embedded/Vulkan views and the 360° viewer for facial/eye/lip/ear alignment and the neck join.
- 최종 모델 / Final model SHA256: `4afb8b3812f4ff7c70cbfd6da948dd8bee3394b0a475dc59cb51088b9c74fbe1`.
- 근거 / Evidence: `build_report.json`, `asset_test.log`, `integration_test.log`, `render.log`, `../../godot-game/artifacts/visual_qa/player_appearance/supplied_face_20260921/`.
- 게시 대상 / Publication target: `duq711/musimusihan-rpg`, `codex/player-fullbody-fp-arms`.
