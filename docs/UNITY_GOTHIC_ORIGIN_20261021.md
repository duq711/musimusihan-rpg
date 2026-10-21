# Unity 고딕의 기원 / Native Gothic Origin

2026-10-21 사용자 확정: 게임은 **Unity Mac 앱**으로 제작하고, 기존35개 방 던전·회랑·가구를 재사용합니다. 브라우저를 실행 대상으로 선택한 것은 작업자의 판단 오류였습니다. `gothic-game/`은 당시 시안으로 보존하고, 미완성 브라우저 맵 연결 코드는 제거했습니다.

User decision: build a **native Unity Mac app** and reuse the existing furnished35-room dungeon. Selecting the browser as the game target was an implementation mistake. The earlier `gothic-game/` prototype is preserved; its unfinished map-bridge changes were removed.

## 실행과 보존 / Running and preservation

- 실행: `~/Applications/무시무시한 RPG - 고딕의 기원.app`을 엽니다. 실제 앱은 `unity-game/Builds/MusimusihanRPG-GothicOrigin.app`입니다. 브라우저·개발 서버·Unity 편집기가 필요하지 않습니다. / Open the Applications shortcut; the self-contained app runs without a browser, development server or Editor.
- Apple Silicon ARM64, Unity6000.6.3f1, 약389MB. 새 앱은 별도 식별자와 저장 파일을 사용합니다. / Native ARM64 player, approximately389MB, with its own product identifier and save.
- 기존 `MusimusihanRPG.app`, 기존 Applications·Dock 연결, 기존 게임 저장, 맵 제작 원본은 보존했습니다. 기존 전체 프로젝트 버전을 일괄 업그레이드하지 않았습니다. / The previous playable app, Applications/Dock links, saves and production originals are preserved. The original full project was not upgraded wholesale.

## 구현 / Implementation

처음부터 고딕으로 제작된 몬스터3종을 재사용한6개 적, 새 검·방패·장갑 형상, 잉크 윤곽과 명암 단계 셰이더, TMP 한글 UI를 하나의 새 Unity 원정 흐름으로 구성했습니다. 기존 던전 패키지80개 파일은 앱에 들어간 파일과 SHA256이 모두 같습니다. 지하 공간에 외부 창문·풍경·자연광을 추가하지 않았고, 하늘 상자도 제거했습니다.

The new native expedition combines six enemies using three creatures originally authored in the gothic style, newly sculpted equipment, a shared ink/paint shader and Korean TMP UI. All80 original map-package files are byte-identical to the bundled files. No exterior windows, outdoor views or daylight were added; the skybox is disabled.

- WASD 이동, 마우스 시점, Shift 달리기, 기력, 좌클릭 검, 우클릭 방패. / First-person movement/look, sprint/stamina, sword and shield.
- E 보급품 조사·철문, Q 회복약, Tab 가방, M 원본 배치 지도, J 기록, Esc 일시정지·설정. / Supplies/gate, potions, inventory, authored-layout map, journal, pause/settings.
- 30·23·1번 방 수호자를 처치해 세 봉인을 회수하고35번 보급실로 귀환. / Defeat three guardians and return with their seals.
- 별도 자동 저장·계속하기·사망·마지막 저장 재시도·새 원정·완료 화면. / Independent autosave/continue, death/retry, reset and completion.

이번 결과는 새 원정 플레이 버전입니다. 기존 RPG의79개 아이템·상인·제작·세부 부상·전체 F2 시험 이식이 완료됐다는 뜻이 아닙니다. 몬스터는 원본 정적 메시를 사용하며 이동·회전·공격 예고를 구현했고 새 골격 애니메이션은 제작하지 않았습니다. 기존 전체 RPG 이식의 미완료 상태는 그대로 구분합니다.

This is the fresh expedition version. It does not certify completion of the broader79-item/shop/crafting/injury/F2 migration. Creatures use the preserved static meshes with movement, turning and attack anticipation, rather than newly authored skeletal animation.

## 검증 / Validation

최종 Mac 전체 빌드 오류0개, 경고16개. 경고에는 Unity6.6에서 비권장으로 바뀐 검색·glTF 로드 API 등이 포함됩니다. 실제 앱의 Metal 실행 로그에는 오류·예외가 없었습니다. ARM64 실행 파일과 Mac 앱의 deep/strict 로컬 서명을 확인했습니다. Unity CLI가 앱 루트에 남긴 provenance JSON은 재사용 도구 폴더로 보존한 뒤 서명했습니다.

The final full build has zero errors and16 warnings, including deprecated search/glTF APIs. The actual Metal player log has no errors/exceptions. ARM64 architecture and deep/strict ad-hoc signing passed. CLI provenance was moved outside the bundle before signing.

