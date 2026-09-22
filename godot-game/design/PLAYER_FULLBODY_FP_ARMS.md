# 전신에 현재 1인칭 양팔 적용 / Current FP arms on the full body

2026-09-20 사용자 요청: 현재 1인칭 손·팔을 전신 캐릭터에 적용하고 기존 전신 손을 제거한다.

- 본편 플레이어와 인벤토리가 공유하는 `assets/3d/player/gravebound_player.glb`를 교체한다.
- 현재 `fp_arms/left.glb`, `right.glb`의 실제 양팔·장갑과 재질을 사용한다. `supplied_fp_arm.gd`의 손 크기·편한 손가락 자세·팔 맞춤을 실행해 얻은 포즈를 전신의 서 있는 자세로 굽는다. Blender 본 축 재정렬을 보정하고 굽기 직후 정점을 실제 Godot 변형과 대조한다. 짧게 잘린 소매 상단은 망토 안으로 12.5cm 이어주고 폭을 줄이며 손·손목 연결부는 보존한다.
- 예전 손 2개·손톱 10개와 겹치는 소매 2개·토시 2개를 제거한다. 얼굴·후드·망토·몸통·허리 장비·하체 등 나머지 24개 메시의 형상·UV·변환은 보존한다.
- 1인칭 에셋과 전투 동작 코드는 변경하지 않는다. 전신은 기존처럼 인벤토리 회전용 정적 모델이며 이번 작업이 전신 걷기·전투 애니메이션을 추가하지는 않는다.
- F2의 `플레이어 외형 · 3D 캐릭터`는 실제 인벤토리의 3D 외형 화면을 명시적으로 연다. 평소 I는 현재 통합 건강·장비 화면을 유지하며 전신 초상은 기본적으로 숨겨진다. F2 복귀·반복 시험·초기화·원정 복원을 검사한다.

English: Replace the shared player/inventory full-body GLB with the current FP gloves and sleeves. Bake the real production relaxed finger pose, hand scale and arm fitting onto the standing body. Remove two old hands, ten nails and four overlapping sleeve/bracer meshes; preserve geometry, UVs and transforms of the other 24 parts. First-person assets and combat behavior remain intact. This remains a static full-body portrait, without new third-person locomotion or combat animation. The existing F2 appearance entry explicitly opens the real inventory portrait; normal I retains the current unified health/loadout page with the portrait hidden. Preserve reset/return/session restoration.

## 제작 자료 / Production files

`../../asset-staging/player_fullbody_fp_arms_20260920/`:

- `export_pose.gd`, `pose.json`: 본편 팔 코드에서 추출한 실제 뼈 변환 / actual bone transforms from production arm code.
- `build.py`, `Gravebound_FP_Arms.blend`: Mac Blender 제작 절차와 편집 가능한 결과 / Mac Blender procedure and editable result.
- `build_report.json`: 원본·소스·결과 해시, 제거 목록, 보존 부위의 서명 / input/output hashes, removed parts and retained geometry signatures.
- `original_gravebound_player.glb`: 로컬 원본 백업 / local original backup. 이전 Git LFS 버전과 기존 9월 11일 제작 원본도 보존한다 / previous Git LFS revision and September 11 production sources remain available.

FP arms: DJMaesen, CC BY 4.0. 원본 출처·가공 내역은 [에셋 표기](../assets/3d/player/fp_arms/ATTRIBUTION.md)를 따른다 / source and modification attribution follows the asset record.

The sleeve tops are extended 12.5cm beneath the original mantle and tapered to fit the body, preserving the hands and wrist seam. Blender bone reorientation is compensated; baked vertices are checked against actual Godot skinning before the sleeve fit.

`player_fullbody_fp_arms`는 소매 상단·손목·장갑 크기·재질·구형 손 제거를, `player_appearance`는 실제 F2·본편 연결·회전·초기화·원정 보존을 검사한다. 최종 상태는 제작 폴더의 `VALIDATION.md`를 따른다. / Asset and integration tests cover sleeve attachment, glove proportions, material maps, old-hand removal, F2, rotation and session restoration. Final validation status is recorded in the production folder's `VALIDATION.md`.

## 2026-09-21 전신 손 비율 / Full-body hand proportions

사용자 피드백에 따라 전신의 양손을 기존 크기의 82%로 조정했다. 손목 중심을 고정하고 소매 하단도 같은 비율로 줄인 뒤 높이 0.975–1.115m 구간에서 기존 소매 폭으로 부드럽게 연결한다. 장갑과 손가락의 세로 범위는 약 21cm다. 나머지 24개 몸 메시와 1인칭 원본은 보존한다. 기존 F2 외형 시험에서 수정된 공용 모델을 확인할 수 있다.

