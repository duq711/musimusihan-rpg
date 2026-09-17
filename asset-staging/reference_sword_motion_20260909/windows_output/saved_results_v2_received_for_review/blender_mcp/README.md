# Windows Blender MCP 설정 완료

Windows `DESKTOP-M9TL6BT`에서 공식 Blender MCP 설치와 실제 SDK 호출을 확인했습니다. 최종 검증은 **2.784초, 도구 26개 조회, 4개 호출 모두 PASS**입니다. MCP 초기화, 전용 Blender 브리지 조회, 시험 파일 저장·GLB 내보내기, 별도 Blender 프로세스 재검증을 수행했습니다. 1·12·24프레임 위치 오차는 모두 0m였으며 기존 시험 원본의 SHA256도 유지됐습니다.

설치 버전은 Blender 5.2.1 LTS, Python 3.11.16, 공식 `blender-mcp` 1.0.2, MCP SDK 1.30.0, Blender 확장 1.0.0입니다. 공식 소스 커밋은 `5181fa06d5c601e910eb680a0012d20d1203b8d5`이며 추적 파일 변경이 없습니다.

최종 Codex 설정 파일은 `C:/Users/duq71/.codex/config.toml`이고 서버 이름은 `blmcp`입니다. 실행 설정은 다음과 같습니다.

```text
command: C:/Users/duq71/.codex/tools/blender-mcp-runtime/.venv/Scripts/python.exe
args: C:/Users/duq71/.codex/tools/blender-mcp-runtime/run_blmcp_windows.py --transport stdio
cwd: C:/Users/duq71/.codex/tools/blender-mcp-official/mcp
BLENDER_PATH: C:/Users/duq71/Documents/Codex/2026-09-08/new-chat/work/tools/blender-5.2.1-windows-x64/blender.exe
BLENDER_MCP_HOST: 127.0.0.1
BLENDER_MCP_PORT: 9876
```

전용 브리지는 검사 당시 PID `29124`로 백그라운드에서 실행 중이었으며 `127.0.0.1:9876`에만 바인딩했습니다. 확장과 환경설정은 `C:/Users/duq71/.codex/tools/blender-mcp-runtime/blender-user`에 격리했습니다. 사용자 Blender 창이나 기존 환경설정은 변경하지 않았습니다.

Windows에서 공식 CLI 도구의 자식 Blender가 MCP 입력 파이프를 상속해 멈추는 현상이 확인됐습니다. 별도 실행 래퍼가 해당 CLI 도우미에만 `stdin=DEVNULL`과 `CREATE_NO_WINDOW`를 적용합니다. 공식 저장소와 설치 패키지 파일은 수정하지 않았습니다. 최초 시도와 `retry_01`의 실패 기록은 보존했고, 수정 후 성공 증거는 `retry_02/sdk_validation.json`과 `retry_02/independent_review.json`에 있습니다. 이 검증은 작은 시험 장면과 조회한 호출 범위를 확인합니다.

설정 이전 백업은 `C:/Users/duq71/.codex/config.toml.before-blmcp-20260909_215426.bak`, 래퍼 적용 이전 백업은 `C:/Users/duq71/.codex/config.toml.before-blmcp-stdin-fix-20260909_220244.bak`입니다. 최초 백업의 TOML과 현재 설정에서 `blmcp`만 제외한 TOML이 동일함을 다시 확인했습니다. 기존 서버·모델·사고 수준을 포함한 다른 설정은 유지됐습니다.

**현재 열린 Codex 작업의 도구 목록에 자동 반영됐다는 뜻은 아닙니다.** SDK 직접 검증은 완료됐으며, Codex에 새 서버 설정을 반영하려면 Codex를 재시작해 새 MCP 연결을 불러와야 합니다. [Codex MCP 안내](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

제작에 사용할 기존 최신 모델은 `C:/Users/duq71/Documents/Codex/2026-09-08/d/outputs/sword_hold_long_grip/model/SwordHold_Static.blend`와 같은 폴더의 `SwordHold_Static.glb`입니다. 손·팔·검을 포함한 정적 메시 11개이며 리그와 애니메이션은 없습니다. 이전 손 리그는 `C:/Users/duq71/Documents/Codex/2026-09-08/d/work/new-motion/references/game_sword_only_ready.blend`에 있고, Godot 원본들은 `C:/Users/duq71/Documents/Codex/2026-09-08/d/work/game-project/RPG_Workspace/godot-game/assets/3d/player/sword_shield`에 있습니다. 자세한 구성은 `asset_inventory_notes.md`에 기록했습니다.

OneDrive 전달 경로는 `C:/Users/duq71/OneDrive/CodexTransfer/reference_sword_motion_20260909`입니다. 설정 완료 확인 당시 `input` 폴더와 요청된 Mac 자료는 도착하지 않았습니다. 이 README와 `report.json`만 `output/windows_mcp_setup`에 복사했습니다. Windows의 로컬 쓰기·읽기는 확인됐지만 **Mac 수신과 동기화 완료는 확인하지 않았습니다.** 설정 백업이나 비밀 정보는 전달하지 않았습니다.

공식 출처: [Blender MCP 저장소](https://projects.blender.org/lab/blender_mcp.git), [Blender 공식 안내](https://www.blender.org/lab/mcp-server/).
