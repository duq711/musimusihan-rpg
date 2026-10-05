# 래브라도 질주 수정 / Labrador gallop correction

사용자는 2026-10-06 이전 Run이 빠른 걷기처럼 보이고 다리를 충분히 뻗지 않는다고 지적했습니다. 기존 수치 검사는 파일·루프·접지의 안정성을 확인했지만 질주 실루엣의 자연스러움을 충분히 평가하지 못했습니다. 같은 래브라도의 Run을 별도 제작본에서 다시 만들며 Walk·쓰다듬기·원본 모델은 보존합니다.

On 2026-10-06 the user rejected the previous Run because it looked like accelerated walking with too little limb extension. Earlier numerical checks established file/loop/contact stability but did not adequately assess the gallop silhouette. Run is rebuilt in a separate production while preserving the same Labrador, Walk, petting and acquired source.

## 인수 기준 / Acceptance criteria

실제 피부의 옆모습에서 앞다리의 큰 전방 뻗기, 뒷다리의 뒤로 밀어내기, 배 아래로 모으는 회수, 짧은 공중 구간, 어깨·골반·척추의 참여를 확인합니다. 뻗은 한 자세를 계속 유지하거나 걷기의 시간만 줄이는 방식은 인수 기준을 충족하지 않습니다. 다리 관절 방향·발과 몸의 연결·순환 경계도 실제 피부와 동영상으로 확인합니다.

Actual side-view skin must show substantial forward forelimb reach, rear hindlimb drive, collected recovery under the abdomen, suspension and shoulder/hip/spine participation. Holding one extended pose or merely accelerating Walk does not satisfy these criteria. Anatomical joint direction, continuous limb/skin attachment and loop transitions are assessed on the rendered dog and video.