English: Reduce both full-body hands to 82% around their wrist anchors. Match the lower sleeve and blend back into its existing shape over heights 0.975–1.115m. The relaxed glove/finger vertical extent is about 21cm. Preserve the other 24 body meshes and first-person source assets. The existing F2 appearance entry displays the updated shared model.

제작·검증 자료 / Production and validation: `../../asset-staging/player_fullbody_proportions_20260921/`. 이전 제작 모델도 보존한다 / Previous production models are retained.

### 같은 날 재수정: 팔 전체 / Follow-up: the entire arm

사용자가 손 축소 후에도 팔 비율이 맞지 않는다고 지적했다. 앞선 82% 손 축소만으로 완료되었다는 판단을 정정한다. 전신용 소매의 전완 부풀림을 줄이고, 손목 높이를 0.94m에서 0.87m로 낮추며 팔꿈치 기준 높이를 1.135m로 맞춘다. 어깨 아래 연결을 유지하며 손목은 몸 쪽으로 2cm 옮긴다. 손 크기는 앞선 82%를 유지한다. 변경은 전신 전용이며 1인칭 전투 모델에는 적용하지 않는다.

English: The user identified that shrinking the hands alone had not corrected the arm proportions. Refit the entire sleeve: reduce forearm inflation, lower the wrist from 0.94m to 0.87m, place the elbow reference at 1.135m, and move the wrist 2cm inward while retaining the shoulder connection. Keep the previous 82% hand scale. These changes affect only the full-body model, preserving first-person combat assets.

최신 제작·검증 / Latest production and validation: `../../asset-staging/player_fullbody_anatomy_20260921/`.

### 손목 접합부 재조정 / Wrist-junction refit

장갑의 손목 구간을 길이 62%, 중심 단면 폭과 깊이 73%로 조정하고 같은 변형을 소매 끝에도 적용한다. 손바닥 아래쪽과 손가락(높이 0.795m 이하)은 보존한다. 손목 폭은 약 6.9cm, 장갑 손목 구간은 약 3cm 짧아졌다. PLAYER_QA_WRIST_DETAIL=1로 손목 확대 렌더를 추가한다.

English: Shorten the glove wrist section to 62% and narrow its central width/depth to 73%, applying the same deformation to the sleeve junction. Preserve the lower palm and fingers at heights up to 0.795m. The glove wrist is about 6.9cm wide and the cuff about 3cm shorter. PLAYER_QA_WRIST_DETAIL=1 adds an actual-model wrist close-up.

Production and validation: ../../asset-staging/player_fullbody_wrist_20260921/

### 사용자 정정: 손목 복원, 팔꿈치 수정 / Restore wrists, refit elbows

사용자가 지적 부위를 팔꿈치로 정정하고 손목 복원을 요청했다. 앞선 손목 축소는 취소하고 player_fullbody_anatomy_20260921의 양손 전체와 높이 0.98m 이하 소매를 복원한다. 팔꿈치 부근 소매 꺾임을 6cm 아래로 이동시키고 관절부 폭을 줄이며 위팔로 이어지는 윤곽을 조정했다. 손목 복원은 정점 비교로 검사하며 팔꿈치는 확대 렌더로 확인한다.

English: The user clarified that the issue was the elbows and requested wrist restoration. Revert the wrist reduction: restore both complete hands and sleeves below 0.98m from player_fullbody_anatomy_20260921. Move the sleeve elbow crease down 6cm, narrow the joint region and reshape its transition into the upper arm. Audit restored vertices and inspect an elbow close-up.

최신 제작 및 검증 / Latest production and validation: ../../asset-staging/player_fullbody_elbow_20260921/

### 팔 해부 구조 참고에 따른 전체 재형성 / Full sleeve reconstruction from the arm reference

사용자가 제공한 사람 팔 참고 그림에 따라, 앞선 팔꿈치 국소 이동을 최종 형상으로 사용하지 않는다. 손목 복원본에서 시작해 소매 표면을 121개 높이에서 절단 측정하고, 어깨·위팔·팔꿈치·전완 상부·전완 하부의 중심선과 단면을 새 연속 프로필로 재형성한다. 어깨와 위팔 볼륨, 팔꿈치의 좁은 단면, 팔꿈치 아래 전완 볼륨과 손목으로 좁아지는 흐름을 구분한다. 손 전체·소매 하단은 보존하고 소매 상부는 연속 표면으로 교체한다. 기존 천 재질을 사용하며 새 표면의 UV는 원본 표면에서 보간한다. 이는 전신 정적 모델의 형상 수정이며 새로운 관절 리깅이나 전투 애니메이션이 아니다.

English: Following the supplied human-arm reference, replace the previous local elbow displacement with a full sleeve reconstruction. Starting from the restored-wrist model, sample 121 horizontal surface sections and remap them to continuous shoulder, upper-arm, elbow and forearm profiles. Replace the disconnected upper sleeve with a continuous loft, transferring UVs from the source surface and retaining fabric materials, complete hands and the lower cuff. This changes the static full-body shape; it does not add articulation or combat animation. Inspect both clothed and neutral-material views.

