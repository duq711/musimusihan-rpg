# Windows 모델링·모션 실행 안내

**2026-09-11 사용자 변경: 앞으로 모든 Blender 작업의 기본 대상은 MacBook이다. Windows는 사용자가 별도로 지정한 경우에만 사용한다.** 아래 내용은 Windows를 명시적으로 요청한 작업의 연결 절차와 이전 검증 기록이다. 현재 적용 기준은 프로젝트 루트 `AGENTS.md`를 따른다.

Windows 실행을 별도로 요청한 경우 원본 에셋을 보존하고 Windows 산출물은 별도 폴더로 가져와 검증한다.

Codex 원격 연결은 연결된 호스트의 파일과 실행 도구를 사용한다. 현재 Mac 작업의 shell이나 `mcp__blender` 도구가 자동으로 Windows로 전환되는 것은 아니다. Chrome 원격 데스크톱 화면이 연결되어 있다는 사실만으로 Windows 연산을 확인할 수도 없다. [OpenAI 공식 원격 연결 안내](https://learn.chatgpt.com/docs/remote-connections)

## 확인된 원격 작업 경로

2026-09-09 연결 점검에서 확인한 값이다. 다음 작업 전에 목록과 상태를 다시 조회한다.

| 항목 | 값 |
| --- | --- |
| Windows `hostId` | `remote-control:env_e_6aa1501084c0832bb5ce612daa560782` |
| 기존 작업 제목 | `칼 모션 영상 제작` |
| 기존 작업 `threadId` | `01a0812a-0c21-7c21-898c-2b0c0b31be35` |
| Windows 작업 폴더 | `C:\Users\duq71\Documents\Codex\2026-09-08\d` |

Mac에서 Windows 작업을 조율할 때는 `mcp__codex_app__list_threads`로 대상과 목적을 확인하고, `mcp__codex_app__send_message_to_thread`에 위 `hostId`와 `threadId`를 모두 명시한다. 새 작업은 사용자 요청 없이 만들지 않으며, 기존 작업에 다른 제작 지시를 보내기 전 현재 진행 상태와 목적을 확인한다.

상태와 완료 결과는 `mcp__codex_app__wait_threads`의 `targets`에 같은 두 식별자를 넣어 받는다. 즉시 확인은 `timeoutMs: 0`, 이후 기다림에는 이전 응답의 cursor를 `afterCursor`로 전달한다. `mcp__codex_app__read_thread`에서 일반 도구 오류가 발생한 경우에도 `wait_threads`로 상태 조회가 가능했던 사례가 있다. 조회 오류만으로 연결 끊김이나 실행 실패를 단정하지 않는다.

## 실행 순서

1. Windows 작업에서 OS, 컴퓨터 이름, 작업 폴더, Blender 실행 파일 경로와 버전을 확인한다. 작업 전달 성공과 Blender 실행 성공을 별도로 확인한다.
2. 원본 경로, 입력 파일과 별도 출력 폴더를 명시해 Windows에 제작 지시를 전달한다. 무거운 연산은 Windows의 Blender `--background` 실행을 우선한다.
3. 로그, 종료 상태, 실제 산출물 경로를 받아 확인한다. 화면을 띄워야 하는 검증은 먼저 숨김 실행 가능 여부를 확인하고 프로젝트의 방해 없는 검증 규칙을 따른다.
4. 결과를 Mac의 별도 에셋 준비 폴더로 가져와 파일과 모션을 검증한 다음 Godot에 통합한다. 원본을 덮어쓰지 않는다. 게임 기능 변경은 `godot-game/AGENTS.md`에 따라 테스트룸과 자동 검증에도 반영한다.

Windows 실행을 명시적으로 요청한 작업에서 해당 PC가 오프라인이거나 재인증이 필요하면 상태를 알린다. 일반 Blender 작업은 Windows 연결과 무관하게 기본 대상인 MacBook에서 진행한다.

## 검증 기록

2026-09-09 Windows 시험 작업의 실제 명령 출력과 `report.json` 조회 결과를 Mac에서 확인했다. 아래는 원격 보고서의 요약이며, 원본 보고서와 시험 산출물은 Windows에 보존되어 있다.

| 항목 | 실제 확인 결과 |
| --- | --- |
| OS·호스트 | Windows 11 Home 64비트, 빌드 26200 · `DESKTOP-M9TL6BT` |
| Blender | 5.2.1 LTS · Windows `--background` 실행 |
| 실행 파일 | `C:\Users\duq71\Documents\Codex\2026-09-08\new-chat\work\tools\blender-5.2.1-windows-x64\blender.exe` |
| GPU | NVIDIA GeForce RTX 4090 · 드라이버 610.47 |
| 원격 보고서 | `C:\Users\duq71\Documents\Codex\2026-09-08\d\outputs\windows_connection_smoke_20260909_213419\report.json` |
| 시험 실행 시간 | 2026-09-09 21:39:12–21:39:17 KST · 실행기 측정 약 4.52초(준비·스크립트 작성·보고 정리 제외) |
| 종료 상태 | 4개 단계 모두 통과, 시험 소유 Blender 프로세스 모두 정상 종료 |

1. `create`: 작은 큐브에 30fps, 1·12·24프레임 위치 키를 생성하고 `.blend`와 애니메이션 포함 `.glb`를 저장했다.
2. `verify_blend`: 별도 Blender 프로세스에서 저장 파일을 다시 열어 위치 채널 3개, 각 키 시각과 위치를 검증했다. 세 표본의 위치 오차는 0이었다.
3. `verify_glb`: 별도 빈 Blender 장면에서 GLB를 가져와 메시 1개, 애니메이션 1개와 동일한 세 프레임 위치를 검증했다. 세 표본의 위치 오차는 0이었다.
4. `render_gpu`: RTX 4090 OptiX만 활성화하고 CPU 렌더 장치를 제외한 상태에서 256×256, 8샘플 Cycles PNG를 생성했다. 렌더 호출 약 0.88초, 해당 Blender 프로세스 전체 약 1.92초. 로그의 `Path tracing on: NVIDIA GeForce RTX 4090 (OptiX)`와 시험 PID의 GPU 사용 관측으로 실제 GPU 실행을 확인했다.

보고서와 같은 Windows 폴더에 `smoke_animation.blend`, `smoke_animation.glb`, `gpu_render.png`, 단계별 JSON·로그, `run_smoke.py`, `smoke_blender.py`가 있다. 기존 사용자 에셋을 편집하지 않은 연결 시험이다. 이 결과는 Windows 백그라운드 Blender 실행 경로에 대한 검증이며, 별도의 대화형 Blender MCP 애드온 연결까지 검증한 것으로 해석하지 않는다.
