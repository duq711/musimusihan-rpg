# 검날 절반을 밀어 넣는 처형 / Half-blade execution

실제 검날 길이 **1.045m의 55%, 약 57.5cm**를 밀어 넣습니다. 기존 36cm는 같은 칼날의 34.45%였습니다. 몸을 가까이 가져가는 목표 거리를 0.88m에서 0.84m로 줄이고, 깊은 찌르기에 맞춰 상체를 더 숙입니다. 실제 충돌과 원래 팔 길이를 유지합니다.

The finishing push now inserts **55% of the actual 1.045m blade, about 57.5cm**. The prior 36cm represented 34.45%. Approach distance changes from 0.88m to 0.84m, and a deeper body lean follows the push while preserving collisions and original arm lengths.

첫 찌르기 4.5cm → 깊은 찌르기에서 큰 움찔 한 번 → 0.44초 유지 → 같은 축으로 뽑기 순서와 총 2.24초 길이는 유지합니다. 검을 줄이거나 숨기는 효과가 아니라 실제 3D 칼날의 이동과 몸통의 깊이 가림입니다.

Timing remains a 4.5cm initial stab, one strong deep-push recoil, a 0.44-second buried hold and same-axis withdrawal, totaling 2.24 seconds. This moves the actual 3D blade into the body with normal depth occlusion; it does not scale or hide the sword.

- `creep_execution_half_blade.mp4`: 실제 Godot GPU 18초·960×540·30fps·540프레임·무음. 한 다리 1인칭 → 측면 재실행 → 양다리 1인칭. / Actual GPU video: single-leg first person, side repeat, both-leg first person.
- `*_stage_*.png`: 주요 단계 39장. / 39 actual phase stills.
- `render_manifest.json`: 독립 칼날 정점 측정·프레임·관절·소스 해시 16개. / Independent blade vertex measurements, frames, joints and 16 source hashes.
- `physics_report.json`, `validation_summary.json`, `*.log`: 실제 피부 교차점·자동 검사·영상 전체 디코딩 근거. / Actual posed-skin crossings, test and full video decode evidence.

`creep_execution`, `creep_execution_trial`은 최종 코드로 통과했습니다. 같은 개정에서 `sword_shield_execution`도 통과했으며 이후 수정은 포복 처형의 접근·상체 숙임에 한정했습니다. 숨김 GPU 검수와 영상 인코딩·전체 디코딩을 통과했습니다. 모든 렌더 사례에서 사망은 한 번이며 원래 상완 0.34m·전완 0.26m를 보존하고 첫 찌르기·최대 깊이·유지 후반·회수 완료 표본의 어깨 보정은 0m입니다.

The final code passes the crawl-execution and test-room suites. Standing sword/shield execution regression also passed in this revision, before crawl-only approach/lean refinements. Hidden GPU validation, encoding and full decoding pass. Every render case records one death, original 0.34m upper arm and 0.26m forearm lengths, and zero shoulder correction in initial-contact, deepest, late-hold and extracted samples.

양쪽 다리 상태를 포함한 세 결정타 자세에서 실제 변형된 피부 삼각형을 검사했습니다. 실제 피부 진입면을 기준으로 칼날 약 55.5%가 들어가고, 칼끝은 반대편 출구보다 약 10.1–11.8cm 안쪽에 있습니다. 1인칭 두 사례의 최대 깊이 및 측면의 최대 깊이·유지 후반 이미지를 직접 열어 노출된 칼날이 줄어든 것을 확인했습니다.

Actual deformed torso triangles were checked in three deepest-contact leg states. About 55.5% of the blade lies beyond the posed skin entry, with approximately 10.1–11.8cm remaining before the far exit. The deepest first-person images for both cases and side deepest/late-hold images were directly opened to verify reduced exposed blade length.

검증 범위는 현재 모델·평평한 시험 바닥입니다. 피부 교차점의 미관통 증명은 결정타 자세이며 이후 모든 랙돌 프레임에 대한 보장은 아닙니다. 경사·계단·다른 적 크기·수동 던전 플레이는 미확인입니다. 측면은 같은 모션을 별도로 실행한 것이며 1인칭 팔만 표시합니다. 원격 반영 기록은 제작 자료 `asset-staging/creep_execution_half_blade_20260919/publication.json`입니다.

Scope is the current models on a flat inspection floor. Geometric containment proof covers the deepest pose, not every later ragdoll frame. Slopes, stairs, other enemy sizes and a manual dungeon playthrough remain unverified. Side inspection is a separate runtime repeat showing first-person arms only. Remote verification is recorded in `asset-staging/creep_execution_half_blade_20260919/publication.json` in the production workspace.
