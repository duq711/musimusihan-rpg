# 방해 없는 실제 렌더러 캡처

루팅 상자 배치는 `LOOT_SPAWN_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=360 ./tests/run_embedded_preview.sh loot_spawn_preview.gd`로 확인합니다. 네 가지 제공 모델의 닫힘·열림 8장, 실제 손 접촉·들기 8장과 성물실·폐광의 전체 후보 자리에서 상자가 있을 때·없을 때 22장을 같은 카메라로 저장합니다. 후보별 화면은 배치 검수를 위해 해당 자리만 명시적으로 표시하며, 실제 입장 추첨 결과를 위조하거나 본편을 전부 점유시키지 않습니다. 실제 원정 추첨과 상태 보존은 `./tests/run_headless_tests.sh loot_spawn loot_container_models`에서 검사합니다.

출력은 `artifacts/visual_qa/loot_spawns/<새 이름>/`입니다. 기존 공간 프리뷰의 원본 지형·횃불·카메라 함수를 재사용하고 플레이 입력·장면 진입·외부 이벤트·소리를 끕니다. 표시 드라이버가 `embedded`인지 확인하며, 원정·커서와 상자 모델·코드 해시가 보존되어야 성공합니다. 성공 표식은 `LOOT SPAWN PREVIEW PASS:`이며 픽셀의 배치 품질은 저장된 화면을 별도로 직접 검토합니다.

이 macOS Godot 4.7 빌드에서는 `--embedded` 부트스트랩으로 **창을 만들지 않는 실제 Forward+ / Vulkan 렌더링**을 실행할 수 있습니다. 일반 `--headless`의 더미 렌더러와 다릅니다.

```sh
PLAYER_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh
```

전신 모델과 같은 실제 일인칭 팔·손의 대기, 검 준비·공격, 방패 가드, 안전지대 횃불, 활 당김, 상자 접촉·들기 자세는 다음처럼 별도로 캡처합니다.

```sh
PLAYER_ARM_QA_ITERATION=iteration_01 godot-game/tests/run_embedded_preview.sh player_arm_preview.gd
```

팔 캡처는 `godot-game/artifacts/visual_qa/player_arms/<반복 이름>/`에 1280×720 자세 화면 8장과 실제 폐광에서의 횃불·일반 장비 화면 2장을 저장합니다. 실제 상태·상자 접촉거리·원정 복원 검증 결과와 원본 GLB·팔·플레이어·상자 손 스크립트의 SHA256도 기록하고, 캡처 도중 원본이 바뀌면 실패 처리합니다. 기존 플레이어의 공격·활·상자 시간 진행 함수를 호출하며, 외부 입력을 읽거나 주입하지 않습니다.

양손 그레이박스용 `player_hands_greybox_preview.gd`도 같은 검토된 실행기에 등록되어 있습니다. `PLAYER_HANDS_GREYBOX_QA_ITERATION=<새폴더이름> godot-game/tests/run_embedded_preview.sh player_hands_greybox_preview.gd`로 맨손·활 당김·발사 후 손 펴기·상자 접촉·뚜껑 들기 5개 실제 상태를 촬영합니다. 기존 팔 프리뷰의 격리된 SubViewport와 입력 비활성화 설정을 재사용하며, 표시 드라이버가 `embedded`가 아니거나 기존 출력 폴더가 있으면 실행하지 않습니다. 검증 표식은 `PLAYER HANDS GREYBOX PREVIEW PASS:`입니다. 먼저 `tests/run_headless_tests.sh player_hands_greybox`를 실행합니다.

캐릭터 비교 화면만 다시 생성할 때는 `PLAYER_QA_BODY_ONLY=1`을 추가합니다. 결과는 `godot-game/artifacts/visual_qa/player_appearance/<반복 이름>/`에 저장됩니다. 생성된 화면은 실제 플레이어 모델·초상화·인벤토리·일인칭 장비·폐광 코드를 격리된 Godot SubViewport에서 그린 것이며, 사용자 데스크톱을 캡처하지 않습니다.

