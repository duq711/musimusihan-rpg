# 방해 없는 실제 렌더러 캡처

이 macOS Godot 4.7 빌드에서는 `--embedded` 부트스트랩으로 **창을 만들지 않는 실제 Forward+ / Vulkan 렌더링**을 실행할 수 있습니다. 일반 `--headless`의 더미 렌더러와 다릅니다.

```sh
PLAYER_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh
```

전신 모델과 같은 실제 일인칭 팔·손의 대기, 검 준비·공격, 방패 가드, 안전지대 횃불, 활 당김, 상자 접촉·들기 자세는 다음처럼 별도로 캡처합니다.

```sh
PLAYER_ARM_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh player_arm_preview.gd
```

팔 캡처는 `godot-game/artifacts/visual_qa/player_arms/<반복 이름>/`에 1280×720 화면 8장과 실제 상태·상자 접촉거리·원정 복원 검증 결과를 저장합니다. 기존 플레이어의 공격·활·상자 시간 진행 함수를 호출하며, 외부 입력을 읽거나 주입하지 않습니다.

캐릭터 비교 화면만 다시 생성할 때는 `PLAYER_QA_BODY_ONLY=1`을 추가합니다. 결과는 `godot-game/artifacts/visual_qa/player_appearance/<반복 이름>/`에 저장됩니다. 생성된 화면은 실제 플레이어 모델·초상화·인벤토리·일인칭 장비·폐광 코드를 격리된 Godot SubViewport에서 그린 것이며, 사용자 데스크톱을 캡처하지 않습니다.

인벤토리 캡처는 격리된 SubViewport 안에만 합성 마우스 이벤트를 전달해 오른쪽 회전 버튼과 정면 복귀 버튼의 실제 클릭 경로도 확인합니다. 버튼 신호를 직접 호출하지 않으며, 사용자 커서를 움직이거나 외부 입력·포커스를 가져오지 않습니다. 결과는 캡처 매니페스트의 `local_gui_checks`에 기록합니다. 실제 하드웨어 조작이나 OS 포커스 동작을 확인하는 시험으로 간주하지 않습니다.

실행기는 검토한 `player_appearance_preview.gd`와 `player_arm_preview.gd`만 허용하며 180초 제한, 낮은 CPU·I/O 우선순위, 더미 오디오를 사용합니다. 실제 렌더러를 시작하기 전에 `--headless --version`으로 실행 파일이 검증한 `4.7.stable.official.5b4e0cb0f` 버전인지 확인하며, 다르면 실행을 거절합니다. 시간 제한은 `GODOT_PREVIEW_TIMEOUT_SECONDS`로 조정할 수 있습니다. 종료·중단·시간 초과 시 이 실행기가 시작한 프로세스만 정리합니다.

매 실행의 로그를 임시 파일에 수집하고 프로세스가 종료되면 Codex 작업 안에 출력합니다. 프로세스 종료 코드가 0이어도 선택한 프리뷰의 명시적인 `PLAYER APPEARANCE PREVIEW PASS:` 또는 `PLAYER ARM PREVIEW PASS:`가 없거나 스크립트 오류가 있으면 실패 처리합니다. 정상 종료·오류·중단·시간 초과 뒤 임시 로그를 제거합니다.

## 검증 근거

Godot 4.7 stable 소스의 다음 경로를 확인했습니다.

- [`godot_main_macos.mm`](https://github.com/godotengine/godot/blob/4.7-stable/platform/macos/godot_main_macos.mm): `--embedded`를 발견하면 `OS_MacOS_Embedded`를 선택하고 백그라운드 프로세스로 전환합니다.
- [`os_macos.mm`](https://github.com/godotengine/godot/blob/4.7-stable/platform/macos/os_macos.mm): 이 경로는 `OS_MacOS_NSApp`의 `NSApplication` 초기화·활성화를 실행하지 않습니다.
- [`display_server_macos_embedded.mm`](https://github.com/godotengine/godot/blob/4.7-stable/platform/macos/display_server_macos_embedded.mm): `NSWindow` 대신 호스트에 연결하지 않은 `CALayer` / `CAMetalLayer`를 만들며, 실제 렌더러를 초기화합니다.

이 환경의 `4.7.stable.official.5b4e0cb0f`에서 단독 SubViewport의 조명·구체를 Metal과 Forward+ / Vulkan 각각으로 PNG에 출력하고 이미지를 확인했습니다. 프로세스는 정상 종료했습니다. `--debug`가 빠지면 임베디드 드라이버가 사용하는 `EngineDebugger`가 없어 초기화 도중 충돌하므로 반드시 유지합니다. 에디터나 외부 디버거에는 연결하지 않습니다.

프리뷰는 자신의 표시 드라이버가 `embedded`인지 검사하고, 커서 모드와 원정 스냅샷이 실행 전후 같은지도 검사합니다. `--embedded`를 일반 macOS 표시 드라이버로 바꾸거나, 프리뷰에서 `grab_focus()`, 커서 이동·캡처, 실제 게임 입력, 인터랙티브 환경 변수를 추가하면 이 검증 근거가 적용되지 않습니다.


## 전체 오브젝트의 여섯 방향

`dark_fantasy_gallery_preview.gd`는 실제 테스트룸 도감과 동일한 3D 뷰포트·생성 함수·조명·카메라를 사용합니다. 캐릭터나 게임 장면의 실행을 시작하지 않으며, 생성한 오브젝트의 입력·물리·처리를 끄고 외부 입력 이벤트도 보내지 않습니다. 바닥판을 추가하지 않아 아래 방향까지 가려짐 없이 확인합니다. 실제 모델의 메시 범위로 여섯 직교 카메라를 맞춥니다.

```sh
DARK_FANTASY_QA_ITERATION=iteration_01 GODOT_PREVIEW_TIMEOUT_SECONDS=600 godot-game/tests/run_embedded_preview.sh dark_fantasy_gallery_preview.gd
```

기존 출력 폴더는 덮어쓰지 않으며 개별 화면·여섯 방향 비교판·SHA-256·전체/부분 촬영 여부를 매니페스트에 남깁니다. `DARK_FANTASY_QA_OBJECTS`에 쉼표로 나눈 카탈로그 id를 지정하면 선택한 항목만 촬영합니다. 실제 PNG는 게임 모델의 이미지이며 사용자 데스크톱이나 창의 스크린샷이 아닙니다. 헤드리스 구조 검증 명령은 `godot-game/tests/run_headless_tests.sh dark_fantasy_gallery`입니다.
