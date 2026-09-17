# Chat On Steroids 작업 인계 / Project handoff

## 이 Mac의 준비 상태 / Setup status on this Mac

2026-09-17: 앱 2.1.13 설치, 기존 프로젝트 `/rpg` 등록, Chrome companion 연결, OpenAI 터널 연결, ChatGPT 개발자 모드 및 **Chat On Steroids Core** 등록을 완료했습니다. ChatGPT에서 Core의 **read**와 **exec_command**가 실제로 성공하는 것을 확인했습니다. 아래 검증은 파일 수정 없이 수행했습니다.

2026-09-17: App 2.1.13 is installed with the existing project registered as `/rpg`. Chrome companion pairing, the OpenAI tunnel, ChatGPT Developer mode, and **Chat On Steroids Core** registration are complete. Core's **read** and **exec_command** tools succeeded from ChatGPT. The checks below made no file changes.

검증 결과: Core가 `/rpg/README.md`, `/rpg/AGENTS.md`, `/rpg/docs/CHAT_ON_STEROIDS.md`를 읽었고, README 내용은 로컬 원본과 일치했습니다. `/rpg`에서 `pwd`와 프로젝트 전용 Git 도구로 확인한 경로·브랜치·HEAD도 별도 로컬 확인과 일치했습니다. 세 명령은 모두 종료 코드 0으로 완료됐습니다. 검증 당시 작업 브랜치는 `codex/creep-creature`, HEAD는 `220bc1697bd52d8d59a2a0faa070cabf702d3366`입니다. 이 작업 폴더의 브랜치와 과거 자료 공유용 `codex/project-archive-20260917` 브랜치는 구분합니다.

Verification: Core read `/rpg/README.md`, `/rpg/AGENTS.md`, and `/rpg/docs/CHAT_ON_STEROIDS.md`; the README matched the local original. Running `pwd` and the project Git wrapper from `/rpg` returned the same path, branch, and HEAD as an independent local check. All three commands exited with code 0. At verification, the working branch was `codex/creep-creature` at `220bc1697bd52d8d59a2a0faa070cabf702d3366`. This working checkout is distinct from the historical publication branch `codex/project-archive-20260917`.

API 키는 사용자가 직접 입력했으며 앱에서 운영체제의 보안 인증 정보 저장소에 보관 중임을 확인했습니다. ChatGPT의 플러그인 권한은 **저위험 액션 허용**입니다. 화면·키보드 제어용 선택 기능인 Desktop 연결은 추가하지 않았습니다.

The user entered the API key directly, and the app confirms it is stored in secure OS credential storage. The ChatGPT plugin permission is **Allow low-risk actions**. The optional Desktop connection for screen and keyboard control was not added.

첫 read 응답에는 대화 식별 지연으로 Unattributed 경고가 있었으나, 앱 Activity에서 두 호출을 해당 대화로 자동 복구했고 미식별 호출이 0개로 바뀐 것을 확인했습니다. 앱의 ‘연결 검증 요약’ 대화에서도 읽기·명령 실행 기록과 결과가 표시됩니다. 초기 응답의 경고는 복구 전 상태입니다.

The initial read response warned of delayed conversation attribution. App Activity subsequently confirmed that both calls were repaired into the correct conversation, with zero calls remaining unknown. The app's verification conversation displays the read and command records and results. The initial response's warning predates this repair.

Codex용 개인 연결 스킬 `chat-on-steroids`와 이후 작업의 연속성 지침을 이 Mac에 저장했습니다. 공유용 [스킬 원본](../skills/chat-on-steroids/SKILL.md)도 포함합니다. 이 스킬은 이번에 작성한 인계 지침이며, 앱 자체가 Codex 안에 설치되거나 모든 대화가 자동 이전된다는 뜻은 아닙니다. 기존 제작 자료의 공유 내역은 [아카이브 안내](WORK_ARCHIVE_20260917.md)를 확인합니다.

A personal `chat-on-steroids` integration skill and persistent continuity preference are saved on this Mac. Its [shareable source](../skills/chat-on-steroids/SKILL.md) is included. This newly authored handoff skill does not embed the app inside Codex or automatically migrate conversations. See the [archive report](WORK_ARCHIVE_20260917.md) for historical materials.

## 평소 사용하는 순서 / Everyday use