인벤토리 캡처는 격리된 SubViewport 안에만 합성 마우스 이벤트를 전달해 오른쪽 회전 버튼과 정면 복귀 버튼의 실제 클릭 경로도 확인합니다. 버튼 신호를 직접 호출하지 않으며, 사용자 커서를 움직이거나 외부 입력·포커스를 가져오지 않습니다. 결과는 캡처 매니페스트의 `local_gui_checks`에 기록합니다. 실제 하드웨어 조작이나 OS 포커스 동작을 확인하는 시험으로 간주하지 않습니다.

실행기는 검토한 `player_appearance_preview.gd`와 `player_arm_preview.gd`, `dark_fantasy_gallery_preview.gd`, `dark_fantasy_scene_preview.gd`, `performance_preview.gd`, `blacksmith_preview.gd`, `first_person_motion_preview.gd`만 허용하며 기본 180초 제한, 낮은 CPU·I/O 우선순위, 더미 오디오를 사용합니다. 실제 렌더러를 시작하기 전에 `--headless --version`으로 실행 파일이 검증한 `4.7.stable.official.5b4e0cb0f` 버전인지 확인하며, 다르면 실행을 거절합니다. 시간 제한은 `GODOT_PREVIEW_TIMEOUT_SECONDS`로 조정할 수 있습니다. 종료·중단·시간 초과 시 이 실행기가 시작한 프로세스만 정리합니다.

매 실행의 로그를 임시 파일에 수집하고 프로세스가 종료되면 Codex 작업 안에 출력합니다. 프로세스 종료 코드가 0이어도 선택한 프리뷰의 명시적인 성공 표식(예: `PLAYER APPEARANCE PREVIEW PASS:`, `PLAYER ARM PREVIEW PASS:`, `BLACKSMITH PREVIEW PASS:`)이 없거나 스크립트 오류가 있으면 실패 처리합니다. 정상 종료·오류·중단·시간 초과 뒤 임시 로그를 제거합니다.

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

60fps의 프레임 예산은 약16.67ms입니다. 이 결과는 해당 컴퓨터의 실제 렌더 처리량이며, 창 합성·화면 표시·입력 지연을 포함한 게임 창의 완전한 FPS 보증은 아닙니다. GPU 시간값은 완료된 이전 프레임의 값일 수 있어 개별 CPU/GPU 행의 동시성을 주장하지 않습니다. 마우스를 캡처하지 않아 원래 코드의 캡처 상태에 의존하는 상호작용 광선 검사·일부 스트레스 표시도 생략되므로 실제 플레이를 위해 여유를 둡니다. 다른 게임·브라우저 등 사용 중인 앱은 종료하지 않으며, 공유 CPU/GPU 부하는 반복 비교에 영향을 줄 수 있습니다. 실행기는 기본적으로 낮은 CPU·I/O 우선순위를 사용합니다. 사용자 요청에 따라 실제 성능 측정만 `PERFORMANCE_QA_SCHEDULING=normal`로 일반 게임과 같은 보통 우선순위를 사용할 수 있습니다. 헤드리스 자동 검증은 항상 낮은 우선순위를 유지합니다.


성능 전후 비교에서는 `GODOT_PERFORMANCE_DRIVER=vulkan`과 `PERFORMANCE_QA_SCHEDULING=normal`을 동일하게 사용합니다. 성능 하네스에 한해 감사된 `metal` 드라이버도 비교할 수 있습니다. 이 빌드의 Metal 진단은 GPU 시간값을 제공하지 않아 그 경우 `gpu_timestamps_available=false`로 기록하며 0ms라는 성능 결과로 해석하지 않습니다. 정상 프레임 루프에서 완료된 실제 렌더 프레임 수와 양수 draw call을 별도로 요구합니다. Vulkan 비교에서는 GPU 시간도 양수여야 통과합니다.

뷰포트별 visible·shadow·canvas 패스의 draw call·primitive·object 수를 따로 기록합니다. 꺼진 인벤토리 초상화 등 `UPDATE_DISABLED` 뷰포트는 이전 렌더 시간과 카운터가 남아 있어도 현재 비용 합계에서 제외합니다. 해당 경로와 크기는 결과에 남습니다.

초기 측정의 카메라는 실제 플레이어가 매 프레임 회전 처리를 끝낸 전방(-Z)입니다. 같은 위치의 변경 전후 비교에서는 그 구도를 유지하고 각 JSON의 실제 카메라 변환을 대조합니다. 이동 시험은 원래 마우스 시점과 동일한 플레이어 몸의 yaw를 사용해 게임의 반동 갱신 후에도 회전이 유지되는지 검사합니다.

