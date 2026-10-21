# 잔향의 성소: 검은 성물실 / Sanctuary of Echoes: The Black Reliquary

> 보존된 브라우저 시안입니다. 현재 확정된 실행 대상은 [Unity Mac 게임](../docs/UNITY_GOTHIC_ORIGIN_20261021.md)입니다. / Archived browser prototype; the active target is the native Unity Mac game.

2026-10-20에 시작해 2026-10-21에 검증한 **새 고딕 코믹스 원정 버전**입니다. 기존 사실적 장면에 필터를 추가하지 않고, 이 폴더의 소스가 건축·가구·적·손·장비·재질·UI를 새로 만듭니다. 현재 탐색기와 같은 Three.js 기반으로 실행합니다.

A new gothic comics expedition, authored from October 20 and validated on October 21, 2026. This folder constructs new architecture, furniture, enemies, hands, equipment, materials and UI. It uses the existing explorer's Three.js runtime approach.

## 실행 / Play

- 이 Mac에서는 `Play.command`를 더블클릭합니다. Python 3와 WebGL 2 브라우저가 필요합니다. 처음부터 내려받은 파일은 macOS에서 우클릭 → 열기가 필요할 수 있습니다.
- 또는 저장소 루트에서 `python3 gothic-game/serve.py --port 8790`을 실행한 뒤 [게임 열기](http://127.0.0.1:8790/)를 선택합니다.
- 서버는 로컬 컴퓨터에서만 접속할 수 있습니다. 실행 후 인터넷·CDN·로그인이 필요하지 않습니다.

On this Mac, double-click `Play.command`, or run the server command above and open the local link. Python 3 and a WebGL 2 browser are required. All runtime files are local; the server binds to loopback only.

## 플레이 / Gameplay

35번 보급 창고에서 시작합니다. 30번 하단 책장실, 23번 큰 묘실, 1번 대예배당의 수호자를 물리치고 성물 세 개를 회수한 뒤, **35번의 귀환 인장**으로 돌아오십시오. 상자 수색으로 회복약·크라운을 얻습니다. 지도는 탐험한 방을 기록하며 미수복 성물 위치를 표시합니다.

Start in Room 35. Defeat the guardians and recover relics in Rooms 30, 23 and 1, then return to Room 35's seal. Search chests for potions and crowns. The map records explored rooms and marks remaining relics.

| 조작 / Input | 기능 / Action |
| --- | --- |
| WASD, Shift | 이동·달리기 / Move, sprint |
| 화면 드래그, ← → | 시선 / Look |
| F | 마우스 잠금 / Optional mouse lock |
| 클릭 또는 Space | 검 공격 / Sword attack |
| 우클릭 또는 Q | 방패 방어 / Shield block |
| E | 상자·성물·귀환 조사 / Interact |
| 1 | 회복약 / Potion |
| I, J, M | 가방·기록·지도 / Inventory, journal, map |
| Esc | 일시정지·설정 / Pause, settings |

탭 전환·대기모드 등으로 포커스를 잃으면 일시정지합니다. **성소로 돌아가기**를 눌러 재개합니다. 자동 저장은 같은 브라우저·같은 주소에 보관됩니다. 새 버전은 `musimusihan.gothic-origin.v1`이라는 별도 저장 키를 사용합니다. 이전 게임의 저장 데이터와 앱·Dock 연결은 교체하지 않습니다.

Focus loss, including tab switches and sleep, pauses play. Select **성소로 돌아가기** to resume. Autosave belongs to this browser and origin. The new save key is isolated from previous versions; the existing app and Dock links remain preserved.

## 범위 / Scope

35개 방의 정체성과 기존 개념 평면도를 이어 쓰고, 방 33–35는 이후 확정된 생활관·간수방·보급 창고 이름을 적용합니다. 제작 소스는 `world.js`, 게임 규칙·입력·저장은 `game.js`, 화면은 `index.html`과 `style.css`입니다. 제작 원본은 이 소스 자체입니다.

The 35 room identities and concept floorplan are retained, including the later approved uses of Rooms 33–35. `world.js` authors the world; `game.js` implements rules, controls and saves; HTML/CSS author the interface. These editable sources are the production originals.

이 버전은 **탐험 → 전투 → 성물 회수 → 귀환**이 가능한 독립 원정입니다. 과거 Unity RPG의 모든 아이템·상점·제작·연금술·부위별 부상·F2 시험실을 재구현한 버전은 아닙니다. 음향은 아직 추가하지 않았습니다. 이전 완성 에셋과 동일한 세밀도나 수작업 회화 품질을 주장하지 않습니다.

This is a complete standalone expedition loop. It does not yet recreate every inventory item, merchant, crafting/alchemy system, anatomical injury or F2 trial from the previous Unity RPG. Audio has not been added. It does not claim the detail or hand-painted finish of the previous production assets.

## 검증 / Validation

기능·성능·정리·공유 상태는 [제작 기록](../docs/GOTHIC_ORIGIN_REBUILD_20261021.md)과 [작은 검증 요약](validation-summary.json)을 확인하십시오. 재사용 검증 도구는 `../tools/gothic-rebuild-20261020/validate.cjs`입니다. 임시 캡처·전체 로그는 정리하고 요약만 남깁니다.

See the linked production record and compact summary for measured results, limitations and delivery status. The reusable validator remains in `tools/`; reviewed temporary captures and full logs are removed.

Three.js는 MIT 라이선스이며 고지문은 `vendor/THREE-LICENSE`에 보존합니다. 나머지 새 모델·재질·UI는 이 프로젝트 소스로 제작합니다.

Three.js uses the MIT license retained in `vendor/THREE-LICENSE`. New models, materials and UI are authored in the project sources.
