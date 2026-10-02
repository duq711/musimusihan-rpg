# Unity 그래픽·60FPS 개선 자료 / Image clarity archive

이번 작업의 코드·셰이더·검증·문서 변경 15개를 `source.patch.gz`에 저장했습니다. 적용 기준은 로컬 Unity 이전 커밋 `97dc2b3b4adf5c1f014dd4f3d9a010f04982a4e8`이고 작업 커밋은 `fa459ca728cbba23ca80c3cca7b28dcb3538949f`입니다. 패치를 기준 파일에 적용한 뒤 모든 결과의 SHA-256 일치를 확인했습니다. `manifest.json`은 파일 해시, `receipt.json`은 비식별 측정 근거입니다.

This archive stores all 15 task files as a compressed patch, based on local Unity migration commit `97dc2b3b4adf5c1f014dd4f3d9a010f04982a4e8` and task commit `fa459ca728cbba23ca80c3cca7b28dcb3538949f`. Applying the patch to the baseline files reproduced every recorded SHA-256. The manifest records hashes; the receipt records sanitized measurements.

로컬 Git 인증 문제로 전체 Unity 이전 브랜치의 push는 완료하지 못했습니다. 이 자료는 기존 Unity 이전 파일·에셋이 필요한 작업 차이이며, 독립 실행 가능한 전체 프로젝트 또는 전체 브랜치 동기화를 뜻하지 않습니다. 설치된 Mac 실행본과 원본 에셋은 로컬에 보존합니다.

Local Git authentication blocked pushing the full migration branch. This task delta requires the existing migration files/assets and is not a standalone project or confirmation of full-branch synchronization. The installed Mac app and source assets remain preserved locally.

복원 / Restore: `gzip -dc source.patch.gz | git apply --check -`, then apply without `--check` from the required baseline checkout. Verify results against `manifest.json`.

---

# Unity 그래픽 선명도와 60FPS / Image clarity and 60FPS — 2026-10-03

자글거리는 성능 모드 화면을 개선한 **빌드 19**를 기존 Dock 실행본에 설치했다. 월드·1인칭 장비 해상도는 **960×540 → 1280×720**, UI·문자·최종 출력은 **1920×1080**이다. 실행 중인 이전 게임을 종료한 뒤 기존 아이콘으로 다시 열고 **Esc → 설정 → 성능 모드**를 사용한다.

은신처 돌 스캔 텍스처는 실제로 밉맵이 없는 1254×1254 원본이었다. 성능용 재질만 전체 크기와 sRGB를 보존한 GPU 복사본에 11단계 밉맵을 생성하고 trilinear 필터링을 적용한다. 원본 텍스처·임포트 설정·Godot 자료는 그대로 보존한다. 기본 단계 1,572,516픽셀의 실제 GPU 비교에서 최대 색상 오차는 **0**이었다. 성능 모드의 샘플링 bias는 +.25이며 화질 모드의 기존 Mac 값 0을 복원한다.

공간 AA에 가로·세로 이웃 기반의 서브픽셀 보정을 추가해 대각선 방식이 놓치던 체크무늬를 처리한다. 기존 HDR·평탄색·알파·반복 안정성 검사는 유지한다. 셰이더의 기하 노멀 변화에 맞춰 거칠기를 보정해 가는 반사광을 완화한다. 시간 누적·추가 깊이/모션 패스는 넣지 않았으며 기존 조명 제한·그림자 제외로 처리 여유를 유지한다. 화질 모드의 원래 1080p·재질·시간 AA는 복원한다.

| 경로 / Route | 평균 FPS / Mean | Wall p99 ms | Wall 최대 / Max ms | GPU p99 ms | GPU 표본 / Samples |
|---|---:|---:|---:|---:|---:|
| 은신처 / Hideout | 98.527 | 15.514 | 27.825 | 11.405 | 3590 |
| 던전 / Dungeon | 175.063 | 8.922 | 12.753 | 15.851 | 3589 |
| 동굴 / Cave | 141.196 | 10.712 | 17.937 | 6.947 | 3590 |

세 경로 모두 각 **3,600구간**의 엄격 60FPS 처리 여유 기준을 통과했다: 무제한 wall/GPU p99 ≤16.667ms, wall 최대 ≤33.333ms, 독립 양수 GPU 표본 ≥90%, 진단용 대체 경로 없음. wall 16.667ms 초과는 은신처 17개(0.4722%), 던전 0개, 동굴 1개(0.0278%)다. GPU 초과는 던전 1개(0.0279%), 다른 경로 0개다. 따라서 모든 프레임의 고정 60을 보증하지 않는다. 720p 타깃은 각 경로 3,600프레임 모두 같았고 측정 중 월드·장비 타깃 재할당·스캔 GPU 재복사·소유권 정리 전수 검색은 **0회**였다.

