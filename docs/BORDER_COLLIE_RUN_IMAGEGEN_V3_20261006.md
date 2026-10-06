# 보더콜리 개별 달리기 이미지 v3 / Border Collie individual run images v3

2026-10-06 사용자 수정 요청: 이전 v2의1–9장이 비슷하게 보이고 달리기가 어색하므로, 각 장에서 실제 자세 변화가 보여야 합니다.
User correction: v2 frames1–9 appeared too similar, and the run felt unnatural; each image must show a real pose change.

이번 제작은 한 주기를16장으로 다시 구성합니다. 각 이미지는 내장 imagegen에서 별도 호출하며, 기존 v1/v2와 기본 생성 원본을 보존합니다. PNG의 픽셀 수정·자르기·크기 변경·보간·합성은 하지 않습니다.
This version rebuilds one cycle as16 separate built-in imagegen calls, preserving v1/v2 and default originals. Selected PNGs are not edited, cropped, resized, interpolated or composited.

## 제작 변경 / Method changes

- 직전 전신 사진을 조금씩 수정하는 방식 대신, 각 단계의 전신 자세 가이드를 첫 참조로 사용합니다. 별도로 생성한 얼굴·가슴 초상에는 다리가 없어, 외형 참조가 직전 다리 포즈까지 복사하는 영향을 줄입니다.
  Use an independent whole-body pose guide first and a leg-free face/chest portrait for appearance, reducing inheritance of a prior full-body pose.
- 앞다리 시작점과 팔꿈치 연결을 다시 그려, 기존 가이드의 바닥 근처 직각 앞팔을 줄였습니다. 몸통이 근위 관절을 가리고, 뒷발은 모으기·전진·하강을 진행합니다.
  Redraw forelimb roots and elbows, occlude proximal joints with torso volume, and advance hind limbs through gathering, forward recovery and descent.
- 각 장의 접지·공중 상태, 실제 실루엣 차이와 인접 이미지 연결은 별도로 검토합니다. 서로 다른 파일 해시는 자세 변화의 증거로 사용하지 않습니다.
  Review actual contact/airborne state, silhouette changes and adjacent-image continuity separately; distinct file hashes do not prove distinct poses.

001은 새 가이드와 초상 생성 이전의 최대 확장 후보이며, 실제 호출에서는 이전018 가이드와 이전 전신 외형 참조를 사용했습니다. 008은 독립 생성 후 같은 자세에서 가려진 먼 발만 내장 imagegen으로 드러냈으며, 이전 참조의 해시·기본 생성 원본도 보존했습니다. 실제 참조와 수정된 프롬프트는 `generation/frameNNN.json`이 우선합니다. 가이드의 좌표·관절 계산·0.7초 주기는 제작 제어값이며 실제 촬영·모션캡처 측정이 아닙니다.
Frame001 predates the new guides/portrait and actually used the prior018 guide plus an older full-body appearance reference. Frame008 received a same-pose built-in visibility edit after independent generation, preserving the prior reference hash/default source. Per-image generation receipts are authoritative. Guide coordinates, link calculations and nominal0.7s cycle are art controls, not capture or mocap measurements.

## 산출물 / Artifacts

기본 경로 / Base: `asset-staging/border-collie-run-imagegen-v3-20261006/`

- `export/frames/Frame_001.png` … `Frame_016.png`: 선택한1536×1024 원본 PNG16장 /16 selected original PNGs.
- `export/index.html`: 개별 보기·이전/다음·슬라이더·반복 재생. 기본24fps, 느린 검토12/16fps / Individual viewer with navigation, slider and loop playback.
- `export/border-collie-run-v3-16-frames-20261006.zip`:16개 원본과 실제 프롬프트 기록 / Original frames and generation receipts.
- `references/dog-appearance-portrait.png`, `generation/appearance-portrait.json`: 내장 imagegen 초상과 출처 / Built-in appearance portrait and provenance.
- `guides/`, `prompts.json`, `generation/`: 제작 제어 자료와 실제 생성 기록 / Art controls and actual generation records.
- `production-summary.json`: 최종 검사 수·품질 한계·정리 결과 / Final checks, quality limits and cleanup results.

로컬 미리보기 / Local preview: http://127.0.0.1:8793/

## 검증 범위 / Validation scope

실제16장을 개별로 보고 마지막→첫 장을 포함한16개 인접 쌍에서 자세 변화가 있음을 확인했습니다. 별도 검토자도 첫9장·인접8쌍에서 같은 실루엣 반복0쌍을 확인했습니다. 원본 바이트·SHA·1536×1024·ZIP 안 원본 검사16/16과 ZIP CRC를 통과했습니다. 003→004→005 머리/가슴 높이, 009→010 앞발 전진, 010→012 머리 높이와 털 차이는 남습니다. 016은 앞발 쌍이 일부 겹칩니다. **자세 구분은 확인했지만 완전히 자연스러운 연속 달리기 합격은 아닙니다.**
All16 selected images were individually inspected, with pose changes in16 adjacent pairs including wrap. An independent reviewer found zero repeated silhouettes across the first9 images/eight pairs. Source bytes, SHA,1536×1024 dimensions and archived PNGs passed16/16 checks plus ZIP CRC. Head/chest jumps around004, forepaw advance009→010, head/fur variation010→012 and overlapping forepaws in016 remain. **Pose variety is verified; fully natural continuous running is not.**

참고한 질적 동작 순서 / Qualitative gait references: [Brixiv side-view slow-motion dog run](https://www.pexels.com/video/side-view-of-dog-running-in-slow-motion-9898378/), [UMN rotary gallop](https://vanat.ahc.umn.edu/gaits/rotGallop.html), [Walter & Carrier2007](https://journals.biologists.com/jeb/article/210/2/208/17106/Ground-forces-applied-by-galloping-dogs). 이전에 실제 확인한 자료이며16장에 정확히 추적·측정한 것이 아닙니다. 사용자의 YouTube Shorts는 접근 실패로 본 영상이라고 보고하지 않습니다.
Previously inspected references inform phase order qualitatively, not exact16-frame tracking. The user's YouTube Short could not be accessed and is not claimed as watched.

GitHub의 텍스트 반영과 PNG/ZIP의 LFS 업로드를 구분합니다. 로컬 Git 인증이 없는 경우 원본·로컬 커밋을 보존하고, 원격 에셋 업로드를 완료했다고 보고하지 않습니다.
Distinguish GitHub text publication from PNG/ZIP LFS upload. Preserve originals/local commits when local Git authentication blocks upload, and do not report full asset publication without verification.
