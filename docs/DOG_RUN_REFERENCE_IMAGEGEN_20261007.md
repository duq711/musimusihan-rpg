# 실제 영상 자세를 참고한 개 달리기 / Dog run based on actual video poses

사용자가 제공한 716장 영상 프레임을 참고하여, 다리 굽힘·발 위치·겹침 순서를 우선한 새 개별 PNG16장을 제작했습니다. 이전 3D Labrador와 보더콜리 이미지 시퀀스는 보존했습니다.

Created16 new individual PNGs from the user's716 video frames, prioritizing leg bends, paw placement and visible overlap order. Preserved the previous3D Labrador and Border Collie image sequences.

## 제작 기준 / Production basis

- 원본: [Slow Motion Dog Run](https://youtu.be/CoL8Gtvxfl0), 이미 추출·보존된 로컬 영상 및 프레임 사용. 다시 다운로드하지 않습니다. / Use the previously extracted and preserved local video frames; no new download.
- 선택: 원본81,85,88,92,95,99,102,106,109,113,116,120,123,127,130,134. 137은 주기 경계 비교용입니다. / Sixteen references from a roughly56-frame cycle;137 is a boundary comparison.
- 제작: 내장 `image_gen.imagegen`, 각 프레임당 별도 호출. 실제 해당 영상 PNG가 포즈 기준이며, 다리가 없는 초상은 검은 개의 얼굴·털·재질에만 사용합니다. / One built-in imagegen call per frame. The corresponding actual PNG controls pose; a leg-free portrait supplies appearance only.
- 외형: 긴 검은 털, 왼쪽 정측면, 밝은 회색 배경. 초기16장에서는 이전 생성 전신 포즈를 입력하지 않았습니다. 13번의 위치 오류 수정에는 원본123을 다리 기준으로 유지하고12번을 카메라·머리·몸통 고정용으로 추가했습니다. / Long black coat, left-facing side view, pale gray background. Initial frames used no prior generated full-body pose. The targeted13revision retained source123 as the leg authority and added12 only to stabilize camera/head/torso.
- 원본 생성 PNG를 바이트 그대로 보존하며 픽셀 편집·리사이즈·보간을 하지 않습니다. / Preserve exact generated output bytes without pixel edits, resizing or interpolation.

## 산출물 / Artifacts

기준 경로 / Root: `asset-staging/dog-run-reference-imagegen-20261007/`

- `export/frames/Frame_001.png`~`Frame_016.png`: 개별 생성 프레임 / Individual generated frames.
- `export/index.html`: 원본과 결과를 나란히 비교하고 한 장씩 이동·재생 / Side-by-side reference comparison and frame playback.
- `export/dog-run-actual-reference-16-frames-20261007.zip`: PNG·원본 자세·뷰어·manifest / PNGs, pose references, viewer and manifest.
- `prompts.json`, `generation/frameNNN.json`: 실제 프롬프트·참조·기본 원본 경로·선택 해시 / Exact prompts, references, default source paths and selected hashes.
- `visual-review.json`, `validation-summary.json`: 육안 비교와 파일 검증 결과 / Visual comparison and file validation.
- `export/viewer-preview.jpg`: 최종 사용자용 비교 화면 / Final user-facing comparison preview.
- 재사용 도구 / Reusable tools: `tools/imagegen/package_dog_reference_frames.py`, `tools/imagegen/dog_reference_frames_gallery.html`.

## 시간과 한계 / Timing and limits

원본 영상은 이미 슬로 모션이며 디코딩 FPS는24입니다. 실제 촬영 FPS는 확인되지 않았습니다. 뷰어의 기본16fps는 재생 미리보기 설정이고 원본 시간 옵션은 각3~4프레임 간격을 따릅니다.

The source is already slow motion with a decoded rate of24fps; original capture FPS is unknown. The default16fps is a preview setting. Source timing follows the selected3–4-frame intervals.

검은 털과 원본 블러 때문에 일부 다리의 해부학적 좌우와 정확한 접지는 확정하기 어렵습니다. 생성 도구의 이미지별 위치·길이 변화는 실제 프레임과 비교해 기록하며, 해시 차이를 포즈 정확도나 자연스러운 연속성의 증거로 사용하지 않습니다.

Dark fur and source blur obscure anatomical left/right assignments and precise ground contact. Record differences of placement and limb length through actual-image comparison. Distinct hashes do not prove pose accuracy or natural continuity.

## 완료 검증·공유 / Completion, validation and publication

PNG16장 모두1672×941이며 생성 기본 원본과 바이트·해시가 일치합니다. 실제 자세 참조16장의 원본 동일성, ZIP35개 멤버의 바이트 동일성과 CRC도 확인했습니다. 생성20회는 선택16장·외형 초상1장·13번의 거부/교체 후보3장입니다. ZIP는27,700,946바이트입니다.

All16 PNGs are1672×941 and exactly match their built-in default sources. Verified16 actual pose references and byte identity/CRC for35 ZIP members. Twenty generation calls produced16 selected frames,1 appearance portrait and3 rejected/replaced frame13candidates. The ZIP is27,700,946bytes.

전체16장과 대응 원본16장, 인접16쌍을 육안 비교했습니다. 다리의 큰 단계는 순서대로 대응하며 명백한 추가 다리·역관절은 발견하지 못했습니다. 13번 수정으로12→13의 위치 이동을 줄였지만2→3,7→8,16→1 등의 머리 이동, 일부 몸 크기·발 높이 오차가 남습니다. 정밀 관절 좌표·접지 고정·매끄러운 루프 일치는 확인되지 않았습니다.

Compared16 generated frames,16 matching sources and16 adjacent pairs visually. Main leg phases follow the source, with no confirmed extra limb or reversed joint. Revised13 reduces12→13registration drift, but head shifts at2→3,7→8 and16→1, plus some scale/paw-height differences remain. Exact joint registration, fixed contact and a seamless loop are unverified.

로컬 비교 뷰어에서 전체 이미지 준비,1→2 이동, 마지막16번,16→1 재생 전환, 정지 및 생성1672×941/원본640×360 디코딩 크기를 확인했습니다. 실제 재생 FPS는 측정하지 않았습니다. 최신 비교 뷰어는 `http://127.0.0.1:8795/`입니다.

Verified preload, next/last navigation,16→1playback, pause and decoded dimensions1672×941/640×360 in the local viewer. Playback FPS was not measured. Latest comparison viewer: `http://127.0.0.1:8795/`.

현재 작업 파일만 별도 Git index로 커밋합니다. 로컬 Git/LFS 인증이 막히면 완성된 PNG·ZIP 및 커밋을 보존하고 원격 텍스트 반영과 바이너리 업로드 상태를 구분합니다. 공유·정리 결과의 실제 상태는 로컬 `publication-local-status.json`에 기록합니다.

Commit only this task through a separate Git index. If local Git/LFS authentication blocks upload, preserve PNGs, ZIP and commits and distinguish remote text publication from binary upload. Record actual publication/cleanup state in local `publication-local-status.json`.

이번 로컬 `git push`는 HTTPS Username 인증을 읽을 수 없어 종료코드128로 실패했습니다. PNG·ZIP·참고 이미지의 LFS 업로드는 완료되지 않았으며, 연결된 GitHub 도구의 텍스트 반영 경로로 문서·프롬프트·제작·검증 기록을 공유합니다. 원격에 있는 텍스트 링크가 완성 이미지 다운로드를 의미하지 않습니다.

This local `git push` failed with exit128 because HTTPS Username authentication was unavailable. PNG, ZIP and reference-image LFS uploads are incomplete. Share documents, prompts, generation receipts and validation records through the connected GitHub text tool. A remote text link does not imply downloadable image assets.
