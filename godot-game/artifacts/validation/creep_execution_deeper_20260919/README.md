# 더 깊은 검 찌르기 / Deeper sword execution

마지막 깊은 찌르기를 **22cm → 36cm**로 늘렸습니다. 팔을 늘이는 대신 실제 접근 목표를 **1.05m → 0.88m**로 바꿔 더 가까이 접근합니다. 첫 얕은 찌르기 4.5cm, 깊게 찌를 때의 큰 움찔, 결정타 뒤 0.44초 유지와 총 2.24초 동작은 유지합니다.

The finishing thrust now inserts **36cm instead of 22cm**. Physical approach distance changes from **1.05m to 0.88m**, bringing the player closer while keeping original arm lengths. The 4.5cm first stab, strong deep-push recoil, 0.44-second hold and 2.24-second action timing remain.

- `creep_execution_deeper.mp4`: 실제 Godot GPU 18초·960×540·30fps·540프레임·무음. 한 다리 1인칭 → 측면 재실행 → 양다리 1인칭. / Actual Godot GPU video: single-leg first person, side repeat, both-leg first person.
- `*_stage_*.png`: 주요 단계 39장. / 39 actual phase stills.
- `render_manifest.json`: 실제 프레임·검끝 깊이·관절·소스 해시. / Actual frames, insertion depth, joints and source hashes.
- `physics_report.json`, `validation_summary.json`, `*.log`: 피부 교차점·팔 길이·자동 검사·영상 디코딩 근거. / Posed-skin crossings, arm lengths, test and video decode evidence.

자동 검사 `creep_execution`, `creep_execution_trial`과 실제 GPU 검수, MP4 인코딩·전체 디코딩을 통과했습니다. 실제 몸통의 변형된 피부 삼각형에서 진입면과 반대편 출구를 구했고, 세 다리 상태 모두 결정타 칼끝이 출구보다 약 31.6–33.3cm 안쪽에 남았습니다. 이 측정은 가장 깊게 찌른 순간의 자세입니다. GPU의 첫 찌르기·깊은 접촉·유지 후반·회수 완료 표본에서 어깨 보정은 0m였고 상완 0.34m·전완 0.26m를 보존했습니다. 각 렌더 사례의 사망은 한 번입니다.

Both targeted tests, actual GPU checks, encoding and full decoding passed. CPU-skinned torso triangles provide entry and opposing exit surfaces; at the deepest pose the tip remains approximately 31.6–33.3cm before the exit in all three leg states. GPU samples at initial contact, deepest contact, late hold and completed extraction record zero shoulder correction, retaining 0.34m upper arms and 0.26m forearms. Each render case has one death.

1인칭과 측면 이미지를 직접 열어 노출된 칼날이 줄고 더 깊이 들어간 모습을 확인했습니다. 실제 피부 검사는 결정타 자세이며 이후 모든 랙돌 프레임에 대한 미관통 보장은 아닙니다. 현재 모델·평평한 시험 바닥을 검수했고, 경사·계단·다른 적 크기와 수동 던전 플레이는 미확인입니다. 측면에는 1인칭 팔만 표시됩니다. 원격 확인 기록은 프로젝트 제작 자료의 `asset-staging/creep_execution_deeper_20260919/publication.json`입니다.

Actual first-person and side images were opened to verify that less blade remains exposed. Geometric containment checks cover the deepest pose, not every later ragdoll frame. Current models on a flat inspection floor are covered; slopes, stairs, other enemy sizes and a manual dungeon playthrough remain unverified. Side inspection shows first-person arms only. Remote verification is recorded in `asset-staging/creep_execution_deeper_20260919/publication.json` in the production workspace.