사용 중인 게임과 파이프라인 캐시가 겹치지 않도록 비교 프로젝트는 별도 `user://` 경로를 지정합니다. 원본 스크립트·셰이더·프로젝트 설정은 해시와 함께 보존하고, 벤치마크의 `override.cfg` 설정과 해시는 별도로 기록합니다. 큰 가져오기 결과는 읽기 전용 심볼릭 링크로 공유하며 이 복사본에서 에디터·가져오기를 실행하지 않습니다. 기존 사용자 캐시를 삭제하거나 수정하지 않습니다. 파이프라인 캐시는 격리된 경로에서 켜서 반복 측정의 초기 컴파일을 재사용합니다.


병목 분리에는 `PERFORMANCE_QA_DIAGNOSTIC=effects PERFORMANCE_QA_CASES=hideout_hearth PERFORMANCE_QA_RESOLUTION=720p`를 사용합니다. 같은 실제 장면을 한 번 만든 후 기본값 → SSIL만 끔 → 세계 그림자만 끔 → SSAO만 끔을 측정합니다. 각 단계는 원래 설정으로 복원한 다음 하나만 바꾸며, 첫 90프레임/나머지 30프레임 예열 뒤 같은 수의 프레임을 기록합니다. 이는 원인 조사 전용으로 본편 기본값을 바꾸지 않습니다. 실제 옵션·그림자 등 수와 `diagnostic_only`를 매니페스트에 표시합니다.

`PERFORMANCE_QA_CAMERA_POLICY=target`은 지정 지점을 실제 플레이어 몸·머리로 바라보는 별도 구도입니다. 물의 화면 비중을 조사할 때 사용할 수 있으며 변경 전후 모두 같은 정책으로 별도 측정해야 합니다. 초기 전방 구도와 직접 합쳐 성능 향상으로 계산하지 않습니다. CPU 부하 스냅샷과 정적 MultiMesh GPU 제출 검증도 측정 구간 밖에서 수행합니다.

`python3 tests/prepare_performance_project.py <새 비교 폴더>`는 실행 없이 현재 소스와 변경 가능한 외부 셰이더·LOD를 보존합니다. 기존 폴더는 덮어쓰지 않습니다. `--source`로 보존한 원본 프로젝트를 선택할 수 있고 모든 스크립트와 벤치마크 재정의의 해시를 `benchmark_provenance.json`에 남깁니다. 기본 별도 사용자 경로 `CodexPerformanceBaseline01`은 순차 비교에만 공유하며 사용자 게임 캐시와 분리됩니다.

## 실제 연금술 제조 화면

`alchemy_preview.gd`도 검토된 허용 목록에 포함됩니다. `ALCHEMY_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=300 ./tests/run_embedded_preview.sh alchemy_preview.gd`로 원본 `AlchemyOverlay`와 생산용 3D 작업대를 촬영합니다. `--embedded`, 더미 오디오, 낮은 우선순위와 외부 입력 비활성화를 유지하며 창·커서·포커스·사용자 데스크톱을 조작하지 않습니다.

별도 인벤토리로 실제 물병 버튼에 뷰포트 내부 합성 클릭을 보내고, 분쇄·가열·증류·완성·실패를 본편의 동일한 제조 함수로 진행합니다. 전경·물 붓기·절구 근접·가루 투입·가열·증류·결과·확대 조제서·작은 화면을 저장합니다. 조작 함수에 정해진 시간을 주는 재현 시험이며 사람의 실시간 숙련도를 판정하는 시험은 아닙니다.

출력은 `artifacts/visual_qa/alchemy/<반복 이름>/`이며 기존 폴더는 덮어쓰지 않습니다. `capture_manifest.json`에 실제 렌더러·배합 상태·원본 소스와 팔 모델 해시·로컬 버튼 클릭·원정/커서 보존·실패 목록이 있습니다. 성공 표식은 `ALCHEMY PREVIEW PASS:`입니다. 새 화면을 확인하기 전에 `./tests/run_headless_tests.sh alchemy_system alchemy_overlay alchemy_visual alchemy_test_room`을 실행하세요.

## 실제 대장간 제작 화면