최신 제작·검증 / Latest production and validation: ../../asset-staging/player_arm_structure_20260921/

### 사용자 최종 방향: 곧게 뻗은 팔 / User direction: straight arms

사용자가 굴곡 없이 일직선으로 뻗은 팔을 요청했다. 앞선 근육형 단면 강조를 제거하고, 보이는 소매 구간의 중심선과 폭 변화를 선형으로 만든다. 형상에 더하던 잔물결도 제거한다. 손·손목과 망토 안쪽 어깨 연결은 유지한다.

English: At the user's request, replace the emphasized anatomical bulges with straight arm axes and a linear taper across the visible sleeve. Remove procedural surface ripples. Preserve hands, wrists and the tucked shoulder connection.

최신 제작·검증 / Latest production and validation: ../../asset-staging/player_straight_arms_20260921/

### 위팔·아래팔 축 분리 / Separate upper-arm and forearm axes

사용자 후속 지시에 따라 팔 전체를 하나의 직선으로 만든 이전 해석을 수정한다. 위팔과 아래팔은 각각 곧게 유지하되 팔꿈치에서 서로 다른 방향을 갖도록 하고, 관절 주변 6cm 구간에서만 부드럽게 연결한다. 부풀림이나 물결형 윤곽을 다시 넣지 않으며 손과 손목은 보존한다. 편안하게 내려놓은 정지 자세로 제작한다.

English: Revise the previous single-axis interpretation following the user's clarification. Keep each limb segment straight while joining distinct upper-arm and forearm axes through a local 6cm elbow transition. Retain the restrained sleeve taper, without repeated bulges or waves, and preserve hands/wrists. Use an authored relaxed static pose.

최신 제작·검증 / Latest production and validation: ../../asset-staging/player_relaxed_elbows_20260921/

### 소매 의상 색조 통일 / Match sleeve outfit colors

소매 천의 기존 UV와 직조 무늬를 보존하고, 별도 천 재질의 알베도 채도를 80% 줄이고 밝기를 72%로 조정해 몸통의 어두운 회갈색에 맞췄다. 거칠기는 0.9로 맞춘다. 피부와 장갑의 원본 재질 및 전체 형상은 유지한다.

English: Preserve the sleeve UVs and weave, grading a separate cloth albedo with 80% desaturation and 72% brightness to match the dark gray-brown outfit. Set roughness to 0.9. Preserve original skin/glove materials and all geometry.

제작·검증 / Production and validation: ../../asset-staging/player_matching_sleeves_20260921/

### 자연스러운 손 피부와 손바닥 / Natural hand skin and palm

손 피부의 밝기와 주황색 기운을 낮춘 별도 알베도를 적용하고 기존 가죽 장갑과 소매 색은 보존한다. 원본 손 리그의 관절·스키닝을 이용해 손가락을 편안하게 굽히고 손바닥의 완만한 오목한 형태를 만든다. 손목 연결과 소매 형상은 유지한다. 변경 범위는 현재 전신 모델이며 일인칭 장비 동작과 원본 에셋은 보존한다.

English: Use a separately graded skin albedo with lower brightness and orange saturation, preserving the leather gloves and matched sleeves. Use the original hand joints and skin weights for relaxed finger flexion and gentle palm cupping. Preserve the wrist seam and sleeve geometry. This updates the current full-body model while preserving first-person equipment behavior and source assets.

제작·검증 / Production and validation: ../../asset-staging/player_natural_hands_20260921/

### 손바닥을 몸 안쪽으로 / Palms facing the body

사용자 요청에 따라 양손을 전완 축 기준으로 서로 반대 방향 90° 돌려 손바닥이 허벅지를 향하게 했다. 옷자락 관통을 피하도록 양손을 1.5cm 바깥으로 옮기고, 손목·소매 하단은 같은 변환으로 연결했다. 소매의 회전은 높이 0.95–1.135m 구간에서 팔꿈치 쪽으로 점차 사라진다. 피부색, 손가락 굽힘, UV와 재질은 보존한다.

English: Turn each hand 90° in opposite directions around the forearm axis so palms face the thighs. Move both hands outward by 1.5cm to clear the coat, applying the same transform to the wrist and lower cuff. Sleeve twist blends out toward the elbow between heights 0.95–1.135m. Preserve skin tone, finger curl, UVs and materials.

제작·검증 / Production and validation: ../../asset-staging/player_inward_palms_20260921/

### 후드 정수리 재설계 / Rebuilt hood crown

