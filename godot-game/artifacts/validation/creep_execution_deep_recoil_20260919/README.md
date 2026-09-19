# 깊은 찌르기에 집중한 움찔 / Deep-push recoil and delayed extraction

첫 찌르기 때의 움찔을 없애고, 깊게 찌르는 마지막 구간에서 크게 한 번 움찔하도록 바꿨습니다. 결정타 후 검은 약 0.44초 같은 위치를 유지한 뒤 들어간 방향을 따라 빠집니다. 준비 전 대기를 다시 추가하지 않았으며, LMB 0.4초 이상 누르기→놓기 조작은 유지합니다.

The shallow stab no longer causes a flinch. One strong contraction occurs in the final part of the deeper push. The sword stays in place for approximately 0.44 seconds after lethal contact, then withdraws along its insertion axis. No pre-thrust pause was reintroduced; the existing hold-LMB-for-0.4-seconds and release input remains.

- `creep_execution_deep_recoil.mp4`: 실제 Godot GPU 영상 18초, 960×540, 30fps, 540프레임, 무음. 한쪽 다리 1인칭 → 측면 재실행 → 양다리 1인칭. / Actual Godot GPU video: single-leg first person, side repeat, both-leg first person.
- `*_stage_*.png`: 39장. 첫 찌르기 무반응, 깊은 움찔, 유지 중간·끝, 회수를 포함합니다. / 39 actual phase stills including quiet shallow contact, deep recoil, mid/late buried hold and extraction.
- `render_manifest.json`, `physics_report.json`, `validation_summary.json`, `*.log`: 실제 관절·접촉·시간·검증과 소스 해시 근거. / Actual bones, contact, timing, validation and source-hash evidence.

자동 검사 `creep_execution`, `creep_execution_trial` 2종과 실제 GPU 검수, MP4 인코딩 및 540프레임 전체 디코딩을 통과했습니다. 세 렌더 사례 모두 첫 찌르기의 관절 자세를 유지하고 깊은 찌르기에서 크게 반응하며 한 번만 사망합니다. 단위 검사에서 깊이 유지 중 검끝 이동은 2mm 이내였고, 취소·포복 복귀·기존 랙돌 연결·테스트룸 상태 복원을 확인했습니다. 전체 처형 동작은 2.24초입니다.

Both targeted suites, actual GPU checks, encoding and complete 540-frame decoding passed. All three rendering cases preserve the initial shallow pose, recoil strongly on deep contact and die once. The physical test keeps the buried blade tip within 2mm and checks cancellation, crawl recovery, existing ragdoll continuity and test-room state restoration. The execution lasts 2.24 seconds.

실제 측면·1인칭 이미지를 열어 검이 깊게 들어간 채 유지된 뒤 빠지는 모습을 확인했습니다. 기존 사망 랙돌은 대기 중에도 이어지며 이번 작업에서 물리 코드를 바꾸지 않았습니다. 평평한 시험 바닥의 현재 모델 검수이며 경사·계단·다른 적 크기와 수동 던전 플레이는 미확인입니다. 측면에는 1인칭 팔만 표시됩니다. 원격 반영 근거는 프로젝트 제작 자료의 `asset-staging/creep_execution_deep_recoil_20260919/publication.json`을 따릅니다.

Actual first-person and side images were opened to inspect the buried hold and extraction. Existing death ragdoll continues during the hold; no physics-controller changes were needed. Checks cover current models on a flat inspection floor. Slopes, stairs, other enemy sizes and a manual dungeon playthrough remain unverified. The side inspection shows first-person arms only. Publication evidence is stored in `asset-staging/creep_execution_deep_recoil_20260919/publication.json` in the production workspace.
