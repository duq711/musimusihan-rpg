# 실제 달리기 영상 프레임 추출 / Actual running-video frame extraction

2026-10-07 사용자 요청: https://youtu.be/CoL8Gtvxfl0 에서 개가 달리는 프레임을 한 장씩 추출.
User request: extract individual frames of the dog running in the linked video.

원본은 **Slow Motion Dog Run**, Lian M,2012-03-18 업로드입니다. 접근 가능한 최고 해상도640×360의 H.264 영상 스트림(format134)을 보존했습니다. 유튜브 영상은24fps이며 실제 고속 촬영 속도는 확인하지 않았습니다.
Source: **Slow Motion Dog Run**, Lian M, uploaded2012-03-18. Preserve the highest accessible resolution640×360 H.264 video stream(format134). YouTube playback is24fps; the original high-speed capture rate is unknown.

791개 원본 프레임 중 앞뒤 검은 구간을 제외한0기준8–723을 **716장 PNG**로 디코드했습니다. 시간은0.333333–30.125초입니다. 원본 페이드·모션 블러·배경은 포함되고, 보간·복제·AI 생성·해상도 확대는 없습니다. 각 프레임의 원본 순번·PTS·시간·SHA256은 manifest.json에 기록합니다.
Decode zero-based frames8–723 from791 original frames into **716 separate PNGs**, at source times0.333333–30.125s. Original fades, blur and backgrounds remain. No interpolation, duplication, AI generation or upscaling. Record source indices, PTS, timestamps and SHA256 in manifest.json.

## 산출물 / Artifacts

기본 경로 / Base: `asset-staging/dog-run-video-frames-CoL8Gtvxfl0-20261007/`

- `source/Slow-Motion-Dog-Run-CoL8Gtvxfl0.mp4`: 받은 원본 영상 스트림 / Downloaded source video stream.
- `source/metadata.json`: 출처·접근 형식 / Attribution and selected format, without signed media URLs.
- `export/frames/Frame_000001.png` … `Frame_000716.png`: 개별 원본 프레임 / Individual source frames.
- `export/dog-run-CoL8Gtvxfl0-716-frames.zip`:716장과 시간 기록 /716 images and source timing records.
- `export/index.html`, `export/manifest.json`: 한 장씩 보기·느린 반복·다운로드 / Individual viewer, slow loop and downloads.
- `extraction-summary.json`, `production-summary.json`: 디코드·파일·시각·브라우저 검증 결과 / Decode, file, visual and browser checks.

미리보기 / Preview: http://127.0.0.1:8794/

뷰어는29번 이미지(원본1.5초)에서 시작합니다. 처음·이전·다음·마지막·슬라이더·키보드 좌우를 지원하며 기본8fps는 검토용 재생 설정입니다. 모든 원본을 한 번에 메모리에 올리지 않습니다. 이번 결과는 참고 자료이며 기존 게임·AI 이미지·애니메이션을 수정하지 않습니다.
Start the viewer at image29(source1.5s). Navigate individually or loop at a review setting of8fps. Do not preload all source images. These are motion-reference materials; existing games, generated images and animations are unchanged.

## 검증과 한계 / Validation and limits

716/716 PNG 형식·RGB·640×360 확인, 원본 순번 연속·PTS 증가 확인, ZIP CRC 및716/716 해시 일치 확인. 완전히 같은 PNG는0장입니다(실루엣 차이나 자연스러움의 판정이 아님). 별도 검토자가29–37과1·716의11장을 개별로 확인했으며 펼침→하강→다리 접힘이 진행하고, 검토 범위에 빈 프레임·몸 잘림·비정상적인 늘어짐은 없었습니다. 인접 이미지 변화가 작은 구간, 검은 다리의 겹침, 모션 블러와 원본의 낮은 해상도는 남습니다.
Verify716/716 PNGs, RGB,640×360; contiguous source indices; increasing PTS; ZIP CRC and716/716 archive hashes. Zero exact duplicate PNGs is a file check, not a silhouette or motion-quality judgment. Independent visual review of11 frames found progression from extension to descent and gathering, with no empty frames, body cropping or abnormal stretching in that sample. Small adjacent changes, dark overlapping limbs, motion blur and limited resolution remain from the source.

브라우저에서 초기29→다음30, 마지막716의 원본640×360 로드,8fps 설정 재생 진행, 정지 후29 복귀를 확인했습니다. 실제 렌더 FPS를 측정한 검사는 아닙니다. 게임 통합은 없으므로 엔진 실행·빌드 검증은 하지 않습니다.
Browser checks confirm initial29→next30, native640×360 loading for last716, playback advance at the8fps setting and paused return to29. Actual rendered FPS was not measured. No engine run/build is needed because this does not integrate into a game.

원본이 새 게임 에셋용 배포 권리를 제공한다고 확인한 것은 아닙니다. 출처 링크와 다운로드 메타데이터를 보존했습니다. 로컬 전체 커밋과 GitHub의 텍스트 반영·LFS 업로드 상태는 구분하고, 최종 업로드·정리 상태는 로컬 publication-local-status.json에 남깁니다. 검토가 끝난 샘플 캡처·임시 도구 설치·전송 자료만 정리하며 원본 영상·716장·ZIP·재사용 도구는 보존합니다.
This does not establish distribution rights for a new game asset. Preserve attribution and source metadata. Distinguish the full local commit, GitHub text publication and LFS asset upload. Record final publication and cleanup in local publication-local-status.json. Remove completed sample captures, temporary dependency installation and publication files; preserve the source video,716 PNGs, ZIP and reusable tools.