360° 검수에서 드러난 정수리의 구멍과 방사형 갈라짐을 수정했다. 너무 작은 끝단 링에 큰 주름이 적용되어 뒤집히던 표면을, 정수리부터 뒤통수까지 이어지는 닫힌 둥근 곡면으로 교체했다. 얼굴 개구부를 유지하고 4mm 천 두께와 어두운 안감을 적용했다. 이마 위 천에는 두피와 안감이 겹치지 않도록 완만한 여유를 추가했다. 기존 의상 컨셉의 깨끗한 천 영역으로 새 UV 알베도를 베이크하여 정수리에서 무늬가 길게 늘어나는 현상을 없앴다.

변경 대상은 `Gravebound_PointHood`이며 다른 27개 메시의 정점·면·UV·변환을 보존했다. 원본 제작 파일도 보존한다. 로컬 360° 뷰어에는 **후드 확대**와 **정수리** 버튼을 추가해 같은 게임 모델을 쉽게 검사할 수 있다.

English: Replace the inverted, wrinkled tip ring with a closed rounded crown that continues into the back of the hood. Preserve the face opening, add a 4mm cloth shell and dark lining, and provide smooth brow clearance around the scalp. Bake a fresh UV albedo from a clean fabric area of the existing outfit concept to avoid stretched crown patterns. Only `Gravebound_PointHood` changes; preserve the other 27 meshes and source files. The local 360° viewer adds hood and crown focus buttons for inspecting the actual game model.

제작·검증 / Production and validation: ../../asset-staging/player_hood_redesign_20260921/VALIDATION.md

### 후드 아래 어깨 연결 보완 / Close the shoulder gaps below the hood

사용자가 추가로 보여준 후측상방 시점에서는 앞·뒤 망토 사이의 연결 천이 빠져 몸 안쪽이 드러났다. 양쪽 망토의 실제 상단 경계를 측정해 목 옆부터 어깨 바깥쪽까지 이어지는 천을 추가했다. 기존 패널 아래로 8mm 겹치고 중앙은 완만한 곡면으로 연결하며, 4mm 두께와 별도 천 알베도를 적용했다. 새 천은 기존 MantleBack에 통합하여 28개 메시 구성을 유지한다. 앞·뒤 기존 패널과 수정된 후드·손·팔은 보존한다.

English: The user's elevated rear/side view exposed missing cloth between the front and rear mantle. Add continuous shoulder fabric along the measured panel edges, extending beneath the neck cowl and overlapping the existing panels by 8mm. Use gentle curvature, 4mm cloth thickness and a separate fabric albedo. Join the additions into MantleBack, retaining 28 mesh nodes and preserving the existing panels, hood, arms and hands.

이전 모델에서 실패하고 수정 모델에서 통과하는 Godot 어깨 광선 검사와 양쪽 고각·무채색 렌더를 추가했다. 360° 뷰어의 **어깨 연결** 버튼으로 해당 부위를 바로 확인한다.

English: Add an imported-mesh regression that fails on the former gaps and passes on the corrected model, plus elevated shoulder and clay renders. The viewer's **어깨 연결** button opens this inspection angle.

제작·검증 / Production and validation: ../../asset-staging/player_hood_shoulder_closure_20260921/VALIDATION.md

### 사용자 최종 방향: 후드 제거 / Final user direction: remove the hood

사용자의 후속 요청은 후드 디자인을 더 수정하는 대신 후드를 없애는 것이다. `Gravebound_PointHood`를 제거하고, 어깨 연결 천·목 카울·망토·손과 팔은 유지한다. 이에 따라 전신 모델은 27개 메시 구성이 된다. 머리 외 다른 26개 메시를 보존하며 기존 머리의 형상도 변경하지 않는다.

English: The user's subsequent request is to remove the hood instead of continuing its redesign. Remove `Gravebound_PointHood`, retaining the shoulder closure, neck cowl, mantle, arms and hands. The full-body model therefore contains 27 meshes. Preserve the other 26 meshes and the existing head geometry.

후드 아래에 가려졌던 머리 표면에도 후드 그림이 투영되어 있어, 원본 `Mercenary_Male_HeadNeck_LOD0`의 얼굴·귀·목·두피 UV와 사용 재질을 좌표가 일치하는 35,366개 면에 복원한다. 두피만 바꾸는 중간 방식은 사용하지 않는다. 원본 에셋은 보존하고 패킹용 텍스처 복사본만 최대 2048 해상도로 준비한다. 앞·뒤 얼굴 투영 재질은 같은 알베도와 UV를 사용하면서 조명에 반응하는 PBR(거칠기 0.88)로 전환했다. 최종 내보내기, Godot 자동 검사 및 360° 정면·후면·전신 검증을 완료했다. Godot embedded/Vulkan 12개 시점 검증도 완료했다. 기존 머리 UV 경계는 남아 있으며 후드 제거·의상 보존 범위로 검수했다. 제작·검증 근거는 아래 문서에 기록한다.

