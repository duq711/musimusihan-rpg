# 다리 절단 후 기어가기 / Crawling after leg loss

2026-09-18 · MacBook · Godot 4.7.

[36초 실제 실행 영상 / 36-second runtime video](creep_crawl.mp4)

## 적용 결과 / Result

한쪽 다리만 잃어도 약 0.48초에 걸쳐 낮은 자세로 전환한다. 손을 번갈아 뻗고 바닥을 당겨 전진하며, 남은 다리는 뒤로 끌고 간다. 멈추면 들고 있던 손도 내려놓고, 가까운 적은 일어서거나 주먹을 휘두르지 않고 낮은 자세에서 문다. 피격·대기·사망 전환에서도 낮은 자세를 유지한다.

Either leg loss blends into a low crawl over approximately 0.48 seconds. Alternating hands reach and pull while the remaining leg trails. Stopping lowers the recovering hand. Close attacks are prone bites rather than upright punches; idle, hit and death transitions remain low.

원본 GLB와 모든 클립은 보존했다. 원본의 수면 자세를 몸통·다리의 낮은 자세 기준으로 사용하고, 손의 교대 운동과 팔 관절, 고개·턱, 전환은 실제 뼈에 적용하는 코드로 만들었다. 단순히 걷기 클립을 느리게 재생하거나 새 FBX 애니메이션을 가져온 방식이 아니다.

Original assets and clips are preserved. The source sleep pose supplies the low torso/leg foundation; procedural skeletal posing supplies alternating arm IK, independent hand roots, alert head/jaw and transitions. This is neither slowed walking nor a newly imported FBX animation.

한 다리 속도 50%, 양다리 속도 18%는 유지했다. 이동 캡슐 높이는 0.86m, 기는 중 공격 거리는 1.15m이며 조준점은 낮아진 실제 가슴을 따른다. `F2 → 기본 → 크리프 절단 · 양다리 기어가기`에서 양쪽을 시험할 수 있다. 해당 시험만 체력 118로 시작해 네 번의 18 피해 후 46이 남는다. 일반 개체 체력은 변경하지 않았다.

Speed remains 50% with one leg missing and 18% with both. Crawling uses a 0.86m navigation capsule, 1.15m attack range and a posed chest aim point. The new both-leg F2 trial uses test-only 118 HP, leaving 46 after four 18-damage hits; ordinary creature health is unchanged.

## 실행 검증 / Executed validation

- `regression.log`: `creep_crawl`, `creep_enemy`, `creep_dismemberment_trial`, `creep_dismemberment`, `creep_ragdoll`, `creep_hit_query`, `test_room` **7개 통과**. 일반 테스트룸의 기존 ObjectDB 종료 경고 2개는 남아 있다.
- `crawl_final.log`: 손의 대기 접지·가슴 조준점·기존 로컬 처형과의 낮은 자세 연결 보정 후 집중 검사 **재통과**.
- `physics_report.json`: 실제 좌·우·양다리 타격, 연속 자세 전환, 실제 추적, 손뼈 교대 운동, 살아 있는 물기 접촉, 부위 타격 판정, F2 정지, 피부 바닥 높이, 낮은 자세에서 사망·래그돌 정착을 기록했다.
- 검사 표본에서 가슴/머리 중심은 바닥 위 약 0.36–0.37m다. 피부 최저점은 약 −0.024~0.020m 범위였다. 손의 앞뒤 이동 범위는 약 0.39m이며 팔이 번갈아 움직인다. 이 수치는 평평한 시험 바닥의 표본이다.
- `render.log`, `render_manifest.json`: 실제 embedded Vulkan Forward+로 3개 경우 모두 통과. 원본 파일·커서·원정 상태 보존도 확인했다.
- 영상은 960×540, 15fps, 무음, 36초이며 **540개의 서로 다른 실제 GPU 프레임**을 그대로 인코딩했다. 프레임 사이 실제 물리 4틱(60Hz)을 검사했고, 보간·복제·생성 이미지를 사용하지 않았다. `decode.log`에서 540프레임 전체 디코딩을 확인했다.
- 0–12초 왼다리, 12–24초 오른다리 측면, 24–36초 양다리다. 영상 끝까지 실제 물기 접촉은 각각 4·4·1회였다. 검수용 카메라가 따라가는 격리 장면이며, 플레이어가 직접 검을 휘두르는 던전 1인칭 녹화는 아니다.
- 생성한 검증 프로세스는 종료했고 기존 사용자 Godot 편집기는 유지했다.

