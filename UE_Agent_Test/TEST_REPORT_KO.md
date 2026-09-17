# UE_Agent_Test 실제 제작·실행 시험 보고서

작성일: 2026년 9월 5일, 한국 시간. 결과 JSON 파일명의 시각은 UTC, 실행 로그 파일명의 시작 시각은 한국 시간이다.

## 현재 판정

**부분 성공 — 방과 이동·문 기능을 만들고 실제 편집기 플레이의 자동 검사 47개를 모두 통과했지만, 일반 화면에서의 macOS 키보드·마우스 조작은 확인하지 못했다.**

최종 재검사에서 실제 그림을 만드는 편집기 플레이가 저장된 맵을 다시 열었고, 47개 검사와 화면 9장 저장을 모두 완료했다. 플레이를 먼저 끝내고 편집기를 정상 종료하도록 고친 뒤 종료까지 재확인했다. 실행 프로세스 종료 값은 0이었다. 엔진 시작 시 별도 기본 진단의 `Condition failed` 15개도 원인을 확인했다. 한국어로 번역된 결과를 엔진 진단이 고정된 영어 문장과 비교하여 실패한 것이다. 같은 진단을 그 실행에 한해서 영어로 돌리자 모두 통과했다. 엔진 파일과 언어 설정은 바꾸지 않았으므로 한국어 실행에는 이 기록이 남을 수 있다. 이는 게임 기능 검사 47개의 실패가 아니다.

**일반 편집기 화면을 클릭하고 실제 macOS 키보드·마우스를 전달하는 검사는 아직 하지 않았다.** 자동 입력 결과를 이 검사와 혼동하면 안 된다. 이전 모델과 같은 조건으로 비교하지 않았으며, 이번 작은 기능의 결과로 언리얼 게임 전체를 자동 제작할 수 있다고 판단하지 않는다.

## 프로젝트와 원본 보호

프로젝트 폴더: `/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test`

- 프로젝트 파일: [UE_Agent_Test.uproject](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/UE_Agent_Test.uproject>)
- 실제 저장된 맵: [Content/Maps/TestRoom.umap](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Content/Maps/TestRoom.umap>)
- 이 환경의 시작 파일: [LaunchEditor.command](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/LaunchEditor.command>)
- 사용 설명: [README_KO.md](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/README_KO.md>)

이 폴더는 앞선 시도에서 새로 만든 시험용 폴더이며, 이번에는 그 준비 파일에서 작업을 이어갔다. 앞선 보고서는 [first_attempt_TEST_REPORT_KO.md](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/first_attempt_TEST_REPORT_KO.md>)에 보존했다. 기존 Godot 게임, 이전 웹 게임, 사용자 에셋은 수정하거나 삭제하지 않았다. 유료 에셋 구매, 엔진 업그레이드, 디스크 포맷이나 시스템 설정 변경은 하지 않았다.

기본 엔진 기능과 도형으로 방·문·조명·안내 화면을 만들었다. 구현은 `Source/UE_Agent_Test` 안에 있으며 사용자에게 블루프린트 연결이나 모델링을 요구하지 않는다. 편집기용 게임 모듈 `Binaries/Mac/libUnrealEditor-UE_Agent_Test.dylib`와 맵을 저장했다. 독립 실행 파일은 만들지 않았다. 전투·적 AI·인벤토리·멀티플레이·파괴 효과도 추가하지 않았다.

## 직접 확인한 환경과 연결 도구

