# Chat On Steroids 한국어 패치 / Korean UI patch

2026-09-17, 이 Mac의 Chat On Steroids **2.1.13**에 적용했습니다. 공식 한국어 배포판이 아닌 로컬 수정본입니다.

Applied to Chat On Steroids **2.1.13** on this Mac on 2026-09-17. This is a local customization, not an official Korean release.

## 적용 내용 / Changes

- 기존 언어 전환 체계에 한국어 문구 **1,134개**와 한국어 선택 항목을 추가했습니다.
- 대화창, 사이드바, 작업 공간, 연결 설정, 사용량, 플러그인, 자동화 설정 및 접근성 설명을 번역했습니다.
- macOS 메뉴, 트레이 메뉴 및 파일 선택창 제목도 한국어로 바꿨습니다. 네이티브 메뉴는 이 패치가 설치된 동안 한국어로 표시됩니다.
- 메시지, 프로젝트 파일, API 키, 도구 실행 로직, 승인 정책, 모델 식별자에는 패치를 적용하지 않습니다.
- 제품·모델·도구 이름, 외부 오류와 실행 로그, 안내 이미지 안의 영어는 원문을 유지합니다.

Added 1,134 Korean UI entries through the existing localization system, a Korean language choice, and Korean native menus/dialog titles. Native menus remain Korean while this patch is installed. Authored messages, project files, API keys, tool execution, approval policies and model identifiers are unchanged. Product names, external errors/logs and text embedded in guide images retain their original language.

## 사용 / Usage

현재 앱은 한국어로 열려 있습니다. 언어는 **설정 → 에이전트 및 자동화 → 화면 모양 → 언어 → 한국어**에서 선택할 수 있습니다. 연결 설정 화면 상단에도 한국어 버튼이 있습니다.

Choose **Settings → Agents & automation → Appearance → Language → 한국어**, or use the Korean button at the top of Setup.

## 확인한 사항 / Validation

- 1,134개 키·자리표시자와 모든 정적 화면 문구의 대응을 검사했습니다.
- 한국어↔영어↔중국어 전환 및 저장 언어 다시 불러오기를 검사했습니다.
- 언어 전환 중 입력 초안·선택 범위·사용자 제목·메시지·아이콘·내부 선택값 보존을 검사했습니다.
- 렌더러와 메인 프로세스 JavaScript 구문 검사, ASAR 파일별 비교, macOS 앱 서명 검사를 통과했습니다.
- ASAR 내 변경 파일은 3개이며, 나머지 패키징된 파일 2,280개는 원본과 바이트 단위로 같습니다.
- 실제 앱에서 대화창·설정·사용량 화면의 한국어 표시, 기존 프로젝트와 대화 목록, Chrome companion 연결 및 터널의 '연결됨' 상태를 확인했습니다.
- 재시작 전 입력 초안과 GPT-6 Pro 선택을 복원했습니다. 검증을 위해 작업 메시지를 전송하지 않았습니다.

Checks passed for catalog/placeholder coverage, language switching and persistence, draft/selection/authored-content preservation, JavaScript syntax, ASAR comparison and macOS signature verification. Three packed files changed; 2,280 other packed files are byte-identical. Native UI checks confirmed Korean screens, existing projects/conversations, companion pairing and a connected tunnel. The unsent draft and GPT-6 Pro selection were restored; no task message was sent for validation.

## 백업·원복 / Backup and restore

원본 앱 백업: `~/Library/Application Support/Chat On Steroids Korean Patch/original-2.1.13.bundle`

앱을 완전히 종료한 뒤 이 폴더에서 실행합니다.

```sh
python3 patch.py restore
```

그런 다음 평소처럼 앱을 실행합니다. 원복은 앱의 패치 파일과 서명만 복원하며 사용자 데이터에는 접근하지 않습니다. 원본 2.1.13에서는 저장된 한국어 설정을 인식하지 못해 영어로 표시됩니다.

Fully quit the app, run the command above from this directory, then launch it normally. Restore replaces patch-owned app files/signature only; user data is untouched. The original version falls back to English when it encounters the Korean preference.

## 재적용 / Reapply

앱 업데이트가 한글 패치를 덮어쓸 수 있습니다. 이 패치는 아래 SHA-256의 2.1.13 macOS 앱에만 적용됩니다. 다른 버전에는 자동 적용하지 않고 중단합니다.

`4e737cc41af837a978472f4b1db17f22b19873615f87c8b559948e046028234a`

```sh
python3 patch.py build
# 앱을 완전히 종료한 뒤 / After fully quitting the app:
python3 patch.py install
```

Updates can overwrite the patch. Its version/hash check rejects other releases. Build and install do not change app data or credentials. For development validation, install the locked jsdom dependency with `pnpm install --frozen-lockfile --ignore-scripts`, then run `node verify.cjs` after building.

Upstream: https://github.com/totec448-spec/chat-on-steroids/tree/a4fe9726232edfbf67b97d6c716b6f653284739a

Upstream English keys and integration structure are MIT-licensed; see `LICENSE.upstream`.