115개 기능 검사가 배칭 전/후 각각 통과했습니다. 원본35개 방의 경계·바닥, 실제 컨트롤러 이동, 네이티브 시작 버튼 이벤트, 검·방패·회복·보급품 중복 방지, 메뉴 일시정지, 지도·가방·기록·설정,3개 수호자, 독립 저장 복원, 사망·재시도·귀환·새 원정·철문을 포함합니다. QA는 음소거·포인터 잠금 해제·별도 저장 경로로 실행했습니다. 전경에서 실제 마우스·키보드를 조작하는 전체 플레이 시험은 하지 않았습니다.

Both runs passed115 functional checks covering room bounds/floors, controller movement, native button events, combat/block/healing/loot, pause/UI, guardians, isolated save/restore, death/retry/return/reset and the original gate. QA was muted and did not capture the pointer or modify existing saves. A full foreground physical mouse/keyboard playthrough was not performed.

### 60FPS 측정 / Frame measurements

Apple M4·동일 앱·Metal·1280×900·2x MSAA·실제 UI/가구/적/정확한 충돌,35·33·1·30번 방에서 같은 컨트롤러 이동과 회전 경로. 경로별 워밍업90프레임 후600개 표본, 전후 각2,400개. 동일 실행본에서 장비 배칭만 환경 변수로 바꿔 비교했습니다. 장비는 원본 개별 형상을 보존하면서 손별 재질로 결합하여, 같은 시점의 시야 내 메시 그리기 추정 수가19개 줄었습니다.

Same Apple M4 player/Metal/1280×900/2x MSAA, furnished rooms, UI, animated creatures and exact collision. Four matching movement/turn routes,90 warmup frames and600 samples each:2,400 per run. A same-player equipment-batching switch provides the comparison; it reduces the frustum mesh-draw estimate by19 without removing authored parts.

| 방 / Room | 평균 전→후 / Mean before→after ms | 최종 p95 / ms | 최종 p99 / ms | 16.67ms 초과 / % |
| --- | ---: | ---: | ---: | ---: |
|35 보급실 |4.642→7.685|12.838|16.360|0.667|
|33 생활관 |5.529→5.077|10.528|14.782|0.333|
|1 대예배당 |7.713→5.130|9.205|11.291|0.333|
|30 하단 책장실 |7.927→5.816|8.904|16.507|0.833|

측정은 매 프레임 카메라를 명시적으로 그리고1px GPU 읽기로 완료를 기다린 벽시계 시간입니다. 자동 카메라 렌더가 생략됐던 최초 배치 모드 수치는 폐기했습니다. p95는 모든 경로에서16.67ms 이내지만 느린 프레임이 남습니다. 방35 평균은 오히려 늘었으므로 모든 경로가 빨라졌다고 해석하지 않습니다. 숨김·무제한 오프스크린 처리 여유 검사이며 전경 전체 화면의 고정60FPS 보증은 아닙니다.

Each sample explicitly renders the camera and synchronizes with a1px GPU readback. The initial non-rendering batch-mode sample was discarded. All p95 results are below16.67ms, with remaining slow frames. Room35 became slower; a universal speedup is not claimed. This is a hidden uncapped offscreen capacity test, not a guarantee of constant60FPS in foreground/fullscreen play.

원본 렌더 삼각형6,397,151개·충돌 삼각형3,312,064개. 장면별 최대 삼각형 카운터는 약96만~144만 개였습니다. release player의 Draw Calls 카운터는 제공되지 않아 null로 남겼고 시야 내 메시 추정과 구분했습니다. FrameTiming GPU 값은 동기 벽시계와 일관되지 않은 구간이 있어 진단 원자료로만 남기고 별도 GPU 성능 판정에는 사용하지 않았습니다.

Authored geometry totals6,397,151 render triangles and3,312,064 collision triangles; peak per-route triangle counters are approximately0.96–1.44 million. Draw-call counters are unavailable and remain null, separately from mesh estimates. Inconsistent FrameTiming GPU values are retained diagnostically and do not certify independent GPU capacity.

## 산출물과 재현 / Artifacts and reproduction

- 소스 / Source: `unity-game/Assets/GothicOrigin/`
- 도구·원본 해시·CLI 기록 / Tools, source hashes and CLI provenance: `tools/unity-gothic-origin-20261021/`
- 작은 검증 요약·빌드 소스 해시 / Compact validation/build receipts: `docs/validation/unity-gothic-origin-20261021/`
- [재현 절차 / Build instructions](../tools/unity-gothic-origin-20261021/README.md)

원본 맵·몬스터·폰트·importer metadata와 최종 앱을 보존합니다. 검토한 캡처·로그·QA 저장·격리 프로젝트와 복제 캐시는 검증 후 제거합니다. 실제 제거 할당량·관찰된 여유 공간 변화는 `cleanup.json`에 기록합니다. APFS 공유 블록 때문에 두 수치는 다를 수 있습니다.

Production originals, importer metadata and the final playable app are preserved. Reviewed captures/logs/QA saves and the isolated project/cache are removed after validation. `cleanup.json` records removed allocation and observed free-space change, which can differ with APFS sharing.
