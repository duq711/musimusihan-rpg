# 절단 후 물리 낙하와 포복 회복 / Physical collapse and crawl recovery

2026-09-18 · MacBook · Godot 4.7

[60초 실제 실행 영상 / 60-second runtime video](creep_living_fall.mp4)

다리 절단 직후 실제 관절·강체 랙돌로 쓰러진다. 몸통 또는 가슴의 실제 위쪽 지면 접촉, 낮아진 몸통·머리, 전신의 낮은 움직임 에너지가 0.35초 유지된 뒤에만 포복 회복을 시작한다. 시간 초과로 공중에서 회복하는 예외는 없다. 접지 시점의 모든 뼈 월드 자세를 보존하고 실제 착지 위치에 이동 기준점을 맞춘 뒤, 0.85초 동안 포복 자세로 이어진다. 전환 완료 전에는 이동·공격을 하지 않는다.

Either leg loss immediately activates an articulated rigid-body fall. Recovery requires actual upward torso/chest ground contacts, a low core/head and low whole-body motion energy held for 0.35 seconds. There is no airborne timeout fallback. Every solved world-space bone pose is preserved while navigation is re-anchored at the landing; an approximately 0.85-second blend then enters crawling. Chasing and attacks wait until that blend completes.

물리 중 추가 절단은 해당 관절·물리 몸체를 제거하고 착지 판정을 다시 시작한다. 낙하 중 사망하면 기존 몸체를 그대로 사망 랙돌로 전환한다. 렌더 단계뿐 아니라 물리 단계에서도 실제 뼈 자세를 동기화해 피격 위치와 포복 전환이 서 있던 자세로 돌아가지 않게 했다. 한쪽 다리/양다리 이동 속도, 낮은 물기 공격, 원본 모델·클립은 보존한다.

Additional cuts remove the corresponding physics chain and require a fresh settling check. A fatal hit promotes the existing fallen bodies into a permanent corpse. Physics-time skeletal synchronization keeps hit queries and recovery aligned with the rendered ragdoll. Existing crawl speeds, low bite attacks and original assets/clips are retained.

## 실행 검사 / Executed checks

`knockdown.log`: 왼다리·오른다리·양다리의 실제 절단, 착지 전 공격 금지, 안정화와 회복 완료 후 추적·물기, 낙하 중 추가 절단·일시정지·사망, 바닥 없는 8초 낙하에서 회복 금지를 통과했다. 물리에서 회복으로 넘어갈 때 뼈·표본 피부 위치 차이는 0.001mm 미만이며, 회복 끝에서 포복 시작 간 최대 뼈 변위는 약 1.21mm였다. `physics_report.json`에 실제 표본을 보존한다.

`knockdown.log` passes real left/right/both-leg cuts, grounded recovery, blocked combat, resumed pursuit/bites, an additional mid-fall cut, pause, fatal upgrade and eight seconds of unsupported free fall without recovery. Bone and sampled skin handoff displacement was below 0.001mm; the final recovery-to-crawl step was at most approximately 1.21mm. See `physics_report.json` for measurements.

`crawl_and_dismemberment.log`: 기존 포복·절단 2종 검사도 통과했다. 별도로 진행 중인 로컬 처형 기능은 낙하·회복 중 취약 판정을 막는 선택적 호환 보정을 적용했다. 이 호환 보정만 `tools/patches/creep_knockdown_execution_compat.patch`로 공유하며, 별도 처형 기능 전체를 이번 변경에 포함하지 않는다.

The existing crawl and dismemberment suites passed. The separate local execution work has an optional compatibility guard blocking execution during collapse/recovery; only that guard is supplied in `tools/patches/creep_knockdown_execution_compat.patch`. Unrelated execution work is not included in this publication.

## 재현 / Reproduction

```sh
GODOT_TEST_TIMEOUT_SECONDS=600 ./godot-game/tests/run_headless_tests.sh creep_knockdown creep_crawl creep_dismemberment creep_ragdoll creep_enemy creep_hit_query creep_dismemberment_trial test_room
CREEP_CRAWL_QA_ITERATION=living_fall_01 CREEP_CRAWL_VIDEO=1 \
GODOT_PREVIEW_TIMEOUT_SECONDS=600 /usr/bin/caffeinate -i \
./godot-game/tests/run_embedded_preview.sh creep_crawl_preview.gd
```

