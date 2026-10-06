# 새 보더콜리 달리기 개별 이미지 / New Border Collie running images

2026-10-06 사용자 요청: 기존 레브라도 모델 대신 새 개를 내장 이미지 생성 기능으로 만들고, 달리는 자세를 한 장씩 개별 제작한다.
User request: create a new dog with built-in image generation and make each running pose a separate image.

## 완료 결과 / Deliverables

- 새 검정·흰색 보더콜리의 독립 PNG 42장. 모든 프레임은 별도 내장 image_gen 호출로 생성했다.
  Forty-two separate PNGs of a new black-and-white Border Collie, each produced by its own built-in image_gen call.
- 한 번에 원본 한 장만 표시하는 갤러리: `asset-staging/border-collie-run-imagegen-20261006/export/index.html`.
  The gallery displays one original frame at a time, with previous/next, slider, keyboard navigation and downloads.
- 원본: `export/frames/Frame_001.png` … `Frame_042.png`, 모두 1536 × 1024.
- ZIP: `export/border-collie-run-original-frames-20261006.zip`, 78,326,201 bytes. 원본 42장과 프롬프트·생성 기록을 함께 보관한다.
  The ZIP preserves 42 original images and production records.
- 프롬프트: `prompts.json`; 실제 사용 기록: `generation/frame001.json` … `frame042.json`.
- 재사용 도구: `tools/imagegen/border_collie_run_prompts.py`, `archive_border_collie_frame.py`, `package_border_collie_frames.py`.
  These prepare text, archive exact output bytes, and package originals; they do not generate or edit image pixels.

이미지는 최초 새 개 이미지로 개체·털 무늬·카메라를 고정하고 인접 프레임을 자세 참고로 사용했다. 모은 공중 자세 → 뒷발 지지·추진 → 길게 뻗은 공중 자세 → 앞발 지지 → 다시 모으는 순서다. 전체가 원본 바이트 복사이며 자르기·리사이즈·보간·합성 시트를 사용하지 않았다.
The seed anchors identity, markings and camera; adjacent generated images guide poses. The cycle covers collection, hind support and propulsion, extended flight, fore support and collection. All selected images are exact copies of built-in output files, without cropping, resizing, interpolation or contact sheets.

## 확인과 한계 / Validation and limits

원본 일치, SHA-256, 1536 × 1024 치수, 서로 다른 해시, ZIP 내부 이미지 일치가 각각 42/42 통과했다. ZIP CRC도 통과했다. 갤러리의 이동·슬라이더·키보드·다운로드 제어를 확인했고, 실제 브라우저에서 다음 프레임과 18번 선택을 확인했다. 1280 × 720 보기에서 전체 개와 제어가 함께 보인다.
Exact source copies, SHA-256, dimensions, unique hashes and ZIP image equality each pass 42/42, along with ZIP CRC. Gallery controls were checked and next-frame / frame18 selection verified in the browser; the whole dog and controls fit at 1280 × 720.

각 생성자의 이미지 검수 기록과 독립 검토는 별도 JSON에 보관한다. 4번의 뒷발이 뒤로 튀는 결과는 내장 imagegen으로 다시 생성했다. 생성 이미지이므로 발 겹침, 접지 각도와 프레임 사이 변화량은 일부 근사치다. 명목상 60fps·0.70초는 제작 순서이며 매끄러운 60fps 영상·측정된 운동학·게임용 3D 리그 완성으로 보고하지 않는다.
Creator reviews and independent inspection are retained as JSON. Frame4 was regenerated to improve a hindpaw discontinuity. Some paw overlap, contact geometry and inter-frame displacement remain approximate. Nominal 60fps / 0.70s describes an art schedule, not a verified smooth video, measured kinematics or completed game-ready 3D rig.

## 보존과 공유 / Preservation and sharing

선택 PNG 42장, ZIP, 내장 생성 도구의 기본 원본 및 보정 이력은 최종 제작 자료로 보존한다. 기존 게임·레브라도 모델·최신 플레이용 앱은 이번 요청의 변경 대상이 아니다.
Preserve the selected PNGs, ZIP, built-in default originals and correction history as production assets.

PNG와 ZIP은 프로젝트 규칙에 따라 Git LFS 대상이다. 현재 이 Mac의 GitHub CLI 로그인과 로컬 Git 자격 증명이 없어 바이너리 원격 업로드는 막혀 있다. 연결된 GitHub 도구로 텍스트 제작 기록은 별도로 공유할 수 있지만 이미지 전체 동기화와 구분한다. 모든 에셋은 로컬 작업 커밋에 포함하고 인증 복구 후 LFS와 커밋을 함께 업로드해야 한다.
PNG and ZIP files use Git LFS. Missing local GitHub/Git credentials currently block binary upload. Connected GitHub tools can publish textual production records separately; this is distinct from full image synchronization. Include all assets in a local task commit, then upload LFS objects and that commit after authentication is restored.

정리는 현재 작업에서 생긴 임시 전달 파일·별도 인덱스만 대상으로 한다. 원본 이미지와 사용자 요청 ZIP은 검증 임시 파일이 아니다.
Cleanup covers only this task's temporary transfer files and isolated index, never the requested images or ZIP.

