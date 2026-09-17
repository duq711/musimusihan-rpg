# 포복 하체 동작 / Lower-body crawling

2026-09-18 · MacBook · Godot 4.7

[60초 실제 하체 포복 영상 / 60-second actual lower-body crawl video](creep_lower_body.mp4)

기존 포복은 원본 수면 자세의 골반·다리 형태를 유지하고 손만 번갈아 움직여, 하체가 고정되어 끌려오는 모습이었다. 이번 변경은 엎드린 골반을 기준으로 좌우 체중 이동과 비틀림을 더하고, 남은 다리의 넓적다리·무릎·뒤 관절·발을 실제 이동 거리에 맞춰 굽히고 편다. 발을 디디며 몸을 밀고, 다리를 굽혀 발을 낮게 회수하는 순환이다. 양다리가 없을 때도 골반이 팔의 당김에 맞춰 움직이며 잘린 다리는 다시 표시하지 않는다.

The previous crawl retained the sleeping lower-body pose while alternating only the hands. The new belly-down pelvis shifts and twists with weight transfer; surviving thigh, knee, hock and foot joints articulate with actual travel. A planted push is followed by a bent-leg recovery close to the floor. Pelvic movement continues when both legs are absent, without restoring detached anatomy.

독립 루트인 Foot와 발가락 전체를 뒤 관절의 끝에 맞춰 이동한다. 원본 세 다리 구간의 길이는 유지하며, 발 표면 두께를 반영해 발목 기준 높이를 맞췄다. 이동을 멈추면 약 0.23초 동안 하체 운동이 줄어들고 쉬는 자세로 돌아온다. 상체 지지, 랙돌 착지 → 안정화 → 포복 회복, 이동 속도·물기·피해·보상 규칙은 유지한다. 원본 GLB나 원본 애니메이션 클립은 수정하지 않았다.

The independent Foot root and all toes follow the solved distal leg endpoint. All three source segment lengths remain unchanged, and ankle height accounts for foot flesh thickness. Locomotion fades into rest over approximately 0.23 seconds. Upper-body support, physical landing and recovery, crawl speeds, bites, damage and rewards are retained. Source GLBs and animation clips are not edited.

## 검증 방법 / Validation method

실제 다리 절단과 추적 상태에서 골반의 좌우 이동·회전, 관절 각도 변화, 발 연결거리, 보폭의 8개 구간 피부 높이를 측정한다. 보행에서 정지할 때 실제 뼈 위치의 연속성과 정지 후 포복 재개를 확인하며, 기존 랙돌·절단·피격·F2 정지·원정 복원 검사도 수행한다. 정확한 미술 각도를 그대로 복사한 테스트 대신 실제 피부·골격과 동작의 넓은 물리 범위를 검사한다.

Tests observe actual pelvis motion, relative joint articulation, foot attachment lengths and skin heights across eight stride intervals after real cuts. They also check walk-to-stop continuity, resuming pursuit, physical recovery, damage queries, F2 pause and expedition restoration. These are broad physical/behavioral checks on actual skin and bones rather than assertions that mirror exact artistic constants.

```sh
GODOT_TEST_TIMEOUT_SECONDS=600 ./godot-game/tests/run_headless_tests.sh creep_crawl creep_knockdown creep_dismemberment creep_hit_query creep_dismemberment_trial test_room
CREEP_CRAWL_QA_ITERATION=lower_body_01 CREEP_CRAWL_VIDEO=1 \
GODOT_PREVIEW_TIMEOUT_SECONDS=600 /usr/bin/caffeinate -i \
./godot-game/tests/run_embedded_preview.sh creep_crawl_preview.gd
```

F2 → 기본 → 크리프 절단의 왼다리·오른다리·양다리 항목을 그대로 사용한다. 해당 시험의 설명과 골반·남은 다리 정지 검사를 함께 확장했다. 새 촬영은 새로운 iteration 이름을 사용한다.

