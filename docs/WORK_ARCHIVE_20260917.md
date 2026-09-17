# 기존 제작 자료 공유 / Historical production archive

2026-09-17 사용자의 기존 작업물 공유 요청에 따라, 원본 위치를 보존하며 과거 제작 자료를 `codex/project-archive-20260917` 브랜치로 정리했습니다. 현재 진행 중인 게임 코드 변경은 이 아카이브에 섞지 않았습니다. 기존에 추적되던 게임 파일과 후속 작업은 각 작업 브랜치의 Git 기록을 확인하세요.

This archive preserves original file locations and adds historical production materials on `codex/project-archive-20260917`, as requested on 2026-09-17. Active game-code changes are kept in their own task branches. Consult those branches for already tracked game files and subsequent development.

## 포함 범위 / Included scope

- 파일 15,019개: 모델·모션·텍스처·제작 스크립트·기획·검증 결과·이전 프로토타입·내보낸 결과. / 15,019 files: models, animation, textures, production scripts, design, validation reports, earlier prototypes, and exports.
- Git LFS로 보관하는 대용량 파일의 고유 객체 4,197개, 약 13.63GB. 경로가 달라도 내용이 같으면 객체를 공유합니다. / 4,197 unique large-file objects, approximately 13.63GB, stored in Git LFS; identical content is deduplicated.
- iCloud 미다운로드 파일 223개는 내려받은 뒤 포함했습니다. 아카이브 대상 중 다운로드 미완료 파일은 없습니다. / All 223 initially unavailable iCloud files were downloaded and included; no in-scope files remain offline.

파일별 경로·크기·SHA-256·보관 방식·제외 사유는 [전체 목록](WORK_ARCHIVE_20260917.json)에 기록했습니다. 이미 Git에 있던 파일은 이 목록에 중복 기록하지 않습니다.

The [manifest](WORK_ARCHIVE_20260917.json) records paths, sizes, SHA-256 values, storage, and exclusion reasons. Files already tracked by Git are not duplicated in this inventory.

## 원본 보존 및 제외 / Preservation and exclusions

재생성 가능한 캐시, 임시 파일, 별도 설치 도구, 기존 Git 제외 대상 등 572개를 업로드 대상에서 제외했습니다. 추가 7개는 재배포 권한을 확인하지 못한 외부 원본, 직접 촬영한 손 참고 사진, 참고 사진을 포함한 ZIP 묶음입니다. ZIP과 별도로 존재하는 공개 가능한 개별 제작 결과와 내용 검토를 통과한 ZIP 17개도 포함했습니다. 이 파일들도 로컬 원본은 그대로 보존합니다.

572 entries are excluded as regenerable caches, temporary files, external tool installations, or existing Git exclusions. Another 7 entries are held: external sources without confirmed redistribution rights, personal hand-reference photos, and a ZIP bundle containing a personal reference photo. Eligible unpacked production outputs and 17 inspected ZIP bundles are included. All original local files remain preserved.

명시적으로 재배포 제한된 Creep·Hunyuan 원본과 인증 정보는 공개 대상이 아닙니다. 완전한 로컬 폴더 접근과 공개 GitHub 공유의 범위는 다릅니다.

Explicitly restricted Creep/Hunyuan sources and credentials are outside public sharing. Local workspace access and public GitHub publication have different scopes.

## 확인 방법 / Verification and retrieval

복사한 모든 파일의 SHA-256과 모든 고유 LFS 객체의 해시를 확인했습니다. 텍스트에는 알려진 인증 키 형식과 비밀키 표식을 검사했습니다. 이 작업은 제작 자료 보관과 연결 문서 작업이므로 게임 동작을 수정하거나 게임 실행 검증을 다시 수행하지 않았습니다.

Every archived file and unique LFS object was checked by SHA-256. Text was scanned for known credential formats and private-key markers. This task changes archive and handoff material; it does not change game behavior or rerun game execution tests.

이 브랜치는 자료 공유용이며, 최신 게임 작업을 통합한 배포 브랜치가 아닙니다. 기존 작업 폴더에서 브랜치를 전환하기 전에 진행 중인 변경을 보존하세요. 다른 컴퓨터에서 전체 자료가 필요하면 Git LFS를 설치한 환경에서 이 브랜치를 별도로 복제하고 `git lfs pull`을 실행합니다.

This is a production archive branch, not an integrated game release. Preserve ongoing edits before switching branches. To retrieve it on another computer, clone this branch into a separate folder with Git LFS installed, then run `git lfs pull`.

[앱 연결과 작업 인계 안내 / App connection and handoff](CHAT_ON_STEROIDS.md)