English: Clothing artwork was also projected onto the formerly hidden head. Restore the original `Mercenary_Male_HeadNeck_LOD0` facial, ear, neck and scalp UVs/materials on the 35,366 position-matched triangles. Do not use the scalp-only intermediate approach. Preserve source assets and cap only packed texture copies at 2048. Convert front/back facial projection materials to light-reactive PBR with the same albedo/UVs and roughness 0.88. Final export, Godot automated checks and front/rear/full-body 360° inspection are complete. Twelve embedded/Vulkan views also passed. Existing head UV boundaries remain; review covers hood removal and outfit preservation. Production and validation evidence is recorded below.

제작·검증 / Production and validation: ../../asset-staging/player_no_hood_20260921/VALIDATION.md

### 노출된 얼굴·눈·머리 수정 / Repair exposed face, eyes and hair

후드 제거 후 드러난 얼굴 재질을 수정했다. 코의 잘못 분류된 72개 면을 얼굴 UV로 복원하고, 얼굴 사진에 남아 이중 눈처럼 보이던 1,120개 픽셀을 주변 피부로 정리했다. 중복 안구는 정리하고 눈꺼풀에 맞춘 갈색 홍채·동공과 음영이 있는 흰자를 적용했다. 두피는 짧은 머리 질감과 연속 앞머리 경계로 정돈했다. 귀 앞·볼 옆·귀 위 머리의 9,085개 면은 원래 앞얼굴과 측면 피부를 공간 기준으로 섞은 1K 재질로 연결해 큰 톱니 색 경계를 줄였다.

English: Repaired the exposed facial materials: restored 72 nose faces to facial UVs, cleaned 1,120 projected eye pixels that looked like a second pair of eyes, removed redundant eye shells, and added aligned brown irises, pupils and shaded sclera. Replaced stretched scalp patterns with short hair and a continuous fringe. A 1K spatial blend connects 9,085 outer-cheek, side-skin and lower-temple hair faces to soften the large jagged color boundary.

머리 형상·다른 25개 메시·전체 27개 메시 구성과 기존 망토·손·팔을 보존했다. 제작·내보내기와 Godot 에셋 검사 3개는 통과했다. 최종 통합 검사와 실제 Godot 10개 시점·360° 뷰어 검수도 완료했다. 검증 결과와 남은 원본 텍스처 품질 한계는 아래 문서에 기록한다.

English: Preserved head geometry, the other 25 meshes, the 27-mesh model, and the existing mantle, hands and arms. Production/export and all three Godot asset checks passed. Final integration, ten actual Godot views and 360° viewer inspection also passed. Results and remaining source-texture limitations are recorded below.

제작·검증 / Production and validation: ../../asset-staging/player_face_repair_20260921/VALIDATION.md

### 제공 머리·눈 모델 적용 / Use the supplied head and eye model

사용자가 제공한 `Untitled.Obj`·`Untitled.mtl`·색상 TGA ZIP을 기준으로 머리와 눈을 교체한다. 기존 머리·머리카락·눈을 제거하고 제공 모델의 6,236개 정점·12,234개 삼각형과 원래 UV를 사용한다. 약 `0.00222755`의 균일 배율과 축 변환·이동으로 몸에 배치하며, 다른 25개 메시는 보존하고 전체 27개 메시 구성을 유지한다. 제공한 세 원본 파일과 4K 아틀라스를 보존하고 게임용 색상 복사본만 2K로 준비한다. 제공되지 않은 선택적 노멀 맵은 생략한다. 제작·Godot 에셋 3개·외형 통합 검사를 통과했고, 실제 렌더 10개 시점과 360° 뷰어에서 원본 얼굴과 목 연결을 확인했다.

English: Replace the old head, hair and eyes with the supplied OBJ/MTL and color atlas, retaining the supplied model's 6,236 vertices, 12,234 triangles and native UVs. Fit it with a uniform scale of approximately `0.00222755`, axis conversion and translation. Preserve the other 25 meshes and the 27-mesh total. Keep all three original files and the 4K atlas; prepare only a 2K runtime color copy. Omit the optional normal map that was not supplied. Production, three Godot asset checks and appearance integration passed; ten actual renders and the 360° viewer confirm the original face and neck join.

제작·검증 / Production and validation: ../../asset-staging/player_supplied_face_20260921/VALIDATION.md


## 2026-09-22 목·어깨 후드 제거 / Remove the draped neck hood

사용자 요청에 따라 `Gravebound_InnerNeckCowl`, `Gravebound_Mantle_L`, `Gravebound_Mantle_R`, `Gravebound_MantleBack`을 실제 모델에서 제거했다. 이전의 목 천·어깨 망토 유지 결정은 이 요청으로 대체한다. 제공한 얼굴·눈과 몸통·양팔·손을 포함한 나머지 23개 메시의 형상·UV·변환·재질은 보존한다. 닫힌 기존 몸통과 소매에 목이 연결되며 별도의 천을 새로 덧대지 않는다.