`blacksmith_preview.gd`는 본편 `BlacksmithOverlay`와 `blacksmith_visual.gd`를 별도 1280×720 뷰포트에 구성합니다. 은신처나 원정을 시작하지 않고 별도 인벤토리를 만들어 실제 제작 함수로 가열·단조·담금질·완성과 개조를 진행합니다. 공방 전경, 화로와 풀무, 모루 타격, 담금질, 손잡이, 칼날 보강, 천공, 룬 삽입, 실제 플레이어의 완성 검 장착까지 아홉 상태를 실제 렌더러로 촬영합니다.

```sh
./godot-game/tests/run_headless_tests.sh smithing_system blacksmith_overlay blacksmith_visual blacksmith_test_room
BLACKSMITH_QA_ITERATION=iteration_01 ./godot-game/tests/run_embedded_preview.sh blacksmith_preview.gd
```

출력은 `godot-game/artifacts/visual_qa/blacksmith/<반복 이름>/`이며 기존 폴더를 덮어쓰지 않습니다. 게임 코드·공유 팔 모델·생성 목표 이미지의 해시를 시작과 종료 때 대조하고 원정 스냅샷과 커서 모드의 보존을 확인합니다. PNG는 게임 뷰포트의 결과이며 사용자 데스크톱을 캡처하지 않습니다. 목표 이미지는 미술 참고 자료이고 실제 게임 화면으로 간주하지 않습니다.

제작법 버튼의 클릭은 이 격리 뷰포트 안으로만 합성 마우스 이벤트를 전달합니다. 외부 입력 처리·오브젝트 선택·오디오 리스너를 끄고 오디오를 음소거하며, OS 창·포커스·마우스 캡처·커서 이동은 사용하지 않습니다. 타격과 풀무 등 후속 작업은 본편의 같은 작업 함수를 호출합니다. 따라서 버튼과 제작 화면의 연결 및 실제 렌더 결과를 확인하지만 하드웨어 입력이나 OS 포커스 검증을 대신하지 않습니다.

미완성 작업을 닫았다 다시 여는 동작과 일반 작업대 조사·테스트룸 F2 복귀·초기화·원정 복원은 헤드리스 통합 검증이 담당합니다. 숨김 촬영은 작업 장면의 픽셀을 평가하는 단계이며, 자동 성공 표식만으로 참고 영상과 동일한 외형이나 게임플레이라고 판단하지 않습니다.

## 전체 1인칭 동작 비교

`first_person_motion_preview.gd`는 기존 팔 촬영의 격리 뷰포트와 실제 `DungeonPlayer` 생성 함수를 재사용합니다. 무거운 동굴 장면을 생성하지 않고 매 상태마다 새 플레이어·가방·표시 무기를 만듭니다. 검 준비·강공격·타격·회수, 방패 대기·가드·피격, 활 대기·절반/완전 당김·발사, 철퇴 대기·근접·회전·투척·회수, 지팡이 대기·시전, 횃불 안전지대·걷기·달리기, 상자 접촉·뚜껑 들기의 **24장**을 1280×720으로 촬영합니다.

```sh
./godot-game/tests/run_headless_tests.sh first_person_motion_preview first_person_motion_test_room
FIRST_PERSON_MOTION_QA_ITERATION=iteration_01 GODOT_PREVIEW_TIMEOUT_SECONDS=300 ./godot-game/tests/run_embedded_preview.sh first_person_motion_preview.gd
```

출력은 `godot-game/artifacts/visual_qa/first_person_motion/<새 반복 이름>/`이며 반복 이름을 반드시 지정해야 합니다. 기존 폴더는 덮어쓰지 않습니다. 각 이미지와 `capture_manifest.json`에 실제 무기·보조 장비·횃불 상태, 전투 단계·시간·당김·회전, 손과 장비 변환, 카메라, 자원 수치와 원본 해시를 기록합니다. 검 단독은 실제 인벤토리의 방패 해제, 방패 비교는 실제 장착을 사용합니다. 횃불 계열 외에는 실제 횃불을 끕니다. 기존 코드가 꺼진 횃불의 형상이나 손을 계속 보여준다면 그 결과를 숨기지 않고 변경 전 화면에 남깁니다.

