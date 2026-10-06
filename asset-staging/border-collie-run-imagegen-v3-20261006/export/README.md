# 보더콜리 달리기 v3 / Border Collie run v3

다리 펴기·착지·모으기를 나타내는 개별 원본 PNG 16장입니다. 내장 imagegen으로 한 장씩 새로 제작합니다.
16 separate original PNGs show extension, landing and collection, generated one image at a time with built-in imagegen.

- `frames/Frame_001.png` … `frames/Frame_016.png`: 1536 × 1024 원본. 픽셀 수정·리사이즈·보간·합성 없음.
  Original 1536 × 1024 images; no pixel edits, resizing, interpolation or compositing.
- `index.html`: 한 번에 한 장만 표시합니다. 이전/다음, 슬라이더, 반복 재생, 12/16/24 fps 미리보기를 제공합니다. 기본은 24 fps입니다.
  Displays one image at a time, with navigation, slider, loop playback and 12/16/24 fps preview settings; the default is 24 fps.
- `manifest.json`: 파일 SHA-256, 원본 동일성, 실제 생성 프롬프트와 개별 검토 메모.
  File checksums, exact source-copy evidence, actual generated prompts and individual review notes.
- `prompts.json`, `generation/`: 제작 계획과 실제 호출 기록 / Art plan and actual per-image generation receipts.

`index.html`을 파일로 직접 열거나 정적 서버에서 열 수 있습니다. 같은 위치의 `frames` 폴더를 유지하세요.
Open index.html directly as a file or through a static server. Keep the sibling frames directory.

미리보기 fps는 재생 설정이며 실제 촬영 속도나 운동 측정값이 아닙니다. 각 PNG는 별도 생성한 2D 이미지입니다.
Preview fps is a playback setting, not a measured capture rate or motion measurement. Each PNG is a separately generated 2D image.

파일·해상도·체크섬 검증은 해부학이나 자연스러운 움직임의 자동 합격을 뜻하지 않습니다.
File, dimension and checksum verification does not automatically establish anatomical or temporal quality.
자세·접지·주기 위치는 제작 계획입니다. 실제 발 이동·머리·몸통·배경 연결 상태는 개별 검토 기록을 확인하세요.
Pose, contacts and cycle positions describe the art plan. Read individual review records for actual paw, head, body and background continuity.