F2 → 기본 → 크리프 절단에서 왼다리·오른다리·양다리 시험을 선택한다. F2는 예약 타격·물리 낙하·회복·이동을 함께 일시정지한다. 시험이 끝나면 원래 원정·인벤토리를 복원한다. 영상 재촬영에는 새 iteration 이름을 쓴다.

Choose left/right/both-leg Creep dismemberment under F2 → Basic. F2 pauses pending hits, physical falls, recovery and locomotion. The sandbox restores the original expedition/inventory. Each render requires a fresh iteration name.

## 남은 범위 / Limits

평지에서 검증한다. 급경사·계단·시체 더미 위에서의 포복과 각 손·발의 지형 맞춤 IK는 미확인이다. 기존 단색 절단면과 분리 부위의 단일 강체 표현은 유지한다.

Validation uses flat floors. Crawling over steep slopes, stairs or corpse piles and individual hand/foot terrain IK remain unverified. Existing flat cut caps and single-body detached pieces are retained.

0.85초 회복 전환 도중 움직이는 플랫폼이나 사라지는 바닥에 대한 재접지는 구현·검증하지 않았다. / Re-grounding against moving platforms or disappearing floors during the recovery blend is not implemented or verified.


## 최종 검증 / Final validation

관련 자동 검사 **8개 모두 통과**: creep_knockdown, creep_crawl, creep_dismemberment, creep_ragdoll, creep_enemy, creep_hit_query, creep_dismemberment_trial, test_room. `related_regressions.log`에 나머지 5개 결과를 보존한다. 일반 테스트룸의 기존 ObjectDB 2개 종료 경고는 남아 있다.

All eight related automated suites passed. The existing general test-room warning about two remaining ObjectDB instances at shutdown is retained.

`render.log`와 `render_manifest.json`: 실제 embedded Vulkan Forward+의 연속 물리 60Hz / 촬영 15fps. 960×540, 무음, 60초, **900개 서로 다른 실제 GPU 프레임**이다. 0–20초 왼다리, 20–40초 오른다리 측면, 40–60초 양다리 순서로 실제 절단 → 랙돌 낙하 → 착지·안정화 → 포복 회복 → 추적·물기를 보여준다. 실제 공격 접촉은 각각 7·8·7회다. 낙하·착지·회복·포복의 PNG를 직접 열어 검토했다. 물리 접촉 근거는 세 경우 모두 몸통의 위쪽 바닥 접촉, 0.35초 안정화 유지이며 허용 문턱을 완화하지 않았다.

The real embedded Vulkan recording contains 900 unique frames at 960×540 and 15fps, with continuous 60Hz physics: left leg 0–20s, right-leg side view 20–40s, both legs 40–60s. Production localized damage, physics falls, supported recovery, crawling and bites run continuously. Actual attack contacts were 7/8/7. Opened and inspected PNGs at each key phase. All three physical handoffs required actual upward torso-floor contact and 0.35 seconds of quiet support with unchanged thresholds.

이는 게임의 실제 크리프·피격·물리·AI를 격리된 검수 장면에서 촬영한 영상이며, 던전 1인칭 플레이 녹화는 아니다. 생성 이미지나 포즈를 임의로 바꾼 컷으로 대체하지 않았다. 커서·원정·원본 파일 해시 보존도 확인했다. 공개 게시 복사본에는 이번 변경분만 적용하여 기존 로컬 처형 작업과 iCloud Git 인덱스를 보존한다.

This is a continuous inspection-scene recording of the actual game creature, damage, physics and AI, rather than first-person dungeon gameplay. No generated images or substituted poses are used. Source hashes, cursor and expedition state are preserved. Only this task's changes are applied to the publication copy, preserving unrelated local execution work and the iCloud Git index.

`decode.log`에서 MP4 전체 900프레임·60초 디코딩을 확인했다. / Full MP4 decoding verified all 900 frames over 60 seconds.
