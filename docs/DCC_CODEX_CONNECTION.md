# Blender·Unity의 Codex 연결 / Blender and Unity in Codex

2026-10-02, 이 Mac의 내부 프로젝트에서 연결을 복구하고 실제 MCP 읽기 호출까지 확인했습니다. 아래 상태는 이 날짜의 검증 결과이며, 저장된 설정만으로 이후 연결을 보장하지 않습니다.

On 2026-10-02, both integrations were repaired and verified with actual MCP read calls on this Mac's internal project. These results describe that verification, rather than guaranteeing that a saved configuration is always connected.

## 확인된 상태 / Verified state

| 항목 / Component | 결과 / Result |
| --- | --- |
| Blender | 5.2.1 LTS, 백그라운드 실행 / running in the background |
| Blender Lab MCP | 공식 애드온·서버 1.0.0, MCP SDK 1.29.1 / official add-on and server 1.0.0, MCP SDK 1.29.1 |
| Python·uv | 관리형 Python 3.11.16, uv 0.12.21 ARM64 / managed Python 3.11.16, uv 0.12.21 ARM64 |
| Blender 검증 / check | MCP 초기화, 도구 26개 조회, `get_blendfile_summary_datablocks` 읽기 성공 / initialization, listing 26 tools, and a successful read call |
| Unity | 기존 Editor 6000.3.25f1, CLI 1.0.0-beta.8, Pipeline 0.8.0-exp.1 / existing Editor, CLI and Pipeline |
| Unity 검증 / check | MCP 초기화, 도구 160개 조회, `editor_status` 읽기 성공 / initialization, listing 160 tools, and a successful read call |
| Unity 상태 / state | `ready`, `compiling=false`, `playMode=stopped` |

Blender는 애드온이 설치·활성화됐지만 Codex 설정의 `uv`와 서버 원본 경로가 없어 시작할 수 없었습니다. 설치된 애드온과 파일 내용이 일치하는 공식 태그 `v1.0.0`, 커밋 `03004fd0216bfe5e0a3d9ac9b47d5efadc3d78c4`를 복원했습니다. 동명의 다른 커뮤니티 서버로 교체하지 않았습니다.

Blender's add-on was already installed and enabled, but the configured `uv` executable and server source directory were missing. The official `v1.0.0` tag, commit `03004fd0216bfe5e0a3d9ac9b47d5efadc3d78c4`, matches the installed add-on and was restored. A different community server with the same package name was not substituted.

## 실행과 설정 / Launch and configuration

Codex 설정은 `~/.codex/config.toml`에 있습니다. 기존 설정과 승인 정책을 보존했으며, 수정 전 백업은 `~/.codex/backups/dcc-20261002/`에 있습니다. 설정·백업·설치 환경·로그는 GitHub에 올리지 않습니다.

Codex configuration is in `~/.codex/config.toml`. Other settings and existing approval policies were preserved, with a prior backup in `~/.codex/backups/dcc-20261002/`. Configuration, backups, installed environments and logs remain local.

- Blender: `/usr/bin/python3`가 이 프로젝트의 [실행 도구](../tools/dcc/blender_mcp_launch.py)를 실행합니다. `127.0.0.1:9876`의 기존 브리지를 재사용하고, 없으면 공식 Blender를 백그라운드로 시작합니다. 미리 설치한 `~/.local/share/blender-mcp-official/runtime-v1/bin/blender-mcp`를 직접 실행하므로 시작할 때마다 패키지를 동기화하거나 내려받지 않습니다.
- Unity: `~/.unity/bin/unity mcp --project-path /Users/byeolee/Projects/musimusihan-rpg/unity-game`를 사용합니다. 기존 내부 프로젝트 Editor가 열려 있어야 장면·에셋 명령이 연결됩니다.

- Blender: `/usr/bin/python3` runs the project's [launcher](../tools/dcc/blender_mcp_launch.py). It reuses the bridge on `127.0.0.1:9876`, or starts official Blender in the background if none is listening. It then executes the prepared `~/.local/share/blender-mcp-official/runtime-v1/bin/blender-mcp` directly, avoiding package synchronization and downloads on each launch.
- Unity: `~/.unity/bin/unity mcp --project-path /Users/byeolee/Projects/musimusihan-rpg/unity-game` targets the existing internal project. Its Editor must be open for live scene and asset commands.

Blender의 전역 온라인 접근 설정은 기존 `false`를 유지합니다. 브리지를 시작하는 해당 프로세스에만 `--online-mode`를 적용하며, 외부 인터페이스에 포트를 공개하지 않습니다. 애드온의 기존 자동 시작·폴링 설정은 유지합니다. 동시 시작은 파일 잠금으로 직렬화하며, 로그와 PID는 무시된 `.local-tools/dcc/`에 기록합니다.

