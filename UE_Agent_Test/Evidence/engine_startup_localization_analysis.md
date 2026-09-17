# 엔진 시작 자체 검사 오류 15개: 한국어 번역과 영어 기대값 비교 분석

이 문서는 UE 5.8.2 설치본의 소스, 실제 한국어 번역 자료, 저장된 실행 로그를 읽어서 확인한 결과다. 분석 과정에서 엔진·번역·사용자 설정은 수정하지 않았고, 별도 언리얼 실행도 하지 않았다.

이후 같은 편집기·맵·숨김 렌더·자동 종료 조건에서 해당 프로세스에만 `-culture=en`을 준 비교 실행이 완료되었다. 아래 영어 실행 로그를 직접 읽어 같은 세 검사의 성공과 해당 오류 0개를 확인했다. 총괄 실행 담당자가 프로세스 종료 코드 0도 확인했다. 엔진 번역이나 사용자 언어 설정을 변경한 결과가 아니다.

## 확인한 실행 증거

로그: [smoke_diagnostic_20260905_231927_console.log](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/smoke_diagnostic_20260905_231927_console.log>)

| 엔진 자체 검사 이름 | 실제 실패 메시지 수 | 해당 로그 위치 |
|---|---:|---|
| `FUnifiedErrorTest_CreateErrorMessage` | 7 | 검사 이름 2090행, 오류 2091–2097행 |
| `FUnifiedErrorTest_CreateErrorMessageWithContext` | 4 | 검사 이름 2098행, 오류 2099–2102행 |
| `FStructuredLogFormatTest` | 4 | 검사 이름 2129행, 오류 2130–2133행 |
| 합계 | **15** | 위 세 검사에서 발생 |

같은 로그 833행에는 `ko-KR`의 언어 자료가 없어 `ko`를 사용한다는 엔진 기록이 있다. 이 15개는 편집기 시작 자체 검사이며, 프로젝트의 방·이동·문 동작 검사 47개와 별개다. 프로젝트 `Source/`에서는 `USTRUCT`, 엔진 자동검사 등록, `TEST_CASE`, 대문자 `CHECK` 호출을 찾지 못했다.

영어 비교 로그: [smoke_diagnostic_en_20260905_232711_console.log](</Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/UE_Agent_Test/Evidence/smoke_diagnostic_en_20260905_232711_console.log>)

| 같은 검사 | 한국어 실행 | 영어 실행 | 영어 로그 위치 |
|---|---:|---|---|
| `FUnifiedErrorTest_CreateErrorMessage` | 오류 7개 | `Success` | 2204행 |
| `FUnifiedErrorTest_CreateErrorMessageWithContext` | 오류 4개 | `Success` | 2205행 |
| `FStructuredLogFormatTest` | 오류 4개 | `Success` | 2232행 |

영어 로그 439행에서 `-culture=en`을 확인했고, 파일 전체에서 `LogAutomationTest: Error`는 발견하지 못했다. 3334행에는 정상 편집기 닫기 요청, 3393행에는 `LogExit: Exiting.`이 기록되어 있다. 언어 비교 실행은 게임 조작 47항목을 다시 시험하는 실행이 아니며, 엔진 시작 자체 검사 오류 원인을 분리하는 진단이었다.

## 오류 메시지 검사: 7개 + 4개

실제 소스: [UnifiedErrorTests.cpp:479](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Experimental/UnifiedError/UnifiedErrorTests.cpp:479>)

첫 검사는 485, 489, 493, 497, 501, 505, 509행에서 생성된 문장 전체를 영어 문자열과 비교한다. 각각 `Empty`, `WithInt`, `WithUint`, `WithIntString`, `WithIntStringFloat`, `WithArray`, `WithStruct`에 대한 비교다. 예를 들어 485행의 기대값은 `UE::UnifiedErrorTest::Empty: Empty error`다.

추가 정보가 붙는 두 번째 검사는 [같은 파일 512행](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Experimental/UnifiedError/UnifiedErrorTests.cpp:512>)부터 시작한다. 522, 523, 532, 533행의 네 비교도 영어 문장을 고정 기대값으로 사용한다.

반면 실제 메시지 생성 구현은 번역을 사용하는 경로다. [UnifiedError.cpp:84](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Experimental/UnifiedError/UnifiedError.cpp:84>)에서 번역되는 로그 형식을 사용하도록 설정되어 있고, 110–125행에서 해당 형식으로 문장을 만든다.

설치된 실제 번역 파일: [Engine.locres](</Volumes/T7/UE 58/UE_5.8/Engine/Content/Localization/Engine/ko/Engine.locres>)

이 파일은 바이너리이므로 줄 번호가 없다. 엔진의 저장 규격을 따라 읽기 전용으로 해석했으며, 다음 값이 실제 포함되어 있음을 확인했다. 아래 표는 실행 중 생성된 오류 문장을 캡처한 것이 아니라 **번역 파일에 저장된 문장 형식**이다.

| 네임스페이스 | 키 | 실제 한국어 번역 자료 |
|---|---|---|
| `UE::UnifiedErrorTest` | `Empty` | `빈 오류` |
| `UE::UnifiedErrorTest` | `WithInt` | `int {IntParam}에 오류가 있음` |
| `UE::UnifiedErrorTest` | `WithUint` | `uint {UintParam}에 오류가 있음` |
| `UE::UnifiedErrorTest` | `WithIntString` | `int {IntParam} 및 string {StringParam}에 오류가 있음` |
| `UE::UnifiedErrorTest` | `WithIntStringFloat` | `int {IntParam}, string {StringParam} 및 float {FloatParam}에 오류가 있음` |
| `UE::UnifiedErrorTest` | `WithArray` | `배열 {ArrayParam}에 오류가 있음` |
| `UE::UnifiedErrorTest` | `WithStruct` | `{Param/X},{Param/Y},{Param/Z} 커스텀 포맷 구조체에 오류가 있음` |
| `UE::UnifiedErrorTest` | `StringContext` | `통합 오류 스트링 컨텍스트 {StringParam}` |

