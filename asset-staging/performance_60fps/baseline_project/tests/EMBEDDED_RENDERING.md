# 방해 없는 실제 렌더러 캡처

이 macOS Godot 4.7 빌드에서는 `--embedded` 부트스트랩으로 **창을 만들지 않는 실제 Forward+ / Vulkan 렌더링**을 실행할 수 있습니다. 일반 `--headless`의 더미 렌더러와 다릅니다.

```sh
PLAYER_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh
```

전신 모델과 같은 실제 일인칭 팔·손의 대기, 검 준비·공격, 방패 가드, 안전지대 횃불, 활 당김, 상자 접촉·들기 자세는 다음처럼 별도로 캡처합니다.

```sh
PLAYER_ARM_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh player_arm_preview.gd
```

팔 캡처는 `godot-game/artifacts/visual_qa/player_arms/<반복 이름>/`에 1280×720 자세 화면 8장과 실제 폐광에서의 횃불·일반 장비 화면 2장을 저장합니다. 실제 상태·상자 접촉거리·원정 복원 검증 결과와 원본 GLB·팔·플레이어·상자 손 스크립트의 SHA256도 기록하고, 캡처 도중 원본이 바뀌면 실패 처리합니다. 기존 플레이어의 공격·활·상자 시간 진행 함수를 호출하며, 외부 입력을 읽거나 주입하지 않습니다.

캐릭터 비교 화면만 다시 생성할 때는 `PLAYER_QA_BODY_ONLY=1`을 추가합니다. 결과는 `godot-game/artifacts/visual_qa/player_appearance/<반복 이름>/`에 저장됩니다. 생성된 화면은 실제 플레이어 모델·초상화·인벤토리·일인칭 장비·폐광 코드를 격리된 Godot SubViewport에서 그린 것이며, 사용자 데스크톱을 캡처하지 않습니다.

인벤토리 캡처는 격리된 SubViewport 안에만 합성 마우스 이벤트를 전달해 오른쪽 회전 버튼과 정면 복귀 버튼의 실제 클릭 경로도 확인합니다. 버튼 신호를 직접 호출하지 않으며, 사용자 커서를 움직이거나 외부 입력·포커스를 가져오지 않습니다. 결과는 캡처 매니페스트의 `local_gui_checks`에 기록합니다. 실제 하드웨어 조작이나 OS 포커스 동작을 확인하는 시험으로 간주하지 않습니다.

실행기는 검토한 `player_appearance_preview.gd`와 `player_arm_preview.gd`, `dark_fantasy_gallery_preview.gd`, `dark_fantasy_scene_preview.gd`만 허용하며 180초 제한, 낮은 CPU·I/O 우선순위, 더미 오디오를 사용합니다. 실제 렌더러를 시작하기 전에 `--headless --version`으로 실행 파일이 검증한 `4.7.stable.official.5b4e0cb0f` 버전인지 확인하며, 다르면 실행을 거절합니다. 시간 제한은 `GODOT_PREVIEW_TIMEOUT_SECONDS`로 조정할 수 있습니다. 종료·중단·시간 초과 시 이 실행기가 시작한 프로세스만 정리합니다.

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

전체 촬영은 시작과 종료 시 모든 제작 스크립트, 내부·외부 동굴 셰이더, 생성한 재질 이미지 7개와 가져오기 설정, 오브젝트 목록과 실제 널빤지 배치 표본의 SHA-256을 비교합니다. 중간에 원본이 달라지면 실패하며 `source_files_unchanged`에 결과를 남깁니다. 큰 GLB 원본은 오브젝트마다 다시 읽지 않고 실행 중 한 번 계산한 해시를 공유합니다. 적의 검은 원본 대기 자세 함수를 적용한 뒤 게임 실행을 제거하므로 보관용 초기 자세에 가려지지 않습니다.

## 실제 장소에서의 비교

추가로 검토한 `dark_fantasy_scene_preview.gd`는 실제 은신처·성물실·폐광을 같은 위치의 10개 카메라로 촬영합니다. 은신처와 성물실의 원본 공간·환경·조명·소품 생성 함수를 실행하고 게임 루프에 들어가기 전에 입력·게임 동작을 제거합니다. 폐광은 기존에 검토한 원본 지형·횃불 카메라 합성 함수를 사용하며 지면에 붙는 장식·등불이 완성될 때까지 기다립니다. 실제 몸과 손은 화면에 표시하지 않습니다. 세 장소는 독립 뷰포트에 구성되고 원정·커서·샌드박스 상태가 보존됩니다.

`DARK_FANTASY_SCENE_LOCATIONS=hideout`을 추가하면 은신처의 같은 카메라 네 곳만 확인합니다. `dungeon`, `mine`도 선택할 수 있으며 쉼표로 묶습니다. 알 수 없는 장소는 실행하지 않고, 부분 촬영은 매니페스트의 `complete_locations`가 거짓으로 기록됩니다. 전체 비교에는 이 값을 지정하지 않아 열 곳을 모두 촬영합니다.

