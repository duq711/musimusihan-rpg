> 이후 사용자 재확인: 게임 실행 대상은 Unity입니다. 이 문서는 잘못 선택했던 브라우저 시안의 당시 기록입니다. 현재 작업은 [Unity 고딕 원정](UNITY_GOTHIC_ORIGIN_20261021.md)을 따릅니다. / Superseded by the confirmed native Unity target. This preserves the earlier browser prototype record; see the native build report.

# 고딕 코믹스 새 제작 / Gothic comics rebuild

시작 2026-10-20 · 검증·전달 2026-10-21. 사용자 요청은 사실적 그래픽에서 전환하며 생긴 이질감을 줄이도록 처음부터 고딕 코믹스풍으로 다시 만드는 것입니다.

Started October 20; validated and delivered October 21, 2026. The user requested a fresh gothic comics game after finding the realism-to-comics conversion inconsistent.

## 결정과 결과 / Decisions and result

- 새 작업 대상은 `gothic-game/`입니다. 현재 탐색기와 같은 Three.js/WebGL 실행 기반에서 새 코드로 형태·재질·화면을 제작했습니다. 이전 PBR 모델·사진 텍스처·Unity 장면·후처리 전환 코드를 읽어 실행하지 않습니다.
- 큰 색면, 단계 명암, 제한된 청회색·황토색·적갈색, 선택적인 기하 먹선, 공간에 고정된 붓결·긁힘을 공통 기준으로 사용합니다. 아치·석조·가구·망토·후드·검·방패·UI를 같은 제작 소스로 구성합니다.
- 35개 방 ID와 기존 개념 평면도를 이어 쓰고, 33번 생활관·34번 간수방·35번 보급 창고의 이후 용도를 적용합니다. 지하 외부 창문·바깥 풍경·창을 통한 자연광은 만들지 않았습니다. 33번은 연속 석벽과 실내 불빛으로 구성합니다.
- 검·방패·기력·피해·회복약, 상자 32개, 적 8명, 성물 3개, 지도·가방·기록, 저장·복원·패배·재시작·귀환 결말을 연결했습니다.
- 사용자 대기모드 이후 작업을 이어 완료했습니다. 게임은 포커스를 잃으면 일시정지하며, 재개 버튼으로 이어갑니다. 휴지 상태 저장 자료를 손상시키는 검사의 fixture를 수정했습니다. 활성 게임을 새로고침하면 `pagehide`가 정상 자료를 다시 저장하므로, 손상 자료 검사는 제목 화면에서 수행해야 합니다.

The new target is `gothic-game/`, using the current explorer's Three.js/WebGL approach with newly authored geometry, surfaces and interface. Broad color planes, stepped values, selective ink and fixed surface strokes share one palette. The 35 identities and concept floorplan remain, including later uses of Rooms 33–35. The underground setting has no exterior windows or daylight. The expedition connects combat, 32 chests, eight enemies, three relics, map/inventory/journal, isolated saving, defeat/retry and a return ending. Work resumed after computer sleep. The game pauses on focus loss and resumes through its menu. A corruption-test fixture was corrected to avoid active-play autosave replacing the injected invalid data.

## 검증 / Validation

**게임 기능 39개, 마지막 UI·재개·서버 검사 8개 통과.** 런타임·셰이더 오류 0개, 외부 네트워크 요청 0개입니다. 실제 Chrome 입력으로 이동·기력·충돌·조사·공격·방어·회복·저장 복원·성물 세 개·귀환·재시작을 검사했습니다. 전체 원정을 사람이 걸어 완주한 기록은 아닙니다. 전투·상호작용 검사는 QA 전용 위치 설정으로 각 상황에 접근한 뒤 실제 게임 입력과 규칙을 실행합니다. 일반 실행에서는 QA 위치 설정 API를 제공하지 않습니다.

**39 gameplay checks and eight final UI/resume/server checks passed**, with zero runtime/shader errors or external requests. Actual browser inputs drive movement, stamina, collision, interactions, attacks, blocking, healing, save restoration, all relics, return and retry. This is not a human full-route playthrough. QA-only placement approaches isolated cases before actual input/rules execute; normal launch excludes the placement API.

