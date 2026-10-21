# Unity 고딕 원정 빌드 / Native Gothic Origin build

2026-10-21 사용자 확정: Unity Mac 게임. 기존35개 방 던전·가구를 재사용하며 신규 전투·화면·장비를 고딕 코믹스 방향으로 제작합니다. 브라우저 버전은 보존된 시안입니다.

User decision: a native Unity Mac game, reusing the furnished35-room dungeon with newly authored gothic comics combat, UI and equipment. The browser version is a preserved prototype.

작업 소스 / Production sources: `unity-game/Assets/GothicOrigin/`.

최종 실행본 / Playable app: `unity-game/Builds/MusimusihanRPG-GothicOrigin.app`.

Unity6000.6.3f1 ARM64를 사용하는 최소 빌드 프로젝트를 준비합니다. 기존 전체 Unity 프로젝트와 플레이용 앱을 수정·교체하지 않습니다. 프로젝트 전용 원본 맵과 몬스터 GLB·폰트가 아래 위치에 있어야 합니다. 이 도구는 원본을 이동하거나 재작성하지 않습니다.

Prepare a minimal Unity6000.6.3f1 ARM64 build project. The original full project and playable app are preserved. This tool requires the existing local map, creature and font originals below; it copies them without moving or rewriting them.

```sh
unity projects create GothicOriginBuild --path "$PWD/asset-staging/unity_gothic_origin_20261021" --editor-version 6000.6.3f1 --architecture arm64 --template com.unity.template.3d --no-cloud --non-interactive
```

1. 생성된 프로젝트의 `Assets/Editor`에 `OriginPackages.cs`만 복사합니다. Unity 에디터 바이너리로 `-batchmode -nographics -projectPath <project> -executeMethod OriginPackages.Install -logFile <log>`를 실행합니다. 비동기 UPM 작업이 끝나면 스크립트가 종료하므로 이 단계에는 `-quit`를 넣지 않습니다. / Copy only `OriginPackages.cs` into the created project's `Assets/Editor`; run the Editor directly with the flags above. Omit `-quit`: the asynchronous UPM operation exits when complete.
2. `python3 tools/unity-gothic-origin-20261021/prepare.py <project>`로 소스·맵·몬스터·폰트 및 비대화식 TMP 필수 리소스를 준비합니다. / Prepare sources, map, creatures, fonts and noninteractive TMP resources.
3. `unity build <project> --editor-version 6000.6.3f1 --target StandaloneOSX --execute-method MusimusihanRpg.GothicOrigin.Editor.OriginBuild.Run --output-path <absolute-app-path> --non-interactive`로 빌드합니다. / Build the standalone Mac app.

필요 원본 / Required originals:

- `unity-game/Assets/StreamingAssets/GothicDungeon/`: 승인된35개 방·회랑·가구 패키지와 SHA256 매니페스트. / Original furnished35-room package and SHA256 manifest.
- `assets/3d/gothic_monster_trio_20261019/reference_match_v2/`: 처음부터 고딕으로 제작된 몬스터3종. / Three creatures originally authored in the gothic style.
- `unity-game/Assets/RPG/Generated/Fonts/`: ExpeditionSansKR, SanctuarySerifKR400, SanctuaryCinzel400 및 OFL. / Existing fonts and OFL licenses.

자동 검증 / QA:

```sh
ORIGIN_QA_DIR=/tmp/origin-native-qa <app>/Contents/MacOS/<executable> -batchmode -force-metal -screen-width 1280 -screen-height 900 -originQa -logFile /tmp/origin-native-player.log
```

QA는 별도 저장 경로·음소거·포인터 잠금 해제로 실행합니다. 실제 Metal 렌더링을 측정하므로 `-nographics`를 붙이지 않습니다. 기능 검증과600프레임씩4개 경로의 결과를 `summary.json`에 기록합니다. 완료 요약을 프로젝트 문서에 남긴 뒤 QA 이미지·로그·격리 프로젝트를 정리합니다.

QA uses a separate save, muted audio and no pointer lock. Do not add `-nographics`: performance uses real Metal rendering. It records functional checks and four600-frame routes in `summary.json`. Retain a compact project report, then remove reviewed captures/logs and the isolated build project.

## Dock 실행 연결 / Dock launcher

`python3 tools/unity-gothic-origin-20261021/install_mac_launcher.py`는 새 앱만 별도 Dock 항목으로 추가합니다. 기존 게임과 다른 앱의 순서는 보존하고, 중복 추가를 방지하며 Mac 정수 형식·실제 앱 북마크·서명을 확인합니다. 기존 프로젝트의 설치·CoreFoundation 도구를 `launcher_support/`에 그대로 재사용했습니다. / Add only the new native app to the Dock, preserving the old game and unrelated app order. The installer checks duplicates, native integer/bookmark data and signing; shared helpers are preserved copies of the existing project tools.

## 방 소실 회귀 검사 / Room-visibility regression

`-originQa -originVisibilityQa`는 신고된35번 방 시점, 문 접근 거리2·4.9·5.1·8·12m와 각도−20·0·20도, 경계 왕복, 기존 기능 및5개 이동 경로를 검증합니다. `ORIGIN_QA_LEGACY_VISIBILITY=1`은 격리 QA 실행에서만 이전5m 숨김 판정을 재현합니다. 일반 게임에서는 이 판정을 사용하지 않습니다. / Test the reported room35 view, doorway distance/angle sweeps, boundary crossings, existing functions and five movement routes. The legacy switch is restricted to isolated QA; normal gameplay uses native mesh-frustum culling.

실제 사용자 게임 로그의2940×1846 해상도에서 비교하려면 `ORIGIN_QA_WIDTH=2940 ORIGIN_QA_HEIGHT=1846`과 같은 `-screen-width 2940 -screen-height 1846`을 두 실행에 똑같이 적용합니다. / Use matching QA texture and player-window dimensions for both runs at the observed2940×1846 resolution. Original game saves are excluded from QA.

2026-10-21 방 소실 수정: [수정·검증 기록](../../docs/UNITY_GOTHIC_VISIBILITY_FIX_20261021.md). 건축은 유지하고 가려진 소품만 별도로 제외하며,3D는 최대1280×900·UI는 출력 해상도를 유지합니다. `ORIGIN_QA_FULL_RESOLUTION=1`은 비교용 전체 해상도3D를 사용합니다. / See the visibility-fix report. Structural geometry stays intact; occluded loose props are culled separately. World pixels are budgeted while UI retains native resolution. The full-resolution switch is QA-only.
