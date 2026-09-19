# 방패 파편 제작 / Shield fragment authoring

Mac Blender 5.2.1 백그라운드에서 실제 `round_shield_low.glb`를 **32개 파편(목재 21·금속 9·가죽 2)**으로 나눴다. 게임용 결과는 `godot-game/assets/3d/player/shield_damage/round_shield_fragments.glb`, 제작 원본은 이 폴더의 `shield_fragments.blend`다. 원본·중·하 단계 GLB는 수정하지 않았다.

The actual low-condition shield was partitioned in background Mac Blender 5.2.1 into **32 fragments: 21 wood, 9 metal and 2 leather**. The game asset is `godot-game/assets/3d/player/shield_damage/round_shield_fragments.glb`; this folder preserves `shield_fragments.blend`. Original, medium and low source GLBs remain unchanged.

## 재생성 / Rebuild

프로젝트 루트에서 실행한다. 엔진은 한 번에 하나만 실행하고 Godot 검사와 겹치지 않는다.

Run from the project root, without overlapping a Godot process:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python asset-staging/shield_shatter_20260919/build_shield_fragments.py
python3 asset-staging/shield_shatter_20260919/validate_fragments.py
```

## 구조·재질 / Structure and materials

- 메시 이름은 `ShieldFragment_###_wood/metal/leather`다. 파편당 메시 하나이며 원점은 바운딩 박스 중심이다. 회전·스케일은 단위값, 이동값으로 원래 하 방패를 재조립한다. GLB는 Godot 좌표이며 Blender `(X,Y,Z)`는 Godot `(X,Z,-Y)`로 변환된다.
- 기존 외면과 재질을 유지하고 새 목재 절단면은 `FP_ShieldFractureOak`을 사용한다. 열린 얇은 철테·버클·봉제 표면은 기존 면을 유지하며 안쪽으로 약 0.8mm 두께와 닫힘을 추가했다. 작은 리벳·봉제·버클은 인접한 파편과 한 몸으로 움직인다.
- 나이테는 파편별 재질의 `wood_coordinates`에 **분리 전 방패 기준 파편 로컬 변환**을 전달한다. 이후 월드 이동을 넣으면 나뭇결이 미끄러진다. `wood_coordinate_offset` extras와 manifest의 `origin_godot`도 원래 중심 위치를 제공한다.
- 충돌은 파편별 볼록 껍질 하나를 만들 수 있다. 휜 철테와 손잡이의 오목한 빈 공간은 단일 볼록체로 근사한다. 런타임 질량·충격·바닥 마찰은 게임 통합에서 검수한다.

Each `ShieldFragment_###_wood/metal/leather` node contains one mesh centered on its bounding box, with identity rotation/scale. Its translation restores the source position. Existing exteriors/materials are retained; new wood caps use `FP_ShieldFractureOak`. Originally open thin rim, buckle and stitch surfaces receive approximately 0.8mm inward backing. Small hardware remains attached to its neighbouring fragment. Supply the **original shield-local fragment transform**, not its later world transform, as the grain shader's `wood_coordinates`. The `wood_coordinate_offset` extras and manifest also record original centers. One convex collision hull per fragment is a practical approximation; curved rim/strap hollows are intentionally approximated.

## 제작 검증 / Authoring validation

`manifest.json`과 `build.log`에 결과를 기록했다. 32개 전부 열린 경계와 비정상 공유 모서리가 0이다. 원본의 모든 정점·면 중심과 재조립 메시 사이 최대 거리는 **0.0499mm 미만**이다. 내·외부 절단면을 포함한 볼록체 부피, 재질, 파편 좌표와 원본·출력 해시를 기록했다. 표준 Python 검사도 GLB의 메시 수·중심·이동·재질·해시를 확인한다. **실제 흩어짐과 바닥 충돌, Godot 렌더는 제작 검증과 별도로 게임 통합 담당자가 확인한다.**

The manifest and build log record closed shells for all 32 fragments: zero boundary and non-manifold edges. Every source vertex and face center is within **0.0499mm** of the reassembled mesh. Per-fragment volume, convex volume, materials, transforms and source/output hashes are recorded. The standard Python check verifies exported counts, centered bounds, translations, materials and hashes. **Actual scattering, floor collision and Godot rendering require separate runtime integration validation.**

물리 통합에서 중앙 금속 파편 `029`의 큰 빈 공간을 덮는 볼록체가 발견되어 분류를 수정했다. 긴 철테는 평균 중심이 아니라 실제 정점 반경으로 분류하고, 뒤쪽 장착 리벳 7묶음은 원래 목재에 붙였다. 중앙 보스는 **17.40×17.40×3.86cm**, 볼록 부피는 **0.00045994m³**로 제한되며 금속 파편의 크기·부피 회귀 검사도 추가했다. 수정 전 제작본은 `classification_baseline/`에 보존했다. 최종 GLB의 1μm 미만 이동 성분은 Blender 내보내기 정밀도로 0이 될 수 있으며 검사도 이 한도를 따른다.

Runtime integration exposed an oversized convex hull on central metal fragment `029`. The revision classifies long rim arcs by actual vertex radius, not their centroid, and attaches seven rear-mount hardware groups to their original planks. The central boss is now **17.40×17.40×3.86cm**, with **0.00045994m³** convex volume; size/volume regressions prevent a return of the oversized metal hull. Previous authoring output is preserved in `classification_baseline/`. Blender may zero exported translation components smaller than 1μm; validation uses that precision limit.
