# 평상시 오른손 제거 / Hide the idle right hand — 2026-10-03

평상시 화면 아래에 보이던 오른손을 숨겼습니다. 검·단검·활·철퇴·지팡이와 손 검토, 치료·먹기에 필요한 손은 유지합니다. 실제 Mac Metal 주방 299개·육포 580개 검사와 네 장비 소유권 확인을 마쳤고, 검증한 실행본을 기존 Dock 위치에 적용해 서명·DLL 해시·에셋 보존을 확인했습니다.

[task-bundle.json](task-bundle.json)은 이번 작업의 7파일 패치와 전후 SHA-256, 검증 기록입니다. 원래 기준 파일에 패치를 적용한 결과를 모두 재검증했습니다. 로컬 기준 커밋은 `d54c8c3fa683d54c9ad1fff9f6e7fe06c1bce545`, 작업 커밋은 `46aabf797514adc0e54015306b7e5fd8294cd8d4`와 `7f2ebc4d`입니다. 기존 Unity 프로젝트·제작 에셋이 필요하며 독립 실행 가능한 프로젝트가 아닙니다.

**인증 만료로 전체 로컬 Unity 브랜치의 push는 차단됐습니다.** 이 브랜치는 연결된 GitHub 도구로 게시한 복원 가능한 작업 자료이며 전체 브랜치 동기화 완료를 뜻하지 않습니다. 초기 패키징 실패와 PCM 불일치 두 개는 과거 시도로 보존했습니다. 후속 횃불 작업의 최종 통합 실행본은 오른손 수정 소스가 같고, 설치 DLL이 성공한 서명 검증 DLL과 일치합니다. 최신 횃불 163개 검사와 네 손 소유권 사례가 오류 없이 통과했습니다. [최종 설치 근거](final-installation.json). 추가 로컬 확인 커밋은 `17cb4ed7`입니다.

---

The idle right hand at the bottom of the screen is hidden. Owned weapon, hand-review, treatment and eating hands remain. The real Mac Metal player passed 299 kitchen and 580 jerky checks and four equipment ownership cases. The verified player was installed at the existing Dock target, with strict signing, matching DLL hashes and preserved art packages.

The bundle contains the complete seven-file patch, before/after hashes and validation. Patch roundtrip was verified against the required local baseline above. It requires the existing Unity project and production assets.

**Expired local authentication blocks the full migration-branch push.** This connected-GitHub archive is a restorable task delta, not full-branch synchronization or a standalone project. Initial packaging/startup failures and two PCM mismatches remain as historical attempts. The latest combined torch player contains the same hand-fix source; its installed DLL matches the successfully tested signed player. All 163 latest torch-control checks and four ownership cases passed without errors. See [final installation evidence](final-installation.json); the additional local verification commit is `17cb4ed7`.
