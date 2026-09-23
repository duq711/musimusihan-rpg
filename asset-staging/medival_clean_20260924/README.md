# Medival 의상 원본 재적용 / Clean Medival outfit

사용자가 다시 첨부한 `Medival.blend`, `Medival.obj`, `Medival.fbx`, `Medival.mtl`, `Textures.rar`는 이미 보존된 `asset-staging/medival_cloth_20260923/source/`의 5개 파일과 SHA-256이 모두 같습니다. 원본은 그대로 두고, 이 디렉터리에 새 의상을 만들었습니다. 정확한 해시는 `structure_report.json`에 있습니다.

The five newly supplied files match the previously preserved originals byte for byte. The originals remain untouched; this directory contains a fresh derivative.

## 결과 / Output

- `Medival_Clean.glb`: 원본 상의·바지·벨트·낮은 신발 두 짝의 5개 메시. 상의를 자르거나 헴을 별도 패널로 분리하지 않았으며, 메시의 정점·면·UV를 줄이거나 삭제하지 않았습니다.
- `Medival_Clean.blend`: 위 모델의 편집용 파일. 사용하는 텍스처 6개를 파일 안에 패킹했습니다.
- `build.py`: Mac Blender에서 원본을 다시 만드는 스크립트. 원본 `Textures.rar`를 풀어 텍스처를 연결합니다.
- `preview_front.png`, `preview_side.png`, `preview_back.png`, `preview_three_quarter.png`: 네 방향 시각 검증 결과.
- `structure_report.json`: 원본 해시, 메시 정점·면 수, 높이와 재질 기록.

The original garment topology and silhouette are intact. Only the source object transforms are baked into the vertices so the exported glTF has metre-scale, Y-up coordinates. The original material used a 1-metre height displacement and a shared opacity map, which caused severe surface noise and see-through gaps. The new five materials are double-sided and opaque; displacement is removed and normal-map strength is reduced to 0.18 while retaining the original colour, roughness, metallic and normal textures.

The source has no armature or animation. The visible separation between trouser cuffs and low shoes is present in the supplied model and reference image. Any cloth motion in the game must be implemented separately without cutting this original tunic.

## 검증 / Validation

Blender 5.2.1 LTS 백그라운드 실행으로 GLB 생성 및 정면·측면·후면·3/4 렌더를 완료했습니다. GLB JSON 검사 결과 노드는 `Medival_ShirtUpper`, `Medival_Pants`, `Medival_Belt`, `Medival_Shoe_L`, `Medival_Shoe_R`이고, 다섯 재질의 `alphaMode`는 모두 `OPAQUE`입니다. 전체 높이는 약 1.578 m입니다.

Blender 5.2.1 LTS generated the GLB and four rendered previews. The glTF has five garment nodes, five OPAQUE materials, and a total height of about 1.578 m.
