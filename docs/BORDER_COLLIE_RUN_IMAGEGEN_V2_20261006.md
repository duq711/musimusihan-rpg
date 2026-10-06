# 보더콜리 달리기 이미지 v2 / Border Collie run images v2

사용자 요청: 기존 래브라도 모델을 쓰지 않고 내장 이미지 생성으로 별도 달리기 프레임을 다시 제작합니다. 한 장짜리 모음 이미지는 만들지 않습니다.

User request: Regenerate separate running frames with built-in image generation, without using the Labrador model or a montage.

## 제작 방법 / Production

- 경로: `asset-staging/border-collie-run-imagegen-v2-20261006/`.
- 새로운 사실적 보더콜리 외형을 001번에서 정하고, 42개의 자세 가이드와 이전·다음 사진을 참조해 각 PNG를 개별 생성합니다.
- 뒷발 지지 → 신전 공중기 → 앞발 순차 착지 → 모은 공중기로 구성합니다. 접지 뒤 가슴·골반의 눌림, 허리 굽힘·펴짐, 발 회수 경로를 추가했습니다.
- 최종 PNG는 생성 도구의 기본 원본을 바이트 그대로 복사합니다. 사진 픽셀의 합성·보간·변형이나 Blender 렌더는 하지 않습니다. SVG/JSON 가이드는 별도 제작 제어 자료입니다.
- 기존 v1 42장, 기본 생성 원본, 교체 전 사진의 생성 기록은 보존합니다. 게임 코드·모델은 변경하지 않습니다.

The new appearance is anchored at frame001. Forty-two authored pose controls plus adjacent photographs direct individual image-generation calls. The cycle includes hind support, extended flight, sequential fore landing and gathered flight. Final image bytes are copied directly from the built-in output; no pixel interpolation, compositing or Blender rendering is used. Earlier v1 art and generation originals remain preserved.

## 검증 범위와 한계 / Validation and limits

파일 수·1536×1024 크기·원본 동일 SHA·ZIP 무결성과 실제 사진의 관절 형태를 따로 확인합니다. 수학적으로 닫힌 가이드 경로가 실제 생성 사진의 연속성 합격을 의미하지 않습니다. 실제 프롬프트·후보·교체 기록은 `generation/`, 최종 파일 검증은 `export/manifest.json`에 남깁니다.

프레임별 좌표 제어는 근사치입니다. 추가 다리·뒤틀림 후보는 재생성하고, 다리의 앞뒤 바뀜과 큰 머리 이동도 고쳤습니다. 일부 이륙·접지 구간의 발 이동량, 털·배경 변화와 후반 동작 정체가 남으므로 **완전히 자연스러운 연속 달리기로 검증된 자료는 아닙니다.** 게임용 3D 리그·모션 캡처도 아닙니다.

File integrity, image anatomy and temporal continuity are distinct checks. The authored guide's mathematical closure is not a pass for generated-image continuity. Coordinate following is approximate. Some paw spacing, fur/background changes and late motion holds remain; these images are **not validated as a fully natural continuous gallop**, a game-ready3D rig or motion capture.

## 참고 / References

[원본 업로더 Brixiv의 측면 슬로모션 / Brixiv side-view slow-motion](https://www.pexels.com/video/side-view-of-dog-running-in-slow-motion-9898378/)을 직접 관찰해 몸통 반응과 회수 경로를 정했습니다. 잔디에 가려진 발의 정확한 접지 시점·좌우 선행 다리는 측정하지 않았습니다.

접지 순서와 공중 자세는 [Walter & Carrier2007](https://journals.biologists.com/jeb/article/210/2/208/17106/Ground-forces-applied-by-galloping-dogs), [University of Minnesota](https://vanat.ahc.umn.edu/gaits/rotGallop.html)를 참고했습니다. 42개의 위상과 12/24/60fps는 제작·미리보기 설정이며 실제 영상에서 측정한 속도가 아닙니다. 사용자의 YouTube 링크는 읽기 오류로 직접 관찰하지 못했으므로 해당 영상과 동일하다고 주장하지 않습니다.

The references informed qualitative gait order and body response only. Forty-two phase slots and preview rates are authoring/playback settings, not measured capture timing. The user's YouTube link could not be observed successfully.

## 산출물·공유 / Outputs and sharing

- 개별 사진: `export/frames/Frame_001.png` … `Frame_042.png`.
- 한 장씩 보기·반복 미리보기: `export/index.html`.
- 원본42장 ZIP: `export/border-collie-run-v2-individual-frames-20261006.zip`.
- 프롬프트: `prompts.json` + 각 `generation/frameNNN.json`.
- 가이드 원본: `guides/`; 도구: `tools/imagegen/*v2*`, `archive_border_collie_revision.py`.
- 최신 확인 상태·용량·남은 한계: `production-summary.json`.

공유 브랜치 `codex/labrador-pet-20261005`의 이전 로컬 바이너리 커밋을 보존하고 이번 작업만 별도 인덱스로 커밋합니다. PNG와ZIP은 프로젝트 Git LFS 규칙을 따릅니다. 로컬 Git/LFS 인증 문제는 이전 작업에서 확인되어 전체 바이너리 업로드 상태와 연결 도구를 통한 텍스트 공개 상태를 구분합니다. 최종 원격 상태는 별도 publication 기록에서 확인합니다.

Preserve the earlier local binary commit on the task branch and commit only this unit through an isolated index. PNG/ZIP follow project LFS rules. Local Git/LFS authentication and connector text publication are separate; do not claim full publication without verified binary upload.
