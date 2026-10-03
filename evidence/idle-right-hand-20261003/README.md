# 평상시 오른손 제거 / Hide the idle right hand — 2026-10-03

평상시 화면 아래에 보이던 오른손을 숨겼습니다. 검·단검·활·철퇴·지팡이와 손 검토, 치료·먹기에 필요한 손은 유지합니다. 실제 Mac Metal 주방 299개·육포 580개 검사와 네 장비 소유권 확인을 마쳤고, 검증한 실행본을 기존 Dock 위치에 적용해 서명·DLL 해시·에셋 보존을 확인했습니다.

[task-bundle.json](task-bundle.json)은 이번 작업의 7파일 패치와 전후 SHA-256, 검증 기록입니다. 원래 기준 파일에 패치를 적용한 결과를 모두 재검증했습니다. 로컬 기준 커밋은 `d54c8c3fa683d54c9ad1fff9f6e7fe06c1bce545`, 작업 커밋은 `46aabf797514adc0e54015306b7e5fd8294cd8d4`와 `7f2ebc4d`입니다. 기존 Unity 프로젝트·제작 에셋이 필요하며 독립 실행 가능한 프로젝트가 아닙니다.

**인증 만료로 전체 로컬 Unity 브랜치의 push는 차단됐습니다.** 이 브랜치는 연결된 GitHub 도구로 게시한 복원 가능한 작업 자료이며 전체 브랜치 동기화 완료를 뜻하지 않습니다. 실패한 패키징·시작 시도와 동시 횃불 오디오 검사의 PCM 불일치 두 개는 검증 기록에 남겨 전체 통과로 세지 않았습니다. 이번 오른손 표시·자세 검사와 주방·먹기 검사는 통과했습니다.

---

The idle right hand at the bottom of the screen is hidden. Owned weapon, hand-review, treatment and eating hands remain. The real Mac Metal player passed 299 kitchen and 580 jerky checks and four equipment ownership cases. The verified player was installed at the existing Dock target, with strict signing, matching DLL hashes and preserved art packages.

The bundle contains the complete seven-file patch, before/after hashes and validation. Patch roundtrip was verified against the required local baseline above. It requires the existing Unity project and production assets.

**Expired local authentication blocks the full migration-branch push.** This connected-GitHub archive is a restorable task delta, not full-branch synchronization or a standalone project. Failed packaging/startup attempts and two unrelated concurrent torch-audio PCM mismatches remain explicit; they are not marked passed. Hand visibility/pose, kitchen and eating checks passed.