Blender's saved global online-access preference remains `false`. Only the launched bridge process receives `--online-mode`, and its port stays on loopback. Existing add-on autostart and polling preferences remain unchanged. A file lock serializes concurrent launches; logs and the PID are recorded in ignored `.local-tools/dcc/`.

실행 환경은 소스 프로젝트의 `.venv`와 분리했습니다. 소스 프로젝트의 자동 의존성 동기화가 MCP SDK 2.x를 선택하면 1.0.0 서버의 `FastMCP` 가져오기가 실패하므로, 분리된 `runtime-v1`에서는 검증한 SDK 1.29.1을 유지합니다. 브리지 시작에 실패하면 실행 도구가 직접 시작한 자식만 정리합니다.

The runtime is separate from the source project's `.venv`. Automatic project dependency synchronization can select MCP SDK 2.x, which breaks the 1.0.0 server's `FastMCP` import. The isolated `runtime-v1` retains verified SDK 1.29.1. On bridge startup failure, the launcher cleans up only the child it created.

프로젝트를 이동하면 Codex 설정의 실행 도구 경로와 Unity 프로젝트 경로도 갱신합니다. 복구 후 Codex 자체에 Blender 도구 26개와 Unity 도구 160개가 로드됐으며, 직접 MCP 읽기 호출도 성공했습니다. 별도의 앱 재시작은 필요하지 않았습니다. 이후 기존 대화에 새 도구가 표시되지 않으면 설정의 MCP 서버를 새로고침하거나 새 대화를 엽니다.

If the project moves, update the launcher and Unity project paths in Codex configuration. After repair, Codex loaded 26 Blender tools and 160 Unity tools, and direct MCP read calls succeeded. No separate app restart was required. If a future existing chat does not show new tools, refresh MCP servers in settings or open a new chat.

## 검증과 제한 / Validation and limits

저장된 Codex 명령·인자를 그대로 실행해 두 서버의 `initialize`, `tools/list`, 실제 읽기 `tools/call`을 통과했습니다. Codex의 직접 Blender 요약 조회와 Unity 상태·열린 장면 조회도 성공했습니다. Blender 실행 도구를 다시 호출해 기존 브리지 재사용을 확인했고, 임시 프로세스로 시작 실패 시 자식 종료·PID 정리를 검증했습니다. `codex mcp list`에서 두 서버가 `enabled`로 표시됩니다. 로컬 검증 요약은 `.local-tools/dcc/connection-check-20261002.json`에 있습니다.

Both saved Codex commands passed `initialize`, `tools/list` and an actual read-only `tools/call`. Native Codex Blender summary and Unity status/open-scene queries also succeeded. Calling the Blender launcher again reused the existing bridge; an isolated temporary process verified child termination and PID cleanup on startup failure. `codex mcp list` reports both servers as enabled. The local verification summary is `.local-tools/dcc/connection-check-20261002.json`.

원본 `.blend`를 열거나 저장하지 않았습니다. Unity에서 Play를 시작하거나 장면을 수정하지 않았으며, `unity-game/`의 전체 Git diff와 상태는 실행 전후 동일했습니다. 연결 설정 작업이므로 게임 기능·테스트룸 완료를 새로 주장하지 않습니다. 장시간 모델링·렌더링·빌드 성능은 이번 검증 범위에 포함되지 않습니다.

No source `.blend` file was opened or saved. Unity Play mode and scenes were not modified, and the complete `unity-game/` Git diff and status matched the baseline. This setup work does not establish new gameplay or test-room completion. Long modeling, rendering and build workloads were not benchmarked.

Blender 백그라운드 모드에서는 동기 작업을 사용합니다. 대화형 뷰포트와 `check_is_finished` 지연 응답이 필요한 도구는 대화형 Blender 브리지에서 사용합니다. 설치된 Unity CLI beta8은 최신 스킬의 표시용 `--caller`·`--skill` 옵션을 지원하지 않으므로 이 버전에서는 해당 옵션을 제외합니다.

Use synchronous operations with background Blender. Tools requiring an interactive viewport or deferred `check_is_finished` responses need an interactive Blender bridge. Installed Unity CLI beta8 does not support the newer skill's labeling-only `--caller` and `--skill` flags; omit those flags for this version.

공식 근거 / Official references: [Blender Lab source](https://projects.blender.org/lab/blender_mcp), [uv installation](https://docs.astral.sh/uv/getting-started/installation/), [OpenAI MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
