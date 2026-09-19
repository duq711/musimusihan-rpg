# 포복 크리프 찌르기 · 대기 제거와 피격 반응 / Immediate stab and contact recoil

처형 준비 뒤 멈춰 있던 구간을 없앴습니다. 0.30초 동안 움직이며 겨냥한 뒤 바로 찌릅니다. 검이 피부에 닿으면 가슴과 머리가 짧게 움찔하고, 깊게 밀어 넣을 때 더 크게 반응한 뒤 랙돌로 이어집니다. 기존 처형 입력인 LMB 0.4초 이상 누르기→놓기는 유지합니다.

The moving preparation now flows directly into the thrust at 0.30 seconds. Actual chest/head bones flinch at skin contact, then contract more strongly during the deeper finishing push before death ragdoll takes over. The existing hold-LMB-for-0.4-seconds and release input remains unchanged.

- `creep_execution_recoil.mp4`: 실제 Godot GPU 영상 18초, 960×540, 30fps, 540프레임, 무음. 한쪽 다리 1인칭 → 동일 기능 측면 재실행 → 양다리 1인칭 순서입니다. / Actual 18-second Godot GPU video: single-leg first person, separate side repeat, then both-leg first person.
- `*_stage_*.png`: 실제 렌더의 주요 단계 33장. / 33 phase stills from the real rendering.
- `render_manifest.json`: 프레임별 자세·반응·체력, 소스 14개 해시와 검수 결과. / Per-frame poses, recoil, health, 14 source hashes and checks.
- `physics_report.json`, `validation_summary.json`, `*.log`: 접촉·관절·취소·사망 검사와 인코딩·전체 디코딩 기록. / Physical contact, bone motion, cancellation, death, encoding and full decode evidence.

자동 검사 4종과 실제 GPU 검수가 통과했습니다. 최초 테스트룸 검사는 F2 설명에서 ‘랙돌’ 단어가 빠져 실패했으며, 설명 복구 후 해당 검사를 다시 통과했습니다. 서 있는 적의 기존 처형은 유지합니다. 첫 찌르기는 약 4.5cm, 깊은 찌르기는 약 22cm이며, 각 사례의 사망·보상은 한 번입니다. 준비·찌르기·깊은 밀기·회수까지 전체 모션은 1.96초입니다.

Four headless suites and actual GPU checks passed. The initial trial check failed only because its F2 description omitted the word “ragdoll”; restoring the wording and rerunning passed. Standing executions are preserved. The shallow/deep targets are approximately 4.5/22cm, with one death/reward per case. The full action lasts 1.96 seconds.

검수 범위는 평평한 시험 바닥과 현재 모델입니다. 경사·계단·다른 적 크기와 OS 입력으로 진행한 던전 플레이는 미확인입니다. 측면 영상에는 1인칭용 팔만 표시되며 별도의 3인칭 캐릭터 모델은 없습니다. 원격 반영은 프로젝트 제작 자료의 `asset-staging/creep_execution_recoil_20260919/publication.json` 기록을 따릅니다.

Checks cover current models on a flat inspection floor. Slopes, stairs, other enemy sizes and a manual OS-input dungeon playthrough remain unverified. The side inspection shows first-person arms, not a separate third-person player model. Remote publication is recorded in `asset-staging/creep_execution_recoil_20260919/publication.json` in the project's production workspace.