반경 0.25m 캐릭터 기준 0.54m 표본 격자와 연결 구간의 추가 표본으로 12,649개 점을 검사했습니다. 시작점에서 12,629개가 연결됐고 **35개 방 및 모든 상자·성물·귀환점 접근에 실패한 곳은 0개**였습니다. 가구 뒤 고립된 표본 20개가 있으므로 모든 바닥 점의 연결을 주장하지 않습니다. 실제 이동은 최대 0.12m 간격으로 벽 격자와 가구의 AABB를 검사하며, 가구 검색은 공간 인덱스를 사용합니다. 실험용 캡처와 원본 제작 자료는 구분합니다.

A 0.25m capsule, a 0.54m sample grid and additional samples along links tested 12,649 points; 12,629 connect to the start. All 35 rooms and all interactables have reachable approaches. Twenty isolated samples behind furnishings remain, so universal floor-point connectivity is not claimed. Actual movement tests wall occupancy and indexed furniture AABBs in steps no larger than 0.12m.

## 성능 / Performance

동일 Mac Apple M4, Chrome 155.0.8059.84, ANGLE Metal, 1280×900, DPR 1, MSAA, 기본 품질, 숨김·음소거 조건입니다. 새 버전은 경로당 준비 90프레임 뒤 600개 간격을 기록했습니다. 이전 탐색기도 동일 하드웨어·브라우저·해상도로 방 33–35와 실제 이동을 측정했습니다. 새 형태와 공간 규모·이동 경로가 달라 픽셀 일치 비교나 인과적인 속도 개선 주장에 사용하지 않습니다. 이전 고정 장면 표본은 각 약 4초로 길이가 다릅니다.

Same Apple M4 Mac, Chrome 155.0.8059.84, ANGLE Metal, 1280×900, DPR 1, MSAA, default quality, hidden and muted. Each new scenario records 600 frame intervals after 90 warmup frames. The earlier explorer was measured on the same hardware/browser/resolution in Rooms 33–35 and actual movement. Geometry, scale and routes differ, and earlier stationary samples last approximately four seconds, so this is not a pixel-matched or causal speedup comparison.

| 새 버전 장면 / New scenario | 평균 ms / Mean | p95 ms | 18ms 초과 / Above 18ms | 최대 제출 삼각형 / Max triangles | 최대 draw calls |
| --- | ---: | ---: | ---: | ---: | ---: |
| 33번 생활관 / Room 33 | 16.666 | 16.7 | 0% | 221,641 | 82 |
| 33번 실제 왕복 이동 / Room 33 walking | 16.666 | 16.8 | 0% | 221,641 | 82 |
| 34번 간수방 / Room 34 | 16.666 | 16.7 | 0% | 159,169 | 70 |
| 35번 보급 창고 / Room 35 | 16.666 | 16.7 | 0% | 286,771 | 94 |
| 대예배당 수호자 전투 / Chapel combat | 16.666 | 16.8 | 0% | 118,113 | 73 |

모두 평균 약60FPS이며 3,000개 간격 중 18ms·33.34ms 초과는 0개입니다. 엄격한 16.67ms 초과 비율은 60Hz 시간 양자화 때문에 약60.8~62.8%이며 작은 요약에 원래 값을 남깁니다. 모든 프레임의 고정60FPS·전경 입력 지연·모든 브라우저·해상도·전체 탐험 구간을 인증하지 않습니다. 이전 탐색기도 측정 구간은 약60FPS였으므로 FPS 향상을 주장하지 않습니다. 새 버전은 정적 지형 병합, 기하·픽셀 예산, 프러스텀 제외, 그림자 맵 없는 공유 재질로 비용을 관리합니다.

All five scenarios averaged approximately60FPS. None of 3,000 intervals exceeded18ms or33.34ms. Strict16.67ms overruns were approximately60.8–62.8% because of60Hz timestamp quantization; exact ratios remain in the summary. This does not certify every frame, foreground input latency, every browser/resolution or the entire journey. The previous explorer also averaged approximately60FPS, so no FPS improvement is claimed. Static batching, submission/pixel budgets, frustum culling and one shared surface shader without shadow maps manage cost.

## 산출물·한계·보존 / Artifacts, limits and preservation