최종 19에서 새 **11,701검사(quality 119 + fast 11,582)**를 통과했다. 실제 카메라 해상도·중첩 샘플링·원본 복원, 실제 은신처 스캔의 전체 크기·밉맵·sRGB·GPU 색상, Renderer.material 호출자가 같은 프레임에 분리되는 경우의 텍스처 수명과 재부착을 검사했다. 합성 체크무늬 3,588픽셀의 이웃 에너지는 90% 줄었지만 이 값은 해당 합성 패턴에 한하며 게임 전체 개선률로 사용하지 않는다. 셰이더 생성기의 12개 출력과 Python 문법도 확인했다. 이전 빌드 17의 다른 분야 검사를 이번의 새 검사 수에 합산하지 않는다.

오류 0·경고 176의 Release Mono universal Mac 빌드이며 엄격 로컬 서명이 통과했다. 기본 앱 디렉터리와 기존 Dock/Applications 연결을 보존했다. 다른 사용자 앱을 종료하지 않았고 Dock 환경설정을 수정하지 않았다. 설치된 `Rpg.Gameplay.dll` SHA-256: `4737e5f99b2280afe92b63a3cd962d6f5296e2d78a9b31006ce33bb2234715d6`. 이전 실행본은 `Artifacts/performance60-20261002/PreviousInstalledBuild-before-19.app`에 보존했다.

실제 최종 19 은신처 이미지에서 돌 이음선·아치·통로와 누락 표면 여부를 확인했다. 측정은 RPG 단독 실행의 조용한 백그라운드 프로덕션 프레임과 지정 카메라 스윕이며 수동 RenderTo/readback은 측정 창 뒤에만 수행한다. 물리적 이동·전투 재생·전경 전체 플레이·다른 하드웨어를 인증하지 않는다. 원본 로그·사진·분리 빌드는 ignored `Artifacts/clarity60-20261003/`, 빌드 도구와 이전 앱은 ignored `Artifacts/performance60-20261002/`에 있다. [비식별 검증 근거](clarity-60fps-20261003.json)는 61개 소스 SHA와 예비 675p 빌드 18의 결과를 최종 720p 빌드 19와 구분한다. [이전 540p 기록](PERFORMANCE_60FPS_20261002.md)은 역사로 보존한다.

---

**Build 19 is installed at the existing Dock target.** It improves grainy performance-mode rendering: world/equipment increase from 960×540 to **1280×720**, while UI/text/output remain **1920×1080**. Relaunch the existing app and select **Esc → Settings → Performance mode**.

The actual hideout 1254² scan had no mipmaps. A performance-only GPU copy preserves size/sRGB/base colors and generates 11 mip levels with trilinear filtering. GPU comparison of all 1,572,516 base pixels measured zero channel error. Original textures/import settings and Godot assets remain preserved. Fast sampling uses bias +.25; quality mode restores the authored Mac bias 0 and full-resolution rendering.

Spatial AA now handles horizontal/vertical subpixel patterns missed by diagonal detection, retaining HDR/flat-color/alpha/repeatability guards. Geometric normal variance limits narrow specular highlights. No temporal history or extra depth/motion passes were added; the existing light budget and disabled shadows retain capacity.

All three **3,600-interval routes passed** the unchanged strict 60FPS capacity criterion shown above. Hideout had 17 wall intervals above 16.667ms, cave had 1 and dungeon had 0; dungeon had 1 GPU exceedance. This is not a guarantee of 60 on every frame. Every measured world/equipment frame used 1280×720. Target reallocations, scan GPU recopying and ownership-cleanup material scans were all zero during measurement.

Final 19 passed **11,701 fresh checks**: 119 quality and 11,582 fast checks. Coverage includes actual target allocation, nested sampling/restoration, real scan mip/sRGB/base-color correctness and a detached Renderer.material caller's lifetime/reattachment. Synthetic checker energy fell 90% for that fixture only; this is not a whole-game improvement percentage. The generator's 12 outputs and Python syntax were verified. Historical tests are not counted as new final 19 checks.

The universal Release Mono Mac build has zero errors / 176 warnings and passed strict local signing. The existing app root, Dock/Applications links and preferences are preserved; no user process was terminated. Installed assembly hash and backup location are recorded above. Final captures were inspected for stone/arch/path detail and missing surfaces. Measurements use the RPG alone and quiet production-frame camera sweeps, without readback during timing; full foreground play, physical movement/combat replay and other hardware are not certified. The linked sanitized receipt records 61 source hashes and distinguishes the 675p build 18 pilot from the final 720p build 19.
