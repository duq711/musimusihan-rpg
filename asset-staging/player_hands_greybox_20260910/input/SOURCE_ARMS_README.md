# 1인칭 검·방패 모델 출처

현재 손 모델과 검·방패 모델은 서로 다른 제작 단계의 결과물입니다. 형상·재질·실제 게임 화면의 비교는 [다방향 시각 검수 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/artifacts/visual_qa/sword_shield_multiview/REVIEW.md>)에서 관리합니다.

| 파일 | 게임에서의 용도 |
|---|---|
| `right_arm.glb` | 기존 `sword_shield_first_person/build_assets.py` 결과를 유지합니다. 오른손의 검 파지, 장갑, 팔 보호대와 소매입니다. |
| `left_arm.glb` | 기존 `sword_shield_first_person/build_assets.py` 결과를 유지합니다. 왼손의 방패 뒤 손잡이 파지, 장갑, 팔 보호대와 소매입니다. |
| `longsword.glb` | 새 `sword_shield_multiview/build_multiview_assets.py`가 `sword_geometry.py`로 만든 현재 검입니다. `PittedBlade`는 실제 칼날 충돌 판정에 사용하며 `HandGrip`, `BladeTip` 기준점을 포함합니다. `GripLeather`, `GripBinding`, `FullerPolishedChannel`은 대장간 개조 재질 연결을 유지합니다. |
| `round_shield.glb` | 새 `sword_shield_multiview/build_multiview_assets.py`가 `shield_geometry.py`로 만든 현재 방패입니다. 목판·금속 테두리·가죽 끈과 `RearGrip`, `RearGripTop`, `RearGripBottom`, `RearArmStrap` 기준점을 포함합니다. |

현재 검·방패는 Codex 내장 ImageGen으로 생성한 [검 여섯 방향 참조](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/sword_views_v2.png>)와 [방패 여섯 방향 참조](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/shield_views_v1.png>)를 기준으로 실제 입체 형상을 제작한 결과입니다. 검의 홈·날 경사면·가드·손잡이·폼멜과 방패의 목판·테두리·보스·뒤쪽 끈을 실제 메시로 구성합니다. 전체 프롬프트, 생성 방식 `built-in image_gen`, 원본 출력 위치는 [generation_records.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/generation_records.json>)에 있습니다. 이 기록은 첫 검·방패 참조 생성과 첫 검 참조의 위·아래 방향을 교정한 편집 요청을 함께 담습니다. 현재 검 제작에는 교정 결과인 `sword_views_v2.png`를 사용합니다.

새 검·방패 표면에는 생성 결과의 원본 픽셀을 보존한 [weapon_material_atlas_v2.png](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/ai/sword_shield/weapon_material_atlas_v2.png>)를 사용합니다. 이미지의 왼쪽 위는 깨끗한 칼날 강철, 오른쪽 위는 오래된 철, 왼쪽 아래는 참나무, 오른쪽 아래는 가죽입니다. 아틀라스 전체 프롬프트, 생성 방식과 원본 출력 위치는 [atlas_generation.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/atlas_generation.json>)에 보존합니다. 이 생성 이미지에 외부 원본 자료의 CC0 표시를 적용하지 않습니다.

표면의 얕은 요철에는 같은 아틀라스를 입력으로 Codex 내장 ImageGen 편집으로 생성한 [weapon_material_normal_v2.png](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/ai/sword_shield/weapon_material_normal_v2.png>)를 연결합니다. 네 사분면 배치와 표면 무늬에 대응하도록 요청한 접선 공간 OpenGL 노멀 맵입니다. 입력·출력 경로, 정확한 방식 `built-in image_gen edit`와 전체 프롬프트는 [normal_generation.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/normal_generation.json>)에 있습니다. 이 생성 노멀 맵에도 외부 자료의 CC0 표시를 적용하지 않습니다.

새 빌더는 목판별 원래 UV 영역을 포함한 각 입체 표면의 UV를 해당 재질 사분면 안에 배치하고, 실제 형상이 만드는 가림을 계산해 `AmbientOcclusion` 정점 색으로 저장합니다. 게임은 `FP_Sword*`, `FP_Shield*` 재질에 알베도 아틀라스·생성 노멀 맵·정점 색을 연결하고 `StandardMaterial3D`의 금속성·거칠기로 렌더링합니다. 금속의 거칠기 변화에는 알베도 아틀라스 적색 채널을 예술적 변조값으로 사용합니다. 입체 형상·UV·정점 가림은 모델에, 공용 텍스처 연결은 게임 코드에 남습니다.

현재 무기 제작 코드는 [build_multiview_assets.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/build_multiview_assets.py>), [sword_geometry.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/sword_geometry.py>), [shield_geometry.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/shield_geometry.py>)입니다. 실행 결과는 같은 폴더의 [build_report.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/build_report.json>)과 편집용 `sword_shield_multiview.blend`에 기록합니다.

손의 원형은 Blender Foundation / Blender 프로젝트의 [Human Base Meshes Bundle v1.4.1](https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip)입니다. 기존 [용병 제작 리소스 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_mercenary_crossbowman_photoreal/SOURCES_AND_LICENSES.md>)에 보존된 **CC0 1.0** 자료를 재사용했습니다. `Body Male - Realistic`의 `GEO-body_male_realistic`에서 손을 추출·정렬하고, 좌우 형상을 따로 만들어 바인딩했습니다. 소매·보호대 형상과 손 리그는 기존 프로젝트 제작 스크립트의 결과를 유지합니다.

