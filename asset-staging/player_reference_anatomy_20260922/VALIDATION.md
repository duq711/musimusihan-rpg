# 참조에 따른 상체 비율 수정 / Reference-guided upper-body proportions

사용자가 제공한 근육질 남성 사진을 큰 비율의 참고로 삼아 목·흉곽·어깨·위팔·팔꿈치를 함께 조정했습니다. 기존 얼굴과 옷은 유지합니다. 참조는 사선 상반신 이미지이므로 전신 실측 자료나 동일 인물의 복제로 취급하지 않습니다.

English: Refit the neck, rib cage, shoulder frame, upper arms and elbow placement using the supplied muscular upper-body reference. Retain the existing face and outfit. The oblique reference guides broad proportions, not exact full-body measurements or identity reproduction.

## 산출물 / Outputs

- Source: `../player_neck_arm_flow_20260922/Gravebound_Neck_Arm_Flow.blend` (preserved).
- Editable result: `Gravebound_Reference_Anatomy.blend`.
- Reproducible build: `build.py`, `deformation.py`.
- Export: `gravebound_player_reference_anatomy.glb`; identical game asset at `godot-game/assets/3d/player/gravebound_player.glb`.
- GLB SHA256: `6fc422a8219ad9d6b431fb800efb22b2277e5235e29aa9ed8fb85129d5d825d7`.
- Actual captures: `godot-game/artifacts/visual_qa/player_appearance/reference_anatomy_20260922/`.

Blender 5.2.1 LTS on this Mac, background with two threads. Rebuild from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b -t 2 --python-exit-code 1 --python asset-staging/player_reference_anatomy_20260922/build.py
```

## 변경 / Changes

가슴의 원통형 앞뒤 두께를 줄이고 흉곽과 가슴 앞쪽 부피를 구분했습니다. 어깨 중심을 좌우 최대 20mm 안쪽으로 이동하고, 목에서 바깥어깨로 내려가는 경사를 조절했습니다. 위팔의 부피를 재분배하고 팔꿈치를 평균 25.77mm 내려 위팔과 전완의 길이 관계를 바꿨습니다. 손목에 이르기 전에 변형을 완전히 없애 손과 소매 끝의 연결을 보존했습니다.

English: Reduce barrel-like torso depth, distinguish anterior chest volume, narrow the shoulder frame by up to 20mm per side and restore its downward slope. Redistribute upper-arm volume and lower the authored elbow region by 25.77mm on average. Fade deformation to zero before the cuff, preserving the hands and wrist connections.

얼굴 Z≥1.51m와 다른 16개 메시, 모든 토폴로지·UV·재질 및 기존 비트맵을 보존했습니다. 위팔 베이크 UV의 active/render 설정도 유지합니다. 하의·부츠·벨트·파우치·일인칭 원본은 수정하지 않습니다.

English: Preserve facial geometry above 1.51m, sixteen other meshes, all topology, UVs, materials and bitmap sources, including the active/render UV used by the sleeve normal-map bake.

## 검증 / Validation

- Asset regressions: `player_fullbody_fp_arms`, `player_hood_closure`, `player_face_asset` — 3 passed.
- Game integration: `player_appearance` — passed actual test-room/inventory model sharing, rotation, F2 roundtrips, reset, cleanup and expedition-state restoration. Existing engine exit warning reported one ObjectDB instance; no test assertion or script error.
- Blender independent audit: protected geometry unchanged, shared shoulder boundaries within 0.000121mm, no new degenerate triangles or significant reversed triangles. Four microscopic collar slivers change orientation at floating-point scale; see `geometry_audit.md`. This bounded audit does not claim exhaustive self-intersection testing.
- Actual rendering: 13 Vulkan/embedded captures using the unmodified production `player_portrait.gd` and current GLB. Texture/clay front, oblique, side and rear, plus full-body and face views. The new `player_anatomy_preview.gd` loads only those asset dependencies; it avoids unrelated gameplay preloads encountered in the broad preview. Fresh import completed before rendering, captured manifest matches the GLB above.
- Visual review: compared source and candidate silhouettes and the user reference. Chest-to-waist taper, shoulder width/slope and upper-arm share improved. Small cloth ridges at the inner shoulder and a simplified neck surface remain; this is a clothed game model, not a perfect anatomical reproduction of the photograph.
- 360° viewer: loaded the current model, selected upper-body view and visually checked it. `/model-info.json` returned the same SHA above. Local game import cache was refreshed for this player only.

한국어 요약: 에셋 검사 3개·게임 연결 검사 1개를 통과하고 실제 렌더 13장을 검토했습니다. 검사 통과를 해부학적 완성의 자동 증명으로 보지 않고, 참조와 이전 모델을 직접 비교했습니다. 제작 원본과 검증 결과는 이 폴더에 보존합니다.

English summary: Three asset checks and one game integration check passed; thirteen actual-renderer images were reviewed against the reference and source. Passing regressions is not an automatic claim of anatomical perfection.
