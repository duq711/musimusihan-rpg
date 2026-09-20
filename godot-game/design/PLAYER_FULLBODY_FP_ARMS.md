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
