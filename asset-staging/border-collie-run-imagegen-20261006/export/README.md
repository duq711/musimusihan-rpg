# 보더 콜리 달리기 개별 원본 / Border Collie original run frames

새 검정·흰색 보더 콜리를 내장 image_gen으로 한 프레임씩 생성한 원본 PNG 42장입니다.
42 original PNGs of a newly generated black-and-white Border Collie, each created by a separate built-in image_gen call.

- `frames/Frame_001.png` … `frames/Frame_042.png`: 1536 × 1024 개별 원본. 픽셀 수정·자르기·리사이즈·보간·합성 없음.
  Individual 1536 × 1024 originals, with no pixel edits, cropping, resizing, interpolation or compositing.
- `manifest.json`: 프레임 순서, SHA-256, 크기, 제작 시점과 개별 검수 한계.
  Frame order, SHA-256 checksums, dimensions, intended art timing and individual review limitations.
- `prompts.json`: 프레임별 자세 제작 지시 / Per-frame pose briefs.
- `generation/`: 실제 사용한 전체 프롬프트·입력 참조·원본 선택 경로와 개별 검수 기록.
  Actual full prompts, references, selected source paths and per-frame review records.

명목상 60 fps·0.70초는 제작 순서를 나타냅니다. 측정된 운동학·물리 시뮬레이션·완성된 3D 리그나 게임 애니메이션이 아닙니다.
Nominal 60 fps and 0.70 seconds describe an art schedule, not measured kinematics, physical simulation, a completed 3D rig or game animation.

접지와 자세는 요청한 제작 계획이며 생성 이미지의 정확한 접지·관절·프레임 간 연속성을 보증하지 않습니다. 각 프레임의 검수 메모는 manifest와 generation 기록에서 확인할 수 있습니다.
Contacts and poses are art-direction intent. Exact contacts, joint positions and temporal continuity are not guaranteed; see the per-frame review notes in the manifest and generation records.

프로젝트의 `export/index.html` 갤러리는 한 번에 한 장만 표시합니다. 파일로 직접 열거나 정적 서버에서 사용할 수 있으며, 현재 PNG와 이 전체 ZIP을 내려받을 수 있습니다. ZIP에는 원본 프레임과 제작 기록이 포함됩니다.
The project's `export/index.html` gallery displays one image at a time and works directly from a file or a static server. It offers the current PNG and this complete ZIP. This ZIP contains original frames and production records.

기존 레브라도 모델·게임 소스·최신 실행본은 변경하지 않았습니다.
The former Labrador model, game source and latest playable app remain preserved.
