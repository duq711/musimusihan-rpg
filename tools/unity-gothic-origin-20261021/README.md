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
