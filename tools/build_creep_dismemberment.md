# 크리프 절단용 메시 제작 / Creep detachable skin build

원본 `godot-game/assets/licensed/creep/creep.glb`을 준비한 다음 실행합니다. Python 표준 라이브러리만 사용하며 Blender·Godot 창을 열지 않습니다.

With the original locally licensed GLB installed, run these standard-library Python tools; neither opens a Blender or Godot window.

```sh
python3 tools/build_creep_dismemberment.py
python3 tools/verify_creep_dismemberment.py
```

결과는 `godot-game/assets/licensed/creep/creep_dismembered.glb`입니다. 원본 모델·55개 관절·17개 애니메이션·피부 재질·텍스처를 보존합니다. 원본과 파생 GLB는 라이선스 에셋이므로 공개 저장소에 올리지 않습니다. 이 제작 스크립트와 검증 스크립트만 공개합니다.

The output is `godot-game/assets/licensed/creep/creep_dismembered.glb`. The source file, 55 joints, 17 clips, original skin material and textures are preserved. Both GLBs remain local licensed assets; only the build and verification code is public.

## 게임 연결 / Runtime contract

- `CreepPart_left_arm`, `CreepPart_right_arm`, `CreepPart_left_leg`, `CreepPart_right_leg`, `CreepPart_head`, `CreepPart_torso`: 같은 뼈대를 공유하는 실제 분리 메시입니다. / Six physically separate meshes sharing the original skin.
- `CreepCap_body_<부위>`: 절단 전에는 숨기고 해당 부위 절단 후 몸체에 남기는 절단면입니다. / Hide until severed; keep this cap on the animated body.
- `CreepCap_part_<부위>`: 해당 부위가 떨어질 때 그 부위와 함께 현재 변형 상태를 구워 독립 물리 물체에 포함합니다. / Bake this cap with its detached part in the current skinned pose.
- GLB의 `hidden_until_severed` 메타데이터만으로 Godot가 자동으로 숨기지는 않습니다. 게임 코드가 캡 10개를 처음부터 숨겨야 합니다. / Metadata does not automatically hide caps in Godot; the runtime must hide all ten initially.
- 좌우는 뼈 이름 `.L`, `.R`을 따릅니다. 독립 루트인 `Hand.L/R`, `Foot.L/R`도 각각 팔·다리에 포함합니다. 어깨 `Shoulder.L/R`은 몸체에 남으며, `Neck`은 몸체에 남고 `Head`, 턱·혀는 머리에 포함합니다. / Regions follow the named left/right bones and include the independently rooted hands and feet. Shoulders and neck remain with the torso; head, jaws and tongue belong to the detached head.

## 제작과 검증 / Construction and checks

각 부위의 뼈 영향치 합이 0.5인 경계에서 기존 삼각형을 잘라 양쪽에 정확히 같은 위치의 정점을 만듭니다. 자외선 좌표와 관절 영향치를 보간하며, 각 경계의 닫힌 고리 안에 겹치지 않는 삼각형 절단면을 만듭니다. 몸체와 떨어질 부위의 캡은 반대 방향을 향합니다.

Triangles are clipped at a region influence of 0.5. Both sides use matching interpolated positions, UVs and joint weights. Each closed boundary is tessellated into non-overlapping cap triangles with opposite-facing body and detached-part normals.

Godot의 관절 영향치 8개 제한에 맞추기 위해 새 정점에서는 영향치가 가장 큰 8개를 유지하고 다시 정규화합니다. 버려지는 영향치 합은 피부 경계 최대 1.415%, 내부 단면 보간 최대 2.689%입니다. 양쪽 정점과 캡은 동일한 보정을 사용합니다. 17개 클립에서 85개 자세를 확인했을 때 이 경계의 양쪽 위치 차이는 0m였습니다.

Godot supports eight skin influences. New vertices retain and renormalize their strongest eight influences; discarded weight stays below 1.415% at skin seams and 2.689% in interpolated cap interiors. Both surfaces and caps use identical results. Across 85 poses from all 17 clips, the measured seam gap was 0m.

모든 새 절단면은 닫혀 있습니다. 머리의 원본 치아·입 메시에는 열린 모서리 238개와 비다양체 모서리 2개가 있으며 원본 그대로 보존합니다. 새 절단에서 생긴 구멍이 아닙니다. 전체 피부 면적 상대 오차는 약 `4.16e-10`입니다. 이 검사는 파일·형상·CPU 피부 변형 검사이며, 실제 Godot 렌더링·전투·절단 물리는 별도로 검증합니다.

All new cut surfaces are closed. The original mouth/teeth geometry contains 238 open edges and two non-manifold edges; these are preserved, not introduced by cutting. The relative skin surface area error is about `4.16e-10`. These tools validate files, geometry and CPU skinning; live Godot rendering, combat and detachment physics require separate checks.

로컬 상세 보고서 / Local detailed reports:

- `exports/Creep_20260917/dismemberment_report.json`
- `exports/Creep_20260917/dismemberment_geometry_validation.json`

2026-09-18: 단면에는 COLOR_0·UV와 최대 3.5cm의 안쪽 깊이, 어두운 경계·근육·작은 뼈 중심을 추가했습니다. [런타임·실제 검수](../godot-game/docs/CREEP_WOUNDS.md). / Caps now include tissue vertex colors, UVs and up to 3.5cm of recessed geometry, with dark rims, muscle and a small bone core. See the linked runtime and rendering guide.