| 확인 대상 | 실제 확인 결과 |
|---|---|
| 운영체제 | macOS 26.6.2, Apple Silicon |
| 설치 엔진 | Unreal Engine 5.8.2, 빌드 56702186 |
| 설치 위치 | `/Volumes/T7/UE 58/UE_5.8` |
| 실제 파일 | `Engine/Build/Build.version`, `Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor`, `Engine/Binaries/Mac/UnrealEditor-Cmd` 존재 |
| 설치 완료 | Launcher 설치 기록과 실제 파일 일치. 설치 미완료 표시 없음. Launcher 화면의 5.8.2와 실행 버튼도 확인 |
| 파일 작업 | 시험 프로젝트 생성·수정·빌드·맵 저장·다시 읽기 가능 |
| 실제 엔진 실행 | 게임 세계를 실행했고, 별도 편집기 프로세스에서 실제 Play In Editor 세계도 시작 |
| 실제 렌더링 | Metal 숨김 렌더링으로 플레이 화면을 저장. 예상 화면이나 생성 이미지를 사용하지 않음 |
| 사용한 도구 | 로컬 파일·프로세스 도구, 설치된 Unreal 명령줄·편집기 기능, CUA 앱 화면 읽기, 이미지 파일 확인 |
| 일반 화면 입력 | 언리얼 일반 창에서의 macOS 키보드·마우스 전달은 미확인. Blender 연결을 언리얼 연결 근거로 사용하지 않음 |

환경 기록: [environment_after_install.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/environment_after_install.json>)

### 이 컴퓨터에서 시작 파일이 필요한 이유

T7은 대소문자를 구별하는 HFS+ 디스크다. 설치된 macOS 언리얼은 이 디스크를 작업 기준 위치로 삼으면 시작 과정에서 이를 거부한다. 멈춘 프로세스의 상태와 설치된 엔진 소스를 대조하여 원인을 확인했다. 우리 작업에서 시작한 해당 프로세스만 종료했으며, 종료 요청에 반응하지 않은 경우 해당 프로세스에 한해 강제 종료했다.

엔진을 다시 설치하거나 고치는 대신, 시험 프로젝트 안의 `RuntimeHost/Engine/Binaries/Mac`를 내부 APFS 디스크의 실행 기준 폴더로 마련했다. 엔진 자료를 가리키는 링크 1,258개를 만들었고 실행 중 기록하는 `Saved`, `Intermediate`, `DerivedDataCache` 폴더는 로컬에 두었다. 설치 엔진의 파일 내용은 수정하지 않았다. 이 방식은 이 컴퓨터에서 확인한 시험용 구성이며 외장 디스크 형식 자체를 바꾼 것은 아니다.

시작 도우미는 임시 영문 경로와 `-basedir`를 사용한다. 공백·한글 경로가 맵 주소로 잘못 해석되던 문제도 피한다. **이 컴퓨터에서는 프로젝트 파일을 단독으로 두 번 클릭하는 대신 `LaunchEditor.command`로 시작해야 한다.** T7을 연결하고 현재 엔진·프로젝트 경로를 유지해야 한다.

근거: [filesystem_blocker.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/filesystem_blocker.json>), [map_start_sample_02.txt](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/map_start_sample_02.txt>), [runtime_host_links.json](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/runtime_host_links.json>)

## 확인 방법의 구분

1. **실제 플레이 화면과 입력으로 확인:** 일반 창을 클릭하고 macOS 입력을 보내는 검사는 아직 하지 않았다.
2. **언리얼 실행 중 자동 검사로 확인:** 실행 중인 플레이어의 실제 입력 처리 경로에 W/A/S/D, E, 마우스 방향 입력을 전달했다. 이후 위치·시선·문 각도·바닥 접촉·통과 결과를 측정했다. 문 상태를 강제로 바꾸거나 문 열기 동작을 직접 호출하지 않았다.
3. **실제 렌더링 화면 캡처로 확인:** 편집기 플레이에서 만들어진 화면을 저장하여 방과 안내 문구를 확인했다. 화면은 실제 실행 증거지만 한 장만으로 이동·충돌 전체를 입증하지는 않는다. 이동과 충돌은 위 자동 실행 결과와 함께 판단한다.
4. **코드·설정만 확인:** 실행 경로와 저장 설정 등은 파일 검토도 했다. 파일 검토만으로 실제 작동을 확인했다고 판정하지 않는다.

자동 검사는 각 상황의 출발점으로 플레이어를 옮기고 시선을 맞추는 준비 동작을 사용한다. 준비 동작은 결과 파일의 `setup_events`에 따로 기록하며 이동·마우스 조작 증거에 포함하지 않는다. 벽·문 통과 검사는 준비 이후 실제 이동 입력을 유지하여 확인했다.