제작한 별도 정지 자세를 그리지 않고 본편 공격 시작·확정, 활 당김·발사, 철퇴 회전·발사와 실제 투사체 진행, 가드 피격, 주문 시전, 상자 조사 함수를 호출합니다. 재현할 전투 시간과 이동 속도를 지정한 뒤 같은 표시 함수를 일정 간격으로 진행합니다. 실제 이동 입력은 읽지 않으며 걷기·달리기는 정해진 속도를 표시 코드에 공급하는 비교입니다. 물리 이동·하드웨어 입력 전체를 대신하는 시험은 아닙니다. 사용하지 않는 상자는 발사 경로 밖에 두어 숨겨진 상자 충돌로 투척이 조기에 회수되지 않게 합니다.

연결된 움직임도 확인하려면 `FIRST_PERSON_MOTION_QA_SEQUENCE=1`을 함께 지정합니다. 정지 화면 24장 다음에 `sequences/sword_cycle/`, `sequences/bow_draw_release/`, `sequences/flail_spin_throw_return/`에 각각 2초 동안 초당 12프레임, 시작 프레임을 포함한 PNG 25장을 저장합니다. 실제 공격·당김·회전을 시작한 뒤 본편의 행동 타이머와 전투 진행 함수를 1/60초 간격으로 호출하고, 실제 화살·철퇴 투사체도 같은 간격으로 진행합니다. 검 준비에서 타격·회복까지, 완전 당김에서 화살 소비·발사·반동 회복까지, 철퇴 회전에서 투척·회수까지의 상태와 자원을 프레임마다 기록합니다. 연속 촬영은 시간이 더 걸리므로 `GODOT_PREVIEW_TIMEOUT_SECONDS=600`을 사용할 수 있습니다.

매 프리뷰는 `TestRoomSandbox`의 별도 원정에서 주문 상태를 준비하고 종료 시 원래 원정 스냅샷과 인벤토리 참조를 복원합니다. 참조 비교와 별도로 원본 가방 슬롯·장착 ID·개별 장비 정보를 촬영 전후 SHA-256으로 비교해 같은 객체 내부의 변경도 검출합니다. 뷰포트의 외부 입력과 오브젝트 선택, 플레이어의 입력·자동 물리 처리를 끄고 소리를 음소거합니다. 실제 공격 함수를 통해 생긴 화살·마법·철퇴는 검사에 필요한 지점까지 진행한 뒤 멈춥니다. 커서 모드를 바꾸거나 사용자 데스크톱을 캡처하지 않습니다. 실제 사용하는 촬영 보조 함수·행동 프로필·투사체·표면/불꽃 스크립트·무기/방패/횃불/상자 모델과 재질, `assets/ai/first_person_motion/`의 다섯 목표 이미지 해시가 촬영 도중 달라지면 실패하며, 새 모션 모듈이 없었던 변경 전 상태도 기록에 명시합니다.

성공 표식은 `FIRST PERSON MOTION PREVIEW PASS:`입니다. 실제 픽셀과 생성 목표를 사람이 비교하는 단계는 자동 동작·원정 보존 검증과 구분합니다. 목표 이미지와 같은 모델이나 동일한 움직임을 달성했다는 판정은 성공 표식만으로 내리지 않습니다.

## 은신처 중앙 화롯불 요리

`hideout_cooking_preview.gd`는 실제 은신처의 `_build_world()`로 공간·조명·화롯불·조리 기구를 만들고, 별도 뷰포트에 본편의 `HideoutCookingController`와 요리 UI를 연결합니다. 은신처의 `_ready()`나 일반 장면 입장은 실행하지 않습니다. 플레이어의 입력·물리 처리와 외부 입력·오디오 리스너를 끄고, 시험용 원정만 사용합니다. OS 창·포커스·마우스 캡처·커서 이동은 사용하지 않습니다.

```sh
./tests/run_headless_tests.sh hideout_cooking_controller hideout_cooking_visual hideout_cooking_test_room
HIDEOUT_COOKING_QA_ITERATION=iteration_01 ./tests/run_embedded_preview.sh hideout_cooking_preview.gd
```

