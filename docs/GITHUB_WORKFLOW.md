# GitHub 작업 안내 / GitHub workflow

대상 / Repository: https://github.com/duq711/musimusihan-rpg

공개 범위 / Visibility: 공개 / Public (사용자 요청 / At the user's request)

2026-09-16 사용자 지시에 따라 이후 게임 작업을 GitHub에 반영하고, 작업 설명은 한국어와 영어로 함께 남깁니다.

Following the user's instruction on 2026-09-16, publish subsequent game work to GitHub and describe it in both Korean and English.

2026-09-17 사용자가 재확인한 공유 범위는 모든 게임 작업입니다. 아이템 추가·수정·삭제, 캐릭터 모델 추가·교체·삭제를 포함하며 맵·UI·상인·퀘스트·밸런스·코드·기획·에셋에도 동일하게 적용합니다. 모든 분야 담당자는 작업 단위가 끝나면 관련 검증부터 원격 반영 확인까지 수행합니다.

On 2026-09-17, the user reconfirmed that sharing covers all game work, including item additions, changes and deletions; character model additions, replacements and deletions; maps, UI, merchants, quests, balance, code, design and assets. Every contributor must complete the relevant checks and verify publication when a unit of work is finished.

## 작업 순서 / Steps

1. 현재 브랜치·원격 상태·다른 진행 중 변경을 확인합니다. / Check the current branch, remote state, and other work in progress.
2. 게임 지침에 따라 구현과 관련 검증을 마칩니다. / Complete implementation and the relevant checks required by the game instructions.
3. 해당 작업의 코드·기획·에셋·필요한 제작 원본·검증 요약만 선택하여 커밋합니다. 신규 파일뿐 아니라 수정·삭제·이름 변경도 검토하여 포함하고, 다른 진행 중 작업은 섞지 않습니다. 게임에서 사용하는 파일을 삭제·교체할 때도 원본 제작 자료는 보존합니다. / Commit only the task's code, design, assets, required production sources, and validation summary. Review and include modifications, deletions and renames as well as new files, without mixing in other work in progress. Preserve original production materials when deleting or replacing files used by the game.
4. 커밋 제목·설명은 한국어와 영어로 함께 작성합니다. / Write commit titles and descriptions in Korean and English.
5. 브랜치를 푸시하고 GitHub의 커밋 SHA와 로컬 SHA가 같은지 확인합니다. LFS 에셋도 업로드되어야 완료입니다. / Push the branch and verify that GitHub and local commit SHAs match. LFS assets must also be uploaded for completion.
6. 사용자에게 변경 내용·검증 결과·GitHub 링크를 한국어 먼저, 영어 다음으로 설명합니다. / Report the changes, validation results, and GitHub link in Korean first, then English.

새 기능을 별도로 개발할 때는 `codex/` 접두사의 브랜치를 사용하고, PR을 만들면 제목·본문도 한·영으로 작성합니다. 사용자가 승인한 일반적인 커밋·푸시는 매번 다시 허락을 구하지 않습니다. 공유 기록을 덮는 강제 푸시는 하지 않습니다.

Use a branch with the `codex/` prefix when developing a feature separately. If creating a PR, use a bilingual title and body. Routine commits and pushes are already authorized. Do not force-push over shared history.

## 설명 예시 / Example

```text
fix: 방패 방어 시 기력 소모 수정 / Fix stamina drain while blocking

한국어: 방패를 든 동안 기력이 중복으로 줄어들던 문제를 수정했습니다.
검증: 해당 기능과 테스트룸의 관련 자동 검증을 통과했습니다.

English: Fixed duplicate stamina drain while holding the shield up.
Validation: The relevant feature and test-room checks passed.
```

위 내용은 작성 형식 예시이며 실제 수정·검증 기록이 아닙니다.

The text above is a formatting example, not a record of an actual fix or test run.

## 에셋과 초기 자료 / Assets and initial materials

`.gitattributes`에 지정한 바이너리는 Git LFS를 사용합니다. Git LFS가 없는 환경에서는 에셋을 커밋하기 전에 먼저 설치합니다. 기존 제작 자료는 삭제하거나 이동하지 않습니다. `.gitignore`로 제외된 검증 결과 중 공유에 필요한 증거는 검토 후 해당 파일만 명시적으로 추가합니다.

Binary formats listed in `.gitattributes` use Git LFS. Install Git LFS before committing those assets. Do not delete or move existing production materials. If a validation artifact excluded by `.gitignore` is needed as evidence, review it and explicitly add only that file.

첫 업로드의 범위는 루트 README를 따릅니다. 이후 새 제작 결과는 과거 자료가 들어 있는 폴더에 저장되더라도 해당 작업 파일을 명시적으로 선택하여 반영합니다. 폴더 전체를 무조건 추가하지 않습니다.

Follow the root README for the initial upload scope. For future production work, explicitly include the relevant new files even when they are saved alongside historical materials. Do not blindly stage entire directories.

## 연결 상태 / Connection state

GitHub 플러그인 연결과 로컬 Git 인증은 별개입니다. 플러그인의 저장소 접근이 성공해도 로컬 Git·LFS 업로드에는 별도 인증이 필요할 수 있습니다. 업로드가 막히면 로컬 작업·커밋을 보존하고 미반영 항목을 명확히 알립니다.

The GitHub plugin connection and local Git authentication are separate. Successful plugin access does not guarantee that local Git and LFS can upload. If an upload is blocked, preserve local work and commits and clearly report what has not reached GitHub.

이 Mac에서는 프로젝트 전용 GitHub CLI·Git LFS가 `.local-tools/`에 설치되어 있습니다. `sh tools/git-project.sh <Git 명령>`을 사용하면 필요한 도구 경로를 함께 적용합니다. 예: `sh tools/git-project.sh status`, `sh tools/git-project.sh push -u origin main`. 이 명령은 자동으로 파일을 추가하거나 커밋하지 않습니다.

On this Mac, project-local GitHub CLI and Git LFS binaries are installed in `.local-tools/`. Use `sh tools/git-project.sh <Git command>` to include them on the tool path; for example, `sh tools/git-project.sh status` or `sh tools/git-project.sh push -u origin main`. The wrapper does not automatically stage or commit files.