Use the existing left/right/both-leg trials under F2 → Basic → Creep dismemberment. Their descriptions and pelvis/surviving-leg pause coverage are updated together. Each capture requires a fresh iteration name.

## 범위 / Scope

평평한 정적 바닥에서의 동작이다. 계단·급경사·이동 플랫폼에 각 손발을 맞추는 지형 IK는 미확인이다. 절단면과 분리 조각의 표현은 이번 동작 수정의 대상이 아니다. 별도 작업의 절단면 개선·처형 기능이나 iCloud Git 인덱스는 보존하며 이번 변경분만 게시한다.

This motion targets a flat static floor. Per-limb terrain IK on stairs, steep slopes and moving platforms remains unverified. Cut-surface and detached-piece rendering is outside this motion change. Unrelated wound/execution work and the iCloud Git index are preserved; only this task's changes are published.


## 실행 결과 / Executed results

- `regressions.log`: 관련 6종 통과. `final_crawl.log`: 정지 완화 시간을 조정한 최종 포복 검사 재통과. 기존 일반 테스트룸의 ObjectDB 2개 종료 경고는 유지된다.
- 실제 골반의 좌우 범위는 약4.1cm, 좌우 회전 범위는 약16도다. 남은 다리는 넓적다리·무릎·뒤 관절이 각각 움직이며, 발의 앞뒤 범위는 약22–26cm다. 세 구간 연결길이의 계측 오차는 반올림상0이었다. `physics_report.json`에 실제 피부·뼈 계측을 남겼다.
- 정지 과정의 실제 하체 관절 최대 한틱 변위는 약3.71cm이며20틱 안에 안정된다. 원본 피부의 얕은 지면 겹침은 표본 최저 약1.05cm로 남아 있다. 깊은 발 관통은 높이 보정 뒤 관찰하지 못했다.
- `knockdown_report.json`: 실제 랙돌 착지·안정화 이후 자세 연결, 공중 회복 금지·추가 절단·도중 사망을 재검사했다.
- `render.log` / `render_manifest.json`: 실제 embedded Vulkan Forward+ 영상900프레임 모두 서로 다르며, 촬영 프레임당60Hz 물리4틱 진행을 확인했다. 원본 파일 해시·커서·원정 상태 보존도 통과했다.
- 0–20초 남은 오른다리 뒤쪽 사선,20–40초 남은 왼다리 반대 사선,40–60초 양다리 손실의 골반 움직임이다. 실제 공격 접촉은6·6·4회다. 생산 크리프·피격·AI를 격리된 검수 장면에서 촬영했으며, 던전1인칭 플레이 녹화나 생성 영상은 아니다.
- 실제 보폭 이미지와 회복·정지·양다리 프레임을 열어 검토했다. MP4의 전체900프레임 디코딩은 `decode.log`에 기록했다.

Six related suites passed, followed by the final focused crawl rerun. Actual pelvis range is approximately 4.1cm laterally and 16 degrees in yaw; the surviving foot travels approximately 22–26cm while all three leg segments retain their source lengths. The final walk-to-stop transition settles within 20 ticks, with maximum joint displacement approximately 3.71cm per tick. Sampled skin retains shallow ground overlap up to approximately 1.05cm. The actual 60-second Vulkan recording contains 900 unique frames, continuous 60Hz physics, left/right rear-oblique views and both-leg pelvis motion, with 6/6/4 actual bite contacts. Key frames were opened and reviewed, and full MP4 decoding completed. Original/session/cursor checks passed; the existing general test-room ObjectDB shutdown warning remains.

영상에 보이는 현재 로컬의 절단면·혈흔 표현은 별도 작업을 그대로 둔 것이다. 이번 게시 범위는 하체 동작·관련 시험·검수 자료이며 그 별도 코드 전체를 섞지 않았다. / The current local wound and blood appearance is retained from separate work visible in the runtime video; that unrelated code is not swept into this lower-body publication.
