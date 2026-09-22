# T자 팔 비율 수정 / T-pose arm anatomy

## 요청과 범위 / Request and scope

첨부된 T자 인체 참조를 기준으로 팔꿈치가 부풀고 겨드랑이가 날개처럼 처지는 검토 자세를 수정했습니다. 기존 얼굴·의상·하체와 승인된 기본 자세를 유지합니다. 보정은 `tools/player-model-viewer/pose.js` 및 `pose-profile.js`에 있고, 정적 검토용 GLB와 Blender 파일을 별도로 저장합니다. 게임 GLB와 애니메이션 리그의 변경은 없습니다.

Correct the rejected T-pose arm silhouette using the supplied anatomical reference. Keep the existing face, outfit, lower body and approved resting asset. The correction runs in the viewer; separate static GLB/Blender review assets are included. It is not a production animation rig.

## 수정 / Correction

- 위팔에서 팔꿈치로 가늘어지고 전완 근위부에서 손목으로 줄어드는 단면을 양측에 적용했습니다.
- 들린 팔의 축과 어깨 지붕을 쇄골 높이에 맞추고, 연결부의 깊은 대각 홈을 완화했습니다.
- 겨드랑이 경계는 연결되어 있었지만 인접 소매 면이 그 아래로 약33mm 접혀 있었습니다. 실제 접합선 위쪽은 유지하고 낮은 접힘만 압축했습니다.
- 공통 정점의 이웃 관계를 함께 사용해 접합부를 다듬고 최종 표면 법선을 계산했습니다. UV·삼각형 인덱스·재질·텍스처는 보존합니다.

English: Restore upper-arm/elbow/forearm taper, raised shoulder height and a soft clavicle transition. Compress the low sleeve pocket beside its intact attachment and relax the shared surface. Preserve UVs, triangle topology, materials and textures.

## 검증 / Validation

`node tools/player-model-viewer/pose.test.mjs` — PASS, actual production GLB:

- 실제 삼각형 단면 높이: 위팔99.0mm, 팔꿈치64.0mm, 전완 근위부81.0mm, 원위부58.1mm(좌우 동일).
- 안쪽 접힘은 실제 공통 경계 아래로 좌3.3mm/우3.2mm 이내.
- 공유 경계765쌍, 최대 위치 차이0.0000mm(표시 정밀도).
- 팔의 길이 방향 위치, 변형값 유효성, 양의 변형장 Jacobian, 정확한 원본 버퍼 복원 및 반복 전환 검사 통과.
- 거절된 이전 `f7ad3a2` 변형은 같은 단면 검사54개와 안쪽 접힘 검사에서 실패함을 확인했습니다. 통과 수치만으로 외관이 자연스럽다고 판단하지 않습니다.
- Mac Blender의 실제 Cycles 렌더: 정면 원단, 정면·사선·후면 클레이 총4장. Codex 360° 뷰어에서도 확대·회전·자세 전환을 검토합니다.
- 변경은 검토 도구와 별도 제작 자료에 한정됩니다. 게임 코드·제작 원본 GLB가 불변이므로 Godot 전체 검사는 재실행하지 않았습니다.

English: Actual triangle sections and shared seams pass independent regression checks; the rejected pose fails them. Four real Mac Cycles renders and the interactive viewer are used for visual review. Godot was not rerun because the game asset and gameplay code are unchanged. These measurements describe the current clothed reference fit, not exact photo identity.

## 산출물 / Artifacts

- `gravebound_player_tpose.glb`: 뷰어와 같은 보정을 구운 별도 모델 / baked static review model.
- `Gravebound_Tpose_Review.blend`: 텍스처를 포함한 Mac Blender 검토 원본 / textured Blender review source.
- `export_review.mjs`, `render_review.py`: 재생성 스크립트 / reproducible export and render.
- `renders/tpose_front.png`, `renders/upper_{front,oblique,rear}_clay.png`: 실제 렌더 / actual renders.
- Live viewer: http://127.0.0.1:8768/?pose=t

Source GLB SHA-256 (unchanged): `e54f38efcba95a849eccbe958a6ab059a647de171101ab15cf851ee2ae61532c`

T-pose GLB SHA-256: `c8e416edc86b8275cc1697291bba252772338131207972951c9a6b3471205c32`
