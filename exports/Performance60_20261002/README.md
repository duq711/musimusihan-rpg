# Unity 60FPS 최적화 자료 / Optimization archive

이번 작업의 코드·셰이더·검증·문서 변경 62개를 `source.patch.gz`에 저장했습니다. 적용 기준은 로컬 Unity 이전 커밋 `08a0d3ffb12c53fab5f6017462402c8d6418343c`이고 작업 커밋은 `97dc2b3b4adf5c1f014dd4f3d9a010f04982a4e8`입니다. 패치를 기준 파일에 적용한 뒤 모든 결과의 SHA-256 일치를 확인했습니다. `manifest.json`은 파일 해시, `receipt.json`은 비식별 측정 근거입니다.

This archive stores all 62 task files as a compressed patch, based on local Unity migration commit `08a0d3ffb12c53fab5f6017462402c8d6418343c` and task commit `97dc2b3b4adf5c1f014dd4f3d9a010f04982a4e8`. Applying the patch to the baseline files reproduced every recorded SHA-256. The manifest records hashes; the receipt records sanitized measurements.

로컬 Git 인증 문제로 전체 Unity 이전 브랜치의 push는 완료하지 못했습니다. 이 자료는 기존 Unity 이전 파일·에셋이 필요한 작업 차이이며, 독립 실행 가능한 전체 프로젝트 또는 전체 브랜치 동기화를 뜻하지 않습니다. 설치된 Mac 실행본과 원본 에셋은 로컬에 보존합니다.

Local Git authentication blocked pushing the full migration branch. This task delta requires the existing migration files/assets and is not a standalone project or confirmation of full-branch synchronization. The installed Mac app and source assets remain preserved locally.

복원 / Restore: `gzip -dc source.patch.gz | git apply --check -`, then apply without `--check` from the required baseline checkout. Verify results against `manifest.json`.

---

# Unity Mac 60FPS 최적화 / Optimization — 2026-10-02

성능 모드의 은신처·던전·동굴은 최종 빌드17의 각 3,600프레임 측정에서 **60FPS 처리 여유 기준을 통과**했다. 새 실행본은 `unity-game/Builds/MusimusihanRPG.app`에 설치했고 기존 Dock 대상과 Applications 연결을 유지했다. 사용자는 기존 아이콘으로 실행하고 **Esc → 설정 → 성능 모드**를 선택하면 된다.

| 경로 / Route | 평균 FPS / Mean FPS | Wall p99 ms | Wall 최대 / Max ms | GPU p99 ms | 판정 / Capacity |
|---|---:|---:|---:|---:|---|
| 은신처 / Hideout | 105.987 | 13.209 | 18.551 | 10.183 | 통과 / Passed |
| 던전 / Dungeon | 197.399 | 7.710 | 12.150 | 6.697 | 통과 / Passed |
| 동굴 / Cave | 169.534 | 8.203 | 13.938 | 5.962 | 통과 / Passed |

기준은 무제한 실제 프로덕션 프레임의 wall/GPU p99 ≤16.667ms, wall 최대 ≤33.333ms, 독립적인 유효 GPU 표본 ≥90%다. 최종 GPU 표본은 3,590 / 3,589 / 3,590개다. 은신처의 wall 간격 하나(0.0278%)가 16.667ms를 넘었고 나머지 경로는 0개였다. GPU 초과는 세 경로 모두 0개다. 평균 FPS는 프레임 간 wall 간격으로 계산하며 CPU·GPU 표본을 짝짓거나 더하지 않는다.

성능 모드에서 월드와 1인칭 장비를 **960×540**으로 렌더링하고 UI·문자·최종 출력을 **1920×1080**으로 유지한다. 최대 4개 점/스폿 조명과 별도의 방향성 키 조명을 한 패스로 처리하고 그림자를 끈다. 시간 AA 대신 FXAA와 bilinear 확대를 사용하며 작은 bloom을 유지한다. 재질의 원본 텍스처·노멀·UV·알파·물결·정점 색은 유지하지만 물 반사와 일부 날씨·조명 효과를 단순화한다. glow가 곧 덮어쓸 중복 확대 패스를 제거했다. 화질 모드로 돌아가면 원래 재질·1080p 월드/장비·시간 AA·그림자·프레임 설정을 복원한다.