## 요청한 10개 항목

최종 실제 편집기 플레이 자동 실행에서 **47개 모두 통과**했고 종료까지 확인했다. “정상 확인”은 표에 적힌 방법에서 확인했다는 뜻이며 일반 화면의 물리 입력 확인을 뜻하지 않는다.

| 번호 | 확인할 내용 | 현재 결과 | 실제 확인 방법·한계 |
|---|---|---|---|
| ① | 프로젝트를 열고 플레이하면 방이 보임 | 정상 확인 | 별도 편집기에서 저장 맵을 읽고 실제 플레이 시작. 캡처에서 바닥·벽·천장·문 확인 |
| ② | W/A/S/D로 실제 이동 | 정상 확인 | 4개 키 입력 후 각 방향 위치 변화 측정. 순간이동 준비 동작과 구분 |
| ③ | 마우스로 시점 이동 | 정상 확인 | 세로 검사 입력 횟수를 수정한 뒤 입력 12회씩 전달. 실제 편집기 최종 재실행에서 가로·세로 시점 변화가 모두 통과 |
| ④ | 벽을 통과하지 않고 바닥 아래로 떨어지지 않음 | 정상 확인 | 정면·옆 벽을 향한 지속 이동이 경계 앞에서 멈춤. 검사 전체에서 높이와 바닥 접촉 확인 |
| ⑤ | 닫힌 문이 통과를 막음 | 정상 확인 | 닫힌 문을 향해 W를 유지했으나 문 앞에서 정지 |
| ⑥ | 가까이서 E로 열고 열린 문 통과 | 정상 확인 | E 입력 후 -100°로 열림. 이어 W로 실내에서 바깥 바닥까지 이동 |
| ⑦ | 다시 E로 닫고 닫힌 문이 통과를 막음 | 정상 확인 | 바깥에서 E 입력으로 닫은 뒤 W로 접근해 문 앞에서 정지 |
| ⑧ | 멀리서·벽 너머에서 조작 불가 | 정상 확인 | 원거리, 시선이 다른 방향, 가까우나 벽에 가린 위치에서 각각 E 입력 거부 |
| ⑨ | 10회 여닫기·빠른 E 반복 후에도 유지 | 정상 확인 | 10회 완전 개폐, 빠른 E 10회, 이후 닫힌 문 차단과 열린 문 통과까지 재검사 |
| ⑩ | 저장 후 다시 열어도 유지 | 정상 확인 | 맵 저장 후 별도 편집기 프로세스가 TestRoom을 다시 열어 47개 모두 통과. 재실행 전후 맵·설정·실행 파일 내용도 동일함을 확인 |

추가 확인: 플레이어가 회전 경로에 서 있을 때 E로 닫으면 문이 앞에서 멈췄다. W로 자리를 비우자 닫기가 이어졌다. 실제 캡처에서 “E: 문 열기”와 “E: 문 닫기”의 한글 표시도 확인했다.

## 실행 기록과 발견·수정 내용

