# 래브라도 달리기 프레임 이미지 / Labrador Run frame images

사용자의 요청에 따라 현재 채택한 수정 Run 한 주기를 실제 3D 제작본에서 PNG로 렌더했습니다. 기준은 `asset-staging/labrador-sprint-repair-20261006/production/LabradorPet_SprintRepair.blend`와 같은 폴더의 `export/sprint-repair-manifest.json`입니다. 애니메이션·모델·게임은 변경하지 않았습니다.

At the user's request, the accepted corrected Run was rendered directly from the actual 3D production. The source is the final SprintRepair Blend and its animation manifest; animation, model and game installation remain unchanged.

0.70초 주기·60fps의 frame 1–42를 순서대로 저장합니다. 각 프레임의 시각은 `(frame-1)/60`초이며 0–0.683333초입니다. frame 43은 첫 자세와 같은 반복 끝점이므로 제외합니다. 출력은 1280×854 PNG이며, 옆 시점·카메라·조명·중립 배경을 고정하고 motion blur를 껐습니다. 상단에 번호와 시간을 표시합니다.

The 0.70s/60fps cycle has 42 unique frames, numbered 1–42. Time is `(frame-1)/60` seconds, spanning 0–0.683333s. Repeated endpoint 43 is omitted. Each PNG is 1280×854 with a fixed side camera, studio lighting and neutral background, without motion blur. A small caption gives frame number and time.

최종 출력 위치: `asset-staging/labrador-run-frames-20261006/export/frames/Run_001.png`부터 `Run_042.png`. 전체 모아보기는 `export/Labrador_Run_42Frames_Overview.png`, 6프레임씩 큰 모아보기 7장은 `export/sheets/`, 개별 42장 ZIP은 `export/Labrador_Run_42Frames.zip`입니다. ZIP에는 번호순 PNG 42장과 설명·소스/시간/해시 manifest를 포함합니다. 원본 모델과 이전 최종 영상·실행본은 보존합니다.

Final output: 42 individual PNGs under `export/frames/`, one overview, seven larger sheets and a frame-only ZIP with README and source/time/hash manifest. Original production, prior final movie and playable app remain preserved.

재사용 도구는 `tools/dcc/labrador_pet_sprint_frames.py`(Mac Blender)와 `tools/dcc/labrador_frame_pack.py`(Pillow 포함 workspace Python)입니다. 렌더는 실제 변형 메시의 카메라 내부 범위를 각 42자세 확인하고, 독립검토는 PNG 무결성·치수·순서·시각·고유성·소스 보존을 검사합니다. 이 작업은 프레임 출력이며 모션 전체 인수를 재실행하지 않습니다. 이전 모션 인수와 스킨 한계는 `docs/LABRADOR_SPRINT_REPAIR_20261006.md`에 기록되어 있습니다.

Reusable tools render with Mac Blender and package using Pillow. Rendering checks actual deformed geometry framing at every pose; independent validation checks PNG integrity, dimensions, sequence/time mapping, uniqueness and source preservation. This frame-export request does not rerun full motion/native acceptance; the repair handoff retains those results and limitations.

요청한 42장·모아보기·ZIP은 최종 사용자 산출물로 보존합니다. 검증이 끝난 임시 log만 작은 요약을 남긴 뒤 정리합니다. 공개 GitHub에는 이번 도구·문서·검증 요약만 반영하고 licensed 이미지/ZIP은 로컬에 보존합니다.

The 42 frames, sheets and ZIP are requested final deliverables and remain preserved. Only temporary logs are cleaned after a compact summary. Publish the task tools, documentation and evidence; licensed rendered images and ZIP remain local.

최종 결과: 실제 메시 framing42검사, 독립12항목, PNG42장 전체 decode/고유성/순서/시각과 ZIP42장 해시가 통과했습니다. root가7장 모아보기에서 모든42자세와 전체 모아보기를 직접 확인했습니다. 제작 원본과 manifest SHA는 동일합니다. PNG 합계40,777,094바이트입니다. 작은 요약은 `run-frames-summary.json`, 전체 시간/해시는 `run-frames-render.json`, 독립검사는 `run-frames-validation.json`에 있습니다.

Final result:42 actual geometry framing checks,12 independent checks, full PNG integrity/uniqueness/order/time mapping and all42 ZIP hashes passed. Root inspected every pose across seven detail pages plus the overview. Source/manifest hashes remain unchanged; individual PNGs total40,777,094bytes. Summary/render/validation receipts preserve the handoff.

임시 렌더 log 한 개만 정리했습니다. 제거 할당량 12,288바이트, 실제 여유 변화 관측 8,192바이트, 현재 여유 12,732,874,752바이트입니다. 최종 요청 이미지·ZIP·모아보기와 원본·게임은 보존했습니다.

Cleaned only the temporary render log: 12,288bytes allocation, observed free delta 8,192bytes, current free 12,732,874,752bytes. Requested final images, ZIP, sheets, originals and game remain preserved.

이번 도구·문서·작은 검증 기록은 기존 Labrador 작업 브랜치에 선택하여 반영하고 원격/로컬 SHA 일치를 확인합니다.

Task tools, documentation and compact evidence are selected for the existing Labrador task branch; publication verifies remote/local hashes.