새 폴더 `artifacts/visual_qa/hideout_cooking/<반복 이름>/`에 조리 기구 전경, 조리법 메뉴, 실제 고기구이 진행, 식사 완료, 스튜 진행, 작은 메뉴 여섯 장을 저장합니다. 조리법 버튼은 격리 뷰포트 내부의 합성 클릭으로 선택하며, 본편 조리 함수에 시간을 전달해 재료 소비·완료 식사를 재현합니다. 원정 스냅샷과 원래 가방·커서, 촬영 중 소스 해시 불변을 검사합니다. 매니페스트에는 실제 렌더러·화면 해시·각 시점의 실제 조리 상태·버튼 클릭 결과·실패 목록을 기록합니다. 성공 표식은 `HIDEOUT COOKING PREVIEW PASS:`이며, 실제 E 조사·Esc·반복 F2 복귀와 초기화·원래 원정 복원은 앞의 헤드리스 통합 검증이 담당합니다.

## 판매용 술 증류와 중개인 거래

`distillation_preview.gd`는 본편 `AlchemyOverlay`의 물약·술 선택과 실제 열·약초·증류·병입 동작을 사용합니다. 같은 시험 가방을 본편 `MerchantScreen`의 거래 UI에 전달해 실제 완성주 판매와 크라운 지급까지 확인합니다. 중개인의 장면 진입 함수만 안전한 어댑터로 바꿔 포커스 이동과 커서 변경을 막으며, 화면 구성·물품 선택·판매 함수는 본편 코드를 실행합니다.

```sh
./tests/run_headless_tests.sh distillation_economy distillation_test_room
HIDEOUT_DISTILLING_QA_ITERATION=iteration_01 ./tests/run_embedded_preview.sh distillation_preview.gd
```

새 폴더 `artifacts/visual_qa/distillation/<반복 이름>/`에 제조 원가·수익 안내, 포도주 붓기, 약초 투입, 실제 증류 진행, 완성 술, 실제 상인 판매, 960×540 메뉴의 일곱 장을 기록합니다. 술 선택·포도주·병입·판매는 격리된 뷰포트 내부의 버튼 클릭으로 검증합니다. 외부 입력·소리·데스크톱 캡처 없이 원래 원정·가방 내용·테스트룸·커서를 보존하며, 촬영 중 제작 코드의 해시가 바뀌면 실패합니다. 성공 표식은 `DISTILLATION PREVIEW PASS:`입니다.

## 검 공격 3종 영상

`reference_sword_motion_preview.gd`의 `REFERENCE_SWORD_MOTION_QA_SCOPE=quick_attacks`는 실제 방패 수납 후 양손으로, `quick_attacks_shield`는 방패 착용 상태로 정베기·역베기·내려베기만 촬영한다. 둘 다 짧은 클릭의 실제 전투 시계를 사용하며 각 공격의 시작부터 복귀까지 60fps 시퀀스를 저장한다. 먼저 `./tests/run_headless_tests.sh reference_sword_cut_preview`로 세 공격과 격리·복원을 확인하고, 기존 숨김 실행기에 새 `REFERENCE_SWORD_MOTION_QA_ITERATION`을 지정한다. 게임 모션이나 공격 수치를 변경하는 옵션은 아니다.

## 왼팔 붕대 사용 모션

`bandage_motion_preview.gd`는 검토된 `player_arm_preview.gd`의 격리 뷰포트 구성 함수를 사용합니다. 본편 `use_consumable()`로 붕대를 사용하고 `_update_viewmodel()`에 1/30초를 공급하여 실제 손·롤·천을 촬영합니다. 모든 플레이어 입력·자동 물리 처리를 끄고, 외부 입력·포커스·커서 조작 없이 별도 원정과 원래 세션 복원을 확인합니다. `BANDAGE_QA_STILLS=1`은 0.4초 간격의 15장 정지 검토입니다. 기본은 30fps 176장이고 `artifacts/visual_qa/bandage_forearm/low_tear_08/`에 저장합니다. 성공 표식은 `BANDAGE MOTION PREVIEW PASS:`입니다. `bandage_motion`, `body_health_routes`, `body_health_test_room` 헤드리스 검증 후 숨김 실행기를 사용합니다.


## 던전 전투 HUD

`dungeon_combat_hud_preview.gd`는 검토된 `performance_scene_factory.gd`의 던전 어댑터로 실제 원정 장면을 별도 SubViewport에 생성합니다. 네이티브 입력을 바꾸는 진입만 대체하고 실제 `_spawn_player()`에서 생성된 전투 HUD를 촬영합니다. 플레이어/적 자동 처리·외부 입력을 중단하고 실제 물품 사용 함수로 회복·식사·물·저주 치료를 진행합니다. 인체와 경고를 별도 목업으로 바꾸지 않습니다. 건강/경고 1280×720과 치료 후 960×540을 저장합니다.

