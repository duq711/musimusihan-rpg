# 크리프 적용 검증 / Creep integration validation

2026-09-17, Mac Godot 4.7 · Forward+ / Vulkan. 기존 오크 제거 후 andriichykrii의 [Creep Creature](https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature)를 폐광 동쪽 창고 1명과 F2 전투 시험에 연결했다. 원본 FBX·텍스처·변환 GLB는 라이선스 조건에 따라 로컬에만 보존한다.

The removed orc is replaced by the licensed Creep in one mine store encounter and the F2 trial. Source and converted reusable assets remain local; this folder contains rendered evidence and test records only.

## 결과 / Results

- `creep_enemy` 설치 검사 통과: 원본 스킨·텍스처·본 움직임, 6개 동작, 첫 공격 주기의 접촉 시점, 물기 1회·양손 공격 2회, 중복 피해 방지, 실제 방패·저스트 가드, 피격·사망·보상 1회, 재시험·초기화·원정 복원.
- `test_room` 통과: 기존 카탈로그와 기능, 원정·인벤토리 격리 및 복원. 이전부터 있던 종료 시 ObjectDB 2개 경고는 남아 있다.
- 첫 `cave_dungeon` 실행은 `use_creep` 변수의 형식 추론 오류로 실패했다. 명시적 `bool`로 수정한 뒤 재실행을 통과했다. 크리프 1명·총 적 6명, 실제 전투·보상·탈출 조건 확인.
- 모델 폴더를 게임 외부로 임시 이동한 새 프로세스에서 `creep_enemy`, `cave_dungeon`을 실행해 둘 다 통과했다. 설치 안내와 기존 검지기 대체를 확인했으며, 해당 실행의 모델 검사는 SKIPPED로 구분했다. 이후 에셋 폴더를 원위치로 복구했다.
- `creep_enemy_preview.gd` 숨김 GPU 렌더 통과. 아래 10개 PNG를 직접 열어 앞·옆·뒤, 걷기·물기·좌우 타격·피격·사망, 실제 폐광 배치를 검토했다. 원래 원정과 커서 상태 보존 확인.

Installed combat and test-room checks passed. The initial mine run failed on type inference; the explicit-bool correction passed its rerun. A separate missing-asset run passed both fallback and mine suites, then the asset directory was restored. All ten actual GPU images were opened and reviewed. No native window, desktop input capture, or audio was used.

## 실제 렌더 / Actual renders

![폐광의 크리프 / Creep in the mine](mine_encounter.png)

[정면 / Front](front.png) · [옆면 / Side](side.png) · [뒷면 / Back](back.png) · [걷기 / Walk](walk.png) · [물기 / Bite](bite.png) · [오른손 타격 / Right punch](punch_right.png) · [왼손 타격 / Left punch](punch_left.png) · [피격 / Hit](hit.png) · [사망 / Death](death.png).

## 범위와 제한 / Scope and limits

원본 17개 클립을 보존하고 현재 AI는 6개를 사용한다. 나머지 11개는 보관 상태다. 타격은 기존 거리·시야·방향 판정이며 피부 표면 단위의 충돌 검증은 아니다. 정지 자세 렌더와 자동 전투 검증을 수행했으며 하드웨어 입력으로 직접 플레이한 검증은 미확인이다. GPU 장면의 플레이어 체력은 격리된 시험 원정의 수치다.

All 17 source clips are retained; six are connected to current AI. Contacts use the existing range, visibility and facing rules rather than mesh-level collision. These are automated combat checks and GPU stills; manual hardware-input playtesting is unverified. The rendered player's stats belong to the isolated test session.

가져오기 캐시의 이미지 UID 3개는 경고 후 실제 파일 경로로 정상 로드된다. 스킨은 정점당 상위 8개 뼈 영향으로 정규화해 62개 정점에서 일부 가중치가 제외된다(정점별 최대 5.22%). 이 제한과 최초 실패를 숨기지 않고 로그에 남겼다. 본편 소스 에셋에는 변경을 가하지 않았다.

Three imported image UIDs warn and successfully fall back to their file paths. The skin keeps eight influences per vertex; 62 vertices lose at most 5.22% weight each. The original source is preserved. Logs retain both the initial failure and the passing rerun.

## 증거 / Evidence

- [최초 설치 검사 / Initial installed run](installed_initial.log)
- [폐광 수정 후 통과 / Mine rerun](cave_pass.log)
- [미설치 검사 / Missing-asset run](missing_asset_pass.log)
- [GPU 로그 / GPU log](gpu_preview.log)
- [촬영 상태 / Capture manifest](manifest.json)
- [에셋 요약 / Asset summary](asset_summary.json)