Seven related suites passed, followed by a focused rerun after final idle/aim/execution compatibility adjustments. Real left/right/both-leg cuts, low movement, alternating hands, bite contacts, posed hit queries, pause, grounding and prone death were checked. The existing general test-room shutdown warnings remain. The 36-second studio capture contains 540 unique GPU frames under continuous 60Hz physics, with full MP4 decoding and unchanged source/session/cursor checks. It is a runtime inspection recording, not first-person dungeon play or generated imagery.

## 파일과 재현 / Files and reproduction

제작: `scripts/creep_crawl.gd`, `creep_enemy.gd`, `creep_dismemberment.gd`, `creep_ragdoll.gd`. 시험: `tests/creep_crawl_test.gd`, `creep_crawl_preview.gd`, 기존 부위 절단·F2 시험과 카탈로그. 원본 중간 프레임은 `/private/tmp/creep-crawl-video_02/frames/`에 두고 영상·선택 이미지·해시·로그를 공유한다.

```sh
./godot-game/tests/run_headless_tests.sh creep_crawl creep_enemy creep_dismemberment_trial creep_dismemberment creep_ragdoll creep_hit_query test_room
CREEP_CRAWL_QA_ITERATION=video_02 CREEP_CRAWL_VIDEO=1 \
GODOT_PREVIEW_TIMEOUT_SECONDS=600 /usr/bin/caffeinate -i \
./godot-game/tests/run_embedded_preview.sh creep_crawl_preview.gd
```

재촬영 시 새 iteration 이름을 쓴다. `CREEP_CRAWL_VIDEO`를 생략하면 선택 PNG만 렌더링한다. `caffeinate`는 촬영 중에만 절전을 막고 지속 설정을 변경하지 않는다.

Use a fresh iteration name for each capture. Without the video flag only selected PNGs are rendered. Scoped caffeinate prevents idle sleep only during the job.

## 남은 범위와 공유 / Limits and publication scope

평평한 바닥을 기준으로 만든 동작이다. 각 손·남은 발을 계단/경사면에 따로 맞추는 지형 IK와 다수의 시체 위 이동은 미확인이다. 목/다리의 단색 절단면과 단일 강체인 분리 조각은 이전 구현을 유지한다. 이번 영상은 새 기는 자세 검수용이며 해당 영역의 추가 미술 제작은 포함하지 않는다.

The motion is validated on a flat floor. Per-hand/foot terrain IK on stairs/slopes and traversal over corpse piles remain unverified. Existing flat cut-surface materials and single-rigid-body detached parts are retained.

원래 iCloud Git 인덱스와 다른 진행 중 작업을 보존하려고 기존 게시 복사본에 이번 작업의 변경분만 적용했다. 로컬에 별도로 진행 중인 처형 기능 전체는 포함하지 않았다. 해당 로컬 기능에 적용·검증한 4줄의 기는 자세 보정은 `tools/patches/creep_crawl_execution_compat.patch`로 함께 공유한다. 그 기능이 없는 공개 코드에서는 선택적 처형 검사를 건너뛴다. 로컬 기존 처형은 새 집중 검사에서 실제 진입·진행·사망까지 낮은 자세를 확인했다.

Only this task's changes are applied to the publication copy, preserving the original iCloud index and unrelated work. The separate local execution feature is not swept into this commit. Its four-line prone compatibility fix is supplied as `tools/patches/creep_crawl_execution_compat.patch`; the optional test skips when that separate feature is absent. The existing local feature passed actual entry/progress/death low-pose checks.
