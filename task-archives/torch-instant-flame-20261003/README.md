# 횃불 즉시 점화 / Instant torch ignition

F/L 즉시 점화와 화르륵 1회 소리를 적용했습니다. 3초 대기·카운트다운·부싯돌 소리는 제거했으며, 즉시 소등과 주머니 수납 모션 제거를 유지합니다. 검증된 실행본을 기존 Mac Dock 연결에 설치했습니다.

F/L lights the torch immediately with one short flame whoosh. Delay, countdown and flint sounds are removed; instant extinguishing and no pocket stowing remain. The verified player is installed at the existing Mac Dock target.

- Unity compile passed; 5 PlayMode audio tests plus 3,533 native torch checks passed (3,538 total).
- Local task commit: `3f0f74ca2bf1fc5c74968b4fdec2f1b1dd0630e2`.
- `task-bundle.json` contains all 16 changed files as a verified binary-capable Git patch, plus the actual WAV payload and validation report.
- WAV SHA-256: `d2ada11822edf8ce07add06cab7335b93747f061c0b2ba75efee4ae3ca5c0574`.
- Embedded PCM and WAV match exactly; one-time native cache avoids duplicating packaged art.

로컬 Git/LFS 인증이 없어 전체 브랜치 푸시는 실패했습니다. 이 자료는 연결된 GitHub로 게시한 전체 작업 재현 패키지이며, 원래 브랜치나 LFS 저장소의 동기화 완료를 뜻하지 않습니다. 앞선 횃불 변경 패키지도 이 브랜치의 task-archives에 보존되어 있습니다.

Local Git/LFS authentication blocked the full branch push. This is a complete task archive published through connected GitHub, not confirmation of branch/LFS synchronization. Earlier torch task archives are preserved on this branch.

복원 / Restore: decode and gunzip the patch, apply it on the recorded parent (or restore the prior archived task first), then decode each binary payload over its Git LFS pointer path. Verify each recorded SHA-256. Original production assets and unrelated work are excluded from this task commit.
