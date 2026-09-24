# Roger 중세 의상 통합 / Roger medieval outfit integration

2026-09-24: [TurboSquid의 Roger 3D Model Character](https://www.turbosquid.com/3d-models/roger-3d-model-character-3d-1861645), 제작자 **Mr Browen**, 모델 ID **1861645**에서 원본을 내려받았습니다. [CGTrader의 같은 Roger 모델](https://www.cgtrader.com/free-3d-models/character/man/roger-3d-model-character)의 다운로드 오류로 공식 대체 판매처를 이용했습니다.

On 2026-09-24, the original was downloaded from **Mr Browen**'s [Roger 3D Model Character on TurboSquid](https://www.turbosquid.com/3d-models/roger-3d-model-character-3d-1861645), product **1861645**. This official alternate listing was used after download failures for [the same Roger model on CGTrader](https://www.cgtrader.com/free-3d-models/character/man/roger-3d-model-character).

## 파일과 재생성 / Files and rebuilding

아래 경로는 프로젝트 루트 기준입니다. `source/`의 원본 모델·텍스처·압축 파일과 기존 의상을 보존하고, 수정 결과는 별도 파일로 만듭니다. `build.py`는 보존한 로컬 원본을 사용하여 두 산출물을 생성합니다.

Paths below are relative to the project root. Preserve the original model, textures, archives, and original outfit under `source/`; save changes separately. `build.py` uses the preserved local sources to generate both outputs.

| 경로 / Path | 용도 / Purpose |
| --- | --- |
| `asset-staging/roger_medival_20260924/source/` | 로컬 전용 원본·텍스처 / Local-only original files and textures |
| `asset-staging/roger_medival_20260924/source/Roger Blender.blend` | 보존할 Blender 원본 / Preserved Blender source |
| `asset-staging/roger_medival_20260924/build.py` | 로컬 Blender 빌드 스크립트 / Local Blender build script |
| `asset-staging/roger_medival_20260924/Roger_Medival.blend` | 로컬 전용 수정본 / Local-only edited Blender file |
| `godot-game/assets/licensed/roger/roger_medival.glb` | 로컬 전용 Godot 모델 / Local-only Godot model |
| `asset-staging/roger_medival_20260924/fit_report.json` | 메시별 정점·면 수와 경계 좌표 / Per-mesh vertex/face counts and bounds |

원본 ZIP을 `source/`에 풀고 기존 `asset-staging/medival_clean_20260924/Medival_Clean.blend`를 준비한 뒤 프로젝트 루트에서 실행합니다. 이번 빌드는 Mac의 **Blender 5.2.1 LTS**에서 실행했습니다.

Extract the original ZIPs into `source/` and retain the existing `asset-staging/medival_clean_20260924/Medival_Clean.blend`, then run from the project root. This build used **Blender 5.2.1 LTS** on Mac.

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --disable-autoexec --python asset-staging/roger_medival_20260924/build.py
```

최종 피팅본은 머리·목, 양손, 양쪽 종아리와 눈·치아·머리카락 등 드러나는 부분을 유지합니다. 옷 아래 가려진 신체 면은 수정본에서만 제거하며 Roger 원본은 바꾸지 않습니다. 기존 Medival 의상 5개의 토폴로지는 그대로 유지합니다.

The final fitted derivative retains the exposed head/neck, hands, calves, eyes, teeth, hair, and related facial parts. Covered body faces are removed only from the derivative; the Roger source stays unchanged. The topology of all five original Medival garments is retained.

울퉁불퉁한 바짓단 위로 종아리가 끊기거나 비치지 않도록 가려지는 윗종아리에 겹침을 남깁니다. 그 부분의 신체 면만 한 번 세분화하고 실제 바지 표면으로 수평 광선을 쏘아 교차하는 정점을 8mm 안쪽으로 맞춥니다. 열린 바짓단 방향과 아래쪽 종아리의 자연스러운 형태는 유지하고 의상 메시에는 손대지 않습니다.

The hidden upper calf overlaps the irregular trouser cuff instead of ending at one flat height. Only that body region is subdivided once; horizontal rays against the actual trousers place covered vertices 8mm inside the garment. Open cuff sectors and the natural lower-calf shape remain unchanged, and no garment mesh is edited.

최종 로컬 GLB SHA-256 / Final local GLB SHA-256: `7477b8cbf4188441f66d1b114597494079cba4ee129e2bd5222bce66fee9584c`.

파일 무결성 검사는 GLB 노드 18개, 96,610,528바이트, 위 해시 일치와 원본 의상 5개의 정점·면 수 유지 및 불투명 재질을 확인했습니다. Blender 5.2에서 머리카락·두피가 혼합 투명도로 내보내져 검은 두피가 비치던 문제는 두 재질의 알파 마스크(`MASK`, 기준값 0.3)로 수정했습니다. 수염·속눈썹의 부드러운 혼합 투명도는 유지합니다.

File integrity checks confirmed 18 GLB nodes, 96,610,528 bytes, the matching hash, unchanged vertex/face counts for all five garments, and opaque garment materials. Blender 5.2 exported hair/scalp as blended transparency, allowing the black scalp to show through sorting. Those two materials now use alpha masks (`MASK`, cutoff 0.3); beard and eyelashes retain smooth blending.

독립 종아리 검사는 정점·삼각형 중심·변 중점에서 바지와 광선이 교차한 2,719개 표본을 검사했고 1mm 초과 돌출은 없었습니다. 왼쪽 최대 돌출은 0.629mm, 오른쪽 최대는 표면보다 2.443mm 안쪽입니다. 열린 바짓단에서 광선이 만나지 않은 1,500개 표본은 이 수치 검사에 포함되지 않으며 별도 화면 확인 대상으로 남습니다.

Independent calf checks sampled vertices, triangle centers, and edge midpoints. None of 2,719 samples whose rays hit the trousers protruded by more than 1mm: the left maximum was 0.629mm outward, and the right maximum was 2.443mm inside. Another 1,500 samples in open cuff sectors had no ray intersection and are outside this numeric check; they require separate visual review.

앞선 외형·이동 관찰 검사와 공용 대체 모델 회귀 4종은 통과했습니다. 브라우저의 정면·후면·머리·손 보기, 회전과 의상만 보기 후 복원을 확인했으며, 마지막 종아리 수정 후에는 위 해시의 전신 화면을 추가 확인했습니다. 앞선 전체 UI·1인칭 검증은 종아리 수정 전 `4f1bdde…28e5b2` 모델의 기록으로 유지합니다.

Earlier appearance/movement checks and four public-fallback regressions passed. Browser checks covered front/back/head/hands, orbit, and outfit-only restoration; the full body was reviewed again at the hash above after the final calf correction. The prior full UI/first-person checks remain evidence for the pre-calf-fix `4f1bdde…28e5b2` model.

최종 종아리 빌드의 전체 통합 재실행은 루트 작업 폴더의 파일 읽기 대기와 게시용 복제본의 다른 `dark_fantasy` 에셋 가져오기 캐시 누락으로 시작 단계에서 막혔습니다. 최종 전체 통합 검사를 통과했다고 기록하지 않습니다. 앞선 검사에서는 UID 경고가 없었고 기존 유형의 ObjectDB 종료 경고 1개가 남았습니다.

The final calf build's full integration rerun was blocked at startup by a file-read stall in the root workspace and missing unrelated `dark_fantasy` import caches in the publication clone. A final full integration pass is not claimed. Prior checks had no UID warnings and retained one existing-style ObjectDB exit warning.

최종 GLB와 수정하지 않은 실제 `player_appearance.gd`·`player_portrait.gd`의 격리된 헤드리스 검사는 6초에 통과했습니다. Roger 선택, 18개 표시 부위·의상 5개·필수 신체 5부위, 공용 메시·재질, 머리카락·두피 `MASK` 0.3, 약 1.426×1.859×0.347m 경계와 바닥 -0.000889m를 확인했습니다. 두 초상 종횡비에서 네 방향 프레임 유지와 실제 회전·정면 버튼도 확인했습니다.

The isolated headless check passed in six seconds using the final GLB and unchanged production `player_appearance.gd`/`player_portrait.gd`. It verified Roger selection, 18 visible parts, five garments and five required body regions, shared meshes/materials, hair/scalp `MASK` at 0.3, approximately 1.426×1.859×0.347m bounds, and floor height -0.000889m. Both portrait aspect ratios retained the model through four turns, and actual rotate/front buttons worked.

동일한 최종 해시를 기록한 `final_02` Vulkan 캡처 5장(정면·사선·상세·후면·측면)을 모두 열어 검수했습니다. 의상과 몸의 연결을 확인했으며 종아리 연결은 자연스럽고 앞선 마스크의 빈 쐐기 모양이 보이지 않았습니다. 이 결과는 최종 외형·초상 렌더 검수이며 새 보행 애니메이션·천 물리나 최종 전체 게임 회귀를 검증한 것은 아닙니다.

All five `final_02` Vulkan captures—front, three-quarter, detail, back, and side—were opened and reviewed with the same final hash in their metadata. Garment/body joins were acceptable, calf connections looked natural, and the earlier mask's empty wedge was absent. This verifies the final appearance/portrait rendering; it does not establish walking animation, cloth simulation, or a final full-game regression pass.

로컬 검수 기록 / Local verification records: `godot-game/artifacts/visual_qa/player_appearance/roger_medival_20260924_final_02/`의 `capture_manifest.json`, `VALIDATION.md`, `cleanup_report.json`, `headless.log`, `gpu.log` 및 PNG 5장. 이 폴더는 Git에서 제외됩니다. / This directory and its five PNGs are excluded from Git.

초기 통합 범위는 **정적 A 포즈**입니다. 아직 의상 시뮬레이션을 구현하지 않았습니다. 원본에 리그가 있다는 사실과 게임 안에서 애니메이션·의상 물리가 동작한다는 사실을 구분합니다.

The initial integration uses a **static A-pose**. Cloth simulation is not implemented yet. A rig in the source model does not establish working animation or cloth physics in the game.

## 공유 범위 / Sharing limits

[TurboSquid Standard License](https://www.turbosquid.com/licensing)는 로컬 수정과 조건에 맞는 게임 제작을 허용하지만, 원본·수정본의 모델과 텍스처를 공개 재배포하도록 허용하지 않습니다. `source/`, `Roger_Medival.blend`, `roger_medival.glb` 및 여기서 파생된 바이너리는 공개 GitHub에 올리지 않습니다. 다른 의상·모델과 결합해도 동일합니다. 코드·이 안내·가져오기 절차만 공유하며, 다른 환경에서는 해당 원본을 공식 판매처에서 직접 받아야 합니다.

The [TurboSquid Standard License](https://www.turbosquid.com/licensing) permits local editing and qualifying game use, but does not permit public redistribution of original or modified model and texture files. Keep `source/`, `Roger_Medival.blend`, `roger_medival.glb`, and derived binaries out of public GitHub, including versions combined with other outfits or models. Share code, this guide, and import instructions; obtain the source directly from the official listing on another environment.

게임 배포 시 모델 접근·추출 방지 조건을 별도로 충족해야 합니다. 이 로컬 통합 기록은 게임 배포 승인이나 Godot 웹 내보내기 허가를 뜻하지 않습니다.

Distributed games must separately meet the license's asset-access and extraction restrictions. This local integration record does not establish release approval or permission for Godot web exports.