1. 이 Mac에서 **Chat On Steroids**를 실행하고 터널 연결을 유지합니다. Chrome과 companion도 실행하고 ChatGPT 로그인을 유지합니다. Chrome은 백그라운드에 두고 앱 화면에서 작업할 수 있습니다. / Run **Chat On Steroids** and keep its tunnel connected. Keep Chrome, the companion, and the ChatGPT login available in the background while working in the app.
2. **앱에서 직접 입력하는 방식을 기본으로 사용합니다.** 왼쪽의 기존 대화를 선택해 아래 **Message ChatGPT**에 입력하고 **Send message**를 누릅니다. 새 작업은 프로젝트 옆 **New chat in this project**에서 시작합니다. / **Use the app's own composer by default.** Select an existing conversation, enter the request in **Message ChatGPT**, and press **Send message**. Use **New chat in this project** for a new project task.
3. “`/rpg`의 인계 문서와 AGENTS.md를 읽고, [요청할 작업]을 진행해 주세요”라고 요청합니다. 같은 파일을 수정 중인 다른 작업이 있으면 담당 범위를 나눕니다. / Ask: “Read the handoff guide and AGENTS.md in `/rpg`, then [requested task].” Coordinate ownership when other tasks are editing the same files.
4. 작업별 관련 검증 후 해당 변경만 커밋·푸시하고 원격 SHA까지 확인하도록 합니다. / Have each task validate its changes, commit and push only those changes, and verify the remote SHA.

2026-09-17 추가 검증: 앱의 **Message ChatGPT**에서 README 1~5행을 읽는 후속 요청을 직접 전송했습니다. 모델 목록이 자동으로 로딩된 뒤 기존 대화의 GPT-6 Pro로 전송됐고, Core 읽기 결과와 프로젝트 이름·장르 답변이 앱에 표시됐습니다.

Additional verification on 2026-09-17: A follow-up request to read README lines 1–5 was sent directly from the app's **Message ChatGPT** composer. Models loaded automatically, the request used the existing conversation's GPT-6 Pro, and the Core read result and project-name/genre answer appeared in the app.

Chrome에서 직접 입력하는 방법도 있습니다. ChatGPT의 **+ → Chat On Steroids Core**를 선택합니다. 설치 직후 기존 탭의 메뉴에 Core가 없으면 빈 입력창인 상태에서 페이지를 새로고침합니다. 이 Mac에서는 새로고침 후 Core 항목이 표시되고 선택되는 것을 확인했습니다. Chrome 화면에서 항상 입력할 필요는 없지만, 앱의 요청 전송은 로그인된 ChatGPT와 companion을 사용하므로 Chrome을 완전히 종료하지 않습니다.

You can also compose in Chrome by selecting **+ → Chat On Steroids Core** in ChatGPT. If an older tab does not list Core immediately after installation, reload the page with an empty composer. Reloading restored the Core entry on this Mac, and selection was verified. You do not need to type in Chrome, but keep it running because the app sends requests through the signed-in ChatGPT session and companion.

## 기존 작업을 이어 쓰는 방법 / Continue existing work

Chat On Steroids는 별도 앱입니다. 기존 프로젝트의 최상위 `무시무시한 rpg` 폴더를 Workspace와 프로젝트로 선택하면 게임 코드뿐 아니라 같은 폴더 안의 모델·모션·기획·제작 원본을 필요할 때 읽고 수정할 수 있습니다. 파일을 복제하거나 GitHub에서 다시 받을 필요가 없습니다. 파일 접근 설정은 파일 전체를 대화에 자동 첨부하거나 공개 업로드하는 동작과 다릅니다.

Chat On Steroids is a separate app. Select the existing top-level project folder as its approved workspace and project to work with game code, models, animation, design, and production sources in place. No duplicate copy or fresh clone is needed. Approving a folder does not automatically load every file into a conversation or publish those files.

Codex의 기존 대화 기록과 현재 진행 중인 작업 상태가 새 앱에 자동 이전된다고 가정하지 않습니다. 저장된 프로젝트 문서·Git 기록·실제 파일을 기준으로 인계합니다. 대화에만 남아 있는 중요한 결정은 관련 기획 문서에 정리한 뒤 이어갑니다.

