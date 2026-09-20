# 전신 양팔 교체 검증 / Full-body FP arm validation

2026-09-20. 현재 1인칭 FP arms를 전신에 적용하고 예전 손·손톱·겹치는 소매·토시 16개를 제거했다. 다른 24개 부위의 형상·UV·변환은 제작 단계에서 서명으로 대조했다. 원본 전신은 `original_gravebound_player.glb`에 로컬 보존하며 이전 Git LFS 이력과 9월 11일 제작 자료도 유지한다.

Applied the current first-person FP arms to the full body, removing 16 old hand/nail/sleeve/bracer objects. Geometry, UVs and transforms of the other 24 parts were checked against source signatures. The original is preserved locally and in previous Git LFS history and September 11 production sources.

## 제작 검증 / Production checks

- `build_report.json`: 원본·양팔·최종 GLB 해시, 제거 목록, 보존 서명, 소매 맞춤 수치를 기록한다. / Records input/output hashes, removed parts, retained signatures and sleeve-fitting measurements.
- Godot의 실제 본 변형을 Blender 축 체계로 옮긴 직후 정점 최대 차이는 0.00000556m 미만이다. 이후 전신용 소매 상단만 12.5cm 연장·안쪽 이동·폭 조절했다. 손과 손목 아래 연결부는 이 추가 변형에서 보존된다. / Maximum baked-vertex error against actual Godot skinning is below 0.00000556m before the documented sleeve fit. Sleeve tops are extended 12.5cm and tapered/inset under the mantle; hands and the lower wrist connection are preserved.
- 실제 제작은 이 Mac의 Blender 5.2.1 백그라운드 실행으로 수행했다. 생성 이미지로 게임 화면을 대체하지 않았다. / Authored in background Blender 5.2.1 on this Mac; no generated image substitutes for game renders.
- 편집 가능한 결과: `Gravebound_FP_Arms.blend`. 재현 절차: `export_pose.gd` → `build.py`. / Editable result and reproducible pose-export/build scripts are included.

## 게임 검사 / Game checks

- `asset_final.log`: `player_fullbody_fp_arms` 통과. 28개 실제 메시, 구형 손 제거, 어깨 안쪽 소매 높이, 손목 위치, 손 크기, 조명 반응 재질을 검사했다. / Passed actual geometry, retired-part removal, shoulder fit, wrist position, glove dimensions and materials.
- `integration_final.log`: `player_appearance` 통과. 실제 F2 외형 화면, 회전, 본편 연결, 재선택, 초기화, 정리와 원정 복원을 검사했다. 평소 I는 기존 통합 건강·장비 화면을 유지한다. / Passed real appearance entry, rotation, dungeon routing, repeated entry, reset, cleanup and session restoration; ordinary I retains the unified page.
- `fp_regression.log`: `supplied_fp_arms` 통과. 1인칭 원본과 동작 코드는 이번 작업에서 수정하지 않았다. / First-person regression passed; FP source assets and behavior code are unchanged by this task.
- 통합 검사는 종료 시 ObjectDB 1개 경고를 남긴다. 검사 자체와 플레이어·초상 정리의 약한 참조 검증은 통과했다. OS 하드웨어 입력이나 새로운 전신 애니메이션을 검증했다는 뜻은 아니다. / Integration exits with one ObjectDB warning while assertions, including player/portrait weak-reference cleanup, pass. This does not claim OS hardware-input coverage or new full-body animation.

## 실제 화면 / Actual renderer review

최종 화면: `../../godot-game/artifacts/visual_qa/player_appearance/fullbody_fp_arms_review_05/`.

Godot 4.7의 검증된 embedded/Vulkan 실행기로 9장을 촬영했다. 전신 정면·사선·측면·후면·얼굴, 실제 1인칭, 인벤토리, 폐광과 폐광 위 외형 화면이다. 양쪽 어깨·손목·손가락과 인벤토리의 회전 버튼을 검토했고 실제 GUI의 오른쪽 회전·정면 복귀 검사가 통과했다. 매니페스트의 GLB SHA-256은 최종 게임 파일과 같다. 원정·커서 상태는 보존됐으며 창·외부 입력·소리를 사용하지 않았다. 이전 후보 화면은 최종 결과로 사용하지 않는다.

Nine actual embedded/Vulkan captures cover front, quarter, side, back, face, first-person, inventory and cave views. Shoulder/wrist/finger connections and inventory controls were reviewed. Local GUI right/reset checks passed. The manifest's model SHA-256 matches the final runtime GLB; expedition and cursor state were preserved without native windows, external input or audio. Earlier candidates are not final evidence.

프로젝트 전체 가져오기는 무관한 파일 읽기에서 지연되어 모델만 같은 리소스 경로의 임시 프로젝트에서 정상 가져왔다. 가져온 캐시와 UID 항목은 로컬에만 적용하며 공유 대상에서 제외했다. / An unrelated file-read delay blocked whole-project import, so the model was normally imported in an isolated project with identical resource paths. Generated caches and UID-cache changes remain local and are not published.

FP arms 원본: DJMaesen, CC BY 4.0. [출처와 가공 표기](../../godot-game/assets/3d/player/fp_arms/ATTRIBUTION.md). / Source and modification attribution is preserved in the linked asset record.

## 게시 사본 / Publication snapshot

원격 최신본 `3cecd2a`에 이번 변경만 적용한 별도 사본에서도 에셋 검사와 외형 통합 검사가 통과했다. 게시 사본은 ObjectDB 2개 종료 경고를 유지한다. 원격본과 로컬 작업본의 다른 진행 중 기능은 합치지 않았다. / Both asset and appearance-integration checks passed on the isolated publication snapshot based on remote `3cecd2a`. It retains two ObjectDB exit warnings. Unrelated local work was not included. See `publication_asset_final.log` and `publication_integration_final.log`.