먼저 `./tests/run_headless_tests.sh dungeon_combat_hud dungeon_combat_hud_preview body_health_test_room health_panel_input`을 실행합니다. 이후 `COMBAT_HUD_QA_ITERATION=iteration_01 ./tests/run_embedded_preview.sh dungeon_combat_hud_preview.gd`로 새 폴더 `artifacts/visual_qa/dungeon_combat_hud/<반복 이름>/`에 실제 PNG·소스 해시·상태·보존 결과를 기록합니다. 원래 원정/가방/커서/샌드박스와 촬영 도중 소스 불변을 검사하고 사용자 데스크톱·포커스·입력은 조작하지 않습니다. 완료 표식은 `DUNGEON COMBAT HUD PREVIEW PASS:`입니다.


아이템 사용 시간 후속 검증은 같은 전투 HUD 프리뷰의 4~6번 화면을 사용합니다. `04_item_use_countdown`은 실제 회복약 사용 시작 후 1.2초를 진행한 남은 1.8초, `05_bandage_countdown_small`은 실제 왼팔 붕대 모션과 남은 시간, `06_item_use_cancelled`는 실제 F 동작의 공통 함수로 취소한 결과입니다. 타이머 숫자를 촬영용으로 지정하지 않고 `begin_item_use()`와 `advance_item_use()`의 실제 상태를 사용합니다. 수량 미소비·취소 결과와 UI 영역을 확인합니다. 해당 촬영 전 `timed_item_use`, `body_health_routes`, `dungeon_combat_hud_preview`, `bandage_motion`, `timed_item_use_room`의 헤드리스 검사를 실행합니다. 전체 건강 상태 장면 이동은 별도 `body_health_test_room`으로 확인합니다. 모션 전용 낮은 수준의 `use_consumable()` 검사는 기존 즉시 커밋 함수를 검증하며, 실제 소지품/가방 입력은 `begin_item_use()`를 거칩니다.

물약 모션은 `POTION_QA_ITERATION=<새이름> ./tests/run_embedded_preview.sh potion_motion_preview.gd`로 촬영합니다. 기존 팔 프리뷰의 입력·오디오 비활성 SubViewport와 TestRoomSandbox를 재사용하며 실제 시간 사용·완료와 소스/세션 보존을 검사합니다. 출력은 `artifacts/visual_qa/potion_drink/<새이름>/`의 실제 사용 시간 + 0.7초 분량(현재 219프레임) 및 manifest.json, 성공 표식은 `POTION MOTION PREVIEW PASS:`입니다. 먼저 `potion_motion` 헤드리스 검사를 통과해야 합니다.

물약 자세 비교에는 같은 실행기에 `POTION_QA_POSE_STUDY=1`을 전달할 수 있습니다. 실제 손·병 에셋의 접촉 관계를 보존한 채 기울기·손목 회전 9개 후보를 숨김 렌더로 비교하며, `diagnostic_pose_study: true`와 후보 값을 매니페스트에 기록합니다. 이 비교 이미지는 완성된 본편 모션으로 제공하지 않습니다. 자세를 본편에 반영한 뒤 회귀 검사를 통과하고, 해당 옵션 없이 전체 실제 모션을 다시 촬영해야 합니다.


## 폐광 동쪽 창고 적 복구 / Restored eastern-store enemy

`CAVE_STORE_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=360 ./tests/run_embedded_preview.sh cave_store_enemy_preview.gd`는 기존 performance scene factory의 안전한 폐광 진입을 재사용한다. 설치된 에셋에 맞는 실제 창고 적(크리프 또는 기본 검지기)과 6명 배치를 확인하고 창고 위치의 게임 화면을 촬영한다. 외부 입력·자동 처리·오디오를 끄고 원정/커서를 보존한다. 먼저 `cave_dungeon`, `test_room`을 실행한다. 성공 표식: `CAVE STORE ENEMY PREVIEW PASS:`.

This uses the audited mine adapter and production geometry, actors, camera and HUD, with native input/audio disabled. It verifies the installed Creep (or original warden fallback) and six-enemy encounter count, then saves an actual GPU image and checks session/cursor preservation.