- 실행: `gothic-game/Play.command` 또는 `python3 gothic-game/serve.py --port 8790` → [로컬 게임](http://127.0.0.1:8790/).
- 제작 원본: `gothic-game/world.js`, `game.js`, `layout.json`, `index.html`, `style.css`. 오프라인 런타임과 MIT 고지는 `vendor/`에 보존합니다.
- 재사용 검사: `tools/gothic-rebuild-20261020/validate.cjs`. 수치·검사명·소스 해시·정리량: `gothic-game/validation-summary.json`.
- 이전 `unity-game/Builds/MusimusihanRPG.app`, `~/Applications/무시무시한 RPG.app` 연결, Dock, 기존 탐색기, 모든 기존 모델·Blender·컨셉·저장 자료는 보존했습니다.
- 이번 산출물은 새 독립 원정입니다. 이전 Unity RPG의 모든 아이템·상점·제작·연금술·신체 부상·F2 항목과 음향은 포함하지 않습니다. 현재 형태는 소스 기반의 단순화된 그래픽이며, 수작업 회화 수준이나 이전 개별 제작 모델의 세밀도와 동일하다고 보고하지 않습니다.

Use the launcher or local server above. Editable production sources, the offline runtime and MIT notice, reusable validator and compact result summary are retained. The previous playable Unity app, Applications/Dock links, explorer, original models, Blender files, concepts and saves remain preserved. This new standalone expedition does not contain all previous RPG systems or audio, and does not claim hand-painted production finish or equivalent asset detail.

정리량과 현재 디스크 여유 공간은 `validation-summary.json`의 `cleanup`에 기록합니다. 검토한 캡처·전체 로그·중간 검증 자료·임시 formatter는 해당 요약을 남긴 뒤 제거했습니다. 실제 제거 할당량과 APFS에서 관측한 여유 공간 변화는 별도로 기록합니다. 실행 서버와 최신 게임 소스는 유지합니다.

The summary's `cleanup` records removed allocation, observed free-space change and current free space separately. Reviewed captures, full logs, intermediate validation outputs and temporary formatting tools were removed after compact results were retained. The running server and latest game sources remain available.

정리 결과: 할당량 **12,800,000B**, 논리 크기 12,507,335B의 임시 자료 156개 항목을 제거했습니다. 즉시 관측한 여유 증가는 **12,759,040B**, 현재 여유 공간은 **19,077,652,480B**입니다. 게임 소스·런타임·런처·요약·검사 도구와 기존 플레이 앱을 보존했습니다.

Cleanup removed **12,800,000 allocated bytes** and12,507,335 logical bytes across156 temporary entries. Observed free space increased **12,759,040 bytes** to **19,077,652,480 bytes**. Game sources, runtime, launcher, compact summary, validator and previous playable app are preserved.

## 공유 / Publication

현재 작업 파일만 `codex/gothic-origin-20261021` 브랜치에 저장합니다. 로컬 커밋·원격 푸시·원격 SHA 확인은 구분하며, 결과는 아래 전달 기록과 작은 요약에 남깁니다. 기존 체크아웃과 다른 진행 중 변경을 보존합니다.

Only task files are published on `codex/gothic-origin-20261021`. Local commit, push and remote SHA verification are tracked separately. The existing checkout and unrelated work remain preserved.

Git HTTPS 인증 부재로 일반 push는 실패했습니다. 연결된 GitHub 앱의 쓰기 권한을 확인한 뒤 Git data API로 기본 브랜치 위에 이 작업 파일만 게시했습니다. 구현 커밋 **`bd6ac428dba7b031fae82ced40bffe894cca41f6`**의 원격 ref와 fetch한 로컬 ref가 같고, 새 버전 파일 **15개 blob**이 로컬 파일과 일치함을 확인했습니다. 원격 루트 README는 기존 역사적 안내를 보존하고 새 버전 실행 안내와 Godot 중단 지시만 앞에 추가했습니다. 다른 로컬 미게시 변경은 전송하지 않았습니다.

Normal Git push failed because HTTPS credentials are absent. The connected GitHub app had write access, so its Git data API published only task files on the remote main baseline. The remote and fetched local refs match implementation commit **`bd6ac428dba7b031fae82ced40bffe894cca41f6`**; **15 rebuild blobs** exactly match local files. The remote root README retains its historical content with a new-version entry and the no-Godot direction prepended. Unrelated unpublished local changes were not uploaded.

[GitHub 새 버전 / Published rebuild](https://github.com/duq711/musimusihan-rpg/tree/codex/gothic-origin-20261021). 로컬 제작 단계 커밋 `332a5153c32b96149060ed5e5bc600ceef6e18b3`과 `codex/gothic-origin-20261020` 브랜치도 보존했습니다. 이 확인 기록은 이후 문서 커밋으로 덧붙입니다.

The earlier local production commit and branch remain preserved. This verification record is appended in a subsequent documentation commit.