각 손은 손목 1개와 다섯 손가락의 관절 각 3개, 총 **16개 본**에 연결된 연속 피부 메시입니다. 손가락 없는 장갑 메시에도 같은 본 가중치를 복사했습니다. 게임은 실제 본 회전으로 파지를 바꾸며, 소매와 팔 보호대는 별도 구간 메시로 팔꿈치에 맞춥니다. GLB에는 스킨과 본을 내보내고 애니메이션 클립은 내보내지 않습니다.

기존 손 재질과 과거 무기 제작에 사용한 외부 원본은 아래와 같습니다. Poly Haven 자료의 라이선스는 기존 출처 기록에 **CC0 1.0**으로 보존돼 있습니다. [Poly Haven 라이선스](https://polyhaven.com/license), [CC0 원문](https://creativecommons.org/publicdomain/zero/1.0/).

| 원본 | 적용 |
|---|---|
| [Brown Leather](https://polyhaven.com/a/brown_leather) | Blender 제작용 가죽 알베도·노멀. 게임의 `textures/leather_normal.jpg`는 기존 `brown_leather_nor_gl_2k.jpg`와 동일한 파일입니다. |
| [Rough Linen](https://polyhaven.com/a/rough_linen) | Blender 소매 알베도·노멀. `textures/linen_albedo.jpg`, `textures/linen_normal.jpg`는 기존 `rough_linen_diff_2k.jpg`, `rough_linen_nor_gl_2k.jpg`와 각각 동일합니다. 게임에서는 노멀과 생성한 어두운 가죽 알베도를 함께 사용합니다. |
| [Worn Wood Table](https://polyhaven.com/a/wood_table_worn) | 과거 방패 빌더의 목재 알베도·노멀입니다. 기존 빌더 의존 자료로 보존하며, 현재 새 방패는 생성 아틀라스를 사용합니다. |
| [Rough Wood](https://polyhaven.com/a/rough_wood), Rob Tuytel | 과거 방패의 `FP_WornOak` 분기에 사용하는 폐광 알베도·OpenGL 노멀입니다. [보존 메타데이터](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_abandoned_mine/material_sources/rough_wood_metadata.json>)와 [소재 출처 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_abandoned_mine/material_sources/README.md>)을 따릅니다. 현재 `FP_ShieldOak`는 생성 아틀라스를 사용합니다. |

게임의 기존 장갑·보호대·소매에는 Codex ImageGen으로 생성한 [worn_charcoal_leather.png](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/ai/sword_shield/worn_charcoal_leather.png>)를 유지합니다. 생성 방식과 프롬프트는 [GENERATED_TEXTURE.md](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/GENERATED_TEXTURE.md>)에 있습니다. 이 생성 이미지에 위 외부 원본의 CC0 표시를 적용하지 않습니다. 기존 프로젝트 이미지 [concept_forged_steel.png](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/ai/materials/concept_forged_steel.png>)는 과거 검·방패 모델의 금속 재질 분기에 남아 있으며, 현재 새 검·방패의 `FP_Sword*`, `FP_Shield*` 금속 재질은 새 아틀라스를 사용합니다. 실제 재질 연결은 [sword_shield_arm_visual.gd](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/scripts/sword_shield_arm_visual.gd>)에서 수행합니다.

기존 손 제작 자료는 [asset-staging/sword_shield_first_person](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person>)에, 현재 검·방패 제작 자료는 [asset-staging/sword_shield_multiview](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview>)에 보존합니다. 현재 검·방패만 재생성하려면 다음 명령을 사용합니다. 새 빌더도 기존 공용 도우미를 읽으므로 `canonical_hand.blend`와 기존 용병 제작 폴더의 원본 텍스처를 함께 보존해야 합니다. `blender`는 설치한 Blender 실행 파일을 사용합니다.

```sh
blender --background --python "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/build_multiview_assets.py"
```

손까지 다시 만들어야 할 때는 아래 순서를 지킵니다. **기존 `build_assets.py`는 손뿐 아니라 과거 검·방패까지 네 GLB를 모두 내보내므로, 실행 뒤 새 무기 빌더를 마지막에 실행해야 현재 검·방패가 복원됩니다.**

1. 손 원형도 다시 만들 때만 [inspect_anatomy.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/inspect_anatomy.py>), [prepare_hand.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/prepare_hand.py>)를 순서대로 실행합니다.
2. 기존 [build_assets.py](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/build_assets.py>)로 손 모델을 만듭니다. 이 단계는 `sword_shield_first_person.blend`와 기존 `build_report.json`도 갱신합니다.
3. `build_multiview_assets.py`로 현재 검·방패 두 GLB를 다시 내보냅니다.

```sh
blender --background --python "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/build_assets.py"
blender --background --python "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_multiview/build_multiview_assets.py"
```

이 빌드 명령은 AI 참조 이미지·아틀라스·손 재질 이미지를 생성하지 않습니다. 생성 기록과 원본 이미지도 함께 보존해야 합니다.

GLB에는 이미지 사본을 넣지 않고 공유 재질을 게임에서 연결합니다. 손·장비의 근접 형태를 유지하도록 네 `.glb.import`의 자동 메시 단순화와 정점 압축을 끄고, 정적 장식은 관절별로 합쳐 그립니다. 과거 내장 이미지 사본은 제작 폴더의 `retired_embedded_textures/`에 보존합니다.

노출된 손가락에는 Codex ImageGen으로 생성한 [weathered_hand_skin.png](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/godot-game/assets/ai/sword_shield/weathered_hand_skin.png>)를 유지합니다. 생성 방식과 전체 프롬프트는 [GENERATED_SKIN.md](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/sword_shield_first_person/GENERATED_SKIN.md>)에 보존합니다. 이 생성 이미지에도 외부 원본의 CC0 표시를 적용하지 않습니다.