English: Remove the four neck-cowl and shoulder-mantle meshes at the user's request, superseding the earlier retained-cowl direction. Preserve the other 23 meshes' geometry, UVs, transforms and materials, including the supplied head/eyes, torso and both arms/hands. The existing closed torso and sleeves provide the exposed joins without adding replacement cloth.

제작 원본·검증 / Production source and validation: `asset-staging/player_cowl_removed_20260922/Gravebound_No_Cowl.blend`, `build.py`, `VALIDATION.md`. 게임 대상 / Runtime: `assets/3d/player/gravebound_player.glb`.


## 2026-09-22 노출된 목·어깨 구조 수정 / Rebuild the exposed neck and shoulders

후드 아래 남아 있던 넓은 몸통 캡과 안쪽으로 접힌 소매 캡을 교체한다. 상부 몸통과 양쪽 소매를 연속된 표면으로 만들고, 실제 목둘레 개구부와 목에서 어깨 끝으로 내려오는 경사를 적용했다. 상의와 소매의 경계는 좌표와 법선을 공유한다. 몸통과 새 어깨의 옷감은 기존 소매 아틀라스의 직물 영역으로 UV를 연속되게 맞추고, 전신 옷감 노멀 강도를 0.25로 줄여 과장된 요철을 제거했다. 후드는 다시 추가하지 않는다.

English: Replace the broad torso cap and inward-folded sleeve caps with a continuous upper garment, a real neck opening and sloping shoulders. The chest and sleeves share seam positions and normals. Remap the torso and new shoulders continuously to the existing sleeve atlas's woven cloth region and reduce full-body cloth normal strength to 0.25. The hood remains removed.

사용자가 제공한 얼굴·눈, 양손·손목과 하체를 포함한 다른 20개 메시, 높이 1.24m 아래 몸통 좌표와 소매 좌표·UV를 보존했다. 몸통 UV는 옷감 연결을 위해 전체적으로 다시 배치했다. 이전 전체 의상 23개 메시 불변 원칙 중 몸통·소매 상단 3개 부위만 이번 요청으로 수정한다. 일인칭 팔 원본과 게임 동작은 변경하지 않는다.

English: Preserve the other 20 meshes, including the supplied head/eyes, hands/wrists and lower body, plus torso geometry and sleeve geometry/UVs below 1.24m; torso UVs are intentionally remapped throughout. This request supersedes the prior all-23-mesh preservation only for the three upper garment parts. First-person source assets and gameplay behavior are unchanged.

제작·검증 / Production and validation: `asset-staging/player_natural_shoulders_20260922/` (`build.py`, `Gravebound_Natural_Shoulders.blend`, `VALIDATION.md`, `geometry_audit.json`).

## 2026-09-22 — 코트 자락 제거, 바지만 유지 / Trousers without coat tails

사용자 요청에 따라 `Gravebound_CoatBackAndSides`, `Gravebound_CoatSkirt_L/R`를 제거했다. 기존 바지는 코트에 가려진 두 다리만 있어 골반과 허리 연결이 비어 있었으므로, `Gravebound_Trousers_L/R`를 허리까지 연결된 완전한 바지로 보완했다. 원래 무릎 좌표와 부츠를 유지하고 밑단을 부츠 안에 넣었다. 바지 원단을 상의와 어울리는 기존 어두운 직물로 맞췄다. 머리·상체·팔·손·벨트·주머니·부츠 등 나머지 18개 메시를 보존했으며 최종 구성은 20개 메시다.

English: Remove the three long coat-tail meshes. Complete the two trouser legs with joined hips, crotch and a waist hidden under the shirt/belt, since the coat previously concealed missing upper trousers. Retain the original knee geometry, tuck the trouser hems into the boots and use existing dark cloth. Preserve the other 18 meshes, including the head, upper body, hands, belt, pouches and boots; the model now has 20 meshes.

제작·검증 / Production and validation: `asset-staging/player_trousers_only_20260922/`. 원본 이전 모델은 보존한다. 360° 뷰어는 같은 게임 GLB를 읽는다. 실제 하의 검사 프리뷰는 `PLAYER_QA_TROUSERS_DETAIL=1`로 앞·뒤·아래쪽을 추가 촬영한다.

English: Preserve earlier models. Production assets and validation live in the folder above. The 360° viewer reads the same game GLB; `PLAYER_QA_TROUSERS_DETAIL=1` adds front, rear and low-angle trouser captures.

## 2026-09-22 — 가슴·등·겨드랑이·위팔 통합 조형 (철회됨) / Resculpt the upper-body transitions (reverted)

사용자가 어깨와 몸통 접합의 어색함을 다시 지적했다. 기존 메시에서 가슴 외측이 깊게 패였다가 소매 캡에서 다시 솟는 앞뒤 단면을 확인했다. 단순 외곽선 정리와 메시 연결 검사는 인체 형태의 시각적 완성도를 보장하지 못했다.