CPU 측에서는 UI 검색 문자열 생성과 렌더 준비의 반복 작업을 줄였다. 재질·알파 깊이·범위·정적 배치의 중복 분류를 같은 호출 안에서 재사용하면서 같은 프레임의 생성·삭제·활성·레이어·셰이더 변경과 호출자 상태를 계속 검사한다. 렌더러·조명 수집은 로드된 씬과 실제 영속 씬을 포함한다. 정상 플레이에는 QA 타이밍 계측이나 활동 유지 토큰을 켜지 않는다.

최종17에서 **fast 11,549 + quality 110 + 원래 draw-culling 766 = 새 검사 12,425개**가 통과했다. 정적 배치 2,642개 검사는 빌드14에서 실행했으며 관련 핵심 소스 3개의 SHA가 최종17과 같아 명시적으로 재사용한다. 최종17의 fast 검사는 중첩 배치 변경도 새로 검증한다. 추가로 이전 단계의 gameplay 225단계, fill 32, arms 182, punctual 1,656, near 439검사 근거를 보존한다. 기존 draw assertion과 16픽셀 HDR guard는 약화하지 않았다. 셰이더 생성기 12개 출력 확인과 Python 문법 확인도 통과했다.

빌드17은 Release Mono universal Mac이며 오류 0, 경고 176이다. 엄격 로컬 서명 검증이 통과했다. 세 경로 스크린샷에서 UI·문자의 1080p 출력, 손·장비와 화면 구성을 확인했으며 누락 셰이더의 분홍색 출력은 보이지 않았다. 기본 앱 디렉터리 inode와 Dock 설정을 보존했고 이전 앱은 ignored `Artifacts/performance60-20261002/PreviousInstalledBuild-before-17.app`에 남겼다. 사용자 프로세스를 종료하지 않았다. 설치된 `Rpg.Gameplay.dll` SHA-256: `fa6712eff46781d2012a664356f7ebcaf33f73783334bd3918dbab4ca1c096b2`.

측정은 **RPG 단독 실행**, 분리된 빌드·설정, 음소거·입력 억제·포인터 해제를 사용하는 숨김 실제 프로덕션 프레임이다. 지정 카메라 스윕과 구간 전환 중 게임 시뮬레이션은 진행하며 측정 창 안에 수동 RenderTo·GPU readback을 넣지 않는다. 하드웨어 입력, 전경 전체 플레이, 실제 이동·전투 replay, 모든 프레임의 고정 60FPS 또는 다른 하드웨어는 인증하지 않는다. 성능 모드는 `vSyncCount=0`, `targetFrameRate=-1`로 측정한 처리 여유를 유지한다. 60FPS 소프트웨어 제한과 VSync 실험은 이전 측정에서 더 나은 안정성을 확인하지 못해 채택하지 않았다. [Unity targetFrameRate](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Application-targetFrameRate.html).

숨김 QA에서만 명시적으로 Mac 활동 토큰을 확보해 3,600프레임 동안 보유하고 해제했다. idle sleep을 허용하며 latency·전역 정책·포커스·환경설정을 변경하지 않는다. 토큰 보유만으로 실제 App Nap 상태를 입증하지 않는다. GPU 타이밍 history는 64개를 요청했고 플랫폼은 최대 32개를 반환했다. 늦게 도착한 양수 GPU 측정을 타임스탬프로 중복 제거하며 회복했다. 0을 유효값으로 대입하지 않고 원래 90% 표본 조건을 유지했다. [FrameTimingManager.GetLatestTimings](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/FrameTimingManager.GetLatestTimings.html).