Do not assume that Codex conversation history or active task state transfers to this app. Use saved project documents, Git history, and actual files as the handoff. Record any important decisions that exist only in a conversation in the appropriate design document.

## 연결 순서 / Connection steps

공식 [설치 안내](https://github.com/totec448-spec/chat-on-steroids/blob/main/docs/setup.md)를 따릅니다. 아래는 2.1.13의 Setup 화면을 기준으로 한 절차입니다.

Follow the official [setup guide](https://github.com/totec448-spec/chat-on-steroids/blob/main/docs/setup.md). These steps correspond to the 2.1.13 Setup screen.

1. **Settings → Workspace**에서 프로젝트 최상위 폴더를 선택합니다. 사이드바에서도 같은 폴더를 프로젝트로 등록합니다. / Select the project root under **Settings → Workspace** and add that same folder as a sidebar project.
2. **Settings → Setup**에서 사용할 ChatGPT 워크스페이스에 연결된 OpenAI 터널을 지정합니다. API 키는 사용자가 직접 만들고 앱의 보안 입력란에 입력합니다. 공식 안내의 제한 권한은 **Tunnels: Read + Use**입니다. 키를 대화·프로젝트 파일·GitHub에 저장하지 않습니다. / Configure an OpenAI tunnel associated with the intended ChatGPT workspace. The user creates and enters the key directly in the app. The documented restricted permissions are **Tunnels: Read + Use**. Keep the key out of chats, project files, and GitHub.
3. **Connect** 후 실제 **Connected** 상태를 확인합니다. ChatGPT의 플러그인/앱 설정에서 **Chat On Steroids Core**를 해당 터널에 연결합니다. / Press **Connect**, verify **Connected**, then connect **Chat On Steroids Core** to that tunnel in ChatGPT's plugin/app settings.
4. **Open extension folder**로 앱이 제공하는 폴더를 확인합니다. Chrome의 `chrome://extensions`에서 개발자 모드 → **Load unpacked**로 해당 폴더를 선택합니다. 이 확장은 ChatGPT 페이지의 작업 대화와 로컬 앱을 연동합니다. 앱에서 브라우저 연결 상태도 확인합니다. / Use **Open extension folder**, then Chrome's developer mode and **Load unpacked** to load the companion. It connects ChatGPT task conversations with the local app. Verify the browser connection in the app as well.
5. 새 대화에서 아래 인계 프롬프트를 사용하고, 먼저 README 읽기와 Git 상태 확인만 요청합니다. 실제 파일 경로·현재 브랜치·커밋이 일치하면 작업을 시작합니다. / Start a conversation with the handoff prompt below. First request only README reading and Git status, and verify the actual path, branch, and commit before editing.

화면·키보드 제어용 Desktop 연결은 일반적인 코드·파일 작업과 별도로 설정하는 선택 기능입니다. 연결 완료 여부는 앱 설치, 터널 연결, ChatGPT Core 연결, Chrome 연동, 실제 파일 읽기의 다섯 단계를 구분하여 확인합니다.

Desktop screen and keyboard control is an optional, separate connection. Distinguish app installation, tunnel connection, ChatGPT Core connection, Chrome pairing, and an actual file read when checking readiness.

## 첫 대화에 붙일 내용 / First-message handoff

```text
선택한 '무시무시한 rpg' 프로젝트의 기존 작업을 이어 주세요.
먼저 작업 폴더를 확인하고 AGENTS.md, docs/CHAT_ON_STEROIDS.md,
docs/GITHUB_WORKFLOW.md와 현재 Git 상태를 읽어 주세요.
게임 작업의 기본 대상은 godot-game/이며, 해당 AGENTS.md를 따르세요.
신규 기획·기능이면 design/GAME_DIRECTION.md와 design/TEAM_ROLES.md도 확인하세요.
처음에는 파일을 수정하지 말고 현재 브랜치·최근 커밋·미커밋 변경을 요약하세요.
이후 제가 요청하는 작업을 같은 프로젝트에서 구현·검증해 주세요.
다른 담당자의 진행 중 변경과 원본 제작 자료를 보존하세요.
게임 실행·검증은 백그라운드에서 진행하고 필요한 기능은 테스트룸에도 반영하세요.
완료한 해당 작업만 한국어·영어 설명으로 커밋·푸시하고 원격 SHA를 확인하세요.
```

English equivalent:

```text
Continue work in the selected Musimusihan RPG project.
First confirm the working directory and read AGENTS.md,
docs/CHAT_ON_STEROIDS.md, docs/GITHUB_WORKFLOW.md, and current Git status.
The primary game project is godot-game/; follow its AGENTS.md.
For new design or features, also read design/GAME_DIRECTION.md and design/TEAM_ROLES.md.
Initially make no edits: summarize the branch, recent commit, and uncommitted changes.
Then implement and validate my requested work in this same project.
Preserve other contributors' in-progress changes and production sources.
Run checks in the background and integrate new game behavior into the test room.
Commit and push only completed task changes with Korean and English summaries,
then verify the remote commit SHA.
```

## 작업물 위치 / Where the work lives

| 경로 / Path | 용도 / Purpose |
| --- | --- |
| `godot-game/` | 기본 게임 소스·실행 에셋·테스트 / Primary game source, runtime assets, and tests |
| `godot-game/design/` | 확정 컨셉·담당 범위·기획 / Confirmed concepts, roles, and design |
| `asset-staging/` | 모델·애니메이션 제작 과정과 원본 / Model and animation production work and sources |
| `exports/` | 작업별 내보낸 결과·제작 자료 / Per-task exports and production materials |
| `concept-art/`, `concept-screens-v2/`, `generated-assets/` | 컨셉과 생성 에셋 / Concepts and generated assets |
| `game/`, `UE_Agent_Test/` | 이전 프로토타입·별도 실험, 명시적 요청 시에만 수정 / Earlier prototypes and separate experiments; edit only when requested |

현재 기능과 조작은 [게임 안내](../godot-game/README.md), 시험 방법은 [테스트룸](../godot-game/TEST_ROOM.md), 원본 제작 흐름은 [에셋 제작 안내](../godot-game/ASSET_PIPELINE.md)를 확인합니다.

Read the [game guide](../godot-game/README.md) for current behavior, [test-room guide](../godot-game/TEST_ROOM.md) for testing, and [asset pipeline](../godot-game/ASSET_PIPELINE.md) for production sources.

## GitHub 공유와 동시 작업 / GitHub sharing and concurrent work

GitHub 대상은 [duq711/musimusihan-rpg](https://github.com/duq711/musimusihan-rpg)입니다. 원격의 `main`만 확인하면 작업 브랜치의 최신 결과를 놓칠 수 있습니다. 현재 브랜치와 원격 SHA를 함께 확인합니다.

The repository is [duq711/musimusihan-rpg](https://github.com/duq711/musimusihan-rpg). Check the active branch and its remote SHA; `main` alone may not contain recent work on feature branches.

```sh
sh tools/git-project.sh status --short
sh tools/git-project.sh branch -vv
sh tools/git-project.sh log -5 --oneline
sh tools/git-project.sh remote -v
```

로컬 폴더 공유는 과거 제작 자료의 공개 업로드와 별개입니다. 공개 범위는 [루트 README](../README.md)와 [GitHub 작업 안내](GITHUB_WORKFLOW.md)를 따릅니다. 인증 정보·재생성 가능한 캐시·재배포할 수 없는 유료 원본 에셋은 공개하지 않습니다. 과거 자료 전체를 새로 업로드하려면 대상과 크기·라이선스를 먼저 검토합니다.

Local workspace access is separate from public upload of historical materials. Follow the [root README](../README.md) and [GitHub workflow](GITHUB_WORKFLOW.md). Keep credentials, regenerable caches, and licensed source assets without redistribution rights out of public uploads. Review scope, sizes, and licensing before adding a historical archive.

Codex와 새 앱이 같은 파일을 동시에 수정하면 변경이 충돌할 수 있습니다. 동일 파일을 담당하는 작업은 순서대로 진행하거나 각 작업에 별도 Git worktree를 사용합니다. 이 문서의 등록만으로 기존 Codex 담당 작업이 새 앱으로 이동하거나 다른 앱의 도구가 자동 연결되지는 않습니다.

Codex and this app can conflict if both edit the same files concurrently. Sequence work on overlapping files or use separate Git worktrees. This handoff document does not move existing Codex tasks into the new app or automatically connect other apps' tools.
