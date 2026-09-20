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