```sh
./godot-game/tests/run_headless_tests.sh dark_fantasy_scene
DARK_FANTASY_SCENE_ITERATION=iteration_01 GODOT_PREVIEW_TIMEOUT_SECONDS=300 ./godot-game/tests/run_embedded_preview.sh dark_fantasy_scene_preview.gd
```

출력은 `artifacts/visual_qa/dark_fantasy_scenes/<반복 이름>/`이며 화면 10장과 정확한 카메라·시야각·실제 스크립트 해시·원정과 커서 보존 결과를 기록합니다. 손에 든 메시를 숨길 때 실제 플레이어 횃불의 전방 조명과 주변 보조광은 모두 유지하며, 이 조건도 자동 검증합니다. 기존 폴더를 덮어쓰지 않습니다. 변경 전 프로젝트 복사본에도 같은 하네스를 실행하여 같은 카메라로 비교할 수 있습니다.

## 실제 게임 성능 측정

`performance_preview.gd`는 창을 만들지 않는 동일한 embedded/Vulkan 경로에서 **실제 게임 처리와 물리**를 계속 실행합니다. 은신처·성물실·폐광의 원본 생성 함수와 상속한 프레임 처리, 플레이어·적 AI·HUD·물리·횃불·일인칭 장비 뷰포트를 포함합니다. 외부 입력을 바꾸는 장면 진입과 OS 포커스 알림만 안전한 어댑터로 대체하고 입력 이벤트 처리는 끕니다. 그림만 남기는 미술 비교 하네스와 측정 목적이 다릅니다.

```sh
./godot-game/tests/run_headless_tests.sh performance_harness
PERFORMANCE_QA_ITERATION=baseline_vulkan_01 GODOT_PREVIEW_TIMEOUT_SECONDS=900 ./godot-game/tests/run_embedded_preview.sh performance_preview.gd
```

기본은 화덕·성물실 입구·폐광 입구·물가의 네 시점을 1280×720과 2560×1664에서 측정합니다. 원래 프로젝트의 TAA·MSAA·오클루전 설정을 읽으며 미술 갤러리 전용 설정을 적용하지 않습니다. 기본 90프레임 예열 후 180프레임을 기록합니다. `PERFORMANCE_QA_FRAMES=120`, `PERFORMANCE_QA_RESOLUTION=720p` 또는 `native`, `PERFORMANCE_QA_CASES=hideout_hearth,mine_entrance`로 범위를 줄일 수 있습니다. `PERFORMANCE_QA_MOTION=1`은 게임 안의 속도·카메라를 제한된 왕복으로 움직이고 실제 검 공격 함수를 호출합니다. 외부 키/마우스 이벤트를 주입하지 않으며 이동 거리·공격 요청과 실제 물리 틱을 기록합니다.

`artifacts/performance/<반복 이름>/`의 각 JSON에 원본 프레임 기록과 평균·p50·p95·p99가 저장됩니다. 장면별 PNG는 **측정 구간이 끝난 다음** 저장합니다. 측정 중 이미지 읽기·`force_draw`·파일 쓰기·통계 정렬을 하지 않습니다. 엔진 FPS 제한과 저사용량 대기를 끄고 VSync 비활성화를 요청합니다. 숨김 뷰포트에는 화면 표시를 기다리는 단계가 없습니다.

렌더 CPU는 프레임 준비 시간과 모든 뷰포트의 CPU 시간 합계, GPU는 모든 실제 뷰포트의 GPU 시간 합계입니다. 일인칭 장비 비용도 따로 기록합니다. 게임 처리·물리·벽시계 프레임 간격, draw call·primitive·GPU 메모리와 계측 호출 비용도 포함합니다. `performance_sampler.gd`의 `begin()`은 기존 계측부터 해제하며 `end()`는 렌더 시간 계측을 끄므로 테스트룸 패널을 닫은 뒤 계측 비용을 남기지 않습니다. [Godot의 렌더 시간 정의](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu)를 따릅니다.

60fps의 프레임 예산은 약16.67ms입니다. 이 결과는 해당 컴퓨터의 실제 렌더 처리량이며, 창 합성·화면 표시·입력 지연을 포함한 게임 창의 완전한 FPS 보증은 아닙니다. GPU 시간값은 완료된 이전 프레임의 값일 수 있어 개별 CPU/GPU 행의 동시성을 주장하지 않습니다. 마우스를 캡처하지 않아 원래 코드의 캡처 상태에 의존하는 상호작용 광선 검사·일부 스트레스 표시도 생략되므로 실제 플레이를 위해 여유를 둡니다. 다른 게임·브라우저 등 사용 중인 앱은 종료하지 않으며, 공유 CPU/GPU 부하는 반복 비교에 영향을 줄 수 있습니다. 실행기는 기존처럼 낮은 CPU·I/O 우선순위를 사용합니다.
