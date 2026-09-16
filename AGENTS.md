# 작업 대상과 필요한 문서

게임 구현·수정·검증의 기본 대상은 `godot-game/`입니다. `game/`은 이전 웹 프로토타입으로, 사용자가 지정한 경우에만 수정·배포합니다. 기존 사용자 변경·게임 데이터를 보존하고, 원본 에셋과 제작 자료는 기존 위치에 보존합니다.

- 게임 작업 전: [Godot 지침](godot-game/AGENTS.md)을 확인하고 테스트룸 완료 조건과 방해 없는 검증 규칙을 따릅니다.
- 신규 기획·기능 작업: [게임 방향](godot-game/design/GAME_DIRECTION.md)의 확정 컨셉·미정 사항과 [담당 범위·인수 기준](godot-game/design/TEAM_ROLES.md)을 확인합니다.
- 테스트룸 확장·조작 변경: [테스트룸 안내](godot-game/TEST_ROOM.md)의 관련 항목을 읽습니다. 그 외 작업은 필요한 문서·부분만 확인합니다.

# 기획과 협업

사용자가 지정한 총괄 PD는 중심 경험·제작 우선순위·분야 간 의존관계·통합 품질을 관리하며, 각 담당자는 지정된 역할을 유지합니다. 사용자 확정 컨셉, PD 제안, 미정 규칙, 실제 구현·검증 상태를 구분합니다. 이후 사용자 지시가 우선하며, 결정이 바뀌면 해당 기획 문서도 갱신합니다.

# GitHub 공유와 한·영 설명 / GitHub sharing and bilingual communication

- 2026-09-16 사용자 지시: 이 게임의 작업 결과는 `https://github.com/duq711/musimusihan-rpg` 리포지터리에 지속적으로 반영합니다. 사용자의 후속 지시에 따라 공개 리포지터리로 운영합니다. 작업 단위가 완료되면 관련 검증을 마치고 해당 변경을 커밋·푸시한 뒤 원격 반영 여부를 확인합니다. 이 지시는 이후 게임 작업에도 적용되며, 통상적인 해당 리포지터리 업로드를 매번 재승인받지 않습니다.
  User instruction dated 2026-09-16: Share this game's work in the repository above. A subsequent user instruction makes this a public repository. After completing a unit of work and the relevant checks, commit and push its changes, then verify the remote result. This authorization also applies to future game work; routine uploads to this repository do not require repeated confirmation.
- 커밋 메시지, PR 제목·설명, 작업 결과·검증 요약은 쉬운 한국어와 영어를 함께 작성합니다. 사용자에게는 한국어를 먼저 설명하고 같은 핵심 내용을 영어로 덧붙입니다. 코드 식별자나 파일 경로를 번역할 필요는 없습니다.
  Write commit messages, PR titles and descriptions, and work and validation summaries in both plain Korean and English. Explain the result in Korean first, followed by the same key information in English. Code identifiers and file paths do not need translation.
- 현재 작업에 속한 변경만 묶고 다른 진행 중 작업을 임의로 커밋하지 않습니다. 재생성 가능한 캐시·임시 파일·인증 정보는 업로드에서 제외합니다. 원본 제작 자료는 보존하고, 대용량 에셋은 크기를 확인하여 적절한 저장 방식을 적용합니다.
  Commit changes belonging to the current task without sweeping in unrelated work in progress. Exclude regenerable caches, temporary files, and credentials. Preserve original production materials and check large asset sizes before choosing how to store them.
- 연결·권한·파일 크기 문제로 업로드가 막히면 로컬 작업을 보존하고, 로컬 완료·커밋 완료·GitHub 반영 완료를 구분해 알립니다. 원격 확인 없이 동기화 완료라고 보고하지 않습니다.
  If authentication, permissions, or file size blocks an upload, preserve the local work and distinguish local completion, committed changes, and confirmed GitHub publication. Do not report synchronization as complete without verifying the remote state.
- 이 Mac의 프로젝트 전용 Git 도구는 `sh tools/git-project.sh <명령>`으로 사용합니다. 자세한 절차는 [GitHub 작업 안내](docs/GITHUB_WORKFLOW.md)를 따릅니다.
  On this Mac, use `sh tools/git-project.sh <command>` for project-local Git tooling. See the [GitHub workflow](docs/GITHUB_WORKFLOW.md) for details.

# Blender 제작

- 2026-09-11 사용자 지시에 따라 **모든 Blender 작업은 MacBook이 기본**입니다. 모델링·리깅·모션·베이크·렌더링·검증에 적용하며 이전 Windows 기본 원칙과 양손 작업 한정 예외를 대체합니다. Windows는 사용자가 별도로 지정한 작업에만 사용합니다.
- 시작 시 실제 실행 위치와 연결 상태를 확인합니다. Mac 백그라운드 실행을 우선하고, 실시간 MCP가 없으면 파일 기반 MCP 또는 Blender CLI로 진행합니다. 일반 작업을 Windows 연결·인증 때문에 멈추지 않습니다.
- 원본은 보존하고 결과를 별도 산출물로 저장·검증한 뒤 게임에 통합합니다. 게임 기능을 추가·확장하면 Godot 지침의 테스트룸 완료 조건도 적용합니다.
