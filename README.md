# 무시무시한 RPG / Musimusihan RPG

2026-10-21 사용자 재확인: **Unity Mac 게임**으로 고딕 코믹스풍 새 버전을 제작하고 **기존35개 방 던전·가구를 재사용**합니다. [새 Unity 버전과 검증](docs/UNITY_GOTHIC_ORIGIN_20261021.md). `gothic-game/`은 브라우저 대상으로 잘못 제작했던 보존 시안이며 현재 실행 대상이 아닙니다.

October21,2026: The confirmed target is a **native Unity Mac game**, rebuilt in a gothic comics style while **reusing the existing furnished35-room dungeon**. See the [native build record](docs/UNITY_GOTHIC_ORIGIN_20261021.md). `gothic-game/` is a preserved browser prototype and is not the active target.

아래 문서는 보존된 이전 버전의 역사적 안내입니다. 2026-10-03 사용자 지시에 따라 이후 작업에서 Godot을 사용하지 않습니다.

The following material is the historical guide for the preserved previous version. The October 3, 2026 user direction stops future Godot use.

---

**잔향의 성소: 검은 성물실** — Godot 4.7로 제작 중인 1인칭 다크 판타지 RPG입니다.

**Sanctuary of Echoes: The Black Reliquary** — a first-person dark fantasy RPG in development with Godot 4.7. The English title is a working translation.

## 프로젝트 열기 / Open the project

Git과 Git LFS를 설치한 뒤 다음 명령으로 내려받습니다. Godot에서 `godot-game/project.godot`를 가져와 실행합니다.

Install Git and Git LFS, then run the commands below. Import `godot-game/project.godot` in Godot to open and run the game.

```sh
git lfs install
git clone https://github.com/duq711/musimusihan-rpg.git
cd musimusihan-rpg
git lfs pull
```

## 주요 문서 / Key documents

| 문서 / Document | 내용 / Contents |
| --- | --- |
| [게임 안내 / Game guide](godot-game/README.md) | 현재 기능·조작·실행 방법 / Features, controls, and running the game |
| [테스트룸 / Test room](godot-game/TEST_ROOM.md) | 실제 기능을 시험하는 방법 / How to try implemented features |
| [게임 방향 / Game direction](godot-game/design/GAME_DIRECTION.md) | 확정 컨셉과 미정 규칙 / Confirmed concepts and open decisions |
| [협업 지침 / Collaboration instructions](AGENTS.md) | GitHub 반영과 한·영 설명 원칙 / GitHub sharing and bilingual reporting |
| [GitHub 작업 안내 / GitHub workflow](docs/GITHUB_WORKFLOW.md) | 업로드 범위·작업 절차 / Repository scope and workflow |

## 저장 범위 / Repository scope

첫 업로드 대상은 현재 `godot-game/`의 소스, 실행용 에셋, 기획, 테스트와 협업 문서입니다. 캐시·자동 백업·빌드·대량의 검증 촬영은 제외합니다. 모델·텍스처 등 바이너리 에셋은 Git LFS로 관리합니다.

The initial upload covers the current `godot-game/` source, runtime assets, design, tests, and collaboration documents. Caches, automatic backups, builds, and bulk QA captures are excluded. Binary assets such as models and textures use Git LFS.

기존 `asset-staging/`, `exports/`, `concept-art/`, `generated-assets/`, `game/`, `UE_Agent_Test/`의 과거 작업은 첫 업로드에 포함하지 않고 로컬 원본을 보존합니다. 앞으로 이 게임에서 새로 완료한 제작 결과와 필요한 원본·문서는 작업별로 선별하여 함께 반영합니다.

Historical work in `asset-staging/`, `exports/`, `concept-art/`, `generated-assets/`, `game/`, and `UE_Agent_Test/` stays preserved locally outside the initial upload. Future completed game work will include the relevant production outputs, required source materials, and documentation in its commits.

사용자 요청에 따라 이 리포지터리는 공개로 운영합니다. 타사 에셋과 폰트에 포함된 라이선스·출처 문서를 유지합니다.

This repository is public at the user's request. Keep the license and attribution documents included with third-party assets and fonts.