English: The user identified an unnatural chest-to-arm junction. Cross-sections showed a deep outer-chest valley followed by a separate sleeve-cap bulge. Smooth outer silhouettes and seam tests alone did not establish natural-looking anatomy.

현재 작업은 `asset-staging/player_shoulder_form_20260922/`에서 가슴·등·양쪽 위팔을 한 표면으로 다룬다. 접합 골을 채우고 어깨 바깥쪽 부피를 줄이며, 고정된 수직 경계를 풀어 겨드랑이와 어깨 상단을 다듬는다. 기존 직물의 연속 UV로 어깨 아래 띠 경계도 정리한다. 목 개구부·손목 피부와 다른 17개 메시를 보존하며, 1.18m 이하 기하는 유지한다. 피부/옷감 비트맵과 일인칭 에셋은 수정하지 않는다.

English: Sculpt the chest, back and both upper sleeves together, filling the junction valley, reducing the lateral shoulder cap and releasing the fixed vertical seam to round the underarms and upper shoulders. Continuous cloth UVs remove the shoulder band. Preserve the neck opening, cuff skin, 17 other meshes and geometry below 1.18m. Bitmap sources and first-person assets remain unchanged.

검토 도구 / Review tooling: `PLAYER_QA_SHOULDER_FORM=1`은 정면·사선·측면·후면의 재질/무채색 8장을 같은 카메라로 촬영한다. 원래 화면과 재질·카메라 상태는 복원한다. 최종 해시와 검증 결과는 제작 폴더 `VALIDATION.md`에 기록한다.

English: `PLAYER_QA_SHOULDER_FORM=1` adds eight matching textured/clay views, restoring materials and camera state afterward. The production folder's `VALIDATION.md` records the accepted model hash and validation.

## 2026-09-22 — 사용자 요청으로 직전 팔 복원 / Restore the previous arms at the user’s request

사용자가 마지막 어깨·팔 조형 결과가 더 부자연스럽다고 지적해 되돌리기를 요청했다. `9081104`의 모델을 철회하고, 바로 이전 `f279eec`의 바지만 남긴 전신 모델을 바이트 단위로 복원했다. 원본은 `asset-staging/player_trousers_only_20260922/gravebound_player_trousers_only.glb`, SHA256은 `f7ad57eddd4ac751daee53fcdb05bf627a749007f0989d9f344f735dfb2e2a77`이다. 얼굴·손·바지와 후드/코트 제거 상태는 그대로 유지한다. 마지막 조형 자료는 이력으로 보존하며 현재 게임에 사용하지 않는다.

English: The user rejected the latest shoulder/arm sculpt as less natural. Restore the immediate predecessor from `f279eec` byte for byte, retaining the supplied face, hands, trousers and hood/coat removal. Keep the rejected sculpt as historical production material, not the active game model. Restoration evidence: `asset-staging/player_shoulder_rollback_20260922/`.

## 2026-09-22 — 목과 어깨 체격 보강 / Strengthen the neck and shoulder build

사용자가 복원본의 목·어깨를 더 듬직하게 요청했다. 기준은 복원한 `f279eec` 모델이며 철회된 재조형본은 사용하지 않는다. 노출 목 아래쪽은 가로 최대 16%, 앞뒤 최대 12% 넓히고 턱이 시작되는 1.51m 높이에서 변화가 0이 되도록 완화한다. 옷깃에도 같은 방향의 팽창을 적용한다. 양쪽 소매와 손은 원래 형상을 유지한 채 각각 18mm 바깥으로 이동하며, 상부 몸통을 연결해 어깨 폭을 총 36mm 늘린다. 승모근 윗윤곽은 최대 9mm 범위에서 완만하게 높인다. 얼굴·눈·하의·원본 직물/피부 텍스처와 일인칭 에셋은 유지한다.

English: Start from the restored `f279eec` model. Thicken the lower neck by up to 16% in width and 12% in depth, fading to no change at 1.51m before the facial geometry. Expand the neckline accordingly. Translate each original sleeve and hand outward by 18mm without resculpting them, widening the shoulder frame by 36mm while blending the upper torso and lifting the trapezius silhouette by up to 9mm. Preserve the face, eyes, trousers, bitmap materials and first-person assets.

제작·검증 / Production and validation: `asset-staging/player_sturdy_neck_shoulders_20260922/`. 360° 뷰어는 실제 게임 GLB를 공유한다. The interactive viewer uses the same game GLB.

## 2026-09-22 — 목·어깨 흐름과 소매 원단 연결 / Neck, shoulder and sleeve flow