| 단계 | 결과와 조치 | 실제 기록 파일 |
|---|---|---|
| 초기 빌드 | 5.8 빌드 설정 불일치, 생성 헤더 준비 순서, 한 번만 도는 반복문 경고로 실패. 설정과 코드 수정 후 빌드 성공 | `build.log`, `build_02.log`, `build_03.log`, `build_04.log` |
| 외장 엔진 직접 시작 | 대소문자 구별 파일 시스템 검사에서 중단. 위 RuntimeHost 실행 기준 폴더로 해결 | `filesystem_blocker.json`, `map_start_sample_02.txt` |
| 첫 맵 저장 | TestRoom 실제 저장 통과 | `map_creation_02_engine.log` |
| 첫 화면 없는 게임 실행 | 47/47 통과. 시작 시 경로 따옴표 문제로 기본 맵 주소로 복구한 경고가 있어 시작 도우미 수정 | `runtime_20260905_134459.json`, `headless_20260905_224219_engine.log` |
| 첫 편집기 렌더링 실행 | 46/47 통과. 마우스 세로는 4.25° 움직였지만 검사 기준 미달. 시간만으로 끝내던 검사에서 입력 12회 전달 후 처리 대기로 수정 | `runtime_20260905_135202.json`, `pie-capture_20260905_224701_engine.log` |
| 시각 점검·최종 빌드 | 첫 화면이 어두워 조명 강화. 문틀 여유도 확보. 수정 후 빌드 성공, 맵 다시 저장 성공 | `build_07.log`, `build-map_20260905_225729_engine.log` |
| 수정본 편집기 재검사 | 47/47 통과했으나 편집기 종료 중 오류 발생. 플레이를 먼저 끝낸 뒤 편집기를 종료하도록 수정 | `runtime_20260905_140536.json`, `pie-capture_20260905_230126_engine.log` |
| 최종 빌드·재실행 | 빌드 성공. 실제 편집기 플레이 47/47 통과, 화면 9장 저장. 플레이와 편집기 정상 종료 확인 | `build_08.log`, `runtime_20260905_141708.json`, `pie-capture_20260905_231333_engine.log` |
| 별도 엔진 시작 진단 | 한국어 결과와 고정된 영어 예상 문장이 달라 3개 진단·15개 조건 실패. 동일 진단을 영어로 실행하자 모두 통과. 언어는 해당 실행에만 적용하고 저장하지 않음 | `smoke_diagnostic_20260905_231927_console.log`, `smoke_diagnostic_en_20260905_232711_console.log` |

위 기록의 실제 폴더: `/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence`

주요 파일을 바로 열기:

- [첫 실행 47/47 결과](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/runtime_20260905_134459.json>)
- [첫 편집기 렌더링 46/47 결과](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/runtime_20260905_135202.json>)
- [최종 빌드 성공 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/build_08.log>)
- [수정 맵 저장 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/build-map_20260905_225729_engine.log>)
- [수정본 기능 47/47 및 종료 오류 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/pie-capture_20260905_230126_engine.log>)

- [최종 실제 편집기 기능 47/47 결과](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/runtime_20260905_141708.json>)
- [최종 편집기 실행·정상 종료 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/pie-capture_20260905_231333_engine.log>)
- [재실행 전 파일 내용 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/final_artifact_manifest_before_reopen.json>)
- [재실행 후 같은 내용 유지 확인](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/final_artifact_manifest_after_reopen.json>)

최신 결과의 사본은 `Evidence/runtime_results.json`에 기록되며 다음 실행에서 바뀔 수 있다. 실행별 UTC 시각이 붙은 원본 파일은 별도로 남긴다.

## 엔진 시작 진단의 원인 확인

게임 기능 검사와 별도로, 기본 한국어 실행에서는 엔진 진단 3개가 실패했다. `FUnifiedErrorTest_CreateErrorMessage`가 7개 조건, `FUnifiedErrorTest_CreateErrorMessageWithContext`가 4개, `FStructuredLogFormatTest`가 4개였다. 설치된 한국어 번역 자료의 결과 문장과 엔진 진단이 기대하는 고정 영어 문장을 대조해 차이를 확인했다.

같은 편집기·프로젝트에서 `-culture=en`을 해당 진단 실행에만 전달한 비교에서는 위 3개가 모두 Success였고 `LogAutomationTest: Error`가 0개였다. 한국어·영어 진단 실행 모두 프로세스 종료 값은 0이었다. 시스템이나 편집기의 언어 설정을 저장하지 않았으며 게임 코드와 설치된 엔진도 수정하지 않았다. 이 비교는 원인을 분리하기 위한 것으로, 한국어 플레이 검사 47/47 결과를 영어 검사로 대신한 것이 아니다.

- [한국어·영어 진단 비교 결과](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/engine_startup_diagnostic_comparison.json>)
- [번역 자료와 엔진 진단 문장 대조 분석](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/engine_startup_localization_analysis.md>)
- [언어 비교 진단 후에도 프로젝트 파일 내용 유지](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/final_artifact_manifest_after_diagnostics.json>)
- [한국어 진단 결과 요약](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/engine_startup_diagnostic_ko.json>)
- [한국어 진단 실행 로그](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/smoke_diagnostic_20260905_231927_console.log>)
- [영어 비교 진단 실행 로그](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/smoke_diagnostic_en_20260905_232711_console.log>)
- [영어 실행에만 언어를 적용한 기록](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/smoke_diagnostic_en_20260905_232711_result.json>)
- [최종 기능 검사·종료·미실시 범위 요약](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/final_execution_summary.json>)