빌드13의 wall p99 실패, 빌드14의 GPU 표본 부족, 빌드15 던전 GPU p99 17.269ms 실패와 이전 pacing·진단 실패는 [비식별 receipt](performance-60fps-20261002.json)에 보존한다. 과거 결과를 최종17의 통과로 바꾸지 않는다. 최종 소스 59파일 SHA와 build별 기능 검사 대응도 receipt에 있다. 원본 로그·화면·분리 빌드는 ignored `unity-game/Artifacts/performance60-20261002/`에 보존한다. 새 기능을 추가한 작업은 없으며 Godot 원본과 제작 에셋을 보존했다.

---

Final build17 **passed the 60FPS capacity criterion** over 3,600 frames on each hideout/dungeon/cave route. The new app is installed at the existing Dock target. Launch it and select **Esc → Settings → Performance mode**. The table above records the final results.

The criterion requires uncapped production wall/GPU p99 ≤16.667ms, worst wall ≤33.333ms and at least 90% distinct positive GPU samples. Final GPU coverage was 3,590 / 3,589 / 3,590 samples. One hideout wall interval exceeded 16.667ms (0.0278%); the other routes had none. GPU exceedance was zero everywhere. Mean FPS uses wall intervals; CPU/GPU samples are not paired or summed.

Performance mode renders world and first-person equipment at **960×540**, keeping UI/text/final output at **1920×1080**. It uses up to four point/spot lights plus a directional key in one pass, no shadows, FXAA/bilinear scaling and small bloom. Textures, normals, UVs, alpha, ripples and vertex colors remain; water reflections and some weather/lighting effects are simplified. A redundant upscale overwritten by glow is skipped. Quality mode restores authored materials, full-resolution world/equipment, temporal AA, shadows and pacing.

CPU work was reduced in UI lookups and repeated render preparation. Material, alpha-depth, range and static-batch classification is reused within the same call while preserving live mutation and caller-state checks. Loaded scenes and the actual persistent scene remain covered. Normal play does not enable QA timing or activity tokens.

Final17 passed **12,425 fresh checks**: 11,549 fast, 110 quality and 766 original draw-culling checks. The 2,642 static checks ran in build14 and are explicitly reused after matching three core source hashes. Fresh final17 fast checks also cover nested batch mutations. Earlier gameplay 225 steps, fill 32, arms 182, punctual 1,656 and near 439 checks remain recorded. Existing draw assertions and the 16-pixel HDR guard were preserved. The shader generator's 12 outputs and Python syntax checks passed.

The Release Mono universal Mac build has zero errors and 176 warnings; strict local signing passed. Three screenshots were inspected for native-resolution UI/text, hands/equipment and missing shaders. The default app root inode and Dock preferences were preserved; the previous app remains in the ignored artifact backup. No user process was terminated. The installed gameplay assembly hash is recorded above.

Measurements use the **RPG alone**, isolated build/settings and hidden actual production frames with muted audio, suppressed input and an uncaptured cursor. Live simulation continues through deterministic camera sweeps and segment transitions, without manual RenderTo/readback during measurement. Hardware input, full foreground play, physical movement/combat replay, constant 60FPS on every frame and other hardware are not certified. Fast mode uses `vSyncCount=0`, `targetFrameRate=-1`; previous software-60 and VSync experiments did not establish better stability and were rejected.

Explicit QA-only Mac activity was acquired, held for 3,600 observations and released. Idle sleep remains allowed; latency/global policy/focus/preferences were not changed. Ownership does not prove actual App Nap state. Timing history requested 64 entries and returned up to 32; delayed positive GPU updates were recovered and deduplicated by timestamp. Zero timings were never imputed, and the 90% sampling guard was retained.

The sanitized receipt preserves historical failures, including build13 wall p99, build14 GPU coverage and build15 dungeon GPU p99 17.269ms. It records the final 59-file source snapshot and the validation build mapping. Raw logs, captures and isolated builds stay in the ignored artifact directory. No gameplay feature was added; Godot sources and production assets remain preserved.