사용자의 사진은 한 순간의 자세 기준이며 시간 정보가 있는 모션 캡처로 취급하지 않습니다. 보조 참고는 [Muybridge의 개 질주 연속 촬영](https://www.nga.gov/artworks/167096-plate-number-707-dread-galloping)과 [개의 비대칭 질주 접촉 연구](https://arxiv.org/abs/0809.2415)입니다. 기존 Lei Han 외 CC BY 4.0 캡처는 `asset-staging/labrador-pet-20261005/source/`에 보존합니다. 실제 사용한 구간과 새로 제작한 범위는 새 제작 요약에 구분합니다.

The user image is a pose reference, not timed motion capture. Supplemental references are Muybridge's photographic sequence and the primary study of asymmetric canine gallop contacts linked above. Preserved CC BY 4.0 capture, selected intervals and newly authored fitting are distinguished in the production receipt. Redistribution rights to the user image are not inferred; the image remains local.

## 산출물과 보기 / Artifacts and viewing

새 작업 폴더 / New task directory: `asset-staging/labrador-gallop-20261006/`.

- `reference/user_running_dog.png`: 로컬 보존한 사용자 기준 사진 / Preserved local user reference.
- `production/LabradorPet_Gallop.blend`: 별도 질주 제작본 / Separate gallop production.
- `export/LabradorPet_Gallop.glb`, `export/gallop-manifest.json`: 기존 care·Walk와 수정 Run의 미리보기 / Combined preview preserving care/Walk with corrected Run.
- `export/LabradorPet_Gallop.mp4`: 보통 속도·0.5배속·비스듬한 시점 영상 / Normal, half-speed and three-quarter reel.
- `tools/dcc/labrador_pet_gallop*.py`, `labrador_gallop_source_review.py`, `LabradorGallopInstaller.cs`: 재사용 제작·검토·영상·Run 전용 임포트 도구 / Reusable authoring, review, reel and Run-only import tools.

기존 http://127.0.0.1:8773/locomotion/ 경로에서 최종 채택한 수정본을 제공합니다. 걷기/달리기, 보통 속도/0.5배속, 옆/비스듬한 시점, 정지·시간 이동을 제공합니다. `tools/labrador-petting-viewer/locomotion-source.json`이 승인된 에셋 경로를 지정하고 기존 쓰다듬기 경로는 유지합니다. 본편은 기존 F2 모션 항목과 1/2 키를 사용합니다. 제자리 게임용 클립이며 이동 AI는 이번 수정 범위가 아닙니다.

The existing viewer route serves the adopted correction with gait/rate/view controls, pause and seek. Its source configuration selects the accepted assets; petting keeps its original route. Native F2 and 1/2 controls remain unchanged. Game clips are in place; translation AI is outside this correction.

## 검증·공유·정리 / Validation, publication and cleanup

- `gallop-production-summary.json`, `gallop-animation-validation.json`: 별도 제작본 및 **29/29 검사**, 실제 피부 120Hz 61자세와 FBX 왕복 5자세. 원본 rest·weights·morph·털 마스크와 care·Walk 키는 정확히 동일합니다. / Separate production and 29 passed checks, 61 skin poses and five FBX round-trip poses; original data and care/Walk keys are exact.
- `gallop-independent-acceptance.json`, `gallop-reference-review.json`: 새 사진 기준 **5개 인수 통과**, 실제 피부 10장과 최종 MP4의 정확 디코드 프레임 48개(보통 옆 12·반속도 옆 24·보통 비스듬히 12)를 순서대로 검토했습니다. 무중단 영상을 인간이 관람했다고 주장하지 않습니다. / Five new reference criteria accepted using ten skin stills and 48 ordered decoded final-movie frames; this is not a claim of human uninterrupted playback review.
- `gallop-unity-import.json`: 실제 설치 Run **147/147 검사**, 593곡선·62피부자세(실제 약 122Hz). 전체 피부 최저 +0.294mm, 0.5초 루프, 루트 평면 이동·반복 위치/각도 차이 0. 기존 Run GUID와 다른 **30개 에셋/metadata**는 동일합니다. / Actual imported Run passes 147 checks; its GUID and 30 other asset/metadata files are retained.
- `gallop-video-summary.json`, `gallop-video-seek.json`: 최종 **12초·960×640·24FPS H264** 영상, 5구간 시간 이동 오차 0, 앞쪽 MP4 인덱스. / Final reel with five exact seeks and fast-start index.
- `gallop-native-build.json`, `gallop-native-acceptance.json`, `gallop-native-install.json`: 새 Mac 빌드 오류 0·기존 공통 경고 171개(래브라도 관련 0개, `gallop-native-build-warning-review.json`), 실제 플레이어 **30/30 검사**. 모션 전환·정지·복귀·재시도·초기화·기존 쓰다듬기·가방 상태 복원을 확인하고 최신 `Builds/MusimusihanRPG.app`으로 설치했습니다. 서명·Applications 심볼릭 링크·Dock 연결을 유지합니다. / Fresh native build and 30 passed player checks, installed as the latest playable while preserving launch links and verified signature.

최종 Run은 **0.5초·60FPS·3.063375910135234m/s 기준**입니다. 지지 발바닥의 측정된 잔여 이동은 최대 10.25mm이며 완전 무미끄럼으로 표현하지 않습니다. LH 발 떼기의 빠른 발끝 회전(최대 26.51°/8.33ms)은 최종 반속도 순차 프레임을 보고 허용했지만 남은 제약으로 기록합니다. 사진 속 셰퍼드의 골격을 래브라도에 그대로 복제한 것은 아닙니다. 네이티브 검사는 실제 모드 명령을 사용하는 결정적 검사이며 물리적 데스크톱 입력·포커스·오디오는 검사하지 않습니다.

Run is 0.5 s at 60 FPS with a 3.063375910135234 m/s nominal travel speed. Residual fixed-sole drift reaches 10.25 mm. A rapid LH toe-down peak remains documented after half-speed frame inspection. The pose reference does not imply breed-exact anatomy. Native checks use production mode commands without physical desktop input, focus or audio.

이전 32개 PlayMode 결과는 변경하지 않은 런타임의 과거 근거이며 이번 질주 품질의 검사로 재사용하지 않습니다. 최종 모델·Blender·Run FBX·영상·포스터·최신 실행본·원본은 보존하고 이번 검토 완료 캡처·진단·로그·이전 실행본만 정리합니다. 작은 결과와 정리량은 `gallop-summary.json`, `gallop-cleanup-summary.json`에 남깁니다. 라이선스 바이너리와 사용자 사진은 로컬에 보존하며, 작업 코드·문서·작은 요약은 기존 `codex/labrador-pet-20261005` 브랜치에 반영하고 `gallop-publication-summary.json`으로 원격 SHA와 선택 파일 일치를 확인합니다.

The prior 32 PlayMode results remain historical evidence for unchanged runtime behavior. Final productions, exports, reel/posters, originals and latest playable are preserved; reviewed task-only QA, diagnostics, logs and the superseded app are cleaned with measured allocation/free-space receipts. Licensed binaries and the user photo stay local. Task source, documentation and compact summaries are published on the existing branch, with remote and selected-file hashes verified in the publication receipt.