## 크리프 원본 애니메이션 / Creep source animations

먼저 `GODOT_TEST_TIMEOUT_SECONDS=600 ./tests/run_headless_tests.sh creep_enemy cave_dungeon test_room`을 실행한다. 로컬 크리프 설치가 있어야 모델·애니메이션 검증을 실행한다. 미설치 검증은 대체 적과 설치 안내만 확인하며 에셋 검사를 생략했다고 명시한다.

`CREEP_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=600 ./tests/run_embedded_preview.sh creep_enemy_preview.gd`는 흰 조명 아래 앞·옆·뒤, 걷기·물기·양손 타격·피격·사망과 실제 폐광 창고 장면을 GPU로 촬영한다. 원본 애니메이션의 접촉 시점을 본편 상태 코드로 선택한다. 창·하드웨어 입력·커서·오디오를 건드리지 않으며 원래 원정을 복원한다. 출력은 `artifacts/visual_qa/creep/<새 이름>/`, 성공 표식은 `CREEP ENEMY PREVIEW PASS:`이다. 정지 시점의 렌더 검사이며 사용자가 직접 조작한 플레이 영상으로 표현하지 않는다.

Run the headless checks first. Installed mode checks the source rig and animations; missing-asset mode explicitly skips those checks and verifies the public-clone fallback. The embedded preview renders nine source poses and the production mine encounter without opening a window or changing the cursor, and restores the original session. These are actual GPU stills, not a claim of manual playtesting.

크리프 모션 영상은 `creep_motion_reel` 헤드리스 검사 후 `CREEP_QA_SEQUENCE=1 CREEP_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=600 ./tests/run_embedded_preview.sh creep_enemy_preview.gd`로 촬영한다. 실제 본편 포즈 계산 함수를 30fps로 샘플하며 5개 적용 모션과 비교용 원본 사망 클립을 한글·영문 이름과 함께 1280×720 PNG 연속 프레임으로 저장한다. 걷기는 제자리이며 타격 대상·AI 이동·피해 판정은 영상에서 실행하지 않는다. 물기 2회·양손 연타 3회·피격 2회를 보여주고 사망 마지막 자세를 유지한다. 캡처 전후 모델·본편 포즈 코드 해시와 원정·커서 보존을 확인한다. 원본 미연결 클립 11개나 새 게임 기능을 보여주는 옵션이 아니다.

For a motion reel, run `creep_motion_reel` first, then use `CREEP_QA_SEQUENCE=1` with the embedded Creep preview. It records five current gameplay clips and the retained source death clip at 30fps and 1280×720 with bilingual labels, using the production posing code. Walk is in place; AI travel and combat hits are not simulated in this presentation. Source hashes, expedition and cursor are preserved. Encode `frames/%05d.png` at exactly 30fps without optical-flow interpolation.


## 크리프 래그돌 / Creep ragdoll

`creep_ragdoll`, `creep_ragdoll_trial`, `creep_enemy` 자동 검사 후 `CREEP_RAGDOLL_QA_ITERATION=<새 이름> GODOT_PREVIEW_TIMEOUT_SECONDS=600 ./tests/run_embedded_preview.sh creep_ragdoll_preview.gd`를 사용한다. 실행기가 `--fixed-fps 30`을 지정하고 실제 60 Hz 물리를 프레임마다 2회 진행한다. 실제 `receive_hit()`로 사망시켜 반응·낙하·벽/바닥 접촉·안정화 과정을 1280×720 연속 프레임으로 기록한다. 스튜디오 시험 장면이며 본편 수동 조작 영상으로 표현하지 않는다. 포즈를 수동 샘플하거나 생성 이미지로 대체하지 않는다. 원정·커서·원본 해시를 보존하고 출력은 `artifacts/visual_qa/creep_ragdoll/<이름>/`에 저장한다. 성공 표식은 `CREEP RAGDOLL PREVIEW PASS:`다.

After the relevant headless checks, the audited embedded runner captures continuous production death at 60 Hz physics and fixed 30 fps. Each saved frame spans exactly two physics ticks. The isolated studio uses real fatal hits, floor/wall collision and settling, preserves session/cursor/source hashes, and produces actual GPU frames rather than sampled death-animation poses.