`UnifiedError` 네임스페이스의 바깥 형식 `DefaultLog_NoContexts`와 `DefaultLog_WithContexts`는 각각 `{ModuleIdString}::{ErrorCodeString}: {Details[0]}`, `{ModuleIdString}::{ErrorCodeString}: {Details}`로 남아 있다. 즉 내부 오류 문장과 추가 정보가 한국어로 바뀌는 것이 영어 고정 비교와 충돌한다.

이 자료로 첫 검사의 7개 비교, 두 번째 검사의 4개 비교가 한국어 실행에서 실패하는 이유를 설명할 수 있다. 실패 수 역시 실제 로그와 일치한다.

## 로그 문장 형식 검사: 4개

실제 소스: [StructuredLogFormatTest.cpp](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Logging/StructuredLogFormatTest.cpp>)

같은 `Engine.locres`에서 `StructuredLogFormatTest` 네임스페이스의 다음 번역을 확인했다.

| 키 | 실제 번역 자료 | 소스의 영어 기대값과 충돌하는 지점 |
|---|---|---|
| `ObjectWithNestedLocFormat` | `타깃=({Point}); X={Point/X}` | 237행의 기대값 `Target=(X=1;Y=2;Z=3); X=1` |
| `EmitterSubheaderText` | `{IntegerPositive}개의 {IntegerPositive}오류가 발견되었습니다!` | 276행의 `Found 63 errors!`라는 영어 기대값 |

237행의 검사는 동일 문장을 두 종류의 문자열 입력으로 검사하는 공통 경로를 사용한다. 실제 비교는 [183행](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Logging/StructuredLogFormatTest.cpp:183>)과 192행에 각각 한 번씩 있어 **2개**의 실패를 설명한다.

[314행](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Logging/StructuredLogFormatTest.cpp:314>)에서도 같은 번역된 내부 문장을 영어 `Target=...`와 비교한다. 이 경로의 실제 비교는 266행이므로 **1개**를 더 설명한다.

[`EmitterSubheaderText`의 276행](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Tests/Logging/StructuredLogFormatTest.cpp:276>)은 번역된 오류 개수 문장을 `Found 63 errors!`와 비교하므로 **1개**를 설명한다. 따라서 이 검사의 합계는 **2 + 1 + 1 = 4개**이며, 로그의 실패 수와 일치한다.

위 4개 세부 조건의 배정은 소스와 실제 번역 자료를 대조한 분석이다. 원래 로그에는 개별 비교문의 실행 결과나 실제 완성 문장이 나오지 않으므로, 개별 조건의 런타임 추적을 별도로 수행했다고 주장하지 않는다.

## 처음에는 이름 없이 오류만 보인 이유

[AutomationTest.cpp:31](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Misc/AutomationTest.cpp:31>)은 해당 로그 종류의 기본 표시 수준을 `Warning`으로 설정한다. 검사 이름과 결과는 [1252행](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Misc/AutomationTest.cpp:1252>)에서 더 상세한 `Log` 수준으로 기록하고, 조건 오류는 1265행에서 `Error` 수준으로 기록한다. 또한 시작 자체 검사에서는 558–559행에서 오류 호출 위치 수집을 끈다.

따라서 이전 로그에는 이름과 조건 위치 없이 `Condition failed`만 보였다. 진단 실행에서 `LogAutomationTest Log`를 사용하자 세 검사 이름과 7 + 4 + 4 분포가 드러났다. 오류를 감추거나 검사를 끈 것은 아니다.

## 번역 파일 해석 근거와 판정 범위

번역 파일 형식은 다음 실제 엔진 소스로 확인했다.

- [TextLocalizationResource.cpp:288](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Internationalization/TextLocalizationResource.cpp:288>): 파일 버전, 문자열 표, 네임스페이스와 키를 읽는 순서.
- [TextLocalizationResource.cpp:190](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Internationalization/TextLocalizationResource.cpp:190>): 번역 문자열과 참조 수의 저장 순서.
- [TextKey.cpp:805](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Private/Internationalization/TextKey.cpp:805>): 키 해시와 문자열의 저장 순서.
- [TextLocalizationResourceVersion.h:41](</Volumes/T7/UE 58/UE_5.8/Engine/Source/Runtime/Core/Public/Internationalization/TextLocalizationResourceVersion.h:41>): 설치된 파일의 버전 3 해석 근거.

소스의 영어 고정 비교, 실제 한국어 번역, 실제 15개 실패 분포가 서로 맞으며, 영어 비교 실행에서는 같은 세 검사가 모두 성공했다. 따라서 이번 15개 메시지는 엔진 자체 문장 검사가 현재 언어의 번역 결과를 영어 고정 기대값과 비교해서 발생하는 문제로 판단한다. 방·문·이동 기능의 고장을 나타내는 증거는 아니다. 한국어로 실행할 때 나타나는 엔진 자체 검사 문제를 수정한 것은 아니므로, 한국어 실행 로그에 오류가 없었다고 보고해서는 안 된다.