## 실제 화면 증거

최종 실제 편집기 실행의 캡처 9장을 `Evidence/screenshots`에 저장했고 결과 JSON에서 파일 존재도 확인했다. 실제 시작 화면과 열린 문 화면을 직접 확인했다. 첫 실행의 어두운 화면은 `Evidence/first_render_screenshots`에 별도로 보존했다. 움직임을 연속 영상으로 촬영하지 않았으며 정지 화면을 동작 전체의 증거로 제시하지 않는다.

- [최종 플레이 시작 화면](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/screenshots/initial_spawn_and_closed_door.png>)
- [닫힌 문과 “E: 문 열기”](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/screenshots/closed_door_blocks_actual_W_movement.png>)
- [열린 문과 “E: 문 닫기”](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/screenshots/open_door_close_prompt.png>)
- [문을 지나 바깥으로 이동한 지점](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/screenshots/open_door_allows_actual_W_passage.png>)
- [빠른 반복 입력 이후 다시 통과한 지점](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/screenshots/door_still_passable_after_repetition.png>)

## 남은 문제와 이번 시험의 범위

- **기능 구현:** 최종 실제 편집기 플레이에서 방·입력·문·충돌 검사 47개를 모두 통과했다. 검사한 범위에서 게임 기능의 오류는 남아 있지 않다.
- **수정하고 재확인한 오류:** 첫 렌더링의 마우스 세로 검사 입력 부족과 이후 편집기 종료 순서 오류를 고쳤다. 최종 재검사에서 마우스 양 방향과 플레이·편집기 정상 종료를 확인했다.
- **원인을 확인한 엔진 진단 기록:** 한국어 실행에서 엔진 자체의 문장 비교 진단 3개가 총 15개 조건 실패를 남겼다. 설치된 한국어 번역과 진단의 고정 영어 문장이 일치하지 않는 문제다. 같은 진단을 영어로 실행하면 모두 통과했다. 엔진을 수정하지 않았으므로 한국어 시작 시 기록이 남을 수 있으나 게임 기능 47개는 모두 통과했다.
- **실행 환경:** T7 디스크 형식 때문에 전용 시작 파일과 연결된 엔진 경로가 필요하다. 새 설치나 디스크 포맷을 요구하지 않았다. 숨김 실제 편집기 실행은 확인했지만 일반 화면 창의 직접 조작은 미확인이다.
- **아직 하지 않은 검사:** 일반 화면 클릭 후 macOS 키보드·마우스 전달, 장시간 플레이, 다른 컴퓨터·엔진 버전에서의 재현은 미확인이다. 사용자 화면의 포커스를 가져오는 검사는 별도로 진행하지 않았다. 검사하지 못한 것을 기능 고장이라고 단정하지 않는다.

일반 화면 입력을 임의로 진행하지 않은 이유는 작업 폴더의 [AGENTS.md](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/AGENTS.md>)에 있는 “불가능하면 사용자의 작업 중 포커스를 빼앗지 말고, 실행 전에 필요성과 예상 영향을 알려 확인받습니다.” 지침이다. 실제 렌더링은 숨김 방식으로 완료했으나 일반 창의 키보드·마우스 조작은 사용자 화면의 포커스와 마우스 캡처에 영향을 주므로 별도 확인 대상으로 남겼다.

이번에 직접 구현하고 실행 검증한 범위는 작은 방과 바깥 바닥, 안전한 1인칭 이동, 거리·시선 제한이 있는 E키 경첩 문, 안내 문구, 저장 후 재실행이다. 다음 기능을 맡기기 전에는 일반 편집기 화면에서 실제 키보드·마우스 입력이 전달되는지 확인하는 것이 남아 있다.