직전 목·어깨 보강본을 기준으로 듬직한 체격을 유지하며 접합부를 국소적으로 조정한다. 목에는 과장된 힘줄 대신 최대 약 2.3mm의 넓고 완만한 입체감을 더했다. 어깨와 가슴 사이 골을 완화하고 둥근 소매 캡을 소폭 줄였으며, 실제 겨드랑이 공간과 팔꿈치·전완·손목 형상은 보존한다. 상체 옷 기하 변화는 1.275m 위에 한정하며 최대 약 7.6mm다. 철회된 팔 전체 재조형본은 사용하지 않는다.

English: Preserve the sturdy source build while making localized corrections. Add broad, subtle neck form up to about 2.3mm, soften the chest-to-shoulder valley and slightly reduce the sleeve cap. Retain the real underarm opening and original elbow, forearm and wrist geometry. Upper garment geometry changes are limited to above 1.275m, up to about 7.6mm; the rejected broad arm resculpt is not reused.

원단 연결은 UV 좌표 보간 대신 표면의 색과 노멀을 혼합해 상부 소매 전용 PBR 텍스처로 베이크한다. 기존 UV와 하단 소매·피부 재질은 보존한다. 얼굴 1.51m 위와 다른 16개 메시도 유지한다. 원본 비트맵과 일인칭 원본 에셋은 변경하지 않는다. 제작·검증과 실제 렌더 근거는 `asset-staging/player_neck_arm_flow_20260922/VALIDATION.md`에 기록한다.

English: Bake a surface-color and normal blend into standard PBR maps for the upper sleeves. Preserve original UVs, lower-sleeve and skin materials, the face above 1.51m and the other sixteen meshes. Source bitmaps and first-person assets remain unchanged. See the production folder above for validation and actual-render evidence.

## 2026-09-22 — 제공 사진을 기준으로 상체 비율 재조정 / Reference-guided upper-body proportions

사용자가 제공한 사진을 기준으로 국소적인 목·어깨 수정에서 상체 전체 비율 조정으로 범위를 넓혔습니다. 원통형 몸통의 앞뒤 두께를 줄이고 가슴·흉곽과 허리의 관계를 조정했습니다. 과도한 어깨 폭을 줄이고 경사를 복원했으며, 위팔의 부피와 팔꿈치 높이를 함께 바꿨습니다. 이번 요청은 이전의 팔꿈치·전완 형상 고정 조건을 대체합니다. 얼굴·손·손목·하의와 기존 복장은 보존합니다.

English: The supplied reference broadens the task from local neck/shoulder polishing to overall upper-body proportions. Reduce cylindrical torso depth, refine chest-to-waist form, narrow and slope the shoulders, and adjust upper-arm volume and elbow height together. This request supersedes the earlier restriction on elbow/forearm reshaping. Preserve the existing face, hands, cuffs, lower body and outfit.

제작 원본과 수치·화면 검증: `asset-staging/player_reference_anatomy_20260922/VALIDATION.md`. 실제 렌더 13장과 별도 360° 뷰어는 현재 게임 GLB `6fc422a8…`를 확인했습니다. 사진은 큰 체형을 위한 참고이며 머리·헤어·상의 교체 요청으로 해석하지 않습니다.

English: Production sources and numeric/visual evidence live in the validation folder above. Thirteen actual renders and the interactive viewer use current game GLB `6fc422a8…`. The photograph guides body proportions; it does not request replacing the supplied face, hair or outfit.

## 2026-09-22 — 4방향 사진 기준 전신 비율 / Four-view full-body reference fit

새 정면·후면·양측면 사진을 기준으로 전신을 함께 조정했습니다. 앞선 얼굴·손·하체 치수 유지 조건은 이 요청으로 대체하며, 기존 인물·복장·재질을 유지합니다. 머리 폭, 어깨 경사, 흉곽과 허리, 팔 길이·각도, 골반 높이, 다리 간격과 부츠 크기·옆모습을 맞췄습니다. 가랑이 연결부와 소매 끝의 급격한 단차도 연속되게 정리했습니다.

English: Refit the whole body from four supplied reference views, superseding prior dimension locks while preserving the character, outfit and materials. Adjust head width, shoulder slope, chest/waist, arm lengths and stance, pelvis height, legs and boots, with continuous crotch and cuff transitions.

현재 GLB: `3f4638ee…`. 제작 원본·비교 사진·실측·게임 검사와 실제 렌더는 `asset-staging/player_multiview_proportions_20260922/VALIDATION.md`에 기록합니다. 360° 뷰어의 **사진 비율 비교**에서 네 방향의 사진과 모델을 겹쳐 살펴볼 수 있습니다. 사진은 정사영 스캔이 아니므로 남은 비율 차이를 문서에 수치로 명시하며 완전 복제라고 간주하지 않습니다.

English: Production, reference measurements, checks and actual captures are documented in the validation folder above. The viewer's photo-comparison link supports four-view wipe and silhouette overlays. Quantify remaining differences rather than claiming exact reconstruction from uncalibrated photographs.
